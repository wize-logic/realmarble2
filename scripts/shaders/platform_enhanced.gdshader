shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// WebGL2/GLES3 Compatible Enhanced Platform Shader
// Designed for HTML5 compatibility with GL Compatibility renderer
// Adds visual interest to procedural platforms

uniform vec4 base_color : source_color = vec4(0.8, 0.5, 0.3, 1.0);
uniform vec4 edge_color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float edge_glow : hint_range(0.0, 3.0) = 0.8;
uniform float edge_width : hint_range(0.0, 0.5) = 0.15;

uniform float metallic : hint_range(0.0, 1.0) = 0.3;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;

// Grid pattern
uniform float grid_scale : hint_range(1.0, 50.0) = 10.0;
uniform float grid_width : hint_range(0.01, 0.2) = 0.05;
uniform vec4 grid_color : source_color = vec4(0.2, 0.2, 0.3, 1.0);

// Simple noise for surface variation
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// Base color with slight noise variation
	float noise = hash(floor(UV * 20.0)) * 0.1;
	ALBEDO = base_color.rgb * (1.0 + noise);

	// Add grid pattern
	vec2 grid_uv = fract(UV * grid_scale);
	float grid_x = step(1.0 - grid_width, grid_uv.x);
	float grid_y = step(1.0 - grid_width, grid_uv.y);
	float grid = max(grid_x, grid_y);

	ALBEDO = mix(ALBEDO, grid_color.rgb, grid * 0.5);

	// Edge detection using world position and normal
	// This creates a fake fresnel effect
	float edge = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);

	// Apply edge glow
	EMISSION = edge_color.rgb * edge * edge_glow;

	// Material properties
	METALLIC = metallic;
	ROUGHNESS = roughness;
}
