shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

// Hazard type: 0 = lava, 1 = slime
uniform int hazard_type : hint_range(0, 1) = 0;

// Lava colors (warm oranges and reds, no white)
uniform vec3 lava_base_color : source_color = vec3(0.9, 0.25, 0.0);
uniform vec3 lava_hot_color : source_color = vec3(1.0, 0.6, 0.1);
uniform vec3 lava_glow_color : source_color = vec3(1.0, 0.4, 0.05);

// Slime colors (toxic greens)
uniform vec3 slime_base_color : source_color = vec3(0.15, 0.6, 0.15);
uniform vec3 slime_bright_color : source_color = vec3(0.3, 0.9, 0.25);
uniform vec3 slime_glow_color : source_color = vec3(0.1, 0.5, 0.1);

// Performance quality: 0=Low (best FPS), 1=Medium, 2=High
uniform int quality_level : hint_range(0, 2) = 1;

// Animation parameters
uniform float flow_speed : hint_range(0.0, 2.0) = 0.4;
uniform float turbulence : hint_range(0.0, 2.0) = 1.0;
uniform float glow_intensity : hint_range(0.5, 5.0) = 2.5;
uniform float bubble_amount : hint_range(0.0, 1.0) = 0.5;
uniform float surface_distortion : hint_range(0.0, 1.0) = 0.3;

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

// FBM for flowing patterns (octave count scales with quality_level)
float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;

	for(int i = 0; i < octaves; i++) {
		value += amplitude * noise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}

	return value;
}

// Voronoi for bubble/cell patterns
float voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);

	float min_dist = 1.0;

	for(int y = -1; y <= 1; y++) {
		for(int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = vec2(hash(i + neighbor), hash(i + neighbor + vec2(43.0, 57.0)));
			vec2 diff = neighbor + point - f;
			float dist = length(diff);
			min_dist = min(min_dist, dist);
		}
	}

	return min_dist;
}

// Bubble pop effect
float bubbles(vec2 uv, float time) {
	float bubble = 0.0;
	for(int i = 0; i < 3; i++) {
		vec2 bubble_uv = uv * (2.0 + float(i)) + vec2(time * 0.1 * float(i + 1), time * 0.15);
		float n = noise(bubble_uv * 8.0);
		float pop = sin(time * 3.0 + float(i) * 2.1) * 0.5 + 0.5;
		bubble += step(0.75 + pop * 0.15, n) * (1.0 - float(i) * 0.3);
	}
	return bubble * bubble_amount;
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = world_pos.xz * 0.15;

	float time = TIME * flow_speed;

	// Scale FBM octaves: low=2, medium=3, high=5
	int fbm_octaves = quality_level == 0 ? 2 : (quality_level == 1 ? 3 : 5);

	// Create flowing distortion (skip on low quality - use simple noise instead)
	vec2 flow_offset;
	if (quality_level > 0) {
		flow_offset = vec2(
			fbm(uv * 2.0 + vec2(time * 0.3, 0.0), fbm_octaves) * surface_distortion,
			fbm(uv * 2.0 + vec2(0.0, time * 0.4), fbm_octaves) * surface_distortion
		);
	} else {
		flow_offset = vec2(
			noise(uv * 2.0 + vec2(time * 0.3, 0.0)) * surface_distortion,
			noise(uv * 2.0 + vec2(0.0, time * 0.4)) * surface_distortion
		);
	}

	vec2 distorted_uv = uv + flow_offset;

	// Generate base flowing pattern
	float flow_pattern = fbm(distorted_uv * turbulence + vec2(time * 0.2, time * 0.15), fbm_octaves);

	// Add cellular/crack pattern (skip voronoi on low quality - expensive 9-tap loop)
	float cells;
	if (quality_level > 0) {
		cells = voronoi(distorted_uv * 3.0 + time * 0.1);
		cells = smoothstep(0.1, 0.4, cells);
	} else {
		cells = noise(distorted_uv * 3.0 + time * 0.1);
	}

	// Add bubbles (skip on low quality)
	float bubble = quality_level >= 2 ? bubbles(distorted_uv, TIME) : 0.0;

	// Pulsing glow effect
	float pulse = sin(TIME * 2.0) * 0.15 + 0.85;

	vec3 final_color;
	float emission_strength;

	if (hazard_type == 0) {
		// LAVA
		// Mix between base and hot based on flow pattern
		final_color = mix(lava_base_color, lava_hot_color, flow_pattern);

		// Add bright spots in cell centers (hottest parts)
		final_color = mix(final_color, lava_glow_color * 1.3, (1.0 - cells) * 0.6);

		// Add bubble highlights (bright orange, not white)
		final_color = mix(final_color, lava_hot_color * 1.4, bubble * 0.5);

		// Pulsing emission
		emission_strength = glow_intensity * pulse;

		// Cracks glow brighter
		emission_strength += (1.0 - cells) * 0.8;
	} else {
		// SLIME
		// Mix between base and bright based on flow pattern
		final_color = mix(slime_base_color, slime_bright_color, flow_pattern * 0.7);

		// Add murky darker areas in cells
		final_color = mix(final_color, slime_base_color * 0.7, cells * 0.4);

		// Add bubble highlights (bright green, not white)
		final_color = mix(final_color, slime_bright_color * 1.2, bubble * 0.6);

		// Pulsing emission (weaker than lava)
		emission_strength = (glow_intensity * 0.6) * pulse;

		// Bubbles glow slightly
		emission_strength += bubble * 0.5;
	}

	// Add subtle surface variation
	float surface_noise = noise(distorted_uv * 10.0 + TIME * 0.5) * 0.1;
	final_color *= (0.95 + surface_noise);

	ALBEDO = final_color;
	EMISSION = final_color * emission_strength;
}
