extends Node3D

## Procedural Level Generator (Type A - Sonic-Style Speedrun Arena)
## Creates open, flowing arenas optimized for high-speed marble gameplay
## Features: floating platforms, ramps, grind rails, and vertical rails

# ============================================================================
# EXPORTED PARAMETERS
# ============================================================================

@export var level_seed: int = 0
@export var arena_size: float = 120.0  # Base arena size (scaled by size setting)
@export var complexity: int = 2  # 1=Low, 2=Medium, 3=High, 4=Extreme

# Calculated counts (set by configure_for_complexity)
var platform_count: int = 15
var ramp_count: int = 10
var grind_rail_count: int = 6
var vertical_rail_count: int = 3
var obstacle_count: int = 4

# Internal parameters
var min_spacing: float = 3.0  # Minimum gap for interactive objects only

var noise: FastNoiseLite
var platforms: Array = []
var interactive_positions: Array[Dictionary] = []  # Only track interactive objects (jump pads, etc.)
var material_manager = preload("res://scripts/procedural_material_manager.gd").new()

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	configure_for_complexity()
	generate_level()

func configure_for_complexity() -> void:
	"""Configure all parameters based on complexity and arena size.
	Complexity affects density and variety, while arena_size affects scale.
	Larger arenas need MORE geometry to fill the space properly."""

	# Calculate arena scale factor (how much bigger than default 120.0)
	var scale_factor: float = arena_size / 120.0
	# For larger arenas, we need dramatically more geometry
	var area_multiplier: float = scale_factor * scale_factor  # Quadratic scaling for area

	# Base counts for complexity levels (at default arena size)
	var base_platforms: Dictionary = {1: 8, 2: 15, 3: 22, 4: 30}
	var base_ramps: Dictionary = {1: 5, 2: 10, 3: 15, 4: 20}
	var base_grind_rails: Dictionary = {1: 4, 2: 6, 3: 8, 4: 10}
	var base_vertical_rails: Dictionary = {1: 2, 2: 3, 3: 4, 4: 6}
	var base_obstacles: Dictionary = {1: 2, 2: 4, 3: 6, 4: 8}

	# Apply complexity base and scale by arena size
	var clamped_complexity: int = clampi(complexity, 1, 4)
	platform_count = int(base_platforms[clamped_complexity] * area_multiplier)
	ramp_count = int(base_ramps[clamped_complexity] * area_multiplier)
	grind_rail_count = int(base_grind_rails[clamped_complexity] * sqrt(scale_factor))  # Linear scaling for rails
	vertical_rail_count = int(base_vertical_rails[clamped_complexity] * sqrt(scale_factor))
	obstacle_count = int(base_obstacles[clamped_complexity] * area_multiplier)

	if OS.is_debug_build():
		print("Level configured - Complexity: %d, Arena Size: %.1f, Scale: %.2f" % [complexity, arena_size, scale_factor])
		print("  Platforms: %d, Ramps: %d, Rails: %d, Vertical: %d, Obstacles: %d" % [platform_count, ramp_count, grind_rail_count, vertical_rail_count, obstacle_count])

# ============================================================================
# LEVEL GENERATION
# ============================================================================

func generate_level() -> void:
	"""Generate a complete procedural level"""
	if OS.is_debug_build():
		print("Generating Sonic-style speedrun level with seed: ", level_seed)

	# Initialize noise for variation
	noise = FastNoiseLite.new()
	noise.seed = level_seed if level_seed != 0 else randi()
	noise.frequency = 0.05

	# Clear any existing geometry
	clear_level()

	# Generate level components (order matters for layering)
	generate_main_floor()
	generate_platforms()
	generate_ramps()
	generate_obstacles()
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
	interactive_positions.clear()

# ============================================================================
# SPACING CHECKS (Only for interactive objects)
# ============================================================================

