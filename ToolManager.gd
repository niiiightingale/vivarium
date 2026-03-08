class_name ToolManager
extends Node3D

# ==========================================
# 1. 状态定义 (枚举法是状态机的灵魂)
# ==========================================
enum ToolMode { BUCKET, BRUSH , MOSS }
var current_mode: ToolMode = ToolMode.BUCKET
# 苔藓系统子状态
# ==========================================
# 0=红(苔藓1), 1=绿(苔藓2), 2=蓝(苔藓3), 3=透明(苔藓4)
var current_moss_brush: int = 0

# ==========================================
# 2. 节点引用
# ==========================================
# 在编辑器里把你的 BucketTool 和 BrushTool 拖到这两个变量里
@export var player_input: PlayerInput  # 【新增】直接获取雷达
@export var soil_manager: Node3D       # 【新增】直接获取泥土系统
@export var moss_system: MossSystem # 【新增】直接获取苔藓系统
@export var bucket_tool: Node3D
@export var drop_radius:float = 0.5
@export var brush_strength:float = 0.05
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
		match current_mode:
			ToolMode.BUCKET:
				_apply_tool_switch(ToolMode.BRUSH)
			ToolMode.BRUSH:
				_apply_tool_switch(ToolMode.MOSS)
			ToolMode.MOSS:
				_apply_tool_switch(ToolMode.BUCKET)

	# ==========================================
	# B. 苔藓画笔快捷切换 (数字键 1-4)
	# ==========================================
	if current_mode == ToolMode.MOSS and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			current_moss_brush = 0
			print("🌿 切换到：1号植物 (R通道)")
		elif event.keycode == KEY_2:
			current_moss_brush = 1
			print("🌾 切换到：2号植物 (G通道)")
		elif event.keycode == KEY_3:
			current_moss_brush = 2
			print("🍄 切换到：3号植物 (B通道)")
		elif event.keycode == KEY_4:
			current_moss_brush = 3
			print("🪨 切换到：4号植物 (A通道)")
			
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

func _process(delta):
	# 1. 安全检查：确保我们在检查器里拖入了这两个关键节点
	if not player_input or not soil_manager:
		return
	
	# 2. 获取雷达数据
	if player_input.is_valid_location:
		var target_pos = player_input.target_position
		
		# 3. 统一驱动当前激活工具的视觉位置
		if current_mode == ToolMode.BUCKET and bucket_tool:
			# 注意：如果 BucketTool 内部自己写了移动逻辑，这里可以注释掉，防止冲突
			bucket_tool.global_position = Vector3(target_pos.x, target_pos.y + 1.5, target_pos.z)
		elif current_mode == ToolMode.BRUSH and brush_tool:
			brush_tool.global_position = Vector3(target_pos.x, target_pos.y + 0.15, target_pos.z)
			
		# ==========================================
		# 4. 核心交互分发 (只管刷子和苔藓，小桶自己管自己了)
		# ==========================================
		if is_using_tool:
			if current_mode == ToolMode.BRUSH:
				# 刷子模式：直接调用泥土系统的减法 API
				# （假设刷子的半径是 0.5，强度是 0.02。你也可以把这两个值作为变量提取出来）
				soil_manager.apply_soil_brush(target_pos, drop_radius, brush_strength, false)
				
			elif current_mode == ToolMode.MOSS and moss_system:
				# 最后一个参数不再是写死的数字，而是你当前选中的画笔！
				moss_system.paint_moss(target_pos, 0.4, 0.05, current_moss_brush)
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
