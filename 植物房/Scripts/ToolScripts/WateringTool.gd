class_name WateringTool
extends Node3D

@export var player_input: PlayerInput

func _ready():
	deactivate() # 默认关闭

func activate() -> void:
	set_process(true)
	# ✨ 以后可以在这里把鼠标变成一个小水壶图标！

func deactivate() -> void:
	set_process(false)

func _process(_delta: float) -> void:
	if not player_input: return
	
	# 只有激活状态下，点左键并且指着花盆，才浇水
	if player_input.is_just_interacted and player_input.is_pointing_at_pot:
		var pot_collider = player_input.hovered_pot_collider
		var pot_node = pot_collider.get_parent() 
		
		if pot_node and pot_node.has_method("get_plant_entity"):
			var plant = pot_node.get_plant_entity()
			if plant:
				plant.water_plant(50.0)
				print("🚰 [水壶工具] 精准滴灌！")
			else:
				print("❌ [水壶工具] 盆是空的...")
