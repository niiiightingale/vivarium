class_name SmoothTool
extends Node3D

@export var soil_manager: Node3D # 指向你的 SoilManager
@export var player_input: PlayerInput

@export var brush_radius: float = 0.8
# 平滑强度不需要太大，0.1 到 0.2 之间刚好，这样拖拽时是一点点融化的感觉
@export var brush_strength: float = 0.1 

var is_smoothing: bool = false

func _ready() -> void:
	deactivate()

# ==========================================
# 工具协议接口
# ==========================================
func activate() -> void:
	visible = true
	set_process(true)
	set_process_unhandled_input(true)
	print("🧽 抹刀激活！按住左键在坑洼处涂抹。")

func deactivate() -> void:
	visible = false
	set_process(false)
	set_process_unhandled_input(false)
	is_smoothing = false # 切走工具时，强制松开左键

# ==========================================
# 输入与位置处理
# ==========================================
func _unhandled_input(event: InputEvent) -> void:
	# 记录左键是否处于“按住”状态
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_smoothing = event.is_pressed()

func _process(_delta: float) -> void:
	if player_input and player_input.is_valid_location:
		var target_pos = player_input.target_position
		
		# 让抹刀模型悬浮在地面上
		global_position = Vector3(target_pos.x, target_pos.y + 0.1, target_pos.z)
		
		# 如果正在按住左键，就持续呼叫 SoilManager 的平滑魔法！
		if is_smoothing:
			soil_manager.apply_smooth_brush(target_pos, brush_radius, brush_strength)
