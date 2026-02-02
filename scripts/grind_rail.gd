extends Path3D
class_name GrindRail

## Minimal rail grinding system
## Player moves along the curve, W/S controls direction

@export var rail_speed: float = 20.0
@export var rail_height_offset: float = 1.0
@export var max_attach_distance: float = 25.0

var active_grinders: Dictionary = {}  # grinder -> state dict

func _ready() -> void:
	if not curve:
		curve = Curve3D.new()


func get_rail_length() -> float:
	if not curve:
		return 0.0
	return curve.get_baked_length()


func get_point_at_offset(offset: float) -> Vector3:
	if not curve:
		return global_position
	return to_global(curve.sample_baked(offset))


func get_tangent_at_offset(offset: float) -> Vector3:
	if not curve:
		return Vector3.FORWARD
	var xform: Transform3D = curve.sample_baked_with_rotation(offset)
	return global_transform.basis * xform.basis.z.normalized()


func can_attach(grinder: RigidBody3D) -> bool:
	if active_grinders.has(grinder):
		return false
	var length: float = get_rail_length()
	if length <= 0:
		return false
	var local_pos: Vector3 = to_local(grinder.global_position)
	var closest_offset: float = curve.get_closest_offset(local_pos)
	var closest_point: Vector3 = get_point_at_offset(closest_offset)
	return grinder.global_position.distance_to(closest_point) <= max_attach_distance


func try_attach_player(grinder: RigidBody3D) -> bool:
	if not can_attach(grinder):
		return false

	var length: float = get_rail_length()
	var local_pos: Vector3 = to_local(grinder.global_position)
	var offset: float = curve.get_closest_offset(local_pos)
	offset = clamp(offset, 1.0, length - 1.0)

	# Determine initial direction from velocity
	var tangent: Vector3 = get_tangent_at_offset(offset)
	var direction: int = 1 if grinder.linear_velocity.dot(tangent) >= 0 else -1

	active_grinders[grinder] = {"offset": offset, "direction": direction}

	if grinder.has_method("start_grinding"):
		grinder.start_grinding(self)

	return true


func detach_grinder(grinder: RigidBody3D) -> Vector3:
	if not active_grinders.has(grinder):
		return Vector3.ZERO

	var state: Dictionary = active_grinders[grinder]
	var tangent: Vector3 = get_tangent_at_offset(state.offset)
	var exit_velocity: Vector3 = tangent * state.direction * rail_speed

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
		if grinder.get("current_rail") != self:
			to_remove.append(grinder)
			continue

		_update_grinder(grinder, delta)

	for grinder in to_remove:
		active_grinders.erase(grinder)


func _update_grinder(grinder: RigidBody3D, delta: float) -> void:
	var state: Dictionary = active_grinders[grinder]
	var length: float = get_rail_length()

	if length <= 0:
		detach_grinder(grinder)
		return

	# W = forward (direction 1), S = backward (direction -1)
	var input_forward: float = Input.get_axis("down", "up")
	if absf(input_forward) > 0.1:
		state.direction = 1 if input_forward > 0 else -1

	# Move along rail
	state.offset += state.direction * rail_speed * delta

	# Check if reached end - detach
	if state.offset <= 0.0 or state.offset >= length:
		var tangent: Vector3 = get_tangent_at_offset(clamp(state.offset, 0.0, length))
		grinder.linear_velocity = tangent * state.direction * rail_speed
		active_grinders.erase(grinder)
		if grinder.has_method("stop_grinding"):
			grinder.stop_grinding()
		return

	# Position player on rail
	var rail_pos: Vector3 = get_point_at_offset(state.offset)
	rail_pos.y += rail_height_offset
	grinder.global_position = rail_pos

	# Set velocity along rail
	var tangent: Vector3 = get_tangent_at_offset(state.offset)
	grinder.linear_velocity = tangent * state.direction * rail_speed
	grinder.angular_velocity = Vector3.ZERO
