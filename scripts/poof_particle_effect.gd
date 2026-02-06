extends Node3D

## POOF Particle Effect
## Creates a puffy cloud effect when new areas appear

var particles: GPUParticles3D = null
var _is_web: bool = false

func _ready() -> void:
	_is_web = OS.has_feature("web")
	create_poof_effect()

func create_poof_effect() -> void:
	"""Create a puffy POOF particle effect"""
	particles = GPUParticles3D.new()
	particles.name = "PoofParticles"
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 50 if _is_web else 200
	particles.lifetime = 1.5
	particles.explosiveness = 1.0  # All particles emit at once
	particles.randomness = 0.8
	add_child(particles)

	# Create particle process material
	var material = ParticleProcessMaterial.new()

	# Emission shape - sphere for puffy cloud effect
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 5.0

	# Direction - expand outward in all directions
	material.direction = Vector3(0, 1, 0)
	material.spread = 180.0  # Full sphere spread

	# Initial velocity - moderate outward explosion
	material.initial_velocity_min = 8.0
	material.initial_velocity_max = 15.0

	# Gravity - slight upward float for puffy cloud feel
	material.gravity = Vector3(0, -2.0, 0)

	# Damping - slow down particles for puffy feel
	material.damping_min = 3.0
	material.damping_max = 5.0

	# Scale - start large and grow even larger
	material.scale_min = 2.0
	material.scale_max = 4.0
	material.scale_curve = create_scale_curve()

	# Color - soft cream-tinted puffy cloud (no pure white)
	material.color = Color(0.95, 0.92, 0.88, 0.85)
	material.color_ramp = create_color_ramp()

	particles.process_material = material

	# Create mesh for particles - QuadMesh on web (2 tris), SphereMesh on desktop
	if _is_web:
		var quad_mesh = QuadMesh.new()
		quad_mesh.size = Vector2(1.0, 1.0)
		particles.draw_pass_1 = quad_mesh
	else:
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radial_segments = 8
		sphere_mesh.rings = 4
		particles.draw_pass_1 = sphere_mesh

	print("POOF particle effect created")

func create_scale_curve() -> Curve:
	"""Create a curve for particle scale over lifetime"""
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 1.0))  # Start at full scale
	curve.add_point(Vector2(0.5, 1.3))  # Grow slightly
	curve.add_point(Vector2(1.0, 0.0))  # Fade to nothing
	return curve

func create_color_ramp() -> Gradient:
	"""Create a color gradient for particle fade"""
	var gradient = Gradient.new()
	# Start soft cream and opaque (no pure white)
	gradient.set_color(0, Color(0.95, 0.92, 0.88, 0.85))
	# Fade to transparent warm gray
	gradient.set_color(1, Color(0.9, 0.88, 0.85, 0.0))
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
