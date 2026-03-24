shader_type spatial;
// 彻底禁用物理高光，保持极致的赛璐璐平面感
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

// ==========================================
// 1. Instance 变量区 (按实例分配内存，必须与描边着色器严格同步)
// ==========================================
instance uniform vec3 color_base : source_color = vec3(0.8, 0.8, 0.8);
instance uniform vec3 shadow_color_tint : source_color = vec3(0.15, 0.15, 0.25);

// ==========================================
// 2. Material 变量区 (材质全局共享，无内存对齐风险)
// ==========================================
uniform int shadow_layers : hint_range(2, 5) = 2; 
uniform float shadow_threshold : hint_range(-1.0, 1.0) = 0.0; 
uniform float cel_shadow_intensity : hint_range(0.0, 1.0) = 0.3; 

void fragment() {
    // 直接输出实例的基础颜色
    ALBEDO = color_base;
}

void light() {
    float dot_prod = dot(NORMAL, LIGHT);
    float smooth_light = clamp((dot_prod + 1.0) * 0.5 + shadow_threshold, 0.0, 1.0);

    // 离散化生成阶梯阴影
    float steps = float(shadow_layers);
    float cel_diffuse_mask = floor(smooth_light * steps) / max(1.0, steps - 1.0);
    cel_diffuse_mask = clamp(cel_diffuse_mask, 0.0, 1.0);

    // 混合基础光与阴影色调
    vec3 light_energy = LIGHT_COLOR * ATTENUATION;
    vec3 shadow_base = (light_energy * cel_shadow_intensity) + (shadow_color_tint * ATTENUATION);
    
    DIFFUSE_LIGHT += mix(shadow_base, light_energy, cel_diffuse_mask);
}