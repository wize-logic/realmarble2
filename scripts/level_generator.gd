extends Node3D

## Procedural Level Generator
## Creates Marble Blast Gold / Quake 3 style arenas

@export var level_seed: int = 0
@export var arena_size: float = 120.0
@export var complexity: int = 2  # 1=Simple, 2=Medium, 3=Complex, 4=Extreme
@export var min_spacing: float = 5.0  # Minimum gap - just enough so they don't touch

# Calculated counts based on complexity and arena_size
var platform_count: int = 30
var ramp_count: int = 20
var grind_rail_count: int = 8
var vertical_rail_count: int = 4
var obstacle_count: int = 0  # Extra obstacles at higher complexity
var platform_height_max: float = 10.0
var platform_size_variation: float = 1.0  # Multiplier for size randomness

var noise: FastNoiseLite
var platforms: Array = []
var geometry_positions: Array[Dictionary] = []  # Stores {position: Vector3, size: Vector3, rotation: Vector3}
var material_manager = preload("res://scripts/procedural_material_manager.gd").new()

func _ready() -> void:
	generate_level()

func configure_from_complexity() -> void:
	"""Configure all generation parameters based on complexity and arena_size"""
	# Size factor for scaling objects proportionally with arena
	var size_factor: float = arena_size / 120.0

	# Complexity ONLY controls object counts (density)
	# Size (arena_size) controls how big everything is
	match complexity:
		1:  # Simple - sparse
			platform_count = 15
			ramp_count = 10
			grind_rail_count = 4
			vertical_rail_count = 2
			obstacle_count = 0
		2:  # Medium (default)
			platform_count = 30
			ramp_count = 20
			grind_rail_count = 8
			vertical_rail_count = 4
			obstacle_count = 6
		3:  # Complex - dense
			platform_count = 50
			ramp_count = 35
			grind_rail_count = 12
			vertical_rail_count = 6
			obstacle_count = 12
		4:  # Extreme - very dense
			platform_count = 75
			ramp_count = 50
			grind_rail_count = 16
			vertical_rail_count = 8
			obstacle_count = 20
		_:  # Default to medium
			complexity = 2
			configure_from_complexity()
			return

	# Heights scale with arena size so bigger arenas have taller structures
	platform_height_max = 12.0 * size_factor
	platform_size_variation = 1.0

	# Minimum spacing scales with arena size - CRITICAL for preventing overlap
	min_spacing = 8.0 * size_factor
	min_spacing = max(min_spacing, 5.0)  # Never less than 5 units

	if OS.is_debug_build():
		print("Level config - Complexity: %d, Arena: %.0f (size_factor: %.2f), Platforms: %d, Ramps: %d, MinSpacing: %.1f" % [
			complexity, arena_size, size_factor, platform_count, ramp_count, min_spacing
		])

func generate_level() -> void:
	"""Generate a complete procedural level"""
	if OS.is_debug_build():
		print("Generating procedural level with seed: ", level_seed)

	# Configure based on complexity and size
	configure_from_complexity()

	# Initialize noise for variation
	noise = FastNoiseLite.new()
	noise.seed = level_seed if level_seed != 0 else randi()
	noise.frequency = 0.05

	# Clear any existing geometry
	clear_level()

	# Generate level components
	generate_main_floor()
	generate_platforms()
	generate_ramps()
	generate_obstacles()  # Extra obstacles based on complexity
	generate_grind_rails()
	generate_death_zone()

	# Apply beautiful procedural materials
	apply_procedural_textures()

	print("Level generation complete!")

func clear_level() -> void:
	"""Remove all existing level geometry"""
	for child in get_children():
		child.queue_free()
	platforms.clear()
	geometry_positions.clear()

