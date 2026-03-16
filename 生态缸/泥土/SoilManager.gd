class_name SoilManager
extends Node3D

const GRID_SIZE = 100 
const PHYSICAL_SIZE = 5.0 

var height_map_image : Image
var height_map_texture : ImageTexture
# ==========================================
# 沙堆塌陷算法控制参数

# ==========================================

@export var initial_soil_thickness: float = 1.5
# ✨ 新增：用于生成初始地形起伏的噪波
@export var base_noise: FastNoiseLite 
# ✨ 新增：起伏的最大落差（比如 0.2 代表土坑最高和最低相差 0.2 米）
@export var base_noise_amplitude: float = 0.2
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
	# ==========================================
	# ✨ 核心魔法：用噪波刷出极其自然的高低起伏！
	# ==========================================
	if base_noise != null:
		for x in range(GRID_SIZE):
			for y in range(GRID_SIZE):
				# 获取当前坐标的噪波值（返回值在 -1.0 到 1.0 之间）
				var noise_val = base_noise.get_noise_2d(float(x), float(y))
				# 将噪波值乘上起伏强度，叠加到基础厚度上
				var final_h = initial_soil_thickness + (noise_val * base_noise_amplitude)
				# 确保高度绝不能低于 0 (不能穿透缸底)
				final_h = max(0.0, final_h)
				
				height_map_image.set_pixel(x, y, Color(final_h, 0.0, 0.0, 1.0))
	else:
		# 如果没有配置噪波，就保底使用完美的纯平面
		height_map_image.fill(Color(initial_soil_thickness, 0.0, 0.0, 1.0))
		
	# ==========================================
	
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

# 核心 API：施加泥土笔刷（支持贴图、容量限制与绝对印章切除）
# ==========================================
func apply_soil_brush(world_position: Vector3, radius: float, strength: float, is_adding: bool, available_volume: float = 9999.0, brush_image: Image = null, brush_rotation: float = 0.0) -> float:
	var center_x = int((world_position.x / PHYSICAL_SIZE + 0.5) * GRID_SIZE)
	var center_y = int((world_position.z / PHYSICAL_SIZE + 0.5) * GRID_SIZE)
	var pixel_radius = int((radius / PHYSICAL_SIZE) * GRID_SIZE)
	
	var space_state = get_world_3d().direct_space_state
	var total_desired_volume: float = 0.0
	var valid_pixels = [] 
	
	# 如果有贴图，获取尺寸并预计算旋转
	var img_w = 0; var img_h = 0
	if brush_image and not brush_image.is_empty():
		img_w = brush_image.get_width() - 1
		img_h = brush_image.get_height() - 1
		
	var cos_r = cos(brush_rotation)
	var sin_r = sin(brush_rotation)

	# ✨ 获取玩家点击正中心的初始高度，作为挖坑/填土的绝对基准高度！
	var safe_cx = clamp(center_x, 0, GRID_SIZE - 1)
	var safe_cy = clamp(center_y, 0, GRID_SIZE - 1)
	var center_h = height_map_image.get_pixel(safe_cx, safe_cy).r

	# ==========================================
	# 阶段一：打草稿！计算每个像素的改变需求
	# ==========================================
	for x in range(center_x - pixel_radius, center_x + pixel_radius + 1):
		for y in range(center_y - pixel_radius, center_y + pixel_radius + 1):
			if x >= 0 and x < GRID_SIZE and y >= 0 and y < GRID_SIZE:
				
				var current_h = height_map_image.get_pixel(x, y).r
				
				
				
				var weight = 0.0
				
				# 读取 Alpha 笔刷贴图数据
				if brush_image and not brush_image.is_empty():
					var nx = (x - center_x) / float(pixel_radius)
					var ny = (y - center_y) / float(pixel_radius)
					var rx = nx * cos_r - ny * sin_r
					var ry = nx * sin_r + ny * cos_r
					var u = rx * 0.5 + 0.5
					var v = ry * 0.5 + 0.5
					
					if u >= 0.0 and u <= 1.0 and v >= 0.0 and v <= 1.0:
						weight = brush_image.get_pixel(int(u * img_w), int(v * img_h)).r
				else:
					# 没有贴图时的后备数学方案 (余弦平滑)
					var dist = Vector2(x, y).distance_to(Vector2(center_x, center_y))
					if dist <= pixel_radius:
						var normalized_dist = dist / float(pixel_radius)
						weight = pow(cos(normalized_dist * PI * 0.5), 1.5)
				
				# 忽略极小的改动，形成硬朗的边缘
				if weight <= 0.05: continue
					
				var actual_change = 0.0
				
			
				# ✨ 绝对的布尔切除/印章逻辑
				if is_adding:
					# 填土：建造平顶斜坡土台
					var target_top_h = center_h + strength 
					actual_change = max(0.0, (target_top_h - current_h) * weight)
				else:
					# 挖土：挖出平底斜坡深坑（并且绝不挖穿缸底 0.0）
					var target_bottom_h = max(0.0, center_h - strength)
					actual_change = max(0.0, (current_h - target_bottom_h) * weight)
					
				if actual_change > 0.0001:
					total_desired_volume += actual_change
					valid_pixels.append({"x": x, "y": y, "change": actual_change, "current_h": current_h})

	# ==========================================
	# 阶段二：正式下笔！(容量不足时整体等比例缩小)
	# ==========================================
	if valid_pixels.size() == 0: 
		return 0.0
		
	var scale_factor = 1.0
	if total_desired_volume > available_volume:
		scale_factor = available_volume / total_desired_volume
		
	var actual_volume_changed = 0.0
	var changed = false
	var b_min_x = GRID_SIZE; var b_max_x = 0
	var b_min_y = GRID_SIZE; var b_max_y = 0

	# 遍历草稿本，正式修改图片
	for p in valid_pixels:
		var final_change = p.change * scale_factor
		var new_h = p.current_h + final_change if is_adding else p.current_h - final_change
		height_map_image.set_pixel(p.x, p.y, Color(new_h, 0, 0, 1))
		
		actual_volume_changed += final_change
		changed = true
		
		# 更新脏矩形范围
		if p.x < b_min_x: b_min_x = p.x
		if p.x > b_max_x: b_max_x = p.x
		if p.y < b_min_y: b_min_y = p.y
		if p.y > b_max_y: b_max_y = p.y

	if changed:
		if not is_terrain_settling:
			active_min_x = b_min_x; active_max_x = b_max_x; active_min_y = b_min_y; active_max_y = b_max_y
		else:
			active_min_x = min(active_min_x, b_min_x); active_max_x = max(active_max_x, b_max_x)
			active_min_y = min(active_min_y, b_min_y); active_max_y = max(active_max_y, b_max_y)

		height_map_texture.update(height_map_image)
		needs_physics_update = true
		is_terrain_settling = true 
		
	return actual_volume_changed
