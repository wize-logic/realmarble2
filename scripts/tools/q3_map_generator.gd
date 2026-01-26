@tool
extends Node

## Quake 3 Arena Map Generator
## Procedurally generates .map files using BSP (Binary Space Partitioning)
## Can be run as a tool script in the Godot editor

# ============================================================================
# CONFIGURATION
# ============================================================================

@export_group("Map Settings")
@export var map_name: String = "generated"
@export var map_seed: int = 0  # 0 = random
@export var map_width: float = 2048.0
@export var map_height: float = 2048.0
@export var room_height: float = 256.0
@export var wall_thickness: float = 16.0

@export_group("BSP Settings")
@export var min_room_size: float = 256.0
@export var max_room_size: float = 512.0
@export var min_rooms: int = 8
@export var max_rooms: int = 16
@export var room_inset_min: float = 0.75  # 75% of cell size
@export var room_inset_max: float = 0.90  # 90% of cell size

@export_group("Corridor Settings")
@export var corridor_width: float = 96.0
@export var corridor_height: float = 192.0

@export_group("Multi-Level")
@export var num_levels: int = 1
@export var level_height: float = 320.0  # Height between levels

@export_group("Entities")
@export var spawn_points: int = 8
@export var weapons_per_room: float = 0.5  # Average weapons per room
@export var health_per_room: float = 0.3
@export var armor_per_room: float = 0.2

@export_group("Textures")
@export var floor_texture: String = "gothic_floor/largeblock3b"
@export var ceiling_texture: String = "gothic_ceiling/woodceiling1a"
@export var wall_texture: String = "gothic_wall/skull4"
@export var corridor_texture: String = "gothic_block/blocks18c"
@export var caulk_texture: String = "common/caulk"

@export_group("Generation")
@export var generate_on_ready: bool = false
@export var output_path: String = "res://generated_maps/"

# ============================================================================
# BSP NODE CLASS
# ============================================================================

class BSPNode:
	var bounds: Rect2  # 2D bounding rectangle (x, z in world space)
	var left: BSPNode = null
	var right: BSPNode = null
	var is_leaf: bool = true
	var room: Rect2 = Rect2()  # Actual room within the cell (after inset)
	var room_id: int = -1
	var level: int = 0  # For multi-level support

	func _init(rect: Rect2, lvl: int = 0):
		bounds = rect
		level = lvl

	func get_center() -> Vector2:
		return room.position + room.size / 2.0

	func get_center_3d(room_height: float, level_height: float) -> Vector3:
		var center_2d = get_center()
		return Vector3(center_2d.x, level * level_height + room_height / 2.0, center_2d.y)

# ============================================================================
# BRUSH GENERATOR CLASS
# ============================================================================

