extends Path3D
class_name GrindRail

## Simple, robust rail grinding system
## Player moves along the rail curve with direct velocity control
## No rope physics - player follows the path directly

# Rail settings
@export var rail_speed: float = 25.0  # Base movement speed along rail
@export var max_rail_speed: float = 50.0  # Maximum speed along rail
@export var rail_acceleration: float = 30.0  # How fast speed builds up
@export var gravity_influence: float = 0.4  # How much slopes affect speed
@export var rail_height_offset: float = 1.0  # Height above rail for player center

# Boost settings
@export var boost_acceleration: float = 40.0  # Additional acceleration when shift held
@export var boost_max_speed: float = 70.0  # Max speed when boosting

# Launch settings
@export var end_launch_upward: float = 18.0  # Upward impulse at rail end
@export var end_launch_forward_mult: float = 0.8  # Forward velocity multiplier at end

# Targeting
@export var max_attach_distance: float = 25.0  # Max distance for E key attachment

# Active grinders
var active_grinders: Dictionary = {}  # grinder -> GrinderState

class GrinderState:
	var offset: float = 0.0  # Position along curve (0 to length)
	var speed: float = 0.0  # Current speed along rail (positive = forward)
	var direction: int = 1  # 1 = forward, -1 = backward
	var is_boosting: bool = false
	var attach_time: float = 0.0

	func _init(start_offset: float, initial_direction: int = 1):
		offset = start_offset
		direction = initial_direction
		attach_time = Time.get_ticks_msec() / 1000.0


func _ready() -> void:
	if not curve:
		curve = Curve3D.new()
		push_warning("GrindRail: No curve assigned")


func _exit_tree() -> void:
	# Clean up all grinders when rail is removed
	for grinder in active_grinders.keys():
		if is_instance_valid(grinder) and grinder.has_method("stop_grinding"):
			grinder.stop_grinding()
	active_grinders.clear()


func get_rail_length() -> float:
	if not curve:
		return 0.0
	return curve.get_baked_length()


func get_point_at_offset(offset: float) -> Vector3:
	"""Get world position at offset along rail"""
	if not curve:
		return global_position
	var local_pos: Vector3 = curve.sample_baked(offset)
	return to_global(local_pos)


func get_tangent_at_offset(offset: float) -> Vector3:
	"""Get normalized tangent direction at offset"""
	if not curve:
		return Vector3.FORWARD
	var xform: Transform3D = curve.sample_baked_with_rotation(offset)
	var tangent_local: Vector3 = xform.basis.z.normalized()
	return global_transform.basis * tangent_local


func can_attach(grinder: RigidBody3D) -> bool:
	"""Check if a grinder can attach to this rail"""
	if active_grinders.has(grinder):
		return false

	var length: float = get_rail_length()
	if length <= 0:
		return false

	# Check distance to closest point on rail
	var grinder_pos: Vector3 = grinder.global_position
	var local_pos: Vector3 = to_local(grinder_pos)
	var closest_offset: float = curve.get_closest_offset(local_pos)
	var closest_point: Vector3 = get_point_at_offset(closest_offset)

	return grinder_pos.distance_to(closest_point) <= max_attach_distance


func try_attach_player(grinder: RigidBody3D) -> bool:
	"""Attempt to attach player when they press E"""
	if not can_attach(grinder):
		return false

	var length: float = get_rail_length()
	var grinder_pos: Vector3 = grinder.global_position
	var local_pos: Vector3 = to_local(grinder_pos)

	# Find closest point on rail
	var raw_offset: float = curve.get_closest_offset(local_pos)

	# Clamp away from ends to prevent immediate launch
	var min_offset: float = minf(3.0, length * 0.1)
	var offset: float = clamp(raw_offset, min_offset, length - min_offset)

	# Determine initial direction based on player velocity
	var tangent: Vector3 = get_tangent_at_offset(offset)
	var vel_dot: float = grinder.linear_velocity.dot(tangent)
	var direction: int = 1 if vel_dot >= 0 else -1

	# Create state
	var state := GrinderState.new(offset, direction)
	state.speed = minf(absf(vel_dot) * 0.5, rail_speed)  # Start with some momentum
	active_grinders[grinder] = state

	# Notify player
	if grinder.has_method("start_grinding"):
		grinder.start_grinding(self)

	DebugLogger.dlog(DebugLogger.Category.RAILS, "[%s] Player attached at offset %.1f/%.1f" % [name, offset, length])
	return true


