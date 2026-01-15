shader_type canvas_item;

// Animated plasma glow shader for logo
uniform vec4 base_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform float glow_intensity : hint_range(0.0, 5.0) = 2.0;
uniform float animation_speed : hint_range(0.0, 5.0) = 1.0;

// Plasma noise functions
float noise(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float plasma(vec2 uv, float time) {
	float v = 0.0;
	v += sin(uv.x * 10.0 + time);
	v += sin(uv.y * 10.0 + time * 0.5);
	v += sin((uv.x + uv.y) * 10.0 + time * 0.3);
	v += sin(sqrt(uv.x * uv.x + uv.y * uv.y) * 10.0 + time * 0.7);
	return v * 0.25;
}

void fragment() {
	vec2 uv = UV;
	float time = TIME * animation_speed;

	// Sample original texture
	vec4 tex = texture(TEXTURE, uv);

	// Generate plasma effect
	float p = plasma(uv, time);
	p = (p + 1.0) * 0.5; // Normalize to 0-1

	// Mix colors based on plasma
	vec4 plasma_color = mix(base_color, glow_color, p);

	// Apply to texture alpha channel
	COLOR = tex * plasma_color;
	COLOR.rgb += glow_color.rgb * p * glow_intensity * tex.a;
	COLOR.a = tex.a;
}
