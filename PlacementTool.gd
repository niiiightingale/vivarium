class_name PlacementTool
extends Node3D

# 在检查器里把你的 PlaceableBranch.tscn 拖给它
@export var item_scene: PackedScene 

var preview_node: PlaceableItem
var current_rotation_y: float = 0.0

func _ready():
	# 初始化时，偷偷生成一个“幻影”并设为自己的子节点
	if item_scene:
		preview_node = item_scene.instantiate() as PlaceableItem
		preview_node.is_preview = true
		add_child(preview_node)

# 让 ToolManager 每帧调用，更新幻影位置
func update_preview(target_pos: Vector3):
	if preview_node:
		preview_node.global_position = target_pos
		preview_node.rotation.y = current_rotation_y

# 滚轮旋转
func rotate_preview(direction: float):
	current_rotation_y += direction * deg_to_rad(15.0) # 每次滚轮转 15 度
	if preview_node:
		preview_node.rotation.y = current_rotation_y

# 尝试放置真正的物品
func attempt_place(target_pos: Vector3):
	if not preview_node or not preview_node.can_place():
		print("位置无效/冲突，无法放置！")
		return
		
	# 生成真实的物品
	var real_item = item_scene.instantiate() as PlaceableItem
	real_item.is_preview = false
	
	# 把它塞进主场景里 (建议以后在主场景专门建个 "PropsRoot" 节点用来放这些道具)
	get_tree().current_scene.add_child(real_item)
	
	# 同步位置和旋转，并彻底激活为真实物理对象
	real_item.global_position = target_pos
	real_item.rotation.y = current_rotation_y
	real_item.set_as_real_object()
	print("放置成功！")
