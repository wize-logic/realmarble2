@tool
extends Node3D

## Procedural Arena Level Generator (Godot Native)
## Generates arena-style levels using Binary Space Partitioning (BSP)
## Optimized for Godot's Compatibility renderer
##
## Features:
## - BSP-based layout generation for natural room/corridor layouts
## - Runtime mesh generation with collisions
## - NavigationRegion3D for AI pathfinding
## - OmniLight3D placement for dynamic lighting
## - OccluderInstance3D for performance optimization
## - Multi-level support with ramps and stairs
## - Jump pads and teleporters
## - Hazard zones (lava/slime)

# ============================================================================
# EXPORTED PARAMETERS
# ============================================================================

@export_group("Arena Settings")
@export var level_seed: int = 0  ## 0 = random seed based on time
@export var arena_size: float = 140.0  ## Base arena size in Godot units
@export var complexity: int = 2  ## 1=Low, 2=Medium, 3=High, 4=Extreme

@export_group("BSP Generation")
@export var use_bsp_layout: bool = false  ## Use BSP for room layout vs procedural structures
@export var min_room_size: float = 20.0  ## Minimum room dimension in Godot units
@export var dynamic_room_scaling: bool = true  ## Scale min_room_size based on arena_size
@export var dynamic_room_scale_factor: float = 0.15  ## Factor for dynamic scaling
@export var max_bsp_depth: int = 4  ## Maximum BSP subdivision depth
@export var room_inset_min: float = 0.75  ## Room inset factor minimum (75%)
@export var room_inset_max: float = 0.90  ## Room inset factor maximum (90%)
@export var enable_symmetry: bool = false  ## Mirror map for competitive balance
@export var symmetry_axis: int = 0  ## 0 = X-axis, 1 = Z-axis

@export_group("Geometry")
@export var room_height: float = 12.0  ## Height of rooms in Godot units
@export var wall_thickness: float = 1.0  ## Wall thickness in Godot units
@export var generate_ceiling: bool = true  ## Generate ceiling geometry
@export var generate_walls: bool = true  ## Generate perimeter walls

@export_group("Multi-Level")
@export var num_levels: int = 1  ## Number of vertical levels
@export var level_height_offset: float = 20.0  ## Height between levels in Godot units

@export_group("Corridor Settings")
@export var corridor_width_min: float = 4.0  ## Minimum corridor width
@export var corridor_width_max: float = 8.0  ## Maximum corridor width

@export_group("Lighting")
@export var generate_lights: bool = true  ## Add OmniLight3D to rooms
## Grid-based lighting for good coverage with proper shadows
@export var q3_light_energy: float = 1.5  ## Base light energy for grid lights
@export var q3_light_range: float = 25.0  ## Light range for coverage (increased to need fewer lights)
@export var q3_light_color: Color = Color(0.92, 0.88, 0.82)  ## Warm white default
@export var q3_grid_spacing: float = 22.0  ## Distance between grid lights (increased for fewer lights)
@export var q3_ambient_energy: float = 0.5  ## Ambient fill for dark areas
@export var q3_bounce_enabled: bool = false  ## Bounce lights disabled for simplicity
@export var q3_bounce_energy: float = 0.5  ## Bounce light intensity
@export var q3_use_colored_zones: bool = false  ## Zone color tints disabled for simplicity
@export var q3_color_intensity: float = 0.0  ## How much zone color affects lights
@export var q3_ceiling_lights: bool = true  ## Add ceiling-mounted lights
@export var q3_floor_fill: bool = false  ## Floor-level fill lights disabled for simplicity
@export var q3_structure_boost: float = 1.0  ## Extra lighting on structures
## Lighting quality for performance: 0=Low (few lights), 1=Medium, 2=High (full)
@export var lighting_quality: int = 0
## Maximum total OmniLight3D nodes (forward renderer evaluates each per-fragment)
@export var max_light_count: int = 32

@export_group("Spawn Points")
@export var target_spawn_points: int = 16

@export_group("Hazards")
@export var enable_hazards: bool = false  ## Add lava/slime hazard zones
@export var hazard_count: int = 2  ## Number of hazard zones
@export var hazard_type: int = 0  ## 0 = lava, 1 = slime
@export var hazard_damage: float = 25.0  ## Damage per second

@export_group("Navigation & AI")
@export var generate_navmesh: bool = true  ## Generate NavigationRegion3D
@export var navmesh_cell_size: float = 0.25  ## Navigation mesh cell size
@export var navmesh_agent_radius: float = 0.5  ## Agent radius for pathfinding

@export_group("Performance")
@export var generate_occluders: bool = true  ## Add OccluderInstance3D for culling
@export var use_static_batching: bool = true  ## Batch static geometry

# Video Walls - replaces perimeter walls with video panels
@export_group("Video Walls")
@export var enable_video_walls: bool = false  ## Replace perimeter walls with video panels

# Visualizer Walls - WMP9 style audio visualizer on walls
@export_group("Visualizer Walls")
@export var enable_visualizer_walls: bool = false  ## Project audio visualizer onto walls
@export_range(0, 4) var visualizer_mode: int = 0  ## 0=Bars, 1=Scope, 2=Ambience, 3=Battery, 4=Plenoptic
@export var visualizer_color_preset: String = "synthwave"  ## Color scheme (ocean, sunset, matrix, synthwave, neon, ice, fire, aurora)
@export var visualizer_sensitivity: float = 2.0  ## Audio reactivity sensitivity

# Menu Preview Mode - only generates floor + video walls for main menu background
var menu_preview_mode: bool = false

# Video wall constants
const VIDEO_WALL_PATH: String = "res://videos/arena_bg.ogv"
const VIDEO_WALL_LOOP: bool = true
const VIDEO_WALL_RESOLUTION: Vector2i = Vector2i(1920, 1080)

# Visualizer wall constants
const VISUALIZER_RESOLUTION: Vector2i = Vector2i(1920, 1080)
const VISUALIZER_AUDIO_BUS: String = "Music"

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

# Godot scene nodes
var navigation_region: NavigationRegion3D = null
var lights: Array[OmniLight3D] = []
var occluders: Array[OccluderInstance3D] = []
var spawn_markers: Array[Marker3D] = []
var _cached_spawn_points: PackedVector3Array = PackedVector3Array()  # PERF: Cached spawn points

# Grid system for structure placement
const CELL_SIZE: float = 8.0

# Material manager for runtime textures (if available)
var material_manager = null

# Cached level generation for HTML5 performance
static var _cached_level_scene: PackedScene = null
static var _cached_level_key: String = ""

# Video wall manager for WebM display on perimeter walls
var video_wall_manager = null
# Visualizer wall manager for WMP9 style audio visualizer
var visualizer_wall_manager = null
var perimeter_walls: Array[MeshInstance3D] = []

# Cached materials for shared instances (avoid per-instance allocations)
var _jump_pad_material: StandardMaterial3D = null
var _teleporter_material: StandardMaterial3D = null
var _rail_material: StandardMaterial3D = null

# Cached meshes for shared instances
var _jump_pad_mesh: SphereMesh = null
var _teleporter_mesh: SphereMesh = null

# Grind rail system
var GrindRailScript = preload("res://scripts/grind_rail.gd")
var rail_positions: Array[Vector3] = []  # Track rail start positions to avoid overlap
const RAIL_RADIUS: float = 0.3  # Visual radius for rail tubes

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		await generate_level()

func generate_level() -> void:
	## Main entry point - generates the complete level
	if OS.has_feature("web"):
		await _generate_level_core(true)
	else:
		await _generate_level_core(false)

func _generate_level_core(yield_between_steps: bool) -> void:
	var cache_key: String = _make_cache_key()
	if OS.has_feature("web") and _try_load_cached_level(cache_key):
		return

	# Auto-reduce light cap on web platform (forward renderer is much slower in WebGL)
	if OS.has_feature("web"):
		max_light_count = mini(max_light_count, 32)
		lighting_quality = mini(lighting_quality, 0)

	# Initialize random number generator
	rng = RandomNumberGenerator.new()
	rng.seed = level_seed if level_seed != 0 else int(Time.get_unix_time_from_system())

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "=== PROCEDURAL ARENA GENERATOR ===")
	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Seed: %d | Arena Size: %.1f | Complexity: %d | BSP: %s | Levels: %d" % [rng.seed, arena_size, complexity, "Enabled" if use_bsp_layout else "Disabled", num_levels])

	# Initialize materials for Compatibility renderer
	setup_materials()
	await _yield_frame_if_needed(yield_between_steps)

	# Clear previous data
	clear_level()
	await _yield_frame_if_needed(yield_between_steps)

	# Menu preview mode: only floor + video walls (no structures, obstacles, etc.)
	if menu_preview_mode:
		# Force complexity to 1 to avoid raised sections on the floor
		var saved_complexity: int = complexity
		complexity = 1
		generate_main_arena()
		complexity = saved_complexity
		apply_procedural_textures()
		# Always enable video walls in menu preview
		enable_video_walls = true
		apply_video_walls()
		DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "=== MENU PREVIEW GENERATION COMPLETE ===")
		if OS.has_feature("web"):
			_cache_generated_level(cache_key)
		return

	if use_bsp_layout:
		# Generate using BSP algorithm
		generate_bsp_level()
	else:
		# Generate using procedural structures (original method)
		generate_procedural_level()
	await _yield_frame_if_needed(yield_between_steps)

	# Add hazard zones if enabled (before interactive elements so they can avoid them)
	if enable_hazards:
		generate_hazard_zones()

	# Boundaries
	generate_perimeter_walls()
	generate_death_zone()
	await _yield_frame_if_needed(yield_between_steps)

	# Connectivity check
	if use_bsp_layout:
		var leak_result: Dictionary = check_for_leaks()
		if leak_result.has_leak:
			DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "WARNING: %s" % leak_result.details)

	# Apply materials (Compatibility renderer safe)
	apply_procedural_textures()
	await _yield_frame_if_needed(yield_between_steps)

	# Apply video walls if enabled (after procedural textures to override them)
	apply_video_walls()

	# Apply visualizer walls if enabled (WMP9 style audio visualizer)
	apply_visualizer_walls()
	await _yield_frame_if_needed(yield_between_steps)

	# Godot-specific features
	if generate_lights:
		generate_room_lights()
		await _yield_frame_if_needed(yield_between_steps)

	if generate_navmesh:
		generate_navigation_mesh()
		await _yield_frame_if_needed(yield_between_steps)

	if generate_occluders:
		generate_occlusion_culling()
		await _yield_frame_if_needed(yield_between_steps)

	# Add interactive elements LAST - after all geometry is in place
	# This ensures we can properly check for geometry clipping
	generate_teleporters()
	generate_jump_pads()
	generate_grind_rails()
	generate_perimeter_rails()

	# Create spawn point markers
	generate_spawn_markers()

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "=== GENERATION COMPLETE === Rooms: %d, Corridors: %d, Platforms: %d, Rails: %d, Lights: %d, Spawns: %d" % [bsp_rooms.size(), corridors.size(), platforms.size(), rail_positions.size() / 2, lights.size(), spawn_markers.size()])
	if OS.has_feature("web"):
		_cache_generated_level(cache_key)

