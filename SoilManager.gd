extends Node3D

# 泥土网格的尺寸
const GRID_SIZE = 100 
const PHYSICAL_SIZE = 5.0 # 5米 x 5米

# 用一张灰度图来存储高度！黑色是0（平地），白色是最高点。
var height_map_image : Image
var height_map_texture : ImageTexture

@export var brush_radius: float = 0.5  # 半径 0.5 米
@export var brush_strength: float = 0.02 # 每次隆起的高度

# 【新增】物理骨架的引用
@onready var soil_body = $SoilBody
@onready var collision_shape = $SoilBody/SoilCollision
var height_shape = HeightMapShape3D.new() # 在内存里捏一个高度图碰撞体

@onready var camera = get_viewport().get_camera_3d()

func _ready():
	# 1. 初始化一张 100x100 的全黑图像，格式选 RF (单通道浮点数，精度极高)
	height_map_image = Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RF)
	height_map_texture = ImageTexture.create_from_image(height_map_image)
	# 拿到泥土网格的材质
	var material = $PlaneMesh.get_active_material(0)
	# 把我们生成的高度图，塞进 Shader 的 "height_map" 变量里！
	material.set_shader_parameter("height_map", height_map_texture)

	# 【新增】初始化物理骨架
	# ==========================================
	height_shape.map_width = GRID_SIZE
	height_shape.map_depth = GRID_SIZE
	collision_shape.shape = height_shape
	
	# 极度关键的缩放！
	# Godot 的 HeightMap 默认每个点相距 1 米，所以 100x100 的图会生成 99x99 米的物理巨兽。
	# 我们必须把它缩放到和我们的网格一样大 (5.0 米)
	var scale_factor = PHYSICAL_SIZE / float(GRID_SIZE - 1)
	soil_body.scale = Vector3(scale_factor, 1.0, scale_factor)
	
	# 游戏开始时同步一次高度
	update_physics_collision()

func update_physics_collision():
	# Godot 的极客操作：直接把图像底层的字节数据，转换成物理引擎要的浮点数组。无需循环，极其高效！
	var float_array = height_map_image.get_data().to_float32_array()
	height_shape.map_data = float_array
# ==========================================
func _process(_delta):
	# 如果按住了鼠标左键
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		paint_soil(1.0) # 向上鼓起
		
	# 如果按住了鼠标右键 (可选：用来挖坑)
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		paint_soil(-1.0) # 向下凹陷
		
func paint_soil(direction: float):
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	
	# 【修改】真正的 3D 物理射线检测
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 100.0)
	var result = space_state.intersect_ray(query)
	
	# 如果射线打到了任何物理物体（我们的泥土骨架）
	if result:
		# result.position 就是打在隆起的山坡上的绝对 3D 坐标！
		apply_soil_brush(result.position, brush_radius, brush_strength * direction)
# ==========================================
# 核心笔刷函数：在这里“捏”泥土
# ==========================================
func apply_soil_brush(world_position: Vector3, brush_radius: float, strength: float):
	# 1. 将 3D 世界坐标转换到 0~100 的图像像素坐标上
	var center_x = int((world_position.x / PHYSICAL_SIZE + 0.5) * GRID_SIZE)
	var center_y = int((world_position.z / PHYSICAL_SIZE + 0.5) * GRID_SIZE)
	
	# 将实际半径(米)换算成像素半径
	var pixel_radius = int((brush_radius / PHYSICAL_SIZE) * GRID_SIZE)
	
	# 2. 遍历笔刷范围内的所有像素（只遍历包围盒，节省性能）
	for x in range(center_x - pixel_radius, center_x + pixel_radius):
		for y in range(center_y - pixel_radius, center_y + pixel_radius):
			
			# 确保不越界
			if x >= 0 and x < GRID_SIZE and y >= 0 and y < GRID_SIZE:
				
				# 计算当前点到笔刷中心的距离
				var dist = Vector2(x, y).distance_to(Vector2(center_x, center_y))
				
				if dist <= pixel_radius:
					# 3. 关键数学：平滑衰减 (Smooth Falloff)
					# 如果不用衰减，刷出来就是一个圆柱体。我们用 smoothstep 让它变成平滑的土丘
					var distance_ratio = dist / float(pixel_radius)
					# smoothstep(1.0, 0.0, ratio) 意味着：中心点权重为1，边缘权重平滑过渡到0
					var weight = smoothstep(1.0, 0.0, distance_ratio)
					
					# 4. 读取旧高度，增加新高度，写入图像
					var current_height = height_map_image.get_pixel(x, y).r
					var new_height = current_height + (strength * weight)
					height_map_image.set_pixel(x, y, Color(new_height, 0, 0, 1))
	
	# 5. 通知显卡更新这张纹理，网格就会瞬间鼓起来！
	height_map_texture.update(height_map_image)
	update_physics_collision()
