extends Node3D

## Procedural Psychedelic Skybox Generator
## Creates trippy animated skyboxes with stars and cloud layers

@export var animation_speed: float = 0.5
@export var color_palette: int = 0  # Different color schemes
@export var color_transition_duration: float = 10.0  # Time to transition between colors (seconds)
@export var color_hold_duration: float = 15.0  # Time to hold each color palette before transitioning
@export var star_density: float = 0.3  # Density of stars (0-1)
@export var cloud_density: float = 0.4  # Density of clouds (0-1)
@export var nebula_intensity: float = 0.5  # Intensity of nebula effect

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
					# Transition complete - update shader with final target colors first
					sky_material.set_shader_parameter("color1", target_colors[0])
					sky_material.set_shader_parameter("color2", target_colors[1])
					sky_material.set_shader_parameter("color3", target_colors[2])

					# Now update the color variables
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
	"""Generate a psychedelic procedural skybox with stars and clouds"""
	if OS.is_debug_build():
		print("Generating procedural skybox with stars and clouds...")

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

	# Initialize color transition system FIRST
	current_colors = generate_color_palette()
	target_colors = generate_color_palette()
	is_transitioning = false
	hold_timer = 0.0
	transition_progress = 0.0

	# Create procedural sky material with the initial current_colors palette
	sky_material = create_enhanced_sky_shader(current_colors)
	sky.sky_material = sky_material

	# Keep existing environment settings, just add glow
	if not environment.glow_enabled:
		environment.glow_enabled = true
		environment.glow_intensity = 0.8
		environment.glow_strength = 1.2
		environment.glow_bloom = 0.3

	print("Enhanced skybox generated with stars, clouds, and gradual color transitions!")

func create_enhanced_sky_shader(colors: Array) -> ShaderMaterial:
	"""Create an enhanced shader for psychedelic sky effects with stars and clouds
	Args:
		colors: Array of 3 Color objects to use for the shader
	"""
	var material: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()

	# Enhanced psychedelic sky shader with stars, clouds, and nebula
	shader.code = """
shader_type sky;

uniform float time = 0.0;
uniform vec3 color1 = vec3(1.0, 0.2, 0.8);
uniform vec3 color2 = vec3(0.2, 0.8, 1.0);
uniform vec3 color3 = vec3(0.8, 1.0, 0.2);

// Star and cloud parameters
uniform float star_density = 0.3;
uniform float star_twinkle_speed = 2.0;
uniform float cloud_density = 0.4;
uniform float cloud_speed = 0.1;
uniform float nebula_intensity = 0.5;

// Improved hash function for smoother noise
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.13);
	p3 += dot(p3, p3.yzx + 3.333);
	return fract((p3.x + p3.y) * p3.z);
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// Super smooth noise using quintic hermite interpolation
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);

	// Quintic hermite curve for ultra-smooth interpolation
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// High-quality Fractal Brownian Motion
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;

	for (int i = 0; i < 8; i++) {
		value += amplitude * noise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}

	return value;
}

// Star field generation
float stars(vec2 uv, float density, float twinkle_time) {
	// Grid-based star placement
	vec2 grid = floor(uv * 200.0);
	vec2 grid_uv = fract(uv * 200.0);

	float star = 0.0;
	float star_hash = hash(grid);

	// Only place stars at random positions
	if (star_hash > (1.0 - density * 0.15)) {
		// Star position within cell
		vec2 star_pos = vec2(hash(grid + 0.1), hash(grid + 0.2));
		float dist = length(grid_uv - star_pos);

		// Star brightness with twinkle
		float brightness = hash(grid + 0.3);
		float twinkle = sin(twinkle_time * (brightness * 3.0 + 1.0) + star_hash * 6.28) * 0.3 + 0.7;

		// Star glow (not pure white - tinted)
		star = smoothstep(0.08, 0.0, dist) * brightness * twinkle;

		// Larger bright stars (rarer)
		if (star_hash > 0.98) {
			star = smoothstep(0.12, 0.0, dist) * twinkle * 1.5;
		}
	}

	return star;
}

// Cloud layer
float clouds(vec2 uv, float cloud_time, float density) {
	vec2 moving_uv = uv + vec2(cloud_time * 0.3, cloud_time * 0.15);

	float cloud = fbm(moving_uv * 3.0);
	cloud += fbm(moving_uv * 6.0 + 10.0) * 0.5;
	cloud += fbm(moving_uv * 12.0 + 20.0) * 0.25;

	// Threshold for cloud coverage
	cloud = smoothstep(0.4 - density * 0.3, 0.7, cloud);

	return cloud * density;
}

// Nebula effect
vec3 nebula(vec2 uv, float neb_time, vec3 col1, vec3 col2, vec3 col3) {
	vec2 moving_uv = uv + vec2(neb_time * 0.05, -neb_time * 0.03);

	float n1 = fbm(moving_uv * 2.0);
	float n2 = fbm(moving_uv * 3.0 + vec2(10.0, 5.0));
	float n3 = fbm(moving_uv * 4.0 + vec2(5.0, 10.0));

	vec3 nebula_color = mix(col1, col2, n1);
	nebula_color = mix(nebula_color, col3, n2 * 0.5);

	float intensity = n3 * 0.5 + 0.5;

	return nebula_color * intensity;
}

// Smooth color blending function
vec3 smooth_color_mix(vec3 a, vec3 b, float t) {
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

	// Base psychedelic background
	float n1 = fbm(uv * 3.0 + vec2(time * 0.1, -time * 0.08));
	float n2 = fbm(uv * 5.0 + vec2(-time * 0.15, time * 0.12));
	float n3 = fbm(uv * 7.0 + vec2(time * 0.2, time * 0.18));

	// Base color mixing
	vec3 color = smooth_color_mix(color1, color2, n1);
	color = smooth_color_mix(color, color3, n2);

	// Add nebula effect
	vec3 neb = nebula(uv, time, color1 * 0.8, color2 * 0.8, color3 * 0.8);
	color = mix(color, color + neb, nebula_intensity);

	// Add cloud layer (tinted, not white)
	float cloud_layer = clouds(uv, time * cloud_speed, cloud_density);
	vec3 cloud_color = mix(color1, color2, 0.5) * 0.9 + vec3(0.1);  // Tinted clouds
	color = mix(color, cloud_color, cloud_layer * 0.4);

	// Add shimmer
	color += vec3(n3 * 0.15);

	// Ultra-smooth gradient from top to bottom
	float gradient = smoothstep(-0.3, 0.9, dir.y);
	color = mix(color * 0.4, color, gradient);

	// Smooth pulsing effect
	float pulse = sin(time * 2.0) * 0.06 + 0.94;
	color *= pulse;

	// Add star field (tinted stars, not pure white)
	float star_layer = stars(uv, star_density, time * star_twinkle_speed);
	// Stars are tinted slightly based on position
	vec3 star_tint = mix(vec3(0.9, 0.95, 1.0), vec3(1.0, 0.9, 0.85), hash(uv * 100.0));
	color += star_layer * star_tint * 0.8;

	// Apply gamma correction
	color = pow(color, vec3(1.0 / 1.1));

	// Clamp to avoid overflow
	color = clamp(color, 0.0, 1.0);

	COLOR = color;
}
"""

	material.shader = shader

	# Use the provided color palette
	material.set_shader_parameter("color1", colors[0])
	material.set_shader_parameter("color2", colors[1])
	material.set_shader_parameter("color3", colors[2])
	material.set_shader_parameter("time", 0.0)
	material.set_shader_parameter("star_density", star_density)
	material.set_shader_parameter("cloud_density", cloud_density)
	material.set_shader_parameter("nebula_intensity", nebula_intensity)

	return material

