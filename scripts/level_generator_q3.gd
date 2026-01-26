@tool
extends Node3D

## Quake 3 Arena Map Generator
## Procedurally generates Q3-style arenas using Binary Space Partitioning (BSP)
## Supports both runtime Godot scene generation and .map file export for Q3 compilation
##
## Features:
## - BSP-based layout generation for natural room/corridor layouts
## - Runtime mesh generation with collisions for Godot gameplay
## - .map file export with proper brush definitions
## - Entity placement (spawns, weapons, health, armor, lights)
## - Multi-level support with ramps and stairs
## - Advanced features: organic noise, ASCII art import, jump pads, teleporters
## - q3map2 compilation integration

# ============================================================================
# EXPORTED PARAMETERS
# ============================================================================

@export_group("Arena Settings")
@export var level_seed: int = 0  ## 0 = random seed based on time
@export var arena_size: float = 140.0  ## Base arena size in Godot units
@export var complexity: int = 2  ## 1=Low, 2=Medium, 3=High, 4=Extreme

@export_group("BSP Generation")
@export var use_bsp_layout: bool = false  ## Use BSP for room layout vs procedural structures (disabled by default for arena gameplay)
@export var min_room_size: float = 20.0  ## Minimum room dimension in Godot units
@export var max_bsp_depth: int = 4  ## Maximum BSP subdivision depth
@export var room_inset_min: float = 0.75  ## Room inset factor minimum (75%)
@export var room_inset_max: float = 0.90  ## Room inset factor maximum (90%)

@export_group("Map Export")
@export var export_map_file: bool = false  ## Also export .map file when generating
@export var map_name: String = "generated"
@export var output_path: String = "res://generated_maps/"
@export var room_height: float = 256.0  ## Height of rooms in .map units
@export var wall_thickness: float = 16.0

@export_group("Multi-Level")
@export var num_levels: int = 1  ## Number of vertical levels
@export var level_height_offset: float = 20.0  ## Height between levels in Godot units

@export_group("Corridor Settings")
@export var corridor_width_min: float = 4.0  ## Minimum corridor width in Godot units
@export var corridor_width_max: float = 8.0  ## Maximum corridor width in Godot units

@export_group("Textures (for .map export)")
@export var floor_texture: String = "gothic_floor/largeblock3b"
@export var ceiling_texture: String = "gothic_ceiling/woodceiling1a"
@export var wall_texture: String = "gothic_wall/skull4"
@export var corridor_texture: String = "gothic_block/blocks18c"
@export var caulk_texture: String = "common/caulk"

@export_group("Entities")
@export var target_spawn_points: int = 16
@export var weapons_per_room: float = 0.5
@export var health_per_room: float = 0.3
@export var armor_per_room: float = 0.2

# ============================================================================
# BSP NODE CLASS
# ============================================================================

class BSPNode:
	## Represents a node in the Binary Space Partition tree
	## Used for procedural room layout generation

	var bounds: Rect2  ## 2D bounding rectangle (x, z in world space)
	var left: BSPNode = null  ## Left child after split
	var right: BSPNode = null  ## Right child after split
	var is_leaf: bool = true  ## True if this node is a room (leaf)
	var room: Rect2 = Rect2()  ## Actual room rectangle after inset
	var room_id: int = -1  ## Unique identifier for this room
	var level: int = 0  ## Vertical level (for multi-level maps)
	var height_offset: float = 0.0  ## Z-offset for this room
	var connected_to: Array[int] = []  ## IDs of connected rooms

	func _init(rect: Rect2, lvl: int = 0, z_offset: float = 0.0):
		bounds = rect
		level = lvl
		height_offset = z_offset

	func get_center() -> Vector2:
		## Get 2D center of the room
		return room.position + room.size / 2.0

	func get_center_3d(room_h: float = 0.0) -> Vector3:
		## Get 3D center of the room
		var center_2d: Vector2 = get_center()
		return Vector3(center_2d.x, height_offset + room_h / 2.0, center_2d.y)

	func get_floor_center_3d() -> Vector3:
		## Get 3D position at floor level
		var center_2d: Vector2 = get_center()
		return Vector3(center_2d.x, height_offset + 1.0, center_2d.y)

# ============================================================================
# BRUSH GENERATOR CLASS (for .map file export)
# ============================================================================

