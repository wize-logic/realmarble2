extends Node3D

## Simple Skybox Generator
## Uses Godot's built-in ProceduralSkyMaterial for a clean sky

@export var animation_speed: float = 0.5
@export var color_palette: int = 0
@export var color_transition_duration: float = 10.0
@export var color_hold_duration: float = 15.0
@export var star_density: float = 0.3
@export var cloud_density: float = 0.4
@export var nebula_intensity: float = 0.5

var sky_material: ProceduralSkyMaterial

func _ready() -> void:
	generate_skybox()

func generate_skybox() -> void:
	"""Generate a clean procedural sky using built-in ProceduralSkyMaterial"""
	var world_env: WorldEnvironment = get_node_or_null("/root/World/WorldEnvironment")
	if not world_env:
		print("ERROR: WorldEnvironment not found!")
		return

	var environment: Environment = world_env.environment
	if not environment:
		environment = Environment.new()
		world_env.environment = environment

	# Use Godot's built-in ProceduralSkyMaterial for a simple, clean sky
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.15, 0.1, 0.35)
	sky_material.sky_horizon_color = Color(0.4, 0.2, 0.5)
	sky_material.ground_bottom_color = Color(0.05, 0.05, 0.1)
	sky_material.ground_horizon_color = Color(0.3, 0.15, 0.4)
	sky_material.sun_angle_max = 30.0
	sky_material.sun_curve = 0.15

	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky

	print("Simple skybox generated!")

func randomize_colors() -> void:
	"""Change to a new random sky color scheme"""
	if not sky_material:
		return

	var palettes: Array = [
		[Color(0.15, 0.1, 0.35), Color(0.4, 0.2, 0.5)],    # Purple
		[Color(0.05, 0.1, 0.25), Color(0.2, 0.3, 0.5)],    # Deep Blue
		[Color(0.2, 0.08, 0.15), Color(0.5, 0.2, 0.3)],    # Sunset
		[Color(0.05, 0.15, 0.15), Color(0.15, 0.35, 0.3)],  # Northern
		[Color(0.1, 0.05, 0.2), Color(0.3, 0.1, 0.4)],     # Deep Space
	]

	var palette = palettes[randi() % palettes.size()]
	sky_material.sky_top_color = palette[0]
	sky_material.sky_horizon_color = palette[1]
	sky_material.ground_bottom_color = palette[0].darkened(0.5)
	sky_material.ground_horizon_color = palette[1].darkened(0.3)

	print("Skybox colors randomized!")

func set_star_density(_density: float) -> void:
	pass

func set_cloud_density(_density: float) -> void:
	pass

func set_nebula_intensity(_intensity: float) -> void:
	pass
