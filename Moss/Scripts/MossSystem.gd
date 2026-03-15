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
		# ✨ 核心修复：等一帧！让子弹飞一会儿，确保 SoilManager 已经把噪波地形彻底捏好并生成了 Texture！
	await get_tree().process_frame
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
# ✨ 改动1：函数末尾新增了 is_adding 参数
func paint_moss(world_pos: Vector3, radius: float, strength: float, brush_type: int = 0, is_adding: bool = true):
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
							# ✨ 改动2：判断是在种苔藓，还是在刮苔藓
							if is_adding:
								new_color = current_color.lerp(target_color, final_strength)
								var color_diff = abs(new_color.r - target_color.r) + abs(new_color.g - target_color.g) + abs(new_color.b - target_color.b) + abs(new_color.a - target_color.a)
								if color_diff < 0.1: new_color = target_color
								
								var new_density = 0.0
								if channel_index == 0: new_density = new_color.r
								elif channel_index == 1: new_density = new_color.g
								elif channel_index == 2: new_density = new_color.b
								elif channel_index == 3: new_density = new_color.a
								
								if new_density > 0.05:
									chunk_manager.spawn_grass_at_pixel(x, y, brush_type, soil_manager.GRID_SIZE, soil_manager.PHYSICAL_SIZE, density_multiplier)
							else:
								# 🧼 擦除模式：把当前位置的苔藓颜色向透明 (0,0,0,0) 褪去
								new_color = current_color.lerp(Color(0, 0, 0, 0), final_strength)
								var color_diff = new_color.r + new_color.g + new_color.b + new_color.a
								if color_diff < 0.1: new_color = Color(0, 0, 0, 0)
								
								# TODO: 以后我们可以在这里加一句 chunk_manager.remove_grass_at_pixel() 来同时拔掉 3D 模型
								
						else:
							# 其他图层的颜色处理保持不变（互相排斥）
							new_color = current_color.lerp(Color(0, 0, 0, 0), final_strength)
							var color_diff = new_color.r + new_color.g + new_color.b + new_color.a
							if color_diff < 0.1: new_color = Color(0, 0, 0, 0)
						
						if not current_color.is_equal_approx(new_color):
							moss_images[i].set_pixel(x, y, new_color)
							changed_images[i] = true
							
	for i in range(moss_images.size()):
		if changed_images[i]:
			moss_textures[i].update(moss_images[i])
# 🔪 专属方法：外科手术式切割 (绝对硬边缘清零)
# ==========================================

func cut_moss(world_pos: Vector3, radius: float, brush_type: int = 0):
	if not soil_manager: return
		
	var center_x = int((world_pos.x / soil_manager.PHYSICAL_SIZE + 0.5) * soil_manager.GRID_SIZE)
	var center_y = int((world_pos.z / soil_manager.PHYSICAL_SIZE + 0.5) * soil_manager.GRID_SIZE)
	
	# 确保哪怕半径很小，也至少能切断 1 个像素的宽度
	var pixel_radius = max(1, int((radius / soil_manager.PHYSICAL_SIZE) * soil_manager.GRID_SIZE))
	
	var target_img_index = brush_type / 4
	var channel_index = brush_type % 4
	
	var changed = false
	
	for x in range(center_x - pixel_radius, center_x + pixel_radius + 1):
		for y in range(center_y - pixel_radius, center_y + pixel_radius + 1):
			if x >= 0 and x < soil_manager.GRID_SIZE and y >= 0 and y < soil_manager.GRID_SIZE:
				var dist = Vector2(x, y).distance_to(Vector2(center_x, center_y))
				if dist <= pixel_radius:
					# 🔪 绝对切割：不需要平滑过渡，直接将该像素的浓度归零！
					var current_color = moss_images[target_img_index].get_pixel(x, y)
					if current_color[channel_index] > 0.0:
						current_color[channel_index] = 0.0 # 强制断开连接
						moss_images[target_img_index].set_pixel(x, y, current_color)
						changed = true
						
	# 一刀划完，更新贴图，让 Shader 里的绿色地皮瞬间裂开
	if changed:
		moss_textures[target_img_index].update(moss_images[target_img_index])
		
		# TODO: 这里之后要加上 ChunkManager 的刷新逻辑，让半空中的 3D 苔藓也掉落/消失
