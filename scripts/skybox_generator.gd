extends Node3D

## Dark Psychedelic Skybox Generator
## Creates trippy animated skyboxes with darker colors

@export var animation_speed: float = 0.3
@export var color_palette: int = 0  # Different color schemes

var sky_material: ShaderMaterial
var time_elapsed: float = 0.0

func _ready() -> void:
	generate_skybox()

func _process(delta: float) -> void:
	# Animate the skybox
	if sky_material:
		time_elapsed += delta * animation_speed
		sky_material.set_shader_parameter("time", time_elapsed)

func generate_skybox() -> void:
	"""Generate a dark psychedelic procedural skybox"""
	if OS.is_debug_build():
		print("Generating dark psychedelic skybox...")

	# Get existing WorldEnvironment
	var world_env: WorldEnvironment = get_node_or_null("/root/World/WorldEnvironment")
	if not world_env:
		print("ERROR: WorldEnvironment not found!")
		return

	# Use existing environment or create new one
	var environment: Environment = world_env.environment
	if not environment:
		environment = Environment.new()
		world_env.environment = environment

	# Create custom sky
	var sky: Sky = Sky.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky

	# Create dark psychedelic sky material
	sky_material = create_dark_psychedelic_shader()
	sky.sky_material = sky_material

	# Minimal lighting to keep map dark
	environment.glow_enabled = true
	environment.glow_intensity = 0.15
	environment.glow_strength = 0.6
	environment.glow_bloom = 0.05
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Very low ambient light for dark atmosphere
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.08

	# Dark tone mapping
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.7
	environment.tonemap_white = 1.0

	print("Dark psychedelic skybox generated!")

func create_dark_psychedelic_shader() -> ShaderMaterial:
	"""Create a shader for dark psychedelic sky effects"""
	var material: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()

	# Dark psychedelic sky shader with animated fractals
	shader.code = """
shader_type sky;

uniform float time = 0.0;
uniform vec3 color1 = vec3(0.5, 0.1, 0.4);
uniform vec3 color2 = vec3(0.1, 0.4, 0.5);
uniform vec3 color3 = vec3(0.4, 0.5, 0.1);

// Hash function for noise
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth noise
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

// Fractal Brownian Motion
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;

	for (int i = 0; i < 6; i++) {
		value += amplitude * noise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}

	return value;
}

// Voronoi pattern for extra detail
float voronoi(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);

	float min_dist = 1.0;

	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 b = vec2(float(i), float(j));
			vec2 r = b - f + hash(n + b) * vec2(1.0);
			float d = length(r);
			min_dist = min(min_dist, d);
		}
	}

	return min_dist;
}

// Spiral pattern
vec2 rotate(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

void sky() {
	// Get sky direction
	vec3 dir = EYEDIR;

	// Create swirling pattern
	vec2 uv = vec2(
		atan(dir.x, dir.z) / (3.14159 * 2.0) + 0.5,
		acos(dir.y) / 3.14159
	);

	// Add spiral distortion
	vec2 center = vec2(0.5, 0.5);
	vec2 toCenter = uv - center;
	float dist = length(toCenter);
	float angle = atan(toCenter.y, toCenter.x);
	angle += time * 0.3 + dist * 2.0;
	uv = center + rotate(toCenter, angle * 0.2);

	// Multiple layers of animated fractal noise
	float n1 = fbm(uv * 3.0 + vec2(time * 0.15, -time * 0.1));
	float n2 = fbm(uv * 5.0 + vec2(-time * 0.2, time * 0.15));
	float n3 = fbm(uv * 8.0 + vec2(time * 0.25, time * 0.2));

	// Add voronoi for cellular patterns
	float v1 = voronoi(uv * 4.0 + time * 0.1);
	float v2 = voronoi(uv * 7.0 - time * 0.15);

	// Color mixing based on noise - darker colors
	vec3 color = mix(color1 * 0.5, color2 * 0.6, n1);
	color = mix(color, color3 * 0.5, n2);

	// Add voronoi influence
	color = mix(color, color * 0.7, v1);
	color += vec3(v2 * 0.1);

	// Add shimmer and detail - but keep it dark
	color += vec3(n3 * 0.15);

	// Gradient from top to bottom - very dark
	float gradient = smoothstep(-0.3, 0.9, dir.y);
	color = mix(color * 0.3, color * 0.7, gradient);

	// Pulsing effect - subtle
	float pulse = sin(time * 1.5) * 0.08 + 0.92;
	color *= pulse;

	// Wave distortion for extra psychedelia
	float wave = sin(uv.x * 10.0 + time) * sin(uv.y * 10.0 - time);
	color += vec3(wave * 0.05);

	// Keep overall darkness
	color *= 0.6;

	COLOR = color;
}
"""

	material.shader = shader

	# Dark psychedelic color palette
	var colors: Array = generate_dark_color_palette()
	material.set_shader_parameter("color1", colors[0])
	material.set_shader_parameter("color2", colors[1])
	material.set_shader_parameter("color3", colors[2])
	material.set_shader_parameter("time", 0.0)

	return material

func generate_dark_color_palette() -> Array:
	"""Generate dark psychedelic color palette"""
	var palettes: Array = [
		# Dark Purple/Pink/Cyan
		[Color(0.4, 0.1, 0.5), Color(0.5, 0.15, 0.35), Color(0.1, 0.4, 0.5)],
		# Dark Orange/Red/Brown
		[Color(0.5, 0.25, 0.0), Color(0.5, 0.05, 0.1), Color(0.4, 0.3, 0.1)],
		# Dark Green/Teal/Blue
		[Color(0.0, 0.4, 0.25), Color(0.2, 0.5, 0.3), Color(0.1, 0.3, 0.5)],
		# Dark Blue/Purple/Magenta
		[Color(0.1, 0.2, 0.5), Color(0.3, 0.1, 0.5), Color(0.5, 0.1, 0.4)],
		# Dark Sunset
		[Color(0.5, 0.15, 0.05), Color(0.5, 0.3, 0.15), Color(0.4, 0.1, 0.3)]
	]

	return palettes[randi() % palettes.size()]

func randomize_colors() -> void:
	"""Change to a new random color palette"""
	if sky_material:
		var colors: Array = generate_dark_color_palette()
		sky_material.set_shader_parameter("color1", colors[0])
		sky_material.set_shader_parameter("color2", colors[1])
		sky_material.set_shader_parameter("color3", colors[2])
		print("Skybox colors randomized!")
