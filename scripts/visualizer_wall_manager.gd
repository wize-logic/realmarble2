extends Node3D

## Visualizer Wall Manager
## Creates Windows Media Player 9 style audio visualizer projected onto walls
## Shader runs directly on 3D panels (no SubViewport needed)

# Visualization modes matching the shader
enum VisualizerMode {
	BARS = 0,      # Classic frequency bars
	SCOPE = 1,     # Oscilloscope waveform
	AMBIENCE = 2,  # Flowing particles and plasma
	BATTERY = 3,   # Geometric energy beams
	PLENOPTIC = 4  # Kaleidoscope circles
}

# Audio analysis
var spectrum_analyzer: AudioEffectSpectrumAnalyzerInstance = null
var spectrum_data: PackedFloat32Array = PackedFloat32Array()
var audio_level: float = 0.0
var bass_level: float = 0.0
var mid_level: float = 0.0
var high_level: float = 0.0

# Smoothing for visual appeal - enhanced with velocity tracking
var smoothed_spectrum: PackedFloat32Array = PackedFloat32Array()
var spectrum_velocity: PackedFloat32Array = PackedFloat32Array()
var peak_spectrum: PackedFloat32Array = PackedFloat32Array()
var peak_decay: PackedFloat32Array = PackedFloat32Array()
var smoothed_audio: float = 0.0
var smoothed_bass: float = 0.0
var smoothed_mid: float = 0.0
var smoothed_high: float = 0.0
var audio_velocity: float = 0.0
var bass_velocity: float = 0.0
var mid_velocity: float = 0.0
var high_velocity: float = 0.0

# Beat detection
var beat_detected: bool = false
var beat_intensity: float = 0.0
var last_bass_level: float = 0.0
var beat_cooldown: float = 0.0

# Settings
@export var current_mode: VisualizerMode = VisualizerMode.BARS
@export var color_primary: Color = Color(0.0, 0.7, 1.0, 1.0)
@export var color_secondary: Color = Color(1.0, 0.3, 0.7, 1.0)
@export var color_accent: Color = Color(0.3, 1.0, 0.5, 1.0)
@export var background_color: Color = Color(0.02, 0.02, 0.05, 1.0)
@export var glow_intensity: float = 1.5
@export var animation_speed: float = 1.0
@export var spectrum_smoothing: float = 0.12
@export var sensitivity: float = 2.0
@export var attack_speed: float = 12.0
@export var release_speed: float = 4.0
@export var peak_hold_time: float = 0.3
@export var peak_fall_speed: float = 1.5

# Auto-cycle settings
@export var auto_cycle: bool = true
@export var cycle_interval: float = 30.0
@export var cycle_colors: bool = true
var _cycle_timer: float = 0.0
var _color_preset_index: int = 0

# Performance settings
## Update interval in seconds (0 = every frame, higher = less updates)
@export var update_interval: float = 0.0
## Shader quality level: 0=Low (best FPS), 1=Medium, 2=High
@export var quality_level: int = 1
var _update_timer: float = 0.0

# Shader reference (spatial shader applied directly to 3D panels)
var _visualizer_shader: Shader = null
var _shader_material: ShaderMaterial = null

# Spectrum textures (32x1 images passed to shader)
var _spectrum_image: Image = null
var _spectrum_texture: ImageTexture = null
var _peak_image: Image = null
var _peak_texture: ImageTexture = null

# Created visualizer panels
var visualizer_panels: Array[MeshInstance3D] = []

# State
var is_initialized: bool = false

