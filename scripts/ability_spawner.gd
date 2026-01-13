extends Node3D

## Spawns ability pickups at random 3D locations in the map volume
## These grant Kirby-style abilities to players

const AbilityPickupScene = preload("res://ability_pickup.tscn")
const DashAttackScene = preload("res://abilities/dash_attack.tscn")
const ExplosionScene = preload("res://abilities/explosion.tscn")
const GunScene = preload("res://abilities/gun.tscn")

# Map volume bounds for random spawning
@export var spawn_bounds_min: Vector3 = Vector3(-50, 10, -50)  # Min X, Y, Z
@export var spawn_bounds_max: Vector3 = Vector3(50, 100, 50)   # Max X, Y, Z

# Number of each ability type to spawn
@export var num_dash_attacks: int = 2
@export var num_explosions: int = 2
@export var num_guns: int = 3

# Respawn settings
@export var respawn_interval: float = 10.0  # Check respawn every 10 seconds
@export var respawn_at_random_location: bool = true

var spawned_pickups: Array[Area3D] = []
var respawn_timer: float = 0.0

func _ready() -> void:
	# Only spawn on server (authoritative)
	if multiplayer.is_server() or multiplayer.multiplayer_peer == null:
		call_deferred("spawn_abilities")

func _process(delta: float) -> void:
	# Server-side respawn timer
	if not (multiplayer.is_server() or multiplayer.multiplayer_peer == null):
		return

	respawn_timer += delta
	if respawn_timer >= respawn_interval:
		respawn_timer = 0.0
		check_and_respawn_pickups()

func spawn_abilities() -> void:
	"""Spawn ability pickups at random 3D positions in the map volume"""
	# Spawn dash attacks
	for i in range(num_dash_attacks):
		var pos: Vector3 = get_random_spawn_position()
		spawn_ability_at(pos, DashAttackScene, "Dash Attack", Color.ORANGE_RED)

	# Spawn explosions
	for i in range(num_explosions):
		var pos: Vector3 = get_random_spawn_position()
		spawn_ability_at(pos, ExplosionScene, "Explosion", Color.ORANGE)

	# Spawn guns
	for i in range(num_guns):
		var pos: Vector3 = get_random_spawn_position()
		spawn_ability_at(pos, GunScene, "Gun", Color.CYAN)

	print("Spawned %d ability pickups in 3D map volume (Y: %.1f to %.1f)" % [spawned_pickups.size(), spawn_bounds_min.y, spawn_bounds_max.y])

func get_random_spawn_position() -> Vector3:
	"""Generate a random position within the spawn bounds"""
	return Vector3(
		randf_range(spawn_bounds_min.x, spawn_bounds_max.x),
		randf_range(spawn_bounds_min.y, spawn_bounds_max.y),
		randf_range(spawn_bounds_min.z, spawn_bounds_max.z)
	)

func spawn_ability_at(pos: Vector3, ability_scene: PackedScene, ability_name: String, ability_color: Color) -> void:
	"""Spawn an ability pickup at the given position"""
	var pickup: Area3D = AbilityPickupScene.instantiate()
	pickup.ability_scene = ability_scene
	pickup.ability_name = ability_name
	pickup.ability_color = ability_color
	add_child(pickup)
	pickup.global_position = pos
	spawned_pickups.append(pickup)

func check_and_respawn_pickups() -> void:
	"""Check collected pickups and respawn them at random locations"""
	if not respawn_at_random_location:
		return

	for pickup in spawned_pickups:
		if pickup and pickup.get("is_collected") == true:
			# Move pickup to new random location
			pickup.global_position = get_random_spawn_position()
			print("Moved collected pickup to new random location: ", pickup.global_position)

func spawn_random_ability(pos: Vector3) -> void:
	"""Spawn a random ability at the given position (for debug menu)"""
	var ability_types: Array = [
		[DashAttackScene, "Dash Attack", Color.ORANGE_RED],
		[ExplosionScene, "Explosion", Color.ORANGE],
		[GunScene, "Gun", Color.CYAN]
	]

	var random_ability: Array = ability_types[randi() % ability_types.size()]
	spawn_ability_at(pos, random_ability[0], random_ability[1], random_ability[2])