class BrushGenerator:
	## Generates brush strings for .map file format

	static func create_box_brush(mins: Vector3, maxs: Vector3, textures: Dictionary) -> String:
		## Creates a 6-sided box brush
		## textures dict: {top, bottom, north, south, east, west}

		var brush: String = "{\n"

		# Get texture names with defaults
		var tex_top: String = textures.get("top", "common/caulk")
		var tex_bottom: String = textures.get("bottom", "common/caulk")
		var tex_north: String = textures.get("north", "common/caulk")
		var tex_south: String = textures.get("south", "common/caulk")
		var tex_east: String = textures.get("east", "common/caulk")
		var tex_west: String = textures.get("west", "common/caulk")

		# Top face (Y+) - normal pointing up
		brush += _plane_string(
			Vector3(mins.x, maxs.y, mins.z),
			Vector3(mins.x, maxs.y, maxs.z),
			Vector3(maxs.x, maxs.y, maxs.z),
			tex_top
		)

		# Bottom face (Y-) - normal pointing down
		brush += _plane_string(
			Vector3(mins.x, mins.y, maxs.z),
			Vector3(mins.x, mins.y, mins.z),
			Vector3(maxs.x, mins.y, mins.z),
			tex_bottom
		)

		# North face (Z+) - normal pointing +Z
		brush += _plane_string(
			Vector3(mins.x, mins.y, maxs.z),
			Vector3(maxs.x, mins.y, maxs.z),
			Vector3(maxs.x, maxs.y, maxs.z),
			tex_north
		)

		# South face (Z-) - normal pointing -Z
		brush += _plane_string(
			Vector3(maxs.x, mins.y, mins.z),
			Vector3(mins.x, mins.y, mins.z),
			Vector3(mins.x, maxs.y, mins.z),
			tex_south
		)

		# East face (X+) - normal pointing +X
		brush += _plane_string(
			Vector3(maxs.x, mins.y, mins.z),
			Vector3(maxs.x, maxs.y, mins.z),
			Vector3(maxs.x, maxs.y, maxs.z),
			tex_east
		)

		# West face (X-) - normal pointing -X
		brush += _plane_string(
			Vector3(mins.x, mins.y, maxs.z),
			Vector3(mins.x, maxs.y, maxs.z),
			Vector3(mins.x, maxs.y, mins.z),
			tex_west
		)

		brush += "}\n"
		return brush

	static func _plane_string(p1: Vector3, p2: Vector3, p3: Vector3, texture: String) -> String:
		## Format: ( x1 y1 z1 ) ( x2 y2 z2 ) ( x3 y3 z3 ) texture offsetX offsetY rotation scaleX scaleY
		return "( %d %d %d ) ( %d %d %d ) ( %d %d %d ) %s 0 0 0 0.5 0.5 0 0 0\n" % [
			int(p1.x), int(p1.y), int(p1.z),
			int(p2.x), int(p2.y), int(p2.z),
			int(p3.x), int(p3.y), int(p3.z),
			texture
		]

	static func create_room_brushes(room: Rect2, floor_z: float, height: float,
			wall_thick: float, textures: Dictionary) -> Array[String]:
		## Creates floor, ceiling, and 4 walls for a room
		var brushes: Array[String] = []

		var mins_2d: Vector2 = room.position
		var maxs_2d: Vector2 = room.position + room.size

		# Floor brush
		var floor_textures: Dictionary = {
			"top": textures.get("floor", "gothic_floor/largeblock3b"),
			"bottom": textures.get("caulk", "common/caulk"),
			"north": textures.get("caulk", "common/caulk"),
			"south": textures.get("caulk", "common/caulk"),
			"east": textures.get("caulk", "common/caulk"),
			"west": textures.get("caulk", "common/caulk")
		}
		brushes.append(create_box_brush(
			Vector3(mins_2d.x, floor_z - wall_thick, mins_2d.y),
			Vector3(maxs_2d.x, floor_z, maxs_2d.y),
			floor_textures
		))

		# Ceiling brush
		var ceil_textures: Dictionary = {
			"bottom": textures.get("ceiling", "gothic_ceiling/woodceiling1a"),
			"top": textures.get("caulk", "common/caulk"),
			"north": textures.get("caulk", "common/caulk"),
			"south": textures.get("caulk", "common/caulk"),
			"east": textures.get("caulk", "common/caulk"),
			"west": textures.get("caulk", "common/caulk")
		}
		brushes.append(create_box_brush(
			Vector3(mins_2d.x, floor_z + height, mins_2d.y),
			Vector3(maxs_2d.x, floor_z + height + wall_thick, maxs_2d.y),
			ceil_textures
		))

		var wall_tex: String = textures.get("wall", "gothic_wall/skull4")
		var caulk: String = textures.get("caulk", "common/caulk")

		# North wall (Z+)
		var north_textures: Dictionary = {
			"south": wall_tex,  # Interior face
			"north": caulk,
			"top": caulk, "bottom": caulk, "east": caulk, "west": caulk
		}
		brushes.append(create_box_brush(
			Vector3(mins_2d.x, floor_z, maxs_2d.y),
			Vector3(maxs_2d.x, floor_z + height, maxs_2d.y + wall_thick),
			north_textures
		))

		# South wall (Z-)
		var south_textures: Dictionary = {
			"north": wall_tex,  # Interior face
			"south": caulk,
			"top": caulk, "bottom": caulk, "east": caulk, "west": caulk
		}
		brushes.append(create_box_brush(
			Vector3(mins_2d.x, floor_z, mins_2d.y - wall_thick),
			Vector3(maxs_2d.x, floor_z + height, mins_2d.y),
			south_textures
		))

		# East wall (X+)
		var east_textures: Dictionary = {
			"west": wall_tex,  # Interior face
			"east": caulk,
			"top": caulk, "bottom": caulk, "north": caulk, "south": caulk
		}
		brushes.append(create_box_brush(
			Vector3(maxs_2d.x, floor_z, mins_2d.y),
			Vector3(maxs_2d.x + wall_thick, floor_z + height, maxs_2d.y),
			east_textures
		))

		# West wall (X-)
		var west_textures: Dictionary = {
			"east": wall_tex,  # Interior face
			"west": caulk,
			"top": caulk, "bottom": caulk, "north": caulk, "south": caulk
		}
		brushes.append(create_box_brush(
			Vector3(mins_2d.x - wall_thick, floor_z, mins_2d.y),
			Vector3(mins_2d.x, floor_z + height, maxs_2d.y),
			west_textures
		))

		return brushes

	static func create_corridor_brush(rect: Rect2, floor_z: float, height: float,
			wall_thick: float, textures: Dictionary) -> Array[String]:
		## Creates floor and ceiling for a corridor segment
		var brushes: Array[String] = []

		var mins: Vector2 = rect.position
		var maxs: Vector2 = rect.position + rect.size

		# Floor
		var floor_tex: Dictionary = {
			"top": textures.get("corridor", "gothic_block/blocks18c"),
			"bottom": textures.get("caulk", "common/caulk"),
			"north": textures.get("caulk", "common/caulk"),
			"south": textures.get("caulk", "common/caulk"),
			"east": textures.get("caulk", "common/caulk"),
			"west": textures.get("caulk", "common/caulk")
		}
		brushes.append(create_box_brush(
			Vector3(mins.x, floor_z - wall_thick, mins.y),
			Vector3(maxs.x, floor_z, maxs.y),
			floor_tex
		))

		# Ceiling
		var ceil_tex: Dictionary = {
			"bottom": textures.get("corridor", "gothic_block/blocks18c"),
			"top": textures.get("caulk", "common/caulk"),
			"north": textures.get("caulk", "common/caulk"),
			"south": textures.get("caulk", "common/caulk"),
			"east": textures.get("caulk", "common/caulk"),
			"west": textures.get("caulk", "common/caulk")
		}
		brushes.append(create_box_brush(
			Vector3(mins.x, floor_z + height, mins.y),
			Vector3(maxs.x, floor_z + height + wall_thick, maxs.y),
			ceil_tex
		))

		return brushes

