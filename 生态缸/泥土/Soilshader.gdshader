shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// ==========================================
// 1. 形状与高度控制 (完美咬合苔藓与盆底)
// ==========================================
uniform float min_top_height : hint_range(0.0, 2.0) = 0.6; 
uniform float min_bottom_height : hint_range(-1.0, 1.0) = 0.0; 

uniform sampler2D height_map : hint_default_black, filter_linear, repeat_disable;
uniform float height_scale = 1.0;

uniform sampler2D bottom_shape_map : hint_default_black, filter_linear, repeat_disable;
uniform float bottom_scale = 0.5; 

const float physical_size = 5.0;  

// ==========================================
// 2. 植被联动系统 (厚度隆起 + 锁水功能)
// ==========================================
uniform sampler2D moss_map_0 : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D moss_map_1 : hint_default_black, filter_linear, repeat_disable;
uniform float moss_thickness : hint_range(0.0, 0.5) = 0.15;
uniform float moss_moisture_retention : hint_range(0.0, 1.0) = 0.4;

uniform vec3 moss_ao_color : source_color = vec3(0.15, 0.2, 0.15);
uniform float moss_ao_threshold : hint_range(0.01, 1.0) = 0.15; 

// ==========================================
// 3. 风格化泥土与实时推导法线系统 
// ==========================================
uniform vec3 color_dirt_light : source_color = vec3(0.45, 0.35, 0.25);
uniform vec3 color_dirt_dark : source_color = vec3(0.30, 0.22, 0.15);
uniform vec3 wet_color_multiplier : source_color = vec3(0.6, 0.5, 0.4);

uniform sampler2D dirt_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float noise_scale = 0.05; 
uniform float bump_intensity : hint_range(0.0, 10.0) = 2.0;

// 全局湿度
uniform float global_moisture : hint_range(0.0, 1.0) = 0.5; 

// ==========================================
// 传递给片元的变量 (Varyings)
// ==========================================
varying vec3 v_world_pos; 
varying float v_local_moisture; 
varying vec2 v_global_uv; 

void vertex() {
    vec2 global_uv = (VERTEX.xz / physical_size) + 0.5;
    v_global_uv = global_uv; 
    
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_world_pos = world_pos;
    
    float target_bottom = min_bottom_height + (texture(bottom_shape_map, global_uv).r * bottom_scale);
    
    // 获取宏观植被密度
    vec4 moss_data_0 = textureLod(moss_map_0, global_uv, 0.0);
    vec4 moss_data_1 = textureLod(moss_map_1, global_uv, 0.0);
    float total_moss = clamp(
        dot(moss_data_0, vec4(1.0)) + dot(moss_data_1, vec4(1.0)), 
        0.0, 1.0
    );
    
    float dynamic_soil_bump = total_moss * moss_thickness;
    float top_offset = texture(height_map, global_uv).r * height_scale;
    float target_top = min_top_height + top_offset + dynamic_soil_bump; 
    
    float normalized_y = VERTEX.y + 0.5;
    VERTEX.y = mix(target_bottom, target_top, normalized_y);
    
    v_local_moisture = clamp(global_moisture + total_moss * moss_moisture_retention, 0.0, 1.0);
}

void fragment() {
    vec2 noise_uv = v_world_pos.xz * noise_scale;
    float noise_val = smoothstep(0.3, 0.7, texture(dirt_noise, noise_uv).r);

    // 1. 颜色与干湿混合
    vec3 base_dirt_color = mix(color_dirt_dark, color_dirt_light, noise_val);
    vec3 wet_dirt_color = base_dirt_color * wet_color_multiplier;
    vec3 final_albedo = mix(base_dirt_color, wet_dirt_color, v_local_moisture);

    ALBEDO = final_albedo;
    ROUGHNESS = 0.95; 
    SPECULAR = 0.1;

    // 2. 实时推导法线
    vec2 eps = vec2(0.002, 0.0); 
    float h_left  = texture(dirt_noise, noise_uv - eps.xy).r;
    float h_right = texture(dirt_noise, noise_uv + eps.xy).r;
    float h_up    = texture(dirt_noise, noise_uv - eps.yx).r;
    float h_down  = texture(dirt_noise, noise_uv + eps.yx).r;
    
    float dX = (h_right - h_left) * bump_intensity;
    float dY = (h_down - h_up) * bump_intensity;
    
    vec3 generated_normal = normalize(vec3(-dX, -dY, 1.0));
    NORMAL_MAP = generated_normal * 0.5 + 0.5;

    // ==========================================
    // 3. 经典纯净版 Fake AO (大色块晕染)
    // ==========================================
    vec4 moss_0 = texture(moss_map_0, v_global_uv);
    vec4 moss_1 = texture(moss_map_1, v_global_uv);
    
    float total_moss = clamp(
        dot(moss_0, vec4(1.0)) + dot(moss_1, vec4(1.0)), 
        0.0, 1.0
    );
    
    float ao_weight = smoothstep(0.0, moss_ao_threshold, total_moss);
    vec3 fake_ao = mix(vec3(1.0), moss_ao_color, ao_weight);
    
    ALBEDO = ALBEDO * fake_ao; 
}