extends Node3D

## Procedural Level Generator (Type A - Sonic-Style Speedrun Arena)
## Creates open, flowing arenas optimized for high-speed marble gameplay
## Features: open central area, perimeter platforms, grind rails, and speed ramps

# ============================================================================
# EXPORTED PARAMETERS
# ============================================================================

@export var level_seed: int = 0
@export var arena_size: float = 120.0  # Base arena size - THIS CONTROLS ACTUAL SIZE
@export var complexity: int = 2  # 1=Low, 2=Medium, 3=High, 4=Extreme

# Calculated counts (set by configure_for_complexity)
var platform_count: int = 12
var ramp_count: int = 8
var grind_rail_count: int = 6
var vertical_rail_count: int = 3

var noise: FastNoiseLite
var platforms: Array = []
var geometry_bounds: Array[Dictionary] = []  # Track all geometry for interactive placement
var material_manager = preload("res://scripts/procedural_material_manager.gd").new()

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	configure_for_complexity()
	generate_level()

func configure_for_complexity() -> void:
	"""Configure parameters based on complexity. Arena size is set externally."""

	# Complexity affects DENSITY, not size
	# Keep counts LOW for Sonic-style open arenas
	var base_platforms: Dictionary = {1: 6, 2: 10, 3: 14, 4: 18}
	var base_ramps: Dictionary = {1: 4, 2: 6, 3: 8, 4: 10}
	var base_grind_rails: Dictionary = {1: 4, 2: 6, 3: 8, 4: 10}
	var base_vertical_rails: Dictionary = {1: 2, 2: 3, 3: 4, 4: 5}

	var c: int = clampi(complexity, 1, 4)
	platform_count = base_platforms[c]
	ramp_count = base_ramps[c]
	grind_rail_count = base_grind_rails[c]
	vertical_rail_count = base_vertical_rails[c]

	print("=== SONIC LEVEL CONFIG ===")
	print("Arena Size: %.1f (floor will be %.1f x %.1f)" % [arena_size, arena_size * 0.7, arena_size * 0.7])
	print("Complexity: %d" % complexity)
	print("Platforms: %d, Ramps: %d, Rails: %d" % [platform_count, ramp_count, grind_rail_count])

# ============================================================================
# LEVEL GENERATION
# ============================================================================

func generate_level() -> void:
	"""Generate a complete procedural level"""
	print("Generating Sonic-style speedrun level...")
	print("Arena size parameter: %.1f" % arena_size)

	noise = FastNoiseLite.new()
	noise.seed = level_seed if level_seed != 0 else randi()
	noise.frequency = 0.05

	clear_level()

	# Generate in order - floor first, then perimeter elements
	generate_main_floor()
	generate_perimeter_platforms()  # Platforms around the EDGES
	generate_speed_ramps()          # Ramps pointing toward center
	generate_grind_rails()          # Rails around perimeter
	generate_death_zone()

	apply_procedural_textures()
	print("Level generation complete! Floor size: %.1f" % (arena_size * 0.7))

func clear_level() -> void:
	for child in get_children():
		child.queue_free()
	platforms.clear()
	geometry_bounds.clear()

func register_geometry(pos: Vector3, size: Vector3) -> void:
	"""Register geometry bounds for interactive object placement"""
	geometry_bounds.append({
		"position": pos,
		"size": size
	})

func is_position_clear(pos: Vector3, radius: float, check_height: bool = true) -> bool:
	"""Check if a position is clear of geometry"""
	for geo in geometry_bounds:
		var geo_pos: Vector3 = geo.position
		var geo_size: Vector3 = geo.size

		# Simple AABB check with margin
		var margin: float = radius + 2.0
		if abs(pos.x - geo_pos.x) < (geo_size.x / 2.0 + margin) and \
		   abs(pos.z - geo_pos.z) < (geo_size.z / 2.0 + margin):
			if check_height and abs(pos.y - geo_pos.y) < (geo_size.y / 2.0 + margin):
				return false
			elif not check_height:
				return false
	return true

# ============================================================================
# UTILITY
# ============================================================================

func create_smooth_box_mesh(size: Vector3) -> BoxMesh:
	var mesh = BoxMesh.new()
	mesh.size = size
	mesh.subdivide_width = 2
	mesh.subdivide_height = 2
	mesh.subdivide_depth = 2
	return mesh

# ============================================================================
# MAIN FLOOR - This is what determines actual arena size
# ============================================================================

