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
	"""Generate spawn points on platforms"""
	var spawns: PackedVector3Array = PackedVector3Array()

	# Main floor spawns
	spawns.append(Vector3(0, 2, 0))
	spawns.append(Vector3(10, 2, 0))
	spawns.append(Vector3(-10, 2, 0))
	spawns.append(Vector3(0, 2, 10))
	spawns.append(Vector3(0, 2, -10))

	# Platform spawns
	for platform in platforms:
		if platform.name.begins_with("Platform"):
			var spawn_pos: Vector3 = platform.position
			spawn_pos.y += 3.0  # Above platform
			spawns.append(spawn_pos)

	return spawns
