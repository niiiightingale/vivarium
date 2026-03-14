class_name SoilManager
extends Node3D

const GRID_SIZE = 100 
const PHYSICAL_SIZE = 5.0 

var height_map_image : Image
var height_map_texture : ImageTexture

# ==========================================
# 沙堆塌陷算法控制参数

# ==========================================
@export var brush_strength:float = 0.05
@export var max_slope: float = 0.05   
@export var flow_rate: float = 0.5    
var is_terrain_settling: bool = false 

var avalanche_timer: float = 0.0
var avalanche_interval: float = 0.05 # 间隔 0.05 秒算一次 (相当于 20 FPS 的塌陷动画)
# 局部唤醒 (脏矩形) 优化参数
# ==========================================
var active_min_x: int = 0
var active_max_x: int = 0
var active_min_y: int = 0
var active_max_y: int = 0


@onready var soil_body = $SoilBody
@onready var collision_shape = $SoilBody/SoilCollision

var height_shape = HeightMapShape3D.new() 

# ==========================================
# 物理碰撞延迟刷新与半空坠落队列
# ==========================================
var needs_physics_update: bool = false
var physics_update_timer: float = 0.0
@export var physics_update_interval: float = 0.1 

var pending_drops: Array[Dictionary] = []



func _ready():
	height_map_image = Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RF)
	height_map_image.fill(Color(0.0, 0.0, 0.0, 1.0)) 
	height_map_texture = ImageTexture.create_from_image(height_map_image)
	
	var material = $PlaneMesh.get_active_material(0)
	material.set_shader_parameter("height_map", height_map_texture)

	var base_height = material.get_shader_parameter("min_top_height")
	if base_height != null:
		soil_body.position.y = base_height

	height_shape.map_width = GRID_SIZE
	height_shape.map_depth = GRID_SIZE
	collision_shape.shape = height_shape
	
	var scale_factor = PHYSICAL_SIZE / float(GRID_SIZE - 1)
	soil_body.scale = Vector3(scale_factor, 1.0, scale_factor)
	
	update_physics_collision()

func update_physics_collision():
	var float_array = height_map_image.get_data().to_float32_array()
	height_shape.map_data = float_array

func _process(delta):
	var current_time = Time.get_ticks_msec() / 1000.0 
	
	# 1. 坠落队列正常跑 (不降频，保证倒土的跟手感)
	for i in range(pending_drops.size() - 1, -1, -1):
		if current_time >= pending_drops[i]["time"]:
			var drop_pos = pending_drops[i]["pos"]
			var drop_radius = pending_drops[i]["radius"]
			apply_soil_brush(drop_pos, drop_radius, brush_strength, true) 
			pending_drops.remove_at(i) 
			
	# 2. 塌陷算法降频执行！
	if is_terrain_settling:
		avalanche_timer += delta
		if avalanche_timer >= avalanche_interval:
			is_terrain_settling = simulate_soil_avalanche() 
			needs_physics_update = true
			avalanche_timer = 0.0

	# 3. 延迟刷新物理
	if needs_physics_update:
		physics_update_timer += delta
		if physics_update_timer >= physics_update_interval:
			update_physics_collision()
			needs_physics_update = false
			physics_update_timer = 0.0

# ==========================================
# 👇 核心改造：对外暴露的公共 API 接口 👇
# ==========================================

# 1. 供 BucketTool 调用的：添加下落任务
func add_pending_drop(world_pos: Vector3, radius: float, fall_time: float):
	var current_time = Time.get_ticks_msec() / 1000.0 
	pending_drops.append({
		"pos": world_pos,
		"radius": radius, # 把工具的半径也传进来，提高灵活度
		"time": current_time + fall_time 
	})

