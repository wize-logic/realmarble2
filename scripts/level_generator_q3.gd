extends Node3D

## Quake 3 Arena-Style Level Generator (Type B)
## Creates multi-tiered arenas with complex geometry, rooms, corridors, and vertical gameplay

@export var level_seed: int = 0
@export var arena_size: float = 140.0

var noise: FastNoiseLite
var platforms: Array = []
var teleporters: Array = []  # For potential teleporter pairs

func _ready() -> void:
	generate_level()

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
	generate_jump_pads()
	generate_teleporters()
	generate_perimeter_walls()
	generate_death_zone()

	print("Quake 3 Arena-style level generation complete!")

func clear_level() -> void:
	"""Remove all existing level geometry"""
	for child in get_children():
		child.queue_free()
	platforms.clear()
	teleporters.clear()

# ============================================================================
# MAIN ARENA
# ============================================================================

func generate_main_arena() -> void:
	"""Generate the main ground floor arena - central combat area"""
	var floor_size: float = arena_size * 0.6

	# Main floor
	var floor_mesh: BoxMesh = BoxMesh.new()
	floor_mesh.size = Vector3(floor_size, 2.0, floor_size)

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
	var pillar_positions: Array = [
		Vector3(20, 0, 20),
		Vector3(-20, 0, 20),
		Vector3(20, 0, -20),
		Vector3(-20, 0, -20),
	]

	for i in range(pillar_positions.size()):
		var pos: Vector3 = pillar_positions[i]

		# Create tall pillar
		var pillar_mesh: BoxMesh = BoxMesh.new()
		pillar_mesh.size = Vector3(4.0, 12.0, 4.0)

		var pillar_instance: MeshInstance3D = MeshInstance3D.new()
		pillar_instance.mesh = pillar_mesh
		pillar_instance.name = "Pillar" + str(i)
		pillar_instance.position = Vector3(pos.x, 6.0, pos.z)
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
	var cover_count: int = 8

	for i in range(cover_count):
		var angle: float = (float(i) / cover_count) * TAU
		var distance: float = 15.0 + randf() * 10.0

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance

		# Create cover box
		var cover_mesh: BoxMesh = BoxMesh.new()
		cover_mesh.size = Vector3(3.0 + randf() * 2.0, 2.0 + randf() * 1.0, 3.0 + randf() * 2.0)

		var cover_instance: MeshInstance3D = MeshInstance3D.new()
		cover_instance.mesh = cover_mesh
		cover_instance.name = "Cover" + str(i)
		cover_instance.position = Vector3(x, cover_mesh.size.y / 2.0, z)
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

	# Tier 1: Mid-level ring platforms (4 large platforms)
	generate_tier_platforms(1, 4, 8.0, 25.0)

	# Tier 2: Upper-level platforms (8 smaller platforms)
	generate_tier_platforms(2, 8, 15.0, 20.0)

	# Tier 3: Highest sniper platforms (4 small platforms)
	generate_tier_platforms(3, 4, 22.0, 15.0)

	print("Generated multi-tier platform system")

func generate_tier_platforms(tier: int, count: int, height: float, distance_from_center: float) -> void:
	"""Generate a ring of platforms at a specific tier level"""

	for i in range(count):
		var angle: float = (float(i) / count) * TAU
		var x: float = cos(angle) * distance_from_center
		var z: float = sin(angle) * distance_from_center

		# Platform size varies by tier (higher = smaller)
		var platform_size: Vector3
		match tier:
			1:  # Large mid-level platforms
				platform_size = Vector3(12.0, 1.5, 12.0)
			2:  # Medium upper platforms
				platform_size = Vector3(8.0, 1.5, 8.0)
			3:  # Small sniper platforms
				platform_size = Vector3(6.0, 1.5, 6.0)
			_:
				platform_size = Vector3(8.0, 1.5, 8.0)

		# Create platform
		var platform_mesh: BoxMesh = BoxMesh.new()
		platform_mesh.size = platform_size

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

		# Add connecting ramps to some platforms
		if tier == 1 and i % 2 == 0:  # Every other platform on tier 1
			generate_ramp_to_platform(Vector3(x, height, z), platform_size)

