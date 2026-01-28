extends Node3D

## Video Wall Manager
## Creates video panel meshes that replace perimeter walls
## All panels share the same video source via a custom shader with linear filtering

# Video components
var video_player: VideoStreamPlayer = null
var sub_viewport: SubViewport = null
var viewport_texture: ViewportTexture = null

# Shader for clean rendering
var _video_shader: Shader = null

# Settings
var loop_video: bool = true
var volume_db: float = -80.0  # Muted by default

# Created video panels
var video_panels: Array[MeshInstance3D] = []

# State
var is_initialized: bool = false


func initialize(video_path: String, viewport_size: Vector2i = Vector2i(1920, 1080)) -> bool:
	## Initialize the video system
	print("[VideoWallManager] Initializing with video: %s" % video_path)

	if video_path.is_empty():
		push_warning("VideoWallManager: No video path provided")
		return false

	# Check if file exists
	if not FileAccess.file_exists(video_path) and not ResourceLoader.exists(video_path):
		push_warning("VideoWallManager: Video file not found: " + video_path)
		return false

	# Load the video wall shader
	_video_shader = load("res://scripts/shaders/video_wall.gdshader")
	if _video_shader == null:
		push_warning("VideoWallManager: Could not load video_wall.gdshader, will use fallback material")

	# Create SubViewport for video rendering
	sub_viewport = SubViewport.new()
	sub_viewport.name = "VideoViewport"
	sub_viewport.size = viewport_size
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	sub_viewport.transparent_bg = false
	sub_viewport.handle_input_locally = false
	sub_viewport.gui_disable_input = true
	# Disable 3D — this viewport only renders 2D video content
	sub_viewport.disable_3d = true
	sub_viewport.snap_2d_transforms_to_pixel = true
	add_child(sub_viewport)

	# Create VideoStreamPlayer that fills the viewport
	video_player = VideoStreamPlayer.new()
	video_player.name = "VideoPlayer"
	video_player.position = Vector2.ZERO
	video_player.size = Vector2(viewport_size)
	video_player.volume_db = volume_db
	video_player.autoplay = false
	video_player.expand = true
	video_player.stretch_mode = VideoStreamPlayer.STRETCH_MODE_KEEP_ASPECT_COVERED
	sub_viewport.add_child(video_player)

	# Load video stream (Godot 4 only supports .ogv)
	var extension = video_path.get_extension().to_lower()
	var video_stream: VideoStream = null

	if extension == "ogv":
		var theora_stream = VideoStreamTheora.new()
		theora_stream.file = video_path
		video_stream = theora_stream
	else:
		video_stream = load(video_path)

	if video_stream == null:
		push_error("VideoWallManager: Failed to load video (only .ogv format supported)")
		sub_viewport.queue_free()
		return false

	video_player.stream = video_stream
	video_player.finished.connect(_on_video_finished)

	# Get viewport texture for materials
	viewport_texture = sub_viewport.get_texture()

	is_initialized = true
	print("[VideoWallManager] Initialized successfully")

	# Start playback
	video_player.play()
	return true


func create_video_panels(wall_configs: Array) -> Array[MeshInstance3D]:
	## Create video panel meshes at the given wall positions
	## wall_configs: Array of {pos: Vector3, size: Vector3, rotation: Vector3}

	if not is_initialized:
		push_warning("VideoWallManager: Not initialized")
		return []

	print("[VideoWallManager] Creating %d video panels" % wall_configs.size())

	for i in range(wall_configs.size()):
		var config = wall_configs[i]
		var panel = _create_video_panel(config.pos, config.size, config.rotation, "VideoPanel%d" % i)
		video_panels.append(panel)
		add_child(panel)

	return video_panels


func _create_video_panel(pos: Vector3, size: Vector3, rot: Vector3, panel_name: String) -> MeshInstance3D:
	## Create a single video panel mesh with collision

	# Create plane mesh facing inward (video screen)
	var mesh = QuadMesh.new()
	# For walls, height is Y, width depends on orientation
	if abs(size.x) > abs(size.z):
		# North/South wall - width is X
		mesh.size = Vector2(size.x, size.y)
	else:
		# East/West wall - width is Z
		mesh.size = Vector2(size.z, size.y)

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.name = panel_name
	mesh_instance.position = pos
	mesh_instance.rotation = rot

	# Use the custom shader for clean, artifact-free rendering
	if _video_shader:
		var material = ShaderMaterial.new()
		material.shader = _video_shader
		material.set_shader_parameter("video_texture", viewport_texture)
		material.set_shader_parameter("flip_h", false)
		material.set_shader_parameter("flip_v", false)
		mesh_instance.material_override = material
	else:
		# Fallback: StandardMaterial3D with explicit linear filtering
		var material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_texture = viewport_texture
		material.albedo_color = Color.WHITE
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		material.disable_ambient_light = true
		material.disable_fog = true
		material.disable_receive_shadows = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		material.emission_enabled = false
		material.metallic = 0.0
		material.roughness = 1.0
		mesh_instance.material_override = material

	# Add collision for gameplay
	var static_body = StaticBody3D.new()
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	if abs(size.x) > abs(size.z):
		shape.size = Vector3(size.x, size.y, 0.1)
	else:
		shape.size = Vector3(0.1, size.y, size.z)
	collision.shape = shape
	static_body.add_child(collision)
	mesh_instance.add_child(static_body)

	return mesh_instance


func _on_video_finished() -> void:
	if loop_video and is_initialized and video_player:
		video_player.play()


func cleanup() -> void:
	print("[VideoWallManager] Cleaning up")

	if video_player:
		video_player.stop()
		video_player.queue_free()
		video_player = null

	for panel in video_panels:
		if is_instance_valid(panel):
			panel.queue_free()
	video_panels.clear()

	if sub_viewport:
		sub_viewport.queue_free()
		sub_viewport = null

	viewport_texture = null
	is_initialized = false


func _exit_tree() -> void:
	cleanup()
