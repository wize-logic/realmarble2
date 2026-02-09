shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

// Hazard type: 0 = lava, 1 = slime
uniform int hazard_type : hint_range(0, 1) = 0;

// Lava colors
uniform vec3 lava_base_color : source_color = vec3(0.9, 0.25, 0.0);
uniform vec3 lava_hot_color : source_color = vec3(1.0, 0.6, 0.1);
uniform vec3 lava_glow_color : source_color = vec3(1.0, 0.4, 0.05);

// Slime colors
uniform vec3 slime_base_color : source_color = vec3(0.15, 0.6, 0.15);
uniform vec3 slime_bright_color : source_color = vec3(0.3, 0.9, 0.25);
uniform vec3 slime_glow_color : source_color = vec3(0.1, 0.5, 0.1);

uniform float flow_speed : hint_range(0.0, 2.0) = 0.4;
uniform float turbulence : hint_range(0.0, 2.0) = 1.0;
uniform float glow_intensity : hint_range(0.5, 5.0) = 2.5;

// Simple noise
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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * 0.15;
	float time = TIME * flow_speed;

	// Simple flowing pattern with one noise sample
	float flow = noise(uv * turbulence + vec2(time * 0.3, time * 0.2));

	// Pulsing glow
	float pulse = sin(TIME * 2.0) * 0.15 + 0.85;

	vec3 final_color;
	float emission_strength;

	if (hazard_type == 0) {
		// LAVA - simple mix between base and hot
		final_color = mix(lava_base_color, lava_hot_color, flow);
		emission_strength = glow_intensity * pulse;
	} else {
		// SLIME
		final_color = mix(slime_base_color, slime_bright_color, flow * 0.7);
		emission_strength = (glow_intensity * 0.6) * pulse;
	}

	ALBEDO = final_color;
	EMISSION = final_color * emission_strength;
}
