extends Node3D

## Sonic-Style Procedural Level Generator (Type A) - v3.0
## Creates dynamic, replayable, speedrun-friendly levels with:
## - Central hub + radiating branching paths (8-20)
## - Floating platforms (15-40) with Perlin noise clustering across 3-5 tiers
## - Full loops, half-pipes, grind rails, tunnels, boost pads
## - L-system path generation with AABB collision avoidance
## - Graph-based connectivity verification
## - Optimized with MultiMesh and StaticBody3D
##
## v3.0: Complete overhaul for Sonic-style speedrun levels

# ============================================================================
# EXPORTED PARAMETERS
# ============================================================================

@export var level_seed: int = 0
@export var arena_size: float = 120.0  # Base size, scales from 60-150 based on size parameter
@export var complexity: int = 3  # 1-5, affects element density

# Legacy parameters (for backwards compatibility with world.gd)
@export var platform_count: int = 30
@export var ramp_count: int = 20
@export var min_spacing: float = 5.0

# ============================================================================
# INTERNAL CONSTANTS
# ============================================================================

# Tier heights for platforms
const TIER_HEIGHTS: Array[float] = [4.0, 10.0, 18.0, 28.0, 40.0]
const MAX_TIERS: int = 5

# Path generation
const MIN_PATH_COUNT: int = 8
const MAX_PATH_COUNT: int = 20
const MIN_PATH_LENGTH: float = 30.0
const MAX_PATH_LENGTH: float = 80.0

# Element counts (base values, scaled by complexity)
const BASE_GRIND_RAILS: int = 8
const BASE_BOOST_PADS: int = 6
const BASE_LOOPS: int = 4
const BASE_HALF_PIPES: int = 3
const BASE_TUNNELS: int = 2

# Slope angles for momentum-friendly design
const MIN_SLOPE_ANGLE: float = 10.0
const MAX_SLOPE_ANGLE: float = 45.0

# Performance limits
const MAX_POLYGONS: int = 50000
var current_polygon_count: int = 0

# ============================================================================
# INTERNAL STATE
# ============================================================================

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var noise: FastNoiseLite
var height_noise: FastNoiseLite  # For organic height variation
var platforms: Array = []
var grind_rails: Array = []
var boost_pads: Array = []
var geometry_positions: Array[Dictionary] = []
var spawn_points: PackedVector3Array = PackedVector3Array()
var ability_spawn_positions: Array[Vector3] = []

# Path network for connectivity
var path_nodes: Array[Dictionary] = []  # {id, position, connections}
var connectivity_graph: Dictionary = {}

# Material manager
var material_manager = preload("res://scripts/procedural_material_manager.gd").new()

# MultiMesh instances for optimization
var platform_multimesh: MultiMeshInstance3D = null
var rail_segment_multimesh: MultiMeshInstance3D = null

# Complexity scaling
var scaled_path_count: int
var scaled_platform_count: int
var scaled_grind_rails: int
var scaled_boost_pads: int
var scaled_loops: int
var scaled_half_pipes: int
var scaled_tunnels: int
var active_tier_count: int

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	generate_level()

func generate_level(size: float = -1.0, complexity_override: int = -1) -> void:
	"""Generate a complete procedural Sonic-style level
	Args:
		size: Override arena_size (if -1, uses exported value)
		complexity_override: Override complexity (if -1, uses exported value)
	"""
	# Apply overrides if provided
	if size > 0:
		arena_size = size
	if complexity_override > 0:
		complexity = complexity_override

	# Initialize RNG with seed for reproducibility (MP sync)
	if level_seed == 0:
		level_seed = randi()
	rng.seed = level_seed

	print("======================================")
	print("Generating Sonic-Style Level (v3.0)")
	print("  Seed: %d" % level_seed)
	print("  Arena Size: %.1f" % arena_size)
	print("  Complexity: %d" % complexity)
	print("======================================")

	# Initialize noise generators
	_initialize_noise()

	# Calculate element counts based on complexity
	_calculate_complexity_scaling()

	# Clear existing geometry
	clear_level()

	# === PHASE 1: Central Hub ===
	generate_central_hub()

	# === PHASE 2: Radiating Paths ===
	generate_radiating_paths()

	# === PHASE 3: Floating Platforms (Perlin Clustered) ===
	generate_floating_platforms()

	# === PHASE 4: Grind Rails (Spline-Based) ===
	generate_grind_rails()

	# === PHASE 5: Boost Pads ===
	generate_boost_pads()

	# === PHASE 6: Loops and Curves ===
	generate_loops_and_curves()

	# === PHASE 7: Half-Pipes ===
	generate_half_pipes()

	# === PHASE 8: Tunnels ===
	generate_tunnels()

	# === PHASE 9: Connecting Ramps ===
	generate_connecting_ramps()

	# === PHASE 10: Death Zone ===
	generate_death_zone()

	# === PHASE 11: Spawn Points ===
	generate_spawn_points()

	# === PHASE 12: Verify Connectivity ===
	verify_connectivity()

	# === PHASE 13: Apply Materials ===
	apply_procedural_textures()

	print("Level generation complete!")
	print("  Platforms: %d" % platforms.size())
	print("  Grind Rails: %d" % grind_rails.size())
	print("  Boost Pads: %d" % boost_pads.size())
	print("  Spawn Points: %d" % spawn_points.size())
	print("  Ability Spots: %d" % ability_spawn_positions.size())
	print("  Estimated Polys: ~%d" % current_polygon_count)
	print("======================================")

func _initialize_noise() -> void:
	"""Initialize Perlin noise generators for organic terrain"""
	noise = FastNoiseLite.new()
	noise.seed = level_seed
	noise.frequency = 0.03
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_octaves = 3

	height_noise = FastNoiseLite.new()
	height_noise.seed = level_seed + 1000
	height_noise.frequency = 0.02
	height_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	height_noise.fractal_octaves = 4

