shader_type spatial;

// Video Wall Shader
// Displays video textures on 3D surfaces - 100% opaque, like a media player

render_mode unshaded, cull_back, depth_draw_opaque, blend_mix;

// Video texture from SubViewport
uniform sampler2D video_texture : source_color, filter_linear, repeat_disable;

// UV settings for proper mapping
uniform bool flip_h = false;
uniform bool flip_v = false;

void fragment() {
	// Calculate UV coordinates - stretched to fit the mesh
	vec2 uv = UV;

	// Apply flipping
	if (flip_h) {
		uv.x = 1.0 - uv.x;
	}
	if (flip_v) {
		uv.y = 1.0 - uv.y;
	}

	// Sample video texture - display exactly as-is, like a media player
	vec4 video_color = texture(video_texture, uv);

	// Output the video color directly - no modifications
	ALBEDO = video_color.rgb;
	ALPHA = 1.0;
}