func detach_grinder(grinder: RigidBody3D) -> Vector3:
	"""Detach grinder and return exit velocity"""
	if not active_grinders.has(grinder):
		return Vector3.ZERO

	var state: GrinderState = active_grinders[grinder]
	var tangent: Vector3 = get_tangent_at_offset(state.offset)
	var exit_velocity: Vector3 = tangent * state.direction * state.speed

	active_grinders.erase(grinder)

	if is_instance_valid(grinder) and grinder.has_method("stop_grinding"):
		grinder.stop_grinding()

	return exit_velocity


func _physics_process(delta: float) -> void:
	var to_remove: Array = []

	for grinder in active_grinders.keys():
		if not is_instance_valid(grinder):
			to_remove.append(grinder)
			continue

		# If grinder's current_rail doesn't match us, they detached elsewhere
		if grinder.get("current_rail") != self:
			to_remove.append(grinder)
			continue

		_update_grinder(grinder, delta)

	# Clean up
	for grinder in to_remove:
		active_grinders.erase(grinder)


func _update_grinder(grinder: RigidBody3D, delta: float) -> void:
	var state: GrinderState = active_grinders[grinder]
	var length: float = get_rail_length()

	if length <= 0:
		detach_grinder(grinder)
		return

	# Get rail info at current position
	var tangent: Vector3 = get_tangent_at_offset(state.offset)
	var rail_pos: Vector3 = get_point_at_offset(state.offset)

	# Check for player input direction
	if "movement_input_direction" in grinder:
		var input_dir: Vector3 = grinder.movement_input_direction
		if input_dir.length_squared() > 0.01:
			var dot: float = input_dir.dot(tangent)
			if absf(dot) > 0.2:
				state.direction = 1 if dot > 0 else -1

	# Check for boost (shift key)
	state.is_boosting = Input.is_key_pressed(KEY_SHIFT)

	# Calculate slope influence
	var look_ahead: float = clamp(state.offset + state.direction * 2.0, 0, length)
	var ahead_pos: Vector3 = get_point_at_offset(look_ahead)
	var slope: float = (rail_pos.y - ahead_pos.y) * state.direction  # Positive = downhill

	# Apply acceleration
	var accel: float = rail_acceleration
	if state.is_boosting:
		accel += boost_acceleration

	# Slope affects speed
	accel += slope * gravity_influence * 50.0

	# Accelerate
	var target_speed: float = max_rail_speed
	if state.is_boosting:
		target_speed = boost_max_speed

	state.speed = minf(state.speed + accel * delta, target_speed)
	state.speed = maxf(state.speed, rail_speed * 0.5)  # Minimum speed

	# Move along rail
	state.offset += state.direction * state.speed * delta

	# Check for end of rail
	var min_grind_time: float = 0.3
	var time_grinding: float = Time.get_ticks_msec() / 1000.0 - state.attach_time

	if time_grinding > min_grind_time and (state.offset <= 0.5 or state.offset >= length - 0.5):
		_launch_grinder(grinder, state, tangent)
		return

	# Clamp offset
	state.offset = clamp(state.offset, 0.5, length - 0.5)

	# Position player on rail
	var target_pos: Vector3 = get_point_at_offset(state.offset)
	target_pos.y += rail_height_offset

	# Smooth movement to rail position
	var current_pos: Vector3 = grinder.global_position
	var new_pos: Vector3 = current_pos.lerp(target_pos, 15.0 * delta)

	# Apply position and velocity
	grinder.global_position = new_pos
	grinder.linear_velocity = tangent * state.direction * state.speed

	# Spin effect when boosting
	if state.is_boosting:
		grinder.angular_velocity = tangent * state.direction * 12.0
	else:
		grinder.angular_velocity = grinder.angular_velocity.lerp(Vector3.ZERO, 5.0 * delta)


func _launch_grinder(grinder: RigidBody3D, state: GrinderState, tangent: Vector3) -> void:
	"""Launch player at end of rail"""
	DebugLogger.dlog(DebugLogger.Category.RAILS, "[%s] End of rail - launching!" % name)

	# Calculate exit velocity
	var exit_velocity: Vector3 = tangent * state.direction * state.speed * end_launch_forward_mult
	exit_velocity.y += end_launch_upward

	# Notify player before clearing state
	if grinder.has_method("launch_from_rail"):
		grinder.launch_from_rail(exit_velocity)

	# Apply impulse
	grinder.linear_velocity = exit_velocity

	# Clean up
	active_grinders.erase(grinder)

	if grinder.has_method("stop_grinding"):
		grinder.stop_grinding()
