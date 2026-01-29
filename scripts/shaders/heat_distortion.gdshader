shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

// Distortion settings
uniform float distortion_strength : hint_range(0.0, 0.1) = 0.02;
uniform float distortion_speed : hint_range(0.0, 5.0) = 1.5;
uniform float wave_scale : hint_range(1.0, 20.0) = 8.0;
uniform float fade_distance : hint_range(1.0, 20.0) = 10.0;

// Color tint for heat haze (subtle warm tint, not white)
uniform vec3 heat_tint : source_color = vec3(1.0, 0.95, 0.9);
uniform float tint_strength : hint_range(0.0, 0.3) = 0.05;

// Visibility
uniform float opacity : hint_range(0.0, 1.0) = 0.15;

// Screen texture for refraction
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Hash function
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth noise
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// FBM for more organic distortion
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;

	for(int i = 0; i < 4; i++) {
		value += amplitude * noise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}

	return value;
}

void fragment() {
	// Get screen UV
	vec2 screen_uv = SCREEN_UV;

	// Get world position for consistent distortion
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Calculate distance-based fade
	float dist = length(VERTEX);
	float fade = smoothstep(fade_distance, 0.0, dist);

	// Create animated distortion
	float time = TIME * distortion_speed;

	// Multi-layered distortion for heat shimmer
	vec2 distortion;
	distortion.x = fbm(world_pos.xz * wave_scale + vec2(time, 0.0)) - 0.5;
	distortion.y = fbm(world_pos.xz * wave_scale + vec2(0.0, time * 1.3)) - 0.5;

	// Add vertical rising effect
	distortion.y += sin(world_pos.x * wave_scale * 0.5 + time * 2.0) * 0.3;
	distortion.y += sin(world_pos.z * wave_scale * 0.7 + time * 1.7) * 0.2;

	// Apply distortion strength and fade
	distortion *= distortion_strength * fade;

	// Sample screen with distortion
	vec3 screen_color = texture(screen_texture, screen_uv + distortion).rgb;

	// Apply subtle heat tint
	screen_color = mix(screen_color, screen_color * heat_tint, tint_strength * fade);

	// Output with fade-based alpha
	ALBEDO = screen_color;
	ALPHA = opacity * fade;
}
