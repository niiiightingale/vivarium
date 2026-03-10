class_name MossSystem
extends Node

# ==========================================
# 1. 外部依赖
# ==========================================


@export var soil_manager: SoilManager # 需要知道泥土系统的尺寸和 Shader 材质

var moss_image: Image
var moss_texture: ImageTexture

@onready var multimesh_nodes = [
	$MossMultiMesh_0,
	$MossMultiMesh_1,
	$MossMultiMesh_2,
	$MossMultiMesh_3
]
var multimeshes: Array[MultiMesh] = []
# ==========================================
# 苔藓生成控制
# ==========================================
# 1.0 = 1万棵草, 1.5 = 2.25万棵草, 2.0 = 4万棵草 (注意：调太高会消耗 CPU！)
@export var density_multiplier: float = 1.5 
var moss_grid_size: int = 100

# 性能保护：网格更新缓冲
# ==========================================
var needs_mesh_update: bool = false
var mesh_update_timer: float = 0.0

# ==========================================
# 2. 内部数据
# ==========================================


func _ready():
	if not soil_manager:
		return
		
	moss_image = Image.create(soil_manager.GRID_SIZE, soil_manager.GRID_SIZE, false, Image.FORMAT_RGBAF)
	moss_image.fill(Color(0, 0, 0, 0)) 
	moss_texture = ImageTexture.create_from_image(moss_image)
	
	var soil_mat = soil_manager.get_node("PlaneMesh").get_active_material(0)
	if soil_mat:
		soil_mat.set_shader_parameter("moss_map", moss_texture)
	
	moss_grid_size = int(soil_manager.GRID_SIZE * density_multiplier)
	var max_instances = moss_grid_size * moss_grid_size
	
	# 【核心修改】：初始化所有 4 个花盆的坑位和 Shader 参数！
	for i in range(4):
		if multimesh_nodes[i]:
			var mm = multimesh_nodes[i].multimesh
			
			# ==========================================
			# ✨ 【救命代码】：强行克隆一份独立的资源！
			# 彻底斩断 Ctrl+D 带来的资源共享诅咒，让 4 个花盆各自独立！
			# ==========================================
			mm = mm.duplicate()
			multimesh_nodes[i].multimesh = mm 
			
			multimeshes.append(mm)
			mm.instance_count = max_instances
			mm.visible_instance_count = max_instances
			
			for j in range(max_instances):
				var t = Transform3D().scaled(Vector3.ZERO)
				t.origin = Vector3(0, -100.0, 0) 
				mm.set_instance_transform(j, t)
				
			# 给对应的材质戴上正确的“滤色镜”
			var mat = multimesh_nodes[i].material_override
			if mat:
				var mask = Vector4(0,0,0,0)
				mask[i] = 1.0 # 0号是R(1,0,0,0)，1号是G(0,1,0,0)...
				mat.set_shader_parameter("channel_mask", mask)
			
	await get_tree().process_frame 
	
	for i in range(4):
		if multimesh_nodes[i] and multimesh_nodes[i].material_override:
			# 获取第一层材质
			var current_mat = multimesh_nodes[i].material_override
			
			# ✨ 核心修复：顺藤摸瓜，用 while 循环给所有的 Next Pass 透传动态数据！
			while current_mat != null:
				# 1. 传高度图
				current_mat.set_shader_parameter("height_map", soil_manager.height_map_texture)
				
				# 2. 传浓度图 
				# (⚠️ 注意：我们新版贴地 Shader 里用的名字是 moss_map，
				# 为了防错，我建议把 moss_map 和 moss_density_map 全给它塞进去)
				current_mat.set_shader_parameter("moss_map", moss_texture)
				current_mat.set_shader_parameter("moss_density_map", moss_texture)
				
				# 3. 传通道遮罩（如果你 Shader 里用到了的话）
				var mask = Vector4(0, 0, 0, 0)
				mask[i] = 1.0
				current_mat.set_shader_parameter("channel_mask", mask)
				
				# 👉 钻进下一层材质，继续循环喂数据！
				current_mat = current_mat.next_pass
# ==========================================
func _physics_process(delta: float) -> void:
	# 降频刷新保护：如果需要更新，我们每隔 0.1 秒才真正去生成一次 3D 网格，绝不卡顿！
	if needs_mesh_update:
		mesh_update_timer += delta
		if mesh_update_timer > 0.1:
			update_multimesh()
			needs_mesh_update = false
			mesh_update_timer = 0.0
			
