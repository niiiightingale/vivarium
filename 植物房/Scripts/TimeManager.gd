extends Node

# 定义一个全局广播喇叭：当一天过去时，向全宇宙广播“过了几天”
signal day_passed(days: int)

var current_day: int = 1

# 推进时间的方法
func advance_day(days_to_add: int = 1):
	current_day += days_to_add
	print("🌅 天亮了！当前是第 ", current_day, " 天")
	# 吹响喇叭！所有听到这个信号的植物都会开始算账
	day_passed.emit(days_to_add)
