extends Node3D

const GRID_SIZE = 100 
const PHYSICAL_SIZE = 5.0 

var height_map_image : Image
var height_map_texture : ImageTexture

@export var brush_radius: float = 0.5  
@export var brush_strength: float = 0.02 

# ==========================================
# 【新增】沙堆塌陷算法控制参数
# ==========================================
@export var max_slope: float = 0.05   # 安息角：允许的最大高度差。越小泥土越容易塌方滑动
@export var flow_rate: float = 0.5    # 流动率：每次塌方滑落的泥土比例
var is_terrain_settling: bool = false # 标记地形是否正在持续塌陷中


@onready var soil_body = $SoilBody
@onready var collision_shape = $SoilBody/SoilCollision

var height_shape = HeightMapShape3D.new() 

@onready var camera = get_viewport().get_camera_3d()

# ==========================================
# 倾倒与生成参数 (已移除废弃的刚体预制体)
# ==========================================
@export var drop_height: float = 4.0      # 从玻璃缸哪个高度倒下
@export var drop_radius: float = 0.5      # 倾倒的圆形范围半径（与贴花大小呼应）
@export var clumps_per_second: float = 30.0 # 爆发力！每秒生成的土块数量
@export var valid_bounds: float = 2.4     # 缸体内部的安全生成边界
var spawn_timer: float = 0.0
@onready var placement_cursor = $PlacementCursor 
@onready var dirt_particles = $DirtParticles # 【新增】获取独立的粒子发射器
@onready var bucket_model = $DirtParticles/BucketModel # 【新增】获取小桶模型
var target_tilt: float = 0.0 # 小桶的目标倾斜角度（度数）
# ==========================================
# 物理碰撞延迟刷新与半空坠落队列
# ==========================================
var needs_physics_update: bool = false
var physics_update_timer: float = 0.0
@export var physics_update_interval: float = 0.1 # 0.1秒刷新一次物理

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
	
	# ==========================================
	# 1. 清算队列：泥土落地瞬间抬升地形
	# ==========================================
	var terrain_modified = false
	for i in range(pending_drops.size() - 1, -1, -1):
		if current_time >= pending_drops[i]["time"]:
			var drop_pos = pending_drops[i]["pos"]
			apply_soil_brush(drop_pos, drop_radius, 0.01) 
			
			pending_drops.remove_at(i) 
			terrain_modified = true
			
	# 【核心修改】：不仅是有泥土落地时要刷，只要地形还没稳定 (is_terrain_settling)，就要一直刷！
	if terrain_modified or is_terrain_settling:
		is_terrain_settling = simulate_soil_avalanche() # 接收返回值
		needs_physics_update = true

	# ==========================================
	# 2. 延迟刷新物理碰撞
	# ==========================================
	if needs_physics_update:
		physics_update_timer += delta
		if physics_update_timer >= physics_update_interval:
			update_physics_collision()
			needs_physics_update = false
			physics_update_timer = 0.0

	# ==========================================
	# 第三步：玩家输入与生成逻辑 (精准物理 + 边缘吸附双保险)
	# ==========================================
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	
	var space_state = get_world_3d().direct_space_state
	
	# 1. 优先打一根真实的物理射线
	var main_query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 100.0)
	main_query.collision_mask = 2 # 只测泥土层
	var main_result = space_state.intersect_ray(main_query)
	
	var target_x: float = 0.0
	var target_z: float = 0.0
	var hit_success: bool = false
	
	# 2. 判断：击中泥土用物理，移出缸外用数学
	# 2. 判断：击中泥土用物理，移出缸外用数学
	# 2. 判断：击中泥土用物理，移出缸外用数学
	# 2. 判断：击中泥土用物理，移出缸外用数学
	if main_result:
		# 鼠标在缸内：绝对精准的物理对齐
		target_x = main_result.position.x
		target_z = main_result.position.z
		hit_success = true
	else:
		# 【1. 生成你想要的“完美匹配玻璃缸的碰撞体” (AABB)】
		# 起点在缸底左后方，尺寸就是缸的长宽高！
		var tank_box = AABB(
			Vector3(-valid_bounds, 0.0, -valid_bounds), 
			Vector3(valid_bounds * 2.0, drop_height, valid_bounds * 2.0)
		)
		
		# 顺着视线打一根射线：拿到“近侧玻璃” (进水点)
		var entry_pt = tank_box.intersects_ray(ray_origin, ray_dir)
		
		# 只有当鼠标真的指在玻璃缸范围内时，才进行下一步
		if entry_pt != null:
			# 【黑魔法：反向打射线】：拿到“远侧对侧玻璃” (出水点)
			var far_origin = ray_origin + ray_dir * 100.0
			var exit_pt = tank_box.intersects_ray(far_origin, -ray_dir)
			
			if exit_pt != null:
				# 测算近侧玻璃背后的泥土真实高度
				var query_near = PhysicsRayQueryParameters3D.create(
					Vector3(entry_pt.x, drop_height + 5.0, entry_pt.z),
					Vector3(entry_pt.x, -10.0, entry_pt.z)
				)
				query_near.collision_mask = 2 # 只测泥土层
				var result_near = space_state.intersect_ray(query_near)
				
				var soil_h_near = soil_body.global_position.y
				if result_near:
					soil_h_near = result_near.position.y
					
				# 【灵魂判定：点的是黑土，还是空玻璃？】
				if entry_pt.y <= soil_h_near + 0.05: 
					# 视线比泥土低：看的是黑乎乎的泥土侧面！停在近端！
					target_x = entry_pt.x
					target_z = entry_pt.z
				else:
					# 视线比泥土高：看的是透明空气！直接穿透到对侧！
					target_x = exit_pt.x
					target_z = exit_pt.z
					
				hit_success = true
			
	if hit_success:
		# 3. 强行钳制坐标，实现边缘吸附
		var safe_x = clamp(target_x, -valid_bounds, valid_bounds)
		var safe_z = clamp(target_z, -valid_bounds, valid_bounds)
		
		# 4. 垂直探照灯：无论在缸内还是边缘，都重新获取一次精确的地形高度
		var query_origin = Vector3(safe_x, drop_height + 5.0, safe_z) 
		var height_query = PhysicsRayQueryParameters3D.create(query_origin, query_origin + Vector3.DOWN * 20.0)
		height_query.collision_mask = 2
		
		var height_result = space_state.intersect_ray(height_query)
		var surface_y = soil_body.global_position.y
		if height_result:
			surface_y = height_result.position.y
			
		var safe_pos = Vector3(safe_x, surface_y, safe_z)
		
		# 5. 视觉与逻辑同步
		placement_cursor.visible = true
		placement_cursor.global_position = safe_pos
		
		dirt_particles.global_position = Vector3(safe_pos.x, drop_height, safe_pos.z)
		
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			dirt_particles.emitting = true 
			# 【新增】：按下鼠标时，目标角度设为倾斜（比如绕 X 轴倾斜 -60 度，具体正负看你的模型朝向）
			target_tilt = 45.0
			spawn_timer += delta
			var spawn_interval = 1.0 / clumps_per_second 
			
			while spawn_timer >= spawn_interval:
				var fall_distance = drop_height - safe_pos.y
				var fall_time = sqrt(max(0.0, 2.0 * fall_distance / 9.8))
				
				var random_angle = randf() * TAU 
				var random_radius = sqrt(randf()) * drop_radius
				var offset_x = cos(random_angle) * random_radius
				var offset_z = sin(random_angle) * random_radius
				
				var final_x = safe_pos.x + offset_x
				var final_z = safe_pos.z + offset_z
				
				if abs(final_x) <= valid_bounds and abs(final_z) <= valid_bounds:
					var target_pos = Vector3(final_x, safe_pos.y, final_z)
					pending_drops.append({
						"pos": target_pos,
						"time": current_time + fall_time 
					})
				
				spawn_timer -= spawn_interval
		else:
			dirt_particles.emitting = false 
			# 【新增】：松开鼠标，目标角度归零，准备回正
			target_tilt = 0.0
	else:
		# 只有当玩家仰角看天的时候，才会彻底关闭
		placement_cursor.visible = false
		dirt_particles.emitting = false 
		spawn_timer = 0.0
		# 【新增】：鼠标移出缸外，小桶也乖乖回正
		target_tilt = 0.0

	if bucket_model:
		# 使用 lerp 让当前角度极其平滑地向目标角度过渡 (12.0 是跟随速度，可微调)
		bucket_model.rotation_degrees.x = lerp(bucket_model.rotation_degrees.x, target_tilt, 12.0 * delta)
