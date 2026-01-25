extends Node3D

## Quake 3 Arena-Style Level Generator (Type B)
## Creates PROCEDURALLY VARIED architectural arenas
## Each seed produces a unique layout while maintaining Q3 arena feel

# ============================================================================
# EXPORTED PARAMETERS
# ============================================================================

@export var level_seed: int = 0
@export var arena_size: float = 140.0  # Base arena size
@export var complexity: int = 2  # 1=Low, 2=Medium, 3=High, 4=Extreme

var rng: RandomNumberGenerator
var platforms: Array = []
var teleporters: Array = []
var clear_positions: Array[Vector3] = []
var occupied_cells: Dictionary = {}  # Grid-based collision avoidance
var material_manager = preload("res://scripts/procedural_material_manager.gd").new()

# Grid cell size for structure placement
const CELL_SIZE: float = 12.0

# ============================================================================
# STRUCTURE TYPES - Q3-inspired architectural elements
# ============================================================================

enum StructureType {
	PILLAR,           # Tall column
	TIERED_PLATFORM,  # Stacked platforms
	L_WALL,           # L-shaped cover wall
	BUNKER,           # Semi-enclosed room
	JUMP_TOWER,       # Platform with jump pad
	CATWALK,          # Elevated walkway
	RAMP_PLATFORM,    # Platform with ramp access
	SPLIT_LEVEL,      # Two-height section
	ARCHWAY,          # Pass-through structure
	SNIPER_NEST       # High vantage point
}

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	generate_level()

func generate_level() -> void:
	"""Generate a unique Q3 Arena-style level"""
	rng = RandomNumberGenerator.new()
	rng.seed = level_seed if level_seed != 0 else randi()

	print("=== Q3 ARENA LEVEL CONFIG ===")
	print("Seed: %d" % rng.seed)
	print("Arena Size: %.1f (floor: %.1f x %.1f)" % [arena_size, arena_size * 0.6, arena_size * 0.6])
	print("Complexity: %d" % complexity)

	clear_level()

	# Always generate base arena
	generate_main_arena()

	# Procedurally select and place structures
	var structure_budget: int = get_structure_budget()
	print("Structure budget: %d" % structure_budget)

	generate_procedural_structures(structure_budget)

	# Add connectivity elements
	generate_procedural_bridges()

	# Interactive objects
	generate_jump_pads()
	generate_teleporters()

	# Boundaries
	generate_perimeter_walls()
	generate_death_zone()

	apply_procedural_textures()
	print("Q3 Arena generation complete! Structures placed: %d" % platforms.size())

func clear_level() -> void:
	for child in get_children():
		child.queue_free()
	platforms.clear()
	teleporters.clear()
	clear_positions.clear()
	occupied_cells.clear()

func get_structure_budget() -> int:
	"""Determine how many major structures based on complexity"""
	var base_count: int = 4 + complexity * 2  # 6, 8, 10, 12
	var size_bonus: int = int((arena_size - 140.0) / 40.0)  # More for larger arenas
	return base_count + size_bonus

# ============================================================================
# GRID-BASED PLACEMENT SYSTEM
# ============================================================================

func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(int(pos.x / CELL_SIZE), int(pos.z / CELL_SIZE))

func is_cell_available(pos: Vector3, radius: int = 1) -> bool:
	var center_cell: Vector2i = world_to_cell(pos)
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var cell: Vector2i = Vector2i(center_cell.x + dx, center_cell.y + dz)
			if occupied_cells.has(cell):
				return false
	return true

func mark_cell_occupied(pos: Vector3, radius: int = 1) -> void:
	var center_cell: Vector2i = world_to_cell(pos)
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var cell: Vector2i = Vector2i(center_cell.x + dx, center_cell.y + dz)
			occupied_cells[cell] = true

func get_random_position_in_arena() -> Vector3:
	"""Get a random position within the arena bounds"""
	var floor_extent: float = (arena_size * 0.6) / 2.0 - CELL_SIZE
	return Vector3(
		rng.randf_range(-floor_extent, floor_extent),
		0,
		rng.randf_range(-floor_extent, floor_extent)
	)

