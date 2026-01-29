shader_type canvas_item;

// Vignette settings
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.5;
uniform vec3 vignette_color : source_color = vec3(0.0, 0.0, 0.05);

// Chromatic aberration settings
uniform float chromatic_aberration : hint_range(0.0, 0.02) = 0.002;
uniform float chromatic_radial : hint_range(0.0, 1.0) = 0.5;

// Speed lines settings
uniform float speed_line_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float speed_line_count : hint_range(4.0, 64.0) = 24.0;
uniform vec3 speed_line_color : source_color = vec3(0.8, 0.85, 0.95);

// Color grading
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float contrast : hint_range(0.5, 1.5) = 1.0;
uniform vec3 color_tint : source_color = vec3(1.0, 1.0, 1.0);

// Film grain
uniform float grain_amount : hint_range(0.0, 0.1) = 0.02;
uniform float grain_speed : hint_range(0.0, 10.0) = 5.0;

// Hash for noise
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Vignette calculation
float calculate_vignette(vec2 uv) {
	vec2 center = uv - 0.5;
	float dist = length(center);
	float vignette = smoothstep(0.5 - vignette_softness * 0.5, 0.8, dist);
	return vignette * vignette_intensity;
}

// Speed lines (radial blur effect)
float speed_lines(vec2 uv, float time) {
	vec2 center = uv - 0.5;
	float angle = atan(center.y, center.x);
	float dist = length(center);

	// Create radial lines
	float lines = sin(angle * speed_line_count + time * 2.0) * 0.5 + 0.5;
	lines = pow(lines, 3.0);

	// Fade toward center and edges
	float fade = smoothstep(0.1, 0.3, dist) * smoothstep(0.7, 0.4, dist);

	return lines * fade * speed_line_intensity;
}

// Film grain
float film_grain(vec2 uv, float time) {
	return (hash(uv * 1000.0 + time * grain_speed) - 0.5) * grain_amount;
}

void fragment() {
	vec2 uv = UV;
	vec2 center_offset = uv - 0.5;
	float dist_from_center = length(center_offset);

	// Chromatic aberration
	float aberration = chromatic_aberration * (1.0 + dist_from_center * chromatic_radial * 5.0);
	vec2 aberration_offset = normalize(center_offset + vec2(0.001)) * aberration;

	vec3 color;
	color.r = texture(TEXTURE, uv + aberration_offset).r;
	color.g = texture(TEXTURE, uv).g;
	color.b = texture(TEXTURE, uv - aberration_offset).b;

	// Apply saturation
	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luminance), color, saturation);

	// Apply contrast
	color = (color - 0.5) * contrast + 0.5;

	// Apply color tint
	color *= color_tint;

	// Apply speed lines
	float lines = speed_lines(uv, TIME);
	color = mix(color, speed_line_color, lines * 0.4);

	// Apply vignette
	float vignette = calculate_vignette(uv);
	color = mix(color, vignette_color, vignette);

	// Apply film grain
	float grain = film_grain(uv, TIME);
	color += grain;

	// Clamp final color
	color = clamp(color, 0.0, 1.0);

	COLOR = vec4(color, 1.0);
}
