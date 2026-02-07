shader_type canvas_item;

// Simple glow shader for logo
uniform vec4 base_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform float glow_intensity : hint_range(0.0, 5.0) = 2.0;
uniform float animation_speed : hint_range(0.0, 5.0) = 1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// Simple pulsing glow instead of plasma
	float pulse = sin(TIME * animation_speed) * 0.3 + 0.7;
	vec4 glow = mix(base_color, glow_color, pulse);

	COLOR = tex * glow;
	COLOR.rgb += glow_color.rgb * pulse * glow_intensity * tex.a * 0.3;
	COLOR.a = tex.a;
}
