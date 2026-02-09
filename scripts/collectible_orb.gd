extends Area3D

## Collectible orb that grants level ups
## Players can collect up to 3 orbs for maximum power

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var collection_sound: AudioStreamPlayer3D = $CollectionSound

# Visual properties
var base_height: float = 0.0
var bob_speed: float = 2.0
var bob_amount: float = 0.3
var rotation_speed: float = 2.0
var time: float = 0.0

# Respawn properties
var respawn_time: float = 15.0  # Respawn after 15 seconds
var is_collected: bool = false
var respawn_timer: float = 0.0

# MULTIPLAYER SYNC FIX: Prevent race condition in orb collection
var collection_pending: bool = false  # True while waiting for server response

# Visual effects
var glow_material: StandardMaterial3D
static var _shared_material: StandardMaterial3D = null

# MULTIPLAYER SYNC FIX: Seeded RNG for deterministic animation across clients
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	# Add to orbs group for bot AI
	add_to_group("orbs")

	# Store initial height
	base_height = global_position.y

	# MULTIPLAYER SYNC FIX: Seed RNG based on orb position for deterministic animation
	# Position is determined by level generator, so all clients get the same seed
	_initialize_seeded_rng()

	# Set up collision detection
	body_entered.connect(_on_body_entered)

	# Set up visual appearance if mesh exists
	if mesh_instance and mesh_instance.mesh:
		# Share material across all orbs - create once, reuse
		if _shared_material == null:
			_shared_material = StandardMaterial3D.new()
			_shared_material.albedo_color = Color(0.3, 0.7, 1.0, 1.0)
			_shared_material.emission_enabled = false
			_shared_material.metallic = 0.2
			_shared_material.roughness = 0.3
		mesh_instance.material_override = _shared_material

	# Use seeded RNG for starting animation phase (deterministic across clients)
	time = rng.randf() * TAU

func _initialize_seeded_rng() -> void:
	"""Initialize seeded RNG for deterministic animation across all clients"""
	# Use orb position as seed - position is deterministic from level generator
	var pos_hash: int = int(global_position.x * 1000) ^ int(global_position.y * 1000) ^ int(global_position.z * 1000)

	# Also incorporate level_seed if available for extra determinism
	var level_seed: int = 0
	if MultiplayerManager and MultiplayerManager.room_settings.has("level_seed"):
		level_seed = MultiplayerManager.room_settings["level_seed"]

	rng.seed = pos_hash ^ level_seed

func _process(delta: float) -> void:
	if is_collected:
		return  # PERF: Collected orbs have set_process(false) - this is a safety fallback

	# Update animation time
	time += delta

	# Bob up and down - only write position when change exceeds threshold
	# (avoids per-frame transform notification propagation)
	var target_y: float = base_height + sin(time * bob_speed) * bob_amount
	if absf(global_position.y - target_y) > 0.005:
		var new_pos: Vector3 = global_position
		new_pos.y = target_y
		global_position = new_pos

	# Rotate slowly
	if mesh_instance:
		mesh_instance.rotation.y += rotation_speed * delta

func _on_body_entered(body: Node3D) -> void:
	# Check if it's a player and not already collected
	if is_collected:
		return

	# MULTIPLAYER SYNC FIX: Check if collection is already pending to prevent race condition
	if collection_pending:
		return

	# Check if body is a player (RigidBody3D with player script)
	# Allow collection regardless of level - even max level players can collect orbs
	if body is RigidBody3D and body.has_method("collect_orb"):
		var player_id: int = body.name.to_int()
		# In multiplayer, only server handles collection to prevent duplication
		if multiplayer.has_multiplayer_peer():
			if multiplayer.is_server():
				collect(body, player_id)
			else:
				# Mark as pending before sending request to prevent double-requests
				collection_pending = true
				# Client requests server to collect
				_request_collect.rpc_id(1, player_id)
		else:
			# Offline mode - collect directly
			collect(body, player_id)

@rpc("any_peer", "reliable")
func _request_collect(player_id: int) -> void:
	"""RPC: Client requests server to collect orb"""
	if not multiplayer.is_server():
		return
	if is_collected:
		return

	# Find the player node
	var world: Node = get_parent()
	if world:
		var player: Node = world.get_node_or_null(str(player_id))
		if player and player.has_method("collect_orb"):
			collect(player, player_id)

func collect(player: Node, player_id: int = -1) -> void:
	"""Handle orb collection"""
	if is_collected:
		return

	# Call player's collect method
	player.collect_orb()

	# Mark as collected and sync to clients
	_set_collected(true)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_collected.rpc(true)

	# Play collection sound
	if collection_sound and collection_sound.stream:
		play_collection_sound.rpc()

	DebugLogger.dlog(DebugLogger.Category.WORLD, "Orb collected by player %d! Respawning in %.1f seconds" % [player_id, respawn_time])

func _set_collected(collected: bool) -> void:
	"""Internal: Set collection state locally"""
	is_collected = collected
	# MULTIPLAYER SYNC FIX: Reset pending flag when collection state is confirmed
	collection_pending = false

	if collected:
		respawn_timer = respawn_time
		# Hide the orb
		if mesh_instance:
			mesh_instance.visible = false
		if collision_shape:
			collision_shape.set_deferred("disabled", true)
		# PERF: Stop _process for collected orbs (respawn handled by OrbSpawner)
		set_process(false)
	else:
		# Respawn - show the orb
		if mesh_instance:
			mesh_instance.visible = true
		if collision_shape:
			collision_shape.set_deferred("disabled", false)
		# MULTIPLAYER SYNC FIX: Use seeded RNG for deterministic time offset
		time += rng.randf() * 2.0
		# PERF: Re-enable _process for bobbing animation
		set_process(true)

@rpc("authority", "call_local", "reliable")
func _sync_collected(collected: bool) -> void:
	"""RPC: Server syncs collection state to all clients"""
	_set_collected(collected)

func respawn_orb() -> void:
	"""Respawn the orb"""
	# In multiplayer, only server initiates respawn
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_set_collected(false)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_collected.rpc(false)

	DebugLogger.dlog(DebugLogger.Category.WORLD, "Orb respawned!")

@rpc("call_local")
func play_collection_sound() -> void:
	"""Play collection sound effect"""
	if collection_sound and collection_sound.stream:
		# MULTIPLAYER SYNC FIX: Use seeded RNG for consistent pitch across clients
		collection_sound.pitch_scale = rng.randf_range(0.9, 1.1)
		collection_sound.play()
