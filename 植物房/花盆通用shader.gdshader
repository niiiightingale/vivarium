shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

// ==========================================
// 1. Instance 级别参数 (仅限每个实例必须差异化的数据)
// ==========================================
instance uniform vec3 color_pot_albedo : source_color = vec3(0.9, 0.4, 0.2); 
instance uniform vec3 shadow_color_tint : source_color = vec3(0.0, 0.0, 0.1); 

// ==========================================
// 2. Material 级别参数 (材质全局共享，避免实例内存对齐冲突)
// ==========================================
uniform float shadow_threshold : hint_range(-1.0, 1.0) = 0.0; 
uniform float edge_softness : hint_range(0.0, 0.1) = 0.01; 
uniform float cel_shadow_intensity : hint_range(0.0, 1.0) = 0.3; 

void vertex() {
    // 置空，无需处理颜色通道
}

void fragment() {
    ALBEDO = color_pot_albedo;
    
    // 硬编码质感，剔除无用的 roughness 变量
    ROUGHNESS = 1.0; 
    SPECULAR = 0.0; 
}

void light() {
    float dot_prod = dot(NORMAL, LIGHT);

    float cel_diffuse_mask = smoothstep(shadow_threshold - edge_softness, shadow_threshold + edge_softness, dot_prod);

    vec3 light_energy = LIGHT_COLOR * ATTENUATION;
    vec3 shadow_base = (light_energy * cel_shadow_intensity) + (shadow_color_tint * ATTENUATION);
    
    DIFFUSE_LIGHT += mix(shadow_base, light_energy, cel_diffuse_mask);
}