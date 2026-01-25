extends Node3D

## Quake 3 Arena-Style Level Generator (Type B)
## Creates architectural arenas with structures, ledges, and vertical combat spaces
## All dimensions SCALE with arena_size

# ============================================================================
# EXPORTED PARAMETERS
# ============================================================================

@export var level_seed: int = 0
@export var arena_size: float = 140.0  # Base arena size - THIS CONTROLS ACTUAL SIZE
@export var complexity: int = 2  # 1=Low, 2=Medium, 3=High, 4=Extreme

var noise: FastNoiseLite
var platforms: Array = []
var teleporters: Array = []
var clear_positions: Array[Vector3] = []  # Known clear spots for interactive objects
var material_manager = preload("res://scripts/procedural_material_manager.gd").new()

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	generate_level()

func generate_level() -> void:
	"""Generate a complete Quake 3 Arena-style level"""
	print("=== Q3 ARENA LEVEL CONFIG ===")
	print("Arena Size: %.1f (floor will be %.1f x %.1f)" % [arena_size, arena_size * 0.6, arena_size * 0.6])
	print("Complexity: %d" % complexity)

	noise = FastNoiseLite.new()
	noise.seed = level_seed if level_seed != 0 else randi()
	noise.frequency = 0.05

	clear_level()

	# Build the arena architecture
	generate_main_arena()
	generate_central_structure()
	generate_corner_towers()
	generate_side_alcoves()
	generate_upper_ring()
	generate_bridges()

	# Place interactive objects in KNOWN clear locations
	generate_jump_pads()
	generate_teleporters()

	generate_perimeter_walls()
	generate_death_zone()

	apply_procedural_textures()
	print("Q3 Arena level generation complete! Floor size: %.1f" % (arena_size * 0.6))

func clear_level() -> void:
	for child in get_children():
		child.queue_free()
	platforms.clear()
	teleporters.clear()
	clear_positions.clear()

func create_smooth_box_mesh(size: Vector3) -> BoxMesh:
	var mesh = BoxMesh.new()
	mesh.size = size
	mesh.subdivide_width = 2
	mesh.subdivide_height = 2
	mesh.subdivide_depth = 2
	return mesh

func add_platform_with_collision(pos: Vector3, size: Vector3, name_prefix: String) -> MeshInstance3D:
	"""Helper to create a platform with collision"""
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

# ============================================================================
# MAIN ARENA FLOOR
# ============================================================================

func generate_main_arena() -> void:
	"""Generate the main ground floor - SIZE SCALES WITH arena_size"""
	var floor_size: float = arena_size * 0.6

	print("Creating main arena floor: %.1f x %.1f" % [floor_size, floor_size])

	add_platform_with_collision(
		Vector3(0, -1, 0),
		Vector3(floor_size, 2.0, floor_size),
		"MainArenaFloor"
	)

	# Register center as a clear position for jump pads
	clear_positions.append(Vector3(0, 0, 0))

# ============================================================================
# CENTRAL STRUCTURE - The iconic Q3 center piece
# ============================================================================

func generate_central_structure() -> void:
	"""Generate a central raised platform structure"""
	var scale: float = arena_size / 140.0

	# Central platform (raised area in the middle)
	var center_size: float = 12.0 * scale
	var center_height: float = 3.0 * scale

	add_platform_with_collision(
		Vector3(0, center_height / 2.0, 0),
		Vector3(center_size, center_height, center_size),
		"CentralPlatform"
	)

	# Slopes leading up to center (one on each side)
	var slope_length: float = 8.0 * scale
	var slope_width: float = 6.0 * scale
	var slope_offset: float = center_size / 2.0 + slope_length / 2.0 - 1.0

	var slope_positions = [
		{"pos": Vector3(slope_offset, center_height / 2.0, 0), "rot": Vector3(0, 90, -20)},
		{"pos": Vector3(-slope_offset, center_height / 2.0, 0), "rot": Vector3(0, -90, -20)},
		{"pos": Vector3(0, center_height / 2.0, slope_offset), "rot": Vector3(-20, 0, 0)},
		{"pos": Vector3(0, center_height / 2.0, -slope_offset), "rot": Vector3(20, 180, 0)},
	]

	for i in range(slope_positions.size()):
		var sp = slope_positions[i]
		var slope_mesh: BoxMesh = create_smooth_box_mesh(Vector3(slope_width, 0.5, slope_length))
		var slope_instance: MeshInstance3D = MeshInstance3D.new()
		slope_instance.mesh = slope_mesh
		slope_instance.name = "CenterSlope" + str(i)
		slope_instance.position = sp.pos
		slope_instance.rotation_degrees = sp.rot
		add_child(slope_instance)

		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = slope_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		slope_instance.add_child(static_body)
		platforms.append(slope_instance)

	# Register top of central platform as clear for items
	clear_positions.append(Vector3(0, center_height + 1.0, 0))

