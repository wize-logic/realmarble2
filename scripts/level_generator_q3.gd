extends Node3D

## Quake 3 Arena-Style Level Generator (Type B)
## Creates multi-tiered arenas with complex geometry, rooms, corridors, and vertical gameplay

@export var level_seed: int = 0
@export var arena_size: float = 140.0
@export var complexity: int = 2  # 1=Simple, 2=Medium, 3=Complex, 4=Extreme

var noise: FastNoiseLite
var platforms: Array = []
var teleporters: Array = []  # For potential teleporter pairs
var geometry_positions: Array[Dictionary] = []  # For spacing checks - stores {position, size}
var material_manager = preload("res://scripts/procedural_material_manager.gd").new()

# Calculated parameters based on complexity
var room_count: int = 4
var corridor_width: float = 6.0
var tier_count: int = 3  # Number of platform tiers
var platforms_per_tier: Array[int] = [4, 8, 4]  # Platforms at each tier
var pillar_count: int = 4
var cover_count: int = 8
var jump_pad_count: int = 5
var teleporter_pair_count: int = 2
var wall_height: float = 25.0
var room_size: Vector3 = Vector3(16.0, 10.0, 16.0)
var min_spacing: float = 6.0  # Minimum gap between objects

func _ready() -> void:
	generate_level()

var tunnel_count: int = 0
var catwalk_count: int = 0

func configure_from_complexity() -> void:
	"""Configure all generation parameters based on complexity and arena_size"""
	var size_factor: float = arena_size / 140.0

	# Complexity ONLY controls density/counts
	# Size (arena_size) controls how big everything is
	match complexity:
		1:  # Simple - open arena, few structures
			room_count = 2
			tier_count = 2
			platforms_per_tier = [3, 3, 0, 0, 0]
			pillar_count = 4
			cover_count = 6
			jump_pad_count = 3
			teleporter_pair_count = 1
			tunnel_count = 0
			catwalk_count = 2
		2:  # Medium (default Q3 arena)
			room_count = 4
			tier_count = 3
			platforms_per_tier = [4, 6, 4, 0, 0]
			pillar_count = 6
			cover_count = 12
			jump_pad_count = 5
			teleporter_pair_count = 2
			tunnel_count = 2
			catwalk_count = 4
		3:  # Complex - interconnected, vertical
			room_count = 6
			tier_count = 4
			platforms_per_tier = [5, 8, 6, 4, 0]
			pillar_count = 10
			cover_count = 20
			jump_pad_count = 8
			teleporter_pair_count = 3
			tunnel_count = 4
			catwalk_count = 6
		4:  # Extreme - dense, many paths
			room_count = 8
			tier_count = 5
			platforms_per_tier = [6, 10, 8, 6, 4]
			pillar_count = 14
			cover_count = 30
			jump_pad_count = 10
			teleporter_pair_count = 4
			tunnel_count = 6
			catwalk_count = 8
		_:  # Default to medium
			complexity = 2
			configure_from_complexity()
			return

	# Sizes scale with arena
	corridor_width = 8.0 * size_factor
	wall_height = 30.0 * size_factor
	room_size = Vector3(18.0, 12.0, 18.0) * size_factor

	# Minimum spacing scales with arena size
	min_spacing = 8.0 * size_factor
	min_spacing = max(min_spacing, 5.0)

	if OS.is_debug_build():
		print("Q3 Level config - Complexity: %d, Arena: %.0f (factor: %.2f), Rooms: %d, Tunnels: %d, Catwalks: %d" % [
			complexity, arena_size, size_factor, room_count, tunnel_count, catwalk_count
		])

func generate_level() -> void:
	"""Generate a complete Quake 3 Arena-style level"""
	if OS.is_debug_build():
		print("Generating Quake 3 Arena-style level with seed: ", level_seed)

	# Configure based on complexity and size
	configure_from_complexity()

	# Initialize noise for variation
	noise = FastNoiseLite.new()
	noise.seed = level_seed if level_seed != 0 else randi()
	noise.frequency = 0.05

	# Clear any existing geometry
	clear_level()

	# Generate level components in Q3 style
	generate_main_arena()
	generate_upper_platforms()
	generate_side_rooms()
	generate_corridors()
	generate_tunnels()      # Underground passages
	generate_catwalks()     # Elevated walkways
	generate_jump_pads()
	generate_teleporters()
	generate_perimeter_walls()
	generate_death_zone()

	# Apply beautiful procedural materials
	apply_procedural_textures()

	print("Quake 3 Arena-style level generation complete!")

func clear_level() -> void:
	"""Remove all existing level geometry"""
	for child in get_children():
		child.queue_free()
	platforms.clear()
	teleporters.clear()
	geometry_positions.clear()

func check_spacing(new_pos: Vector3, new_size: Vector3) -> bool:
	"""Check if a new piece of geometry would have proper spacing from existing geometry.
	Returns true if the position is valid (has enough spacing), false if it would overlap/touch."""
	var new_half_size: Vector3 = new_size * 0.5

	for existing in geometry_positions:
		var existing_pos: Vector3 = existing.position
		var existing_size: Vector3 = existing.size
		var existing_half_size: Vector3 = existing_size * 0.5

		# Simple distance check first (fast rejection)
		var distance: float = new_pos.distance_to(existing_pos)
		var combined_radius: float = (new_half_size.length() + existing_half_size.length()) + min_spacing

		if distance < combined_radius:
			# More precise AABB check with spacing margin
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

