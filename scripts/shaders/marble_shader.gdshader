shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Marble appearance parameters
uniform vec3 primary_color : source_color = vec3(0.8, 0.2, 0.2);
uniform vec3 secondary_color : source_color = vec3(0.9, 0.4, 0.4);
uniform vec3 swirl_color : source_color = vec3(1.0, 0.8, 0.8);

// Material properties
uniform float glossiness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.1;
uniform float transparency : hint_range(0.0, 1.0) = 0.02;

// Pattern controls
uniform float swirl_scale : hint_range(0.1, 5.0) = 2.0;
uniform float swirl_intensity : hint_range(0.0, 1.0) = 0.6;
uniform float bubble_density : hint_range(0.0, 2.0) = 0.4;
uniform float time_speed : hint_range(0.0, 2.0) = 0.2;

// Enhanced visual effects
uniform float rim_power : hint_range(1.0, 8.0) = 2.5;
uniform float rim_intensity : hint_range(0.0, 1.0) = 0.08;

// Performance quality: 0=Low (best FPS), 1=Medium, 2=High
uniform int quality_level : hint_range(0, 2) = 1;

varying vec3 world_pos;

// Simple hash function
float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// 3D noise function - optimized version
float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	// Optimized: unrolled interpolation instead of nested loops
	float a = hash(i);
	float b = hash(i + vec3(1.0, 0.0, 0.0));
	float c = hash(i + vec3(0.0, 1.0, 0.0));
	float d = hash(i + vec3(1.0, 1.0, 0.0));
	float e = hash(i + vec3(0.0, 0.0, 1.0));
	float f1 = hash(i + vec3(1.0, 0.0, 1.0));
	float g = hash(i + vec3(0.0, 1.0, 1.0));
	float h = hash(i + vec3(1.0, 1.0, 1.0));

	float z1 = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
	float z2 = mix(mix(e, f1, f.x), mix(g, h, f.x), f.y);
	return mix(z1, z2, f.z);
}

// Fractal Brownian Motion for marble veins - quality-adaptive
float fbm3d(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	// Low: 1 octave, Medium: 2 octaves, High: 3 octaves
	int max_octaves = quality_level == 0 ? 1 : (quality_level == 1 ? 2 : 3);

	for(int i = 0; i < 3; i++) {
		if (i >= max_octaves) break;
		value += amplitude * noise3d(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}

	return value;
}

// Marble swirl pattern
float marble_pattern(vec3 pos, float time) {
	// Create flowing swirls
	vec3 flow_pos = pos;
	flow_pos.x += sin(pos.y * 2.0 + time * time_speed) * 0.3;
	flow_pos.y += cos(pos.x * 2.0 + time * time_speed) * 0.3;
	flow_pos.z += sin(pos.x * 1.5 + pos.y * 1.5 + time * time_speed) * 0.2;

	// Layered noise for marble veins
	float pattern = fbm3d(flow_pos * swirl_scale);
	pattern = sin(pattern * 10.0 + pos.x + pos.y + pos.z);

	return pattern * 0.5 + 0.5;
}

// Bubble/inclusion pattern with multiple layers - quality-adaptive
float bubbles(vec3 pos) {
	float bubble = 0.0;
	// Low: 1 layer, Medium: 2 layers, High: 3 layers
	int max_layers = quality_level == 0 ? 1 : (quality_level == 1 ? 2 : 3);

	for(int i = 0; i < 3; i++) {
		if (i >= max_layers) break;
		vec3 bubble_pos = pos * (1.5 + float(i) * 0.5);
		float n = noise3d(bubble_pos);
		bubble += step(0.72, n) * (1.0 - float(i) * 0.25);
	}

	return bubble * bubble_density;
}

// Fresnel effect for glass-like appearance
float fresnel(float amount, vec3 normal, vec3 view) {
	return pow(1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0), amount);
}

void vertex() {
	world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Create marble swirl pattern
	float swirl = marble_pattern(world_pos, TIME);

	// Add bubble inclusions
	float bubble = bubbles(world_pos);

	// Sharpen the pattern for well-defined veins — Marble Blast style
	float sharp_swirl = smoothstep(0.35, 0.65, swirl);

	// Mix colors based on sharpened pattern — high contrast bands
	vec3 base_mix = mix(primary_color, secondary_color, sharp_swirl);
	vec3 final_color = mix(base_mix, swirl_color, sharp_swirl * swirl_intensity);

	// Add colored spots where bubbles are (use swirl color tinted)
	vec3 bubble_tint = mix(swirl_color, secondary_color, 0.5) * 1.1;
	final_color = mix(final_color, bubble_tint, bubble * 0.4);

	// Calculate view direction from camera to fragment (world space)
	vec3 view_dir = normalize(CAMERA_POSITION - world_pos);

	// Calculate enhanced fresnel for rim lighting
	float fresnel_amount = fresnel(rim_power, NORMAL, view_dir);

	// Add rim highlight with color tint (not white) - reduced intensity
	vec3 rim_color = mix(secondary_color, swirl_color, 0.5) * 1.2;
	final_color += fresnel_amount * rim_intensity * rim_color;

	// Output material properties
	ALBEDO = final_color;
	ROUGHNESS = 1.0 - glossiness;
	METALLIC = metallic_amount;
	SPECULAR = 0.3;

}
