extends Node3D

## Quake 3 Arena-Style Level Generator (Type B)
## Creates multi-tiered arenas with complex geometry, rooms, corridors, and vertical gameplay
## Features: rooms, corridors, jump pads, teleporters, catwalks, and tunnels

# ============================================================================
# EXPORTED PARAMETERS
# ============================================================================

@export var level_seed: int = 0
@export var arena_size: float = 140.0  # Base arena size (scaled by size setting)
@export var complexity: int = 2  # 1=Low, 2=Medium, 3=High, 4=Extreme

# Calculated counts (set by configure_for_complexity)
var room_count: int = 4
var corridor_width: float = 6.0
var tier1_platform_count: int = 4
var tier2_platform_count: int = 6
var tier3_platform_count: int = 4
var pillar_count: int = 4
var cover_count: int = 8
var jump_pad_count: int = 5
var teleporter_pair_count: int = 2

# Internal parameters
var min_interactive_spacing: float = 8.0  # Minimum gap for interactive objects only

var noise: FastNoiseLite
var platforms: Array = []
var teleporters: Array = []
var interactive_positions: Array[Dictionary] = []  # Track jump pads and teleporters
var material_manager = preload("res://scripts/procedural_material_manager.gd").new()

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	configure_for_complexity()
	generate_level()

func configure_for_complexity() -> void:
	"""Configure all parameters based on complexity and arena size.
	Complexity affects density, variety, and advanced features.
	Larger arenas need more geometry to fill the space."""

	# Calculate arena scale factor
	var scale_factor: float = arena_size / 140.0
	var area_multiplier: float = scale_factor * scale_factor

	# Clamp complexity
	var c: int = clampi(complexity, 1, 4)

	# Room and corridor configuration
	room_count = [2, 4, 6, 8][c - 1]  # 2, 4, 6, 8 rooms
	corridor_width = [8.0, 6.0, 5.0, 4.0][c - 1]  # Narrower at high complexity

	# Platform tiers (scaled by area)
	tier1_platform_count = int([2, 4, 6, 8][c - 1] * sqrt(area_multiplier))
	tier2_platform_count = int([4, 6, 8, 12][c - 1] * sqrt(area_multiplier))
	tier3_platform_count = int([2, 4, 6, 8][c - 1] * sqrt(area_multiplier))

	# Arena features
	pillar_count = int([2, 4, 6, 8][c - 1] * sqrt(area_multiplier))
	cover_count = int([4, 8, 12, 16][c - 1] * area_multiplier)

	# Interactive objects (scaled less aggressively)
	jump_pad_count = int([3, 5, 7, 9][c - 1] * sqrt(scale_factor))
	teleporter_pair_count = int([1, 2, 3, 4][c - 1] * sqrt(scale_factor))

	if OS.is_debug_build():
		print("Q3 Level configured - Complexity: %d, Arena Size: %.1f, Scale: %.2f" % [c, arena_size, scale_factor])
		print("  Rooms: %d, Tiers: %d/%d/%d, Pillars: %d, Cover: %d" % [room_count, tier1_platform_count, tier2_platform_count, tier3_platform_count, pillar_count, cover_count])
		print("  Jump Pads: %d, Teleporter Pairs: %d" % [jump_pad_count, teleporter_pair_count])

# ============================================================================
# LEVEL GENERATION
# ============================================================================

func generate_level() -> void:
	"""Generate a complete Quake 3 Arena-style level"""
	if OS.is_debug_build():
		print("Generating Quake 3 Arena-style level with seed: ", level_seed)

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

	# Generate complexity-based advanced features
	if complexity >= 3:
		generate_catwalks()
	if complexity >= 4:
		generate_tunnels()

	# Generate interactive objects (with spacing checks)
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
	interactive_positions.clear()

# ============================================================================
# SPACING CHECKS (Only for interactive objects)
# ============================================================================