class BrushGenerator:
	## Generates brush strings in Quake 3 .map file format
	## Each brush is a convex solid defined by 4-6+ planes

	static func create_box_brush(mins: Vector3, maxs: Vector3, textures: Dictionary) -> String:
		## Creates a 6-sided box brush with specified textures
		## textures dict keys: top, bottom, north, south, east, west

		var brush: String = "{\n"

		# Get texture names with caulk defaults for hidden faces
		var tex_top: String = textures.get("top", "common/caulk")
		var tex_bottom: String = textures.get("bottom", "common/caulk")
		var tex_north: String = textures.get("north", "common/caulk")
		var tex_south: String = textures.get("south", "common/caulk")
		var tex_east: String = textures.get("east", "common/caulk")
		var tex_west: String = textures.get("west", "common/caulk")

		# Top face (Y+) - three points define plane, winding order matters
		brush += _plane_string(
			Vector3(mins.x, maxs.y, mins.z),
			Vector3(mins.x, maxs.y, maxs.z),
			Vector3(maxs.x, maxs.y, maxs.z),
			tex_top
		)

		# Bottom face (Y-)
		brush += _plane_string(
			Vector3(mins.x, mins.y, maxs.z),
			Vector3(mins.x, mins.y, mins.z),
			Vector3(maxs.x, mins.y, mins.z),
			tex_bottom
		)

		# North face (Z+)
		brush += _plane_string(
			Vector3(mins.x, mins.y, maxs.z),
			Vector3(maxs.x, mins.y, maxs.z),
			Vector3(maxs.x, maxs.y, maxs.z),
			tex_north
		)

		# South face (Z-)
		brush += _plane_string(
			Vector3(maxs.x, mins.y, mins.z),
			Vector3(mins.x, mins.y, mins.z),
			Vector3(mins.x, maxs.y, mins.z),
			tex_south
		)

		# East face (X+)
		brush += _plane_string(
			Vector3(maxs.x, mins.y, mins.z),
			Vector3(maxs.x, maxs.y, mins.z),
			Vector3(maxs.x, maxs.y, maxs.z),
			tex_east
		)

		# West face (X-)
		brush += _plane_string(
			Vector3(mins.x, mins.y, maxs.z),
			Vector3(mins.x, maxs.y, maxs.z),
			Vector3(mins.x, maxs.y, mins.z),
			tex_west
		)

		brush += "}\n"
		return brush

	static func _plane_string(p1: Vector3, p2: Vector3, p3: Vector3, texture: String) -> String:
		## Format a plane definition: ( x1 y1 z1 ) ( x2 y2 z2 ) ( x3 y3 z3 ) texture params
		return "( %d %d %d ) ( %d %d %d ) ( %d %d %d ) %s 0 0 0 0.5 0.5 0 0 0\n" % [
			int(p1.x), int(p1.y), int(p1.z),
			int(p2.x), int(p2.y), int(p2.z),
			int(p3.x), int(p3.y), int(p3.z),
			texture
		]

	static func create_bevel_brush(corner: Vector3, size: float, direction: Vector3, texture: String) -> String:
		## Creates a small bevel/chamfer brush at edges to prevent BSP glitches
		## These are small triangular prisms that smooth out sharp corners

		var brush: String = "{\n"
		var half: float = size / 2.0

		# Create a small pyramid-like shape
		var base1: Vector3 = corner
		var base2: Vector3 = corner + Vector3(size, 0, 0)
		var base3: Vector3 = corner + Vector3(0, 0, size)
		var apex: Vector3 = corner + Vector3(half, size, half)

		# Bottom face
		brush += _plane_string(base1, base3, base2, texture)
		# Front face
		brush += _plane_string(base1, base2, apex, texture)
		# Left face
		brush += _plane_string(base1, apex, base3, texture)
		# Right face
		brush += _plane_string(base2, base3, apex, texture)

		brush += "}\n"
		return brush

	static func create_room_brushes(room: Rect2, floor_z: float, height: float,
			wall_thick: float, textures: Dictionary, add_bevels: bool = true) -> Array[String]:
		## Creates complete room geometry: floor, ceiling, and 4 walls
		## Optionally adds bevel brushes at corners

		var brushes: Array[String] = []
		var mins_2d: Vector2 = room.position
		var maxs_2d: Vector2 = room.position + room.size

		# Floor brush - visible top face
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

		# Ceiling brush - visible bottom face
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

		# North wall (Z+) - interior face is south-facing
		brushes.append(create_box_brush(
			Vector3(mins_2d.x, floor_z, maxs_2d.y),
			Vector3(maxs_2d.x, floor_z + height, maxs_2d.y + wall_thick),
			{"south": wall_tex, "north": caulk, "top": caulk, "bottom": caulk, "east": caulk, "west": caulk}
		))

		# South wall (Z-) - interior face is north-facing
		brushes.append(create_box_brush(
			Vector3(mins_2d.x, floor_z, mins_2d.y - wall_thick),
			Vector3(maxs_2d.x, floor_z + height, mins_2d.y),
			{"north": wall_tex, "south": caulk, "top": caulk, "bottom": caulk, "east": caulk, "west": caulk}
		))

		# East wall (X+) - interior face is west-facing
		brushes.append(create_box_brush(
			Vector3(maxs_2d.x, floor_z, mins_2d.y),
			Vector3(maxs_2d.x + wall_thick, floor_z + height, maxs_2d.y),
			{"west": wall_tex, "east": caulk, "top": caulk, "bottom": caulk, "north": caulk, "south": caulk}
		))

		# West wall (X-) - interior face is east-facing
		brushes.append(create_box_brush(
			Vector3(mins_2d.x - wall_thick, floor_z, mins_2d.y),
			Vector3(mins_2d.x, floor_z + height, maxs_2d.y),
			{"east": wall_tex, "west": caulk, "top": caulk, "bottom": caulk, "north": caulk, "south": caulk}
		))

		# Add bevel brushes at corners to prevent BSP errors
		if add_bevels:
			var bevel_size: float = 8.0
			var corners: Array = [
				Vector3(mins_2d.x, floor_z, mins_2d.y),
				Vector3(maxs_2d.x - bevel_size, floor_z, mins_2d.y),
				Vector3(mins_2d.x, floor_z, maxs_2d.y - bevel_size),
				Vector3(maxs_2d.x - bevel_size, floor_z, maxs_2d.y - bevel_size)
			]
			for corner in corners:
				brushes.append(create_bevel_brush(corner, bevel_size, Vector3.UP, caulk))

		return brushes

	static func create_corridor_brushes(rect: Rect2, floor_z: float, height: float,
			wall_thick: float, textures: Dictionary) -> Array[String]:
		## Creates floor and ceiling for a corridor segment (walls are implicit from room layout)

		var brushes: Array[String] = []
		var mins: Vector2 = rect.position
		var maxs: Vector2 = rect.position + rect.size

		var corridor_tex: String = textures.get("corridor", "gothic_block/blocks18c")
		var caulk: String = textures.get("caulk", "common/caulk")

		# Floor
		brushes.append(create_box_brush(
			Vector3(mins.x, floor_z - wall_thick, mins.y),
			Vector3(maxs.x, floor_z, maxs.y),
			{"top": corridor_tex, "bottom": caulk, "north": caulk, "south": caulk, "east": caulk, "west": caulk}
		))

		# Ceiling
		brushes.append(create_box_brush(
			Vector3(mins.x, floor_z + height, mins.y),
			Vector3(maxs.x, floor_z + height + wall_thick, maxs.y),
			{"bottom": corridor_tex, "top": caulk, "north": caulk, "south": caulk, "east": caulk, "west": caulk}
		))

		return brushes

	static func create_ramp_brush(start: Vector3, end: Vector3, width: float, texture: String) -> String:
		## Creates a sloped ramp brush connecting two heights

		var dir: Vector3 = (end - start).normalized()
		var length: float = start.distance_to(end)
		var height_diff: float = end.y - start.y

		# Calculate perpendicular direction for width
		var perp: Vector3 = dir.cross(Vector3.UP).normalized() * (width / 2.0)

		var brush: String = "{\n"

		# Define the 8 corners of the ramp
		var b1: Vector3 = start - perp
		var b2: Vector3 = start + perp
		var b3: Vector3 = Vector3(end.x, start.y, end.z) + perp
		var b4: Vector3 = Vector3(end.x, start.y, end.z) - perp
		var t1: Vector3 = Vector3(start.x, start.y + 16, start.z) - perp
		var t2: Vector3 = Vector3(start.x, start.y + 16, start.z) + perp
		var t3: Vector3 = end + perp
		var t4: Vector3 = end - perp

		# Bottom face
		brush += _plane_string(b1, b2, b3, "common/caulk")
		# Top sloped face
		brush += _plane_string(t1, t4, t3, texture)
		# Front face
		brush += _plane_string(b3, b4, t4, "common/caulk")
		# Back face
		brush += _plane_string(b1, t1, t2, "common/caulk")
		# Left face
		brush += _plane_string(b1, b4, t4, "common/caulk")
		# Right face
		brush += _plane_string(b2, t2, t3, "common/caulk")

		brush += "}\n"
		return brush

# ============================================================================
# ENTITY PLACER CLASS
# ============================================================================

class EntityPlacer:
	## Generates entity strings for Quake 3 .map file format

	static func point_entity(classname: String, origin: Vector3, properties: Dictionary = {}) -> String:
		## Creates a point entity with specified class and properties
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

	static func func_static(origin: Vector3, model: String) -> String:
		return point_entity("misc_model", origin, {"model": model})

	static func trigger_push(origin: Vector3, size: Vector3, target: String) -> String:
		return point_entity("trigger_push", origin, {
			"target": target,
			"mins": "%d %d %d" % [int(-size.x/2), int(-size.y/2), int(-size.z/2)],
			"maxs": "%d %d %d" % [int(size.x/2), int(size.y/2), int(size.z/2)]
		})

	static func target_position(name: String, origin: Vector3) -> String:
		return point_entity("target_position", origin, {"targetname": name})

# ============================================================================
# STRUCTURE TYPES
# ============================================================================

enum StructureType {
	PILLAR,           ## Tall column
	TIERED_PLATFORM,  ## Stacked platforms
	L_WALL,           ## L-shaped cover wall
	BUNKER,           ## Semi-enclosed room
	JUMP_TOWER,       ## Platform with jump pad
	CATWALK,          ## Elevated walkway
	RAMP_PLATFORM,    ## Platform with ramp access
	SPLIT_LEVEL,      ## Two-height section
	ARCHWAY,          ## Pass-through structure
	SNIPER_NEST       ## High vantage point
}

# ============================================================================
# INTERNAL STATE
# ============================================================================

var rng: RandomNumberGenerator
var bsp_root: BSPNode
var bsp_rooms: Array[BSPNode] = []
var corridors: Array[Dictionary] = []  # {segments: Array[Rect2], level: int}
var platforms: Array[MeshInstance3D] = []  # Runtime mesh instances
var teleporters: Array[Dictionary] = []
var clear_positions: Array[Vector3] = []  # Valid spawn positions
var occupied_cells: Dictionary = {}  # Grid-based collision

# For .map export
var map_brushes: Array[String] = []
var map_entities: Array[String] = []

# Grid system for structure placement
const CELL_SIZE: float = 8.0

# Material manager for runtime textures
var material_manager = preload("res://scripts/procedural_material_manager.gd").new()

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	if not Engine.is_editor_hint():
		generate_level()

func generate_level() -> void:
	## Main entry point - generates the complete level

	# Initialize random number generator
	rng = RandomNumberGenerator.new()
	rng.seed = level_seed if level_seed != 0 else int(Time.get_unix_time_from_system())

	print("=== Q3 ARENA LEVEL GENERATOR ===")
	print("Seed: %d" % rng.seed)
	print("Arena Size: %.1f" % arena_size)
	print("Complexity: %d" % complexity)
	print("BSP Layout: %s" % ("Enabled" if use_bsp_layout else "Disabled"))
	print("Levels: %d" % num_levels)

	# Clear previous data
	clear_level()

	if use_bsp_layout:
		# Generate using BSP algorithm
		generate_bsp_level()
	else:
		# Generate using procedural structures (original method)
		generate_procedural_level()

	# Add interactive elements
	generate_jump_pads()
	generate_teleporters()

	# Boundaries
	generate_perimeter_walls()
	generate_death_zone()

	# Apply materials
	apply_procedural_textures()

	# Export .map file if enabled
	if export_map_file:
		export_to_map_file()

	print("=== GENERATION COMPLETE ===")
	print("Rooms: %d, Corridors: %d, Platforms: %d" % [bsp_rooms.size(), corridors.size(), platforms.size()])
	print("Spawn positions: %d" % clear_positions.size())

func clear_level() -> void:
	## Remove all generated content
	for child in get_children():
		child.queue_free()

	platforms.clear()
	teleporters.clear()
	clear_positions.clear()
	occupied_cells.clear()
	bsp_rooms.clear()
	corridors.clear()
	map_brushes.clear()
	map_entities.clear()
	bsp_root = null

# ============================================================================
# BSP LEVEL GENERATION
# ============================================================================

