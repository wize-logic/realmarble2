shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Marble appearance parameters (kept for compatibility)
uniform vec3 primary_color : source_color = vec3(0.8, 0.2, 0.2);
uniform vec3 secondary_color : source_color = vec3(0.9, 0.4, 0.4);
uniform vec3 swirl_color : source_color = vec3(1.0, 0.8, 0.8);

// Material properties
uniform float glossiness : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.3;
uniform float transparency : hint_range(0.0, 1.0) = 0.02;

// Kept for compatibility but unused
uniform float swirl_scale : hint_range(0.1, 5.0) = 2.0;
uniform float swirl_intensity : hint_range(0.0, 1.0) = 0.6;
uniform float bubble_density : hint_range(0.0, 2.0) = 0.4;
uniform float time_speed : hint_range(0.0, 2.0) = 0.2;
uniform float iridescence_strength : hint_range(0.0, 1.0) = 0.0;
uniform float sss_strength : hint_range(0.0, 1.0) = 0.0;
uniform float specular_intensity : hint_range(0.0, 2.0) = 0.8;
uniform float rim_power : hint_range(1.0, 8.0) = 2.5;
uniform float rim_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.0;
uniform float glow_pulse_speed : hint_range(0.0, 5.0) = 0.0;
uniform float glow_pulse_amount : hint_range(0.0, 0.5) = 0.0;
uniform float outer_rim_power : hint_range(1.0, 5.0) = 2.2;
uniform float outer_rim_intensity : hint_range(0.0, 1.0) = 0.0;
uniform int quality_level : hint_range(0, 2) = 0;

void fragment() {
	// Simple solid color marble
	ALBEDO = primary_color;
	ROUGHNESS = 1.0 - glossiness;
	METALLIC = metallic_amount;
	SPECULAR = specular_intensity;
	ALPHA = 1.0;
}
