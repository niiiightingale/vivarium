shader_type sky;

// 顶部和底部基色
uniform vec3 top_color : source_color = vec3(0.25, 0.35, 0.25); 
uniform vec3 bottom_color : source_color = vec3(0.1, 0.15, 0.1); 

// ✨ 关键 Uniform：我们要在面板里塞入噪波贴图
uniform sampler2D brush_texture : filter_linear_mipmap, repeat_enable; 

uniform float texture_scale = 2.0; // 笔触的缩放
uniform float brush_opacity : hint_range(0.0, 1.0) = 0.5; // 笔触的明显程度
uniform float brightness : hint_range(0.0, 2.0) = 1.0; // 整体亮度控制

void sky() {
    // 1. 生成平滑的垂直渐变底色
    float t = clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0);
    vec3 gradient = mix(bottom_color, top_color, t);

    // 2. 将 3D 视角球形映射成 2D UV，用来平铺噪波贴图
    vec2 sky_uv = vec2(atan(EYEDIR.x, EYEDIR.z), acos(EYEDIR.y)) * texture_scale;
    
    // 3. 采样笔触纹理（此时还是一张黑白灰的“噪波”）
    vec3 brush_noise = texture(brush_texture, sky_uv).rgb;

    // 4. 正片叠底 (Multiply) 混合：让噪波变成画笔的深色笔触
    vec3 final_color = mix(gradient, gradient * brush_noise, brush_opacity);
    
    // 5. 调整整体亮度，输出最终颜色
    COLOR = final_color * brightness;
}