func generate_bsp_level() -> void:
	## Generate level layout using Binary Space Partitioning

	var scale: float = arena_size / 140.0
	var map_size: float = arena_size * 0.8  # Actual playable area

	# Generate BSP tree for each level
	for level_idx in range(num_levels):
		var level_z: float = level_idx * level_height_offset
		generate_bsp_for_level(level_idx, level_z, map_size)

	# Generate connections between levels
	if num_levels > 1:
		generate_level_ramps()

func generate_bsp_for_level(level_idx: int, level_z: float, map_size: float) -> void:
	## Generate BSP tree for a single level

	var half_size: float = map_size / 2.0
	var root_rect: Rect2 = Rect2(-half_size, -half_size, map_size, map_size)

	# Create BSP root for this level
	var level_root: BSPNode = BSPNode.new(root_rect, level_idx, level_z)

	if level_idx == 0:
		bsp_root = level_root

	# Subdivide recursively
	subdivide_bsp(level_root, 0)

	# Collect leaf nodes (rooms)
	var level_rooms: Array[BSPNode] = []
	collect_leaves(level_root, level_rooms)

	# Apply room insets with organic noise
	var room_id_offset: int = bsp_rooms.size()
	for i in range(level_rooms.size()):
		var node: BSPNode = level_rooms[i]
		node.room_id = room_id_offset + i
		create_room_with_noise(node)
		bsp_rooms.append(node)

	print("Level %d: %d rooms generated" % [level_idx, level_rooms.size()])

	# Generate runtime geometry for rooms
	for node in level_rooms:
		generate_room_geometry(node)

	# Connect rooms with corridors
	generate_bsp_corridors(level_root, level_z)

func subdivide_bsp(node: BSPNode, depth: int) -> void:
	## Recursively subdivide a BSP node

	# Adjust min room size based on arena size
	var effective_min_size: float = min_room_size * (arena_size / 140.0)

	var can_split_h: bool = node.bounds.size.y >= effective_min_size * 2.2
	var can_split_v: bool = node.bounds.size.x >= effective_min_size * 2.2

	# Stop conditions
	if depth >= max_bsp_depth:
		return
	if not can_split_h and not can_split_v:
		return

	# Random early termination based on size
	if node.bounds.size.x <= effective_min_size * 1.5 and node.bounds.size.y <= effective_min_size * 1.5:
		if rng.randf() > 0.6:  # 40% chance to stop early for variety
			return

	# Choose split direction - prefer splitting the longer dimension
	var split_horizontal: bool
	if can_split_h and can_split_v:
		if node.bounds.size.y > node.bounds.size.x * 1.3:
			split_horizontal = true
		elif node.bounds.size.x > node.bounds.size.y * 1.3:
			split_horizontal = false
		else:
			split_horizontal = rng.randf() > 0.5
	else:
		split_horizontal = can_split_h

	# Calculate split position with some randomness
	var split_ratio: float = rng.randf_range(0.35, 0.65)  # 35-65% split

	if split_horizontal:
		var split_y: float = node.bounds.position.y + node.bounds.size.y * split_ratio

		node.left = BSPNode.new(
			Rect2(node.bounds.position, Vector2(node.bounds.size.x, split_y - node.bounds.position.y)),
			node.level, node.height_offset
		)
		node.right = BSPNode.new(
			Rect2(Vector2(node.bounds.position.x, split_y),
				  Vector2(node.bounds.size.x, node.bounds.position.y + node.bounds.size.y - split_y)),
			node.level, node.height_offset
		)
	else:
		var split_x: float = node.bounds.position.x + node.bounds.size.x * split_ratio

		node.left = BSPNode.new(
			Rect2(node.bounds.position, Vector2(split_x - node.bounds.position.x, node.bounds.size.y)),
			node.level, node.height_offset
		)
		node.right = BSPNode.new(
			Rect2(Vector2(split_x, node.bounds.position.y),
				  Vector2(node.bounds.position.x + node.bounds.size.x - split_x, node.bounds.size.y)),
			node.level, node.height_offset
		)

	node.is_leaf = false

	# Recurse
	subdivide_bsp(node.left, depth + 1)
	subdivide_bsp(node.right, depth + 1)

func collect_leaves(node: BSPNode, result: Array[BSPNode]) -> void:
	## Collect all leaf nodes (rooms) from a BSP tree
	if node == null:
		return

	if node.is_leaf:
		result.append(node)
	else:
		collect_leaves(node.left, result)
		collect_leaves(node.right, result)

func create_room_with_noise(node: BSPNode) -> void:
	## Create room rectangle with inset and organic noise

	var inset_factor: float = rng.randf_range(room_inset_min, room_inset_max)
	var room_size: Vector2 = node.bounds.size * inset_factor

	# Center the room with some random offset
	var max_offset: Vector2 = node.bounds.size - room_size
	var offset: Vector2 = Vector2(
		rng.randf_range(max_offset.x * 0.2, max_offset.x * 0.8),
		rng.randf_range(max_offset.y * 0.2, max_offset.y * 0.8)
	)

	node.room = Rect2(node.bounds.position + offset, room_size)

	# Apply organic noise to edges (subtle perturbation)
	var noise_amount: float = 4.0 * (arena_size / 140.0)
	node.room.position.x += rng.randf_range(-noise_amount, noise_amount)
	node.room.position.y += rng.randf_range(-noise_amount, noise_amount)
	node.room.size.x += rng.randf_range(-noise_amount * 0.5, noise_amount * 0.5)
	node.room.size.y += rng.randf_range(-noise_amount * 0.5, noise_amount * 0.5)

	# Ensure minimum size
	var min_dim: float = 16.0 * (arena_size / 140.0)
	node.room.size.x = maxf(node.room.size.x, min_dim)
	node.room.size.y = maxf(node.room.size.y, min_dim)

func generate_room_geometry(node: BSPNode) -> void:
	## Generate runtime Godot geometry for a BSP room

	var room: Rect2 = node.room
	var floor_y: float = node.height_offset
	var scale: float = arena_size / 140.0

	# Floor
	add_platform_with_collision(
		Vector3(room.position.x + room.size.x / 2.0, floor_y - 0.5, room.position.y + room.size.y / 2.0),
		Vector3(room.size.x, 1.0, room.size.y),
		"BSPRoom%d_Floor" % node.room_id
	)

	# Add room center as spawn position
	clear_positions.append(Vector3(
		room.position.x + room.size.x / 2.0,
		floor_y + 2.0,
		room.position.y + room.size.y / 2.0
	))

	# Optional height variations for larger rooms
	if room.size.x > 30 * scale and room.size.y > 30 * scale and rng.randf() > 0.5:
		var raised_size: float = minf(room.size.x, room.size.y) * rng.randf_range(0.3, 0.5)
		var raised_height: float = rng.randf_range(1.0, 3.0) * scale
		var raised_offset: Vector2 = Vector2(
			rng.randf_range(raised_size, room.size.x - raised_size),
			rng.randf_range(raised_size, room.size.y - raised_size)
		)

		add_platform_with_collision(
			Vector3(room.position.x + raised_offset.x, floor_y + raised_height / 2.0, room.position.y + raised_offset.y),
			Vector3(raised_size, raised_height, raised_size),
			"BSPRoom%d_Raised" % node.room_id
		)

		clear_positions.append(Vector3(
			room.position.x + raised_offset.x,
			floor_y + raised_height + 2.0,
			room.position.y + raised_offset.y
		))

func generate_bsp_corridors(node: BSPNode, level_z: float) -> void:
	## Generate corridors connecting BSP sibling rooms

	if node == null or node.is_leaf:
		return

	# Find closest rooms from each subtree to connect
	var left_room: BSPNode = get_closest_room_to_sibling(node.left, node.right)
	var right_room: BSPNode = get_closest_room_to_sibling(node.right, node.left)

	if left_room != null and right_room != null:
		create_corridor_geometry(left_room, right_room, level_z)

	# Recurse to connect child subtrees
	generate_bsp_corridors(node.left, level_z)
	generate_bsp_corridors(node.right, level_z)

func get_closest_room_to_sibling(from_node: BSPNode, to_node: BSPNode) -> BSPNode:
	## Get the room from from_node that's closest to any room in to_node

	if from_node == null:
		return null

	if from_node.is_leaf:
		return from_node

	var all_rooms: Array[BSPNode] = []
	collect_leaves(from_node, all_rooms)

	if all_rooms.is_empty():
		return null

	var to_center: Vector2 = to_node.bounds.get_center()
	var closest: BSPNode = null
	var closest_dist: float = INF

	for room in all_rooms:
		var dist: float = room.get_center().distance_to(to_center)
		if dist < closest_dist:
			closest_dist = dist
			closest = room

	return closest

