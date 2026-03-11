class_name ToolManager
extends Node3D

# ==========================================
# 1. 状态定义
# ==========================================
enum ToolMode { BUCKET, BRUSH , MOSS }
var current_mode: ToolMode = ToolMode.BUCKET

# 苔藓系统子状态：现在支持 0 到 7 了！
var current_moss_brush: int = 0

# ==========================================
# 2. 节点引用
# ==========================================
@export var player_input: PlayerInput  
@export var soil_manager: Node3D       
@export var moss_system: MossSystem 
@export var bucket_tool: Node3D
@export var drop_radius:float = 0.5
@export var brush_strength:float = 0.05
@export var brush_tool: Node3D

var is_using_tool: bool = false

func _ready():
	_apply_tool_switch(ToolMode.BUCKET, false)

func _unhandled_input(event):
	# A. 切换工具逻辑
	if event.is_action_pressed("toggle_tool"):
		match current_mode:
			ToolMode.BUCKET: _apply_tool_switch(ToolMode.BRUSH)
			ToolMode.BRUSH: _apply_tool_switch(ToolMode.MOSS)
			ToolMode.MOSS: _apply_tool_switch(ToolMode.BUCKET)

	# ==========================================
	# B. ✨ 苔藓画笔快捷切换 (数字键 1-8 扩充！)
	# ==========================================
	if current_mode == ToolMode.MOSS and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			current_moss_brush = 0; print("🌿 切换到：1号 (图0-R)")
		elif event.keycode == KEY_2:
			current_moss_brush = 1; print("🌾 切换到：2号 (图0-G)")
		elif event.keycode == KEY_3:
			current_moss_brush = 2; print("🍄 切换到：3号 (图0-B)")
		elif event.keycode == KEY_4:
			current_moss_brush = 3; print("🪨 切换到：4号 (图0-A)")
		elif event.keycode == KEY_5:
			current_moss_brush = 4; print("🌱 切换到：5号 (图1-R)")
		elif event.keycode == KEY_6:
			current_moss_brush = 5; print("🌺 切换到：6号 (图1-G)")
		elif event.keycode == KEY_7:
			current_moss_brush = 6; print("🍀 切换到：7号 (图1-B)")
		elif event.keycode == KEY_8:
			current_moss_brush = 7; print("🌵 切换到：8号 (图1-A)")
			
	# C. 使用工具逻辑
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_using_tool = event.is_pressed()
		
		if current_mode == ToolMode.BUCKET:
			if "is_pouring" in bucket_tool: bucket_tool.is_pouring = is_using_tool
		elif current_mode == ToolMode.BRUSH:
			if "is_brushing" in brush_tool: brush_tool.is_brushing = is_using_tool

func _process(delta):
	if not player_input or not soil_manager: return
	
	if player_input.is_valid_location:
		var target_pos = player_input.target_position
		
		if current_mode == ToolMode.BUCKET and bucket_tool:
			bucket_tool.global_position = Vector3(target_pos.x, target_pos.y + 1.5, target_pos.z)
		elif current_mode == ToolMode.BRUSH and brush_tool:
			brush_tool.global_position = Vector3(target_pos.x, target_pos.y + 0.15, target_pos.z)
			
		if is_using_tool:
			if current_mode == ToolMode.BRUSH:
				soil_manager.apply_soil_brush(target_pos, drop_radius, brush_strength, false)
			elif current_mode == ToolMode.MOSS and moss_system:
				moss_system.paint_moss(target_pos, 0.4, 0.05, current_moss_brush)

func _apply_tool_switch(new_mode: ToolMode, play_animation: bool = true):
	current_mode = new_mode
	is_using_tool = false
	if "is_pouring" in bucket_tool: bucket_tool.is_pouring = false
	if "is_brushing" in brush_tool: brush_tool.is_brushing = false

	if bucket_tool:
		bucket_tool.visible = (current_mode == ToolMode.BUCKET)
		bucket_tool.set_process(current_mode == ToolMode.BUCKET) 
		
	if brush_tool:
		brush_tool.visible = (current_mode == ToolMode.BRUSH)
		brush_tool.set_process(current_mode == ToolMode.BRUSH)

	if play_animation:
		var active_tool = bucket_tool if current_mode == ToolMode.BUCKET else brush_tool
		if active_tool:
			active_tool.scale = Vector3.ZERO
			var tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(active_tool, "scale", Vector3.ONE, 0.6)

func get_current_mode() -> ToolMode:
	return current_mode