func generate_ramp_to_platform(platform_pos: Vector3, platform_size: Vector3) -> void:
	"""Generate a ramp leading up to a platform"""

	# Calculate ramp position (extend from platform toward center)
	var direction_to_center: Vector3 = -platform_pos.normalized()
	var ramp_offset: float = platform_size.z / 2.0 + 6.0  # Extend from platform edge
	var ramp_base: Vector3 = platform_pos + direction_to_center * ramp_offset
	ramp_base.y = 0.0  # Start at ground level

	# Create ramp
	var ramp_mesh: BoxMesh = BoxMesh.new()
	ramp_mesh.size = Vector3(8.0, 0.5, 14.0)

	var ramp_instance: MeshInstance3D = MeshInstance3D.new()
	ramp_instance.mesh = ramp_mesh
	ramp_instance.name = "RampTo" + str(platform_pos)

	# Position at midpoint between ground and platform
	var ramp_height: float = platform_pos.y / 2.0
	ramp_instance.position = Vector3(ramp_base.x, ramp_height, ramp_base.z)

	# Rotate ramp to face center and tilt
	var angle_to_center: float = atan2(-direction_to_center.x, -direction_to_center.z)
	ramp_instance.rotation = Vector3(-0.4, angle_to_center, 0)  # Tilted slope

	add_child(ramp_instance)

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
	var room_positions: Array = [
		Vector3(45, 0, 0),    # East room
		Vector3(-45, 0, 0),   # West room
		Vector3(0, 0, 45),    # North room
		Vector3(0, 0, -45),   # South room
	]

	for i in range(room_positions.size()):
		var room_pos: Vector3 = room_positions[i]
		generate_room(room_pos, i)

	print("Generated 4 side rooms")

func generate_room(center_pos: Vector3, room_index: int) -> void:
	"""Generate a single enclosed room with openings"""
	var room_size: Vector3 = Vector3(16.0, 10.0, 16.0)
	var wall_thickness: float = 1.0

	# Floor
	var floor_mesh: BoxMesh = BoxMesh.new()
	floor_mesh.size = Vector3(room_size.x, 1.0, room_size.z)

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

	# Ceiling
	var ceiling_mesh: BoxMesh = BoxMesh.new()
	ceiling_mesh.size = Vector3(room_size.x, 1.0, room_size.z)

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
	var wall_mesh: BoxMesh = BoxMesh.new()
	wall_mesh.size = size

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
	var platform_mesh: BoxMesh = BoxMesh.new()
	platform_mesh.size = Vector3(6.0, 1.0, 6.0)

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
	var corridor_configs: Array = [
		{"start": Vector3(30, 0, 0), "end": Vector3(45, 0, 0), "width": 6.0},  # To east room
		{"start": Vector3(-30, 0, 0), "end": Vector3(-45, 0, 0), "width": 6.0},  # To west room
		{"start": Vector3(0, 0, 30), "end": Vector3(0, 0, 45), "width": 6.0},  # To north room
		{"start": Vector3(0, 0, -30), "end": Vector3(0, 0, -45), "width": 6.0},  # To south room
	]

	for config in corridor_configs:
		create_corridor(config.start, config.end, config.width)

	print("Generated connecting corridors")

func create_corridor(start_pos: Vector3, end_pos: Vector3, width: float) -> void:
	"""Create a corridor between two points"""
	var direction: Vector3 = (end_pos - start_pos).normalized()
	var length: float = start_pos.distance_to(end_pos)
	var mid_point: Vector3 = (start_pos + end_pos) / 2.0

	# Floor
	var corridor_mesh: BoxMesh = BoxMesh.new()
	corridor_mesh.size = Vector3(width if abs(direction.x) > 0.5 else length, 1.0, width if abs(direction.z) > 0.5 else length)

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
# JUMP PADS
# ============================================================================

func generate_jump_pads() -> void:
	"""Generate jump pads for quick vertical movement"""
	var jump_pad_positions: Array = [
		Vector3(0, 0, 0),      # Center jump pad to upper levels
		Vector3(30, 0, 30),
		Vector3(-30, 0, 30),
		Vector3(30, 0, -30),
		Vector3(-30, 0, -30),
	]

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

	# Material for jump pad (bright color to stand out)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 1.0, 0.3)  # Bright green
	material.emission_enabled = true
	material.emission = Color(0.2, 1.0, 0.3)
	material.emission_energy = 0.5
	pad_instance.material_override = material

	# Area3D for jump boost detection
	var jump_area: Area3D = Area3D.new()
	jump_area.name = "JumpPadArea"
	jump_area.position = Vector3.ZERO
	jump_area.add_to_group("jump_pad")
	pad_instance.add_child(jump_area)

	var area_collision: CollisionShape3D = CollisionShape3D.new()
	var area_shape: CylinderShape3D = CylinderShape3D.new()
	area_shape.radius = 2.5
	area_shape.height = 1.0
	area_collision.shape = area_shape
	jump_area.add_child(area_collision)

	# Connect signal for jump boost (players will need to handle this)
	jump_area.body_entered.connect(_on_jump_pad_entered.bind(index))

	platforms.append(pad_instance)

