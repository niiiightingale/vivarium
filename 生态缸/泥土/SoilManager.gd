extends Node3D

const GRID_SIZE = 100 
const PHYSICAL_SIZE = 5.0 

var height_map_image : Image
var height_map_texture : ImageTexture

@export var brush_radius: float = 0.5  
@export var brush_strength: float = 0.02 

# ==========================================
# 沙堆塌陷算法控制参数
# ==========================================
@export var max_slope: float = 0.05   
@export var flow_rate: float = 0.5    
var is_terrain_settling: bool = false 

@onready var soil_body = $SoilBody
@onready var collision_shape = $SoilBody/SoilCollision

var height_shape = HeightMapShape3D.new() 

# ==========================================
# 交互与工具参数 
# ==========================================
@export var bucket_hover_height: float = 1.5   # 小桶悬浮高度
@export var brush_hover_height: float = 0.15  # 刷子悬浮高度（地表上方一丢丢）

@export var drop_radius: float = 0.5        
@export var clumps_per_second: float = 30.0 
@export var valid_bounds: float = 2.4       
var spawn_timer: float = 0.0

@onready var player_input = $PlayerInput 
@onready var tool_manager = $"../ToolManager" # 确保路径指向你的 ToolManager

# ==========================================
# 物理碰撞延迟刷新与半空坠落队列
# ==========================================
var needs_physics_update: bool = false
var physics_update_timer: float = 0.0
@export var physics_update_interval: float = 0.1 

var pending_drops: Array[Dictionary] = []

func _ready():
	height_map_image = Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RF)
	height_map_image.fill(Color(0.0, 0.0, 0.0, 1.0)) 
	height_map_texture = ImageTexture.create_from_image(height_map_image)
	
	var material = $PlaneMesh.get_active_material(0)
	material.set_shader_parameter("height_map", height_map_texture)

	var base_height = material.get_shader_parameter("min_top_height")
	if base_height != null:
		soil_body.position.y = base_height

	height_shape.map_width = GRID_SIZE
	height_shape.map_depth = GRID_SIZE
	collision_shape.shape = height_shape
	
	var scale_factor = PHYSICAL_SIZE / float(GRID_SIZE - 1)
	soil_body.scale = Vector3(scale_factor, 1.0, scale_factor)
	
	update_physics_collision()

func update_physics_collision():
	var float_array = height_map_image.get_data().to_float32_array()
	height_shape.map_data = float_array

func _process(delta):
	var current_time = Time.get_ticks_msec() / 1000.0 
	
	# ==========================================
	# 1. 处理小桶坠落队列 (仅加法)
	# ==========================================
	var terrain_modified = false
	for i in range(pending_drops.size() - 1, -1, -1):
		if current_time >= pending_drops[i]["time"]:
			var drop_pos = pending_drops[i]["pos"]
			# 0.01 是单次落地的泥土厚度
			apply_soil_brush(drop_pos, drop_radius, 0.01, true) 
			pending_drops.remove_at(i) 
			terrain_modified = true
			
	if terrain_modified or is_terrain_settling:
		is_terrain_settling = simulate_soil_avalanche() 
		needs_physics_update = true

	# ==========================================
	# 2. 延迟刷新物理碰撞
	# ==========================================
	if needs_physics_update:
		physics_update_timer += delta
		if physics_update_timer >= physics_update_interval:
			update_physics_collision()
			needs_physics_update = false
			physics_update_timer = 0.0

	# ==========================================
	# 3. 接收指令：根据 ToolManager 切换逻辑
	# ==========================================
	if player_input and player_input.is_valid_location:
		var safe_pos = player_input.target_position
		var current_mode = tool_manager.get_current_mode()
		
		# 更新视觉表现位置：桶高，刷低
		if current_mode == ToolManager.ToolMode.BUCKET:
			# 假设你的桶节点叫 bucket_tool，这里同步它的 Y 轴
			tool_manager.bucket_tool.global_position.y = safe_pos.y + bucket_hover_height
		else:
			tool_manager.brush_tool.global_position.y = safe_pos.y + brush_hover_height

		if player_input.is_interacting:
			if current_mode == ToolManager.ToolMode.BUCKET:
				# --- 小桶逻辑：生成坠落队列 ---
				spawn_timer += delta
				var spawn_interval = 1.0 / clumps_per_second 
				while spawn_timer >= spawn_interval:
					var fall_time = sqrt(max(0.0, 2.0 * bucket_hover_height / 9.8))
					var random_angle = randf() * TAU 
					var random_radius = sqrt(randf()) * drop_radius
					var target_pos = Vector3(
						safe_pos.x + cos(random_angle) * random_radius,
						safe_pos.y,
						safe_pos.z + sin(random_angle) * random_radius
					)
					
					if abs(target_pos.x) <= valid_bounds and abs(target_pos.z) <= valid_bounds:
						pending_drops.append({
							"pos": target_pos,
							"time": current_time + fall_time 
						})
					spawn_timer -= spawn_interval
			
			else:
				# --- 毛刷逻辑：即时降低高度 ---
				# 刷子扫土是实时的，不需要物理延迟，直接修改高度图
				apply_soil_brush(safe_pos, brush_radius, brush_strength, false)
				needs_physics_update = true
		else:
			spawn_timer = 0.0
	else:
		spawn_timer = 0.0

