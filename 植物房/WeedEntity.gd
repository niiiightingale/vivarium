class_name WeedEntity
extends Area3D

@export var reward_points: int = 20 # ✨ 拔草的收益直接配在杂草身上

func interact():
	# 1. 向上溯源：找到寄生的花盆，修正底层负面数据
	var pot_node = get_parent()
	if pot_node and pot_node is Pot:
		pot_node.current_weeds -= 1
		# 安全兜底，防止数值异常穿透为负数
		pot_node.current_weeds = max(0, pot_node.current_weeds) 
		print("➖ 成功拔除杂草！当前杂草数: ", pot_node.current_weeds, "/", Pot.MAX_WEEDS[pot_node.pot_tier])
	
	# 2. 横向通信：呼叫经济总管加钱
	var inv_manager = get_tree().get_first_node_in_group("inventory_manager")
	if inv_manager and inv_manager.has_method("add_points"):
		inv_manager.add_points(reward_points)
		
	# 3. 自我毁灭：从内存和画面中抹除
	queue_free()
