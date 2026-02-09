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
var _palettes: Array = []
var _current_palette_index: int = 0
var _next_palette_index: int = 0
var _transition_timer: float = 0.0
var _hold_timer: float = 0.0
var _is_transitioning: bool = false

func _ready() -> void:
	generate_skybox()
	_setup_color_cycle()
	set_process(false)

func _process(delta: float) -> void:
	if not sky_material or _palettes.is_empty():
		return

	var scaled_delta := delta * animation_speed
	if _is_transitioning:
		_transition_timer += scaled_delta
		var progress := clampf(_transition_timer / max(color_transition_duration, 0.01), 0.0, 1.0)
		var from_palette: Array = _palettes[_current_palette_index]
		var to_palette: Array = _palettes[_next_palette_index]
		var top_color: Color = from_palette[0].lerp(to_palette[0], progress)
		var horizon_color: Color = from_palette[1].lerp(to_palette[1], progress)
		_apply_palette(top_color, horizon_color)

		if progress >= 1.0:
			_current_palette_index = _next_palette_index
			_transition_timer = 0.0
			_is_transitioning = false
			_hold_timer = 0.0
			set_process(false)
			# Schedule next transition after hold duration
			if is_inside_tree():
				get_tree().create_timer(color_hold_duration / max(animation_speed, 0.01)).timeout.connect(_start_next_transition)
	else:
		# Hold phase is handled by a timer; _process only runs during transitions
		pass

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
	_apply_palette(Color(0.15, 0.1, 0.35), Color(0.4, 0.2, 0.5))
	sky_material.sun_angle_max = 30.0
	sky_material.sun_curve = 0.15

	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky

	print("Simple skybox generated!")

func randomize_colors() -> void:
	"""Change to a new random sky color scheme"""
	if not sky_material or _palettes.is_empty():
		return

	_current_palette_index = randi() % _palettes.size()
	_next_palette_index = _current_palette_index
	_transition_timer = 0.0
	_hold_timer = 0.0
	_is_transitioning = false
	var palette: Array = _palettes[_current_palette_index]
	_apply_palette(palette[0], palette[1])

	print("Skybox colors randomized!")

func _setup_color_cycle() -> void:
	_palettes = [
		[Color(0.95, 0.2, 0.8), Color(0.2, 0.9, 0.95)],   # Neon magenta -> cyan
		[Color(0.15, 0.95, 0.6), Color(0.9, 0.7, 0.1)],   # Acid green -> gold
		[Color(0.75, 0.25, 1.0), Color(0.15, 0.4, 0.95)], # Ultraviolet -> electric blue
		[Color(1.0, 0.35, 0.15), Color(1.0, 0.1, 0.6)],   # Hot orange -> neon pink
		[Color(0.2, 0.9, 0.4), Color(0.8, 0.2, 1.0)],     # Lime -> purple
		[Color(0.1, 0.85, 1.0), Color(0.9, 0.3, 0.2)],    # Aqua -> coral
	]
	_current_palette_index = clampi(color_palette, 0, _palettes.size() - 1)
	_next_palette_index = _current_palette_index
	_transition_timer = 0.0
	_hold_timer = 0.0
	_is_transitioning = false
	var palette: Array = _palettes[_current_palette_index]
	_apply_palette(palette[0], palette[1])
	# Schedule first transition after initial hold duration
	if is_inside_tree() and _palettes.size() >= 2:
		get_tree().create_timer(color_hold_duration / max(animation_speed, 0.01)).timeout.connect(_start_next_transition)

func _start_next_transition() -> void:
	if _palettes.size() < 2:
		return
	_next_palette_index = randi() % _palettes.size()
	if _next_palette_index == _current_palette_index:
		_next_palette_index = (_current_palette_index + 1) % _palettes.size()
	_transition_timer = 0.0
	_is_transitioning = true
	set_process(true)

func _apply_palette(top_color: Color, horizon_color: Color) -> void:
	if not sky_material:
		return
	sky_material.sky_top_color = top_color
	sky_material.sky_horizon_color = horizon_color
	sky_material.ground_bottom_color = top_color.darkened(0.5)
	sky_material.ground_horizon_color = horizon_color.darkened(0.35)

func set_star_density(_density: float) -> void:
	pass

func set_cloud_density(_density: float) -> void:
	pass

func set_nebula_intensity(_intensity: float) -> void:
	pass
