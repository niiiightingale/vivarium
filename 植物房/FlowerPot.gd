class_name FlowerPot
extends Node3D

@onready var spawn_point = $PlantSpawnPoint

# 记录当前盆里种着的植物实体
var current_plant_entity: Node3D = null 

# 准备好我们之前写的实体预制体（你需要把你之前写的挂着 PlantEntity.gd 的那个场景保存为 .tscn 并拖到这里）
@export var plant_entity_scene: PackedScene 

# 接收 PlayerInput 递过来的种子
func receive_seed(seed_data: PlantItemResource) -> bool:
	# 1. 拒收判定：如果已经有植物了，不准种！
	if current_plant_entity != null:
		print("❌ 种不了！这个花盆里已经有植物了！")
		return false
		
	# 2. 拒收判定2：如果是微观植物（苔藓），只能种在小房间的特殊生态缸里！
	if seed_data.is_micro_plant:
		# 假设咱们这个是普通大花盆，可以写个判断拒绝
		pass # 具体看你当前是啥花盆，咱们先不管这个
		
	# 3. 奇迹发生：实例化植物实体！
	if plant_entity_scene:
		current_plant_entity = plant_entity_scene.instantiate()
		
		# 给这个新生命注入灵魂（玩家手里的那个 Resource）
		# 注意：因为你的 PlantEntity 脚本的 _ready 里写了自动 duplicate()，
		# 这里只要赋值 base_plant_resource 就行。
		current_plant_entity.base_plant_resource = seed_data
		
		# 把它添加为花盆的子节点
		add_child(current_plant_entity)
		
		# ✨ 完美吸附：把坐标设定为刚才预留的 Marker3D 的中心点！
		current_plant_entity.global_position = spawn_point.global_position
		
		# (可选) 播放一个种下的尘土特效和音效
		
		return true
		
	return false

# 让外部（比如浇水壶、剪刀、铲子）能够获取到盆里的植物实体
func get_plant_entity() -> Node3D:
	return current_plant_entity
