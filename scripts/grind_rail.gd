extends Path3D
class_name GrindRail

## Rail grinding system similar to Sonic Adventure 2
## Dynamic physics-based grinding - player maintains momentum and responds to gravity

@export var detection_radius: float = 12.0  ## How close player needs to be to snap to rail
@export var rope_length: float = 2.0  ## Length of the rope connecting player to rail
@export var rope_stiffness: float = 50.0  ## How strongly the rope pulls player (spring constant)
@export var rope_damping: float = 20.0  ## Damping to prevent excessive swinging
@export var max_rope_force: float = 100.0  ## Maximum force rope can apply (prevents extreme pulls)
@export var min_grind_speed: float = 0.5  ## Minimum speed to stay on rail (very low)
@export var gravity_multiplier: float = 0.5  ## How much gravity affects grind speed on slopes
@export var rail_friction: float = 0.98  ## Speed retention per second (0.98 = loses 2% per second)

var active_grinders: Array[RigidBody3D] = []  ## Players currently grinding this rail
var grinder_data: Dictionary = {}  ## Stores grinding data per player

## Data structure for each grinder
class GrinderData:
	var closest_offset: float = 0.0  ## Current position along curve
	var last_offset: float = 0.0  ## Previous position (for direction detection)
	var rope_visual: MeshInstance3D = null  ## Visual rope line

	func _init(start_offset: float):
		closest_offset = start_offset
		last_offset = start_offset


func _ready():
	# Ensure we have a curve
	if not curve:
		curve = Curve3D.new()
		push_warning("GrindRail: No curve assigned, created empty curve")
		return

	# Wait for curve to be fully set up
	await get_tree().process_frame

	# Create collision detection along the entire rail path
	_create_rail_collision()


func _create_rail_collision():
	"""Create collision detection areas along the rail curve"""
	if not curve or curve.get_baked_length() == 0:
		push_warning("GrindRail: Cannot create collision - curve is empty")
		return

	var curve_length = curve.get_baked_length()
	var segment_length = 3.0  # Create a detection area every 3 units
	var num_segments = max(int(curve_length / segment_length), 4)  # At least 4 segments

	for i in range(num_segments):
		var t = float(i) / float(num_segments - 1)
		var offset = t * curve_length
		var pos = curve.sample_baked(offset)

		# Create Area3D for this segment
		var area = Area3D.new()
		area.name = "DetectionSegment" + str(i)
		area.collision_layer = 0
		area.collision_mask = 2  # Detect players (layer 2)
		area.position = pos
		add_child(area)

		# Add sphere collision shape
		var collision_shape = CollisionShape3D.new()
		var shape = SphereShape3D.new()
		shape.radius = detection_radius
		collision_shape.shape = shape
		area.add_child(collision_shape)

		# Connect signals
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)

	print("Created ", num_segments, " detection segments for rail ", name)


func _process(delta: float):
	# Update all active grinders
	for grinder in active_grinders.duplicate():
		if not is_instance_valid(grinder) or not grinder_data.has(grinder):
			_remove_grinder(grinder)
			continue

		_update_grinder(grinder, delta)


func _on_body_entered(body: Node3D):
	if not body is RigidBody3D:
		return

	if not body.has_method("start_grinding"):
		return

	# Get player velocity (attach at any speed, even 0)
	var velocity = body.linear_velocity

	# Find closest point on rail
	var player_pos = body.global_position
	var closest_offset = curve.get_closest_offset(to_local(player_pos))
	var closest_point = curve.sample_baked(closest_offset)
	var world_closest = to_global(closest_point)

	# Check distance
	var distance = player_pos.distance_to(world_closest)
	if distance > detection_radius:
		return

	# ONLY attach if player is ABOVE the rail (not from sides or below)
	var to_player = player_pos - world_closest
	var vertical_offset = to_player.y

	# Must be above the rail (positive Y) - very generous range for easier attachment
	if vertical_offset < -1.0:  # Can even attach slightly below
		return

	# Check horizontal distance - very generous for rope attachment
	var horizontal_offset = Vector2(to_player.x, to_player.z).length()
	if horizontal_offset > 8.0:  # Max 8.0 units horizontal offset - very generous
		return

	# Start grinding
	_attach_grinder(body, closest_offset, velocity)


