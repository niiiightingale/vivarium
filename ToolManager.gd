class_name ToolManager
extends Node3D

# ==========================================
# 1. 状态定义 (枚举法是状态机的灵魂)
# ==========================================
enum ToolMode { BUCKET, BRUSH , MOSS }
var current_mode: ToolMode = ToolMode.BUCKET

# ==========================================
# 2. 节点引用
# ==========================================
# 在编辑器里把你的 BucketTool 和 BrushTool 拖到这两个变量里
@export var bucket_tool: Node3D
@export var brush_tool: Node3D

# 记录当前玩家是否按住了左键
var is_using_tool: bool = false

func _ready():
	# 游戏开始时，强制初始化为小桶模式
	_apply_tool_switch(ToolMode.BUCKET, false)

func _unhandled_input(event):
	# ==========================================
	# A. 切换工具逻辑 (按 X 键)
	# ==========================================
	if event.is_action_pressed("toggle_tool"):
		if current_mode == ToolMode.BUCKET:
			_apply_tool_switch(ToolMode.BRUSH)
		else:
			_apply_tool_switch(ToolMode.BUCKET)

	# ==========================================
	# B. 使用工具逻辑 (鼠标左键按下/松开)
	# ==========================================
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_using_tool = event.is_pressed()
		
		# 将玩家的输入状态传递给对应的工具
		if current_mode == ToolMode.BUCKET:
			# 假设你的小桶脚本里有一个 is_pouring 变量
			if "is_pouring" in bucket_tool:
				bucket_tool.is_pouring = is_using_tool
				
		elif current_mode == ToolMode.BRUSH:
			# 触发我们之前在毛刷脚本里写的正弦波摇摆和扬尘！
			if "is_brushing" in brush_tool:
				brush_tool.is_brushing = is_using_tool

func _process(_delta):
	# 从 SoilSystem 或者 PlayerInput 获取鼠标在泥土表面的实时位置
	# 假设你的 SoilSystem 节点叫 soil_system
	var soil_system = get_node("../SoilSystem") # 这里的路径根据你实际修改
	var input = soil_system.player_input
	
	if input and input.is_valid_location:
		var target_pos = input.target_position
		
		# 统一驱动当前激活工具的 XZ 坐标
		if current_mode == ToolMode.BUCKET:
			# 桶在半空
			bucket_tool.global_position = Vector3(target_pos.x, target_pos.y + 1.5, target_pos.z)
		else:
			# 刷子贴地 (0.15)
			brush_tool.global_position = Vector3(target_pos.x, target_pos.y + 0.15, target_pos.z)
# ==========================================
# 3. 核心切换引擎 (处理显示、隐藏与动画)
# ==========================================
func _apply_tool_switch(new_mode: ToolMode, play_animation: bool = true):
	current_mode = new_mode
	
	# 每次切换工具时，强制打断当前的使用状态，防止切工具后还在自动倒土/扫土
	is_using_tool = false
	if "is_pouring" in bucket_tool: bucket_tool.is_pouring = false
	if "is_brushing" in brush_tool: brush_tool.is_brushing = false

	# 1. 逻辑与可见性切换
	if bucket_tool:
		bucket_tool.visible = (current_mode == ToolMode.BUCKET)
		# 如果不显示，直接暂停该节点的 _process，节省性能！
		bucket_tool.set_process(current_mode == ToolMode.BUCKET) 
		
	if brush_tool:
		brush_tool.visible = (current_mode == ToolMode.BRUSH)
		brush_tool.set_process(current_mode == ToolMode.BRUSH)

	# 2. 视觉魔法：Q弹缩放动画 (Juicy Effect)
	if play_animation:
		var active_tool = bucket_tool if current_mode == ToolMode.BUCKET else brush_tool
		if active_tool:
			# 先把模型缩到看不见
			active_tool.scale = Vector3.ZERO
			# 用 TWEEN_ELASTIC 做出带有弹簧阻尼感的弹出效果
			var tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(active_tool, "scale", Vector3.ONE, 0.6)

# ==========================================
# 4. 对外提供当前模式，供 SoilSystem 调用
# ==========================================
func get_current_mode() -> ToolMode:
	return current_mode
