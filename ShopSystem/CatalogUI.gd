class_name CatalogUI
extends CanvasLayer

@export var item_ui_prefab: PackedScene
# ✨ 声明依赖：接收指定的 3D 交互实体
@export var interactable_trigger: CatalogInteractable

@onready var permanent_grid = $ColorRect/Panel/ScrollContainer/VBoxContainer/PermanentGrid
@onready var daily_grid = $ColorRect/Panel/ScrollContainer/VBoxContainer/DailyGrid
@onready var close_button = $ColorRect/CloseButton

var shop_manager: Node

func _ready():
	visible = false
	close_button.pressed.connect(func(): visible = false)
	
	# ✨ 内部闭环：直接监听绑定的 3D 实体信号
	if interactable_trigger:
		interactable_trigger.catalog_opened.connect(open_catalog)
	else:
		push_warning("⚠️ CatalogUI 未绑定 interactable_trigger，将无法通过物理点击打开！")
		
	call_deferred("_init_shop_manager")

func _init_shop_manager():
	shop_manager = get_tree().get_first_node_in_group("shop_manager")

# 由 3D 实体的信号触发
func open_catalog():
	if not shop_manager:
		push_error("❌ CatalogUI 找不到 ShopManager！")
		return
		
	visible = true
	_refresh_catalog()

func _refresh_catalog():
	# 1. 暴力清理旧节点
	for child in permanent_grid.get_children(): child.queue_free()
	for child in daily_grid.get_children(): child.queue_free()
	
	# 2. 渲染常驻商品
	for item in shop_manager.permanent_stock:
		_create_item_ui(item, permanent_grid)
		
	# 3. 渲染每日限定
	for item in shop_manager.current_daily_stock:
		_create_item_ui(item, daily_grid)

func _create_item_ui(item: ItemResource, parent: Control):
	var ui = item_ui_prefab.instantiate() as CatalogItemUI
	parent.add_child(ui)
	ui.setup(item)
	ui.buy_requested.connect(_on_buy_requested)

func _on_buy_requested(item: ItemResource):
	if not shop_manager: return
	
	# 核心扣款逻辑，ShopManager 返回 true 说明点数够并已发货
	var success = shop_manager.buy_item(item)
	
	if success:
		print("🛒 [UI] 购买成功视觉表现")
		# 可以在这里让按钮闪烁绿光，或播放金币音效
	else:
		print("❌ [UI] 购买失败视觉表现：余额不足")
		# 可以在这里让价格标签闪烁红光，或播放错误音效
