shader_type canvas_item;

// Card glow shader for menu buttons
uniform vec4 glow_color : source_color = vec4(0.3, 0.7, 1.0, 1.0);
uniform float glow_strength : hint_range(0.0, 3.0) = 1.0;
uniform float edge_thickness : hint_range(0.0, 0.5) = 0.05;
uniform float pulse_speed : hint_range(0.0, 5.0) = 2.0;
uniform bool is_hovered = false;

void fragment() {
	vec2 uv = UV;
	vec4 tex = texture(TEXTURE, uv);

	// Calculate distance from edges
	float dist_x = min(uv.x, 1.0 - uv.x);
	float dist_y = min(uv.y, 1.0 - uv.y);
	float edge_dist = min(dist_x, dist_y);

	// Edge glow
	float edge_glow = smoothstep(edge_thickness, 0.0, edge_dist);

	// Pulsing effect
	float pulse = (sin(TIME * pulse_speed) + 1.0) * 0.5;
	float pulse_amount = mix(0.3, 1.0, pulse);

	// Apply glow based on hover state
	float glow_multiplier = is_hovered ? 2.0 : 1.0;
	vec3 glow = glow_color.rgb * edge_glow * glow_strength * pulse_amount * glow_multiplier;

	// Combine with original texture
	COLOR.rgb = tex.rgb + glow;
	COLOR.a = tex.a + edge_glow * 0.5;
}
