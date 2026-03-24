class_name PlantItemResource
extends ItemResource

# ==========================================
# 🏷️ 基础身份信息 (Identity)
# ==========================================
@export_group("Identity")
@export var item_id: String = "plant_unknown" 
@export var is_micro_plant: bool = false 

enum MutationType { NONE, VARIEGATED_WHITE, VARIEGATED_PINK, GOLDEN }
@export var mutation: MutationType = MutationType.NONE

# ==========================================
# 🌳 多阶段模型库 (Stage Models)
# ==========================================
# 🌱 生长时间轴 (Growth)
# ==========================================
@export_group("Growth")
@export var current_stage: int = 1 
@export var max_stage: int = 3 

@export_range(0.0, 1.0) var growth_progress: float = 0.0 
# ==========================================
@export_group("Visuals")
# ✨ 核心升级：把单一模型变成了一个数组！
# 在检查器里，索引 0 放阶段 1 的模型（种子），索引 1 放阶段 2 的模型（幼苗）...
@export var stage_models: Array[PackedScene] = []
# 数组索引 0 对应 stage 1，索引 1 对应 stage 2...
# 填入 Pot.PotTier 的枚举值 (0:多肉, 1:小盆, 2:中盆, 3:大盆)
@export var required_pot_tiers: Array[int] = [0, 0, 0]
# ⏱️ 新陈代谢与生长速率 (Metabolism & Rates)
# ==========================================
@export_group("Metabolism")

# 1. 消耗速度：每天（游戏时间）扣除多少点数值？
@export_range(0.0, 50.0) var daily_water_consumption: float = 10.0 # 每天掉多少水
@export_range(0.0, 50.0) var daily_nutrition_consumption: float = 5.0 # 每天掉多少营养

@export_range(0.0, 100.0) var hungry_threshold: float = 20.0 # 营养低于 20，停止生长

# 3. 生长速度：每天（在水分营养健康的情况下）增加多少生长进度？
# 比如填 0.2，就意味着 5 天（0.2 * 5 = 1.0）可以升一个阶段！
# 填 0.05，就意味着需要 20 天才能升一个阶段（适合大型长寿植物）。
@export_range(0.0, 1.0) var daily_growth_rate: float = 0.2
# ==========================================
# 💧 生存与状态 (Survival & Health)
# ==========================================
@export_group("Survival")
# ✨ 核心改动 1：加入了 DROWNED (淹死/烂根) 状态！
enum HealthState { HEALTHY, THIRSTY, DORMANT, DROWNED }
@export var current_health: HealthState = HealthState.HEALTHY

# 🌟 1. 动态状态（Current 参数）：随游戏进程实时变化的当前水分
@export var current_water: float = 80.0 

# 🌟 2. 固定参数（固定体质）：决定这盆植物好不好养的“生死线”
# 健康下限：低于这个值，植物进入缺水 (THIRSTY) 状态，停止生长
@export var healthy_water_threshold: float = 30.0 

# 淹死上限：达到或超过这个值，植物直接烂根淹死 (DROWNED)
@export var drown_water_threshold: float = 150.0


# ==========================================
# ✂️ 枝条修剪系统 (The Bone Cutting System)
# ==========================================
@export_group("Interaction")
@export var available_cuttings: int = 0 
@export var max_cuttings: int = 3 

# 记录完全体模型上可以剪断的骨骼名称
@export var cuttable_bones: Array[String] = []

# ==========================================
# 💌 情感与羁绊 (Lore & Social)
# ==========================================
@export_group("Lore")
@export var custom_notes: String = "" 
@export var planted_timestamp: int = 0 
@export var original_owner: String = "Player" 
@export_multiline var gift_message: String = "" 


# ==========================================
# 🛠️ 实用工具函数 (Helper Methods)
# ==========================================
# 只要调用这个函数，传入当前的 stage，它就会安全地返回对应的模型！
func get_current_model_scene() -> PackedScene:
	# 因为阶段是从 1 开始的 (1, 2, 3)，而数组索引是从 0 开始的 (0, 1, 2)
	# 所以我们要减去 1
	var index = current_stage - 1
	
	if index >= 0 and index < stage_models.size():
		return stage_models[index]
	else:
		push_error("🚨 找不到对应的阶段模型！请检查 stage_models 数组是否配置完整。")
		return null
