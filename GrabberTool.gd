class_name GrabberTool
extends Node3D

@export var moss_system: MossSystem
@export var player_input: PlayerInput
@export var main_moss_material: Material
# ✨ 新增：在检查器里，把刚才做的 chunk_material.tres 拖进来！
@export var chunk_base_material: ShaderMaterial

enum GrabState { IDLE, HOLDING }
var state: GrabState = GrabState.IDLE
var clipboard_data: Dictionary = {}

var preview_renderer: MultiMeshInstance3D
# ✨ 新增：泥土块的渲染器
var dirt_chunk_renderer: MeshInstance3D 

func _ready() -> void:
	# 初始化苔藓渲染器
	preview_renderer = MultiMeshInstance3D.new()
	add_child(preview_renderer)
	
	# ✨ 初始化泥土块渲染器
	dirt_chunk_renderer = MeshInstance3D.new()
	add_child(dirt_chunk_renderer)
	
	deactivate()

func activate() -> void:
	visible = true
	set_process(true)
	set_process_unhandled_input(true)
	state = GrabState.IDLE
	print("🖐️ 抓手已就绪！左键抓取/放置，右键取消。")

func deactivate() -> void:
	visible = false
	set_process(false)
	set_process_unhandled_input(false)
	_clear_clipboard()

# ==========================================
# 细节 2：严谨的输入状态机
# ==========================================
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not player_input or not player_input.is_valid_location:
		return
		
	if event is InputEventMouseButton and event.is_pressed():
		var target = player_input.hit_collider
		
		# 左键：抓取 或 粘贴
		if event.button_index == MOUSE_BUTTON_LEFT:
			if state == GrabState.IDLE:
				_try_grab(target, player_input.target_position)
			elif state == GrabState.HOLDING:
				_try_paste(target, player_input.target_position)
				
		# 右键：清空手里的东西
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if state == GrabState.HOLDING:
				_clear_clipboard()

func _process(_delta: float) -> void:
	if player_input and player_input.is_valid_location:
		# 让整个工具（包括预览模型）紧紧跟着鼠标
		global_position = player_input.target_position

# ==========================================
# 核心逻辑：抓取与构建全息预览
# ==========================================
func _try_grab(target: Node3D, hit_pos: Vector3) -> void:
	if target is CultivationBox:
		var extracted = target.extract_moss(hit_pos)
		
		# 如果成功抓到了东西（字典不为空）
		if extracted.has("is_valid") and extracted["is_valid"]:
			clipboard_data = extracted
			state = GrabState.HOLDING
			_build_preview()

# 核心逻辑：生成真实的 3D 苔藓与泥土块！
# ==========================================
func _build_preview() -> void:
	var island_height_map: Image = clipboard_data.get("island_height_map")
	var shape_mask: Image = clipboard_data.get("shape_mask")
	var base_depth: float = clipboard_data.get("base_depth", 0.0)
	var pixels = clipboard_data["pixels"]
	var pixel_size = clipboard_data["pixel_physical_size"]
	
	# ✨ 接收全新的质量守恒厚度图
	var thickness_map: Image = clipboard_data.get("thickness_map")
	var dig_depth = clipboard_data.get("dig_depth", 0.05)
	var mask_offset_x = clipboard_data.get("mask_offset_x", 0)
	var mask_offset_y = clipboard_data.get("mask_offset_y", 0)
	
	var hover_y = 0.1 

	# 1. 重建上方真实的 3D 苔藓
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = pixels.size()
	if clipboard_data.has("source_mesh"): mm.mesh = clipboard_data["source_mesh"]
	if main_moss_material: preview_renderer.material_override = main_moss_material

	for i in range(pixels.size()):
		var p_data = pixels[i]
		var t: Transform3D = p_data["exact_transform"]
		t.origin.y += hover_y
		mm.set_instance_transform(i, t)

	preview_renderer.multimesh = mm

	if island_height_map != null and shape_mask != null and chunk_base_material != null:
		var mask_w = island_height_map.get_width()
		var mask_h = island_height_map.get_height()
		var box_size_x = mask_w * pixel_size
		var box_size_z = mask_h * pixel_size
		
		var box = BoxMesh.new()
		box.size = Vector3(box_size_x, 1.0, box_size_z) 
		box.subdivide_width = mask_w  # 依然需要细分，让顶部有顶点可以撑起起伏
		box.subdivide_depth = mask_h
		
		var active_mat = chunk_base_material.duplicate()
		active_mat.set_shader_parameter("island_height_map", ImageTexture.create_from_image(island_height_map))
		active_mat.set_shader_parameter("shape_mask", ImageTexture.create_from_image(shape_mask))
		active_mat.set_shader_parameter("base_depth", base_depth)
		active_mat.set_shader_parameter("mesh_size", Vector2(box_size_x, box_size_z))
		
		box.material = active_mat
		dirt_chunk_renderer.mesh = box
		
		var exact_center_x = (mask_offset_x + (mask_w - 1.0) / 2.0) * pixel_size
		var exact_center_z = (mask_offset_y + (mask_h - 1.0) / 2.0) * pixel_size
		
		# 底部绝对平坦，放在 hover_y 的高度
		dirt_chunk_renderer.position = Vector3(exact_center_x, hover_y, exact_center_z)
# ==========================================
func _clear_clipboard() -> void:
	clipboard_data.clear()
	state = GrabState.IDLE
	if preview_renderer:
		preview_renderer.multimesh = null 
	if dirt_chunk_renderer:
		dirt_chunk_renderer.mesh = null # ✨ 扔掉手里的泥土块
	print("🗑️ 剪贴板已清空。")
# ==========================================
# 最终出口：执行跨界粘贴！
# ==========================================
func _try_paste(target: Node3D, hit_pos: Vector3) -> void:
	if clipboard_data.is_empty(): return
	
	# 只有当目标不是培育箱时，才允许粘贴（从培育箱拿，放到大世界）
	if target != null and not (target is CultivationBox) and moss_system != null:
		print("🌱 正在将苔藓移植到主生态缸...")
		
		# 呼叫主缸的接收函数！这里可以传当前选择的苔藓类型 current_moss_layer
		# 如果你的 GrabberTool 没有 current_moss_layer 变量，可以直接传 0
		var moss_layer = 0 
		if "current_moss_layer" in self:
			moss_layer = self.current_moss_layer
			
		moss_system.paste_moss(hit_pos, clipboard_data, moss_layer)
		
		# 移植成功后，清空剪贴板并销毁悬浮的全息预览
		_clear_clipboard()
