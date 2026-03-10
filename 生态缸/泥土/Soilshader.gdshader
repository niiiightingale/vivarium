shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// ==========================================
// 1. 形状与高度控制
// ==========================================
uniform float min_top_height : hint_range(0.0, 2.0) = 0.6;    
uniform float min_bottom_height : hint_range(-1.0, 1.0) = 0.0; 

uniform sampler2D height_map : hint_default_black, filter_linear, repeat_disable;
uniform float height_scale = 1.0;

uniform sampler2D bottom_shape_map : hint_default_black, filter_linear, repeat_disable;
uniform float bottom_scale = 0.5; 

const float physical_size = 5.0;  

// ==========================================
// 2. 风格化地貌融合系统 (纯色块 + 噪波)
// ==========================================
uniform sampler2D moss_map : hint_default_black, filter_linear, repeat_disable;
uniform float moss_blend_softness : hint_range(0.1, 1.0) = 0.8;

// 4 种植物对泥土的实体顶起高度
uniform vec4 moss_soil_bump = vec4(0.1, 0.1, 0.05, 0.0);

// 鼓包与边缘破碎共用的全局噪波
uniform sampler2D clump_noise : hint_default_white, filter_linear, repeat_enable;
uniform vec4 clump_noise_scales = vec4(15.0, 80.0, 40.0, 10.0);
uniform float edge_break_scale : hint_range(1.0, 100.0) = 40.0;

// ✨ 恢复纯色面板：在这里直接调出你想要的童话/低面纸片风色彩！
uniform vec3 moss_color_1 : source_color = vec3(0.2, 0.4, 0.1);  
uniform vec3 moss_color_2 : source_color = vec3(0.4, 0.35, 0.1); 
uniform vec3 moss_color_3 : source_color = vec3(0.1, 0.2, 0.3);  
uniform vec3 moss_color_4 : source_color = vec3(0.3, 0.3, 0.3);  

// ==========================================
// 3. 全局水分与物理泥土底盘系统
// ==========================================
uniform float global_moisture : hint_range(0.0, 1.0) = 0.5; 

uniform vec3 color_dry_earth : source_color = vec3(0.4, 0.4, 0.35); 
uniform vec3 color_wet_mud : source_color = vec3(0.1, 0.08, 0.07);  
uniform vec3 color_puddle : source_color = vec3(0.01, 0.01, 0.02);  
uniform vec3 color_side_dirt : source_color = vec3(0.08, 0.06, 0.05);

uniform float roughness_dry_earth = 0.85; 
uniform float roughness_wet_mud = 0.3;    
uniform float roughness_puddle = 0.05;

// 泥土本身的法线贴图保留，用于增加泥土的颗粒感
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
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	float target_bottom = min_bottom_height + (texture(bottom_shape_map, global_uv).r * bottom_scale);
	
	vec4 moss_data = textureLod(moss_map, global_uv, 0.0);
	
	vec4 noises;
	noises.r = textureLod(clump_noise, (world_pos.xz / clump_noise_scales.r) + 0.5, 0.0).r;
	noises.g = textureLod(clump_noise, (world_pos.xz / clump_noise_scales.g) + 0.5, 0.0).r;
	noises.b = textureLod(clump_noise, (world_pos.xz / clump_noise_scales.b) + 0.5, 0.0).r;
	noises.a = textureLod(clump_noise, (world_pos.xz / clump_noise_scales.a) + 0.5, 0.0).r;
	
	vec4 dynamic_bumps = moss_soil_bump * noises;
	float dynamic_soil_bump = dot(moss_data, dynamic_bumps);
	
	float top_offset = texture(height_map, global_uv).r * height_scale;
	float target_top = min_top_height + top_offset + dynamic_soil_bump; 
	
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
    
    vec2 base_uv = (v_world_pos.xz / physical_size) + 0.5;
    vec4 moss_data = texture(moss_map, base_uv);
    
    float edge_noise_val = texture(clump_noise, v_world_pos.xz / edge_break_scale).r;
    
    float base_total_moss = clamp(moss_data.r + moss_data.g + moss_data.b + moss_data.a, 0.0, 1.0);
    float organic_moss = clamp(base_total_moss - (edge_noise_val * 0.4), 0.0, 1.0); 
    
    vec3 mixed_moss_color = surface_color;
    if (organic_moss > 0.001) {
        mixed_moss_color = (
            moss_color_1 * moss_data.r +
            moss_color_2 * moss_data.g +
            moss_color_3 * moss_data.b +
            moss_color_4 * moss_data.a
        ) / (moss_data.r + moss_data.g + moss_data.b + moss_data.a);
    }
    
    float moss_factor = smoothstep(0.0, moss_blend_softness, organic_moss); 
    
    vec3 top_final_color = mix(surface_color, mixed_moss_color, moss_factor);
    float top_final_roughness = mix(surface_roughness, 0.9, moss_factor);
    float final_top_normal_scale = mix(top_normal_scale, top_normal_scale * 0.5, moss_factor);

    float is_top = smoothstep(0.4, 0.8, abs(v_normal.y));
    vec3 side_color = mix(color_dry_earth * 0.5, color_side_dirt, global_moisture);
    
    ALBEDO = mix(side_color, top_final_color, is_top);
    ROUGHNESS = mix(0.9, top_final_roughness, is_top);
    
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
    NORMAL_MAP_DEPTH = mix(side_normal_scale, final_top_normal_scale, is_top);
}