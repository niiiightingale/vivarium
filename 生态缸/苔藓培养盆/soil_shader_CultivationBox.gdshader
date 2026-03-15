shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// ==========================================
// 1. 形状与高度控制
// ==========================================
uniform float physical_size = 5.0;
uniform float min_top_height : hint_range(0.0, 2.0) = 0.6; 
uniform float min_bottom_height : hint_range(-1.0, 1.0) = 0.0; 

uniform sampler2D height_map : hint_default_black, filter_linear, repeat_disable;
uniform float height_scale = 1.0;

uniform sampler2D bottom_shape_map : hint_default_black, filter_linear, repeat_disable;
uniform float bottom_scale = 0.5; 

// 改成这样：

// ==========================================
// 2. 植被联动系统
// ==========================================
uniform sampler2D moss_map_0 : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D moss_map_1 : hint_default_black, filter_linear, repeat_disable;
uniform float moss_thickness : hint_range(0.0, 0.5) = 0.15;
uniform float moss_moisture_retention : hint_range(0.0, 1.0) = 0.4;

// ==========================================
// 3. 风格化泥土与法线系统 
// ==========================================
uniform vec3 color_dirt_light : source_color = vec3(0.45, 0.35, 0.25);
uniform vec3 color_dirt_dark : source_color = vec3(0.30, 0.22, 0.15);
// ✨ 新增：深层土壤的颜色（地下部分会越来越接近这个颜色）
uniform vec3 color_dirt_deep : source_color = vec3(0.12, 0.08, 0.05); 
uniform vec3 wet_color_multiplier : source_color = vec3(0.6, 0.5, 0.4);

uniform sampler2D dirt_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float noise_scale = 0.05; 

// ✨ 新增：地层拉伸参数（越小，侧面的泥土越有横向条纹感）
uniform float side_layer_stretch : hint_range(0.05, 1.0) = 0.15; 
// ✨ 新增：深度渐变的范围（多少米深的地方完全变成深色土）
uniform float depth_gradient_scale : hint_range(0.1, 5.0) = 1.0; 

uniform float macro_bump_intensity : hint_range(0.0, 5.0) = 1.0; 
uniform float micro_bump_intensity : hint_range(0.0, 10.0) = 1.5;

uniform float global_moisture : hint_range(0.0, 1.0) = 0.5; 

varying vec3 v_world_pos; 
varying float v_local_moisture; 
varying vec2 v_global_uv; 

// ==========================================
// 封装的全局函数：带地层拉伸的三向采样
// ==========================================
float get_triplanar_noise(sampler2D tex, vec3 pos, vec3 weights) {
    // 侧面(X和Z轴投影)强行压缩 Y 轴坐标，产生横向沉积层的拉伸感
    float n_x = texture(tex, vec2(pos.z, pos.y * side_layer_stretch)).r;
    float n_y = texture(tex, pos.xz).r; // 顶面保持正常
    float n_z = texture(tex, vec2(pos.x, pos.y * side_layer_stretch)).r;
    return n_x * weights.x + n_y * weights.y + n_z * weights.z;
}

void vertex() {
    vec2 global_uv = (VERTEX.xz / physical_size) + 0.5;
    v_global_uv = global_uv; 
    
    float target_bottom = min_bottom_height + (texture(bottom_shape_map, global_uv).r * bottom_scale);
    
    vec4 moss_data_0 = textureLod(moss_map_0, global_uv, 0.0);
    vec4 moss_data_1 = textureLod(moss_map_1, global_uv, 0.0);
    float total_moss = clamp(dot(moss_data_0, vec4(1.0)) + dot(moss_data_1, vec4(1.0)), 0.0, 1.0);
    
    float dynamic_soil_bump = total_moss * moss_thickness;
    float top_offset = texture(height_map, global_uv).r * height_scale;
    float target_top = min_top_height + top_offset + dynamic_soil_bump; 
    
    float normalized_y = VERTEX.y + 0.5;
    VERTEX.y = mix(target_bottom, target_top, normalized_y);
    
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_local_moisture = clamp(global_moisture + total_moss * moss_moisture_retention, 0.0, 1.0);
}

