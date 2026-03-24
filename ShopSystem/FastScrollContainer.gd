class_name SmoothScrollContainer
extends ScrollContainer

@export var scroll_step: float = 120.0 # 每次滚动的像素距离
@export var scroll_duration: float = 0.3 # 缓动耗时 (秒)

var target_scroll: float = 0.0
var scroll_tween: Tween

func _ready():
	# 初始化目标游标，防止初始位置非 0 时发生跳跃
	target_scroll = scroll_vertical
	
	# ✨ 边缘情况防御：监听玩家直接拖动原生滚动条的操作，同步目标游标
	get_v_scroll_bar().scrolling.connect(_on_native_scroll)

func _on_native_scroll():
	target_scroll = scroll_vertical

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_animate_scroll(-scroll_step)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_animate_scroll(scroll_step)
			accept_event()

func _animate_scroll(delta_target: float):
	# 1. 获取当前容器的真实可滚动上限
	var v_bar = get_v_scroll_bar()
	var max_scroll = max(0, v_bar.max_value - v_bar.page)
	
	# 2. 累加目标值，并严格限制在 [0, max_scroll] 范围内
	# 作用：防止玩家在顶部狂滚滚轮导致 target_scroll 变成负数，从而需要很长时间才能滚回来
	target_scroll = clamp(target_scroll + delta_target, 0.0, max_scroll)
	
	# 3. 杀死正在执行的旧缓动，防止两个动画同时抢夺 scroll_vertical 的控制权
	if scroll_tween and scroll_tween.is_valid():
		scroll_tween.kill()
		
	# 4. 生成新的缓动动画
	scroll_tween = create_tween()
	# TRANS_QUART 配合 EASE_OUT 提供极强的减速阻尼感 (比 SINE 和 CUBIC 更干脆)
	scroll_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	scroll_tween.tween_property(self, "scroll_vertical", int(target_scroll), scroll_duration)