func _yield_frame_if_needed(yield_between_steps: bool) -> void:
	if yield_between_steps:
		await get_tree().process_frame

func _make_cache_key() -> String:
	var settings := {
		"seed": level_seed,
		"arena_size": arena_size,
		"complexity": complexity,
		"use_bsp": use_bsp_layout,
		"min_room": min_room_size,
		"max_depth": max_bsp_depth,
		"levels": num_levels,
		"corridor_min": corridor_width_min,
		"corridor_max": corridor_width_max,
		"hazards": enable_hazards,
		"hazard_count": hazard_count,
		"hazard_type": hazard_type,
		"lights": generate_lights,
		"lighting_quality": lighting_quality,
		"occluders": generate_occluders,
		"navmesh": generate_navmesh,
		"video_walls": enable_video_walls,
		"visualizer_walls": enable_visualizer_walls,
		"menu_preview": menu_preview_mode,
	}
	return JSON.stringify(settings)

func _try_load_cached_level(cache_key: String) -> bool:
	if _cached_level_scene == null or _cached_level_key != cache_key:
		return false

	clear_level()
	var cached_root: Node = _cached_level_scene.instantiate()
	add_child(cached_root)
	_rebuild_cached_references(cached_root)
	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Loaded cached level for HTML5 performance.")
	return true

func _cache_generated_level(cache_key: String) -> void:
	var cache_root := Node3D.new()
	cache_root.name = "CachedLevelRoot"
	for child in get_children():
		if not is_instance_valid(child):
			continue
		var duplicated = child.duplicate(
			Node.DUPLICATE_USE_INSTANTIATION | Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS
		)
		cache_root.add_child(duplicated)

	var packed := PackedScene.new()
	if packed.pack(cache_root) == OK:
		_cached_level_scene = packed
		_cached_level_key = cache_key

func _rebuild_cached_references(root: Node) -> void:
	lights.clear()
	occluders.clear()
	spawn_markers.clear()
	_cached_spawn_points.clear()
	navigation_region = null
	_collect_cached_nodes(root)

func _collect_cached_nodes(node: Node) -> void:
	if node is OmniLight3D:
		lights.append(node)
	elif node is OccluderInstance3D:
		occluders.append(node)
	elif node is Marker3D:
		spawn_markers.append(node)
	elif node is NavigationRegion3D:
		navigation_region = node

	for child in node.get_children():
		_collect_cached_nodes(child)

func clear_level() -> void:
	## Remove all generated content

	# Clean up wall managers FIRST (before clearing other children)
	# This ensures proper cleanup of collision shapes and resources
	if video_wall_manager != null and is_instance_valid(video_wall_manager):
		video_wall_manager.cleanup()
		video_wall_manager = null  # Clear reference - loop below will queue_free

	if visualizer_wall_manager != null and is_instance_valid(visualizer_wall_manager):
		visualizer_wall_manager.cleanup()
		visualizer_wall_manager = null  # Clear reference - loop below will queue_free

	# Now free all children (including the wall managers)
	for child in get_children():
		if is_instance_valid(child):
			child.queue_free()

	platforms.clear()
	teleporters.clear()
	rail_positions.clear()
	clear_positions.clear()
	occupied_cells.clear()
	bsp_rooms.clear()
	corridors.clear()
	jump_pad_positions.clear()
	teleporter_positions.clear()
	perimeter_walls.clear()

	# Clear Godot-specific nodes
	lights.clear()
	occluders.clear()
	spawn_markers.clear()
	_cached_spawn_points.clear()
	navigation_region = null
	bsp_root = null

# ============================================================================
# BSP LEVEL GENERATION
# ============================================================================

func generate_bsp_level() -> void:
	## Generate level layout using Binary Space Partitioning

	# Use arena_size directly for BSP root - room insets handle margins
	# This ensures consistent scaling regardless of arena_size
	var map_size: float = arena_size  # Full arena bounds

	# Generate BSP tree for each level
	for level_idx in range(num_levels):
		var level_z: float = level_idx * level_height_offset
		generate_bsp_for_level(level_idx, level_z, map_size)

	# Apply symmetry to BSP rooms if enabled (mirrors rooms before corridor gen)
	if enable_symmetry:
		apply_bsp_symmetry()

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

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Level %d: %d rooms generated" % [level_idx, level_rooms.size()])

	# Generate runtime geometry for rooms
	for node in level_rooms:
		generate_room_geometry(node)

	# Connect rooms with corridors
	generate_bsp_corridors(level_root, level_z)

func subdivide_bsp(node: BSPNode, depth: int) -> void:
	## Recursively subdivide a BSP node

	# Calculate effective minimum room size
	var effective_min_size: float
	if dynamic_room_scaling:
		# Dynamic scaling ties min_room_size to arena_size for better proportions
		effective_min_size = maxf(arena_size * dynamic_room_scale_factor, min_room_size * 0.5)
	else:
		# Traditional scaling
		effective_min_size = min_room_size * (arena_size / 140.0)

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

func apply_bsp_symmetry() -> void:
	## Mirror all BSP rooms across the symmetry axis
	## This creates a balanced arena layout for competitive play

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Applying BSP symmetry across %s axis..." % ("X" if symmetry_axis == 0 else "Z"))

	var original_rooms: Array[BSPNode] = bsp_rooms.duplicate()
	var next_room_id: int = bsp_rooms.size()

	for room in original_rooms:
		# Create mirrored room
		var mirrored: BSPNode = BSPNode.new(
			mirror_rect2(room.bounds),
			room.level,
			room.height_offset
		)
		mirrored.room = mirror_rect2(room.room)
		mirrored.room_id = next_room_id
		mirrored.is_leaf = true

		# Skip if mirrored room overlaps with original (center rooms)
		var center_dist: float
		if symmetry_axis == 0:
			center_dist = absf(room.get_center().x)
		else:
			center_dist = absf(room.get_center().y)

		if center_dist < room.room.size.length() * 0.3:
			continue  # Too close to center, skip mirroring

		# Generate geometry for mirrored room
		generate_room_geometry(mirrored)
		bsp_rooms.append(mirrored)
		next_room_id += 1

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Mirrored %d rooms (total: %d)" % [bsp_rooms.size() - original_rooms.size(), bsp_rooms.size()])

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
	## Enhanced: Creates multiple connection points for better accessibility

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

		# Calculate how many ramps to create based on room count
		var min_rooms: int = mini(lower_rooms.size(), upper_rooms.size())
		var num_ramps: int = maxi(1, mini(min_rooms / 2, 3))  # 1-3 ramps per level pair

		# Track which rooms have been connected
		var connected_lower: Array[int] = []
		var connected_upper: Array[int] = []

		for ramp_idx in range(num_ramps):
			# Find closest unconnected pair
			var best_lower: BSPNode = null
			var best_upper: BSPNode = null
			var best_dist: float = INF

			for lower in lower_rooms:
				if lower.room_id in connected_lower:
					continue
				for upper in upper_rooms:
					if upper.room_id in connected_upper:
						continue
					var dist: float = lower.get_center().distance_to(upper.get_center())
					if dist < best_dist:
						best_dist = dist
						best_lower = lower
						best_upper = upper

			if best_lower != null and best_upper != null:
				create_ramp_geometry(best_lower, best_upper)
				connected_lower.append(best_lower.room_id)
				connected_upper.append(best_upper.room_id)
				best_lower.connected_to.append(best_upper.room_id)
				best_upper.connected_to.append(best_lower.room_id)

	# Also add ramps for height variations within rooms (raised sections)
	generate_intra_room_ramps()

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

func generate_intra_room_ramps() -> void:
	## Generate small ramps for height variations within larger rooms
	## This adds accessibility to raised sections created during room generation

	var scale: float = arena_size / 140.0
	var height_threshold: float = 1.5 * scale  # Minimum height diff to warrant a ramp

	for platform in platforms:
		if not platform.name.contains("Raised"):
			continue

		var raised_pos: Vector3 = platform.position
		var raised_height: float = raised_pos.y

		# Skip if too low to need a ramp
		if raised_height < height_threshold:
			continue

		# Find the nearest floor level
		var floor_y: float = 0.0
		for room in bsp_rooms:
			if Vector2(raised_pos.x, raised_pos.z).distance_to(room.get_center()) < room.room.size.length() / 2.0:
				floor_y = room.height_offset
				break

		var height_diff: float = raised_height - floor_y
		if height_diff < height_threshold:
			continue

		# Create a small access ramp
		var ramp_width: float = 3.0 * scale
		var ramp_length: float = height_diff * 2.5
		var ramp_dir: Vector2 = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()

		var num_steps: int = maxi(2, int(height_diff / (1.5 * scale)))
		var step_height: float = height_diff / num_steps
		var step_depth: float = ramp_length / num_steps

		for i in range(num_steps):
			var step_y: float = floor_y + i * step_height + step_height / 2.0
			var step_pos: Vector2 = Vector2(raised_pos.x, raised_pos.z) + ramp_dir * (i * step_depth + ramp_length * 0.3)

			add_platform_with_collision(
				Vector3(step_pos.x, step_y, step_pos.y),
				Vector3(ramp_width, step_height, step_depth * 1.2),
				"IntraRamp_%s_Step%d" % [platform.name, i]
			)

# ============================================================================
# PROCEDURAL STRUCTURE GENERATION (Alternative to BSP)
# ============================================================================

func generate_procedural_level() -> void:
	## Generate level using procedural structure placement (original method)

	generate_main_arena()

	var structure_budget: int = get_structure_budget()
	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Structure budget: %d" % structure_budget)

	generate_procedural_structures(structure_budget)
	generate_procedural_bridges()

func get_structure_budget() -> int:
	## Calculate number of structures based on complexity and size
	## Complexity 1-4 gives base counts of 9, 12, 15, 18
	## Size multiplies this - smaller arenas get fewer structures
	var base_count: int = 6 + complexity * 3
	var size_scale: float = arena_size / 140.0
	var scaled_count: int = int(base_count * size_scale)
	return maxi(3, scaled_count)  # Minimum 3 structures

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

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Placed %d/%d structures" % [structures_placed, budget])

