shader_type canvas_item;

// Vignette settings
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.5;
uniform vec3 vignette_color : source_color = vec3(0.0, 0.0, 0.05);

// Speed lines (kept for gameplay feedback)
uniform float speed_line_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float speed_line_count : hint_range(4.0, 64.0) = 24.0;
uniform vec3 speed_line_color : source_color = vec3(0.8, 0.85, 0.95);

// Unused but kept for compatibility
uniform float chromatic_aberration : hint_range(0.0, 0.02) = 0.0;
uniform float chromatic_radial : hint_range(0.0, 1.0) = 0.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float contrast : hint_range(0.5, 1.5) = 1.0;
uniform vec3 color_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float grain_amount : hint_range(0.0, 0.1) = 0.0;
uniform float grain_speed : hint_range(0.0, 10.0) = 0.0;
uniform int quality_level : hint_range(0, 2) = 1;

float calculate_vignette(vec2 uv) {
	vec2 center = uv - 0.5;
	float dist = length(center);
	float vignette = smoothstep(0.5 - vignette_softness * 0.5, 0.8, dist);
	return vignette * vignette_intensity;
}

void fragment() {
	vec3 color = texture(TEXTURE, UV).rgb;

	// Apply vignette
	float vignette = calculate_vignette(UV);
	color = mix(color, vignette_color, vignette);

	color = clamp(color, 0.0, 1.0);
	COLOR = vec4(color, 1.0);
}
