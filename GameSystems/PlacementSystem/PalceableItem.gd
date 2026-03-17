class_name PlaceableItem
extends Node3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var detect_area: Area3D = $DetectArea
# ✨【新增】获取你的物理实体节点（请确保子节点名字叫 StaticBody3D）
@onready var static_body: StaticBody3D = $StaticBody3D 

var error_material: StandardMaterial3D
var is_overlapping: bool = false
var is_preview: bool = true

# ✨ 新增：用于监测地形塌陷的数据
var soil_manager: Node3D = null
var original_soil_height: float = 0.0
var is_planted: bool = false

func _ready() -> void:
	if not is_preview:
		if static_body:
			static_body.collision_layer = 16 
		return 

	if static_body:
		static_body.collision_layer = 0 

	error_material = StandardMaterial3D.new()
	error_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	error_material.albedo_color = Color(1.0, 0.0, 0.0, 0.5) 
	error_material.no_depth_test = true 
	error_material.render_priority = 100
	
	mesh_instance.material_overlay = null

func _physics_process(delta: float) -> void:
	# 预览模式下的重叠检测（保持不变）
	if is_preview:
		var overlapping_bodies = detect_area.get_overlapping_bodies()
		if overlapping_bodies.size() > 0:
			if not is_overlapping:
				is_overlapping = true
				mesh_instance.material_overlay = error_material
		else:
			if is_overlapping:
				is_overlapping = false
				mesh_instance.material_overlay = null
		return

	# ✨ 新增：真实模式下的“失足监测”！
	if is_planted and soil_manager:
		# 实时查询脚下的地形高度
		var current_h = soil_manager.get_soil_height_at(global_position)
		
		# 容差判定：如果脚下的土被挖深了超过 0.15 米（根据你的模型大小微调）
		if current_h < original_soil_height - 0.15:
			pop_into_inventory()

func can_place() -> bool:
	return not is_overlapping

# ✨ 修改：接收 soil_manager 参数，记录初始高度
func set_as_real_object(mgr: Node3D) -> void:
	is_preview = false
	mesh_instance.material_overlay = null 
	detect_area.monitoring = false
	
	if static_body:
		static_body.collision_layer = 16
		
	# 记录出生数据开始监测
	soil_manager = mgr
	if soil_manager:
		original_soil_height = soil_manager.get_soil_height_at(global_position)
		is_planted = true

# ✨ 新增：被连根挖起时的表现演出！
func pop_into_inventory() -> void:
	is_planted = false # 停止监测，防止重复触发
	
	# TODO: 在这里调用你的 InventoryManager.add_item("rock_01")
	print("🎈 地形被破坏，物品已收回背包！")
	
	# ==========================================
	# 演出效果：Q弹缩小并消失 (Tween 动画)
	# ==========================================
	var tween = create_tween().set_parallel(true)
	# ✨ 修复：TRANS_QUAD 决定曲线是二次方，EASE_OUT 决定它是减速弹出
	tween.tween_property(self, "position:y", position.y + 0.5, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 这个是对的：TRANS_BACK 有个回弹效果，EASE_IN 是加速缩小
	tween.tween_property(self, "scale", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	# 动画结束后自动销毁节点
	tween.chain().tween_callback(queue_free)
