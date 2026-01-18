extends Node
class_name GraphicsEnhancer

## Graphics Enhancement System
## Adds advanced visual effects to game objects while maintaining HTML5 compatibility
## Uses WebGL2/GLES3 compatible shaders and optimized particle systems

static func enhance_marble(marble: RigidBody3D, player_color: Color = Color(0.3, 0.5, 0.9)) -> void:
	"""Add advanced graphics to a marble player"""
	if not marble:
		return

	# Find mesh instance
	var mesh_instance: MeshInstance3D = null
	for child in marble.get_children():
		if child is MeshInstance3D:
			mesh_instance = child
			break

	if not mesh_instance:
		print("GraphicsEnhancer: No MeshInstance3D found on marble")
		return

	# Apply metallic marble shader
	var marble_material = ShaderMaterial.new()
	marble_material.shader = load("res://scripts/shaders/marble_metallic.gdshader")
	marble_material.set_shader_parameter("base_color", player_color)
	marble_material.set_shader_parameter("rim_color", player_color.lightened(0.3))
	marble_material.set_shader_parameter("rim_intensity", 2.5)
	marble_material.set_shader_parameter("rim_power", 3.0)
	marble_material.set_shader_parameter("metallic", 0.85)
	marble_material.set_shader_parameter("roughness", 0.15)
	marble_material.set_shader_parameter("emission_strength", 0.8)
	marble_material.set_shader_parameter("emission_color", player_color.lightened(0.2))
	marble_material.set_shader_parameter("pulse_speed", 1.5)
	marble_material.set_shader_parameter("pulse_strength", 0.3)
	mesh_instance.material_override = marble_material

	# Add player light
	var player_light = OmniLight3D.new()
	player_light.name = "PlayerLight"
	player_light.light_color = player_color.lightened(0.2)
	player_light.light_energy = 2.5
	player_light.omni_range = 8.0
	player_light.omni_attenuation = 2.0
	player_light.shadow_enabled = false  # Optimize for HTML5
	marble.add_child(player_light)

	print("GraphicsEnhancer: Enhanced marble with metallic shader and lighting")


static func add_movement_trail(marble: RigidBody3D, trail_color: Color = Color(0.5, 0.8, 1.0)) -> void:
	"""Add movement trail particles to marble"""
	if not marble:
		return

	# Create trail particles
	var trail_particles = GPUParticles3D.new()
	trail_particles.name = "MovementTrail"
	trail_particles.emitting = true
	trail_particles.amount = 50
	trail_particles.lifetime = 0.8
	trail_particles.one_shot = false
	trail_particles.explosiveness = 0.0
	trail_particles.randomness = 0.3
	trail_particles.visibility_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	marble.add_child(trail_particles)

	# Create particle material
	var material = ParticleProcessMaterial.new()
	material.direction = Vector3(0, 0, 1)  # Trail behind
	material.spread = 15.0
	material.initial_velocity_min = 0.5
	material.initial_velocity_max = 1.5
	material.gravity = Vector3(0, -1.0, 0)
	material.damping_min = 2.0
	material.damping_max = 4.0
	material.scale_min = 0.3
	material.scale_max = 0.6

	# Fade curve
	var scale_curve = Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.0))
	material.scale_curve = scale_curve

	# Color gradient
	var gradient = Gradient.new()
	gradient.set_color(0, trail_color)
	gradient.set_color(1, Color(trail_color.r, trail_color.g, trail_color.b, 0.0))
	material.color_ramp = gradient

	trail_particles.process_material = material

	# Use billboard quad for particles
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(0.5, 0.5)
	trail_particles.draw_pass_1 = quad_mesh

	# Create particle material with glow
	var particle_mat = StandardMaterial3D.new()
	particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_mat.albedo_color = trail_color
	particle_mat.emission_enabled = true
	particle_mat.emission = trail_color
	particle_mat.emission_energy_multiplier = 2.0
	particle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad_mesh.material = particle_mat

	print("GraphicsEnhancer: Added movement trail to marble")


