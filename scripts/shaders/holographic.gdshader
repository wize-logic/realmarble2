shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// WebGL2/GLES3 Compatible Holographic Shader
// Designed for HTML5 compatibility with GL Compatibility renderer
// Used for ability pickups and special effects

uniform vec4 holo_color : source_color = vec4(0.3, 0.8, 1.0, 0.6);
uniform float scan_speed : hint_range(0.0, 5.0) = 1.5;
uniform float scan_width : hint_range(0.01, 0.5) = 0.1;
uniform float flicker_speed : hint_range(0.0, 10.0) = 5.0;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.3;

// Simple noise for glitches
float noise(float t) {
	return fract(sin(t * 12.9898) * 43758.5453);
}

void fragment() {
	// Scanning lines moving up
	float scan_pos = fract(TIME * scan_speed);
	float scan_line = smoothstep(scan_width, 0.0, abs(UV.y - scan_pos));

	// Fresnel effect for holographic look
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);

	// Flicker effect
	float flicker = noise(floor(TIME * flicker_speed)) * flicker_amount + (1.0 - flicker_amount);

	// Grid pattern for tech look
	vec2 grid_uv = fract(UV * 20.0);
	float grid = step(0.9, max(grid_uv.x, grid_uv.y));

	// Combine effects
	float intensity = (fresnel * 0.7 + scan_line + grid * 0.3) * flicker;

	ALBEDO = holo_color.rgb;
	ALPHA = intensity * holo_color.a;
	EMISSION = holo_color.rgb * intensity * 2.0;
}
