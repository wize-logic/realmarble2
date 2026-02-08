extends Node3D
class_name Ability

## Base class for all Kirby-style abilities
## Abilities can be picked up, used, and dropped by players

@export var ability_name: String = "Ability"
@export var ability_color: Color = Color(0.7, 0.85, 1.0)  # Soft cyan default (no white)
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
	if not player.is_multiplayer_authority():
		return false
	return not (player.has_method("is_bot") and player.is_bot())

func _ready() -> void:
	# Create charge particles if charging is supported
	# PERF: Skip charge particles for bots on HTML5 - bots never charge abilities
	if supports_charging and not _is_bot_owner():
		charge_particles = CPUParticles3D.new()
		charge_particles.name = "ChargeParticles"
		add_child(charge_particles)

		# Configure charge particles - growing glow
		charge_particles.emitting = false
		charge_particles.amount = 50
		charge_particles.lifetime = 0.8
		charge_particles.explosiveness = 0.0  # Continuous emission
		charge_particles.randomness = 0.3
		charge_particles.local_coords = true

		# Set up particle mesh
		var particle_mesh: QuadMesh = QuadMesh.new()
		particle_mesh.size = Vector2(0.2, 0.2)
		charge_particles.mesh = particle_mesh

		# Create material for particles
		var particle_material: StandardMaterial3D = StandardMaterial3D.new()
		particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		particle_material.vertex_color_use_as_albedo = true
		particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		particle_material.disable_receive_shadows = true
		charge_particles.mesh.material = particle_material

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

		if charge_time >= 2.0:
			charge_level = 3
		elif charge_time >= 1.0:
			charge_level = 2
		else:
			charge_level = 1

		update_charge_visuals()

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
	print("Ability activated: ", ability_name)

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
	match charge_level:
		1:  # Weak - dim glow
			charge_particles.amount = 30
			charge_particles.scale_amount_min = 1.0
			charge_particles.scale_amount_max = 1.5
			charge_particles.initial_velocity_min = 1.0
			charge_particles.initial_velocity_max = 2.0
		2:  # Medium - bright pulse
			charge_particles.amount = 60
			charge_particles.scale_amount_min = 1.5
			charge_particles.scale_amount_max = 2.5
			charge_particles.initial_velocity_min = 2.0
			charge_particles.initial_velocity_max = 4.0
		3:  # Max - explosion aura
			charge_particles.amount = 100
			charge_particles.scale_amount_min = 2.0
			charge_particles.scale_amount_max = 4.0
			charge_particles.initial_velocity_min = 3.0
			charge_particles.initial_velocity_max = 6.0

			# Add camera shake for max charge
			if player and player.has_method("add_camera_shake"):
				player.add_camera_shake(0.05)
