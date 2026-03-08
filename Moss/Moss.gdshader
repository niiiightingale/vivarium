shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform vec4 moss_color : source_color = vec4(0.3, 0.6, 0.2, 1.0);
uniform sampler2D moss_texture : source_color, filter_nearest;
uniform float moss_scale = 1.0;
uniform float sway_speed = 2.0;
uniform float sway_strength = 0.05;

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
uniform vec4 clump_noise_scales = vec4(15.0, 80.0, 40.0, 10.0);
// ✨ 必须和泥土 Shader 里的参数保持绝对一致！
uniform vec4 moss_soil_bump = vec4(0.3, 0.1, 0.05, 0.0);

uniform float hue_variation : hint_range(0.0, 0.05) = 0.015;   
// 【修改】：默认值设为 0.02，极其克制的光影变化
uniform float value_variation : hint_range(0.0, 0.2) = 0.02; 

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
	
	// ==========================================
	// ✨ 【完全同步】：计算泥土底盘的真实混合高度
	// ==========================================
	vec4 noises;
	noises.r = textureLod(clump_noise, (world_pos.xz / clump_noise_scales.r) + 0.5, 0.0).r;
	noises.g = textureLod(clump_noise, (world_pos.xz / clump_noise_scales.g) + 0.5, 0.0).r;
	noises.b = textureLod(clump_noise, (world_pos.xz / clump_noise_scales.b) + 0.5, 0.0).r;
	noises.a = textureLod(clump_noise, (world_pos.xz / clump_noise_scales.a) + 0.5, 0.0).r;
	
	vec4 dynamic_bumps = moss_soil_bump * noises;
	float dynamic_soil_bump = dot(tex_color, dynamic_bumps);
	
	// ✨ 【提取私有数据】：利用通道掩码，提取当前植物专属的噪波，传递给 fragment 算颜色变异！
	// 如果当前是 1号草(R通道)，v_noise 就等于 noises.r！
	v_noise = dot(noises, channel_mask);
	
	float soil_h = texture(height_map, global_uv).r * height_scale + min_top_height;
	float center_y = soil_h + dynamic_soil_bump + elevation_offset;

	float instance_scale = length(MODEL_MATRIX[0].xyz);
	
	mat4 modified_model_view = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * instance_scale,
		INV_VIEW_MATRIX[1] * instance_scale,
		INV_VIEW_MATRIX[2] * instance_scale,
		vec4(world_pos.x, center_y, world_pos.z, 1.0) 
	);
	
	MODELVIEW_MATRIX = modified_model_view;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);

	float grow_factor = smoothstep(0.05, 0.5, current_density); 
	
	VERTEX *= moss_scale * grow_factor;

	float wind = sin(TIME * sway_speed + world_pos.x * 5.0 + world_pos.z * 5.0) * sway_strength;
	VERTEX.x += wind * (1.0 - UV.y); 
}

void fragment() {
	vec4 tex = texture(moss_texture, UV);
	
	vec3 ao_color = moss_color.rgb * 0.4; 
	float camera_down_factor = abs(INV_VIEW_MATRIX[2].y);
	float ao_intensity = 1.0 - smoothstep(0.2, 0.7, camera_down_factor);
	float root_ao_factor = smoothstep(0.4, 1.0, UV.y) * ao_intensity; 
	vec3 base_albedo = mix(moss_color.rgb, ao_color, root_ao_factor);
	
	vec3 hsv = rgb2hsv(base_albedo);
	
	// ==========================================
	// ✨【纯净色彩】：底层原色，高处高亮！
	// 直接使用 0.0~1.0 的 v_noise 作为 shift。
	// ==========================================
	float shift = v_noise;
	
	// 底面 (shift=0) 保持原色原亮度；包顶 (shift=1) 会发生最强烈的色彩偏移和提亮！
	hsv.x = fract(hsv.x + shift * hue_variation);
	hsv.z += shift * value_variation;
	
	vec3 final_albedo = hsv2rgb(hsv);
	
	ALBEDO = tex.rgb * final_albedo;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5; 
}