# 核心 API：施加平滑笔刷（抹平棱角，不增减总体积）
# ==========================================
func apply_smooth_brush(world_position: Vector3, radius: float, strength: float) -> void:
	var center_x = int((world_position.x / PHYSICAL_SIZE + 0.5) * GRID_SIZE)
	var center_y = int((world_position.z / PHYSICAL_SIZE + 0.5) * GRID_SIZE)
	var pixel_radius = int((radius / PHYSICAL_SIZE) * GRID_SIZE)
	
	var space_state = get_world_3d().direct_space_state
	
	var total_height = 0.0
	var count = 0
	var valid_pixels = []
	
	# ==========================================
	# 阶段一：扫描范围，算出“平均高度”
	# ==========================================
	for x in range(center_x - pixel_radius, center_x + pixel_radius + 1):
		for y in range(center_y - pixel_radius, center_y + pixel_radius + 1):
			if x >= 0 and x < GRID_SIZE and y >= 0 and y < GRID_SIZE:
				var dist = Vector2(x, y).distance_to(Vector2(center_x, center_y))
				if dist <= pixel_radius:
					var current_h = height_map_image.get_pixel(x, y).r
					# 边缘柔和过渡权重
					var weight = pow(cos((dist / float(pixel_radius)) * PI * 0.5), 1.5)
					if weight <= 0.05: continue
					
					total_height += current_h
					count += 1
					valid_pixels.append({"x": x, "y": y, "h": current_h, "w": weight})
					
	if count == 0: return
	
	# 算出这片区域的平均海平面
	var average_height = total_height / float(count)
	
	# ==========================================
	# 阶段二：把高低不平的像素，向平均值拉平 (Lerp)
	# ==========================================
	var changed = false
	var b_min_x = GRID_SIZE; var b_max_x = 0
	var b_min_y = GRID_SIZE; var b_max_y = 0
	
	for p in valid_pixels:
		# 核心：使用 lerp 向平均值插值。strength 决定了抹平的速度，weight 决定了边缘不那么生硬
		var new_h = lerp(p.h, average_height, strength * p.w)
		
		if abs(new_h - p.h) > 0.0001:
			height_map_image.set_pixel(p.x, p.y, Color(new_h, 0, 0, 1))
			changed = true
			
			if p.x < b_min_x: b_min_x = p.x
			if p.x > b_max_x: b_max_x = p.x
			if p.y < b_min_y: b_min_y = p.y
			if p.y > b_max_y: b_max_y = p.y
			
	if changed:
		if not is_terrain_settling:
			active_min_x = b_min_x; active_max_x = b_max_x; active_min_y = b_min_y; active_max_y = b_max_y
		else:
			active_min_x = min(active_min_x, b_min_x); active_max_x = max(active_max_x, b_max_x)
			active_min_y = min(active_min_y, b_min_y); active_max_y = max(active_max_y, b_max_y)

		height_map_texture.update(height_map_image)
		needs_physics_update = true
		is_terrain_settling = true
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
# ✨ 新增接口 1：计算地表法线 (让物体贴合斜坡)
# ==========================================
func get_soil_normal_at(world_pos: Vector3) -> Vector3:
	var cx = int((world_pos.x / PHYSICAL_SIZE + 0.5) * GRID_SIZE)
	var cy = int((world_pos.z / PHYSICAL_SIZE + 0.5) * GRID_SIZE)
	
	if cx < 1 or cx >= GRID_SIZE - 1 or cy < 1 or cy >= GRID_SIZE - 1:
		return Vector3.UP
		
	# 读取四周的高度，计算坡度差 (索贝尔算子原理)
	var h_left = height_map_image.get_pixel(cx - 1, cy).r
	var h_right = height_map_image.get_pixel(cx + 1, cy).r
	var h_up = height_map_image.get_pixel(cx, cy - 1).r
	var h_down = height_map_image.get_pixel(cx, cy + 1).r
	
	# 一个像素的物理真实宽度
	var pixel_size = PHYSICAL_SIZE / float(GRID_SIZE)
	
	var normal = Vector3(h_left - h_right, 2.0 * pixel_size, h_up - h_down)
	return normal.normalized()
