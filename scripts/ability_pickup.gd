extends Area3D

## Ability pickup that grants players a Kirby-style ability
## Randomly spawns after being collected

@export var ability_scene: PackedScene  # The ability to grant
@export var ability_name: String = "Unknown Ability"
@export var ability_color: Color = Color.WHITE

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
var aura_particles: CPUParticles3D

func _ready() -> void:
	# Add to ability pickups group for bot AI
	add_to_group("ability_pickups")

	# Store initial height
	base_height = global_position.y

	# Set up collision detection
	body_entered.connect(_on_body_entered)

	# Set up visual appearance
	if mesh_instance and mesh_instance.mesh:
		# Create glowing material based on ability color
		glow_material = StandardMaterial3D.new()
		glow_material.albedo_color = ability_color
		glow_material.emission_enabled = true
		glow_material.emission = ability_color
		glow_material.emission_energy_multiplier = 2.5
		glow_material.metallic = 0.5
		glow_material.roughness = 0.1
		mesh_instance.material_override = glow_material

	# Randomize starting animation phase
	time = randf() * TAU

	# Set up aura particle effect for better visibility
	if not aura_particles:
		aura_particles = CPUParticles3D.new()
		aura_particles.name = "AuraParticles"
		add_child(aura_particles)

		# Configure aura particles
		aura_particles.emitting = true
		aura_particles.amount = 15
		aura_particles.lifetime = 1.2
		aura_particles.explosiveness = 0.0
		aura_particles.randomness = 0.4
		aura_particles.local_coords = true

		# Set up particle mesh
		var particle_mesh: QuadMesh = QuadMesh.new()
		particle_mesh.size = Vector2(0.2, 0.2)
		aura_particles.mesh = particle_mesh

		# Create glowing material for aura
		var particle_material: StandardMaterial3D = StandardMaterial3D.new()
		particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		particle_material.vertex_color_use_as_albedo = true
		particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		particle_material.disable_receive_shadows = true
		aura_particles.mesh.material = particle_material

		# Emission shape - sphere around pickup
		aura_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		aura_particles.emission_sphere_radius = 0.7

		# Movement - gentle floating
		aura_particles.direction = Vector3.UP
		aura_particles.spread = 30.0
		aura_particles.gravity = Vector3(0, -0.5, 0)
		aura_particles.initial_velocity_min = 0.4
		aura_particles.initial_velocity_max = 1.0

		# Size over lifetime
		aura_particles.scale_amount_min = 1.0
		aura_particles.scale_amount_max = 1.5
		aura_particles.scale_amount_curve = Curve.new()
		aura_particles.scale_amount_curve.add_point(Vector2(0, 0.3))
		aura_particles.scale_amount_curve.add_point(Vector2(0.5, 1.0))
		aura_particles.scale_amount_curve.add_point(Vector2(1, 0.1))

		# Color - use ability color with glow
		var gradient: Gradient = Gradient.new()
		gradient.add_point(0.0, Color(ability_color.r, ability_color.g, ability_color.b, 0.7))
		gradient.add_point(0.5, Color(ability_color.r * 1.2, ability_color.g * 1.2, ability_color.b * 1.2, 0.5))
		gradient.add_point(1.0, Color(ability_color.r, ability_color.g, ability_color.b, 0.0))
		aura_particles.color_ramp = gradient

func _process(delta: float) -> void:
	if is_collected:
		# Handle respawn timer
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			respawn_pickup()
		return

	# Update animation time
	time += delta

	# Bob up and down
	var new_pos: Vector3 = global_position
	new_pos.y = base_height + sin(time * bob_speed) * bob_amount
	global_position = new_pos

	# Rotate
	if mesh_instance:
		mesh_instance.rotation.y += rotation_speed * delta
		mesh_instance.rotation.x = sin(time * 1.5) * 0.2  # Slight tilt

		# Pulse emission
		if glow_material:
			var pulse: float = 2.0 + sin(time * 4.0) * 0.5
			glow_material.emission_energy_multiplier = pulse

func _on_body_entered(body: Node3D) -> void:
	# Check if it's a player and not already collected
	if is_collected:
		return

	# Check if body is a player
	if body is RigidBody3D and body.has_method("pickup_ability"):
		collect(body)

func collect(player: Node) -> void:
	"""Handle ability pickup collection"""
	# Give player the ability
	if ability_scene:
		player.pickup_ability(ability_scene, ability_name)
	else:
		print("Warning: Ability pickup has no ability_scene assigned!")

	# Play pickup sound
	if pickup_sound and pickup_sound.stream:
		play_pickup_sound.rpc()

	# Mark as collected
	is_collected = true
	respawn_timer = respawn_time

	# Hide the pickup
	if mesh_instance:
		mesh_instance.visible = false
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if aura_particles:
		aura_particles.emitting = false

	print("Ability '%s' collected by player! Respawning in %.1f seconds" % [ability_name, respawn_time])

func respawn_pickup() -> void:
	"""Respawn the ability pickup"""
	is_collected = false

	# Show the pickup again
	if mesh_instance:
		mesh_instance.visible = true
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	if aura_particles:
		aura_particles.emitting = true

	# Reset animation phase slightly for variety
	time += randf() * 2.0

	print("Ability pickup '%s' respawned!" % ability_name)

@rpc("call_local")
func play_pickup_sound() -> void:
	"""Play pickup sound effect"""
	if pickup_sound and pickup_sound.stream:
		pickup_sound.pitch_scale = randf_range(1.0, 1.2)
		pickup_sound.play()
