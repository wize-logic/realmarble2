shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Surface type parameters
uniform vec3 base_color : source_color = vec3(0.5, 0.5, 0.5);
uniform vec3 accent_color : source_color = vec3(0.3, 0.3, 0.3);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float scale : hint_range(0.1, 10.0) = 2.0;
uniform float pattern_mix : hint_range(0.0, 1.0) = 0.5;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.3;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.2;

// Fake baked directional light (emulates pre-baked sun contribution)
uniform vec3 baked_light_dir = vec3(-0.5, -0.7, -0.3);
uniform vec3 baked_light_color : source_color = vec3(0.95, 0.9, 0.82);
uniform float baked_light_energy : hint_range(0.0, 2.0) = 0.35;

// Fake ambient occlusion
uniform float ao_strength : hint_range(0.0, 1.0) = 0.35;
uniform float ao_height_fade : hint_range(0.1, 30.0) = 6.0;

// Cheap hash noise (single sample, no octaves)
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

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

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// World-space UVs for consistent tiling
	vec2 uv = world_pos.xz * 0.1 * scale;

	// Simple tile grid pattern
	vec2 grid = abs(fract(uv) - 0.5);
	float grid_line = smoothstep(0.48, 0.5, max(grid.x, grid.y));
	float tile_edge = grid_line * detail_strength * 0.5;

	// Cheap single-sample noise for surface variation
	float n = noise(uv * 2.0);

	// Mix base and accent color using noise + grid
	vec3 color = mix(base_color, accent_color, n * pattern_mix);

	// Darken along tile edges for subtle depth
	color *= 1.0 - tile_edge;

	// Simple wear: slightly lighten raised areas using noise
	color = mix(color, color * 1.15, n * wear_amount * 0.3);

	// --- Fake baked directional light ---
	// Adds a cheap directional light contribution without a real DirectionalLight3D node
	vec3 light_dir = normalize(baked_light_dir);
	float ndotl = max(dot(world_normal, -light_dir), 0.0);
	// Half-Lambert wrap for softer falloff (less harsh shadows)
	float wrapped = ndotl * 0.5 + 0.5;
	color += color * baked_light_color * wrapped * baked_light_energy;

	// --- Fake ambient occlusion ---
	// Height-based AO: darken geometry near floor level
	float height_ao = smoothstep(0.0, ao_height_fade, world_pos.y);
	float ao = mix(1.0 - ao_strength, 1.0, height_ao);
	// Underside darkening: surfaces facing downward get extra shadow
	float underside = max(-world_normal.y, 0.0) * ao_strength * 0.5;
	ao -= underside;
	// Corner contact hint: add noise-based micro-AO at floor level for grit
	float contact_noise = noise(world_pos.xz * 0.5) * 0.15 * (1.0 - height_ao);
	ao -= contact_noise;
	color *= max(ao, 0.05);

	ALBEDO = color;
	ROUGHNESS = roughness + n * 0.05;
	METALLIC = metallic;
}
