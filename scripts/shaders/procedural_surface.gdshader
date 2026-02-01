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

// Enhanced visual controls
uniform float edge_wear_strength : hint_range(0.0, 1.0) = 0.4;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.25;  // Reduced for Q3-style bright lighting
uniform float wet_area_amount : hint_range(0.0, 1.0) = 0.15;
uniform float color_variation : hint_range(0.0, 0.3) = 0.08;
uniform float emission_strength : hint_range(0.0, 0.5) = 0.05;  // Increased base emission
uniform vec3 emission_tint : source_color = vec3(0.8, 0.85, 0.9);  // Brighter emission tint

// Q3-style lighting controls - ensures no dark spots
uniform float min_brightness : hint_range(0.0, 0.5) = 0.15;  // Minimum surface brightness
uniform float ambient_boost : hint_range(0.0, 0.5) = 0.1;  // Extra ambient for dark areas

// Simple hash function for noise
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
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

// 3D noise for volumetric effects
float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n = 0.0;
	for(int z = 0; z <= 1; z++) {
		for(int y = 0; y <= 1; y++) {
			for(int x = 0; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				n += hash3(i + g) *
					(f.x * g.x + (1.0 - f.x) * (1.0 - g.x)) *
					(f.y * g.y + (1.0 - f.y) * (1.0 - g.y)) *
					(f.z * g.z + (1.0 - f.z) * (1.0 - g.z));
			}
		}
	}
	return n;
}

// Fractal Brownian Motion for complex patterns
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;

	for(int i = 0; i < 5; i++) {
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

// Edge detection for wear effects
float edge_factor(vec3 normal, vec3 world_pos) {
	// Use normal variation to detect edges
	float normal_variance = length(dFdx(normal)) + length(dFdy(normal));
	// Also use position-based noise for organic wear
	float pos_noise = noise3d(world_pos * 0.5) * 0.5 + 0.5;
	return smoothstep(0.0, 0.15, normal_variance * pos_noise);
}

// Ambient occlusion approximation from noise - Q3-style (minimal darkening)
float calculate_ao(vec3 world_pos, vec3 normal) {
	// Use reduced noise for very subtle AO - Q3 had minimal dark spots
	float ao = 1.0;
	ao -= fbm(world_pos.xz * 2.0) * 0.15;  // Reduced from 0.3
	ao -= noise3d(world_pos * 1.5) * 0.1;   // Reduced from 0.2
	// Minimal darkening under overhangs - keep surfaces bright
	ao *= 0.85 + 0.15 * max(0.0, normal.y);  // Less aggressive
	// Q3-style: ensure high minimum brightness
	return clamp(ao, 0.6, 1.0);  // Raised minimum from 0.3 to 0.6
}

// Wet/glossy puddle effect
float wet_puddles(vec3 world_pos) {
	float puddle = fbm(world_pos.xz * 0.8);
	puddle = smoothstep(0.55, 0.65, puddle);
	return puddle;
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

	// Calculate edge wear
	float edge = edge_factor(NORMAL, world_pos) * edge_wear_strength;

	// Calculate ambient occlusion
	float ao = calculate_ao(world_pos, NORMAL);

	// Calculate wet puddle areas
	float wet = wet_puddles(world_pos) * wet_area_amount;

	// Add per-surface color variation using world position
	float hue_shift = noise3d(world_pos * 0.1) * color_variation;
	vec3 varied_base = base_color + vec3(hue_shift, hue_shift * 0.5, -hue_shift * 0.3);
	vec3 varied_accent = accent_color + vec3(-hue_shift * 0.5, hue_shift, hue_shift * 0.2);

	// Mix base and accent colors based on pattern
	vec3 final_color = mix(varied_base, varied_accent, combined);

	// Apply wear darkening
	final_color = mix(final_color, final_color * 0.65, wear);

	// Apply edge highlighting (worn edges are lighter/shinier)
	vec3 edge_highlight = mix(varied_base, varied_accent, 0.3) * 1.3;
	final_color = mix(final_color, edge_highlight, edge * 0.6);

	// Apply ambient occlusion (reduced strength for Q3-style)
	final_color *= mix(1.0, ao, ao_strength);

	// Apply wet areas (darken slightly, will increase glossiness)
	final_color = mix(final_color, final_color * 0.9, wet);  // Less darkening

	// Q3-style minimum brightness - ensure no surface goes too dark
	float brightness = max(final_color.r, max(final_color.g, final_color.b));
	if (brightness < min_brightness) {
		float boost = min_brightness / max(brightness, 0.001);
		final_color *= boost;
	}

	// Add ambient boost to ensure surfaces catch light
	final_color += vec3(ambient_boost);
	final_color = clamp(final_color, vec3(0.0), vec3(1.0));

	// Output
	ALBEDO = final_color;

	// Roughness varies based on wear and wetness
	float final_roughness = roughness + (combined - 0.5) * 0.15;
	final_roughness = mix(final_roughness, final_roughness * 1.1, edge); // Worn edges slightly rougher
	final_roughness = mix(final_roughness, 0.15, wet); // Wet areas very glossy
	ROUGHNESS = clamp(final_roughness, 0.1, 1.0);

	// Metallic slightly increases on worn edges
	METALLIC = metallic + edge * 0.15;

	// Specular increases on wet areas
	SPECULAR = 0.5 + wet * 0.4;

	// Normal map detail from noise (enhanced)
	float normal_detail_x = (noise(world_pos.xz * scale * 8.0) - 0.5) * detail_strength * 0.6;
	float normal_detail_y = (noise(world_pos.xz * scale * 8.0 + vec2(100.0, 0.0)) - 0.5) * detail_strength * 0.6;
	NORMAL_MAP = vec3(normal_detail_x, normal_detail_y, 1.0);
	NORMAL_MAP_DEPTH = 0.6;

	// Q3-style emission - subtle self-illumination to prevent dark spots
	vec3 emit_color = emission_tint * final_color;
	// Base emission plus edge/wet emphasis
	float base_emit = emission_strength * 0.5;  // Constant base emission
	float detail_emit = (edge * 0.3 + wet * 0.2) * emission_strength;
	EMISSION = emit_color * (base_emit + detail_emit);

	// Apply AO to the final output - reduced influence for Q3-style
	AO = ao;
	AO_LIGHT_AFFECT = 0.3;  // Reduced from 0.5 - less shadow influence
}