# ============================================================================
# CORNER TOWERS - Vertical elements at each corner
# ============================================================================

func generate_corner_towers() -> void:
	"""Generate tower structures at each corner"""
	var scale: float = arena_size / 140.0
	var floor_extent: float = (arena_size * 0.6) / 2.0 - 5.0 * scale

	var tower_width: float = 8.0 * scale
	var tower_heights = [
		6.0 * scale,   # Base tier
		12.0 * scale,  # Mid tier (complexity 2+)
		18.0 * scale   # Top tier (complexity 3+)
	]

	var corners = [
		Vector3(floor_extent, 0, floor_extent),
		Vector3(-floor_extent, 0, floor_extent),
		Vector3(floor_extent, 0, -floor_extent),
		Vector3(-floor_extent, 0, -floor_extent)
	]

	for i in range(corners.size()):
		var corner: Vector3 = corners[i]

		# Base platform (always)
		var base_height: float = tower_heights[0]
		add_platform_with_collision(
			Vector3(corner.x, base_height / 2.0, corner.z),
			Vector3(tower_width, base_height, tower_width),
			"Tower" + str(i) + "Base"
		)

		# Register top of base as clear position
		clear_positions.append(Vector3(corner.x, base_height + 1.0, corner.z))

		# Slope to base
		var slope_dir: Vector3 = -corner.normalized()
		var slope_pos: Vector3 = corner + slope_dir * (tower_width / 2.0 + 4.0 * scale)
		slope_pos.y = base_height / 2.0

		var slope_mesh: BoxMesh = create_smooth_box_mesh(Vector3(5.0 * scale, 0.5, 10.0 * scale))
		var slope_instance: MeshInstance3D = MeshInstance3D.new()
		slope_instance.mesh = slope_mesh
		slope_instance.name = "Tower" + str(i) + "Slope"
		slope_instance.position = slope_pos
		slope_instance.rotation.y = atan2(slope_dir.x, slope_dir.z)
		slope_instance.rotation_degrees.x = -25
		add_child(slope_instance)

		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = slope_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		slope_instance.add_child(static_body)
		platforms.append(slope_instance)

		# Mid tier ledge (complexity 2+)
		if complexity >= 2:
			var mid_height: float = tower_heights[1]
			var ledge_size: float = tower_width * 0.7
			add_platform_with_collision(
				Vector3(corner.x, mid_height, corner.z),
				Vector3(ledge_size, 1.0, ledge_size),
				"Tower" + str(i) + "MidLedge"
			)
			clear_positions.append(Vector3(corner.x, mid_height + 1.5, corner.z))

		# Top sniper ledge (complexity 3+)
		if complexity >= 3:
			var top_height: float = tower_heights[2]
			var top_size: float = tower_width * 0.5
			add_platform_with_collision(
				Vector3(corner.x, top_height, corner.z),
				Vector3(top_size, 1.0, top_size),
				"Tower" + str(i) + "TopLedge"
			)
			clear_positions.append(Vector3(corner.x, top_height + 1.5, corner.z))

# ============================================================================
# SIDE ALCOVES - Recessed areas along the walls
# ============================================================================

