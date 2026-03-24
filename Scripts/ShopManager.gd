class_name ShopManager
extends Node

# ==========================================
# 📦 货源配置区 (在检查器中拖入你的物品 tres)
# ==========================================
# 1. 常驻商品 (普通花盆、基础肥料、常见种子)
@export var permanent_stock: Array[ItemResource] = []

# 2. 稀有卡池 (变异种子、高级营养液)
@export var rare_item_pool: Array[ItemResource] = []

# 3. 每日刷新的格子数量
@export var daily_slots: int = 3

# ==========================================
# 🛒 当前真实货架数据
# ==========================================
var current_daily_stock: Array[ItemResource] = []

signal shop_refreshed # 货架刷新时广播，通知 UI 更新

func _ready():
	# 监听时间系统，每天刷新货架
	var time_manager = get_tree().get_first_node_in_group("time_manager")
	if time_manager and time_manager.has_signal("day_passed"):
		time_manager.day_passed.connect(_on_new_day)
		
	# 游戏启动时先强制进一次货
	refresh_daily_stock()

# ==========================================
# 🔄 核心机制：每日洗牌逻辑
# ==========================================
func _on_new_day(_days: int):
	refresh_daily_stock()

func refresh_daily_stock():
	current_daily_stock.clear()
	
	# 如果稀有池是空的，就不刷了
	if rare_item_pool.is_empty(): return
	
	# 简单洗牌算法：打乱卡池，抽取前 N 个
	var temp_pool = rare_item_pool.duplicate()
	temp_pool.shuffle()
	
	for i in range(min(daily_slots, temp_pool.size())):
		current_daily_stock.append(temp_pool[i])
		
	print("🛒 邮购目录已更新！今日限定商品：", current_daily_stock.map(func(i): return i.display_name))
	shop_refreshed.emit()

# ==========================================
# 💳 交易接口
# ==========================================
func buy_item(item: ItemResource) -> bool:
	var inv_manager = get_tree().get_first_node_in_group("inventory_manager")
	if not inv_manager: return false
	
	# 1. 查验余额并尝试扣款
	if inv_manager.spend_points(item.price):
		# 2. 扣款成功，发货！
		inv_manager.add_item(item)
		print("📦 购买成功！已将 [", item.display_name, "] 放入背包。")
		return true
	else:
		print("❌ 购买失败：点数不足！需要 ", item.price, "，只有 ", inv_manager.current_points)
		return false
