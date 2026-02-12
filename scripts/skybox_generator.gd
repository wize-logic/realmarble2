extends Node3D

## Dynamic Skybox Generator
## Uses ProceduralSkyMaterial with curated palettes and gentle animated transitions

@export var animation_speed: float = 0.5
@export var color_palette: int = 0
@export var color_transition_duration: float = 14.0
@export var color_hold_duration: float = 18.0
@export var star_density: float = 0.3
@export var cloud_density: float = 0.4
@export var nebula_intensity: float = 0.5
@export var menu_static_mode: bool = false
@export var menu_static_palette: int = 1

var sky_material: ProceduralSkyMaterial
var _cloud_cover_texture: ImageTexture = null
var _palettes: Array[Dictionary] = []
var _current_palette_index: int = 0
var _next_palette_index: int = 0
var _transition_timer: float = 0.0
var _hold_timer: float = 0.0
var _is_transitioning: bool = false

func _ready() -> void:
	generate_skybox()
	_setup_color_cycle()
	if menu_static_mode:
		_apply_menu_static_lighting()
	set_process(false)

func _process(delta: float) -> void:
	if not sky_material or _palettes.is_empty():
		return

	var scaled_delta := delta * animation_speed
	if _is_transitioning:
		_transition_timer += scaled_delta
		var progress := clampf(_transition_timer / max(color_transition_duration, 0.01), 0.0, 1.0)
		var from_palette: Dictionary = _palettes[_current_palette_index]
		var to_palette: Dictionary = _palettes[_next_palette_index]
		var top_color: Color = from_palette.top.lerp(to_palette.top, progress)
		var horizon_color: Color = from_palette.horizon.lerp(to_palette.horizon, progress)
		var ground_color: Color = from_palette.ground.lerp(to_palette.ground, progress)
		_apply_palette(top_color, horizon_color, ground_color)

		if progress >= 1.0:
			_current_palette_index = _next_palette_index
			_transition_timer = 0.0
			_is_transitioning = false
			_hold_timer = 0.0
			set_process(false)
			# Schedule next transition after hold duration
			if is_inside_tree() and not menu_static_mode:
				get_tree().create_timer(color_hold_duration / max(animation_speed, 0.01)).timeout.connect(_start_next_transition)
	else:
		# Hold phase is handled by a timer; _process only runs during transitions
		pass

func generate_skybox() -> void:
	"""Generate a richer procedural sky for a more atmospheric arena backdrop"""
	var world_env: WorldEnvironment = get_node_or_null("/root/World/WorldEnvironment")
	if not world_env:
		DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "ERROR: WorldEnvironment not found!")
		return

	var environment: Environment = world_env.environment
	if not environment:
		environment = Environment.new()
		world_env.environment = environment

	# NOTE: ambient_light and tonemap are set by _apply_prebaked_lighting_profile() in world.gd
	# which runs AFTER skybox generation. Only set sky-specific properties here.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES

	# Use ProceduralSkyMaterial for compatibility-friendly visuals with better art direction
	sky_material = ProceduralSkyMaterial.new()
	if menu_static_mode:
		sky_material.energy_multiplier = 1.0
	else:
		sky_material.energy_multiplier = 1.4
	sky_material.sky_curve = 0.12
	sky_material.ground_curve = 0.12
	sky_material.sun_angle_max = 1.0
	sky_material.sun_curve = 0.01
	sky_material.use_debanding = true
	_apply_cloud_cover_if_supported()

	# Apply first palette immediately (psychedelic dusk default)
	_apply_palette(Color(0.06, 0.02, 0.18), Color(0.85, 0.30, 0.65), Color(0.14, 0.04, 0.28))

	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Enhanced skybox generated!")

func randomize_colors() -> void:
	"""Change to a new random sky color scheme"""
	if not sky_material or _palettes.is_empty():
		return

	_current_palette_index = randi() % _palettes.size()
	_next_palette_index = _current_palette_index
	_transition_timer = 0.0
	_hold_timer = 0.0
	_is_transitioning = false
	var palette: Dictionary = _palettes[_current_palette_index]
	_apply_palette(palette.top, palette.horizon, palette.ground)

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Skybox colors randomized!")

