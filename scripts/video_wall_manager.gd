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

# Rotating cylinder container (holds all wall segments)
var video_cylinder: Node3D = null

# State
var is_initialized: bool = false


func initialize(video_path: String, viewport_size: Vector2i = Vector2i(1920, 1080)) -> bool:
	## Initialize the video system
	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "[VideoWallManager] Initializing with video: %s" % video_path)

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
	if OS.has_feature("web"):
		sub_viewport.size = Vector2i(960, 540)
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
	video_player.size = Vector2(sub_viewport.size)
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
	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "[VideoWallManager] Initialized successfully")

	# Start playback
	video_player.play()
	return true


func create_video_panels(wall_configs: Array) -> Array[MeshInstance3D]:
	## Create video panel meshes at the given wall positions
	## wall_configs: Array of {pos: Vector3, size: Vector3, rotation: Vector3}

	if not is_initialized:
		push_warning("VideoWallManager: Not initialized")
		return []

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "[VideoWallManager] Creating %d video panels" % wall_configs.size())

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

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "[VideoWallManager] Created panel: %s with viewport texture" % panel_name)

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
	# Rotate the video cylinder container slowly around the Y axis
	if enable_rotation and video_cylinder and is_instance_valid(video_cylinder):
		video_cylinder.rotate_y(rotation_speed * delta)


func create_video_cylinder(radius: float, height: float, center: Vector3 = Vector3.ZERO, h_segments: int = 64, v_segments: int = 1, num_walls: int = 8) -> Node3D:
	## Create multiple inward-facing curved wall segments with video texture.
	## The walls are separate meshes but positioned close together to look like one.
	## The container rotates slowly around the arena.
	## radius: distance from center to the walls
	## height: vertical height of the walls
	## center: center position of the cylinder
	## h_segments: number of horizontal segments per wall (smoothness)
	## v_segments: number of vertical segments
	## num_walls: number of separate wall segments

	if not is_initialized:
		push_warning("VideoWallManager: Not initialized")
		return null

	# Create a container node that holds all wall segments and rotates
	var container := Node3D.new()
	container.name = "VideoCylinderContainer"
	container.position = center
	add_child(container)

	# Calculate the angle each wall segment covers
	var angle_per_wall := TAU / float(num_walls)
	var segments_per_wall := h_segments / num_walls

	# Create shared material once for all segments
	var shared_material := StandardMaterial3D.new()
	shared_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shared_material.albedo_texture = viewport_texture
	shared_material.albedo_color = Color(1.0, 1.0, 1.0)
	shared_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	shared_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	shared_material.cull_mode = BaseMaterial3D.CULL_BACK
	shared_material.metallic = 0.0
	shared_material.roughness = 1.0

	# Create each wall segment
	for wall_idx in range(num_walls):
		var start_angle := wall_idx * angle_per_wall
		var end_angle := (wall_idx + 1) * angle_per_wall

		var wall_mesh := _create_curved_wall_segment(radius, height, start_angle, end_angle, segments_per_wall, v_segments, shared_material)
		wall_mesh.name = "VideoWall%d" % wall_idx
		container.add_child(wall_mesh)
		video_panels.append(wall_mesh)

	video_cylinder = container
	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "[VideoWallManager] Created %d rotating video wall segments: radius=%.1f, height=%.1f" % [num_walls, radius, height])

	return container


func _create_curved_wall_segment(radius: float, height: float, start_angle: float, end_angle: float, h_segments: int, v_segments: int, shared_material: StandardMaterial3D = null) -> MeshInstance3D:
	## Create a single curved wall segment mesh

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var half_height := height / 2.0

	# Generate vertices for this wall segment
	for v in range(v_segments + 1):
		var y := lerpf(-half_height, half_height, float(v) / float(v_segments))
		# Flip V coordinate to fix upside-down video (1.0 - v_ratio)
		var v_uv := 1.0 - float(v) / float(v_segments)

		for h in range(h_segments + 1):
			var t := float(h) / float(h_segments)
			var azimuth := lerpf(start_angle, end_angle, t)
			var x := cos(azimuth) * radius
			var z := sin(azimuth) * radius

			vertices.append(Vector3(x, y, z))
			# Normal points inward (toward center)
			normals.append(-Vector3(x, 0, z).normalized())
			# UV: each wall segment gets full 0-1 range so video displays completely on each
			uvs.append(Vector2(t, v_uv))

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

	var segment_mesh := ArrayMesh.new()
	segment_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = segment_mesh

	# Use shared material if provided, otherwise create one
	if shared_material:
		mesh_instance.material_override = shared_material
	else:
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

	return mesh_instance


func cleanup() -> void:
	# Prevent double-cleanup
	if not is_initialized:
		return

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "[VideoWallManager] Cleaning up")
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
