extends Node3D

## Visualizer Wall Manager
## Creates Windows Media Player 9 style audio visualizer projected onto walls
## Similar to video walls but renders procedural audio-reactive visuals

# Visualization modes matching the shader
enum VisualizerMode {
	BARS = 0,      # Classic frequency bars
	SCOPE = 1,     # Oscilloscope waveform
	AMBIENCE = 2,  # Flowing particles and plasma
	BATTERY = 3,   # Geometric energy beams
	PLENOPTIC = 4  # Kaleidoscope circles
}

# Visualization components
var sub_viewport: SubViewport = null
var viewport_texture: ViewportTexture = null
var viz_control: ColorRect = null

# Audio analysis
var spectrum_analyzer: AudioEffectSpectrumAnalyzerInstance = null
var spectrum_data: PackedFloat32Array = PackedFloat32Array()
var audio_level: float = 0.0
var bass_level: float = 0.0
var mid_level: float = 0.0
var high_level: float = 0.0

# Smoothing for visual appeal - enhanced with velocity tracking
var smoothed_spectrum: PackedFloat32Array = PackedFloat32Array()
var spectrum_velocity: PackedFloat32Array = PackedFloat32Array()  # Velocity for spring-based smoothing
var peak_spectrum: PackedFloat32Array = PackedFloat32Array()  # Peak hold values
var peak_decay: PackedFloat32Array = PackedFloat32Array()  # Peak decay timers
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
@export var spectrum_smoothing: float = 0.12  # Lower = smoother
@export var sensitivity: float = 2.0  # Audio sensitivity multiplier
@export var attack_speed: float = 12.0  # How fast bars rise (higher = faster)
@export var release_speed: float = 4.0  # How fast bars fall (lower = slower)
@export var peak_hold_time: float = 0.3  # How long peaks stay visible
@export var peak_fall_speed: float = 1.5  # How fast peaks fall after hold

# Shader reference
var _visualizer_shader: Shader = null
var _shader_material: ShaderMaterial = null

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
	# Initialize spectrum data arrays with velocity tracking
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


func initialize(audio_bus_name: String = "Music", viewport_size: Vector2i = Vector2i(1920, 1080)) -> bool:
	## Initialize the visualizer system
	print("[VisualizerWallManager] Initializing with audio bus: %s" % audio_bus_name)

	# Load the visualizer shader
	_visualizer_shader = load("res://scripts/shaders/visualizer_wmp9.gdshader")
	if _visualizer_shader == null:
		push_error("VisualizerWallManager: Could not load visualizer_wmp9.gdshader")
		return false

	# Set up spectrum analyzer on the audio bus
	if not _setup_spectrum_analyzer(audio_bus_name):
		push_warning("VisualizerWallManager: Could not set up spectrum analyzer, visualizer will run without audio reactivity")

	# Create SubViewport for rendering the visualizer
	sub_viewport = SubViewport.new()
	sub_viewport.name = "VisualizerViewport"
	sub_viewport.size = viewport_size
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	sub_viewport.transparent_bg = false
	sub_viewport.handle_input_locally = false
	sub_viewport.gui_disable_input = true
	sub_viewport.disable_3d = true
	sub_viewport.snap_2d_transforms_to_pixel = true
	add_child(sub_viewport)

	# Create a ColorRect that fills the viewport with our shader
	viz_control = ColorRect.new()
	viz_control.name = "VisualizerRect"
	viz_control.color = Color.BLACK  # Black fallback if shader fails (prevents white flash)
	viz_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	viz_control.size = Vector2(viewport_size)

	# Create shader material
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = _visualizer_shader

	# Set initial shader parameters
	_update_shader_colors()
	_shader_material.set_shader_parameter("viz_mode", current_mode)
	_shader_material.set_shader_parameter("glow_intensity", glow_intensity)
	_shader_material.set_shader_parameter("animation_speed", animation_speed)

	# Initialize audio uniforms before first render to prevent garbage data
	_shader_material.set_shader_parameter("spectrum", smoothed_spectrum)
	_shader_material.set_shader_parameter("peak_spectrum", peak_spectrum)
	_shader_material.set_shader_parameter("audio_level", 0.0)
	_shader_material.set_shader_parameter("bass_level", 0.0)
	_shader_material.set_shader_parameter("mid_level", 0.0)
	_shader_material.set_shader_parameter("high_level", 0.0)
	_shader_material.set_shader_parameter("beat_intensity", 0.0)

	viz_control.material = _shader_material
	sub_viewport.add_child(viz_control)

	# Get viewport texture for materials
	viewport_texture = sub_viewport.get_texture()

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
	analyzer_effect.buffer_length = 0.1  # 100ms buffer
	analyzer_effect.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
	AudioServer.add_bus_effect(bus_idx, analyzer_effect)

	# Get the instance
	var effect_idx = AudioServer.get_bus_effect_count(bus_idx) - 1
	spectrum_analyzer = AudioServer.get_bus_effect_instance(bus_idx, effect_idx)

	print("[VisualizerWallManager] Added spectrum analyzer to bus %s" % bus_name)
	return spectrum_analyzer != null