# ============================================================================
# ENTITY PLACER CLASS
# ============================================================================

class EntityPlacer:
	## Generates entity strings for .map file

	static func point_entity(classname: String, origin: Vector3, properties: Dictionary = {}) -> String:
		var entity: String = "{\n"
		entity += "\"classname\" \"%s\"\n" % classname
		entity += "\"origin\" \"%d %d %d\"\n" % [int(origin.x), int(origin.y), int(origin.z)]

		for key in properties:
			entity += "\"%s\" \"%s\"\n" % [key, str(properties[key])]

		entity += "}\n"
		return entity

	static func spawn_point(origin: Vector3, angle: float = 0.0) -> String:
		return point_entity("info_player_deathmatch", origin, {"angle": str(int(angle))})

	static func weapon(weapon_type: String, origin: Vector3) -> String:
		return point_entity(weapon_type, origin)

	static func item(item_type: String, origin: Vector3) -> String:
		return point_entity(item_type, origin)

	static func light(origin: Vector3, intensity: int = 300, color: Color = Color.WHITE) -> String:
		var props: Dictionary = {
			"light": str(intensity),
			"_color": "%.2f %.2f %.2f" % [color.r, color.g, color.b]
		}
		return point_entity("light", origin, props)

	static func ambient_light(origin: Vector3, intensity: int = 100) -> String:
		return point_entity("light", origin, {
			"light": str(intensity),
			"_deviance": "64",
			"_samples": "4"
		})

# ============================================================================
# MAIN GENERATOR
# ============================================================================

var rng: RandomNumberGenerator
var bsp_root: BSPNode
var rooms: Array[BSPNode] = []
var corridors: Array[Dictionary] = []  # {rect: Rect2, level: int}
var brushes: Array[String] = []
var entities: Array[String] = []

