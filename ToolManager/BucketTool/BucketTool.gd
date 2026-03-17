class_name BucketTool
extends Node3D

# ==========================================
# 外部依赖
# ==========================================
@export var player_input: PlayerInput 
@export var soil_manager: Node3D # 【新增】必须在检查器中把 SoilSystem/SoilManager 拖给它！

@export var hover_height: float = 1.5 
@export var y_rotation_offset: float = -45.0 

# ==========================================
# 倾倒生成参数 【从 SoilManager 搬家过来】
# ==========================================
@export var clumps_per_second: float = 30.0
@export var drop_radius: float = 0.5
var spawn_timer: float = 0.0

# ==========================================
# 内部状态与视觉组件
# ==========================================
var is_pouring: bool = false # 【关键】：现在由 ToolManager 统一修改这个状态

@onready var placement_cursor = $PlacementCursor
@onready var dirt_particles = $DirtParticles
@onready var bucket_pivot = $DirtParticles/BucketPivot
@onready var bucket_model = $DirtParticles/BucketPivot/BucketModel

var target_tilt: float = 0.0

func _process(delta: float) -> void:
	if global_transform.basis.get_scale().length_squared() < 0.001:
		return
	if not player_input:
		return
		
	# 1. 位置追踪：雷达说去哪，我就去哪
	if player_input.is_valid_location:
		var safe_pos = player_input.target_position
		
		placement_cursor.visible = true
		placement_cursor.global_position = safe_pos
		var dynamic_y = safe_pos.y + hover_height
		dirt_particles.global_position = Vector3(safe_pos.x, dynamic_y, safe_pos.z)
		
		# 2. 状态表现与逻辑执行：依赖 is_pouring
		if is_pouring:
			# --- A. 视觉表现：正在倒土 ---
			dirt_particles.emitting = true 
			target_tilt = 45.0
			var shake_pulse = sin(Time.get_ticks_msec() * 0.05) * 0.08
			placement_cursor.scale = Vector3(1.0 + shake_pulse, 0.2, 1.0 + shake_pulse)
			placement_cursor.rotate_y(10.0 * delta) 
			
			# --- B. 核心逻辑：自己算数学题，生成掉落点 ---
			if soil_manager:
				spawn_timer += delta
				var spawn_interval = 1.0 / clumps_per_second 
				
				while spawn_timer >= spawn_interval:
					# 算出一个下落时间 (根据悬浮高度)
					var fall_time = sqrt(max(0.0, 2.0 * hover_height / 9.8))
					
					# 计算圆形范围内的随机偏移
					var random_angle = randf() * TAU 
					var random_radius = sqrt(randf()) * drop_radius
					
					var final_x = safe_pos.x + cos(random_angle) * random_radius
					var final_z = safe_pos.z + sin(random_angle) * random_radius
					
					var target_pos = Vector3(final_x, safe_pos.y, final_z)
					
					# 【向下发号施令】：把算好的坐标和时间交给泥土系统！
					# （注意：我们下一步要在 SoilManager 里写这个函数）
					soil_manager.add_pending_drop(target_pos, drop_radius, fall_time)
					
					spawn_timer -= spawn_interval
		else:
			# 悬停待机
			_reset_pouring_state(delta)
	else:
		# 3. 越界关闭
		placement_cursor.visible = false
		_reset_pouring_state(delta)

	# 4. 统一执行小桶的物理平滑倾斜
	if bucket_pivot:
		if player_input.camera:
			bucket_pivot.global_rotation.y = player_input.camera.global_rotation.y + deg_to_rad(y_rotation_offset)
			
		bucket_model.rotation_degrees.x = lerp(bucket_model.rotation_degrees.x, target_tilt, 12.0 * delta)

# 抽离出一个重置函数，保持代码整洁
func _reset_pouring_state(delta: float):
	dirt_particles.emitting = false 
	target_tilt = 0.0
	spawn_timer = 0.0 # 玩家松手，立刻打断生成计时器
	
	if placement_cursor.visible:
		placement_cursor.scale = placement_cursor.scale.lerp(Vector3(1.0, 0.2, 1.0), 15.0 * delta)
		placement_cursor.rotate_y(1.0 * delta)