func generate_color_palette() -> Array:
	"""Generate random psychedelic color palette (no pure whites)"""
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
		[Color(1.0, 0.3, 0.1), Color(1.0, 0.6, 0.3), Color(0.8, 0.2, 0.6)],
		# Northern Lights
		[Color(0.1, 0.8, 0.5), Color(0.3, 0.5, 1.0), Color(0.6, 0.2, 0.9)],
		# Tropical
		[Color(1.0, 0.4, 0.6), Color(0.2, 0.9, 0.8), Color(1.0, 0.8, 0.3)],
		# Deep Space
		[Color(0.15, 0.1, 0.4), Color(0.4, 0.1, 0.5), Color(0.1, 0.3, 0.6)]
	]

	return palettes[randi() % palettes.size()]

func randomize_colors() -> void:
	"""Change to a new random color palette"""
	if sky_material:
		var colors: Array = generate_color_palette()
		sky_material.set_shader_parameter("color1", colors[0])
		sky_material.set_shader_parameter("color2", colors[1])
		sky_material.set_shader_parameter("color3", colors[2])

		# Update transition system to stay in sync
		current_colors = colors.duplicate()
		target_colors = generate_color_palette()
		is_transitioning = false
		hold_timer = 0.0
		transition_progress = 0.0

		print("Skybox colors randomized!")

func set_star_density(density: float) -> void:
	"""Set the density of stars in the skybox"""
	star_density = clamp(density, 0.0, 1.0)
	if sky_material:
		sky_material.set_shader_parameter("star_density", star_density)

func set_cloud_density(density: float) -> void:
	"""Set the density of clouds in the skybox"""
	cloud_density = clamp(density, 0.0, 1.0)
	if sky_material:
		sky_material.set_shader_parameter("cloud_density", cloud_density)

func set_nebula_intensity(intensity: float) -> void:
	"""Set the intensity of nebula effect"""
	nebula_intensity = clamp(intensity, 0.0, 1.0)
	if sky_material:
		sky_material.set_shader_parameter("nebula_intensity", nebula_intensity)
