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

	# Q3 arenas have deliberate structure - complexity adds more features
	match complexity:
		1:  # Simple - basic arena with minimal features
			room_count = 2          # Side alcoves
			pillar_count = 4        # Central pillars for cover
			cover_count = 4         # Small cover blocks
			jump_pad_count = 2      # Strategic jump pads
			teleporter_pair_count = 1
			tunnel_count = 0
			catwalk_count = 1       # One elevated walkway
		2:  # Medium (classic Q3 arena)
			room_count = 2          # Weapon rooms
			pillar_count = 4        # Cover pillars
			cover_count = 6         # Cover blocks
			jump_pad_count = 4      # Jump pads to upper areas
			teleporter_pair_count = 1
			tunnel_count = 1        # Underground passage
			catwalk_count = 2       # Elevated walkways
		3:  # Complex - more interconnected
			room_count = 4          # Multiple weapon rooms
			pillar_count = 6        # More cover
			cover_count = 8         # More cover blocks
			jump_pad_count = 5      # More vertical movement
			teleporter_pair_count = 2
			tunnel_count = 2        # Multiple tunnels
			catwalk_count = 3       # More walkways
		4:  # Extreme - full featured arena
			room_count = 4          # Multiple weapon rooms
			pillar_count = 8        # Lots of cover
			cover_count = 10        # Cover throughout
			jump_pad_count = 6      # Jump pads everywhere
			teleporter_pair_count = 2
			tunnel_count = 2        # Underground network
			catwalk_count = 4       # Elevated network
		_:  # Default to medium
			complexity = 2
			configure_from_complexity()
			return

	# Sizes scale with arena
	corridor_width = 8.0 * size_factor
	wall_height = 25.0 * size_factor
	room_size = Vector3(16.0, 10.0, 16.0) * size_factor

	# Minimum spacing for interactive objects
	min_spacing = 6.0 * size_factor
	min_spacing = max(min_spacing, 4.0)

	if OS.is_debug_build():
		print("Q3 Level config - Complexity: %d, Arena: %.0f, Rooms: %d, JumpPads: %d, Catwalks: %d" % [
			complexity, arena_size, room_count, jump_pad_count, catwalk_count
		])

func generate_level() -> void:
	"""Generate a complete Quake 3 Arena-style level with deliberate architecture"""
	if OS.is_debug_build():
		print("Generating Quake 3 Arena-style level with seed: ", level_seed)

	# Configure based on complexity and size
	configure_from_complexity()

	# Initialize noise for minor variation
	noise = FastNoiseLite.new()
	noise.seed = level_seed if level_seed != 0 else randi()
	noise.frequency = 0.05

	# Clear any existing geometry
	clear_level()

	# Generate Q3-style architecture in a deliberate order:
	# 1. Main arena floor - central combat area
	generate_main_arena()

	# 2. Weapon platforms - distinct raised areas at cardinal directions
	generate_weapon_platforms()

	# 3. Sniper towers - elevated positions at corners
	generate_sniper_towers()

	# 4. Cover elements - pillars and blocks for combat flow
	generate_cover_elements()

	# 5. Catwalks - elevated walkways connecting areas
	generate_catwalks()

	# 6. Tunnels - underground passages (if complexity allows)
	if tunnel_count > 0:
		generate_tunnels()

	# 7. Jump pads - strategic vertical movement (placed after structures)
	generate_jump_pads()

	# 8. Teleporters - connect distant areas
	generate_teleporters()

	# 9. Perimeter walls - arena boundary
	generate_perimeter_walls()

	# 10. Death zone - respawn trigger below arena
	generate_death_zone()

	# Apply procedural materials
	apply_procedural_textures()

	print("Quake 3 Arena-style level generation complete!")

func clear_level() -> void:
	"""Remove all existing level geometry"""
	for child in get_children():
		child.queue_free()
	platforms.clear()
	teleporters.clear()
	geometry_positions.clear()

