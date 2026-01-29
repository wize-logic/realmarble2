extends Node3D

## Marble Visual Effects Manager
## Adds trail particles and impact effects to marbles
## Designed for GL Compatibility renderer (WebGL2)

# Trail particles
var trail_particles: GPUParticles3D = null
var speed_trail_particles: GPUParticles3D = null

# Impact effect pool
var impact_pool: Array[GPUParticles3D] = []
const IMPACT_POOL_SIZE: int = 3

# Parent marble reference
var marble_body: RigidBody3D = null
var marble_color: Color = Color(0.6, 0.8, 1.0)  # Default cyan

# Speed thresholds
const TRAIL_SPEED_MIN: float = 5.0  # Minimum speed to show trail
const SPEED_TRAIL_MIN: float = 15.0  # Speed for enhanced trail
const IMPACT_SPEED_MIN: float = 8.0  # Minimum speed for impact effect

# State tracking
var last_velocity: Vector3 = Vector3.ZERO
var current_impact_index: int = 0

func _ready() -> void:
	# Find parent marble
	marble_body = get_parent() as RigidBody3D
	if not marble_body:
		push_warning("MarbleEffects: Parent is not a RigidBody3D")
		return

	create_trail_particles()
	create_speed_trail_particles()
	create_impact_pool()

func set_marble_color(color: Color) -> void:
	"""Set the marble's color for trail effects"""
	marble_color = color
	update_trail_colors()

func update_trail_colors() -> void:
	"""Update trail particle colors to match marble"""
	if trail_particles and trail_particles.process_material:
		var mat: ParticleProcessMaterial = trail_particles.process_material
		mat.color = Color(marble_color.r, marble_color.g, marble_color.b, 0.6)

	if speed_trail_particles and speed_trail_particles.process_material:
		var mat: ParticleProcessMaterial = speed_trail_particles.process_material
		var bright_color = marble_color.lightened(0.3)
		mat.color = Color(bright_color.r, bright_color.g, bright_color.b, 0.8)

func create_trail_particles() -> void:
	"""Create the basic trail particle effect"""
	trail_particles = GPUParticles3D.new()
	trail_particles.name = "TrailParticles"
	trail_particles.emitting = false
	trail_particles.amount = 20  # Light for HTML5
	trail_particles.lifetime = 0.4
	trail_particles.explosiveness = 0.0
	trail_particles.randomness = 0.2
	trail_particles.local_coords = false
	add_child(trail_particles)

	var mat = ParticleProcessMaterial.new()

	# Emission from point behind marble
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT

	# Direction - inherit marble velocity
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.5

	# Gravity - slight float
	mat.gravity = Vector3(0, 1.0, 0)

	# Damping
	mat.damping_min = 2.0
	mat.damping_max = 4.0

	# Scale
	mat.scale_min = 0.15
	mat.scale_max = 0.25
	mat.scale_curve = create_fade_curve()

	# Color - marble tinted (no white)
	mat.color = Color(marble_color.r, marble_color.g, marble_color.b, 0.6)
	mat.color_ramp = create_trail_gradient()

	trail_particles.process_material = mat

	# Create mesh
	var mesh_mat = StandardMaterial3D.new()
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	var quad = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = mesh_mat
	trail_particles.draw_pass_1 = quad

func create_speed_trail_particles() -> void:
	"""Create enhanced speed trail for fast movement"""
	speed_trail_particles = GPUParticles3D.new()
	speed_trail_particles.name = "SpeedTrailParticles"
	speed_trail_particles.emitting = false
	speed_trail_particles.amount = 30  # Light for HTML5
	speed_trail_particles.lifetime = 0.3
	speed_trail_particles.explosiveness = 0.0
	speed_trail_particles.randomness = 0.15
	speed_trail_particles.local_coords = false
	add_child(speed_trail_particles)

	var mat = ParticleProcessMaterial.new()

	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.3

	mat.direction = Vector3(0, 0, 0)
	mat.spread = 15.0
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 0.8

	mat.gravity = Vector3(0, 0.5, 0)
	mat.damping_min = 3.0
	mat.damping_max = 5.0

	mat.scale_min = 0.2
	mat.scale_max = 0.4
	mat.scale_curve = create_fade_curve()

	# Brighter color for speed (no white)
	var bright_color = marble_color.lightened(0.3)
	mat.color = Color(bright_color.r, bright_color.g, bright_color.b, 0.8)
	mat.color_ramp = create_speed_gradient()

	speed_trail_particles.process_material = mat

	# Create mesh
	var mesh_mat = StandardMaterial3D.new()
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	var quad = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = mesh_mat
	speed_trail_particles.draw_pass_1 = quad

