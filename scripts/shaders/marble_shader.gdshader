shader_type spatial;
render_mode blend_mix, depth_draw_always, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

// Marble appearance parameters
uniform vec3 primary_color : source_color = vec3(0.8, 0.2, 0.2);
uniform vec3 secondary_color : source_color = vec3(0.9, 0.4, 0.4);
uniform vec3 swirl_color : source_color = vec3(1.0, 0.8, 0.8);

// Material properties
uniform float glossiness : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.3;
uniform float transparency : hint_range(0.0, 1.0) = 0.02;

// Pattern controls
uniform float swirl_scale : hint_range(0.1, 5.0) = 2.0;
uniform float swirl_intensity : hint_range(0.0, 1.0) = 0.6;
uniform float bubble_density : hint_range(0.0, 2.0) = 0.4;
uniform float time_speed : hint_range(0.0, 2.0) = 0.2;

// Enhanced visual effects
uniform float iridescence_strength : hint_range(0.0, 1.0) = 0.3;
uniform float sss_strength : hint_range(0.0, 1.0) = 0.4;
uniform float specular_intensity : hint_range(0.0, 2.0) = 0.8;
uniform float rim_power : hint_range(1.0, 8.0) = 2.5;
uniform float rim_intensity : hint_range(0.0, 1.0) = 0.15;

// Special marble lighting - subtle glow to help marbles stand out (reduced values)
uniform float glow_strength : hint_range(0.0, 1.0) = 0.12;
uniform float glow_pulse_speed : hint_range(0.0, 5.0) = 1.2;
uniform float glow_pulse_amount : hint_range(0.0, 0.5) = 0.08;
uniform float outer_rim_power : hint_range(1.0, 5.0) = 2.2;
uniform float outer_rim_intensity : hint_range(0.0, 1.0) = 0.2;

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

// Bubble/inclusion pattern with multiple layers
float bubbles(vec3 pos) {
	float bubble = 0.0;

	for(int i = 0; i < 4; i++) {
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

// Iridescence - rainbow effect based on view angle
vec3 iridescence(vec3 normal, vec3 view, float strength) {
	float ndotv = dot(normalize(normal), normalize(view));
	float hue = fract(ndotv * 2.0 + 0.5);

	// Convert hue to RGB (simplified HSV to RGB)
	vec3 rgb;
	float h = hue * 6.0;
	float c = 1.0;
	float x = c * (1.0 - abs(mod(h, 2.0) - 1.0));

	if (h < 1.0) rgb = vec3(c, x, 0.0);
	else if (h < 2.0) rgb = vec3(x, c, 0.0);
	else if (h < 3.0) rgb = vec3(0.0, c, x);
	else if (h < 4.0) rgb = vec3(0.0, x, c);
	else if (h < 5.0) rgb = vec3(x, 0.0, c);
	else rgb = vec3(c, 0.0, x);

	return rgb * strength;
}

// Subsurface scattering approximation
vec3 sss_color(vec3 base_color, vec3 view_dir, vec3 normal, float strength) {
	// Simulate light passing through the marble
	float sss_factor = pow(1.0 - abs(dot(normal, view_dir)), 2.0);
	vec3 warm_tint = vec3(1.0, 0.85, 0.7); // Warm internal glow
	return mix(base_color, base_color * warm_tint * 1.3, sss_factor * strength);
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

	// Add colored spots where bubbles are (not white, use swirl color tinted)
	vec3 bubble_tint = mix(swirl_color, secondary_color, 0.5) * 1.2;
	final_color = mix(final_color, bubble_tint, bubble * 0.35);

	// Calculate view direction
	vec3 view_dir = normalize(VERTEX);

	// Apply subsurface scattering simulation
	final_color = sss_color(final_color, view_dir, NORMAL, sss_strength);

	// Add iridescence effect
	vec3 iris = iridescence(NORMAL, view_dir, iridescence_strength);
	final_color += iris * 0.15;

	// Calculate enhanced fresnel for rim lighting
	float fresnel_amount = fresnel(rim_power, NORMAL, view_dir);

	// Add rim highlight with color tint (not white) - reduced intensity
	vec3 rim_color = mix(secondary_color, swirl_color, 0.5) * 1.2;
	final_color += fresnel_amount * rim_intensity * rim_color;

	// Calculate outer rim glow - subtle wider glow (reduced intensity)
	float outer_fresnel = fresnel(outer_rim_power, NORMAL, view_dir);
	vec3 outer_glow_color = mix(primary_color, secondary_color, 0.3) * 1.3;
	final_color += outer_fresnel * outer_rim_intensity * outer_glow_color;

	// Output material properties
	ALBEDO = final_color;
	ROUGHNESS = 1.0 - glossiness;
	METALLIC = metallic_amount;
	SPECULAR = specular_intensity;

	// Set to fully opaque for proper shadow casting and receiving
	ALPHA = 1.0;

	// Enhanced normal map detail from swirl pattern
	float normal_detail_x = (noise3d(world_pos * swirl_scale * 4.0 + vec3(0.1, 0.0, 0.0)) - 0.5) * 0.4;
	float normal_detail_y = (noise3d(world_pos * swirl_scale * 4.0 + vec3(0.0, 0.1, 0.0)) - 0.5) * 0.4;
	NORMAL_MAP = vec3(normal_detail_x, normal_detail_y, 1.0);
	NORMAL_MAP_DEPTH = 0.8;

	// === SPECIAL MARBLE LIGHTING - Subtle glow to help differentiate marbles ===
	// Pulsing glow animation (subtle)
	float pulse = 1.0 + sin(TIME * glow_pulse_speed) * glow_pulse_amount;

	// Base emission color from marble colors
	vec3 emission_base = mix(primary_color, secondary_color, 0.4);

	// Core glow - subtle inner light
	float core_glow = glow_strength * pulse;

	// Rim emission - gentle glow at edges (significantly reduced)
	float rim_emission = fresnel_amount * 0.3 + outer_fresnel * 0.15;

	// Combine emission components (reduced multipliers)
	vec3 total_emission = emission_base * core_glow * (0.15 + rim_emission * 0.2);

	// Add a very subtle highlight at steep angles
	total_emission += swirl_color * outer_fresnel * outer_fresnel * 0.08 * pulse;

	EMISSION = total_emission;
}