func check_interactive_object_spacing(new_pos: Vector3, radius: float) -> bool:
	"""Check if an interactive object (jump pad, teleporter) would clip through or be under geometry.
	Returns true if position is valid, false if it would clip or be blocked."""
	for existing in geometry_positions:
		var existing_pos: Vector3 = existing.position
		var existing_size: Vector3 = existing.size
		var existing_half_size: Vector3 = existing_size * 0.5

		# Check if horizontally within the geometry's footprint
		var dx: float = abs(new_pos.x - existing_pos.x)
		var dz: float = abs(new_pos.z - existing_pos.z)
		var margin: float = radius + 0.5

		var horizontally_overlapping: bool = (dx < existing_half_size.x + margin and
											   dz < existing_half_size.z + margin)

		if horizontally_overlapping:
			# Check vertical relationship
			var geometry_bottom: float = existing_pos.y - existing_half_size.y
			var geometry_top: float = existing_pos.y + existing_half_size.y

			# Reject if object is INSIDE the geometry
			if new_pos.y >= geometry_bottom - margin and new_pos.y <= geometry_top + margin:
				return false  # Would clip through geometry

			# Reject if object is UNDER a platform (platform is above us)
			# This prevents jump pads spawning under elevated platforms
			if new_pos.y < geometry_bottom and geometry_bottom < 20.0:  # Only check platforms below reasonable height
				return false  # Would be under a platform

	return true  # Valid position

func register_geometry(pos: Vector3, size: Vector3) -> void:
	"""Register solid geometry for interactive object collision checks"""
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
	var size_factor: float = arena_size / 140.0
	var floor_size: float = arena_size * 0.55

	# Main floor - octagonal feel with a central area
	var floor_mesh: BoxMesh = create_smooth_box_mesh(Vector3(floor_size, 2.0, floor_size))

	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.name = "MainArenaFloor"
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

	# Central raised platform (like quad damage area in Q3)
	var center_size: Vector3 = Vector3(10.0 * size_factor, 1.5 * size_factor, 10.0 * size_factor)
	var center_mesh: BoxMesh = create_smooth_box_mesh(center_size)
	var center_platform: MeshInstance3D = MeshInstance3D.new()
	center_platform.mesh = center_mesh
	center_platform.name = "CenterPlatform"
	center_platform.position = Vector3(0, center_size.y / 2.0, 0)
	add_child(center_platform)
	add_collision_to_mesh(center_platform, center_size)
	platforms.append(center_platform)
	register_geometry(center_platform.position, center_size)

	if OS.is_debug_build():
		print("Generated main arena floor: ", floor_size, "x", floor_size)

# ============================================================================
# WEAPON PLATFORMS (Q3 Style - at cardinal directions)
# ============================================================================

func generate_weapon_platforms() -> void:
	"""Generate raised weapon platforms at cardinal directions - like rocket/rail areas in Q3"""
	var size_factor: float = arena_size / 140.0
	var platform_distance: float = arena_size * 0.22

	# 4 weapon platforms at N, S, E, W
	var directions: Array[Vector3] = [
		Vector3(0, 0, 1),   # North
		Vector3(0, 0, -1),  # South
		Vector3(1, 0, 0),   # East
		Vector3(-1, 0, 0)   # West
	]

	for i in range(4):
		var dir: Vector3 = directions[i]
		var platform_height: float = (5.0 + (i % 2) * 2.0) * size_factor  # Alternating heights
		var platform_size: Vector3 = Vector3(12.0 * size_factor, 2.0 * size_factor, 12.0 * size_factor)
		var platform_pos: Vector3 = dir * platform_distance + Vector3(0, platform_height, 0)

		# Main platform
		var platform_mesh: BoxMesh = create_smooth_box_mesh(platform_size)
		var platform_instance: MeshInstance3D = MeshInstance3D.new()
		platform_instance.mesh = platform_mesh
		platform_instance.name = "WeaponPlatform" + str(i)
		platform_instance.position = platform_pos
		add_child(platform_instance)
		add_collision_to_mesh(platform_instance, platform_size)
		platforms.append(platform_instance)
		register_geometry(platform_pos, platform_size)

		# Access ramp from ground to platform
		create_platform_ramp(platform_pos, platform_size, -dir, i)

	if OS.is_debug_build():
		print("Generated 4 weapon platforms")

