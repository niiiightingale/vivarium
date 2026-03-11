class_name CameraController
extends Node3D

# ==========================================
# 操控手感参数
# ==========================================
@export var pan_speed: float = 0.015      
@export var rotation_speed: float = 0.005 
@export var zoom_speed: float = 2.0       

@export var min_zoom: float = 4.0         
@export var max_zoom: float = 15.0        

@export var bounds_xz: float = 3.0        
@export var bounds_y_min: float = -1.0    
@export var bounds_y_max: float = 10.0    

@export var min_pitch: float = -80.0      
@export var max_pitch: float = -10.0      

# ==========================================
# 挂机展示模式参数 (Idle Showcase)
# ==========================================
@export var enable_idle_mode: bool = true      
@export var idle_time_threshold: float = 10.0  
@export var opening_zoom: float = 30.0         
@export var opening_duration: float = 4.0      

var opening_tween: Tween 
@export var idle_zoom: float = 12.0            
@export var idle_pitch: float = -30.0          
@export var idle_height_offset: float = 2.0
@export var idle_rotation_speed: float = 0.05  
@export var idle_transition_speed: float = 1.5 

# ==========================================
# ✨ 终极智能景深 (Smart DoF & AutoFocus)
# ==========================================
@export_group("Smart DoF Settings")
@export var enable_smart_dof: bool = true

@export var show_debug_rays: bool = false      

@export_subgroup("Autofocus Radar (九宫格雷达)")
@export var focus_reticle_size: float = 0.03       
@export var focus_speed: float = 25.0              
@export var edge_slip_threshold: float = 1.5       
@export var foreground_ignore_ratio: float = 0.6   

@export_subgroup("DoF Curves (X: Zoom, Y: Weight)")
@export var blur_start_curve: Curve       
@export var blur_transition_curve: Curve  
@export var blur_amount_curve: Curve      

@export_subgroup("DoF Ranges (X: Macro, Y: Wide)")
@export var blur_start_margin_range: Vector2 = Vector2(0.5, 8.0)  
@export var blur_transition_range: Vector2 = Vector2(0.5, 6.0)    
@export var blur_amount_range: Vector2 = Vector2(0.12, 0.02)      

@onready var camera = $Camera3D

var target_position: Vector3
var target_zoom: float

var target_yaw: float = 0.0   
var target_pitch: float = 0.0 

var is_panning: bool = false
var is_rotating: bool = false

var idle_timer: float = 0.0
var is_idle_mode: bool = false

var smooth_focus_distance: float = 5.0 

var debug_mesh: ImmediateMesh
var debug_mesh_instance: MeshInstance3D

func _ready():
	is_idle_mode = true
	
	target_position = Vector3(0.0, idle_height_offset, 0.0)
	target_pitch = deg_to_rad(idle_pitch) 
	target_yaw = rotation.y 
	
	global_position = target_position
	rotation.x = target_pitch 
	
	camera.position.z = opening_zoom
	target_zoom = opening_zoom 
	smooth_focus_distance = opening_zoom
	
	opening_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	opening_tween.tween_property(self, "target_zoom", idle_zoom, opening_duration)
	
	if enable_smart_dof:
		if not camera.attributes:
			camera.attributes = CameraAttributesPractical.new()
		camera.attributes.dof_blur_far_enabled = true
		
	if show_debug_rays:
		debug_mesh = ImmediateMesh.new()
		debug_mesh_instance = MeshInstance3D.new()
		debug_mesh_instance.mesh = debug_mesh
		debug_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		debug_mesh_instance.material_override = mat
		
		add_child(debug_mesh_instance)
		debug_mesh_instance.top_level = true 

func reset_idle_timer():
	idle_timer = 0.0
	if is_idle_mode:
		is_idle_mode = false
		target_yaw = rotation.y