func _calculate_complexity_scaling() -> void:
	"""Calculate element counts based on complexity level (1-5)"""
	complexity = clampi(complexity, 1, 5)

	# Scale factor from 0.5 (complexity 1) to 1.5 (complexity 5)
	var scale: float = 0.5 + (complexity - 1) * 0.25

	# Path count: 8-20 based on complexity
	scaled_path_count = clampi(int(MIN_PATH_COUNT + (MAX_PATH_COUNT - MIN_PATH_COUNT) * (scale - 0.5)), MIN_PATH_COUNT, MAX_PATH_COUNT)

	# Platform count: 15-40 based on complexity
	scaled_platform_count = clampi(int(15 + 25 * (scale - 0.5) * 2), 15, 40)

	# Override with legacy parameter if set higher
	if platform_count > scaled_platform_count:
		scaled_platform_count = platform_count

	# Other elements
	scaled_grind_rails = clampi(int(BASE_GRIND_RAILS * scale), 8, 16)
	scaled_boost_pads = clampi(int(BASE_BOOST_PADS * scale), 6, 12)
	scaled_loops = clampi(int(BASE_LOOPS * scale), 4, 8)
	scaled_half_pipes = clampi(int(BASE_HALF_PIPES * scale), 2, 5)
	scaled_tunnels = clampi(int(BASE_TUNNELS * scale), 1, 4)

	# Active tiers: 3-5 based on complexity
	active_tier_count = clampi(3 + (complexity - 1) / 2, 3, MAX_TIERS)

	print("Complexity scaling (level %d):" % complexity)
	print("  Paths: %d, Platforms: %d, Rails: %d" % [scaled_path_count, scaled_platform_count, scaled_grind_rails])
	print("  Boost Pads: %d, Loops: %d, Half-Pipes: %d, Tunnels: %d" % [scaled_boost_pads, scaled_loops, scaled_half_pipes, scaled_tunnels])
	print("  Active Tiers: %d" % active_tier_count)

func clear_level() -> void:
	"""Remove all existing level geometry"""
	for child in get_children():
		child.queue_free()
	platforms.clear()
	grind_rails.clear()
	boost_pads.clear()
	geometry_positions.clear()
	path_nodes.clear()
	connectivity_graph.clear()
	spawn_points.clear()
	ability_spawn_positions.clear()
	current_polygon_count = 0

# ============================================================================
# CENTRAL HUB GENERATION
# ============================================================================

func generate_central_hub() -> void:
	"""Generate the central hub platform where all paths originate"""
	var hub_radius: float = arena_size * 0.15  # Hub is 15% of arena size
	var hub_thickness: float = 3.0

	# Create octagonal hub platform for Sonic-style aesthetic
	var hub: MeshInstance3D = MeshInstance3D.new()
	hub.name = "CentralHub"

	# Use cylinder mesh for the hub (smooth, circular)
	var cylinder_mesh: CylinderMesh = CylinderMesh.new()
	cylinder_mesh.top_radius = hub_radius
	cylinder_mesh.bottom_radius = hub_radius * 1.1  # Slightly wider at base
	cylinder_mesh.height = hub_thickness
	cylinder_mesh.radial_segments = 16  # Smooth but performant
	hub.mesh = cylinder_mesh
	hub.position = Vector3(0, hub_thickness / 2.0, 0)
	add_child(hub)

	# Add collision
	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = hub_radius
	shape.height = hub_thickness
	collision.shape = shape
	static_body.add_child(collision)
	hub.add_child(static_body)

	platforms.append(hub)
	current_polygon_count += cylinder_mesh.radial_segments * 4

	# Register hub as a path node (central node 0)
	_add_path_node(0, Vector3(0, hub_thickness, 0))

	# Create elevated ring around hub for visual interest
	var ring_height: float = 6.0
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.name = "HubRing"
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = hub_radius * 0.8
	ring_mesh.outer_radius = hub_radius * 0.95
	ring.mesh = ring_mesh
	ring.position = Vector3(0, ring_height, 0)
	add_child(ring)

	# Ring collision (approximated with multiple boxes)
	var ring_static: StaticBody3D = StaticBody3D.new()
	for i in range(8):
		var angle: float = i * TAU / 8.0
		var ring_col: CollisionShape3D = CollisionShape3D.new()
		var ring_shape: BoxShape3D = BoxShape3D.new()
		ring_shape.size = Vector3(hub_radius * 0.4, 0.5, hub_radius * 0.2)
		ring_col.shape = ring_shape
		ring_col.position = Vector3(cos(angle) * hub_radius * 0.85, 0, sin(angle) * hub_radius * 0.85)
		ring_col.rotation.y = angle
		ring_static.add_child(ring_col)
	ring.add_child(ring_static)

	platforms.append(ring)
	current_polygon_count += 200  # Torus estimate

	register_geometry(Vector3.ZERO, Vector3(hub_radius * 2, hub_thickness, hub_radius * 2))

	print("Generated central hub (radius: %.1f)" % hub_radius)

# ============================================================================
# RADIATING PATH GENERATION (L-SYSTEM / RANDOM WALK)
# ============================================================================

func generate_radiating_paths() -> void:
	"""Generate branching paths radiating from the central hub using L-system approach"""
	var hub_radius: float = arena_size * 0.15
	var max_extent: float = arena_size * 0.45

	print("Generating %d radiating paths..." % scaled_path_count)

	for i in range(scaled_path_count):
		var base_angle: float = (float(i) / scaled_path_count) * TAU
		# Add slight randomness to angle
		var angle: float = base_angle + rng.randf_range(-0.15, 0.15)

		# Generate path using random walk with L-system branching
		var path_data: Dictionary = _generate_path_branch(
			Vector3(cos(angle) * hub_radius, 3.0, sin(angle) * hub_radius),
			angle,
			rng.randf_range(MIN_PATH_LENGTH, MAX_PATH_LENGTH),
			0  # Depth for recursion
		)

		if path_data.points.size() >= 3:
			_build_path_geometry(path_data, i)

			# Register end point as path node
			var end_pos: Vector3 = path_data.points[-1]
			_add_path_node(i + 1, end_pos)
			_connect_path_nodes(0, i + 1)  # Connect to hub

