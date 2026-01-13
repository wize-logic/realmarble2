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

# Visual effects
var glow_material: StandardMaterial3D
var aura_particles: CPUParticles3D

func _ready() -> void:
	# Add to orbs group for bot AI
	add_to_group("orbs")

	# Store initial height
	base_height = global_position.y

	# Set up collision detection
	body_entered.connect(_on_body_entered)

	# Set up visual appearance if mesh exists
	if mesh_instance and mesh_instance.mesh:
		# Create glowing material for orb
		glow_material = StandardMaterial3D.new()
		glow_material.albedo_color = Color(0.3, 0.7, 1.0, 1.0)  # Cyan/blue color
		glow_material.emission_enabled = true
		glow_material.emission = Color(0.5, 0.8, 1.0)
		glow_material.emission_energy_multiplier = 2.0
		glow_material.metallic = 0.3
		glow_material.roughness = 0.2
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
		aura_particles.amount = 20
		aura_particles.lifetime = 1.5
		aura_particles.explosiveness = 0.0
		aura_particles.randomness = 0.3
		aura_particles.local_coords = true

		# Set up particle mesh
		var particle_mesh: QuadMesh = QuadMesh.new()
		particle_mesh.size = Vector2(0.15, 0.15)
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

		# Emission shape - sphere around orb
		aura_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		aura_particles.emission_sphere_radius = 0.6

		# Movement - gentle sparkle effect
		aura_particles.direction = Vector3.UP
		aura_particles.spread = 45.0
		aura_particles.gravity = Vector3(0, -0.3, 0)
		aura_particles.initial_velocity_min = 0.5
		aura_particles.initial_velocity_max = 1.2

		# Size over lifetime
		aura_particles.scale_amount_min = 1.2
		aura_particles.scale_amount_max = 1.8
		aura_particles.scale_amount_curve = Curve.new()
		aura_particles.scale_amount_curve.add_point(Vector2(0, 0.5))
		aura_particles.scale_amount_curve.add_point(Vector2(0.3, 1.0))
		aura_particles.scale_amount_curve.add_point(Vector2(1, 0.0))

		# Color - cyan sparkle effect
		var gradient: Gradient = Gradient.new()
		gradient.add_point(0.0, Color(0.7, 1.0, 1.0, 0.8))  # Bright cyan
		gradient.add_point(0.5, Color(0.4, 0.9, 1.0, 0.6))  # Cyan
		gradient.add_point(1.0, Color(0.2, 0.5, 0.8, 0.0))  # Dark transparent
		aura_particles.color_ramp = gradient

func _process(delta: float) -> void:
	if is_collected:
		# Handle respawn timer
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			respawn_orb()
		return

	# Update animation time
	time += delta

	# Bob up and down
	var new_pos: Vector3 = global_position
	new_pos.y = base_height + sin(time * bob_speed) * bob_amount
	global_position = new_pos

	# Rotate slowly
	if mesh_instance:
		mesh_instance.rotation.y += rotation_speed * delta

		# Pulse emission for extra effect
		if glow_material:
			var pulse: float = 1.5 + sin(time * 3.0) * 0.5
			glow_material.emission_energy_multiplier = pulse

func _on_body_entered(body: Node3D) -> void:
	# Check if it's a player and not already collected
	if is_collected:
		return

	# Check if body is a player (RigidBody3D with player script)
	if body is RigidBody3D and body.has_method("collect_orb"):
		# Check if player can still level up
		if "level" in body and "MAX_LEVEL" in body:
			if body.level < body.MAX_LEVEL:
				collect(body)
		else:
			# Fallback - just collect it
			collect(body)

func collect(player: Node) -> void:
	"""Handle orb collection"""
	# Call player's collect method
	player.collect_orb()

	# Play collection sound
	if collection_sound and collection_sound.stream:
		play_collection_sound.rpc()

	# Mark as collected
	is_collected = true
	respawn_timer = respawn_time

	# Hide the orb
	if mesh_instance:
		mesh_instance.visible = false
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if aura_particles:
		aura_particles.emitting = false

	print("Orb collected by player! Respawning in %.1f seconds" % respawn_time)

func respawn_orb() -> void:
	"""Respawn the orb"""
	is_collected = false

	# Show the orb again
	if mesh_instance:
		mesh_instance.visible = true
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	if aura_particles:
		aura_particles.emitting = true

	# Reset animation phase slightly for variety
	time += randf() * 2.0

	print("Orb respawned!")

@rpc("call_local")
func play_collection_sound() -> void:
	"""Play collection sound effect"""
	if collection_sound and collection_sound.stream:
		collection_sound.pitch_scale = randf_range(0.9, 1.1)
		collection_sound.play()