func check_interactive_spacing(new_pos: Vector3, new_radius: float) -> bool:
	"""Check if an interactive object has proper spacing from others.
	Only used for jump pads, teleporters - NOT for geometry."""

	for existing in interactive_positions:
		var existing_pos: Vector3 = existing.position
		var existing_radius: float = existing.radius
		var distance: float = new_pos.distance_to(existing_pos)
		var min_dist: float = new_radius + existing_radius + min_interactive_spacing

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
	"""Generate decorative pillars - count and height scale with complexity"""
	var floor_radius: float = (arena_size * 0.6) / 2.0
	var pillar_dist: float = floor_radius * 0.5

	# Pillar height increases with complexity
	var pillar_height: float = 8.0 + complexity * 2.0  # 10, 12, 14, 16

	for i in range(pillar_count):
		var angle: float = (float(i) / pillar_count) * TAU
		var x: float = cos(angle) * pillar_dist
		var z: float = sin(angle) * pillar_dist

		# Create tall pillar with smooth geometry
		var pillar_size: Vector3 = Vector3(3.0 + complexity * 0.5, pillar_height, 3.0 + complexity * 0.5)
		var pillar_mesh: BoxMesh = create_smooth_box_mesh(pillar_size)

		var pillar_instance: MeshInstance3D = MeshInstance3D.new()
		pillar_instance.mesh = pillar_mesh
		pillar_instance.name = "Pillar" + str(i)
		pillar_instance.position = Vector3(x, pillar_height / 2.0, z)
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

func generate_cover_objects() -> void:
	"""Generate small cover boxes scattered in the arena"""
	var floor_radius: float = (arena_size * 0.6) / 2.0

	for i in range(cover_count):
		var angle: float = (float(i) / cover_count) * TAU + randf() * 0.5
		var distance: float = randf_range(10.0, floor_radius - 5.0)

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance

		# Cover size varies with complexity
		var cover_width: float = 2.0 + randf() * (1.0 + complexity * 0.5)
		var cover_height: float = 1.5 + randf() * (0.5 + complexity * 0.3)
		var cover_depth: float = 2.0 + randf() * (1.0 + complexity * 0.5)

		var cover_mesh: BoxMesh = create_smooth_box_mesh(Vector3(cover_width, cover_height, cover_depth))

		var cover_instance: MeshInstance3D = MeshInstance3D.new()
		cover_instance.mesh = cover_mesh
		cover_instance.name = "Cover" + str(i)
		cover_instance.position = Vector3(x, cover_height / 2.0, z)
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

# ============================================================================
# UPPER PLATFORMS (MULTI-TIER DESIGN)
# ============================================================================

func generate_upper_platforms() -> void:
	"""Generate multiple tiers of platforms for vertical gameplay"""
	var base_distance: float = arena_size * 0.18

	# Tier heights scale with complexity
	var tier1_height: float = 6.0 + complexity * 1.0
	var tier2_height: float = 12.0 + complexity * 2.0
	var tier3_height: float = 18.0 + complexity * 3.0

	# Tier 1: Mid-level ring platforms
	generate_tier_platforms(1, tier1_platform_count, tier1_height, base_distance)

	# Tier 2: Upper-level platforms
	generate_tier_platforms(2, tier2_platform_count, tier2_height, base_distance * 0.8)

	# Tier 3: Highest sniper platforms
	generate_tier_platforms(3, tier3_platform_count, tier3_height, base_distance * 0.6)

	print("Generated multi-tier platform system (heights: %.0f/%.0f/%.0f)" % [tier1_height, tier2_height, tier3_height])

func generate_tier_platforms(tier: int, count: int, height: float, distance_from_center: float) -> void:
	"""Generate a ring of platforms at a specific tier level"""

	for i in range(count):
		var angle: float = (float(i) / count) * TAU
		var x: float = cos(angle) * distance_from_center
		var z: float = sin(angle) * distance_from_center

		# Platform size varies by tier and complexity
		var base_size: float = [10.0, 7.0, 5.0][tier - 1]
		var size_mod: float = 1.0 + complexity * 0.1
		var platform_size: Vector3 = Vector3(
			base_size * size_mod + randf() * 2.0,
			1.2 + complexity * 0.2,
			base_size * size_mod + randf() * 2.0
		)

		# Create platform with smooth geometry
		var platform_mesh: BoxMesh = create_smooth_box_mesh(platform_size)

		var platform_instance: MeshInstance3D = MeshInstance3D.new()
		platform_instance.mesh = platform_mesh
		platform_instance.name = "Tier" + str(tier) + "Platform" + str(i)
		platform_instance.position = Vector3(x, height, z)
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

		# Add connecting SLOPES (not stairs) to tier 1 platforms
		if tier == 1 and i % 2 == 0:
			generate_slope_to_platform(Vector3(x, height, z), platform_size)

