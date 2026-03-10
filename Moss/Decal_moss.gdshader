shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// ==========================================
// 1. 同步泥土的起伏参数
// ==========================================
uniform float min_top_height : hint_range(0.0, 2.0) = 0.6;    
uniform sampler2D height_map : hint_default_black, filter_linear, repeat_disable;
uniform float height_scale = 1.0;
const float physical_size = 5.0;  

uniform sampler2D moss_map : hint_default_black, filter_linear, repeat_disable;
uniform vec4 moss_soil_bump = vec4(0.1, 0.1, 0.05, 0.0);
uniform sampler2D clump_noise : hint_default_white, filter_linear, repeat_enable;
uniform vec4 clump_noise_scales = vec4(15.0, 80.0, 40.0, 10.0);

// ==========================================
// 2. 🌸 贴花参数
// ==========================================
uniform vec3 moss_color : source_color = vec3(1.0, 1.0, 1.0);
uniform sampler2D moss_texture : source_color, filter_linear_mipmap;

uniform float moss_scale : hint_range(0.1, 5.0) = 0.83; 
uniform float layer_y_offset : hint_range(0.0, 0.5) = 0.02; 
uniform float spawn_density : hint_range(0.0, 1.0) = 1.0; 

// ✨ 【新增核心】：悬崖剔除角度！(0度=只能长在纯平的地上，90度=垂直悬崖也能长)
uniform float max_slope_degree : hint_range(0.0, 90.0) = 45.0; 
uniform float steepness_scale_boost : hint_range(0.0, 2.0) = 0.0; // 缓坡膨胀补偿 (不需要可保持0)

uniform float sway_speed : hint_range(0.0, 5.0) = 0.32;
uniform float sway_strength : hint_range(0.0, 0.1) = 0.015;

// ==========================================
// 3. 核心高度读取与随机函数
// ==========================================
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float get_terrain_height(vec2 pos_xz) {
    vec2 global_uv = (pos_xz / physical_size) + 0.5;
    vec4 m_data = textureLod(moss_map, global_uv, 0.0);
    vec4 noises;
    noises.r = textureLod(clump_noise, (pos_xz / clump_noise_scales.r) + 0.5, 0.0).r;
    noises.g = textureLod(clump_noise, (pos_xz / clump_noise_scales.g) + 0.5, 0.0).r;
    noises.b = textureLod(clump_noise, (pos_xz / clump_noise_scales.b) + 0.5, 0.0).r;
    noises.a = textureLod(clump_noise, (pos_xz / clump_noise_scales.a) + 0.5, 0.0).r;
    
    float dynamic_soil_bump = dot(m_data, moss_soil_bump * noises);
    float top_offset = textureLod(height_map, global_uv, 0.0).r * height_scale;
    return min_top_height + top_offset + dynamic_soil_bump;
}

void vertex() {
    vec3 instance_center = MODEL_MATRIX[3].xyz;
    
    float random_spawn = hash(instance_center.xz * 135.246);
    if (random_spawn > spawn_density) {
        VERTEX = vec3(0.0);
    } else {
        // 1. 获取中心点高度与精确法线
        float center_h = get_terrain_height(instance_center.xz);
        
        vec2 e = vec2(0.05, 0.0);
        float h_L = get_terrain_height(instance_center.xz - e.xy);
        float h_R = get_terrain_height(instance_center.xz + e.xy);
        float h_D = get_terrain_height(instance_center.xz - e.yx);
        float h_U = get_terrain_height(instance_center.xz + e.yx);
        vec3 center_normal = normalize(vec3(h_L - h_R, 2.0 * e.x, h_D - h_U));
        
        // ==========================================
        // ✨ 核心逻辑：悬崖角度剔除
        // ==========================================
        // 解析法线，算出当前地块的物理倾斜角度（度数）
        float current_slope_degree = degrees(acos(center_normal.y));
        
        // 如果脚下的坡度，大于你设定的最大忍受角度，这根草当场死亡（剔除）
        if (current_slope_degree > max_slope_degree) {
            VERTEX = vec3(0.0);
        } else {
            // 2. 完美修复的旋转矩阵！
            vec3 up_dir = vec3(0.0, 1.0, 0.0);
            vec3 axis = cross(up_dir, center_normal);
            mat3 tilt_mat = mat3(1.0); 
            
            if (length(axis) > 0.0001) {
                axis = normalize(axis);
                float s = length(cross(up_dir, center_normal));
                float c = dot(up_dir, center_normal);
                float oc = 1.0 - c;
                float x = axis.x; float y = axis.y; float z = axis.z;
                
                tilt_mat = mat3(
                    vec3(c + x*x*oc,     y*x*oc + z*s,   z*x*oc - y*s),
                    vec3(x*y*oc - z*s,   c + y*y*oc,     z*y*oc + x*s),
                    vec3(x*z*oc + y*s,   y*z*oc - x*s,   c + z*z*oc)
                );
            }
            
            // 3. 缓坡膨胀补偿 
            float scale_boost = mix(1.0, 1.0 / max(center_normal.y, 0.3), steepness_scale_boost);
            vec3 local_pos = VERTEX * moss_scale * scale_boost;
            
            // 4. 风吹动画
            vec3 pseudo_world = instance_center + local_pos;
            float wind = sin(TIME * sway_speed + pseudo_world.x * 5.0 + pseudo_world.z * 5.0) * sway_strength;
            local_pos.x += wind;
            local_pos.z += wind;
            
            // 5. 将坐标系交给矩阵并旋转贴合
            vec3 world_offset = (MODEL_MATRIX * vec4(local_pos, 0.0)).xyz;
            world_offset = tilt_mat * world_offset; 
            
            // 6. 最终高度定位 (带防闪烁层级)
            vec3 final_world_pos = instance_center;
            float random_micro_offset = hash(instance_center.xz) * 0.015;
            final_world_pos.y = center_h + layer_y_offset + random_micro_offset;
            final_world_pos += world_offset;
            
            // 7. 转回渲染管线！完美赋上地形的法线
            VERTEX = (inverse(MODEL_MATRIX) * vec4(final_world_pos, 1.0)).xyz;
            NORMAL = (inverse(MODEL_MATRIX) * vec4(center_normal, 0.0)).xyz;
        }
    }
}

void fragment() {
    vec4 tex = texture(moss_texture, UV);
    
    ALBEDO = tex.rgb * moss_color;
    ALPHA = tex.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5; 
    
    ROUGHNESS = 0.95; 
    SPECULAR = 0.0;   
}