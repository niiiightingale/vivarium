extends Node
# 如果不设为单例，请加上 class_name InventoryManager

# ==========================================
# 📡 全局广播信号
# ==========================================
# 当背包发生任何增删改时，呼叫 UI 重新渲染
signal inventory_updated 
signal points_updated(new_amount: int) # ✨ 新增：点数变动信号

# ==========================================
# ⚙️ 测试配置区 (供开发者在检查器填入)
# ==========================================
# 在这里添加 InventorySlotConfig，比如：[姬玉露, 3]
@export var initial_items: Array[InventorySlotConfig] = []

# ==========================================
# 📦 运行时真实数据 (纯粹的一维数组)
# ==========================================
# 这里的元素绝对不堆叠，有3个姬玉露，这里面就有3个相同的引用
var current_points: int = 0 # ✨ 新增：玩家当前的硬通货
var items: Array[ItemResource] = []

func _ready():
	_unpack_initial_data()

# 核心逻辑：将开发者配置的“堆叠数据”，解包碾平为“单格数组”
func _unpack_initial_data():
	items.clear()
	for config in initial_items:
		if config.item:
			# 如果填了数量为 3，就往真实数组里塞 3 次！
			for i in range(config.amount):
				items.append(config.item)
				
	print("🎒 背包初始化完成，当前真实占用的格子数：", items.size())
	# 延迟一帧发送信号，确保 UI 已经准备好接收
	call_deferred("emit_signal", "inventory_updated")


# ==========================================
# 🔍 数据查询与过滤接口 (供 UI 调用)
# ==========================================
# ⚠️ 绝对不要只返回物品，必须把“绝对物理索引”一起返回，防止 UI 删错东西！
func get_items_by_category(target_category: int) -> Array[Dictionary]:
	var filtered_results: Array[Dictionary] = []
	
	for i in range(items.size()):
		var current_item = items[i]
		if current_item and current_item.category == target_category:
			# 把真实索引打包在一起交出去
			filtered_results.append({
				"real_index": i,
				"item": current_item
			})
			
	return filtered_results


# ==========================================
# 🔧 增删查改接口 (供游戏逻辑调用)
# ==========================================
func add_item(new_item: ItemResource):
	if new_item == null: return
	items.append(new_item)
	print("➕ 获得了物品：", new_item.display_name)
	inventory_updated.emit()

# 必须通过物理绝对索引删除！
func remove_item_at_index(real_index: int) -> bool:
	if real_index < 0 or real_index >= items.size():
		push_error("❌ 背包越界：试图删除不存在的索引 ", real_index)
		return false
		
	var removed_name = items[real_index].display_name
	items.remove_at(real_index)
	print("➖ 消耗了物品：", removed_name)
	
	inventory_updated.emit()
	return true
# 💳 货币收支接口 (在文件最底部添加)
# ==========================================
func add_points(amount: int):
	current_points += amount
	print("💰 获得点数：+", amount, "，当前余额：", current_points)
	points_updated.emit(current_points)

func spend_points(amount: int) -> bool:
	if current_points >= amount:
		current_points -= amount
		print("💸 消耗点数：-", amount, "，当前余额：", current_points)
		points_updated.emit(current_points)
		return true
	else:
		print("❌ 余额不足！")
		return false