# ============================================================================
# MAIN ARENA FLOOR
# ============================================================================

func generate_main_arena() -> void:
	var floor_size: float = arena_size * 0.6
	var scale: float = arena_size / 140.0

	# Main floor with slight height variation zones
	add_platform_with_collision(
		Vector3(0, -1, 0),
		Vector3(floor_size, 2.0, floor_size),
		"MainArenaFloor"
	)

	# Mark center area
	mark_cell_occupied(Vector3.ZERO, 1)
	clear_positions.append(Vector3(0, 0, 0))

	# Randomly add floor height variations (complexity 2+)
	if complexity >= 2:
		var num_raised_sections: int = rng.randi_range(1, complexity)
		for i in range(num_raised_sections):
			var pos: Vector3 = get_random_position_in_arena()
			if is_cell_available(pos, 1):
				var section_size: float = rng.randf_range(8.0, 16.0) * scale
				var section_height: float = rng.randf_range(0.5, 1.5)
				add_platform_with_collision(
					Vector3(pos.x, section_height / 2.0, pos.z),
					Vector3(section_size, section_height, section_size),
					"RaisedSection" + str(i)
				)
				clear_positions.append(Vector3(pos.x, section_height + 0.5, pos.z))

# ============================================================================
# PROCEDURAL STRUCTURE GENERATION
# ============================================================================

func generate_procedural_structures(budget: int) -> void:
	"""Generate random structures until budget is spent"""
	var scale: float = arena_size / 140.0
	var attempts: int = 0
	var max_attempts: int = budget * 10  # Increased attempts
	var structures_placed: int = 0

	print("[Q3 DEBUG] Starting structure generation:")
	print("  Budget: %d, Scale: %.2f, Complexity: %d" % [budget, scale, complexity])

	# Determine available structure types based on complexity
	var available_types: Array = [StructureType.PILLAR, StructureType.TIERED_PLATFORM]
	if complexity >= 2:
		available_types.append_array([StructureType.L_WALL, StructureType.RAMP_PLATFORM, StructureType.CATWALK])
	if complexity >= 3:
		available_types.append_array([StructureType.BUNKER, StructureType.JUMP_TOWER, StructureType.ARCHWAY])
	if complexity >= 4:
		available_types.append_array([StructureType.SPLIT_LEVEL, StructureType.SNIPER_NEST])

	print("  Available structure types: %d" % available_types.size())

	var floor_extent: float = (arena_size * 0.6) / 2.0 - CELL_SIZE
	print("  Floor extent for placement: %.1f (cells from %.1f to %.1f)" % [floor_extent, -floor_extent, floor_extent])

	while structures_placed < budget and attempts < max_attempts:
		attempts += 1

		var pos: Vector3 = get_random_position_in_arena()
		var struct_type: int = available_types[rng.randi() % available_types.size()]
		var cell_radius: int = get_structure_cell_radius(struct_type)

		if is_cell_available(pos, cell_radius):
			print("  [%d] Placing structure type %d at (%.1f, %.1f)" % [structures_placed, struct_type, pos.x, pos.z])
			generate_structure(struct_type, pos, scale, structures_placed)
			mark_cell_occupied(pos, cell_radius)
			structures_placed += 1

	print("[Q3 DEBUG] Placed %d/%d structures in %d attempts" % [structures_placed, budget, attempts])
	print("  Occupied cells: %d" % occupied_cells.size())

func get_structure_cell_radius(type: int) -> int:
	match type:
		StructureType.PILLAR:
			return 1
		StructureType.TIERED_PLATFORM, StructureType.JUMP_TOWER:
			return 1
		StructureType.L_WALL, StructureType.RAMP_PLATFORM:
			return 1
		StructureType.BUNKER, StructureType.ARCHWAY:
			return 2
		StructureType.CATWALK:
			return 1
		StructureType.SPLIT_LEVEL:
			return 2
		StructureType.SNIPER_NEST:
			return 1
	return 1

