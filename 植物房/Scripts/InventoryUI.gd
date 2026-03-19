class_name InventoryUI
extends Control

signal item_selected(real_index: int, item: ItemResource)

# ==========================================
# 🔗 外部依赖
# ==========================================
@export var inventory_manager: Node # 拖入你挂载了 InventoryManager 的节点
@export var slot_prefab: PackedScene # 拖入刚刚保存的 InventorySlotUI.tscn

@onready var tabs_container = $VBoxContainer/Tabs_Category
@onready var slot_grid = $VBoxContainer/ScrollContainer/SlotGrid

# 当前停留的分类页签，默认是种子 (对应 ItemCategory.SEED = 0)
var current_category: int = 0 

func _ready():
	# 1. 监听底层大脑的数据变动信号
	if inventory_manager:
		inventory_manager.inventory_updated.connect(refresh_ui)
		
	# 2. 绑定分类 Tab 按钮的点击事件 (硬编码绑定枚举值)
	var btn_seed = tabs_container.get_node("Btn_Seed")
	var btn_fert = tabs_container.get_node("Btn_Fertilizer")
	var btn_pot = tabs_container.get_node("Btn_Pot")
	
	if btn_seed: btn_seed.pressed.connect(_switch_tab.bind(0))
	if btn_fert: btn_fert.pressed.connect(_switch_tab.bind(1))
	if btn_pot: btn_pot.pressed.connect(_switch_tab.bind(2))
	
	# 初始化渲染一次
	refresh_ui()

# ==========================================
# 🔄 核心渲染逻辑
# ==========================================
func _switch_tab(category_enum: int):
	current_category = category_enum
	refresh_ui()

func refresh_ui():
	if not inventory_manager or not slot_prefab: return
	
	# 1. 极度残忍地清理旧节点（防止节点残留）
	for child in slot_grid.get_children():
		child.queue_free()
		
	# 2. 向大脑请求当前分类的过滤数据
	# 返回的数据格式是数组：[{"real_index": 1, "item": ItemResource}, ...]
	var filtered_data = inventory_manager.get_items_by_category(current_category)
	
	# 3. 实例化新的 UI 格子
	for data in filtered_data:
		var slot_ui = slot_prefab.instantiate() as InventorySlotUI
		slot_grid.add_child(slot_ui)
		
		# ✨ 核心绑定：把绝对物理索引注入给 UI 格子
		var r_index = data["real_index"]
		var item_res = data["item"]
		slot_ui.setup(r_index, item_res)
		
		# 监听玩家点击格子的操作
		slot_ui.pressed.connect(_on_slot_clicked.bind(r_index, item_res))
		print("refreshUI")

# ==========================================
# 🖱️ 交互逻辑
# ==========================================
func _on_slot_clicked(r_index: int, item: ItemResource):
	print("🎒 UI 选中了物品 [", item.display_name, "]，其底层物理索引为: ", r_index)
	# 把选中的信息广播出去，让 RoomUI 或者 ToolManager 接收并装填进工具
	item_selected.emit(r_index, item)
