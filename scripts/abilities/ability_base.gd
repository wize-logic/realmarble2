extends Node3D
class_name Ability

## Base class for all Kirby-style abilities
## Abilities can be picked up, used, and dropped by players

@export var ability_name: String = "Ability"
@export var ability_color: Color = Color(0.2, 0.85, 1.0)  # Vivid electric cyan default
@export var cooldown_time: float = 2.0
@export var supports_charging: bool = true  # Can this ability be charged?
@export var max_charge_time: float = 2.0  # Max charge time in seconds

var player: Node = null  # Reference to the player who has this ability
var is_on_cooldown: bool = false
var cooldown_timer: float = 0.0

# Charging system
var is_charging: bool = false
var charge_time: float = 0.0  # Current charge time
var charge_level: int = 1  # 1 = weak, 2 = medium, 3 = max
var charge_particles: CPUParticles3D = null  # Visual feedback for charging

# PERF: Static shared resources for particle effects across ALL abilities
# Avoids redundant StandardMaterial3D creation which triggers WebGL shader recompilation
static var _shared_particle_mat_billboard: StandardMaterial3D = null  # Additive, billboard, unshaded
static var _shared_particle_mat_no_billboard: StandardMaterial3D = null  # Additive, no billboard, unshaded
static var _shared_particle_quad_small: QuadMesh = null  # 0.15x0.15
static var _shared_particle_quad_medium: QuadMesh = null  # 0.3x0.3
static var _shared_particle_quad_large: QuadMesh = null  # 0.5x0.5
static var _shared_particle_quad_xlarge: QuadMesh = null  # 0.8x0.8
static var _is_web: bool = false
static var _shared_resources_initialized: bool = false

# PERF: Shared hit sound pool to avoid creating AudioStreamPlayer3D per hit
var _hit_sound_pool: Array[AudioStreamPlayer3D] = []
const HIT_SOUND_POOL_SIZE: int = 3
var _hit_sound_pool_initialized: bool = false

static func _ensure_shared_resources() -> void:
	if _shared_resources_initialized:
		return
	_shared_resources_initialized = true
	_is_web = OS.has_feature("web")

	# Billboard additive particle material (most common)
	_shared_particle_mat_billboard = StandardMaterial3D.new()
	_shared_particle_mat_billboard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shared_particle_mat_billboard.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shared_particle_mat_billboard.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shared_particle_mat_billboard.vertex_color_use_as_albedo = true
	_shared_particle_mat_billboard.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_shared_particle_mat_billboard.disable_receive_shadows = true

	# Non-billboard additive particle material (for spin attacks etc.)
	_shared_particle_mat_no_billboard = StandardMaterial3D.new()
	_shared_particle_mat_no_billboard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shared_particle_mat_no_billboard.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shared_particle_mat_no_billboard.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shared_particle_mat_no_billboard.vertex_color_use_as_albedo = true
	_shared_particle_mat_no_billboard.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_shared_particle_mat_no_billboard.disable_receive_shadows = true

	# Shared quad meshes at common sizes
	_shared_particle_quad_small = QuadMesh.new()
	_shared_particle_quad_small.size = Vector2(0.15, 0.15)
	_shared_particle_quad_small.material = _shared_particle_mat_billboard

	_shared_particle_quad_medium = QuadMesh.new()
	_shared_particle_quad_medium.size = Vector2(0.3, 0.3)
	_shared_particle_quad_medium.material = _shared_particle_mat_billboard

	_shared_particle_quad_large = QuadMesh.new()
	_shared_particle_quad_large.size = Vector2(0.5, 0.5)
	_shared_particle_quad_large.material = _shared_particle_mat_billboard

	_shared_particle_quad_xlarge = QuadMesh.new()
	_shared_particle_quad_xlarge.size = Vector2(0.8, 0.8)
	_shared_particle_quad_xlarge.material = _shared_particle_mat_billboard

func get_entity_id() -> int:
	"""Get the owner player/bot's entity ID for debug logging"""
	if player:
		return player.name.to_int()
	return -1

