extends Node3D

## Procedural Psychedelic Skybox Generator
## Creates trippy animated skyboxes

@export var animation_speed: float = 0.5
@export var color_palette: int = 0  # Different color schemes
@export var color_transition_duration: float = 10.0  # Time to transition between colors (seconds)
@export var color_hold_duration: float = 15.0  # Time to hold each color palette before transitioning

var sky_material: ShaderMaterial
var time_elapsed: float = 0.0

# Color transition variables
var current_colors: Array = []
var target_colors: Array = []
var transition_progress: float = 0.0
var hold_timer: float = 0.0
var is_transitioning: bool = false

func _ready() -> void:
	generate_skybox()

func _process(delta: float) -> void:
	# Animate the skybox
	if sky_material:
		time_elapsed += delta * animation_speed
		sky_material.set_shader_parameter("time", time_elapsed)

		# Handle color transitions
		if current_colors.size() > 0 and target_colors.size() > 0:
			if is_transitioning:
				# Transitioning between colors
				transition_progress += delta / color_transition_duration

				if transition_progress >= 1.0:
					# Transition complete
					transition_progress = 0.0
					is_transitioning = false
					current_colors = target_colors.duplicate()
					target_colors = generate_color_palette()
					hold_timer = 0.0
				else:
					# Smoothly interpolate between current and target colors
					var color1 = current_colors[0].lerp(target_colors[0], transition_progress)
					var color2 = current_colors[1].lerp(target_colors[1], transition_progress)
					var color3 = current_colors[2].lerp(target_colors[2], transition_progress)

					sky_material.set_shader_parameter("color1", color1)
					sky_material.set_shader_parameter("color2", color2)
					sky_material.set_shader_parameter("color3", color3)
			else:
				# Holding current colors
				hold_timer += delta

				if hold_timer >= color_hold_duration:
					# Start transitioning to next palette
					is_transitioning = true
					transition_progress = 0.0

func generate_skybox() -> void:
	"""Generate a psychedelic procedural skybox"""
	if OS.is_debug_build():
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

	# Initialize color transition system
	current_colors = generate_color_palette()
	target_colors = generate_color_palette()
	is_transitioning = false
	hold_timer = 0.0
	transition_progress = 0.0

	print("Skybox generated with gradual color transitions!")

func create_psychedelic_shader() -> ShaderMaterial:
	"""Create a shader for psychedelic sky effects"""
	var material: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()

	# Smooth psychedelic sky shader with anti-aliasing
	shader.code = """
shader_type sky;

uniform float time = 0.0;
uniform vec3 color1 = vec3(1.0, 0.2, 0.8);
uniform vec3 color2 = vec3(0.2, 0.8, 1.0);
uniform vec3 color3 = vec3(0.8, 1.0, 0.2);

// Improved hash function for smoother noise
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.13);
	p3 += dot(p3, p3.yzx + 3.333);
	return fract((p3.x + p3.y) * p3.z);
}

// Super smooth noise using quintic hermite interpolation
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);

	// Quintic hermite curve for ultra-smooth interpolation (removes jagged edges)
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// High-quality Fractal Brownian Motion with more octaves for smoothness
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;

	// Increased to 8 octaves for ultra-smooth transitions
	for (int i = 0; i < 8; i++) {
		value += amplitude * noise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}

	return value;
}

// Smooth color blending function
vec3 smooth_color_mix(vec3 a, vec3 b, float t) {
	// Use smoothstep for even smoother color transitions
	t = smoothstep(0.0, 1.0, t);
	return mix(a, b, t);
}

void sky() {
	// Get sky direction
	vec3 dir = normalize(EYEDIR);

	// Anti-aliased UV mapping with pole smoothing
	float phi = atan(dir.x, dir.z);
	float theta = acos(clamp(dir.y, -1.0, 1.0));

	vec2 uv = vec2(
		phi / (3.14159265 * 2.0) + 0.5,
		theta / 3.14159265
	);

	// Add slight offset to prevent seam artifacts
	uv.x = fract(uv.x);

	// Multiple layers of smooth animated fractal noise
	float n1 = fbm(uv * 3.0 + vec2(time * 0.1, -time * 0.08));
	float n2 = fbm(uv * 5.0 + vec2(-time * 0.15, time * 0.12));
	float n3 = fbm(uv * 7.0 + vec2(time * 0.2, time * 0.18));

	// Additional high-frequency layer for detail without jaggedness
	float n4 = fbm(uv * 10.0 + time * 0.25) * 0.5 + 0.5;

	// Smooth color mixing with gradual transitions
	vec3 color = smooth_color_mix(color1, color2, n1);
	color = smooth_color_mix(color, color3, n2);

	// Add shimmer with smooth blending
	color += vec3(n3 * 0.2);
	color = mix(color, color * 1.2, n4 * 0.15);

	// Ultra-smooth gradient from top to bottom with wider transition
	float gradient = smoothstep(-0.3, 0.9, dir.y);
	color = mix(color * 0.5, color, gradient);

	// Smooth pulsing effect
	float pulse = sin(time * 2.0) * 0.08 + 0.92;
	color *= pulse;

	// Apply gamma correction for smoother visual appearance
	color = pow(color, vec3(1.0 / 1.1));

	// Clamp to avoid any overflow artifacts
	color = clamp(color, 0.0, 1.0);

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
