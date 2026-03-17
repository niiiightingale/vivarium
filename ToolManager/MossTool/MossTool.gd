class_name MossTool
extends Node3D

@export var moss_system: MossSystem
@export var player_input: PlayerInput

@export var brush_radius: float = 0.4
@export var brush_strength: float = 0.05

var current_moss_brush: int = 0
var is_painting: bool = false
var is_erasing: bool = false

func _ready() -> void:
	deactivate()

# ==========================================
# 工具协议接口
# ==========================================
func activate() -> void:
	visible = true
	set_process(true)
	set_process_unhandled_input(true)
	print("🌿 苔藓刷激活！按 1-8 切换种类，左键涂抹，右键擦除。当前选中: ", current_moss_brush)

func deactivate() -> void:
	visible = false
	set_process(false)
	set_process_unhandled_input(false)
	is_painting = false
	is_erasing = false

# ==========================================
# 独立接管：按键与点击
# ==========================================
func _unhandled_input(event: InputEvent) -> void:
	# 1. 数字键 1-8 切换苔藓类型
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_8:
			current_moss_brush = event.keycode - KEY_1
			print("🌿 切换苔藓刷: ", current_moss_brush)

	# 2. 记录鼠标左右键的“按住”状态
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_painting = event.is_pressed()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			is_erasing = event.is_pressed()

# ==========================================
# 独立接管：每帧跟随与执行
# ==========================================
func _process(_delta: float) -> void:
	if player_input and player_input.is_valid_location:
		var target_pos = player_input.target_position
		
		# 让光标/刷子模型跟着鼠标走
		global_position = Vector3(target_pos.x, target_pos.y + 0.1, target_pos.z)
		
		# 持续调用系统
		if is_painting:
			# ✨ 传入 true 代表涂抹（加法）
			moss_system.paint_moss(target_pos, brush_radius, brush_strength, current_moss_brush, true)
		elif is_erasing:
			# ✨ 传入 false 代表擦除（减法）
			moss_system.paint_moss(target_pos, brush_radius, brush_strength, current_moss_brush, false)