func create_impact_pool() -> void:
	"""Create a pool of impact particle effects"""
	for i in range(IMPACT_POOL_SIZE):
		var impact = GPUParticles3D.new()
		impact.name = "ImpactParticles_%d" % i
		impact.emitting = false
		impact.one_shot = true
		impact.amount = 15  # Light for HTML5
		impact.lifetime = 0.35
		impact.explosiveness = 1.0
		impact.randomness = 0.4
		impact.local_coords = false
		add_child(impact)

		var mat = ParticleProcessMaterial.new()

		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		mat.emission_sphere_radius = 0.2

		mat.direction = Vector3(0, 1, 0)
		mat.spread = 120.0
		mat.initial_velocity_min = 3.0
		mat.initial_velocity_max = 6.0

		mat.gravity = Vector3(0, -8.0, 0)
		mat.damping_min = 1.5
		mat.damping_max = 3.0

		mat.scale_min = 0.15
		mat.scale_max = 0.3
		mat.scale_curve = create_fade_curve()

		# Impact color (warm spark, no white)
		mat.color = Color(1.0, 0.85, 0.5, 0.9)
		mat.color_ramp = create_impact_gradient()

		impact.process_material = mat

		# Create mesh
		var mesh_mat = StandardMaterial3D.new()
		mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mesh_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

		var quad = QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		quad.material = mesh_mat
		impact.draw_pass_1 = quad

		impact_pool.append(impact)

func create_fade_curve() -> Curve:
	"""Create a fade-out scale curve"""
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.8))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	return curve

func create_trail_gradient() -> Gradient:
	"""Create trail color gradient (no white)"""
	var gradient = Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(marble_color.r, marble_color.g, marble_color.b, 0.0))
	gradient.add_point(0.3, Color(marble_color.r, marble_color.g, marble_color.b, 0.6))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(marble_color.r * 0.6, marble_color.g * 0.6, marble_color.b * 0.6, 0.0))
	return gradient

func create_speed_gradient() -> Gradient:
	"""Create speed trail color gradient (no white)"""
	var gradient = Gradient.new()
	var bright = marble_color.lightened(0.2)
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(bright.r, bright.g, bright.b, 0.0))
	gradient.add_point(0.2, Color(bright.r, bright.g, bright.b, 0.8))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(marble_color.r * 0.5, marble_color.g * 0.5, marble_color.b * 0.5, 0.0))
	return gradient

func create_impact_gradient() -> Gradient:
	"""Create impact spark gradient (no white)"""
	var gradient = Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1.0, 0.9, 0.5, 0.9))  # Warm golden
	gradient.add_point(0.3, Color(1.0, 0.7, 0.3, 0.8))  # Orange
	gradient.add_point(0.7, Color(0.8, 0.4, 0.2, 0.4))  # Rust
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(0.4, 0.2, 0.1, 0.0))  # Fade
	return gradient

func _physics_process(_delta: float) -> void:
	if not marble_body:
		return

	var velocity = marble_body.linear_velocity
	var speed = velocity.length()

	# Update trail visibility based on speed
	if trail_particles:
		trail_particles.emitting = speed > TRAIL_SPEED_MIN

	if speed_trail_particles:
		speed_trail_particles.emitting = speed > SPEED_TRAIL_MIN

	# Check for impacts (sudden deceleration)
	var decel = (last_velocity - velocity).length()
	if decel > IMPACT_SPEED_MIN and speed < last_velocity.length() * 0.5:
		spawn_impact_effect(global_position)

	last_velocity = velocity

func spawn_impact_effect(pos: Vector3) -> void:
	"""Spawn an impact effect from the pool"""
	if impact_pool.is_empty():
		return

	var impact = impact_pool[current_impact_index]
	current_impact_index = (current_impact_index + 1) % IMPACT_POOL_SIZE

	impact.global_position = pos
	impact.restart()
	impact.emitting = true