func create_platform_ramp(platform_pos: Vector3, platform_size: Vector3, direction: Vector3, index: int) -> void:
	"""Create an access ramp leading up to a weapon platform"""
	var size_factor: float = arena_size / 140.0
	var ramp_length: float = platform_pos.y * 2.0  # Gentle slope
	var ramp_width: float = 6.0 * size_factor
	var ramp_thickness: float = 1.0 * size_factor

	# Position ramp to connect ground to platform edge
	var ramp_start: Vector3 = platform_pos + direction * (platform_size.z / 2.0 + ramp_length / 2.0)
	ramp_start.y = platform_pos.y / 2.0

	var ramp_size: Vector3 = Vector3(ramp_width, ramp_thickness, ramp_length)
	var ramp_mesh: BoxMesh = create_smooth_box_mesh(ramp_size)

	var ramp_instance: MeshInstance3D = MeshInstance3D.new()
	ramp_instance.mesh = ramp_mesh
	ramp_instance.name = "PlatformRamp" + str(index)
	ramp_instance.position = ramp_start

	# Calculate slope angle and facing
	var slope_angle: float = atan2(platform_pos.y, ramp_length)
	var facing_angle: float = atan2(direction.x, direction.z)
	ramp_instance.rotation = Vector3(-slope_angle, facing_angle, 0)

	add_child(ramp_instance)
	add_collision_to_mesh(ramp_instance, ramp_size)
	platforms.append(ramp_instance)

# ============================================================================
# SNIPER TOWERS (Corner elevated positions)
# ============================================================================

func generate_sniper_towers() -> void:
	"""Generate elevated sniper/lookout positions at corners"""
	var size_factor: float = arena_size / 140.0
	var tower_distance: float = arena_size * 0.28

	# 4 towers at diagonal corners
	var corners: Array[Vector3] = [
		Vector3(1, 0, 1).normalized(),
		Vector3(1, 0, -1).normalized(),
		Vector3(-1, 0, 1).normalized(),
		Vector3(-1, 0, -1).normalized()
	]

	for i in range(4):
		var dir: Vector3 = corners[i]
		var tower_pos: Vector3 = dir * tower_distance

		# Tower base/pillar
		var pillar_height: float = 12.0 * size_factor
		var pillar_size: Vector3 = Vector3(4.0 * size_factor, pillar_height, 4.0 * size_factor)
		var pillar_pos: Vector3 = tower_pos + Vector3(0, pillar_height / 2.0, 0)

		var pillar_mesh: BoxMesh = create_smooth_box_mesh(pillar_size)
		var pillar_instance: MeshInstance3D = MeshInstance3D.new()
		pillar_instance.mesh = pillar_mesh
		pillar_instance.name = "TowerPillar" + str(i)
		pillar_instance.position = pillar_pos
		add_child(pillar_instance)
		add_collision_to_mesh(pillar_instance, pillar_size)
		platforms.append(pillar_instance)
		register_geometry(pillar_pos, pillar_size)

		# Tower platform on top
		var top_size: Vector3 = Vector3(8.0 * size_factor, 1.0 * size_factor, 8.0 * size_factor)
		var top_pos: Vector3 = tower_pos + Vector3(0, pillar_height + top_size.y / 2.0, 0)

		var top_mesh: BoxMesh = create_smooth_box_mesh(top_size)
		var top_instance: MeshInstance3D = MeshInstance3D.new()
		top_instance.mesh = top_mesh
		top_instance.name = "TowerTop" + str(i)
		top_instance.position = top_pos
		add_child(top_instance)
		add_collision_to_mesh(top_instance, top_size)
		platforms.append(top_instance)
		register_geometry(top_pos, top_size)

	if OS.is_debug_build():
		print("Generated 4 sniper towers")

# ============================================================================
# COVER ELEMENTS (Pillars and blocks for combat flow)
# ============================================================================

func generate_cover_elements() -> void:
	"""Generate cover pillars and blocks in strategic positions"""
	var size_factor: float = arena_size / 140.0

	# Inner ring of pillars around center
	var inner_distance: float = arena_size * 0.12
	for i in range(pillar_count):
		var angle: float = (float(i) / pillar_count) * TAU + PI / pillar_count  # Offset from platforms
		var pillar_height: float = 6.0 * size_factor
		var pillar_width: float = 2.5 * size_factor
		var pillar_size: Vector3 = Vector3(pillar_width, pillar_height, pillar_width)
		var pillar_pos: Vector3 = Vector3(
			cos(angle) * inner_distance,
			pillar_height / 2.0,
			sin(angle) * inner_distance
		)

		var pillar_mesh: BoxMesh = create_smooth_box_mesh(pillar_size)
		var pillar_instance: MeshInstance3D = MeshInstance3D.new()
		pillar_instance.mesh = pillar_mesh
		pillar_instance.name = "CoverPillar" + str(i)
		pillar_instance.position = pillar_pos
		add_child(pillar_instance)
		add_collision_to_mesh(pillar_instance, pillar_size)
		platforms.append(pillar_instance)
		register_geometry(pillar_pos, pillar_size)

	# Low cover blocks between weapon platforms
	var cover_distance: float = arena_size * 0.18
	for i in range(cover_count):
		var angle: float = (float(i) / cover_count) * TAU + PI / 4.0  # Offset 45 degrees
		var cover_size: Vector3 = Vector3(
			3.0 * size_factor,
			2.0 * size_factor,
			3.0 * size_factor
		)
		var cover_pos: Vector3 = Vector3(
			cos(angle) * cover_distance,
			cover_size.y / 2.0,
			sin(angle) * cover_distance
		)

		var cover_mesh: BoxMesh = create_smooth_box_mesh(cover_size)
		var cover_instance: MeshInstance3D = MeshInstance3D.new()
		cover_instance.mesh = cover_mesh
		cover_instance.name = "CoverBlock" + str(i)
		cover_instance.position = cover_pos
		add_child(cover_instance)
		add_collision_to_mesh(cover_instance, cover_size)
		platforms.append(cover_instance)
		register_geometry(cover_pos, cover_size)

	if OS.is_debug_build():
		print("Generated %d pillars and %d cover blocks" % [pillar_count, cover_count])

