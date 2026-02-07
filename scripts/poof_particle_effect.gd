extends Node3D

## Simple POOF Particle Effect
## Lightweight cloud puff when areas appear

var particles: CPUParticles3D = null

func _ready() -> void:
	create_poof_effect()

func create_poof_effect() -> void:
	"""Create a simple poof particle effect"""
	particles = CPUParticles3D.new()
	particles.name = "PoofParticles"
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 15
	particles.lifetime = 1.0
	particles.explosiveness = 1.0
	particles.randomness = 0.6
	add_child(particles)

	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 3.0
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 180.0
	particles.initial_velocity_min = 5.0
	particles.initial_velocity_max = 10.0
	particles.gravity = Vector3(0, -2.0, 0)
	particles.damping_min = 3.0
	particles.damping_max = 5.0
	particles.scale_amount_min = 1.5
	particles.scale_amount_max = 3.0
	particles.color = Color(0.9, 0.88, 0.85, 0.6)

	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(1.0, 1.0)
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	quad_mesh.material = mat
	particles.mesh = quad_mesh

	print("POOF particle effect created")

func play_poof() -> void:
	"""Play the POOF effect"""
	if particles:
		particles.emitting = true
		print("POOF effect playing at position: ", global_position)
		await get_tree().create_timer(particles.lifetime + 0.5).timeout
		queue_free()

func play_at_position(pos: Vector3) -> void:
	"""Play the POOF effect at a specific position"""
	global_position = pos
	play_poof()
