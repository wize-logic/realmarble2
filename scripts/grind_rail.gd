extends Path3D
class_name GrindRail

## 100% NO AUTO-DETACH + VERY FAST SPEED BUILDUP + STRONG UPWARD LAUNCH
## Now attaches from a LARGE AREA BELOW the rail
## STUCK SAFEGUARD: Detects when player can't make progress and applies boosts or safe detachment
## MANUAL ATTACHMENT: Players must press E while looking at the rail to attach

@export var detection_radius: float = 18.0
@export var manual_attachment_only: bool = true  # Require E key press to attach
@export var rope_length: float = 3.2
@export var max_allowed_stretch: float = 30.0
@export var rope_stiffness: float = 160.0
@export var rope_damping: float = 80.0
@export var max_rope_force: float = 1400.0
@export var emergency_force_multiplier: float = 18.0

@export var gravity_multiplier: float = 0.22
@export var rail_friction: float = 0.996
@export var constant_forward_push: float = 420.0  # aggressive acceleration

@export var initial_snap_stiffness_multiplier: float = 7.0
@export var initial_snap_duration: float = 0.45

# Launch settings at rail end
@export var end_launch_upward_impulse: float = 200.0
@export var end_launch_forward_boost: float = 1.5

# Stuck safeguard settings
@export var stuck_detection_interval: float = 1.0  # Check progress every N seconds
@export var stuck_min_progress: float = 2.0  # Minimum distance to travel in interval
@export var stuck_threshold_time: float = 2.5  # Time stuck before applying boost
@export var emergency_boost_force: float = 800.0  # Force applied when stuck
@export var max_boost_attempts: int = 3  # Max boosts before detaching
@export var boost_cooldown: float = 1.5  # Time between boost attempts

var active_grinders: Array[RigidBody3D] = []
var grinder_data: Dictionary = {}
var nearby_players: Array[RigidBody3D] = []  # Players near rail but not attached

class GrinderData:
	var closest_offset: float = 0.0
	var rope_visual: MeshInstance3D = null
	var attach_time: float = 0.0

	# Stuck detection safeguard
	var last_progress_check_time: float = 0.0
	var last_progress_offset: float = 0.0
	var stuck_time: float = 0.0
	var boost_attempts: int = 0
	var last_boost_time: float = 0.0

	func _init(start_offset: float):
		closest_offset = start_offset
		attach_time = Time.get_ticks_msec() / 1000.0
		last_progress_check_time = attach_time
		last_progress_offset = start_offset
		last_boost_time = attach_time


func _ready() -> void:
	if not curve:
		curve = Curve3D.new()
		push_warning("GrindRail: No curve → created empty one")
		return

	await get_tree().process_frame
	_create_detection_areas()


func _create_detection_areas() -> void:
	var length: float = curve.get_baked_length()
	if length <= 0:
		return

	var seg_len: float = 3.0
	var count: int = max(int(length / seg_len) + 1, 4)

	for i: int in count:
		var t: float = float(i) / float(count - 1)
		var offset: float = t * length
		var pos: Vector3 = curve.sample_baked(offset)

		var area := Area3D.new()
		area.name = "RailSeg" + str(i)
		area.collision_layer = 0
		area.collision_mask = 2
		area.position = pos
		add_child(area)

		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = detection_radius
		shape.shape = sphere
		area.add_child(shape)

		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not body is RigidBody3D: return
	if not body.has_method("start_grinding"): return

	var pos: Vector3 = body.global_position
	var local: Vector3 = to_local(pos)
	var offset: float = curve.get_closest_offset(local)
	var closest_world: Vector3 = to_global(curve.sample_baked(offset))

	if pos.distance_to(closest_world) > detection_radius:
		return

	var delta: Vector3 = pos - closest_world

	# ALLOW LARGE AREA BELOW the rail (up to -12 units)
	if delta.y < -12.0: return   # only reject if extremely far below

	# Reasonable horizontal range
	if Vector2(delta.x, delta.z).length() > 6.0: return

	# If manual attachment is enabled, just track nearby players instead of auto-attaching
	if manual_attachment_only:
		if not nearby_players.has(body):
			nearby_players.append(body)
			# Player nearby - ready for manual attachment (removed print to reduce spam)
	else:
		_attach(body, offset, closest_world)