# ==========================================
# 笔刷涂抹 (高度图增加)
# ==========================================
func apply_soil_brush(world_position: Vector3, brush_radius: float, strength: float):
	var center_x = int((world_position.x / PHYSICAL_SIZE + 0.5) * GRID_SIZE)
	var center_y = int((world_position.z / PHYSICAL_SIZE + 0.5) * GRID_SIZE)
	var pixel_radius = int((brush_radius / PHYSICAL_SIZE) * GRID_SIZE)
	
	for x in range(center_x - pixel_radius, center_x + pixel_radius):
		for y in range(center_y - pixel_radius, center_y + pixel_radius):
			if x >= 0 and x < GRID_SIZE and y >= 0 and y < GRID_SIZE:
				var dist = Vector2(x, y).distance_to(Vector2(center_x, center_y))
				
				if dist <= pixel_radius:
					var distance_ratio = dist / float(pixel_radius)
					var weight = smoothstep(1.0, 0.0, distance_ratio)
					
					var current_offset = height_map_image.get_pixel(x, y).r
					var new_offset = current_offset + (strength * weight)
					new_offset = max(new_offset, 0.0)
					
					height_map_image.set_pixel(x, y, Color(new_offset, 0, 0, 1))
	
	height_map_texture.update(height_map_image)

