extends Node3D

## Star Trek-style Beam Spawn Effect
## Creates a smooth transporter beam effect with particles rising from below

var beam_particles: GPUParticles3D = null
var glow_particles: GPUParticles3D = null

func _ready() -> void:
	create_beam_effect()

func create_beam_effect() -> void:
	"""Create a smooth Star Trek-style beam spawn effect (HTML5-optimized)"""
	# Main beam particles - rising column of light
	beam_particles = GPUParticles3D.new()
	beam_particles.name = "BeamParticles"
	beam_particles.emitting = false
	beam_particles.one_shot = true
	beam_particles.amount = 50  # Reduced from 150 for HTML5 performance
	beam_particles.lifetime = 1.0  # Reduced from 1.2 for faster cleanup
	beam_particles.explosiveness = 0.0  # Continuous emission over time
	beam_particles.randomness = 0.3
	add_child(beam_particles)

	# Create particle process material for main beam
	var material = ParticleProcessMaterial.new()

	# Emission shape - box (tall and narrow) for beam effect
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(1.5, 4.0, 1.5)  # Wide base, tall height

	# Direction - upward with slight inward convergence
	material.direction = Vector3(0, 1, 0)
	material.spread = 15.0  # Slight spread for natural beam look

	# Initial velocity - rising upward
	material.initial_velocity_min = 6.0
	material.initial_velocity_max = 10.0

	# Gravity - slight upward pull for beam effect
	material.gravity = Vector3(0, 5.0, 0)

	# Damping - particles slow down as they rise
	material.damping_min = 1.5
	material.damping_max = 2.5

	# Radial accel - pull particles toward center for beam convergence
	material.radial_accel_min = -8.0
	material.radial_accel_max = -12.0

	# Scale - start medium and fade out
	material.scale_min = 0.3
	material.scale_max = 0.5
	material.scale_curve = create_scale_curve()

	# Color - bright blue-white transporter beam with glow
	material.color = Color(0.6, 0.8, 1.0, 0.9)  # Light blue
	material.color_ramp = create_color_ramp()

	beam_particles.process_material = material

	# Use circular texture for smooth appearance (no jagged edges)
	var particle_material = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # Self-illuminated
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.albedo_texture = load("res://textures/kenney_particle_pack/circle_05.png")
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD  # Additive blending for glow

	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(1.0, 1.0)
	quad_mesh.material = particle_material
	beam_particles.draw_pass_1 = quad_mesh

	# Create secondary glow particles for extra shine
	create_glow_particles()

	print("Beam spawn effect created")

func create_glow_particles() -> void:
	"""Create additional glow particles for enhanced beam effect (HTML5-optimized)"""
	glow_particles = GPUParticles3D.new()
	glow_particles.name = "GlowParticles"
	glow_particles.emitting = false
	glow_particles.one_shot = true
	glow_particles.amount = 25  # Reduced from 80 for HTML5 performance
	glow_particles.lifetime = 1.0  # Reduced from 1.2 for faster cleanup
	glow_particles.explosiveness = 0.0
	glow_particles.randomness = 0.4
	add_child(glow_particles)

	# Create particle process material for glow
	var material = ParticleProcessMaterial.new()

	# Emission shape - box (tall and narrow) for beam effect
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(1.2, 4.0, 1.2)  # Slightly smaller than main beam

	# Direction - upward
	material.direction = Vector3(0, 1, 0)
	material.spread = 20.0

	# Initial velocity - slower rising
	material.initial_velocity_min = 4.0
	material.initial_velocity_max = 7.0

	# Gravity - upward pull
	material.gravity = Vector3(0, 4.0, 0)

	# Damping
	material.damping_min = 2.0
	material.damping_max = 3.0

	# Radial accel - strong convergence
	material.radial_accel_min = -10.0
	material.radial_accel_max = -15.0

	# Scale - larger glow particles
	material.scale_min = 0.6
	material.scale_max = 1.0
	material.scale_curve = create_glow_scale_curve()

	# Color - bright white-blue glow
	material.color = Color(0.8, 0.9, 1.0, 0.7)
	material.color_ramp = create_glow_color_ramp()

	glow_particles.process_material = material

	# Use star texture for glow variation
	var particle_material = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.albedo_texture = load("res://textures/kenney_particle_pack/star_05.png")
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD  # Additive for glow

	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(1.0, 1.0)
	quad_mesh.material = particle_material
	glow_particles.draw_pass_1 = quad_mesh

func create_scale_curve() -> Curve:
	"""Create a curve for particle scale over lifetime (simplified for HTML5)"""
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.5))  # Start small
	curve.add_point(Vector2(0.4, 1.0))  # Grow quickly
	curve.add_point(Vector2(1.0, 0.0))  # Fade to nothing
	return curve

func create_glow_scale_curve() -> Curve:
	"""Create a curve for glow particle scale (simplified for HTML5)"""
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.3))  # Start small
	curve.add_point(Vector2(0.3, 1.0))  # Grow fast
	curve.add_point(Vector2(1.0, 0.0))  # Fade out
	return curve

func create_color_ramp() -> Gradient:
	"""Create a color gradient for beam particles (simplified for HTML5)"""
	var gradient = Gradient.new()
	# Start with transparent blue
	gradient.set_color(0, Color(0.6, 0.8, 1.0, 0.0))
	# Peak brightness
	gradient.set_color(0.5, Color(0.7, 0.9, 1.0, 0.9))
	# Fade to transparent
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	return gradient

func create_glow_color_ramp() -> Gradient:
	"""Create a color gradient for glow particles (simplified for HTML5)"""
	var gradient = Gradient.new()
	# Start transparent
	gradient.set_color(0, Color(0.8, 0.9, 1.0, 0.0))
	# Peak brightness
	gradient.set_color(0.4, Color(1.0, 1.0, 1.0, 0.7))
	# Fade to transparent
	gradient.set_color(1, Color(0.8, 0.9, 1.0, 0.0))
	return gradient

func play_beam() -> void:
	"""Play the beam spawn effect"""
	if beam_particles and glow_particles:
		beam_particles.emitting = true
		glow_particles.emitting = true
		print("Beam spawn effect playing at position: ", global_position)
		# Auto-cleanup after effect finishes
		await get_tree().create_timer(beam_particles.lifetime + 0.5).timeout
		queue_free()

func play_at_position(pos: Vector3) -> void:
	"""Play the beam effect at a specific position"""
	global_position = pos
	play_beam()
