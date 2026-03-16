class_name BuildUI
extends CanvasLayer

signal tool_selected(index: int)

@onready var container = $VBoxContainer
@export var camera_controller: CameraController 
@onready var btn_idle_toggle = $BtnIdleToggle 

# ✨ 增加两个变量，用来记忆玩家的操作
var current_active_index: int = -1 
var stored_tool_index: int = -1 # 挂机前手里的工具

func _ready():
	var tool_index = 0
	for child in container.get_children():
		if child is Button:
			if child.name == "BtnEmpty":
				child.pressed.connect(_on_btn_pressed.bind(-1))
			else:
				child.pressed.connect(_on_btn_pressed.bind(tool_index))
				tool_index += 1

	if btn_idle_toggle and camera_controller:
		btn_idle_toggle.pressed.connect(camera_controller.toggle_manual_idle)
		# ✨ 核心：监听相机的起床/睡觉信号！
		camera_controller.idle_state_changed.connect(_on_camera_idle_changed)

func _on_btn_pressed(index: int):
	current_active_index = index # 记住当前拿的是啥
	tool_selected.emit(index)
	_update_visuals(index)

# ==========================================
# ✨ 核心魔法：处理挂机与苏醒
# ==========================================
func _on_camera_idle_changed(is_idle: bool):
	if is_idle:
		# 睡着了：把手里的工具存起来，然后强制切成空手（-1），并隐藏工具栏
		stored_tool_index = current_active_index
		tool_selected.emit(-1) 
		container.visible = false
	else:
		# 醒来了：显示工具栏，并把刚才存起来的工具还给玩家
		container.visible = true
		_on_btn_pressed(stored_tool_index)

func _update_visuals(active_index: int):
	var tool_index = 0
	for child in container.get_children():
		if child is Button:
			if child.name == "BtnEmpty":
				child.disabled = (active_index == -1)
			else:
				child.disabled = (active_index == tool_index)
				tool_index += 1
