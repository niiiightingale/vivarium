class_name PlaceableItem
extends Node3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var detect_area: Area3D = $DetectArea
# ✨【新增】获取你的物理实体节点（请确保子节点名字叫 StaticBody3D）
@onready var static_body: StaticBody3D = $StaticBody3D 

var error_material: StandardMaterial3D
var is_overlapping: bool = false
var is_preview: bool = true

func _ready() -> void:
	if not is_preview:
		# ✨【新增】如果它一生下来就是真实的（比如你以后做场景存档加载）
		# 确保它的物理层是打开的 (16 代表 Layer 5)
		if static_body:
			static_body.collision_layer = 16 
		return 

	# ==========================================
	# ✨【新增】幽灵模式：剥夺物理实体！
	# 让 PlayerInput 的寻路射线彻底穿透它，防止“左脚踩右脚飞天”
	# ==========================================
	if static_body:
		static_body.collision_layer = 0 

	# 我们不再准备绿色材质了，而是只准备一个“红色警告膜”
	error_material = StandardMaterial3D.new()
	error_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	error_material.albedo_color = Color(1.0, 0.0, 0.0, 0.5) 
	
	# 保留这两行：防止红色警告膜被地形或其他东西错误遮挡
	error_material.no_depth_test = true 
	error_material.render_priority = 100
	
	# 🌟 初始状态（有效位置）：不盖任何膜，显示 100% 真实的枯木画质！
	mesh_instance.material_overlay = null

func _physics_process(_delta: float) -> void:
	if not is_preview:
		return

	var overlapping_bodies = detect_area.get_overlapping_bodies()
	if overlapping_bodies.size() > 0:
		if not is_overlapping:
			is_overlapping = true
			# 发生穿模冲突时：给真实的树枝套上一层红色警告膜！
			mesh_instance.material_overlay = error_material
	else:
		if is_overlapping:
			is_overlapping = false
			# 恢复正常时：撤销红膜，恢复完美画质
			mesh_instance.material_overlay = null

func can_place() -> bool:
	return not is_overlapping

func set_as_real_object() -> void:
	is_preview = false
	# 确保放下时绝对没有残留的红膜
	mesh_instance.material_overlay = null 
	detect_area.monitoring = false
	
	# 以前你改的是 detect_area 的层，现在不用管它了
	# detect_area.collision_layer = 8
	# detect_area.collision_mask = 0
	
	# ==========================================
	# ✨【新增】赋予实体！
	# 玩家点击放置后，让它正式加入物理世界 (Layer 5)
	# 这样下一次放东西时，寻路射线就能打中它的头顶，实现堆叠了！
	# ==========================================
	if static_body:
		static_body.collision_layer = 16