func _setup_color_cycle() -> void:
	_palettes = [
		# MBU-inspired deep space nebula palettes — dark zenith, vivid horizon, rich ground
		{"top": Color(0.06, 0.02, 0.18), "horizon": Color(0.85, 0.30, 0.65), "ground": Color(0.14, 0.04, 0.28)}, # nebula magenta
		{"top": Color(0.02, 0.06, 0.22), "horizon": Color(0.20, 0.75, 0.90), "ground": Color(0.04, 0.12, 0.30)}, # deep ocean cyan
		{"top": Color(0.10, 0.02, 0.20), "horizon": Color(0.95, 0.50, 0.20), "ground": Color(0.18, 0.06, 0.16)}, # solar flare
		{"top": Color(0.04, 0.04, 0.20), "horizon": Color(0.55, 0.40, 0.95), "ground": Color(0.10, 0.06, 0.28)}, # cosmic violet
		{"top": Color(0.02, 0.10, 0.12), "horizon": Color(0.25, 0.90, 0.50), "ground": Color(0.04, 0.16, 0.14)}, # emerald nebula
		{"top": Color(0.12, 0.02, 0.16), "horizon": Color(1.0, 0.35, 0.75), "ground": Color(0.20, 0.04, 0.22)}, # hot pink nova
		{"top": Color(0.03, 0.05, 0.22), "horizon": Color(0.35, 0.65, 1.0), "ground": Color(0.06, 0.10, 0.30)}, # electric blue
		{"top": Color(0.08, 0.02, 0.16), "horizon": Color(1.0, 0.55, 0.25), "ground": Color(0.16, 0.06, 0.12)}, # amber sunset
	]
	_current_palette_index = clampi(color_palette, 0, _palettes.size() - 1)
	_next_palette_index = _current_palette_index
	_transition_timer = 0.0
	_hold_timer = 0.0
	_is_transitioning = false
	var palette: Dictionary = _palettes[_current_palette_index]
	_apply_palette(palette.top, palette.horizon, palette.ground)
	# Schedule first transition after initial hold duration
	if is_inside_tree() and _palettes.size() >= 2 and not menu_static_mode:
		get_tree().create_timer(color_hold_duration / max(animation_speed, 0.01)).timeout.connect(_start_next_transition)

func _start_next_transition() -> void:
	if menu_static_mode or _palettes.size() < 2:
		return
	_next_palette_index = randi() % _palettes.size()
	if _next_palette_index == _current_palette_index:
		_next_palette_index = (_current_palette_index + 1) % _palettes.size()
	_transition_timer = 0.0
	_is_transitioning = true
	set_process(true)

func _apply_palette(top_color: Color, horizon_color: Color, ground_color: Color) -> void:
	if not sky_material:
		return
	sky_material.sky_top_color = top_color
	sky_material.sky_horizon_color = horizon_color
	sky_material.ground_bottom_color = ground_color
	sky_material.ground_horizon_color = horizon_color.lerp(ground_color, 0.5)


func _apply_menu_static_lighting() -> void:
	if _palettes.is_empty():
		return
	_current_palette_index = clampi(menu_static_palette, 0, _palettes.size() - 1)
	_next_palette_index = _current_palette_index
	_transition_timer = 0.0
	_is_transitioning = false
	var palette: Dictionary = _palettes[_current_palette_index]
	_apply_palette(palette.top, palette.horizon, palette.ground)
	set_process(false)

func _apply_cloud_cover_if_supported() -> void:
	if not sky_material:
		return

	var has_sky_cover: bool = false
	var has_sky_cover_modulate: bool = false
	for property_info in sky_material.get_property_list():
		var property_name: String = String(property_info.name)
		if property_name == "sky_cover":
			has_sky_cover = true
		elif property_name == "sky_cover_modulate":
			has_sky_cover_modulate = true

	if not has_sky_cover:
		return

	_cloud_cover_texture = _create_cloud_cover_texture()
	sky_material.set("sky_cover", _cloud_cover_texture)
	if has_sky_cover_modulate:
		sky_material.set("sky_cover_modulate", Color(1.0, 1.0, 1.0, clampf(cloud_density, 0.0, 1.0)))

func _create_cloud_cover_texture() -> ImageTexture:
	var width: int = 512
	var height: int = 256
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = int(Time.get_unix_time_from_system())
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.018
	noise.fractal_octaves = 4

	var radial_scale: float = 72.0
	for y in range(height):
		var v: float = float(y) / float(height - 1)
		for x in range(width):
			var u: float = float(x) / float(width)
			var theta: float = u * TAU
			var nx: float = cos(theta) * radial_scale
			var nz: float = sin(theta) * radial_scale
			var ny: float = (v - 0.5) * 42.0
			var n: float = noise.get_noise_3d(nx, ny, nz)
			var cloud_signal: float = clampf((n + 1.0) * 0.5, 0.0, 1.0)
			cloud_signal = _smoothstep(0.50, 0.78, cloud_signal)
			var alpha: float = cloud_signal * clampf(cloud_density, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	var texture := ImageTexture.create_from_image(image)
	return texture



func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t: float = clampf((value - edge0) / max(edge1 - edge0, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)



func set_star_density(_density: float) -> void:
	pass

func set_cloud_density(_density: float) -> void:
	cloud_density = clampf(_density, 0.0, 1.0)
	_apply_cloud_cover_if_supported()

func set_nebula_intensity(_intensity: float) -> void:
	pass
