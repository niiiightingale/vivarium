class_name PlacementTool
extends Node3D

@export var item_scene: PackedScene 
@export var player_input: PlayerInput 
# ✨ 需要拿到 SoilManager 来查询法线
@export var soil_manager: SoilManager 

var preview_node: PlaceableItem
var current_rotation_y: float = 0.0

func _ready():
	set_process(false)
	set_process_unhandled_input(false)
	visible = false
	
	if item_scene:
		preview_node = item_scene.instantiate() as PlaceableItem
		preview_node.is_preview = true
		add_child(preview_node)

func activate() -> void:
	visible = true
	set_process(true)
	set_process_unhandled_input(true)

func deactivate() -> void:
	visible = false
	set_process(false)
	set_process_unhandled_input(false)

func _unhandled_input(event: InputEvent) -> void:
	# 1. ✨ Q/E 键旋转 (需要你在项目的输入映射 Input Map 里配好 rotate_left 和 rotate_right)
	if event.is_action_pressed("rotate_left"):  # 对应 Q 键
		rotate_preview(1.0)
	elif event.is_action_pressed("rotate_right"): # 对应 E 键
		rotate_preview(-1.0)
		
	# 如果你不想去设置 Input Map，也可以直接硬编码按键（但不推荐）：
	# if event is InputEventKey and event.pressed:
	# 	if event.keycode == KEY_Q: rotate_preview(1.0)
	# 	elif event.keycode == KEY_E: rotate_preview(-1.0)

	if event is InputEventMouseButton:
		# 2. 左键点击放置
		if event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
			if player_input and player_input.is_valid_location:
				attempt_place(player_input.target_position)

func _process(_delta: float) -> void:
	if player_input and player_input.is_valid_location:
		update_preview(player_input.target_position)

func update_preview(target_pos: Vector3):
	if not preview_node: return
	
	preview_node.global_position = target_pos
	
	# ✨ 核心魔法：使用四元数 (Quaternion) 将“法线贴合”与“自身Y轴旋转”完美融合
	var surface_normal = Vector3.UP
	if soil_manager:
		surface_normal = soil_manager.get_soil_normal_at(target_pos)
		
	# 计算让物体的 UP 对齐地表法线的旋转
	var q_align = Quaternion(Vector3.UP, surface_normal)
	# 计算玩家按 Q/E 产生的自身 Y 轴旋转
	var q_spin = Quaternion(Vector3.UP, current_rotation_y)
	
	# 两者相乘，完美融合！
	preview_node.transform.basis = Basis(q_align * q_spin)

func rotate_preview(direction: float):
	current_rotation_y += direction * deg_to_rad(15.0) 
	if player_input and player_input.is_valid_location:
		update_preview(player_input.target_position)

func attempt_place(target_pos: Vector3):
	if not preview_node or not preview_node.can_place():
		print("位置无效/冲突，无法放置！")
		return
		
	var real_item = item_scene.instantiate() as PlaceableItem
	real_item.is_preview = false
	get_tree().current_scene.add_child(real_item)
	
	real_item.global_position = target_pos
	# 把刚才算好的华丽旋转原封不动地交接给真实物体
	real_item.transform.basis = preview_node.transform.basis 
	
	# ✨ 核心修复：把手里拿着的 soil_manager 递给植物，让它自己去监测地形塌陷就好啦！
	real_item.set_as_real_object(soil_manager)
	
	print("放置成功！")