func _ready() -> void:
	if generate_on_ready:
		generate_map()

func generate_map() -> void:
	"""Main entry point for map generation"""
	print("=== Q3 Map Generator ===")

	# Initialize RNG
	rng = RandomNumberGenerator.new()
	rng.seed = map_seed if map_seed != 0 else int(Time.get_unix_time_from_system())
	print("Seed: %d" % rng.seed)

	# Clear previous data
	rooms.clear()
	corridors.clear()
	brushes.clear()
	entities.clear()

	# Generate for each level
	for level in range(num_levels):
		print("Generating level %d..." % level)
		generate_level(level)

	# Generate inter-level connections (ramps/stairs)
	if num_levels > 1:
		generate_level_connections()

	# Place entities
	place_entities()

	# Write .map file
	write_map_file()

	print("Map generation complete!")
	print("Rooms: %d, Corridors: %d, Brushes: %d, Entities: %d" % [
		rooms.size(), corridors.size(), brushes.size(), entities.size()
	])

func generate_level(level: int) -> void:
	"""Generate a single level using BSP"""
	var level_z: float = level * level_height

	# Create BSP tree
	var root_rect: Rect2 = Rect2(0, 0, map_width, map_height)
	bsp_root = BSPNode.new(root_rect, level)

	# Subdivide
	subdivide_bsp(bsp_root, 0)

	# Collect leaf nodes (rooms)
	var level_rooms: Array[BSPNode] = []
	collect_leaves(bsp_root, level_rooms)

	# Assign rooms with inset
	var room_id_offset: int = rooms.size()
	for i in range(level_rooms.size()):
		var node: BSPNode = level_rooms[i]
		node.room_id = room_id_offset + i
		create_room_inset(node)
		rooms.append(node)

	print("  Level %d: %d rooms" % [level, level_rooms.size()])

	# Generate room brushes
	var textures: Dictionary = {
		"floor": floor_texture,
		"ceiling": ceiling_texture,
		"wall": wall_texture,
		"corridor": corridor_texture,
		"caulk": caulk_texture
	}

	for node in level_rooms:
		var room_brushes: Array[String] = BrushGenerator.create_room_brushes(
			node.room, level_z, room_height, wall_thickness, textures
		)
		brushes.append_array(room_brushes)

	# Generate corridors connecting sibling rooms
	generate_corridors(bsp_root, level_z, textures)

func subdivide_bsp(node: BSPNode, depth: int) -> void:
	"""Recursively subdivide BSP node"""
	var can_split_h: bool = node.bounds.size.y >= min_room_size * 2.2
	var can_split_v: bool = node.bounds.size.x >= min_room_size * 2.2

	# Stop conditions
	if depth > 6:  # Max depth
		return
	if not can_split_h and not can_split_v:
		return
	if node.bounds.size.x <= max_room_size and node.bounds.size.y <= max_room_size:
		if rng.randf() > 0.7:  # 30% chance to stop early
			return

	# Choose split direction
	var split_horizontal: bool
	if can_split_h and can_split_v:
		split_horizontal = rng.randf() > 0.5
	else:
		split_horizontal = can_split_h

	# Calculate split position
	var split_pos: float
	if split_horizontal:
		var min_pos: float = node.bounds.position.y + min_room_size
		var max_pos: float = node.bounds.position.y + node.bounds.size.y - min_room_size
		split_pos = rng.randf_range(min_pos, max_pos)

		# Create children
		node.left = BSPNode.new(
			Rect2(node.bounds.position, Vector2(node.bounds.size.x, split_pos - node.bounds.position.y)),
			node.level
		)
		node.right = BSPNode.new(
			Rect2(Vector2(node.bounds.position.x, split_pos),
				  Vector2(node.bounds.size.x, node.bounds.position.y + node.bounds.size.y - split_pos)),
			node.level
		)
	else:
		var min_pos: float = node.bounds.position.x + min_room_size
		var max_pos: float = node.bounds.position.x + node.bounds.size.x - min_room_size
		split_pos = rng.randf_range(min_pos, max_pos)

		# Create children
		node.left = BSPNode.new(
			Rect2(node.bounds.position, Vector2(split_pos - node.bounds.position.x, node.bounds.size.y)),
			node.level
		)
		node.right = BSPNode.new(
			Rect2(Vector2(split_pos, node.bounds.position.y),
				  Vector2(node.bounds.position.x + node.bounds.size.x - split_pos, node.bounds.size.y)),
			node.level
		)

	node.is_leaf = false

	# Recurse
	subdivide_bsp(node.left, depth + 1)
	subdivide_bsp(node.right, depth + 1)