# ==========================================
# 【新增】沙堆塌陷算法 (Cellular Automata)
# ==========================================
# 【升级版】沙堆塌陷算法：单向流动 & 极限保护
func simulate_soil_avalanche() -> bool:
	var is_unstable = false
	
	for x in range(1, GRID_SIZE - 1):
		for y in range(1, GRID_SIZE - 1):
			var current_h = height_map_image.get_pixel(x, y).r
			
			var max_diff = 0.0
			var target_neighbor = Vector2i(-1, -1)
			var neighbor_h = 0.0
			
			# 1. 寻找落差最大的方向（泥土只会向最陡峭的方向滑落）
			var neighbors = [
				Vector2i(x+1, y), Vector2i(x-1, y),
				Vector2i(x, y+1), Vector2i(x, y-1)
			]
			
			for n in neighbors:
				var nh = height_map_image.get_pixel(n.x, n.y).r
				var diff = current_h - nh
				if diff > max_diff:
					max_diff = diff
					target_neighbor = n
					neighbor_h = nh
					
			# 2. 如果最大落差超过了安息角，触发滑落
			if max_diff > max_slope:
				var flow_amount = (max_diff - max_slope) * flow_rate
				
				# 【安全锁】：每次滑落的量，绝对不能超过落差的一半！
				# 否则高地流走太多，反而变成了低地，造成地形震荡抽搐
				flow_amount = min(flow_amount, max_diff / 2.0)
				
				# 当前像素失去高度，最低的邻居获得高度
				height_map_image.set_pixel(x, y, Color(current_h - flow_amount, 0, 0, 1))
				height_map_image.set_pixel(target_neighbor.x, target_neighbor.y, Color(neighbor_h + flow_amount, 0, 0, 1))
				
				# 标记：这帧依然有泥土在滑动，地形还没完全稳定！
				is_unstable = true
				
	height_map_texture.update(height_map_image)
	return is_unstable
