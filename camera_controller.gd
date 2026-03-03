extends Node3D

# ==========================================
# 摄像机控制参数 (可以在右侧面板随时调手感)
# ==========================================
@export var orbit_sensitivity: float = 0.005 # 鼠标拖动时的旋转灵敏度
@export var zoom_speed: float = 0.5          # 滚轮缩放速度
@export var min_zoom: float = 1.0            # 离泥土最近的距离
@export var max_zoom: float = 10.0           # 离泥土最远的距离

@onready var camera = $Camera3D

# 记录当前的缩放距离
var current_zoom: float = 5.0

func _ready():
	# 初始化时，确保摄像机的距离是对的
	current_zoom = camera.position.z

# ==========================================
# 核心逻辑：拦截并处理鼠标输入
# ==========================================
func _input(event):
	# 1. 处理视角旋转 (按住鼠标中键 + 移动鼠标)
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			# 左右移动鼠标 -> 绕 Y 轴旋转 (水平环顾)
			rotate_y(-event.relative.x * orbit_sensitivity)
			
			# 上下移动鼠标 -> 绕 X 轴旋转 (俯仰)
			var new_rot_x = rotation.x - event.relative.y * orbit_sensitivity
			
			# 极度关键的限制 (Clamp)：
			# 限制俯仰角，防止摄像机翻转过去 (产生眩晕)，或者钻到泥土底下去
			# -PI/2 是正上方俯视，0.0 是平视 (如果你的泥土在 Y=0)
			rotation.x = clamp(new_rot_x, -PI / 2 + 0.05, PI / 2 - 0.05)

	# 2. 处理视角缩放 (滚轮上下)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			current_zoom -= zoom_speed  # 滚轮向上，拉近视角
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			current_zoom += zoom_speed  # 滚轮向下，拉远视角
			
		# 限制缩放的最大和最小距离
		current_zoom = clamp(current_zoom, min_zoom, max_zoom)
		
		# 将算好的距离直接赋给摄像机的 Z 轴
		camera.position.z = current_zoom