func _process(delta: float) -> void:
	if not is_initialized:
		return

	# Update audio analysis
	_update_spectrum_data(delta)

	# Update shader with audio data
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

	# Sample 32 frequency bands
	var min_freq = 20.0
	var max_freq = 16000.0

	# Logarithmic frequency distribution
	for i in range(32):
		var freq_low = min_freq * pow(max_freq / min_freq, float(i) / 32.0)
		var freq_high = min_freq * pow(max_freq / min_freq, float(i + 1) / 32.0)

		var magnitude = spectrum_analyzer.get_magnitude_for_frequency_range(freq_low, freq_high)
		var energy = (magnitude.x + magnitude.y) / 2.0

		# Convert to dB and normalize
		var db = linear_to_db(energy)
		var normalized = clamp((db + 60.0) / 60.0, 0.0, 1.0)  # -60dB to 0dB range

		# Apply sensitivity
		normalized = clamp(normalized * sensitivity, 0.0, 1.0)

		spectrum_data[i] = normalized

	# Calculate frequency band levels
	# Bass: 20-250 Hz (indices 0-7)
	# Mid: 250-4000 Hz (indices 8-20)
	# High: 4000-16000 Hz (indices 21-31)
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

	# Calculate adaptive smoothing based on delta time
	var attack_factor = 1.0 - exp(-attack_speed * delta)
	var release_factor = 1.0 - exp(-release_speed * delta)

	# Beat detection
	beat_cooldown = max(0.0, beat_cooldown - delta)
	var bass_delta = bass_level - last_bass_level
	if bass_delta > 0.15 and beat_cooldown <= 0.0:
		beat_detected = true
		beat_intensity = min(bass_delta * 3.0, 1.0)
		beat_cooldown = 0.1  # Minimum time between beats
	else:
		beat_detected = false
		beat_intensity = max(0.0, beat_intensity - delta * 3.0)
	last_bass_level = bass_level

	# Smooth each spectrum band with asymmetric attack/release
	for i in range(32):
		var target = spectrum_data[i]
		var current = smoothed_spectrum[i]
		var diff = target - current

		# Use attack speed when rising, release speed when falling
		var factor = attack_factor if diff > 0 else release_factor

		# Spring-based smoothing with velocity for more natural movement
		var spring_force = diff * 30.0
		var damping = spectrum_velocity[i] * 8.0
		spectrum_velocity[i] += (spring_force - damping) * delta

		# Blend spring physics with direct interpolation for stability
		var spring_contribution = current + spectrum_velocity[i] * delta
		var direct_contribution = lerp(current, target, factor)
		smoothed_spectrum[i] = lerp(direct_contribution, spring_contribution, 0.3)

		# Clamp to valid range
		smoothed_spectrum[i] = clamp(smoothed_spectrum[i], 0.0, 1.0)

		# Peak hold and decay
		if smoothed_spectrum[i] > peak_spectrum[i]:
			peak_spectrum[i] = smoothed_spectrum[i]
			peak_decay[i] = peak_hold_time
		else:
			peak_decay[i] -= delta
			if peak_decay[i] <= 0:
				peak_spectrum[i] = max(peak_spectrum[i] - peak_fall_speed * delta, smoothed_spectrum[i])

	# Smooth overall levels with velocity tracking
	_smooth_level_with_velocity(audio_level, smoothed_audio, audio_velocity, delta, attack_factor, release_factor)
	smoothed_audio = _get_smoothed_value(audio_level, smoothed_audio, audio_velocity, delta, attack_factor, release_factor)
	smoothed_bass = _get_smoothed_value(bass_level, smoothed_bass, bass_velocity, delta, attack_factor, release_factor)
	smoothed_mid = _get_smoothed_value(mid_level, smoothed_mid, mid_velocity, delta, attack_factor, release_factor)
	smoothed_high = _get_smoothed_value(high_level, smoothed_high, high_velocity, delta, attack_factor, release_factor)


