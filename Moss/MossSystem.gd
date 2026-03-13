class_name MossSystem
extends Node

@export var soil_manager: SoilManager
@export var chunk_manager: ChunkManager 

var moss_images: Array[Image] = []
var moss_textures: Array[ImageTexture] = []

@export var density_multiplier: float = 1.5 
@export var brush_flow_curve: Curve 

func _ready():
	if not soil_manager or not chunk_manager:
		return
		
	# 1. 建立空画板
	for i in range(2):
		var img = Image.create(soil_manager.GRID_SIZE, soil_manager.GRID_SIZE, false, Image.FORMAT_RGBAF)
		img.fill(Color(0, 0, 0, 0))
		moss_images.append(img)
		moss_textures.append(ImageTexture.create_from_image(img))
	
	var soil_mat = soil_manager.get_node("PlaneMesh").get_active_material(0)
	if soil_mat:
		soil_mat.set_shader_parameter("moss_map_0", moss_textures[0])
		soil_mat.set_shader_parameter("moss_map_1", moss_textures[1])
	
	# 2. 呼叫管家建空仓库
	chunk_manager.initialize_chunks()
	chunk_manager.update_chunk_materials(soil_manager.height_map_texture, moss_textures)

# ==========================================
# 3. 终极性能版画笔系统 (像素级精准触发)
# ==========================================
func paint_moss(world_pos: Vector3, radius: float, strength: float, brush_type: int = 0):
	var center_x = int((world_pos.x / soil_manager.PHYSICAL_SIZE + 0.5) * soil_manager.GRID_SIZE)
	var center_y = int((world_pos.z / soil_manager.PHYSICAL_SIZE + 0.5) * soil_manager.GRID_SIZE)
	var pixel_radius = int((radius / soil_manager.PHYSICAL_SIZE) * soil_manager.GRID_SIZE)
	
	var target_img_index = brush_type / 4
	var channel_index = brush_type % 4
	
	var target_color = Color(0, 0, 0, 0)
	if channel_index == 0: target_color = Color(1, 0, 0, 0)   
	elif channel_index == 1: target_color = Color(0, 1, 0, 0) 
	elif channel_index == 2: target_color = Color(0, 0, 1, 0) 
	elif channel_index == 3: target_color = Color(0, 0, 0, 1) 
	
	var changed_images = []
	changed_images.resize(moss_images.size())
	changed_images.fill(false)
	
	for x in range(center_x - pixel_radius, center_x + pixel_radius):
		for y in range(center_y - pixel_radius, center_y + pixel_radius):
			if x >= 0 and x < soil_manager.GRID_SIZE and y >= 0 and y < soil_manager.GRID_SIZE:
				var dist = Vector2(x, y).distance_to(Vector2(center_x, center_y))
				if dist <= pixel_radius:
					var weight = smoothstep(1.0, 0.0, dist / float(pixel_radius))
					var target_current_color = moss_images[target_img_index].get_pixel(x, y)
					var current_density = 0.0
					if channel_index == 0: current_density = target_current_color.r
					elif channel_index == 1: current_density = target_current_color.g
					elif channel_index == 2: current_density = target_current_color.b
					elif channel_index == 3: current_density = target_current_color.a
					
					var flow_multiplier = 1.0
					if brush_flow_curve:
						flow_multiplier = brush_flow_curve.sample(current_density)
					
					var final_strength = strength * weight * flow_multiplier
					
					for i in range(moss_images.size()):
						var current_color = moss_images[i].get_pixel(x, y)
						var new_color: Color
						
						if i == target_img_index:
							new_color = current_color.lerp(target_color, final_strength)
							var color_diff = abs(new_color.r - target_color.r) + abs(new_color.g - target_color.g) + abs(new_color.b - target_color.b) + abs(new_color.a - target_color.a)
							if color_diff < 0.1: new_color = target_color
							
							# ✨ 核心联动：一旦画笔让浓度突破阈值，立刻叫管家在这个像素精准种草！
							var new_density = 0.0
							if channel_index == 0: new_density = new_color.r
							elif channel_index == 1: new_density = new_color.g
							elif channel_index == 2: new_density = new_color.b
							elif channel_index == 3: new_density = new_color.a
							
							if new_density > 0.05:
								chunk_manager.spawn_grass_at_pixel(x, y, brush_type, soil_manager.GRID_SIZE, soil_manager.PHYSICAL_SIZE, density_multiplier)
								
						else:
							new_color = current_color.lerp(Color(0, 0, 0, 0), final_strength)
							var color_diff = new_color.r + new_color.g + new_color.b + new_color.a
							if color_diff < 0.1: new_color = Color(0, 0, 0, 0)
						
						if not current_color.is_equal_approx(new_color):
							moss_images[i].set_pixel(x, y, new_color)
							changed_images[i] = true
							
	for i in range(moss_images.size()):
		if changed_images[i]:
			moss_textures[i].update(moss_images[i])
