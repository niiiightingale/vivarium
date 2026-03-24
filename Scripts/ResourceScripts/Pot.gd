class_name Pot
extends Node3D

enum PotTier { SUCCULENT, SMALL, MEDIUM, LARGE }
@export var pot_tier: PotTier = PotTier.SMALL

const MAX_WEEDS: Dictionary = {
	PotTier.SUCCULENT: 0,
	PotTier.SMALL: 3,
	PotTier.MEDIUM: 5,
	PotTier.LARGE: 9
}

# 花盆只保留杂草相关的数据，删除了 current_water
@export var weed_water_penalty: float = 5.0 # 每棵杂草每天额外抢 5 点水
@export var daily_weed_chance: float = 0.3  

var current_weeds: int = 0
var current_plant_entity: Node3D = null

@onready var spawn_point = $PlantSpawnPoint
@export var plant_entity_scene: PackedScene 
@export var weed_prefab: PackedScene

# 散布半径配置
@export var spawn_inner_radius: float = 0.05
@export var spawn_outer_radius: float = 0.1
@export var soil_height_offset: float = 0.01


func _ready():
	# 建立时间监听，接管原属于植物的驱动源
	if TimeManager.has_signal("day_passed"):
		TimeManager.day_passed.connect(_on_day_passed)
	else:
		push_error("❌ Pot 无法找到 TimeManager 的 day_passed 信号！")
# ==========================================
# 🌱 核心种植逻辑 (加入阶段与盆的校验)
# ==========================================
func receive_seed(seed_data: PlantItemResource) -> bool:
	if current_plant_entity != null:
		print("❌ 种不了：花盆里已经有植物了！")
		return false
		
	# 拒收判定 1：微观植物专属拦截
	if seed_data.is_micro_plant:
		print("❌ 种不了：微观植物只能种在生态缸！")
		return false
		
	# ✨ 拒收判定 2：花盆太小，连种子都种不下！
	# 获取该种子阶段 1 (索引0) 所需的最小盆等级
	if seed_data.required_pot_tiers.size() > 0:
		var required_tier = seed_data.required_pot_tiers[0]
		if pot_tier != required_tier:
			print("❌ 种不了：这个植物不能种在此花盆里，需要种在 ", required_tier, " 的花盆！")
			return false
		
	if plant_entity_scene:
		current_plant_entity = plant_entity_scene.instantiate()
		current_plant_entity.base_plant_resource = seed_data
		add_child(current_plant_entity)
		current_plant_entity.global_position = spawn_point.global_position
		return true
		
	return false

# ==========================================
# ⏱️ 时间流逝 (降级为惩罚传递者)
# ==========================================
func _on_day_passed(days: int):
	# 1. 杂草生成判定
	var max_capacity = MAX_WEEDS[pot_tier]
	if current_weeds < max_capacity:
		if randf() <= daily_weed_chance:
			current_weeds += 1
			print("🌿 花盆长出了杂草！当前: ", current_weeds, "/", max_capacity)
			_spawn_weed_visual()
			
	# 2. 计算环境对植物的水分惩罚 (不再自己扣水)
	var env_water_penalty = current_weeds * weed_water_penalty * days
	
	# 3. ✨ 把惩罚和当前的花盆等级传给植物！让植物自己决定生与死！
	if current_plant_entity and current_plant_entity.has_method("process_growth"):
		current_plant_entity.process_growth(days, env_water_penalty, pot_tier)
# ==========================================
# 🎨 视觉散布算法 (Annular Scatter)
# ==========================================
func _spawn_weed_visual():
	if not weed_prefab: return
	
	var new_weed = weed_prefab.instantiate() as WeedEntity
	
	# 极角完全随机
	var random_theta = randf() * TAU 
	# 极径平方根加权，保证圆环面积内分布均匀，避免模型向花盆中心扎堆
	var r_inner_sq = pow(spawn_inner_radius, 2)
	var r_outer_sq = pow(spawn_outer_radius, 2)
	var random_r = sqrt(randf_range(r_inner_sq, r_outer_sq))
	
	var spawn_pos = Vector3(
		random_r * cos(random_theta),
		soil_height_offset,
		random_r * sin(random_theta)
	)
	
	add_child(new_weed)
	# 使用相对于花盆的局部坐标系
	new_weed.position = spawn_pos
	new_weed.rotation.y = randf() * TAU

# 🚪 外部交互网关 (给工具调用)
# ==========================================
func get_plant_entity() -> Node3D:
	return current_plant_entity