func get_structure_cell_radius(type: int) -> int:
	match type:
		StructureType.PILLAR, StructureType.TIERED_PLATFORM, StructureType.JUMP_TOWER, StructureType.SNIPER_NEST:
			return 0
		StructureType.L_WALL, StructureType.RAMP_PLATFORM:
			return 0
		StructureType.BUNKER, StructureType.ARCHWAY, StructureType.CATWALK, StructureType.SPLIT_LEVEL:
			return 1
	return 0

func _can_add_light() -> bool:
	## Check if we're under the global light cap (forward renderer perf guard)
	return lights.size() < max_light_count

func _register_light(light: OmniLight3D) -> OmniLight3D:
	## Add a light to the scene and tracking array (respecting the cap)
	if not _can_add_light():
		light.queue_free()
		return null
	add_child(light)
	lights.append(light)
	return light

func add_interior_light(position: Vector3, index: int, suffix: String = "") -> void:
	## Add a warm interior light for enclosed spaces (like torches in a cave)
	if not generate_lights or not _can_add_light():
		return
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "InteriorLight_%d%s" % [index, suffix]
	light.position = position
	light.light_color = Color(1.0, 0.9, 0.75)  # Warm amber torch color
	light.light_energy = q3_light_energy * 1.5
	light.omni_range = q3_light_range * 1.2
	light.omni_attenuation = 1.0  # Linear falloff for full coverage
	light.shadow_enabled = false
	_register_light(light)

func add_structure_light(pos: Vector3, height: float, structure_size: float, index: int) -> void:
	## Quake 3 style structure lighting - reduced from 10 lights to 2 per structure
	if not generate_lights or not _can_add_light():
		return

	var base_energy: float = q3_light_energy * q3_structure_boost
	var base_range: float = maxf(structure_size * 2.5, q3_light_range * 1.5)

	# Top light - bright overhead illumination (increased range to compensate for removed side/corner lights)
	var top_light: OmniLight3D = OmniLight3D.new()
	top_light.name = "StructureTopLight_%d" % index
	top_light.position = Vector3(pos.x, height + 3.0, pos.z)
	top_light.light_color = q3_light_color
	top_light.light_energy = base_energy * 1.3
	top_light.omni_range = base_range * 1.5
	top_light.omni_attenuation = 0.8
	top_light.shadow_enabled = false
	_register_light(top_light)

	# Ground-level fill (increased range to compensate)
	var ground_light: OmniLight3D = OmniLight3D.new()
	ground_light.name = "StructureGroundLight_%d" % index
	ground_light.position = Vector3(pos.x, 1.0, pos.z)
	ground_light.light_color = q3_light_color
	ground_light.light_energy = base_energy * 1.2
	ground_light.omni_range = base_range * 2.0
	ground_light.omni_attenuation = 0.8
	ground_light.shadow_enabled = false
	_register_light(ground_light)

func generate_structure(type: int, pos: Vector3, scale: float, index: int) -> void:
	# Generate the structure
	var structure_height: float = 6.0 * scale  # Default height estimate
	var structure_size: float = 4.0 * scale    # Default size estimate

	match type:
		StructureType.PILLAR:
			generate_pillar(pos, scale, index)
			structure_height = 10.0 * scale
			structure_size = 3.0 * scale
		StructureType.TIERED_PLATFORM:
			generate_tiered_platform(pos, scale, index)
			structure_height = 8.0 * scale
			structure_size = 8.0 * scale
		StructureType.L_WALL:
			generate_l_wall(pos, scale, index)
			structure_height = 4.5 * scale
			structure_size = 9.0 * scale
		StructureType.BUNKER:
			generate_bunker(pos, scale, index)
			structure_height = 5.5 * scale
			structure_size = 11.0 * scale
		StructureType.JUMP_TOWER:
			generate_jump_tower(pos, scale, index)
			structure_height = 4.5 * scale
			structure_size = 5.0 * scale
		StructureType.CATWALK:
			generate_catwalk(pos, scale, index)
			structure_height = 7.5 * scale
			structure_size = 18.0 * scale
		StructureType.RAMP_PLATFORM:
			generate_ramp_platform(pos, scale, index)
			structure_height = 4.5 * scale
			structure_size = 8.0 * scale
		StructureType.SPLIT_LEVEL:
			generate_split_level(pos, scale, index)
			structure_height = 6.0 * scale
			structure_size = 12.0 * scale
		StructureType.ARCHWAY:
			generate_archway(pos, scale, index)
			structure_height = 6.0 * scale
			structure_size = 10.0 * scale
		StructureType.SNIPER_NEST:
			generate_sniper_nest(pos, scale, index)
			structure_height = 10.0 * scale
			structure_size = 6.0 * scale

	# Add lighting to the structure
	add_structure_light(pos, structure_height, structure_size, index)

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

	var has_roof: bool = rng.randf() > 0.5
	if has_roof:
		add_platform_with_collision(
			Vector3(pos.x, bunk_wall_height + 0.5, pos.z),
			Vector3(bunker_size, 1.0, bunker_size),
			"BunkerRoof%d" % index
		)
		clear_positions.append(Vector3(pos.x, bunk_wall_height + 1.5, pos.z))

	clear_positions.append(Vector3(pos.x, 1.0, pos.z))

	# Interior torch light for bunker
	var light_height: float = bunk_wall_height * 0.5 if has_roof else bunk_wall_height * 0.3
	add_interior_light(Vector3(pos.x, light_height, pos.z), index, "_bunker")

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

	# Interior torch light under the catwalk
	add_interior_light(Vector3(pos.x, height * 0.5, pos.z), index, "_catwalk")

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

	# Interior torch light under the archway beam
	add_interior_light(Vector3(pos.x, arch_height * 0.6, pos.z), index, "_archway")

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

	# Interior torch light under the tall sniper platform
	add_interior_light(Vector3(pos.x, height * 0.4, pos.z), index, "_sniper")

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

# Store positions of interactive elements to filter spawns
var jump_pad_positions: Array[Vector3] = []
var teleporter_positions: Array[Vector3] = []

func generate_jump_pads() -> void:
	var scale: float = arena_size / 140.0
	var floor_extent: float = (arena_size * 0.6) / 2.0
	var pad_radius: float = 2.0 * scale

	jump_pad_positions.clear()

	# 60% ratio: Generate 3-6 jump pads based on complexity
	var num_target_pads: int = 3 + complexity
	var attempts: int = 0
	var max_attempts: int = num_target_pads * 40

	while jump_pad_positions.size() < num_target_pads and attempts < max_attempts:
		attempts += 1

		var pad_pos: Vector3 = Vector3(
			rng.randf_range(-floor_extent * 0.8, floor_extent * 0.8),
			0,
			rng.randf_range(-floor_extent * 0.8, floor_extent * 0.8)
		)

		# Light geometry check: ensure not inside a structure
		# Uses direct mesh bounds checking, skips main floor automatically
		if is_near_platform_geometry(pad_pos, 3.0):
			continue

		# Ensure position has overhead clearance
		if not has_overhead_clearance(pad_pos, 3.0):
			continue

		# Check distance to other jump pads (not too close)
		var too_close: bool = false
		for existing in jump_pad_positions:
			if pad_pos.distance_to(existing) < 15.0:
				too_close = true
				break
		# Check distance to teleporters
		for tele_pos in teleporter_positions:
			if pad_pos.distance_to(tele_pos) < 10.0:
				too_close = true
				break

		if not too_close:
			jump_pad_positions.append(pad_pos)

	# Create the jump pads
	for i in range(jump_pad_positions.size()):
		create_jump_pad(jump_pad_positions[i], i, scale)

	# Remove spawn positions that are too close to jump pads
	filter_spawns_near_positions(jump_pad_positions, pad_radius * 2.0)

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Generated %d jump pads" % jump_pad_positions.size())

func create_jump_pad(pos: Vector3, index: int, scale: float) -> void:
	var pad_radius: float = 1.4 * scale  # Smaller than before

	# Create shared mesh on first use (reduced tessellation for performance)
	if _jump_pad_mesh == null:
		_jump_pad_mesh = SphereMesh.new()
		_jump_pad_mesh.radius = pad_radius
		_jump_pad_mesh.height = pad_radius * 0.6  # Squashed for dome look
		_jump_pad_mesh.radial_segments = 12
		_jump_pad_mesh.rings = 6

	var pad_instance: MeshInstance3D = MeshInstance3D.new()
	pad_instance.mesh = _jump_pad_mesh
	pad_instance.name = "JumpPad%d" % index
	pad_instance.position = Vector3(pos.x, pad_radius * 0.15, pos.z)  # Slightly above ground
	add_child(pad_instance)

	# Shared glowing green material (Compatibility renderer safe)
	if _jump_pad_material == null:
		_jump_pad_material = StandardMaterial3D.new()
		_jump_pad_material.albedo_color = Color(0.3, 1.0, 0.4)  # Bright vibrant green
		_jump_pad_material.emission_enabled = true
		_jump_pad_material.emission = Color(0.3, 1.0, 0.4)  # Match albedo for solid color
		_jump_pad_material.emission_energy_multiplier = 2.0  # Glow intensity
		_jump_pad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # Shows color directly
	pad_instance.set_surface_override_material(0, _jump_pad_material)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var collision_shape: SphereShape3D = SphereShape3D.new()
	collision_shape.radius = pad_radius * 0.5
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
	area_shape.height = 2.5
	area_collision.shape = area_shape
	jump_area.add_child(area_collision)

# ============================================================================
# TELEPORTERS
# ============================================================================

