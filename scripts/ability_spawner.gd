extends Node3D

## Spawns ability pickups at random 3D locations in the map volume
## These grant Kirby-style abilities to players

const AbilityPickupScene = preload("res://ability_pickup.tscn")
const DashAttackScene = preload("res://abilities/dash_attack.tscn")
const ExplosionScene = preload("res://abilities/explosion.tscn")
const CannonScene = preload("res://abilities/cannon.tscn")
const SwordScene = preload("res://abilities/sword.tscn")
const LightningStrikeScene = preload("res://abilities/lightning_strike.tscn")

# Map volume bounds for random spawning
@export var spawn_bounds_min: Vector3 = Vector3(-40, 6, -40)  # Min X, Y, Z (doubled Y from 3)
@export var spawn_bounds_max: Vector3 = Vector3(40, 60, 40)   # Max X, Y, Z (doubled Y from 30)

# Minimum distance between spawned items to prevent overlap
const MIN_SPAWN_SEPARATION: float = 3.0  # Minimum distance between abilities/orbs

# Number of each ability type to spawn (reduced by half)
@export var num_dash_attacks: int = 2
@export var num_explosions: int = 2
@export var num_cannons: int = 4
@export var num_swords: int = 2

# Respawn settings
@export var respawn_interval: float = 7.0  # Check respawn every 7 seconds (reduced from 10)
@export var respawn_at_random_location: bool = true

var spawned_pickups: Array[Area3D] = []
var respawn_timer: float = 0.0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _respawn_queue: Array[Area3D] = []  # PERF: Queue respawns to spread raycasts across frames

func _ready() -> void:
	# MULTIPLAYER SYNC FIX: Use level_seed for deterministic spawning across all clients
	# Falls back to randomize() for offline/practice mode
	var level_seed: int = 0
	if MultiplayerManager and MultiplayerManager.room_settings.has("level_seed"):
		level_seed = MultiplayerManager.room_settings["level_seed"]
	if level_seed != 0:
		rng.seed = level_seed ^ 0x41424C53  # XOR with "ABLS" for unique but deterministic seed
	else:
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

	# PERF: Process respawn queue 1 item per frame to spread raycasts across frames
	# (Previously respawned ALL items at once = up to 1800 raycasts in a single frame)
	if not _respawn_queue.is_empty():
		var pickup: Area3D = _respawn_queue.pop_front()
		if pickup and is_instance_valid(pickup) and pickup.get("is_collected") == true:
			var new_pos: Vector3 = get_random_spawn_position()
			pickup.global_position = new_pos
			if "base_height" in pickup:
				pickup.base_height = new_pos.y
			if pickup.has_method("respawn_pickup"):
				pickup.respawn_pickup()

	respawn_timer += delta
	if respawn_timer >= respawn_interval:
		respawn_timer = 0.0
		check_and_respawn_pickups()

func seed_rng_from_level() -> void:
	"""MULTIPLAYER SYNC FIX: Re-seed RNG from current level_seed for deterministic spawning"""
	var level_seed: int = 0
	if MultiplayerManager and MultiplayerManager.room_settings.has("level_seed"):
		level_seed = MultiplayerManager.room_settings["level_seed"]
	if level_seed != 0:
		rng.seed = level_seed ^ 0x41424C53  # XOR with "ABLS" for unique but deterministic seed
	else:
		rng.randomize()

func spawn_abilities() -> void:
	"""Spawn ability pickups at random 3D positions in the map volume"""
	# MULTIPLAYER SYNC FIX: All clients must spawn abilities (not just server)
	# Abilities need to exist on all clients for collection detection to work
	# Seeded RNG ensures all clients generate identical positions

	# Check if game is active before spawning
	var world: Node = get_parent()
	if not (world and world.has_method("is_game_active") and world.is_game_active()):
		DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "ABILITY SPAWNER: Game is not active, skipping spawn")
		return

	# Re-seed RNG before spawning to ensure deterministic positions across all clients
	seed_rng_from_level()

	# Scale ability count based on number of players
	# PERF: Reduced counts on HTML5 to cut per-frame _process overhead (each item runs bobbing animation)
	var player_count: int = get_tree().get_nodes_in_group("players").size()
	var _is_web: bool = OS.has_feature("web")
	var abilities_per_player: float = 2.0 if _is_web else 4.0

	# Check if Type B arena (more abilities needed for larger, multi-tier arenas)
	# Reuse world variable from above
	if world and world.has_method("get_current_level_type"):
		if world.get_current_level_type() == "B":
			abilities_per_player = 3.0 if _is_web else 5.5

	var max_abilities: int = 30 if _is_web else 60
	var total_abilities: int = clamp(int(player_count * abilities_per_player), 10, max_abilities)

	# Distribute abilities equally across all types (20% each for 5 abilities)
	# All abilities are equally viable - none should be rare
	var scaled_dash: int = max(1, int(total_abilities * 0.20))       # 20%
	var scaled_explosion: int = max(1, int(total_abilities * 0.20))  # 20%
	var scaled_cannon: int = max(1, int(total_abilities * 0.20))     # 20%
	var scaled_sword: int = max(1, int(total_abilities * 0.20))      # 20%
	var scaled_lightning: int = max(1, int(total_abilities * 0.20)) # 20%

	DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "=== ABILITY SPAWNER: Starting to spawn abilities ===")
	DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Players: %d | Total abilities: %d" % [player_count, total_abilities])
	DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Spawn bounds: min=%s, max=%s" % [spawn_bounds_min, spawn_bounds_max])

	# Spawn dash attacks
	for i in range(scaled_dash):
		var pos: Vector3 = get_random_spawn_position()
		DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Dash Attack %d spawning at: %s" % [i+1, pos])
		spawn_ability_at(pos, DashAttackScene, "Dash Attack", Color.MAGENTA)

	# Spawn explosions
	for i in range(scaled_explosion):
		var pos: Vector3 = get_random_spawn_position()
		DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Explosion %d spawning at: %s" % [i+1, pos])
		spawn_ability_at(pos, ExplosionScene, "Explosion", Color.ORANGE)

	# Spawn cannons
	for i in range(scaled_cannon):
		var pos: Vector3 = get_random_spawn_position()
		DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Cannon %d spawning at: %s" % [i+1, pos])
		spawn_ability_at(pos, CannonScene, "Cannon", Color(0.5, 1.0, 0.0))  # Lime green

	# Spawn swords
	for i in range(scaled_sword):
		var pos: Vector3 = get_random_spawn_position()
		DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Sword %d spawning at: %s" % [i+1, pos])
		spawn_ability_at(pos, SwordScene, "Sword", Color.CYAN)

	# Spawn lightning strikes
	for i in range(scaled_lightning):
		var pos: Vector3 = get_random_spawn_position()
		DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Lightning Strike %d spawning at: %s" % [i+1, pos])
		spawn_ability_at(pos, LightningStrikeScene, "Lightning", Color(0.4, 0.8, 1.0))  # Electric cyan

	DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "=== ABILITY SPAWNER: Spawned %d ability pickups ===" % spawned_pickups.size())

