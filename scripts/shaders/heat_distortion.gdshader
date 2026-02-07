shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

// Distortion settings (kept for compatibility but effect is minimal)
uniform float distortion_strength : hint_range(0.0, 0.1) = 0.02;
uniform float distortion_speed : hint_range(0.0, 5.0) = 1.5;
uniform float wave_scale : hint_range(1.0, 20.0) = 8.0;
uniform float fade_distance : hint_range(1.0, 20.0) = 10.0;
uniform vec3 heat_tint : source_color = vec3(1.0, 0.95, 0.9);
uniform float tint_strength : hint_range(0.0, 0.3) = 0.05;
uniform int quality_level : hint_range(0, 2) = 1;
uniform float opacity : hint_range(0.0, 1.0) = 0.15;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 screen_uv = SCREEN_UV;
	float dist = length(VERTEX);
	float fade = smoothstep(fade_distance, 0.0, dist);

	// Simple sine-wave distortion instead of FBM
	float time = TIME * distortion_speed;
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 distortion;
	distortion.x = sin(world_pos.x * wave_scale + time) * 0.5;
	distortion.y = sin(world_pos.z * wave_scale + time * 1.3) * 0.5;
	distortion *= distortion_strength * fade;

	vec3 screen_color = texture(screen_texture, screen_uv + distortion).rgb;
	screen_color = mix(screen_color, screen_color * heat_tint, tint_strength * fade);

	ALBEDO = screen_color;
	ALPHA = opacity * fade;
}