func generate_teleporters() -> void:
	var scale: float = arena_size / 140.0
	var floor_extent: float = (arena_size * 0.6) / 2.0
	var teleporter_radius: float = 2.5 * scale

	teleporter_positions.clear()

	# 40% ratio: Generate 1-2 teleporter pairs based on complexity
	# Strategic placement: opposite ends of the arena for quick traversal
	var num_pairs: int = 1 if complexity <= 2 else 2
	var pairs_created: int = 0

	# Place teleporter pairs at strategic positions (opposite ends of arena)
	for pair_index in range(num_pairs):
		# Distribute pairs around the arena
		var base_angle: float = (float(pair_index) / num_pairs) * PI + rng.randf_range(-0.2, 0.2)

		# Position 1: Near one edge of the arena
		var dist1: float = floor_extent * rng.randf_range(0.6, 0.85)
		var pos1: Vector3 = Vector3(
			cos(base_angle) * dist1,
			0,
			sin(base_angle) * dist1
		)

		# Position 2: Opposite side for strategic advantage
		var opposite_angle: float = base_angle + PI + rng.randf_range(-0.3, 0.3)
		var dist2: float = floor_extent * rng.randf_range(0.6, 0.85)
		var pos2: Vector3 = Vector3(
			cos(opposite_angle) * dist2,
			0,
			sin(opposite_angle) * dist2
		)

		# Light geometry check: ensure not inside a structure
		# Uses direct mesh bounds checking, skips main floor automatically
		if is_near_platform_geometry(pos1, 3.0) or is_near_platform_geometry(pos2, 3.0):
			# Try adjusting positions slightly
			pos1.x += rng.randf_range(-5.0, 5.0)
			pos1.z += rng.randf_range(-5.0, 5.0)
			pos2.x += rng.randf_range(-5.0, 5.0)
			pos2.z += rng.randf_range(-5.0, 5.0)

		# Simple overhead clearance check
		if not has_overhead_clearance(pos1, 3.0) or not has_overhead_clearance(pos2, 3.0):
			# Try adjusting positions slightly
			pos1.x += rng.randf_range(-5.0, 5.0)
			pos1.z += rng.randf_range(-5.0, 5.0)
			pos2.x += rng.randf_range(-5.0, 5.0)
			pos2.z += rng.randf_range(-5.0, 5.0)

		teleporter_positions.append(pos1)
		teleporter_positions.append(pos2)
		create_teleporter(pos1, pos2, pairs_created * 2, scale)
		create_teleporter(pos2, pos1, pairs_created * 2 + 1, scale)
		pairs_created += 1

	# Remove spawn positions that are too close to teleporters
	filter_spawns_near_positions(teleporter_positions, teleporter_radius * 2.0)

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Generated %d teleporters (%d pairs spanning arena)" % [pairs_created * 2, pairs_created])

func create_teleporter(pos: Vector3, destination: Vector3, index: int, scale: float) -> void:
	var pad_radius: float = 1.4 * scale  # Same size as jump pads

	# Create shared mesh on first use (reduced tessellation for performance)
	if _teleporter_mesh == null:
		_teleporter_mesh = SphereMesh.new()
		_teleporter_mesh.radius = pad_radius
		_teleporter_mesh.height = pad_radius * 0.6  # Squashed for dome look
		_teleporter_mesh.radial_segments = 12
		_teleporter_mesh.rings = 6

	var teleporter_instance: MeshInstance3D = MeshInstance3D.new()
	teleporter_instance.mesh = _teleporter_mesh
	teleporter_instance.name = "Teleporter%d" % index
	teleporter_instance.position = Vector3(pos.x, pad_radius * 0.15, pos.z)
	add_child(teleporter_instance)

	# Shared glowing purple material (Compatibility renderer safe)
	if _teleporter_material == null:
		_teleporter_material = StandardMaterial3D.new()
		_teleporter_material.albedo_color = Color(0.7, 0.3, 1.0)  # Bright purple/magenta
		_teleporter_material.emission_enabled = true
		_teleporter_material.emission = Color(0.7, 0.3, 1.0)  # Match albedo for solid color
		_teleporter_material.emission_energy_multiplier = 2.0  # Glow intensity
		_teleporter_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # Shows color directly
	teleporter_instance.set_surface_override_material(0, _teleporter_material)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var collision_shape: SphereShape3D = SphereShape3D.new()
	collision_shape.radius = pad_radius * 0.5
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
	area_shape.radius = pad_radius
	area_shape.height = 2.5
	area_collision.shape = area_shape
	teleport_area.add_child(area_collision)

	teleporters.append({"area": teleport_area, "destination": destination})

# ============================================================================
# GRIND RAILS (Strategic placement - sparse to avoid clutter)
# ============================================================================

func generate_grind_rails() -> void:
	## Generate strategic grind rails - sparingly placed to avoid clutter
	## Rails span across the arena at elevated height
	var scale: float = arena_size / 140.0
	var floor_extent: float = (arena_size * 0.6) / 2.0

	rail_positions.clear()

	# Sparse rail count: 1-2 rails total
	var num_target_rails: int = 1 if complexity == 1 else 2
	var rails_created: int = 0

	# Fixed height that works well across arena sizes (high enough to clear most structures)
	var rail_height: float = 12.0 * scale

	# Create rails that span across the arena
	for rail_index in range(num_target_rails):
		# Distribute rails evenly around the arena
		var base_angle: float = (float(rail_index) / num_target_rails) * PI + rng.randf_range(-0.3, 0.3)

		# Start point on one side
		var start_dist: float = floor_extent * rng.randf_range(0.4, 0.7)
		var start_pos: Vector3 = Vector3(
			cos(base_angle) * start_dist,
			rail_height,
			sin(base_angle) * start_dist
		)

		# End point on opposite side
		var end_angle: float = base_angle + PI + rng.randf_range(-0.4, 0.4)
		var end_dist: float = floor_extent * rng.randf_range(0.4, 0.7)
		var end_pos: Vector3 = Vector3(
			cos(end_angle) * end_dist,
			rail_height + rng.randf_range(-2.0, 2.0) * scale,  # Slight height variation
			sin(end_angle) * end_dist
		)

		# Check distance - should be reasonable
		var distance: float = start_pos.distance_to(end_pos)
		if distance < 15.0:
			continue

		# Check distance to jump pads and teleporters (simplified check)
		var too_close: bool = false
		for pad_pos in jump_pad_positions:
			if start_pos.distance_to(pad_pos) < 8.0 or end_pos.distance_to(pad_pos) < 8.0:
				too_close = true
				break
		if too_close:
			continue

		# Create the rail
		create_grind_rail(start_pos, end_pos, rails_created, scale)
		rail_positions.append(start_pos)
		rail_positions.append(end_pos)
		rails_created += 1

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Generated %d strategic grind rails" % rails_created)

func create_grind_rail(start: Vector3, end: Vector3, index: int, _scale: float) -> void:
	## Create a grind rail between two points with a smooth arc
	var rail: Path3D = GrindRailScript.new()
	rail.name = "GrindRail%d" % index
	rail.curve = Curve3D.new()

	var distance: float = start.distance_to(end)
	var num_points: int = max(8, int(distance / 4.0))  # Smooth curve

	# Calculate arc height - creates a nice curved path
	# Distance is already in world units, arc is proportional to length
	var arc_height: float = distance * 0.12

	for i in range(num_points):
		var t: float = float(i) / (num_points - 1)
		var pos: Vector3 = start.lerp(end, t)

		# Add arc using sine curve (highest at middle)
		pos.y += sin(t * PI) * arc_height

		rail.curve.add_point(pos)

	# Set smooth tangents for better grinding physics
	_set_rail_tangents(rail)

	add_child(rail)

	# Create visual mesh for the rail
	_create_rail_visual(rail)

func _set_rail_tangents(rail: Path3D) -> void:
	## Set smooth tangents for rail curves
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

func _create_rail_visual(rail: Path3D) -> void:
	## Create visual mesh for the rail (Compatibility renderer safe)
	if not rail.curve or rail.curve.get_baked_length() < 1.0:
		return

	var rail_visual: MeshInstance3D = MeshInstance3D.new()
	rail_visual.name = "RailVisual"

	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var radial_segments: int = 6  # Reduced for performance
	var rail_length: float = rail.curve.get_baked_length()
	var length_segments: int = clampi(int(rail_length * 0.4), 4, 80)

	var last_right: Vector3 = Vector3.RIGHT
	var last_up: Vector3 = Vector3.UP

	for i in range(length_segments):
		var offset_dist: float = (float(i) / length_segments) * rail_length
		var next_offset: float = (float(i + 1) / length_segments) * rail_length

		var pos: Vector3 = rail.curve.sample_baked(offset_dist)
		var next_pos: Vector3 = rail.curve.sample_baked(next_offset)

		var forward: Vector3 = (next_pos - pos)
		if forward.length_squared() < 0.001:
			continue
		forward = forward.normalized()

		var right: Vector3 = forward.cross(Vector3.UP)
		if right.length_squared() < 0.01:
			right = forward.cross(last_right)
			if right.length_squared() < 0.01:
				right = forward.cross(Vector3.RIGHT)
		right = right.normalized()
		var up: Vector3 = right.cross(forward).normalized()

		last_right = right
		last_up = up

		for j in range(radial_segments):
			var angle_curr: float = (float(j) / radial_segments) * TAU
			var angle_next: float = (float(j + 1) / radial_segments) * TAU

			var offset_curr: Vector3 = (right * cos(angle_curr) + up * sin(angle_curr)) * RAIL_RADIUS
			var offset_next_rad: Vector3 = (right * cos(angle_next) + up * sin(angle_next)) * RAIL_RADIUS

			var v1: Vector3 = pos + offset_curr
			var v2: Vector3 = pos + offset_next_rad
			var v3: Vector3 = next_pos + offset_curr
			var v4: Vector3 = next_pos + offset_next_rad

			var n1: Vector3 = offset_curr.normalized()
			var n2: Vector3 = offset_next_rad.normalized()

			# Triangle 1
			surface_tool.set_normal(n1)
			surface_tool.add_vertex(v1)
			surface_tool.set_normal(n2)
			surface_tool.add_vertex(v2)
			surface_tool.set_normal(n1)
			surface_tool.add_vertex(v3)

			# Triangle 2
			surface_tool.set_normal(n2)
			surface_tool.add_vertex(v2)
			surface_tool.set_normal(n2)
			surface_tool.add_vertex(v4)
			surface_tool.set_normal(n1)
			surface_tool.add_vertex(v3)

	rail_visual.mesh = surface_tool.commit()

	# Shared rail material - dark grey with subtle sheen (Compatibility renderer safe)
	if _rail_material == null:
		_rail_material = StandardMaterial3D.new()
		_rail_material.albedo_color = Color(0.25, 0.25, 0.28)  # Dark grey
		_rail_material.emission_enabled = true
		_rail_material.emission = Color(0.15, 0.15, 0.18)  # Subtle grey glow for visibility
		_rail_material.emission_energy_multiplier = 0.8
		_rail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rail_visual.set_surface_override_material(0, _rail_material)

	rail.add_child(rail_visual)

# ============================================================================
# PERIMETER RAILS (Safety rails around arena edges to prevent falling)
# ============================================================================