func check_interactive_spacing(new_pos: Vector3, new_radius: float) -> bool:
	"""Check if a new interactive object has proper spacing from other interactive objects.
	This is ONLY used for jump pads, teleporters, etc. - NOT for geometry.
	Returns true if the position is valid."""

	for existing in interactive_positions:
		var existing_pos: Vector3 = existing.position
		var existing_radius: float = existing.radius
		var distance: float = new_pos.distance_to(existing_pos)
		var min_dist: float = new_radius + existing_radius + min_spacing

		if distance < min_dist:
			return false

	return true

func register_interactive(pos: Vector3, radius: float) -> void:
	"""Register an interactive object for spacing checks"""
	interactive_positions.append({
		"position": pos,
		"radius": radius
	})

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

func create_smooth_box_mesh(size: Vector3) -> BoxMesh:
	"""Create a box mesh with smooth appearance"""
	var mesh = BoxMesh.new()
	mesh.size = size
	mesh.subdivide_width = 2
	mesh.subdivide_height = 2
	mesh.subdivide_depth = 2
	return mesh

# ============================================================================
# MAIN FLOOR
# ============================================================================

func generate_main_floor() -> void:
	"""Generate the main arena floor"""
	var floor_size: float = arena_size * 0.7

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

	platforms.append(floor_instance)

	if OS.is_debug_build():
		print("Generated main floor: ", floor_size, "x", floor_size)

# ============================================================================
# PLATFORMS
# ============================================================================

func generate_platforms() -> void:
	"""Generate elevated platforms - complexity affects count, height range, and size variation"""
	var floor_radius: float = (arena_size * 0.7) / 2.0

	# Complexity affects height range and size variation
	var max_height: float = 6.0 + complexity * 3.0  # 9, 12, 15, 18
	var min_height: float = 2.0 + complexity * 0.5   # 2.5, 3, 3.5, 4
	var size_variation: float = 1.0 + complexity * 0.3  # More variation at higher complexity

	for i in range(platform_count):
		# Distribute platforms across the arena
		var angle: float = randf() * TAU
		var distance: float = randf_range(8.0, floor_radius - 5.0)

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance
		var y: float = randf_range(min_height, max_height)

		# Platform size varies with complexity
		var base_size: float = 5.0 + randf() * 4.0 * size_variation
		var width: float = base_size + randf() * 3.0
		var depth: float = base_size + randf() * 3.0
		var height: float = 0.8 + randf() * 0.7

		var platform_size: Vector3 = Vector3(width, height, depth)
		var platform_pos: Vector3 = Vector3(x, y, z)

		# Create platform (no spacing checks - geometry can overlap slightly)
		var platform_mesh: BoxMesh = create_smooth_box_mesh(platform_size)

		var platform_instance: MeshInstance3D = MeshInstance3D.new()
		platform_instance.mesh = platform_mesh
		platform_instance.name = "Platform" + str(i)
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

	if OS.is_debug_build():
		print("Generated ", platform_count, " platforms (height range: %.1f-%.1f)" % [min_height, max_height])

# ============================================================================
# RAMPS (Slopes for Speed)
# ============================================================================

func generate_ramps() -> void:
	"""Generate ramps/slopes - complexity affects count, angles, and sizes"""
	var floor_radius: float = (arena_size * 0.7) / 2.0

	# Complexity affects ramp steepness and size
	var max_angle: float = 20.0 + complexity * 5.0  # Steeper at higher complexity
	var min_angle: float = 10.0 + complexity * 2.0
	var ramp_scale: float = 1.0 + complexity * 0.2

	for i in range(ramp_count):
		# Position ramps across the arena floor
		var angle: float = randf() * TAU
		var distance: float = randf_range(5.0, floor_radius - 8.0)

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance
		var y: float = randf_range(0.3, 3.0 + complexity)  # Higher ramps at higher complexity

		# Ramp size scales with complexity
		var ramp_length: float = (8.0 + randf() * 6.0) * ramp_scale
		var ramp_width: float = (6.0 + randf() * 4.0) * ramp_scale
		var ramp_size: Vector3 = Vector3(ramp_width, 0.5, ramp_length)
		var ramp_pos: Vector3 = Vector3(x, y, z)

		# Random rotation with complexity-based tilt
		var tilt_angle: float = randf_range(min_angle, max_angle)
		var ramp_rotation: Vector3 = Vector3(-tilt_angle, randf() * 360.0, 0)

		# Create ramp (no spacing checks for geometry)
		var ramp_mesh: BoxMesh = create_smooth_box_mesh(ramp_size)

		var ramp_instance: MeshInstance3D = MeshInstance3D.new()
		ramp_instance.mesh = ramp_mesh
		ramp_instance.name = "Ramp" + str(i)
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

	if OS.is_debug_build():
		print("Generated ", ramp_count, " ramps (angle range: %.1f-%.1f)" % [min_angle, max_angle])