func _is_bot_owner() -> bool:
	"""Check if this ability is owned by a bot on HTML5"""
	if not OS.has_feature("web"):
		return false
	var parent: Node = get_parent()
	return parent and parent.has_method("is_bot") and parent.is_bot()

func is_local_human_player() -> bool:
	"""Check if this ability is owned by the local human player (not a bot, not remote)"""
	if not player:
		return false
	# Guard: only call is_multiplayer_authority() when the peer is active.
	# After leaving a lobby the peer is null/disconnected and get_unique_id() errors.
	if MultiplayerManager.has_active_peer():
		if not player.is_multiplayer_authority():
			return false
	return not (player.has_method("is_bot") and player.is_bot())

func _ensure_hit_sound_pool() -> void:
	"""Lazily initialize the hit sound pool"""
	if _hit_sound_pool_initialized:
		return
	_hit_sound_pool_initialized = true
	for i in range(HIT_SOUND_POOL_SIZE):
		var snd: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		snd.name = "PooledHitSound_%d" % i
		snd.max_distance = 20.0
		snd.volume_db = 3.0
		add_child(snd)
		_hit_sound_pool.append(snd)

func play_pooled_hit_sound(position: Vector3) -> void:
	"""Play a hit sound from the pool instead of creating a new AudioStreamPlayer3D"""
	# ability_sound is declared in subclasses via @onready, access dynamically
	var snd_source: AudioStreamPlayer3D = get("ability_sound") as AudioStreamPlayer3D
	if not snd_source or not snd_source.stream:
		return
	_ensure_hit_sound_pool()
	# Find a non-playing sound in the pool
	for snd in _hit_sound_pool:
		if not snd.playing:
			snd.stream = snd_source.stream
			snd.global_position = position
			snd.pitch_scale = randf_range(1.2, 1.4)
			snd.play()
			return
	# All busy - reuse the first one (oldest sound)
	var snd: AudioStreamPlayer3D = _hit_sound_pool[0]
	snd.stream = snd_source.stream
	snd.global_position = position
	snd.pitch_scale = randf_range(1.2, 1.4)
	snd.play()

func _ready() -> void:
	# PERF: Initialize shared resources once (idempotent)
	_ensure_shared_resources()

	# Create charge particles if charging is supported
	# PERF: Skip charge particles for bots on HTML5 - bots never charge abilities
	if supports_charging and not _is_bot_owner():
		charge_particles = CPUParticles3D.new()
		charge_particles.name = "ChargeParticles"
		add_child(charge_particles)

		# Configure charge particles - growing glow
		charge_particles.emitting = false
		charge_particles.amount = 12 if _is_web else 25  # PERF: Reduced for performance
		charge_particles.lifetime = 0.8
		charge_particles.explosiveness = 0.0  # Continuous emission
		charge_particles.randomness = 0.3
		charge_particles.local_coords = true

		# PERF: Use shared particle mesh + material instead of creating new ones
		charge_particles.mesh = _shared_particle_quad_small

		# Emission shape - sphere around ability
		charge_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		charge_particles.emission_sphere_radius = 1.0

		# Movement - orbit around ability
		charge_particles.direction = Vector3(0, 1, 0)
		charge_particles.spread = 180.0
		charge_particles.gravity = Vector3.ZERO
		charge_particles.initial_velocity_min = 1.0
		charge_particles.initial_velocity_max = 2.0

		# Size - will scale with charge level
		charge_particles.scale_amount_min = 1.0
		charge_particles.scale_amount_max = 1.5

		# Color - based on ability color, will intensify with charge
		var gradient: Gradient = Gradient.new()
		gradient.add_point(0.0, ability_color * 1.5)
		gradient.add_point(0.5, ability_color)
		gradient.add_point(1.0, Color(ability_color.r, ability_color.g, ability_color.b, 0.0))
		charge_particles.color_ramp = gradient

