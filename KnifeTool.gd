class_name KnifeTool
extends Node3D

@export var moss_system: MossSystem
@export var player_input: PlayerInput

@export var knife_width: float = 0.05 
@export var cut_speed: float = 1.5 

enum KnifeState { IDLE, DRAWING, CUTTING }
var state: KnifeState = KnifeState.IDLE

var path_points: Array[Vector3] = []
var current_target_node: Node3D = null
var current_moss_layer: int = 0 

var preview_dots: Array[Node3D] = []

func _ready() -> void:
	deactivate()

func activate() -> void:
	visible = true
	set_process(true)
	set_process_unhandled_input(true)
	state = KnifeState.IDLE

func deactivate() -> void:
	visible = false
	set_process(false)
	set_process_unhandled_input(false)
	state = KnifeState.IDLE
	_clear_preview()

func _unhandled_input(event: InputEvent) -> void:
	if state == KnifeState.CUTTING: return 

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			state = KnifeState.DRAWING
			path_points.clear()
			_clear_preview()
			current_target_node = player_input.hit_collider
		else:
			if path_points.size() > 1:
				state = KnifeState.CUTTING
				
				# ✨ 核心修复 1：鼠标松开时，把小刀瞬间传送回虚线的“起点”！
				# 否则它会从线尾巴直接倒退着直线切回起点，毁掉你的路径！
				global_position = path_points[0]
				
			else:
				state = KnifeState.IDLE
				_clear_preview()

func _process(delta: float) -> void:
	match state:
		KnifeState.IDLE:
			if player_input and player_input.is_valid_location:
				var tp = player_input.target_position
				global_position = Vector3(tp.x, tp.y + 0.1, tp.z)
		KnifeState.DRAWING:
			_handle_drawing()
		KnifeState.CUTTING:
			_handle_cutting_animation(delta)

func _handle_drawing() -> void:
	if not player_input or not player_input.is_valid_location: return
	var target_pos = player_input.target_position
	global_position = Vector3(target_pos.x, target_pos.y + 0.1, target_pos.z)

	# 1. 如果是第一笔，直接记录
	if path_points.is_empty():
		path_points.append(target_pos)
		_spawn_preview_dot(target_pos)
		return

	# 2. 计算当前鼠标位置与上一个点之间的真实距离
	var last_pos = path_points.back()
	var dist = last_pos.distance_to(target_pos)
	
	# ✨ 核心魔法：绝对固定的珠串间距！
	var dot_spacing = 0.1

	# 3. 如果距离超过了设定的间距，我们就把中间漏掉的点全部补齐！
	if dist >= dot_spacing:
		# 计算两帧之间到底能塞下几个标准间距的点
		var steps = floor(dist / dot_spacing) 
		
		for i in range(1, int(steps) + 1):
			# 计算出极其精确的固定比例
			var t = (float(i) * dot_spacing) / dist
			var new_point = last_pos.lerp(target_pos, t)
			
			# 把补出来的点塞进路点列表，并生成模型
			path_points.append(new_point)
			_spawn_preview_dot(new_point)

func _handle_cutting_animation(delta: float) -> void:
	if path_points.is_empty():
		state = KnifeState.IDLE 
		current_target_node = null
		_clear_preview()
		return

	var target_point = path_points[0]
	var dist = global_position.distance_to(target_point)
	var move_step = cut_speed * delta 

	var prev_pos = global_position # 记录移动前的位置

	if dist <= move_step:
		global_position = target_point
		path_points.pop_front()
		if preview_dots.size() > 0:
			var dot = preview_dots.pop_front()
			if is_instance_valid(dot): dot.queue_free()
	else:
		global_position = global_position.move_toward(target_point, move_step)

	# ✨ 核心修复 2：在动画的两帧位移之间进行完美的“插值切削”，绝对不断线！
	_perform_continuous_cut(prev_pos, global_position)

func _perform_continuous_cut(start_pos: Vector3, end_pos: Vector3) -> void:
	var dist = start_pos.distance_to(end_pos)
	var step_size = max(0.01, knife_width * 0.5)
	var steps = max(1, ceil(dist / step_size))
	
	for i in range(1, int(steps) + 1):
		var t = float(i) / float(steps)
		var interp_pos = start_pos.lerp(end_pos, t)
		_perform_cut(interp_pos)

func _perform_cut(pos: Vector3) -> void:
	if current_target_node is CultivationBox:
		current_target_node.cut_moss(pos, knife_width)
	elif current_target_node != null and moss_system != null:
		moss_system.cut_moss(pos, knife_width, current_moss_layer)

func _spawn_preview_dot(pos: Vector3) -> void:
	var dot = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.015
	sphere.height = 0.03
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.8)
	mat.flags_unshaded = true 
	mat.no_depth_test = true 
	sphere.material = mat
	dot.mesh = sphere
	get_tree().current_scene.add_child(dot)
	dot.global_position = Vector3(pos.x, pos.y + 0.05, pos.z) 
	preview_dots.append(dot)

func _clear_preview() -> void:
	for dot in preview_dots:
		if is_instance_valid(dot):
			dot.queue_free()
	preview_dots.clear()
