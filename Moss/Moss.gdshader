shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// ==========================================
// 🌸 基础表现参数
// ==========================================
uniform vec3 moss_color : source_color = vec3(0.3, 0.6, 0.2);
uniform sampler2D moss_texture : source_color, filter_linear_mipmap;
uniform float moss_scale = 1.0;
uniform float sway_speed = 2.0;
uniform float sway_strength = 0.05;
uniform float elevation_offset : hint_range(0.0, 0.5) = 0.02;

// ==========================================
// ⛰️ 地形锚定参数
// ==========================================
uniform float physical_size = 5.0;
uniform float min_top_height = 0.6;
uniform float height_scale = 1.0;
uniform sampler2D height_map : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D moss_density_map : hint_default_black, filter_linear, repeat_disable;
uniform vec4 channel_mask = vec4(1.0, 0.0, 0.0, 0.0); // 决定当前是几号画笔

// ==========================================
// 📦 终极优化：打包后的通道噪波 (Channel Packing)
// ==========================================
// ⚠️ 注意：这张图的 RGBA 四个通道，将分别装载 4 种不同缩放大小的噪波！
uniform sampler2D packed_clump_noise : hint_default_white, filter_linear, repeat_enable;
uniform float packed_noise_scale = 1.0; // 整体噪波贴图的缩放
uniform vec4 moss_soil_bump = vec4(0.1, 0.1, 0.1, 0.1);

// ==========================================
// 🎨 色彩变异系统
// ==========================================
uniform float hue_variation : hint_range(0.0, 0.1) = 0.015;
uniform float value_variation : hint_range(0.0, 0.5) = 0.02;
varying float v_noise;

// ==========================================
// 🛠️ 工具函数
// ==========================================
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// ✨ 优化后的高度函数：仅需 1 次采样，获取 4 种噪波！
float get_terrain_height(vec2 pos_xz) {
    vec2 global_uv = (pos_xz / physical_size) + 0.5;
    vec4 tex_color = textureLod(moss_density_map, global_uv, 0.0);
    
    // 🚀 核心性能跨越：一次性读取 packed_clump_noise，直接得到 RGBA 四个值！
    vec2 noise_uv = pos_xz * packed_noise_scale;
    vec4 noises = textureLod(packed_clump_noise, noise_uv, 0.0);
    
    float dynamic_soil_bump = dot(tex_color, moss_soil_bump * noises);
    float soil_h = textureLod(height_map, global_uv, 0.0).r * height_scale + min_top_height;
    
    return soil_h + dynamic_soil_bump;
}

void vertex() {
    // 1. 获取当前草丛的根部中心坐标
    vec3 instance_center = MODEL_MATRIX[3].xyz;
    
    // 2. 局部基础缩放与微风动画 (为将来的浇水舒展动画预留好了位置！)
    vec3 local_pos = VERTEX * moss_scale;
    vec3 world_pos_base = instance_center + local_pos;
    
    float wind = sin(TIME * sway_speed + world_pos_base.x * 5.0 + world_pos_base.z * 5.0) * sway_strength;
    local_pos.x += wind * (1.0 - UV.y);
    
    // 3. 将带有风吹的顶点转到世界坐标
    vec3 world_pos = (MODEL_MATRIX * vec4(local_pos, 1.0)).xyz;
    
    // 4. ✨ 逐顶点完美贴合计算 (因为有了通道打包，现在算 5 次也毫无压力！)
    float terrain_h = get_terrain_height(world_pos.xz);
    
    vec2 e = vec2(0.05, 0.0);
    float h_L = get_terrain_height(world_pos.xz - e.xy);
    float h_R = get_terrain_height(world_pos.xz + e.xy);
    float h_D = get_terrain_height(world_pos.xz - e.yx);
    float h_U = get_terrain_height(world_pos.xz + e.yx);
    vec3 local_normal = normalize(vec3(h_L - h_R, 2.0 * e.x, h_D - h_U));
    
    // 5. 应用高度
    world_pos.y = terrain_h + elevation_offset;
    
    // 6. 提取色彩变异用的噪波值 (用中心点采样，保证整片苔藓颜色统一)
    vec4 center_noises = textureLod(packed_clump_noise, instance_center.xz * packed_noise_scale, 0.0);
    v_noise = dot(center_noises, channel_mask);
    
    // 7. 画笔边缘柔和生长控制
    vec2 global_uv = (instance_center.xz / physical_size) + 0.5;
    float current_density = dot(textureLod(moss_density_map, global_uv, 0.0), channel_mask);
    float grow_factor = smoothstep(0.05, 0.5, current_density);
    
    // 让草从中心点生长出来
    world_pos = mix(vec3(instance_center.x, world_pos.y, instance_center.z), world_pos, grow_factor);
    
    // 8. 重新交还给 Godot 渲染管线
    VERTEX = (inverse(MODEL_MATRIX) * vec4(world_pos, 1.0)).xyz;
    NORMAL = (inverse(MODEL_MATRIX) * vec4(local_normal, 0.0)).xyz;
}

void fragment() {
    vec4 tex = texture(moss_texture, UV);
    
    // 色彩宏观变异
    vec3 hsv = rgb2hsv(moss_color.rgb);
    float shift = v_noise;
    hsv.x = fract(hsv.x + shift * hue_variation);
    hsv.z += shift * value_variation;
    vec3 final_albedo = hsv2rgb(hsv);
    
    ALBEDO = tex.rgb * final_albedo;
    ALPHA = tex.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5; 
    
    ROUGHNESS = 0.95; 
    SPECULAR = 0.0;   
    
    // 背面防死黑
    if (!FRONT_FACING) {
        NORMAL = -NORMAL;
    }
    
    // 次表面透光
    BACKLIGHT = final_albedo * 0.8; 
}