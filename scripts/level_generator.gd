extends Node3D

## Procedural Level Generator
## Creates Marble Blast Gold / Quake 3 style arenas

@export var level_seed: int = 0
@export var arena_size: float = 120.0
@export var platform_count: int = 24
@export var ramp_count: int = 12

var noise: FastNoiseLite
var platforms: Array = []

func _ready() -> void:
	generate_level()

func generate_level() -> void:
	"""Generate a complete procedural level"""
	print("Generating procedural level with seed: ", level_seed)

	# Initialize noise for variation
	noise = FastNoiseLite.new()
	noise.seed = level_seed if level_seed != 0 else randi()
	noise.frequency = 0.05

	# Clear any existing geometry
	clear_level()

	# Generate level components
	generate_main_floor()
	generate_platforms()
	generate_ramps()
	generate_walls()
	generate_grind_rails()
	generate_death_zone()

	print("Level generation complete!")

func clear_level() -> void:
	"""Remove all existing level geometry"""
	for child in get_children():
		child.queue_free()
	platforms.clear()

func generate_main_floor() -> void:
	"""Generate the main arena floor"""
	var floor_size: float = arena_size * 0.7

	# Create main platform
	var floor_mesh: BoxMesh = BoxMesh.new()
	floor_mesh.size = Vector3(floor_size, 2.0, floor_size)

	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.name = "MainFloor"
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

	# Store for texture application
	platforms.append(floor_instance)

	print("Generated main floor: ", floor_size, "x", floor_size)

func generate_platforms() -> void:
	"""Generate elevated platforms around the arena"""
	var radius: float = arena_size * 0.4

	for i in range(platform_count):
		var angle: float = (float(i) / platform_count) * TAU
		var distance: float = radius * (0.6 + randf() * 0.4)

		# Position around circle with noise variation
		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance
		var y: float = 3.0 + randf() * 8.0  # Random heights

		# Random platform size
		var width: float = 6.0 + randf() * 6.0
		var depth: float = 6.0 + randf() * 6.0
		var height: float = 1.0 + randf() * 1.0

		# Create platform
		var platform_mesh: BoxMesh = BoxMesh.new()
		platform_mesh.size = Vector3(width, height, depth)

		var platform_instance: MeshInstance3D = MeshInstance3D.new()
		platform_instance.mesh = platform_mesh
		platform_instance.name = "Platform" + str(i)
		platform_instance.position = Vector3(x, y, z)
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

	print("Generated ", platform_count, " platforms")

func generate_ramps() -> void:
	"""Generate ramps connecting different levels"""
	for i in range(ramp_count):
		var angle: float = (float(i) / ramp_count) * TAU + (TAU / ramp_count * 0.5)
		var distance: float = arena_size * 0.3

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance
		var y: float = 0.0

		# Create ramp
		var ramp_mesh: BoxMesh = BoxMesh.new()
		ramp_mesh.size = Vector3(8.0, 0.5, 12.0)

		var ramp_instance: MeshInstance3D = MeshInstance3D.new()
		ramp_instance.mesh = ramp_mesh
		ramp_instance.name = "Ramp" + str(i)
		ramp_instance.position = Vector3(x, y + 3, z)
		ramp_instance.rotation_degrees = Vector3(-25, rad_to_deg(angle), 0)  # Sloped
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

	print("Generated ", ramp_count, " ramps")

func generate_walls() -> void:
	"""Generate perimeter walls"""
	var wall_distance: float = arena_size * 0.55
	var wall_height: float = 15.0
	var wall_thickness: float = 2.0

	# Four walls
	var wall_configs: Array = [
		{"pos": Vector3(0, wall_height/2, wall_distance), "size": Vector3(arena_size, wall_height, wall_thickness)},
		{"pos": Vector3(0, wall_height/2, -wall_distance), "size": Vector3(arena_size, wall_height, wall_thickness)},
		{"pos": Vector3(wall_distance, wall_height/2, 0), "size": Vector3(wall_thickness, wall_height, arena_size)},
		{"pos": Vector3(-wall_distance, wall_height/2, 0), "size": Vector3(wall_thickness, wall_height, arena_size)}
	]

	for i in range(wall_configs.size()):
		var config: Dictionary = wall_configs[i]

		var wall_mesh: BoxMesh = BoxMesh.new()
		wall_mesh.size = config.size

		var wall_instance: MeshInstance3D = MeshInstance3D.new()
		wall_instance.mesh = wall_mesh
		wall_instance.name = "Wall" + str(i)
		wall_instance.position = config.pos
		add_child(wall_instance)

		# Add collision
		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = wall_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		wall_instance.add_child(static_body)

		platforms.append(wall_instance)

	print("Generated perimeter walls")