func get_random_spawn_position() -> Vector3:
	"""Generate a random position on top of the ground, avoiding overlap with existing items"""
	const DEATH_ZONE_Y: float = -50.0  # Death zone position
	const MIN_SAFE_Y: float = -40.0    # Minimum safe Y position (above death zone)
	const MAX_ATTEMPTS: int = 10  # Reduced from 30 to limit raycast spikes

	var attempts: int = 0
	while attempts < MAX_ATTEMPTS:
		attempts += 1

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

		var candidate_pos: Vector3
		if result:
			# Found ground - check if it's in death zone
			var spawn_y: float = result.position.y + 1.0
			if spawn_y < MIN_SAFE_Y:
				# Too close to death zone - try again
				continue
			candidate_pos = result.position + Vector3.UP * 1.0
		else:
			# No ground found - use middle Y as fallback
			candidate_pos = Vector3(x, (spawn_bounds_min.y + spawn_bounds_max.y) / 2.0, z)

		# Check if this position is too close to existing abilities
		if is_position_too_close_to_existing(candidate_pos):
			continue  # Try again

		# Position is valid - return it
		return candidate_pos

	# If we exhausted all attempts, return a fallback position (center of map)
	DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Warning: Could not find non-overlapping position after %d attempts, using fallback" % MAX_ATTEMPTS)
	return Vector3(0, (spawn_bounds_min.y + spawn_bounds_max.y) / 2.0, 0)

func is_position_too_close_to_existing(pos: Vector3) -> bool:
	"""Check if a position is too close to any existing abilities or orbs"""
	# Check against existing abilities
	for pickup in spawned_pickups:
		if pickup and pickup.global_position.distance_to(pos) < MIN_SPAWN_SEPARATION:
			return true

	# Check against existing orbs from OrbSpawner
	var world: Node = get_parent()
	if world:
		var orb_spawner: Node = world.get_node_or_null("OrbSpawner")
		if orb_spawner and orb_spawner.has_method("get_all_orb_positions"):
			var orb_positions: Array = orb_spawner.get_all_orb_positions()
			for orb_pos in orb_positions:
				if orb_pos.distance_to(pos) < MIN_SPAWN_SEPARATION:
					return true

	return false

func get_all_ability_positions() -> Array:
	"""Return positions of all spawned abilities (used by OrbSpawner to avoid overlap)"""
	var positions: Array = []
	for pickup in spawned_pickups:
		if pickup:
			positions.append(pickup.global_position)
	return positions

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
	"""Queue collected pickups for respawn (processed 1 per frame to avoid raycast spikes)"""
	if not respawn_at_random_location:
		return

	for pickup in spawned_pickups:
		if pickup and pickup.get("is_collected") == true:
			if pickup not in _respawn_queue:
				_respawn_queue.append(pickup)

func spawn_random_ability(pos: Vector3) -> void:
	"""Spawn a random ability at the given position (for debug menu)"""
	var ability_types: Array = [
		[DashAttackScene, "Dash Attack", Color.MAGENTA],
		[ExplosionScene, "Explosion", Color.ORANGE],
		[CannonScene, "Cannon", Color(0.5, 1.0, 0.0)],  # Lime green
		[SwordScene, "Sword", Color.CYAN],
		[LightningStrikeScene, "Lightning", Color(0.4, 0.8, 1.0)]  # Electric cyan
	]

	var random_ability: Array = ability_types[randi() % ability_types.size()]
	spawn_ability_at(pos, random_ability[0], random_ability[1], random_ability[2])

func clear_all() -> void:
	"""Clear all abilities without respawning (called when match ends)"""
	for pickup in spawned_pickups:
		if pickup:
			pickup.queue_free()
	spawned_pickups.clear()
	DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Cleared all ability pickups")

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
