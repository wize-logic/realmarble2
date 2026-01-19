shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Marble appearance parameters
uniform vec3 primary_color : source_color = vec3(0.8, 0.2, 0.2);
uniform vec3 secondary_color : source_color = vec3(0.9, 0.4, 0.4);
uniform vec3 swirl_color : source_color = vec3(1.0, 0.8, 0.8);

// Material properties
uniform float glossiness : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.3;
uniform float transparency : hint_range(0.0, 1.0) = 0.15;

// Pattern controls
uniform float swirl_scale : hint_range(0.1, 5.0) = 2.0;
uniform float swirl_intensity : hint_range(0.0, 1.0) = 0.6;
uniform float bubble_density : hint_range(0.0, 2.0) = 0.4;
uniform float time_speed : hint_range(0.0, 2.0) = 0.2;

// Simple hash function
float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// 3D noise function
float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n = 0.0;
	for(int z = 0; z <= 1; z++) {
		for(int y = 0; y <= 1; y++) {
			for(int x = 0; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				n += hash(i + g) *
					(f.x * g.x + (1.0 - f.x) * (1.0 - g.x)) *
					(f.y * g.y + (1.0 - f.y) * (1.0 - g.y)) *
					(f.z * g.z + (1.0 - f.z) * (1.0 - g.z));
			}
		}
	}
	return n;
}

// Fractal Brownian Motion for marble veins
float fbm3d(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;

	for(int i = 0; i < 4; i++) {
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

// Bubble/inclusion pattern
float bubbles(vec3 pos) {
	float bubble = 0.0;

	for(int i = 0; i < 3; i++) {
		vec3 bubble_pos = pos * (1.5 + float(i) * 0.5);
		float n = noise3d(bubble_pos);
		bubble += step(0.7, n) * (1.0 - float(i) * 0.3);
	}

	return bubble * bubble_density;
}

// Fresnel effect for glass-like appearance
float fresnel(float amount, vec3 normal, vec3 view) {
	return pow(1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0), amount);
}

void fragment() {
	// Get world position for consistent patterns
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Create marble swirl pattern
	float swirl = marble_pattern(world_pos, TIME);

	// Add bubble inclusions
	float bubble = bubbles(world_pos);

	// Mix colors based on patterns
	vec3 base_mix = mix(primary_color, secondary_color, swirl);
	vec3 final_color = mix(base_mix, swirl_color, swirl * swirl_intensity);

	// Add bright spots where bubbles are
	final_color = mix(final_color, vec3(1.0), bubble * 0.3);

	// Calculate fresnel for rim lighting
	vec3 view_dir = normalize(VERTEX);
	float fresnel_amount = fresnel(3.0, NORMAL, view_dir);

	// Add rim highlight
	final_color += fresnel_amount * 0.3;

	// Output material properties
	ALBEDO = final_color;
	ROUGHNESS = 1.0 - glossiness;
	METALLIC = metallic_amount;

	// Set to fully opaque for proper shadow casting and receiving
	ALPHA = 1.0;

	// Add normal map detail from swirl pattern
	float normal_detail = (noise3d(world_pos * swirl_scale * 4.0) - 0.5) * 0.3;
	NORMAL_MAP = vec3(normal_detail, normal_detail, 1.0);

	// Emission for a subtle inner glow
	EMISSION = final_color * 0.05 * (1.0 + fresnel_amount * 0.2);
}