func generate_grind_rails() -> void:
	"""Generate grinding rails around the arena perimeter (Sonic style)"""
	var rail_count: int = 8  # Number of rails around the arena
	# Position between platforms (max 0.4) and walls (0.55)
	var rail_distance: float = arena_size * 0.47  # ~56 units at default size

	for i in range(rail_count):
		var angle_start: float = (float(i) / rail_count) * TAU
		var angle_end: float = angle_start + (TAU / rail_count) * 0.7  # Rails cover 70% of arc segment

		# Create a curved rail using Path3D and Curve3D
		var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
		rail.name = "GrindRail" + str(i)
		rail.curve = Curve3D.new()

		# Determine rail height (varied for interest, accessible heights)
		var base_height: float = 3.0 + (i % 3) * 2.5  # Heights: 3, 5.5, 8, repeating

		# Create curve points along the arc
		var num_points: int = 12  # Number of control points
		for j in range(num_points):
			var t: float = float(j) / (num_points - 1)
			var angle: float = lerp(angle_start, angle_end, t)

			# Position along arc
			var x: float = cos(angle) * rail_distance
			var z: float = sin(angle) * rail_distance

			# Height variation (slight wave for interest)
			var height_offset: float = sin(t * PI) * 1.0  # Slight arc up and down
			var y: float = base_height + height_offset

			# Add point to curve
			rail.curve.add_point(Vector3(x, y, z))

		# Calculate proper tangent handles based on curve direction
		for j in range(rail.curve.point_count):
			var tangent: Vector3

			if j == 0:
				# First point - use direction to next point
				tangent = (rail.curve.get_point_position(j + 1) - rail.curve.get_point_position(j)).normalized()
			elif j == rail.curve.point_count - 1:
				# Last point - use direction from previous point
				tangent = (rail.curve.get_point_position(j) - rail.curve.get_point_position(j - 1)).normalized()
			else:
				# Middle points - use average direction from previous to next
				var prev_to_curr: Vector3 = rail.curve.get_point_position(j) - rail.curve.get_point_position(j - 1)
				var curr_to_next: Vector3 = rail.curve.get_point_position(j + 1) - rail.curve.get_point_position(j)
				tangent = (prev_to_curr + curr_to_next).normalized()

			# Set in/out handles based on actual curve direction (scaled for smoothness)
			var handle_length: float = 0.5  # Adjust for curve smoothness
			rail.curve.set_point_in(j, -tangent * handle_length)
			rail.curve.set_point_out(j, tangent * handle_length)

		add_child(rail)

		# Create visual rail mesh (cylinder along the path)
		create_rail_visual(rail)

	# Add some vertical connecting rails (like loops)
	generate_vertical_rails()

	print("Generated ", rail_count, " grind rails around perimeter")

func generate_vertical_rails() -> void:
	"""Generate vertical/diagonal rails connecting different heights"""
	var vertical_rail_count: int = 4

	for i in range(vertical_rail_count):
		var angle: float = (float(i) / vertical_rail_count) * TAU + (TAU / vertical_rail_count * 0.5)
		var distance: float = arena_size * 0.47  # Same as horizontal rails

		# Create vertical rail
		var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
		rail.name = "VerticalRail" + str(i)
		rail.curve = Curve3D.new()

		# Start position (low and accessible)
		var start_x: float = cos(angle) * distance
		var start_z: float = sin(angle) * distance
		var start_y: float = 2.0  # Low starting height

		# End position (moderate height)
		var end_y: float = 10.0

		# Create upward spiral
		var num_points: int = 8
		for j in range(num_points):
			var t: float = float(j) / (num_points - 1)
			var current_angle: float = angle + t * PI * 0.5  # Quarter turn
			var current_distance: float = lerp(distance, distance * 0.85, t)  # Curve inward slightly

			var x: float = cos(current_angle) * current_distance
			var z: float = sin(current_angle) * current_distance
			var y: float = lerp(start_y, end_y, t)

			rail.curve.add_point(Vector3(x, y, z))

		# Calculate proper tangent handles based on curve direction
		for j in range(rail.curve.point_count):
			var tangent: Vector3

			if j == 0:
				# First point - use direction to next point
				tangent = (rail.curve.get_point_position(j + 1) - rail.curve.get_point_position(j)).normalized()
			elif j == rail.curve.point_count - 1:
				# Last point - use direction from previous point
				tangent = (rail.curve.get_point_position(j) - rail.curve.get_point_position(j - 1)).normalized()
			else:
				# Middle points - use average direction from previous to next
				var prev_to_curr: Vector3 = rail.curve.get_point_position(j) - rail.curve.get_point_position(j - 1)
				var curr_to_next: Vector3 = rail.curve.get_point_position(j + 1) - rail.curve.get_point_position(j)
				tangent = (prev_to_curr + curr_to_next).normalized()

			# Set in/out handles based on actual curve direction (scaled for smoothness)
			var handle_length: float = 0.5  # Adjust for curve smoothness
			rail.curve.set_point_in(j, -tangent * handle_length)
			rail.curve.set_point_out(j, tangent * handle_length)

		add_child(rail)
		create_rail_visual(rail)

	print("Generated ", vertical_rail_count, " vertical rails")

