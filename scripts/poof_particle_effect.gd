extends Node3D

## POOF Particle Effect
## Creates a puffy cloud effect when new areas appear

var particles: GPUParticles3D = null

func _ready() -> void:
	create_poof_effect()

func create_poof_effect() -> void:
	"""Create a puffy POOF particle effect"""
	particles = GPUParticles3D.new()
	particles.name = "PoofParticles"
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 500  # Increased for denser, more impressive effect
	particles.lifetime = 2.0  # Longer lifetime for more impact
	particles.explosiveness = 0.95  # Slight variation for more organic feel
	particles.randomness = 0.9
	add_child(particles)

	# Create particle process material
	var material = ParticleProcessMaterial.new()

	# Emission shape - sphere for puffy cloud effect
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 3.0  # Tighter initial sphere

	# Direction - expand outward in all directions
	material.direction = Vector3(0, 1, 0)
	material.spread = 180.0  # Full sphere spread

	# Initial velocity - more dramatic explosion
	material.initial_velocity_min = 12.0
	material.initial_velocity_max = 25.0

	# Gravity - very slight upward float for magical feel
	material.gravity = Vector3(0, -1.0, 0)

	# Damping - smooth deceleration
	material.damping_min = 4.0
	material.damping_max = 7.0

	# Turbulence - add swirling motion for more organic feel
	material.turbulence_enabled = true
	material.turbulence_noise_strength = 2.5
	material.turbulence_noise_scale = 4.0
	material.turbulence_influence_min = 0.3
	material.turbulence_influence_max = 0.6

	# Scale - dynamic size changes
	material.scale_min = 1.5
	material.scale_max = 4.5
	material.scale_curve = create_scale_curve()

	# Rotation - add spin for more visual interest
	material.angle_min = -180.0
	material.angle_max = 180.0
	material.angular_velocity_min = -90.0
	material.angular_velocity_max = 90.0

	# Color - vibrant gradient with magical shimmer
	material.color = Color(1.0, 1.0, 1.0, 1.0)
	material.color_ramp = create_color_ramp()

	particles.process_material = material

	# Create mesh for particles - use sphere for puffy look
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radial_segments = 12  # Smoother spheres
	sphere_mesh.rings = 6
	particles.draw_pass_1 = sphere_mesh

	print("POOF particle effect created")

func create_scale_curve() -> Curve:
	"""Create a curve for particle scale over lifetime"""
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.2))  # Start small
	curve.add_point(Vector2(0.15, 1.4))  # Quick expansion
	curve.add_point(Vector2(0.6, 1.2))  # Maintain size
	curve.add_point(Vector2(0.85, 0.8))  # Begin shrinking
	curve.add_point(Vector2(1.0, 0.0))  # Fade to nothing
	return curve

func create_color_ramp() -> Gradient:
	"""Create a color gradient for particle fade with magical shimmer"""
	var gradient = Gradient.new()
	# Start bright white with full opacity
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	# Shift to pale cyan shimmer
	gradient.add_point(0.3)
	gradient.set_color(1, Color(0.85, 0.95, 1.0, 0.9))
	# Warm golden glow in middle
	gradient.add_point(0.6)
	gradient.set_color(2, Color(1.0, 0.95, 0.85, 0.7))
	# Fade to soft blue-white
	gradient.add_point(0.85)
	gradient.set_color(3, Color(0.9, 0.95, 1.0, 0.3))
	# Finally transparent
	gradient.set_color(4, Color(1.0, 1.0, 1.0, 0.0))
	return gradient

func play_poof() -> void:
	"""Play the POOF effect"""
	if particles:
		particles.emitting = true
		print("POOF effect playing at position: ", global_position)
		# Auto-cleanup after effect finishes
		await get_tree().create_timer(particles.lifetime + 0.5).timeout
		queue_free()

func play_at_position(pos: Vector3) -> void:
	"""Play the POOF effect at a specific position"""
	global_position = pos
	play_poof()