func generate_structure(type: int, pos: Vector3, scale: float, index: int) -> void:
	match type:
		StructureType.PILLAR:
			generate_pillar(pos, scale, index)
		StructureType.TIERED_PLATFORM:
			generate_tiered_platform(pos, scale, index)
		StructureType.L_WALL:
			generate_l_wall(pos, scale, index)
		StructureType.BUNKER:
			generate_bunker(pos, scale, index)
		StructureType.JUMP_TOWER:
			generate_jump_tower(pos, scale, index)
		StructureType.CATWALK:
			generate_catwalk(pos, scale, index)
		StructureType.RAMP_PLATFORM:
			generate_ramp_platform(pos, scale, index)
		StructureType.SPLIT_LEVEL:
			generate_split_level(pos, scale, index)
		StructureType.ARCHWAY:
			generate_archway(pos, scale, index)
		StructureType.SNIPER_NEST:
			generate_sniper_nest(pos, scale, index)

# ============================================================================
# INDIVIDUAL STRUCTURE GENERATORS
# ============================================================================

func generate_pillar(pos: Vector3, scale: float, index: int) -> void:
	"""Generate a tall pillar/column"""
	var width: float = rng.randf_range(2.0, 4.0) * scale
	var height: float = rng.randf_range(6.0, 14.0) * scale

	print("    -> Creating pillar: width=%.1f, height=%.1f at (%.1f, %.1f, %.1f)" % [width, height, pos.x, height/2.0, pos.z])

	add_platform_with_collision(
		Vector3(pos.x, height / 2.0, pos.z),
		Vector3(width, height, width),
		"Pillar" + str(index)
	)

	# Sometimes add a platform on top
	if rng.randf() > 0.4:
		var platform_size: float = width * rng.randf_range(1.5, 2.5)
		add_platform_with_collision(
			Vector3(pos.x, height + 0.5, pos.z),
			Vector3(platform_size, 1.0, platform_size),
			"PillarTop" + str(index)
		)
		clear_positions.append(Vector3(pos.x, height + 1.5, pos.z))

func generate_tiered_platform(pos: Vector3, scale: float, index: int) -> void:
	"""Generate stacked platforms like Q3 jump pads areas"""
	var num_tiers: int = rng.randi_range(2, 3 + complexity / 2)
	var base_size: float = rng.randf_range(6.0, 10.0) * scale
	var tier_height: float = rng.randf_range(2.5, 4.0) * scale

	for i in range(num_tiers):
		var tier_size: float = base_size * (1.0 - i * 0.2)
		var height: float = tier_height * (i + 1)

		add_platform_with_collision(
			Vector3(pos.x, height - tier_height / 2.0, pos.z),
			Vector3(tier_size, tier_height * 0.3, tier_size),
			"TieredPlatform" + str(index) + "_" + str(i)
		)

		clear_positions.append(Vector3(pos.x, height + 0.5, pos.z))

func generate_l_wall(pos: Vector3, scale: float, index: int) -> void:
	"""Generate L-shaped cover wall"""
	var wall_length: float = rng.randf_range(6.0, 12.0) * scale
	var wall_height: float = rng.randf_range(3.0, 6.0) * scale
	var wall_thickness: float = 1.0 * scale
	var rotation: float = rng.randf() * TAU

	# Vertical part
	var v_offset: Vector3 = Vector3(wall_length / 2.0, 0, 0).rotated(Vector3.UP, rotation)
	add_platform_with_collision(
		Vector3(pos.x + v_offset.x, wall_height / 2.0, pos.z + v_offset.z),
		Vector3(wall_thickness, wall_height, wall_length),
		"LWallV" + str(index)
	)

	# Horizontal part
	var h_offset: Vector3 = Vector3(0, 0, wall_length / 2.0).rotated(Vector3.UP, rotation)
	add_platform_with_collision(
		Vector3(pos.x + h_offset.x, wall_height / 2.0, pos.z + h_offset.z),
		Vector3(wall_length, wall_height, wall_thickness),
		"LWallH" + str(index)
	)