# ============================================================================
# OBSTACLES (Low obstacles that don't block upward movement)
# ============================================================================

func generate_obstacles() -> void:
	"""Generate small obstacles - kept LOW to not impede upward progression"""
	var floor_radius: float = (arena_size * 0.7) / 2.0

	for i in range(obstacle_count):
		var angle: float = randf() * TAU
		var distance: float = randf_range(10.0, floor_radius - 10.0)

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance

		# IMPORTANT: Keep obstacles LOW so they don't block upward movement
		var obstacle_height: float = 1.0 + randf() * 1.5  # Max 2.5 units tall
		var obstacle_width: float = 2.0 + randf() * 3.0
		var obstacle_depth: float = 2.0 + randf() * 3.0

		var obstacle_size: Vector3 = Vector3(obstacle_width, obstacle_height, obstacle_depth)
		var obstacle_pos: Vector3 = Vector3(x, obstacle_height / 2.0, z)

		var obstacle_mesh: BoxMesh = create_smooth_box_mesh(obstacle_size)

		var obstacle_instance: MeshInstance3D = MeshInstance3D.new()
		obstacle_instance.mesh = obstacle_mesh
		obstacle_instance.name = "Obstacle" + str(i)
		obstacle_instance.position = obstacle_pos
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

	if OS.is_debug_build():
		print("Generated ", obstacle_count, " obstacles (kept low for upward progression)")

# ============================================================================
# GRIND RAILS
# ============================================================================

func generate_grind_rails() -> void:
	"""Generate grinding rails around the arena perimeter (Sonic style)"""
	# Position around the arena perimeter
	var rail_distance: float = arena_size * 0.55

	# Complexity affects rail height variation and arc coverage
	var height_variation: float = 1.0 + complexity * 0.5
	var arc_coverage: float = 0.6 + complexity * 0.05  # More coverage at higher complexity

	for i in range(grind_rail_count):
		var angle_start: float = (float(i) / grind_rail_count) * TAU
		var angle_end: float = angle_start + (TAU / grind_rail_count) * arc_coverage

		# Create a curved rail using Path3D and Curve3D
		var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
		rail.name = "GrindRail" + str(i)
		rail.curve = Curve3D.new()

		# Varied heights based on complexity
		var base_height: float = 2.5 + (i % 3) * (2.0 + complexity * 0.5)

		# Create curve points along the arc
		var num_points: int = 10 + complexity * 2
		for j in range(num_points):
			var t: float = float(j) / (num_points - 1)
			var angle: float = lerp(angle_start, angle_end, t)

			var x: float = cos(angle) * rail_distance
			var z: float = sin(angle) * rail_distance

			# Height variation increases with complexity
			var height_offset: float = sin(t * PI) * height_variation
			var y: float = base_height + height_offset

			rail.curve.add_point(Vector3(x, y, z))

		# Set smooth tangent handles
		_set_rail_tangents(rail)

		add_child(rail)
		create_rail_visual(rail)

	# Add vertical connecting rails
	generate_vertical_rails()

	if OS.is_debug_build():
		print("Generated ", grind_rail_count, " grind rails around perimeter")

