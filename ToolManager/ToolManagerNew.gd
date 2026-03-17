class_name ToolManagerNew
extends Node3D

@export var tools: Array[Node3D] 
var current_tool_index: int = -1

func _ready() -> void:
	# 游戏开始时，先把所有工具“断电”
	for tool in tools:
		if tool.has_method("deactivate"):
			tool.deactivate()
			
	# 如果你想让玩家一进游戏手里就是空的，就把下面这两行注释掉
	# 如果想默认拿着第一个工具，就保留
	if tools.size() > 0:
		switch_tool(0)

# ==========================================
# 开放给 UI 层调用的核心接口
# ==========================================
func switch_tool(index: int) -> void:
	# 如果点的就是当前正拿着的工具，啥也不做
	if index == current_tool_index:
		return 
		
	# 1. 给当前工具断电
	if current_tool_index >= 0 and current_tool_index < tools.size():
		var old_tool = tools[current_tool_index]
		if old_tool.has_method("deactivate"):
			old_tool.deactivate()
			
	# 2. 更新序号
	current_tool_index = index
	
	# 如果传入的序号越界或为 -1，代表玩家选择了“空手/取消装备”
	if current_tool_index < 0 or current_tool_index >= tools.size():
		print("🔧 当前手无寸铁")
		return
	
	# 3. 给新工具通电
	var new_tool = tools[current_tool_index]
	if new_tool.has_method("activate"):
		new_tool.activate()
		
	print("🔧 当前工具已切换为: ", new_tool.name)