# ============================================================================
# CATWALKS (Elevated walkways connecting areas)
# ============================================================================

func generate_catwalks() -> void:
	"""Generate elevated catwalks connecting weapon platforms and towers"""
	if catwalk_count <= 0:
		return

	var size_factor: float = arena_size / 140.0
	var catwalk_height: float = 8.0 * size_factor  # Consistent height
	var catwalk_distance: float = arena_size * 0.22

	# Catwalks connect adjacent weapon platforms in a ring
	for i in range(min(catwalk_count, 4)):
		var angle_start: float = (float(i) / 4.0) * TAU
		var angle_end: float = (float(i + 1) / 4.0) * TAU

		var start_pos: Vector3 = Vector3(
			cos(angle_start) * catwalk_distance,
			catwalk_height,
			sin(angle_start) * catwalk_distance
		)
		var end_pos: Vector3 = Vector3(
			cos(angle_end) * catwalk_distance,
			catwalk_height,
			sin(angle_end) * catwalk_distance
		)

		create_catwalk_segment(start_pos, end_pos, i)

	if OS.is_debug_build():
		print("Generated %d catwalks" % catwalk_count)

func create_catwalk_segment(start_pos: Vector3, end_pos: Vector3, index: int) -> void:
	"""Create a single catwalk segment between two points"""
	var size_factor: float = arena_size / 140.0
	var direction: Vector3 = (end_pos - start_pos).normalized()
	var length: float = start_pos.distance_to(end_pos)
	var mid_point: Vector3 = (start_pos + end_pos) / 2.0

	var catwalk_width: float = 4.0 * size_factor
	var catwalk_thickness: float = 0.8 * size_factor
	var catwalk_size: Vector3 = Vector3(catwalk_width, catwalk_thickness, length)

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

	# Railings on sides (low walls for cover)
	create_catwalk_railing(mid_point, catwalk_size, direction, index)

func create_catwalk_railing(pos: Vector3, catwalk_size: Vector3, direction: Vector3, index: int) -> void:
	"""Create low railings on catwalk for cover"""
	var size_factor: float = arena_size / 140.0
	var railing_height: float = 1.5 * size_factor
	var railing_thickness: float = 0.3 * size_factor

	# Right side perpendicular to direction
	var right: Vector3 = direction.cross(Vector3.UP).normalized()

	for side in [-1, 1]:
		var railing_size: Vector3 = Vector3(railing_thickness, railing_height, catwalk_size.z * 0.9)
		var railing_pos: Vector3 = pos + right * side * (catwalk_size.x / 2.0 - railing_thickness) + Vector3(0, railing_height / 2.0 + catwalk_size.y / 2.0, 0)

		var railing_mesh: BoxMesh = create_smooth_box_mesh(railing_size)
		var railing_instance: MeshInstance3D = MeshInstance3D.new()
		railing_instance.mesh = railing_mesh
		railing_instance.name = "CatwalkRailing" + str(index) + "_" + str(side)
		railing_instance.position = railing_pos
		railing_instance.rotation.y = atan2(direction.x, direction.z)
		add_child(railing_instance)
		add_collision_to_mesh(railing_instance, railing_size)
		platforms.append(railing_instance)

# ============================================================================
# TUNNELS (Underground passages)
# ============================================================================

