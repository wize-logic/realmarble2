shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Marble appearance parameters
uniform vec3 primary_color : source_color = vec3(0.8, 0.2, 0.2);
uniform vec3 secondary_color : source_color = vec3(0.9, 0.4, 0.4);
uniform vec3 swirl_color : source_color = vec3(1.0, 0.8, 0.8);

// Material properties
uniform float glossiness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.1;
uniform float transparency : hint_range(0.0, 1.0) = 0.0;

// Pattern controls
uniform float swirl_scale : hint_range(0.1, 5.0) = 1.5;
uniform float swirl_intensity : hint_range(0.0, 1.0) = 0.8;
uniform float bubble_density : hint_range(0.0, 2.0) = 0.4;
uniform float time_speed : hint_range(0.0, 2.0) = 0.1;

// Enhanced visual effects
uniform float rim_power : hint_range(1.0, 8.0) = 3.0;
uniform float rim_intensity : hint_range(0.0, 1.0) = 0.12;

// Pattern darkness — how dark the vein pattern gets
uniform float pattern_darkness : hint_range(0.0, 1.0) = 0.7;

// Performance quality: 0=Low (best FPS), 1=Medium, 2=High
uniform int quality_level : hint_range(0, 2) = 1;

varying vec3 world_pos;

// Simple hash function
float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// 3D noise function
float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

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

// Fractal Brownian Motion - quality-adaptive
float fbm3d(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	int max_octaves = quality_level == 0 ? 1 : (quality_level == 1 ? 2 : 3);

	for(int i = 0; i < 3; i++) {
		if (i >= max_octaves) break;
		value += amplitude * noise3d(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}

	return value;
}

// Marble vein pattern — produces dark veins on bright surface
float marble_veins(vec3 pos, float time) {
	vec3 flow_pos = pos;
	flow_pos.x += sin(pos.y * 2.0 + time * time_speed) * 0.3;
	flow_pos.y += cos(pos.x * 2.0 + time * time_speed) * 0.3;
	flow_pos.z += sin(pos.x * 1.5 + pos.y * 1.5 + time * time_speed) * 0.2;

	float pattern = fbm3d(flow_pos * swirl_scale);
	// Sin produces veins — abs() makes them sharp dark lines
	float veins = abs(sin(pattern * 10.0 + pos.x + pos.y + pos.z));
	return veins;
}

// Bubble/inclusion pattern - quality-adaptive
float bubbles(vec3 pos) {
	float bubble = 0.0;
	int max_layers = quality_level == 0 ? 1 : (quality_level == 1 ? 2 : 3);

	for(int i = 0; i < 3; i++) {
		if (i >= max_layers) break;
		vec3 bubble_pos = pos * (1.5 + float(i) * 0.5);
		float n = noise3d(bubble_pos);
		bubble += step(0.72, n) * (1.0 - float(i) * 0.25);
	}

	return bubble * bubble_density;
}

// Fresnel effect
float fresnel(float amount, vec3 normal, vec3 view) {
	return pow(1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0), amount);
}

void vertex() {
	world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Get vein pattern — 0.0 = vein center (dark), 1.0 = clean surface (bright)
	float veins = marble_veins(world_pos, TIME);

	// Sharpen veins into crisp dark lines
	float vein_mask = smoothstep(0.05, 0.4, veins);

	// Bright base: blend primary → secondary across the surface
	float surface_noise = noise3d(world_pos * 1.2);
	vec3 bright_base = mix(secondary_color, swirl_color, surface_noise * 0.5);

	// Dark vein color: much darker version of primary
	vec3 dark_vein = primary_color * (1.0 - pattern_darkness);

	// Final color: bright surface with dark veins carved in
	vec3 final_color = mix(dark_vein, bright_base, vein_mask);

	// Bubble inclusions — bright patches
	float bubble = bubbles(world_pos);
	final_color = mix(final_color, swirl_color, bubble * 0.4);

	// Overall brightness boost — marbles should read bright
	final_color *= 1.25;

	// Calculate view direction
	vec3 view_dir = normalize(CAMERA_POSITION - world_pos);

	// Fresnel rim — bright colored edge for readability at distance
	float fresnel_amount = fresnel(rim_power, NORMAL, view_dir);
	vec3 rim_color = mix(secondary_color, swirl_color, 0.6);
	final_color += fresnel_amount * rim_intensity * rim_color;

	// Clamp
	final_color = clamp(final_color, vec3(0.0), vec3(1.0));

	// Output
	ALBEDO = final_color;
	ROUGHNESS = 1.0 - glossiness;
	METALLIC = metallic_amount;
	SPECULAR = 0.35;
}