func generate_side_alcoves() -> void:
	"""Generate alcove structures on each side"""
	var scale: float = arena_size / 140.0
	var floor_extent: float = (arena_size * 0.6) / 2.0

	var alcove_depth: float = 8.0 * scale
	var alcove_width: float = 16.0 * scale
	var alcove_height: float = 4.0 * scale

	var sides = [
		{"pos": Vector3(floor_extent + alcove_depth / 2.0, 0, 0), "rot": 0},
		{"pos": Vector3(-floor_extent - alcove_depth / 2.0, 0, 0), "rot": 0},
		{"pos": Vector3(0, 0, floor_extent + alcove_depth / 2.0), "rot": 0},
		{"pos": Vector3(0, 0, -floor_extent - alcove_depth / 2.0), "rot": 0}
	]

	for i in range(sides.size()):
		var side = sides[i]

		# Alcove floor (extends past main floor)
		add_platform_with_collision(
			Vector3(side.pos.x, -0.5, side.pos.z),
			Vector3(alcove_depth if abs(side.pos.x) > 0.1 else alcove_width,
					1.0,
					alcove_width if abs(side.pos.x) > 0.1 else alcove_depth),
			"Alcove" + str(i) + "Floor"
		)

		# Raised platform in alcove
		add_platform_with_collision(
			Vector3(side.pos.x, alcove_height / 2.0, side.pos.z),
			Vector3(6.0 * scale, alcove_height, 6.0 * scale),
			"Alcove" + str(i) + "Platform"
		)

		# Register alcove platform top as clear
		clear_positions.append(Vector3(side.pos.x, alcove_height + 1.0, side.pos.z))

		# Side walls for alcove (complexity 2+)
		if complexity >= 2:
			var wall_height: float = 8.0 * scale
			var wall_offset: float = alcove_width / 2.0 - 0.5

			if abs(side.pos.x) > 0.1:
				# X-axis alcove - walls on Z sides
				add_platform_with_collision(
					Vector3(side.pos.x, wall_height / 2.0, side.pos.z + wall_offset),
					Vector3(alcove_depth, wall_height, 1.0),
					"Alcove" + str(i) + "WallA"
				)
				add_platform_with_collision(
					Vector3(side.pos.x, wall_height / 2.0, side.pos.z - wall_offset),
					Vector3(alcove_depth, wall_height, 1.0),
					"Alcove" + str(i) + "WallB"
				)
			else:
				# Z-axis alcove - walls on X sides
				add_platform_with_collision(
					Vector3(side.pos.x + wall_offset, wall_height / 2.0, side.pos.z),
					Vector3(1.0, wall_height, alcove_depth),
					"Alcove" + str(i) + "WallA"
				)
				add_platform_with_collision(
					Vector3(side.pos.x - wall_offset, wall_height / 2.0, side.pos.z),
					Vector3(1.0, wall_height, alcove_depth),
					"Alcove" + str(i) + "WallB"
				)

# ============================================================================
# UPPER RING - Elevated walkway around perimeter
# ============================================================================

func generate_upper_ring() -> void:
	"""Generate an upper walkway ring"""
	var scale: float = arena_size / 140.0
	var floor_extent: float = (arena_size * 0.6) / 2.0

	var ring_height: float = 8.0 * scale
	var ring_width: float = 4.0 * scale
	var ring_inset: float = 3.0 * scale

	# Four sides of the ring
	var ring_length: float = arena_size * 0.6 - ring_inset * 2

	# North
	add_platform_with_collision(
		Vector3(0, ring_height, floor_extent - ring_inset),
		Vector3(ring_length, 1.0, ring_width),
		"UpperRingNorth"
	)
	# South
	add_platform_with_collision(
		Vector3(0, ring_height, -floor_extent + ring_inset),
		Vector3(ring_length, 1.0, ring_width),
		"UpperRingSouth"
	)
	# East
	add_platform_with_collision(
		Vector3(floor_extent - ring_inset, ring_height, 0),
		Vector3(ring_width, 1.0, ring_length),
		"UpperRingEast"
	)
	# West
	add_platform_with_collision(
		Vector3(-floor_extent + ring_inset, ring_height, 0),
		Vector3(ring_width, 1.0, ring_length),
		"UpperRingWest"
	)

	# Register ring positions as clear
	clear_positions.append(Vector3(0, ring_height + 1.0, floor_extent - ring_inset))
	clear_positions.append(Vector3(0, ring_height + 1.0, -floor_extent + ring_inset))
	clear_positions.append(Vector3(floor_extent - ring_inset, ring_height + 1.0, 0))
	clear_positions.append(Vector3(-floor_extent + ring_inset, ring_height + 1.0, 0))

# ============================================================================
# BRIDGES - Connect structures (complexity 2+)
# ============================================================================

