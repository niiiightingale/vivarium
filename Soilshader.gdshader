// NOTE: Shader automatically converted from Godot Engine 4.6.1.stable's StandardMaterial3D.

shader_type spatial;


render_mode cull_disabled, depth_draw_opaque;

// 接收外部传进来的参数
uniform sampler2D height_map : hint_default_black, filter_linear, repeat_disable;
uniform float height_scale = 1.0; // 隆起的高低倍率，方便随时调节
uniform vec3 soil_default_color : source_color = vec3(0.1, 0.08, 0.07); // 湿漉漉的黑褐色
uniform float soil_default_roughness = 0.25; // 反光度

uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform ivec2 albedo_texture_size;
uniform float point_size : hint_range(0.1, 128.0, 0.1);

uniform float roughness : hint_range(0.0, 1.0);
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_texture_channel;
uniform sampler2D texture_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;

uniform float specular : hint_range(0.0, 1.0, 0.01);
uniform float metallic : hint_range(0.0, 1.0, 0.01);

uniform sampler2D texture_normal : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale : hint_range(-16.0, 16.0);

uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;

group_uniforms EcoSystem;
// 1. 水位线高度 (低于这个高度会形成积水视觉)
uniform float water_level_threshold = 0.02; 
// 2. 干燥开始高度 (高于这个高度泥土开始发灰)
uniform float drying_start_height = 0.1;
// 3. 完全干燥高度 (高于这个高度泥土完全变灰)
uniform float fully_dry_height = 0.5;

// 【新增】三种状态的颜色
uniform vec3 color_puddle : source_color = vec3(0.01, 0.01, 0.02); // 极深蓝黑 (积水)
uniform vec3 color_wet_mud : source_color = vec3(0.1, 0.08, 0.07); // 深黑褐色 (湿泥)
uniform vec3 color_dry_earth : source_color = vec3(0.4, 0.4, 0.35); // 浅灰褐色 (干土)

// 【新增】三种状态的粗糙度
uniform float roughness_puddle = 0.05;   // 极光滑 (水面反射)
uniform float roughness_wet_mud = 0.3;    // 较光滑 (湿泥反光)
uniform float roughness_dry_earth = 0.85; // 很粗糙 (干土漫反射)

varying float v_world_height; // 用来把 Y 轴高度从 vertex 传给 fragment
void vertex() {
    // 1. 读取高度图在当前坐标 (UV) 的红色通道值
    float h = texture(height_map, UV).r;
    
    // 2. 将网格的顶点 (VERTEX) 沿着 Y 轴 (向上) 抬升！
    VERTEX.y += h * height_scale;
	v_world_height = VERTEX.y;
}

void fragment() {
	vec2 base_uv = UV;

	vec4 albedo_tex = texture(texture_albedo, base_uv);
	ALBEDO = albedo.rgb * albedo_tex.rgb;

	float metallic_tex = dot(texture(texture_metallic, base_uv), metallic_texture_channel);
	METALLIC = metallic_tex * metallic;
	SPECULAR = specular;

	vec4 roughness_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
	float roughness_tex = dot(texture(texture_roughness, base_uv), roughness_texture_channel);
	ROUGHNESS = roughness_tex * roughness;

	// Normal Map: Enabled
	NORMAL_MAP = texture(texture_normal, base_uv).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
	
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	
	vec3 final_color;
	float final_roughness;
	
	// 1. 计算【干燥度】(0.0=湿泥, 1.0=完全干土)
	// 使用 smoothstep 在指定高度区间进行丝滑过渡
	float dry_factor = smoothstep(drying_start_height, fully_dry_height, v_world_height);
	
	// 先计算泥土本身的干湿混合
	vec3 soil_color = mix(color_wet_mud, color_dry_earth, dry_factor);
	float soil_roughness = mix(roughness_wet_mud, roughness_dry_earth, dry_factor);
	
	// 2. 计算【积水度】(低于阈值积水)
	// 高度越接近底部，puddle_factor 越接近 1.0
	float puddle_factor = smoothstep(water_level_threshold, 0.0, v_world_height);
	
	// 3. 最终混合：在泥土之上覆盖水坑效果
	ALBEDO = mix(soil_color, color_puddle, puddle_factor);
	ROUGHNESS = mix(soil_roughness, roughness_puddle, puddle_factor);
	
	// 可选：给水坑加一点点金属感，让反光更锐利，更像水面
	METALLIC = mix(0.0, 0.1, puddle_factor);
}
