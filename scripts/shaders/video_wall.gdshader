shader_type spatial;

// Video Wall Shader
// Displays video textures on 3D surfaces with pitch black background

render_mode unshaded, cull_back, depth_draw_opaque;

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

	// Sample video texture
	vec4 video_color = texture(video_texture, uv);

	// Use pitch black as background, blend video on top
	// This ensures any transparent or missing areas show as black
	vec3 black = vec3(0.0, 0.0, 0.0);
	ALBEDO = mix(black, video_color.rgb, video_color.a);
	ALPHA = 1.0;
}
