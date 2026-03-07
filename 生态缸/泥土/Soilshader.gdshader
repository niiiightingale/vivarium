shader_type spatial;

render_mode cull_back, depth_draw_opaque;

// ==========================================
// 1. 形状控制参数
// ==========================================
uniform float min_top_height : hint_range(0.0, 2.0) = 0.6;    // 顶面默认起始高度
uniform float min_bottom_height : hint_range(-1.0, 1.0) = 0.0; // 【新增】底面默认起始高度

uniform sampler2D height_map : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D moss_map;
uniform vec3 moss_color : source_color = vec3(0.1, 0.4, 0.05);
uniform float height_scale = 1.0;

uniform sampler2D bottom_shape_map : hint_default_black, filter_linear, repeat_disable;
uniform float bottom_scale = 0.5; 

const float physical_size = 5.0;  

// ==========================================
// 2. 独立的全局水分系统
// ==========================================
uniform float global_moisture : hint_range(0.0, 1.0) = 0.5; 

uniform vec3 color_dry_earth : source_color = vec3(0.4, 0.4, 0.35); 
uniform vec3 color_wet_mud : source_color = vec3(0.1, 0.08, 0.07);  
uniform vec3 color_puddle : source_color = vec3(0.01, 0.01, 0.02);  
uniform vec3 color_side_dirt : source_color = vec3(0.08, 0.06, 0.05);

uniform float roughness_dry_earth = 0.85; 
uniform float roughness_wet_mud = 0.3;    
uniform float roughness_puddle = 0.05;

// ==========================================
// 3. 法线贴图系统 
// ==========================================
uniform sampler2D top_normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float top_normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform vec2 top_uv_scale = vec2(1.0, 1.0); 

uniform sampler2D side_normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float side_normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform vec2 side_uv_scale = vec2(1.0, 1.0); 

varying vec3 v_normal;
varying vec3 v_world_pos; 

void vertex() {
    vec2 global_uv = (VERTEX.xz / physical_size) + 0.5;
    
    // 1. 【修改】底面目标高度 = 新增的底面默认高度 + 烘焙高度图起伏
    float target_bottom = min_bottom_height + (texture(bottom_shape_map, global_uv).r * bottom_scale);
    
    // 2. 顶面目标高度 = 顶面默认高度 + 笔刷隆起偏移
    float top_offset = texture(height_map, global_uv).r * height_scale;
    float target_top = min_top_height + top_offset; 
    
    // 3. 空间插值，让 BoxMesh 撑开在顶底之间
    float normalized_y = VERTEX.y + 0.5;
    VERTEX.y = mix(target_bottom, target_top, normalized_y);
    
    v_normal = NORMAL;
    v_world_pos = VERTEX; 
}

void fragment() {
    vec3 surface_color;
    float surface_roughness;
    
    if (global_moisture < 0.5) {
        float factor = global_moisture * 2.0;
        surface_color = mix(color_dry_earth, color_wet_mud, factor);
        surface_roughness = mix(roughness_dry_earth, roughness_wet_mud, factor);
    } else {
        float factor = (global_moisture - 0.5) * 2.0;
        surface_color = mix(color_wet_mud, color_puddle, factor);
        surface_roughness = mix(roughness_wet_mud, roughness_puddle, factor);
    }
    
    float is_top = smoothstep(0.4, 0.8, abs(v_normal.y));
    vec3 side_color = mix(color_dry_earth * 0.5, color_side_dirt, global_moisture);
    
    ALBEDO = mix(side_color, surface_color, is_top);
    ROUGHNESS = mix(0.9, surface_roughness, is_top);
    
    float current_metallic = mix(0.0, 0.1, max(0.0, (global_moisture - 0.5) * 2.0));
    METALLIC = mix(0.0, current_metallic, is_top);

    vec2 top_uv = ((v_world_pos.xz / physical_size) + 0.5) * top_uv_scale;

    vec3 abs_n = abs(v_normal);
    vec2 side_uv;
    if (abs_n.x > abs_n.z) {
        side_uv = v_world_pos.zy * side_uv_scale;
    } else {
        side_uv = v_world_pos.xy * side_uv_scale;
    }

    vec3 top_normal_tex = texture(top_normal_map, top_uv).rgb;
    vec3 side_normal_tex = texture(side_normal_map, side_uv).rgb;

    NORMAL_MAP = mix(side_normal_tex, top_normal_tex, is_top);
    NORMAL_MAP_DEPTH = mix(side_normal_scale, top_normal_scale, is_top);
}