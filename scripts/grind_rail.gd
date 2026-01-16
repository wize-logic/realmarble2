extends Path3D
class_name GrindRail

## Rail grinding system similar to Sonic series
## Allows players to grind along rails with speed boosts and momentum

@export var grind_speed: float = 20.0  ## Base speed while grinding
@export var speed_boost: float = 1.5  ## Speed multiplier when entering grind
@export var min_speed: float = 10.0  ## Minimum speed to maintain grind
@export var gravity_assist: float = 0.3  ## How much downward slope increases speed
@export var uphill_resistance: float = 0.15  ## How much upward slope decreases speed
@export var detection_radius: float = 3.0  ## How close player needs to be to snap to rail
@export var rail_height_offset: float = 0.6  ## Height above rail path for player

var active_grinders: Array[RigidBody3D] = []  ## Players currently grinding this rail
var grinder_data: Dictionary = {}  ## Stores grinding data per player

## Data structure for each grinder
class GrinderData:
	var progress: float = 0.0  ## Position along curve (0.0 to 1.0)
	var speed: float = 0.0  ## Current grinding speed
	var direction: int = 1  ## 1 for forward, -1 for backward
	var entry_velocity: Vector3 = Vector3.ZERO

	func _init(start_progress: float, initial_speed: float, vel: Vector3):
		progress = start_progress
		speed = initial_speed
		direction = 1 if initial_speed >= 0 else -1
		entry_velocity = vel


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

	# Start grinding
	_attach_grinder(body, closest_offset, velocity)


func _on_body_exited(body: Node3D):
	# Don't auto-remove on exit, let player jump off manually
	pass


func _attach_grinder(grinder: RigidBody3D, offset: float, velocity: Vector3):
	if active_grinders.has(grinder):
		return  ## Already grinding

	# Calculate progress (0.0 to 1.0)
	var curve_length = curve.get_baked_length()
	if curve_length == 0:
		return

	var progress = offset / curve_length

	# Calculate direction based on velocity
	var tangent = curve.sample_baked_with_rotation(offset).basis.z
	var world_tangent = global_transform.basis * tangent

	var speed = velocity.length()
	var direction = 1  # Default to forward
	var initial_speed = grind_speed  # Default to base grind speed

	# If player has velocity, use it to determine direction and boost speed
	if speed > 0.1:
		var dot = velocity.normalized().dot(world_tangent.normalized())
		direction = 1 if dot >= 0 else -1
		initial_speed = speed * speed_boost
	else:
		# Player attached at rest, start grinding at base speed forward
		initial_speed = grind_speed

	# Create grinder data
	var data = GrinderData.new(progress, initial_speed * direction, velocity)
	grinder_data[grinder] = data
	active_grinders.append(grinder)

	# Notify player they're grinding
	if grinder.has_method("start_grinding"):
		grinder.start_grinding(self)

	print("Rail: Player attached at progress ", progress, " with speed ", initial_speed)


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

	# Calculate current offset
	var current_offset = data.progress * curve_length

	# Get current and next position to determine slope
	var current_pos = curve.sample_baked(current_offset)
	var next_offset = current_offset + (data.speed * delta * 0.01)  ## Small lookahead
	next_offset = clamp(next_offset, 0, curve_length)
	var next_pos = curve.sample_baked(next_offset)

	# Calculate slope effect
	var height_diff = (to_global(next_pos).y - to_global(current_pos).y)
	var slope_effect = 0.0
	if data.speed > 0:
		if height_diff < 0:  ## Going downhill
			slope_effect = -height_diff * gravity_assist
		else:  ## Going uphill
			slope_effect = -height_diff * uphill_resistance

	# Update speed
	data.speed += slope_effect * delta * 10.0
	data.speed = max(data.speed, min_speed)  ## Don't go too slow

	# Update progress
	var speed_delta = (data.speed * delta) / curve_length
	data.progress += speed_delta

	# Check if reached end
	if data.progress >= 1.0 or data.progress <= 0.0:
		# Launch player off the end
		var launch_dir = curve.sample_baked_with_rotation(current_offset).basis.z
		var world_launch = global_transform.basis * launch_dir
		if grinder.has_method("launch_from_rail"):
			grinder.launch_from_rail(world_launch * data.speed)
		_remove_grinder(grinder)
		return

	# Update player position
	current_offset = data.progress * curve_length
	var rail_pos = curve.sample_baked_with_rotation(current_offset)
	var rail_tangent = rail_pos.basis.z
	var rail_up = rail_pos.basis.y

	# Calculate world position (slightly above rail)
	var world_pos = to_global(rail_pos.origin) + global_transform.basis * rail_up * rail_height_offset
	var world_tangent = global_transform.basis * rail_tangent

	# Update grinder transform
	grinder.global_position = world_pos

	# Maintain velocity along rail
	var velocity_magnitude = data.speed
	grinder.linear_velocity = world_tangent.normalized() * velocity_magnitude

	# Reduce angular velocity while grinding
	grinder.angular_velocity *= 0.5


## Called by player to detach from rail (jumping off)
func detach_grinder(grinder: RigidBody3D):
	if not active_grinders.has(grinder):
		return

	var data: GrinderData = grinder_data[grinder]

	# Give player a boost in current direction
	var current_offset = data.progress * curve.get_baked_length()
	var rail_dir = curve.sample_baked_with_rotation(current_offset).basis.z
	var world_dir = global_transform.basis * rail_dir

	_remove_grinder(grinder)

	# Return velocity for player to use
	return world_dir * data.speed


## Check if a specific grinder is on this rail
func is_grinding(grinder: RigidBody3D) -> bool:
	return active_grinders.has(grinder)


## Get current grinding speed for a grinder
func get_grind_speed(grinder: RigidBody3D) -> float:
	if not grinder_data.has(grinder):
		return 0.0
	var data: GrinderData = grinder_data[grinder]
	return data.speed
