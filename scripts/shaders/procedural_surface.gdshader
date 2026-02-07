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

// Kept for compatibility
uniform float edge_wear_strength : hint_range(0.0, 1.0) = 0.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.0;
uniform float wet_area_amount : hint_range(0.0, 1.0) = 0.0;
uniform float color_variation : hint_range(0.0, 0.3) = 0.0;
uniform float emission_strength : hint_range(0.0, 0.5) = 0.0;
uniform vec3 emission_tint : source_color = vec3(0.7, 0.75, 0.8);
uniform int quality_level : hint_range(0, 2) = 0;
uniform float min_brightness : hint_range(0.0, 0.5) = 0.03;
uniform float ambient_boost : hint_range(0.0, 0.5) = 0.01;

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

void fragment() {
	// World-space UVs for consistent tiling
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
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

	ALBEDO = color;
	ROUGHNESS = roughness + n * 0.05;
	METALLIC = metallic;
}