func _generate_path_branch(start: Vector3, direction: float, length: float, depth: int) -> Dictionary:
	"""Generate a path using random walk with optional branching
	Returns: {points: Array[Vector3], type: String, branches: Array[Dictionary]}
	"""
	var result: Dictionary = {
		"points": [start],
		"type": _choose_path_type(),
		"branches": []
	}

	var current_pos: Vector3 = start
	var current_dir: float = direction
	var remaining_length: float = length
	var segment_length: float = rng.randf_range(8.0, 15.0)

	var max_extent: float = arena_size * 0.45
	var max_iterations: int = 20
	var iteration: int = 0

	while remaining_length > 0 and iteration < max_iterations:
		iteration += 1

		# Calculate next segment
		var seg_len: float = min(segment_length, remaining_length)

		# Random walk: slight direction changes
		current_dir += rng.randf_range(-0.3, 0.3)

		# Height variation using Perlin noise
		var height_var: float = height_noise.get_noise_2d(current_pos.x * 0.1, current_pos.z * 0.1) * 8.0
		var target_height: float = clampf(current_pos.y + height_var, 2.0, TIER_HEIGHTS[active_tier_count - 1])

		# Calculate next position
		var next_pos: Vector3 = Vector3(
			current_pos.x + cos(current_dir) * seg_len,
			target_height,
			current_pos.z + sin(current_dir) * seg_len
		)

		# Clamp to arena bounds
		var dist_from_center: float = Vector2(next_pos.x, next_pos.z).length()
		if dist_from_center > max_extent:
			var scale_factor: float = max_extent / dist_from_center
			next_pos.x *= scale_factor
			next_pos.z *= scale_factor

		# Check collision with existing geometry
		var proposed_size: Vector3 = Vector3(seg_len + 4.0, 3.0, 6.0)
		if check_spacing(next_pos, proposed_size):
			result.points.append(next_pos)
			current_pos = next_pos
			remaining_length -= seg_len

			# L-system branching: 20% chance to branch at depth < 2
			if depth < 2 and rng.randf() < 0.2 and remaining_length > MIN_PATH_LENGTH * 0.5:
				var branch_angle: float = current_dir + rng.randf_range(0.5, 1.2) * (1 if rng.randf() > 0.5 else -1)
				var branch: Dictionary = _generate_path_branch(
					current_pos,
					branch_angle,
					remaining_length * 0.6,
					depth + 1
				)
				if branch.points.size() >= 2:
					result.branches.append(branch)
		else:
			# Collision detected, try different direction
			current_dir += PI * 0.25

	return result

func _choose_path_type() -> String:
	"""Choose a random path type with weighted probabilities"""
	var roll: float = rng.randf()
	if roll < 0.35:
		return "ramp"
	elif roll < 0.55:
		return "curve"
	elif roll < 0.70:
		return "straight"
	elif roll < 0.85:
		return "stairs"
	else:
		return "bridge"

func _build_path_geometry(path_data: Dictionary, path_index: int) -> void:
	"""Build 3D geometry for a path"""
	var points: Array = path_data.points
	if points.size() < 2:
		return

	var path_type: String = path_data.type

	for i in range(points.size() - 1):
		var start: Vector3 = points[i]
		var end: Vector3 = points[i + 1]
		var segment_vec: Vector3 = end - start
		var segment_length: float = segment_vec.length()
		var mid_point: Vector3 = (start + end) / 2.0

		# Calculate slope angle
		var height_diff: float = end.y - start.y
		var horizontal_dist: float = Vector2(segment_vec.x, segment_vec.z).length()
		var slope_angle: float = rad_to_deg(atan2(height_diff, horizontal_dist))
		slope_angle = clampf(slope_angle, -MAX_SLOPE_ANGLE, MAX_SLOPE_ANGLE)

		# Create path segment mesh
		var segment: MeshInstance3D = MeshInstance3D.new()
		segment.name = "Path%d_Seg%d" % [path_index, i]

		var width: float = 6.0 if path_type != "bridge" else 4.0
		var thickness: float = 1.0 if path_type != "stairs" else 0.5

		var box_mesh: BoxMesh = BoxMesh.new()
		box_mesh.size = Vector3(width, thickness, segment_length)
		segment.mesh = box_mesh

		segment.position = mid_point
		segment.look_at(end, Vector3.UP)
		segment.rotation.x = deg_to_rad(-slope_angle)

		add_child(segment)

		# Add collision
		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = box_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		segment.add_child(static_body)

		platforms.append(segment)
		register_geometry(mid_point, Vector3(width, thickness, segment_length))
		current_polygon_count += 12  # Box = 12 triangles

		# Add ability spawn position along path
		if rng.randf() < 0.3:  # 30% chance per segment
			ability_spawn_positions.append(mid_point + Vector3.UP * 2.0)

	# Build branch geometry recursively
	for branch in path_data.branches:
		_build_path_geometry(branch, path_index * 100 + path_data.branches.find(branch))

# ============================================================================
# FLOATING PLATFORM GENERATION (PERLIN CLUSTERING)
# ============================================================================

