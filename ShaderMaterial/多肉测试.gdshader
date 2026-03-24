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
uniform int shadow_layers : hint_range(2, 5) = 2; // 阴影层数 (2层即1明1暗，3层即1明1灰1暗)
uniform float shadow_threshold : hint_range(-1.0, 1.0) = 0.0; // 整体阴影偏移阈值
uniform vec3 shadow_color_tint : source_color = vec3(0.0, 0.0, 0.1); // 最底层的平和色调
uniform float cel_shadow_intensity : hint_range(0.0, 1.0) = 0.3; // 最底层的光照强度



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
	// --- 1. 计算基础光照映射 ---
	float dot_prod = dot(NORMAL, LIGHT);
	
	// 将 -1 到 1 的点乘，映射到 0 到 1 的空间，并加上你的偏移阈值
	float smooth_light = clamp((dot_prod + 1.0) * 0.5 + shadow_threshold, 0.0, 1.0);

	// --- 2. 核心逻辑：离散化 (Quantization) 生成阶梯 ---
	// 减 1 是因为：如果是 3 层颜色，实际上只有 2 个过渡台阶
	float steps = float(max(1, shadow_layers - 1)); 
	
	// 乘以台阶数 -> 向下取整抹平 -> 除以台阶数归一化
	// + 0.001 是为了防止浮点数精度误差导致最高亮度 (1.0) 被错误归入下一级
	float cel_diffuse_mask = floor(smooth_light * (steps + 0.001)) / steps;

	// --- 3. 组合漫反射光 ---
	// 定义最底层的阴影基础色调
	vec3 light_energy = LIGHT_COLOR * ATTENUATION;
	vec3 shadow_base = (light_energy * cel_shadow_intensity) + (shadow_color_tint * ATTENUATION);
	
	// 这里的 mix 会根据阶梯 mask 自动混合。
	// 如果 mask 是 0.5，它会输出介于 shadow_base 和 light_energy 之间绝对中间的颜色。
	DIFFUSE_LIGHT += mix(shadow_base, light_energy, cel_diffuse_mask);
	
	// --- 4. 优化 SSS ---
	float subsurface = pow(max(0.0, dot(-NORMAL, LIGHT)), 1.5);
	vec3 final_sss_energy = subsurface * sss_tint * sss_intensity;
	SPECULAR_LIGHT += final_sss_energy * LIGHT_COLOR * ATTENUATION * v_sss_mask;
}