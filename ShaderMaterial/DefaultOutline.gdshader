shader_type spatial;
render_mode cull_front, blend_mix;

// ==========================================
// 1. 花盆主材质占位区 (严格同步花盆主材质的变量声明，顺序不可变)
// ==========================================
instance uniform vec3 color_pot_albedo : source_color = vec3(0.9, 0.4, 0.2); 
instance uniform vec3 shadow_color_tint : source_color = vec3(0.0, 0.0, 0.1); 

// ==========================================
// 2. 描边专属变量区 (追加在占位区之后)
// ==========================================
instance uniform vec4 outline_color : source_color = vec4(0.05, 0.02, 0.0, 1.0); 
uniform float outline_width : hint_range(0.0, 5.0) = 1.0;

void vertex() {
    float stroke_width = outline_width * 0.001; 
    VERTEX += NORMAL * stroke_width;
}

void fragment() {
    ALBEDO = outline_color.rgb;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}

void light() {
    DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION;
}