func create_corridor_geometry(from_room: BSPNode, to_room: BSPNode, level_z: float) -> void:
	## Create L-shaped or Z-shaped corridor geometry between two rooms

	var from_center: Vector2 = from_room.get_center()
	var to_center: Vector2 = to_room.get_center()

	var corridor_w: float = rng.randf_range(corridor_width_min, corridor_width_max) * (arena_size / 140.0)
	var half_width: float = corridor_w / 2.0

	# Choose corridor shape: L-shape or Z-shape
	var use_z_shape: bool = rng.randf() > 0.7 and absf(from_center.x - to_center.x) > corridor_w * 3 and absf(from_center.y - to_center.y) > corridor_w * 3

	var segments: Array[Rect2] = []

	if use_z_shape:
		# Z-shaped corridor with 3 segments
		var mid_x: float = (from_center.x + to_center.x) / 2.0

		# First horizontal segment
		var x1_min: float = minf(from_center.x, mid_x) - half_width
		var x1_max: float = maxf(from_center.x, mid_x) + half_width
		segments.append(Rect2(x1_min, from_center.y - half_width, x1_max - x1_min, corridor_w))

		# Vertical connector
		var y_min: float = minf(from_center.y, to_center.y) - half_width
		var y_max: float = maxf(from_center.y, to_center.y) + half_width
		segments.append(Rect2(mid_x - half_width, y_min, corridor_w, y_max - y_min))

		# Second horizontal segment
		var x2_min: float = minf(mid_x, to_center.x) - half_width
		var x2_max: float = maxf(mid_x, to_center.x) + half_width
		segments.append(Rect2(x2_min, to_center.y - half_width, x2_max - x2_min, corridor_w))
	else:
		# L-shaped corridor
		var horizontal_first: bool = rng.randf() > 0.5

		if horizontal_first:
			# Horizontal then vertical
			var x_min: float = minf(from_center.x, to_center.x) - half_width
			var x_max: float = maxf(from_center.x, to_center.x) + half_width
			segments.append(Rect2(x_min, from_center.y - half_width, x_max - x_min, corridor_w))

			var y_min: float = minf(from_center.y, to_center.y) - half_width
			var y_max: float = maxf(from_center.y, to_center.y) + half_width
			segments.append(Rect2(to_center.x - half_width, y_min, corridor_w, y_max - y_min))
		else:
			# Vertical then horizontal
			var y_min: float = minf(from_center.y, to_center.y) - half_width
			var y_max: float = maxf(from_center.y, to_center.y) + half_width
			segments.append(Rect2(from_center.x - half_width, y_min, corridor_w, y_max - y_min))

			var x_min: float = minf(from_center.x, to_center.x) - half_width
			var x_max: float = maxf(from_center.x, to_center.x) + half_width
			segments.append(Rect2(x_min, to_center.y - half_width, x_max - x_min, corridor_w))

	# Create geometry for each segment
	for segment in segments:
		add_platform_with_collision(
			Vector3(segment.position.x + segment.size.x / 2.0, level_z - 0.5, segment.position.y + segment.size.y / 2.0),
			Vector3(segment.size.x, 1.0, segment.size.y),
			"Corridor_%d_%d" % [from_room.room_id, to_room.room_id]
		)

	# Store corridor data
	corridors.append({
		"segments": segments,
		"level": from_room.level,
		"from_room": from_room.room_id,
		"to_room": to_room.room_id
	})

	# Mark rooms as connected
	from_room.connected_to.append(to_room.room_id)
	to_room.connected_to.append(from_room.room_id)

	# Add corridor junction as spawn point
	if segments.size() > 1:
		var junction: Rect2 = segments[0] if segments.size() == 2 else segments[1]
		clear_positions.append(Vector3(
			junction.position.x + junction.size.x / 2.0,
			level_z + 2.0,
			junction.position.y + junction.size.y / 2.0
		))

func generate_level_ramps() -> void:
	## Generate ramps connecting different vertical levels

	for level_idx in range(num_levels - 1):
		# Find rooms on each level
		var lower_rooms: Array[BSPNode] = []
		var upper_rooms: Array[BSPNode] = []

		for room in bsp_rooms:
			if room.level == level_idx:
				lower_rooms.append(room)
			elif room.level == level_idx + 1:
				upper_rooms.append(room)

		if lower_rooms.is_empty() or upper_rooms.is_empty():
			continue

		# Connect random rooms with ramp/stairs
		var lower_room: BSPNode = lower_rooms[rng.randi() % lower_rooms.size()]
		var upper_room: BSPNode = upper_rooms[rng.randi() % upper_rooms.size()]

		create_ramp_geometry(lower_room, upper_room)

func create_ramp_geometry(lower_room: BSPNode, upper_room: BSPNode) -> void:
	## Create ramp or stairs connecting two levels

	var lower_center: Vector3 = lower_room.get_floor_center_3d()
	var upper_center: Vector3 = upper_room.get_floor_center_3d()
	var height_diff: float = upper_center.y - lower_center.y

	var scale: float = arena_size / 140.0
	var ramp_width: float = corridor_width_max * scale
	var ramp_length: float = height_diff * 3.0  # Gentle slope

	# Create steps for the ramp
	var num_steps: int = int(height_diff / (2.0 * scale)) + 1
	var step_height: float = height_diff / num_steps
	var step_depth: float = ramp_length / num_steps

	var dir: Vector2 = (Vector2(upper_center.x, upper_center.z) - Vector2(lower_center.x, lower_center.z)).normalized()
	var start_pos: Vector2 = Vector2(lower_center.x, lower_center.z) + dir * 10.0

	for i in range(num_steps):
		var step_z: float = lower_center.y + i * step_height
		var step_pos: Vector2 = start_pos + dir * (i * step_depth)

		add_platform_with_collision(
			Vector3(step_pos.x, step_z + step_height / 2.0, step_pos.y),
			Vector3(ramp_width, step_height, step_depth * 1.2),
			"LevelRamp_%d_Step%d" % [lower_room.level, i]
		)

	# Add spawn point at ramp midpoint
	var mid_idx: int = num_steps / 2
	var mid_pos: Vector2 = start_pos + dir * (mid_idx * step_depth)
	clear_positions.append(Vector3(mid_pos.x, lower_center.y + height_diff / 2.0 + 2.0, mid_pos.y))

# ============================================================================
# PROCEDURAL STRUCTURE GENERATION (Alternative to BSP)
# ============================================================================

func generate_procedural_level() -> void:
	## Generate level using procedural structure placement (original method)

	generate_main_arena()

	var structure_budget: int = get_structure_budget()
	print("Structure budget: %d" % structure_budget)

	generate_procedural_structures(structure_budget)
	generate_procedural_bridges()

func get_structure_budget() -> int:
	## Calculate number of structures based on complexity and size
	var base_count: int = 6 + complexity * 3  # 9, 12, 15, 18
	var size_bonus: int = int((arena_size - 140.0) / 30.0)
	return base_count + size_bonus

func generate_main_arena() -> void:
	## Generate main floor platform

	var floor_size: float = arena_size * 0.6
	var scale: float = arena_size / 140.0

	add_platform_with_collision(
		Vector3(0, -1, 0),
		Vector3(floor_size, 2.0, floor_size),
		"MainArenaFloor"
	)

	mark_cell_occupied(Vector3.ZERO, 0)
	clear_positions.append(Vector3(0, 0, 0))

	# Add height variations for higher complexity
	if complexity >= 2:
		var num_raised: int = rng.randi_range(1, complexity)
		for i in range(num_raised):
			var pos: Vector3 = get_random_arena_position()
			if is_cell_available(pos, 1):
				var section_size: float = rng.randf_range(8.0, 16.0) * scale
				var section_height: float = rng.randf_range(0.5, 1.5)
				add_platform_with_collision(
					Vector3(pos.x, section_height / 2.0, pos.z),
					Vector3(section_size, section_height, section_size),
					"RaisedSection%d" % i
				)
				clear_positions.append(Vector3(pos.x, section_height + 0.5, pos.z))

func generate_procedural_structures(budget: int) -> void:
	## Place random structures within budget

	var scale: float = arena_size / 140.0
	var attempts: int = 0
	var max_attempts: int = budget * 10
	var structures_placed: int = 0

	# Available structure types based on complexity
	var available_types: Array = [StructureType.PILLAR, StructureType.TIERED_PLATFORM]
	if complexity >= 2:
		available_types.append_array([StructureType.L_WALL, StructureType.RAMP_PLATFORM, StructureType.CATWALK])
	if complexity >= 3:
		available_types.append_array([StructureType.BUNKER, StructureType.JUMP_TOWER, StructureType.ARCHWAY])
	if complexity >= 4:
		available_types.append_array([StructureType.SPLIT_LEVEL, StructureType.SNIPER_NEST])

	while structures_placed < budget and attempts < max_attempts:
		attempts += 1

		var pos: Vector3 = get_random_arena_position()
		var struct_type: int = available_types[rng.randi() % available_types.size()]
		var cell_radius: int = get_structure_cell_radius(struct_type)

		if is_cell_available(pos, cell_radius):
			generate_structure(struct_type, pos, scale, structures_placed)
			mark_cell_occupied(pos, cell_radius)
			structures_placed += 1

	print("Placed %d/%d structures" % [structures_placed, budget])