func _on_body_exited(body: Node3D) -> void:
	"""Called when a body exits the detection area"""
	if body in nearby_players:
		nearby_players.erase(body)
		# Player left detection area (removed print to reduce spam)


func can_attach(grinder: RigidBody3D) -> bool:
	"""Check if a grinder can attach to this rail"""
	if active_grinders.has(grinder):
		return false  # Already attached

	if not nearby_players.has(grinder):
		return false  # Not in range

	return true


func try_attach_player(grinder: RigidBody3D) -> bool:
	"""Attempt to attach a player to the rail (called when player presses E)"""
	# Allow attachment if visually targeting, regardless of physical proximity
	# The player.gd visual targeting system has already validated the distance
	if active_grinders.has(grinder):
		return false  # Already attached

	var pos: Vector3 = grinder.global_position
	var local: Vector3 = to_local(pos)
	var offset: float = curve.get_closest_offset(local)
	var closest_world: Vector3 = to_global(curve.sample_baked(offset))

	# Validate distance one more time (max 30 units as per player.gd)
	var distance: float = pos.distance_to(closest_world)
	if distance > 30.0:
		print("[", name, "] Attachment failed - too far: ", distance)
		return false

	_attach(grinder, offset, closest_world)
	nearby_players.erase(grinder)  # Remove from nearby list if present
	print("[", name, "] Manual attachment successful! Distance: ", distance)
	return true


func _attach(grinder: RigidBody3D, offset: float, closest_world: Vector3) -> void:
	if active_grinders.has(grinder):
		return

	var data := GrinderData.new(offset)
	grinder_data[grinder] = data
	active_grinders.append(grinder)

	data.rope_visual = MeshInstance3D.new()
	data.rope_visual.name = "Rope"
	add_child(data.rope_visual)
	data.rope_visual.visible = false

	var dir_to_rail: Vector3 = (closest_world - grinder.global_position).normalized()
	grinder.apply_central_impulse(dir_to_rail * 45.0)

	if grinder.has_method("start_grinding"):
		grinder.start_grinding(self)

	print("[", name, "] Attached — unbreakable rope at ", snapped(offset, 0.1))


func _remove_grinder(grinder: RigidBody3D) -> void:
	if not active_grinders.has(grinder): return

	var data = grinder_data.get(grinder)
	if data and data.rope_visual:
		data.rope_visual.queue_free()

	active_grinders.erase(grinder)
	grinder_data.erase(grinder)

	if is_instance_valid(grinder) and grinder.has_method("stop_grinding"):
		grinder.stop_grinding()


func detach_grinder(grinder: RigidBody3D) -> Vector3:
	var exit_vel: Vector3 = grinder.linear_velocity if is_instance_valid(grinder) else Vector3.ZERO
	_remove_grinder(grinder)
	return exit_vel


func _process(_delta: float) -> void:
	for grinder in active_grinders.duplicate():
		if not is_instance_valid(grinder) or not grinder_data.has(grinder):
			_remove_grinder(grinder)


func _physics_process(delta: float) -> void:
	for grinder: RigidBody3D in active_grinders.duplicate():
		if not is_instance_valid(grinder) or not grinder_data.has(grinder):
			_remove_grinder(grinder)
			continue

		if grinder.get("current_rail") != self:
			var data = grinder_data[grinder]
			if data and data.rope_visual:
				data.rope_visual.visible = false
			continue

		_update_active_grinder(grinder, delta)