func generate_bunker(pos: Vector3, scale: float, index: int) -> void:
	"""Generate semi-enclosed room structure"""
	var bunker_size: float = rng.randf_range(8.0, 14.0) * scale
	var wall_height: float = rng.randf_range(4.0, 7.0) * scale
	var wall_thickness: float = 1.0 * scale
	var opening_size: float = bunker_size * 0.4

	# Floor
	add_platform_with_collision(
		Vector3(pos.x, 0.25, pos.z),
		Vector3(bunker_size, 0.5, bunker_size),
		"BunkerFloor" + str(index)
	)

	# Randomly select which walls to include (at least 2)
	var walls_to_build: Array = []
	var wall_configs = [
		{"offset": Vector3(0, 0, bunker_size/2.0), "size": Vector3(bunker_size, wall_height, wall_thickness)},
		{"offset": Vector3(0, 0, -bunker_size/2.0), "size": Vector3(bunker_size, wall_height, wall_thickness)},
		{"offset": Vector3(bunker_size/2.0, 0, 0), "size": Vector3(wall_thickness, wall_height, bunker_size)},
		{"offset": Vector3(-bunker_size/2.0, 0, 0), "size": Vector3(wall_thickness, wall_height, bunker_size)}
	]

	# Pick 2-3 walls randomly
	var num_walls: int = rng.randi_range(2, 3)
	var indices: Array = [0, 1, 2, 3]
	indices.shuffle()

	for i in range(num_walls):
		var config = wall_configs[indices[i]]
		add_platform_with_collision(
			Vector3(pos.x + config.offset.x, wall_height / 2.0, pos.z + config.offset.z),
			config.size,
			"BunkerWall" + str(index) + "_" + str(i)
		)

	# Roof (sometimes)
	if rng.randf() > 0.5:
		add_platform_with_collision(
			Vector3(pos.x, wall_height + 0.5, pos.z),
			Vector3(bunker_size, 1.0, bunker_size),
			"BunkerRoof" + str(index)
		)
		clear_positions.append(Vector3(pos.x, wall_height + 1.5, pos.z))

	clear_positions.append(Vector3(pos.x, 1.0, pos.z))

func generate_jump_tower(pos: Vector3, scale: float, index: int) -> void:
	"""Generate a small platform with integrated jump pad area"""
	var tower_size: float = rng.randf_range(4.0, 6.0) * scale
	var tower_height: float = rng.randf_range(3.0, 6.0) * scale

	# Base pillar
	add_platform_with_collision(
		Vector3(pos.x, tower_height / 2.0, pos.z),
		Vector3(tower_size * 0.6, tower_height, tower_size * 0.6),
		"JumpTowerBase" + str(index)
	)

	# Top platform
	add_platform_with_collision(
		Vector3(pos.x, tower_height + 0.5, pos.z),
		Vector3(tower_size, 1.0, tower_size),
		"JumpTowerTop" + str(index)
	)

	clear_positions.append(Vector3(pos.x, tower_height + 1.5, pos.z))

func generate_catwalk(pos: Vector3, scale: float, index: int) -> void:
	"""Generate elevated walkway"""
	var length: float = rng.randf_range(12.0, 24.0) * scale
	var width: float = rng.randf_range(2.5, 4.0) * scale
	var height: float = rng.randf_range(5.0, 10.0) * scale
	var rotation: float = rng.randf() * PI  # 0 to 180 degrees

	# Main walkway
	var walkway = add_platform_with_collision(
		Vector3(pos.x, height, pos.z),
		Vector3(length, 0.5, width),
		"Catwalk" + str(index)
	)
	walkway.rotation.y = rotation

	# Support pillars at ends
	var end_offset: float = length / 2.0 - 1.0
	var offset1: Vector3 = Vector3(end_offset, 0, 0).rotated(Vector3.UP, rotation)
	var offset2: Vector3 = Vector3(-end_offset, 0, 0).rotated(Vector3.UP, rotation)

	add_platform_with_collision(
		Vector3(pos.x + offset1.x, height / 2.0, pos.z + offset1.z),
		Vector3(2.0 * scale, height, 2.0 * scale),
		"CatwalkSupport" + str(index) + "A"
	)
	add_platform_with_collision(
		Vector3(pos.x + offset2.x, height / 2.0, pos.z + offset2.z),
		Vector3(2.0 * scale, height, 2.0 * scale),
		"CatwalkSupport" + str(index) + "B"
	)

	clear_positions.append(Vector3(pos.x, height + 1.0, pos.z))

