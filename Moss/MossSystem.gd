class_name MossSystem
extends Node

# ==========================================
# 1. 外部依赖
# ==========================================
@export var soil_manager: SoilManager # 需要知道泥土系统的尺寸和 Shader 材质

# ✨ 核心变动：从单张图彻底升级为画板数组！
var moss_images: Array[Image] = []
var moss_textures: Array[ImageTexture] = []

@onready var multimesh_nodes = [
	$MossMultiMesh_0, $MossMultiMesh_1, $MossMultiMesh_2, $MossMultiMesh_3,
	$MossMultiMesh_4, $MossMultiMesh_5, $MossMultiMesh_6, $MossMultiMesh_7
]
var multimeshes: Array[MultiMesh] = []

# ==========================================
# 苔藓生成控制
# ==========================================
@export var density_multiplier: float = 1.5 
@export var brush_flow_curve: Curve # 画笔流量曲线 (控制长按加速)
var moss_grid_size: int = 100

# ==========================================
# 2. 核心初始化 (GPU-Driven 预生成 8 种植物)
# ==========================================
func _ready():
	if not soil_manager:
		return
		
	# ✨ 1. 初始化两张画板 (装载 8 个通道)
	for i in range(2):
		var img = Image.create(soil_manager.GRID_SIZE, soil_manager.GRID_SIZE, false, Image.FORMAT_RGBAF)
		img.fill(Color(0, 0, 0, 0))
		moss_images.append(img)
		moss_textures.append(ImageTexture.create_from_image(img))
	
	# 同步给泥土 (注意：泥土 Shader 里要改成 moss_map_0 和 moss_map_1)
	var soil_mat = soil_manager.get_node("PlaneMesh").get_active_material(0)
	if soil_mat:
		soil_mat.set_shader_parameter("moss_map_0", moss_textures[0])
		soil_mat.set_shader_parameter("moss_map_1", moss_textures[1])
	
	moss_grid_size = int(soil_manager.GRID_SIZE * density_multiplier)
	var max_instances = moss_grid_size * moss_grid_size
	var rng = RandomNumberGenerator.new()
	
	# ✨ 2. 循环 8 次，预生成 8 个 MultiMesh
	for i in range(8):
		if multimesh_nodes[i]:
			var mm = multimesh_nodes[i].multimesh
			mm = mm.duplicate()
			multimesh_nodes[i].multimesh = mm 
			
			multimeshes.append(mm)
			mm.instance_count = max_instances
			mm.visible_instance_count = max_instances
			
			# 给对应的材质戴上正确的“滤色镜” (0~3 循环)
			var mat = multimesh_nodes[i].material_override
			if mat:
				var channel_index = i % 4
				var mask = Vector4(0,0,0,0)
				mask[channel_index] = 1.0 
				mat.set_shader_parameter("channel_mask", mask)
			
			rng.seed = hash(i * 12345) 
			
			for x in range(moss_grid_size):
				for y in range(moss_grid_size):
					var idx = y * moss_grid_size + x 
					var base_x = (float(x) / moss_grid_size - 0.5) * soil_manager.PHYSICAL_SIZE
					var base_z = (float(y) / moss_grid_size - 0.5) * soil_manager.PHYSICAL_SIZE
					
					var offset_range = 0.02 / density_multiplier 
					var offset_x = rng.randf_range(-offset_range, offset_range)
					var offset_z = rng.randf_range(-offset_range, offset_range)
					
					var t_rot = Transform3D().rotated(Vector3.UP, rng.randf() * TAU)
					var base_scale = rng.randf_range(0.8, 1.2)
					var t_scale = t_rot.scaled(Vector3(base_scale, base_scale, base_scale))
					
					t_scale.origin = Vector3(base_x + offset_x, 0.0, base_z + offset_z)
					mm.set_instance_transform(idx, t_scale)
			
	await get_tree().process_frame 
	
	# ✨ 3. 统一往下传 Shader 贴图参数 (精准分发给 8 个图层)
	# ✨ 3. 统一往下传 Shader 贴图参数 (极简版！)
	for i in range(8):
		if multimesh_nodes[i] and multimesh_nodes[i].material_override:
			var img_index = i / 4 # 0~3得0，4~7得1
			var channel_index = i % 4
			
			var mat = multimesh_nodes[i].material_override
			
			# 直接传给当前这一层材质即可，没有 next_pass 了！
			mat.set_shader_parameter("height_map", soil_manager.height_map_texture)
			mat.set_shader_parameter("moss_map", moss_textures[img_index])
			mat.set_shader_parameter("moss_density_map", moss_textures[img_index])
			
			var mask = Vector4(0, 0, 0, 0)
			mask[channel_index] = 1.0
			mat.set_shader_parameter("channel_mask", mask)


