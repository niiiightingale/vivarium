class_name RoomUI
extends CanvasLayer

# 核心依赖
@export var tool_manager: RoomToolManager
@export var seed_resources: Array[PlantItemResource] # 把你所有的种子tres按顺序拖到这里！

# 节点引用
@onready var main_toolbar = $MarginContainer/VBoxContainer/MainToolbar
@onready var seed_sub_menu = $MarginContainer/VBoxContainer/SeedSubMenu

# 状态记忆
var current_active_index: int = -1

func _ready():
	# 1. 动态绑定【主工具栏】按钮 (复刻你的优秀代码！)
	var tool_index = 0
	for child in main_toolbar.get_children():
		if child is Button:
			if child.name == "Btn_Empty":
				child.pressed.connect(_on_main_tool_pressed.bind(-1))
			else:
				child.pressed.connect(_on_main_tool_pressed.bind(tool_index))
				tool_index += 1
				
	# 2. 动态绑定【种子子菜单】按钮
	var seed_index = 0
	for child in seed_sub_menu.get_children():
		if child is Button:
			child.pressed.connect(_on_seed_selected.bind(seed_index))
			seed_index += 1
			
	# 初始化 UI 状态
	seed_sub_menu.visible = false
	_update_visuals(-1)


# ==========================================
# 🛠️ 交互逻辑
# ==========================================
func _on_main_tool_pressed(index: int):
	current_active_index = index
	
	# 呼叫 3D 世界的管理器切换工具
	if tool_manager:
		tool_manager.switch_tool(index)
		
	# ✨ 核心表现：如果选中的是播种工具（假设是 0），展开种子子菜单！
	if index == 0:
		seed_sub_menu.visible = true
	else:
		seed_sub_menu.visible = false
		
	_update_visuals(index)

func _on_seed_selected(seed_index: int):
	# 确保当前拿着的是播种工具，并且资源数组里有东西
	if current_active_index == 0 and tool_manager and seed_index < seed_resources.size():
		var seed_tool = tool_manager.tools[0] as SeedTool
		if seed_tool:
			var res = seed_resources[seed_index]
			seed_tool.load_seed(res)
			print("🎒 播种工具已装填种子：", res.display_name)
			
			# (可选) 选完种子后自动收起子菜单，看你喜欢的交互体验
			#seed_sub_menu.visible = false 

func _update_visuals(active_index: int):
	# 禁用当前选中的按钮，让玩家知道自己拿着啥
	var idx = 0
	for child in main_toolbar.get_children():
		if child is Button:
			if child.name == "Btn_Empty":
				child.disabled = (active_index == -1)
			else:
				child.disabled = (active_index == idx)
				idx += 1