static func create_spark_particles(parent: Node3D, position: Vector3 = Vector3.ZERO) -> GPUParticles3D:
	"""Create spark particles for grind rails and impacts"""
	var sparks = GPUParticles3D.new()
	sparks.name = "SparkParticles"
	sparks.position = position
	sparks.emitting = true
	sparks.amount = 30
	sparks.lifetime = 0.5
	sparks.one_shot = false
	sparks.explosiveness = 0.3
	sparks.randomness = 0.6
	sparks.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	parent.add_child(sparks)

	# Create spark material
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.5
	material.direction = Vector3(0, 1, 0)
	material.spread = 45.0
	material.initial_velocity_min = 5.0
	material.initial_velocity_max = 10.0
	material.gravity = Vector3(0, -15.0, 0)
	material.damping_min = 8.0
	material.damping_max = 12.0
	material.scale_min = 0.1
	material.scale_max = 0.3

	# Fade curve
	var scale_curve = Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.5, 0.8))
	scale_curve.add_point(Vector2(1.0, 0.0))
	material.scale_curve = scale_curve

	# Spark colors - orange to yellow
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.8, 0.3, 1.0))
	gradient.add_point(0.5, Color(1.0, 0.5, 0.1, 1.0))
	gradient.add_point(1.0, Color(1.0, 0.3, 0.0, 0.0))
	material.color_ramp = gradient

	sparks.process_material = material

	# Use sphere mesh for sparks
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radial_segments = 4
	sphere_mesh.rings = 3
	sphere_mesh.radius = 0.1
	sphere_mesh.height = 0.2
	sparks.draw_pass_1 = sphere_mesh

	# Emissive material
	var spark_mat = StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.albedo_color = Color(1.0, 0.6, 0.2)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.6, 0.2)
	spark_mat.emission_energy_multiplier = 3.0
	sphere_mesh.material = spark_mat

	return sparks


static func enhance_grind_rail(rail: Path3D) -> void:
	"""Add glow shader and visual effects to grind rail"""
	if not rail or not rail.curve:
		return

	# Create visual mesh along the rail
	var path_follow = PathFollow3D.new()
	rail.add_child(path_follow)

	# Create glowing rail mesh
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "RailGlow"
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.15
	cylinder.bottom_radius = 0.15
	cylinder.height = rail.curve.get_baked_length()
	mesh_instance.mesh = cylinder

	# Apply glow shader
	var glow_material = ShaderMaterial.new()
	glow_material.shader = load("res://scripts/shaders/grind_rail_glow.gdshader")
	glow_material.set_shader_parameter("base_color", Color(0.7, 0.7, 0.8))
	glow_material.set_shader_parameter("glow_color", Color(0.3, 0.8, 1.0))
	glow_material.set_shader_parameter("glow_intensity", 4.0)
	glow_material.set_shader_parameter("glow_speed", 2.5)
	glow_material.set_shader_parameter("flow_speed", 2.0)
	glow_material.set_shader_parameter("flow_scale", 5.0)
	glow_material.set_shader_parameter("metallic", 0.9)
	glow_material.set_shader_parameter("roughness", 0.1)
	mesh_instance.material_override = glow_material

	path_follow.add_child(mesh_instance)

	# Add rail light
	var rail_light = OmniLight3D.new()
	rail_light.name = "RailLight"
	rail_light.light_color = Color(0.3, 0.8, 1.0)
	rail_light.light_energy = 1.5
	rail_light.omni_range = 6.0
	rail_light.omni_attenuation = 2.0
	rail_light.shadow_enabled = false
	path_follow.add_child(rail_light)

	print("GraphicsEnhancer: Enhanced grind rail with glow shader and lighting")


static func create_enhanced_death_particles(position: Vector3, color: Color = Color(0.8, 0.3, 0.3)) -> GPUParticles3D:
	"""Create enhanced death explosion particles"""
	var death_particles = GPUParticles3D.new()
	death_particles.name = "DeathExplosion"
	death_particles.global_position = position
	death_particles.emitting = true
	death_particles.one_shot = true
	death_particles.amount = 100
	death_particles.lifetime = 1.5
	death_particles.explosiveness = 1.0
	death_particles.randomness = 0.8

	# Create explosion material
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 1.0
	material.direction = Vector3(0, 1, 0)
	material.spread = 180.0
	material.initial_velocity_min = 8.0
	material.initial_velocity_max = 15.0
	material.gravity = Vector3(0, -12.0, 0)
	material.damping_min = 2.0
	material.damping_max = 4.0
	material.scale_min = 0.5
	material.scale_max = 1.5

	# Scale curve
	var scale_curve = Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.3, 1.2))
	scale_curve.add_point(Vector2(1.0, 0.0))
	material.scale_curve = scale_curve

	# Color gradient - explosion effect
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 1.0, 0.8, 1.0))  # Bright flash
	gradient.add_point(0.2, color)  # Player color
	gradient.add_point(0.5, color.darkened(0.3))
	gradient.add_point(1.0, Color(0.1, 0.1, 0.1, 0.0))  # Fade to smoke
	material.color_ramp = gradient

	death_particles.process_material = material

	# Use star mesh for explosion
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(1.0, 1.0)
	death_particles.draw_pass_1 = quad_mesh

	# Particle material
	var particle_mat = StandardMaterial3D.new()
	particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_mat.albedo_texture = load("res://textures/kenney_particle_pack/star_05.png")
	particle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	particle_mat.emission_enabled = true
	particle_mat.emission = color
	particle_mat.emission_energy_multiplier = 3.0
	quad_mesh.material = particle_mat

	return death_particles


