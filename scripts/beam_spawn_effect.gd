extends Node3D

## Simple Beam Spawn Effect
## Lightweight spawn indicator with minimal particles

var beam_particles: CPUParticles3D = null
static var _shared_beam_material: StandardMaterial3D = null

static func precache_resources() -> void:
	if _shared_beam_material != null:
		return
	_shared_beam_material = StandardMaterial3D.new()
	_shared_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shared_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shared_beam_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_shared_beam_material.vertex_color_use_as_albedo = true

func _ready() -> void:
	create_beam_effect()

func create_beam_effect() -> void:
	"""Create a simple spawn effect with minimal particles"""
	beam_particles = CPUParticles3D.new()
	beam_particles.name = "BeamParticles"
	beam_particles.emitting = false
	beam_particles.one_shot = true
	beam_particles.amount = 6
	beam_particles.lifetime = 0.8
	beam_particles.explosiveness = 0.8
	beam_particles.randomness = 0.3
	beam_particles.local_coords = false
	add_child(beam_particles)

	# Simple upward burst
	beam_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	beam_particles.emission_sphere_radius = 0.5
	beam_particles.direction = Vector3(0, 1, 0)
	beam_particles.spread = 30.0
	beam_particles.initial_velocity_min = 4.0
	beam_particles.initial_velocity_max = 8.0
	beam_particles.gravity = Vector3(0, 2.0, 0)
	beam_particles.damping_min = 2.0
	beam_particles.damping_max = 3.0
	beam_particles.scale_amount_min = 0.3
	beam_particles.scale_amount_max = 0.5
	beam_particles.color = Color(0.4, 0.7, 0.95, 0.8)

	# PERF: Share beam material across all instances
	if _shared_beam_material == null:
		precache_resources()

	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(0.5, 0.5)
	quad_mesh.material = _shared_beam_material
	beam_particles.mesh = quad_mesh

	DebugLogger.dlog(DebugLogger.Category.WORLD, "Beam spawn effect created")

func play_beam() -> void:
	"""Play the beam spawn effect"""
	if beam_particles:
		beam_particles.emitting = true
		DebugLogger.dlog(DebugLogger.Category.WORLD, "Beam spawn effect playing at position: %s" % global_position)
		await get_tree().create_timer(beam_particles.lifetime + 0.3).timeout
		queue_free()

func play_at_position(pos: Vector3) -> void:
	"""Play the beam effect at a specific position"""
	global_position = pos
	play_beam()