# Preset color schemes (WMP9 inspired)
const COLOR_PRESETS = {
	"ocean": {
		"primary": Color(0.0, 0.7, 1.0),
		"secondary": Color(0.0, 0.3, 0.8),
		"accent": Color(0.3, 1.0, 0.8),
		"background": Color(0.0, 0.02, 0.05)
	},
	"sunset": {
		"primary": Color(1.0, 0.4, 0.0),
		"secondary": Color(1.0, 0.1, 0.3),
		"accent": Color(1.0, 0.8, 0.0),
		"background": Color(0.05, 0.01, 0.02)
	},
	"matrix": {
		"primary": Color(0.0, 1.0, 0.3),
		"secondary": Color(0.0, 0.7, 0.2),
		"accent": Color(0.5, 1.0, 0.5),
		"background": Color(0.0, 0.03, 0.01)
	},
	"synthwave": {
		"primary": Color(1.0, 0.0, 0.8),
		"secondary": Color(0.0, 0.8, 1.0),
		"accent": Color(1.0, 0.5, 0.0),
		"background": Color(0.02, 0.0, 0.04)
	},
	"neon": {
		"primary": Color(1.0, 0.0, 0.5),
		"secondary": Color(0.0, 1.0, 0.5),
		"accent": Color(1.0, 1.0, 0.0),
		"background": Color(0.01, 0.01, 0.02)
	},
	"ice": {
		"primary": Color(0.6, 0.9, 1.0),
		"secondary": Color(0.3, 0.5, 1.0),
		"accent": Color(1.0, 1.0, 1.0),
		"background": Color(0.01, 0.02, 0.04)
	},
	"fire": {
		"primary": Color(1.0, 0.3, 0.0),
		"secondary": Color(1.0, 0.0, 0.0),
		"accent": Color(1.0, 0.9, 0.3),
		"background": Color(0.03, 0.01, 0.0)
	},
	"aurora": {
		"primary": Color(0.0, 1.0, 0.5),
		"secondary": Color(0.5, 0.0, 1.0),
		"accent": Color(0.0, 0.8, 1.0),
		"background": Color(0.0, 0.02, 0.03)
	}
}

func _ready() -> void:
	spectrum_data.resize(32)
	spectrum_data.fill(0.0)
	smoothed_spectrum.resize(32)
	smoothed_spectrum.fill(0.0)
	spectrum_velocity.resize(32)
	spectrum_velocity.fill(0.0)
	peak_spectrum.resize(32)
	peak_spectrum.fill(0.0)
	peak_decay.resize(32)
	peak_decay.fill(0.0)


func initialize(audio_bus_name: String = "Music", _viewport_size: Vector2i = Vector2i(1920, 1080)) -> bool:
	## Initialize the visualizer system (viewport_size kept for API compat but unused)
	print("[VisualizerWallManager] Initializing with audio bus: %s" % audio_bus_name)

	# Load the visualizer shader (spatial shader applied directly to 3D panels)
	_visualizer_shader = load("res://scripts/shaders/visualizer_wmp9.gdshader")
	if _visualizer_shader == null:
		push_error("VisualizerWallManager: Could not load visualizer_wmp9.gdshader")
		return false

	# Set up spectrum analyzer on the audio bus
	if not _setup_spectrum_analyzer(audio_bus_name):
		push_warning("VisualizerWallManager: Could not set up spectrum analyzer, visualizer will run without audio reactivity")

	# Create shader material (shared across all panels)
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = _visualizer_shader

	# Set initial shader parameters
	_update_shader_colors()
	_shader_material.set_shader_parameter("viz_mode", int(current_mode))
	_shader_material.set_shader_parameter("glow_intensity", glow_intensity)
	_shader_material.set_shader_parameter("animation_speed", animation_speed)
	_shader_material.set_shader_parameter("quality_level", quality_level)
	_shader_material.set_shader_parameter("dome_mode", true)  # Enable dome-optimized rendering

	# Create spectrum textures (32x1 RGBA8 images)
	_spectrum_image = Image.create(32, 1, false, Image.FORMAT_RGBA8)
	_spectrum_texture = ImageTexture.create_from_image(_spectrum_image)
	_peak_image = Image.create(32, 1, false, Image.FORMAT_RGBA8)
	_peak_texture = ImageTexture.create_from_image(_peak_image)

	# Initialize audio uniforms
	_shader_material.set_shader_parameter("spectrum_tex", _spectrum_texture)
	_shader_material.set_shader_parameter("peak_tex", _peak_texture)
	_shader_material.set_shader_parameter("audio_level", 0.0)
	_shader_material.set_shader_parameter("bass_level", 0.0)
	_shader_material.set_shader_parameter("mid_level", 0.0)
	_shader_material.set_shader_parameter("high_level", 0.0)
	_shader_material.set_shader_parameter("beat_intensity", 0.0)

	is_initialized = true
	print("[VisualizerWallManager] Initialized successfully")
	return true