func _on_jump_pad_entered(body: Node3D, pad_index: int) -> void:
	"""Handle player entering jump pad"""
	if body is RigidBody3D and body.has_method("apply_jump_pad_boost"):
		# Apply strong upward boost
		var boost_force: Vector3 = Vector3.UP * 80.0
		body.apply_central_impulse(boost_force)
		print("Jump pad ", pad_index, " activated for ", body.name)

# ============================================================================
# TELEPORTERS
# ============================================================================

func generate_teleporters() -> void:
	"""Generate teleporter pairs for quick arena traversal"""
	var teleporter_pairs: Array = [
		{"from": Vector3(35, 0, 35), "to": Vector3(-35, 0, -35)},
		{"from": Vector3(-35, 0, 35), "to": Vector3(35, 0, -35)},
	]

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

	# Material for teleporter (glowing blue/purple)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.3, 1.0)  # Blue
	material.emission_enabled = true
	material.emission = Color(0.5, 0.3, 1.0)  # Purple glow
	material.emission_energy = 1.0
	teleporter_instance.material_override = material

	# Area3D for teleportation
	var teleport_area: Area3D = Area3D.new()
	teleport_area.name = "TeleportArea"
	teleport_area.position = Vector3.ZERO
	teleport_area.add_to_group("teleporter")
	teleport_area.set_meta("destination", destination)
	teleporter_instance.add_child(teleport_area)

	var area_collision: CollisionShape3D = CollisionShape3D.new()
	var area_shape: CylinderShape3D = CylinderShape3D.new()
	area_shape.radius = 3.0
	area_shape.height = 3.0  # Tall enough to catch players
	area_collision.shape = area_shape
	teleport_area.add_child(area_collision)

	# Connect signal
	teleport_area.body_entered.connect(_on_teleporter_entered)

	platforms.append(teleporter_instance)
	teleporters.append({"area": teleport_area, "destination": destination})

func _on_teleporter_entered(body: Node3D) -> void:
	"""Handle player entering teleporter"""
	if body is RigidBody3D:
		var teleport_area: Area3D = body.get_parent() if body.get_parent() is Area3D else null
		if teleport_area and teleport_area.has_meta("destination"):
			var destination: Vector3 = teleport_area.get_meta("destination")
			# Teleport player (add slight height offset to ensure they're above ground)
			body.global_position = destination + Vector3(0, 2, 0)
			# Reset velocity to prevent momentum issues
			if body.has_method("set_linear_velocity"):
				body.set_linear_velocity(Vector3.ZERO)
			print("Teleported ", body.name, " to ", destination)

# ============================================================================
# PERIMETER WALLS
# ============================================================================

func generate_perimeter_walls() -> void:
	"""Generate outer perimeter walls"""
	var wall_distance: float = arena_size * 0.55
	var wall_height: float = 25.0  # Taller walls for Q3 style
	var wall_thickness: float = 2.0

	var wall_configs: Array = [
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

	print("Generated death zone")

func _on_death_zone_entered(body: Node3D) -> void:
	"""Handle player falling into death zone"""
	print("Death zone entered by: %s (type: %s)" % [body.name, body.get_class()])
	if body.has_method("fall_death"):
		print("Calling fall_death() on %s" % body.name)
		body.fall_death()
	elif body.has_method("respawn"):
		print("Calling respawn() directly on %s" % body.name)
		body.respawn()
	else:
		print("WARNING: %s has neither fall_death() nor respawn() method!" % body.name)

# ============================================================================
# SPAWN POINTS
# ============================================================================

func get_spawn_points() -> PackedVector3Array:
	"""Generate spawn points throughout the arena - supports up to 16 players"""
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
	for platform in platforms:
		if platform is MeshInstance3D:
			var material: StandardMaterial3D = StandardMaterial3D.new()

			# Color scheme based on platform type
			var base_color: Color
			if platform.name.contains("Jump"):
				base_color = Color(0.2, 1.0, 0.3)  # Green for jump pads
			elif platform.name.contains("Teleporter"):
				base_color = Color(0.3, 0.3, 1.0)  # Blue for teleporters
			else:
				# Random industrial colors
				base_color = Color(
					randf_range(0.3, 0.7),
					randf_range(0.3, 0.7),
					randf_range(0.3, 0.7)
				)

			material.albedo_color = base_color
			material.metallic = 0.3
			material.roughness = 0.7
			material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

			platform.material_override = material

	print("Applied procedural materials to ", platforms.size(), " objects")