func _unhandled_input(event):
	if event is InputEventMouseButton:
		reset_idle_timer()

	if event is InputEventMouseButton:
		if event.is_action_pressed("camera_zoom_in") or event.is_action_pressed("camera_zoom_out"):
			var is_zoom_in = event.is_action_pressed("camera_zoom_in")
			
			var mouse_pos = get_viewport().get_mouse_position()
			var ray_origin = camera.project_ray_origin(mouse_pos)
			var ray_dir = camera.project_ray_normal(mouse_pos)
			var space_state = get_world_3d().direct_space_state
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 100.0)
			query.collision_mask = 2 
			
			var result = space_state.intersect_ray(query)
			
			if result:
				var hit_pos = result.position
				if is_zoom_in and target_zoom > min_zoom:
					var actual_step = min(zoom_speed, target_zoom - min_zoom)
					var shift_weight = actual_step / target_zoom
					target_zoom -= actual_step
					target_position = target_position.lerp(hit_pos, shift_weight)
				elif not is_zoom_in and target_zoom < max_zoom:
					var actual_step = min(zoom_speed, max_zoom - target_zoom)
					var shift_weight = actual_step / target_zoom
					target_zoom += actual_step
					target_position += (target_position - hit_pos) * shift_weight
			else:
				if is_zoom_in: target_zoom = clamp(target_zoom - zoom_speed, min_zoom, max_zoom)
				else: target_zoom = clamp(target_zoom + zoom_speed, min_zoom, max_zoom)

			clamp_target_position()

	if event.is_action_pressed("camera_rotate", false, true):
		is_rotating = true
	elif event.is_action_released("camera_rotate", true):
		is_rotating = false
		
	if event.is_action_pressed("camera_pan", false, true):
		is_panning = true
	elif event.is_action_released("camera_pan", true):
		is_panning = false

	if event is InputEventMouseMotion:
		if is_rotating:
			target_yaw -= event.relative.x * rotation_speed
			target_pitch -= event.relative.y * rotation_speed
			target_pitch = clamp(target_pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))

		if is_panning:
			var cam_right = camera.global_transform.basis.x.normalized()
			var cam_up = camera.global_transform.basis.y.normalized()
			
			target_position -= cam_right * event.relative.x * pan_speed
			target_position += cam_up * event.relative.y * pan_speed
			clamp_target_position()

func clamp_target_position():
	target_position.x = clamp(target_position.x, -bounds_xz, bounds_xz)
	target_position.y = clamp(target_position.y, bounds_y_min, bounds_y_max)
	target_position.z = clamp(target_position.z, -bounds_xz, bounds_xz)