func _setup_spectrum_analyzer(bus_name: String) -> bool:
	## Set up the spectrum analyzer effect on the audio bus
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx == -1:
		push_warning("VisualizerWallManager: Audio bus '%s' not found" % bus_name)
		return false

	# Check if there's already a spectrum analyzer on this bus
	for i in range(AudioServer.get_bus_effect_count(bus_idx)):
		var effect = AudioServer.get_bus_effect(bus_idx, i)
		if effect is AudioEffectSpectrumAnalyzer:
			spectrum_analyzer = AudioServer.get_bus_effect_instance(bus_idx, i)
			print("[VisualizerWallManager] Found existing spectrum analyzer on bus %s" % bus_name)
			return true

	# Add a new spectrum analyzer effect
	var analyzer_effect = AudioEffectSpectrumAnalyzer.new()
	analyzer_effect.buffer_length = 0.1
	analyzer_effect.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
	AudioServer.add_bus_effect(bus_idx, analyzer_effect)

	var effect_idx = AudioServer.get_bus_effect_count(bus_idx) - 1
	spectrum_analyzer = AudioServer.get_bus_effect_instance(bus_idx, effect_idx)

	print("[VisualizerWallManager] Added spectrum analyzer to bus %s" % bus_name)
	return spectrum_analyzer != null


func _process(delta: float) -> void:
	if not is_initialized:
		return

	# Auto-cycle through visualization modes
	if auto_cycle:
		_cycle_timer += delta
		if _cycle_timer >= cycle_interval:
			_cycle_timer = 0.0
			_advance_cycle()

	# Performance: skip updates based on interval
	if update_interval > 0.0:
		_update_timer += delta
		if _update_timer < update_interval:
			return
		_update_timer = 0.0

	_update_spectrum_data(delta if update_interval == 0.0 else update_interval)
	_update_shader_audio()


func _update_spectrum_data(delta: float) -> void:
	## Sample the audio spectrum and calculate levels
	if spectrum_analyzer == null:
		# Generate fake data for testing when no audio
		var time = Time.get_ticks_msec() / 1000.0
		for i in range(32):
			var fake_val = (sin(time * 2.0 + float(i) * 0.3) * 0.3 + 0.5) * 0.5
			spectrum_data[i] = fake_val
		_smooth_spectrum_data(delta)
		return

	var min_freq = 20.0
	var max_freq = 16000.0

	for i in range(32):
		var freq_low = min_freq * pow(max_freq / min_freq, float(i) / 32.0)
		var freq_high = min_freq * pow(max_freq / min_freq, float(i + 1) / 32.0)

		var magnitude = spectrum_analyzer.get_magnitude_for_frequency_range(freq_low, freq_high)
		var energy = (magnitude.x + magnitude.y) / 2.0

		var db = linear_to_db(energy)
		var normalized = clamp((db + 60.0) / 60.0, 0.0, 1.0)
		normalized = clamp(normalized * sensitivity, 0.0, 1.0)

		spectrum_data[i] = normalized

	bass_level = 0.0
	mid_level = 0.0
	high_level = 0.0

	for i in range(8):
		bass_level += spectrum_data[i]
	bass_level /= 8.0

	for i in range(8, 21):
		mid_level += spectrum_data[i]
	mid_level /= 13.0

	for i in range(21, 32):
		high_level += spectrum_data[i]
	high_level /= 11.0

	audio_level = (bass_level + mid_level + high_level) / 3.0

	_smooth_spectrum_data(delta)