func generate_perimeter_rails() -> void:
	## Generate multiple grind rails scattered around the outer edges of the arena
	## These serve as safety rails to catch players before they fall off
	var scale: float = arena_size / 140.0

	# Bring rails closer to the play area
	var base_distance: float = arena_size * 0.42

	# Height range for perimeter rails
	var min_height: float = 1.5 * scale
	var max_height: float = 6.0 * scale

	# Number of rails per side (randomized)
	var rails_per_side: int = rng.randi_range(2, 4)

	var rail_count: int = 0
	var side_names: Array[String] = ["South", "East", "North", "West"]

	# Direction vectors for each side (along the side, and outward from center)
	var side_configs: Array[Dictionary] = [
		{"along": Vector3(1, 0, 0), "out": Vector3(0, 0, -1), "center": Vector3(0, 0, -base_distance)},  # South
		{"along": Vector3(0, 0, 1), "out": Vector3(1, 0, 0), "center": Vector3(base_distance, 0, 0)},   # East
		{"along": Vector3(-1, 0, 0), "out": Vector3(0, 0, 1), "center": Vector3(0, 0, base_distance)},  # North
		{"along": Vector3(0, 0, -1), "out": Vector3(-1, 0, 0), "center": Vector3(-base_distance, 0, 0)} # West
	]

	for side_idx in range(4):
		var config: Dictionary = side_configs[side_idx]
		var side_name: String = side_names[side_idx]

		# Generate multiple rails for this side
		var num_rails: int = rng.randi_range(2, 4)

		for i in range(num_rails):
			# Random position along the side
			var side_length: float = arena_size * 0.8
			var along_offset: float = rng.randf_range(-side_length / 2, side_length / 2)

			# Random distance from center (some closer, some further)
			var distance_variation: float = rng.randf_range(-4.0, 6.0) * scale

			# Random height
			var height: float = rng.randf_range(min_height, max_height)

			# Random rail length (longer segments)
			var rail_length: float = rng.randf_range(30.0, 60.0) * scale

			# Calculate rail start and end positions
			var center_pos: Vector3 = config["center"] + config["out"] * distance_variation
			center_pos.y = height
			center_pos += config["along"] * along_offset

			var half_length: float = rail_length / 2.0
			var start_pos: Vector3 = center_pos - config["along"] * half_length
			var end_pos: Vector3 = center_pos + config["along"] * half_length

			# Create the rail
			_create_perimeter_rail(start_pos, end_pos, rail_count, side_name, scale)

			# Track positions
			rail_positions.append(start_pos)
			rail_positions.append(end_pos)
			rail_count += 1

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Generated %d perimeter safety rails around arena edges" % rail_count)

func _create_perimeter_rail(start: Vector3, end: Vector3, index: int, side_name: String, scale: float) -> void:
	## Create a perimeter rail with gentle random curves
	var rail: Path3D = GrindRailScript.new()
	rail.name = "PerimeterRail_%s_%d" % [side_name, index]
	rail.curve = Curve3D.new()

	var distance: float = start.distance_to(end)
	var num_points: int = max(8, int(distance / 8.0))

	# Random vertical arc - gentle curve up or down
	var arc_height: float = distance * rng.randf_range(0.02, 0.06)
	var arc_direction: float = 1.0 if rng.randf() > 0.3 else -1.0

	# Random sideways bend - single gentle curve inward or outward
	var bend_dir: Vector3
	if side_name == "South" or side_name == "North":
		bend_dir = Vector3(0, 0, 1)
	else:
		bend_dir = Vector3(1, 0, 0)
	var bend_amount: float = rng.randf_range(-3.0, 3.0) * scale

	for i in range(num_points):
		var t: float = float(i) / (num_points - 1)
		var pos: Vector3 = start.lerp(end, t)

		# Smooth curve factor - peaks in middle, zero at ends
		var curve_factor: float = sin(t * PI)

		# Apply vertical arc
		pos.y += curve_factor * arc_height * arc_direction

		# Apply sideways bend (single gentle curve)
		pos += bend_dir * curve_factor * bend_amount

		rail.curve.add_point(pos)

	# Set smooth tangents for better grinding physics
	_set_rail_tangents(rail)

	add_child(rail)

	# Create visual mesh for the rail
	_create_rail_visual(rail)

# ============================================================================
# PERIMETER & DEATH ZONE
# ============================================================================

func generate_perimeter_walls() -> void:
	# Outer walls have been removed - only video walls are used now (when enabled or on main menu)
	print("[LevelGen] Skipping perimeter walls - outer walls removed")
	perimeter_walls.clear()


func apply_video_walls() -> void:
	## Create video panel meshes - only shown when enabled OR on main menu
	print("[LevelGen] apply_video_walls() called, enable_video_walls: %s, menu_preview_mode: %s" % [enable_video_walls, menu_preview_mode])

	# Only show video walls if explicitly enabled OR if we're on the main menu (menu preview mode)
	if not enable_video_walls and not menu_preview_mode:
		print("[LevelGen] Video walls disabled and not on main menu - skipping")
		return

	# Rotating cylinder sizing based on arena
	var scale: float = arena_size / 140.0
	var cylinder_radius: float = arena_size * 0.6
	var cylinder_height: float = 30.0 * scale
	var cylinder_center: Vector3 = Vector3(0, cylinder_height / 2.0, 0)

	# Load and initialize video wall manager
	print("[LevelGen] Loading VideoWallManager...")
	var VideoWallManagerScript = load("res://scripts/video_wall_manager.gd")
	if VideoWallManagerScript == null:
		push_error("Failed to load VideoWallManager script")
		return

	video_wall_manager = Node3D.new()
	video_wall_manager.set_script(VideoWallManagerScript)
	video_wall_manager.name = "VideoWallManager"
	video_wall_manager.loop_video = VIDEO_WALL_LOOP
	add_child(video_wall_manager)

	# Initialize video and create rotating cylinder
	if video_wall_manager.initialize(VIDEO_WALL_PATH, VIDEO_WALL_RESOLUTION):
		print("[LevelGen] Creating rotating video cylinder...")
		video_wall_manager.create_video_cylinder(cylinder_radius, cylinder_height, cylinder_center, 64, 1)
		DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Rotating video cylinder created with: " + VIDEO_WALL_PATH)
	else:
		push_warning("Failed to initialize video walls")
		video_wall_manager.queue_free()
		video_wall_manager = null


func apply_visualizer_walls() -> void:
	## Create WMP9-style audio visualizer projected onto walls
	print("[LevelGen] apply_visualizer_walls() called, enable_visualizer_walls: %s" % enable_visualizer_walls)

	if not enable_visualizer_walls:
		print("[LevelGen] Visualizer walls disabled - skipping")
		return

	# Don't create visualizer walls if video walls are already enabled
	if enable_video_walls:
		print("[LevelGen] Video walls enabled, skipping visualizer walls")
		return

	# Dome sizing: radius encompasses the arena with some breathing room
	# Complete sphere dome with no gaps
	var dome_radius: float = arena_size * 0.65

	# Load and initialize visualizer wall manager
	print("[LevelGen] Loading VisualizerWallManager...")
	var VisualizerWallManagerScript = load("res://scripts/visualizer_wall_manager.gd")
	if VisualizerWallManagerScript == null:
		push_error("Failed to load VisualizerWallManager script")
		return

	visualizer_wall_manager = Node3D.new()
	visualizer_wall_manager.set_script(VisualizerWallManagerScript)
	visualizer_wall_manager.name = "VisualizerWallManager"

	# Configure visualizer settings
	visualizer_wall_manager.current_mode = visualizer_mode
	visualizer_wall_manager.sensitivity = visualizer_sensitivity
	add_child(visualizer_wall_manager)

	# Initialize visualizer and create dome
	if visualizer_wall_manager.initialize(VISUALIZER_AUDIO_BUS, VISUALIZER_RESOLUTION):
		print("[LevelGen] Creating visualizer dome...")
		# Complete sphere with 64h x 48v segments for smooth coverage
		visualizer_wall_manager.create_visualizer_dome(dome_radius, Vector3.ZERO, 64, 48)

		# Apply color preset
		visualizer_wall_manager.set_color_preset(visualizer_color_preset)

		DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Complete sphere visualizer dome created with mode: %d, preset: %s" % [visualizer_mode, visualizer_color_preset])
	else:
		push_warning("Failed to initialize visualizer walls")
		visualizer_wall_manager.queue_free()
		visualizer_wall_manager = null


func get_visualizer_wall_manager():
	## Get the visualizer wall manager for external control
	return visualizer_wall_manager


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

func filter_spawns_near_positions(positions: Array[Vector3], min_distance: float) -> void:
	## Remove spawn points that are too close to given positions
	# PERF: Use squared distance to avoid sqrt + Vector2 allocations
	var min_dist_sq: float = min_distance * min_distance
	var filtered: Array[Vector3] = []
	for spawn in clear_positions:
		var too_close: bool = false
		for pos in positions:
			var dx: float = spawn.x - pos.x
			var dz: float = spawn.z - pos.z
			if dx * dx + dz * dz < min_dist_sq:
				too_close = true
				break
		if not too_close:
			filtered.append(spawn)
	clear_positions = filtered

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

func has_overhead_clearance(pos: Vector3, required_height: float = 3.0) -> bool:
	## Check if a position has enough vertical clearance above it.
	## Used to prevent spawning teleporters/jump pads under geometry.
	## required_height: minimum clearance needed (default 3.0 for player height)

	for platform in platforms:
		if platform == null or platform.mesh == null:
			continue

		var plat_pos: Vector3 = platform.position
		var plat_size: Vector3 = platform.mesh.size if platform.mesh is BoxMesh else Vector3(4, 4, 4)

		# Calculate platform bounds in X/Z
		var half_x: float = plat_size.x / 2.0
		var half_z: float = plat_size.z / 2.0

		# Check if position is within platform's X/Z footprint
		if pos.x < plat_pos.x - half_x or pos.x > plat_pos.x + half_x:
			continue
		if pos.z < plat_pos.z - half_z or pos.z > plat_pos.z + half_z:
			continue

		# Position is under this platform's footprint - check height
		var platform_bottom: float = plat_pos.y - plat_size.y / 2.0

		# If platform bottom is above pos but within required_height, it blocks
		if platform_bottom > pos.y and platform_bottom < pos.y + required_height:
			return false

	return true

func is_near_platform_geometry(pos: Vector3, min_distance: float) -> bool:
	## Check if a position is too close to structures/geometry.
	## Returns true if position is within min_distance of blocking geometry.
	## Skips floor-like meshes (large AND flat) but checks tall structures.

	# PERF: Use platforms array instead of get_children() to avoid array allocation
	for child in platforms:
		if not is_instance_valid(child) or child.mesh == null:
			continue

		# Explicitly skip main floor and raised sections (these are placeable surfaces)
		var child_name: String = child.name
		if child_name.begins_with("MainArenaFloor") or child_name.begins_with("RaisedSection"):
			continue

		var mesh_pos: Vector3 = child.position
		var mesh_size: Vector3 = Vector3(4, 4, 4)  # Default size

		if child.mesh is BoxMesh:
			mesh_size = child.mesh.size
		elif child.mesh is CylinderMesh:
			var cyl: CylinderMesh = child.mesh
			mesh_size = Vector3(cyl.top_radius * 2, cyl.height, cyl.top_radius * 2)
		else:
			continue  # Skip unknown mesh types

		# Skip FLOOR-LIKE meshes: large horizontally AND short vertically
		# This allows us to place on floors but still detect large walls/pillars
		var is_floor_like: bool = (mesh_size.x > 50.0 or mesh_size.z > 50.0) and mesh_size.y < 5.0
		if is_floor_like:
			continue

		# Skip meshes that are clearly elevated above ground level
		var mesh_bottom: float = mesh_pos.y - mesh_size.y / 2.0
		if mesh_bottom > 1.0:
			continue  # This is elevated, won't clip with ground-level elements

		# Skip very thin/flat meshes (likely floor tiles or decorations)
		if mesh_size.y < 0.5:
			continue

		# Calculate expanded bounds for collision check
		var half_x: float = mesh_size.x / 2.0 + min_distance
		var half_z: float = mesh_size.z / 2.0 + min_distance

		# Check horizontal proximity
		if pos.x >= mesh_pos.x - half_x and pos.x <= mesh_pos.x + half_x:
			if pos.z >= mesh_pos.z - half_z and pos.z <= mesh_pos.z + half_z:
				return true

	return false

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
	if material_manager:
		material_manager.apply_materials_to_level(self)

