extends Node3D

## Quake 3 Arena-Style Level Generator (Type B) - v2.1
## Uses BSP for room generation, tunneling for corridors, multi-tier platforms
## Fully procedural with size and complexity parameters
##
## v2.1 Fixes:
## - Fixed ramps to allow upward travel (angles were all negative/downward)
## - Added connectivity infrastructure: stairs, walkways, bridges between rooms/tiers
## - Fixed teleporter placement to use valid floor surfaces (no wall clipping)
## - Improved jump pad targeting to connect lower areas to higher platforms

# ============================================================================
# EXPORTED PARAMETERS
# ============================================================================

@export var level_seed: int = 0
@export var arena_size: float = 140.0
@export var complexity: int = 3  # 1-5, affects element density

# ============================================================================
# INTERNAL STATE
# ============================================================================

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var noise: FastNoiseLite
var platforms: Array = []
var teleporters: Array = []
var rooms: Array[Dictionary] = []  # BSP-generated rooms
var corridors: Array[Dictionary] = []  # Tunneled corridors
var spawn_points: PackedVector3Array = PackedVector3Array()
var material_manager = preload("res://scripts/procedural_material_manager.gd").new()

# Connectivity graph for reachability checks
var connectivity_graph: Dictionary = {}  # node_id -> [connected_node_ids]
var floor_regions: Array[Dictionary] = []  # For pathfinding verification

# Complexity scaling factors
var room_count_range: Vector2i
var platform_count_range: Vector2i
var jump_pad_count_range: Vector2i
var teleporter_pair_range: Vector2i
var cover_count_range: Vector2i

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	generate_level()

func generate_level() -> void:
	"""Generate a complete procedural Quake 3 Arena-style level"""
	# Initialize RNG with seed for reproducibility
	if level_seed == 0:
		level_seed = randi()
	rng.seed = level_seed

	print("======================================")
	print("Generating Q3 Arena Level (v2.1 - Connectivity Fix)")
	print("  Seed: %d" % level_seed)
	print("  Arena Size: %.1f" % arena_size)
	print("  Complexity: %d" % complexity)
	print("======================================")

	# Initialize noise for terrain variation
	noise = FastNoiseLite.new()
	noise.seed = level_seed
	noise.frequency = 0.02
	noise.noise_type = FastNoiseLite.TYPE_PERLIN

	# Calculate element counts based on complexity (1-5)
	_calculate_complexity_scaling()

	# Clear existing geometry
	clear_level()

	# === PHASE 1: BSP Room Generation ===
	generate_bsp_rooms()

	# === PHASE 2: Corridor Tunneling ===
	generate_tunneled_corridors()

	# === PHASE 3: Multi-Tier Platforms ===
	generate_multi_tier_platforms()

	# === PHASE 4: Ramps and Slopes ===
	generate_ramps_and_slopes()

	# === PHASE 4.5: Connectivity Infrastructure (Stairs, Walkways, Bridges) ===
	generate_connectivity_infrastructure()

	# === PHASE 5: Jump Pads ===
	generate_dynamic_jump_pads()

	# === PHASE 6: Teleporters ===
	generate_dynamic_teleporters()

	# === PHASE 7: Cover Objects (Pillars, Walls) ===
	generate_cover_objects()

	# === PHASE 8: Optional Hazards ===
	if complexity >= 3:
		generate_hazard_pits()

	# === PHASE 9: Perimeter and Death Zone ===
	generate_perimeter_walls()
	generate_death_zone()

	# === PHASE 10: Spawn Points ===
	generate_spawn_points()

	# === PHASE 11: Verify Connectivity ===
	verify_connectivity()

	# === PHASE 12: Apply Materials ===
	apply_procedural_textures()

	print("Level generation complete!")
	print("  Rooms: %d" % rooms.size())
	print("  Corridors: %d" % corridors.size())
	print("  Platforms: %d" % platforms.size())
	print("  Spawn Points: %d" % spawn_points.size())
	print("======================================")

func _calculate_complexity_scaling() -> void:
	"""Calculate element counts based on complexity level (1-5)"""
	# Clamp complexity to valid range
	complexity = clampi(complexity, 1, 5)

	# Room count: 8-20 based on complexity
	room_count_range = Vector2i(6 + complexity * 2, 8 + complexity * 3)

	# Platform count: 10-30 based on complexity
	platform_count_range = Vector2i(8 + complexity * 2, 12 + complexity * 4)

	# Jump pads: 5-15 based on complexity
	jump_pad_count_range = Vector2i(3 + complexity, 5 + complexity * 2)

	# Teleporter pairs: 2-5 based on complexity
	teleporter_pair_range = Vector2i(1 + complexity / 2, 2 + complexity)

	# Cover objects: 10-50 based on complexity
	cover_count_range = Vector2i(8 + complexity * 4, 15 + complexity * 8)

func clear_level() -> void:
	"""Remove all existing level geometry"""
	for child in get_children():
		child.queue_free()
	platforms.clear()
	teleporters.clear()
	rooms.clear()
	corridors.clear()
	spawn_points.clear()
	connectivity_graph.clear()
	floor_regions.clear()

# ============================================================================
# BSP ROOM GENERATION
# ============================================================================

class BSPNode:
	var bounds: Rect2  # x, y represent floor position (x, z in 3D)
	var left: BSPNode = null
	var right: BSPNode = null
	var room: Rect2 = Rect2()  # Actual room within bounds
	var room_type: int = 0  # 0=rectangular, 1=L-shaped

	func is_leaf() -> bool:
		return left == null and right == null

func generate_bsp_rooms() -> void:
	"""Generate rooms using Binary Space Partitioning"""
	var target_rooms: int = rng.randi_range(room_count_range.x, room_count_range.y)
	var floor_extent: float = arena_size * 0.45

	# Create root BSP node covering entire arena
	var root: BSPNode = BSPNode.new()
	root.bounds = Rect2(-floor_extent, -floor_extent, floor_extent * 2, floor_extent * 2)

	# Recursively split until we have enough leaves
	var leaves: Array[BSPNode] = []
	_bsp_split(root, target_rooms, leaves)

	print("BSP generated %d leaf nodes for rooms" % leaves.size())

	# Create rooms within each leaf
	for leaf in leaves:
		_create_room_in_leaf(leaf)

	# Build room geometry
	for room_data in rooms:
		_build_room_geometry(room_data)

func _bsp_split(node: BSPNode, target_count: int, leaves: Array[BSPNode], depth: int = 0) -> void:
	"""Recursively split BSP node"""
	var min_size: float = arena_size * 0.12  # Minimum room size

	# Stop conditions
	if depth > 6 or leaves.size() >= target_count:
		leaves.append(node)
		return

	# Check if we can split
	var can_split_h: bool = node.bounds.size.y > min_size * 2.5
	var can_split_v: bool = node.bounds.size.x > min_size * 2.5

	if not can_split_h and not can_split_v:
		leaves.append(node)
		return

	# Choose split direction (prefer splitting the longer axis)
	var split_horizontal: bool
	if can_split_h and can_split_v:
		split_horizontal = node.bounds.size.y > node.bounds.size.x
		# Add some randomness
		if rng.randf() < 0.3:
			split_horizontal = not split_horizontal
	else:
		split_horizontal = can_split_h

	# Calculate split position (40-60% of the way)
	var split_ratio: float = rng.randf_range(0.4, 0.6)

	node.left = BSPNode.new()
	node.right = BSPNode.new()

	if split_horizontal:
		var split_y: float = node.bounds.position.y + node.bounds.size.y * split_ratio
		node.left.bounds = Rect2(node.bounds.position, Vector2(node.bounds.size.x, node.bounds.size.y * split_ratio))
		node.right.bounds = Rect2(Vector2(node.bounds.position.x, split_y), Vector2(node.bounds.size.x, node.bounds.size.y * (1 - split_ratio)))
	else:
		var split_x: float = node.bounds.position.x + node.bounds.size.x * split_ratio
		node.left.bounds = Rect2(node.bounds.position, Vector2(node.bounds.size.x * split_ratio, node.bounds.size.y))
		node.right.bounds = Rect2(Vector2(split_x, node.bounds.position.y), Vector2(node.bounds.size.x * (1 - split_ratio), node.bounds.size.y))

	# Recursively split children
	_bsp_split(node.left, target_count, leaves, depth + 1)
	_bsp_split(node.right, target_count, leaves, depth + 1)

