extends Node3D
class_name Ability

## Base class for all Kirby-style abilities
## Abilities can be picked up, used, and dropped by players

@export var ability_name: String = "Ability"
@export var ability_color: Color = Color.WHITE
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

func _ready() -> void:
	# Create charge particles if charging is supported
	if supports_charging:
		charge_particles = CPUParticles3D.new()
		charge_particles.name = "ChargeParticles"
		add_child(charge_particles)

		# Configure charge particles - beautiful magical energy glow
		charge_particles.emitting = false
		charge_particles.amount = 8  # Reduced by 90% for HTML5
		charge_particles.lifetime = 1.0  # Longer lifetime
		charge_particles.explosiveness = 0.0  # Continuous emission
		charge_particles.randomness = 0.4
		charge_particles.local_coords = true

		# Set up particle mesh - larger for more visibility
		var particle_mesh: QuadMesh = QuadMesh.new()
		particle_mesh.size = Vector2(0.6, 0.6)  # Larger to compensate
		charge_particles.mesh = particle_mesh

		# Create material for particles with enhanced glow
		var particle_material: StandardMaterial3D = StandardMaterial3D.new()
		particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		particle_material.vertex_color_use_as_albedo = true
		particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		particle_material.disable_receive_shadows = true
		particle_material.albedo_texture = load("res://textures/kenney_particle_pack/circle_05.png")
		charge_particles.mesh.material = particle_material

		# Emission shape - ring around ability for energy focus
		charge_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		charge_particles.emission_ring_axis = Vector3.UP
		charge_particles.emission_ring_height = 0.5
		charge_particles.emission_ring_radius = 1.2
		charge_particles.emission_ring_inner_radius = 0.8

		# Movement - swirling orbital motion
		charge_particles.direction = Vector3(0, 1, 0)
		charge_particles.spread = 25.0  # More focused
		charge_particles.gravity = Vector3(0, -0.5, 0)  # Gentle float
		charge_particles.initial_velocity_min = 1.5
		charge_particles.initial_velocity_max = 3.0

		# Add damping for graceful motion
		charge_particles.damping_min = 0.5
		charge_particles.damping_max = 1.5

		# Rotation for spinning particles
		charge_particles.angle_min = -180.0
		charge_particles.angle_max = 180.0
		charge_particles.angular_velocity_min = -90.0
		charge_particles.angular_velocity_max = 90.0

		# Size - will scale with charge level
		charge_particles.scale_amount_min = 1.5
		charge_particles.scale_amount_max = 2.5

		# Color - vibrant ability color with magical shimmer
		var gradient: Gradient = Gradient.new()
		gradient.add_point(0.0, ability_color * 1.8)  # Bright start
		gradient.add_point(0.3, ability_color * 1.4)  # Maintain brightness
		gradient.add_point(0.6, ability_color * 1.0)  # Base color
		gradient.add_point(0.85, ability_color * 0.6)  # Dim
		gradient.add_point(1.0, Color(ability_color.r, ability_color.g, ability_color.b, 0.0))  # Fade
		charge_particles.color_ramp = gradient

func _process(delta: float) -> void:
	# Handle cooldown
	if is_on_cooldown:
		cooldown_timer -= delta
		if cooldown_timer <= 0.0:
			is_on_cooldown = false

	# Handle charging
	if is_charging and supports_charging:
		charge_time += delta
		charge_time = min(charge_time, max_charge_time)

		# Update charge level based on time
		if charge_time >= 2.0:
			charge_level = 3  # Max charge
		elif charge_time >= 1.0:
			charge_level = 2  # Medium charge
		else:
			charge_level = 1  # Weak charge

		# Update particle effects based on charge level
		update_charge_visuals()

## Called when the ability is picked up by a player
func pickup(p_player: Node) -> void:
	player = p_player
	print("Player picked up: ", ability_name)

## Called when the ability is dropped by the player
func drop() -> void:
	player = null
	print("Player dropped: ", ability_name)

## Called when the player uses the ability
func use() -> void:
	if is_on_cooldown:
		print("Ability on cooldown! %.1fs remaining" % cooldown_timer)
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

	print("Started charging %s" % ability_name)

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

	print("Released %s at charge level %d (%.1fs)" % [ability_name, charge_level, charge_time])

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

	# Scale particle intensity based on charge level - dramatic escalation
	match charge_level:
		1:  # Weak - gentle magical glow
			charge_particles.amount = 5  # Reduced by 90% for HTML5
			charge_particles.scale_amount_min = 1.5
			charge_particles.scale_amount_max = 2.0
			charge_particles.initial_velocity_min = 1.5
			charge_particles.initial_velocity_max = 3.0
			charge_particles.emission_ring_radius = 1.0
			charge_particles.lifetime = 0.8
		2:  # Medium - intensifying energy pulse
			charge_particles.amount = 10  # Reduced by 90% for HTML5
			charge_particles.scale_amount_min = 2.0
			charge_particles.scale_amount_max = 3.5
			charge_particles.initial_velocity_min = 2.5
			charge_particles.initial_velocity_max = 5.0
			charge_particles.emission_ring_radius = 1.4
			charge_particles.lifetime = 1.0
		3:  # Max - spectacular power surge
			charge_particles.amount = 18  # Reduced by 90% for HTML5
			charge_particles.scale_amount_min = 3.0
			charge_particles.scale_amount_max = 5.5
			charge_particles.initial_velocity_min = 4.0
			charge_particles.initial_velocity_max = 8.0
			charge_particles.emission_ring_radius = 1.8
			charge_particles.lifetime = 1.2

			# Add camera shake for max charge
			if player and player.has_method("add_camera_shake"):
				player.add_camera_shake(0.05)
