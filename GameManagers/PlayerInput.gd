class_name PlayerInput
extends Node

# ==========================================
# 🖱️ 玩家按键状态 (触觉)
# ==========================================
var is_interacting: bool = false
var is_just_interacted: bool = false

# ==========================================
# 🟤 泥土层探测数据 (Layer 18)
# ==========================================
var target_position: Vector3 = Vector3.ZERO
var is_valid_location: bool = false
var hit_collider: Node3D = null

# ==========================================
# 🪴 花盆层探测数据 (Layer 6)
# ==========================================
var is_pointing_at_pot: bool = false
var hovered_pot_collider: Node3D = null

@onready var camera = get_viewport().get_camera_3d()

func _process(_delta: float) -> void:
	if not camera:
		return
		
	# 1. 更新按键状态
	is_interacting = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	# 假设你在项目设置里配置了 "left_click"
	is_just_interacted = Input.is_action_just_pressed("left_click") 
	
	# 2. 获取射线基础数据
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	var space_state = camera.get_world_3d().direct_space_state
	
	# 3. 分别呼叫两个检测方法
	_check_dirt_layer(ray_origin, ray_dir, space_state)
	_check_pot_layer(ray_origin, ray_dir, space_state)


# ==========================================
# 📡 射线雷达方法
# ==========================================
func _check_dirt_layer(ray_origin: Vector3, ray_dir: Vector3, space_state: PhysicsDirectSpaceState3D):
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 100.0)
	query.collision_mask = 131072 # Layer 18 的值 (1 << 17)
	var result = space_state.intersect_ray(query)
	
	if result:
		target_position = result.position
		hit_collider = result.collider
		is_valid_location = true
	else:
		is_valid_location = false
		hit_collider = null


func _check_pot_layer(ray_origin: Vector3, ray_dir: Vector3, space_state: PhysicsDirectSpaceState3D):
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 100.0)
	# ✨ 核心魔法：只检测 Layer 6！
	# 在 Godot 中，Layer 6 的十进制值是 32 (即 2 的 5 次方：1 << 5)
	query.collision_mask = 32 
	var result = space_state.intersect_ray(query)
	
	if result:
		is_pointing_at_pot = true
		hovered_pot_collider = result.collider
	else:
		is_pointing_at_pot = false
		hovered_pot_collider = null