func generate_floating_platforms() -> void:
	"""Generate floating platforms using Perlin noise clustering across multiple tiers"""
	print("Generating %d floating platforms across %d tiers..." % [scaled_platform_count, active_tier_count])

	var generated: int = 0
	var max_attempts: int = scaled_platform_count * 10
	var attempt: int = 0

	while generated < scaled_platform_count and attempt < max_attempts:
		attempt += 1

		# Use Perlin noise to cluster platforms
		var test_x: float = rng.randf_range(-arena_size * 0.4, arena_size * 0.4)
		var test_z: float = rng.randf_range(-arena_size * 0.4, arena_size * 0.4)

		# Use noise to determine if this is a good cluster location
		var cluster_value: float = noise.get_noise_2d(test_x * 0.05, test_z * 0.05)
		if cluster_value < -0.2:  # Skip low-cluster areas (creates gaps)
			continue

		# Select tier based on noise and randomness
		var tier_noise: float = height_noise.get_noise_2d(test_x * 0.03, test_z * 0.03)
		var tier_index: int = clampi(int((tier_noise + 1.0) * 0.5 * active_tier_count), 0, active_tier_count - 1)
		var base_height: float = TIER_HEIGHTS[tier_index]

		# Add height variation within tier
		var height_variation: float = rng.randf_range(-2.0, 2.0)
		var platform_y: float = base_height + height_variation

		var platform_pos: Vector3 = Vector3(test_x, platform_y, test_z)

		# Randomize platform size based on tier (higher = smaller)
		var size_factor: float = 1.0 - tier_index * 0.1
		var width: float = rng.randf_range(5.0, 10.0) * size_factor
		var depth: float = rng.randf_range(5.0, 10.0) * size_factor
		var height: float = rng.randf_range(0.8, 1.5)
		var platform_size: Vector3 = Vector3(width, height, depth)

		if not check_spacing(platform_pos, platform_size):
			continue

		# Create platform
		var platform: MeshInstance3D = _create_platform_mesh(platform_pos, platform_size, "Platform%d" % generated)
		platforms.append(platform)
		register_geometry(platform_pos, platform_size)

		# Add path node for connectivity
		_add_path_node(1000 + generated, platform_pos + Vector3.UP * height)

		# 40% chance to add ability spawn on platform
		if rng.randf() < 0.4:
			ability_spawn_positions.append(platform_pos + Vector3.UP * (height + 1.5))

		generated += 1

	print("Generated %d floating platforms (%d attempts)" % [generated, attempt])

func _create_platform_mesh(pos: Vector3, size: Vector3, name_str: String) -> MeshInstance3D:
	"""Create a platform mesh with collision"""
	var platform: MeshInstance3D = MeshInstance3D.new()
	platform.name = name_str

	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	platform.mesh = mesh
	platform.position = pos

	add_child(platform)

	# Add collision
	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	static_body.add_child(collision)
	platform.add_child(static_body)

	current_polygon_count += 12

	return platform

# ============================================================================
# GRIND RAIL GENERATION (SPLINE-BASED)
# ============================================================================

func generate_grind_rails() -> void:
	"""Generate spline-based grind rails connecting platforms and paths"""
	print("Generating %d grind rails..." % scaled_grind_rails)

	var rails_generated: int = 0

	# Generate perimeter rails (curved around arena edge)
	var perimeter_rail_count: int = scaled_grind_rails / 2
	for i in range(perimeter_rail_count):
		var rail: Path3D = _generate_perimeter_rail(i, perimeter_rail_count)
		if rail:
			add_child(rail)
			grind_rails.append(rail)
			_create_rail_visual(rail)
			rails_generated += 1

	# Generate connecting rails between platforms
	var connecting_rail_count: int = scaled_grind_rails - rails_generated
	for i in range(connecting_rail_count):
		var rail: Path3D = _generate_connecting_rail(i)
		if rail:
			add_child(rail)
			grind_rails.append(rail)
			_create_rail_visual(rail)
			rails_generated += 1

	# Generate spiral/vertical rails
	var spiral_count: int = clampi(complexity, 2, 4)
	for i in range(spiral_count):
		var rail: Path3D = _generate_spiral_rail(i, spiral_count)
		if rail:
			add_child(rail)
			grind_rails.append(rail)
			_create_rail_visual(rail)
			rails_generated += 1

	print("Generated %d grind rails total" % rails_generated)

func _generate_perimeter_rail(index: int, total: int) -> Path3D:
	"""Generate a curved rail around the arena perimeter"""
	var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
	rail.name = "PerimeterRail%d" % index
	rail.curve = Curve3D.new()

	var rail_distance: float = arena_size * 0.42
	var angle_start: float = (float(index) / total) * TAU
	var angle_end: float = angle_start + (TAU / total) * 0.75

	var base_height: float = 4.0 + (index % 3) * 3.0
	var num_points: int = 12

	for j in range(num_points):
		var t: float = float(j) / (num_points - 1)
		var angle: float = lerp(angle_start, angle_end, t)

		var x: float = cos(angle) * rail_distance
		var z: float = sin(angle) * rail_distance
		var height_wave: float = sin(t * PI) * 2.0
		var y: float = base_height + height_wave

		rail.curve.add_point(Vector3(x, y, z))

	_smooth_rail_tangents(rail)
	return rail

func _generate_connecting_rail(index: int) -> Path3D:
	"""Generate a rail connecting two platforms or path points"""
	if path_nodes.size() < 2:
		return null

	# Select two random nodes to connect
	var node_a: Dictionary = path_nodes[rng.randi() % path_nodes.size()]
	var node_b: Dictionary = path_nodes[rng.randi() % path_nodes.size()]

	if node_a.id == node_b.id:
		return null

	var start: Vector3 = node_a.position + Vector3.UP * 2.0
	var end: Vector3 = node_b.position + Vector3.UP * 2.0

	if start.distance_to(end) < 15.0 or start.distance_to(end) > 60.0:
		return null

	var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
	rail.name = "ConnectingRail%d" % index
	rail.curve = Curve3D.new()

	# Create curved path between points
	var mid: Vector3 = (start + end) / 2.0
	mid.y += rng.randf_range(3.0, 8.0)  # Arc upward

	var num_points: int = 8
	for j in range(num_points):
		var t: float = float(j) / (num_points - 1)
		var pos: Vector3 = _bezier_quadratic(start, mid, end, t)
		rail.curve.add_point(pos)

	_smooth_rail_tangents(rail)

	# Connect nodes in graph
	_connect_path_nodes(node_a.id, node_b.id)

	return rail

