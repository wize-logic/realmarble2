shader_type spatial;

// Video Wall Shader
// Displays video texture on 3D surfaces — fully unshaded, no effects

render_mode unshaded, cull_back, depth_draw_opaque,
	ambient_light_disabled, fog_disabled, shadows_disabled;

// Video texture from SubViewport (no source_color — viewport texture
// is already in the correct color space, avoid double conversion)
uniform sampler2D video_texture : filter_linear, repeat_disable;

// UV settings for proper mapping
uniform bool flip_h = false;
uniform bool flip_v = false;

void fragment() {
	vec2 uv = UV;

	if (flip_h) {
		uv.x = 1.0 - uv.x;
	}
	if (flip_v) {
		uv.y = 1.0 - uv.y;
	}

	ALBEDO = texture(video_texture, uv).rgb;
}
