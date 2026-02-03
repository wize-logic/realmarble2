extends Path3D
class_name GrindRail

## Rail grinding with rope physics
## Player hangs from rail by a rope and can swing

@export var rail_speed: float = 15.0
@export var boost_speed: float = 25.0  # Max speed when boosting
@export var boost_acceleration: float = 25.0  # How fast you accelerate when boosting
@export var rope_length: float = 5.0
@export var max_attach_distance: float = 25.0
@export var gravity: float = 28.0  # Gravity for pendulum feel
@export var swing_damping: float = 0.8  # Light damping for fluid swings
@export var swing_force: float = 12.0  # Responsive swing control
@export var rope_thickness: float = 0.008  # Ultra-thin rope (wire-like)

# Transition smoothing
@export var transition_duration: float = 0.25  # Smooth attach transition time
@export var momentum_transfer: float = 0.85  # How much velocity converts to swing

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
	cylinder.radial_segments = 6  # Fewer segments for thin wire look
	cylinder.rings = 1
	mesh_instance.mesh = cylinder

	# Create thin wire/cable material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.35)  # Dark metallic gray (wire/cable look)
	mat.metallic = 0.7  # Metallic sheen
	mat.roughness = 0.4  # Slightly shiny
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
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

	# Determine initial direction from velocity (prefer direction of movement)
	var tangent: Vector3 = get_tangent_at_offset(offset)
	var vel_dot: float = grinder.linear_velocity.dot(tangent)
	var direction: int = 1 if vel_dot >= 0 else -1

	# Calculate right vector for swing calculations
	var right: Vector3 = tangent.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.1:
		right = tangent.cross(Vector3.FORWARD).normalized()

	# Convert incoming velocity to initial swing angle and angular velocity
	# This creates a fluid momentum transfer into the swing
	var horizontal_vel: Vector3 = grinder.linear_velocity
	var perpendicular_speed: float = horizontal_vel.dot(right)

	# Initial swing angle based on perpendicular momentum (swing INTO the rail motion)
	var initial_angle: float = clamp(perpendicular_speed * 0.04 * momentum_transfer, -0.5, 0.5)

	# Initial angular velocity from the player's momentum
	var initial_angular_vel: float = perpendicular_speed / rope_length * momentum_transfer
	initial_angular_vel = clamp(initial_angular_vel, -4.0, 4.0)

	# Inherit some speed from player's velocity along the rail
	var speed_along_rail: float = absf(vel_dot)
	var initial_speed: float = clamp(
		lerpf(rail_speed, speed_along_rail, 0.6),  # Blend between base and incoming speed
		rail_speed * 0.8,  # Minimum speed
		boost_speed  # Maximum speed
	)

	# Store starting position for smooth transition
	var attach_point: Vector3 = get_point_at_offset(offset)
	var target_rope_dir: Vector3 = Vector3.DOWN * cos(initial_angle) + right * sin(initial_angle)
	var target_pos: Vector3 = attach_point + target_rope_dir * rope_length

	active_grinders[grinder] = {
		"offset": offset,
		"direction": direction,
		"swing_angle": initial_angle,
		"angular_velocity": initial_angular_vel,
		"current_speed": initial_speed,
		# Smooth transition state
		"transition_progress": 0.0,
		"start_position": grinder.global_position,
		"target_position": target_pos,
		"transitioning": true
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
	var clamped_offset: float = clamp(state.offset, 0.0, length)

	# Calculate actual rail direction from positions (not tangent)
	# Handle edge cases where we're at or past the rail ends
	var rail_dir: Vector3
	if state.direction > 0:
		# Moving toward end - look ahead, or look back and invert if at edge
		if clamped_offset >= length - 0.5:
			# At end - look backward and invert to get forward direction
			var behind_pos: Vector3 = get_point_at_offset(maxf(clamped_offset - 2.0, 0.0))
			var current_pos: Vector3 = get_point_at_offset(clamped_offset)
			rail_dir = (current_pos - behind_pos).normalized()
		else:
			var current_pos: Vector3 = get_point_at_offset(clamped_offset)
			var ahead_pos: Vector3 = get_point_at_offset(minf(clamped_offset + 2.0, length))
			rail_dir = (ahead_pos - current_pos).normalized()
	else:
		# Moving toward start - look ahead (backward on rail), or invert if at edge
		if clamped_offset <= 0.5:
			# At start - look forward and invert to get backward direction
			var current_pos: Vector3 = get_point_at_offset(clamped_offset)
			var ahead_pos: Vector3 = get_point_at_offset(minf(clamped_offset + 2.0, length))
			rail_dir = (current_pos - ahead_pos).normalized()
		else:
			var current_pos: Vector3 = get_point_at_offset(clamped_offset)
			var behind_pos: Vector3 = get_point_at_offset(maxf(clamped_offset - 2.0, 0.0))
			rail_dir = (behind_pos - current_pos).normalized()

	# Get perpendicular for swing calculation
	var right: Vector3 = rail_dir.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.1:
		right = rail_dir.cross(Vector3.FORWARD).normalized()

	# Velocity along rail (in actual travel direction)
	var current_speed: float = state.get("current_speed", rail_speed)
	var rail_vel: Vector3 = rail_dir * current_speed

	# Velocity from swing (tangent to the swing arc) - this creates the satisfying momentum feel
	# The swing tangent is perpendicular to the rope direction
	var swing_tangent: Vector3 = right * cos(state.swing_angle) + Vector3.UP * sin(state.swing_angle)
	var swing_vel: Vector3 = swing_tangent * state.angular_velocity * rope_length

	# Add a small vertical component based on swing position for more dynamic feel
	# When swinging up, you get a small lift
	var swing_lift: float = sin(state.swing_angle) * absf(state.angular_velocity) * 0.15
	swing_vel.y += swing_lift

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
	var attach_point: Vector3 = get_point_at_offset(state.offset)
	var start_pos: Vector3 = get_point_at_offset(0.0)
	var end_pos: Vector3 = get_point_at_offset(length)

	# Handle smooth transition when first attaching
	var is_transitioning: bool = state.get("transitioning", false)
	if is_transitioning:
		state.transition_progress += delta / transition_duration
		if state.transition_progress >= 1.0:
			state.transition_progress = 1.0
			state.transitioning = false

	# Direction control along rail (responsive controls)
	if "movement_input_direction" in grinder:
		var input_dir: Vector3 = grinder.movement_input_direction
		if input_dir.length_squared() > 0.01:
			var dir_to_end: Vector3 = (end_pos - attach_point).normalized()
			var dir_to_start: Vector3 = (start_pos - attach_point).normalized()

			var dot_to_end: float = input_dir.dot(dir_to_end)
			var dot_to_start: float = input_dir.dot(dir_to_start)

			# More responsive direction switching
			if dot_to_end > 0.15 and dot_to_end > dot_to_start:
				state.direction = 1
			elif dot_to_start > 0.15 and dot_to_start > dot_to_end:
				state.direction = -1

			# Swing control - input perpendicular to rail direction (very responsive)
			var swing_input: float = input_dir.dot(right)
			# Use exponential response for more satisfying feel
			var swing_power: float = swing_input * absf(swing_input) * 0.5 + swing_input * 0.5
			state.angular_velocity += swing_power * swing_force * delta

	# Pendulum physics - gravity creates restoring force
	# Use sine for small angles, but allow bigger swings to feel weighty
	var gravity_torque: float = -gravity / rope_length * sin(state.swing_angle)
	state.angular_velocity += gravity_torque * delta

	# Variable damping - less damping at low speeds for fluid feel, more at high speeds for control
	var speed_factor: float = minf(absf(state.angular_velocity) / 3.0, 1.0)
	var effective_damping: float = lerpf(swing_damping * 0.5, swing_damping * 1.5, speed_factor)
	state.angular_velocity *= (1.0 - effective_damping * delta)

	# Update swing angle
	state.swing_angle += state.angular_velocity * delta

	# Soft clamp swing angle (allow big swings but resist extremes)
	var max_swing: float = PI * 0.7  # Allow up to ~126 degree swings
	if absf(state.swing_angle) > max_swing:
		var excess: float = absf(state.swing_angle) - max_swing
		var resistance: float = 1.0 + excess * 2.0  # Increasing resistance
		state.angular_velocity /= resistance
		state.swing_angle = clamp(state.swing_angle, -PI * 0.85, PI * 0.85)

	# Boost when holding shift (smooth acceleration)
	var is_boosting: bool = Input.is_key_pressed(KEY_SHIFT)
	if is_boosting:
		# Smooth acceleration curve
		var speed_ratio: float = state.current_speed / boost_speed
		var accel_factor: float = 1.0 - speed_ratio * speed_ratio  # Slower as you approach max
		state.current_speed = minf(state.current_speed + boost_acceleration * accel_factor * delta, boost_speed)
	else:
		# Gradual deceleration back to base speed
		if state.current_speed > rail_speed:
			var decel: float = boost_acceleration * 0.4 * delta
			state.current_speed = maxf(state.current_speed - decel, rail_speed)

	# Move along rail
	state.offset += state.direction * state.current_speed * delta

	# Check if reached end - launch player with satisfying momentum
	if state.offset <= 0.0 or state.offset >= length:
		var exit_vel: Vector3 = _calculate_velocity(grinder, state)

		# Calculate launch direction based on rail end tangent and swing
		var end_tangent: Vector3 = get_tangent_at_offset(clamp(state.offset, 0.0, length))
		if state.direction < 0:
			end_tangent = -end_tangent

		# Add upward launch proportional to speed (faster = higher launch)
		var speed_bonus: float = state.current_speed / rail_speed
		var launch_strength: float = 16.0 + 6.0 * speed_bonus

		# Include swing momentum in launch (swing forward = more forward momentum)
		var swing_boost: float = sin(state.swing_angle) * state.angular_velocity * rope_length * 0.3
		exit_vel += end_tangent * swing_boost
		exit_vel.y = maxf(exit_vel.y, 0.0) + launch_strength

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

	# Calculate target player position: attachment point + rope direction
	var rope_dir: Vector3 = Vector3.DOWN * cos(state.swing_angle) + right * sin(state.swing_angle)
	var target_pos: Vector3 = attach_point + rope_dir * rope_length

	# Apply smooth transition if still transitioning
	var player_pos: Vector3
	var rope_start: Vector3 = attach_point
	if is_transitioning:
		# Use smooth ease-out curve for natural feel
		var t: float = state.transition_progress
		var ease_t: float = 1.0 - (1.0 - t) * (1.0 - t)  # Quadratic ease-out
		player_pos = state.start_position.lerp(target_pos, ease_t)
		# Rope appears to extend from attachment point
		rope_start = attach_point
	else:
		player_pos = target_pos

	grinder.global_position = player_pos
	grinder.linear_velocity = _calculate_velocity(grinder, state)
	grinder.angular_velocity = Vector3.ZERO

	# Update rope visual
	if rope_visuals.has(grinder):
		var rope: MeshInstance3D = rope_visuals[grinder]
		if is_instance_valid(rope):
			_update_rope_visual(rope, rope_start, player_pos)