func get_structure_cell_radius(type: int) -> int:
	match type:
		StructureType.PILLAR, StructureType.TIERED_PLATFORM, StructureType.JUMP_TOWER, StructureType.SNIPER_NEST:
			return 0
		StructureType.L_WALL, StructureType.RAMP_PLATFORM:
			return 0
		StructureType.BUNKER, StructureType.ARCHWAY, StructureType.CATWALK, StructureType.SPLIT_LEVEL:
			return 1
	return 0

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
	var width: float = rng.randf_range(2.0, 4.0) * scale
	var height: float = rng.randf_range(6.0, 14.0) * scale

	add_platform_with_collision(
		Vector3(pos.x, height / 2.0, pos.z),
		Vector3(width, height, width),
		"Pillar%d" % index
	)

	if rng.randf() > 0.4:
		var platform_size: float = width * rng.randf_range(1.5, 2.5)
		add_platform_with_collision(
			Vector3(pos.x, height + 0.5, pos.z),
			Vector3(platform_size, 1.0, platform_size),
			"PillarTop%d" % index
		)
		clear_positions.append(Vector3(pos.x, height + 1.5, pos.z))

func generate_tiered_platform(pos: Vector3, scale: float, index: int) -> void:
	var num_tiers: int = rng.randi_range(2, 3 + complexity / 2)
	var base_size: float = rng.randf_range(6.0, 10.0) * scale
	var tier_height: float = rng.randf_range(2.5, 4.0) * scale

	for i in range(num_tiers):
		var tier_size: float = base_size * (1.0 - i * 0.2)
		var height: float = tier_height * (i + 1)

		add_platform_with_collision(
			Vector3(pos.x, height - tier_height / 2.0, pos.z),
			Vector3(tier_size, tier_height * 0.3, tier_size),
			"TieredPlatform%d_%d" % [index, i]
		)
		clear_positions.append(Vector3(pos.x, height + 0.5, pos.z))

func generate_l_wall(pos: Vector3, scale: float, index: int) -> void:
	var wall_length: float = rng.randf_range(6.0, 12.0) * scale
	var wall_height: float = rng.randf_range(3.0, 6.0) * scale
	var wall_thickness: float = 1.0 * scale
	var rotation: float = rng.randf() * TAU

	var v_offset: Vector3 = Vector3(wall_length / 2.0, 0, 0).rotated(Vector3.UP, rotation)
	add_platform_with_collision(
		Vector3(pos.x + v_offset.x, wall_height / 2.0, pos.z + v_offset.z),
		Vector3(wall_thickness, wall_height, wall_length),
		"LWallV%d" % index
	)

	var h_offset: Vector3 = Vector3(0, 0, wall_length / 2.0).rotated(Vector3.UP, rotation)
	add_platform_with_collision(
		Vector3(pos.x + h_offset.x, wall_height / 2.0, pos.z + h_offset.z),
		Vector3(wall_length, wall_height, wall_thickness),
		"LWallH%d" % index
	)

func generate_bunker(pos: Vector3, scale: float, index: int) -> void:
	var bunker_size: float = rng.randf_range(8.0, 14.0) * scale
	var bunk_wall_height: float = rng.randf_range(4.0, 7.0) * scale
	var bunk_wall_thickness: float = 1.0 * scale

	add_platform_with_collision(
		Vector3(pos.x, 0.25, pos.z),
		Vector3(bunker_size, 0.5, bunker_size),
		"BunkerFloor%d" % index
	)

	var wall_configs = [
		{"offset": Vector3(0, 0, bunker_size/2.0), "size": Vector3(bunker_size, bunk_wall_height, bunk_wall_thickness)},
		{"offset": Vector3(0, 0, -bunker_size/2.0), "size": Vector3(bunker_size, bunk_wall_height, bunk_wall_thickness)},
		{"offset": Vector3(bunker_size/2.0, 0, 0), "size": Vector3(bunk_wall_thickness, bunk_wall_height, bunker_size)},
		{"offset": Vector3(-bunker_size/2.0, 0, 0), "size": Vector3(bunk_wall_thickness, bunk_wall_height, bunker_size)}
	]

	var num_walls: int = rng.randi_range(2, 3)
	var indices: Array = [0, 1, 2, 3]
	indices.shuffle()

	for i in range(num_walls):
		var config = wall_configs[indices[i]]
		add_platform_with_collision(
			Vector3(pos.x + config.offset.x, bunk_wall_height / 2.0, pos.z + config.offset.z),
			config.size,
			"BunkerWall%d_%d" % [index, i]
		)

	if rng.randf() > 0.5:
		add_platform_with_collision(
			Vector3(pos.x, bunk_wall_height + 0.5, pos.z),
			Vector3(bunker_size, 1.0, bunker_size),
			"BunkerRoof%d" % index
		)
		clear_positions.append(Vector3(pos.x, bunk_wall_height + 1.5, pos.z))

	clear_positions.append(Vector3(pos.x, 1.0, pos.z))

func generate_jump_tower(pos: Vector3, scale: float, index: int) -> void:
	var tower_size: float = rng.randf_range(4.0, 6.0) * scale
	var tower_height: float = rng.randf_range(3.0, 6.0) * scale

	add_platform_with_collision(
		Vector3(pos.x, tower_height / 2.0, pos.z),
		Vector3(tower_size * 0.6, tower_height, tower_size * 0.6),
		"JumpTowerBase%d" % index
	)

	add_platform_with_collision(
		Vector3(pos.x, tower_height + 0.5, pos.z),
		Vector3(tower_size, 1.0, tower_size),
		"JumpTowerTop%d" % index
	)

	clear_positions.append(Vector3(pos.x, tower_height + 1.5, pos.z))

func generate_catwalk(pos: Vector3, scale: float, index: int) -> void:
	var length: float = rng.randf_range(12.0, 24.0) * scale
	var width: float = rng.randf_range(2.5, 4.0) * scale
	var height: float = rng.randf_range(5.0, 10.0) * scale
	var rotation: float = rng.randf() * PI

	var walkway = add_platform_with_collision(
		Vector3(pos.x, height, pos.z),
		Vector3(length, 0.5, width),
		"Catwalk%d" % index
	)
	walkway.rotation.y = rotation

	var end_offset: float = length / 2.0 - 1.0
	var offset1: Vector3 = Vector3(end_offset, 0, 0).rotated(Vector3.UP, rotation)
	var offset2: Vector3 = Vector3(-end_offset, 0, 0).rotated(Vector3.UP, rotation)

	add_platform_with_collision(
		Vector3(pos.x + offset1.x, height / 2.0, pos.z + offset1.z),
		Vector3(2.0 * scale, height, 2.0 * scale),
		"CatwalkSupport%dA" % index
	)
	add_platform_with_collision(
		Vector3(pos.x + offset2.x, height / 2.0, pos.z + offset2.z),
		Vector3(2.0 * scale, height, 2.0 * scale),
		"CatwalkSupport%dB" % index
	)

	clear_positions.append(Vector3(pos.x, height + 1.0, pos.z))