func collect_leaves(node: BSPNode, result: Array[BSPNode]) -> void:
	"""Collect all leaf nodes (rooms) from BSP tree"""
	if node == null:
		return

	if node.is_leaf:
		result.append(node)
	else:
		collect_leaves(node.left, result)
		collect_leaves(node.right, result)

func create_room_inset(node: BSPNode) -> void:
	"""Create actual room rect with random inset from cell bounds"""
	var inset_factor: float = rng.randf_range(room_inset_min, room_inset_max)
	var room_size: Vector2 = node.bounds.size * inset_factor

	# Random position within cell
	var max_offset: Vector2 = node.bounds.size - room_size
	var offset: Vector2 = Vector2(
		rng.randf_range(0, max_offset.x),
		rng.randf_range(0, max_offset.y)
	)

	node.room = Rect2(node.bounds.position + offset, room_size)

	# Apply organic noise to room edges (slight perturbation)
	var noise_amount: float = 8.0
	node.room.position.x += rng.randf_range(-noise_amount, noise_amount)
	node.room.position.y += rng.randf_range(-noise_amount, noise_amount)

func generate_corridors(node: BSPNode, level_z: float, textures: Dictionary) -> void:
	"""Generate corridors connecting sibling rooms in BSP tree"""
	if node == null or node.is_leaf:
		return

	# Find rooms to connect from each subtree
	var left_room: BSPNode = get_closest_room(node.left, node.right)
	var right_room: BSPNode = get_closest_room(node.right, node.left)

	if left_room != null and right_room != null:
		create_corridor(left_room, right_room, level_z, textures)

	# Recurse
	generate_corridors(node.left, level_z, textures)
	generate_corridors(node.right, level_z, textures)

func get_closest_room(from_node: BSPNode, to_node: BSPNode) -> BSPNode:
	"""Get the room from from_node that's closest to any room in to_node"""
	if from_node == null:
		return null

	if from_node.is_leaf:
		return from_node

	var left_rooms: Array[BSPNode] = []
	var right_rooms: Array[BSPNode] = []
	collect_leaves(from_node.left, left_rooms)
	collect_leaves(from_node.right, right_rooms)

	# Find room closest to to_node's center
	var to_center: Vector2 = to_node.bounds.get_center()
	var closest: BSPNode = null
	var closest_dist: float = INF

	for room in left_rooms + right_rooms:
		var dist: float = room.get_center().distance_to(to_center)
		if dist < closest_dist:
			closest_dist = dist
			closest = room

	return closest

func create_corridor(from_room: BSPNode, to_room: BSPNode, level_z: float, textures: Dictionary) -> void:
	"""Create an L-shaped corridor between two rooms"""
	var from_center: Vector2 = from_room.get_center()
	var to_center: Vector2 = to_room.get_center()

	# Decide if L-shape goes horizontal first or vertical first
	var horizontal_first: bool = rng.randf() > 0.5

	var half_width: float = corridor_width / 2.0
	var segments: Array[Rect2] = []

	if horizontal_first:
		# Horizontal segment
		var x_min: float = minf(from_center.x, to_center.x) - half_width
		var x_max: float = maxf(from_center.x, to_center.x) + half_width
		segments.append(Rect2(x_min, from_center.y - half_width, x_max - x_min, corridor_width))

		# Vertical segment
		var y_min: float = minf(from_center.y, to_center.y) - half_width
		var y_max: float = maxf(from_center.y, to_center.y) + half_width
		segments.append(Rect2(to_center.x - half_width, y_min, corridor_width, y_max - y_min))
	else:
		# Vertical segment first
		var y_min: float = minf(from_center.y, to_center.y) - half_width
		var y_max: float = maxf(from_center.y, to_center.y) + half_width
		segments.append(Rect2(from_center.x - half_width, y_min, corridor_width, y_max - y_min))

		# Horizontal segment
		var x_min: float = minf(from_center.x, to_center.x) - half_width
		var x_max: float = maxf(from_center.x, to_center.x) + half_width
		segments.append(Rect2(x_min, to_center.y - half_width, x_max - x_min, corridor_width))

	# Create brushes for each segment
	for segment in segments:
		var corridor_brushes: Array[String] = BrushGenerator.create_corridor_brush(
			segment, level_z, corridor_height, wall_thickness, textures
		)
		brushes.append_array(corridor_brushes)
		corridors.append({"rect": segment, "level": from_room.level})