static func add_ability_charge_effect(ability_node: Node3D, charge_color: Color = Color(0.8, 0.3, 1.0)) -> GPUParticles3D:
	"""Add charging particles to an ability"""
	var charge_particles = GPUParticles3D.new()
	charge_particles.name = "ChargeParticles"
	charge_particles.emitting = false
	charge_particles.amount = 40
	charge_particles.lifetime = 0.8
	charge_particles.one_shot = false
	ability_node.add_child(charge_particles)

	# Create charge material
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 2.0
	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 4.0
	material.gravity = Vector3(0, 0, 0)
	material.radial_accel_min = -5.0  # Pull toward center
	material.radial_accel_max = -8.0
	material.damping_min = 1.0
	material.damping_max = 2.0
	material.scale_min = 0.2
	material.scale_max = 0.5

	# Scale curve
	var scale_curve = Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.5))
	scale_curve.add_point(Vector2(0.5, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.2))
	material.scale_curve = scale_curve

	# Charging color
	var gradient = Gradient.new()
	gradient.set_color(0, charge_color.lightened(0.3))
	gradient.set_color(1, charge_color)
	material.color_ramp = gradient

	charge_particles.process_material = material

	# Use circle texture
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(0.4, 0.4)
	charge_particles.draw_pass_1 = quad_mesh

	var particle_mat = StandardMaterial3D.new()
	particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_mat.albedo_texture = load("res://textures/kenney_particle_pack/circle_05.png")
	particle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	particle_mat.emission_enabled = true
	particle_mat.emission = charge_color
	particle_mat.emission_energy_multiplier = 2.5
	quad_mesh.material = particle_mat

	return charge_particles


static func enhance_platform(platform: MeshInstance3D, platform_type: String = "normal") -> void:
	"""Add enhanced materials to platforms"""
	if not platform:
		return

	var material = ShaderMaterial.new()
	material.shader = load("res://scripts/shaders/platform_enhanced.gdshader")

	# Different colors based on platform type
	match platform_type:
		"main":
			material.set_shader_parameter("base_color", Color(0.6, 0.4, 0.3))
			material.set_shader_parameter("edge_color", Color(0.3, 0.6, 1.0))
			material.set_shader_parameter("grid_scale", 15.0)
		"ramp":
			material.set_shader_parameter("base_color", Color(0.5, 0.5, 0.6))
			material.set_shader_parameter("edge_color", Color(0.4, 0.8, 0.9))
			material.set_shader_parameter("grid_scale", 10.0)
		"wall":
			material.set_shader_parameter("base_color", Color(0.3, 0.3, 0.4))
			material.set_shader_parameter("edge_color", Color(0.5, 0.5, 0.8))
			material.set_shader_parameter("grid_scale", 20.0)
		_:  # floating platforms
			material.set_shader_parameter("base_color", Color(0.7, 0.5, 0.4))
			material.set_shader_parameter("edge_color", Color(0.3, 0.7, 1.0))
			material.set_shader_parameter("grid_scale", 8.0)

	material.set_shader_parameter("edge_glow", 1.2)
	material.set_shader_parameter("edge_width", 0.12)
	material.set_shader_parameter("metallic", 0.4)
	material.set_shader_parameter("roughness", 0.5)
	material.set_shader_parameter("grid_width", 0.05)
	material.set_shader_parameter("grid_color", Color(0.2, 0.2, 0.3))

	platform.material_override = material
	print("GraphicsEnhancer: Enhanced platform with shader material")