# ✨ 核心算法：将 2D 图片翻译成 3D 纸片草丛 ✨
# ==========================================
func update_multimesh():
	if multimeshes.is_empty() or not soil_manager:
		return

	var rng = RandomNumberGenerator.new() 
	
	for x in range(moss_grid_size):
		for y in range(moss_grid_size):
			var idx = y * moss_grid_size + x 
			
			var img_x = int((float(x) / moss_grid_size) * soil_manager.GRID_SIZE)
			var img_y = int((float(y) / moss_grid_size) * soil_manager.GRID_SIZE)
			img_x = clamp(img_x, 0, soil_manager.GRID_SIZE - 1)
			img_y = clamp(img_y, 0, soil_manager.GRID_SIZE - 1)
			
			var color_data = moss_image.get_pixel(img_x, img_y)
			# 提取出当前像素的四种植物浓度
			var densities = [color_data.r, color_data.g, color_data.b, color_data.a]
			
			rng.seed = hash(Vector2(x, y))
			
			var base_x = (float(x) / moss_grid_size - 0.5) * soil_manager.PHYSICAL_SIZE
			var base_z = (float(y) / moss_grid_size - 0.5) * soil_manager.PHYSICAL_SIZE
			
			var offset_range = 0.02 / density_multiplier 
			var offset_x = rng.randf_range(-offset_range, offset_range)
			var offset_z = rng.randf_range(-offset_range, offset_range)
			var final_x = base_x + offset_x
			var final_z = base_z + offset_z
			
			var t_rot = Transform3D().rotated(Vector3.UP, rng.randf() * TAU)
			var base_scale = rng.randf_range(0.8, 1.2)
			var t_scale = t_rot.scaled(Vector3(base_scale, base_scale, base_scale))
			t_scale.origin = Vector3(final_x, 0.0, final_z)
			
			var t_hidden = Transform3D().scaled(Vector3.ZERO)
			t_hidden.origin = Vector3(0, -100.0, 0)
			
			# 【核心修改】：把生成逻辑分发给 4 个 MultiMesh！
			for type in range(4):
				if densities[type] > 0.05:
					multimeshes[type].set_instance_transform(idx, t_scale)
				else:
					multimeshes[type].set_instance_transform(idx, t_hidden)
func paint_moss(world_pos: Vector3, radius: float, strength: float, brush_type: int = 0):
	var center_x = int((world_pos.x / soil_manager.PHYSICAL_SIZE + 0.5) * soil_manager.GRID_SIZE)
	var center_y = int((world_pos.z / soil_manager.PHYSICAL_SIZE + 0.5) * soil_manager.GRID_SIZE)
	var pixel_radius = int((radius / soil_manager.PHYSICAL_SIZE) * soil_manager.GRID_SIZE)
	
	# 根据你选的笔刷，设定“目标纯色”
	var target_color = Color(0, 0, 0, 0)
	if brush_type == 0: target_color = Color(1, 0, 0, 0)   # 1号刷：纯红 (对应苔藓1)
	elif brush_type == 1: target_color = Color(0, 1, 0, 0) # 2号刷：纯绿 (对应苔藓2)
	elif brush_type == 2: target_color = Color(0, 0, 1, 0) # 3号刷：纯蓝 (对应苔藓3)
	elif brush_type == 3: target_color = Color(0, 0, 0, 1) # 4号刷：纯透明(对应苔藓4)
	
	var changed = false
	
	for x in range(center_x - pixel_radius, center_x + pixel_radius):
		for y in range(center_y - pixel_radius, center_y + pixel_radius):
			if x >= 0 and x < soil_manager.GRID_SIZE and y >= 0 and y < soil_manager.GRID_SIZE:
				var dist = Vector2(x, y).distance_to(Vector2(center_x, center_y))
				
				if dist <= pixel_radius:
					var weight = smoothstep(1.0, 0.0, dist / float(pixel_radius))
					
					# 获取当前像素的 RGBA 颜色
					var current_color = moss_image.get_pixel(x, y)
					
					# ✨【核心魔法】：颜色插值挤占！
					# 向目标颜色渐变。如果目标是红色，那么G、B、A通道的值都会被自动按比例缩减！
					var new_color = current_color.lerp(target_color, strength * weight)
					
					# 只有颜色发生实质性变化时才去修改，节省性能
					if not current_color.is_equal_approx(new_color):
						moss_image.set_pixel(x, y, new_color)
						changed = true
						
	if changed:
		moss_texture.update(moss_image)
		needs_mesh_update = true