func generate_ramp_platform(pos: Vector3, scale: float, index: int) -> void:
	"""Generate platform with ramp access"""
	var platform_size: float = rng.randf_range(6.0, 10.0) * scale
	var platform_height: float = rng.randf_range(3.0, 6.0) * scale
	var ramp_length: float = platform_height * 2.5
	var rotation: float = rng.randf() * TAU

	# Platform
	add_platform_with_collision(
		Vector3(pos.x, platform_height, pos.z),
		Vector3(platform_size, 1.0, platform_size),
		"RampPlatform" + str(index)
	)

	# Ramp
	var ramp_offset: Vector3 = Vector3(platform_size / 2.0 + ramp_length / 2.0 - 1.0, 0, 0).rotated(Vector3.UP, rotation)
	var ramp_mesh: BoxMesh = create_smooth_box_mesh(Vector3(ramp_length, 0.5, platform_size * 0.6))
	var ramp_instance: MeshInstance3D = MeshInstance3D.new()
	ramp_instance.mesh = ramp_mesh
	ramp_instance.name = "Ramp" + str(index)
	ramp_instance.position = Vector3(pos.x + ramp_offset.x, platform_height / 2.0, pos.z + ramp_offset.z)
	ramp_instance.rotation.y = rotation
	ramp_instance.rotation.z = -atan2(platform_height, ramp_length)
	add_child(ramp_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = ramp_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	ramp_instance.add_child(static_body)
	platforms.append(ramp_instance)

	clear_positions.append(Vector3(pos.x, platform_height + 1.5, pos.z))

func generate_split_level(pos: Vector3, scale: float, index: int) -> void:
	"""Generate area with two different floor heights"""
	var section_size: float = rng.randf_range(10.0, 16.0) * scale
	var height_diff: float = rng.randf_range(2.0, 4.0) * scale

	# Lower section
	add_platform_with_collision(
		Vector3(pos.x - section_size / 4.0, 0.25, pos.z),
		Vector3(section_size / 2.0, 0.5, section_size),
		"SplitLow" + str(index)
	)

	# Higher section
	add_platform_with_collision(
		Vector3(pos.x + section_size / 4.0, height_diff / 2.0, pos.z),
		Vector3(section_size / 2.0, height_diff, section_size),
		"SplitHigh" + str(index)
	)

	# Connecting ramp
	var ramp_mesh: BoxMesh = create_smooth_box_mesh(Vector3(section_size * 0.3, 0.5, section_size * 0.4))
	var ramp_instance: MeshInstance3D = MeshInstance3D.new()
	ramp_instance.mesh = ramp_mesh
	ramp_instance.name = "SplitRamp" + str(index)
	ramp_instance.position = Vector3(pos.x, height_diff / 2.0, pos.z)
	ramp_instance.rotation.z = -atan2(height_diff, section_size * 0.3)
	add_child(ramp_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = ramp_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	ramp_instance.add_child(static_body)
	platforms.append(ramp_instance)

	clear_positions.append(Vector3(pos.x + section_size / 4.0, height_diff + 1.0, pos.z))

func generate_archway(pos: Vector3, scale: float, index: int) -> void:
	"""Generate pass-through archway structure"""
	var arch_width: float = rng.randf_range(6.0, 10.0) * scale
	var arch_height: float = rng.randf_range(5.0, 8.0) * scale
	var pillar_width: float = 2.0 * scale
	var rotation: float = rng.randf() * PI

	var offset: float = arch_width / 2.0
	var offset_vec: Vector3 = Vector3(offset, 0, 0).rotated(Vector3.UP, rotation)

	# Left pillar
	add_platform_with_collision(
		Vector3(pos.x + offset_vec.x, arch_height / 2.0, pos.z + offset_vec.z),
		Vector3(pillar_width, arch_height, pillar_width),
		"ArchPillarL" + str(index)
	)

	# Right pillar
	add_platform_with_collision(
		Vector3(pos.x - offset_vec.x, arch_height / 2.0, pos.z - offset_vec.z),
		Vector3(pillar_width, arch_height, pillar_width),
		"ArchPillarR" + str(index)
	)

	# Top beam
	var beam = add_platform_with_collision(
		Vector3(pos.x, arch_height + 0.5, pos.z),
		Vector3(arch_width + pillar_width, 1.0, pillar_width * 1.5),
		"ArchBeam" + str(index)
	)
	beam.rotation.y = rotation

	clear_positions.append(Vector3(pos.x, arch_height + 1.5, pos.z))

func generate_sniper_nest(pos: Vector3, scale: float, index: int) -> void:
	"""Generate high vantage point"""
	var base_width: float = 3.0 * scale
	var height: float = rng.randf_range(12.0, 18.0) * scale
	var platform_size: float = rng.randf_range(5.0, 7.0) * scale

	# Tall pillar
	add_platform_with_collision(
		Vector3(pos.x, height / 2.0, pos.z),
		Vector3(base_width, height, base_width),
		"SniperBase" + str(index)
	)

	# Platform at top
	add_platform_with_collision(
		Vector3(pos.x, height + 0.5, pos.z),
		Vector3(platform_size, 1.0, platform_size),
		"SniperPlatform" + str(index)
	)

	# Low walls for cover
	var wall_height: float = 2.0 * scale
	var directions = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var num_walls: int = rng.randi_range(2, 3)
	directions.shuffle()

	for i in range(num_walls):
		var dir: Vector3 = directions[i]
		var wall_pos: Vector3 = Vector3(
			pos.x + dir.x * (platform_size / 2.0 - 0.5),
			height + 1.0 + wall_height / 2.0,
			pos.z + dir.z * (platform_size / 2.0 - 0.5)
		)
		var wall_size: Vector3
		if abs(dir.x) > 0.5:
			wall_size = Vector3(0.5, wall_height, platform_size * 0.8)
		else:
			wall_size = Vector3(platform_size * 0.8, wall_height, 0.5)

		add_platform_with_collision(wall_pos, wall_size, "SniperWall" + str(index) + "_" + str(i))

	clear_positions.append(Vector3(pos.x, height + 2.0, pos.z))

# ============================================================================
# PROCEDURAL BRIDGES
# ============================================================================

func generate_procedural_bridges() -> void:
	"""Generate bridges connecting elevated positions"""
	if complexity < 2 or clear_positions.size() < 4:
		return

	var scale: float = arena_size / 140.0
	var bridge_width: float = 3.0 * scale

	# Find elevated positions (height > 4)
	var elevated_positions: Array[Vector3] = []
	for pos in clear_positions:
		if pos.y > 4.0:
			elevated_positions.append(pos)

	if elevated_positions.size() < 2:
		return

	# Try to connect some elevated positions
	var num_bridges: int = mini(rng.randi_range(1, complexity), elevated_positions.size() / 2)
	elevated_positions.shuffle()

	for i in range(num_bridges):
		if i * 2 + 1 >= elevated_positions.size():
			break

		var pos1: Vector3 = elevated_positions[i * 2]
		var pos2: Vector3 = elevated_positions[i * 2 + 1]

		# Only connect if reasonable distance
		var dist: float = pos1.distance_to(pos2)
		if dist < 10.0 * scale or dist > 40.0 * scale:
			continue

		var mid_point: Vector3 = (pos1 + pos2) / 2.0
		var avg_height: float = (pos1.y + pos2.y) / 2.0
		var direction: Vector3 = (pos2 - pos1).normalized()
		var angle: float = atan2(direction.x, direction.z)

		var bridge_mesh: BoxMesh = create_smooth_box_mesh(Vector3(dist, 0.5, bridge_width))
		var bridge_instance: MeshInstance3D = MeshInstance3D.new()
		bridge_instance.mesh = bridge_mesh
		bridge_instance.name = "Bridge" + str(i)
		bridge_instance.position = Vector3(mid_point.x, avg_height - 0.5, mid_point.z)
		bridge_instance.rotation.y = angle
		add_child(bridge_instance)

		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = bridge_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		bridge_instance.add_child(static_body)
		platforms.append(bridge_instance)

# ============================================================================
# JUMP PADS
# ============================================================================

func generate_jump_pads() -> void:
	"""Place jump pads in strategic locations"""
	var scale: float = arena_size / 140.0
	var floor_extent: float = (arena_size * 0.6) / 2.0

	# Always one at center
	var jump_pad_positions: Array[Vector3] = [Vector3(0, 0, 0)]

	# Add pads at random positions
	var num_extra_pads: int = 2 + complexity
	for i in range(num_extra_pads):
		var pos: Vector3 = Vector3(
			rng.randf_range(-floor_extent * 0.7, floor_extent * 0.7),
			0,
			rng.randf_range(-floor_extent * 0.7, floor_extent * 0.7)
		)
		# Avoid duplicates
		var too_close: bool = false
		for existing in jump_pad_positions:
			if pos.distance_to(existing) < 10.0 * scale:
				too_close = true
				break
		if not too_close:
			jump_pad_positions.append(pos)

	for i in range(jump_pad_positions.size()):
		create_jump_pad(jump_pad_positions[i], i, scale)

	print("Generated %d jump pads" % jump_pad_positions.size())

func create_jump_pad(pos: Vector3, index: int, scale: float) -> void:
	var pad_radius: float = 2.0 * scale

	var pad_mesh: CylinderMesh = CylinderMesh.new()
	pad_mesh.top_radius = pad_radius
	pad_mesh.bottom_radius = pad_radius
	pad_mesh.height = 0.5

	var pad_instance: MeshInstance3D = MeshInstance3D.new()
	pad_instance.mesh = pad_mesh
	pad_instance.name = "JumpPad" + str(index)
	pad_instance.position = Vector3(pos.x, 0.25, pos.z)
	add_child(pad_instance)

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 1.0, 0.4)
	material.emission_enabled = true
	material.emission = Color(0.2, 0.8, 0.3)
	material.emission_energy_multiplier = 0.5
	pad_instance.material_override = material

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var collision_shape: CylinderShape3D = CylinderShape3D.new()
	collision_shape.radius = pad_radius
	collision_shape.height = 0.5
	collision.shape = collision_shape
	static_body.add_child(collision)
	pad_instance.add_child(static_body)

	var jump_area: Area3D = Area3D.new()
	jump_area.name = "JumpPadArea"
	jump_area.add_to_group("jump_pad")
	jump_area.collision_layer = 8
	jump_area.collision_mask = 0
	jump_area.monitorable = true
	jump_area.monitoring = false
	pad_instance.add_child(jump_area)

	var area_collision: CollisionShape3D = CollisionShape3D.new()
	var area_shape: CylinderShape3D = CylinderShape3D.new()
	area_shape.radius = pad_radius
	area_shape.height = 3.0
	area_collision.shape = area_shape
	jump_area.add_child(area_collision)

# ============================================================================
# TELEPORTERS
# ============================================================================

func generate_teleporters() -> void:
	"""Place teleporter pairs"""
	var scale: float = arena_size / 140.0
	var floor_extent: float = (arena_size * 0.6) / 2.0

	var num_pairs: int = 1 + complexity / 2

	for i in range(num_pairs):
		# Random positions on opposite sides
		var angle1: float = rng.randf() * TAU
		var angle2: float = angle1 + PI + rng.randf_range(-0.5, 0.5)
		var dist1: float = rng.randf_range(floor_extent * 0.5, floor_extent * 0.8)
		var dist2: float = rng.randf_range(floor_extent * 0.5, floor_extent * 0.8)

		var pos1: Vector3 = Vector3(cos(angle1) * dist1, 0, sin(angle1) * dist1)
		var pos2: Vector3 = Vector3(cos(angle2) * dist2, 0, sin(angle2) * dist2)

		create_teleporter(pos1, pos2, i * 2, scale)
		create_teleporter(pos2, pos1, i * 2 + 1, scale)

	print("Generated %d teleporters" % (num_pairs * 2))

func create_teleporter(pos: Vector3, destination: Vector3, index: int, scale: float) -> void:
	var teleporter_radius: float = 2.5 * scale

	var teleporter_mesh: CylinderMesh = CylinderMesh.new()
	teleporter_mesh.top_radius = teleporter_radius
	teleporter_mesh.bottom_radius = teleporter_radius
	teleporter_mesh.height = 0.3

	var teleporter_instance: MeshInstance3D = MeshInstance3D.new()
	teleporter_instance.mesh = teleporter_mesh
	teleporter_instance.name = "Teleporter" + str(index)
	teleporter_instance.position = Vector3(pos.x, 0.15, pos.z)
	add_child(teleporter_instance)

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.4, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.5, 0.3, 0.9)
	material.emission_energy_multiplier = 0.5
	teleporter_instance.material_override = material

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var collision_shape: CylinderShape3D = CylinderShape3D.new()
	collision_shape.radius = teleporter_radius
	collision_shape.height = 0.3
	collision.shape = collision_shape
	static_body.add_child(collision)
	teleporter_instance.add_child(static_body)

	var teleport_area: Area3D = Area3D.new()
	teleport_area.name = "TeleportArea"
	teleport_area.add_to_group("teleporter")
	teleport_area.set_meta("destination", destination + Vector3(0, 1.0, 0))
	teleport_area.collision_layer = 8
	teleport_area.collision_mask = 0
	teleport_area.monitorable = true
	teleport_area.monitoring = false
	teleporter_instance.add_child(teleport_area)

	var area_collision: CollisionShape3D = CollisionShape3D.new()
	var area_shape: CylinderShape3D = CylinderShape3D.new()
	area_shape.radius = teleporter_radius
	area_shape.height = 5.0
	area_collision.shape = area_shape
	teleport_area.add_child(area_collision)

	teleporters.append({"area": teleport_area, "destination": destination})