func check_spacing(new_pos: Vector3, new_size: Vector3, new_rotation: Vector3 = Vector3.ZERO) -> bool:
	"""Check if a new piece of geometry would have proper spacing from existing geometry

	Returns true if the position is valid (has enough spacing), false if it would overlap/touch
	"""
	# Calculate oriented bounding box for new geometry
	var new_half_size: Vector3 = new_size * 0.5

	for existing in geometry_positions:
		var existing_pos: Vector3 = existing.position
		var existing_size: Vector3 = existing.size
		var existing_half_size: Vector3 = existing_size * 0.5

		# Simple distance check first (fast rejection)
		var distance: float = new_pos.distance_to(existing_pos)
		var combined_radius: float = (new_half_size.length() + existing_half_size.length()) + min_spacing

		if distance < combined_radius:
			# More precise AABB check (axis-aligned bounding box)
			# Expand both boxes by min_spacing/2 to ensure separation
			var spacing_margin: float = min_spacing * 0.5

			var new_min: Vector3 = new_pos - new_half_size - Vector3.ONE * spacing_margin
			var new_max: Vector3 = new_pos + new_half_size + Vector3.ONE * spacing_margin

			var existing_min: Vector3 = existing_pos - existing_half_size - Vector3.ONE * spacing_margin
			var existing_max: Vector3 = existing_pos + existing_half_size + Vector3.ONE * spacing_margin

			# AABB overlap test
			if (new_min.x <= existing_max.x and new_max.x >= existing_min.x and
				new_min.y <= existing_max.y and new_max.y >= existing_min.y and
				new_min.z <= existing_max.z and new_max.z >= existing_min.z):
				return false  # Would overlap/touch

	return true  # Valid position with proper spacing

func register_geometry(pos: Vector3, size: Vector3, rotation: Vector3 = Vector3.ZERO) -> void:
	"""Register a piece of geometry in the spacing tracker"""
	geometry_positions.append({
		"position": pos,
		"size": size,
		"rotation": rotation
	})

func create_smooth_box_mesh(size: Vector3) -> BoxMesh:
	"""Create a box mesh with smooth appearance"""
	var mesh = BoxMesh.new()
	mesh.size = size
	# Increase subdivisions for smoother appearance
	mesh.subdivide_width = 2
	mesh.subdivide_height = 2
	mesh.subdivide_depth = 2
	return mesh

func generate_main_floor() -> void:
	"""Generate the main arena floor"""
	var floor_size: float = arena_size * 0.7

	# Create main platform with smooth geometry
	var floor_mesh: BoxMesh = create_smooth_box_mesh(Vector3(floor_size, 2.0, floor_size))

	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.name = "MainFloor"
	floor_instance.position = Vector3(0, -1, 0)
	add_child(floor_instance)

	# Add collision
	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = floor_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	floor_instance.add_child(static_body)

	# Store for texture application
	platforms.append(floor_instance)

	# DON'T register floor - it's the base and objects should be allowed on/above it
	# register_geometry(floor_instance.position, floor_mesh.size)

	if OS.is_debug_build():
		print("Generated main floor: ", floor_size, "x", floor_size)

func generate_platforms() -> void:
	"""Generate elevated platforms around the arena with proper spacing"""
	var size_factor: float = arena_size / 120.0
	var floor_radius: float = (arena_size * 0.7) / 2.0
	var generated_count: int = 0
	var max_attempts: int = platform_count * 20

	# Platform sizes scale directly with arena - bigger arena = bigger platforms
	var min_platform_size: float = 6.0 * size_factor
	var max_platform_size: float = 14.0 * size_factor
	var min_height: float = 3.0 * size_factor
	var max_height: float = platform_height_max

	for attempt in range(max_attempts):
		if generated_count >= platform_count:
			break

		# Generate random position - spread across the floor
		var angle: float = randf() * TAU
		var distance: float = randf_range(min_spacing, floor_radius - min_spacing)

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance
		var y: float = randf_range(min_height, max_height)

		# Platform size scales with arena
		var width: float = randf_range(min_platform_size, max_platform_size)
		var depth: float = randf_range(min_platform_size, max_platform_size)
		var height: float = randf_range(1.5, 3.0) * size_factor

		var platform_size: Vector3 = Vector3(width, height, depth)
		var platform_pos: Vector3 = Vector3(x, y, z)

		# Create platform - geometry can overlap/connect to form interesting structures
		var platform_mesh: BoxMesh = create_smooth_box_mesh(platform_size)

		var platform_instance: MeshInstance3D = MeshInstance3D.new()
		platform_instance.mesh = platform_mesh
		platform_instance.name = "Platform" + str(generated_count)
		platform_instance.position = platform_pos
		add_child(platform_instance)

		# Add collision
		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = platform_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		platform_instance.add_child(static_body)

		platforms.append(platform_instance)
		generated_count += 1

	if OS.is_debug_build():
		print("Generated ", generated_count, " / ", platform_count, " platforms (", max_attempts, " attempts)")

