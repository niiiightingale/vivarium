shader_type canvas_item;

// 顶部和底部基色 (Viridi 风格的治愈色)
uniform vec3 top_color : source_color = vec3(0.35, 0.45, 0.35); 
uniform vec3 bottom_color : source_color = vec3(0.15, 0.2, 0.15); 

// 引入噪波贴图
uniform sampler2D brush_texture : repeat_enable, filter_linear_mipmap; 

uniform float texture_scale = 1.0; // 控制笔触纹理的大小
uniform float brush_opacity : hint_range(0.0, 1.0) = 0.6; // 笔触明显程度
uniform float brightness : hint_range(0.0, 2.0) = 1.0; // 整体亮度

void fragment() {
    // 1. 生成屏幕上下方向的平滑渐变 (UV.y 从上到下是 0 到 1)
    vec3 gradient = mix(top_color, bottom_color, UV.y);

    // 2. 采样噪波纹理 (加上 scale 方便调整比例)
    vec2 sample_uv = UV * texture_scale;
    vec3 brush_noise = texture(brush_texture, sample_uv).rgb;

    // 3. 正片叠底混合，把黑白噪波变成深色笔触
    vec3 final_color = mix(gradient, gradient * brush_noise, brush_opacity);
    
    // 4. 输出最终颜色
    COLOR.rgb = final_color * brightness;
}