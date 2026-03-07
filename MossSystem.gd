extends Node

# 引用 SoilSystem 拿到相同的尺寸
@onready var soil_system = get_parent().get_node("SoilSystem")

var moss_image : Image
var moss_texture : ImageTexture

@export var growth_speed: float = 0.1 # 蔓延系数
@export var moss_brush_radius: float = 0.4
@export var moss_brush_strength: float = 0.5

func _ready():
	# 初始化一张和高度图一样大的黑色图片
	moss_image = Image.create(soil_system.GRID_SIZE, soil_system.GRID_SIZE, false, Image.FORMAT_RF)
	moss_image.fill(Color(0, 0, 0, 1))
	moss_texture = ImageTexture.create_from_image(moss_image)
	
	# 把这张图传给渲染泥土的材质
	var mat = soil_system.get_node("PlaneMesh").get_active_material(0)
	mat.set_shader_parameter("moss_map", moss_texture)

# 外部调用的涂抹接口 (由 ToolManager 调用)
func paint_moss(world_pos: Vector3, delta: float):
	var center_x = int((world_pos.x / soil_system.PHYSICAL_SIZE + 0.5) * soil_system.GRID_SIZE)
	var center_y = int((world_pos.z / soil_system.PHYSICAL_SIZE + 0.5) * soil_system.GRID_SIZE)
	var pixel_radius = int((moss_brush_radius / soil_system.PHYSICAL_SIZE) * soil_system.GRID_SIZE)
	
	for x in range(center_x - pixel_radius, center_x + pixel_radius):
		for y in range(center_y - pixel_radius, center_y + pixel_radius):
			if x >= 0 and x < soil_system.GRID_SIZE and y >= 0 and y < soil_system.GRID_SIZE:
				var dist = Vector2(x, y).distance_to(Vector2(center_x, center_y))
				if dist <= pixel_radius:
					var current_m = moss_image.get_pixel(x, y).r
					# 增加苔藓浓度
					var new_m = min(1.0, current_m + moss_brush_strength * delta)
					moss_image.set_pixel(x, y, Color(new_m, 0, 0, 1))
	
	moss_texture.update(moss_image)