func generate_level_connections() -> void:
	"""Generate ramps/stairs between levels"""
	print("Generating inter-level connections...")

	for level in range(num_levels - 1):
		# Find a room on each level to connect
		var lower_rooms: Array[BSPNode] = []
		var upper_rooms: Array[BSPNode] = []

		for room in rooms:
			if room.level == level:
				lower_rooms.append(room)
			elif room.level == level + 1:
				upper_rooms.append(room)

		if lower_rooms.is_empty() or upper_rooms.is_empty():
			continue

		# Pick random rooms to connect
		var lower_room: BSPNode = lower_rooms[rng.randi() % lower_rooms.size()]
		var upper_room: BSPNode = upper_rooms[rng.randi() % upper_rooms.size()]

		# Create ramp brush
		create_ramp(lower_room, upper_room, level)

func create_ramp(lower_room: BSPNode, upper_room: BSPNode, lower_level: int) -> void:
	"""Create a ramp connecting two levels"""
	var lower_z: float = lower_level * level_height
	var upper_z: float = (lower_level + 1) * level_height

	var lower_center: Vector2 = lower_room.get_center()
	var upper_center: Vector2 = upper_room.get_center()

	# Create ramp geometry (simplified - just a sloped platform)
	var ramp_length: float = level_height * 3.0  # Gentle slope
	var ramp_width: float = corridor_width * 1.5

	# Direction from lower to upper
	var dir: Vector2 = (upper_center - lower_center).normalized()
	var start_pos: Vector2 = lower_center

	# For simplicity, create a series of step platforms
	var num_steps: int = 8
	var step_height: float = (upper_z - lower_z) / num_steps
	var step_depth: float = ramp_length / num_steps

	for i in range(num_steps):
		var step_z: float = lower_z + i * step_height
		var step_pos: Vector2 = start_pos + dir * (i * step_depth)

		var step_rect: Rect2 = Rect2(
			step_pos.x - ramp_width / 2.0,
			step_pos.y - step_depth / 2.0,
			ramp_width,
			step_depth * 1.5
		)

		var step_textures: Dictionary = {
			"top": corridor_texture,
			"bottom": caulk_texture,
			"north": corridor_texture,
			"south": corridor_texture,
			"east": corridor_texture,
			"west": corridor_texture
		}

		brushes.append(BrushGenerator.create_box_brush(
			Vector3(step_rect.position.x, step_z, step_rect.position.y),
			Vector3(step_rect.position.x + step_rect.size.x, step_z + step_height,
					step_rect.position.y + step_rect.size.y),
			step_textures
		))

func place_entities() -> void:
	"""Place all entities in the map"""
	print("Placing entities...")

	# Spawn points
	place_spawn_points()

	# Weapons
	place_weapons()

	# Items
	place_items()

	# Lights
	place_lights()

func place_spawn_points() -> void:
	"""Place player spawn points in rooms"""
	var available_rooms: Array[BSPNode] = rooms.duplicate()
	available_rooms.shuffle()

	var spawns_placed: int = 0
	var spawn_index: int = 0

	while spawns_placed < spawn_points and spawn_index < available_rooms.size():
		var room: BSPNode = available_rooms[spawn_index]
		var pos: Vector3 = room.get_center_3d(room_height, level_height)
		pos.y = room.level * level_height + 32.0  # Slightly above floor

		# Random angle
		var angle: float = rng.randf_range(0, 360)

		entities.append(EntityPlacer.spawn_point(pos, angle))
		spawns_placed += 1
		spawn_index += 1

	print("  Placed %d spawn points" % spawns_placed)