func generate_ramps() -> void:
	"""Generate ramps/slopes on the stage with proper spacing"""
	var size_factor: float = arena_size / 120.0
	var floor_radius: float = (arena_size * 0.7) / 2.0
	var generated_count: int = 0
	var max_attempts: int = ramp_count * 20

	# Ramp sizes scale with arena
	var ramp_width_min: float = 6.0 * size_factor
	var ramp_width_max: float = 12.0 * size_factor
	var ramp_length_min: float = 10.0 * size_factor
	var ramp_length_max: float = 20.0 * size_factor
	var ramp_height_max: float = 8.0 * size_factor

	for attempt in range(max_attempts):
		if generated_count >= ramp_count:
			break

		# Generate position on the stage
		var angle: float = randf() * TAU
		var distance: float = randf_range(min_spacing, floor_radius - min_spacing)

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance
		var y: float = randf_range(1.0 * size_factor, ramp_height_max)

		# Ramp size scales with arena
		var ramp_width: float = randf_range(ramp_width_min, ramp_width_max)
		var ramp_length: float = randf_range(ramp_length_min, ramp_length_max)
		var ramp_tilt: float = -randf_range(15, 35)

		var ramp_size: Vector3 = Vector3(ramp_width, 1.0 * size_factor, ramp_length)
		var ramp_pos: Vector3 = Vector3(x, y, z)
		var ramp_rotation: Vector3 = Vector3(ramp_tilt, randf() * 360.0, 0)

		# Create ramp - geometry can overlap/connect
		var ramp_mesh: BoxMesh = create_smooth_box_mesh(ramp_size)

		var ramp_instance: MeshInstance3D = MeshInstance3D.new()
		ramp_instance.mesh = ramp_mesh
		ramp_instance.name = "Ramp" + str(generated_count)
		ramp_instance.position = ramp_pos
		ramp_instance.rotation_degrees = ramp_rotation
		add_child(ramp_instance)

		# Add collision
		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = ramp_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		ramp_instance.add_child(static_body)

		platforms.append(ramp_instance)
		generated_count += 1

	if OS.is_debug_build():
		print("Generated ", generated_count, " / ", ramp_count, " ramps (", max_attempts, " attempts)")

