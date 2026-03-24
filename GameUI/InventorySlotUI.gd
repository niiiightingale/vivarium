class_name InventorySlotUI
extends Button

# ==========================================
# 📦 数据绑定
# ==========================================
var real_index: int = -1
var item_data: ItemResource = null

# 由主面板在实例化时调用此方法注入数据
func setup(index: int, item: ItemResource):
	real_index = index
	item_data = item
	
	# 设置视觉表现
	if item.icon:
		icon = item.icon
		icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		expand_icon = true
		
	# 鼠标悬停时显示物品名字
	tooltip_text = item.display_name
