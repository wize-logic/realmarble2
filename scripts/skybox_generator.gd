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

	# Don't override glow settings - they're configured in the scene
	# Only enable minimal glow if completely disabled
	if not environment.glow_enabled:
		environment.glow_enabled = true
		environment.glow_intensity = 0.15
		environment.glow_strength = 0.3
		environment.glow_bloom = 0.05

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
uniform int quality_level = 1; // 0=low (web), 1=medium, 2=high

// Improved hash function for smoother noise
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.13);
	p3 += dot(p3, p3.yzx + 3.333);
	return fract((p3.x + p3.y) * p3.z);
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// 3D noise to avoid cylindrical UV seams
float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

	float n = dot(i, vec3(1.0, 57.0, 113.0));
	float a = hash3(i);
	float b = hash3(i + vec3(1.0, 0.0, 0.0));
	float c = hash3(i + vec3(0.0, 1.0, 0.0));
	float d = hash3(i + vec3(1.0, 1.0, 0.0));
	float e = hash3(i + vec3(0.0, 0.0, 1.0));
	float f2 = hash3(i + vec3(1.0, 0.0, 1.0));
	float g = hash3(i + vec3(0.0, 1.0, 1.0));
	float h = hash3(i + vec3(1.0, 1.0, 1.0));

	float k0 = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
	float k1 = mix(mix(e, f2, f.x), mix(g, h, f.x), f.y);
	return mix(k0, k1, f.z);
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

// 3D FBM using world direction (seamless, no UV seams)
float fbm3d(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	int octaves = quality_level >= 2 ? 8 : (quality_level >= 1 ? 5 : 3);

	for (int i = 0; i < 8; i++) {
		if (i >= octaves) break;
		value += amplitude * noise3d(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}

	return value;
}

// Fractal Brownian Motion with quality-dependent octave count (2D, for stars only)
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	int octaves = quality_level >= 2 ? 8 : (quality_level >= 1 ? 5 : 3);

	for (int i = 0; i < 8; i++) {
		if (i >= octaves) break;
		value += amplitude * noise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}

	return value;
}

// Star field generation using 3D direction (seamless)
float stars3d(vec3 dir, float density, float twinkle_time) {
	// Project direction onto a 3D grid for seamless star placement
	vec3 scaled = dir * 100.0;
	vec3 grid = floor(scaled);
	vec3 grid_frac = fract(scaled);

	float star = 0.0;
	float star_hash = hash3(grid);

	// Only place stars at random positions
	if (star_hash > (1.0 - density * 0.15)) {
		// Star position within cell
		vec3 star_pos = vec3(hash3(grid + 0.1), hash3(grid + 0.2), hash3(grid + 0.4));
		float dist = length(grid_frac - star_pos);

		// Star brightness with twinkle
		float brightness = hash3(grid + 0.3);
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

// Cloud layer using 3D direction (seamless, no UV seams)
float clouds3d(vec3 dir, float cloud_time, float density) {
	vec3 moving_dir = dir + vec3(cloud_time * 0.3, 0.0, cloud_time * 0.15);

	float cloud = fbm3d(moving_dir * 3.0);
	if (quality_level >= 1) {
		cloud += fbm3d(moving_dir * 6.0 + 10.0) * 0.5;
	}
	if (quality_level >= 2) {
		cloud += fbm3d(moving_dir * 12.0 + 20.0) * 0.25;
	}

	// Threshold for cloud coverage
	cloud = smoothstep(0.4 - density * 0.3, 0.7, cloud);

	return cloud * density;
}

// Nebula effect using 3D direction (seamless, no UV seams)
vec3 nebula3d(vec3 dir, float neb_time, vec3 col1, vec3 col2, vec3 col3) {
	vec3 moving_dir = dir + vec3(neb_time * 0.05, 0.0, -neb_time * 0.03);

	float n1 = fbm3d(moving_dir * 2.0);
	float n2 = fbm3d(moving_dir * 3.0 + vec3(10.0, 5.0, 7.0));
	float n3 = fbm3d(moving_dir * 4.0 + vec3(5.0, 10.0, 3.0));

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

	// Use 3D direction for all noise (seamless, no UV seam lines)
	// Base psychedelic background
	float n1 = fbm3d(dir * 3.0 + vec3(time * 0.1, -time * 0.08, time * 0.05));
	float n2 = fbm3d(dir * 5.0 + vec3(-time * 0.15, time * 0.12, -time * 0.07));

	// Base color mixing
	vec3 color = smooth_color_mix(color1, color2, n1);
	color = smooth_color_mix(color, color3, n2);

	// Add nebula effect (skip on low quality - saves 3 fbm calls per pixel)
	if (quality_level >= 1) {
		vec3 neb = nebula3d(dir, time, color1 * 0.8, color2 * 0.8, color3 * 0.8);
		color = mix(color, color + neb, nebula_intensity);
	}

	// Add cloud layer (tinted, not white)
	float cloud_layer = clouds3d(dir, time * cloud_speed, cloud_density);
	vec3 cloud_color = mix(color1, color2, 0.5) * 0.9 + vec3(0.1);  // Tinted clouds
	color = mix(color, cloud_color, cloud_layer * 0.4);

	// Add shimmer (use n2 instead of separate n3 fbm on low quality)
	float n3 = quality_level >= 1 ? fbm3d(dir * 7.0 + vec3(time * 0.2, time * 0.18, time * 0.1)) : n2;
	color += vec3(n3 * 0.15);

	// Ultra-smooth gradient from top to bottom
	float gradient = smoothstep(-0.3, 0.9, dir.y);
	color = mix(color * 0.4, color, gradient);

	// Smooth pulsing effect
	float pulse = sin(time * 2.0) * 0.06 + 0.94;
	color *= pulse;

	// Add star field (tinted stars, not pure white)
	float star_layer = stars3d(dir, star_density, time * star_twinkle_speed);
	// Stars are tinted slightly based on position
	vec3 star_tint = mix(vec3(0.9, 0.95, 1.0), vec3(1.0, 0.9, 0.85), hash3(dir * 100.0));
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
	# Auto-reduce quality on web platform (sky shader is the most expensive full-screen pass)
	var sky_quality: int = 0 if OS.has_feature("web") else 1
	material.set_shader_parameter("quality_level", sky_quality)

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
