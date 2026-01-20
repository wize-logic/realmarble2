extends Node3D

## Spawns ability pickups at random 3D locations in the map volume
## These grant Kirby-style abilities to players

const AbilityPickupScene = preload("res://ability_pickup.tscn")
const DashAttackScene = preload("res://abilities/dash_attack.tscn")
const ExplosionScene = preload("res://abilities/explosion.tscn")
const CannonScene = preload("res://abilities/cannon.tscn")
const SwordScene = preload("res://abilities/sword.tscn")

# Map volume bounds for random spawning
@export var spawn_bounds_min: Vector3 = Vector3(-40, 6, -40)  # Min X, Y, Z (doubled Y from 3)
@export var spawn_bounds_max: Vector3 = Vector3(40, 60, 40)   # Max X, Y, Z (doubled Y from 30)

# Number of each ability type to spawn (reduced by half)
@export var num_dash_attacks: int = 2
@export var num_explosions: int = 2
@export var num_cannons: int = 4
@export var num_swords: int = 2

# Respawn settings
@export var respawn_interval: float = 10.0  # Check respawn every 10 seconds
@export var respawn_at_random_location: bool = true

var spawned_pickups: Array[Area3D] = []
var respawn_timer: float = 0.0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	# Initialize RNG with unique seed
	rng.randomize()
	# Don't spawn automatically - wait for world to call spawn_abilities() when match starts

func _process(delta: float) -> void:
	# Server-side respawn timer - only when game is active
	if not (multiplayer.is_server() or multiplayer.multiplayer_peer == null):
		return

	# Check if game is active
	var world: Node = get_parent()
	if not (world and world.has_method("is_game_active") and world.is_game_active()):
		return

	respawn_timer += delta
	if respawn_timer >= respawn_interval:
		respawn_timer = 0.0
		check_and_respawn_pickups()

func spawn_abilities() -> void:
	"""Spawn ability pickups at random 3D positions in the map volume"""
	# Only spawn on server (authoritative)
	if not (multiplayer.is_server() or multiplayer.multiplayer_peer == null):
		return

	# Check if game is active before spawning
	var world: Node = get_parent()
	if not (world and world.has_method("is_game_active") and world.is_game_active()):
		print("ABILITY SPAWNER: Game is not active, skipping spawn")
		return

	# Scale ability count based on number of players (2.5 abilities per player)
	# Type B arenas get more abilities due to larger vertical space and rooms
	var player_count: int = get_tree().get_nodes_in_group("players").size()
	var abilities_per_player: float = 2.5

	# Check if Type B arena (more abilities needed for larger, multi-tier arenas)
	var world: Node = get_parent()
	if world and world.has_method("get_current_level_type"):
		if world.get_current_level_type() == "B":
			abilities_per_player = 3.5  # 40% more abilities for Type B

	var total_abilities: int = clamp(int(player_count * abilities_per_player), 10, 35)  # Increased for Type B

	# Distribute abilities across types (proportional to original ratios)
	# Original ratio: Dash=2, Explosion=2, Cannon=4, Sword=2 (total=10)
	var scaled_dash: int = max(1, int(total_abilities * 0.2))      # 20%
	var scaled_explosion: int = max(1, int(total_abilities * 0.2))  # 20%
	var scaled_cannon: int = max(2, int(total_abilities * 0.4))     # 40%
	var scaled_sword: int = max(1, int(total_abilities * 0.2))      # 20%

	print("=== ABILITY SPAWNER: Starting to spawn abilities ===")
	print("Players: %d | Total abilities: %d" % [player_count, total_abilities])
	print("Spawn bounds: min=%s, max=%s" % [spawn_bounds_min, spawn_bounds_max])

	# Spawn dash attacks
	for i in range(scaled_dash):
		var pos: Vector3 = get_random_spawn_position()
		print("Dash Attack %d spawning at: %s" % [i+1, pos])
		spawn_ability_at(pos, DashAttackScene, "Dash Attack", Color.MAGENTA)

	# Spawn explosions
	for i in range(scaled_explosion):
		var pos: Vector3 = get_random_spawn_position()
		print("Explosion %d spawning at: %s" % [i+1, pos])
		spawn_ability_at(pos, ExplosionScene, "Explosion", Color.ORANGE)

	# Spawn cannons
	for i in range(scaled_cannon):
		var pos: Vector3 = get_random_spawn_position()
		print("Cannon %d spawning at: %s" % [i+1, pos])
		spawn_ability_at(pos, CannonScene, "Cannon", Color(0.5, 1.0, 0.0))  # Lime green

	# Spawn swords
	for i in range(scaled_sword):
		var pos: Vector3 = get_random_spawn_position()
		print("Sword %d spawning at: %s" % [i+1, pos])
		spawn_ability_at(pos, SwordScene, "Sword", Color.CYAN)

	print("=== ABILITY SPAWNER: Spawned %d ability pickups ===" % spawned_pickups.size())