func _generate_spiral_rail(index: int, total: int) -> Path3D:
	"""Generate a vertical spiral rail"""
	var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
	rail.name = "SpiralRail%d" % index
	rail.curve = Curve3D.new()

	var angle_offset: float = (float(index) / total) * TAU
	var base_distance: float = arena_size * 0.25
	var spiral_height: float = TIER_HEIGHTS[active_tier_count - 1] * 0.8
	var num_points: int = 16
	var turns: float = 1.5

	for j in range(num_points):
		var t: float = float(j) / (num_points - 1)
		var angle: float = angle_offset + t * TAU * turns
		var distance: float = base_distance * (1.0 - t * 0.3)  # Spiral inward slightly

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance
		var y: float = 3.0 + t * spiral_height

		rail.curve.add_point(Vector3(x, y, z))

	_smooth_rail_tangents(rail)
	return rail

func _smooth_rail_tangents(rail: Path3D) -> void:
	"""Calculate and set smooth tangent handles for rail curve"""
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

func _create_rail_visual(rail: Path3D) -> void:
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
	var radial_segments: int = 6  # Reduced for performance
	var length_segments: int = int(rail.curve.get_baked_length() * 1.5)
	length_segments = clampi(length_segments, 8, 40)

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

	current_polygon_count += length_segments * radial_segments * 2

# ============================================================================
# BOOST PAD GENERATION
# ============================================================================

func generate_boost_pads() -> void:
	"""Generate boost pads that give players impulse up/forward"""
	print("Generating %d boost pads..." % scaled_boost_pads)

	var generated: int = 0

	# Place boost pads along paths and on platforms
	for i in range(scaled_boost_pads):
		var position: Vector3
		var direction: Vector3

		if rng.randf() < 0.6 and path_nodes.size() > 0:
			# Place on a path node
			var node: Dictionary = path_nodes[rng.randi() % path_nodes.size()]
			position = node.position + Vector3.UP * 0.5
			direction = Vector3(rng.randf_range(-1, 1), 0.5, rng.randf_range(-1, 1)).normalized()
		else:
			# Place randomly
			position = Vector3(
				rng.randf_range(-arena_size * 0.35, arena_size * 0.35),
				rng.randf_range(3.0, TIER_HEIGHTS[active_tier_count - 2]),
				rng.randf_range(-arena_size * 0.35, arena_size * 0.35)
			)
			direction = Vector3.UP

		var boost_pad: Area3D = _create_boost_pad(position, direction, i)
		if boost_pad:
			add_child(boost_pad)
			boost_pads.append(boost_pad)
			generated += 1

	print("Generated %d boost pads" % generated)

func _create_boost_pad(pos: Vector3, direction: Vector3, index: int) -> Area3D:
	"""Create a boost pad at the given position"""
	var pad: Area3D = Area3D.new()
	pad.name = "BoostPad%d" % index
	pad.position = pos
	pad.collision_layer = 0
	pad.collision_mask = 2  # Detect players
	pad.add_to_group("boost_pads")

	# Store boost direction as metadata
	pad.set_meta("boost_direction", direction)
	pad.set_meta("boost_force", 350.0)  # Adjustable boost strength

	# Visual mesh (glowing arrow/chevron)
	var visual: MeshInstance3D = MeshInstance3D.new()
	var prism: PrismMesh = PrismMesh.new()
	prism.size = Vector3(3.0, 0.5, 3.0)
	visual.mesh = prism

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 1.0, 0.3)  # Bright green
	material.emission_enabled = true
	material.emission = Color(0.2, 1.0, 0.3) * 0.5
	visual.material_override = material

	# Point visual in boost direction
	if direction != Vector3.UP:
		visual.look_at(pos + direction, Vector3.UP)

	pad.add_child(visual)

	# Collision area
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(3.0, 1.0, 3.0)
	collision.shape = shape
	pad.add_child(collision)

	# Connect signal
	pad.body_entered.connect(_on_boost_pad_entered.bind(pad))

	current_polygon_count += 12

	return pad

func _on_boost_pad_entered(body: Node3D, pad: Area3D) -> void:
	"""Apply boost when player enters pad"""
	if body.has_method("apply_central_impulse"):
		var direction: Vector3 = pad.get_meta("boost_direction", Vector3.UP)
		var force: float = pad.get_meta("boost_force", 350.0)
		body.apply_central_impulse(direction * force)
		DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Boost pad activated: impulse %.1f" % force)

# ============================================================================
# LOOPS AND CURVES GENERATION
# ============================================================================

func generate_loops_and_curves() -> void:
	"""Generate full and partial loop structures"""
	print("Generating %d loops/curves..." % scaled_loops)

	for i in range(scaled_loops):
		var angle: float = (float(i) / scaled_loops) * TAU + rng.randf_range(-0.2, 0.2)
		var distance: float = rng.randf_range(arena_size * 0.2, arena_size * 0.35)
		var center: Vector3 = Vector3(
			cos(angle) * distance,
			rng.randf_range(5.0, 12.0),
			sin(angle) * distance
		)

		# 30% chance for full loop, 70% for partial curve
		var is_full_loop: bool = rng.randf() < 0.3

		if is_full_loop:
			_create_full_loop(center, i)
		else:
			_create_partial_curve(center, i)

func _create_full_loop(center: Vector3, index: int) -> void:
	"""Create a full loop (tube extruded along circle)"""
	var loop_radius: float = 8.0
	var tube_radius: float = 2.0
	var segments: int = 24

	var loop: MeshInstance3D = MeshInstance3D.new()
	loop.name = "FullLoop%d" % index

	# Create torus mesh for the loop
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = loop_radius - tube_radius
	torus.outer_radius = loop_radius + tube_radius
	torus.rings = segments
	torus.ring_segments = 8
	loop.mesh = torus
	loop.position = center
	loop.rotation.x = PI / 2  # Stand the loop upright

	add_child(loop)

	# Add collision (approximated with capsules around the ring)
	var static_body: StaticBody3D = StaticBody3D.new()
	for j in range(8):
		var t: float = float(j) / 8.0
		var loop_angle: float = t * TAU
		var col_pos: Vector3 = Vector3(
			cos(loop_angle) * loop_radius,
			0,
			sin(loop_angle) * loop_radius
		)

		var col: CollisionShape3D = CollisionShape3D.new()
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = tube_radius
		capsule.height = loop_radius * 0.8
		col.shape = capsule
		col.position = col_pos
		col.rotation.y = loop_angle
		static_body.add_child(col)

	loop.add_child(static_body)
	platforms.append(loop)
	register_geometry(center, Vector3(loop_radius * 2 + tube_radius * 2, loop_radius * 2 + tube_radius * 2, tube_radius * 2))

	current_polygon_count += segments * 8 * 2

