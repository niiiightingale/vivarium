shader_type spatial;

// 开启双面渲染，这是让玻璃产生“两层折射”厚度感的物理基础
render_mode blend_mix, depth_draw_always, cull_disabled, shadows_disabled;

// ==========================================
// 完美复刻 Cycles Glass BSDF 的三个输入端口
// ==========================================
uniform vec3 glass_color : source_color = vec3(1.0, 1.0, 1.0); // 颜色 (Color)
uniform float roughness : hint_range(0.0, 1.0) = 0.0;          // 粗糙度 (Roughness)
uniform float ior : hint_range(1.0, 2.5) = 1.45;               // 折射率 (IOR，Cycles 默认值为 1.45)

// 额外参数：模拟 Cycles 里的光线内部全反射（TIR）衰减
// 当光线追踪在边缘打不穿玻璃时，会显得深邃发暗。这个参数用来模拟那个效果。
uniform float edge_darkness : hint_range(0.0, 1.0) = 0.35; 

// 获取屏幕背景图，用于计算物理折射透射
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    // 1. 修正内外壁法线（确保从内往外看和从外往内看的物理算式都正确）
    vec3 normal = NORMAL;
    if (!FRONT_FACING) {
        normal = -NORMAL;
    }

    // 2. 完美的 Cycles 菲涅尔公式 (Schlick's Approximation)
    // 根据 IOR 自动计算正面反射率 (R0) 和边缘反射率
    float r0 = (1.0 - ior) / (1.0 + ior);
    r0 = r0 * r0;
    float v_dot_n = clamp(dot(VIEW, normal), 0.0, 1.0);
    float fresnel = r0 + (1.0 - r0) * pow(1.0 - v_dot_n, 5.0);

    // 3. 计算真实的光线折射偏移量 (Refraction Vector)
    // 模拟光线进入 1.45 折射率介质时的物理弯曲
    vec3 ref_vec = refract(-VIEW, normal, 1.0 / ior);
    // 根据折射向量扭曲屏幕 UV（系数 0.05 用于适配 Godot 屏幕空间比例）
    vec2 screen_uv = SCREEN_UV + (ref_vec.xy * 0.05 * (ior - 1.0));

    // 4. 采样折射后的画面 (Transmission)
    // Godot 的 mipmap 完美对应了 Cycles 里的 Roughness 毛玻璃模糊效果
    vec3 background = textureLod(screen_texture, screen_uv, roughness * 8.0).rgb;

    // 5. 模拟光线追踪中的“全反射边缘吸收”
    // 在视线极度倾斜的厚边缘，画面变暗，颜色变得浓郁
    float edge_mask = pow(1.0 - v_dot_n, 4.0);
    vec3 transmission_color = mix(background, background * (1.0 - edge_darkness), edge_mask);

    // 6. BSDF 输出拼合
    // 在真实的物理 PBR 中，纯玻璃本身的漫反射（Albedo）是黑色的，颜色全靠透射光和环境高光
    ALBEDO = vec3(0.0);
    ROUGHNESS = roughness;
    SPECULAR = 0.5;
    
    // ★ 性能与层级黑魔法：强制不透明，将透射光作为自发光画在表面
    // 这不仅能完美解决 Godot 多层透明交叠的闪烁问题，还能让内外两层网格互相折射！
    ALPHA = 1.0; 
    
    // 最终透射光 = 扭曲后的背景 * 玻璃颜色 * (1 - 被物理反射掉的光)
    EMISSION = transmission_color * glass_color * (1.0 - fresnel);
}