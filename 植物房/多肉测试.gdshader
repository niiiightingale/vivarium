shader_type spatial;
// 关键修改：render_mode 移除了 diffuse_lambert_wrap，使用标准 diffuse_lambert，我们在 light() 中自己处理赛璐璐
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

// ==========================================
// 1. 基础多肉底色 (Instance)
// ==========================================
instance uniform vec3 color_base : source_color = vec3(0.20, 0.45, 0.25); 

// ==========================================
// 2. 表面亮面 (Rim Surface) 效果 (Instance)
// ==========================================
instance uniform vec3 color_rim_surface : source_color = vec3(0.80, 0.20, 0.15); 
instance uniform float rim_intensity : hint_range(0.0, 5.0) = 1.0; 
instance uniform float rim_threshold_start : hint_range(0.0, 1.0) = 0.0;
instance uniform float rim_threshold_end : hint_range(0.0, 1.0) = 0.1;

// ==========================================
// 3. 极尖端边缘 (Tip Edge) 效果 (Instance)
// ==========================================
instance uniform vec3 color_tip_edge : source_color = vec3(0.9, 0.8, 0.6);
instance uniform float tip_intensity : hint_range(0.0, 5.0) = 1.0; 
instance uniform float tip_threshold_start : hint_range(0.0, 1.0) = 0.8;
instance uniform float tip_threshold_end : hint_range(0.0, 1.0) = 1.0;

// ==========================================
// 4. 次表面散射 parameters (Instance)
// ==========================================
instance uniform vec3 sss_tint : source_color = vec3(0.80, 0.40, 0.20); 
instance uniform float sss_intensity : hint_range(0.0, 5.0) = 1.0;

// ==========================================
// 5. 赛璐璐着色新参数 (Instance)
// ==========================================
uniform float shadow_threshold : hint_range(-1.0, 1.0) = 0.0; // 阴影阈值
uniform vec3 shadow_color_tint : source_color = vec3(0.0, 0.0, 0.1); // 阴影的平和色调 (例如：加一点蓝)
uniform float cel_shadow_intensity : hint_range(0.0, 1.0) = 0.3; // 阴影区域的基础光照强度



varying float v_leaf_tip; 
// 关键修改：一个新的 Varying，用于控制 SSS 仅在叶子中部变强
varying float v_sss_mask;

void vertex() {
	// 仅保留 G 通道作为边缘掩膜
	v_leaf_tip = COLOR.g; 
	
	// 关键修改：SSS 掩膜
	// G 通道低表示叶子中部（更厚、更有质感），G 通道高表示尖端边缘（更薄、几乎透明）。
	// 我们希望 SSS 在尖端以外的中部更强。
	v_sss_mask = 1.0 - COLOR.g; // 这使得 SSS 在中部更强
}

void fragment() {
	vec3 current_albedo = color_base;
	
	// 应用表面亮面 (Rim Surface)
	float raw_rim_mask = smoothstep(rim_threshold_start, rim_threshold_end, v_leaf_tip);
	float rim_surface_mask = 1.0 - raw_rim_mask;
	float final_rim_weight = clamp(rim_surface_mask * rim_intensity, 0.0, 1.0);
	current_albedo = mix(current_albedo, color_rim_surface, final_rim_weight);
	
	// 应用极尖端边缘 (Tip Edge)
	float tip_edge_mask = smoothstep(tip_threshold_start, tip_threshold_end, v_leaf_tip);
	float final_tip_weight = clamp(tip_edge_mask * tip_intensity, 0.0, 1.0);
	ALBEDO = mix(current_albedo, color_tip_edge, final_tip_weight);
	
	SPECULAR = 0.0; // 这里是关键：移除了镜面高光
}

void light() {
	// --- 1. 计算标准兰伯特点积 (N·L) ---
	float dot_prod = dot(NORMAL, LIGHT);

	// --- 2. 实现硬边缘 (赛璐璐) 漫反射 ---
	// 使用 smoothstep 将平滑的 dot_prod 转换为硬边缘
	float cel_diffuse_mask = smoothstep(shadow_threshold, shadow_threshold, dot_prod);

	// --- 3. 组合漫反射光 ---
	// 定义阴影基础色调。
	vec3 light_energy = LIGHT_COLOR * ATTENUATION;
	vec3 shadow_base = (light_energy * cel_shadow_intensity) + (shadow_color_tint * ATTENUATION);
	
	// 根据掩膜组合
	DIFFUSE_LIGHT += mix(shadow_base, light_energy, cel_diffuse_mask);
	
	// --- 4. 优化 SSS ---
	// SSS 通常是后向光，但硬边缘阴影意味着 SSS 应与其对齐。
	// dot(-NORMAL, LIGHT) 是很好的。
	
	float subsurface = pow(max(0.0, dot(-NORMAL, LIGHT)), 1.5);
	vec3 final_sss_energy = subsurface * sss_tint * sss_intensity;

	// 使用 sss_mask。SSS 在尖端（G=1）将为 0，在中部（G=0）将为 1。
	// 这使得 SSS 不在硬边缘尖端出现，而是保留在叶子中部，
	// 从而与硬边缘漫反射和谐共存。
	SPECULAR_LIGHT += final_sss_energy * LIGHT_COLOR * ATTENUATION * v_sss_mask;
}