func _smooth_spectrum_data(delta: float) -> void:
	## Apply enhanced smoothing with velocity tracking and asymmetric attack/release
	var attack_factor = 1.0 - exp(-attack_speed * delta)
	var release_factor = 1.0 - exp(-release_speed * delta)

	# Beat detection
	beat_cooldown = max(0.0, beat_cooldown - delta)
	var bass_delta = bass_level - last_bass_level
	if bass_delta > 0.15 and beat_cooldown <= 0.0:
		beat_detected = true
		beat_intensity = min(bass_delta * 3.0, 1.0)
		beat_cooldown = 0.1
	else:
		beat_detected = false
		beat_intensity = max(0.0, beat_intensity - delta * 3.0)
	last_bass_level = bass_level

	for i in range(32):
		var target = spectrum_data[i]
		var current = smoothed_spectrum[i]
		var diff = target - current

		var factor = attack_factor if diff > 0 else release_factor

		var spring_force = diff * 30.0
		var damping = spectrum_velocity[i] * 8.0
		spectrum_velocity[i] += (spring_force - damping) * delta

		var spring_contribution = current + spectrum_velocity[i] * delta
		var direct_contribution = lerp(current, target, factor)
		smoothed_spectrum[i] = lerp(direct_contribution, spring_contribution, 0.3)

		smoothed_spectrum[i] = clamp(smoothed_spectrum[i], 0.0, 1.0)

		if smoothed_spectrum[i] > peak_spectrum[i]:
			peak_spectrum[i] = smoothed_spectrum[i]
			peak_decay[i] = peak_hold_time
		else:
			peak_decay[i] -= delta
			if peak_decay[i] <= 0:
				peak_spectrum[i] = max(peak_spectrum[i] - peak_fall_speed * delta, smoothed_spectrum[i])

	smoothed_audio = _get_smoothed_value(audio_level, smoothed_audio, audio_velocity, delta, attack_factor, release_factor)
	smoothed_bass = _get_smoothed_value(bass_level, smoothed_bass, bass_velocity, delta, attack_factor, release_factor)
	smoothed_mid = _get_smoothed_value(mid_level, smoothed_mid, mid_velocity, delta, attack_factor, release_factor)
	smoothed_high = _get_smoothed_value(high_level, smoothed_high, high_velocity, delta, attack_factor, release_factor)

	# Idle animation: ensure minimum visual activity so walls are never dead black
	var t = Time.get_ticks_msec() / 1000.0
	for i in range(32):
		var idle_wave = (sin(t * 1.5 + float(i) * 0.5) * 0.5 + 0.5) * 0.08
		idle_wave += (sin(t * 0.7 + float(i) * 0.3) * 0.5 + 0.5) * 0.04
		smoothed_spectrum[i] = max(smoothed_spectrum[i], idle_wave)
	smoothed_audio = max(smoothed_audio, 0.05)
	smoothed_bass = max(smoothed_bass, 0.03)
	smoothed_mid = max(smoothed_mid, 0.03)
	smoothed_high = max(smoothed_high, 0.02)


func _get_smoothed_value(target: float, current: float, _velocity: float, _delta: float, attack: float, release: float) -> float:
	## Smooth a single value with asymmetric attack/release
	var diff = target - current
	var factor = attack if diff > 0 else release
	return clamp(lerp(current, target, factor), 0.0, 1.0)


func _update_shader_audio() -> void:
	## Update shader with current audio data
	if _shader_material == null:
		return

	# Write spectrum data into 32x1 textures (red channel = value)
	for i in range(32):
		var spec_val = clamp(smoothed_spectrum[i], 0.0, 1.0)
		var peak_val = clamp(peak_spectrum[i], 0.0, 1.0)
		_spectrum_image.set_pixel(i, 0, Color(spec_val, 0.0, 0.0, 1.0))
		_peak_image.set_pixel(i, 0, Color(peak_val, 0.0, 0.0, 1.0))
	_spectrum_texture.update(_spectrum_image)
	_peak_texture.update(_peak_image)

	_shader_material.set_shader_parameter("audio_level", smoothed_audio)
	_shader_material.set_shader_parameter("bass_level", smoothed_bass)
	_shader_material.set_shader_parameter("mid_level", smoothed_mid)
	_shader_material.set_shader_parameter("high_level", smoothed_high)
	_shader_material.set_shader_parameter("beat_intensity", beat_intensity)