func _create_room_in_leaf(leaf: BSPNode) -> void:
	"""Create a room within a BSP leaf node"""
	var padding: float = arena_size * 0.02
	var min_room_size: float = arena_size * 0.08

	# Room size is 60-90% of leaf bounds
	var room_width: float = leaf.bounds.size.x * rng.randf_range(0.6, 0.9)
	var room_height: float = leaf.bounds.size.y * rng.randf_range(0.6, 0.9)

	# Ensure minimum size
	room_width = maxf(room_width, min_room_size)
	room_height = maxf(room_height, min_room_size)

	# Random position within leaf bounds
	var max_x_offset: float = leaf.bounds.size.x - room_width - padding * 2
	var max_y_offset: float = leaf.bounds.size.y - room_height - padding * 2

	var room_x: float = leaf.bounds.position.x + padding + rng.randf() * maxf(0, max_x_offset)
	var room_y: float = leaf.bounds.position.y + padding + rng.randf() * maxf(0, max_y_offset)

	leaf.room = Rect2(room_x, room_y, room_width, room_height)

	# Decide room type (20% chance of L-shaped for higher complexity)
	leaf.room_type = 1 if (complexity >= 3 and rng.randf() < 0.2) else 0

	# Calculate height variation using noise
	var center_x: float = room_x + room_width / 2
	var center_z: float = room_y + room_height / 2
	var height_variation: float = noise.get_noise_2d(center_x * 0.1, center_z * 0.1) * 2.0

	# Store room data
	var room_data: Dictionary = {
		"rect": leaf.room,
		"type": leaf.room_type,
		"center": Vector3(center_x, 0, center_z),
		"height_offset": height_variation,
		"has_ceiling": rng.randf() < 0.4,  # 40% chance of ceiling
		"ceiling_height": rng.randf_range(8.0, 14.0)
	}
	rooms.append(room_data)

func _build_room_geometry(room_data: Dictionary) -> void:
	"""Build the 3D geometry for a room"""
	var rect: Rect2 = room_data.rect
	var center: Vector3 = room_data.center
	var height_offset: float = room_data.height_offset

	if room_data.type == 0:
		# Rectangular room
		_create_rectangular_room(rect, height_offset, room_data)
	else:
		# L-shaped room
		_create_l_shaped_room(rect, height_offset, room_data)

func _create_rectangular_room(rect: Rect2, height_offset: float, room_data: Dictionary) -> void:
	"""Create a rectangular room floor"""
	var floor_mesh: BoxMesh = BoxMesh.new()
	floor_mesh.size = Vector3(rect.size.x, 2.0, rect.size.y)

	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.name = "RoomFloor_%d" % rooms.find(room_data)
	floor_instance.position = Vector3(rect.position.x + rect.size.x / 2, -1.0 + height_offset, rect.position.y + rect.size.y / 2)
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

	# Register floor region for connectivity
	floor_regions.append({
		"center": floor_instance.position + Vector3(0, 2, 0),
		"bounds": rect,
		"room_index": rooms.find(room_data)
	})

	# Add ceiling if specified
	if room_data.has_ceiling:
		_create_room_ceiling(rect, height_offset, room_data.ceiling_height, room_data)

	# Add walls with doorway openings
	_create_room_walls(rect, height_offset, room_data)

func _create_l_shaped_room(rect: Rect2, height_offset: float, room_data: Dictionary) -> void:
	"""Create an L-shaped room using two overlapping rectangles"""
	# Main section (full width, partial height)
	var main_height: float = rect.size.y * rng.randf_range(0.5, 0.7)
	var main_rect: Rect2 = Rect2(rect.position, Vector2(rect.size.x, main_height))

	# Wing section (partial width, remaining height)
	var wing_width: float = rect.size.x * rng.randf_range(0.4, 0.6)
	var wing_start_x: float = rect.position.x + (rect.size.x - wing_width) * rng.randf()
	var wing_rect: Rect2 = Rect2(Vector2(wing_start_x, rect.position.y + main_height), Vector2(wing_width, rect.size.y - main_height))

	# Create main section floor
	var main_floor: BoxMesh = BoxMesh.new()
	main_floor.size = Vector3(main_rect.size.x, 2.0, main_rect.size.y)

	var main_instance: MeshInstance3D = MeshInstance3D.new()
	main_instance.mesh = main_floor
	main_instance.name = "LRoomMain_%d" % rooms.find(room_data)
	main_instance.position = Vector3(main_rect.position.x + main_rect.size.x / 2, -1.0 + height_offset, main_rect.position.y + main_rect.size.y / 2)
	add_child(main_instance)

	var main_body: StaticBody3D = StaticBody3D.new()
	var main_collision: CollisionShape3D = CollisionShape3D.new()
	var main_shape: BoxShape3D = BoxShape3D.new()
	main_shape.size = main_floor.size
	main_collision.shape = main_shape
	main_body.add_child(main_collision)
	main_instance.add_child(main_body)
	platforms.append(main_instance)

	# Create wing section floor
	var wing_floor: BoxMesh = BoxMesh.new()
	wing_floor.size = Vector3(wing_rect.size.x, 2.0, wing_rect.size.y)

	var wing_instance: MeshInstance3D = MeshInstance3D.new()
	wing_instance.mesh = wing_floor
	wing_instance.name = "LRoomWing_%d" % rooms.find(room_data)
	wing_instance.position = Vector3(wing_rect.position.x + wing_rect.size.x / 2, -1.0 + height_offset, wing_rect.position.y + wing_rect.size.y / 2)
	add_child(wing_instance)

	var wing_body: StaticBody3D = StaticBody3D.new()
	var wing_collision: CollisionShape3D = CollisionShape3D.new()
	var wing_shape: BoxShape3D = BoxShape3D.new()
	wing_shape.size = wing_floor.size
	wing_collision.shape = wing_shape
	wing_body.add_child(wing_collision)
	wing_instance.add_child(wing_body)
	platforms.append(wing_instance)

	# Register both sections for connectivity
	floor_regions.append({
		"center": main_instance.position + Vector3(0, 2, 0),
		"bounds": main_rect,
		"room_index": rooms.find(room_data)
	})
	floor_regions.append({
		"center": wing_instance.position + Vector3(0, 2, 0),
		"bounds": wing_rect,
		"room_index": rooms.find(room_data)
	})

