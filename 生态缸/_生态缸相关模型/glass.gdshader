shader_type spatial;

// 🚨 改动 1：在 render_mode 后面加上 ambient_light_disabled
// 这会强制玻璃忽略天空/世界的全局环境光染色，只接受聚光灯等直接光照
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx, ambient_light_disabled;

// --- 材质参数 ---
uniform vec4 glass_color : source_color = vec4(1.0, 1.0, 1.0, 0.05); 
uniform float roughness : hint_range(0.0, 1.0) = 0.15; 
uniform float metallic : hint_range(0.0, 1.0) = 0.0; 

// 🚨 改动 2：新增一个 specular（镜面反射）控制参数
uniform float specular_strength : hint_range(0.0, 1.0) = 0.1; // 默认调低，减少天空倒影

// --- 折射控制 ---
uniform float base_refraction_strength : hint_range(0.0, 1.0) = 0.005; 
uniform float edge_refraction_intensity : hint_range(0.0, 5.0) = 2.0; 

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
    // 1. 基础物理属性
    ROUGHNESS = roughness;
    METALLIC = metallic;
    
    // 🚨 改动 3：应用镜面反射强度
    // Godot 默认 Specular 是 0.5，调低它能极大地减少玻璃表面印上的天空颜色
    SPECULAR = specular_strength;
    
    // 2. 菲涅尔边缘检测
    float fresnel = pow(1.0 - dot(NORMAL, VIEW), 3.0);
    
    // 3. 计算折射UV偏移量
    float refraction_offset = base_refraction_strength + fresnel * edge_refraction_intensity * 0.1;
    vec2 sample_uv = SCREEN_UV - (NORMAL.xy * refraction_offset);
    
    // 4. 实现物理模糊
    vec3 refracted_bg = textureLod(screen_texture, sample_uv, ROUGHNESS * 8.0).rgb;
    
    // 5. 折射混合
    float ref_amount = 1.0 - glass_color.a;
    EMISSION = refracted_bg * ref_amount;
    ALBEDO = glass_color.rgb * (1.0 - ref_amount);
    
    // 终极防穿模
    ALPHA = 1.0;
}