func _physics_process(delta: float) -> void:
	if enable_idle_mode and not is_rotating and not is_panning:
		idle_timer += delta
		if idle_timer >= idle_time_threshold:
			is_idle_mode = true

	if is_idle_mode:
		var perfect_center = Vector3(0.0, idle_height_offset, 0.0)
		target_position = target_position.lerp(perfect_center, idle_transition_speed * delta)
		target_zoom = lerp(target_zoom, idle_zoom, idle_transition_speed * delta)
		target_yaw += idle_rotation_speed * delta

	camera.position.z = lerp(camera.position.z, target_zoom, 10.0 * delta)
	camera.rotation = Vector3.ZERO 

	rotation.y = lerp_angle(rotation.y, target_yaw, 15.0 * delta)
	rotation.x = lerp_angle(rotation.x, target_pitch, 15.0 * delta)
	global_position = global_position.lerp(target_position, 15.0 * delta)

	# 🚨 核心防线 1：强制刷新相机矩阵！根除一帧延迟带来的横向飞线错觉！
	camera.force_update_transform()

	# ==========================================
	# ✨ 智能九宫格自动对焦核心逻辑
	# ==========================================
	if enable_smart_dof and camera.attributes is CameraAttributesPractical:
		var viewport_size = get_viewport().get_visible_rect().size
		var center = viewport_size / 2.0
		var offset = min(viewport_size.x, viewport_size.y) * focus_reticle_size
		
		var focus_points = [
			center, 
			center + Vector2(-offset, -offset), center + Vector2(0, -offset), center + Vector2(offset, -offset), 
			center + Vector2(-offset, 0),                                     center + Vector2(offset, 0),       
			center + Vector2(-offset, offset),  center + Vector2(0, offset),  center + Vector2(offset, offset)   
		]
		
		var space_state = get_world_3d().direct_space_state
		var center_depth = 9999.0
		var min_grid_depth = 9999.0
		
		if show_debug_rays and debug_mesh:
			debug_mesh_instance.global_transform = Transform3D.IDENTITY
			debug_mesh.clear_surfaces()
			debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		
		for i in range(focus_points.size()):
			var pt = focus_points[i]
			var ray_origin = camera.project_ray_origin(pt)
			var ray_dir = camera.project_ray_normal(pt)
			
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 100.0)
			
			# 🚨 核心防线 2：只碰撞 Layer 2！彻底根除撞到隐形玻璃引发的景深抽风！
			query.collision_mask = 2
			
			var result = space_state.intersect_ray(query)
			var current_z_depth = 9999.0
			var hit_pos = ray_origin + ray_dir * 100.0 
			
			if result:
				hit_pos = result.position
				current_z_depth = -camera.to_local(hit_pos).z
			elif ray_dir.y < -0.001:
				var t = -ray_origin.y / ray_dir.y
				hit_pos = ray_origin + ray_dir * t
				current_z_depth = -camera.to_local(hit_pos).z
				
			if show_debug_rays and debug_mesh:
				var line_color = Color.GREEN if i == 0 else Color.RED
				debug_mesh.surface_set_color(line_color)
				debug_mesh.surface_add_vertex(ray_origin)
				debug_mesh.surface_set_color(line_color)
				debug_mesh.surface_add_vertex(hit_pos)
				
			if i == 0:
				center_depth = current_z_depth
				
			if current_z_depth > 0.1 and current_z_depth < min_grid_depth:
				min_grid_depth = current_z_depth
				
		if show_debug_rays and debug_mesh:
			debug_mesh.surface_end()
				
		var target_focus_z = smooth_focus_distance
		
		if center_depth < 9000.0:
			var is_foreground_clutter = min_grid_depth < (center_depth * foreground_ignore_ratio)
			
			if (center_depth - min_grid_depth > edge_slip_threshold) and not is_foreground_clutter:
				target_focus_z = min_grid_depth
			else:
				target_focus_z = center_depth
				
		elif min_grid_depth < 9000.0:
			target_focus_z = min_grid_depth
		else:
			target_focus_z = target_zoom
			
		if focus_speed <= 0.0:
			smooth_focus_distance = target_focus_z 
		else:
			smooth_focus_distance = lerp(smooth_focus_distance, target_focus_z, focus_speed * delta)
		
		var current_dist = camera.position.z
		var zoom_ratio = clamp((current_dist - min_zoom) / (max_zoom - min_zoom), 0.0, 1.0)
		
		var start_weight = blur_start_curve.sample_baked(zoom_ratio) if blur_start_curve else zoom_ratio
		var trans_weight = blur_transition_curve.sample_baked(zoom_ratio) if blur_transition_curve else zoom_ratio
		var amount_weight = blur_amount_curve.sample_baked(zoom_ratio) if blur_amount_curve else zoom_ratio
		
		var blur_margin = lerp(blur_start_margin_range.x, blur_start_margin_range.y, start_weight)
		camera.attributes.dof_blur_far_distance = smooth_focus_distance + blur_margin
		camera.attributes.dof_blur_far_transition = lerp(blur_transition_range.x, blur_transition_range.y, trans_weight)
		camera.attributes.dof_blur_amount = lerp(blur_amount_range.x, blur_amount_range.y, amount_weight)
