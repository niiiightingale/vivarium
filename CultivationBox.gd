class_name CultivationBox
extends StaticBody3D

@export var soil_mesh_instance: MeshInstance3D 
@export var initial_soil_thickness: float = 0.5 
@export var dig_depth: float = 0.05 

var soil_height_image: Image
var soil_height_texture: ImageTexture

@export var box_size: float = 3.0
@export var pixels_per_meter: int = 20 
@export var template_multimesh: MultiMesh 

var grid_size: int
var moss_image: Image
var moss_texture: ImageTexture

@onready var moss_renderer: MultiMeshInstance3D = $MossMultiMesh

func _ready() -> void:
	grid_size = int(box_size * pixels_per_meter) # 3米 * 20 = 60x60 像素
	
	# 1. 初始化纯绿色的“完美地毯”数据
	moss_image = Image.create(grid_size, grid_size, false, Image.FORMAT_RF)
	moss_image.fill(Color(1.0, 0, 0, 1)) 
	moss_texture = ImageTexture.create_from_image(moss_image)
	
	# 2. 初始化极简版 3D 渲染器
	if template_multimesh:
		var mm = template_multimesh.duplicate()
		mm.instance_count = grid_size * grid_size 
		moss_renderer.multimesh = mm
	
	call_deferred("init_all_meshes") 
	
	# ==========================================
	# ✨ 核心修复：彻底独立的物理泥土地基初始化
	# ==========================================
	soil_height_image = Image.create(grid_size, grid_size, false, Image.FORMAT_RF)
	soil_height_image.fill(Color(initial_soil_thickness, 0.0, 0.0, 1.0))
	soil_height_texture = ImageTexture.create_from_image(soil_height_image)
	
	if soil_mesh_instance:
		# ✨ 暴力保护 1：强行用代码细分网格！确保中间有足够的顶点可以凹陷！
		if soil_mesh_instance.mesh is PlaneMesh:
			soil_mesh_instance.mesh.size = Vector2(box_size, box_size)
			# 强行细分，网格精度对齐像素精度，告别假平原！
			soil_mesh_instance.mesh.subdivide_width = grid_size
			soil_mesh_instance.mesh.subdivide_depth = grid_size
			
		# ✨ 暴力保护 2：材质彻底独立，绝不和生态缸打架
		var base_mat = soil_mesh_instance.material_override
		if not base_mat: 
			base_mat = soil_mesh_instance.get_active_material(0)
			
		if base_mat:
			var unique_mat = base_mat.duplicate()
			# 统一使用 material_override，优先级最高且绝对独立
			soil_mesh_instance.material_override = unique_mat
			
			unique_mat.set_shader_parameter("height_map", soil_height_texture)
			# ✨ 暴力保护 3：强行纠正 Shader 的物理尺寸！
			unique_mat.set_shader_parameter("physical_size", box_size)


