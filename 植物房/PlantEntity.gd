class_name PlantEntity
extends Node3D

# ==========================================
# 📦 数据源
# ==========================================
# 在检查器里把配置好的植物图鉴（比如 haworthia.tres）拖到这里
@export var base_plant_resource: PlantItemResource 

# 这是这盆植物独一无二的私人账本（复制体）
var plant_data: PlantItemResource 

# ==========================================
# 🪴 节点引用
# ==========================================
# 我们需要一个空节点作为“展台”，用来装载/替换不同阶段的模型
var visual_container: Node3D 
var current_model_instance: Node3D # 当前正在显示的 3D 模型

func _ready():
	if not base_plant_resource:
		return
	
	plant_data = base_plant_resource.duplicate()
	
	visual_container = Node3D.new()
	visual_container.name = "VisualContainer"
	add_child(visual_container)
	
	_update_visual_model()
	# ✨ 方便 UI 找到所有的植物！给它贴个标签
	add_to_group("plants")
	# ✨ 核心魔法：植物“竖起耳朵”，监听 TimeManager 的喇叭
	TimeManager.day_passed.connect(_on_day_passed)
	
func _check_health_state():
	# 1. 如果已经淹死了，神仙难救，直接跳过判定
	if plant_data.current_health == plant_data.HealthState.DROWNED:
		return
		
	# 2. 判定是否淹死 (超过最高致死线)
	if plant_data.current_water >= plant_data.drown_water_threshold:
		plant_data.current_health = plant_data.HealthState.DROWNED
		print("🌊 糟了！水漫金山！[", plant_data.display_name, "] 被淹死了！")
		
		# 表现淹死的视觉效果 (稍微压扁一点)
		if current_model_instance:
			create_tween().tween_property(current_model_instance, "scale", Vector3(1.1, 0.6, 1.1), 0.5)
			
	# 3. 判定是否缺水 (低于健康下限)
	elif plant_data.current_water < plant_data.healthy_water_threshold:
		plant_data.current_health = plant_data.HealthState.THIRSTY
		print("🥀 [", plant_data.display_name, "] 缺水了，叶子都干瘪了...")
		
	# 4. 如果都不满足，说明在安全区间内！恢复健康！
	else:
		if plant_data.current_health == plant_data.HealthState.THIRSTY:
			print("✨ 喝饱了水！[", plant_data.display_name, "] 恢复了健康！")
		plant_data.current_health = plant_data.HealthState.HEALTHY
# ==========================================
# ⏳ 每日结算系统
# ==========================================
func _on_day_passed(days: int):
	# 如果植物已经淹死，直接停止一切生长和代谢！
	if plant_data.current_health == plant_data.HealthState.DROWNED:
		print("🪦 [", plant_data.display_name, "] 已阵亡，停止生长。")
		return
		
	# 1. 扣除水分 (注意变量名改成了 current_water)
	var water_lost = plant_data.daily_water_consumption * days
	plant_data.current_water -= water_lost
	
	# 水分最低只能掉到 0，不能是负数 (去掉了100的上限限制，因为上限交给了淹死线)
	plant_data.current_water = max(plant_data.current_water, 0.0)
	
	print("💧 ", plant_data.display_name, " 消耗了 ", water_lost, " 水分。剩余：", plant_data.current_water)
	
	# ✨ 核心魔法：每天掉完水，立刻检查是否触发了干瘪(缺水)状态
	_check_health_state()
	
	# 2. 只有在绝对健康的状态下，才允许增加生长进度
	if plant_data.current_health == plant_data.HealthState.HEALTHY:
		if plant_data.current_stage < plant_data.max_stage:
			var growth_gain = plant_data.daily_growth_rate * days
			plant_data.growth_progress += growth_gain
			
			print("🌱 正在生长... 当前阶段进度: ", plant_data.growth_progress * 100, "%")
			
			# 3. 惊喜时刻：如果进度满了，升级！
			if plant_data.growth_progress >= 1.0:
				plant_data.growth_progress -= 1.0 # 扣除 1.0，保留溢出的一点点进度
				plant_data.current_stage += 1
				print("🌟 升级啦！", plant_data.display_name, " 成长到了阶段 ", plant_data.current_stage)
				
				# 刷新 3D 模型
				_update_visual_model()
	else:
		# 如果因为掉水触发了 THIRSTY 状态，就会走到这里
		print("⚠️ 植物太渴了(状态: ", plant_data.current_health, ")，今天停止生长。")
			
func _update_visual_model():
	# 1. 如果展台上已经有旧模型了，先把它无情销毁
	if current_model_instance:
		current_model_instance.queue_free()
		current_model_instance = null
		
	# 2. 从字典里要出当前阶段的 PackedScene（场景预制体）
	var model_scene: PackedScene = plant_data.get_current_model_scene()
	if not model_scene:
		return
		
	# 3. 实例化这个场景，并放到展台上
	current_model_instance = model_scene.instantiate() as Node3D
	visual_container.add_child(current_model_instance)
	
	# ✨ 核心魔法 3：出生/升级时的 Q 弹动画 (Juiciness)
	# 让模型从 0 瞬间缩放到原来的大小，带一点果冻回弹效果
	current_model_instance.scale = Vector3.ZERO
	var tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(current_model_instance, "scale", Vector3.ONE, 1.2)


# ==========================================
# 🎮 游戏玩法接口 (供外部调用)
# ==========================================

# 浇水函数（以后让玩家拿水壶点击时调用）
# ==========================================
func water_plant(amount: float = 50.0):
	if plant_data.current_health == plant_data.HealthState.DROWNED:
		print("💀 [", plant_data.display_name, "] 已经烂根，浇水没用了...")
		return

	# 增加 current 水分
	plant_data.current_water += amount
	print("💦 浇水 +", amount, "。当前水分: ", plant_data.current_water)
	
	# 每次浇完水，立刻检查死活！
	_check_health_state()