func generate_obstacles() -> void:
	"""Generate extra obstacles based on complexity (pillars, blocks, barriers)"""
	if obstacle_count <= 0:
		return

	var size_factor: float = arena_size / 120.0
	var floor_radius: float = (arena_size * 0.7) / 2.0
	var generated_count: int = 0
	var max_attempts: int = obstacle_count * 20

	for attempt in range(max_attempts):
		if generated_count >= obstacle_count:
			break

		var angle: float = randf() * TAU
		var distance: float = randf_range(min_spacing, floor_radius - min_spacing)

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance

		# Obstacle sizes scale with arena
		var obstacle_type: int = randi() % 4
		var obstacle_size: Vector3
		var obstacle_pos: Vector3

		match obstacle_type:
			0:  # Low block/cover
				obstacle_size = Vector3(
					randf_range(3.0, 6.0) * size_factor,
					randf_range(2.0, 4.0) * size_factor,
					randf_range(3.0, 6.0) * size_factor
				)
				obstacle_pos = Vector3(x, obstacle_size.y / 2.0, z)
			1:  # Tall pillar
				var pillar_width: float = randf_range(2.0, 4.0) * size_factor
				obstacle_size = Vector3(pillar_width, randf_range(8.0, 15.0) * size_factor, pillar_width)
				obstacle_pos = Vector3(x, obstacle_size.y / 2.0, z)
			2:  # Wide barrier
				obstacle_size = Vector3(
					randf_range(8.0, 14.0) * size_factor,
					randf_range(3.0, 5.0) * size_factor,
					randf_range(2.0, 3.0) * size_factor
				)
				obstacle_pos = Vector3(x, obstacle_size.y / 2.0, z)
			_:  # Large platform block
				obstacle_size = Vector3(
					randf_range(5.0, 8.0) * size_factor,
					randf_range(3.0, 6.0) * size_factor,
					randf_range(5.0, 8.0) * size_factor
				)
				obstacle_pos = Vector3(x, obstacle_size.y / 2.0, z)

		# Create obstacle - geometry can overlap/connect
		var obstacle_mesh: BoxMesh = create_smooth_box_mesh(obstacle_size)

		var obstacle_instance: MeshInstance3D = MeshInstance3D.new()
		obstacle_instance.mesh = obstacle_mesh
		obstacle_instance.name = "Obstacle" + str(generated_count)
		obstacle_instance.position = obstacle_pos

		# Random rotation for some variety
		if obstacle_type >= 2:
			obstacle_instance.rotation_degrees.y = randf() * 360.0

		add_child(obstacle_instance)

		# Add collision
		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = obstacle_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		obstacle_instance.add_child(static_body)

		platforms.append(obstacle_instance)
		generated_count += 1

	if OS.is_debug_build():
		print("Generated ", generated_count, " / ", obstacle_count, " obstacles")

func generate_grind_rails() -> void:
	"""Generate grinding rails around the arena perimeter (Sonic style)"""
	# Rail count scales with complexity
	var rail_distance: float = arena_size * 0.60

	# Rail height varies more at higher complexity
	var rail_height_base: float = 3.0
	var rail_height_increment: float = 2.0 + complexity * 0.5

	for i in range(grind_rail_count):
		var angle_start: float = (float(i) / grind_rail_count) * TAU
		var angle_end: float = angle_start + (TAU / grind_rail_count) * 0.7  # Rails cover 70% of arc segment

		# Create a curved rail using Path3D and Curve3D
		var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
		rail.name = "GrindRail" + str(i)
		rail.curve = Curve3D.new()

		# Determine rail height (varied for interest, accessible heights)
		var height_tier: int = i % (2 + complexity)  # More height tiers at higher complexity
		var base_height: float = rail_height_base + height_tier * rail_height_increment

		# Create curve points along the arc
		var num_points: int = 12  # Number of control points
		for j in range(num_points):
			var t: float = float(j) / (num_points - 1)
			var angle: float = lerp(angle_start, angle_end, t)

			# Position along arc
			var x: float = cos(angle) * rail_distance
			var z: float = sin(angle) * rail_distance

			# Height variation (slight wave for interest)
			var height_offset: float = sin(t * PI) * 1.0  # Slight arc up and down
			var y: float = base_height + height_offset

			# Add point to curve
			rail.curve.add_point(Vector3(x, y, z))

		# Calculate proper tangent handles based on curve direction
		for j in range(rail.curve.point_count):
			var tangent: Vector3

			if j == 0:
				# First point - use direction to next point
				tangent = (rail.curve.get_point_position(j + 1) - rail.curve.get_point_position(j)).normalized()
			elif j == rail.curve.point_count - 1:
				# Last point - use direction from previous point
				tangent = (rail.curve.get_point_position(j) - rail.curve.get_point_position(j - 1)).normalized()
			else:
				# Middle points - use average direction from previous to next
				var prev_to_curr: Vector3 = rail.curve.get_point_position(j) - rail.curve.get_point_position(j - 1)
				var curr_to_next: Vector3 = rail.curve.get_point_position(j + 1) - rail.curve.get_point_position(j)
				tangent = (prev_to_curr + curr_to_next).normalized()

			# Set in/out handles based on actual curve direction (scaled for smoothness)
			var handle_length: float = 0.5  # Adjust for curve smoothness
			rail.curve.set_point_in(j, -tangent * handle_length)
			rail.curve.set_point_out(j, tangent * handle_length)

		add_child(rail)

		# Create visual rail mesh (cylinder along the path)
		create_rail_visual(rail)

	# Add some vertical connecting rails (like loops)
	generate_vertical_rails()

	print("Generated ", grind_rail_count, " grind rails around perimeter")