func generate_slope_to_platform(platform_pos: Vector3, platform_size: Vector3) -> void:
	"""Generate a slope leading up to a platform (slopes work better for marbles than stairs)"""

	# Calculate slope position (extend from platform toward center)
	var direction_to_center: Vector3 = -platform_pos.normalized()
	var slope_offset: float = platform_size.z / 2.0 + 5.0
	var slope_base: Vector3 = platform_pos + direction_to_center * slope_offset
	slope_base.y = 0.0

	# Create slope with smooth geometry
	var slope_length: float = 12.0 + complexity * 2.0
	var slope_width: float = 6.0 + complexity
	var slope_mesh: BoxMesh = create_smooth_box_mesh(Vector3(slope_width, 0.5, slope_length))

	var slope_instance: MeshInstance3D = MeshInstance3D.new()
	slope_instance.mesh = slope_mesh
	slope_instance.name = "SlopeTo" + str(platform_pos)

	# Position at midpoint between ground and platform
	var slope_height: float = platform_pos.y / 2.0
	slope_instance.position = Vector3(slope_base.x, slope_height, slope_base.z)

	# Rotate slope to face center and tilt
	var angle_to_center: float = atan2(-direction_to_center.x, -direction_to_center.z)
	var tilt_angle: float = atan2(platform_pos.y, slope_length) * 0.8  # Gentle slope
	slope_instance.rotation = Vector3(-tilt_angle, angle_to_center, 0)

	add_child(slope_instance)

	# Add collision
	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = slope_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	slope_instance.add_child(static_body)

	platforms.append(slope_instance)

# ============================================================================
# SIDE ROOMS (Q3 STYLE)
# ============================================================================

func generate_side_rooms() -> void:
	"""Generate enclosed side rooms with openings - Q3 Arena style"""
	var room_distance: float = arena_size * 0.32

	for i in range(room_count):
		var angle: float = (float(i) / room_count) * TAU
		var x: float = cos(angle) * room_distance
		var z: float = sin(angle) * room_distance
		var room_pos: Vector3 = Vector3(x, 0, z)

		generate_room(room_pos, i)

	print("Generated %d side rooms" % room_count)

func generate_room(center_pos: Vector3, room_index: int) -> void:
	"""Generate a single enclosed room with openings"""
	# Room size scales with complexity
	var room_width: float = 12.0 + complexity * 2.0
	var room_height: float = 8.0 + complexity * 1.5
	var room_depth: float = 12.0 + complexity * 2.0
	var room_size: Vector3 = Vector3(room_width, room_height, room_depth)
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

	# Walls with doorway facing center
	generate_room_walls(center_pos, room_size, wall_thickness, room_index)

	# Add raised platform inside room (weapon spawn area)
	generate_room_platform(center_pos, room_index)

func generate_room_walls(center_pos: Vector3, room_size: Vector3, wall_thickness: float, room_index: int) -> void:
	"""Generate walls for a room with one opening facing the center arena"""

	# Determine which wall should have the doorway based on room position
	var angle_to_center: float = atan2(-center_pos.z, -center_pos.x)
	var doorway_wall: int = -1

	# Simplified: doorway on wall closest to center
	if abs(center_pos.x) > abs(center_pos.z):
		doorway_wall = 2 if center_pos.x > 0 else 3  # East or West
	else:
		doorway_wall = 0 if center_pos.z > 0 else 1  # North or South

	var wall_configs: Array = [
		{"pos": Vector3(0, room_size.y/2, room_size.z/2), "size": Vector3(room_size.x, room_size.y, wall_thickness), "name": "North", "axis": "x"},
		{"pos": Vector3(0, room_size.y/2, -room_size.z/2), "size": Vector3(room_size.x, room_size.y, wall_thickness), "name": "South", "axis": "x"},
		{"pos": Vector3(room_size.x/2, room_size.y/2, 0), "size": Vector3(wall_thickness, room_size.y, room_size.z), "name": "East", "axis": "z"},
		{"pos": Vector3(-room_size.x/2, room_size.y/2, 0), "size": Vector3(wall_thickness, room_size.y, room_size.z), "name": "West", "axis": "z"}
	]

	for i in range(wall_configs.size()):
		var config: Dictionary = wall_configs[i]

		if i == doorway_wall:
			# Create wall segments with doorway gap
			create_wall_with_doorway(center_pos + config.pos, config.size, config.name, room_index, config.axis)
		else:
			# Create solid wall
			create_solid_wall(center_pos + config.pos, config.size, config.name + str(room_index))