func generate_vertical_rails() -> void:
	"""Generate vertical/diagonal rails connecting different heights"""
	var rail_distance: float = arena_size * 0.50

	# Complexity affects end height and spiral tightness
	var end_height: float = 8.0 + complexity * 3.0
	var spiral_amount: float = PI * (0.3 + complexity * 0.1)

	for i in range(vertical_rail_count):
		var angle: float = (float(i) / vertical_rail_count) * TAU + (TAU / vertical_rail_count * 0.5)

		var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
		rail.name = "VerticalRail" + str(i)
		rail.curve = Curve3D.new()

		var start_y: float = 1.5

		var num_points: int = 6 + complexity
		for j in range(num_points):
			var t: float = float(j) / (num_points - 1)
			var current_angle: float = angle + t * spiral_amount
			var current_distance: float = lerp(rail_distance, rail_distance * 0.8, t)

			var x: float = cos(current_angle) * current_distance
			var z: float = sin(current_angle) * current_distance
			var y: float = lerp(start_y, end_height, t)

			rail.curve.add_point(Vector3(x, y, z))

		_set_rail_tangents(rail)

		add_child(rail)
		create_rail_visual(rail)

	if OS.is_debug_build():
		print("Generated ", vertical_rail_count, " vertical rails (max height: %.1f)" % end_height)

func _set_rail_tangents(rail: Path3D) -> void:
	"""Calculate and set proper tangent handles for smooth rail curves"""
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

func create_rail_visual(rail: Path3D) -> void:
	"""Create visual representation of a rail using a 3D cylindrical tube"""
	if not rail.curve or rail.curve.get_baked_length() == 0:
		return

	var rail_visual: MeshInstance3D = MeshInstance3D.new()
	rail_visual.name = "RailVisual"

	var immediate_mesh: ImmediateMesh = ImmediateMesh.new()
	rail_visual.mesh = immediate_mesh

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.75, 0.85)
	material.metallic = 0.85
	material.roughness = 0.3

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)

	var rail_radius: float = 0.15
	var radial_segments: int = 8
	var length_segments: int = int(rail.curve.get_baked_length() * 2)
	length_segments = max(length_segments, 10)

	for i in range(length_segments):
		var offset: float = (float(i) / length_segments) * rail.curve.get_baked_length()
		var next_offset: float = (float(i + 1) / length_segments) * rail.curve.get_baked_length()

		var pos: Vector3 = rail.curve.sample_baked(offset)
		var next_pos: Vector3 = rail.curve.sample_baked(next_offset)

		var forward: Vector3 = (next_pos - pos).normalized()
		if forward.length() < 0.1:
			forward = Vector3.FORWARD

		var right: Vector3 = forward.cross(Vector3.UP).normalized()
		if right.length() < 0.1:
			right = forward.cross(Vector3.RIGHT).normalized()
		var up: Vector3 = right.cross(forward).normalized()

		for j in range(radial_segments):
			var angle_curr: float = (float(j) / radial_segments) * TAU
			var angle_next: float = (float(j + 1) / radial_segments) * TAU

			var offset_curr: Vector3 = (right * cos(angle_curr) + up * sin(angle_curr)) * rail_radius
			var offset_next: Vector3 = (right * cos(angle_next) + up * sin(angle_next)) * rail_radius

			var v1: Vector3 = pos + offset_curr
			var v2: Vector3 = pos + offset_next
			var v3: Vector3 = next_pos + offset_curr
			var v4: Vector3 = next_pos + offset_next

			immediate_mesh.surface_add_vertex(v1)
			immediate_mesh.surface_add_vertex(v2)
			immediate_mesh.surface_add_vertex(v3)

			immediate_mesh.surface_add_vertex(v2)
			immediate_mesh.surface_add_vertex(v4)
			immediate_mesh.surface_add_vertex(v3)

	immediate_mesh.surface_end()

	rail.add_child(rail_visual)

# ============================================================================
# DEATH ZONE
# ============================================================================