func _smooth_level_with_velocity(target: float, current: float, velocity: float, delta: float, attack: float, release: float) -> void:
	## Helper to update velocity (modifies the passed velocity reference via class vars)
	pass  # Handled inline in _get_smoothed_value


func _get_smoothed_value(target: float, current: float, velocity: float, delta: float, attack: float, release: float) -> float:
	## Smooth a single value with asymmetric attack/release
	var diff = target - current
	var factor = attack if diff > 0 else release
	return clamp(lerp(current, target, factor), 0.0, 1.0)


func _update_shader_audio() -> void:
	## Update shader with current audio data
	if _shader_material == null:
		return

	# Pass spectrum array to shader
	_shader_material.set_shader_parameter("spectrum", smoothed_spectrum)
	_shader_material.set_shader_parameter("peak_spectrum", peak_spectrum)
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
	## Create visualizer panel meshes at the given wall positions
	## wall_configs: Array of {pos: Vector3, size: Vector3, rotation: Vector3}

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
	## Create a single visualizer panel mesh with collision

	# Create plane mesh facing inward
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

	# Use StandardMaterial3D with viewport texture for compatibility
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport_texture
	material.albedo_color = Color(1.0, 1.0, 1.0)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.metallic = 0.0
	material.roughness = 1.0
	mesh_instance.material_override = material

	print("[VisualizerWallManager] Created panel: %s with viewport texture" % panel_name)

	# Add collision for gameplay
	var static_body = StaticBody3D.new()
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	# Determine if this is a North/South wall (wider in X) or East/West wall (wider in Z)
	var is_ns_wall = abs(size.x) > abs(size.z)
	if is_ns_wall:
		# N/S walls: no 90-degree rotation, collision stays wide in X, thin in Z
		shape.size = Vector3(size.x, size.y, 0.1)
	else:
		# E/W walls: rotated 90 degrees, so we need collision wide in X locally
		# so that after rotation it becomes wide in Z (parallel to wall) in world space
		shape.size = Vector3(size.z, size.y, 0.1)
	collision.shape = shape
	static_body.add_child(collision)
	mesh_instance.add_child(static_body)

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
	## Set the glow intensity
	glow_intensity = clamp(intensity, 0.0, 3.0)
	if _shader_material:
		_shader_material.set_shader_parameter("glow_intensity", glow_intensity)


func set_animation_speed(speed: float) -> void:
	## Set the animation speed
	animation_speed = clamp(speed, 0.1, 3.0)
	if _shader_material:
		_shader_material.set_shader_parameter("animation_speed", animation_speed)


func set_sensitivity(value: float) -> void:
	## Set the audio sensitivity
	sensitivity = clamp(value, 0.5, 5.0)


func get_available_presets() -> Array[String]:
	## Get list of available color presets
	var presets: Array[String] = []
	for key in COLOR_PRESETS.keys():
		presets.append(key)
	return presets


func get_current_mode_name() -> String:
	## Get the name of the current visualization mode
	return VisualizerMode.keys()[current_mode]


func cleanup() -> void:
	# Prevent double-cleanup
	if not is_initialized:
		return

	print("[VisualizerWallManager] Cleaning up")
	is_initialized = false

	for panel in visualizer_panels:
		if is_instance_valid(panel) and panel.is_inside_tree():
			panel.queue_free()
	visualizer_panels.clear()

	if viz_control and is_instance_valid(viz_control):
		if viz_control.is_inside_tree():
			viz_control.queue_free()
		viz_control = null

	if sub_viewport and is_instance_valid(sub_viewport):
		if sub_viewport.is_inside_tree():
			sub_viewport.queue_free()
		sub_viewport = null

	viewport_texture = null
	_shader_material = null


func _exit_tree() -> void:
	cleanup()