func _update_active_grinder(grinder: RigidBody3D, delta: float) -> void:
	var data: GrinderData = grinder_data[grinder]
	var length: float = curve.get_baked_length()
	if length <= 0:
		_remove_grinder(grinder)
		return

	var current_time: float = Time.get_ticks_msec() / 1000.0
	var time_since_attach: float = current_time - data.attach_time

	var player_local: Vector3 = to_local(grinder.global_position)
	var closest_offset: float = curve.get_closest_offset(player_local)

	var xform: Transform3D = curve.sample_baked_with_rotation(closest_offset)
	var tangent_local: Vector3 = xform.basis.z.normalized()
	var tangent: Vector3 = global_transform.basis * tangent_local

	var vel_along: float = grinder.linear_velocity.dot(tangent)

	var slide: float = vel_along * delta * 1.4
	var attach_offset: float = clamp(closest_offset + slide, 1.0, length - 1.0)

	var attach_pos: Vector3 = to_global(curve.sample_baked(attach_offset))

	if data.rope_visual:
		data.rope_visual.visible = true
		var mesh := ImmediateMesh.new()
		data.rope_visual.mesh = mesh

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.9, 0.3, 0.9)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

		mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		mesh.surface_add_vertex(to_local(attach_pos))
		mesh.surface_add_vertex(to_local(grinder.global_position))
		mesh.surface_end()

	# Unbreakable rope
	var rope_vec: Vector3 = grinder.global_position - attach_pos
	var rope_len: float = rope_vec.length()

	var stretch: float = max(0.0, rope_len - rope_length)

	if stretch > 0.0:
		var dir: Vector3 = rope_vec.normalized()

		var effective_stiffness: float = rope_stiffness
		if time_since_attach < initial_snap_duration:
			effective_stiffness *= initial_snap_stiffness_multiplier

		var spring: Vector3 = -dir * effective_stiffness * stretch
		var v_along_rope: float = grinder.linear_velocity.dot(dir)
		var damping: Vector3 = -dir * rope_damping * v_along_rope

		var force: Vector3 = spring + damping

		if rope_len > max_allowed_stretch:
			var emergency_force: Vector3 = -dir * (rope_len - rope_length) * rope_stiffness * emergency_force_multiplier
			force += emergency_force
			grinder.linear_velocity += (attach_pos - grinder.global_position).normalized() * 2.5

		force = force.limit_length(max_rope_force)
		grinder.apply_central_force(force)

	# Aggressive forward acceleration
	grinder.apply_central_force(tangent * constant_forward_push * grinder.mass * delta)

	# Strong slope acceleration
	var look_ahead_off: float = clamp(attach_offset + sign(vel_along) * 3.0, 0, length)
	var ahead_pos: Vector3 = to_global(curve.sample_baked(look_ahead_off))
	var dy: float = ahead_pos.y - attach_pos.y
	var slope_f: Vector3 = tangent * (-dy * gravity_multiplier * 120.0)
	grinder.apply_central_force(slope_f)

	# STUCK DETECTION SAFEGUARD
	# Check if player is making sufficient progress along the rail
	if current_time - data.last_progress_check_time >= stuck_detection_interval:
		var progress: float = abs(attach_offset - data.last_progress_offset)

		if progress < stuck_min_progress:
			# Not making enough progress - increment stuck time
			data.stuck_time += stuck_detection_interval

			if data.stuck_time >= stuck_threshold_time:
				# Player is stuck! Try to help them
				if data.boost_attempts < max_boost_attempts and current_time - data.last_boost_time >= boost_cooldown:
					# Apply emergency boost in the direction of nearest end
					var to_start: float = attach_offset
					var to_end: float = length - attach_offset
					var boost_direction: Vector3 = tangent if to_end < to_start else -tangent

					grinder.apply_central_impulse(boost_direction * emergency_boost_force)
					data.boost_attempts += 1
					data.last_boost_time = current_time

					print("[", name, "] STUCK SAFEGUARD: Applied boost #", data.boost_attempts, " toward ",
						("end" if to_end < to_start else "start"))

				elif data.boost_attempts >= max_boost_attempts:
					# Tried multiple boosts, still stuck - detach player safely
					print("[", name, "] STUCK SAFEGUARD: Max boost attempts reached, detaching player safely")

					# Give player a gentle upward and forward impulse
					grinder.apply_central_impulse(Vector3.UP * 80.0)
					grinder.apply_central_impulse(tangent * 100.0)

					_remove_grinder(grinder)
					return
		else:
			# Making good progress - reset stuck tracking
			data.stuck_time = 0.0
			data.boost_attempts = 0

		# Update progress tracking
		data.last_progress_check_time = current_time
		data.last_progress_offset = attach_offset

	# Only detach at end of rail
	if attach_offset <= 1.5 or attach_offset >= length - 1.5:
		print("[", name, "] End of rail — HIGH LAUNCH!")
		if grinder.has_method("launch_from_rail"):
			grinder.launch_from_rail(grinder.linear_velocity)

		grinder.apply_central_impulse(Vector3.UP * end_launch_upward_impulse)
		grinder.apply_central_impulse(tangent * grinder.linear_velocity.length() * end_launch_forward_boost)

		_remove_grinder(grinder)
		return

	grinder.angular_velocity *= 0.15
	data.closest_offset = closest_offset
