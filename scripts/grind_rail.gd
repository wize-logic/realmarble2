extends Path3D
class_name GrindRail

## Rail grinding with rope physics
## Player hangs from rail by a rope and can swing

@export var rail_speed: float = 15.0
@export var rope_length: float = 5.0
@export var max_attach_distance: float = 25.0
@export var gravity: float = 15.0
@export var swing_damping: float = 3.0
@export var swing_force: float = 8.0  # How much player input affects swing
@export var max_swing_angle: float = 1.2  # ~70 degrees max swing
@export var rope_thickness: float = 0.08

var active_grinders: Dictionary = {}  # grinder -> state dict
var rope_visuals: Dictionary = {}  # grinder -> MeshInstance3D


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


func _create_rope_visual() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = rope_thickness
	cylinder.bottom_radius = rope_thickness
	cylinder.height = 1.0  # Will be scaled
	cylinder.radial_segments = 8  # Make it round, not rectangular
	cylinder.rings = 1
	mesh_instance.mesh = cylinder

	# Create rope material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.35, 0.2)  # Brown rope color
	mat.roughness = 0.95
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mesh_instance.material_override = mat

	get_tree().root.add_child(mesh_instance)
	return mesh_instance


func _update_rope_visual(mesh: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var rope_vec: Vector3 = end - start
	var rope_len: float = rope_vec.length()

	if rope_len < 0.01:
		return

	var rope_dir: Vector3 = rope_vec / rope_len

	# Position at midpoint
	mesh.global_position = (start + end) / 2.0

	# Build basis to orient cylinder along rope direction
	# Cylinder's local Y axis should point along rope_dir
	var y_axis: Vector3 = rope_dir
	var x_axis: Vector3
	if absf(y_axis.dot(Vector3.UP)) < 0.99:
		x_axis = y_axis.cross(Vector3.UP).normalized()
	else:
		x_axis = y_axis.cross(Vector3.FORWARD).normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()

	mesh.global_transform.basis = Basis(x_axis, y_axis, z_axis)
	mesh.scale = Vector3(1, rope_len, 1)


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

	# Start with small initial swing angle (mostly hanging straight down)
	var initial_angle: float = 0.0

	# Small initial angular velocity from player's horizontal velocity
	var horizontal_vel: Vector3 = grinder.linear_velocity
	horizontal_vel.y = 0
	var right: Vector3 = tangent.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.1:
		right = tangent.cross(Vector3.FORWARD).normalized()
	var initial_angular_vel: float = horizontal_vel.dot(right) / rope_length * 0.3  # Reduced

	active_grinders[grinder] = {
		"offset": offset,
		"direction": direction,
		"swing_angle": initial_angle,
		"angular_velocity": clamp(initial_angular_vel, -2.0, 2.0)  # Clamp initial velocity
	}

	# Create rope visual
	rope_visuals[grinder] = _create_rope_visual()

	if grinder.has_method("start_grinding"):
		grinder.start_grinding(self)

	return true


func detach_grinder(grinder: RigidBody3D) -> Vector3:
	if not active_grinders.has(grinder):
		return Vector3.ZERO

	var state: Dictionary = active_grinders[grinder]
	var exit_velocity: Vector3 = _calculate_velocity(grinder, state)

	active_grinders.erase(grinder)

	# Clean up rope visual
	if rope_visuals.has(grinder):
		var rope: MeshInstance3D = rope_visuals[grinder]
		if is_instance_valid(rope):
			rope.queue_free()
		rope_visuals.erase(grinder)

	if is_instance_valid(grinder) and grinder.has_method("stop_grinding"):
		grinder.stop_grinding()

	return exit_velocity


func _calculate_velocity(grinder: RigidBody3D, state: Dictionary) -> Vector3:
	var length: float = get_rail_length()
	var current_pos: Vector3 = get_point_at_offset(state.offset)

	# Calculate actual rail direction from positions (not tangent)
	var rail_dir: Vector3
	if state.direction > 0:
		# Moving toward end
		var ahead_offset: float = minf(state.offset + 1.0, length)
		var ahead_pos: Vector3 = get_point_at_offset(ahead_offset)
		rail_dir = (ahead_pos - current_pos).normalized()
	else:
		# Moving toward start
		var ahead_offset: float = maxf(state.offset - 1.0, 0.0)
		var ahead_pos: Vector3 = get_point_at_offset(ahead_offset)
		rail_dir = (ahead_pos - current_pos).normalized()

	# Get perpendicular for swing calculation
	var right: Vector3 = rail_dir.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.1:
		right = rail_dir.cross(Vector3.FORWARD).normalized()

	# Velocity along rail (in actual travel direction)
	var rail_vel: Vector3 = rail_dir * rail_speed

	# Velocity from swing (tangent to the swing arc)
	var swing_tangent: Vector3 = right * cos(state.swing_angle) + Vector3.UP * sin(state.swing_angle)
	var swing_vel: Vector3 = swing_tangent * state.angular_velocity * rope_length

	return rail_vel + swing_vel


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
		# Clean up rope visual
		if rope_visuals.has(grinder):
			var rope: MeshInstance3D = rope_visuals[grinder]
			if is_instance_valid(rope):
				rope.queue_free()
			rope_visuals.erase(grinder)
		active_grinders.erase(grinder)


func _update_grinder(grinder: RigidBody3D, delta: float) -> void:
	var state: Dictionary = active_grinders[grinder]
	var length: float = get_rail_length()

	if length <= 0:
		detach_grinder(grinder)
		return

	var tangent: Vector3 = get_tangent_at_offset(state.offset)
	var right: Vector3 = tangent.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.1:
		right = tangent.cross(Vector3.FORWARD).normalized()

	# Get rail end positions for direction control
	var current_pos: Vector3 = get_point_at_offset(state.offset)
	var start_pos: Vector3 = get_point_at_offset(0.0)
	var end_pos: Vector3 = get_point_at_offset(length)

	# Direction control along rail
	if "movement_input_direction" in grinder:
		var input_dir: Vector3 = grinder.movement_input_direction
		if input_dir.length_squared() > 0.01:
			var dir_to_end: Vector3 = (end_pos - current_pos).normalized()
			var dir_to_start: Vector3 = (start_pos - current_pos).normalized()

			var dot_to_end: float = input_dir.dot(dir_to_end)
			var dot_to_start: float = input_dir.dot(dir_to_start)

			if dot_to_end > 0.2 and dot_to_end > dot_to_start:
				state.direction = 1
			elif dot_to_start > 0.2 and dot_to_start > dot_to_end:
				state.direction = -1

			# Swing control - input perpendicular to rail direction
			var swing_input: float = input_dir.dot(right)
			state.angular_velocity += swing_input * swing_force * delta

	# Pendulum physics - gravity creates restoring force
	var gravity_torque: float = -gravity / rope_length * sin(state.swing_angle)
	state.angular_velocity += gravity_torque * delta

	# Damping
	state.angular_velocity *= (1.0 - swing_damping * delta)

	# Update swing angle
	state.swing_angle += state.angular_velocity * delta

	# Clamp swing angle to prevent going over the top
	state.swing_angle = clamp(state.swing_angle, -max_swing_angle, max_swing_angle)

	# Move along rail
	state.offset += state.direction * rail_speed * delta

	# Check if reached end - detach with full velocity
	if state.offset <= 0.0 or state.offset >= length:
		var exit_vel: Vector3 = _calculate_velocity(grinder, state)
		grinder.linear_velocity = exit_vel
		# Clean up rope visual
		if rope_visuals.has(grinder):
			var rope: MeshInstance3D = rope_visuals[grinder]
			if is_instance_valid(rope):
				rope.queue_free()
			rope_visuals.erase(grinder)
		active_grinders.erase(grinder)
		if grinder.has_method("stop_grinding"):
			grinder.stop_grinding()
		return

	# Calculate player position: attachment point + rope direction
	var attach_point: Vector3 = get_point_at_offset(state.offset)
	var rope_dir: Vector3 = Vector3.DOWN * cos(state.swing_angle) + right * sin(state.swing_angle)
	var player_pos: Vector3 = attach_point + rope_dir * rope_length

	grinder.global_position = player_pos
	grinder.linear_velocity = _calculate_velocity(grinder, state)
	grinder.angular_velocity = Vector3.ZERO

	# Update rope visual
	if rope_visuals.has(grinder):
		var rope: MeshInstance3D = rope_visuals[grinder]
		if is_instance_valid(rope):
			_update_rope_visual(rope, attach_point, player_pos)