func _create_partial_curve(center: Vector3, index: int) -> void:
	"""Create a partial curved ramp/halfpipe shape"""
	var curve_extent: float = rng.randf_range(0.3, 0.6) * TAU  # 30-60% of circle
	var start_angle: float = rng.randf() * TAU
	var radius: float = 6.0
	var width: float = 4.0
	var segments: int = 12

	for j in range(segments):
		var t: float = float(j) / (segments - 1)
		var angle: float = start_angle + t * curve_extent

		var pos: Vector3 = center + Vector3(
			cos(angle) * radius,
			sin(angle * 0.5) * 3.0,  # Height variation
			sin(angle) * radius
		)

		var segment: MeshInstance3D = MeshInstance3D.new()
		segment.name = "Curve%d_Seg%d" % [index, j]

		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(width, 0.5, radius * curve_extent / segments * 1.5)
		segment.mesh = mesh
		segment.position = pos
		segment.rotation.y = angle + PI / 2

		add_child(segment)

		# Collision
		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		segment.add_child(static_body)

		platforms.append(segment)
		current_polygon_count += 12

# ============================================================================
# HALF-PIPE GENERATION
# ============================================================================

func generate_half_pipes() -> void:
	"""Generate U-shaped half-pipe troughs"""
	print("Generating %d half-pipes..." % scaled_half_pipes)

	for i in range(scaled_half_pipes):
		var angle: float = rng.randf() * TAU
		var distance: float = rng.randf_range(arena_size * 0.15, arena_size * 0.3)
		var center: Vector3 = Vector3(
			cos(angle) * distance,
			rng.randf_range(2.0, 8.0),
			sin(angle) * distance
		)

		_create_half_pipe(center, angle, i)

func _create_half_pipe(center: Vector3, direction: float, index: int) -> void:
	"""Create a U-shaped half-pipe trough"""
	var pipe_length: float = rng.randf_range(15.0, 30.0)
	var pipe_width: float = 6.0
	var pipe_height: float = 4.0
	var segments: int = 8

	# Create the half-pipe as a series of curved segments
	for j in range(segments):
		var t: float = float(j) / (segments - 1)
		var local_z: float = (t - 0.5) * pipe_length

		var pos: Vector3 = center + Vector3(
			cos(direction) * local_z,
			0,
			sin(direction) * local_z
		)

		# Create U-shaped cross-section using 3 boxes
		for side in range(3):
			var segment: MeshInstance3D = MeshInstance3D.new()
			segment.name = "HalfPipe%d_Seg%d_%d" % [index, j, side]

			var size: Vector3
			var offset: Vector3

			if side == 0:  # Bottom
				size = Vector3(pipe_width, 0.5, pipe_length / segments * 1.2)
				offset = Vector3.ZERO
			elif side == 1:  # Left wall
				size = Vector3(0.5, pipe_height, pipe_length / segments * 1.2)
				offset = Vector3(-pipe_width / 2, pipe_height / 2, 0)
			else:  # Right wall
				size = Vector3(0.5, pipe_height, pipe_length / segments * 1.2)
				offset = Vector3(pipe_width / 2, pipe_height / 2, 0)

			var mesh: BoxMesh = BoxMesh.new()
			mesh.size = size
			segment.mesh = mesh
			segment.position = pos + offset.rotated(Vector3.UP, direction)
			segment.rotation.y = direction

			add_child(segment)

			# Collision
			var static_body: StaticBody3D = StaticBody3D.new()
			var collision: CollisionShape3D = CollisionShape3D.new()
			var shape: BoxShape3D = BoxShape3D.new()
			shape.size = size
			collision.shape = shape
			static_body.add_child(collision)
			segment.add_child(static_body)

			platforms.append(segment)
			current_polygon_count += 12

	register_geometry(center, Vector3(pipe_width, pipe_height, pipe_length))

	# Add ability spawn in the half-pipe
	ability_spawn_positions.append(center + Vector3.UP * 2.0)

# ============================================================================
# TUNNEL GENERATION
# ============================================================================

func generate_tunnels() -> void:
	"""Generate cylindrical tunnels"""
	print("Generating %d tunnels..." % scaled_tunnels)

	for i in range(scaled_tunnels):
		var start_angle: float = rng.randf() * TAU
		var end_angle: float = start_angle + rng.randf_range(0.5, 1.5)
		var distance: float = rng.randf_range(arena_size * 0.2, arena_size * 0.35)

		var start: Vector3 = Vector3(
			cos(start_angle) * distance,
			rng.randf_range(3.0, 10.0),
			sin(start_angle) * distance
		)
		var end: Vector3 = Vector3(
			cos(end_angle) * distance,
			start.y + rng.randf_range(-3.0, 3.0),
			sin(end_angle) * distance
		)

		_create_tunnel(start, end, i)