func generate_ramp_platform(pos: Vector3, scale: float, index: int) -> void:
	var platform_size: float = rng.randf_range(6.0, 10.0) * scale
	var platform_height: float = rng.randf_range(3.0, 6.0) * scale
	var ramp_length: float = platform_height * 2.5
	var rotation: float = rng.randf() * TAU

	add_platform_with_collision(
		Vector3(pos.x, platform_height, pos.z),
		Vector3(platform_size, 1.0, platform_size),
		"RampPlatform%d" % index
	)

	var ramp_offset: Vector3 = Vector3(platform_size / 2.0 + ramp_length / 2.0 - 1.0, 0, 0).rotated(Vector3.UP, rotation)
	var ramp_mesh: BoxMesh = create_smooth_box_mesh(Vector3(ramp_length, 0.5, platform_size * 0.6))
	var ramp_instance: MeshInstance3D = MeshInstance3D.new()
	ramp_instance.mesh = ramp_mesh
	ramp_instance.name = "Ramp%d" % index
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
	var section_size: float = rng.randf_range(10.0, 16.0) * scale
	var height_diff: float = rng.randf_range(2.0, 4.0) * scale

	add_platform_with_collision(
		Vector3(pos.x - section_size / 4.0, 0.25, pos.z),
		Vector3(section_size / 2.0, 0.5, section_size),
		"SplitLow%d" % index
	)

	add_platform_with_collision(
		Vector3(pos.x + section_size / 4.0, height_diff / 2.0, pos.z),
		Vector3(section_size / 2.0, height_diff, section_size),
		"SplitHigh%d" % index
	)

	var ramp_mesh: BoxMesh = create_smooth_box_mesh(Vector3(section_size * 0.3, 0.5, section_size * 0.4))
	var ramp_instance: MeshInstance3D = MeshInstance3D.new()
	ramp_instance.mesh = ramp_mesh
	ramp_instance.name = "SplitRamp%d" % index
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
	var arch_width: float = rng.randf_range(6.0, 10.0) * scale
	var arch_height: float = rng.randf_range(5.0, 8.0) * scale
	var pillar_width: float = 2.0 * scale
	var rotation: float = rng.randf() * PI

	var offset: float = arch_width / 2.0
	var offset_vec: Vector3 = Vector3(offset, 0, 0).rotated(Vector3.UP, rotation)

	add_platform_with_collision(
		Vector3(pos.x + offset_vec.x, arch_height / 2.0, pos.z + offset_vec.z),
		Vector3(pillar_width, arch_height, pillar_width),
		"ArchPillarL%d" % index
	)

	add_platform_with_collision(
		Vector3(pos.x - offset_vec.x, arch_height / 2.0, pos.z - offset_vec.z),
		Vector3(pillar_width, arch_height, pillar_width),
		"ArchPillarR%d" % index
	)

	var beam = add_platform_with_collision(
		Vector3(pos.x, arch_height + 0.5, pos.z),
		Vector3(arch_width + pillar_width, 1.0, pillar_width * 1.5),
		"ArchBeam%d" % index
	)
	beam.rotation.y = rotation

	clear_positions.append(Vector3(pos.x, arch_height + 1.5, pos.z))

func generate_sniper_nest(pos: Vector3, scale: float, index: int) -> void:
	var base_width: float = 3.0 * scale
	var height: float = rng.randf_range(12.0, 18.0) * scale
	var platform_size: float = rng.randf_range(5.0, 7.0) * scale

	add_platform_with_collision(
		Vector3(pos.x, height / 2.0, pos.z),
		Vector3(base_width, height, base_width),
		"SniperBase%d" % index
	)

	add_platform_with_collision(
		Vector3(pos.x, height + 0.5, pos.z),
		Vector3(platform_size, 1.0, platform_size),
		"SniperPlatform%d" % index
	)

	var nest_wall_height: float = 2.0 * scale
	var directions = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var num_walls: int = rng.randi_range(2, 3)
	directions.shuffle()

	for i in range(num_walls):
		var dir: Vector3 = directions[i]
		var wall_pos: Vector3 = Vector3(
			pos.x + dir.x * (platform_size / 2.0 - 0.5),
			height + 1.0 + nest_wall_height / 2.0,
			pos.z + dir.z * (platform_size / 2.0 - 0.5)
		)
		var wall_size: Vector3
		if abs(dir.x) > 0.5:
			wall_size = Vector3(0.5, nest_wall_height, platform_size * 0.8)
		else:
			wall_size = Vector3(platform_size * 0.8, nest_wall_height, 0.5)

		add_platform_with_collision(wall_pos, wall_size, "SniperWall%d_%d" % [index, i])

	clear_positions.append(Vector3(pos.x, height + 2.0, pos.z))

# ============================================================================
# PROCEDURAL BRIDGES
# ============================================================================

func generate_procedural_bridges() -> void:
	if complexity < 2 or clear_positions.size() < 4:
		return

	var scale: float = arena_size / 140.0
	var bridge_width: float = 3.0 * scale

	var elevated_positions: Array[Vector3] = []
	for pos in clear_positions:
		if pos.y > 4.0:
			elevated_positions.append(pos)

	if elevated_positions.size() < 2:
		return

	var num_bridges: int = mini(rng.randi_range(1, complexity), elevated_positions.size() / 2)
	elevated_positions.shuffle()

	for i in range(num_bridges):
		if i * 2 + 1 >= elevated_positions.size():
			break

		var pos1: Vector3 = elevated_positions[i * 2]
		var pos2: Vector3 = elevated_positions[i * 2 + 1]

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
		bridge_instance.name = "Bridge%d" % i
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
	var scale: float = arena_size / 140.0
	var floor_extent: float = (arena_size * 0.6) / 2.0

	var jump_pad_positions: Array[Vector3] = [Vector3(0, 0, 0)]

	var num_extra_pads: int = 2 + complexity
	for i in range(num_extra_pads):
		var pad_pos: Vector3 = Vector3(
			rng.randf_range(-floor_extent * 0.7, floor_extent * 0.7),
			0,
			rng.randf_range(-floor_extent * 0.7, floor_extent * 0.7)
		)

		var too_close: bool = false
		for existing in jump_pad_positions:
			if pad_pos.distance_to(existing) < 10.0 * scale:
				too_close = true
				break
		if not too_close:
			jump_pad_positions.append(pad_pos)

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
	pad_instance.name = "JumpPad%d" % index
	pad_instance.position = Vector3(pos.x, 0.25, pos.z)
	add_child(pad_instance)

	# Create a bright green material for jump pads
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.9, 0.3)  # Bright green
	material.emission_enabled = true
	material.emission = Color(0.1, 0.6, 0.2)  # Green glow
	material.emission_energy_multiplier = 2.0  # Visible glow
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # Prevent lighting issues
	pad_instance.set_surface_override_material(0, material)

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
	var scale: float = arena_size / 140.0
	var floor_extent: float = (arena_size * 0.6) / 2.0

	var num_pairs: int = 1 + complexity / 2

	for i in range(num_pairs):
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
	teleporter_instance.name = "Teleporter%d" % index
	teleporter_instance.position = Vector3(pos.x, 0.15, pos.z)
	add_child(teleporter_instance)

	# Create a purple material for teleporters
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.3, 0.9)  # Purple
	material.emission_enabled = true
	material.emission = Color(0.4, 0.2, 0.8)  # Purple glow
	material.emission_energy_multiplier = 2.0  # Visible glow
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # Prevent lighting issues
	teleporter_instance.set_surface_override_material(0, material)

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
	var perim_wall_height: float = 25.0 * scale
	var perim_wall_thickness: float = 2.0

	var wall_configs = [
		{"pos": Vector3(0, perim_wall_height / 2.0, wall_distance), "size": Vector3(arena_size * 1.2, perim_wall_height, perim_wall_thickness)},
		{"pos": Vector3(0, perim_wall_height / 2.0, -wall_distance), "size": Vector3(arena_size * 1.2, perim_wall_height, perim_wall_thickness)},
		{"pos": Vector3(wall_distance, perim_wall_height / 2.0, 0), "size": Vector3(perim_wall_thickness, perim_wall_height, arena_size * 1.2)},
		{"pos": Vector3(-wall_distance, perim_wall_height / 2.0, 0), "size": Vector3(perim_wall_thickness, perim_wall_height, arena_size * 1.2)}
	]

	for i in range(wall_configs.size()):
		var config = wall_configs[i]
		add_platform_with_collision(config.pos, config.size, "PerimeterWall%d" % i)

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
# GRID HELPER FUNCTIONS
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

func get_random_arena_position() -> Vector3:
	var floor_extent: float = (arena_size * 0.6) / 2.0 * 0.85
	return Vector3(
		rng.randf_range(-floor_extent, floor_extent),
		0,
		rng.randf_range(-floor_extent, floor_extent)
	)

# ============================================================================
# MESH/PLATFORM HELPER FUNCTIONS
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

	for pos in clear_positions:
		spawns.append(pos)

	var floor_radius: float = (arena_size * 0.6) / 2.0 * 0.5
	spawns.append(Vector3(0, 2, 0))
	spawns.append(Vector3(floor_radius, 2, 0))
	spawns.append(Vector3(-floor_radius, 2, 0))
	spawns.append(Vector3(0, 2, floor_radius))
	spawns.append(Vector3(0, 2, -floor_radius))

	return spawns

# ============================================================================
# .MAP FILE EXPORT
# ============================================================================

func export_to_map_file() -> void:
	## Export the current level to a Quake 3 .map file

	print("=== Exporting to .map file ===")

	map_brushes.clear()
	map_entities.clear()

	# Generate brushes for all BSP rooms
	var textures: Dictionary = {
		"floor": floor_texture,
		"ceiling": ceiling_texture,
		"wall": wall_texture,
		"corridor": corridor_texture,
		"caulk": caulk_texture
	}

	# Export BSP rooms
	for room in bsp_rooms:
		var room_brushes: Array[String] = BrushGenerator.create_room_brushes(
			room.room, room.height_offset, room_height, wall_thickness, textures
		)
		map_brushes.append_array(room_brushes)

	# Export corridors
	for corridor_data in corridors:
		var corridor_level: int = corridor_data.level
		var level_z: float = corridor_level * level_height_offset
		for segment in corridor_data.segments:
			var corridor_brushes: Array[String] = BrushGenerator.create_corridor_brushes(
				segment, level_z, room_height * 0.75, wall_thickness, textures
			)
			map_brushes.append_array(corridor_brushes)

	# Generate entities
	generate_map_entities()

	# Write the file
	write_map_file()

