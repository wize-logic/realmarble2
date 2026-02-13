shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

// Surface type parameters
uniform vec3 base_color : source_color = vec3(0.5, 0.5, 0.5);
uniform vec3 accent_color : source_color = vec3(0.3, 0.3, 0.3);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float scale : hint_range(0.1, 10.0) = 2.0;
uniform float pattern_mix : hint_range(0.0, 1.0) = 0.5;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.3;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.2;

// Hash noise
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

// Boost saturation — push colors to be more vivid
vec3 saturate_color(vec3 color, float amount) {
	float grey = dot(color, vec3(0.299, 0.587, 0.114));
	return mix(vec3(grey), color, 1.0 + amount);
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

	// Tile grid with clean edges
	vec2 tile_pos = fract(uv);
	vec2 grid = abs(tile_pos - 0.5);
	float grid_line = smoothstep(0.46, 0.50, max(grid.x, grid.y));

	// Per-tile color variation — each tile gets a slightly different shade
	vec2 tile_id = floor(uv);
	float tile_hash = hash(tile_id);

	// Noise for surface detail
	float n = noise(uv * 2.0);
	float n2 = noise(uv * 4.0 + 17.3);

	// Mix base and accent with per-tile variation for a checkered look
	float checker = step(0.5, fract(tile_hash * 3.7));
	float mix_factor = mix(n * pattern_mix, 1.0 - n * pattern_mix, checker * 0.6);
	vec3 color = mix(base_color, accent_color, mix_factor);

	// Per-tile hue shift for variety (subtle)
	color *= 0.9 + tile_hash * 0.2;

	// Tile edge darkening — gives depth between tiles
	float edge_darken = grid_line * detail_strength * 0.7;
	color *= 1.0 - edge_darken;

	// Inner tile highlight — subtle bright center for 3D pop
	float dist_from_center = length(tile_pos - 0.5) * 2.0;
	float center_highlight = 1.0 - smoothstep(0.0, 0.8, dist_from_center);
	color *= 1.0 + center_highlight * 0.08;

	// Surface wear — slight lightening on "raised" areas
	color = mix(color, color * 1.2, n * wear_amount * 0.3);

	// Boost saturation — make colors pop
	color = saturate_color(color, 0.35);

	// Clamp to prevent overbright
	color = clamp(color, vec3(0.0), vec3(1.0));

	ALBEDO = color;
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
	SPECULAR = 0.0;

	// Subtle normal variation from noise for surface texture feel
	vec3 noise_normal = vec3(
		noise(uv * 3.0 + vec2(0.5, 0.0)) - noise(uv * 3.0 - vec2(0.5, 0.0)),
		0.0,
		noise(uv * 3.0 + vec2(0.0, 0.5)) - noise(uv * 3.0 - vec2(0.0, 0.5))
	);
	NORMAL_MAP = normalize(vec3(noise_normal.x * 0.15, noise_normal.z * 0.15, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.3;
}