func place_weapons() -> void:
	"""Place weapons throughout the map"""
	var weapon_types: Array[String] = [
		"weapon_rocketlauncher",
		"weapon_railgun",
		"weapon_plasmagun",
		"weapon_lightning",
		"weapon_shotgun",
		"weapon_grenadelauncher"
	]

	var weapons_placed: int = 0

	for room in rooms:
		if rng.randf() < weapons_per_room:
			var pos: Vector3 = room.get_center_3d(room_height, level_height)
			# Offset from center
			pos.x += rng.randf_range(-room.room.size.x * 0.3, room.room.size.x * 0.3)
			pos.z += rng.randf_range(-room.room.size.y * 0.3, room.room.size.y * 0.3)
			pos.y = room.level * level_height + 32.0

			var weapon: String = weapon_types[rng.randi() % weapon_types.size()]
			entities.append(EntityPlacer.weapon(weapon, pos))
			weapons_placed += 1

	# Place weapons at corridor junctions
	for corridor in corridors:
		if rng.randf() < 0.3:
			var rect: Rect2 = corridor.rect
			var level: int = corridor.level
			var pos: Vector3 = Vector3(
				rect.position.x + rect.size.x / 2.0,
				level * level_height + 32.0,
				rect.position.y + rect.size.y / 2.0
			)

			var weapon: String = weapon_types[rng.randi() % weapon_types.size()]
			entities.append(EntityPlacer.weapon(weapon, pos))
			weapons_placed += 1

	print("  Placed %d weapons" % weapons_placed)

func place_items() -> void:
	"""Place health and armor pickups"""
	var health_items: Array[String] = ["item_health", "item_health_large", "item_health_mega"]
	var armor_items: Array[String] = ["item_armor_shard", "item_armor_combat", "item_armor_body"]

	var items_placed: int = 0

	for room in rooms:
		var base_y: float = room.level * level_height + 32.0

		# Health
		if rng.randf() < health_per_room:
			var pos: Vector3 = Vector3(
				room.room.position.x + rng.randf_range(32, room.room.size.x - 32),
				base_y,
				room.room.position.y + rng.randf_range(32, room.room.size.y - 32)
			)
			var health_type: String = health_items[rng.randi() % health_items.size()]
			entities.append(EntityPlacer.item(health_type, pos))
			items_placed += 1

		# Armor
		if rng.randf() < armor_per_room:
			var pos: Vector3 = Vector3(
				room.room.position.x + rng.randf_range(32, room.room.size.x - 32),
				base_y,
				room.room.position.y + rng.randf_range(32, room.room.size.y - 32)
			)
			var armor_type: String = armor_items[rng.randi() % armor_items.size()]
			entities.append(EntityPlacer.item(armor_type, pos))
			items_placed += 1

	print("  Placed %d items" % items_placed)

func place_lights() -> void:
	"""Place light entities for illumination"""
	var lights_placed: int = 0

	for room in rooms:
		var center: Vector3 = room.get_center_3d(room_height, level_height)
		center.y = room.level * level_height + room_height - 32.0  # Near ceiling

		# Main room light
		var intensity: int = int(rng.randf_range(200, 400))
		var color: Color = Color(
			rng.randf_range(0.8, 1.0),
			rng.randf_range(0.7, 1.0),
			rng.randf_range(0.6, 1.0)
		)
		entities.append(EntityPlacer.light(center, intensity, color))
		lights_placed += 1

		# Corner lights for larger rooms
		if room.room.size.x > 300 or room.room.size.y > 300:
			var corners: Array[Vector2] = [
				room.room.position + Vector2(64, 64),
				room.room.position + Vector2(room.room.size.x - 64, 64),
				room.room.position + Vector2(64, room.room.size.y - 64),
				room.room.position + Vector2(room.room.size.x - 64, room.room.size.y - 64)
			]

			for corner in corners:
				var corner_pos: Vector3 = Vector3(corner.x, center.y, corner.y)
				entities.append(EntityPlacer.light(corner_pos, 150))
				lights_placed += 1

	# Corridor lights
	for corridor in corridors:
		var rect: Rect2 = corridor.rect
		var level: int = corridor.level
		var center: Vector3 = Vector3(
			rect.position.x + rect.size.x / 2.0,
			level * level_height + corridor_height - 16.0,
			rect.position.y + rect.size.y / 2.0
		)
		entities.append(EntityPlacer.light(center, 150))
		lights_placed += 1

	print("  Placed %d lights" % lights_placed)

