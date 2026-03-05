extends Node3D

const GRID_SIZE = 100 
const PHYSICAL_SIZE = 5.0 

var height_map_image : Image
var height_map_texture : ImageTexture

@export var brush_radius: float = 0.5  
@export var brush_strength: float = 0.02 

@onready var soil_body = $SoilBody
@onready var collision_shape = $SoilBody/SoilCollision
var height_shape = HeightMapShape3D.new() 

@onready var camera = get_viewport().get_camera_3d()

# 【新增】泥土团预制体和生成控制参数
var dirt_clump_scene = preload("res://DirtClump.tscn")
@export var drop_height: float = 4.0      # 从玻璃缸哪个高度倒下
@export var drop_radius: float = 0.5      # 倾倒的圆形范围半径（与贴花大小呼应）
@export var clumps_per_second: float = 30.0 # 爆发力！每秒生成的土块数量
# 【新增】缸体内部的安全生成边界 (5米直径，边界是2.5，留0.1安全距离)
@export var valid_bounds: float = 2.4
var spawn_timer: float = 0.0
@onready var placement_cursor = $PlacementCursor # 引用我们刚才创建的贴花

# 【新增】物理碰撞延迟刷新系统
var needs_physics_update: bool = false
var physics_update_timer: float = 0.0
@export var physics_update_interval: float = 0.1 # 0.1秒刷新一次物理

func _ready():
	height_map_image = Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RF)
	
	# 初始化：此时没有任何泥土隆起，纯平状态，偏移量全为 0.0
	height_map_image.fill(Color(0.0, 0.0, 0.0, 1.0)) 
	height_map_texture = ImageTexture.create_from_image(height_map_image)
	
	var material = $PlaneMesh.get_active_material(0)
	material.set_shader_parameter("height_map", height_map_texture)

	# 关键步骤：读取 Shader 里配置的默认基础高度，让物理碰撞体垫高自己！
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
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 100.0)
	
	# 极其重要：掩码为2，无视玻璃缸，只打泥土！
	query.collision_mask = 2 
	
	var result = space_state.intersect_ray(query)
	
	if result:
		# 1. 显示光圈，并让光圈紧紧跟随鼠标在地表游走
		placement_cursor.visible = true
		placement_cursor.global_position = result.position
		
		# 2. 如果按住左键，开始疯狂倒土！
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			spawn_timer += delta
			var spawn_interval = 1.0 / clumps_per_second # 计算每个土块之间的间隔时间
			
			# 使用 while 循环：防止帧率波动导致的卡顿，确保绝对的“每秒 N 个”
			while spawn_timer >= spawn_interval:
				spawn_dirt_clump(result.position)
				spawn_timer -= spawn_interval
	else:
		# 如果鼠标指到了缸外虚空，隐藏光圈并重置计时器
		placement_cursor.visible = false
		spawn_timer = 0.0
		
		# 【新增】物理碰撞延迟刷新逻辑
	if needs_physics_update:
		physics_update_timer += delta
		if physics_update_timer >= physics_update_interval:
			update_physics_collision()
			needs_physics_update = false
			physics_update_timer = 0.0
# 【核心修改】在圆形范围内均匀撒土的数学魔法
# ==========================================
func spawn_dirt_clump(center_target: Vector3):
	var random_angle = randf() * TAU 
	var random_radius = sqrt(randf()) * drop_radius
	
	var offset_x = cos(random_angle) * random_radius
	var offset_z = sin(random_angle) * random_radius
	
	# 计算出带有随机偏移的原始坐标
	var final_x = center_target.x + offset_x
	var final_z = center_target.z + offset_z
	
	# 【核心魔法：边界钳制】
	# 强行把 X 和 Z 坐标锁死在玻璃缸的内壁范围内！
	# 超出边界的土块会自动“挤”在玻璃边上掉落，形成极其真实的贴边堆积感。
	final_x = clamp(final_x, -valid_bounds, valid_bounds)
	final_z = clamp(final_z, -valid_bounds, valid_bounds)
	
	var spawn_pos = Vector3(
		final_x, 
		drop_height, 
		final_z
	)
	
	# 4. 实例化土块
	var clump = dirt_clump_scene.instantiate()
	get_tree().current_scene.add_child(clump)
	
	clump.global_position = spawn_pos
	clump.soil_manager = self
	
	# 5. 赋予完全随机的旋转和一点点向下的初速度
	clump.rotation_degrees = Vector3(randf_range(0,360), randf_range(0,360), randf_range(0,360))
	clump.linear_velocity = Vector3(0, -2.0, 0)

func paint_soil(direction: float):
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 100.0)
	var result = space_state.intersect_ray(query)
	
	if result:
		apply_soil_brush(result.position, brush_radius, brush_strength * direction)

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
					
					# 铁底限制：纹理里只存“隆起偏移量”，偏移量最低不能小于 0.0
					# 这样就永远无法挖穿 Shader 里的 min_top_height
					new_offset = max(new_offset, 0.0)
					
					height_map_image.set_pixel(x, y, Color(new_offset, 0, 0, 1))
	
	height_map_texture.update(height_map_image)
	#update_physics_collision()
	needs_physics_update = true
# 【核心修改】终极魔法方案：瞄准底层，高空生成