func create_rail_visual(rail: Path3D) -> void:
	"""Create visual representation of a rail using a 3D cylindrical tube"""
	if not rail.curve or rail.curve.get_baked_length() == 0:
		return

	# Create mesh for the rail
	var rail_visual: MeshInstance3D = MeshInstance3D.new()
	rail_visual.name = "RailVisual"

	# Use ImmediateMesh to draw the rail
	var immediate_mesh: ImmediateMesh = ImmediateMesh.new()
	rail_visual.mesh = immediate_mesh

	# Material for the rail
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.8, 0.9)  # Metallic silver
	material.metallic = 0.9
	material.roughness = 0.2
	material.emission_enabled = true
	material.emission = Color(0.3, 0.5, 1.0)  # Slight blue glow
	material.emission_energy_multiplier = 0.1

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)

	# Draw rail as a proper 3D cylindrical tube
	var rail_radius: float = 0.15
	var radial_segments: int = 8  # Number of sides around the cylinder
	var length_segments: int = int(rail.curve.get_baked_length() * 2)
	length_segments = max(length_segments, 10)

	# Generate vertices around the rail path
	for i in range(length_segments):
		var offset: float = (float(i) / length_segments) * rail.curve.get_baked_length()
		var next_offset: float = (float(i + 1) / length_segments) * rail.curve.get_baked_length()

		var pos: Vector3 = rail.curve.sample_baked(offset)
		var next_pos: Vector3 = rail.curve.sample_baked(next_offset)

		# Calculate forward direction
		var forward: Vector3 = (next_pos - pos).normalized()
		if forward.length() < 0.1:
			forward = Vector3.FORWARD

		# Calculate right and up vectors
		var right: Vector3 = forward.cross(Vector3.UP).normalized()
		if right.length() < 0.1:
			right = forward.cross(Vector3.RIGHT).normalized()
		var up: Vector3 = right.cross(forward).normalized()

		# Create ring of vertices at this position
		for j in range(radial_segments):
			var angle_curr: float = (float(j) / radial_segments) * TAU
			var angle_next: float = (float(j + 1) / radial_segments) * TAU

			# Current ring vertices
			var offset_curr: Vector3 = (right * cos(angle_curr) + up * sin(angle_curr)) * rail_radius
			var offset_next: Vector3 = (right * cos(angle_next) + up * sin(angle_next)) * rail_radius

			var v1: Vector3 = pos + offset_curr
			var v2: Vector3 = pos + offset_next
			var v3: Vector3 = next_pos + offset_curr
			var v4: Vector3 = next_pos + offset_next

			# First triangle
			immediate_mesh.surface_add_vertex(v1)
			immediate_mesh.surface_add_vertex(v2)
			immediate_mesh.surface_add_vertex(v3)

			# Second triangle
			immediate_mesh.surface_add_vertex(v2)
			immediate_mesh.surface_add_vertex(v4)
			immediate_mesh.surface_add_vertex(v3)

	immediate_mesh.surface_end()

	rail.add_child(rail_visual)

func generate_death_zone() -> void:
	"""Generate death zone below the arena"""
	var death_zone: Area3D = Area3D.new()
	death_zone.name = "DeathZone"
	death_zone.position = Vector3(0, -50, 0)
	death_zone.collision_layer = 0  # Death zone is on no layers
	death_zone.collision_mask = 2   # Detect players on layer 2
	death_zone.add_to_group("death_zone")
	add_child(death_zone)

	# Large collision box below everything
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(arena_size * 2, 10, arena_size * 2)
	collision.shape = shape
	death_zone.add_child(collision)

	# Connect signal
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