func create_wall_with_doorway(wall_pos: Vector3, wall_size: Vector3, wall_name: String, room_index: int, axis: String) -> void:
	"""Create a wall with a doorway opening in the middle"""
	var doorway_width: float = 5.0 + complexity * 0.5  # Wider at higher complexity

	if axis == "x":
		# North/South walls
		var segment_width: float = (wall_size.x - doorway_width) / 2.0
		var segment_size: Vector3 = Vector3(segment_width, wall_size.y, wall_size.z)

		# Left segment
		var left_offset: Vector3 = Vector3(-doorway_width/2 - segment_width/2, 0, 0)
		create_solid_wall(wall_pos + left_offset, segment_size, wall_name + str(room_index) + "Left")

		# Right segment
		var right_offset: Vector3 = Vector3(doorway_width/2 + segment_width/2, 0, 0)
		create_solid_wall(wall_pos + right_offset, segment_size, wall_name + str(room_index) + "Right")
	else:
		# East/West walls
		var segment_depth: float = (wall_size.z - doorway_width) / 2.0
		var segment_size: Vector3 = Vector3(wall_size.x, wall_size.y, segment_depth)

		# Front segment
		var front_offset: Vector3 = Vector3(0, 0, -doorway_width/2 - segment_depth/2)
		create_solid_wall(wall_pos + front_offset, segment_size, wall_name + str(room_index) + "Front")

		# Back segment
		var back_offset: Vector3 = Vector3(0, 0, doorway_width/2 + segment_depth/2)
		create_solid_wall(wall_pos + back_offset, segment_size, wall_name + str(room_index) + "Back")

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
	var platform_size: float = 4.0 + complexity
	var platform_mesh: BoxMesh = create_smooth_box_mesh(Vector3(platform_size, 1.0, platform_size))

	var platform_instance: MeshInstance3D = MeshInstance3D.new()
	platform_instance.mesh = platform_mesh
	platform_instance.name = "Room" + str(room_index) + "Platform"
	platform_instance.position = center_pos + Vector3(0, 2.0 + complexity * 0.3, 0)
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
	"""Generate connecting corridors between main arena and rooms"""
	var main_floor_edge: float = (arena_size * 0.6) / 2.0
	var room_distance: float = arena_size * 0.32

	for i in range(room_count):
		var angle: float = (float(i) / room_count) * TAU

		# Start from main floor edge
		var start_x: float = cos(angle) * main_floor_edge
		var start_z: float = sin(angle) * main_floor_edge

		# End at room
		var end_x: float = cos(angle) * room_distance
		var end_z: float = sin(angle) * room_distance

		create_corridor(Vector3(start_x, 0, start_z), Vector3(end_x, 0, end_z))

	print("Generated %d connecting corridors" % room_count)

func create_corridor(start_pos: Vector3, end_pos: Vector3) -> void:
	"""Create a corridor between two points"""
	var direction: Vector3 = (end_pos - start_pos).normalized()
	var length: float = start_pos.distance_to(end_pos)
	var mid_point: Vector3 = (start_pos + end_pos) / 2.0

	# Determine corridor orientation
	var is_x_aligned: bool = abs(direction.x) > abs(direction.z)

	var corridor_size: Vector3
	if is_x_aligned:
		corridor_size = Vector3(length, 1.0, corridor_width)
	else:
		corridor_size = Vector3(corridor_width, 1.0, length)

	var corridor_mesh: BoxMesh = create_smooth_box_mesh(corridor_size)

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
# CATWALKS (High Complexity Feature)
# ============================================================================