# ============================================================================
# GEOMETRY HELPER FUNCTIONS
# ============================================================================

func mirror_rect2(rect: Rect2) -> Rect2:
	## Mirror a Rect2 across the specified axis
	if symmetry_axis == 0:  # X-axis mirror
		return Rect2(
			Vector2(-rect.position.x - rect.size.x, rect.position.y),
			rect.size
		)
	else:  # Z-axis mirror
		return Rect2(
			Vector2(rect.position.x, -rect.position.y - rect.size.y),
			rect.size
		)

func mirror_vector3(vec: Vector3) -> Vector3:
	## Mirror a Vector3 across the specified axis
	if symmetry_axis == 0:  # X-axis mirror
		return Vector3(-vec.x, vec.y, vec.z)
	else:  # Z-axis mirror
		return Vector3(vec.x, vec.y, -vec.z)

# ============================================================================
# HAZARD ZONES
# ============================================================================

func generate_hazard_zones() -> void:
	## Generate lava or slime hazard zones

	if not enable_hazards:
		return

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Generating %d hazard zones..." % hazard_count)

	var scale: float = arena_size / 140.0
	var floor_extent: float = (arena_size * 0.6) / 2.0

	for i in range(hazard_count):
		var attempts: int = 0
		var placed: bool = false

		while attempts < 20 and not placed:
			attempts += 1

			var pos: Vector3 = Vector3(
				rng.randf_range(-floor_extent * 0.5, floor_extent * 0.5),
				-0.5,
				rng.randf_range(-floor_extent * 0.5, floor_extent * 0.5)
			)

			# Check if position is clear of other structures
			if not is_cell_available(pos, 2):
				continue

			var hazard_size: Vector3 = Vector3(
				rng.randf_range(6.0, 12.0) * scale,
				1.0,
				rng.randf_range(6.0, 12.0) * scale
			)

			create_hazard_zone(pos, hazard_size, i)
			mark_cell_occupied(pos, 2)
			placed = true

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Hazard zones created: %d" % hazard_count)

func create_hazard_zone(pos: Vector3, size: Vector3, index: int) -> void:
	## Create a hazard zone (lava/slime) at the specified position
	## Uses animated shader for flowing effect

	var hazard_mesh: BoxMesh = BoxMesh.new()
	hazard_mesh.size = size

	var hazard_instance: MeshInstance3D = MeshInstance3D.new()
	hazard_instance.mesh = hazard_mesh
	hazard_instance.name = "Hazard%d_%s" % [index, "Lava" if hazard_type == 0 else "Slime"]
	hazard_instance.position = pos
	add_child(hazard_instance)

	# Try to load animated hazard shader
	var hazard_shader: Shader = null
	if ResourceLoader.exists("res://scripts/shaders/hazard_surface.gdshader"):
		hazard_shader = load("res://scripts/shaders/hazard_surface.gdshader")

	if hazard_shader:
		# Use animated shader material
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = hazard_shader
		material.set_shader_parameter("hazard_type", hazard_type)
		material.set_shader_parameter("quality_level", lighting_quality)
		if hazard_type == 0:  # Lava
			material.set_shader_parameter("glow_intensity", 2.8)
			material.set_shader_parameter("flow_speed", 0.5)
			material.set_shader_parameter("bubble_amount", 0.6)
		else:  # Slime
			material.set_shader_parameter("glow_intensity", 1.8)
			material.set_shader_parameter("flow_speed", 0.3)
			material.set_shader_parameter("bubble_amount", 0.7)
		hazard_instance.set_surface_override_material(0, material)
	else:
		# Fallback to standard material (no white glow)
		var material: StandardMaterial3D = MaterialPool.get_hazard_fallback_material(hazard_type)
		hazard_instance.set_surface_override_material(0, material)

	# Create damage area
	var damage_area: Area3D = Area3D.new()
	damage_area.name = "HazardDamageArea"
	damage_area.add_to_group("hazard_damage")
	damage_area.set_meta("damage_type", "lava" if hazard_type == 0 else "slime")
	damage_area.set_meta("damage_per_second", 50 if hazard_type == 0 else 25)
	damage_area.collision_layer = 8
	damage_area.collision_mask = 0
	damage_area.monitorable = true
	hazard_instance.add_child(damage_area)

	var area_collision: CollisionShape3D = CollisionShape3D.new()
	var area_shape: BoxShape3D = BoxShape3D.new()
	area_shape.size = size + Vector3(0, 2.0, 0)  # Extend upward
	area_collision.shape = area_shape
	area_collision.position.y = 1.0
	damage_area.add_child(area_collision)

	platforms.append(hazard_instance)

# ============================================================================
# GODOT-SPECIFIC FEATURES
# ============================================================================

func setup_materials() -> void:
	## Initialize materials optimized for Compatibility renderer
	## Uses simple StandardMaterial3D with no advanced features
	material_manager = MaterialPool.get_procedural_manager()

func generate_room_lights() -> void:
	## Quake 3 Style Lighting System
	## Creates uniform, bright illumination across all surfaces with no dark spots
	## Uses grid-based light placement with overlapping coverage zones

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Generating Quake 3 style lighting...")

	# Zone color palette for subtle color variation (still bright, just tinted)
	var zone_colors: Array[Color] = [
		Color(1.0, 0.95, 0.90),   # Warm white
		Color(0.90, 0.95, 1.0),   # Cool white
		Color(0.95, 1.0, 0.92),   # Mint white
		Color(1.0, 0.92, 0.95),   # Rose white
		Color(0.98, 0.98, 0.90),  # Cream
		Color(0.92, 0.90, 1.0),   # Lavender white
		Color(1.0, 0.95, 0.92),   # Peach white
		Color(0.90, 0.98, 0.98),  # Ice white
	]

	# First pass: Generate grid-based ambient lighting across entire arena
	_generate_arena_light_grid()

	# Second pass: Room-specific lighting for BSP rooms
	var room_idx: int = 0
	for room in bsp_rooms:
		_generate_room_q3_lights(room, zone_colors[room_idx % zone_colors.size()], room_idx)
		room_idx += 1

	# Third pass: Corridor lighting
	_generate_corridor_q3_lights()

	# Fourth pass: Wall bounce lights for radiosity simulation (skip on low quality)
	if q3_bounce_enabled and lighting_quality >= 1:
		_generate_bounce_lights()

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Created %d Q3-style lights (grid + room + corridor + bounce)" % lights.size())


func _generate_arena_light_grid() -> void:
	## Generate a uniform grid of lights across the entire arena
	## This ensures base illumination everywhere - the Q3 "lightmap" approach
	## Performance: lighting_quality controls light density

	var half_arena: float = arena_size * 0.5
	# Increase grid spacing on lower quality for fewer lights
	var quality_multiplier: float = 1.0 if lighting_quality >= 2 else (1.5 if lighting_quality == 1 else 2.5)
	var grid_step: float = q3_grid_spacing * quality_multiplier
	var grid_count_x: int = int(arena_size / grid_step) + 1
	var grid_count_z: int = int(arena_size / grid_step) + 1

	# Calculate starting position (centered on arena)
	var start_x: float = -half_arena + (arena_size - (grid_count_x - 1) * grid_step) * 0.5
	var start_z: float = -half_arena + (arena_size - (grid_count_z - 1) * grid_step) * 0.5

	# On lower quality, increase light range to compensate for fewer lights
	var range_boost: float = 1.0 if lighting_quality >= 2 else (1.3 if lighting_quality == 1 else 1.6)
	var energy_boost: float = 1.0 if lighting_quality >= 2 else (1.2 if lighting_quality == 1 else 1.4)

	var grid_idx: int = 0
	var lights_created: int = 0
	for gx in range(grid_count_x):
		# PERF: Stop grid loop early if light cap reached
		if not _can_add_light():
			break
		for gz in range(grid_count_z):
			if not _can_add_light():
				break
			var pos_x: float = start_x + gx * grid_step
			var pos_z: float = start_z + gz * grid_step

			# Ceiling light - primary illumination (always enabled)
			if q3_ceiling_lights and _can_add_light():
				var ceiling_light: OmniLight3D = OmniLight3D.new()
				ceiling_light.name = "GridCeilingLight_%d" % grid_idx
				ceiling_light.position = Vector3(pos_x, room_height * 0.85, pos_z)
				ceiling_light.light_color = q3_light_color
				ceiling_light.light_energy = q3_light_energy * energy_boost
				ceiling_light.omni_range = q3_light_range * 1.2 * range_boost
				ceiling_light.omni_attenuation = 0.7
				ceiling_light.shadow_enabled = false
				_register_light(ceiling_light)
				lights_created += 1

			# Floor fill light - only on medium/high quality
			if q3_floor_fill and lighting_quality >= 1 and _can_add_light():
				var floor_light: OmniLight3D = OmniLight3D.new()
				floor_light.name = "GridFloorLight_%d" % grid_idx
				floor_light.position = Vector3(pos_x, 1.5, pos_z)
				floor_light.light_color = q3_light_color
				floor_light.light_energy = q3_ambient_energy * energy_boost
				floor_light.omni_range = q3_light_range * range_boost
				floor_light.omni_attenuation = 0.6
				floor_light.shadow_enabled = false
				_register_light(floor_light)
				lights_created += 1

			# Mid-height ambient light - only on high quality
			if lighting_quality >= 2 and _can_add_light():
				var mid_light: OmniLight3D = OmniLight3D.new()
				mid_light.name = "GridMidLight_%d" % grid_idx
				mid_light.position = Vector3(pos_x, room_height * 0.4, pos_z)
				mid_light.light_color = q3_light_color
				mid_light.light_energy = q3_ambient_energy * 0.7 * energy_boost
				mid_light.omni_range = q3_light_range * 0.9 * range_boost
				mid_light.omni_attenuation = 0.6
				mid_light.shadow_enabled = false
				_register_light(mid_light)
				lights_created += 1

			grid_idx += 1

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "  Grid lights: %d (%dx%d grid, quality=%d)" % [lights_created, grid_count_x, grid_count_z, lighting_quality])