func generate_tunnels() -> void:
	"""Generate underground tunnel passages - simple cross pattern"""
	if tunnel_count <= 0:
		return

	var size_factor: float = arena_size / 140.0
	var tunnel_half_dist: float = arena_size * 0.30

	# Create tunnels in a simple cross pattern (not random)
	for i in range(min(tunnel_count, 2)):
		var angle: float = float(i) * PI / 2.0  # 0 and 90 degrees
		var start_pos: Vector3 = Vector3(cos(angle) * tunnel_half_dist, -4.0 * size_factor, sin(angle) * tunnel_half_dist)
		var end_pos: Vector3 = Vector3(-cos(angle) * tunnel_half_dist, -4.0 * size_factor, -sin(angle) * tunnel_half_dist)

		create_tunnel(start_pos, end_pos, i)

	if OS.is_debug_build():
		print("Generated %d tunnels" % tunnel_count)

func create_tunnel(start_pos: Vector3, end_pos: Vector3, index: int) -> void:
	"""Create a simple underground tunnel with entrance ramps at each end"""
	var size_factor: float = arena_size / 140.0
	var direction: Vector3 = (end_pos - start_pos).normalized()
	var length: float = start_pos.distance_to(end_pos)
	var mid_point: Vector3 = (start_pos + end_pos) / 2.0

	var tunnel_width: float = 8.0 * size_factor
	var tunnel_thickness: float = 1.0 * size_factor

	# Main tunnel floor
	var floor_size: Vector3 = Vector3(tunnel_width, tunnel_thickness, length)
	var floor_mesh: BoxMesh = create_smooth_box_mesh(floor_size)
	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.name = "TunnelFloor" + str(index)
	floor_instance.position = mid_point
	floor_instance.rotation.y = atan2(direction.x, direction.z)
	add_child(floor_instance)
	add_collision_to_mesh(floor_instance, floor_size)
	platforms.append(floor_instance)

	# Entrance ramps at each end
	create_tunnel_entrance(start_pos, direction, index, "Start", size_factor)
	create_tunnel_entrance(end_pos, -direction, index, "End", size_factor)

func create_tunnel_entrance(pos: Vector3, dir: Vector3, index: int, suffix: String, size_factor: float) -> void:
	"""Create a sloped entrance ramp into a tunnel"""
	var ramp_length: float = abs(pos.y) * 2.5  # Length based on depth
	var ramp_width: float = 8.0 * size_factor

	# Position ramp to connect surface to tunnel depth
	var ramp_center_height: float = pos.y / 2.0
	var ramp_pos: Vector3 = pos + dir * (ramp_length * 0.5)
	ramp_pos.y = ramp_center_height

	var ramp_size: Vector3 = Vector3(ramp_width, 1.0 * size_factor, ramp_length)
	var ramp_mesh: BoxMesh = create_smooth_box_mesh(ramp_size)
	var ramp_instance: MeshInstance3D = MeshInstance3D.new()
	ramp_instance.mesh = ramp_mesh
	ramp_instance.name = "TunnelRamp" + str(index) + suffix
	ramp_instance.position = ramp_pos

	# Calculate slope angle and facing
	var slope_angle: float = atan2(abs(pos.y), ramp_length)
	var angle_y: float = atan2(dir.x, dir.z)
	ramp_instance.rotation = Vector3(slope_angle, angle_y, 0)  # Slope down

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
# JUMP PADS (Strategic placement for vertical movement)
# ============================================================================

func generate_jump_pads() -> void:
	"""Generate jump pads at strategic locations for vertical movement"""
	var size_factor: float = arena_size / 140.0
	var jump_pad_positions: Array[Vector3] = []

	# Strategic positions based on arena layout:
	# 1. Near sniper tower bases (to get up quickly)
	var tower_distance: float = arena_size * 0.28
	var tower_corners: Array[Vector3] = [
		Vector3(1, 0, 1).normalized() * tower_distance,
		Vector3(1, 0, -1).normalized() * tower_distance,
		Vector3(-1, 0, 1).normalized() * tower_distance,
		Vector3(-1, 0, -1).normalized() * tower_distance
	]

	# Add jump pads near towers (offset slightly toward center)
	for i in range(min(jump_pad_count, 4)):
		var tower_pos: Vector3 = tower_corners[i]
		var pad_pos: Vector3 = tower_pos * 0.7  # Closer to center than tower
		jump_pad_positions.append(pad_pos)

	# Add center jump pad if we have room for more
	if jump_pad_count > 4:
		jump_pad_positions.append(Vector3(0, 0, 0))

	# Add jump pads between weapon platforms if complexity allows
	if jump_pad_count > 5:
		var platform_distance: float = arena_size * 0.18
		for i in range(min(jump_pad_count - 5, 4)):
			var angle: float = (float(i) / 4.0) * TAU + PI / 4.0  # Offset 45 degrees from platforms
			var pos: Vector3 = Vector3(cos(angle) * platform_distance, 0, sin(angle) * platform_distance)
			jump_pad_positions.append(pos)

	# Create the jump pads
	var created_count: int = 0
	for i in range(jump_pad_positions.size()):
		if create_jump_pad(jump_pad_positions[i], i):
			created_count += 1

	if OS.is_debug_build():
		print("Generated %d jump pads" % created_count)

