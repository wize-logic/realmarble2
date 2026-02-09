shader_type canvas_item;

// Vignette settings
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.5;
uniform vec3 vignette_color : source_color = vec3(0.0, 0.0, 0.05);

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

	COLOR = vec4(color, 1.0);
}