func generate_death_zone() -> void:
	"""Generate death zone below the arena"""
	var death_zone: Area3D = Area3D.new()
	death_zone.name = "DeathZone"
	death_zone.position = Vector3(0, -50, 0)
	death_zone.collision_layer = 0
	death_zone.collision_mask = 2
	death_zone.add_to_group("death_zone")
	add_child(death_zone)

	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(arena_size * 2, 10, arena_size * 2)
	collision.shape = shape
	death_zone.add_child(collision)

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

# ============================================================================
# MATERIALS
# ============================================================================

func apply_procedural_textures() -> void:
	"""Apply procedurally generated textures to all platforms"""
	material_manager.apply_materials_to_level(self)

# ============================================================================
# SPAWN POINTS
# ============================================================================

func get_spawn_points() -> PackedVector3Array:
	"""Generate spawn points on platforms - supports up to 8 players total"""
	var spawns: PackedVector3Array = PackedVector3Array()
	var floor_radius: float = (arena_size * 0.7) / 2.0

	# Main floor spawns - scaled with arena size
	spawns.append(Vector3(0, 2, 0))  # Center

	# Ring spawns scaled to arena size
	var ring1_dist: float = min(10.0, floor_radius * 0.25)
	var ring2_dist: float = min(20.0, floor_radius * 0.5)

	spawns.append(Vector3(ring1_dist, 2, 0))
	spawns.append(Vector3(-ring1_dist, 2, 0))
	spawns.append(Vector3(0, 2, ring1_dist))
	spawns.append(Vector3(0, 2, -ring1_dist))

	spawns.append(Vector3(ring1_dist, 2, ring1_dist))
	spawns.append(Vector3(-ring1_dist, 2, ring1_dist))
	spawns.append(Vector3(ring1_dist, 2, -ring1_dist))
	spawns.append(Vector3(-ring1_dist, 2, -ring1_dist))

	spawns.append(Vector3(ring2_dist, 2, 0))
	spawns.append(Vector3(-ring2_dist, 2, 0))
	spawns.append(Vector3(0, 2, ring2_dist))
	spawns.append(Vector3(0, 2, -ring2_dist))

	# Platform spawns
	for platform in platforms:
		if platform.name.begins_with("Platform"):
			var spawn_pos: Vector3 = platform.position
			spawn_pos.y += 3.0
			spawns.append(spawn_pos)

	return spawns

# ============================================================================
# MID-ROUND EXPANSION SYSTEM
# ============================================================================

func generate_secondary_map(offset: Vector3) -> void:
	"""Generate a secondary map at the specified offset position"""
	print("Generating secondary map at offset: ", offset)

	var secondary_seed: int = noise.seed + 1000
	var old_seed: int = noise.seed
	noise.seed = secondary_seed

	generate_secondary_floor(offset)
	generate_secondary_platforms(offset)
	generate_secondary_ramps(offset)
	generate_secondary_rails(offset)

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
	var rail_distance: float = arena_size * 0.54

	for i in range(grind_rail_count):
		var angle_start: float = (float(i) / grind_rail_count) * TAU
		var angle_end: float = angle_start + (TAU / grind_rail_count) * 0.7

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

		_set_rail_tangents(rail)

		add_child(rail)
		create_rail_visual(rail)

func generate_connecting_rail(start_pos: Vector3, end_pos: Vector3) -> void:
	"""Generate a long connecting rail between two map areas"""
	print("Generating connecting rail from ", start_pos, " to ", end_pos)

	var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
	rail.name = "ConnectingRail"
	rail.curve = Curve3D.new()

	var distance: float = start_pos.distance_to(end_pos)
	var num_points: int = max(20, int(distance / 15.0))

	for i in range(num_points):
		var t: float = float(i) / (num_points - 1)
		var pos: Vector3 = start_pos.lerp(end_pos, t)
		var arc_height: float = 15.0
		var height_offset: float = sin(t * PI) * arc_height
		pos.y += height_offset

		rail.curve.add_point(pos)

	_set_rail_tangents(rail)

	add_child(rail)
	create_rail_visual(rail)

	print("Connecting rail created with ", num_points, " points")