void fragment() {
    // ==========================================
    // 1. 智能法线系统 (区分顶面与侧面)
    // ==========================================
    // 获取模型真实的几何法线 (未经修改的原始朝向)
    vec3 geom_world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
    
    // 生成一个遮罩：朝上的面接近 1.0 (顶面)，朝侧面的面接近 0.0 (侧面剖面)
    float top_mask = smoothstep(0.1, 0.8, geom_world_normal.y);

    // 计算顶面的高度图宏观法线
    vec2 eps_macro = vec2(0.002, 0.0); 
    float hL = texture(height_map, v_global_uv - eps_macro.xy).r * height_scale;
    float hR = texture(height_map, v_global_uv + eps_macro.xy).r * height_scale;
    float hU = texture(height_map, v_global_uv - eps_macro.yx).r * height_scale;
    float hD = texture(height_map, v_global_uv + eps_macro.yx).r * height_scale;
    float dX_macro = (hR - hL) / (2.0 * eps_macro.x * physical_size) * macro_bump_intensity;
    float dZ_macro = (hD - hU) / (2.0 * eps_macro.x * physical_size) * macro_bump_intensity;
    vec3 top_macro_normal = normalize(vec3(-dX_macro, 1.0, -dZ_macro));

    // ✨ 核心混合：顶面用凹凸法线，侧面保留真实的几何法线（面向玻璃外）！
    vec3 macro_world_normal = normalize(mix(geom_world_normal, top_macro_normal, top_mask));

    vec3 blend_weights = abs(macro_world_normal);
    blend_weights = normalize(max(blend_weights - 0.2, vec3(0.0))); 
    blend_weights /= dot(blend_weights, vec3(1.0));

    // ==========================================
    // 2. 三向地层采样与深度渐变
    // ==========================================
    vec3 pos = v_world_pos * noise_scale;
    float noise_center = get_triplanar_noise(dirt_noise, pos, blend_weights);
    float noise_val = smoothstep(0.3, 0.7, noise_center);
    
    // ✨ 计算深度：越往下，颜色越深
    float depth = max(0.0, min_top_height - v_world_pos.y);
    float depth_ratio = clamp(depth / depth_gradient_scale, 0.0, 1.0);
    
    // 混合表层颜色和深层颜色
    vec3 current_base_color = mix(color_dirt_light, color_dirt_deep, depth_ratio);
    vec3 current_dark_color = mix(color_dirt_dark, color_dirt_deep * 0.5, depth_ratio);
    
    vec3 base_color = mix(current_dark_color, current_base_color, noise_val);
    vec3 final_albedo = mix(base_color, base_color * wet_color_multiplier, v_local_moisture);

    ALBEDO = final_albedo;
    ROUGHNESS = 0.95; 
    SPECULAR = 0.1;

    // ==========================================
    // 3. 真·3D 微观梯度法线
    // ==========================================
    float eps_micro = 0.01;
    
    float nX_val = get_triplanar_noise(dirt_noise, pos + vec3(eps_micro, 0.0, 0.0), blend_weights);
    float nY_val = get_triplanar_noise(dirt_noise, pos + vec3(0.0, eps_micro, 0.0), blend_weights);
    float nZ_val = get_triplanar_noise(dirt_noise, pos + vec3(0.0, 0.0, eps_micro), blend_weights);
    
    vec3 micro_world_grad = vec3(nX_val - noise_center, nY_val - noise_center, nZ_val - noise_center) / eps_micro * micro_bump_intensity;
    
    // 把微观凹凸融合到刚刚算好的宏观法线上
    vec3 final_world_normal = normalize(macro_world_normal - micro_world_grad * 0.1); 
    
    NORMAL = (VIEW_MATRIX * vec4(final_world_normal, 0.0)).xyz;
}