func get_random_spawn_position() -> Vector3:
	"""Generate a random position on top of the ground"""
	const DEATH_ZONE_Y: float = -50.0  # Death zone position
	const MIN_SAFE_Y: float = -40.0    # Minimum safe Y position (above death zone)

	# Generate random X and Z within bounds
	var x: float = rng.randf_range(spawn_bounds_min.x, spawn_bounds_max.x)
	var z: float = rng.randf_range(spawn_bounds_min.z, spawn_bounds_max.z)

	# Raycast from high up to find the ground
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var start_pos: Vector3 = Vector3(x, spawn_bounds_max.y, z)
	var end_pos: Vector3 = Vector3(x, spawn_bounds_min.y - 10, z)

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
	query.collision_mask = 1  # Only check world geometry (layer 1)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result: Dictionary = space_state.intersect_ray(query)

	if result:
		# Found ground - check if it's in death zone
		var spawn_y: float = result.position.y + 1.0
		if spawn_y < MIN_SAFE_Y:
			# Too close to death zone - use safe fallback position
			return Vector3(x, (spawn_bounds_min.y + spawn_bounds_max.y) / 2.0, z)
		return result.position + Vector3.UP * 1.0
	else:
		# No ground found - use middle Y as fallback
		return Vector3(x, (spawn_bounds_min.y + spawn_bounds_max.y) / 2.0, z)

func spawn_ability_at(pos: Vector3, ability_scene: PackedScene, ability_name: String, ability_color: Color) -> void:
	"""Spawn an ability pickup at the given position"""
	var pickup: Area3D = AbilityPickupScene.instantiate()
	pickup.ability_scene = ability_scene
	pickup.ability_name = ability_name
	pickup.ability_color = ability_color
	pickup.position = pos  # Set position BEFORE add_child so _ready() captures correct base_height
	add_child(pickup)
	spawned_pickups.append(pickup)

func check_and_respawn_pickups() -> void:
	"""Check collected pickups and respawn them at random locations"""
	if not respawn_at_random_location:
		return

	for pickup in spawned_pickups:
		if pickup and pickup.get("is_collected") == true:
			# Move pickup to new random location on the ground
			var new_pos: Vector3 = get_random_spawn_position()
			pickup.global_position = new_pos
			# Update base_height for the bobbing animation
			if "base_height" in pickup:
				pickup.base_height = new_pos.y

			# Properly reset the pickup state by calling its respawn function
			if pickup.has_method("respawn_pickup"):
				pickup.respawn_pickup()
			print("Respawned pickup at new random location: ", pickup.global_position)

func spawn_random_ability(pos: Vector3) -> void:
	"""Spawn a random ability at the given position (for debug menu)"""
	var ability_types: Array = [
		[DashAttackScene, "Dash Attack", Color.MAGENTA],
		[ExplosionScene, "Explosion", Color.ORANGE],
		[CannonScene, "Cannon", Color(0.5, 1.0, 0.0)],  # Lime green
		[SwordScene, "Sword", Color.CYAN]
	]

	var random_ability: Array = ability_types[randi() % ability_types.size()]
	spawn_ability_at(pos, random_ability[0], random_ability[1], random_ability[2])

func clear_all() -> void:
	"""Clear all abilities without respawning (called when match ends)"""
	for pickup in spawned_pickups:
		if pickup:
			pickup.queue_free()
	spawned_pickups.clear()
	print("Cleared all ability pickups")

func respawn_all() -> void:
	"""Clear and respawn all abilities (called when level is regenerated)"""
	# Clear existing pickups
	for pickup in spawned_pickups:
		if pickup:
			pickup.queue_free()
	spawned_pickups.clear()

	# Wait a frame for cleanup
	await get_tree().process_frame

	# Respawn all abilities
	spawn_abilities()
