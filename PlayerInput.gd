class_name PlayerInput
extends Node

# ==========================================
# 外部依赖
# ==========================================
# (保留变量是为了兼容旧代码，但实际上我们不再依赖单独的 soil_body 了)
@export var soil_body: Node3D 

# ==========================================
# 向外暴露的“雷达数据”（供其他系统只读）
# ==========================================
var target_position: Vector3 = Vector3.ZERO
var is_valid_location: bool = false
var is_interacting: bool = false
var hit_collider: Node3D = null

@onready var camera = get_viewport().get_camera_3d()

func _process(_delta: float) -> void:
	if not camera:
		return
		
	# 1. 更新交互状态
	is_interacting = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	
	# 2. 获取射线基础数据
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	var space_state = camera.get_world_3d().direct_space_state
	
	# 3. 纯物理射线探测 (通吃缸内与所有培育箱！)
	# 只要碰撞体在 Layer 18 (泥土层)，指哪打哪！
	var main_query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 100.0)
	main_query.collision_mask = 18 
	var main_result = space_state.intersect_ray(main_query)
	
	if main_result:
		target_position = main_result.position
		hit_collider = main_result.collider # ✨ 把被鼠标射中的实体暴露给外部！
		is_valid_location = true
	else:
		# 没有指在任何泥土上，直接失效
		is_valid_location = false
