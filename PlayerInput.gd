class_name PlayerInput
extends Node

# ==========================================
# 外部依赖 (在检查器中赋值)
# ==========================================
@export var soil_body: Node3D # 【必须赋值】用于获取泥土的基础高度
@export var valid_bounds: float = 2.4
@export var drop_height: float = 4.0
@export var buffer_zone: float = 1.5 # 缸外允许吸附的缓冲区大小

# ==========================================
# 向外暴露的“雷达数据”（供其他系统只读）
# ==========================================
var target_position: Vector3 = Vector3.ZERO
var is_valid_location: bool = false
var is_interacting: bool = false

@onready var camera = get_viewport().get_camera_3d()

func _process(_delta: float) -> void:
	if not camera or not soil_body:
		return
		
	# 1. 更新交互状态
	is_interacting = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	
	# 2. 获取射线基础数据
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	var space_state = camera.get_world_3d().direct_space_state
	
	var target_x: float = 0.0
	var target_z: float = 0.0
	var hit_success: bool = false
	
	# 3. 物理射线探测 (缸内)
	var main_query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 100.0)
	main_query.collision_mask = 18 # 只测泥土层
	var main_result = space_state.intersect_ray(main_query)
	
	if main_result:
		target_x = main_result.position.x
		target_z = main_result.position.z
		hit_success = true
	else:
		# 4. 数学射线透视与吸附 (缸外)
		var test_plane = Plane(Vector3.UP, drop_height)
		var test_point = test_plane.intersects_ray(ray_origin, ray_dir)
		var max_range = valid_bounds + buffer_zone 
		
		if test_point != null and (abs(test_point.x) > max_range or abs(test_point.z) > max_range):
			hit_success = false # 甩出太远，直接关闭倒土！
		elif test_point != null:
			var tank_box = AABB(
				Vector3(-valid_bounds, 0.0, -valid_bounds), 
				Vector3(valid_bounds * 2.0, drop_height, valid_bounds * 2.0)
			)
			var entry_pt = tank_box.intersects_ray(ray_origin, ray_dir)
			
			if entry_pt != null:
				var far_origin = ray_origin + ray_dir * 100.0
				var exit_pt = tank_box.intersects_ray(far_origin, -ray_dir)
				
				if exit_pt != null:
					var query_near = PhysicsRayQueryParameters3D.create(
						Vector3(entry_pt.x, drop_height + 5.0, entry_pt.z),
						Vector3(entry_pt.x, -10.0, entry_pt.z)
					)
					query_near.collision_mask = 18
					var result_near = space_state.intersect_ray(query_near)
					
					var soil_h_near = soil_body.global_position.y
					if result_near:
						soil_h_near = result_near.position.y
						
					if entry_pt.y <= soil_h_near + 0.05: 
						target_x = entry_pt.x
						target_z = entry_pt.z
					else:
						target_x = exit_pt.x
						target_z = exit_pt.z
						
					hit_success = true
					
	# 5. 整合最终输出坐标，更新雷达数据
	is_valid_location = hit_success
	
	if hit_success:
		var safe_x = clamp(target_x, -valid_bounds, valid_bounds)
		var safe_z = clamp(target_z, -valid_bounds, valid_bounds)
		
		var query_origin = Vector3(safe_x, drop_height + 5.0, safe_z) 
		var height_query = PhysicsRayQueryParameters3D.create(query_origin, query_origin + Vector3.DOWN * 20.0)
		height_query.collision_mask = 18
		
		var height_result = space_state.intersect_ray(height_query)
		var surface_y = soil_body.global_position.y
		if height_result:
			surface_y = height_result.position.y
			
		target_position = Vector3(safe_x, surface_y, safe_z)
