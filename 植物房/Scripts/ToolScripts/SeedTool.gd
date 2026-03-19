class_name SeedTool
extends Node3D

@export var player_input: PlayerInput
@export var inventory_manager: Node # ✨ 必须引入背包大脑，才能执行扣除

var current_seed: PlantItemResource = null
var current_seed_index: int = -1 # ✨ 新增：记住这颗种子在背包里的绝对物理索引

func _ready():
	deactivate()

func activate() -> void:
	set_process(true)

func deactivate() -> void:
	set_process(false)
	_clear_hand() # 断电时彻底清空手里的东西

# ✨ 核心变动：UI 调用此方法时，必须把 [物品引用] 和 [物理索引] 一起塞进来
func load_seed(seed_res: PlantItemResource, inventory_index: int):
	current_seed = seed_res
	current_seed_index = inventory_index

# 内部清理方法
func _clear_hand():
	current_seed = null
	current_seed_index = -1

func _process(_delta: float) -> void:
	if not player_input or not current_seed: return
	
	if player_input.is_just_interacted and player_input.is_pointing_at_pot:
		var pot_collider = player_input.hovered_pot_collider
		var pot_node = pot_collider.get_parent() 
		
		if pot_node and pot_node.has_method("receive_seed"):
			var success = pot_node.receive_seed(current_seed)
			
			if success:
				print("🎉 [播种工具] 种植成功！准备销毁背包数据...")
				
				# ✨ 核心闭环：真正从背包中抹除这颗种子！
				if inventory_manager and current_seed_index != -1:
					inventory_manager.remove_item_at_index(current_seed_index)
				
				# 种完之后必须清空双手，因为这是一次性消耗品
				_clear_hand()