func generate_vertical_rails() -> void:
	"""Generate vertical/diagonal rails connecting different heights"""
	# Vertical rail count scales with complexity
	var end_height: float = 10.0 + complexity * 3.0  # Higher at more complexity

	for i in range(vertical_rail_count):
		var angle: float = (float(i) / vertical_rail_count) * TAU + (TAU / vertical_rail_count * 0.5)
		var distance: float = arena_size * 0.54  # Farther from stage - same as horizontal rails

		# Create vertical rail
		var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
		rail.name = "VerticalRail" + str(i)
		rail.curve = Curve3D.new()

		# Start position (low and accessible)
		var start_x: float = cos(angle) * distance
		var start_z: float = sin(angle) * distance
		var start_y: float = 2.0  # Low starting height

		# End position (height scales with complexity)
		var end_y: float = end_height

		# Create upward spiral
		var num_points: int = 8
		for j in range(num_points):
			var t: float = float(j) / (num_points - 1)
			var current_angle: float = angle + t * PI * 0.5  # Quarter turn
			var current_distance: float = lerp(distance, distance * 0.85, t)  # Curve inward slightly

			var x: float = cos(current_angle) * current_distance
			var z: float = sin(current_angle) * current_distance
			var y: float = lerp(start_y, end_y, t)

			rail.curve.add_point(Vector3(x, y, z))

		# Calculate proper tangent handles based on curve direction
		for j in range(rail.curve.point_count):
			var tangent: Vector3

			if j == 0:
				# First point - use direction to next point
				tangent = (rail.curve.get_point_position(j + 1) - rail.curve.get_point_position(j)).normalized()
			elif j == rail.curve.point_count - 1:
				# Last point - use direction from previous point
				tangent = (rail.curve.get_point_position(j) - rail.curve.get_point_position(j - 1)).normalized()
			else:
				# Middle points - use average direction from previous to next
				var prev_to_curr: Vector3 = rail.curve.get_point_position(j) - rail.curve.get_point_position(j - 1)
				var curr_to_next: Vector3 = rail.curve.get_point_position(j + 1) - rail.curve.get_point_position(j)
				tangent = (prev_to_curr + curr_to_next).normalized()

			# Set in/out handles based on actual curve direction (scaled for smoothness)
			var handle_length: float = 0.5  # Adjust for curve smoothness
			rail.curve.set_point_in(j, -tangent * handle_length)
			rail.curve.set_point_out(j, tangent * handle_length)

		add_child(rail)
		create_rail_visual(rail)

	if OS.is_debug_build():
		print("Generated ", vertical_rail_count, " vertical rails (max height: ", end_height, ")")

