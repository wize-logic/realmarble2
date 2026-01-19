shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Surface type parameters
uniform vec3 base_color : source_color = vec3(0.5, 0.5, 0.5);
uniform vec3 accent_color : source_color = vec3(0.3, 0.3, 0.3);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// Procedural pattern controls
uniform float scale : hint_range(0.1, 10.0) = 2.0;
uniform float pattern_mix : hint_range(0.0, 1.0) = 0.5;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.3;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.2;

// Simple hash function for noise
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 2D noise function
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // Smooth interpolation

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian Motion for complex patterns
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

// Voronoi-style cellular pattern
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

// Triplanar mapping for better texture projection
vec3 triplanar_blend(vec3 world_normal) {
	vec3 blend = abs(world_normal);
	blend = normalize(max(blend, vec3(0.00001)));
	float b = blend.x + blend.y + blend.z;
	return blend / vec3(b);
}

void fragment() {
	// Get world position and normal for triplanar mapping
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 blend_weights = triplanar_blend(NORMAL);

	// Sample procedural patterns from three directions
	vec2 uv_x = world_pos.zy * scale;
	vec2 uv_y = world_pos.xz * scale;
	vec2 uv_z = world_pos.xy * scale;

	// Generate multiple noise layers
	float pattern_x = fbm(uv_x);
	float pattern_y = fbm(uv_y);
	float pattern_z = fbm(uv_z);

	// Blend based on surface normal (triplanar)
	float pattern = pattern_x * blend_weights.x +
	                pattern_y * blend_weights.y +
	                pattern_z * blend_weights.z;

	// Add cellular/tile pattern
	float cells_x = voronoi(uv_x * 0.5);
	float cells_y = voronoi(uv_y * 0.5);
	float cells_z = voronoi(uv_z * 0.5);
	float cells = cells_x * blend_weights.x +
	              cells_y * blend_weights.y +
	              cells_z * blend_weights.z;

	// Combine patterns
	float combined = mix(pattern, cells, pattern_mix);

	// Create detail variation
	float detail = noise(world_pos.xz * scale * 4.0) * detail_strength;
	combined += detail;

	// Add wear/weathering effect
	float wear = smoothstep(0.4, 0.6, fbm(world_pos.xz * 0.5)) * wear_amount;

	// Mix base and accent colors based on pattern
	vec3 final_color = mix(base_color, accent_color, combined);
	final_color = mix(final_color, final_color * 0.7, wear);

	// Output
	ALBEDO = final_color;
	ROUGHNESS = roughness + (combined - 0.5) * 0.2;
	METALLIC = metallic;

	// Normal map detail from noise
	float normal_detail = (noise(world_pos.xz * scale * 8.0) - 0.5) * detail_strength * 0.5;
	NORMAL_MAP = vec3(normal_detail, normal_detail, 1.0);
}