func _generate_room_q3_lights(room: BSPNode, zone_color: Color, room_idx: int) -> void:
	## Generate Q3-style lighting for a specific room
	## Adds additional lights to ensure complete room coverage

	var room_center: Vector3 = room.get_center_3d(room_height)
	var room_size: float = maxf(room.room.size.x, room.room.size.y)

	# Calculate zone tint (subtle color influence)
	var tinted_color: Color = q3_light_color
	if q3_use_colored_zones:
		tinted_color = q3_light_color.lerp(zone_color, q3_color_intensity)

	# PERF: Early exit if light cap reached
	if not _can_add_light():
		return

	# Primary room light - bright central illumination
	var main_light: OmniLight3D = OmniLight3D.new()
	main_light.name = "RoomMainLight_%d" % room.room_id
	main_light.position = Vector3(room_center.x, room.height_offset + room_height * 0.85, room_center.z)
	main_light.light_color = tinted_color
	main_light.light_energy = q3_light_energy * 1.3
	main_light.omni_range = maxf(q3_light_range * 1.5, room_size)
	main_light.omni_attenuation = 0.7
	main_light.shadow_enabled = false
	_register_light(main_light)

	# Corner lights - 4 corners to eliminate dark spots
	var corner_inset: float = minf(room.room.size.x, room.room.size.y) * 0.2
	var corner_height: float = room.height_offset + room_height * 0.6
	var corners: Array[Vector3] = [
		Vector3(room.room.position.x + corner_inset, corner_height, room.room.position.y + corner_inset),
		Vector3(room.room.position.x + room.room.size.x - corner_inset, corner_height, room.room.position.y + corner_inset),
		Vector3(room.room.position.x + corner_inset, corner_height, room.room.position.y + room.room.size.y - corner_inset),
		Vector3(room.room.position.x + room.room.size.x - corner_inset, corner_height, room.room.position.y + room.room.size.y - corner_inset),
	]

	for c_idx in range(corners.size()):
		if not _can_add_light():
			break
		var corner_light: OmniLight3D = OmniLight3D.new()
		corner_light.name = "RoomCornerLight_%d_%d" % [room.room_id, c_idx]
		corner_light.position = corners[c_idx]
		corner_light.light_color = tinted_color
		corner_light.light_energy = q3_light_energy * 0.8
		corner_light.omni_range = q3_light_range * 0.9
		corner_light.omni_attenuation = 0.7
		corner_light.shadow_enabled = false
		_register_light(corner_light)

	# Floor-level corner lights - brighten ground in corners
	for c_idx in range(corners.size()):
		if not _can_add_light():
			break
		var floor_corner: OmniLight3D = OmniLight3D.new()
		floor_corner.name = "RoomFloorCorner_%d_%d" % [room.room_id, c_idx]
		floor_corner.position = Vector3(corners[c_idx].x, room.height_offset + 1.0, corners[c_idx].z)
		floor_corner.light_color = tinted_color
		floor_corner.light_energy = q3_ambient_energy * 0.9
		floor_corner.omni_range = q3_light_range * 0.7
		floor_corner.omni_attenuation = 0.6
		floor_corner.shadow_enabled = false
		_register_light(floor_corner)

	# Edge midpoint lights for larger rooms
	if room_size >= 15.0:
		var mid_x: float = room.room.position.x + room.room.size.x / 2.0
		var mid_z: float = room.room.position.y + room.room.size.y / 2.0
		var edge_inset: float = 2.5
		var edge_height: float = room.height_offset + room_height * 0.5

		var edges: Array[Vector3] = [
			Vector3(mid_x, edge_height, room.room.position.y + edge_inset),
			Vector3(mid_x, edge_height, room.room.position.y + room.room.size.y - edge_inset),
			Vector3(room.room.position.x + edge_inset, edge_height, mid_z),
			Vector3(room.room.position.x + room.room.size.x - edge_inset, edge_height, mid_z),
		]

		for e_idx in range(edges.size()):
			var edge_light: OmniLight3D = OmniLight3D.new()
			edge_light.name = "RoomEdgeLight_%d_%d" % [room.room_id, e_idx]
			edge_light.position = edges[e_idx]
			edge_light.light_color = tinted_color
			edge_light.light_energy = q3_light_energy * 0.7
			edge_light.omni_range = q3_light_range * 0.85
			edge_light.omni_attenuation = 0.7
			edge_light.shadow_enabled = false
			_register_light(edge_light)

	# Additional sub-grid lights for very large rooms
	if room_size >= 25.0:
		var sub_step: float = q3_grid_spacing * 0.75
		var sub_count_x: int = int(room.room.size.x / sub_step)
		var sub_count_z: int = int(room.room.size.y / sub_step)

		for sx in range(1, sub_count_x):
			for sz in range(1, sub_count_z):
				var sub_pos: Vector3 = Vector3(
					room.room.position.x + sx * sub_step,
					room.height_offset + room_height * 0.7,
					room.room.position.y + sz * sub_step
				)
				var sub_light: OmniLight3D = OmniLight3D.new()
				sub_light.name = "RoomSubLight_%d_%d_%d" % [room.room_id, sx, sz]
				sub_light.position = sub_pos
				sub_light.light_color = tinted_color
				sub_light.light_energy = q3_light_energy * 0.6
				sub_light.omni_range = q3_light_range * 0.75
				sub_light.omni_attenuation = 0.7
				sub_light.shadow_enabled = false
				_register_light(sub_light)


func _generate_corridor_q3_lights() -> void:
	## Generate Q3-style corridor lighting with full coverage

	var corridor_idx: int = 0
	for corridor_data in corridors:
		for segment in corridor_data.segments:
			var seg_center: Vector2 = segment.position + segment.size / 2.0
			var level_z: float = corridor_data.level * level_height_offset
			var seg_length: float = maxf(segment.size.x, segment.size.y)

			# Primary corridor light
			var main_light: OmniLight3D = OmniLight3D.new()
			main_light.name = "CorridorMainLight_%d" % corridor_idx
			main_light.position = Vector3(seg_center.x, level_z + room_height * 0.75, seg_center.y)
			main_light.light_color = q3_light_color
			main_light.light_energy = q3_light_energy * 1.1
			main_light.omni_range = q3_light_range * 1.2
			main_light.omni_attenuation = 0.7
			main_light.shadow_enabled = false
			_register_light(main_light)

			# Floor light for corridor
			var floor_light: OmniLight3D = OmniLight3D.new()
			floor_light.name = "CorridorFloorLight_%d" % corridor_idx
			floor_light.position = Vector3(seg_center.x, level_z + 1.0, seg_center.y)
			floor_light.light_color = q3_light_color
			floor_light.light_energy = q3_ambient_energy
			floor_light.omni_range = q3_light_range * 0.9
			floor_light.omni_attenuation = 0.6
			floor_light.shadow_enabled = false
			_register_light(floor_light)

			# Additional lights for long corridors
			if seg_length > q3_grid_spacing:
				var is_horizontal: bool = segment.size.x > segment.size.y
				var num_extra: int = int(seg_length / q3_grid_spacing)

				for i in range(1, num_extra + 1):
					var offset_ratio: float = float(i) / float(num_extra + 1)
					var extra_pos: Vector3

					if is_horizontal:
						extra_pos = Vector3(
							segment.position.x + segment.size.x * offset_ratio,
							level_z + room_height * 0.65,
							seg_center.y
						)
					else:
						extra_pos = Vector3(
							seg_center.x,
							level_z + room_height * 0.65,
							segment.position.y + segment.size.y * offset_ratio
						)

					var extra_light: OmniLight3D = OmniLight3D.new()
					extra_light.name = "CorridorExtraLight_%d_%d" % [corridor_idx, i]
					extra_light.position = extra_pos
					extra_light.light_color = q3_light_color
					extra_light.light_energy = q3_light_energy * 0.85
					extra_light.omni_range = q3_light_range
					extra_light.omni_attenuation = 0.7
					extra_light.shadow_enabled = false
					_register_light(extra_light)

			corridor_idx += 1


func _generate_bounce_lights() -> void:
	## Generate bounce lights near walls to simulate radiosity
	## This fills in areas where direct lighting might not reach

	var half_arena: float = arena_size * 0.5
	var wall_offset: float = 3.0
	var bounce_step: float = q3_grid_spacing * 1.5
	var num_per_wall: int = int(arena_size / bounce_step) + 1

	# Bounce lights along each wall
	var walls: Array[Dictionary] = [
		{"start": Vector3(-half_arena + wall_offset, 0, -half_arena), "dir": Vector3(0, 0, 1)},  # West wall
		{"start": Vector3(half_arena - wall_offset, 0, -half_arena), "dir": Vector3(0, 0, 1)},   # East wall
		{"start": Vector3(-half_arena, 0, -half_arena + wall_offset), "dir": Vector3(1, 0, 0)},  # North wall
		{"start": Vector3(-half_arena, 0, half_arena - wall_offset), "dir": Vector3(1, 0, 0)},   # South wall
	]

	var bounce_idx: int = 0
	for wall in walls:
		for i in range(num_per_wall):
			var offset: float = i * bounce_step
			var pos: Vector3 = wall.start + wall.dir * offset

			# Low bounce light
			var low_bounce: OmniLight3D = OmniLight3D.new()
			low_bounce.name = "BounceLight_Low_%d" % bounce_idx
			low_bounce.position = Vector3(pos.x, 2.5, pos.z)
			low_bounce.light_color = q3_light_color
			low_bounce.light_energy = q3_bounce_energy
			low_bounce.omni_range = q3_light_range * 0.8
			low_bounce.omni_attenuation = 0.6
			low_bounce.shadow_enabled = false
			_register_light(low_bounce)

			# High bounce light
			var high_bounce: OmniLight3D = OmniLight3D.new()
			high_bounce.name = "BounceLight_High_%d" % bounce_idx
			high_bounce.position = Vector3(pos.x, room_height * 0.6, pos.z)
			high_bounce.light_color = q3_light_color
			high_bounce.light_energy = q3_bounce_energy * 0.8
			high_bounce.omni_range = q3_light_range * 0.7
			high_bounce.omni_attenuation = 0.6
			high_bounce.shadow_enabled = false
			_register_light(high_bounce)

			bounce_idx += 1

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "  Bounce lights: %d" % (bounce_idx * 2))

