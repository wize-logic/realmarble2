shader_type spatial;

// Video Wall Shader
// Displays video texture on 3D surfaces — fully unshaded, no effects
// Compatible with GL Compatibility renderer

render_mode unshaded, cull_back, depth_draw_opaque;

// Video texture from SubViewport
uniform sampler2D video_texture : filter_linear, repeat_disable;

// UV settings for proper mapping
uniform bool flip_h = false;
uniform bool flip_v = false;

// Brightness control
uniform float brightness : hint_range(0.5, 2.0) = 1.0;

void fragment() {
	vec2 uv = UV;

	if (flip_h) {
		uv.x = 1.0 - uv.x;
	}
	if (flip_v) {
		uv.y = 1.0 - uv.y;
	}

	vec3 color = texture(video_texture, uv).rgb;
	ALBEDO = color * brightness;
}
