extends Node3D

## Spawns collectible orbs at random 3D locations in the map volume

const OrbScene = preload("res://collectible_orb.tscn")

# Map volume bounds for random spawning
@export var spawn_bounds_min: Vector3 = Vector3(-40, 6, -40)  # Min X, Y, Z (doubled Y from 3)
@export var spawn_bounds_max: Vector3 = Vector3(40, 60, 40)   # Max X, Y, Z (doubled Y from 30)
@export var num_orbs: int = 9  # Number of orbs to spawn

# Respawn settings
@export var respawn_interval: float = 10.0  # Respawn every 10 seconds
@export var respawn_at_random_location: bool = true

var spawned_orbs: Array[Area3D] = []
var respawn_timer: float = 0.0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	# Initialize RNG with unique seed
	rng.randomize()
	# Only spawn on server (authoritative)
	if multiplayer.is_server() or multiplayer.multiplayer_peer == null:
		call_deferred("spawn_orbs")

func _process(delta: float) -> void:
	# Server-side respawn timer
	if not (multiplayer.is_server() or multiplayer.multiplayer_peer == null):
		return

	respawn_timer += delta
	if respawn_timer >= respawn_interval:
		respawn_timer = 0.0
		check_and_respawn_orbs()

func spawn_orbs() -> void:
	"""Spawn orbs at random 3D positions in the map volume"""
	print("=== ORB SPAWNER: Starting to spawn orbs ===")
	print("Spawn bounds: min=%s, max=%s" % [spawn_bounds_min, spawn_bounds_max])

	for i in range(num_orbs):
		var random_pos: Vector3 = get_random_spawn_position()
		print("Orb %d spawning at position: %s" % [i+1, random_pos])
		spawn_orb_at_position(random_pos)

	print("=== ORB SPAWNER: Spawned %d orbs in 3D map volume ===" % spawned_orbs.size())

func get_random_spawn_position() -> Vector3:
	"""Generate a random position within the spawn bounds"""
	return Vector3(
		rng.randf_range(spawn_bounds_min.x, spawn_bounds_max.x),
		rng.randf_range(spawn_bounds_min.y, spawn_bounds_max.y),
		rng.randf_range(spawn_bounds_min.z, spawn_bounds_max.z)
	)

func spawn_orb_at_position(pos: Vector3) -> void:
	"""Spawn a single orb at the given position"""
	var orb: Area3D = OrbScene.instantiate()
	add_child(orb)
	orb.global_position = pos
	spawned_orbs.append(orb)
	# Note: Orbs have built-in bob animation, no need for velocity

func check_and_respawn_orbs() -> void:
	"""Check collected orbs and respawn them at random locations"""
	if not respawn_at_random_location:
		return

	for orb in spawned_orbs:
		if orb and orb.get("is_collected") == true:
			# Move orb to new random location
			orb.global_position = get_random_spawn_position()
			print("Moved collected orb to new random location: ", orb.global_position)