# ============================================================================
# PERIMETER & DEATH ZONE
# ============================================================================

func generate_perimeter_walls() -> void:
	var scale: float = arena_size / 140.0
	var wall_distance: float = arena_size * 0.55
	var wall_height: float = 25.0 * scale
	var wall_thickness: float = 2.0

	var wall_configs = [
		{"pos": Vector3(0, wall_height / 2.0, wall_distance), "size": Vector3(arena_size * 1.2, wall_height, wall_thickness)},
		{"pos": Vector3(0, wall_height / 2.0, -wall_distance), "size": Vector3(arena_size * 1.2, wall_height, wall_thickness)},
		{"pos": Vector3(wall_distance, wall_height / 2.0, 0), "size": Vector3(wall_thickness, wall_height, arena_size * 1.2)},
		{"pos": Vector3(-wall_distance, wall_height / 2.0, 0), "size": Vector3(wall_thickness, wall_height, arena_size * 1.2)}
	]

	for i in range(wall_configs.size()):
		var config = wall_configs[i]
		add_platform_with_collision(config.pos, config.size, "PerimeterWall" + str(i))

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
# HELPER FUNCTIONS
# ============================================================================

func create_smooth_box_mesh(size: Vector3) -> BoxMesh:
	var mesh = BoxMesh.new()
	mesh.size = size
	return mesh

func add_platform_with_collision(pos: Vector3, size: Vector3, name_prefix: String) -> MeshInstance3D:
	var mesh: BoxMesh = create_smooth_box_mesh(size)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.name = name_prefix
	instance.position = pos
	add_child(instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	instance.add_child(static_body)

	platforms.append(instance)
	return instance

func apply_procedural_textures() -> void:
	material_manager.apply_materials_to_level(self)

func get_spawn_points() -> PackedVector3Array:
	var spawns: PackedVector3Array = PackedVector3Array()

	# Use clear positions
	for pos in clear_positions:
		spawns.append(pos)

	# Add ground spawns
	var floor_radius: float = (arena_size * 0.6) / 2.0 * 0.5
	spawns.append(Vector3(0, 2, 0))
	spawns.append(Vector3(floor_radius, 2, 0))
	spawns.append(Vector3(-floor_radius, 2, 0))
	spawns.append(Vector3(0, 2, floor_radius))
	spawns.append(Vector3(0, 2, -floor_radius))

	return spawns