func _process(delta: float) -> void:
	# Handle cooldown
	if is_on_cooldown:
		cooldown_timer -= delta
		if cooldown_timer <= 0.0:
			is_on_cooldown = false
			# PERF: If not charging, nothing else to do - skip rest of _process
			if not is_charging:
				return
	elif not is_charging:
		return  # PERF: Nothing to do - early out

	# Handle charging (human players only - bots never charge)
	if is_charging and supports_charging:
		charge_time += delta
		charge_time = min(charge_time, max_charge_time)

		var prev_charge_level: int = charge_level
		if charge_time >= 2.0:
			charge_level = 3
		elif charge_time >= 1.0:
			charge_level = 2
		else:
			charge_level = 1

		# PERF: Only update particle properties when charge level changes (not every frame)
		if charge_level != prev_charge_level:
			update_charge_visuals()
		elif charge_particles and player:
			# Just update position every frame (cheap)
			charge_particles.global_position = player.global_position

## Called when the ability is picked up by a player
func pickup(p_player: Node) -> void:
	player = p_player
	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Player picked up: %s" % ability_name, false, get_entity_id())

## Called when the ability is dropped by the player
func drop() -> void:
	player = null
	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Player dropped: %s" % ability_name, false, get_entity_id())

## Called when the player uses the ability
func use() -> void:
	if is_on_cooldown:
		return

	# Call the specific ability implementation
	activate()

	# Start cooldown
	is_on_cooldown = true
	cooldown_timer = cooldown_time

## Override this in specific abilities
func activate() -> void:
	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Ability activated: %s" % ability_name)

## Check if the ability is ready to use
func is_ready() -> bool:
	return not is_on_cooldown

## Start charging the ability
func start_charge() -> void:
	if not supports_charging or is_on_cooldown:
		return

	is_charging = true
	charge_time = 0.0
	charge_level = 1

	# Enable charge particles
	if charge_particles:
		charge_particles.emitting = true
		if player:
			charge_particles.global_position = player.global_position

	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Started charging %s" % ability_name, false, get_entity_id())

## Stop charging and release the ability
func release_charge() -> void:
	if not is_charging:
		return

	is_charging = false

	# Disable charge particles
	if charge_particles:
		charge_particles.emitting = false

	# Activate ability with charge multiplier
	activate()

	# Start cooldown
	is_on_cooldown = true
	cooldown_timer = cooldown_time

	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Released %s at charge level %d (%.1fs)" % [ability_name, charge_level, charge_time], false, get_entity_id())

	# Reset charge
	charge_time = 0.0
	charge_level = 1

## Cancel charging without activating
func cancel_charge() -> void:
	is_charging = false
	charge_time = 0.0
	charge_level = 1

	# Disable charge particles
	if charge_particles:
		charge_particles.emitting = false

## Get the damage/effect multiplier based on charge level
func get_charge_multiplier() -> float:
	match charge_level:
		1: return 1.0  # Weak
		2: return 2.0  # Medium
		3: return 3.0  # Max
		_: return 1.0

## Update visual effects based on charge level
func update_charge_visuals() -> void:
	if not charge_particles or not player:
		return

	# Update particle position to follow player
	charge_particles.global_position = player.global_position

	# Scale particle intensity based on charge level
	# PERF: Halved particle counts on web for HTML5 performance
	var web_mult: int = 1 if not _is_web else 2
	match charge_level:
		1:  # Weak - dim glow
			charge_particles.amount = 15 / web_mult
			charge_particles.scale_amount_min = 1.0
			charge_particles.scale_amount_max = 1.5
			charge_particles.initial_velocity_min = 1.0
			charge_particles.initial_velocity_max = 2.0
		2:  # Medium - bright pulse
			charge_particles.amount = 30 / web_mult
			charge_particles.scale_amount_min = 1.5
			charge_particles.scale_amount_max = 2.5
			charge_particles.initial_velocity_min = 2.0
			charge_particles.initial_velocity_max = 4.0
		3:  # Max - explosion aura
			charge_particles.amount = 50 / web_mult
			charge_particles.scale_amount_min = 2.0
			charge_particles.scale_amount_max = 4.0
			charge_particles.initial_velocity_min = 3.0
			charge_particles.initial_velocity_max = 6.0

			# Add camera shake for max charge
			if player and player.has_method("add_camera_shake"):
				player.add_camera_shake(0.05)
