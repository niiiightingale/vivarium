shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// ==========================================
// 🌸 基础色彩与明暗系统 (Color & Shading)
// ==========================================
uniform sampler2D height_gradient : source_color, filter_linear; 
uniform sampler2D dry_gradient : source_color, filter_linear;    

uniform sampler2D vertical_shade_curve : hint_default_white, filter_linear; 
uniform float mesh_original_height = 1.0; 

// ==========================================
// 🌟 边缘绒毛发光 (Fresnel Fuzz)
// ==========================================
// 🌟 边缘绒毛发光 (Fresnel Fuzz) 参数
// 请将这些放到 shader 顶部的 uniform 声明区域
// ==========================================
uniform vec3 fuzz_color : source_color = vec3(0.6, 0.95, 0.1); 
uniform float fuzz_intensity : hint_range(0.0, 5.0) = 1.5;

// ✨ 新增：精确控制菲涅尔发光的角度阈值
uniform float fuzz_start : hint_range(0.0, 1.0) = 0.5;       // 正对视线时不发光的“死区”范围
uniform float fuzz_smoothness : hint_range(0.01, 1.0) = 0.3; // 边缘发光过渡的柔和度

// ✨ 新增：控制发光的高度范围 (利用 mesh_original_height 算出的 v_local_height_ratio)
uniform float fuzz_mask_bottom : hint_range(0.0, 1.0) = 0.4; // 从多高开始出现发光
uniform float fuzz_mask_top : hint_range(0.0, 1.0) = 1.0;    // 到多高达到最大发光强度

// ==========================================
// 📏 缩放与变形曲线
// ==========================================
uniform sampler2D size_curve : hint_default_white, filter_linear; 
uniform sampler2D offset_curve : hint_default_white, filter_linear; 
uniform float terrain_align_strength : hint_range(0.0, 1.0) = 0.3;

uniform float moss_scale = 1.0;
uniform float sway_speed = 2.0;
uniform float sway_strength = 0.05;

uniform float hydration : hint_range(0.0, 1.0) = 1.0; 
uniform float puff_height : hint_range(0.0, 1.0) = 0.15; 

// ==========================================
// 🥞 千层厚涂与密度控制
// ==========================================
uniform float elevation_offset : hint_range(0.0, 2.0) = 0.8; 
uniform float micro_y_variance : hint_range(0.0, 0.5) = 0.05; 
uniform float spawn_density : hint_range(0.0, 1.0) = 1.0;     
uniform float max_slope_degree : hint_range(0.0, 90.0) = 45.0; 

// ==========================================
// ⛰️ 地形锚定
// ==========================================
uniform float physical_size = 5.0;
uniform float height_scale = 1.0;
uniform sampler2D height_map : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D moss_density_map : hint_default_black, filter_linear, repeat_disable;
uniform vec4 channel_mask = vec4(1.0, 0.0, 0.0, 0.0);
uniform float moss_thickness : hint_range(0.0, 0.5) = 0.15; 

// ==========================================
// 🛠️ 工具函数
// ==========================================
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float get_terrain_height(vec2 pos_xz) {
    vec2 global_uv = (pos_xz / physical_size) + 0.5;
    float soil_h = textureLod(height_map, global_uv, 0.0).r * height_scale;
    float density = dot(textureLod(moss_density_map, global_uv, 0.0), channel_mask);
    return soil_h + density * moss_thickness;
}

// ==========================================
// 传递给片元的变量
// ==========================================
varying float v_instance_variance; 
varying float v_local_height_ratio; 