func _on_body_exited(body: Node3D):
	# Don't auto-remove on exit, let player jump off manually
	pass


func _attach_grinder(grinder: RigidBody3D, offset: float, velocity: Vector3):
	if active_grinders.has(grinder):
		return  ## Already grinding

	var curve_length = curve.get_baked_length()
	if curve_length == 0:
		return

	# Create grinder data with starting offset
	var data = GrinderData.new(offset)
	grinder_data[grinder] = data
	active_grinders.append(grinder)

	# Create visual rope line
	data.rope_visual = MeshInstance3D.new()
	data.rope_visual.name = "RopeVisual"
	add_child(data.rope_visual)

	# Give player an initial boost along the rail direction
	var rail_pos_with_rotation = curve.sample_baked_with_rotation(offset)
	var rail_tangent = rail_pos_with_rotation.basis.z
	var world_rail_tangent = global_transform.basis * rail_tangent

	# Determine initial direction based on player's approach velocity
	var velocity_along_rail = velocity.dot(world_rail_tangent)
	var initial_direction = sign(velocity_along_rail) if abs(velocity_along_rail) > 1.0 else 1.0

	# Set player's velocity to move along rail at a good speed
	var initial_speed = max(abs(velocity_along_rail), 10.0)  # At least 10 units/sec
	grinder.linear_velocity = world_rail_tangent * initial_direction * initial_speed

	# Notify player they're grinding
	if grinder.has_method("start_grinding"):
		grinder.start_grinding(self)

	print("Rail: Player attached at offset ", offset, " with velocity ", velocity.length(), " -> rail speed: ", initial_speed)


func _remove_grinder(grinder: RigidBody3D):
	if not active_grinders.has(grinder):
		return

	# Remove visual rope
	if grinder_data.has(grinder):
		var data: GrinderData = grinder_data[grinder]
		if data.rope_visual and is_instance_valid(data.rope_visual):
			data.rope_visual.queue_free()

	active_grinders.erase(grinder)
	grinder_data.erase(grinder)

	# Notify player they stopped grinding
	if is_instance_valid(grinder) and grinder.has_method("stop_grinding"):
		grinder.stop_grinding()


