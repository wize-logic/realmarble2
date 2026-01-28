shader_type spatial;

// Video Wall Shader
// Displays video textures on 3D surfaces with optional effects

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Video texture from SubViewport
uniform sampler2D video_texture : source_color, filter_linear, repeat_disable;

// Display settings
uniform float brightness : hint_range(0.0, 2.0) = 1.0;
uniform float contrast : hint_range(0.0, 2.0) = 1.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform vec3 tint_color : source_color = vec3(1.0, 1.0, 1.0);

// Edge glow effect
uniform bool enable_edge_glow = true;
uniform vec3 edge_glow_color : source_color = vec3(0.2, 0.6, 1.0);
uniform float edge_glow_intensity : hint_range(0.0, 2.0) = 0.5;
uniform float edge_glow_width : hint_range(0.0, 0.2) = 0.05;

// Scanline effect (optional retro look)
uniform bool enable_scanlines = false;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float scanline_count : hint_range(10.0, 500.0) = 100.0;

// Emission for self-illumination
uniform float emission_strength : hint_range(0.0, 5.0) = 0.5;

// UV settings for proper mapping
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform bool flip_h = false;
uniform bool flip_v = false;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 adjust_saturation(vec3 color, float sat) {
	float gray = dot(color, vec3(0.299, 0.587, 0.114));
	return mix(vec3(gray), color, sat);
}

void fragment() {
	// Calculate UV coordinates based on wall orientation
	vec2 uv = UV;

	// Apply UV transformations
	uv = uv * uv_scale + uv_offset;

	// Apply flipping
	if (flip_h) {
		uv.x = 1.0 - uv.x;
	}
	if (flip_v) {
		uv.y = 1.0 - uv.y;
	}

	// Sample video texture
	vec4 video_color = texture(video_texture, uv);

	// Apply color adjustments
	vec3 color = video_color.rgb;

	// Contrast adjustment
	color = (color - 0.5) * contrast + 0.5;

	// Brightness adjustment
	color *= brightness;

	// Saturation adjustment
	color = adjust_saturation(color, saturation);

	// Apply tint
	color *= tint_color;

	// Scanline effect
	if (enable_scanlines) {
		float scanline = sin(uv.y * scanline_count * 3.14159) * 0.5 + 0.5;
		color = mix(color, color * (1.0 - scanline_intensity), scanline * scanline_intensity);
	}

	// Edge glow effect
	vec3 emission = vec3(0.0);
	if (enable_edge_glow) {
		float edge_x = smoothstep(0.0, edge_glow_width, uv.x) * smoothstep(0.0, edge_glow_width, 1.0 - uv.x);
		float edge_y = smoothstep(0.0, edge_glow_width, uv.y) * smoothstep(0.0, edge_glow_width, 1.0 - uv.y);
		float edge = 1.0 - (edge_x * edge_y);
		emission += edge_glow_color * edge * edge_glow_intensity;
	}

	// Set output
	ALBEDO = color;
	EMISSION = color * emission_strength + emission;
	ROUGHNESS = 0.5;
	METALLIC = 0.0;
}
