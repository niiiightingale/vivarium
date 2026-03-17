class_name SeedTool
extends Node3D

@export var player_input: PlayerInput
var current_seed: PlantItemResource = null

func _ready():
	deactivate()

func activate() -> void:
	set_process(true)
	# ✨ 以后可以在这里在鼠标位置生成一个半透明的植物预览模型！(就像你的 PlacementTool 一样)

func deactivate() -> void:
	set_process(false)
	current_seed = null # 断电时清空手里的种子

# UI 会调用这个方法把具体的图鉴塞进来
func load_seed(seed_res: PlantItemResource):
	current_seed = seed_res

func _process(_delta: float) -> void:
	if not player_input or not current_seed: return
	
	if player_input.is_just_interacted and player_input.is_pointing_at_pot:
		var pot_collider = player_input.hovered_pot_collider
		var pot_node = pot_collider.get_parent() 
		
		if pot_node and pot_node.has_method("receive_seed"):
			var success = pot_node.receive_seed(current_seed)
			if success:
				print("🎉 [播种工具] 种植成功！")
				# 如果种完想自动切回空手，可以发信号给 Manager
