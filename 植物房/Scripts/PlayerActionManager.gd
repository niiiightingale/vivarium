class_name PlayerActionManager
extends Node

# 这个大脑需要知道玩家手里拿了什么
@export var holding_seed: PlantItemResource = null 

# 假设你的场景里有一个叫 PlayerInput 的节点
@export var player_input: PlayerInput 

func _process(_delta: float):
	if not player_input:
		return
		
	# 🧠 大脑的思考逻辑：
	# 如果玩家点了一下左键 + 鼠标正指着花盆 + 手里确实拿着种子
	if player_input.is_just_interacted and player_input.is_pointing_at_pot and holding_seed != null:
		
		# 从 input 里拿到那个花盆的碰撞体
		var pot_collider = player_input.hovered_pot_collider
		
		# 顺藤摸瓜找到花盆的根节点
		var pot_node = pot_collider.get_parent() 
		
		# 呼叫咱们之前写好的花盆受孕方法
		if pot_node and pot_node.has_method("receive_seed"):
			var success = pot_node.receive_seed(holding_seed)
			
			if success:
				print("🎉 行动管理器：种植成功！扣除种子！")
				holding_seed = null # 种完了，手里空了
