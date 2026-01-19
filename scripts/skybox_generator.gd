extends Node3D

## Beautiful Atmospheric Skybox Generator
## Creates stunning realistic skies with detailed volumetric clouds

@export var animation_speed: float = 0.02  # Slow, realistic cloud movement
@export var cloud_density: float = 0.5  # 0.0 = clear, 1.0 = overcast
@export var sun_intensity: float = 1.0
@export var time_of_day: float = 0.4  # 0.0 = sunrise, 0.5 = noon, 1.0 = sunset

var sky_material: ShaderMaterial
var time_elapsed: float = 0.0

func _ready() -> void:
	generate_skybox()

func _process(delta: float) -> void:
	# Animate the clouds slowly
	if sky_material:
		time_elapsed += delta * animation_speed
		sky_material.set_shader_parameter("time", time_elapsed)

func generate_skybox() -> void:
	"""Generate a beautiful atmospheric skybox with detailed clouds"""
	if OS.is_debug_build():
		print("Generating beautiful atmospheric skybox with HD clouds...")

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

	# Create realistic atmospheric sky shader
	sky_material = create_atmospheric_sky_shader()
	sky.sky_material = sky_material

	# Enhanced environment settings for beautiful visuals
	environment.glow_enabled = true
	environment.glow_intensity = 0.4
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.15
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Add subtle ambient light from sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.8

	# Subtle tone mapping for realistic look
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 1.0

	print("Beautiful skybox with HD clouds generated!")

