shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Surface type parameters
uniform vec3 base_color : source_color = vec3(0.5, 0.5, 0.5);
uniform vec3 accent_color : source_color = vec3(0.3, 0.3, 0.3);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// Kept for compatibility but simplified/unused
uniform float scale : hint_range(0.1, 10.0) = 2.0;
uniform float pattern_mix : hint_range(0.0, 1.0) = 0.5;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.3;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.2;
uniform float edge_wear_strength : hint_range(0.0, 1.0) = 0.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.0;
uniform float wet_area_amount : hint_range(0.0, 1.0) = 0.0;
uniform float color_variation : hint_range(0.0, 0.3) = 0.0;
uniform float emission_strength : hint_range(0.0, 0.5) = 0.0;
uniform vec3 emission_tint : source_color = vec3(0.7, 0.75, 0.8);
uniform int quality_level : hint_range(0, 2) = 0;
uniform float min_brightness : hint_range(0.0, 0.5) = 0.03;
uniform float ambient_boost : hint_range(0.0, 0.5) = 0.01;

void fragment() {
	ALBEDO = base_color;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
