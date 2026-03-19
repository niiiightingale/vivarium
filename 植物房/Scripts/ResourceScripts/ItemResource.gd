class_name ItemResource
extends Resource

# 核心：用于 UI 顶部的分类过滤
enum ItemCategory { SEED, FERTILIZER, POT }

@export var id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D
@export var category: ItemCategory = ItemCategory.SEED
# ✨ 新增：商店售价
@export_range(0, 9999) var price: int = 50
# ✨ 新增：物品的多行描述文本 (用 multiline 可以让输入框大一点，方便你写长文)
@export_multiline var description: String = "这是一段未知的神秘描述。"