func _update_shader_colors() -> void:
	## Update shader color parameters
	if _shader_material == null:
		return

	_shader_material.set_shader_parameter("color_primary", color_primary)
	_shader_material.set_shader_parameter("color_secondary", color_secondary)
	_shader_material.set_shader_parameter("color_accent", color_accent)
	_shader_material.set_shader_parameter("background_color", background_color)


func create_visualizer_panels(wall_configs: Array) -> Array[MeshInstance3D]:
	## Create visualizer panel meshes at the given wall positions (legacy flat walls)

	if not is_initialized:
		push_warning("VisualizerWallManager: Not initialized")
		return []

	print("[VisualizerWallManager] Creating %d visualizer panels" % wall_configs.size())

	for i in range(wall_configs.size()):
		var config = wall_configs[i]
		var panel = _create_visualizer_panel(config.pos, config.size, config.rotation, "VisualizerPanel%d" % i)
		visualizer_panels.append(panel)
		add_child(panel)

	return visualizer_panels


func _create_visualizer_panel(pos: Vector3, size: Vector3, rot: Vector3, panel_name: String) -> MeshInstance3D:
	## Create a single visualizer panel with the shader applied directly

	var mesh = QuadMesh.new()
	if abs(size.x) > abs(size.z):
		mesh.size = Vector2(size.x, size.y)
	else:
		mesh.size = Vector2(size.z, size.y)

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.name = panel_name
	mesh_instance.position = pos
	mesh_instance.rotation = rot

	mesh_instance.material_override = _shader_material

	print("[VisualizerWallManager] Created panel: %s with direct shader" % panel_name)

	var static_body = StaticBody3D.new()
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	var is_ns_wall = abs(size.x) > abs(size.z)
	if is_ns_wall:
		shape.size = Vector3(size.x, size.y, 0.1)
	else:
		shape.size = Vector3(size.z, size.y, 0.1)
	collision.shape = shape
	static_body.add_child(collision)
	mesh_instance.add_child(static_body)

	return mesh_instance


func create_visualizer_dome(dome_radius: float, center: Vector3 = Vector3.ZERO, h_segments: int = 64, v_segments: int = 32) -> MeshInstance3D:
	## Create an inward-facing complete sphere with the visualizer shader.
	## This creates a fully enclosed sphere with no gaps.

	if not is_initialized:
		push_warning("VisualizerWallManager: Not initialized")
		return null

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	# Complete sphere: from nadir (-90°) to zenith (+90°)
	var min_elevation := deg_to_rad(-90.0)
	var max_elevation := deg_to_rad(90.0)

	# Generate vertices ring-by-ring from bottom to top
	for v in range(v_segments + 1):
		var elevation := lerpf(min_elevation, max_elevation, float(v) / float(v_segments))
		var y := sin(elevation) * dome_radius
		var ring_r := cos(elevation) * dome_radius

		for h in range(h_segments + 1):
			var azimuth := float(h) / float(h_segments) * TAU
			var x := cos(azimuth) * ring_r
			var z := sin(azimuth) * ring_r

			vertices.append(Vector3(x, y, z) + center)
			# Normal points inward (toward center)
			normals.append(-Vector3(x, y, z).normalized())
			# UV: u wraps around, v goes bottom-to-top
			uvs.append(Vector2(float(h) / float(h_segments), float(v) / float(v_segments)))

	# Generate triangle indices with reversed winding for inward-facing
	for v in range(v_segments):
		for h in range(h_segments):
			var tl := v * (h_segments + 1) + h
			var tr := tl + 1
			var bl := (v + 1) * (h_segments + 1) + h
			var br := bl + 1
			# Reversed winding so front face points inward (matches cull_back)
			indices.append(tl)
			indices.append(bl)
			indices.append(tr)
			indices.append(tr)
			indices.append(bl)
			indices.append(br)

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var dome_mesh := ArrayMesh.new()
	dome_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = dome_mesh
	mesh_instance.name = "VisualizerDome"
	mesh_instance.material_override = _shader_material

	# Collision using ConcavePolygonShape3D (trimesh)
	var static_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	var faces := PackedVector3Array()
	for i in range(0, indices.size(), 3):
		faces.append(vertices[indices[i]])
		faces.append(vertices[indices[i + 1]])
		faces.append(vertices[indices[i + 2]])
	shape.set_faces(faces)
	collision.shape = shape
	static_body.add_child(collision)
	mesh_instance.add_child(static_body)

	visualizer_panels.append(mesh_instance)
	add_child(mesh_instance)

	print("[VisualizerWallManager] Created complete sphere dome: radius=%.1f" % dome_radius)

	return mesh_instance


