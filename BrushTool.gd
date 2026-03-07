class_name BrushTool
extends Node3D

# ==========================================
# 毛刷手感参数
# ==========================================
@export var sweep_speed: float = 15.0     # 刷子左右摇摆的速度 (频率)
@export var sweep_angle: float = 30.0     # 刷子摇摆的最大角度 (度数)
@export var hover_height: float = 0.2     # 刷子悬浮在泥土上方的高度

@onready var brush_model = $BrushModel    # 你的低多边形刷子模型xxx
@onready var dust_particles = $DustParticals # 粉尘粒子系统

var is_brushing: bool = false
var sweep_time: float = 0.0

func _process(delta):
	if is_brushing:
		# 1. 时间累加
		sweep_time += delta * sweep_speed
		
		# 2. 正弦波摇摆魔法 (sin的值在 -1 到 1 之间平滑过渡)
		var current_angle = sin(sweep_time) * deg_to_rad(sweep_angle)
		brush_model.rotation.z = current_angle # 假设 Z 轴是控制左右摇摆的轴
		
		# 3. 开启扬尘特效
		dust_particles.emitting = true
		
	else:
		# 停止刷土时
		dust_particles.emitting = false
		
		# 极其丝滑地让刷子回到正中间的回正动画
		brush_model.rotation.z = lerp_angle(brush_model.rotation.z, 0.0, 15.0 * delta)
		# 稍微重置一下时间，保证下次下笔也是从中间开始
		sweep_time = lerp(sweep_time, 0.0, 10.0 * delta)
