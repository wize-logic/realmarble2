shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// WebGL2/GLES3 Compatible Energy Trail Shader
// Designed for HTML5 compatibility with GL Compatibility renderer
// Used for movement trails and ability effects

uniform vec4 trail_color : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform float trail_intensity : hint_range(0.0, 5.0) = 2.0;
uniform float fade_power : hint_range(0.1, 5.0) = 2.0;

// Animation
uniform float flow_speed : hint_range(0.0, 10.0) = 3.0;
uniform float noise_scale : hint_range(0.1, 10.0) = 2.0;

// Simple noise function for energy distortion
float noise(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// Fade along the trail (V coordinate goes 0 to 1 along trail)
	float fade = pow(1.0 - UV.y, fade_power);

	// Fade along width (U coordinate)
	float width_fade = 1.0 - abs(UV.x * 2.0 - 1.0);
	width_fade = pow(width_fade, 2.0);

	// Add flowing energy effect
	float flow = fract((UV.y * noise_scale) - (TIME * flow_speed));
	float energy = smoothstep(0.3, 0.7, flow);

	// Add noise for organic feel
	float n = noise(UV * 10.0 + TIME);
	energy += n * 0.2;

	// Combine all fade factors
	float final_alpha = fade * width_fade * (0.5 + energy * 0.5);

	// Apply color and intensity
	ALBEDO = trail_color.rgb;
	ALPHA = final_alpha * trail_intensity * trail_color.a;
	EMISSION = trail_color.rgb * trail_intensity;
}