# ==========================================
# 核心修改：高度图笔刷 (支持加/减)
# ==========================================
func apply_soil_brush(world_position: Vector3, radius: float, strength: float, is_adding: bool):
	var center_x = int((world_position.x / PHYSICAL_SIZE + 0.5) * GRID_SIZE)
	var center_y = int((world_position.z / PHYSICAL_SIZE + 0.5) * GRID_SIZE)
	var pixel_radius = int((radius / PHYSICAL_SIZE) * GRID_SIZE)
	
	for x in range(center_x - pixel_radius, center_x + pixel_radius):
		for y in range(center_y - pixel_radius, center_y + pixel_radius):
			if x >= 0 and x < GRID_SIZE and y >= 0 and y < GRID_SIZE:
				var dist = Vector2(x, y).distance_to(Vector2(center_x, center_y))
				
				if dist <= pixel_radius:
					var weight = smoothstep(1.0, 0.0, dist / float(pixel_radius))
					var current_h = height_map_image.get_pixel(x, y).r
					
					var new_h = 0.0
					if is_adding:
						new_h = current_h + (strength * weight)
					else:
						# 减法逻辑：确保不低于 0.0（或你设定的最低限制）
						new_h = max(0.0, current_h - (strength * weight))
					
					height_map_image.set_pixel(x, y, Color(new_h, 0, 0, 1))
	
	height_map_texture.update(height_map_image)

# ==========================================
# 沙堆塌陷算法 (保持不变)
# ==========================================
func simulate_soil_avalanche() -> bool:
	var is_unstable = false
	for x in range(1, GRID_SIZE - 1):
		for y in range(1, GRID_SIZE - 1):
			var current_h = height_map_image.get_pixel(x, y).r
			var max_diff = 0.0
			var target_neighbor = Vector2i(-1, -1)
			var neighbor_h = 0.0
			
			var neighbors = [Vector2i(x+1, y), Vector2i(x-1, y), Vector2i(x, y+1), Vector2i(x, y-1)]
			for n in neighbors:
				var nh = height_map_image.get_pixel(n.x, n.y).r
				var diff = current_h - nh
				if diff > max_diff:
					max_diff = diff
					target_neighbor = n
					neighbor_h = nh
					
			if max_diff > max_slope:
				var flow_amount = min((max_diff - max_slope) * flow_rate, max_diff / 2.0)
				height_map_image.set_pixel(x, y, Color(current_h - flow_amount, 0, 0, 1))
				height_map_image.set_pixel(target_neighbor.x, target_neighbor.y, Color(neighbor_h + flow_amount, 0, 0, 1))
				is_unstable = true
				
	height_map_texture.update(height_map_image)
	return is_unstable
