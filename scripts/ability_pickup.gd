extends Area3D

## Ability pickup that grants players a Kirby-style ability
## Randomly spawns after being collected

@export var ability_scene: PackedScene  # The ability to grant
@export var ability_name: String = "Unknown Ability"
@export var ability_color: Color = Color(0.7, 0.85, 1.0)  # Soft cyan default (no white)

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var pickup_sound: AudioStreamPlayer3D = $PickupSound

# Visual properties
var base_height: float = 0.0
var bob_speed: float = 2.5
var bob_amount: float = 0.25
var rotation_speed: float = 3.0
var time: float = 0.0

# Respawn properties
var respawn_time: float = 20.0  # Respawn after 20 seconds
var is_collected: bool = false
var respawn_timer: float = 0.0

# Visual effects
var glow_material: StandardMaterial3D

# Spawn animation
var spawn_animation_time: float = 0.5  # Duration of spawn animation
var spawn_timer: float = 0.0
var is_spawning: bool = true

# MULTIPLAYER SYNC FIX: Seeded RNG for deterministic animation across clients
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	# Add to ability pickups group for bot AI
	add_to_group("ability_pickups")

	# Store initial height
	base_height = global_position.y

	# Set up collision detection
	body_entered.connect(_on_body_entered)

	# Set up visual appearance
	if mesh_instance and mesh_instance.mesh:
		# Create material based on ability color (no emission/glow)
		glow_material = StandardMaterial3D.new()
		glow_material.albedo_color = ability_color
		glow_material.metallic = 0.3
		glow_material.roughness = 0.3
		mesh_instance.material_override = glow_material

	# Customize animation based on ability type for variety
	match ability_name:
		"Dash Attack":
			# Fast, energetic bobbing and spinning
			bob_speed = 4.0
			bob_amount = 0.35
			rotation_speed = 5.0
			spawn_animation_time = 0.3  # Quick spawn
		"Explosion":
			# Slow, heavy bobbing
			bob_speed = 1.5
			bob_amount = 0.15
			rotation_speed = 2.0
			spawn_animation_time = 0.7  # Slow spawn
		"Cannon":
			# Medium, steady bobbing
			bob_speed = 2.0
			bob_amount = 0.3
			rotation_speed = 3.5
			spawn_animation_time = 0.4  # Medium spawn
		"Sword":
			# Sharp, precise bobbing
			bob_speed = 3.0
			bob_amount = 0.2
			rotation_speed = 4.5
			spawn_animation_time = 0.35  # Quick spawn

	# Start with scale 0 for spawn animation
	if mesh_instance:
		mesh_instance.scale = Vector3.ZERO

	# MULTIPLAYER SYNC FIX: Seed RNG based on position for deterministic animation
	var pos_hash: int = int(global_position.x * 1000) ^ int(global_position.y * 1000) ^ int(global_position.z * 1000)
	var level_seed: int = 0
	if MultiplayerManager and MultiplayerManager.room_settings.has("level_seed"):
		level_seed = MultiplayerManager.room_settings["level_seed"]
	rng.seed = pos_hash ^ level_seed

	# Use seeded RNG for starting animation phase (deterministic across clients)
	time = rng.randf() * TAU

func _process(delta: float) -> void:
	if is_collected:
		return  # PERF: Collected pickups have set_process(false) - this is a safety fallback

	# Handle spawn animation
	if is_spawning:
		spawn_timer += delta
		var spawn_progress: float = min(spawn_timer / spawn_animation_time, 1.0)

		if mesh_instance:
			# Different spawn animations per ability type
			match ability_name:
				"Dash Attack":
					# Fast pop-in with overshoot
					var scale_curve: float = ease(spawn_progress, -2.0)  # Overshoot
					mesh_instance.scale = Vector3.ONE * scale_curve
				"Explosion":
					# Slow expand from center
					var scale_curve: float = ease(spawn_progress, 0.5)
					mesh_instance.scale = Vector3.ONE * scale_curve
				"Cannon":
					# Smooth fade-in scale
					var scale_curve: float = ease(spawn_progress, 1.0)
					mesh_instance.scale = Vector3.ONE * scale_curve
				"Sword":
					# Sharp linear scale-in
					mesh_instance.scale = Vector3.ONE * spawn_progress
				_:
					# Default smooth scale
					mesh_instance.scale = Vector3.ONE * ease(spawn_progress, 1.0)

		if spawn_timer >= spawn_animation_time:
			is_spawning = false
			if mesh_instance:
				mesh_instance.scale = Vector3.ONE

	# Update animation time
	time += delta

	# Bob up and down - only write position when change exceeds threshold
	# (avoids per-frame transform notification propagation)
	var target_y: float = base_height + sin(time * bob_speed) * bob_amount
	if absf(global_position.y - target_y) > 0.005:
		var new_pos: Vector3 = global_position
		new_pos.y = target_y
		global_position = new_pos

	# Rotate
	if mesh_instance:
		mesh_instance.rotation.y += rotation_speed * delta
		mesh_instance.rotation.x = sin(time * 1.5) * 0.2  # Slight tilt