func apply_procedural_textures() -> void:
	"""Apply procedurally generated textures to all platforms"""
	for platform in platforms:
		if platform is MeshInstance3D:
			var material: StandardMaterial3D = StandardMaterial3D.new()

			# Random color scheme - use solid colors to avoid texture flashing
			var base_color: Color = Color(
				randf_range(0.4, 0.9),
				randf_range(0.4, 0.9),
				randf_range(0.4, 0.9)
			)

			material.albedo_color = base_color
			material.metallic = 0.2
			material.roughness = 0.8
			material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

			platform.material_override = material

	print("Applied procedural materials to ", platforms.size(), " objects")

func get_spawn_points() -> PackedVector3Array:
	"""Generate spawn points on platforms - supports up to 16 players"""
	var spawns: PackedVector3Array = PackedVector3Array()

	# Main floor spawns - 16 guaranteed spawns in a circular pattern
	spawns.append(Vector3(0, 2, 0))  # Center
	# Ring 1 - 4 spawns
	spawns.append(Vector3(10, 2, 0))
	spawns.append(Vector3(-10, 2, 0))
	spawns.append(Vector3(0, 2, 10))
	spawns.append(Vector3(0, 2, -10))
	# Ring 2 - 4 spawns (diagonals)
	spawns.append(Vector3(10, 2, 10))
	spawns.append(Vector3(-10, 2, 10))
	spawns.append(Vector3(10, 2, -10))
	spawns.append(Vector3(-10, 2, -10))
	# Ring 3 - 4 spawns (further out)
	spawns.append(Vector3(20, 2, 0))
	spawns.append(Vector3(-20, 2, 0))
	spawns.append(Vector3(0, 2, 20))
	spawns.append(Vector3(0, 2, -20))
	# Ring 4 - 3 spawns (additional positions)
	spawns.append(Vector3(15, 2, 15))
	spawns.append(Vector3(-15, 2, -15))
	spawns.append(Vector3(15, 2, -15))

	# Platform spawns - additional variety
	for platform in platforms:
		if platform.name.begins_with("Platform"):
			var spawn_pos: Vector3 = platform.position
			spawn_pos.y += 3.0  # Above platform
			spawns.append(spawn_pos)

	return spawns

# ============================================================================
# MID-ROUND EXPANSION SYSTEM
# ============================================================================

func generate_secondary_map(offset: Vector3) -> void:
	"""Generate a secondary map at the specified offset position"""
	print("Generating secondary map at offset: ", offset)

	# Store current seed to generate varied but consistent secondary map
	var secondary_seed: int = noise.seed + 1000  # Different but deterministic
	var old_seed: int = noise.seed
	noise.seed = secondary_seed

	# Generate a complete secondary arena at the offset
	generate_secondary_floor(offset)
	generate_secondary_platforms(offset)
	generate_secondary_ramps(offset)
	generate_secondary_walls(offset)
	generate_secondary_rails(offset)

	# Restore original seed
	noise.seed = old_seed

	print("Secondary map generation complete at offset: ", offset)

