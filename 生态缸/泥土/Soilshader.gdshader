shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// ==========================================
// 1. 形状与高度控制 (完美咬合苔藓)
// ==========================================
uniform float min_top_height : hint_range(0.0, 2.0) = 0.6;    
uniform float min_bottom_height : hint_range(-1.0, 1.0) = 0.0; 

uniform sampler2D height_map : hint_default_black, filter_linear, repeat_disable;
uniform float height_scale = 1.0;

uniform sampler2D bottom_shape_map : hint_default_black, filter_linear, repeat_disable;
uniform float bottom_scale = 0.5; 

const float physical_size = 5.0;  

// ==========================================
// 2. 植被联动系统 (厚度隆起 + 保水变湿)
// ==========================================
uniform sampler2D moss_map_0 : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D moss_map_1 : hint_default_black, filter_linear, repeat_disable;
uniform float moss_thickness : hint_range(0.0, 0.5) = 0.15;
uniform float moss_moisture_retention : hint_range(0.0, 1.0) = 0.4;
// ✨ 新增：暴露给面板的植物底部阴影颜色！
uniform vec3 moss_ao_color : source_color = vec3(0.15, 0.2, 0.15);
uniform float moss_ao_threshold : hint_range(0.01, 1.0) = 0.15;

// ==========================================
// 3. 极简干湿泥土系统 (只有干与湿！)
// ==========================================
uniform float global_moisture : hint_range(0.0, 1.0) = 0.5; 

uniform vec3 color_dry_earth : source_color = vec3(0.4, 0.4, 0.35); 
uniform vec3 color_wet_mud : source_color = vec3(0.1, 0.08, 0.07);  

uniform float roughness_dry_earth = 0.85; 
uniform float roughness_wet_mud = 0.3;    

// ==========================================
// 4. 三向贴图 (Triplanar) 法线系统
// ==========================================
uniform sampler2D top_normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float top_normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform vec2 top_uv_scale = vec2(1.0, 1.0); 

uniform sampler2D side_normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float side_normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform vec2 side_uv_scale = vec2(1.0, 1.0); 

// ==========================================
// 传递给片元的变量 (Varyings)
// ==========================================
varying vec3 v_normal;
varying vec3 v_world_pos; 
varying float v_local_moisture; 
// ✨ 新增的快递员：安全运送世界对齐的 UV 坐标！
varying vec2 v_global_uv; 

void vertex() {
    vec2 global_uv = (VERTEX.xz / physical_size) + 0.5;
    
    // ✨ 把算好的绝对坐标交给快递员
    v_global_uv = global_uv; 
    
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
    float target_bottom = min_bottom_height + (texture(bottom_shape_map, global_uv).r * bottom_scale);
    
    vec4 moss_data_0 = textureLod(moss_map_0, global_uv, 0.0);
    vec4 moss_data_1 = textureLod(moss_map_1, global_uv, 0.0);
    float total_moss = clamp(
        (moss_data_0.r + moss_data_0.g + moss_data_0.b + moss_data_0.a) + 
        (moss_data_1.r + moss_data_1.g + moss_data_1.b + moss_data_1.a), 
        0.0, 1.0
    );
    
    float dynamic_soil_bump = total_moss * moss_thickness;
    
    float top_offset = texture(height_map, global_uv).r * height_scale;
    float target_top = min_top_height + top_offset + dynamic_soil_bump; 
    
    float normalized_y = VERTEX.y + 0.5;
    VERTEX.y = mix(target_bottom, target_top, normalized_y);
    
    v_local_moisture = clamp(global_moisture + total_moss * moss_moisture_retention, 0.0, 1.0);
    
    v_normal = NORMAL;
    v_world_pos = VERTEX; 
}

void fragment() {
    vec3 surface_color = mix(color_dry_earth, color_wet_mud, v_local_moisture);
    float surface_roughness = mix(roughness_dry_earth, roughness_wet_mud, v_local_moisture);

    float is_top = smoothstep(0.4, 0.8, abs(v_normal.y));
    vec3 side_color = surface_color * 0.85; 
    
    ALBEDO = mix(side_color, surface_color, is_top);
    ROUGHNESS = surface_roughness; 
    METALLIC = mix(0.0, 0.15, smoothstep(0.7, 1.0, v_local_moisture)); 

    vec3 blend_weights = abs(v_normal);
    blend_weights = max(blend_weights - 0.2, 0.0); 
    blend_weights /= (blend_weights.x + blend_weights.y + blend_weights.z); 

    vec2 uv_x = v_world_pos.zy * side_uv_scale;
    vec2 uv_y = v_world_pos.xz * top_uv_scale;
    vec2 uv_z = v_world_pos.xy * side_uv_scale;

    vec3 tex_x = texture(side_normal_map, uv_x).rgb;
    vec3 tex_y = texture(top_normal_map, uv_y).rgb;
    vec3 tex_z = texture(side_normal_map, uv_z).rgb;

    vec3 triplanar_normal = tex_x * blend_weights.x + tex_y * blend_weights.y + tex_z * blend_weights.z;
    float triplanar_scale = side_normal_scale * blend_weights.x + top_normal_scale * blend_weights.y + side_normal_scale * blend_weights.z;
    
    NORMAL_MAP = triplanar_normal;
    NORMAL_MAP_DEPTH = triplanar_scale;

    // ✨ Fake AO (伪环境光遮蔽)
    // ==========================================
    vec4 moss_0 = texture(moss_map_0, v_global_uv);
    vec4 moss_1 = texture(moss_map_1, v_global_uv);
    
    float total_moss = clamp(
        dot(moss_0, vec4(1.0)) + dot(moss_1, vec4(1.0)), 
        0.0, 1.0
    );
    
    // 🚨 核心改动：用 smoothstep 把线性的苔藓浓度“拔苗助长”！
    // 意思：当浓度从 0 涨到 moss_ao_threshold (比如 0.15) 时，ao_weight 就已经从 0 飙升到 1 了！
    // 这样即便浓度只有 0.15 的稀疏苔藓，也能拥有 100% 的深色底座！
    float ao_weight = smoothstep(0.0, moss_ao_threshold, total_moss);
    
    // 这里不再用 total_moss，而是用算好的 ao_weight
    vec3 fake_ao = mix(vec3(1.0), moss_ao_color, ao_weight);
    
    ALBEDO = ALBEDO * fake_ao; 
    // 粗糙度保持原样，用线性的 total_moss 比较自然
    ROUGHNESS = mix(ROUGHNESS, 1.0, total_moss);
}