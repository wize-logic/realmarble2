extends Path3D
class_name GrindRail

## Rail grinding system similar to Sonic Adventure 2
## Dynamic physics-based grinding - player maintains momentum and responds to gravity

@export var detection_radius: float = 5.0  ## How close player needs to be to snap to rail
@export var rail_constraint_strength: float = 50.0  ## How strongly rail pulls player onto it
@export var min_grind_speed: float = 2.0  ## Minimum speed to stay on rail (very low)
@export var gravity_multiplier: float = 1.5  ## How much gravity affects grind speed on slopes
@export var rail_friction: float = 0.98  ## Speed retention per second (0.98 = loses 2% per second)

var active_grinders: Array[RigidBody3D] = []  ## Players currently grinding this rail
var grinder_data: Dictionary = {}  ## Stores grinding data per player

## Data structure for each grinder
class GrinderData:
	var closest_offset: float = 0.0  ## Current position along curve
	var last_offset: float = 0.0  ## Previous position (for direction detection)

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

	# Must be above the rail (positive Y) and close to directly above
	if vertical_offset < 0.2:  # Must be at least 0.2 units above
		return

	# Check horizontal distance - shouldn't be too far to the side
	var horizontal_offset = Vector2(to_player.x, to_player.z).length()
	if horizontal_offset > 2.5:  # Max 2.5 units horizontal offset (increased for easier grinding)
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

	# Notify player they're grinding
	if grinder.has_method("start_grinding"):
		grinder.start_grinding(self)

	print("Rail: Player attached at offset ", offset, " with velocity ", velocity.length())


func _remove_grinder(grinder: RigidBody3D):
	if not active_grinders.has(grinder):
		return

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
	var closest_point = curve.sample_baked(closest_offset)
	var rail_pos_with_rotation = curve.sample_baked_with_rotation(closest_offset)

	# Get rail tangent (direction along rail) and up vector
	var rail_tangent = rail_pos_with_rotation.basis.z
	var rail_up = rail_pos_with_rotation.basis.y
	var world_rail_tangent = global_transform.basis * rail_tangent
	var world_rail_up = global_transform.basis * rail_up

	# Get rail position in world space (slightly above for player to sit on top)
	var rail_height_offset = 0.6
	var world_rail_pos = to_global(closest_point) + world_rail_up * rail_height_offset

	# AGGRESSIVE SNAP: Force player position to be exactly on top of rail
	grinder.global_position = world_rail_pos

	# PROJECT velocity along rail tangent (maintain momentum direction)
	var current_velocity = grinder.linear_velocity
	var velocity_along_rail = current_velocity.dot(world_rail_tangent)

	# Keep only the velocity component along the rail
	var speed_magnitude = abs(velocity_along_rail)
	var velocity_direction = sign(velocity_along_rail)

	# FORWARD PUSH: Give player a constant push to prevent getting stuck
	speed_magnitude += 5.0 * delta  # Add constant forward momentum

	# Set velocity to be along rail tangent only
	grinder.linear_velocity = world_rail_tangent * velocity_direction * speed_magnitude

	# GRAVITY EFFECT on slopes (adjust speed based on slope)
	# Calculate slope direction (is rail going up or down?)
	var lookahead_offset = closest_offset + velocity_direction * 2.0
	lookahead_offset = clamp(lookahead_offset, 0, curve_length)
	var lookahead_point = curve.sample_baked(lookahead_offset)
	var world_lookahead = to_global(lookahead_point)
	var slope_delta_y = world_lookahead.y - to_global(closest_point).y

	# Adjust speed based on slope (downhill = faster, uphill = slower)
	var gravity_acceleration = slope_delta_y * -gravity_multiplier * 10.0 * delta
	speed_magnitude += gravity_acceleration

	# Update velocity with gravity effect
	grinder.linear_velocity = world_rail_tangent * velocity_direction * speed_magnitude

	# Check if moving too slow - fall off rail
	if speed_magnitude < min_grind_speed:
		print("Speed too low (", speed_magnitude, "), falling off rail")
		_remove_grinder(grinder)
		return

	# Check if reached end of rail
	if closest_offset <= 0.5 or closest_offset >= curve_length - 0.5:
		# Launch player off the end
		var launch_velocity = grinder.linear_velocity
		if grinder.has_method("launch_from_rail"):
			grinder.launch_from_rail(launch_velocity)
		_remove_grinder(grinder)
		return

	# Update tracking data
	data.last_offset = data.closest_offset
	data.closest_offset = closest_offset

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
