class_name PlacementTool
extends Node3D

@export var item_scene: PackedScene 
# ✨【新增】自己持有雷达！在检查器里把 PlayerInput 节点拖给它
@export var player_input: PlayerInput 

var preview_node: PlaceableItem
var current_rotation_y: float = 0.0

func _ready():
	# ✨【新增】默认状态下，先让自己处于“断电休眠”状态
	set_process(false)
	set_process_unhandled_input(false)
	visible = false
	
	# 初始化时，偷偷生成一个“幻影”并设为自己的子节点
	if item_scene:
		preview_node = item_scene.instantiate() as PlaceableItem
		preview_node.is_preview = true
		add_child(preview_node)

# ==========================================
# ✨【新增】工具标准协议：通电与断电
# ==========================================
func activate() -> void:
	visible = true
	set_process(true) # 开启 _process 跟随鼠标
	set_process_unhandled_input(true) # 开启 _unhandled_input 监听点击
	print("🟢 放置工具已激活！")

func deactivate() -> void:
	visible = false
	set_process(false)
	set_process_unhandled_input(false)
	print("🔴 放置工具已关闭！")

# ==========================================
# ✨【新增】自己接管输入监听 (不用再去 ToolManager 里写 if else 了！)
# ==========================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# 1. 滚轮旋转
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			rotate_preview(1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			rotate_preview(-1.0)
			
		# 2. 左键点击放置
		if event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
			if player_input and player_input.is_valid_location:
				attempt_place(player_input.target_position)

# ==========================================
# ✨【新增】自己接管位置更新
# ==========================================
func _process(_delta: float) -> void:
	if player_input and player_input.is_valid_location:
		update_preview(player_input.target_position)

# ==========================================
# 下方逻辑与你原来完全保持一致
# ==========================================
func update_preview(target_pos: Vector3):
	if preview_node:
		preview_node.global_position = target_pos
		preview_node.rotation.y = current_rotation_y

func rotate_preview(direction: float):
	current_rotation_y += direction * deg_to_rad(15.0) 
	if preview_node:
		preview_node.rotation.y = current_rotation_y

func attempt_place(target_pos: Vector3):
	if not preview_node or not preview_node.can_place():
		print("位置无效/冲突，无法放置！")
		return
		
	var real_item = item_scene.instantiate() as PlaceableItem
	real_item.is_preview = false
	
	get_tree().current_scene.add_child(real_item)
	
	real_item.global_position = target_pos
	real_item.rotation.y = current_rotation_y
	real_item.set_as_real_object()
	print("放置成功！")