func _create_tunnel(start: Vector3, end: Vector3, index: int) -> void:
	"""Create a cylindrical tunnel between two points"""
	var tunnel_radius: float = 3.0
	var segments: int = 12
	var length: float = start.distance_to(end)
	var direction: Vector3 = (end - start).normalized()
	var center: Vector3 = (start + end) / 2.0

	# Create tunnel shell using cylinder segments
	var tunnel: MeshInstance3D = MeshInstance3D.new()
	tunnel.name = "Tunnel%d" % index

	# Use a cylinder mesh
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = tunnel_radius
	mesh.bottom_radius = tunnel_radius
	mesh.height = length
	mesh.radial_segments = 12
	tunnel.mesh = mesh
	tunnel.position = center

	# Orient tunnel along direction
	tunnel.look_at(end, Vector3.UP)
	tunnel.rotation.x += PI / 2

	add_child(tunnel)

	# Collision (hollow cylinder approximated with box)
	var static_body: StaticBody3D = StaticBody3D.new()

	# Floor of tunnel
	var floor_col: CollisionShape3D = CollisionShape3D.new()
	var floor_shape: BoxShape3D = BoxShape3D.new()
	floor_shape.size = Vector3(tunnel_radius * 1.8, 0.5, length)
	floor_col.shape = floor_shape
	floor_col.position = Vector3(0, -tunnel_radius + 0.25, 0)
	static_body.add_child(floor_col)

	tunnel.add_child(static_body)
	platforms.append(tunnel)
	register_geometry(center, Vector3(tunnel_radius * 2, tunnel_radius * 2, length))

	current_polygon_count += mesh.radial_segments * 4

	# Add ability spawn inside tunnel
	ability_spawn_positions.append(center + Vector3.UP * 1.5)

# ============================================================================
# CONNECTING RAMPS
# ============================================================================

func generate_connecting_ramps() -> void:
	"""Generate ramps connecting different height levels"""
	print("Generating connecting ramps...")

	var ramps_generated: int = 0
	var target_ramps: int = scaled_platform_count / 3  # About 1 ramp per 3 platforms

	for i in range(min(path_nodes.size() - 1, target_ramps)):
		var node_a: Dictionary = path_nodes[i]
		var node_b: Dictionary = path_nodes[(i + 1) % path_nodes.size()]

		var height_diff: float = abs(node_a.position.y - node_b.position.y)
		if height_diff < 2.0 or height_diff > 15.0:
			continue

		var start: Vector3 = node_a.position if node_a.position.y < node_b.position.y else node_b.position
		var end: Vector3 = node_b.position if node_a.position.y < node_b.position.y else node_a.position

		_create_connecting_ramp(start, end, ramps_generated)
		ramps_generated += 1

	print("Generated %d connecting ramps" % ramps_generated)

func _create_connecting_ramp(start: Vector3, end: Vector3, index: int) -> void:
	"""Create a ramp connecting two points at different heights"""
	var ramp: MeshInstance3D = MeshInstance3D.new()
	ramp.name = "ConnectingRamp%d" % index

	var length: float = start.distance_to(end)
	var width: float = 5.0
	var thickness: float = 0.5
	var center: Vector3 = (start + end) / 2.0

	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(width, thickness, length)
	ramp.mesh = mesh
	ramp.position = center

	# Orient ramp
	ramp.look_at(end, Vector3.UP)
	var height_diff: float = end.y - start.y
	var horizontal_dist: float = Vector2(end.x - start.x, end.z - start.z).length()
	var slope_angle: float = atan2(height_diff, horizontal_dist)
	ramp.rotation.x = -slope_angle

	add_child(ramp)

	# Collision
	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	ramp.add_child(static_body)

	platforms.append(ramp)
	register_geometry(center, Vector3(width, thickness + height_diff, length))
	current_polygon_count += 12

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
	shape.size = Vector3(arena_size * 3, 10, arena_size * 3)
	collision.shape = shape
	death_zone.add_child(collision)

	death_zone.body_entered.connect(_on_death_zone_entered)

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Generated death zone")

func _on_death_zone_entered(body: Node3D) -> void:
	"""Handle player falling into death zone"""
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Death zone entered by: %s" % body.name)
	if body.has_method("fall_death"):
		body.fall_death()
	elif body.has_method("respawn"):
		body.respawn()

# ============================================================================
# SPAWN POINT GENERATION
# ============================================================================

func generate_spawn_points() -> void:
	"""Generate safe spawn points around the hub and on platforms"""
	spawn_points.clear()

	var hub_radius: float = arena_size * 0.12

	# Hub edge spawns (8 points)
	for i in range(8):
		var angle: float = (float(i) / 8.0) * TAU
		var spawn: Vector3 = Vector3(
			cos(angle) * hub_radius,
			4.0,
			sin(angle) * hub_radius
		)
		spawn_points.append(spawn)

	# Additional spawns on platforms (up to 8 more)
	var platform_spawns: int = 0
	for platform in platforms:
		if platform_spawns >= 8:
			break
		if platform.name.begins_with("Platform"):
			var spawn: Vector3 = platform.position + Vector3.UP * 3.0
			spawn_points.append(spawn)
			platform_spawns += 1

	print("Generated %d spawn points" % spawn_points.size())

func get_spawn_points() -> PackedVector3Array:
	"""Return available spawn points"""
	return spawn_points

func get_ability_spawn_positions() -> Array[Vector3]:
	"""Return positions for ability spawner"""
	return ability_spawn_positions

# ============================================================================
# CONNECTIVITY VERIFICATION
# ============================================================================

func _add_path_node(id: int, position: Vector3) -> void:
	"""Add a node to the path network"""
	path_nodes.append({
		"id": id,
		"position": position,
		"connections": []
	})
	connectivity_graph[id] = []

func _connect_path_nodes(id_a: int, id_b: int) -> void:
	"""Connect two nodes in the path network"""
	if id_a in connectivity_graph and id_b in connectivity_graph:
		if not id_b in connectivity_graph[id_a]:
			connectivity_graph[id_a].append(id_b)
		if not id_a in connectivity_graph[id_b]:
			connectivity_graph[id_b].append(id_a)

