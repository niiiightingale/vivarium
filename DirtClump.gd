extends RigidBody3D

var is_melting = false
var soil_manager = null # 生成时，SoilManager 会把自己的引用传过来

func _physics_process(delta):
	# 如果已经在融化中，就不再重复检测
	if is_melting: return
	
	# 如果土块的移动速度极小（说明砸到地面/石头上停住了）
	if linear_velocity.length() < 0.1:
		melt_into_soil()

func melt_into_soil():
	is_melting = true
	
	# 稍微延迟 0.15 秒，给玩家一个“土块砸在地上停顿了一下”的厚重视觉反馈
	await get_tree().create_timer(0.02).timeout
	
	if soil_manager:
		# 通知管理器：以我当前的 3D 世界坐标为中心，隆起地形！
		# 这里的 0.4 是笔刷半径，0.02 是隆起高度，你可以自己调手感
		soil_manager.apply_soil_brush(global_position, 0.4, 0.02)
	
	# 瞬间删除自己 (土块模型消失，假装它变成了下面隆起的泥土)
	queue_free()
