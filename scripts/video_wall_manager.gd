extends Node

## Video Wall Manager
## Manages video playback for perimeter walls using SubViewport rendering
## Supports WebM video files for dynamic wall displays

const VIDEO_WALL_SHADER = preload("res://scripts/shaders/video_wall.gdshader")

# Video settings
var video_path: String = ""
var video_stream: VideoStream = null
var video_player: VideoStreamPlayer = null
var sub_viewport: SubViewport = null
var viewport_texture: ViewportTexture = null

# Playback settings
var loop_video: bool = true
var autoplay: bool = true
var volume_db: float = -80.0  # Muted by default

# Display settings
var brightness: float = 1.0
var contrast: float = 1.0
var saturation: float = 1.0
var tint_color: Color = Color.WHITE
var emission_strength: float = 0.5

# Edge glow settings
var enable_edge_glow: bool = true
var edge_glow_color: Color = Color(0.2, 0.6, 1.0)
var edge_glow_intensity: float = 0.5

# Scanline effect
var enable_scanlines: bool = false
var scanline_intensity: float = 0.3

# Wall references
var wall_meshes: Array[MeshInstance3D] = []

# State
var is_initialized: bool = false
var is_playing: bool = false


func _ready() -> void:
	pass


func initialize(webm_path: String, viewport_size: Vector2i = Vector2i(1920, 1080)) -> bool:
	## Initialize the video wall system with a WebM file path
	## Returns true on success, false on failure

	if webm_path.is_empty():
		push_warning("VideoWallManager: No video path provided")
		return false

	video_path = webm_path

	# Check if file exists
	if not FileAccess.file_exists(video_path) and not ResourceLoader.exists(video_path):
		push_warning("VideoWallManager: Video file not found: " + video_path)
		return false

	# Create SubViewport for video rendering
	sub_viewport = SubViewport.new()
	sub_viewport.name = "VideoWallViewport"
	sub_viewport.size = viewport_size
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport.transparent_bg = false
	sub_viewport.handle_input_locally = false
	sub_viewport.gui_disable_input = true
	add_child(sub_viewport)

	# Create VideoStreamPlayer inside the viewport
	video_player = VideoStreamPlayer.new()
	video_player.name = "VideoPlayer"
	video_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	video_player.volume_db = volume_db
	video_player.autoplay = false  # We'll control playback manually
	video_player.expand = true

	# Load the video stream
	video_stream = load(video_path)
	if video_stream == null:
		push_error("VideoWallManager: Failed to load video: " + video_path)
		sub_viewport.queue_free()
		return false

	video_player.stream = video_stream
	sub_viewport.add_child(video_player)

	# Connect signals
	video_player.finished.connect(_on_video_finished)

	# Get viewport texture
	viewport_texture = sub_viewport.get_texture()

	is_initialized = true
	print("VideoWallManager: Initialized with video: " + video_path)

	if autoplay:
		play()

	return true


func play() -> void:
	## Start video playback
	if not is_initialized or video_player == null:
		return

	video_player.play()
	is_playing = true


func pause() -> void:
	## Pause video playback
	if not is_initialized or video_player == null:
		return

	video_player.paused = true
	is_playing = false


func resume() -> void:
	## Resume video playback
	if not is_initialized or video_player == null:
		return

	video_player.paused = false
	is_playing = true


func stop() -> void:
	## Stop video playback
	if not is_initialized or video_player == null:
		return

	video_player.stop()
	is_playing = false


func _on_video_finished() -> void:
	## Called when video finishes playing
	if loop_video and is_initialized:
		video_player.play()


func create_video_material(flip_h: bool = false, flip_v: bool = false) -> ShaderMaterial:
	## Create a new video wall material using the viewport texture
	## flip_h/flip_v: Flip texture horizontally/vertically (useful for different wall orientations)

	if not is_initialized or viewport_texture == null:
		push_warning("VideoWallManager: Cannot create material - not initialized")
		return null

	var material = ShaderMaterial.new()
	material.shader = VIDEO_WALL_SHADER

	# Set video texture
	material.set_shader_parameter("video_texture", viewport_texture)

	# Apply display settings
	material.set_shader_parameter("brightness", brightness)
	material.set_shader_parameter("contrast", contrast)
	material.set_shader_parameter("saturation", saturation)
	material.set_shader_parameter("tint_color", Vector3(tint_color.r, tint_color.g, tint_color.b))
	material.set_shader_parameter("emission_strength", emission_strength)

	# Edge glow settings
	material.set_shader_parameter("enable_edge_glow", enable_edge_glow)
	material.set_shader_parameter("edge_glow_color", Vector3(edge_glow_color.r, edge_glow_color.g, edge_glow_color.b))
	material.set_shader_parameter("edge_glow_intensity", edge_glow_intensity)

	# Scanline settings
	material.set_shader_parameter("enable_scanlines", enable_scanlines)
	material.set_shader_parameter("scanline_intensity", scanline_intensity)

	# UV settings
	material.set_shader_parameter("flip_h", flip_h)
	material.set_shader_parameter("flip_v", flip_v)

	return material


func apply_to_wall(mesh_instance: MeshInstance3D, flip_h: bool = false, flip_v: bool = false) -> void:
	## Apply video material to a wall mesh
	if mesh_instance == null:
		return

	var material = create_video_material(flip_h, flip_v)
	if material:
		mesh_instance.material_override = material
		wall_meshes.append(mesh_instance)


func apply_to_perimeter_walls(walls: Array) -> void:
	## Apply video to perimeter walls with proper orientation
	## Expects walls array in order: North, South, East, West

	for i in range(walls.size()):
		if walls[i] is MeshInstance3D:
			var flip_h = false
			var flip_v = false

			# Adjust flipping based on wall orientation
			match i:
				0:  # North wall (facing south, towards player)
					flip_h = false
				1:  # South wall (facing north, away from player)
					flip_h = true
				2:  # East wall (facing west)
					flip_h = false
				3:  # West wall (facing east)
					flip_h = true

			apply_to_wall(walls[i], flip_h, flip_v)


func set_brightness(value: float) -> void:
	## Update brightness for all video walls
	brightness = value
	_update_all_materials("brightness", value)


func set_contrast(value: float) -> void:
	## Update contrast for all video walls
	contrast = value
	_update_all_materials("contrast", value)


func set_emission_strength(value: float) -> void:
	## Update emission strength for all video walls
	emission_strength = value
	_update_all_materials("emission_strength", value)


func set_edge_glow_enabled(enabled: bool) -> void:
	## Enable/disable edge glow for all video walls
	enable_edge_glow = enabled
	_update_all_materials("enable_edge_glow", enabled)


func set_volume(db: float) -> void:
	## Set video audio volume in decibels
	volume_db = db
	if video_player:
		video_player.volume_db = db


func _update_all_materials(param_name: String, value: Variant) -> void:
	## Update a shader parameter on all video wall materials
	for mesh in wall_meshes:
		if is_instance_valid(mesh) and mesh.material_override is ShaderMaterial:
			mesh.material_override.set_shader_parameter(param_name, value)


func cleanup() -> void:
	## Clean up video resources
	stop()

	wall_meshes.clear()

	if video_player:
		video_player.queue_free()
		video_player = null

	if sub_viewport:
		sub_viewport.queue_free()
		sub_viewport = null

	video_stream = null
	viewport_texture = null
	is_initialized = false


func _exit_tree() -> void:
	cleanup()