func create_rail_visual(rail: Path3D) -> void:
	"""Create visual representation of a rail using a 3D cylindrical tube"""
	if not rail.curve or rail.curve.get_baked_length() == 0:
		return

	# Create mesh for the rail
	var rail_visual: MeshInstance3D = MeshInstance3D.new()
	rail_visual.name = "RailVisual"

	# Use ImmediateMesh to draw the rail
	var immediate_mesh: ImmediateMesh = ImmediateMesh.new()
	rail_visual.mesh = immediate_mesh

	# Material for the rail
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.75, 0.85)  # Metallic silver with slight blue tint
	material.metallic = 0.85
	material.roughness = 0.3
	material.emission_enabled = false  # Disabled - emission was causing white washout

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)

	# Draw rail as a proper 3D cylindrical tube
	var rail_radius: float = 0.15
	var radial_segments: int = 8  # Number of sides around the cylinder
	var length_segments: int = int(rail.curve.get_baked_length() * 2)
	length_segments = max(length_segments, 10)

	# Generate vertices around the rail path
	for i in range(length_segments):
		var offset: float = (float(i) / length_segments) * rail.curve.get_baked_length()
		var next_offset: float = (float(i + 1) / length_segments) * rail.curve.get_baked_length()

		var pos: Vector3 = rail.curve.sample_baked(offset)
		var next_pos: Vector3 = rail.curve.sample_baked(next_offset)

		# Calculate forward direction
		var forward: Vector3 = (next_pos - pos).normalized()
		if forward.length() < 0.1:
			forward = Vector3.FORWARD

		# Calculate right and up vectors
		var right: Vector3 = forward.cross(Vector3.UP).normalized()
		if right.length() < 0.1:
			right = forward.cross(Vector3.RIGHT).normalized()
		var up: Vector3 = right.cross(forward).normalized()

		# Create ring of vertices at this position
		for j in range(radial_segments):
			var angle_curr: float = (float(j) / radial_segments) * TAU
			var angle_next: float = (float(j + 1) / radial_segments) * TAU

			# Current ring vertices
			var offset_curr: Vector3 = (right * cos(angle_curr) + up * sin(angle_curr)) * rail_radius
			var offset_next: Vector3 = (right * cos(angle_next) + up * sin(angle_next)) * rail_radius

			var v1: Vector3 = pos + offset_curr
			var v2: Vector3 = pos + offset_next
			var v3: Vector3 = next_pos + offset_curr
			var v4: Vector3 = next_pos + offset_next

			# First triangle
			immediate_mesh.surface_add_vertex(v1)
			immediate_mesh.surface_add_vertex(v2)
			immediate_mesh.surface_add_vertex(v3)

			# Second triangle
			immediate_mesh.surface_add_vertex(v2)
			immediate_mesh.surface_add_vertex(v4)
			immediate_mesh.surface_add_vertex(v3)

	immediate_mesh.surface_end()

	rail.add_child(rail_visual)

func generate_death_zone() -> void:
	"""Generate death zone below the arena"""
	var death_zone: Area3D = Area3D.new()
	death_zone.name = "DeathZone"
	death_zone.position = Vector3(0, -50, 0)
	death_zone.collision_layer = 0  # Death zone is on no layers
	death_zone.collision_mask = 2   # Detect players on layer 2
	death_zone.add_to_group("death_zone")
	add_child(death_zone)

	# Large collision box below everything
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(arena_size * 2, 10, arena_size * 2)
	collision.shape = shape
	death_zone.add_child(collision)

	# Connect signal
	death_zone.body_entered.connect(_on_death_zone_entered)

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Generated death zone")

func _on_death_zone_entered(body: Node3D) -> void:
	"""Handle player falling into death zone"""
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Death zone entered by: %s (type: %s)" % [body.name, body.get_class()])
	if body.has_method("fall_death"):
		DebugLogger.dlog(DebugLogger.Category.WORLD, "Calling fall_death() on %s" % body.name)
		body.fall_death()
	elif body.has_method("respawn"):
		DebugLogger.dlog(DebugLogger.Category.WORLD, "Calling respawn() directly on %s" % body.name)
		body.respawn()
	else:
		DebugLogger.dlog(DebugLogger.Category.WORLD, "WARNING: %s has neither fall_death() nor respawn() method!" % body.name)

func apply_procedural_textures() -> void:
	"""Apply procedurally generated textures to all platforms"""
	material_manager.apply_materials_to_level(self)

