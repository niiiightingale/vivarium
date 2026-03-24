class_name PlantEntity
extends Node3D

@export var base_plant_resource: PlantItemResource 
var plant_data: PlantItemResource 

var visual_container: Node3D 
var current_model_instance: Node3D 

func _ready():
	if not base_plant_resource:
		return
	
	plant_data = base_plant_resource.duplicate()
	
	visual_container = Node3D.new()
	visual_container.name = "VisualContainer"
	add_child(visual_container)
	
	_update_visual_model()
	add_to_group("plants")
	
	# ❌ 核心修正：绝对不要在这里监听 TimeManager！
	# 必须由父节点 (Pot) 通过 process_growth() 来驱动它

func _check_health_state():
	if plant_data.current_health == plant_data.HealthState.DROWNED:
		return
		
	if plant_data.current_water >= plant_data.drown_water_threshold:
		plant_data.current_health = plant_data.HealthState.DROWNED
		print("🌊 淹死判定触发！[", plant_data.display_name, "] 烂根阵亡！")
		if current_model_instance:
			create_tween().tween_property(current_model_instance, "scale", Vector3(1.1, 0.6, 1.1), 0.5)
			
	elif plant_data.current_water < plant_data.healthy_water_threshold:
		plant_data.current_health = plant_data.HealthState.THIRSTY
		print("🥀 缺水判定触发！[", plant_data.display_name, "] 干瘪停滞。")
		
	else:
		if plant_data.current_health == plant_data.HealthState.THIRSTY:
			print("✨ 恢复健康！[", plant_data.display_name, "] 水分达标。")
		plant_data.current_health = plant_data.HealthState.HEALTHY

# ==========================================
# ⏳ 每日结算系统 (由 Pot 主动调用)
# ==========================================
# ✨ 核心魔法：接收杂草惩罚 (env_water_penalty) 和 当前花盆等级 (current_pot_tier)
func process_growth(days: int, env_water_penalty: float, current_pot_tier: int):
	if plant_data.current_health == plant_data.HealthState.DROWNED:
		return
		
	# 1. 综合扣除水分 (自身代谢 + 环境杂草抢夺)
	var base_water_lost = plant_data.daily_water_consumption * days
	var total_water_lost = base_water_lost + env_water_penalty
	
	plant_data.current_water = max(plant_data.current_water - total_water_lost, 0.0)
	print("💧 [", plant_data.display_name, "] 自身消耗 ", base_water_lost, "，杂草抢夺 ", env_water_penalty, "。剩余水分：", plant_data.current_water)
	
	_check_health_state()
	
	# 2. 状态合规，执行生长逻辑
	if plant_data.current_health == plant_data.HealthState.HEALTHY:
		if plant_data.current_stage < plant_data.max_stage:
			
			# ✨ 核心改动：容量预判 (Root Bound Check)
			var next_stage_index = plant_data.current_stage # stage 1 升 stage 2，对应的 index 是 1
			var required_tier = 0
			
			# 安全读取所需等级
			if next_stage_index < plant_data.required_pot_tiers.size():
				required_tier = plant_data.required_pot_tiers[next_stage_index]
				
			# 爆盆拦截
			if current_pot_tier < required_tier:
				print("⚠️ 爆盆警告！[", plant_data.display_name, "] 尝试生长，但当前花盆等级 (", current_pot_tier, ") 无法满足下一阶段需求 (", required_tier, ")！")
				plant_data.growth_progress = 0.99 # 锁死在即将升级的边缘
				return # 阻断后续升级逻辑
				
			# 正常生长
			var growth_gain = plant_data.daily_growth_rate * days
			plant_data.growth_progress += growth_gain
			
			if plant_data.growth_progress >= 1.0:
				_level_up()
	else:
		print("⚠️ 因健康状态不佳( ", plant_data.current_health, " )，今日停止生长。")

func _level_up():
	plant_data.growth_progress -= 1.0 
	plant_data.current_stage += 1
	print("🌟 升级！[", plant_data.display_name, "] 达到阶段 ", plant_data.current_stage)
	
	# 经济产出逻辑
	var inv_manager = get_tree().get_first_node_in_group("inventory_manager")
	if inv_manager and inv_manager.has_method("add_points"):
		var reward = 50 * plant_data.current_stage # 动态奖励：等级越高给的越多
		inv_manager.add_points(reward)
		
	_update_visual_model()

func _update_visual_model():
	if current_model_instance:
		current_model_instance.queue_free()
		current_model_instance = null
		
	var model_scene: PackedScene = plant_data.get_current_model_scene()
	if not model_scene:
		return
		
	current_model_instance = model_scene.instantiate() as Node3D
	visual_container.add_child(current_model_instance)
	
	current_model_instance.scale = Vector3.ZERO
	var tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(current_model_instance, "scale", Vector3.ONE, 1.2)

func water_plant(amount: float = 50.0):
	if plant_data.current_health == plant_data.HealthState.DROWNED:
		return
	plant_data.current_water += amount
	_check_health_state()