func _on_body_entered(body: Node3D) -> void:
	# Check if it's a player and not already collected
	if is_collected:
		return

	# Check if body is a player
	if body is RigidBody3D and body.has_method("pickup_ability"):
		var player_id: int = body.name.to_int()
		# In multiplayer, only server handles collection to prevent duplication
		if multiplayer.has_multiplayer_peer():
			if multiplayer.is_server():
				collect(body, player_id)
			else:
				# Client requests server to collect
				_request_collect.rpc_id(1, player_id)
		else:
			# Offline mode - collect directly
			collect(body, player_id)

@rpc("any_peer", "reliable")
func _request_collect(player_id: int) -> void:
	"""RPC: Client requests server to collect ability"""
	if not multiplayer.is_server():
		return
	if is_collected:
		return

	# Find the player node
	var world: Node = get_parent()
	if world:
		var player: Node = world.get_node_or_null(str(player_id))
		if player and player.has_method("pickup_ability"):
			collect(player, player_id)

func collect(player: Node, player_id: int = -1) -> void:
	"""Handle ability pickup collection"""
	if is_collected:
		return

	# Give player the ability
	if ability_scene:
		player.pickup_ability(ability_scene, ability_name)
	else:
		DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Warning: Ability pickup has no ability_scene assigned!")

	# Mark as collected and sync to clients
	_set_collected(true)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_collected.rpc(true)

	# Play pickup sound
	if pickup_sound and pickup_sound.stream:
		play_pickup_sound.rpc()

	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Ability '%s' collected by player %d! Respawning in %.1f seconds" % [ability_name, player_id, respawn_time])

func _set_collected(collected: bool) -> void:
	"""Internal: Set collection state locally"""
	is_collected = collected
	if collected:
		respawn_timer = respawn_time
		# Hide the pickup
		if mesh_instance:
			mesh_instance.visible = false
		if collision_shape:
			collision_shape.set_deferred("disabled", true)
		# PERF: Stop _process for collected pickups (respawn handled by AbilitySpawner)
		set_process(false)
	else:
		# Respawn - show the pickup with animation
		if mesh_instance:
			mesh_instance.visible = true
			mesh_instance.scale = Vector3.ZERO
		if collision_shape:
			collision_shape.set_deferred("disabled", false)
		is_spawning = true
		spawn_timer = 0.0
		time += rng.randf() * 2.0
		# PERF: Re-enable _process for bobbing animation
		set_process(true)

@rpc("authority", "call_local", "reliable")
func _sync_collected(collected: bool) -> void:
	"""RPC: Server syncs collection state to all clients"""
	_set_collected(collected)

func respawn_pickup() -> void:
	"""Respawn the ability pickup"""
	# In multiplayer, only server initiates respawn
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_do_respawn()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_collected.rpc(false)

func _do_respawn() -> void:
	"""Internal: Perform respawn locally"""
	is_collected = false

	# Show the pickup again
	if mesh_instance:
		mesh_instance.visible = true
	if collision_shape:
		collision_shape.set_deferred("disabled", false)

	# Reset spawn animation
	is_spawning = true
	spawn_timer = 0.0
	if mesh_instance:
		mesh_instance.scale = Vector3.ZERO

	# MULTIPLAYER SYNC FIX: Use seeded RNG for deterministic animation phase
	time += rng.randf() * 2.0

	# PERF: Re-enable _process for bobbing animation
	set_process(true)

	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Ability pickup '%s' respawned!" % ability_name)

@rpc("call_local")
func play_pickup_sound() -> void:
	"""Play pickup sound effect"""
	if pickup_sound and pickup_sound.stream:
		# MULTIPLAYER SYNC FIX: Use seeded RNG for consistent pitch across clients
		pickup_sound.pitch_scale = rng.randf_range(1.0, 1.2)
		pickup_sound.play()
