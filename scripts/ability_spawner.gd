extends Node3D

## Spawns ability pickups at predefined locations in the map
## These grant Kirby-style abilities to players

const AbilityPickupScene = preload("res://ability_pickup.tscn")
const DashAttackScene = preload("res://abilities/dash_attack.tscn")
const ExplosionScene = preload("res://abilities/explosion.tscn")
const GunScene = preload("res://abilities/gun.tscn")

# Ability spawn locations (strategic points on the map)
@export var dash_positions: PackedVector3Array = [
	Vector3(5, 6.0, 8),
	Vector3(-5, 6.0, 8),
]

@export var explosion_positions: PackedVector3Array = [
	Vector3(8, 6.0, -5),
	Vector3(-8, 6.0, -5),
]

@export var gun_positions: PackedVector3Array = [
	Vector3(0, 6.0, 10),
	Vector3(10, 6.0, 0),
	Vector3(-10, 6.0, 0),
]

var spawned_pickups: Array[Area3D] = []

func _ready() -> void:
	# Spawn abilities at all positions
	call_deferred("spawn_abilities")

func spawn_abilities() -> void:
	"""Spawn ability pickups at all predefined positions"""
	# Spawn dash attacks
	for pos in dash_positions:
		spawn_ability_at(pos, DashAttackScene, "Dash Attack", Color.ORANGE_RED)

	# Spawn explosions
	for pos in explosion_positions:
		spawn_ability_at(pos, ExplosionScene, "Explosion", Color.ORANGE)

	# Spawn guns
	for pos in gun_positions:
		spawn_ability_at(pos, GunScene, "Gun", Color.CYAN)

	print("Spawned %d ability pickups in the map" % spawned_pickups.size())

func spawn_ability_at(pos: Vector3, ability_scene: PackedScene, ability_name: String, ability_color: Color) -> void:
	"""Spawn an ability pickup at the given position"""
	var pickup: Area3D = AbilityPickupScene.instantiate()
	pickup.ability_scene = ability_scene
	pickup.ability_name = ability_name
	pickup.ability_color = ability_color
	add_child(pickup)
	pickup.global_position = pos
	spawned_pickups.append(pickup)

func spawn_random_ability(pos: Vector3) -> void:
	"""Spawn a random ability at the given position (for debug menu)"""
	var ability_types: Array = [
		[DashAttackScene, "Dash Attack", Color.ORANGE_RED],
		[ExplosionScene, "Explosion", Color.ORANGE],
		[GunScene, "Gun", Color.CYAN]
	]

	var random_ability: Array = ability_types[randi() % ability_types.size()]
	spawn_ability_at(pos, random_ability[0], random_ability[1], random_ability[2])