func get_spawn_points() -> PackedVector3Array:
	"""Generate spawn points on platforms - supports up to 8 players total (16 spawn points available)"""
	var spawns: PackedVector3Array = PackedVector3Array()

	# Main floor spawns - 16 spawn points in a circular pattern
	spawns.append(Vector3(0, 2, 0))  # Center
	# Ring 1 - 4 spawns
	spawns.append(Vector3(10, 2, 0))
	spawns.append(Vector3(-10, 2, 0))
	spawns.append(Vector3(0, 2, 10))
	spawns.append(Vector3(0, 2, -10))
	# Ring 2 - 4 spawns (diagonals)
	spawns.append(Vector3(10, 2, 10))
	spawns.append(Vector3(-10, 2, 10))
	spawns.append(Vector3(10, 2, -10))
	spawns.append(Vector3(-10, 2, -10))
	# Ring 3 - 4 spawns (further out)
	spawns.append(Vector3(20, 2, 0))
	spawns.append(Vector3(-20, 2, 0))
	spawns.append(Vector3(0, 2, 20))
	spawns.append(Vector3(0, 2, -20))
	# Ring 4 - 3 spawns (additional positions)
	spawns.append(Vector3(15, 2, 15))
	spawns.append(Vector3(-15, 2, -15))
	spawns.append(Vector3(15, 2, -15))

	# Platform spawns - additional variety
	for platform in platforms:
		if platform.name.begins_with("Platform"):
			var spawn_pos: Vector3 = platform.position
			spawn_pos.y += 3.0  # Above platform
			spawns.append(spawn_pos)

	return spawns

# ============================================================================
# MID-ROUND EXPANSION SYSTEM
# ============================================================================

func generate_secondary_map(offset: Vector3) -> void:
	"""Generate a secondary map at the specified offset position"""
	print("Generating secondary map at offset: ", offset)

	# Store current seed to generate varied but consistent secondary map
	var secondary_seed: int = noise.seed + 1000  # Different but deterministic
	var old_seed: int = noise.seed
	noise.seed = secondary_seed

	# Generate a complete secondary arena at the offset
	generate_secondary_floor(offset)
	generate_secondary_platforms(offset)
	generate_secondary_ramps(offset)
	generate_secondary_rails(offset)

	# Restore original seed
	noise.seed = old_seed

	print("Secondary map generation complete at offset: ", offset)