# 🌱 终极绝杀：跨界移植苔藓与泥土
# ==========================================
func paste_moss(hit_pos: Vector3, clipboard_data: Dictionary, brush_type: int = 0) -> void:
	if not soil_manager or not chunk_manager or clipboard_data.is_empty(): 
		return
		
	# ==========================================
	# ✨ 步骤 1：先把包裹着苔藓根部的“泥土块”拍进主世界的地里！
	# ==========================================
	soil_manager.paste_soil_chunk(hit_pos, clipboard_data)
	
	# ==========================================
	# 步骤 2：在刚刚凸起的新泥土上，种下真实的 3D 苔藓
	# ==========================================
	var pixels = clipboard_data["pixels"]
	var source_pixel_size = clipboard_data["pixel_physical_size"] 
	
	var target_img_index = brush_type / 4
	var channel_index = brush_type % 4
	var changed = false
	
	for p in pixels:
		var offset_x_m = float(p["dx"]) * source_pixel_size
		var offset_z_m = float(p["dy"]) * source_pixel_size
		var world_x = hit_pos.x + offset_x_m
		var world_z = hit_pos.z + offset_z_m
		
		var grid_x = int((world_x / soil_manager.PHYSICAL_SIZE + 0.5) * soil_manager.GRID_SIZE)
		var grid_y = int((world_z / soil_manager.PHYSICAL_SIZE + 0.5) * soil_manager.GRID_SIZE)
		
		if grid_x >= 0 and grid_x < soil_manager.GRID_SIZE and grid_y >= 0 and grid_y < soil_manager.GRID_SIZE:
			var current_color = moss_images[target_img_index].get_pixel(grid_x, grid_y)
			var new_density = max(current_color[channel_index], p["density"])
			
			if current_color[channel_index] != new_density:
				current_color[channel_index] = new_density
				moss_images[target_img_index].set_pixel(grid_x, grid_y, current_color)
				changed = true
				
				# 呼叫 ChunkManager 在主缸里瞬间种出 3D 实体！
				# 注意：如果这里你的 density_multiplier 报错，请替换为你原本代码里的变量或传 1.0
				chunk_manager.spawn_grass_at_pixel(grid_x, grid_y, brush_type, soil_manager.GRID_SIZE, soil_manager.PHYSICAL_SIZE, 1.0)
				
	if changed:
		moss_textures[target_img_index].update(moss_images[target_img_index])
		print("🌱 完美移植了 %d 像素的活体苔藓！" % pixels.size())
func spawn_solid_moss_block(world_pos: Vector3, size_in_meters: float, brush_type: int = 0):
	var center_x = int((world_pos.x / soil_manager.PHYSICAL_SIZE + 0.5) * soil_manager.GRID_SIZE)
	var center_y = int((world_pos.z / soil_manager.PHYSICAL_SIZE + 0.5) * soil_manager.GRID_SIZE)
	var pixel_size = int((size_in_meters / soil_manager.PHYSICAL_SIZE) * soil_manager.GRID_SIZE)
	
	var target_img_index = brush_type / 4
	var channel_index = brush_type % 4
	
	var changed = false
	for x in range(center_x - pixel_size, center_x + pixel_size):
		for y in range(center_y - pixel_size, center_y + pixel_size):
			if x >= 0 and x < soil_manager.GRID_SIZE and y >= 0 and y < soil_manager.GRID_SIZE:
				var current = moss_images[target_img_index].get_pixel(x, y)
				# 直接将浓度写死为 1.0 (最完美的健康状态)
				current[channel_index] = 1.0
				moss_images[target_img_index].set_pixel(x, y, current)
				changed = true
				
				# 立刻呼叫 3D 生成
				chunk_manager.spawn_grass_at_pixel(x, y, brush_type, soil_manager.GRID_SIZE, soil_manager.PHYSICAL_SIZE, density_multiplier)
				
	if changed:
		moss_textures[target_img_index].update(moss_images[target_img_index])