func create_atmospheric_sky_shader() -> ShaderMaterial:
	"""Create a beautiful realistic atmospheric sky shader with detailed clouds"""
	var material: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()

	# Beautiful atmospheric sky with volumetric clouds
	shader.code = """
shader_type sky;

uniform float time = 0.0;
uniform float cloud_density = 0.5;
uniform float sun_intensity = 1.0;
uniform vec3 sun_direction = vec3(0.3, 0.5, 0.2);

// === High-Quality Noise Functions for Detailed Clouds ===

// 3D Hash for better randomness
vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
			 dot(p, vec3(269.5, 183.3, 246.1)),
			 dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

// 3D Value noise for volumetric clouds
float noise3D(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = dot(hash3(i), vec3(1.0));
	float n100 = dot(hash3(i + vec3(1.0, 0.0, 0.0)), vec3(1.0));
	float n010 = dot(hash3(i + vec3(0.0, 1.0, 0.0)), vec3(1.0));
	float n110 = dot(hash3(i + vec3(1.0, 1.0, 0.0)), vec3(1.0));
	float n001 = dot(hash3(i + vec3(0.0, 0.0, 1.0)), vec3(1.0));
	float n101 = dot(hash3(i + vec3(1.0, 0.0, 1.0)), vec3(1.0));
	float n011 = dot(hash3(i + vec3(0.0, 1.0, 1.0)), vec3(1.0));
	float n111 = dot(hash3(i + vec3(1.0, 1.0, 1.0)), vec3(1.0));

	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			   mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// High-detail Fractal Brownian Motion (8 octaves for HD detail)
float fbm(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;

	// 8 octaves for very detailed clouds
	for (int i = 0; i < 8; i++) {
		value += amplitude * noise3D(p * frequency);
		frequency *= 2.07;  // Slightly irregular for more natural look
		amplitude *= 0.5;
	}

	return value;
}

// Worley/Cellular noise for fluffy cloud details
float worley(vec3 p) {
	vec3 id = floor(p);
	vec3 fd = fract(p);

	float min_dist = 1.0;

	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 coord = vec3(float(x), float(y), float(z));
				vec3 point = hash3(id + coord);

				point = 0.5 + 0.5 * sin(time * 0.01 + 6.2831 * point);
				vec3 diff = coord + point - fd;
				float dist = length(diff);

				min_dist = min(min_dist, dist);
			}
		}
	}

	return min_dist;
}

// === Atmospheric Scattering ===

vec3 rayleigh_scatter(float cos_theta) {
	// Blue sky scattering
	float phase = 0.75 * (1.0 + cos_theta * cos_theta);
	return vec3(0.058, 0.135, 0.331) * phase;
}

vec3 mie_scatter(float cos_theta) {
	// Sun glow scattering
	float g = 0.76;
	float gg = g * g;
	float phase = (1.5 * (1.0 - gg)) / (2.0 + gg) *
				  (1.0 + cos_theta * cos_theta) /
				  pow(1.0 + gg - 2.0 * g * cos_theta, 1.5);
	return vec3(1.0, 0.98, 0.95) * phase * 0.1;
}

// === Cloud Rendering ===

vec4 render_clouds(vec3 dir, float height_factor) {
	// Multiple cloud layers for depth
	vec3 cloud_pos = dir * 2.0;

	// Layer 1: Large cumulus clouds
	float cloud_scale_1 = 1.5;
	float clouds_1 = fbm(cloud_pos * cloud_scale_1 + vec3(time * 0.5, 0.0, time * 0.3));

	// Layer 2: Medium detail clouds
	float cloud_scale_2 = 3.0;
	float clouds_2 = fbm(cloud_pos * cloud_scale_2 + vec3(time * 0.3, 0.0, -time * 0.2));

	// Layer 3: Fine detail / wisps
	float cloud_scale_3 = 6.0;
	float clouds_3 = fbm(cloud_pos * cloud_scale_3 + vec3(-time * 0.4, 0.0, time * 0.25));

	// Layer 4: Fluffy cellular details
	float worley_detail = worley(cloud_pos * 4.0 + vec3(time * 0.1, 0.0, 0.0));

	// Combine layers
	float cloud_pattern = clouds_1 * 0.5 + clouds_2 * 0.3 + clouds_3 * 0.2;
	cloud_pattern = mix(cloud_pattern, 1.0 - worley_detail, 0.3);

	// Adjust by height - more clouds at horizon, less at zenith
	float height_influence = 1.0 - smoothstep(0.0, 0.4, height_factor);
	cloud_pattern += height_influence * 0.2;

	// Apply density control
	cloud_pattern = smoothstep(0.4 - cloud_density * 0.2, 0.7 + cloud_density * 0.2, cloud_pattern);

	// Cloud lighting - brighter on sun side
	vec3 cloud_light_dir = normalize(sun_direction);
	float cloud_lighting = dot(normalize(dir), cloud_light_dir);
	cloud_lighting = smoothstep(-0.2, 0.6, cloud_lighting);

	// Cloud colors - white to grey with sun influence
	vec3 cloud_bright = vec3(1.0, 1.0, 1.0);
	vec3 cloud_dark = vec3(0.5, 0.55, 0.6);
	vec3 cloud_color = mix(cloud_dark, cloud_bright, cloud_lighting);

	// Add subtle color variation
	cloud_color += vec3(0.05, 0.08, 0.1) * clouds_3;

	// Sun illumination on clouds
	float sun_highlight = pow(max(dot(normalize(dir), cloud_light_dir), 0.0), 8.0);
	cloud_color += vec3(1.0, 0.9, 0.7) * sun_highlight * 0.3;

	return vec4(cloud_color, cloud_pattern);
}

// === Main Sky Function ===

void sky() {
	vec3 dir = EYEDIR;

	// Sky gradient base
	float height = dir.y;
	float height_factor = clamp(height, 0.0, 1.0);

	// Atmospheric colors
	vec3 zenith_color = vec3(0.1, 0.3, 0.65);  // Deep blue
	vec3 horizon_color = vec3(0.6, 0.75, 0.9);  // Light blue/white

	// Base sky gradient
	vec3 sky_color = mix(horizon_color, zenith_color, pow(height_factor, 0.7));

	// Add atmospheric scattering
	vec3 sun_dir = normalize(sun_direction);
	float cos_theta = dot(dir, sun_dir);

	sky_color += rayleigh_scatter(cos_theta) * sun_intensity;
	sky_color += mie_scatter(cos_theta) * sun_intensity;

	// Sun disc
	float sun_disc = smoothstep(0.9998, 0.9999, cos_theta);
	sky_color += vec3(1.0, 0.95, 0.85) * sun_disc * 2.0 * sun_intensity;

	// Sun glow
	float sun_glow = pow(max(cos_theta, 0.0), 12.0);
	sky_color += vec3(1.0, 0.8, 0.5) * sun_glow * 0.3 * sun_intensity;

	// Render clouds only above horizon
	if (height > -0.1) {
		vec4 clouds = render_clouds(dir, height_factor);

		// Blend clouds with sky
		sky_color = mix(sky_color, clouds.rgb, clouds.a * 0.95);
	}

	// Subtle color grading for atmosphere
	sky_color = pow(sky_color, vec3(1.05));  // Slight contrast boost

	// Add subtle ambient variation
	float ambient_variation = noise3D(dir * 0.5 + vec3(time * 0.05)) * 0.02;
	sky_color += ambient_variation;

	COLOR = sky_color;
}
"""

	material.shader = shader

	# Set shader parameters
	material.set_shader_parameter("time", 0.0)
	material.set_shader_parameter("cloud_density", cloud_density)
	material.set_shader_parameter("sun_intensity", sun_intensity)
	material.set_shader_parameter("sun_direction", Vector3(0.3, 0.5, 0.2))

	return material

func set_cloud_density(density: float) -> void:
	"""Adjust cloud coverage (0.0 = clear, 1.0 = overcast)"""
	cloud_density = clamp(density, 0.0, 1.0)
	if sky_material:
		sky_material.set_shader_parameter("cloud_density", cloud_density)
		print("Cloud density set to: ", cloud_density)

func set_sun_intensity(intensity: float) -> void:
	"""Adjust sun brightness"""
	sun_intensity = clamp(intensity, 0.0, 2.0)
	if sky_material:
		sky_material.set_shader_parameter("sun_intensity", sun_intensity)
		print("Sun intensity set to: ", sun_intensity)

func set_sun_direction(direction: Vector3) -> void:
	"""Set sun position/direction"""
	if sky_material:
		sky_material.set_shader_parameter("sun_direction", direction.normalized())
		print("Sun direction updated")