# ==========================================
# 🔪 极简切割接口 (完美防穿透版)
# ==========================================
func cut_moss(hit_pos: Vector3, radius: float) -> void:
	var local_pos = moss_renderer.to_local(hit_pos)
	var cx = int((local_pos.x / box_size + 0.5) * grid_size)
	var cy = int((local_pos.z / box_size + 0.5) * grid_size)
	
	# 1. 苔藓的断开半径（代表锋利的刀刃本身）
	var moss_pixel_r = max(1, int((radius / box_size) * grid_size))
	
	# 2. ✨ 泥土的塌陷受力半径（模拟面包被刀背挤压，比刀刃宽 3 倍）
	var soil_pixel_r = moss_pixel_r * 3
	
	var changed = false
	for x in range(cx - soil_pixel_r, cx + soil_pixel_r + 1):
		for y in range(cy - soil_pixel_r, cy + soil_pixel_r + 1):
			if x >= 0 and x < grid_size and y >= 0 and y < grid_size:
				var dist = Vector2(x, y).distance_to(Vector2(cx, cy))
				
				# 在宽广的“塌陷区”内
				if dist <= soil_pixel_r:
					
					# A. 仅仅在最核心的“刀刃区”，才会切断苔藓
					if dist <= moss_pixel_r:
						var current_color = moss_image.get_pixel(x, y)
						if current_color.r > 0.0:
							current_color.r = 0.0 
							moss_image.set_pixel(x, y, current_color)
							
							var index = y * grid_size + x
							moss_renderer.multimesh.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
							changed = true
							
					# B. ✨ 核心魔法：泥土的平滑斜坡塌陷
					var current_depth = soil_height_image.get_pixel(x, y).r
					
					# 算出一个从中心 (1.0) 到边缘 (0.0) 的平滑衰减权重
					var normalized_dist = dist / float(soil_pixel_r)
					# 使用余弦函数捏出一个非常平滑、自然的 "U" 型截面
					var weight = pow(cos(normalized_dist * PI * 0.5), 1.5)
					
					# 刀刃最中心要抵达的绝对底线深度
					var target_bottom = max(0.0, initial_soil_thickness - dig_depth)
					
					# ✨ 生成小刀的“曲面印章”：
					# 在这个像素点上，刀刃曲面的高度是多少？(边缘高，中心低)
					var knife_surface_h = lerp(initial_soil_thickness, target_bottom, weight)
					
					# 布尔切除：只有当当前泥土比小刀的曲面要高时，才被削平到曲面高度
					# 这保证了多次反复切削绝不会穿透这层曲面！
					if current_depth > knife_surface_h:
						soil_height_image.set_pixel(x, y, Color(knife_surface_h, 0, 0, 1))
						changed = true
	
	if changed:
		moss_texture.update(moss_image)
		soil_height_texture.update(soil_height_image)
func init_all_meshes() -> void:
	if not moss_renderer.multimesh: return
	var mm = moss_renderer.multimesh
	mm.visible_instance_count = -1 
	
	var rng = RandomNumberGenerator.new()
	
	for y in range(grid_size):
		for x in range(grid_size):
			var index = y * grid_size + x 
			
			if moss_image.get_pixel(x, y).r > 0.1:
				var local_x = (float(x) / grid_size - 0.5) * box_size
				var local_z = (float(y) / grid_size - 0.5) * box_size
				
				rng.seed = hash(str(x) + "_" + str(y) + "_" + name)
				var offset_x = rng.randf_range(-0.02, 0.02)
				var offset_z = rng.randf_range(-0.02, 0.02)
				var t = Transform3D().rotated(Vector3.UP, rng.randf() * TAU)
				t.origin = Vector3(local_x + offset_x, 0.0, local_z + offset_z)
				
				mm.set_instance_transform(index, t)
			else:
				mm.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))

