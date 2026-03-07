class_name CameraController
extends Node3D

# ==========================================
# 操控手感参数
# ==========================================
@export var pan_speed: float = 0.015      
@export var rotation_speed: float = 0.005 
@export var zoom_speed: float = 2.0       

@export var min_zoom: float = 4.0         
@export var max_zoom: float = 15.0        

@export var bounds_xz: float = 3.0        
@export var bounds_y_min: float = -1.0    
@export var bounds_y_max: float = 10.0    

@export var min_pitch: float = -80.0      
@export var max_pitch: float = -10.0      

# ==========================================
# 【新增】挂机展示模式参数 (Idle Showcase)
# ==========================================
@export var enable_idle_mode: bool = true      # 是否开启挂机展示
@export var idle_time_threshold: float = 10.0  # 多少秒无操作后触发
@export var opening_zoom: float = 30.0         # 开场极远距离
@export var opening_duration: float = 4.0      # 【新增】开场运镜耗时（秒），随便调！

var opening_tween: Tween # 用来存开场动画的引用，方便随时打断         # 【新增】开场运镜的极远起始距离
@export var idle_zoom: float = 12.0            # 展示模式下的完美缩放距离
@export var idle_pitch: float = -30.0          # 展示模式下的完美俯视角度(度数)
@export var idle_height_offset: float = 2.0
@export var idle_rotation_speed: float = 0.05  # 自动旋转的速度
@export var idle_transition_speed: float = 1.5 # 自动归位的平滑过渡速度

@onready var camera = $Camera3D

var target_position: Vector3
var target_zoom: float

var target_yaw: float = 0.0   
var target_pitch: float = 0.0 

var is_panning: bool = false
var is_rotating: bool = false

# 挂机计时器
var idle_timer: float = 0.0
var is_idle_mode: bool = false

func _ready():
	is_idle_mode = true
	
	target_position = Vector3(0.0, idle_height_offset, 0.0)
	target_pitch = deg_to_rad(idle_pitch)
	target_yaw = rotation.y 
	
	global_position = target_position
	rotation.x = target_pitch
	
	# 1. 初始把真实距离和目标距离都设为极远
	camera.position.z = opening_zoom
	target_zoom = opening_zoom 
	
	# 2. 【核心运镜魔法：Tween】
	# set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT) 是一种“先快后慢”的电影级减速曲线
	opening_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	opening_tween.tween_property(self, "target_zoom", idle_zoom, opening_duration)

# 【新增】打断挂机状态的方法
func reset_idle_timer():
	idle_timer = 0.0
	if is_idle_mode:
		is_idle_mode = false
		# 退出展示模式时，将目标偏航角重置为当前真实角度，防止镜头鬼畜狂转
		target_yaw = rotation.y

func _unhandled_input(event):
	# 任何鼠标的点击或滑动，都会瞬间唤醒镜头，交还给玩家控制！
	# 【核心修改】：只有鼠标按键操作（左键/中键/右键点击、滚轮滚动）才会打断挂机状态！
	# 纯粹的鼠标滑动 (InputEventMouseMotion) 彻底被放行。
	if event is InputEventMouseButton:
		reset_idle_timer()

	if event is InputEventMouseButton:
		# 1. 焦点缩放 
		if event.is_action_pressed("camera_zoom_in") or event.is_action_pressed("camera_zoom_out"):
			var is_zoom_in = event.is_action_pressed("camera_zoom_in")
			
			var mouse_pos = get_viewport().get_mouse_position()
			var ray_origin = camera.project_ray_origin(mouse_pos)
			var ray_dir = camera.project_ray_normal(mouse_pos)
			var space_state = get_world_3d().direct_space_state
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 100.0)
			query.collision_mask = 2 
			
			var result = space_state.intersect_ray(query)
			
			if result:
				var hit_pos = result.position
				if is_zoom_in and target_zoom > min_zoom:
					var actual_step = min(zoom_speed, target_zoom - min_zoom)
					var shift_weight = actual_step / target_zoom
					target_zoom -= actual_step
					target_position = target_position.lerp(hit_pos, shift_weight)
				elif not is_zoom_in and target_zoom < max_zoom:
					var actual_step = min(zoom_speed, max_zoom - target_zoom)
					var shift_weight = actual_step / target_zoom
					target_zoom += actual_step
					target_position += (target_position - hit_pos) * shift_weight
			else:
				if is_zoom_in: target_zoom = clamp(target_zoom - zoom_speed, min_zoom, max_zoom)
				else: target_zoom = clamp(target_zoom + zoom_speed, min_zoom, max_zoom)

			clamp_target_position()

	# 2. 状态开关 
	if event.is_action_pressed("camera_rotate", false, true):
		is_rotating = true
	elif event.is_action_released("camera_rotate", true):
		is_rotating = false
		
	if event.is_action_pressed("camera_pan", false, true):
		is_panning = true
	elif event.is_action_released("camera_pan", true):
		is_panning = false

	# 3. 滑动拖拽执行 
	if event is InputEventMouseMotion:
		if is_rotating:
			target_yaw -= event.relative.x * rotation_speed
			target_pitch -= event.relative.y * rotation_speed
			target_pitch = clamp(target_pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))

		if is_panning:
			var cam_right = camera.global_transform.basis.x.normalized()
			var cam_up = camera.global_transform.basis.y.normalized()
			
			target_position -= cam_right * event.relative.x * pan_speed
			target_position += cam_up * event.relative.y * pan_speed
			clamp_target_position()

func clamp_target_position():
	target_position.x = clamp(target_position.x, -bounds_xz, bounds_xz)
	target_position.y = clamp(target_position.y, bounds_y_min, bounds_y_max)
	target_position.z = clamp(target_position.z, -bounds_xz, bounds_xz)

func _physics_process(delta: float) -> void:
	# ==========================================
	# 【新增】展示模式计时与拦截
	# ==========================================
	# 只要玩家没有在按住中键/右键，就开始计时
	if enable_idle_mode and not is_rotating and not is_panning:
		idle_timer += delta
		if idle_timer >= idle_time_threshold:
			is_idle_mode = true

	# 如果进入了挂机模式，AI开始接管目标变量
	if is_idle_mode:
		# 1. 目标位置极其缓慢地向缸体中心(0,0,0)靠拢
		# 1. 目标位置向缸体中心的高空目标点靠拢
		var perfect_center = Vector3(0.0, idle_height_offset, 0.0)
		target_position = target_position.lerp(perfect_center, idle_transition_speed * delta)
		# 2. 目标缩放退回展示全貌的距离
		target_zoom = lerp(target_zoom, idle_zoom, idle_transition_speed * delta)
		# 3. 目标俯仰角抬起到完美的展示角度
		target_pitch = lerp(target_pitch, deg_to_rad(idle_pitch), idle_transition_speed * delta)
		# 4. 目标偏航角持续累加，实现永不停止的环绕旋转！
		target_yaw += idle_rotation_speed * delta

	# ==========================================
	# 底层物理插值计算 (完全不变，丝滑执行上面的目标)
	# ==========================================
	camera.position.z = lerp(camera.position.z, target_zoom, 10.0 * delta)
	camera.rotation = Vector3.ZERO 

	rotation.y = lerp_angle(rotation.y, target_yaw, 15.0 * delta)
	rotation.x = lerp_angle(rotation.x, target_pitch, 15.0 * delta)

	global_position = global_position.lerp(target_position, 15.0 * delta)
