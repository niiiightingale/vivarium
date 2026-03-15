shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// ==========================================
// 1. 高度图与遮罩接收 (岛屿起伏重现)
// ==========================================
uniform sampler2D island_height_map : filter_nearest, repeat_disable;
uniform sampler2D shape_mask : filter_nearest, repeat_disable;
uniform vec2 mesh_size;
uniform float base_depth; // 从提取端传过来的基准坑底高度
uniform float max_dig_depth = 0.05; // 仅用于深色土渐变计算参考

// ==========================================
// 2. 风格化泥土与法线系统 (与主缸完全一致)
// ==========================================
uniform vec3 color_dirt_light : source_color = vec3(0.45, 0.35, 0.25);
uniform vec3 color_dirt_dark : source_color = vec3(0.30, 0.22, 0.15);
uniform vec3 color_dirt_deep : source_color = vec3(0.12, 0.08, 0.05); 
uniform vec3 wet_color_multiplier : source_color = vec3(0.6, 0.5, 0.4);

uniform sampler2D dirt_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float noise_scale = 0.05; 
uniform float side_layer_stretch : hint_range(0.05, 1.0) = 0.15; 

uniform float micro_bump_intensity : hint_range(0.0, 10.0) = 1.5;
uniform float global_moisture : hint_range(0.0, 1.0) = 0.5; 

varying vec3 v_world_pos; 
varying float v_local_y; 
varying vec2 v_local_xz; // ✨ 修复了你上一版代码漏掉的分号

// 带地层拉伸的三向采样
float get_triplanar_noise(sampler2D tex, vec3 pos, vec3 weights) {
    float n_x = texture(tex, vec2(pos.z, pos.y * side_layer_stretch)).r;
    float n_y = texture(tex, pos.xz).r; 
    float n_z = texture(tex, vec2(pos.x, pos.y * side_layer_stretch)).r;
    return n_x * weights.x + n_y * weights.y + n_z * weights.z;
}

void vertex() {
    v_local_xz = VERTEX.xz;
    vec2 projected_uv = (VERTEX.xz / mesh_size) + 0.5;
    
    // 读取提取瞬间拍下的“岛屿真实起伏高度”
    float island_h = 0.0;
    if (projected_uv.x >= 0.0 && projected_uv.x <= 1.0 && projected_uv.y >= 0.0 && projected_uv.y <= 1.0) {
        island_h = texture(island_height_map, projected_uv).r;
    }
    
    // 计算当前像素真正的厚度：原始高度 - 坑底基准面
    float thickness = max(0.0, island_h - base_depth);
    
    // ✨ 绝对形变重塑：
    // 上半部分的点：往上顶，重现岛屿原本的高低起伏！
    // 下半部分的点：强制锁定在 Y=0，变成绝对平坦的切底！
    if (VERTEX.y > 0.0) {
        VERTEX.y = thickness; 
    } else {
        VERTEX.y = 0.0; 
    }
    
    v_local_y = VERTEX.y;
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 projected_uv = (v_local_xz / mesh_size) + 0.5;
    
    // 越界保护
    if (projected_uv.x < 0.0 || projected_uv.x > 1.0 || projected_uv.y < 0.0 || projected_uv.y > 1.0) {
        discard;
    }
    
    // ✨ 核心剔除：读取抓手切出来的形状遮罩，黑色的地方直接隐形！
    float mask = texture(shape_mask, projected_uv).r;
    if (mask < 0.5) {
        discard; 
    }
    
    // ==========================================
    // 法线、噪波与颜色渲染
    // ==========================================
    vec3 geom_world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
    
    // 泥土块不需要宏观的高度图法线，直接用真实的几何起伏法线
    vec3 blend_weights = abs(geom_world_normal);
    blend_weights = normalize(max(blend_weights - 0.2, vec3(0.0))); 
    blend_weights /= dot(blend_weights, vec3(1.0));

    vec3 pos = v_world_pos * noise_scale;
    float noise_center = get_triplanar_noise(dirt_noise, pos, blend_weights);
    float noise_val = smoothstep(0.3, 0.7, noise_center);
    
    // ✨ 真实深度颜色渐变更新：
    // 因为底部现在是 Y=0，顶部是 Y=thickness
    // 越接近0（底部），颜色越深（color_dirt_deep）
    float depth_ratio = clamp(v_local_y / max_dig_depth, 0.0, 1.0);
    vec3 current_base_color = mix(color_dirt_deep, color_dirt_light, depth_ratio);
    vec3 current_dark_color = mix(color_dirt_deep * 0.5, color_dirt_dark, depth_ratio);
    
    vec3 base_color = mix(current_dark_color, current_base_color, noise_val);
    ALBEDO = mix(base_color, base_color * wet_color_multiplier, global_moisture);
    ROUGHNESS = 0.95; 
    SPECULAR = 0.1;

    // 细微的微观表面起伏
    float eps_micro = 0.01;
    float nX_val = get_triplanar_noise(dirt_noise, pos + vec3(eps_micro, 0.0, 0.0), blend_weights);
    float nY_val = get_triplanar_noise(dirt_noise, pos + vec3(0.0, eps_micro, 0.0), blend_weights);
    float nZ_val = get_triplanar_noise(dirt_noise, pos + vec3(0.0, 0.0, eps_micro), blend_weights);
    
    vec3 micro_world_grad = vec3(nX_val - noise_center, nY_val - noise_center, nZ_val - noise_center) / eps_micro * micro_bump_intensity;
    vec3 final_world_normal = normalize(geom_world_normal - micro_world_grad * 0.1); 
    
    NORMAL = (VIEW_MATRIX * vec4(final_world_normal, 0.0)).xyz;
}