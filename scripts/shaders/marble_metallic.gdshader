shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// WebGL2/GLES3 Compatible Marble Shader with Fresnel Rim Lighting
// Designed for HTML5 compatibility with GL Compatibility renderer

uniform vec4 base_color : source_color = vec4(0.3, 0.5, 0.9, 1.0);
uniform vec4 rim_color : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform float rim_intensity : hint_range(0.0, 5.0) = 2.0;
uniform float rim_power : hint_range(0.1, 8.0) = 3.0;

uniform float metallic : hint_range(0.0, 1.0) = 0.8;
uniform float roughness : hint_range(0.0, 1.0) = 0.2;
uniform float specular : hint_range(0.0, 1.0) = 0.8;

uniform float emission_strength : hint_range(0.0, 5.0) = 0.5;
uniform vec4 emission_color : source_color = vec4(0.4, 0.7, 1.0, 1.0);

// Pulse effect for visual interest
uniform float pulse_speed : hint_range(0.0, 5.0) = 1.0;
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.2;

void fragment() {
	// Base color
	ALBEDO = base_color.rgb;

	// Fresnel effect for rim lighting
	float fresnel = pow(1.0 - dot(NORMAL, VIEW), rim_power);

	// Add animated pulse
	float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
	float enhanced_fresnel = fresnel * (1.0 + pulse * pulse_strength);

	// Apply rim lighting to emission
	vec3 rim_emission = rim_color.rgb * enhanced_fresnel * rim_intensity;
	EMISSION = emission_color.rgb * emission_strength + rim_emission;

	// Material properties
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;

	// Subtle color variation based on fresnel
	ALBEDO = mix(ALBEDO, rim_color.rgb * 0.3, fresnel * 0.2);
}