func write_map_file() -> void:
	"""Write the complete .map file"""
	# Ensure output directory exists
	var dir: DirAccess = DirAccess.open("res://")
	if dir and not dir.dir_exists(output_path):
		dir.make_dir_recursive(output_path)

	var file_path: String = output_path + map_name + ".map"
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)

	if file == null:
		push_error("Failed to open file for writing: %s" % file_path)
		return

	# Write header
	file.store_string("// Generated by Q3 Map Generator for Godot\n")
	file.store_string("// Seed: %d\n" % rng.seed)
	file.store_string("// Rooms: %d, Corridors: %d\n" % [rooms.size(), corridors.size()])
	file.store_string("\n")

	# Write worldspawn entity with all brushes
	file.store_string("{\n")
	file.store_string("\"classname\" \"worldspawn\"\n")
	file.store_string("\"message\" \"Generated Q3 Map\"\n")
	file.store_string("\"_ambient\" \"10\"\n")

	for brush in brushes:
		file.store_string(brush)

	file.store_string("}\n")

	# Write point entities
	for entity in entities:
		file.store_string(entity)

	file.close()
	print("Map written to: %s" % file_path)

# ============================================================================
# COMPILATION HELPERS
# ============================================================================

func compile_map(q3map2_path: String) -> void:
	"""Compile the map using q3map2"""
	var map_file: String = output_path + map_name + ".map"

	print("Compiling map with q3map2...")

	# BSP compile
	print("  Running BSP...")
	var bsp_result: int = OS.execute(q3map2_path, ["-v", map_file])
	if bsp_result != 0:
		push_error("BSP compile failed with code: %d" % bsp_result)
		return

	# Visibility
	print("  Running VIS...")
	var vis_result: int = OS.execute(q3map2_path, ["-vis", "-saveprt", map_file])
	if vis_result != 0:
		push_warning("VIS compile failed with code: %d" % vis_result)

	# Lighting
	print("  Running LIGHT...")
	var light_result: int = OS.execute(q3map2_path, ["-light", "-fast", "-bounce", "2", map_file])
	if light_result != 0:
		push_warning("LIGHT compile failed with code: %d" % light_result)

	print("Compilation complete!")

# ============================================================================
# ASCII ART PARSER (OPTIONAL)
# ============================================================================

func parse_ascii_art(file_path: String, scale: float = 64.0, height: float = 128.0) -> Array[String]:
	"""Parse ASCII art file and extrude into brushes"""
	var result: Array[String] = []

	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open ASCII art file: %s" % file_path)
		return result

	var content: String = file.get_as_text()
	file.close()

	var lines: PackedStringArray = content.split("\n")
	var textures: Dictionary = {
		"top": wall_texture,
		"bottom": wall_texture,
		"north": wall_texture,
		"south": wall_texture,
		"east": wall_texture,
		"west": wall_texture
	}

	for y in range(lines.size()):
		var line: String = lines[y]
		for x in range(line.length()):
			var char: String = line[x]

			if char == "#" or char == "X":  # Wall characters
				var mins: Vector3 = Vector3(x * scale, 0, y * scale)
				var maxs: Vector3 = Vector3((x + 1) * scale, height, (y + 1) * scale)
				result.append(BrushGenerator.create_box_brush(mins, maxs, textures))

	return result

# ============================================================================
# EDITOR INTEGRATION
# ============================================================================

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []

	if map_width < min_room_size * 4:
		warnings.append("Map width is too small for the minimum room size")
	if map_height < min_room_size * 4:
		warnings.append("Map height is too small for the minimum room size")
	if spawn_points < 2:
		warnings.append("Deathmatch maps should have at least 2 spawn points")

	return warnings
