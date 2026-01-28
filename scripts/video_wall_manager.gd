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
	print("[VideoWallManager] _ready() called")


func initialize(webm_path: String, viewport_size: Vector2i = Vector2i(1920, 1080)) -> bool:
	## Initialize the video wall system with a WebM file path
	## Returns true on success, false on failure

	print("[VideoWallManager] initialize() called with path: '%s', viewport_size: %s" % [webm_path, viewport_size])

	if webm_path.is_empty():
		print("[VideoWallManager] ERROR: No video path provided (empty string)")
		push_warning("VideoWallManager: No video path provided")
		return false

	video_path = webm_path
	print("[VideoWallManager] video_path set to: '%s'" % video_path)

	# Check if file exists
	var file_exists = FileAccess.file_exists(video_path)
	var resource_exists = ResourceLoader.exists(video_path)
	print("[VideoWallManager] FileAccess.file_exists('%s'): %s" % [video_path, file_exists])
	print("[VideoWallManager] ResourceLoader.exists('%s'): %s" % [video_path, resource_exists])

	if not file_exists and not resource_exists:
		print("[VideoWallManager] ERROR: Video file not found at path: '%s'" % video_path)
		push_warning("VideoWallManager: Video file not found: " + video_path)
		return false

	# Create SubViewport for video rendering
	print("[VideoWallManager] Creating SubViewport...")
	sub_viewport = SubViewport.new()
	sub_viewport.name = "VideoWallViewport"
	sub_viewport.size = viewport_size
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport.transparent_bg = false
	sub_viewport.handle_input_locally = false
	sub_viewport.gui_disable_input = true
	add_child(sub_viewport)
	print("[VideoWallManager] SubViewport created and added as child, size: %s" % sub_viewport.size)

	# Create VideoStreamPlayer inside the viewport
	print("[VideoWallManager] Creating VideoStreamPlayer...")
	video_player = VideoStreamPlayer.new()
	video_player.name = "VideoPlayer"
	video_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	video_player.volume_db = volume_db
	video_player.autoplay = false  # We'll control playback manually
	video_player.expand = true
	print("[VideoWallManager] VideoStreamPlayer created with expand=%s, volume_db=%s" % [video_player.expand, video_player.volume_db])

	# Load the video stream
	print("[VideoWallManager] Loading video stream from: '%s'" % video_path)
	video_stream = load(video_path)
	print("[VideoWallManager] load() returned: %s (type: %s)" % [video_stream, typeof(video_stream)])

	if video_stream == null:
		print("[VideoWallManager] ERROR: Failed to load video stream from: '%s'" % video_path)
		push_error("VideoWallManager: Failed to load video: " + video_path)
		sub_viewport.queue_free()
		return false

	print("[VideoWallManager] Video stream loaded successfully, class: %s" % video_stream.get_class())
	video_player.stream = video_stream
	sub_viewport.add_child(video_player)
	print("[VideoWallManager] VideoStreamPlayer added to SubViewport")

	# Connect signals
	video_player.finished.connect(_on_video_finished)
	print("[VideoWallManager] Connected finished signal")

	# Get viewport texture
	viewport_texture = sub_viewport.get_texture()
	print("[VideoWallManager] Got viewport texture: %s" % viewport_texture)

	is_initialized = true
	print("[VideoWallManager] Initialization complete! is_initialized=%s" % is_initialized)

	if autoplay:
		print("[VideoWallManager] Autoplay enabled, calling play()...")
		play()

	return true


func play() -> void:
	## Start video playback
	print("[VideoWallManager] play() called, is_initialized=%s, video_player=%s" % [is_initialized, video_player])
	if not is_initialized or video_player == null:
		print("[VideoWallManager] Cannot play - not initialized or no video_player")
		return

	video_player.play()
	is_playing = true
	print("[VideoWallManager] Video playback started, is_playing=%s" % is_playing)


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
	print("[VideoWallManager] Video finished, loop_video=%s" % loop_video)
	if loop_video and is_initialized:
		video_player.play()


func create_video_material(flip_h: bool = false, flip_v: bool = false) -> ShaderMaterial:
	## Create a new video wall material using the viewport texture
	## flip_h/flip_v: Flip texture horizontally/vertically (useful for different wall orientations)

	print("[VideoWallManager] create_video_material() called, flip_h=%s, flip_v=%s" % [flip_h, flip_v])
	print("[VideoWallManager] is_initialized=%s, viewport_texture=%s" % [is_initialized, viewport_texture])

	if not is_initialized or viewport_texture == null:
		print("[VideoWallManager] ERROR: Cannot create material - not initialized or no viewport_texture")
		push_warning("VideoWallManager: Cannot create material - not initialized")
		return null

	print("[VideoWallManager] Creating ShaderMaterial with VIDEO_WALL_SHADER...")
	var material = ShaderMaterial.new()
	material.shader = VIDEO_WALL_SHADER
	print("[VideoWallManager] Shader set: %s" % material.shader)

	# Set video texture
	material.set_shader_parameter("video_texture", viewport_texture)
	print("[VideoWallManager] Set video_texture parameter to viewport_texture")

	# Apply display settings
	material.set_shader_parameter("brightness", brightness)
	material.set_shader_parameter("contrast", contrast)
	material.set_shader_parameter("saturation", saturation)
	material.set_shader_parameter("tint_color", Vector3(tint_color.r, tint_color.g, tint_color.b))
	material.set_shader_parameter("emission_strength", emission_strength)
	print("[VideoWallManager] Set display settings: brightness=%s, contrast=%s, emission=%s" % [brightness, contrast, emission_strength])

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

	print("[VideoWallManager] Material created successfully")
	return material


func apply_to_wall(mesh_instance: MeshInstance3D, flip_h: bool = false, flip_v: bool = false) -> void:
	## Apply video material to a wall mesh
	print("[VideoWallManager] apply_to_wall() called, mesh_instance=%s, flip_h=%s, flip_v=%s" % [mesh_instance, flip_h, flip_v])

	if mesh_instance == null:
		print("[VideoWallManager] ERROR: mesh_instance is null!")
		return

	print("[VideoWallManager] Applying to mesh: %s (path: %s)" % [mesh_instance.name, mesh_instance.get_path()])
	var material = create_video_material(flip_h, flip_v)
	if material:
		mesh_instance.material_override = material
		wall_meshes.append(mesh_instance)
		print("[VideoWallManager] Material applied to %s, total wall_meshes: %d" % [mesh_instance.name, wall_meshes.size()])
	else:
		print("[VideoWallManager] ERROR: Failed to create material for %s" % mesh_instance.name)


func apply_to_perimeter_walls(walls: Array) -> void:
	## Apply video to perimeter walls with proper orientation
	## Expects walls array in order: North, South, East, West

	print("[VideoWallManager] apply_to_perimeter_walls() called with %d walls" % walls.size())

	for i in range(walls.size()):
		print("[VideoWallManager] Processing wall[%d]: %s (is MeshInstance3D: %s)" % [i, walls[i], walls[i] is MeshInstance3D])
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
		else:
			print("[VideoWallManager] WARNING: walls[%d] is NOT a MeshInstance3D, skipping" % i)

	print("[VideoWallManager] Finished applying to perimeter walls, total applied: %d" % wall_meshes.size())


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
	print("[VideoWallManager] cleanup() called")
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
