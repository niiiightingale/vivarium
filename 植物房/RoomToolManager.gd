class_name RoomToolManager
extends Node3D

@export var tools: Array[Node3D] 
var current_tool_index: int = -1

func _ready() -> void:
	# 游戏开始时，全部工具断电静音
	for tool in tools:
		if tool.has_method("deactivate"):
			tool.deactivate()

# ==========================================
# 开放给 UI 调用的接口
# ==========================================
func switch_tool(index: int) -> void:
	if index == current_tool_index:
		return 
		
	# 1. 旧工具断电
	if current_tool_index >= 0 and current_tool_index < tools.size():
		var old_tool = tools[current_tool_index]
		if old_tool.has_method("deactivate"):
			old_tool.deactivate()
			
	current_tool_index = index
	
	# 传入 -1 代表空手
	if current_tool_index < 0 or current_tool_index >= tools.size():
		print("🖐️ 放下一切，当前为空手状态")
		return
	
	# 2. 新工具通电
	var new_tool = tools[current_tool_index]
	if new_tool.has_method("activate"):
		new_tool.activate()
		
	print("🔧 大房间工具已切换为: ", new_tool.name)
