extends Node3D

## Spawns collectible orbs at random 3D locations in the map volume

const OrbScene = preload("res://collectible_orb.tscn")

# Map volume bounds for random spawning
@export var spawn_bounds_min: Vector3 = Vector3(-40, 6, -40)  # Min X, Y, Z (doubled Y from 3)
@export var spawn_bounds_max: Vector3 = Vector3(40, 60, 40)   # Max X, Y, Z (doubled Y from 30)
@export var num_orbs: int = 12  # Number of orbs to spawn (reduced by half)

# Minimum distance between spawned items to prevent overlap
const MIN_SPAWN_SEPARATION: float = 3.0  # Minimum distance between abilities/orbs

# Respawn settings
@export var respawn_interval: float = 7.0  # Respawn every 7 seconds (reduced from 10)
@export var respawn_at_random_location: bool = true

var spawned_orbs: Array[Area3D] = []
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
		rng.seed = level_seed ^ 0x4F524253  # XOR with "ORBS" for unique but deterministic seed
	else:
		rng.randomize()
	# Don't spawn automatically - wait for world to call spawn_orbs() when match starts

func _process(delta: float) -> void:
	# Server-side respawn timer - only when game is active
	if not (multiplayer.is_server() or multiplayer.multiplayer_peer == null):
		return

	# Check if game is active
	var world: Node = get_parent()
	if not (world and world.has_method("is_game_active") and world.is_game_active()):
		return

	# PERF: Process respawn queue 1 item per frame to spread raycasts across frames
	# (Previously respawned ALL items at once = up to 2400 raycasts in a single frame)
	if not _respawn_queue.is_empty():
		var orb: Area3D = _respawn_queue.pop_front()
		if orb and is_instance_valid(orb) and orb.get("is_collected") == true:
			var new_pos: Vector3 = get_random_spawn_position()
			orb.global_position = new_pos
			if "base_height" in orb:
				orb.base_height = new_pos.y
			if orb.has_method("respawn_orb"):
				orb.respawn_orb()

	respawn_timer += delta
	if respawn_timer >= respawn_interval:
		respawn_timer = 0.0
		check_and_respawn_orbs()

func seed_rng_from_level() -> void:
	"""MULTIPLAYER SYNC FIX: Re-seed RNG from current level_seed for deterministic spawning"""
	var level_seed: int = 0
	if MultiplayerManager and MultiplayerManager.room_settings.has("level_seed"):
		level_seed = MultiplayerManager.room_settings["level_seed"]
	if level_seed != 0:
		rng.seed = level_seed ^ 0x4F524253  # XOR with "ORBS" for unique but deterministic seed
	else:
		rng.randomize()

func spawn_orbs() -> void:
	"""Spawn orbs at random 3D positions in the map volume"""
	# MULTIPLAYER SYNC FIX: All clients must spawn orbs (not just server)
	# Orbs need to exist on all clients for collection detection to work
	# Seeded RNG ensures all clients generate identical positions

	# Check if game is active before spawning
	var world: Node = get_parent()
	if not (world and world.has_method("is_game_active") and world.is_game_active()):
		DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "ORB SPAWNER: Game is not active, skipping spawn")
		return

	# Re-seed RNG before spawning to ensure deterministic positions across all clients
	seed_rng_from_level()

	# Scale orb count based on number of players (5 orbs per player)
	# Type B arenas get more orbs due to larger vertical space and rooms
	var player_count: int = get_tree().get_nodes_in_group("players").size()
	var orbs_per_player: float = 5.0  # Increased from 3.0

	# Check if Type B arena (more orbs needed for larger, multi-tier arenas)
	# Reuse world variable from above
	if world and world.has_method("get_current_level_type"):
		if world.get_current_level_type() == "B":
			orbs_per_player = 7.0  # Increased from 4.5

	var scaled_orbs: int = clamp(int(player_count * orbs_per_player), 25, 80)  # Increased from 12-48

	DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "=== ORB SPAWNER: Starting to spawn orbs ===")
	DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Players: %d | Total orbs: %d" % [player_count, scaled_orbs])
	DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Spawn bounds: min=%s, max=%s" % [spawn_bounds_min, spawn_bounds_max])

	for i in range(scaled_orbs):
		var random_pos: Vector3 = get_random_spawn_position()
		DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Orb %d spawning at position: %s" % [i+1, random_pos])
		spawn_orb_at_position(random_pos)

	DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "=== ORB SPAWNER: Spawned %d orbs in 3D map volume ===" % spawned_orbs.size())

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

		# Check if this position is too close to existing orbs or abilities
		if is_position_too_close_to_existing(candidate_pos):
			continue  # Try again

		# Position is valid - return it
		return candidate_pos

	# If we exhausted all attempts, return a fallback position (center of map)
	DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Warning: Could not find non-overlapping position after %d attempts, using fallback" % MAX_ATTEMPTS)
	return Vector3(0, (spawn_bounds_min.y + spawn_bounds_max.y) / 2.0, 0)

func is_position_too_close_to_existing(pos: Vector3) -> bool:
	"""Check if a position is too close to any existing orbs or abilities"""
	# Check against existing orbs
	for orb in spawned_orbs:
		if orb and orb.global_position.distance_to(pos) < MIN_SPAWN_SEPARATION:
			return true

	# Check against existing abilities from AbilitySpawner
	var world: Node = get_parent()
	if world:
		var ability_spawner: Node = world.get_node_or_null("AbilitySpawner")
		if ability_spawner and ability_spawner.has_method("get_all_ability_positions"):
			var ability_positions: Array = ability_spawner.get_all_ability_positions()
			for ability_pos in ability_positions:
				if ability_pos.distance_to(pos) < MIN_SPAWN_SEPARATION:
					return true

	return false

func get_all_orb_positions() -> Array:
	"""Return positions of all spawned orbs (used by AbilitySpawner to avoid overlap)"""
	var positions: Array = []
	for orb in spawned_orbs:
		if orb:
			positions.append(orb.global_position)
	return positions

func spawn_orb_at_position(pos: Vector3) -> void:
	"""Spawn a single orb at the given position"""
	var orb: Area3D = OrbScene.instantiate()
	orb.position = pos  # Set position BEFORE add_child so _ready() captures correct base_height
	add_child(orb)
	spawned_orbs.append(orb)
	# Note: Orbs have built-in bob animation, no need for velocity

func check_and_respawn_orbs() -> void:
	"""Queue collected orbs for respawn (processed 1 per frame to avoid raycast spikes)"""
	if not respawn_at_random_location:
		return

	for orb in spawned_orbs:
		if orb and orb.get("is_collected") == true:
			if orb not in _respawn_queue:
				_respawn_queue.append(orb)

func clear_all() -> void:
	"""Clear all orbs without respawning (called when match ends)"""
	for orb in spawned_orbs:
		if orb:
			orb.queue_free()
	spawned_orbs.clear()
	DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Cleared all orbs")

func respawn_all() -> void:
	"""Clear and respawn all orbs (called when level is regenerated)"""
	# Clear existing orbs
	for orb in spawned_orbs:
		if orb:
			orb.queue_free()
	spawned_orbs.clear()

	# Wait a frame for cleanup
	await get_tree().process_frame

	# Respawn all orbs
	spawn_orbs()
