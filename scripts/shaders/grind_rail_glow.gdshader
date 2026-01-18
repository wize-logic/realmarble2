shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// WebGL2/GLES3 Compatible Grind Rail Glow Shader
// Designed for HTML5 compatibility with GL Compatibility renderer

uniform vec4 base_color : source_color = vec4(0.7, 0.7, 0.8, 1.0);
uniform vec4 glow_color : source_color = vec4(0.3, 0.8, 1.0, 1.0);
uniform float glow_intensity : hint_range(0.0, 10.0) = 3.0;
uniform float glow_speed : hint_range(0.0, 5.0) = 2.0;

uniform float metallic : hint_range(0.0, 1.0) = 0.9;
uniform float roughness : hint_range(0.0, 1.0) = 0.1;

// Animated glow that travels along the rail
uniform float flow_speed : hint_range(0.0, 5.0) = 1.5;
uniform float flow_scale : hint_range(0.1, 10.0) = 3.0;

void fragment() {
	ALBEDO = base_color.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;

	// Create flowing energy effect along rail using UV coordinates
	float flow = fract((UV.y * flow_scale) - (TIME * flow_speed));

	// Create pulses
	float pulse = sin(TIME * glow_speed) * 0.5 + 0.5;

	// Combine flow and pulse for dynamic glow
	float glow_pattern = smoothstep(0.3, 0.7, flow) * pulse;

	// Apply glow
	EMISSION = glow_color.rgb * glow_pattern * glow_intensity;

	// Add constant subtle glow
	EMISSION += glow_color.rgb * 0.3;
}
