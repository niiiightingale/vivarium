shader_type spatial;
// 渲染模式：cull_front 渲染背面实现外扩，不再使用 unshaded 以便接受环境光
render_mode cull_front, blend_mix;

instance uniform vec3 color_base : source_color = vec3(0.20, 0.45, 0.25); 
// ==========================================
// 2. 表面亮面 (Rim Surface) 效果 (Instance)
// ==========================================
instance uniform vec3 color_rim_surface : source_color = vec3(0.80, 0.20, 0.15); 
instance uniform float rim_intensity : hint_range(0.0, 5.0) = 1.0; 
instance uniform float rim_threshold_start : hint_range(0.0, 1.0) = 0.0;
instance uniform float rim_threshold_end : hint_range(0.0, 1.0) = 0.1;

// ==========================================
// 3. 极尖端边缘 (Tip Edge) 效果 (Instance)
// ==========================================
instance uniform vec3 color_tip_edge : source_color = vec3(0.9, 0.8, 0.6);
instance uniform float tip_intensity : hint_range(0.0, 5.0) = 1.0; 
instance uniform float tip_threshold_start : hint_range(0.0, 1.0) = 0.8;
instance uniform float tip_threshold_end : hint_range(0.0, 1.0) = 1.0;

// ==========================================
// 4. 次表面散射 parameters (Instance)
// ==========================================
instance uniform vec3 sss_tint : source_color = vec3(0.80, 0.40, 0.20); 
instance uniform float sss_intensity : hint_range(0.0, 5.0) = 1.0;

// ==========================================
// 5. 赛璐璐着色新参数 (Instance)
// ==========================================
uniform float shadow_threshold : hint_range(-1.0, 1.0) = 0.0; // 阴影阈值
uniform vec3 shadow_color_tint : source_color = vec3(0.0, 0.0, 0.1); // 阴影的平和色调 (例如：加一点蓝)
uniform float cel_shadow_intensity : hint_range(0.0, 1.0) = 0.3; // 阴影区域的基础光照强度

// ==========================================
// 2. 描边专属变量区 (分配到后续安全的 Offset)
// ==========================================
// 建议使用 vec4，Godot 的底层 std140 内存对齐规则对 vec3 非常不友好，极易发生字节溢出导致串色
instance uniform vec4 outline_color : source_color = vec4(0.05, 0.02, 0.0, 1.0); 
instance uniform float outline_width : hint_range(0.0, 5.0) = 1.0;

void vertex() {
    // 基础物理挤出逻辑
    float stroke_width = outline_width * 0.001; 
    VERTEX += NORMAL * stroke_width;
}

void fragment() {
    // 此时 ALBEDO 读到的是独立的 outline_color，不再受主材质 color_old 干扰
    ALBEDO = outline_color.rgb;
    
    // 斩断高光，防止描边像塑料一样反光
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}

// 解决“黑夜荧光”逻辑：手动接管光照计算
void light() {
    // 强制扁平化光照：不计算法线点乘，只接受光源颜色。
    // 这样顺光和逆光看起来颜色一致，且黑夜里会随灯光熄灭而变暗。
    DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION;
}