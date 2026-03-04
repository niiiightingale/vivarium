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

func _process(_delta):
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		paint_soil(1.0) 
		
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		paint_soil(-1.0) 
		
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
	update_physics_collision()
