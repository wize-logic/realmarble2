extends Node3D

## Video Wall Manager
## Creates a rotating curved video wall around the arena
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

# Rotation settings
var rotation_speed: float = 0.05  # Radians per second (slow rotation)
var enable_rotation: bool = true

# Created video panels
var video_panels: Array[MeshInstance3D] = []

# Rotating cylinder mesh
var video_cylinder: MeshInstance3D = null

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

	# Always use StandardMaterial3D for maximum compatibility with GL Compatibility renderer
	# ShaderMaterial with viewport textures can have issues in WebGL
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport_texture
	material.albedo_color = Color(1.0, 1.0, 1.0)  # Full brightness
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.metallic = 0.0
	material.roughness = 1.0
	mesh_instance.material_override = material

	print("[VideoWallManager] Created panel: %s with viewport texture" % panel_name)

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


func _on_video_finished() -> void:
	if loop_video and is_initialized and video_player:
		video_player.play()


func _process(delta: float) -> void:
	# Rotate the video cylinder slowly around the Y axis
	if enable_rotation and video_cylinder and is_instance_valid(video_cylinder):
		video_cylinder.rotate_y(rotation_speed * delta)


func create_video_cylinder(radius: float, height: float, center: Vector3 = Vector3.ZERO, h_segments: int = 64, v_segments: int = 1) -> MeshInstance3D:
	## Create an inward-facing curved cylindrical wall with video texture.
	## The cylinder rotates slowly around the arena.
	## radius: distance from center to the wall
	## height: vertical height of the wall
	## center: center position of the cylinder
	## h_segments: number of horizontal segments (smoothness)
	## v_segments: number of vertical segments

	if not is_initialized:
		push_warning("VideoWallManager: Not initialized")
		return null

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var half_height := height / 2.0

	# Generate vertices for a cylinder (open top and bottom)
	for v in range(v_segments + 1):
		var y := lerpf(-half_height, half_height, float(v) / float(v_segments))

		for h in range(h_segments + 1):
			var azimuth := float(h) / float(h_segments) * TAU
			var x := cos(azimuth) * radius
			var z := sin(azimuth) * radius

			vertices.append(Vector3(x, y, z) + center)
			# Normal points inward (toward center)
			normals.append(-Vector3(x, 0, z).normalized())
			# UV: u wraps around horizontally, v goes bottom-to-top
			uvs.append(Vector2(float(h) / float(h_segments), float(v) / float(v_segments)))

	# Generate triangle indices with reversed winding for inward-facing
	for v in range(v_segments):
		for h in range(h_segments):
			var tl := v * (h_segments + 1) + h
			var tr := tl + 1
			var bl := (v + 1) * (h_segments + 1) + h
			var br := bl + 1
			# Reversed winding so front face points inward
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

	var cylinder_mesh := ArrayMesh.new()
	cylinder_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = cylinder_mesh
	mesh_instance.name = "VideoCylinder"

	# Create material with video texture
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport_texture
	material.albedo_color = Color(1.0, 1.0, 1.0)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.metallic = 0.0
	material.roughness = 1.0
	mesh_instance.material_override = material

	video_cylinder = mesh_instance
	video_panels.append(mesh_instance)
	add_child(mesh_instance)

	print("[VideoWallManager] Created rotating video cylinder: radius=%.1f, height=%.1f" % [radius, height])

	return mesh_instance


func cleanup() -> void:
	# Prevent double-cleanup
	if not is_initialized:
		return

	print("[VideoWallManager] Cleaning up")
	is_initialized = false

	if video_player and is_instance_valid(video_player):
		video_player.stop()
		if video_player.is_inside_tree():
			video_player.queue_free()
		video_player = null

	for panel in video_panels:
		if is_instance_valid(panel) and panel.is_inside_tree():
			panel.queue_free()
	video_panels.clear()
	video_cylinder = null

	if sub_viewport and is_instance_valid(sub_viewport):
		if sub_viewport.is_inside_tree():
			sub_viewport.queue_free()
		sub_viewport = null

	viewport_texture = null


func _exit_tree() -> void:
	cleanup()