# ==========================================
# 🖐️ 抓手核心：带土拔出 (生成物理坑与形状印章)
# ==========================================
func extract_moss(hit_pos: Vector3) -> Dictionary:
	var local_pos = moss_renderer.to_local(hit_pos)
	var start_x = int((local_pos.x / box_size + 0.5) * grid_size)
	var start_y = int((local_pos.z / box_size + 0.5) * grid_size)
	
	if start_x < 0 or start_x >= grid_size or start_y < 0 or start_y >= grid_size:
		return {}
	if moss_image.get_pixel(start_x, start_y).r <= 0.0:
		return {}
		
	var epicenter_x = (float(start_x) / grid_size - 0.5) * box_size
	var epicenter_z = (float(start_y) / grid_size - 0.5) * box_size
	var epicenter_pos = Vector3(epicenter_x, 0.0, epicenter_z)
	
	var extracted_pixels = []
	var core_pixels = [] # ✨ 用于存下所有被抓起的绝对核心
	
	var queue: Array[Vector2] = [Vector2(start_x, start_y)]
	var visited: Dictionary = {}
	visited[Vector2(start_x, start_y)] = true
	
	# 1. 第一波泛洪：只收集苔藓核心
	while queue.size() > 0:
		var curr = queue.pop_front()
		var cx = int(curr.x); var cy = int(curr.y)
		var current_color = moss_image.get_pixel(cx, cy)
		
		if current_color.r > 0.0:
			core_pixels.append(curr)
			
			var index = cy * grid_size + cx
			var relative_transform = moss_renderer.multimesh.get_instance_transform(index)
			relative_transform.origin -= epicenter_pos
			
			extracted_pixels.append({
				"dx": cx - start_x, "dy": cy - start_y,
				"density": current_color.r, "exact_transform": relative_transform
			})
			
			current_color.r = 0.0
			moss_image.set_pixel(cx, cy, current_color)
			moss_renderer.multimesh.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			
			var neighbors = [ Vector2(cx + 1, cy), Vector2(cx - 1, cy), Vector2(cx, cy + 1), Vector2(cx, cy - 1) ]
			for n in neighbors:
				if n.x >= 0 and n.x < grid_size and n.y >= 0 and n.y < grid_size and not visited.has(n):
					visited[n] = true
					if moss_image.get_pixel(n.x, n.y).r > 0.0: queue.append(n)
							
	if core_pixels.size() == 0: 
		return {}

	# 1. 计算包围盒
	var min_x = grid_size; var max_x = 0
	var min_y = grid_size; var max_y = 0
	for p in core_pixels:
		min_x = min(min_x, int(p.x)); max_x = max(max_x, int(p.x))
		min_y = min(min_y, int(p.y)); max_y = max(max_y, int(p.y))
		
	var mask_w = max_x - min_x + 1
	var mask_h = max_y - min_y + 1
	
	# ✨ 核心魔法 1：准备两张图，一张存“绝对高度”，一张存“形状遮罩”
	var island_height_map = Image.create(mask_w, mask_h, false, Image.FORMAT_RF)
	island_height_map.fill(Color(0, 0, 0, 1))
	
	var shape_mask = Image.create(mask_w, mask_h, false, Image.FORMAT_R8)
	shape_mask.fill(Color(0, 0, 0, 1))
	
	var changed_soil = false
	
	# ✨ 核心魔法 2：绝对平坦的坑底高度 (和小刀切到最底的深度保持完全一致)
	var base_depth = max(0.0, initial_soil_thickness - dig_depth)
	
	for p in core_pixels:
		var cx = int(p.x)
		var cy = int(p.y)
		var local_x = cx - min_x
		var local_y = cy - min_y
		
		# 读取这座岛屿被拔起来前，极其珍贵的“真实高度起伏”
		var current_h = soil_height_image.get_pixel(cx, cy).r
		
		if current_h > base_depth:
			# 拍照留存！把真实高度存进快照图里
			island_height_map.set_pixel(local_x, local_y, Color(current_h, 0, 0, 1))
			shape_mask.set_pixel(local_x, local_y, Color(1, 1, 1, 1)) # 画上白色遮罩
			
			# 原地推平！变成一个平底的深坑
			soil_height_image.set_pixel(cx, cy, Color(base_depth, 0, 0, 1))
			changed_soil = true

	if changed_soil:
		moss_texture.update(moss_image)
		soil_height_texture.update(soil_height_image) 
	
	return {
		"is_valid": true,
		"pixels": extracted_pixels,
		"pixel_physical_size": box_size / float(grid_size),
		"source_mesh": moss_renderer.multimesh.mesh,
		# ✨ 把这两张完美的图传给抓手！
		"island_height_map": island_height_map, 
		"shape_mask": shape_mask,
		"base_depth": base_depth, # 告诉 Shader 这个岛屿是从多深的地方被挖起来的
		"mask_offset_x": min_x - start_x,
		"mask_offset_y": min_y - start_y 
	}
