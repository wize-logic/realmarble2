extends Node3D

## Handles camera occlusion by making the player marble transparent when blocked by geometry

@export var marble_mesh: MeshInstance3D
@export var player: Node3D

var is_occluded: bool = false
var original_material: Material = null
var transparent_material: StandardMaterial3D = null

# Throttle occlusion raycast — 60 raycasts/sec is far too expensive on HTML5
var _occlusion_check_timer: float = 0.0
const OCCLUSION_CHECK_INTERVAL: float = 0.1  # 10 Hz

# Transparency settings
var occluded_transparency: float = 0.3  # How transparent when occluded (0.0 = invisible, 1.0 = opaque)
var fade_speed: float = 10.0  # How fast to fade in/out

func _ready() -> void:
	# Find the marble mesh if not assigned
	if not marble_mesh and player:
		marble_mesh = player.get_node_or_null("MeshInstance3D")

	if marble_mesh and marble_mesh.mesh:
		# Store original material
		if marble_mesh.get_surface_override_material_count() > 0:
			original_material = marble_mesh.get_surface_override_material(0)

		if not original_material:
			original_material = marble_mesh.mesh.surface_get_material(0)

		# Create transparent material based on original
		create_transparent_material()

func create_transparent_material() -> void:
	"""Create a transparent version of the marble material"""
	transparent_material = StandardMaterial3D.new()

	# Copy properties from original if it exists
	if original_material and original_material is StandardMaterial3D:
		var orig: StandardMaterial3D = original_material
		transparent_material.albedo_color = orig.albedo_color
		transparent_material.albedo_texture = orig.albedo_texture
		transparent_material.metallic = orig.metallic
		transparent_material.roughness = orig.roughness
		transparent_material.emission = orig.emission
		transparent_material.emission_enabled = orig.emission_enabled
	else:
		# Default marble appearance
		transparent_material.albedo_color = Color(0.9, 0.9, 1.0, 1.0)
		transparent_material.metallic = 0.8
		transparent_material.roughness = 0.1

	# Enable transparency
	transparent_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	transparent_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	transparent_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	transparent_material.no_depth_test = false
	transparent_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Show both sides when transparent

func _process(delta: float) -> void:
	if not marble_mesh or not player:
		return

	# Throttle the expensive raycast; transparency fading still runs every frame
	_occlusion_check_timer += delta
	if _occlusion_check_timer >= OCCLUSION_CHECK_INTERVAL:
		_occlusion_check_timer = 0.0
		check_occlusion()
	update_transparency(delta)

func check_occlusion() -> void:
	"""Check if geometry is blocking the camera's view of the marble"""
	var camera: Camera3D = get_viewport().get_camera_3d()

	if not camera or not player:
		is_occluded = false
		return

	# Cast ray from camera to player
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		camera.global_position,
		player.global_position
	)

	# Don't collide with the player itself
	query.exclude = [player]
	query.collision_mask = 1  # Only check against world geometry (layer 1)

	var result: Dictionary = space_state.intersect_ray(query)

	# If ray hit something before reaching the player, we're occluded
	is_occluded = not result.is_empty()

func update_transparency(delta: float) -> void:
	"""Smoothly transition marble transparency based on occlusion state"""
	if not marble_mesh or not transparent_material:
		return

	var current_material: Material = marble_mesh.get_surface_override_material(0)
	var target_alpha: float = occluded_transparency if is_occluded else 1.0

	if is_occluded:
		# Switch to transparent material if not already
		if current_material != transparent_material:
			marble_mesh.set_surface_override_material(0, transparent_material)
			# Set initial alpha
			var color: Color = transparent_material.albedo_color
			color.a = 1.0
			transparent_material.albedo_color = color

		# Fade to transparent
		var color: Color = transparent_material.albedo_color
		color.a = move_toward(color.a, target_alpha, fade_speed * delta)
		transparent_material.albedo_color = color
	else:
		if current_material == transparent_material:
			# Fade back to opaque first
			var color: Color = transparent_material.albedo_color
			color.a = move_toward(color.a, 1.0, fade_speed * delta)
			transparent_material.albedo_color = color

			# Once fully opaque, switch back to original material
			if color.a >= 0.99:
				marble_mesh.set_surface_override_material(0, original_material)
