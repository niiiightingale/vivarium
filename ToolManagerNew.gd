class_name ToolManagerNew
extends Node3D

# 在检查器里，把你所有的工具节点（比如 PlacementTool）拖进这个数组里
@export var tools: Array[Node3D] 
var current_tool_index: int = -1

func _ready() -> void:
	# 游戏开始时，先把所有工具“断电”
	for tool in tools:
		if tool.has_method("deactivate"):
			tool.deactivate()
			
	# 默认给第一个工具“通电”
	if tools.size() > 0:
		_switch_to_tool(0)

func _unhandled_input(event: InputEvent) -> void:
	# ToolManager 唯一需要监听的按键：切换工具
	if event.is_action_pressed("toggle_tool"):
		if tools.size() > 0:
			var next_index = (current_tool_index + 1) % tools.size()
			_switch_to_tool(next_index)

func _switch_to_tool(index: int) -> void:
	# 1. 给当前工具断电
	if current_tool_index >= 0 and current_tool_index < tools.size():
		var old_tool = tools[current_tool_index]
		if old_tool.has_method("deactivate"):
			old_tool.deactivate()
			
	# 2. 更新序号
	current_tool_index = index
	var new_tool = tools[current_tool_index]
	
	# 3. 给新工具通电
	if new_tool.has_method("activate"):
		new_tool.activate()
		
	print("🔧 当前工具已切换为: ", new_tool.name)