func generate_map_entities() -> void:
	## Generate entity strings for .map export

	# Spawn points at room centers
	var spawns_placed: int = 0
	var shuffled_rooms: Array[BSPNode] = bsp_rooms.duplicate()
	shuffled_rooms.shuffle()

	for room in shuffled_rooms:
		if spawns_placed >= target_spawn_points:
			break

		var pos: Vector3 = room.get_floor_center_3d()
		pos.y += 32.0  # Slightly above floor
		var angle: float = rng.randf_range(0, 360)

		map_entities.append(EntityPlacer.spawn_point(pos, angle))
		spawns_placed += 1

	print("  Placed %d spawn points" % spawns_placed)

	# Weapons
	var weapon_types: Array[String] = [
		"weapon_rocketlauncher", "weapon_railgun", "weapon_plasmagun",
		"weapon_lightning", "weapon_shotgun", "weapon_grenadelauncher"
	]

	var weapons_placed: int = 0
	for room in bsp_rooms:
		if rng.randf() < weapons_per_room:
			var pos: Vector3 = room.get_floor_center_3d()
			pos.x += rng.randf_range(-room.room.size.x * 0.3, room.room.size.x * 0.3)
			pos.z += rng.randf_range(-room.room.size.y * 0.3, room.room.size.y * 0.3)
			pos.y += 32.0

			var weapon: String = weapon_types[rng.randi() % weapon_types.size()]
			map_entities.append(EntityPlacer.weapon(weapon, pos))
			weapons_placed += 1

	# Weapons at corridor junctions
	for corridor_data in corridors:
		if rng.randf() < 0.3:
			var segment: Rect2 = corridor_data.segments[0]
			var level_z: float = corridor_data.level * level_height_offset
			var pos: Vector3 = Vector3(
				segment.position.x + segment.size.x / 2.0,
				level_z + 32.0,
				segment.position.y + segment.size.y / 2.0
			)
			var weapon: String = weapon_types[rng.randi() % weapon_types.size()]
			map_entities.append(EntityPlacer.weapon(weapon, pos))
			weapons_placed += 1

	print("  Placed %d weapons" % weapons_placed)

	# Health and armor items
	var health_items: Array[String] = ["item_health", "item_health_large", "item_health_mega"]
	var armor_items: Array[String] = ["item_armor_shard", "item_armor_combat", "item_armor_body"]

	var items_placed: int = 0
	for room in bsp_rooms:
		var base_y: float = room.height_offset + 32.0

		if rng.randf() < health_per_room:
			var pos: Vector3 = Vector3(
				room.room.position.x + rng.randf_range(32, room.room.size.x - 32),
				base_y,
				room.room.position.y + rng.randf_range(32, room.room.size.y - 32)
			)
			var health_type: String = health_items[rng.randi() % health_items.size()]
			map_entities.append(EntityPlacer.item(health_type, pos))
			items_placed += 1

		if rng.randf() < armor_per_room:
			var pos: Vector3 = Vector3(
				room.room.position.x + rng.randf_range(32, room.room.size.x - 32),
				base_y,
				room.room.position.y + rng.randf_range(32, room.room.size.y - 32)
			)
			var armor_type: String = armor_items[rng.randi() % armor_items.size()]
			map_entities.append(EntityPlacer.item(armor_type, pos))
			items_placed += 1

	print("  Placed %d items" % items_placed)

	# Lights
	var lights_placed: int = 0
	for room in bsp_rooms:
		var center: Vector3 = room.get_center_3d(room_height)
		center.y = room.height_offset + room_height - 32.0

		var intensity: int = int(rng.randf_range(200, 400))
		var color: Color = Color(
			rng.randf_range(0.8, 1.0),
			rng.randf_range(0.7, 1.0),
			rng.randf_range(0.6, 1.0)
		)
		map_entities.append(EntityPlacer.light(center, intensity, color))
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
				map_entities.append(EntityPlacer.light(corner_pos, 150))
				lights_placed += 1

	# Corridor lights
	for corridor_data in corridors:
		for segment in corridor_data.segments:
			var level_z: float = corridor_data.level * level_height_offset
			var center: Vector3 = Vector3(
				segment.position.x + segment.size.x / 2.0,
				level_z + room_height * 0.75 - 16.0,
				segment.position.y + segment.size.y / 2.0
			)
			map_entities.append(EntityPlacer.light(center, 150))
			lights_placed += 1

	print("  Placed %d lights" % lights_placed)

func write_map_file() -> void:
	## Write the complete .map file to disk

	# Ensure output directory exists
	var dir: DirAccess = DirAccess.open("res://")
	if dir and not dir.dir_exists(output_path):
		dir.make_dir_recursive(output_path)

	var file_path: String = output_path + map_name + ".map"
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)

	if file == null:
		push_error("Failed to open file for writing: %s" % file_path)
		print("ERROR: Could not write .map file to %s" % file_path)
		return

	# Header
	file.store_string("// Quake 3 Arena Map - Generated by Godot Q3 Map Generator\n")
	file.store_string("// Seed: %d\n" % rng.seed)
	file.store_string("// Rooms: %d, Corridors: %d, Brushes: %d, Entities: %d\n" % [
		bsp_rooms.size(), corridors.size(), map_brushes.size(), map_entities.size()
	])
	file.store_string("Version 29\n")
	file.store_string("\n")

	# Worldspawn entity containing all brushes
	file.store_string("{\n")
	file.store_string("\"classname\" \"worldspawn\"\n")
	file.store_string("\"message\" \"Generated Q3 Arena Map\"\n")
	file.store_string("\"_ambient\" \"10\"\n")
	file.store_string("\"_color\" \"1 1 1\"\n")
	file.store_string("\"gridsize\" \"64 64 128\"\n")

	for brush in map_brushes:
		file.store_string(brush)

	file.store_string("}\n")

	# Point entities
	for entity in map_entities:
		file.store_string(entity)

	file.close()
	print("Map written to: %s" % file_path)
	print("  Brushes: %d" % map_brushes.size())
	print("  Entities: %d" % map_entities.size())

# ============================================================================
# Q3MAP2 COMPILATION
# ============================================================================

func compile_map(q3map2_path: String, game_path: String = "") -> Dictionary:
	## Compile the .map file using q3map2
	## Returns a dictionary with success status and any error messages

	var map_file: String = ProjectSettings.globalize_path(output_path + map_name + ".map")
	var result: Dictionary = {
		"success": false,
		"bsp_result": -1,
		"vis_result": -1,
		"light_result": -1,
		"errors": []
	}

	print("=== Compiling map with q3map2 ===")
	print("Map file: %s" % map_file)
	print("q3map2 path: %s" % q3map2_path)

	# Verify q3map2 exists
	if not FileAccess.file_exists(q3map2_path):
		result.errors.append("q3map2 not found at: %s" % q3map2_path)
		push_error(result.errors[-1])
		return result

	# Build base arguments
	var base_args: Array = []
	if game_path != "":
		base_args.append_array(["-game", game_path])

	# BSP compile
	print("  [1/3] Running BSP compile...")
	var bsp_args: Array = base_args.duplicate()
	bsp_args.append_array(["-v", "-meta", map_file])

	var bsp_output: Array = []
	result.bsp_result = OS.execute(q3map2_path, bsp_args, bsp_output, true)

	if result.bsp_result != 0:
		var error_msg: String = "BSP compile failed with code: %d" % result.bsp_result
		result.errors.append(error_msg)
		push_error(error_msg)

		# Check for leak
		for line in bsp_output:
			if "leak" in str(line).to_lower():
				result.errors.append("MAP LEAK DETECTED - Check .lin file for leak location")
				print("WARNING: Map has a leak! The .lin file shows the leak path.")

		return result

	print("  BSP compile successful")

	# Visibility compile
	print("  [2/3] Running VIS compile...")
	var vis_args: Array = base_args.duplicate()
	vis_args.append_array(["-vis", "-saveprt", map_file])

	var vis_output: Array = []
	result.vis_result = OS.execute(q3map2_path, vis_args, vis_output, true)

	if result.vis_result != 0:
		var warning: String = "VIS compile failed with code: %d (non-fatal)" % result.vis_result
		result.errors.append(warning)
		push_warning(warning)
	else:
		print("  VIS compile successful")

	# Light compile
	print("  [3/3] Running LIGHT compile...")
	var light_args: Array = base_args.duplicate()
	light_args.append_array(["-light", "-fast", "-bounce", "2", "-patchshadows", map_file])

	var light_output: Array = []
	result.light_result = OS.execute(q3map2_path, light_args, light_output, true)

	if result.light_result != 0:
		var warning: String = "LIGHT compile failed with code: %d (non-fatal)" % result.light_result
		result.errors.append(warning)
		push_warning(warning)
	else:
		print("  LIGHT compile successful")

	result.success = result.bsp_result == 0

	if result.success:
		print("=== Compilation complete! ===")
		print("BSP file: %s.bsp" % map_file.get_basename())

	return result