# ==========================================
# 3. 纯净版画笔系统 (支持跨画板挤占的大逃杀模式！)
# ==========================================
func paint_moss(world_pos: Vector3, radius: float, strength: float, brush_type: int = 0):
	var center_x = int((world_pos.x / soil_manager.PHYSICAL_SIZE + 0.5) * soil_manager.GRID_SIZE)
	var center_y = int((world_pos.z / soil_manager.PHYSICAL_SIZE + 0.5) * soil_manager.GRID_SIZE)
	var pixel_radius = int((radius / soil_manager.PHYSICAL_SIZE) * soil_manager.GRID_SIZE)
	
	# 锁定我们要画的目标图和通道
	var target_img_index = brush_type / 4
	var channel_index = brush_type % 4
	
	var target_color = Color(0, 0, 0, 0)
	if channel_index == 0: target_color = Color(1, 0, 0, 0)   
	elif channel_index == 1: target_color = Color(0, 1, 0, 0) 
	elif channel_index == 2: target_color = Color(0, 0, 1, 0) 
	elif channel_index == 3: target_color = Color(0, 0, 0, 1) 
	
	# 用一个数组来记录哪张画板发生了改变
	var changed_images = []
	changed_images.resize(moss_images.size())
	changed_images.fill(false)
	
	for x in range(center_x - pixel_radius, center_x + pixel_radius):
		for y in range(center_y - pixel_radius, center_y + pixel_radius):
			if x >= 0 and x < soil_manager.GRID_SIZE and y >= 0 and y < soil_manager.GRID_SIZE:
				var dist = Vector2(x, y).distance_to(Vector2(center_x, center_y))
				
				if dist <= pixel_radius:
					var weight = smoothstep(1.0, 0.0, dist / float(pixel_radius))
					
					# 1. 先读取目标画板，算出画笔的流速 (Flow)
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
					
					# 2. ✨ 核心魔法：遍历所有的画板！执行大逃杀！
					for i in range(moss_images.size()):
						var current_color = moss_images[i].get_pixel(x, y)
						var new_color: Color
						
						if i == target_img_index:
							# 目标画板：往目标颜色挤占
							new_color = current_color.lerp(target_color, final_strength)
							var color_diff = abs(new_color.r - target_color.r) + abs(new_color.g - target_color.g) + abs(new_color.b - target_color.b) + abs(new_color.a - target_color.a)
							if color_diff < 0.1:
								new_color = target_color
						else:
							# 其他画板：被无情地擦除成纯透明 Color(0,0,0,0)！
							new_color = current_color.lerp(Color(0, 0, 0, 0), final_strength)
							var color_diff = new_color.r + new_color.g + new_color.b + new_color.a
							if color_diff < 0.1:
								new_color = Color(0, 0, 0, 0)
						
						# 如果像素有变化，写回并标记这张画板需要更新
						if not current_color.is_equal_approx(new_color):
							moss_images[i].set_pixel(x, y, new_color)
							changed_images[i] = true
							
	# 3. 把发生改变的画板提交给显卡
	for i in range(moss_images.size()):
		if changed_images[i]:
			moss_textures[i].update(moss_images[i])
