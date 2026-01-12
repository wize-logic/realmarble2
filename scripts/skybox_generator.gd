extends Node3D

## Procedural Psychedelic Skybox Generator
## Creates trippy animated skyboxes

@export var animation_speed: float = 0.5
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
	"""Generate a psychedelic procedural skybox"""
	print("Generating procedural skybox...")

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

	# Create procedural sky material
	sky_material = create_psychedelic_shader()
	sky.sky_material = sky_material

	# Keep existing environment settings, just add glow
	if not environment.glow_enabled:
		environment.glow_enabled = true
		environment.glow_intensity = 0.8
		environment.glow_strength = 1.2
		environment.glow_bloom = 0.3

	print("Skybox generated!")

func create_psychedelic_shader() -> ShaderMaterial:
	"""Create a shader for psychedelic sky effects"""
	var material: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()

	# Psychedelic sky shader with animated fractals
	shader.code = """
shader_type sky;

uniform float time = 0.0;
uniform vec3 color1 = vec3(1.0, 0.2, 0.8);
uniform vec3 color2 = vec3(0.2, 0.8, 1.0);
uniform vec3 color3 = vec3(0.8, 1.0, 0.2);

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

	for (int i = 0; i < 5; i++) {
		value += amplitude * noise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}

	return value;
}

void sky() {
	// Get sky direction
	vec3 dir = EYEDIR;

	// Create swirling pattern
	vec2 uv = vec2(
		atan(dir.x, dir.z) / (3.14159 * 2.0) + 0.5,
		acos(dir.y) / 3.14159
	);

	// Animated fractal noise
	float n1 = fbm(uv * 3.0 + time * 0.1);
	float n2 = fbm(uv * 5.0 - time * 0.15);
	float n3 = fbm(uv * 7.0 + time * 0.2);

	// Color mixing based on noise
	vec3 color = mix(color1, color2, n1);
	color = mix(color, color3, n2);

	// Add some shimmer
	color += vec3(n3 * 0.3);

	// Gradient from top to bottom
	float gradient = smoothstep(-0.2, 0.8, dir.y);
	color = mix(color * 0.5, color, gradient);

	// Pulsing effect
	float pulse = sin(time * 2.0) * 0.1 + 0.9;
	color *= pulse;

	COLOR = color;
}
"""

	material.shader = shader

	# Random color palette
	var colors: Array = generate_color_palette()
	material.set_shader_parameter("color1", colors[0])
	material.set_shader_parameter("color2", colors[1])
	material.set_shader_parameter("color3", colors[2])
	material.set_shader_parameter("time", 0.0)

	return material

func generate_color_palette() -> Array:
	"""Generate random psychedelic color palette"""
	var palettes: Array = [
		# Purple/Pink/Cyan
		[Color(0.8, 0.2, 1.0), Color(1.0, 0.3, 0.7), Color(0.2, 0.8, 1.0)],
		# Orange/Red/Yellow
		[Color(1.0, 0.5, 0.0), Color(1.0, 0.1, 0.2), Color(1.0, 0.9, 0.2)],
		# Green/Lime/Cyan
		[Color(0.0, 1.0, 0.5), Color(0.5, 1.0, 0.2), Color(0.2, 1.0, 1.0)],
		# Blue/Purple/Magenta
		[Color(0.2, 0.4, 1.0), Color(0.6, 0.2, 1.0), Color(1.0, 0.2, 0.8)],
		# Sunset
		[Color(1.0, 0.3, 0.1), Color(1.0, 0.6, 0.3), Color(0.8, 0.2, 0.6)]
	]

	return palettes[randi() % palettes.size()]

func randomize_colors() -> void:
	"""Change to a new random color palette"""
	if sky_material:
		var colors: Array = generate_color_palette()
		sky_material.set_shader_parameter("color1", colors[0])
		sky_material.set_shader_parameter("color2", colors[1])
		sky_material.set_shader_parameter("color3", colors[2])
		print("Skybox colors randomized!")
