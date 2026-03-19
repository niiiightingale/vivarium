class_name CatalogItemUI
extends PanelContainer

signal buy_requested(item: ItemResource)

# 重新绑定节点
@onready var name_label = $HBoxContainer/TextContainer/NameLabel
@onready var desc_label = $HBoxContainer/TextContainer/DescLabel
@onready var price_label = $HBoxContainer/ActionContainer/PriceLabel
@onready var buy_button = $HBoxContainer/ActionContainer/BuyButton

var item_data: ItemResource

func setup(item: ItemResource):
	item_data = item
	
	# 文本渲染
	name_label.text = item.display_name
	desc_label.text = item.description # ✨ 渲染你新加的描述文本
	price_label.text = "💰 " + str(item.price)
	
	buy_button.pressed.connect(_on_buy_pressed)

func _on_buy_pressed():
	buy_requested.emit(item_data)