func generate_main_floor() -> void:
	"""Generate the main arena floor - SIZE SCALES WITH arena_size"""
	var floor_size: float = arena_size * 0.7

	print("Creating main floor: %.1f x %.1f" % [floor_size, floor_size])

	var floor_mesh: BoxMesh = create_smooth_box_mesh(Vector3(floor_size, 2.0, floor_size))

	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.name = "MainFloor"
	floor_instance.position = Vector3(0, -1, 0)
	add_child(floor_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = floor_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	floor_instance.add_child(static_body)

	platforms.append(floor_instance)
	# Don't register floor as blocking geometry

# ============================================================================
# PERIMETER PLATFORMS - Around the edges, NOT in the center
# ============================================================================

func generate_perimeter_platforms() -> void:
	"""Generate elevated platforms around the PERIMETER of the arena"""
	var floor_radius: float = (arena_size * 0.7) / 2.0

	# Platforms go in the OUTER 40% of the arena (60-100% of radius)
	var inner_limit: float = floor_radius * 0.6
	var outer_limit: float = floor_radius * 0.95

	# Heights scale with arena size
	var base_height: float = arena_size * 0.04  # ~5 at default, ~10 at huge
	var max_height: float = arena_size * 0.12   # ~15 at default, ~30 at huge

	print("Placing %d platforms between radius %.1f and %.1f" % [platform_count, inner_limit, outer_limit])

	for i in range(platform_count):
		# Distribute evenly around perimeter with some randomness
		var base_angle: float = (float(i) / platform_count) * TAU
		var angle: float = base_angle + randf_range(-0.2, 0.2)
		var distance: float = randf_range(inner_limit, outer_limit)

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance
		var y: float = randf_range(base_height, max_height)

		# Platform size scales with arena
		var size_scale: float = arena_size / 120.0
		var width: float = (5.0 + randf() * 4.0) * size_scale
		var depth: float = (5.0 + randf() * 4.0) * size_scale
		var height: float = 0.8 + randf() * 0.7

		var platform_size: Vector3 = Vector3(width, height, depth)
		var platform_pos: Vector3 = Vector3(x, y, z)

		var platform_mesh: BoxMesh = create_smooth_box_mesh(platform_size)

		var platform_instance: MeshInstance3D = MeshInstance3D.new()
		platform_instance.mesh = platform_mesh
		platform_instance.name = "Platform" + str(i)
		platform_instance.position = platform_pos
		add_child(platform_instance)

		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = platform_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		platform_instance.add_child(static_body)

		platforms.append(platform_instance)
		register_geometry(platform_pos, platform_size)

	print("Generated %d perimeter platforms" % platform_count)

# ============================================================================
# SPEED RAMPS - At edges, pointing toward center for speed boosts
# ============================================================================

func generate_speed_ramps() -> void:
	"""Generate ramps at the perimeter pointing toward center"""
	var floor_radius: float = (arena_size * 0.7) / 2.0

	# Ramps at the outer edge
	var ramp_distance: float = floor_radius * 0.75

	print("Placing %d speed ramps at distance %.1f" % [ramp_count, ramp_distance])

	for i in range(ramp_count):
		var angle: float = (float(i) / ramp_count) * TAU + randf_range(-0.1, 0.1)

		var x: float = cos(angle) * ramp_distance
		var z: float = sin(angle) * ramp_distance

		# Ramp size scales with arena
		var size_scale: float = arena_size / 120.0
		var ramp_length: float = (10.0 + randf() * 4.0) * size_scale
		var ramp_width: float = (6.0 + randf() * 2.0) * size_scale
		var ramp_size: Vector3 = Vector3(ramp_width, 0.5, ramp_length)

		# Ramp sits on ground, tilted toward center
		var ramp_pos: Vector3 = Vector3(x, ramp_length * 0.15, z)  # Slight elevation based on tilt

		# Rotate to face center
		var angle_to_center: float = atan2(-x, -z)
		var tilt: float = 15.0 + randf() * 10.0  # 15-25 degree tilt

		var ramp_mesh: BoxMesh = create_smooth_box_mesh(ramp_size)

		var ramp_instance: MeshInstance3D = MeshInstance3D.new()
		ramp_instance.mesh = ramp_mesh
		ramp_instance.name = "Ramp" + str(i)
		ramp_instance.position = ramp_pos
		ramp_instance.rotation_degrees = Vector3(-tilt, rad_to_deg(angle_to_center), 0)
		add_child(ramp_instance)

		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = ramp_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		ramp_instance.add_child(static_body)

		platforms.append(ramp_instance)
		register_geometry(ramp_pos, ramp_size * 1.5)  # Larger bounds due to rotation

	print("Generated %d speed ramps" % ramp_count)

# ============================================================================
# GRIND RAILS - The signature Sonic element
# ============================================================================

func generate_grind_rails() -> void:
	"""Generate grinding rails around the arena perimeter"""
	var rail_distance: float = arena_size * 0.45  # Outside the main floor

	# Rail heights scale with arena size
	var base_rail_height: float = arena_size * 0.025  # ~3 at default, ~6 at huge

	print("Placing %d grind rails at distance %.1f" % [grind_rail_count, rail_distance])

	for i in range(grind_rail_count):
		var angle_start: float = (float(i) / grind_rail_count) * TAU
		var angle_end: float = angle_start + (TAU / grind_rail_count) * 0.7

		var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
		rail.name = "GrindRail" + str(i)
		rail.curve = Curve3D.new()

		var height: float = base_rail_height + (i % 3) * (arena_size * 0.02)

		var num_points: int = 10 + complexity * 2
		for j in range(num_points):
			var t: float = float(j) / (num_points - 1)
			var angle: float = lerp(angle_start, angle_end, t)

			var x: float = cos(angle) * rail_distance
			var z: float = sin(angle) * rail_distance
			var height_offset: float = sin(t * PI) * (arena_size * 0.01)
			var y: float = height + height_offset

			rail.curve.add_point(Vector3(x, y, z))

		_set_rail_tangents(rail)
		add_child(rail)
		create_rail_visual(rail)

	generate_vertical_rails()
	print("Generated %d grind rails" % grind_rail_count)

func generate_vertical_rails() -> void:
	"""Generate vertical/diagonal rails for height transitions"""
	var rail_distance: float = arena_size * 0.40
	var end_height: float = arena_size * 0.08 + complexity * (arena_size * 0.02)

	for i in range(vertical_rail_count):
		var angle: float = (float(i) / vertical_rail_count) * TAU + PI / vertical_rail_count

		var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
		rail.name = "VerticalRail" + str(i)
		rail.curve = Curve3D.new()

		var start_y: float = arena_size * 0.015
		var num_points: int = 6 + complexity

		for j in range(num_points):
			var t: float = float(j) / (num_points - 1)
			var current_angle: float = angle + t * PI * 0.4
			var current_distance: float = lerp(rail_distance, rail_distance * 0.85, t)

			var x: float = cos(current_angle) * current_distance
			var z: float = sin(current_angle) * current_distance
			var y: float = lerp(start_y, end_height, t)

			rail.curve.add_point(Vector3(x, y, z))

		_set_rail_tangents(rail)
		add_child(rail)
		create_rail_visual(rail)

func _set_rail_tangents(rail: Path3D) -> void:
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

		rail.curve.set_point_in(j, -tangent * 0.5)
		rail.curve.set_point_out(j, tangent * 0.5)

func create_rail_visual(rail: Path3D) -> void:
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

func _on_death_zone_entered(body: Node3D) -> void:
	if body.has_method("fall_death"):
		body.fall_death()
	elif body.has_method("respawn"):
		body.respawn()

# ============================================================================
# MATERIALS & SPAWNS
# ============================================================================

func apply_procedural_textures() -> void:
	material_manager.apply_materials_to_level(self)

func get_spawn_points() -> PackedVector3Array:
	var spawns: PackedVector3Array = PackedVector3Array()
	var floor_radius: float = (arena_size * 0.7) / 2.0

	# Center spawn
	spawns.append(Vector3(0, 2, 0))

	# Ring spawns that SCALE with arena size
	var ring1_dist: float = floor_radius * 0.25
	var ring2_dist: float = floor_radius * 0.5

	for i in range(4):
		var angle: float = (float(i) / 4) * TAU
		spawns.append(Vector3(cos(angle) * ring1_dist, 2, sin(angle) * ring1_dist))
		spawns.append(Vector3(cos(angle) * ring2_dist, 2, sin(angle) * ring2_dist))

	# Platform spawns
	for platform in platforms:
		if platform.name.begins_with("Platform"):
			var spawn_pos: Vector3 = platform.position
			spawn_pos.y += 3.0
			spawns.append(spawn_pos)

	return spawns

# ============================================================================
# EXPANSION SYSTEM (for mid-round expansion)
# ============================================================================

func generate_secondary_map(offset: Vector3) -> void:
	print("Generating secondary map at offset: ", offset)
	var secondary_seed: int = noise.seed + 1000
	var old_seed: int = noise.seed
	noise.seed = secondary_seed

	# Secondary floor
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

	noise.seed = old_seed
	print("Secondary map generation complete")

func generate_connecting_rail(start_pos: Vector3, end_pos: Vector3) -> void:
	var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
	rail.name = "ConnectingRail"
	rail.curve = Curve3D.new()

	var distance: float = start_pos.distance_to(end_pos)
	var num_points: int = max(20, int(distance / 15.0))

	for i in range(num_points):
		var t: float = float(i) / (num_points - 1)
		var pos: Vector3 = start_pos.lerp(end_pos, t)
		pos.y += sin(t * PI) * 15.0
		rail.curve.add_point(pos)

	_set_rail_tangents(rail)
	add_child(rail)
	create_rail_visual(rail)