# =============================================================================
# PUBLIC API
# =============================================================================

func set_mode(mode: VisualizerMode) -> void:
	## Change the visualization mode
	current_mode = mode
	if _shader_material:
		_shader_material.set_shader_parameter("viz_mode", int(mode))
	print("[VisualizerWallManager] Mode changed to: %s" % VisualizerMode.keys()[mode])


func next_mode() -> void:
	## Cycle to the next visualization mode
	var next = (current_mode + 1) % VisualizerMode.size()
	set_mode(next as VisualizerMode)


func previous_mode() -> void:
	## Cycle to the previous visualization mode
	var prev = (current_mode - 1) if current_mode > 0 else (VisualizerMode.size() - 1)
	set_mode(prev as VisualizerMode)


func _advance_cycle() -> void:
	## Advance to the next mode and optionally cycle the color preset
	var next = (current_mode + 1) % VisualizerMode.size()
	set_mode(next as VisualizerMode)

	if cycle_colors:
		var preset_names = COLOR_PRESETS.keys()
		_color_preset_index = (_color_preset_index + 1) % preset_names.size()
		set_color_preset(preset_names[_color_preset_index])


func set_color_preset(preset_name: String) -> void:
	## Apply a color preset
	if not COLOR_PRESETS.has(preset_name):
		push_warning("VisualizerWallManager: Unknown preset '%s'" % preset_name)
		return

	var preset = COLOR_PRESETS[preset_name]
	color_primary = preset["primary"]
	color_secondary = preset["secondary"]
	color_accent = preset["accent"]
	background_color = preset["background"]

	var preset_names = COLOR_PRESETS.keys()
	var idx = preset_names.find(preset_name)
	if idx >= 0:
		_color_preset_index = idx

	_update_shader_colors()
	print("[VisualizerWallManager] Applied color preset: %s" % preset_name)


func set_colors(primary: Color, secondary: Color, accent: Color, background: Color) -> void:
	## Set custom colors
	color_primary = primary
	color_secondary = secondary
	color_accent = accent
	background_color = background
	_update_shader_colors()


func set_glow_intensity(intensity: float) -> void:
	glow_intensity = clamp(intensity, 0.0, 3.0)
	if _shader_material:
		_shader_material.set_shader_parameter("glow_intensity", glow_intensity)


func set_animation_speed(speed: float) -> void:
	animation_speed = clamp(speed, 0.1, 3.0)
	if _shader_material:
		_shader_material.set_shader_parameter("animation_speed", animation_speed)


func set_sensitivity(value: float) -> void:
	sensitivity = clamp(value, 0.5, 5.0)


func get_available_presets() -> Array[String]:
	var presets: Array[String] = []
	for key in COLOR_PRESETS.keys():
		presets.append(key)
	return presets


func get_current_mode_name() -> String:
	return VisualizerMode.keys()[current_mode]


func cleanup() -> void:
	if not is_initialized:
		return

	print("[VisualizerWallManager] Cleaning up")
	is_initialized = false

	for panel in visualizer_panels:
		if is_instance_valid(panel) and panel.is_inside_tree():
			panel.queue_free()
	visualizer_panels.clear()

	_shader_material = null


func _exit_tree() -> void:
	cleanup()
