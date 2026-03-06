@tool
extends Control

# ==========================================
# 🎨 视觉与布局配置
# ==========================================
const RADIUS: float = 110.0      
const DEADZONE: float = 25.0     

var slice_labels = [
	"右视图", "查看所选", "底视图", "摄像机视角",
	"左视图", "前视图", "顶视图", "后视图"
]

var current_hover_index: int = -1
var center_pos: Vector2
var buttons: Array[PanelContainer] = []
var style_normal: StyleBoxFlat
var style_hover: StyleBoxFlat

# 🌟 状态追踪
var is_camera_mode: bool = false

# ==========================================
# 🚀 初始化与生命周期
# ==========================================
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE 
	_init_styles()
	
	for i in range(8):
		var btn = _create_button_node(slice_labels[i])
		add_child(btn)
		buttons.append(btn)
		btn.hide()

func _init_styles() -> void:
	style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.15, 0.15, 0.15, 0.85)
	style_normal.set_corner_radius_all(20) 
	style_normal.content_margin_left = 16
	style_normal.content_margin_right = 16
	style_normal.content_margin_top = 8
	style_normal.content_margin_bottom = 8
	style_normal.set_border_width_all(1) 
	style_normal.border_color = Color(0.3, 0.3, 0.3, 0.5)
	style_normal.shadow_color = Color(0, 0, 0, 0.3)
	style_normal.shadow_size = 4
	
	style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.2, 0.4, 0.6, 0.95)
	style_hover.set_corner_radius_all(20)
	style_hover.set_border_width_all(1)
	style_hover.border_color = Color(0.4, 0.6, 0.8, 0.8)
	style_hover.content_margin_left = 16
	style_hover.content_margin_right = 16
	style_hover.content_margin_top = 8
	style_hover.content_margin_bottom = 8

func _create_button_node(text: String) -> PanelContainer:
	var pc = PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_theme_stylebox_override("panel", style_normal)
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	pc.add_child(label)
	return pc

# ==========================================
# 🕹️ 外部调用接口
# ==========================================
func open_menu() -> void:
	show() 
	center_pos = get_local_mouse_position()
	current_hover_index = -1
	_layout_buttons()
	_update_button_styles()

func close_menu() -> void:
	hide()
	if current_hover_index != -1:
		_execute_action(current_hover_index)
# ==========================================
func _process(_delta: float) -> void:
	if not visible: return
	
	var dir = get_local_mouse_position() - center_pos
	var new_hover_index = -1
	if dir.length() > DEADZONE:
		var angle = dir.angle()
		var index = int(floor((angle + PI / 8.0) / (PI / 4.0)))
		new_hover_index = posmod(index, 8)
	
	if new_hover_index != current_hover_index:
		current_hover_index = new_hover_index
		_update_button_styles()
		queue_redraw()

func _layout_buttons() -> void:
	for i in range(8):
		var btn = buttons[i]
		btn.show()
		btn.reset_size() 
		var angle = i * (PI / 4.0)
		var target_pos = center_pos + Vector2(cos(angle), sin(angle)) * RADIUS
		btn.position = target_pos - (btn.size / 2.0)
		btn.pivot_offset = btn.size / 2.0

func _update_button_styles() -> void:
	for i in range(8):
		var btn = buttons[i]
		btn.add_theme_stylebox_override("panel", style_hover if i == current_hover_index else style_normal)
		btn.scale = Vector2(1.05, 1.05) if i == current_hover_index else Vector2(1.0, 1.0)

func _draw() -> void:
	if not visible: return
	draw_arc(center_pos, DEADZONE - 5, 0, TAU, 32, Color(1, 1, 1, 0.3), 3.0, true)
	draw_circle(center_pos, 4.0, Color(1, 1, 1, 0.8))
	if current_hover_index != -1:
		var btn = buttons[current_hover_index]
		draw_line(center_pos, btn.position + btn.size/2.0, Color(1, 1, 1, 0.2), 2.0)

# ==========================================
# 🎯 核心逻辑 (你的天才思路：精准控制 Ctrl+P)
# ==========================================
func _execute_action(index: int) -> void:
	# 🌟 情况 A：如果我们在预览里，并且选了别的视图 -> 必须按一次 Ctrl+P 退出
	if is_camera_mode and index != 3:
		_simulate_key(KEY_P, true) # 退出预览
		is_camera_mode = false
		await get_tree().process_frame

	_break_axis_lock()
	
	match index:
		0: _simulate_key(KEY_KP_3) # 右
		1: _simulate_key(KEY_F)    # 聚焦
		2: _simulate_key(KEY_KP_7, false, true) # 底
		3: 
			# 🌟 情况 B：我们要切相机视角。
			# 如果之前不在里面，就进去；如果在里面了，就再次按 Ctrl+P 退出
			_toggle_camera_preview()
			is_camera_mode = not is_camera_mode
		4: _simulate_key(KEY_KP_3, false, true) # 左
		5: _simulate_key(KEY_KP_1) # 前
		6: _simulate_key(KEY_KP_7) # 顶
		7: _simulate_key(KEY_KP_1, false, true) # 后

func _simulate_key(keycode: int, ctrl: bool = false, alt: bool = false) -> void:
	var event = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	event.pressed = true
	Input.parse_input_event(event)
	var event_up = event.duplicate()
	event_up.pressed = false
	Input.parse_input_event(event_up)

func _break_axis_lock() -> void:
	# 稍微移动一下鼠标中键即可
	var mb = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_MIDDLE
	mb.position = get_global_mouse_position()
	mb.pressed = true
	Input.parse_input_event(mb)
	
	# 🌟 唯一改动：克隆一个新的事件对象来发送“松开”指令，消除警告
	var mb_up = mb.duplicate()
	mb_up.pressed = false
	Input.parse_input_event(mb_up)

func _toggle_camera_preview() -> void:
	var target_cam: Camera3D = null
	var selection = EditorInterface.get_selection()
	for node in selection.get_selected_nodes():
		if node is Camera3D: target_cam = node; break
	if not target_cam:
		var root = EditorInterface.get_edited_scene_root()
		var cams = root.find_children("*", "Camera3D", true, false)
		if cams.size() > 0: target_cam = cams[0]
	
	if target_cam:
		selection.clear()
		selection.add_node(target_cam)
		await get_tree().process_frame
		_simulate_key(KEY_P, true)
