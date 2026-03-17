shader_type spatial;
render_mode depth_draw_opaque;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap; 
uniform sampler2D brush_mask_texture : hint_default_black; // 你马上要画好的满铺笔刷图

uniform float voronoi_scale : hint_range(1.0, 100.0) = 40.0; // 决定颜料色块有多大
uniform float brush_tiling : hint_range(0.1, 10.0) = 1.0;    // 决定笔刷贴图的平铺密度

// Voronoi 噪声生成器
vec2 random2(vec2 p) {
    return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

// 返回 Voronoi 细胞的中心点坐标
vec2 get_voronoi_center(vec2 uv) {
    vec2 n = floor(uv);
    vec2 f = fract(uv);
    float min_dist = 1.0;
    vec2 closest_center = vec2(0.0);

    for(int y = -1; y <= 1; y++) {
        for(int x = -1; x <= 1; x++) {
            vec2 g = vec2(float(x), float(y));
            vec2 o = random2(n + g);
            vec2 r = g + o - f;
            float d = dot(r, r);
            if(d < min_dist) {
                min_dist = d;
                closest_center = n + g + o;
            }
        }
    }
    return closest_center;
}

void fragment() {
    // 1. 获取底层的平滑原色
    vec3 base_color = texture(albedo_texture, UV).rgb;

    // 2. 生成 Voronoi 晶格化的 UV，并提取“纯色颜料块”
    vec2 cell_center_uv = get_voronoi_center(UV * voronoi_scale) / voronoi_scale;
    vec3 chunky_color = texture(albedo_texture, cell_center_uv).rgb;

    // 3. 读取你画的满铺笔刷遮罩
    float brush_mask = texture(brush_mask_texture, UV * brush_tiling).r;

    // 4. 完美混合：白色的笔刷透出块状纯色，黑色的缝隙透出平滑底色！
    vec3 final_color = mix(base_color, chunky_color, brush_mask);
    
    ALBEDO = final_color;
    ROUGHNESS = 0.8;
}