# 2. 供 ToolManager/BrushTool 调用的：即时修改高度图 (支持加法/减法)
func apply_soil_brush(world_position: Vector3, radius: float, strength: float, is_adding: bool):
	var center_x = int((world_position.x / PHYSICAL_SIZE + 0.5) * GRID_SIZE)
	var center_y = int((world_position.z / PHYSICAL_SIZE + 0.5) * GRID_SIZE)
	var pixel_radius = int((radius / PHYSICAL_SIZE) * GRID_SIZE)
	
	var changed = false
	
	# 【新增】获取当前物理空间的射线检测器
	var space_state = get_world_3d().direct_space_state
	# 【新增】设定射线起点的绝对高度 (假设缸体顶部高度为 5.0，你可以根据实际情况调整)
	var drop_start_height = 5.0 
	
	for x in range(center_x - pixel_radius, center_x + pixel_radius):
		for y in range(center_y - pixel_radius, center_y + pixel_radius):
			if x >= 0 and x < GRID_SIZE and y >= 0 and y < GRID_SIZE:
				var dist = Vector2(x, y).distance_to(Vector2(center_x, center_y))
				
				if dist <= pixel_radius:
					var current_h = height_map_image.get_pixel(x, y).r
					
					# ==========================================
					# ✨【新增：物理射线遮挡检测】✨
					# ==========================================
					# 1. 把像素网格坐标 (x, y) 反推回真实世界坐标 (world_x, world_z)
					# 1. 算出绝对的全局坐标 (加上自身的 global_position)
					var world_x = (float(x) / GRID_SIZE - 0.5) * PHYSICAL_SIZE + global_position.x
					var world_z = (float(y) / GRID_SIZE - 0.5) * PHYSICAL_SIZE + global_position.z
					
					# 2. 超长射线：起点在头上 10 米，终点在脚下 2 米，保证绝对贯穿！
					var start_pos = Vector3(world_x, global_position.y + 10.0, world_z)
					var end_pos = Vector3(world_x, global_position.y - 2.0, world_z)
					
					var query = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
					query.collision_mask = 16 # 请确保石头的碰撞层在 Layer 4！
					
					# 开启这个选项：如果射线起点不小心卡在别的碰撞体里面，也能检测到！
					query.hit_from_inside = true 
					
					var result = space_state.intersect_ray(query)
					if result:
						# 打中了！再加个保险判定：
						# 如果打中的位置比当前的泥土还要低（说明石头已经被土彻底埋起来了）
						# 那我们就允许继续在它上面堆土。否则就跳过！
						if result.position.y > (current_h + global_position.y):
							continue # 被外露的石头遮挡，跳过加土！
					# ==========================================
					
					var weight = smoothstep(1.0, 0.0, dist / float(pixel_radius))
					var new_h = 0.0
					
					if is_adding:
						new_h = current_h + (strength * weight)
					else:
						# 减法逻辑：确保不低于 0.0 限制
						new_h = max(0.0, current_h - (strength * weight))
					
					# 只有发生实质改变才更新，节约性能
					if abs(current_h - new_h) > 0.0001:
						height_map_image.set_pixel(x, y, Color(new_h, 0, 0, 1))
						changed = true
	
	if changed:
		# 1. 计算当前这一笔刷的范围边界，并往外扩张1格作为安全区
		var b_min_x = max(0, center_x - pixel_radius - 1)
		var b_max_x = min(GRID_SIZE, center_x + pixel_radius + 2)
		var b_min_y = max(0, center_y - pixel_radius - 1)
		var b_max_y = min(GRID_SIZE, center_y + pixel_radius + 2)

		# 2. 动态更新活跃区块 (脏矩形)
		if not is_terrain_settling:
			active_min_x = b_min_x
			active_max_x = b_max_x
			active_min_y = b_min_y
			active_max_y = b_max_y
		else:
			# 如果已经在塌陷了，就把新刷的区域和旧区域合并
			active_min_x = min(active_min_x, b_min_x)
			active_max_x = max(active_max_x, b_max_x)
			active_min_y = min(active_min_y, b_min_y)
			active_max_y = max(active_max_y, b_max_y)

		height_map_texture.update(height_map_image)
		needs_physics_update = true
		is_terrain_settling = true # 唤醒塌陷