func create_jump_pad(pos: Vector3, index: int) -> bool:
	"""Create a jump pad (visual platform + Area3D for boost). Returns true if created."""
	var size_factor: float = arena_size / 140.0
	var pad_radius: float = 2.0 * size_factor

	# Check that jump pad won't clip through or be under geometry
	if not check_interactive_object_spacing(Vector3(pos.x, 0.25, pos.z), pad_radius):
		return false  # Skip this jump pad if it would clip

	# Visual platform
	var pad_mesh: CylinderMesh = CylinderMesh.new()
	pad_mesh.top_radius = pad_radius
	pad_mesh.bottom_radius = pad_radius
	pad_mesh.height = 0.5 * size_factor

	var pad_instance: MeshInstance3D = MeshInstance3D.new()
	pad_instance.mesh = pad_mesh
	pad_instance.name = "JumpPad" + str(index)
	pad_instance.position = Vector3(pos.x, 0.25 * size_factor, pos.z)
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
	collision_shape.radius = pad_radius
	collision_shape.height = 0.5 * size_factor
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
	area_shape.radius = pad_radius
	area_shape.height = 3.0  # Taller to catch jumping players
	area_collision.shape = area_shape
	jump_area.add_child(area_collision)

	# Don't add to platforms array - jump pads need to keep their custom material
	return true

# ============================================================================
# TELEPORTERS
# ============================================================================

func generate_teleporters() -> void:
	"""Generate teleporter pairs connecting opposite sides of the arena"""
	var size_factor: float = arena_size / 140.0

	# Strategic teleporter placement: connect opposite weapon platforms
	# This allows quick traversal across the arena
	var teleporter_pairs: Array[Dictionary] = []

	# Place teleporters near the edge, between structures
	var teleporter_distance: float = arena_size * 0.35  # Near perimeter

	for i in range(teleporter_pair_count):
		# Offset angle to avoid placing on top of weapon platforms (which are at cardinal directions)
		var angle: float = (float(i) / teleporter_pair_count) * PI + PI / 4.0  # Start at 45 degrees
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

	if OS.is_debug_build():
		print("Generated %d teleporter pairs" % teleporter_pairs.size())

func create_teleporter_pair(from_pos: Vector3, to_pos: Vector3, pair_index: int) -> void:
	"""Create a bidirectional teleporter pair"""
	create_teleporter(from_pos, to_pos, pair_index * 2)
	create_teleporter(to_pos, from_pos, pair_index * 2 + 1)

func create_teleporter(pos: Vector3, destination: Vector3, index: int) -> void:
	"""Create a single teleporter"""
	var size_factor: float = arena_size / 140.0
	var teleporter_radius: float = 2.0 * size_factor  # Smaller to avoid clipping

	# Check that teleporter won't clip through or be under geometry
	if not check_interactive_object_spacing(Vector3(pos.x, 0.15, pos.z), teleporter_radius):
		return  # Skip this teleporter if it would clip

	# Visual platform
	var teleporter_mesh: CylinderMesh = CylinderMesh.new()
	teleporter_mesh.top_radius = teleporter_radius
	teleporter_mesh.bottom_radius = teleporter_radius
	teleporter_mesh.height = 0.3 * size_factor

	var teleporter_instance: MeshInstance3D = MeshInstance3D.new()
	teleporter_instance.mesh = teleporter_mesh
	teleporter_instance.name = "Teleporter" + str(index)
	teleporter_instance.position = Vector3(pos.x, 0.15 * size_factor, pos.z)
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
	collision_shape.radius = teleporter_radius
	collision_shape.height = 0.3 * size_factor
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
	area_shape.radius = teleporter_radius
	area_shape.height = 5.0 * size_factor  # Tall enough to catch players reliably
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