func generate_navigation_mesh() -> void:
	## Generate NavigationRegion3D for AI pathfinding

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Generating navigation mesh...")

	navigation_region = NavigationRegion3D.new()
	navigation_region.name = "NavigationRegion"
	add_child(navigation_region)

	var navmesh: NavigationMesh = NavigationMesh.new()

	# Configure navmesh for arena gameplay
	navmesh.cell_size = navmesh_cell_size
	navmesh.cell_height = navmesh_cell_size
	navmesh.agent_radius = navmesh_agent_radius
	navmesh.agent_height = 2.0
	navmesh.agent_max_climb = 0.5
	navmesh.agent_max_slope = 45.0

	# Set geometry source - parse child meshes
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS

	navigation_region.navigation_mesh = navmesh

	# Bake the navmesh (deferred to avoid blocking)
	navigation_region.bake_navigation_mesh.call_deferred()

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Navigation mesh configured (will bake asynchronously)")

func generate_occlusion_culling() -> void:
	## Generate OccluderInstance3D nodes for performance optimization
	## Creates box occluders for large solid geometry

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Generating occlusion culling...")

	# Create occluders for perimeter walls
	var wall_distance: float = arena_size * 0.55
	var scale: float = arena_size / 140.0
	var occ_wall_height: float = 25.0 * scale

	var wall_configs: Array = [
		{"pos": Vector3(0, occ_wall_height / 2.0, wall_distance), "size": Vector3(arena_size * 1.2, occ_wall_height, 2.0)},
		{"pos": Vector3(0, occ_wall_height / 2.0, -wall_distance), "size": Vector3(arena_size * 1.2, occ_wall_height, 2.0)},
		{"pos": Vector3(wall_distance, occ_wall_height / 2.0, 0), "size": Vector3(2.0, occ_wall_height, arena_size * 1.2)},
		{"pos": Vector3(-wall_distance, occ_wall_height / 2.0, 0), "size": Vector3(2.0, occ_wall_height, arena_size * 1.2)}
	]

	for i in range(wall_configs.size()):
		var config: Dictionary = wall_configs[i]
		var occluder: OccluderInstance3D = OccluderInstance3D.new()
		occluder.name = "WallOccluder_%d" % i
		occluder.position = config.pos

		var box_occluder: BoxOccluder3D = BoxOccluder3D.new()
		box_occluder.size = config.size
		occluder.occluder = box_occluder

		add_child(occluder)
		occluders.append(occluder)

	# Create occluders for large structures (pillars, bunkers)
	for platform in platforms:
		if not is_instance_valid(platform):
			continue
		if not platform.mesh is BoxMesh:
			continue

		var box_mesh: BoxMesh = platform.mesh as BoxMesh
		# Only create occluders for tall structures
		if box_mesh.size.y < 5.0:
			continue

		var occluder: OccluderInstance3D = OccluderInstance3D.new()
		occluder.name = "StructureOccluder_%s" % platform.name
		occluder.position = platform.position

		var box_occluder: BoxOccluder3D = BoxOccluder3D.new()
		box_occluder.size = box_mesh.size * 0.9  # Slightly smaller to avoid z-fighting
		occluder.occluder = box_occluder

		add_child(occluder)
		occluders.append(occluder)

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Created %d occluders" % occluders.size())

func generate_spawn_markers() -> void:
	## Create Marker3D nodes at spawn positions for game integration

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Generating spawn markers...")

	var spawn_idx: int = 0
	for pos in clear_positions:
		if spawn_idx >= target_spawn_points:
			break

		var marker: Marker3D = Marker3D.new()
		marker.name = "SpawnPoint_%d" % spawn_idx
		marker.position = pos
		marker.add_to_group("spawn_points")

		add_child(marker)
		spawn_markers.append(marker)
		spawn_idx += 1

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Created %d spawn markers" % spawn_markers.size())

func get_spawn_points() -> PackedVector3Array:
	## Return spawn points for game integration (cached after first call)
	if not _cached_spawn_points.is_empty():
		return _cached_spawn_points

	for marker in spawn_markers:
		if is_instance_valid(marker):
			_cached_spawn_points.append(marker.global_position)

	# Fallback to clear_positions if no markers
	if _cached_spawn_points.is_empty():
		for pos in clear_positions:
			_cached_spawn_points.append(pos)

	return _cached_spawn_points

func get_random_spawn_point() -> Vector3:
	## Get a random spawn point for respawning
	var spawns: PackedVector3Array = get_spawn_points()
	if spawns.is_empty():
		return Vector3.ZERO
	return spawns[rng.randi() % spawns.size()]

# ============================================================================
# LEAK DETECTION
# ============================================================================

func check_for_leaks() -> Dictionary:
	## Pre-export leak detection via graph connectivity analysis
	## Returns {has_leak: bool, details: String, disconnected_rooms: Array}

	var result: Dictionary = {
		"has_leak": false,
		"details": "",
		"disconnected_rooms": []
	}

	if bsp_rooms.is_empty():
		result.details = "No rooms to analyze"
		return result

	# Build connectivity graph
	var visited: Dictionary = {}
	var to_visit: Array[int] = [bsp_rooms[0].room_id]
	visited[bsp_rooms[0].room_id] = true

	# BFS traversal
	while not to_visit.is_empty():
		var current_id: int = to_visit.pop_front()
		var current_room: BSPNode = null

		for room in bsp_rooms:
			if room.room_id == current_id:
				current_room = room
				break

		if current_room == null:
			continue

		for connected_id in current_room.connected_to:
			if not visited.has(connected_id):
				visited[connected_id] = true
				to_visit.append(connected_id)

	# Check if all rooms are reachable
	for room in bsp_rooms:
		if not visited.has(room.room_id):
			result.has_leak = true
			result.disconnected_rooms.append(room.room_id)

	if result.has_leak:
		result.details = "Disconnected rooms detected: %s" % str(result.disconnected_rooms)
		DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "WARNING: Potential map leak - %d disconnected room(s)" % result.disconnected_rooms.size())
	else:
		result.details = "All %d rooms are connected" % bsp_rooms.size()

	# Also check for rooms extending beyond arena bounds
	var max_extent: float = arena_size * 0.6
	for room in bsp_rooms:
		if absf(room.room.position.x) > max_extent or absf(room.room.position.y) > max_extent:
			result.has_leak = true
			result.details += "\nRoom %d extends beyond arena bounds" % room.room_id

		var room_end: Vector2 = room.room.position + room.room.size
		if absf(room_end.x) > max_extent or absf(room_end.y) > max_extent:
			result.has_leak = true
			result.details += "\nRoom %d end extends beyond arena bounds" % room.room_id

	return result

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

@export_group("Editor Preview")
@export var show_bsp_preview: bool = false  ## Show BSP room outlines in editor
@export var preview_room_color: Color = Color(0.2, 0.6, 1.0, 0.3)  ## Color for room previews
@export var preview_corridor_color: Color = Color(0.2, 1.0, 0.4, 0.3)  ## Color for corridor previews

var _preview_meshes: Array[MeshInstance3D] = []

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and show_bsp_preview:
		update_editor_preview()

func update_editor_preview() -> void:
	## Update editor preview meshes for BSP layout visualization

	# Only update if BSP rooms exist
	if bsp_rooms.is_empty() and not use_bsp_layout:
		clear_editor_preview()
		return

	# Generate preview if we don't have any
	if _preview_meshes.is_empty() and use_bsp_layout:
		generate_editor_preview()

func generate_editor_preview() -> void:
	## Generate preview meshes for BSP rooms and corridors in editor

	clear_editor_preview()

	# Create preview for arena bounds
	var arena_preview: MeshInstance3D = create_preview_box(
		Vector3(0, 0, 0),
		Vector3(arena_size, 1.0, arena_size),
		Color(0.5, 0.5, 0.5, 0.1)
	)
	arena_preview.name = "ArenaPreview"
	_preview_meshes.append(arena_preview)

	# Generate room previews if BSP rooms exist
	for room in bsp_rooms:
		var room_center: Vector2 = room.get_center()
		var room_preview: MeshInstance3D = create_preview_box(
			Vector3(room_center.x, room.height_offset + 2.0, room_center.y),
			Vector3(room.room.size.x, 4.0, room.room.size.y),
			preview_room_color
		)
		room_preview.name = "RoomPreview_%d" % room.room_id
		_preview_meshes.append(room_preview)

	# Generate corridor previews
	for corridor_data in corridors:
		var level_z: float = corridor_data.level * level_height_offset
		for i in range(corridor_data.segments.size()):
			var segment: Rect2 = corridor_data.segments[i]
			var seg_center: Vector2 = segment.position + segment.size / 2.0
			var corridor_preview: MeshInstance3D = create_preview_box(
				Vector3(seg_center.x, level_z + 2.0, seg_center.y),
				Vector3(segment.size.x, 3.0, segment.size.y),
				preview_corridor_color
			)
			corridor_preview.name = "CorridorPreview_%d_%d" % [corridor_data.from_room, i]
			_preview_meshes.append(corridor_preview)

	# Show symmetry axis if enabled
	if enable_symmetry:
		var axis_length: float = arena_size * 1.2
		var axis_color: Color = Color(1.0, 0.2, 0.2, 0.5)
		var axis_preview: MeshInstance3D
		if symmetry_axis == 0:  # X-axis
			axis_preview = create_preview_box(
				Vector3(0, 5, 0),
				Vector3(0.5, 10.0, axis_length),
				axis_color
			)
		else:  # Z-axis
			axis_preview = create_preview_box(
				Vector3(0, 5, 0),
				Vector3(axis_length, 10.0, 0.5),
				axis_color
			)
		axis_preview.name = "SymmetryAxisPreview"
		_preview_meshes.append(axis_preview)

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Editor Preview: %d rooms, %d corridors, symmetry=%s" % [
		bsp_rooms.size(), corridors.size(), "on" if enable_symmetry else "off"
	])

func create_preview_box(pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	## Create a transparent preview box for editor visualization

	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size

	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	instance.name = "PreviewBox"

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.set_surface_override_material(0, material)

	add_child(instance)
	return instance

func clear_editor_preview() -> void:
	## Remove all preview meshes

	for mesh in _preview_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_preview_meshes.clear()

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
	if enable_symmetry and not use_bsp_layout:
		warnings.append("Symmetry works best with BSP layout enabled")
	if enable_hazards and hazard_count > 4:
		warnings.append("Many hazard zones may make the arena too dangerous")

	return warnings

# ============================================================================
# GENERATE MAP METHOD (for tool script usage)
# ============================================================================

func generate_map() -> void:
	## Alternative entry point for tool script usage
	## Calls generate_level() which handles both runtime and export
	generate_level()
