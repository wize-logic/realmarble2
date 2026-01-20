extends Node3D

## Spawns collectible orbs at random 3D locations in the map volume

const OrbScene = preload("res://collectible_orb.tscn")

# Map volume bounds for random spawning
@export var spawn_bounds_min: Vector3 = Vector3(-40, 6, -40)  # Min X, Y, Z (doubled Y from 3)
@export var spawn_bounds_max: Vector3 = Vector3(40, 60, 40)   # Max X, Y, Z (doubled Y from 30)
@export var num_orbs: int = 12  # Number of orbs to spawn (reduced by half)

# Respawn settings
@export var respawn_interval: float = 7.0  # Respawn every 7 seconds (reduced from 10)
@export var respawn_at_random_location: bool = true

# Spawn spacing
const MIN_SPAWN_DISTANCE: float = 8.0  # Minimum distance between spawned items

var spawned_orbs: Array[Area3D] = []
var respawn_timer: float = 0.0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	# Initialize RNG with unique seed
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

	respawn_timer += delta
	if respawn_timer >= respawn_interval:
		respawn_timer = 0.0
		check_and_respawn_orbs()

func spawn_orbs() -> void:
	"""Spawn orbs at random 3D positions in the map volume"""
	# Only spawn on server (authoritative)
	if not (multiplayer.is_server() or multiplayer.multiplayer_peer == null):
		return

	# Check if game is active before spawning
	var world: Node = get_parent()
	if not (world and world.has_method("is_game_active") and world.is_game_active()):
		print("ORB SPAWNER: Game is not active, skipping spawn")
		return

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

	print("=== ORB SPAWNER: Starting to spawn orbs ===")
	print("Players: %d | Total orbs: %d" % [player_count, scaled_orbs])
	print("Spawn bounds: min=%s, max=%s" % [spawn_bounds_min, spawn_bounds_max])

	for i in range(scaled_orbs):
		var random_pos: Vector3 = get_random_spawn_position()
		print("Orb %d spawning at position: %s" % [i+1, random_pos])
		spawn_orb_at_position(random_pos)

	print("=== ORB SPAWNER: Spawned %d orbs in 3D map volume ===" % spawned_orbs.size())

func is_position_too_close_to_existing(pos: Vector3) -> bool:
	"""Check if a position is too close to existing orbs or ability pickups"""
	# Check distance to all existing orbs
	for orb in spawned_orbs:
		if orb and is_instance_valid(orb):
			var distance: float = pos.distance_to(orb.global_position)
			if distance < MIN_SPAWN_DISTANCE:
				return true

	# Also check distance to abilities to prevent overlap
	var abilities: Array[Node] = get_tree().get_nodes_in_group("ability_pickups")
	for ability in abilities:
		if ability and is_instance_valid(ability):
			var distance: float = pos.distance_to(ability.global_position)
			if distance < MIN_SPAWN_DISTANCE:
				return true

	return false

func get_random_spawn_position() -> Vector3:
	"""Generate a random position on top of the ground with spacing from other items"""
	const DEATH_ZONE_Y: float = -50.0  # Death zone position
	const MIN_SAFE_Y: float = -40.0    # Minimum safe Y position (above death zone)
	const MAX_ATTEMPTS: int = 30  # Maximum attempts to find a valid position

	var attempts: int = 0
	var spawn_pos: Vector3 = Vector3.ZERO

	while attempts < MAX_ATTEMPTS:
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
				# Too close to death zone - try again
				attempts += 1
				continue
			spawn_pos = result.position + Vector3.UP * 1.0
		else:
			# No ground found - use middle Y as fallback
			spawn_pos = Vector3(x, (spawn_bounds_min.y + spawn_bounds_max.y) / 2.0, z)

		# Check if this position is far enough from existing items
		if not is_position_too_close_to_existing(spawn_pos):
			return spawn_pos

		attempts += 1

	# If we couldn't find a valid position after max attempts, return the last position anyway
	# This prevents infinite loops while still trying to space items out
	return spawn_pos

func spawn_orb_at_position(pos: Vector3) -> void:
	"""Spawn a single orb at the given position"""
	var orb: Area3D = OrbScene.instantiate()
	orb.position = pos  # Set position BEFORE add_child so _ready() captures correct base_height
	add_child(orb)
	spawned_orbs.append(orb)
	# Note: Orbs have built-in bob animation, no need for velocity

func check_and_respawn_orbs() -> void:
	"""Check collected orbs and respawn them at random locations"""
	if not respawn_at_random_location:
		return

	for orb in spawned_orbs:
		if orb and orb.get("is_collected") == true:
			# Move orb to new random location on the ground
			var new_pos: Vector3 = get_random_spawn_position()
			orb.global_position = new_pos
			# Update base_height for the bobbing animation
			if "base_height" in orb:
				orb.base_height = new_pos.y

			# Properly reset the orb state by calling its respawn function
			if orb.has_method("respawn_orb"):
				orb.respawn_orb()
			print("Respawned orb at new random location: ", orb.global_position)

func clear_all() -> void:
	"""Clear all orbs without respawning (called when match ends)"""
	for orb in spawned_orbs:
		if orb:
			orb.queue_free()
	spawned_orbs.clear()
	print("Cleared all orbs")

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