void vertex() {
    vec3 instance_center = MODEL_MATRIX[3].xyz;
    
    // 1. 浓度检测与秒退 (Early Out)
    vec2 global_uv = (instance_center.xz / physical_size) + 0.5;
    float current_density = dot(textureLod(moss_density_map, global_uv, 0.0), channel_mask);
    float grow_factor = smoothstep(0.01, 0.5, current_density); 
    
    float random_spawn = hash(instance_center.xz * 135.246);
    
    if (grow_factor <= 0.0 || random_spawn > spawn_density) {
        VERTEX = vec3(0.0);
    } else {
        // 2. ✨ 计算变形前模型自身高度百分比 (0=底, 1=顶)
        float current_height_ratio = clamp(VERTEX.y / mesh_original_height, 0.0, 1.0);
        v_local_height_ratio = current_height_ratio; // 传给片元算颜色
        
        // 提取顶点颜色 R 通道 (⚠️ 仅作为物理遮罩！)
        float wind_puff_mask = COLOR.r; 
        
        float raw_linear_rand = hash(instance_center.xz * 77.77);
        float curved_height_ratio = textureLod(offset_curve, vec2(raw_linear_rand, 0.5), 0.0).r;
        v_instance_variance = curved_height_ratio; 
        
        // 3. 基础缩放 
        float height_size_multiplier = textureLod(size_curve, vec2(curved_height_ratio, 0.5), 0.0).r;
        float current_scale = moss_scale * mix(0.7, 1.0, hydration) * grow_factor * height_size_multiplier;
        vec3 local_pos = VERTEX * current_scale;
        
        // ✨ 4. 彻底修正的拉伸魔法 (只拉伸伞柄！) 
        float stalk_stretch_mask = smoothstep(0.0, 0.8, current_height_ratio);
        stalk_stretch_mask = clamp(stalk_stretch_mask / 0.8, 0.0, 1.0);
        if (current_height_ratio >= 0.8) {
            stalk_stretch_mask = 1.0; 
        }
        
        // A. 个体高度随机差异
        float random_micro_offset = curved_height_ratio * micro_y_variance;
        local_pos.y += current_height_ratio * random_micro_offset; 
        
        // B. 遇水膨胀 
        float current_puff = puff_height * mix(0.3, 1.0, hydration) * grow_factor;
        local_pos.y += wind_puff_mask * current_puff; 
        
        // 5. 风吹摇摆 
        vec3 world_pos_base = instance_center + local_pos;
        float wind = sin(TIME * sway_speed + world_pos_base.x * 5.0 + world_pos_base.z * 5.0) * sway_strength;
        local_pos.x += wind * wind_puff_mask * grow_factor; 
        
        vec3 world_offset = (MODEL_MATRIX * vec4(local_pos, 0.0)).xyz; 
        
        // B. 采样植物根部周围 4 个微小点的高度
        vec2 e = vec2(0.05, 0.0);
        float h_L = get_terrain_height(instance_center.xz - e.xy);
        float h_R = get_terrain_height(instance_center.xz + e.xy);
        float h_D = get_terrain_height(instance_center.xz - e.yx);
        float h_U = get_terrain_height(instance_center.xz + e.yx);
        vec3 terrain_normal = normalize(vec3(h_L - h_R, 2.0 * e.x, h_D - h_U));
        
        // C. 算出“目标朝向”
        vec3 target_up = normalize(mix(vec3(0.0, 1.0, 0.0), terrain_normal, terrain_align_strength));
        
        // D. 罗德里格斯刚体旋转 (Rodrigues)
        vec3 axis = cross(vec3(0.0, 1.0, 0.0), target_up);
        float s = length(axis);
        if (s > 0.0001) {
            axis /= s;
            float c = dot(vec3(0.0, 1.0, 0.0), target_up);
            world_offset = world_offset * c + cross(axis, world_offset) * s + axis * dot(axis, world_offset) * (1.0 - c);
        }
        
        // E. 重新组合
        vec3 final_world_pos = instance_center;
        float terrain_h = get_terrain_height(instance_center.xz);
        
        final_world_pos.y = terrain_h + elevation_offset; 
        final_world_pos += world_offset; 
        
        VERTEX = (inverse(MODEL_MATRIX) * vec4(final_world_pos, 1.0)).xyz;
    }
}


// ... (你的 vertex 函数保持不变) ...

void fragment() {
    // 🎨 1. 获取基础颜色 (由 HeightGradient 和 个体差异 决定)
    vec3 gradient_color = texture(height_gradient, vec2(v_instance_variance, 0.5)).rgb;
    vec3 dry_gradient_color = texture(dry_gradient, vec2(v_instance_variance, 0.5)).rgb;
    vec3 base_color = mix(dry_gradient_color, gradient_color, hydration);
    
    // 🎨 2. 获取纵向灰度 (由 VerticalShadeCurve 和 v_local_height_ratio 决定)
    float shade_multiplier = texture(vertical_shade_curve, vec2(v_local_height_ratio, 0.5)).r;
    
    // 🎨 3. 混合基础色
    vec3 actual_color = base_color * shade_multiplier;
    
    // ==========================================
    // ✨ 4. 精确控制的边缘发光 (Custom Range Fresnel)
    // ==========================================
    // A. 算出法线和视线的关系 (正对=1，边缘=0)
    float dot_nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
    
    // B. 反转它，让逻辑符合直觉 (正对=0，边缘=1)
    float edge_factor = 1.0 - dot_nv;
    
    // C. 【核心控制】使用 smoothstep 划分发光区和非发光区
    // 如果 edge_factor < fuzz_start，结果就是 0 (正对你的一定范围内绝对不发光)
    // 如果 edge_factor > fuzz_start + fuzz_smoothness，结果就是 1 (边缘完全发光)
    float fresnel = smoothstep(fuzz_start, fuzz_start + fuzz_smoothness, edge_factor);
    
    // D. 高度遮罩：确保只有苔藓的尖端发光，根部泥土部分不发光
    float height_mask = smoothstep(fuzz_mask_bottom, fuzz_mask_top, v_local_height_ratio);
    
    // E. 计算最终的绒毛光强度，并用加法 (+=) 直接叠加到原本的颜色上，保证通透感
    float final_fuzz = fresnel * fuzz_intensity * height_mask;
    actual_color += fuzz_color * final_fuzz;
    // ==========================================
    
    ALBEDO = actual_color;
    ROUGHNESS = 0.95; // 苔藓很粗糙
    SPECULAR = 0.1;   // 反光很弱
    
    // 让 BACKLIGHT (背光透视) 也沾点绒毛的颜色，这样逆光看苔藓会非常漂亮
    BACKLIGHT = actual_color * 0.8; 
}