# 3. 【新增】供 MossSystem 调用的：安全查询高度
func get_soil_height_at(world_pos: Vector3) -> float:
	var x = int((world_pos.x / PHYSICAL_SIZE + 0.5) * GRID_SIZE)
	var y = int((world_pos.z / PHYSICAL_SIZE + 0.5) * GRID_SIZE)
	
	# 边界保护，防止因为查询越界导致游戏崩溃
	if x >= 0 and x < GRID_SIZE and y >= 0 and y < GRID_SIZE:
		return height_map_image.get_pixel(x, y).r
	return 0.0

# ==========================================
# 沙堆塌陷算法 (内部算法，保持原样)
# ==========================================
# 把方向和距离写死成只读数组，彻底消灭内存分配！
# 沙堆塌陷算法 (内存级极限优化版)
# ==========================================
# 沙堆塌陷算法 (脏矩形极限优化版)
# ==========================================
const DIR_X = [1, -1, 0, 0, 1, -1, 1, -1]
const DIR_Y = [0, 0, 1, -1, 1, -1, -1, 1]
const DIST  = [1.0, 1.0, 1.0, 1.0, 1.414, 1.414, 1.414, 1.414]

func simulate_soil_avalanche() -> bool:
	var is_unstable = false
	var byte_data = height_map_image.get_data()
	var floats = byte_data.to_float32_array()
	
	# 用于记录下一帧需要计算的“脏矩形”范围。初始设为极限反向值
	var next_min_x = GRID_SIZE
	var next_max_x = 0
	var next_min_y = GRID_SIZE
	var next_max_y = 0
	
	# 【核心优化】：只在活跃区块内进行双层循环！
	for x in range(active_min_x, active_max_x):
		for y in range(active_min_y, active_max_y):
			var idx = y * GRID_SIZE + x
			var current_h = floats[idx]
			
			var max_slope_val = 0.0  
			var target_idx = -1
			var target_nx = -1
			var target_ny = -1
			var neighbor_h = 0.0
			var target_dist = 1.0    
			
			for i in range(8):
				var nx = x + DIR_X[i]
				var ny = y + DIR_Y[i]
				
				if nx >= 0 and nx < GRID_SIZE and ny >= 0 and ny < GRID_SIZE:
					var n_idx = ny * GRID_SIZE + nx
					var nh = floats[n_idx]
					var height_diff = current_h - nh
					var current_slope = height_diff / DIST[i]
					
					if current_slope > max_slope_val:
						max_slope_val = current_slope
						target_idx = n_idx
						target_nx = nx
						target_ny = ny
						neighbor_h = nh
						target_dist = DIST[i]
					
			if max_slope_val > max_slope and target_idx != -1:
				var actual_diff = current_h - neighbor_h
				var stable_diff = max_slope * target_dist
				var excess_diff = actual_diff - stable_diff
				
				var flow_amount = min(excess_diff * flow_rate, actual_diff / 2.0)
				
				floats[idx] -= flow_amount
				floats[target_idx] += flow_amount
				is_unstable = true
				
				# 【动态扩容】：如果有泥土流动了，把它和它流向的位置加入下一帧的计算范围，并外扩 1 像素缓冲
				next_min_x = min(next_min_x, min(x, target_nx) - 1)
				next_max_x = max(next_max_x, max(x, target_nx) + 2)
				next_min_y = min(next_min_y, min(y, target_ny) - 1)
				next_max_y = max(next_max_y, max(y, target_ny) + 2)
				
	if is_unstable:
		# 安全更新下一帧的脏矩形边界，防止越界
		active_min_x = max(0, next_min_x)
		active_max_x = min(GRID_SIZE, next_max_x)
		active_min_y = max(0, next_min_y)
		active_max_y = min(GRID_SIZE, next_max_y)
		
		var new_bytes = floats.to_byte_array()
		height_map_image.set_data(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RF, new_bytes)
		height_map_texture.update(height_map_image)
		
	return is_unstable
