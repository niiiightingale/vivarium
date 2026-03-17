extends CanvasLayer

@onready var day_label = $GlobalTool/VBoxContainer/Label
@onready var next_day_btn = $GlobalTool/VBoxContainer/NextDayButton
@onready var water_btn = $GlobalTool/VBoxContainer/WaterButton # 新的浇水按钮

func _ready():
	update_label()
	next_day_btn.pressed.connect(_on_next_day_pressed)
	# 把新按钮连上！
	water_btn.pressed.connect(_on_water_pressed)

func _on_next_day_pressed():
	TimeManager.advance_day(1)
	update_label()

# ✨ 浇水按钮按下时的逻辑
func _on_water_pressed():
	# 呼叫全场贴了 "plants" 标签的植物，让它们执行浇水动作
	var plants = get_tree().get_nodes_in_group("plants")
	for p in plants:
		p.water_plant(50.0)

func update_label():
	day_label.text = "当前天数: " + str(TimeManager.current_day)