func generate_secondary_floor(offset: Vector3) -> void:
	"""Generate floor for secondary map"""
	var floor_size: float = arena_size * 0.7

	var floor_mesh: BoxMesh = create_smooth_box_mesh(Vector3(floor_size, 2.0, floor_size))

	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.name = "SecondaryFloor"
	floor_instance.position = offset + Vector3(0, -1, 0)
	add_child(floor_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = floor_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	floor_instance.add_child(static_body)

	platforms.append(floor_instance)

func generate_secondary_platforms(offset: Vector3) -> void:
	"""Generate platforms for secondary map"""
	var radius: float = arena_size * 0.4

	for i in range(platform_count):
		var angle: float = (float(i) / platform_count) * TAU
		var distance: float = radius * (0.6 + randf() * 0.4)

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance
		var y: float = 3.0 + randf() * 8.0

		var width: float = 6.0 + randf() * 6.0
		var depth: float = 6.0 + randf() * 6.0
		var height: float = 1.0 + randf() * 1.0

		var platform_mesh: BoxMesh = create_smooth_box_mesh(Vector3(width, height, depth))

		var platform_instance: MeshInstance3D = MeshInstance3D.new()
		platform_instance.mesh = platform_mesh
		platform_instance.name = "SecondaryPlatform" + str(i)
		platform_instance.position = offset + Vector3(x, y, z)
		add_child(platform_instance)

		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = platform_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		platform_instance.add_child(static_body)

		platforms.append(platform_instance)

func generate_secondary_ramps(offset: Vector3) -> void:
	"""Generate ramps for secondary map"""
	for i in range(ramp_count):
		var angle: float = (float(i) / ramp_count) * TAU + (TAU / ramp_count * 0.5)
		var distance: float = arena_size * 0.3

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance
		var y: float = 0.0

		var ramp_mesh: BoxMesh = create_smooth_box_mesh(Vector3(8.0, 0.5, 12.0))

		var ramp_instance: MeshInstance3D = MeshInstance3D.new()
		ramp_instance.mesh = ramp_mesh
		ramp_instance.name = "SecondaryRamp" + str(i)
		ramp_instance.position = offset + Vector3(x, y + 3, z)
		ramp_instance.rotation_degrees = Vector3(-25, rad_to_deg(angle), 0)
		add_child(ramp_instance)

		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = ramp_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		ramp_instance.add_child(static_body)

		platforms.append(ramp_instance)

func generate_secondary_rails(offset: Vector3) -> void:
	"""Generate rails for secondary map"""
	var rail_count: int = 8
	var rail_distance: float = arena_size * 0.54

	for i in range(rail_count):
		var angle_start: float = (float(i) / rail_count) * TAU
		var angle_end: float = angle_start + (TAU / rail_count) * 0.7

		var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
		rail.name = "SecondaryGrindRail" + str(i)
		rail.curve = Curve3D.new()

		var base_height: float = 3.0 + (i % 3) * 2.5

		var num_points: int = 12
		for j in range(num_points):
			var t: float = float(j) / (num_points - 1)
			var angle: float = lerp(angle_start, angle_end, t)

			var x: float = cos(angle) * rail_distance
			var z: float = sin(angle) * rail_distance
			var height_offset: float = sin(t * PI) * 1.0
			var y: float = base_height + height_offset

			rail.curve.add_point(offset + Vector3(x, y, z))

		for j in range(rail.curve.point_count):
			var tangent: Vector3

			if j == 0:
				tangent = (rail.curve.get_point_position(j + 1) - rail.curve.get_point_position(j)).normalized()
			elif j == rail.curve.point_count - 1:
				tangent = (rail.curve.get_point_position(j) - rail.curve.get_point_position(j - 1)).normalized()
			else:
				var prev_to_curr: Vector3 = rail.curve.get_point_position(j) - rail.curve.get_point_position(j - 1)
				var curr_to_next: Vector3 = rail.curve.get_point_position(j + 1) - rail.curve.get_point_position(j)
				tangent = (prev_to_curr + curr_to_next).normalized()

			var handle_length: float = 0.5
			rail.curve.set_point_in(j, -tangent * handle_length)
			rail.curve.set_point_out(j, tangent * handle_length)

		add_child(rail)
		create_rail_visual(rail)

func generate_connecting_rail(start_pos: Vector3, end_pos: Vector3) -> void:
	"""Generate a long connecting rail between two map areas"""
	print("Generating connecting rail from ", start_pos, " to ", end_pos)

	var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
	rail.name = "ConnectingRail"
	rail.curve = Curve3D.new()

	# Calculate distance and create enough points for a smooth path
	var distance: float = start_pos.distance_to(end_pos)
	var num_points: int = max(20, int(distance / 15.0))  # At least 20 points, more for longer rails

	# Create a gentle curve from start to end
	for i in range(num_points):
		var t: float = float(i) / (num_points - 1)

		# Interpolate between start and end positions
		var pos: Vector3 = start_pos.lerp(end_pos, t)

		# Add a slight upward arc for visual interest (parabolic arc)
		var arc_height: float = 15.0  # Maximum height of the arc
		var height_offset: float = sin(t * PI) * arc_height
		pos.y += height_offset

		rail.curve.add_point(pos)

	# Set smooth tangent handles
	for j in range(rail.curve.point_count):
		var tangent: Vector3

		if j == 0:
			tangent = (rail.curve.get_point_position(j + 1) - rail.curve.get_point_position(j)).normalized()
		elif j == rail.curve.point_count - 1:
			tangent = (rail.curve.get_point_position(j) - rail.curve.get_point_position(j - 1)).normalized()
		else:
			var prev_to_curr: Vector3 = rail.curve.get_point_position(j) - rail.curve.get_point_position(j - 1)
			var curr_to_next: Vector3 = rail.curve.get_point_position(j + 1) - rail.curve.get_point_position(j)
			tangent = (prev_to_curr + curr_to_next).normalized()

		var handle_length: float = distance / float(num_points) * 0.5
		rail.curve.set_point_in(j, -tangent * handle_length)
		rail.curve.set_point_out(j, tangent * handle_length)

	add_child(rail)
	create_rail_visual(rail)

	print("Connecting rail created with ", num_points, " points")