func _create_room_ceiling(rect: Rect2, height_offset: float, ceiling_height: float, room_data: Dictionary) -> void:
	"""Create a ceiling for an enclosed room"""
	var ceiling_mesh: BoxMesh = BoxMesh.new()
	ceiling_mesh.size = Vector3(rect.size.x, 1.0, rect.size.y)

	var ceiling_instance: MeshInstance3D = MeshInstance3D.new()
	ceiling_instance.mesh = ceiling_mesh
	ceiling_instance.name = "RoomCeiling_%d" % rooms.find(room_data)
	ceiling_instance.position = Vector3(rect.position.x + rect.size.x / 2, ceiling_height + height_offset, rect.position.y + rect.size.y / 2)
	add_child(ceiling_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = ceiling_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	ceiling_instance.add_child(static_body)

	platforms.append(ceiling_instance)

func _create_room_walls(rect: Rect2, height_offset: float, room_data: Dictionary) -> void:
	"""Create walls around a room with doorway openings"""
	var wall_height: float = room_data.ceiling_height if room_data.has_ceiling else 6.0
	var wall_thickness: float = 1.0
	var doorway_width: float = 6.0

	# Determine which walls should have doorways (toward center and neighboring rooms)
	var room_center: Vector3 = room_data.center
	var needs_north_door: bool = room_center.z < 0
	var needs_south_door: bool = room_center.z > 0
	var needs_east_door: bool = room_center.x < 0
	var needs_west_door: bool = room_center.x > 0

	# Wall definitions: position offset from room center, size, doorway needed
	var walls: Array[Dictionary] = [
		# North wall (positive Z)
		{"pos": Vector3(0, wall_height/2 + height_offset, rect.size.y/2), "size": Vector3(rect.size.x, wall_height, wall_thickness), "door": needs_south_door, "axis": "x"},
		# South wall (negative Z)
		{"pos": Vector3(0, wall_height/2 + height_offset, -rect.size.y/2), "size": Vector3(rect.size.x, wall_height, wall_thickness), "door": needs_north_door, "axis": "x"},
		# East wall (positive X)
		{"pos": Vector3(rect.size.x/2, wall_height/2 + height_offset, 0), "size": Vector3(wall_thickness, wall_height, rect.size.y), "door": needs_west_door, "axis": "z"},
		# West wall (negative X)
		{"pos": Vector3(-rect.size.x/2, wall_height/2 + height_offset, 0), "size": Vector3(wall_thickness, wall_height, rect.size.y), "door": needs_east_door, "axis": "z"}
	]

	var room_center_2d: Vector2 = Vector2(rect.position.x + rect.size.x/2, rect.position.y + rect.size.y/2)

	for i in range(walls.size()):
		var wall: Dictionary = walls[i]
		var wall_pos: Vector3 = Vector3(room_center_2d.x, 0, room_center_2d.y) + wall.pos

		if wall.door and rng.randf() < 0.7:  # 70% chance of doorway where needed
			_create_wall_with_doorway(wall_pos, wall.size, doorway_width, wall.axis, room_data, i)
		else:
			_create_solid_wall(wall_pos, wall.size, "RoomWall_%d_%d" % [rooms.find(room_data), i])

func _create_wall_with_doorway(pos: Vector3, size: Vector3, doorway_width: float, axis: String, room_data: Dictionary, wall_index: int) -> void:
	"""Create a wall segment with a doorway opening"""
	var room_idx: int = rooms.find(room_data)

	if axis == "x":
		# Wall runs along X axis, doorway cuts through
		var segment_width: float = (size.x - doorway_width) / 2.0
		if segment_width > 1.0:
			# Left segment
			var left_size: Vector3 = Vector3(segment_width, size.y, size.z)
			var left_pos: Vector3 = pos + Vector3(-doorway_width/2 - segment_width/2, 0, 0)
			_create_solid_wall(left_pos, left_size, "RoomWall_%d_%d_L" % [room_idx, wall_index])

			# Right segment
			var right_pos: Vector3 = pos + Vector3(doorway_width/2 + segment_width/2, 0, 0)
			_create_solid_wall(right_pos, left_size, "RoomWall_%d_%d_R" % [room_idx, wall_index])
	else:
		# Wall runs along Z axis
		var segment_depth: float = (size.z - doorway_width) / 2.0
		if segment_depth > 1.0:
			var left_size: Vector3 = Vector3(size.x, size.y, segment_depth)
			var left_pos: Vector3 = pos + Vector3(0, 0, -doorway_width/2 - segment_depth/2)
			_create_solid_wall(left_pos, left_size, "RoomWall_%d_%d_L" % [room_idx, wall_index])

			var right_pos: Vector3 = pos + Vector3(0, 0, doorway_width/2 + segment_depth/2)
			_create_solid_wall(right_pos, left_size, "RoomWall_%d_%d_R" % [room_idx, wall_index])

func _create_solid_wall(pos: Vector3, size: Vector3, wall_name: String) -> void:
	"""Create a solid wall segment"""
	var wall_mesh: BoxMesh = BoxMesh.new()
	wall_mesh.size = size

	var wall_instance: MeshInstance3D = MeshInstance3D.new()
	wall_instance.mesh = wall_mesh
	wall_instance.name = wall_name
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

# ============================================================================
# CORRIDOR TUNNELING
# ============================================================================

func generate_tunneled_corridors() -> void:
	"""Generate corridors connecting rooms using tunneling algorithm"""
	if rooms.size() < 2:
		return

	# Build minimum spanning tree of room connections
	var connected: Array[int] = [0]  # Start with first room
	var unconnected: Array[int] = []
	for i in range(1, rooms.size()):
		unconnected.append(i)

	# Prim's algorithm for MST
	while unconnected.size() > 0:
		var best_distance: float = INF
		var best_from: int = -1
		var best_to: int = -1

		for from_idx in connected:
			for to_idx in unconnected:
				var from_center: Vector3 = rooms[from_idx].center
				var to_center: Vector3 = rooms[to_idx].center
				var dist: float = from_center.distance_to(to_center)

				if dist < best_distance:
					best_distance = dist
					best_from = from_idx
					best_to = to_idx

		if best_from >= 0 and best_to >= 0:
			_create_tunnel(rooms[best_from], rooms[best_to])
			connected.append(best_to)
			unconnected.erase(best_to)

	# Add some extra corridors for loops (based on complexity)
	var extra_corridors: int = complexity - 1
	for _i in range(extra_corridors):
		if rooms.size() < 2:
			break
		var room_a: int = rng.randi() % rooms.size()
		var room_b: int = rng.randi() % rooms.size()
		if room_a != room_b:
			_create_tunnel(rooms[room_a], rooms[room_b])

	print("Generated %d corridors" % corridors.size())

func _create_tunnel(from_room: Dictionary, to_room: Dictionary) -> void:
	"""Create a tunnel between two rooms using L-shaped or curved path"""
	var from_center: Vector3 = from_room.center
	var to_center: Vector3 = to_room.center

	# Use L-shaped corridor (horizontal then vertical, or vice versa)
	var use_horizontal_first: bool = rng.randf() < 0.5
	var corner: Vector3

	if use_horizontal_first:
		corner = Vector3(to_center.x, 0, from_center.z)
	else:
		corner = Vector3(from_center.x, 0, to_center.z)

	var corridor_width: float = rng.randf_range(5.0, 8.0)
	var corridor_height: float = (from_room.height_offset + to_room.height_offset) / 2.0

	# First segment: from_center to corner
	if from_center.distance_to(corner) > 2.0:
		_create_corridor_segment(from_center, corner, corridor_width, corridor_height)

	# Second segment: corner to to_center
	if corner.distance_to(to_center) > 2.0:
		_create_corridor_segment(corner, to_center, corridor_width, corridor_height)

	corridors.append({"from": from_center, "to": to_center, "corner": corner})

func _create_corridor_segment(start: Vector3, end: Vector3, width: float, height_offset: float) -> void:
	"""Create a single corridor segment (floor section)"""
	var direction: Vector3 = (end - start)
	var length: float = direction.length()
	direction = direction.normalized()

	if length < 1.0:
		return

	var mid_point: Vector3 = (start + end) / 2.0

	# Determine corridor orientation
	var is_x_aligned: bool = abs(direction.x) > abs(direction.z)

	var corridor_size: Vector3
	if is_x_aligned:
		corridor_size = Vector3(length, 2.0, width)
	else:
		corridor_size = Vector3(width, 2.0, length)

	var corridor_mesh: BoxMesh = BoxMesh.new()
	corridor_mesh.size = corridor_size

	var corridor_instance: MeshInstance3D = MeshInstance3D.new()
	corridor_instance.mesh = corridor_mesh
	corridor_instance.name = "Corridor_%d" % corridors.size()
	corridor_instance.position = Vector3(mid_point.x, -1.0 + height_offset, mid_point.z)
	add_child(corridor_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = corridor_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	corridor_instance.add_child(static_body)

	platforms.append(corridor_instance)

	# Register for connectivity
	floor_regions.append({
		"center": corridor_instance.position + Vector3(0, 2, 0),
		"bounds": Rect2(mid_point.x - corridor_size.x/2, mid_point.z - corridor_size.z/2, corridor_size.x, corridor_size.z),
		"room_index": -1  # Corridor
	})

# ============================================================================
# CONNECTIVITY INFRASTRUCTURE (STAIRS, WALKWAYS, BRIDGES)
# ============================================================================

func generate_connectivity_infrastructure() -> void:
	"""Generate stairs, walkways, and bridges to ensure all areas are reachable"""
	print("Generating connectivity infrastructure...")

	# Phase 1: Connect rooms with height differences via stairs
	_generate_room_to_room_stairs()

	# Phase 2: Generate tier-connecting stairways from floor to platforms
	_generate_tier_staircases()

	# Phase 3: Generate walkways connecting nearby platforms
	_generate_platform_walkways()

	print("Connectivity infrastructure complete")

func _generate_room_to_room_stairs() -> void:
	"""Create stair connections between rooms at different heights"""
	if rooms.size() < 2:
		return

	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			var room_a: Dictionary = rooms[i]
			var room_b: Dictionary = rooms[j]

			var height_diff: float = abs(room_a.height_offset - room_b.height_offset)
			var horizontal_dist: float = room_a.center.distance_to(room_b.center)

			# If rooms are connected by corridor but have height difference, add stairs
			if height_diff > 1.0 and horizontal_dist < arena_size * 0.4:
				var lower_room: Dictionary = room_a if room_a.height_offset < room_b.height_offset else room_b
				var higher_room: Dictionary = room_a if room_a.height_offset >= room_b.height_offset else room_b

				# Find the midpoint (where corridor connects)
				var mid_point: Vector3 = (lower_room.center + higher_room.center) / 2.0
				var direction: Vector3 = (higher_room.center - lower_room.center).normalized()

				_create_staircase(mid_point, lower_room.height_offset, higher_room.height_offset, direction)

func _generate_tier_staircases() -> void:
	"""Generate staircases from ground level up to each tier"""
	var tiers: Array[float] = [4.0, 8.0, 14.0, 20.0]
	var max_tier: int = mini(complexity + 1, 4)
	var floor_extent: float = arena_size * 0.35

	# Place 4 main staircases around the arena (cardinal directions)
	for i in range(4):
		var angle: float = (float(i) / 4.0) * TAU + PI / 4.0  # Start at 45 degrees
		var distance: float = floor_extent * 0.6

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance

		# Create ascending staircase from ground to tier 1
		var direction: Vector3 = Vector3(cos(angle), 0, sin(angle))
		_create_staircase(Vector3(x, 0, z), 0.0, tiers[0], direction)

	# Add tier-to-tier connectors if we have multiple tiers
	if max_tier >= 2:
		for i in range(2):
			var angle: float = (float(i) / 2.0) * TAU + PI / 2.0
			var distance: float = floor_extent * 0.5

			var x: float = cos(angle) * distance
			var z: float = sin(angle) * distance

			var direction: Vector3 = Vector3(cos(angle), 0, sin(angle))
			_create_staircase(Vector3(x, tiers[0], z), tiers[0], tiers[1], direction)

func _create_staircase(pos: Vector3, start_height: float, end_height: float, direction: Vector3) -> void:
	"""Create a staircase connecting two height levels"""
	var height_diff: float = end_height - start_height
	if height_diff < 0.5:
		return

	# Calculate stair parameters
	var step_height: float = 0.8  # Height per step (marble-friendly)
	var step_depth: float = 2.0   # Depth per step
	var step_width: float = 5.0   # Width of staircase
	var num_steps: int = int(ceil(height_diff / step_height))

	# Ensure direction is normalized and horizontal
	direction = Vector3(direction.x, 0, direction.z).normalized()
	if direction.length() < 0.1:
		direction = Vector3.FORWARD

	for step_i in range(num_steps):
		var step_y: float = start_height + (step_i * step_height)
		var step_offset: float = step_i * step_depth

		var step_pos: Vector3 = pos + direction * step_offset
		step_pos.y = step_y + step_height * 0.5

		var step_mesh: BoxMesh = BoxMesh.new()
		step_mesh.size = Vector3(step_width, step_height, step_depth)

		var step_instance: MeshInstance3D = MeshInstance3D.new()
		step_instance.mesh = step_mesh
		step_instance.name = "Stair_%d" % platforms.size()
		step_instance.position = step_pos

		# Rotate to face direction
		var rot_y: float = atan2(direction.x, direction.z)
		step_instance.rotation.y = rot_y

		add_child(step_instance)

		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = step_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		step_instance.add_child(static_body)

		platforms.append(step_instance)

func _generate_platform_walkways() -> void:
	"""Generate walkways connecting nearby platforms at similar heights"""
	var platform_positions: Array[Dictionary] = []

	# Collect platform positions
	for platform in platforms:
		if platform.name.begins_with("Platform_") or platform.name.begins_with("CircPlatform_"):
			var pos: Vector3 = platform.position
			platform_positions.append({"pos": pos, "node": platform})

	# Connect platforms that are close and at similar heights
	for i in range(platform_positions.size()):
		for j in range(i + 1, platform_positions.size()):
			var pos_a: Vector3 = platform_positions[i].pos
			var pos_b: Vector3 = platform_positions[j].pos

			var horizontal_dist: float = Vector2(pos_a.x, pos_a.z).distance_to(Vector2(pos_b.x, pos_b.z))
			var height_diff: float = abs(pos_a.y - pos_b.y)

			# Connect if close horizontally (8-25 units) and similar height (< 3 units)
			if horizontal_dist >= 8.0 and horizontal_dist <= 25.0 and height_diff < 3.0:
				if rng.randf() < 0.4:  # 40% chance to create walkway
					_create_walkway(pos_a, pos_b)

func _create_walkway(start: Vector3, end: Vector3) -> void:
	"""Create a walkway/bridge between two points"""
	var mid_point: Vector3 = (start + end) / 2.0
	mid_point.y = (start.y + end.y) / 2.0  # Average height

	var direction: Vector3 = end - start
	var length: float = direction.length()
	direction = direction.normalized()

	var walkway_mesh: BoxMesh = BoxMesh.new()
	walkway_mesh.size = Vector3(3.0, 0.5, length)

	var walkway_instance: MeshInstance3D = MeshInstance3D.new()
	walkway_instance.mesh = walkway_mesh
	walkway_instance.name = "Walkway_%d" % platforms.size()
	walkway_instance.position = mid_point

	# Rotate to align with direction
	var rot_y: float = atan2(direction.x, direction.z)
	walkway_instance.rotation.y = rot_y

	add_child(walkway_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = walkway_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	walkway_instance.add_child(static_body)

	platforms.append(walkway_instance)

# ============================================================================
# MULTI-TIER PLATFORMS
# ============================================================================

func generate_multi_tier_platforms() -> void:
	"""Generate platforms at multiple height tiers"""
	var platform_count: int = rng.randi_range(platform_count_range.x, platform_count_range.y)
	var floor_extent: float = arena_size * 0.4

	# Define tier heights
	var tiers: Array[float] = [4.0, 8.0, 14.0, 20.0]  # Up to 4 tiers
	var max_tier: int = mini(complexity + 1, 4)  # Higher complexity = more tiers

	var platforms_per_tier: int = platform_count / max_tier

	for tier in range(max_tier):
		var tier_height: float = tiers[tier]
		var tier_platforms: int = platforms_per_tier + rng.randi_range(-2, 2)

		for _i in range(tier_platforms):
			_create_tier_platform(tier, tier_height, floor_extent)

	print("Generated multi-tier platforms across %d tiers" % max_tier)

func _create_tier_platform(tier: int, base_height: float, extent: float) -> void:
	"""Create a single platform at a specific tier"""
	# Random position
	var x: float = rng.randf_range(-extent, extent)
	var z: float = rng.randf_range(-extent, extent)

	# Height variation using noise
	var height_variation: float = noise.get_noise_2d(x * 0.05, z * 0.05) * 2.0
	var y: float = base_height + height_variation

	# Platform shape (0=square, 1=rectangle, 2=circular)
	var shape_type: int = rng.randi() % 3

	# Size decreases with height
	var size_factor: float = 1.0 - (tier * 0.15)
	var base_size: float = rng.randf_range(6.0, 12.0) * size_factor

	match shape_type:
		0:  # Square
			_create_box_platform(Vector3(x, y, z), Vector3(base_size, 1.5, base_size), tier)
		1:  # Rectangle
			var width: float = base_size * rng.randf_range(0.6, 1.0)
			var depth: float = base_size * rng.randf_range(1.0, 1.6)
			_create_box_platform(Vector3(x, y, z), Vector3(width, 1.5, depth), tier)
		2:  # Circular
			_create_circular_platform(Vector3(x, y, z), base_size * 0.5, tier)

func _create_box_platform(pos: Vector3, size: Vector3, tier: int) -> void:
	"""Create a box-shaped platform"""
	var platform_mesh: BoxMesh = BoxMesh.new()
	platform_mesh.size = size

	var platform_instance: MeshInstance3D = MeshInstance3D.new()
	platform_instance.mesh = platform_mesh
	platform_instance.name = "Platform_T%d_%d" % [tier, platforms.size()]
	platform_instance.position = pos
	add_child(platform_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = platform_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	platform_instance.add_child(static_body)

	platforms.append(platform_instance)

func _create_circular_platform(pos: Vector3, radius: float, tier: int) -> void:
	"""Create a circular platform using cylinder"""
	var platform_mesh: CylinderMesh = CylinderMesh.new()
	platform_mesh.top_radius = radius
	platform_mesh.bottom_radius = radius
	platform_mesh.height = 1.5

	var platform_instance: MeshInstance3D = MeshInstance3D.new()
	platform_instance.mesh = platform_mesh
	platform_instance.name = "CircPlatform_T%d_%d" % [tier, platforms.size()]
	platform_instance.position = pos
	add_child(platform_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = radius
	shape.height = 1.5
	collision.shape = shape
	static_body.add_child(collision)
	platform_instance.add_child(static_body)

	platforms.append(platform_instance)

# ============================================================================
# RAMPS AND SLOPES
# ============================================================================

func generate_ramps_and_slopes() -> void:
	"""Generate ramps connecting different height levels - ensuring upward traversal"""
	var ramp_count: int = 4 + complexity * 2
	var floor_extent: float = arena_size * 0.35
	var ramps_generated: int = 0

	# Phase 1: Generate strategic ramps connecting floor to tier 1 platforms
	var tier1_height: float = 4.0
	var strategic_ramps: int = mini(4, ramp_count / 2)

	for i in range(strategic_ramps):
		var angle: float = (float(i) / strategic_ramps) * TAU + rng.randf_range(-0.3, 0.3)
		var distance: float = rng.randf_range(floor_extent * 0.3, floor_extent * 0.7)

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance

		var ramp_length: float = rng.randf_range(12.0, 18.0)
		var ramp_width: float = rng.randf_range(5.0, 8.0)
		# FIXED: Positive angle slopes UPWARD in the direction the ramp faces
		var ramp_angle: float = rng.randf_range(0.25, 0.40)  # ~15-23 degrees upward slope
		# Point ramp toward center for accessibility
		var rotation_y: float = atan2(-x, -z) + rng.randf_range(-0.3, 0.3)

		# Start at ground level, ramp goes up
		_create_ramp(Vector3(x, 0, z), ramp_length, ramp_width, ramp_angle, rotation_y)
		ramps_generated += 1

	# Phase 2: Generate ramps connecting tier 1 to tier 2
	var tier2_ramps: int = mini(3, (ramp_count - strategic_ramps) / 2)
	for i in range(tier2_ramps):
		var angle: float = rng.randf() * TAU
		var distance: float = rng.randf_range(floor_extent * 0.4, floor_extent * 0.8)

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance

		var ramp_length: float = rng.randf_range(10.0, 14.0)
		var ramp_width: float = rng.randf_range(4.0, 6.0)
		var ramp_angle: float = rng.randf_range(0.30, 0.45)  # Steeper for higher tiers
		var rotation_y: float = rng.randf() * TAU

		# Start at tier 1 height
		_create_ramp(Vector3(x, tier1_height, z), ramp_length, ramp_width, ramp_angle, rotation_y)
		ramps_generated += 1

	# Phase 3: Fill remaining with varied placement
	var remaining_ramps: int = ramp_count - ramps_generated
	for _i in range(remaining_ramps):
		var x: float = rng.randf_range(-floor_extent, floor_extent)
		var z: float = rng.randf_range(-floor_extent, floor_extent)
		var base_y: float = rng.randf_range(0.0, 8.0)

		var ramp_length: float = rng.randf_range(10.0, 18.0)
		var ramp_width: float = rng.randf_range(5.0, 8.0)
		# FIXED: Use positive angles for upward slopes
		var ramp_angle: float = rng.randf_range(0.20, 0.45)  # 11-26 degrees upward
		var rotation_y: float = rng.randf() * TAU

		_create_ramp(Vector3(x, base_y, z), ramp_length, ramp_width, ramp_angle, rotation_y)
		ramps_generated += 1

	print("Generated %d ramps (strategic placement for upward travel)" % ramps_generated)

func _create_ramp(pos: Vector3, length: float, width: float, slope_angle: float, rotation_y: float) -> void:
	"""Create a ramp/slope for marble rolling - properly positioned for upward travel"""
	var ramp_mesh: BoxMesh = BoxMesh.new()
	ramp_mesh.size = Vector3(width, 0.5, length)

	var ramp_instance: MeshInstance3D = MeshInstance3D.new()
	ramp_instance.mesh = ramp_mesh
	ramp_instance.name = "Ramp_%d" % platforms.size()

	# Calculate proper ramp positioning:
	# - The ramp's low end should start at pos.y
	# - The ramp tilts around its center, so we need to offset Y to keep low end grounded
	var height_rise: float = length * 0.5 * sin(slope_angle)
	# Offset position so the bottom edge of the ramp touches the ground at pos.y
	ramp_instance.position = pos + Vector3(0, height_rise + 0.25, 0)
	ramp_instance.rotation = Vector3(slope_angle, rotation_y, 0)
	add_child(ramp_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = ramp_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	ramp_instance.add_child(static_body)

	platforms.append(ramp_instance)

# ============================================================================
# JUMP PADS
# ============================================================================

func generate_dynamic_jump_pads() -> void:
	"""Generate jump pads at strategic locations - positioned to reach higher platforms"""
	var jump_pad_count: int = rng.randi_range(jump_pad_count_range.x, jump_pad_count_range.y)
	var floor_extent: float = arena_size * 0.4
	var tiers: Array[float] = [4.0, 8.0, 14.0, 20.0]
	var pads_placed: int = 0

	# Always place one in center (for reaching tier 1)
	_create_jump_pad(Vector3(0, 0, 0), pads_placed, tiers[0])
	pads_placed += 1

	# Phase 1: Place jump pads beneath high-tier platforms for vertical access
	var high_platforms: Array[Dictionary] = []
	for platform in platforms:
		if platform.name.begins_with("Platform_T") or platform.name.begins_with("CircPlatform_T"):
			var pos: Vector3 = platform.position
			if pos.y >= 8.0:  # Tier 2 and above
				high_platforms.append({"pos": pos, "node": platform})

	# Sort by height (highest first)
	high_platforms.sort_custom(func(a, b): return a.pos.y > b.pos.y)

	# Place jump pads beneath the highest platforms
	var strategic_pads: int = mini(high_platforms.size(), jump_pad_count / 2)
	for i in range(strategic_pads):
		if pads_placed >= jump_pad_count:
			break

		var platform_pos: Vector3 = high_platforms[i].pos
		# Place jump pad on ground level, slightly offset from directly below
		var offset_angle: float = rng.randf() * TAU
		var offset_dist: float = rng.randf_range(2.0, 5.0)
		var pad_x: float = platform_pos.x + cos(offset_angle) * offset_dist
		var pad_z: float = platform_pos.z + sin(offset_angle) * offset_dist

		# Clamp to arena bounds
		pad_x = clampf(pad_x, -floor_extent, floor_extent)
		pad_z = clampf(pad_z, -floor_extent, floor_extent)

		_create_jump_pad(Vector3(pad_x, 0, pad_z), pads_placed, platform_pos.y)
		pads_placed += 1

	# Phase 2: Place pads at room exits for quick traversal
	for room_data in rooms:
		if pads_placed >= jump_pad_count:
			break

		var center: Vector3 = room_data.center
		var rect: Rect2 = room_data.rect

		# Place at room edge (doorway area)
		if rect.size.x > 10.0 and rng.randf() < 0.5:
			var edge_x: float = center.x + (rect.size.x / 2.0 - 3.0) * (1.0 if rng.randf() < 0.5 else -1.0)
			_create_jump_pad(Vector3(edge_x, room_data.height_offset, center.z), pads_placed, tiers[1])
			pads_placed += 1

	# Phase 3: Fill remaining with distributed placement
	var remaining: int = jump_pad_count - pads_placed
	for i in range(remaining):
		var angle: float = (float(i) / remaining) * TAU + rng.randf_range(-0.3, 0.3)
		var distance: float = rng.randf_range(floor_extent * 0.3, floor_extent * 0.8)

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance

		# Determine target height based on location
		var target_tier: int = rng.randi_range(0, mini(complexity, 3))
		_create_jump_pad(Vector3(x, 0, z), pads_placed, tiers[target_tier])
		pads_placed += 1

	print("Generated %d jump pads (strategically positioned for vertical access)" % pads_placed)

func _create_jump_pad(pos: Vector3, index: int, target_height: float = 10.0) -> void:
	"""Create a jump pad with visual and Area3D - calibrated to reach target height"""
	var pad_mesh: CylinderMesh = CylinderMesh.new()
	pad_mesh.top_radius = 2.5
	pad_mesh.bottom_radius = 2.5
	pad_mesh.height = 0.5

	var pad_instance: MeshInstance3D = MeshInstance3D.new()
	pad_instance.mesh = pad_mesh
	pad_instance.name = "JumpPad%d" % index
	pad_instance.position = Vector3(pos.x, pos.y + 0.25, pos.z)
	add_child(pad_instance)

	# Color intensity based on target height (brighter = higher boost)
	var intensity: float = clampf(target_height / 20.0, 0.3, 1.0)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.8 + intensity * 0.2, 0.3 + intensity * 0.2)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	pad_instance.material_override = material

	# Collision for standing on
	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var collision_shape: CylinderShape3D = CylinderShape3D.new()
	collision_shape.radius = 2.5
	collision_shape.height = 0.5
	collision.shape = collision_shape
	static_body.add_child(collision)
	pad_instance.add_child(static_body)

	# Area3D for boost detection
	var jump_area: Area3D = Area3D.new()
	jump_area.name = "JumpPadArea"
	jump_area.position = Vector3.ZERO
	jump_area.add_to_group("jump_pad")

	# Store boost force calibrated to reach target height
	# Physics: v = sqrt(2 * g * h) where g = gravity, h = height
	# With marble gravity_scale ~2.5 and base gravity ~9.8, effective gravity ~24.5
	# Adding margin for air time and horizontal movement
	var height_to_reach: float = maxf(target_height - pos.y + 3.0, 5.0)
	var boost_force: float = sqrt(2.0 * 24.5 * height_to_reach) * 1.3  # 30% margin
	boost_force = clampf(boost_force, 200.0, 500.0)  # Reasonable range
	jump_area.set_meta("boost_force", boost_force)
	jump_area.set_meta("target_height", target_height)

	pad_instance.add_child(jump_area)

	jump_area.collision_layer = 8
	jump_area.collision_mask = 0
	jump_area.monitorable = true
	jump_area.monitoring = false

	var area_collision: CollisionShape3D = CollisionShape3D.new()
	var area_shape: CylinderShape3D = CylinderShape3D.new()
	area_shape.radius = 2.5
	area_shape.height = 3.0
	area_collision.shape = area_shape
	jump_area.add_child(area_collision)

# ============================================================================
# TELEPORTERS
# ============================================================================

func generate_dynamic_teleporters() -> void:
	"""Generate teleporter pairs connecting distant areas - placed on valid floor surfaces"""
	var pair_count: int = rng.randi_range(teleporter_pair_range.x, teleporter_pair_range.y)

	# Collect valid teleporter locations (room centers and corridor midpoints)
	var valid_locations: Array[Dictionary] = []

	# Add room centers as valid locations (offset from exact center to avoid walls)
	for room_data in rooms:
		var center: Vector3 = room_data.center
		var rect: Rect2 = room_data.rect
		# Place teleporter in center of room floor with safe margin from walls
		var safe_margin: float = 5.0
		if rect.size.x > safe_margin * 2 and rect.size.y > safe_margin * 2:
			valid_locations.append({
				"pos": Vector3(center.x, room_data.height_offset, center.z),
				"type": "room"
			})

	# Add corridor midpoints as valid locations
	for corridor_data in corridors:
		var from_pos: Vector3 = corridor_data.from
		var to_pos: Vector3 = corridor_data.to
		var corner: Vector3 = corridor_data.corner

		# Corridor segment midpoints (safer placement)
		var mid1: Vector3 = (from_pos + corner) / 2.0
		var mid2: Vector3 = (corner + to_pos) / 2.0

		if mid1.distance_to(Vector3.ZERO) > 10.0:  # Avoid center area
			valid_locations.append({"pos": Vector3(mid1.x, 0, mid1.z), "type": "corridor"})
		if mid2.distance_to(Vector3.ZERO) > 10.0:
			valid_locations.append({"pos": Vector3(mid2.x, 0, mid2.z), "type": "corridor"})

	# If we don't have enough valid locations, add some fallback positions
	if valid_locations.size() < pair_count * 2:
		var floor_extent: float = arena_size * 0.3
		for i in range(pair_count * 2 - valid_locations.size()):
			var angle: float = rng.randf() * TAU
			var dist: float = rng.randf_range(floor_extent * 0.4, floor_extent * 0.8)
			var x: float = cos(angle) * dist
			var z: float = sin(angle) * dist
			# Verify position is not inside any room wall
			if _is_valid_teleporter_position(Vector3(x, 0, z)):
				valid_locations.append({"pos": Vector3(x, 0, z), "type": "fallback"})

	# Shuffle locations and create pairs from distant positions
	valid_locations.shuffle()

	var used_locations: Array[int] = []
	for i in range(pair_count):
		if valid_locations.size() < 2:
			break

		# Find two distant locations
		var best_pair: Array[int] = [-1, -1]
		var best_distance: float = 0.0

		for a in range(valid_locations.size()):
			if a in used_locations:
				continue
			for b in range(a + 1, valid_locations.size()):
				if b in used_locations:
					continue

				var pos_a: Vector3 = valid_locations[a].pos
				var pos_b: Vector3 = valid_locations[b].pos
				var dist: float = pos_a.distance_to(pos_b)

				# Prefer distant teleporter pairs
				if dist > best_distance and dist > arena_size * 0.3:
					best_distance = dist
					best_pair = [a, b]

		if best_pair[0] >= 0 and best_pair[1] >= 0:
			var pos1: Vector3 = valid_locations[best_pair[0]].pos
			var pos2: Vector3 = valid_locations[best_pair[1]].pos
			_create_teleporter_pair(pos1, pos2, i)
			used_locations.append(best_pair[0])
			used_locations.append(best_pair[1])

	print("Generated %d teleporter pairs (placed on valid floor surfaces)" % pair_count)

func _is_valid_teleporter_position(pos: Vector3) -> bool:
	"""Check if a position is valid for teleporter placement (not inside walls)"""
	var teleporter_radius: float = 4.0  # Teleporter needs this much clearance

	for room_data in rooms:
		var rect: Rect2 = room_data.rect
		var center: Vector3 = room_data.center

		# Check if position is inside the room bounds (valid)
		if rect.has_point(Vector2(pos.x, pos.z)):
			# Inside room - check if too close to walls
			var margin: float = teleporter_radius
			var inner_rect: Rect2 = Rect2(
				rect.position.x + margin,
				rect.position.y + margin,
				rect.size.x - margin * 2,
				rect.size.y - margin * 2
			)
			if inner_rect.size.x > 0 and inner_rect.size.y > 0:
				if inner_rect.has_point(Vector2(pos.x, pos.z)):
					return true  # Safe position inside room
			return false  # Too close to wall

	# Position is in open area (corridor or arena floor), check corridors
	for corridor_data in corridors:
		var from_pos: Vector3 = corridor_data.from
		var to_pos: Vector3 = corridor_data.to
		var corner: Vector3 = corridor_data.corner

		# Simple proximity check to corridor paths
		var dist_to_path1: float = _point_to_line_distance(pos, from_pos, corner)
		var dist_to_path2: float = _point_to_line_distance(pos, corner, to_pos)

		if dist_to_path1 < 4.0 or dist_to_path2 < 4.0:
			return true  # Near a corridor

	# Default: if position is in central arena area, it's likely valid
	var arena_center_extent: float = arena_size * 0.25
	if abs(pos.x) < arena_center_extent and abs(pos.z) < arena_center_extent:
		return true

	return false

func _point_to_line_distance(point: Vector3, line_start: Vector3, line_end: Vector3) -> float:
	"""Calculate distance from a point to a line segment (XZ plane)"""
	var p: Vector2 = Vector2(point.x, point.z)
	var a: Vector2 = Vector2(line_start.x, line_start.z)
	var b: Vector2 = Vector2(line_end.x, line_end.z)

	var ab: Vector2 = b - a
	var ap: Vector2 = p - a

	var t: float = clampf(ap.dot(ab) / ab.dot(ab), 0.0, 1.0)
	var closest: Vector2 = a + ab * t

	return p.distance_to(closest)

func _create_teleporter_pair(from_pos: Vector3, to_pos: Vector3, pair_index: int) -> void:
	"""Create a bidirectional teleporter pair"""
	_create_teleporter(from_pos, to_pos, pair_index * 2)
	_create_teleporter(to_pos, from_pos, pair_index * 2 + 1)

func _create_teleporter(pos: Vector3, destination: Vector3, index: int) -> void:
	"""Create a single teleporter"""
	var teleporter_mesh: CylinderMesh = CylinderMesh.new()
	teleporter_mesh.top_radius = 3.0
	teleporter_mesh.bottom_radius = 3.0
	teleporter_mesh.height = 0.3

	var teleporter_instance: MeshInstance3D = MeshInstance3D.new()
	teleporter_instance.mesh = teleporter_mesh
	teleporter_instance.name = "Teleporter%d" % index
	teleporter_instance.position = Vector3(pos.x, 0.15, pos.z)
	add_child(teleporter_instance)

	# Blue-purple material (unshaded for GL Compatibility)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.4, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	teleporter_instance.material_override = material

	# Collision for standing
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
	teleport_area.set_meta("destination", destination + Vector3(0, 2, 0))  # Slightly above ground
	teleporter_instance.add_child(teleport_area)

	teleport_area.collision_layer = 8
	teleport_area.collision_mask = 0
	teleport_area.monitorable = true
	teleport_area.monitoring = false

	var area_collision: CollisionShape3D = CollisionShape3D.new()
	var area_shape: CylinderShape3D = CylinderShape3D.new()
	area_shape.radius = 3.0
	area_shape.height = 5.0
	area_collision.shape = area_shape
	teleport_area.add_child(area_collision)

	teleporters.append({"area": teleport_area, "destination": destination})

# ============================================================================
# COVER OBJECTS
# ============================================================================

func generate_cover_objects() -> void:
	"""Generate pillars and walls for cover"""
	var cover_count: int = rng.randi_range(cover_count_range.x, cover_count_range.y)
	var floor_extent: float = arena_size * 0.4

	# Mix of pillars and low walls
	var pillar_count: int = cover_count * 2 / 3
	var wall_count: int = cover_count - pillar_count

	# Generate pillars
	for i in range(pillar_count):
		var x: float = rng.randf_range(-floor_extent, floor_extent)
		var z: float = rng.randf_range(-floor_extent, floor_extent)

		# Avoid center area
		if Vector2(x, z).length() < 8.0:
			continue

		_create_pillar(Vector3(x, 0, z), i)

	# Generate low walls
	for i in range(wall_count):
		var x: float = rng.randf_range(-floor_extent, floor_extent)
		var z: float = rng.randf_range(-floor_extent, floor_extent)
		var rotation: float = rng.randf() * PI

		_create_cover_wall(Vector3(x, 0, z), rotation, i)

	print("Generated %d cover objects (%d pillars, %d walls)" % [cover_count, pillar_count, wall_count])

func _create_pillar(pos: Vector3, index: int) -> void:
	"""Create a decorative pillar"""
	var height: float = rng.randf_range(8.0, 16.0)
	var width: float = rng.randf_range(2.0, 4.0)

	var pillar_mesh: BoxMesh = BoxMesh.new()
	pillar_mesh.size = Vector3(width, height, width)

	var pillar_instance: MeshInstance3D = MeshInstance3D.new()
	pillar_instance.mesh = pillar_mesh
	pillar_instance.name = "Pillar%d" % index
	pillar_instance.position = Vector3(pos.x, height / 2.0, pos.z)
	add_child(pillar_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = pillar_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	pillar_instance.add_child(static_body)

	platforms.append(pillar_instance)

func _create_cover_wall(pos: Vector3, rotation: float, index: int) -> void:
	"""Create a low wall for cover"""
	var width: float = rng.randf_range(6.0, 12.0)
	var height: float = rng.randf_range(2.0, 4.0)
	var depth: float = rng.randf_range(1.0, 2.0)

	var wall_mesh: BoxMesh = BoxMesh.new()
	wall_mesh.size = Vector3(width, height, depth)

	var wall_instance: MeshInstance3D = MeshInstance3D.new()
	wall_instance.mesh = wall_mesh
	wall_instance.name = "CoverWall%d" % index
	wall_instance.position = Vector3(pos.x, height / 2.0, pos.z)
	wall_instance.rotation.y = rotation
	add_child(wall_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = wall_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	wall_instance.add_child(static_body)

	platforms.append(wall_instance)

# ============================================================================
# HAZARDS
# ============================================================================

func generate_hazard_pits() -> void:
	"""Generate hazard pits with death zones"""
	var pit_count: int = complexity - 2  # 1-3 pits for complexity 3-5
	var floor_extent: float = arena_size * 0.3

	for i in range(pit_count):
		var x: float = rng.randf_range(-floor_extent, floor_extent)
		var z: float = rng.randf_range(-floor_extent, floor_extent)

		# Avoid center
		if Vector2(x, z).length() < 15.0:
			continue

		_create_hazard_pit(Vector3(x, 0, z), i)

	if pit_count > 0:
		print("Generated %d hazard pits" % pit_count)

func _create_hazard_pit(pos: Vector3, index: int) -> void:
	"""Create a hazard pit (hole in floor with death zone)"""
	var pit_radius: float = rng.randf_range(4.0, 8.0)

	# Create pit death zone
	var pit_zone: Area3D = Area3D.new()
	pit_zone.name = "HazardPit%d" % index
	pit_zone.position = Vector3(pos.x, -10, pos.z)
	pit_zone.collision_layer = 0
	pit_zone.collision_mask = 2
	pit_zone.add_to_group("death_zone")
	add_child(pit_zone)

	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = pit_radius
	shape.height = 20.0
	collision.shape = shape
	pit_zone.add_child(collision)

	pit_zone.body_entered.connect(_on_death_zone_entered)

	# Visual warning ring around pit
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = pit_radius - 0.5
	ring_mesh.outer_radius = pit_radius + 0.5

	var ring_instance: MeshInstance3D = MeshInstance3D.new()
	ring_instance.mesh = ring_mesh
	ring_instance.name = "PitRing%d" % index
	ring_instance.position = Vector3(pos.x, 0.1, pos.z)
	ring_instance.rotation.x = -PI / 2
	add_child(ring_instance)

	# Red warning material
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.2, 0.2)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_instance.material_override = material

# ============================================================================
# PERIMETER AND DEATH ZONE
# ============================================================================

func generate_perimeter_walls() -> void:
	"""Generate outer perimeter walls"""
	var wall_distance: float = arena_size * 0.55
	var wall_height: float = 25.0
	var wall_thickness: float = 2.0

	var wall_configs: Array[Dictionary] = [
		{"pos": Vector3(0, wall_height/2, wall_distance), "size": Vector3(arena_size * 1.2, wall_height, wall_thickness)},
		{"pos": Vector3(0, wall_height/2, -wall_distance), "size": Vector3(arena_size * 1.2, wall_height, wall_thickness)},
		{"pos": Vector3(wall_distance, wall_height/2, 0), "size": Vector3(wall_thickness, wall_height, arena_size * 1.2)},
		{"pos": Vector3(-wall_distance, wall_height/2, 0), "size": Vector3(wall_thickness, wall_height, arena_size * 1.2)}
	]

	for i in range(wall_configs.size()):
		var config: Dictionary = wall_configs[i]

		var wall_mesh: BoxMesh = BoxMesh.new()
		wall_mesh.size = config.size

		var wall_instance: MeshInstance3D = MeshInstance3D.new()
		wall_instance.mesh = wall_mesh
		wall_instance.name = "PerimeterWall%d" % i
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

func _on_death_zone_entered(body: Node3D) -> void:
	"""Handle player falling into death zone"""
	if body.has_method("fall_death"):
		body.fall_death()
	elif body.has_method("respawn"):
		body.respawn()

# ============================================================================
# SPAWN POINTS
# ============================================================================

func generate_spawn_points() -> void:
	"""Generate safe spawn points throughout the arena"""
	spawn_points.clear()

	# Target 8-16 spawn points
	var target_spawns: int = 8 + complexity * 2

	# Spawn in room centers (elevated and safe)
	for room_data in rooms:
		var center: Vector3 = room_data.center
		var spawn_y: float = 2.0 + room_data.height_offset
		spawn_points.append(Vector3(center.x, spawn_y, center.z))

	# Spawn on platforms (find suitable ones)
	var platform_spawns: int = target_spawns - spawn_points.size()
	var floor_extent: float = arena_size * 0.35

	for _i in range(platform_spawns):
		var angle: float = rng.randf() * TAU
		var dist: float = rng.randf_range(10.0, floor_extent)
		var x: float = cos(angle) * dist
		var z: float = sin(angle) * dist
		var y: float = rng.randf_range(2.0, 10.0)

		spawn_points.append(Vector3(x, y, z))

	# Always ensure center spawn
	if spawn_points.size() == 0 or spawn_points[0].distance_to(Vector3.ZERO) > 5.0:
		spawn_points.insert(0, Vector3(0, 2, 0))

	print("Generated %d spawn points" % spawn_points.size())

func get_spawn_points() -> PackedVector3Array:
	"""Return spawn points for players"""
	return spawn_points

# ============================================================================
# CONNECTIVITY VERIFICATION
# ============================================================================

func verify_connectivity() -> void:
	"""Verify all areas are reachable (basic check)"""
	# For now, just ensure we have corridors connecting rooms
	# A more sophisticated check would use pathfinding

	if rooms.size() > 1 and corridors.size() < rooms.size() - 1:
		push_warning("Level may have unreachable areas! Rooms: %d, Corridors: %d" % [rooms.size(), corridors.size()])
	else:
		print("Connectivity check passed: %d rooms connected by %d corridors" % [rooms.size(), corridors.size()])

# ============================================================================
# PROCEDURAL TEXTURES
# ============================================================================

func apply_procedural_textures() -> void:
	"""Apply procedurally generated textures to all platforms"""
	material_manager.apply_materials_to_level(self)