func _update_grinder(grinder: RigidBody3D, delta: float):
	var data: GrinderData = grinder_data[grinder]
	var curve_length = curve.get_baked_length()

	if curve_length == 0:
		_remove_grinder(grinder)
		return

	# Find closest point on rail to player's current position
	var player_local_pos = to_local(grinder.global_position)
	var closest_offset = curve.get_closest_offset(player_local_pos)

	# ROPE PHYSICS: Move attachment point along rail based on player momentum
	# Look slightly ahead in the direction of player's velocity along the rail
	var current_velocity = grinder.linear_velocity
	var rail_pos_with_rotation = curve.sample_baked_with_rotation(closest_offset)
	var rail_tangent = rail_pos_with_rotation.basis.z
	var world_rail_tangent = global_transform.basis * rail_tangent

	# Project player velocity onto rail to determine sliding direction
	var velocity_along_rail = current_velocity.dot(world_rail_tangent)
	var slide_speed = velocity_along_rail * delta * 2.0  # How far attachment point slides

	# Update attachment point offset (slide along rail with player)
	var attachment_offset = closest_offset + slide_speed
	attachment_offset = clamp(attachment_offset, 0, curve_length)

	# Get attachment point on rail
	var attachment_point = curve.sample_baked(attachment_offset)
	var world_attachment_pos = to_global(attachment_point)

	# ROPE CONSTRAINT: Apply spring-damper forces to maintain rope length
	var rope_vector = grinder.global_position - world_attachment_pos
	var current_rope_length = rope_vector.length()

	# Only apply rope constraint when stretched beyond target length (gentle)
	if current_rope_length > rope_length and current_rope_length > 0.1:  # Avoid division by zero
		var rope_direction = rope_vector.normalized()
		var rope_extension = current_rope_length - rope_length

		# Spring force (Hooke's law: F = -kx) - gentle pull
		var spring_force = -rope_direction * rope_stiffness * rope_extension

		# Damping force (F = -cv) - only along rope direction
		var velocity_along_rope = current_velocity.dot(rope_direction)
		var damping_force = -rope_direction * rope_damping * velocity_along_rope

		# Calculate total rope force
		var total_rope_force = spring_force + damping_force

		# LIMIT maximum rope force to prevent extreme pulls
		var force_magnitude = total_rope_force.length()
		if force_magnitude > max_rope_force:
			total_rope_force = total_rope_force.normalized() * max_rope_force

		# Apply limited rope force
		grinder.apply_central_force(total_rope_force)

	# FORWARD MOMENTUM: Give player a gentle push along the rail to keep grinding
	var push_force = world_rail_tangent * 100.0  # Gentle constant forward push
	grinder.apply_central_force(push_force)

	# DRAW ROPE VISUAL
	if data.rope_visual and is_instance_valid(data.rope_visual):
		var immediate_mesh = ImmediateMesh.new()
		data.rope_visual.mesh = immediate_mesh

		# Create material for rope
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.9, 0.9, 0.3, 1.0)  # Yellow rope
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

		immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)

		# Draw line from attachment point to player
		var local_attachment = to_local(world_attachment_pos)
		var local_player = to_local(grinder.global_position)

		immediate_mesh.surface_add_vertex(local_attachment)
		immediate_mesh.surface_add_vertex(local_player)

		immediate_mesh.surface_end()

	# GRAVITY EFFECT on slopes: Accelerate downhill, decelerate uphill (gentle)
	var lookahead_offset = attachment_offset + sign(velocity_along_rail) * 2.0
	lookahead_offset = clamp(lookahead_offset, 0, curve_length)
	var lookahead_point = curve.sample_baked(lookahead_offset)
	var world_lookahead = to_global(lookahead_point)
	var slope_delta_y = world_lookahead.y - world_attachment_pos.y

	# Apply gentle gravity-based slope force along rail
	var slope_force = world_rail_tangent * (-slope_delta_y * gravity_multiplier * 50.0)
	grinder.apply_central_force(slope_force)

	# Calculate grinding speed (along rail component)
	var grind_speed = abs(velocity_along_rail)

	# Check if moving too slow - fall off rail
	if grind_speed < min_grind_speed:
		print("Speed too low (", grind_speed, "), falling off rail")
		_remove_grinder(grinder)
		return

	# Check if reached end of rail
	if attachment_offset <= 0.5 or attachment_offset >= curve_length - 0.5:
		# Launch player off the end
		var launch_velocity = grinder.linear_velocity
		if grinder.has_method("launch_from_rail"):
			grinder.launch_from_rail(launch_velocity)
		_remove_grinder(grinder)
		return

	# Update tracking data
	data.last_offset = data.closest_offset
	data.closest_offset = attachment_offset

	# Reduce angular velocity (prevent spinning)
	grinder.angular_velocity *= 0.3


## Called by player to detach from rail (jumping off)
func detach_grinder(grinder: RigidBody3D):
	if not active_grinders.has(grinder):
		return grinder.linear_velocity

	# Player maintains their current velocity
	var current_velocity = grinder.linear_velocity
	_remove_grinder(grinder)

	# Return velocity for player to use
	return current_velocity


## Check if a specific grinder is on this rail
func is_grinding(grinder: RigidBody3D) -> bool:
	return active_grinders.has(grinder)


## Get current grinding speed for a grinder
func get_grind_speed(grinder: RigidBody3D) -> float:
	if not grinder_data.has(grinder):
		return 0.0
	# Speed is the player's actual velocity magnitude
	return grinder.linear_velocity.length()