func generate_catwalks() -> void:
	"""Generate elevated catwalks connecting platforms (complexity 3+)"""
	var catwalk_count: int = 2 + complexity
	var catwalk_height: float = 10.0 + complexity * 2.0

	for i in range(catwalk_count):
		var angle_start: float = (float(i) / catwalk_count) * TAU
		var angle_end: float = angle_start + PI / catwalk_count

		var start_dist: float = arena_size * 0.15
		var end_dist: float = arena_size * 0.25

		var start_pos: Vector3 = Vector3(
			cos(angle_start) * start_dist,
			catwalk_height,
			sin(angle_start) * start_dist
		)
		var end_pos: Vector3 = Vector3(
			cos(angle_end) * end_dist,
			catwalk_height + randf() * 3.0,
			sin(angle_end) * end_dist
		)

		create_catwalk(start_pos, end_pos, i)

	print("Generated %d catwalks at height %.1f" % [catwalk_count, catwalk_height])

func create_catwalk(start_pos: Vector3, end_pos: Vector3, index: int) -> void:
	"""Create a narrow catwalk between two points"""
	var direction: Vector3 = (end_pos - start_pos)
	var length: float = direction.length()
	var mid_point: Vector3 = (start_pos + end_pos) / 2.0

	# Narrow catwalk
	var catwalk_width: float = 2.0 + complexity * 0.3
	var catwalk_mesh: BoxMesh = create_smooth_box_mesh(Vector3(catwalk_width, 0.5, length))

	var catwalk_instance: MeshInstance3D = MeshInstance3D.new()
	catwalk_instance.mesh = catwalk_mesh
	catwalk_instance.name = "Catwalk" + str(index)
	catwalk_instance.position = mid_point

	# Rotate to align with direction
	var angle: float = atan2(direction.x, direction.z)
	catwalk_instance.rotation.y = angle

	# Slight tilt if heights differ
	if abs(end_pos.y - start_pos.y) > 0.1:
		var tilt: float = atan2(end_pos.y - start_pos.y, length)
		catwalk_instance.rotation.x = -tilt

	add_child(catwalk_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = catwalk_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	catwalk_instance.add_child(static_body)

	platforms.append(catwalk_instance)

# ============================================================================
# TUNNELS (Extreme Complexity Feature)
# ============================================================================

func generate_tunnels() -> void:
	"""Generate underground tunnels (complexity 4 only)"""
	var tunnel_count: int = complexity - 2  # 2 tunnels at complexity 4
	var tunnel_depth: float = -4.0

	for i in range(tunnel_count):
		var angle: float = (float(i) / tunnel_count) * TAU + PI / 4

		var start_pos: Vector3 = Vector3(
			cos(angle) * arena_size * 0.1,
			tunnel_depth,
			sin(angle) * arena_size * 0.1
		)
		var end_pos: Vector3 = Vector3(
			cos(angle + PI) * arena_size * 0.1,
			tunnel_depth,
			sin(angle + PI) * arena_size * 0.1
		)

		create_tunnel(start_pos, end_pos, i)

		# Add slope entrances
		create_tunnel_entrance(start_pos, i * 2)
		create_tunnel_entrance(end_pos, i * 2 + 1)

	print("Generated %d underground tunnels" % tunnel_count)

func create_tunnel(start_pos: Vector3, end_pos: Vector3, index: int) -> void:
	"""Create an underground tunnel"""
	var direction: Vector3 = (end_pos - start_pos)
	var length: float = direction.length()
	var mid_point: Vector3 = (start_pos + end_pos) / 2.0

	var tunnel_width: float = 6.0
	var tunnel_height: float = 4.0

	# Floor
	var floor_mesh: BoxMesh = create_smooth_box_mesh(Vector3(tunnel_width, 1.0, length))
	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.name = "Tunnel" + str(index) + "Floor"
	floor_instance.position = mid_point + Vector3(0, -tunnel_height / 2.0, 0)
	floor_instance.rotation.y = atan2(direction.x, direction.z)
	add_child(floor_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = floor_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	floor_instance.add_child(static_body)

	platforms.append(floor_instance)

func create_tunnel_entrance(tunnel_pos: Vector3, index: int) -> void:
	"""Create a sloped entrance to a tunnel"""
	var slope_length: float = 8.0
	var slope_mesh: BoxMesh = create_smooth_box_mesh(Vector3(5.0, 0.5, slope_length))

	var slope_instance: MeshInstance3D = MeshInstance3D.new()
	slope_instance.mesh = slope_mesh
	slope_instance.name = "TunnelEntrance" + str(index)

	# Position slope from ground level to tunnel depth
	var slope_start: Vector3 = Vector3(tunnel_pos.x, 0, tunnel_pos.z)
	var slope_mid: Vector3 = slope_start + Vector3(0, tunnel_pos.y / 2.0, 0)
	slope_instance.position = slope_mid

	# Rotate to face outward and tilt down
	var angle_out: float = atan2(tunnel_pos.x, tunnel_pos.z)
	slope_instance.rotation.y = angle_out
	slope_instance.rotation.x = atan2(-tunnel_pos.y, slope_length)

	add_child(slope_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = slope_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	slope_instance.add_child(static_body)

	platforms.append(slope_instance)

# ============================================================================
# JUMP PADS (Interactive - uses spacing checks)
# ============================================================================

func generate_jump_pads() -> void:
	"""Generate jump pads for quick vertical movement"""
	var floor_radius: float = (arena_size * 0.6) / 2.0
	var generated: int = 0
	var max_attempts: int = jump_pad_count * 5

	# Always place one at center
	if check_interactive_spacing(Vector3.ZERO, 3.0):
		create_jump_pad(Vector3.ZERO, 0)
		register_interactive(Vector3.ZERO, 3.0)
		generated += 1

	# Generate remaining jump pads
	for attempt in range(max_attempts):
		if generated >= jump_pad_count:
			break

		var angle: float = randf() * TAU
		var distance: float = randf_range(15.0, floor_radius - 5.0)
		var pos: Vector3 = Vector3(cos(angle) * distance, 0, sin(angle) * distance)

		if check_interactive_spacing(pos, 3.0):
			create_jump_pad(pos, generated)
			register_interactive(pos, 3.0)
			generated += 1

	print("Generated %d jump pads" % generated)

func create_jump_pad(pos: Vector3, index: int) -> void:
	"""Create a jump pad (visual platform + Area3D for boost)"""

	# Visual platform
	var pad_mesh: CylinderMesh = CylinderMesh.new()
	pad_mesh.top_radius = 2.0 + complexity * 0.3
	pad_mesh.bottom_radius = 2.0 + complexity * 0.3
	pad_mesh.height = 0.5

	var pad_instance: MeshInstance3D = MeshInstance3D.new()
	pad_instance.mesh = pad_mesh
	pad_instance.name = "JumpPad" + str(index)
	pad_instance.position = Vector3(pos.x, 0.25, pos.z)
	add_child(pad_instance)

	# Material for jump pad (bright green - unshaded for GL Compatibility)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 1.0, 0.4)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	pad_instance.material_override = material

	# Add collision
	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var collision_shape: CylinderShape3D = CylinderShape3D.new()
	collision_shape.radius = pad_mesh.top_radius
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

	jump_area.collision_layer = 8
	jump_area.collision_mask = 0
	jump_area.monitorable = true
	jump_area.monitoring = false

	var area_collision: CollisionShape3D = CollisionShape3D.new()
	var area_shape: CylinderShape3D = CylinderShape3D.new()
	area_shape.radius = pad_mesh.top_radius
	area_shape.height = 3.0
	area_collision.shape = area_shape
	jump_area.add_child(area_collision)

# ============================================================================
# TELEPORTERS (Interactive - uses spacing checks)
# ============================================================================

func generate_teleporters() -> void:
	"""Generate teleporter pairs for quick arena traversal"""
	var floor_radius: float = (arena_size * 0.6) / 2.0
	var generated_pairs: int = 0
	var max_attempts: int = teleporter_pair_count * 10

	for attempt in range(max_attempts):
		if generated_pairs >= teleporter_pair_count:
			break

		# Generate two positions for a pair
		var angle1: float = randf() * TAU
		var angle2: float = angle1 + PI + randf_range(-0.5, 0.5)  # Roughly opposite
		var dist1: float = randf_range(20.0, floor_radius - 5.0)
		var dist2: float = randf_range(20.0, floor_radius - 5.0)

		var pos1: Vector3 = Vector3(cos(angle1) * dist1, 0, sin(angle1) * dist1)
		var pos2: Vector3 = Vector3(cos(angle2) * dist2, 0, sin(angle2) * dist2)

		# Check spacing for both positions
		if check_interactive_spacing(pos1, 4.0) and check_interactive_spacing(pos2, 4.0):
			create_teleporter_pair(pos1, pos2, generated_pairs)
			register_interactive(pos1, 4.0)
			register_interactive(pos2, 4.0)
			generated_pairs += 1

	print("Generated %d teleporter pairs" % generated_pairs)

func create_teleporter_pair(from_pos: Vector3, to_pos: Vector3, pair_index: int) -> void:
	"""Create a bidirectional teleporter pair"""
	create_teleporter(from_pos, to_pos, pair_index * 2)
	create_teleporter(to_pos, from_pos, pair_index * 2 + 1)

func create_teleporter(pos: Vector3, destination: Vector3, index: int) -> void:
	"""Create a single teleporter"""

	# Visual platform
	var teleporter_mesh: CylinderMesh = CylinderMesh.new()
	teleporter_mesh.top_radius = 2.5 + complexity * 0.3
	teleporter_mesh.bottom_radius = 2.5 + complexity * 0.3
	teleporter_mesh.height = 0.3

	var teleporter_instance: MeshInstance3D = MeshInstance3D.new()
	teleporter_instance.mesh = teleporter_mesh
	teleporter_instance.name = "Teleporter" + str(index)
	teleporter_instance.position = Vector3(pos.x, 0.15, pos.z)
	add_child(teleporter_instance)

	# Material for teleporter (blue/purple - unshaded for GL Compatibility)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.4, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	teleporter_instance.material_override = material

	# Add collision
	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var collision_shape: CylinderShape3D = CylinderShape3D.new()
	collision_shape.radius = teleporter_mesh.top_radius
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

	teleport_area.collision_layer = 8
	teleport_area.collision_mask = 0
	teleport_area.monitorable = true
	teleport_area.monitoring = false

	var area_collision: CollisionShape3D = CollisionShape3D.new()
	var area_shape: CylinderShape3D = CylinderShape3D.new()
	area_shape.radius = teleporter_mesh.top_radius
	area_shape.height = 5.0
	area_collision.shape = area_shape
	teleport_area.add_child(area_collision)

	teleporters.append({"area": teleport_area, "destination": destination})

# ============================================================================
# PERIMETER WALLS
# ============================================================================

func generate_perimeter_walls() -> void:
	"""Generate outer perimeter walls"""
	var wall_distance: float = arena_size * 0.55
	var wall_height: float = 20.0 + complexity * 3.0  # Taller at higher complexity
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

	print("Generated perimeter walls (height: %.1f)" % wall_height)

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
	"""Generate spawn points throughout the arena"""
	var spawns: PackedVector3Array = PackedVector3Array()
	var floor_radius: float = (arena_size * 0.6) / 2.0

	# Main arena spawns
	spawns.append(Vector3(0, 2, 0))

	# Ring spawns scaled to arena
	var ring_dist: float = min(15.0, floor_radius * 0.4)
	spawns.append(Vector3(ring_dist, 2, 0))
	spawns.append(Vector3(-ring_dist, 2, 0))
	spawns.append(Vector3(0, 2, ring_dist))
	spawns.append(Vector3(0, 2, -ring_dist))

	# Room spawns
	var room_distance: float = arena_size * 0.32
	for i in range(room_count):
		var angle: float = (float(i) / room_count) * TAU
		var x: float = cos(angle) * room_distance
		var z: float = sin(angle) * room_distance
		spawns.append(Vector3(x, 3, z))

	# Platform spawns (tier 1)
	var base_distance: float = arena_size * 0.18
	var tier1_height: float = 6.0 + complexity * 1.0
	for i in range(min(4, tier1_platform_count)):
		var angle: float = (float(i) / 4) * TAU
		var x: float = cos(angle) * base_distance
		var z: float = sin(angle) * base_distance
		spawns.append(Vector3(x, tier1_height + 2, z))

	return spawns

# ============================================================================
# PROCEDURAL TEXTURES
# ============================================================================

func apply_procedural_textures() -> void:
	"""Apply procedurally generated textures to all platforms"""
	material_manager.apply_materials_to_level(self)
