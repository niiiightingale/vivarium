class_name RoomUI
extends CanvasLayer

# 核心依赖
@export var tool_manager: RoomToolManager
# ✨ 新增依赖：直接指向你的动态背包 UI
@export var inventory_ui: InventoryUI 

# 节点引用 (旧的 seed_sub_menu 和 seed_resources 已被彻底剔除)
@onready var main_toolbar = $MarginContainer/VBoxContainer/MainToolbar
@onready var points_label =	$PointsLabel

var current_active_index: int = -1

func _ready():
	var tool_index = 0
	for child in main_toolbar.get_children():
		if child is Button:
			if child.name == "Btn_Empty":
				child.pressed.connect(_on_main_tool_pressed.bind(-1))
			else:
				child.pressed.connect(_on_main_tool_pressed.bind(tool_index))
				tool_index += 1
				
	# ✨ 核心变动：监听新背包系统的信号
	if inventory_ui:
		inventory_ui.item_selected.connect(_on_inventory_item_selected)
		inventory_ui.visible = false # 游戏开始时隐藏背包
		
	_update_visuals(-1)
	
	# ✨ 新增：通过群组找到总管，监听钱包余额变化！
	var inv_manager = get_tree().get_first_node_in_group("inventory_manager")
	if inv_manager:
		inv_manager.points_updated.connect(_on_points_updated)
		# 强制刷一次初始显示
		_on_points_updated(inv_manager.current_points)

# ==========================================
# 🛠️ 工具切换逻辑
# ==========================================
func _on_main_tool_pressed(index: int):
	current_active_index = index
	
	if tool_manager:
		tool_manager.switch_tool(index)
		
	# ✨ 核心表现：选中播种工具(0)时，呼出真正的动态背包
	if index == 0 and inventory_ui:
		inventory_ui.visible = true
		# 强制背包切到种子分类 (假设 ItemResource 里 SEED 枚举值为 0)
		inventory_ui._switch_tab(0) 
	elif inventory_ui:
		inventory_ui.visible = false
		
	_update_visuals(index)

func _update_visuals(active_index: int):
	var idx = 0
	for child in main_toolbar.get_children():
		if child is Button:
			var is_active = false
			if child.name == "Btn_Empty":
				is_active = (active_index == -1)
			else:
				is_active = (active_index == idx)
				idx += 1
				
			child.modulate = Color(0.5, 1.0, 0.5) if is_active else Color.WHITE

# ==========================================
# 📦 数据流转链路 (接收背包数据 -> 传给工具)
# ==========================================
func _on_inventory_item_selected(real_index: int, item: ItemResource):
	# 确保当前拿着的是播种工具
	if current_active_index == 0 and tool_manager:
		var current_tool = tool_manager.tools[0]
		
		# 鸭子类型检查：目标工具是否能装种子，且传入物品确实是植物数据
		if current_tool.has_method("load_seed") and item is PlantItemResource:
			
			# ✨ 完美传递：引用和物理索引一同注入！
			current_tool.load_seed(item, real_index)
			print("🎒 播种工具装填完毕 | 物品: ", item.display_name, " | 底层索引: ", real_index)
			
			# (可选) 装填完毕后自动收起背包面板，避免挡住屏幕中心的花盆
			inventory_ui.visible = false
# ✨ 钱包变动回调
func _on_points_updated(new_amount: int):
	if points_label:
		points_label.text = "💰 点数: " + str(new_amount)
		
		# (可选的 Juiciness) 给 Label 做个简单的缩放动画，强化获得金币的视觉反馈
		var tween = create_tween().set_trans(Tween.TRANS_BOUNCE)
		points_label.scale = Vector2(1.5, 1.5)
		tween.tween_property(points_label, "scale", Vector2.ONE, 0.3)
