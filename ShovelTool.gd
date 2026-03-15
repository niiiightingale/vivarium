class_name ShovelTool
extends Node3D

@export var soil_manager: SoilManager
@export var player_input: PlayerInput

@export var brush_texture: Texture2D 
var _brush_image: Image

@export var max_capacity: float = 5.0 
@export var current_load: float = 0.0 

# ✨【新增】：定义每次点击鼠标左/右键，最多能交互多少体积的泥土！
@export var dig_volume_per_click: float = 1.5 
@export var fill_volume_per_click: float = 1.5 

@export var brush_radius: float = 0.6
@export var brush_strength: float = 0.4

func _ready() -> void:
	deactivate()
	if brush_texture:
		_brush_image = brush_texture.get_image()
		if _brush_image.is_compressed():
			_brush_image.decompress()

func activate() -> void:
	visible = true
	set_process(true)
	set_process_unhandled_input(true)
	print("🪓 铁铲激活！")

func deactivate() -> void:
	visible = false
	set_process(false)
	set_process_unhandled_input(false)

func _process(_delta: float) -> void:
	if player_input and player_input.is_valid_location:
		global_position = Vector3(player_input.target_position.x, player_input.target_position.y + 0.5, player_input.target_position.z)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		if not player_input or not player_input.is_valid_location: return
			
		var target_pos = player_input.target_position
		var random_rotation = randf() * PI * 2.0 
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dig(target_pos, random_rotation)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_fill(target_pos, random_rotation)

# ==========================================
# 核心挖填逻辑升级
# ==========================================
func _dig(target_pos: Vector3, random_rot: float) -> void:
	var available_space = max_capacity - current_load
	if available_space <= 0.001: 
		print("🚨 铲子已满！不能再挖了！")
		return
		
	# ✨【核心魔法】：这一铲子想要挖出的土，绝不能超过“单次挖掘上限”，也不能超过“铲子剩余空间”
	var volume_to_dig = min(available_space, dig_volume_per_click)
		
	# 将计算好的 volume_to_dig 传给 SoilManager
	var volume_dug = soil_manager.apply_soil_brush(target_pos, brush_radius, brush_strength, false, volume_to_dig, _brush_image, random_rot)
	current_load += volume_dug
	
	print("⏬ 挖土: +", snapped(volume_dug, 0.01), " | 当前装载: ", snapped(current_load, 0.01), "/", max_capacity)

func _fill(target_pos: Vector3, random_rot: float) -> void:
	if current_load <= 0.001: 
		print("🪹 铲子空了！")
		return
		
	# ✨【核心魔法】：这一下想要倒出的土，绝不能超过“单次倒土上限”，也不能超过“当前铲子里的存货”
	var volume_to_drop = min(current_load, fill_volume_per_click)
		
	var volume_dropped = soil_manager.apply_soil_brush(target_pos, brush_radius, brush_strength, true, volume_to_drop, _brush_image, random_rot)
	current_load -= volume_dropped
	
	print("⏫ 填土: -", snapped(volume_dropped, 0.01), " | 当前装载: ", snapped(current_load, 0.01), "/", max_capacity)
