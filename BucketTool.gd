class_name BucketTool
extends Node3D

# ==========================================
# 外部依赖
# ==========================================
@export var player_input: PlayerInput # 必须在检查器中把 PlayerInput 节点拖给它！
# 把原来的 drop_height 换成悬浮高度
@export var hover_height: float = 1.5 # 小桶永远悬浮在泥土上方 1.5 米处
@export var y_rotation_offset: float = -45.0 # 默认向侧边偏转 45 度，你可以在检查器里随时调

# ==========================================
# 内部视觉组件
# ==========================================
@onready var placement_cursor = $PlacementCursor
@onready var dirt_particles = $DirtParticles
@onready var bucket_pivot = $DirtParticles/BucketPivot
@onready var bucket_model = $DirtParticles/BucketPivot/BucketModel

var target_tilt: float = 0.0

func _process(delta: float) -> void:
	# 【关键修复】：如果当前缩放太小（正在执行弹出动画），直接跳过旋转计算，防止报错
	if global_transform.basis.get_scale().length_squared() < 0.001:
		return
	if not player_input:
		return
		
	# 1. 位置追踪：雷达说去哪，我就去哪
	if player_input.is_valid_location:
		var safe_pos = player_input.target_position
		
		placement_cursor.visible = true
		placement_cursor.global_position = safe_pos
		# 【关键修改】：不再使用固定高度，而是“泥土真实高度 + 悬浮距离”
		var dynamic_y = safe_pos.y + hover_height
		dirt_particles.global_position = Vector3(safe_pos.x, dynamic_y, safe_pos.z)
		
		# 2. 状态表现：玩家按下了吗？
		if player_input.is_interacting:
			# 【正在倒土】
			dirt_particles.emitting = true 
			target_tilt = 45.0
			
			var shake_pulse = sin(Time.get_ticks_msec() * 0.05) * 0.08
			placement_cursor.scale = Vector3(1.0 + shake_pulse, 0.2, 1.0 + shake_pulse)
			placement_cursor.rotate_y(10.0 * delta) 
		else:
			# 【悬停待机】
			dirt_particles.emitting = false 
			target_tilt = 0.0
			
			placement_cursor.scale = placement_cursor.scale.lerp(Vector3(1.0, 0.2, 1.0), 15.0 * delta)
			placement_cursor.rotate_y(1.0 * delta)
	else:
		# 3. 越界关闭
		placement_cursor.visible = false
		dirt_particles.emitting = false 
		target_tilt = 0.0

	# 4. 统一执行小桶的物理平滑倾斜
	if bucket_pivot:
		# 1. 动态同步摄像机的 Y 轴旋转
		if player_input.camera:
			bucket_pivot.global_rotation.y = player_input.camera.global_rotation.y + deg_to_rad(y_rotation_offset)
			
			
		# 2. 独立处理 X 轴的物理平滑倾倒动画
		bucket_model.rotation_degrees.x = lerp(bucket_model.rotation_degrees.x, target_tilt, 12.0 * delta)