func register_geometry(pos: Vector3, size: Vector3) -> void:
	"""Register a piece of geometry in the spacing tracker"""
	geometry_positions.append({
		"position": pos,
		"size": size
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

# ============================================================================
# MAIN ARENA
# ============================================================================

func generate_main_arena() -> void:
	"""Generate the main ground floor arena - central combat area"""
	var floor_size: float = arena_size * 0.6

	# Main floor with smooth geometry
	var floor_mesh: BoxMesh = create_smooth_box_mesh(Vector3(floor_size, 2.0, floor_size))

	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.name = "MainArenaFloor"
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

	# Add decorative pillars/columns in the arena
	generate_arena_pillars()

	# Add small cover boxes in the arena
	generate_cover_objects()

	if OS.is_debug_build():
		print("Generated main arena floor: ", floor_size, "x", floor_size)

func generate_arena_pillars() -> void:
	"""Generate decorative pillars around the main arena"""
	# Generate pillars in a ring pattern based on pillar_count
	var pillar_distance: float = arena_size * 0.15  # Distance from center
	var pillar_height: float = (8.0 + complexity * 2.0) * (arena_size / 140.0)  # Scales with arena
	var generated_count: int = 0

	for i in range(pillar_count):
		var angle: float = (float(i) / pillar_count) * TAU
		var pillar_width: float = (3.0 + randf() * 2.0) * (arena_size / 140.0)
		var pillar_size: Vector3 = Vector3(pillar_width, pillar_height, pillar_width)
		var pillar_pos: Vector3 = Vector3(
			cos(angle) * pillar_distance,
			pillar_height / 2.0,
			sin(angle) * pillar_distance
		)

		# Check spacing before creating
		if not check_spacing(pillar_pos, pillar_size):
			continue

		# Create tall pillar with smooth geometry
		var pillar_mesh: BoxMesh = create_smooth_box_mesh(pillar_size)

		var pillar_instance: MeshInstance3D = MeshInstance3D.new()
		pillar_instance.mesh = pillar_mesh
		pillar_instance.name = "Pillar" + str(generated_count)
		pillar_instance.position = pillar_pos
		add_child(pillar_instance)

		# Add collision
		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = pillar_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		pillar_instance.add_child(static_body)

		platforms.append(pillar_instance)
		register_geometry(pillar_pos, pillar_size)
		generated_count += 1

func generate_cover_objects() -> void:
	"""Generate small cover boxes scattered in the arena"""
	# cover_count is set by configure_from_complexity()
	var cover_distance_max: float = arena_size * 0.2
	var size_factor: float = arena_size / 140.0
	var generated_count: int = 0
	var max_attempts: int = cover_count * 10

	for attempt in range(max_attempts):
		if generated_count >= cover_count:
			break

		var angle: float = randf() * TAU
		var distance: float = 10.0 * size_factor + randf() * cover_distance_max

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance

		# Create cover box with smooth geometry - scales with arena size
		var size_mult: float = size_factor * (1.0 - complexity * 0.05)
		var cover_size: Vector3 = Vector3(
			(3.0 + randf() * 2.0) * size_mult,
			(2.0 + randf() * 1.0) * size_mult,
			(3.0 + randf() * 2.0) * size_mult
		)
		var cover_pos: Vector3 = Vector3(x, cover_size.y / 2.0, z)

		# Check spacing before creating
		if not check_spacing(cover_pos, cover_size):
			continue

		var cover_mesh: BoxMesh = create_smooth_box_mesh(cover_size)

		var cover_instance: MeshInstance3D = MeshInstance3D.new()
		cover_instance.mesh = cover_mesh
		cover_instance.name = "Cover" + str(generated_count)
		cover_instance.position = cover_pos
		add_child(cover_instance)

		# Add collision
		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = cover_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		cover_instance.add_child(static_body)

		platforms.append(cover_instance)
		register_geometry(cover_pos, cover_size)
		generated_count += 1

# ============================================================================
# UPPER PLATFORMS (MULTI-TIER DESIGN)
# ============================================================================

func generate_upper_platforms() -> void:
	"""Generate multiple tiers of platforms for vertical gameplay"""
	var size_factor: float = arena_size / 140.0

	# Tier heights and distances scale with arena size
	var tier_base_height: float = 8.0 * size_factor
	var tier_height_increment: float = (6.0 + complexity) * size_factor
	var tier_base_distance: float = arena_size * 0.18
	var tier_distance_decrement: float = arena_size * 0.03

	for tier in range(tier_count):
		var tier_num: int = tier + 1
		var platform_count_for_tier: int = platforms_per_tier[tier] if tier < platforms_per_tier.size() else 4
		var height: float = tier_base_height + tier * tier_height_increment
		var distance: float = tier_base_distance - tier * tier_distance_decrement
		distance = max(distance, arena_size * 0.1)  # Minimum distance

		generate_tier_platforms(tier_num, platform_count_for_tier, height, distance)

	print("Generated ", tier_count, "-tier platform system")

func generate_tier_platforms(tier: int, count: int, height: float, distance_from_center: float) -> void:
	"""Generate a ring of platforms at a specific tier level"""
	var size_factor: float = arena_size / 140.0

	# Platform size scales with arena and decreases at higher tiers
	var size_reduction_per_tier: float = 2.0 * size_factor
	var complexity_size_factor: float = 1.0 - (complexity - 2) * 0.1  # Slightly smaller at high complexity
	var generated_count: int = 0

	for i in range(count):
		var angle: float = (float(i) / count) * TAU
		var x: float = cos(angle) * distance_from_center
		var z: float = sin(angle) * distance_from_center

		# Platform size scales with arena, varies by tier (higher = smaller)
		var base_size: float = (14.0 - tier * 2.0) * size_factor
		base_size = max(base_size, 5.0 * size_factor)  # Minimum size
		base_size *= complexity_size_factor
		# Add some random variation (scaled with arena)
		var variation: float = randf_range(-1.0, 2.0) * size_factor
		var platform_size: Vector3 = Vector3(
			base_size + variation,
			1.5 * size_factor,
			base_size + variation
		)
		var platform_pos: Vector3 = Vector3(x, height, z)

		# Check spacing before creating
		if not check_spacing(platform_pos, platform_size):
			continue

		# Create platform with smooth geometry
		var platform_mesh: BoxMesh = create_smooth_box_mesh(platform_size)

		var platform_instance: MeshInstance3D = MeshInstance3D.new()
		platform_instance.mesh = platform_mesh
		platform_instance.name = "Tier" + str(tier) + "Platform" + str(generated_count)
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
		register_geometry(platform_pos, platform_size)
		generated_count += 1

		# Add connecting ramps to some platforms
		if tier == 1 and generated_count % 2 == 0:  # Every other platform on tier 1
			generate_ramp_to_platform(platform_pos, platform_size)

func generate_ramp_to_platform(platform_pos: Vector3, platform_size: Vector3) -> void:
	"""Generate a ramp leading up to a platform"""
	var size_factor: float = arena_size / 140.0

	# Calculate ramp position (extend from platform toward center)
	var direction_to_center: Vector3 = -platform_pos.normalized()
	var ramp_offset: float = platform_size.z / 2.0 + 6.0 * size_factor  # Extend from platform edge
	var ramp_base: Vector3 = platform_pos + direction_to_center * ramp_offset
	ramp_base.y = 0.0  # Start at ground level

	# Ramp size scales with arena
	var ramp_size: Vector3 = Vector3(8.0 * size_factor, 0.5 * size_factor, 14.0 * size_factor)

	# Position at midpoint between ground and platform
	var ramp_height: float = platform_pos.y / 2.0
	var ramp_pos: Vector3 = Vector3(ramp_base.x, ramp_height, ramp_base.z)

	# Check spacing before creating
	if not check_spacing(ramp_pos, ramp_size):
		return

	# Create ramp with smooth geometry
	var ramp_mesh: BoxMesh = create_smooth_box_mesh(ramp_size)

	var ramp_instance: MeshInstance3D = MeshInstance3D.new()
	ramp_instance.mesh = ramp_mesh
	ramp_instance.name = "RampTo" + str(platform_pos)
	ramp_instance.position = ramp_pos

	# Rotate ramp to face center and tilt
	var angle_to_center: float = atan2(-direction_to_center.x, -direction_to_center.z)
	ramp_instance.rotation = Vector3(-0.4, angle_to_center, 0)  # Tilted slope

	add_child(ramp_instance)
	register_geometry(ramp_pos, ramp_size)

	# Add collision
	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = ramp_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	ramp_instance.add_child(static_body)

	platforms.append(ramp_instance)

# ============================================================================
# SIDE ROOMS (Q3 STYLE)
# ============================================================================

func generate_side_rooms() -> void:
	"""Generate enclosed side rooms with openings - Q3 Arena style"""
	# Room count and positions scale with complexity
	var room_distance: float = arena_size * 0.32
	var room_positions: Array = []

	# Generate room positions in a ring around the arena
	for i in range(room_count):
		var angle: float = (float(i) / room_count) * TAU
		var pos: Vector3 = Vector3(
			cos(angle) * room_distance,
			0,
			sin(angle) * room_distance
		)
		room_positions.append(pos)

	for i in range(room_positions.size()):
		var room_pos: Vector3 = room_positions[i]
		generate_room(room_pos, i)

	print("Generated ", room_count, " side rooms")

func generate_room(center_pos: Vector3, room_index: int) -> void:
	"""Generate a single enclosed room with openings"""
	# room_size is set by configure_from_complexity()
	var wall_thickness: float = 1.0

	# Floor with smooth geometry
	var floor_mesh: BoxMesh = create_smooth_box_mesh(Vector3(room_size.x, 1.0, room_size.z))

	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.name = "Room" + str(room_index) + "Floor"
	floor_instance.position = center_pos + Vector3(0, 0.5, 0)
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

	# Ceiling with smooth geometry
	var ceiling_mesh: BoxMesh = create_smooth_box_mesh(Vector3(room_size.x, 1.0, room_size.z))

	var ceiling_instance: MeshInstance3D = MeshInstance3D.new()
	ceiling_instance.mesh = ceiling_mesh
	ceiling_instance.name = "Room" + str(room_index) + "Ceiling"
	ceiling_instance.position = center_pos + Vector3(0, room_size.y, 0)
	add_child(ceiling_instance)

	var ceiling_body: StaticBody3D = StaticBody3D.new()
	var ceiling_collision: CollisionShape3D = CollisionShape3D.new()
	var ceiling_shape: BoxShape3D = BoxShape3D.new()
	ceiling_shape.size = ceiling_mesh.size
	ceiling_collision.shape = ceiling_shape
	ceiling_body.add_child(ceiling_collision)
	ceiling_instance.add_child(ceiling_body)
	platforms.append(ceiling_instance)

	# Walls (4 walls with doorway in one wall facing center)
	generate_room_walls(center_pos, room_size, wall_thickness, room_index)

	# Add raised platform inside room (weapon spawn area)
	generate_room_platform(center_pos, room_index)

func generate_room_walls(center_pos: Vector3, room_size: Vector3, wall_thickness: float, room_index: int) -> void:
	"""Generate walls for a room with one opening facing the center arena"""

	# Determine which wall should have the doorway based on room position
	var has_doorway: Array = [false, false, false, false]  # North, South, East, West

	# Room facing determines doorway position
	if center_pos.x > 0:  # East room - doorway on west wall
		has_doorway[3] = true
	elif center_pos.x < 0:  # West room - doorway on east wall
		has_doorway[2] = true
	elif center_pos.z > 0:  # North room - doorway on south wall
		has_doorway[1] = true
	else:  # South room - doorway on north wall
		has_doorway[0] = true

	var wall_configs: Array = [
		{"pos": Vector3(0, room_size.y/2, room_size.z/2), "size": Vector3(room_size.x, room_size.y, wall_thickness), "name": "North"},
		{"pos": Vector3(0, room_size.y/2, -room_size.z/2), "size": Vector3(room_size.x, room_size.y, wall_thickness), "name": "South"},
		{"pos": Vector3(room_size.x/2, room_size.y/2, 0), "size": Vector3(wall_thickness, room_size.y, room_size.z), "name": "East"},
		{"pos": Vector3(-room_size.x/2, room_size.y/2, 0), "size": Vector3(wall_thickness, room_size.y, room_size.z), "name": "West"}
	]

	for i in range(wall_configs.size()):
		var config: Dictionary = wall_configs[i]

		if has_doorway[i]:
			# Create wall segments with doorway gap
			create_wall_with_doorway(center_pos + config.pos, config.size, config.name, room_index, i)
		else:
			# Create solid wall
			create_solid_wall(center_pos + config.pos, config.size, config.name + str(room_index))

func create_wall_with_doorway(wall_pos: Vector3, wall_size: Vector3, wall_name: String, room_index: int, wall_dir: int) -> void:
	"""Create a wall with a doorway opening in the middle"""
	var doorway_width: float = 6.0

	# For walls aligned on X-axis (North/South walls)
	if wall_dir == 0 or wall_dir == 1:
		# Left segment
		var left_width: float = (wall_size.x - doorway_width) / 2.0
		var left_size: Vector3 = Vector3(left_width, wall_size.y, wall_size.z)
		var left_offset: Vector3 = Vector3(-doorway_width/2 - left_width/2, 0, 0)
		create_solid_wall(wall_pos + left_offset, left_size, wall_name + str(room_index) + "Left")

		# Right segment
		var right_offset: Vector3 = Vector3(doorway_width/2 + left_width/2, 0, 0)
		create_solid_wall(wall_pos + right_offset, left_size, wall_name + str(room_index) + "Right")
	else:
		# For walls aligned on Z-axis (East/West walls)
		var left_depth: float = (wall_size.z - doorway_width) / 2.0
		var left_size: Vector3 = Vector3(wall_size.x, wall_size.y, left_depth)
		var left_offset: Vector3 = Vector3(0, 0, -doorway_width/2 - left_depth/2)
		create_solid_wall(wall_pos + left_offset, left_size, wall_name + str(room_index) + "Left")

		var right_offset: Vector3 = Vector3(0, 0, doorway_width/2 + left_depth/2)
		create_solid_wall(wall_pos + right_offset, left_size, wall_name + str(room_index) + "Right")

func create_solid_wall(pos: Vector3, size: Vector3, wall_name: String) -> void:
	"""Create a solid wall segment"""
	var wall_mesh: BoxMesh = create_smooth_box_mesh(size)

	var wall_instance: MeshInstance3D = MeshInstance3D.new()
	wall_instance.mesh = wall_mesh
	wall_instance.name = "Wall_" + wall_name
	wall_instance.position = pos
	add_child(wall_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = wall_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	wall_instance.add_child(static_body)

	platforms.append(wall_instance)

func generate_room_platform(center_pos: Vector3, room_index: int) -> void:
	"""Generate a raised platform inside the room for item spawns"""
	var platform_mesh: BoxMesh = create_smooth_box_mesh(Vector3(6.0, 1.0, 6.0))

	var platform_instance: MeshInstance3D = MeshInstance3D.new()
	platform_instance.mesh = platform_mesh
	platform_instance.name = "Room" + str(room_index) + "Platform"
	platform_instance.position = center_pos + Vector3(0, 2.5, 0)
	add_child(platform_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = platform_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	platform_instance.add_child(static_body)

	platforms.append(platform_instance)

# ============================================================================
# CORRIDORS
# ============================================================================

func generate_corridors() -> void:
	"""Generate connecting corridors between areas"""
	# Generate corridors to connect rooms to the main arena
	var room_distance: float = arena_size * 0.32
	var corridor_start_distance: float = arena_size * 0.22

	var corridor_configs: Array = []
	for i in range(room_count):
		var angle: float = (float(i) / room_count) * TAU
		var start_pos: Vector3 = Vector3(
			cos(angle) * corridor_start_distance,
			0,
			sin(angle) * corridor_start_distance
		)
		var end_pos: Vector3 = Vector3(
			cos(angle) * room_distance,
			0,
			sin(angle) * room_distance
		)
		corridor_configs.append({"start": start_pos, "end": end_pos, "width": corridor_width})

	for config in corridor_configs:
		create_corridor(config.start, config.end, config.width)

	print("Generated ", corridor_configs.size(), " connecting corridors")

func create_corridor(start_pos: Vector3, end_pos: Vector3, width: float) -> void:
	"""Create a corridor between two points"""
	var direction: Vector3 = (end_pos - start_pos).normalized()
	var length: float = start_pos.distance_to(end_pos)
	var mid_point: Vector3 = (start_pos + end_pos) / 2.0

	# Floor with smooth geometry
	var corridor_mesh: BoxMesh = create_smooth_box_mesh(Vector3(width if abs(direction.x) > 0.5 else length, 1.0, width if abs(direction.z) > 0.5 else length))

	var corridor_instance: MeshInstance3D = MeshInstance3D.new()
	corridor_instance.mesh = corridor_mesh
	corridor_instance.name = "Corridor_" + str(start_pos) + "_to_" + str(end_pos)
	corridor_instance.position = Vector3(mid_point.x, 0.5, mid_point.z)
	add_child(corridor_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = corridor_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	corridor_instance.add_child(static_body)

	platforms.append(corridor_instance)

# ============================================================================
# TUNNELS (Underground passages)
# ============================================================================

func generate_tunnels() -> void:
	"""Generate underground tunnel passages connecting different areas"""
	if tunnel_count <= 0:
		return

	var size_factor: float = arena_size / 140.0
	var tunnel_half_dist: float = arena_size * 0.35

	for i in range(tunnel_count):
		# Create tunnels crossing the arena at different angles
		var angle: float = (float(i) / tunnel_count) * PI + randf() * 0.3
		var start_pos: Vector3 = Vector3(cos(angle) * tunnel_half_dist, -3.0 * size_factor, sin(angle) * tunnel_half_dist)
		var end_pos: Vector3 = Vector3(-cos(angle) * tunnel_half_dist, -3.0 * size_factor, -sin(angle) * tunnel_half_dist)

		create_tunnel(start_pos, end_pos, i)

	print("Generated ", tunnel_count, " tunnels")

func create_tunnel(start_pos: Vector3, end_pos: Vector3, index: int) -> void:
	"""Create an underground tunnel with entrance/exit slopes"""
	var size_factor: float = arena_size / 140.0
	var direction: Vector3 = (end_pos - start_pos).normalized()
	var length: float = start_pos.distance_to(end_pos)
	var mid_point: Vector3 = (start_pos + end_pos) / 2.0

	var tunnel_width: float = 10.0 * size_factor
	var tunnel_height: float = 6.0 * size_factor

	# Main tunnel floor
	var floor_size: Vector3 = Vector3(tunnel_width, 1.0 * size_factor, length)
	var floor_mesh: BoxMesh = create_smooth_box_mesh(floor_size)
	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.name = "TunnelFloor" + str(index)
	floor_instance.position = mid_point
	floor_instance.rotation.y = atan2(direction.x, direction.z)
	add_child(floor_instance)
	add_collision_to_mesh(floor_instance, floor_size)
	platforms.append(floor_instance)

	# Tunnel ceiling
	var ceiling_pos: Vector3 = mid_point + Vector3(0, tunnel_height, 0)
	var ceiling_mesh: BoxMesh = create_smooth_box_mesh(floor_size)
	var ceiling_instance: MeshInstance3D = MeshInstance3D.new()
	ceiling_instance.mesh = ceiling_mesh
	ceiling_instance.name = "TunnelCeiling" + str(index)
	ceiling_instance.position = ceiling_pos
	ceiling_instance.rotation.y = atan2(direction.x, direction.z)
	add_child(ceiling_instance)
	add_collision_to_mesh(ceiling_instance, floor_size)
	platforms.append(ceiling_instance)

	# Entrance slope (ramp down into tunnel)
	create_tunnel_entrance(start_pos, direction, index, "Start", size_factor)
	create_tunnel_entrance(end_pos, -direction, index, "End", size_factor)

func create_tunnel_entrance(pos: Vector3, dir: Vector3, index: int, suffix: String, size_factor: float) -> void:
	"""Create a sloped entrance into a tunnel"""
	var ramp_length: float = 12.0 * size_factor
	var ramp_width: float = 10.0 * size_factor
	var ramp_pos: Vector3 = pos + dir * (ramp_length * 0.5) + Vector3(0, pos.y * 0.5 + 1.5 * size_factor, 0)

	var ramp_size: Vector3 = Vector3(ramp_width, 1.0 * size_factor, ramp_length)
	var ramp_mesh: BoxMesh = create_smooth_box_mesh(ramp_size)
	var ramp_instance: MeshInstance3D = MeshInstance3D.new()
	ramp_instance.mesh = ramp_mesh
	ramp_instance.name = "TunnelRamp" + str(index) + suffix
	ramp_instance.position = ramp_pos

	# Angle the ramp
	var angle_y: float = atan2(dir.x, dir.z)
	ramp_instance.rotation = Vector3(0.35, angle_y, 0)  # Slope down

	add_child(ramp_instance)
	add_collision_to_mesh(ramp_instance, ramp_size)
	platforms.append(ramp_instance)

func add_collision_to_mesh(mesh_instance: MeshInstance3D, size: Vector3) -> void:
	"""Helper to add collision to a mesh instance"""
	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	static_body.add_child(collision)
	mesh_instance.add_child(static_body)

# ============================================================================
# CATWALKS (Elevated pathways)
# ============================================================================

func generate_catwalks() -> void:
	"""Generate elevated catwalk pathways connecting platforms"""
	if catwalk_count <= 0:
		return

	var size_factor: float = arena_size / 140.0
	var catwalk_distance: float = arena_size * 0.25

	for i in range(catwalk_count):
		var angle: float = (float(i) / catwalk_count) * TAU
		var height: float = (8.0 + (i % 3) * 5.0) * size_factor  # Varied heights

		# Catwalks go from one side to the other at various angles
		var start_angle: float = angle
		var end_angle: float = angle + PI * 0.6 + randf() * 0.4

		var start_pos: Vector3 = Vector3(
			cos(start_angle) * catwalk_distance,
			height,
			sin(start_angle) * catwalk_distance
		)
		var end_pos: Vector3 = Vector3(
			cos(end_angle) * catwalk_distance,
			height,
			sin(end_angle) * catwalk_distance
		)

		create_catwalk(start_pos, end_pos, i)

	print("Generated ", catwalk_count, " catwalks")

func create_catwalk(start_pos: Vector3, end_pos: Vector3, index: int) -> void:
	"""Create an elevated catwalk pathway"""
	var size_factor: float = arena_size / 140.0
	var direction: Vector3 = (end_pos - start_pos).normalized()
	var length: float = start_pos.distance_to(end_pos)
	var mid_point: Vector3 = (start_pos + end_pos) / 2.0

	var catwalk_width: float = 5.0 * size_factor
	var catwalk_thickness: float = 0.8 * size_factor

	# Check spacing
	var catwalk_size: Vector3 = Vector3(catwalk_width, catwalk_thickness, length)
	if not check_spacing(mid_point, catwalk_size):
		return

	# Main catwalk walkway
	var walkway_mesh: BoxMesh = create_smooth_box_mesh(catwalk_size)
	var walkway_instance: MeshInstance3D = MeshInstance3D.new()
	walkway_instance.mesh = walkway_mesh
	walkway_instance.name = "Catwalk" + str(index)
	walkway_instance.position = mid_point
	walkway_instance.rotation.y = atan2(direction.x, direction.z)
	add_child(walkway_instance)
	add_collision_to_mesh(walkway_instance, catwalk_size)
	platforms.append(walkway_instance)
	register_geometry(mid_point, catwalk_size)

	# Add support pillars at each end
	create_catwalk_support(start_pos, index, "Start", size_factor)
	create_catwalk_support(end_pos, index, "End", size_factor)

	# Add access ramps at each end
	create_catwalk_ramp(start_pos, direction, index, "Start", size_factor)
	create_catwalk_ramp(end_pos, -direction, index, "End", size_factor)

func create_catwalk_support(pos: Vector3, index: int, suffix: String, size_factor: float) -> void:
	"""Create a support pillar for a catwalk"""
	var pillar_width: float = 2.0 * size_factor
	var pillar_height: float = pos.y
	var pillar_size: Vector3 = Vector3(pillar_width, pillar_height, pillar_width)
	var pillar_pos: Vector3 = Vector3(pos.x, pillar_height / 2.0, pos.z)

	if not check_spacing(pillar_pos, pillar_size):
		return

	var pillar_mesh: BoxMesh = create_smooth_box_mesh(pillar_size)
	var pillar_instance: MeshInstance3D = MeshInstance3D.new()
	pillar_instance.mesh = pillar_mesh
	pillar_instance.name = "CatwalkSupport" + str(index) + suffix
	pillar_instance.position = pillar_pos
	add_child(pillar_instance)
	add_collision_to_mesh(pillar_instance, pillar_size)
	platforms.append(pillar_instance)
	register_geometry(pillar_pos, pillar_size)

func create_catwalk_ramp(pos: Vector3, dir: Vector3, index: int, suffix: String, size_factor: float) -> void:
	"""Create an access ramp to a catwalk"""
	var ramp_length: float = pos.y * 1.5  # Gentle slope
	var ramp_width: float = 5.0 * size_factor
	var ramp_pos: Vector3 = pos + dir * (ramp_length * 0.5) - Vector3(0, pos.y * 0.5, 0)

	var ramp_size: Vector3 = Vector3(ramp_width, 0.8 * size_factor, ramp_length)

	# Check spacing
	if not check_spacing(ramp_pos, ramp_size * 1.2):
		return

	var ramp_mesh: BoxMesh = create_smooth_box_mesh(ramp_size)
	var ramp_instance: MeshInstance3D = MeshInstance3D.new()
	ramp_instance.mesh = ramp_mesh
	ramp_instance.name = "CatwalkRamp" + str(index) + suffix
	ramp_instance.position = ramp_pos

	# Slope angle based on height
	var slope_angle: float = atan2(pos.y, ramp_length)
	var angle_y: float = atan2(dir.x, dir.z)
	ramp_instance.rotation = Vector3(-slope_angle, angle_y, 0)

	add_child(ramp_instance)
	add_collision_to_mesh(ramp_instance, ramp_size)
	platforms.append(ramp_instance)
	register_geometry(ramp_pos, ramp_size)

# ============================================================================
# JUMP PADS
# ============================================================================

func generate_jump_pads() -> void:
	"""Generate jump pads for quick vertical movement"""
	var jump_pad_positions: Array = []
	var pad_ring_distance: float = arena_size * 0.22

	# Always add center jump pad
	jump_pad_positions.append(Vector3(0, 0, 0))

	# Add jump pads in a ring pattern
	var ring_pad_count: int = jump_pad_count - 1
	for i in range(ring_pad_count):
		var angle: float = (float(i) / ring_pad_count) * TAU
		var pos: Vector3 = Vector3(
			cos(angle) * pad_ring_distance,
			0,
			sin(angle) * pad_ring_distance
		)
		jump_pad_positions.append(pos)

	for i in range(jump_pad_positions.size()):
		var pos: Vector3 = jump_pad_positions[i]
		create_jump_pad(pos, i)

	print("Generated ", jump_pad_positions.size(), " jump pads")

func create_jump_pad(pos: Vector3, index: int) -> void:
	"""Create a jump pad (visual platform + Area3D for boost)"""

	# Visual platform
	var pad_mesh: CylinderMesh = CylinderMesh.new()
	pad_mesh.top_radius = 2.5
	pad_mesh.bottom_radius = 2.5
	pad_mesh.height = 0.5

	var pad_instance: MeshInstance3D = MeshInstance3D.new()
	pad_instance.mesh = pad_mesh
	pad_instance.name = "JumpPad" + str(index)
	pad_instance.position = Vector3(pos.x, 0.25, pos.z)
	add_child(pad_instance)

	# Material for jump pad (bright green - unshaded for GL Compatibility)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 1.0, 0.4)  # Bright green
	# Use UNSHADED mode to bypass lighting issues in GL Compatibility mode
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	pad_instance.material_override = material

	# Add collision to jump pad so players can stand on it
	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var collision_shape: CylinderShape3D = CylinderShape3D.new()
	collision_shape.radius = 2.5
	collision_shape.height = 0.5
	collision.shape = collision_shape
	static_body.add_child(collision)
	pad_instance.add_child(static_body)

	# Area3D for jump boost detection
	var jump_area: Area3D = Area3D.new()
	jump_area.name = "JumpPadArea"
	jump_area.position = Vector3.ZERO
	jump_area.add_to_group("jump_pad")
	pad_instance.add_child(jump_area)

	# Set collision layers - Layer 8 for pickups/areas
	jump_area.collision_layer = 8
	jump_area.collision_mask = 0  # Don't detect anything
	jump_area.monitorable = true  # Allow players to detect us
	jump_area.monitoring = false  # We don't need to detect

	var area_collision: CollisionShape3D = CollisionShape3D.new()
	var area_shape: CylinderShape3D = CylinderShape3D.new()
	area_shape.radius = 2.5
	area_shape.height = 3.0  # Taller to catch jumping players
	area_collision.shape = area_shape
	jump_area.add_child(area_collision)

	# Don't add to platforms array - jump pads need to keep their custom material

# ============================================================================
# TELEPORTERS
# ============================================================================

func generate_teleporters() -> void:
	"""Generate teleporter pairs for quick arena traversal"""
	var teleporter_pairs: Array = []
	var teleporter_distance: float = arena_size * 0.25

	# Generate teleporter pairs at opposite corners
	for i in range(teleporter_pair_count):
		var angle: float = (float(i) / teleporter_pair_count) * PI  # Half circle
		var from_pos: Vector3 = Vector3(
			cos(angle) * teleporter_distance,
			0,
			sin(angle) * teleporter_distance
		)
		var to_pos: Vector3 = Vector3(
			-cos(angle) * teleporter_distance,
			0,
			-sin(angle) * teleporter_distance
		)
		teleporter_pairs.append({"from": from_pos, "to": to_pos})

	for i in range(teleporter_pairs.size()):
		var pair: Dictionary = teleporter_pairs[i]
		create_teleporter_pair(pair.from, pair.to, i)

	print("Generated ", teleporter_pairs.size(), " teleporter pairs")

func create_teleporter_pair(from_pos: Vector3, to_pos: Vector3, pair_index: int) -> void:
	"""Create a bidirectional teleporter pair"""
	create_teleporter(from_pos, to_pos, pair_index * 2)
	create_teleporter(to_pos, from_pos, pair_index * 2 + 1)

func create_teleporter(pos: Vector3, destination: Vector3, index: int) -> void:
	"""Create a single teleporter"""

	# Visual platform
	var teleporter_mesh: CylinderMesh = CylinderMesh.new()
	teleporter_mesh.top_radius = 3.0
	teleporter_mesh.bottom_radius = 3.0
	teleporter_mesh.height = 0.3

	var teleporter_instance: MeshInstance3D = MeshInstance3D.new()
	teleporter_instance.mesh = teleporter_mesh
	teleporter_instance.name = "Teleporter" + str(index)
	teleporter_instance.position = Vector3(pos.x, 0.15, pos.z)
	add_child(teleporter_instance)

	# Material for teleporter (blue/purple - unshaded for GL Compatibility)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.4, 1.0)  # Blue-purple
	# Use UNSHADED mode to bypass lighting issues in GL Compatibility mode
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	teleporter_instance.material_override = material

	# Add collision to teleporter so players can stand on it
	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var collision_shape: CylinderShape3D = CylinderShape3D.new()
	collision_shape.radius = 3.0
	collision_shape.height = 0.3
	collision.shape = collision_shape
	static_body.add_child(collision)
	teleporter_instance.add_child(static_body)

	# Area3D for teleportation
	var teleport_area: Area3D = Area3D.new()
	teleport_area.name = "TeleportArea"
	teleport_area.position = Vector3.ZERO
	teleport_area.add_to_group("teleporter")
	teleport_area.set_meta("destination", destination)
	teleporter_instance.add_child(teleport_area)

	# Set collision layers - Layer 8 for pickups/areas
	teleport_area.collision_layer = 8
	teleport_area.collision_mask = 0  # Don't detect anything
	teleport_area.monitorable = true  # Allow players to detect us
	teleport_area.monitoring = false  # We don't need to detect

	var area_collision: CollisionShape3D = CollisionShape3D.new()
	var area_shape: CylinderShape3D = CylinderShape3D.new()
	area_shape.radius = 3.0
	area_shape.height = 5.0  # Tall enough to catch players reliably
	area_collision.shape = area_shape
	teleport_area.add_child(area_collision)

	# Don't add to platforms array - teleporters need to keep their custom material
	teleporters.append({"area": teleport_area, "destination": destination})

# ============================================================================
# PERIMETER WALLS
# ============================================================================

func generate_perimeter_walls() -> void:
	"""Generate outer perimeter walls"""
	var wall_distance: float = arena_size * 0.55
	# wall_height is set by configure_from_complexity()
	var wall_thickness: float = 2.0

	var wall_configs: Array = [
		{"pos": Vector3(0, wall_height/2, wall_distance), "size": Vector3(arena_size * 1.2, wall_height, wall_thickness)},
		{"pos": Vector3(0, wall_height/2, -wall_distance), "size": Vector3(arena_size * 1.2, wall_height, wall_thickness)},
		{"pos": Vector3(wall_distance, wall_height/2, 0), "size": Vector3(wall_thickness, wall_height, arena_size * 1.2)},
		{"pos": Vector3(-wall_distance, wall_height/2, 0), "size": Vector3(wall_thickness, wall_height, arena_size * 1.2)}
	]

	for i in range(wall_configs.size()):
		var config: Dictionary = wall_configs[i]

		var wall_mesh: BoxMesh = create_smooth_box_mesh(config.size)

		var wall_instance: MeshInstance3D = MeshInstance3D.new()
		wall_instance.mesh = wall_mesh
		wall_instance.name = "PerimeterWall" + str(i)
		wall_instance.position = config.pos
		add_child(wall_instance)

		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = wall_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		wall_instance.add_child(static_body)

		platforms.append(wall_instance)

	print("Generated perimeter walls")

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
# SPAWN POINTS
# ============================================================================

func get_spawn_points() -> PackedVector3Array:
	"""Generate spawn points throughout the arena - supports up to 8 players total (16+ spawn points available)"""
	var spawns: PackedVector3Array = PackedVector3Array()

	# Main arena spawns
	spawns.append(Vector3(0, 2, 0))
	spawns.append(Vector3(15, 2, 0))
	spawns.append(Vector3(-15, 2, 0))
	spawns.append(Vector3(0, 2, 15))
	spawns.append(Vector3(0, 2, -15))

	# Room spawns
	spawns.append(Vector3(45, 3, 0))   # East room
	spawns.append(Vector3(-45, 3, 0))  # West room
	spawns.append(Vector3(0, 3, 45))   # North room
	spawns.append(Vector3(0, 3, -45))  # South room

	# Platform spawns (tier 1)
	for i in range(4):
		var angle: float = (float(i) / 4) * TAU
		var x: float = cos(angle) * 25.0
		var z: float = sin(angle) * 25.0
		spawns.append(Vector3(x, 10, z))

	# Upper platform spawns (tier 2)
	for i in range(3):
		var angle: float = (float(i) / 3) * TAU
		var x: float = cos(angle) * 20.0
		var z: float = sin(angle) * 20.0
		spawns.append(Vector3(x, 17, z))

	return spawns

# ============================================================================
# PROCEDURAL TEXTURES
# ============================================================================

func apply_procedural_textures() -> void:
	"""Apply procedurally generated textures to all platforms"""
	material_manager.apply_materials_to_level(self)
