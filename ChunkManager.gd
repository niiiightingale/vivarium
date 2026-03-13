class_name ChunkManager
extends Node3D

const TERRAIN_SIZE = 5.0
const CHUNKS_PER_AXIS = 4 
var chunk_size: float = TERRAIN_SIZE / float(CHUNKS_PER_AXIS)

var chunk_dict: Dictionary = {}
var chunk_counts: Dictionary = {}    
var spawned_pixels: Dictionary = {}  

const MAX_INSTANCES_PER_CHUNK = 2000 

# ==========================================
# ✨ 终极整洁：现在只需暴露一个 MultiMesh 数组！
# ==========================================
@export var plant_multimeshes: Array[MultiMesh] = []
# ✨ 新增：存储8个全局共享的材质，找回你的上帝调节权！
var shared_materials: Array[Material] = []

func initialize_chunks():
	for child in get_children():
		child.queue_free()
	chunk_dict.clear()
	chunk_counts.clear()
	spawned_pixels.clear()
	shared_materials.clear()
	shared_materials.resize(8)

	# ==========================================
	# ✨ 第一步：提前克隆并调配好 8 个“总司令材质”
	# ==========================================
	for plant_type in range(8):
		if plant_type < plant_multimeshes.size() and plant_multimeshes[plant_type] != null:
			var template_mm = plant_multimeshes[plant_type]
			if template_mm.mesh and template_mm.mesh.get_surface_count() > 0:
				var base_mat = template_mm.mesh.surface_get_material(0)
				if base_mat:
					var mat = base_mat.duplicate() # 只在这里克隆 8 次！
					var channel_index = plant_type % 4
					var mask = Vector4(0, 0, 0, 0)
					mask[channel_index] = 1.0
					mat.set_shader_parameter("channel_mask", mask)
					shared_materials[plant_type] = mat

	# ==========================================
	# ✨ 第二步：把总司令材质分发给 16 个区块
	# ==========================================
	for cx in range(CHUNKS_PER_AXIS):
		for cz in range(CHUNKS_PER_AXIS):
			var grid_pos = Vector2i(cx, cz)
			chunk_dict[grid_pos] = []
			chunk_counts[grid_pos] = []
			spawned_pixels[grid_pos] = []

			var chunk_root = Node3D.new()
			chunk_root.name = "Chunk_%d_%d" % [cx, cz]
			add_child(chunk_root)

			for plant_type in range(8):
				var mm_instance = MultiMeshInstance3D.new()
				
				if mm_instance.has_method("set_physics_interpolation_mode"):
					mm_instance.set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)

				if plant_type < plant_multimeshes.size() and plant_multimeshes[plant_type] != null:
					var template_mm = plant_multimeshes[plant_type]
					var multimesh = template_mm.duplicate() # MultiMesh 还是必须每个区块独立的
					
					multimesh.instance_count = MAX_INSTANCES_PER_CHUNK
					multimesh.visible_instance_count = 0
					mm_instance.multimesh = multimesh
					mm_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

					# ✨ 直接引用总司令材质！不再 duplicate！
					if shared_materials[plant_type] != null:
						mm_instance.material_override = shared_materials[plant_type]
				else:
					var empty_mm = MultiMesh.new()
					empty_mm.transform_format = MultiMesh.TRANSFORM_3D
					empty_mm.instance_count = 0
					mm_instance.multimesh = empty_mm

				mm_instance.name = "PlantType_%d" % plant_type
				chunk_root.add_child(mm_instance)
				chunk_dict[grid_pos].append(mm_instance)
				chunk_counts[grid_pos].append(0)
				spawned_pixels[grid_pos].append({})

func update_chunk_materials(height_map: Texture2D, moss_textures: Array[ImageTexture]):
	for cx in range(CHUNKS_PER_AXIS):
		for cz in range(CHUNKS_PER_AXIS):
			var grid_pos = Vector2i(cx, cz)
			var mm_array = chunk_dict[grid_pos]
			for plant_type in range(8):
				var mat = mm_array[plant_type].material_override
				# ✨ 新增判空：没有配置的植物就没有材质，跳过
				if mat != null:
					@warning_ignore("integer_division")
					var img_index = plant_type / 4 
					mat.set_shader_parameter("height_map", height_map)
					mat.set_shader_parameter("moss_map", moss_textures[img_index])
					mat.set_shader_parameter("moss_density_map", moss_textures[img_index])

# ==========================================
# 5. 追加式单像素生成 (Append-Only)
# ==========================================
func spawn_grass_at_pixel(px: int, py: int, plant_type: int, grid_resolution: int, physical_size: float, density_multiplier: float):
	@warning_ignore("integer_division")
	var pixels_per_chunk = grid_resolution / CHUNKS_PER_AXIS

	@warning_ignore("integer_division")
	var cx = px / pixels_per_chunk
	@warning_ignore("integer_division")
	var cz = py / pixels_per_chunk

	var grid_pos = Vector2i(cx, cz)
	if not chunk_dict.has(grid_pos): return

	var pixel_pos = Vector2i(px, py)

	if spawned_pixels[grid_pos][plant_type].has(pixel_pos):
		return 

	var multimesh = chunk_dict[grid_pos][plant_type].multimesh
	var current_count = chunk_counts[grid_pos][plant_type]
	
	# ✨ 安全拦截：如果是没有配置的植物空壳（最大容量为0），直接退出不生成
	if current_count >= multimesh.instance_count:
		return 

	spawned_pixels[grid_pos][plant_type][pixel_pos] = true

	var base_x = (float(px) / grid_resolution - 0.5) * physical_size
	var base_z = (float(py) / grid_resolution - 0.5) * physical_size

	var rng = RandomNumberGenerator.new()
	rng.seed = hash(px * 100000 + py * 100 + plant_type)

	var offset_range = 0.02 / density_multiplier
	var offset_x = rng.randf_range(-offset_range, offset_range)
	var offset_z = rng.randf_range(-offset_range, offset_range)

	var t_rot = Transform3D().rotated(Vector3.UP, rng.randf() * TAU)
	var base_scale = rng.randf_range(0.8, 1.2)
	var t_scale = t_rot.scaled(Vector3(base_scale, base_scale, base_scale))
	t_scale.origin = Vector3(base_x + offset_x, 0.0, base_z + offset_z)

	multimesh.set_instance_transform(current_count, t_scale)
	
	current_count += 1
	chunk_counts[grid_pos][plant_type] = current_count
	multimesh.visible_instance_count = current_count
