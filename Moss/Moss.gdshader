shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform vec4 moss_color : source_color = vec4(0.3, 0.6, 0.2, 1.0);
uniform sampler2D moss_texture : source_color, filter_nearest;
uniform float moss_scale = 1.0;
uniform float sway_speed = 2.0;
uniform float sway_strength = 0.05;
// ✨【新增】：限制广告牌的最大仰角 (Pitch Limit)
// 0.0 表示完全垂直(僵尸)，1.57 表示允许完全平躺。0.6 弧度(约 35 度)是最佳观赏角度！
uniform float max_pitch_angle : hint_range(0.0, 1.57) = 0.6;

uniform float elevation_offset : hint_range(0.0, 0.5) = 0.1; 
uniform vec4 channel_mask = vec4(1.0, 0.0, 0.0, 0.0); 

uniform sampler2D height_map : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D moss_density_map : hint_default_black, filter_linear, repeat_disable;
uniform float physical_size = 5.0;
uniform float min_top_height = 0.6; 
uniform float height_scale = 1.0;

// ==========================================
// ✨ 鼓包与色彩变异系统 (优化版)
// ==========================================
uniform sampler2D clump_noise : hint_default_white, filter_linear, repeat_enable;
// ✨ 必须和泥土 Shader 保持绝对一致！
uniform vec4 clump_noise_scales = vec4(35.0, 1.0, 5.0, 20.0);
// ✨ 必须和泥土 Shader 里的参数保持绝对一致！
uniform vec4 moss_soil_bump = vec4(0.1, 0.1, 0.1, 0.1);

uniform float hue_variation : hint_range(0.0, 0.1) = 0.015;   
// 【修改】：默认值设为 0.02，极其克制的光影变化
uniform float value_variation : hint_range(0.0, 0.5) = 0.02; 

varying float v_noise;

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void vertex() {
	vec3 world_pos = MODEL_MATRIX[3].xyz;
	vec2 global_uv = (world_pos.xz / physical_size) + 0.5;
	vec4 tex_color = texture(moss_density_map, global_uv);
	float current_density = dot(tex_color, channel_mask);
	
	vec4 noises;
	noises.r = textureLod(clump_noise, (world_pos.xz / clump_noise_scales.r) + 0.5, 0.0).r;
	noises.g = textureLod(clump_noise, (world_pos.xz / clump_noise_scales.g) + 0.5, 0.0).r;
	noises.b = textureLod(clump_noise, (world_pos.xz / clump_noise_scales.b) + 0.5, 0.0).r;
	noises.a = textureLod(clump_noise, (world_pos.xz / clump_noise_scales.a) + 0.5, 0.0).r;
	
	vec4 dynamic_bumps = moss_soil_bump * noises;
	float dynamic_soil_bump = dot(tex_color, dynamic_bumps);
	
	v_noise = dot(noises, channel_mask);
	
	float soil_h = texture(height_map, global_uv).r * height_scale + min_top_height;
	float center_y = soil_h + dynamic_soil_bump + elevation_offset;

	float instance_scale = length(MODEL_MATRIX[0].xyz);
	
	// ==========================================
	// ✨ 【核心黑科技】：受限广告牌 (Pitch-Limited Billboard)
	// ==========================================
	// 1. 获取相机本来的后退方向
	vec3 cam_dir = INV_VIEW_MATRIX[2].xyz;
	float xz_len = length(cam_dir.xz);

	// 2. 防踩坑：如果玩家从正上方 90 度往下看，水平向量会消失。
	// 这时我们借用相机的 Up 向量作为水平朝向参考
	if (xz_len < 0.001) {
		cam_dir.xz = INV_VIEW_MATRIX[1].xz;
		xz_len = length(cam_dir.xz);
		if (xz_len < 0.001) cam_dir.xz = vec2(0.0, 1.0); // 终极防错
	}

	vec2 xz_dir = cam_dir.xz / xz_len;

	// 3. 计算当前的俯仰角，并强行把它关进牢笼！
	float pitch = atan(cam_dir.y, xz_len);
	pitch = clamp(pitch, -max_pitch_angle, max_pitch_angle);

	// 4. 用截断后的安全角度，重新组装草丛的朝向向量
	vec3 target_dir = vec3(xz_dir.x * cos(pitch), sin(pitch), xz_dir.y * cos(pitch));

	// 5. 重新构建不会左右侧倾的 Right 和 Up 向量
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), target_dir));
	vec3 up = cross(target_dir, right);

	// 6. 生成最终的安全矩阵！
	mat4 modified_model_view = VIEW_MATRIX * mat4(
		vec4(right * instance_scale, 0.0),
		vec4(up * instance_scale, 0.0),
		vec4(target_dir * instance_scale, 0.0),
		vec4(world_pos.x, center_y, world_pos.z, 1.0) 
	);
	// ==========================================
	
	MODELVIEW_MATRIX = modified_model_view;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);

	float grow_factor = smoothstep(0.05, 0.5, current_density); 
	VERTEX *= moss_scale * grow_factor;

	float wind = sin(TIME * sway_speed + world_pos.x * 5.0 + world_pos.z * 5.0) * sway_strength;
	VERTEX.x += wind * (1.0 - UV.y); 
}

void fragment() {
	vec4 tex = texture(moss_texture, UV);
	
	// ==========================================
	// 🗑️ 【已删除】：移除了之前的 Fake Root AO (根部变暗)
	// 直接使用最纯净的基础颜色作为底色
	// ==========================================
	vec3 base_albedo = moss_color.rgb; 
	
	// ✨【保留】：全局宏观色彩变异 (HSV)
	// 依然让高处的鼓包颜色变异/提亮，保留地貌的层次感
	vec3 hsv = rgb2hsv(base_albedo);
	float shift = v_noise;
	hsv.x = fract(hsv.x + shift * hue_variation);
	hsv.z += shift * value_variation;
	vec3 final_albedo = hsv2rgb(hsv);
	
	ALBEDO = tex.rgb * final_albedo;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5; 
	
	// ✨【保留】：材质物理属性，哑光吸光质感
	ROUGHNESS = 0.95; 
	SPECULAR = 0.0;   
	
	// ✨【保留】：植物专属光影魔法
	// 透光感 (Backlight) + 法线强制朝天 (柔和漫反射)
	BACKLIGHT = final_albedo * 0.8; 
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}