func package_to_pk3(pk3_name: String = "", include_files: Array[String] = []) -> bool:
	## Package the compiled map into a .pk3 file (ZIP format)
	## include_files: Additional files to include (textures, sounds, etc.)

	if pk3_name == "":
		pk3_name = map_name

	var bsp_file: String = output_path + map_name + ".bsp"
	var pk3_path: String = output_path + pk3_name + ".pk3"

	print("=== Packaging to .pk3 ===")

	# Check if BSP exists
	if not FileAccess.file_exists(bsp_file):
		push_error("BSP file not found: %s - Run compile_map() first" % bsp_file)
		return false

	# For .pk3 creation, we need to use an external zip tool or implement ZIP writing
	# Godot doesn't have built-in ZIP creation, so we'll use OS commands

	var global_output: String = ProjectSettings.globalize_path(output_path)
	var global_pk3: String = ProjectSettings.globalize_path(pk3_path)
	var global_bsp: String = ProjectSettings.globalize_path(bsp_file)

	# Create maps directory structure
	var temp_dir: String = global_output + "pk3_temp/"
	var maps_dir: String = temp_dir + "maps/"

	# Use OS commands to create the pk3
	var zip_result: int = -1

	if OS.get_name() == "Windows":
		# Windows - use PowerShell's Compress-Archive
		var ps_script: String = """
		$tempDir = '%s'
		$mapsDir = '%s'
		$bspFile = '%s'
		$pk3File = '%s'

		New-Item -ItemType Directory -Force -Path $mapsDir | Out-Null
		Copy-Item $bspFile -Destination ($mapsDir + '%s.bsp')
		Compress-Archive -Path ($tempDir + '*') -DestinationPath $pk3File -Force
		Remove-Item -Recurse -Force $tempDir
		""" % [temp_dir, maps_dir, global_bsp, global_pk3, map_name]

		zip_result = OS.execute("powershell", ["-Command", ps_script])
	else:
		# Linux/Mac - use zip command
		var commands: String = """
		mkdir -p '%s' && \
		cp '%s' '%s%s.bsp' && \
		cd '%s' && \
		zip -r '%s' maps/ && \
		rm -rf '%s'
		""" % [maps_dir, global_bsp, maps_dir, map_name, temp_dir, global_pk3, temp_dir]

		zip_result = OS.execute("bash", ["-c", commands])

	if zip_result == 0:
		print("PK3 created: %s" % pk3_path)
		return true
	else:
		push_error("Failed to create PK3 file")
		print("TIP: You can manually create the .pk3 by:")
		print("  1. Create a 'maps' folder")
		print("  2. Copy %s.bsp into maps/")
		print("  3. Zip the maps folder and rename to .pk3")
		return false

# ============================================================================
# ASCII ART PARSER
# ============================================================================

func parse_ascii_art(file_path: String, cell_scale: float = 64.0, extrude_height: float = 128.0, floor_z: float = 0.0) -> Array[String]:
	## Parse ASCII art from a text file and extrude into brushes
	## '#' and 'X' characters become walls
	## '.' and ' ' are empty space
	## Returns array of brush strings for .map export

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

	print("Parsing ASCII art: %d lines" % lines.size())

	for y in range(lines.size()):
		var line: String = lines[y]
		for x in range(line.length()):
			var char: String = line[x]

			# Wall characters
			if char == "#" or char == "X" or char == "*":
				var mins: Vector3 = Vector3(x * cell_scale, floor_z, y * cell_scale)
				var maxs: Vector3 = Vector3((x + 1) * cell_scale, floor_z + extrude_height, (y + 1) * cell_scale)
				result.append(BrushGenerator.create_box_brush(mins, maxs, textures))

				# Also create runtime geometry
				if not Engine.is_editor_hint():
					add_platform_with_collision(
						Vector3(mins.x + cell_scale/2, floor_z + extrude_height/2, mins.y + cell_scale/2),
						Vector3(cell_scale, extrude_height, cell_scale),
						"ASCIIWall_%d_%d" % [x, y]
					)

	print("Generated %d brushes from ASCII art" % result.size())
	return result

func load_ascii_layout(file_path: String, cell_scale: float = 8.0, wall_height: float = 10.0) -> void:
	## Load an ASCII art file and generate runtime geometry
	## This is simpler alternative to parse_ascii_art that only generates runtime meshes

	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open ASCII layout file: %s" % file_path)
		return

	var content: String = file.get_as_text()
	file.close()

	var lines: PackedStringArray = content.split("\n")
	var center_offset_x: float = 0.0
	var center_offset_z: float = 0.0

	# Calculate center offset
	if lines.size() > 0:
		center_offset_z = lines.size() * cell_scale / 2.0
		center_offset_x = lines[0].length() * cell_scale / 2.0

	for y in range(lines.size()):
		var line: String = lines[y]
		for x in range(line.length()):
			var char: String = line[x]
			var world_x: float = x * cell_scale - center_offset_x
			var world_z: float = y * cell_scale - center_offset_z

			match char:
				"#", "X", "*":  # Wall
					add_platform_with_collision(
						Vector3(world_x, wall_height / 2.0, world_z),
						Vector3(cell_scale, wall_height, cell_scale),
						"ASCIIWall_%d_%d" % [x, y]
					)
				".", " ":  # Floor
					add_platform_with_collision(
						Vector3(world_x, -0.5, world_z),
						Vector3(cell_scale, 1.0, cell_scale),
						"ASCIIFloor_%d_%d" % [x, y]
					)
					clear_positions.append(Vector3(world_x, 2.0, world_z))
				"S":  # Spawn point
					add_platform_with_collision(
						Vector3(world_x, -0.5, world_z),
						Vector3(cell_scale, 1.0, cell_scale),
						"ASCIISpawn_%d_%d" % [x, y]
					)
					clear_positions.append(Vector3(world_x, 2.0, world_z))
				"J":  # Jump pad location
					add_platform_with_collision(
						Vector3(world_x, -0.5, world_z),
						Vector3(cell_scale, 1.0, cell_scale),
						"ASCIIJumpPad_%d_%d" % [x, y]
					)
					create_jump_pad(Vector3(world_x, 0, world_z), x * 100 + y, arena_size / 140.0)
				"T":  # Teleporter (needs pair)
					add_platform_with_collision(
						Vector3(world_x, -0.5, world_z),
						Vector3(cell_scale, 1.0, cell_scale),
						"ASCIITeleporter_%d_%d" % [x, y]
					)

# ============================================================================
# ADVANCED: NOISE PERTURBATION
# ============================================================================

func apply_organic_noise_to_room(room: Rect2, noise_strength: float = 8.0) -> Rect2:
	## Apply organic noise to room edges for more natural-looking layouts

	var noisy_room: Rect2 = room

	# Perturb each edge
	noisy_room.position.x += rng.randf_range(-noise_strength, noise_strength)
	noisy_room.position.y += rng.randf_range(-noise_strength, noise_strength)
	noisy_room.size.x += rng.randf_range(-noise_strength * 0.5, noise_strength * 0.5)
	noisy_room.size.y += rng.randf_range(-noise_strength * 0.5, noise_strength * 0.5)

	# Ensure positive size
	noisy_room.size.x = maxf(noisy_room.size.x, 16.0)
	noisy_room.size.y = maxf(noisy_room.size.y, 16.0)

	return noisy_room

# ============================================================================
# EDITOR INTEGRATION
# ============================================================================

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []

	if arena_size < 50:
		warnings.append("Arena size is very small - may not have enough room for structures")
	if complexity < 1 or complexity > 4:
		warnings.append("Complexity should be between 1 and 4")
	if num_levels > 3:
		warnings.append("More than 3 levels may cause performance issues")
	if target_spawn_points < 2:
		warnings.append("Deathmatch maps should have at least 2 spawn points")

	return warnings

# ============================================================================
# GENERATE MAP METHOD (for tool script usage)
# ============================================================================

func generate_map() -> void:
	## Alternative entry point for tool script usage
	## Calls generate_level() which handles both runtime and export
	generate_level()