func generate_secondary_floor(offset: Vector3) -> void:
	"""Generate floor for secondary map"""
	var floor_size: float = arena_size * 0.7

	var floor_mesh: BoxMesh = BoxMesh.new()
	floor_mesh.size = Vector3(floor_size, 2.0, floor_size)

	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.name = "SecondaryFloor"
	floor_instance.position = offset + Vector3(0, -1, 0)
	add_child(floor_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = floor_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	floor_instance.add_child(static_body)

	platforms.append(floor_instance)

func generate_secondary_platforms(offset: Vector3) -> void:
	"""Generate platforms for secondary map"""
	var radius: float = arena_size * 0.4

	for i in range(platform_count):
		var angle: float = (float(i) / platform_count) * TAU
		var distance: float = radius * (0.6 + randf() * 0.4)

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance
		var y: float = 3.0 + randf() * 8.0

		var width: float = 6.0 + randf() * 6.0
		var depth: float = 6.0 + randf() * 6.0
		var height: float = 1.0 + randf() * 1.0

		var platform_mesh: BoxMesh = BoxMesh.new()
		platform_mesh.size = Vector3(width, height, depth)

		var platform_instance: MeshInstance3D = MeshInstance3D.new()
		platform_instance.mesh = platform_mesh
		platform_instance.name = "SecondaryPlatform" + str(i)
		platform_instance.position = offset + Vector3(x, y, z)
		add_child(platform_instance)

		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = platform_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		platform_instance.add_child(static_body)

		platforms.append(platform_instance)

func generate_secondary_ramps(offset: Vector3) -> void:
	"""Generate ramps for secondary map"""
	for i in range(ramp_count):
		var angle: float = (float(i) / ramp_count) * TAU + (TAU / ramp_count * 0.5)
		var distance: float = arena_size * 0.3

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance
		var y: float = 0.0

		var ramp_mesh: BoxMesh = BoxMesh.new()
		ramp_mesh.size = Vector3(8.0, 0.5, 12.0)

		var ramp_instance: MeshInstance3D = MeshInstance3D.new()
		ramp_instance.mesh = ramp_mesh
		ramp_instance.name = "SecondaryRamp" + str(i)
		ramp_instance.position = offset + Vector3(x, y + 3, z)
		ramp_instance.rotation_degrees = Vector3(-25, rad_to_deg(angle), 0)
		add_child(ramp_instance)

		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = ramp_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		ramp_instance.add_child(static_body)

		platforms.append(ramp_instance)

func generate_secondary_walls(offset: Vector3) -> void:
	"""Generate walls for secondary map"""
	var wall_distance: float = arena_size * 0.55
	var wall_height: float = 15.0
	var wall_thickness: float = 2.0

	var wall_configs: Array = [
		{"pos": Vector3(0, wall_height/2, wall_distance), "size": Vector3(arena_size, wall_height, wall_thickness)},
		{"pos": Vector3(0, wall_height/2, -wall_distance), "size": Vector3(arena_size, wall_height, wall_thickness)},
		{"pos": Vector3(wall_distance, wall_height/2, 0), "size": Vector3(wall_thickness, wall_height, arena_size)},
		{"pos": Vector3(-wall_distance, wall_height/2, 0), "size": Vector3(wall_thickness, wall_height, arena_size)}
	]

	for i in range(wall_configs.size()):
		var config: Dictionary = wall_configs[i]

		var wall_mesh: BoxMesh = BoxMesh.new()
		wall_mesh.size = config.size

		var wall_instance: MeshInstance3D = MeshInstance3D.new()
		wall_instance.mesh = wall_mesh
		wall_instance.name = "SecondaryWall" + str(i)
		wall_instance.position = offset + config.pos
		add_child(wall_instance)

		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = wall_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		wall_instance.add_child(static_body)

		platforms.append(wall_instance)

func generate_secondary_rails(offset: Vector3) -> void:
	"""Generate rails for secondary map"""
	var rail_count: int = 8
	var rail_distance: float = arena_size * 0.47

	for i in range(rail_count):
		var angle_start: float = (float(i) / rail_count) * TAU
		var angle_end: float = angle_start + (TAU / rail_count) * 0.7

		var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
		rail.name = "SecondaryGrindRail" + str(i)
		rail.curve = Curve3D.new()

		var base_height: float = 3.0 + (i % 3) * 2.5

		var num_points: int = 12
		for j in range(num_points):
			var t: float = float(j) / (num_points - 1)
			var angle: float = lerp(angle_start, angle_end, t)

			var x: float = cos(angle) * rail_distance
			var z: float = sin(angle) * rail_distance
			var height_offset: float = sin(t * PI) * 1.0
			var y: float = base_height + height_offset

			rail.curve.add_point(offset + Vector3(x, y, z))

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

		add_child(rail)
		create_rail_visual(rail)

func generate_connecting_rail(start_pos: Vector3, end_pos: Vector3) -> void:
	"""Generate a long connecting rail between two map areas"""
	print("Generating connecting rail from ", start_pos, " to ", end_pos)

	var rail: Path3D = preload("res://scripts/grind_rail.gd").new()
	rail.name = "ConnectingRail"
	rail.curve = Curve3D.new()

	# Calculate distance and create enough points for a smooth path
	var distance: float = start_pos.distance_to(end_pos)
	var num_points: int = max(20, int(distance / 15.0))  # At least 20 points, more for longer rails

	# Create a gentle curve from start to end
	for i in range(num_points):
		var t: float = float(i) / (num_points - 1)

		# Interpolate between start and end positions
		var pos: Vector3 = start_pos.lerp(end_pos, t)

		# Add a slight upward arc for visual interest (parabolic arc)
		var arc_height: float = 15.0  # Maximum height of the arc
		var height_offset: float = sin(t * PI) * arc_height
		pos.y += height_offset

		rail.curve.add_point(pos)

	# Set smooth tangent handles
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

		var handle_length: float = distance / float(num_points) * 0.5
		rail.curve.set_point_in(j, -tangent * handle_length)
		rail.curve.set_point_out(j, tangent * handle_length)

	add_child(rail)
	create_rail_visual(rail)

	print("Connecting rail created with ", num_points, " points")