func generate_bridges() -> void:
	"""Generate bridges connecting structures"""
	if complexity < 2:
		return

	var scale: float = arena_size / 140.0
	var floor_extent: float = (arena_size * 0.6) / 2.0 - 5.0 * scale

	var bridge_width: float = 3.0 * scale
	var bridge_height: float = 6.0 * scale

	# Diagonal bridges from corners toward center (at tower base height)
	var corners = [
		Vector3(floor_extent, bridge_height, floor_extent),
		Vector3(-floor_extent, bridge_height, floor_extent),
		Vector3(floor_extent, bridge_height, -floor_extent),
		Vector3(-floor_extent, bridge_height, -floor_extent)
	]

	for i in range(corners.size()):
		var corner: Vector3 = corners[i]
		var to_center: Vector3 = -corner.normalized()
		var bridge_length: float = floor_extent * 0.5

		var bridge_center: Vector3 = corner + to_center * (bridge_length / 2.0 + 4.0 * scale)
		bridge_center.y = bridge_height

		var bridge_mesh: BoxMesh = create_smooth_box_mesh(Vector3(bridge_width, 0.5, bridge_length))
		var bridge_instance: MeshInstance3D = MeshInstance3D.new()
		bridge_instance.mesh = bridge_mesh
		bridge_instance.name = "Bridge" + str(i)
		bridge_instance.position = bridge_center
		bridge_instance.rotation.y = atan2(to_center.x, to_center.z)
		add_child(bridge_instance)

		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = bridge_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		bridge_instance.add_child(static_body)
		platforms.append(bridge_instance)

	# Cross bridges at higher level (complexity 3+)
	if complexity >= 3:
		var high_bridge_height: float = 12.0 * scale

		# N-S bridge
		add_platform_with_collision(
			Vector3(0, high_bridge_height, 0),
			Vector3(bridge_width, 0.5, floor_extent * 1.2),
			"HighBridgeNS"
		)
		# E-W bridge
		add_platform_with_collision(
			Vector3(0, high_bridge_height + 0.5, 0),  # Slightly higher to cross over
			Vector3(floor_extent * 1.2, 0.5, bridge_width),
			"HighBridgeEW"
		)

# ============================================================================
# JUMP PADS - Placed in KNOWN clear locations
# ============================================================================

func generate_jump_pads() -> void:
	"""Generate jump pads in pre-determined clear locations"""
	var scale: float = arena_size / 140.0

	# Strategic jump pad locations (on ground, in clear areas)
	var jump_pad_spots = [
		Vector3(0, 0, 0),  # Center
	]

	# Add spots at cardinal directions
	var floor_extent: float = (arena_size * 0.6) / 2.0 * 0.6
	jump_pad_spots.append(Vector3(floor_extent, 0, 0))
	jump_pad_spots.append(Vector3(-floor_extent, 0, 0))
	jump_pad_spots.append(Vector3(0, 0, floor_extent))
	jump_pad_spots.append(Vector3(0, 0, -floor_extent))

	# Add more spots for higher complexity
	if complexity >= 3:
		var diag_dist: float = floor_extent * 0.7
		jump_pad_spots.append(Vector3(diag_dist, 0, diag_dist))
		jump_pad_spots.append(Vector3(-diag_dist, 0, diag_dist))
		jump_pad_spots.append(Vector3(diag_dist, 0, -diag_dist))
		jump_pad_spots.append(Vector3(-diag_dist, 0, -diag_dist))

	for i in range(jump_pad_spots.size()):
		create_jump_pad(jump_pad_spots[i], i, scale)

	print("Generated %d jump pads" % jump_pad_spots.size())

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
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
# TELEPORTERS - Placed in alcoves and clear spots
# ============================================================================

func generate_teleporters() -> void:
	"""Generate teleporter pairs in known clear locations"""
	var scale: float = arena_size / 140.0
	var floor_extent: float = (arena_size * 0.6) / 2.0

	# Teleporters in the side alcoves (opposite pairs)
	var alcove_offset: float = floor_extent + 4.0 * scale

	# Pair 1: East <-> West alcoves
	create_teleporter(Vector3(alcove_offset, 0, 0), Vector3(-alcove_offset, 0, 0), 0, scale)
	create_teleporter(Vector3(-alcove_offset, 0, 0), Vector3(alcove_offset, 0, 0), 1, scale)

	# Pair 2: North <-> South alcoves (complexity 2+)
	if complexity >= 2:
		create_teleporter(Vector3(0, 0, alcove_offset), Vector3(0, 0, -alcove_offset), 2, scale)
		create_teleporter(Vector3(0, 0, -alcove_offset), Vector3(0, 0, alcove_offset), 3, scale)

	print("Generated %d teleporters" % (2 if complexity < 2 else 4))

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
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
# PERIMETER WALLS
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

	# Use the pre-calculated clear positions
	for pos in clear_positions:
		spawns.append(pos)

	# Add some ground spawns
	var floor_radius: float = (arena_size * 0.6) / 2.0 * 0.5
	spawns.append(Vector3(0, 2, 0))
	spawns.append(Vector3(floor_radius, 2, 0))
	spawns.append(Vector3(-floor_radius, 2, 0))
	spawns.append(Vector3(0, 2, floor_radius))
	spawns.append(Vector3(0, 2, -floor_radius))

	return spawns