func verify_connectivity() -> void:
	"""Verify all major areas are reachable using flood fill"""
	if path_nodes.is_empty():
		print("Warning: No path nodes to verify connectivity")
		return

	var visited: Dictionary = {}
	var queue: Array = [0]  # Start from hub (node 0)

	while not queue.is_empty():
		var current: int = queue.pop_front()
		if current in visited:
			continue
		visited[current] = true

		if current in connectivity_graph:
			for neighbor in connectivity_graph[current]:
				if not neighbor in visited:
					queue.append(neighbor)

	var total_nodes: int = path_nodes.size()
	var connected_nodes: int = visited.size()

	if connected_nodes < total_nodes:
		print("Warning: Only %d/%d nodes connected. Adding emergency bridges..." % [connected_nodes, total_nodes])
		_add_emergency_connections(visited)
	else:
		print("Connectivity verified: All %d nodes reachable from hub" % total_nodes)

func _add_emergency_connections(visited: Dictionary) -> void:
	"""Add rails/ramps to connect isolated areas"""
	for node in path_nodes:
		if node.id in visited:
			continue

		# Find nearest connected node
		var nearest_id: int = -1
		var nearest_dist: float = INF

		for connected_node in path_nodes:
			if not connected_node.id in visited:
				continue
			var dist: float = node.position.distance_to(connected_node.position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_id = connected_node.id

		if nearest_id >= 0:
			# Create emergency rail
			var rail: Path3D = _generate_emergency_rail(node.position, path_nodes[nearest_id].position)
			if rail:
				add_child(rail)
				grind_rails.append(rail)
				_create_rail_visual(rail)
				_connect_path_nodes(node.id, nearest_id)
				print("Added emergency connection: node %d -> %d" % [node.id, nearest_id])

func _generate_emergency_rail(start: Vector3, end: Vector3) -> Path3D:
	"""Generate an emergency connecting rail"""
	var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
	rail.name = "EmergencyRail"
	rail.curve = Curve3D.new()

	var mid: Vector3 = (start + end) / 2.0
	mid.y = max(start.y, end.y) + 5.0

	rail.curve.add_point(start + Vector3.UP * 2.0)
	rail.curve.add_point(mid)
	rail.curve.add_point(end + Vector3.UP * 2.0)

	_smooth_rail_tangents(rail)
	return rail

# ============================================================================
# GEOMETRY UTILITIES
# ============================================================================

func check_spacing(new_pos: Vector3, new_size: Vector3, _new_rotation: Vector3 = Vector3.ZERO) -> bool:
	"""Check if a new piece of geometry would have proper spacing from existing geometry"""
	var new_half_size: Vector3 = new_size * 0.5

	for existing in geometry_positions:
		var existing_pos: Vector3 = existing.position
		var existing_size: Vector3 = existing.size
		var existing_half_size: Vector3 = existing_size * 0.5

		var distance: float = new_pos.distance_to(existing_pos)
		var combined_radius: float = (new_half_size.length() + existing_half_size.length()) + min_spacing

		if distance < combined_radius:
			var spacing_margin: float = min_spacing * 0.5

			var new_min: Vector3 = new_pos - new_half_size - Vector3.ONE * spacing_margin
			var new_max: Vector3 = new_pos + new_half_size + Vector3.ONE * spacing_margin

			var existing_min: Vector3 = existing_pos - existing_half_size - Vector3.ONE * spacing_margin
			var existing_max: Vector3 = existing_pos + existing_half_size + Vector3.ONE * spacing_margin

			if (new_min.x <= existing_max.x and new_max.x >= existing_min.x and
				new_min.y <= existing_max.y and new_max.y >= existing_min.y and
				new_min.z <= existing_max.z and new_max.z >= existing_min.z):
				return false

	return true

func register_geometry(pos: Vector3, size: Vector3, rotation: Vector3 = Vector3.ZERO) -> void:
	"""Register a piece of geometry in the spacing tracker"""
	geometry_positions.append({
		"position": pos,
		"size": size,
		"rotation": rotation
	})

func _bezier_quadratic(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	"""Calculate point on quadratic Bezier curve"""
	var q0: Vector3 = p0.lerp(p1, t)
	var q1: Vector3 = p1.lerp(p2, t)
	return q0.lerp(q1, t)

func apply_procedural_textures() -> void:
	"""Apply procedurally generated textures to all geometry"""
	material_manager.apply_materials_to_level(self)

# ============================================================================
# MID-ROUND EXPANSION SYSTEM (LEGACY SUPPORT)
# ============================================================================

func generate_secondary_map(offset: Vector3) -> void:
	"""Generate a secondary map at the specified offset position"""
	print("Generating secondary map at offset: ", offset)

	var secondary_seed: int = level_seed + 1000
	var old_seed: int = rng.seed
	rng.seed = secondary_seed

	# Generate secondary hub
	var hub_size: float = arena_size * 0.12
	var hub: MeshInstance3D = MeshInstance3D.new()
	hub.name = "SecondaryHub"
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = hub_size
	mesh.bottom_radius = hub_size * 1.1
	mesh.height = 3.0
	hub.mesh = mesh
	hub.position = offset + Vector3(0, 1.5, 0)
	add_child(hub)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = hub_size
	shape.height = 3.0
	collision.shape = shape
	static_body.add_child(collision)
	hub.add_child(static_body)

	platforms.append(hub)

	# Generate some platforms around secondary hub
	for i in range(scaled_platform_count / 2):
		var angle: float = rng.randf() * TAU
		var distance: float = rng.randf_range(hub_size + 5, arena_size * 0.3)
		var height: float = rng.randf_range(3.0, 15.0)

		var pos: Vector3 = offset + Vector3(
			cos(angle) * distance,
			height,
			sin(angle) * distance
		)

		var size: Vector3 = Vector3(
			rng.randf_range(5.0, 10.0),
			rng.randf_range(0.8, 1.5),
			rng.randf_range(5.0, 10.0)
		)

		var platform: MeshInstance3D = _create_platform_mesh(pos, size, "SecondaryPlatform%d" % i)
		platforms.append(platform)

	rng.seed = old_seed

	apply_procedural_textures()
	print("Secondary map generation complete at offset: ", offset)

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

	_smooth_rail_tangents(rail)

	add_child(rail)
	grind_rails.append(rail)
	_create_rail_visual(rail)

	print("Connecting rail created with ", num_points, " points")
