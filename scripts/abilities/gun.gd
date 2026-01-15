extends Ability

## Gun Ability
## Shoots projectiles that damage enemies
## Like a ranged attack!

@export var projectile_damage: int = 1
@export var projectile_speed: float = 40.0
@export var projectile_lifetime: float = 3.0
@export var fire_rate: float = 0.3  # Shots per second
@onready var ability_sound: AudioStreamPlayer3D = $GunSound

func _ready() -> void:
	super._ready()
	ability_name = "Gun"
	ability_color = Color.CYAN
	cooldown_time = fire_rate
	supports_charging = true  # Gun supports charging for more powerful shots
	max_charge_time = 2.0  # 2 seconds for max charge

func activate() -> void:
	if not player:
		return

	# Get charge multiplier for scaled damage/speed
	var charge_multiplier: float = get_charge_multiplier()
	var charged_damage: int = int(projectile_damage * charge_multiplier)
	var charged_speed: float = projectile_speed * charge_multiplier

	print("BANG! (Charge level %d, %.1fx power)" % [charge_level, charge_multiplier])

	# Get firing direction from camera (always shoot where camera is looking)
	var camera_arm: Node3D = player.get_node_or_null("CameraArm")
	var camera: Camera3D = player.get_node_or_null("CameraArm/Camera3D")
	var fire_direction: Vector3 = Vector3.FORWARD

	if camera and camera_arm:
		# Shoot in camera forward direction (use camera, not camera_arm, to include pitch)
		fire_direction = -camera.global_transform.basis.z
	elif camera_arm:
		# Fallback to camera_arm if camera not found
		fire_direction = -camera_arm.global_transform.basis.z
	else:
		# Fallback for bots: use player's facing direction (rotation.y)
		# This is CRITICAL for bots to aim properly
		fire_direction = Vector3(sin(player.rotation.y), 0, cos(player.rotation.y))

	# Calculate gun barrel position (offset in front of player in camera direction)
	var barrel_offset: float = 1.0  # Distance in front of player
	var barrel_position: Vector3 = player.global_position + Vector3.UP * 0.5 + fire_direction * barrel_offset

	# Raycast from gun barrel in camera direction for better targeting feedback
	var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		barrel_position,
		barrel_position + fire_direction * 100.0
	)
	query.exclude = [player]
	query.collision_mask = 3  # Check world (1) and players (2)
	var result: Dictionary = space_state.intersect_ray(query)

	# Spawn projectile
	var projectile: Node3D = create_projectile()
	if projectile:
		# Add to world FIRST
		player.get_parent().add_child(projectile)

		# Position at gun barrel (after adding to tree)
		projectile.global_position = barrel_position

		# Set velocity - inherit player velocity + projectile velocity in fire direction
		var level_multiplier: float = 1.0
		if player and "level" in player:
			level_multiplier = 1.0 + (player.level * 0.25)

		# Projectile velocity = player velocity + fire direction * charged speed
		var projectile_velocity: Vector3 = player.linear_velocity + (fire_direction * charged_speed * level_multiplier)
		if projectile is RigidBody3D:
			projectile.linear_velocity = projectile_velocity

		# Set charged damage, owner, charge multiplier, and player level via metadata
		var owner_id: int = player.name.to_int() if player else -1
		var player_level: int = player.level if player and "level" in player else 0
		projectile.set_meta("damage", charged_damage)
		projectile.set_meta("owner_id", owner_id)
		projectile.set_meta("charge_multiplier", charge_multiplier)
		projectile.set_meta("player_level", player_level)

		# Auto-destroy after lifetime
		get_tree().create_timer(projectile_lifetime).timeout.connect(projectile.queue_free)

	# Spawn muzzle flash particles at barrel position
	spawn_muzzle_flash(barrel_position, fire_direction)

	# Play gun sound
	if ability_sound:
		ability_sound.global_position = barrel_position
		ability_sound.play()

func _on_projectile_body_entered(body: Node, projectile: Node3D) -> void:
	"""Handle projectile collision with another body"""
	# Get projectile metadata
	var damage: int = projectile.get_meta("damage", 1)
	var owner_id: int = projectile.get_meta("owner_id", -1)

	# Don't hit the owner
	if body.name == str(owner_id):
		return

	# Check if it's a player
	if body.has_method('receive_damage_from'):
		var target_id: int = body.get_multiplayer_authority()
		# CRITICAL FIX: Don't call RPC on ourselves (check if target is local peer)
		if target_id >= 9000 or multiplayer.multiplayer_peer == null or target_id == multiplayer.get_unique_id():
			# Local call for bots, no multiplayer, or local peer
			body.receive_damage_from(damage, owner_id)
			print('Projectile hit player (local): ', body.name, ' | Damage: ', damage)
		else:
			# RPC call for remote network players only
			body.receive_damage_from.rpc_id(target_id, damage, owner_id)
			print('Projectile hit player (RPC): ', body.name, ' | Damage: ', damage)

		# Apply knockback from projectile impact
		# Get charge multiplier and player level multiplier from projectile metadata
		var charge_mult: float = projectile.get_meta("charge_multiplier", 1.0)
		var player_level: int = projectile.get_meta("player_level", 0)
		var level_mult: float = 1.0 + (player_level * 0.2)

		# Calculate knockback (base 20.0, scaled by charge and level)
		var base_knockback: float = 20.0
		var total_knockback: float = base_knockback * charge_mult * level_mult

		# Apply knockback in projectile direction with slight upward component
		var knockback_dir: Vector3 = projectile.linear_velocity.normalized()
		knockback_dir.y = 0.15  # Slight upward knockback
		body.apply_central_impulse(knockback_dir * total_knockback)

		# Play attack hit sound (satisfying feedback for landing a hit)
		var hit_sound: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		hit_sound.max_distance = 20.0
		hit_sound.volume_db = 3.0
		hit_sound.pitch_scale = randf_range(1.2, 1.4)
		hit_sound.global_position = projectile.global_position
		if player and player.get_parent():
			player.get_parent().add_child(hit_sound)
			hit_sound.play()
			# Sound will auto-cleanup when it finishes

	# Destroy projectile on hit
	projectile.queue_free()

func create_projectile() -> Node3D:
	"""Create a projectile node"""
	# Create a simple projectile
	var projectile: RigidBody3D = RigidBody3D.new()
	projectile.name = "Projectile"

	# Physics setup
	projectile.mass = 0.1
	projectile.gravity_scale = 0.0  # No gravity for projectiles
	projectile.continuous_cd = true
	projectile.collision_layer = 4  # Projectile layer
	projectile.collision_mask = 3   # Hit players (layer 2) and world (layer 1)
	projectile.contact_monitor = true  # Enable contact monitoring for collision detection
	projectile.max_contacts_reported = 10  # Allow reporting up to 10 contacts

	# Create mesh
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	mesh_instance.mesh = sphere

	# Create glowing material
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color.CYAN
	mat.emission_enabled = true
	mat.emission = Color.CYAN
	mat.emission_energy_multiplier = 2.0
	mesh_instance.material_override = mat
	projectile.add_child(mesh_instance)

	# Create collision shape
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.15
	collision.shape = shape
	projectile.add_child(collision)

	# Store projectile data as metadata (no dynamic script needed)
	projectile.set_meta("damage", 1)
	projectile.set_meta("owner_id", -1)
	projectile.set_meta("lifetime", projectile_lifetime)

	# Connect body_entered signal to Gun ability's handler
	# Use Callable.bind to pass projectile reference to the handler
	projectile.body_entered.connect(_on_projectile_body_entered.bind(projectile))

	# Add trail particles to projectile
	add_projectile_trail(projectile)

	return projectile

func add_projectile_trail(projectile: Node3D) -> void:
	"""Add visual trail effect to projectile"""
	var trail: CPUParticles3D = CPUParticles3D.new()
	trail.name = "Trail"
	projectile.add_child(trail)

	# Configure trail particles
	trail.emitting = true
	trail.amount = 30
	trail.lifetime = 0.4
	trail.explosiveness = 0.0  # Continuous emission
	trail.randomness = 0.2
	trail.local_coords = false  # World space - particles stay where emitted

	# Set up particle mesh
	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.15, 0.15)
	trail.mesh = particle_mesh

	# Create material for trail
	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.disable_receive_shadows = true
	trail.mesh.material = particle_material

	# Emission shape - point source
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT

	# Movement - minimal, just fade in place
	trail.direction = Vector3.ZERO
	trail.spread = 5.0
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.1
	trail.initial_velocity_max = 0.5

	# Size over lifetime - shrink and fade
	trail.scale_amount_min = 1.5
	trail.scale_amount_max = 2.0
	trail.scale_amount_curve = Curve.new()
	trail.scale_amount_curve.add_point(Vector2(0, 1.0))
	trail.scale_amount_curve.add_point(Vector2(0.5, 0.6))
	trail.scale_amount_curve.add_point(Vector2(1, 0.0))

	# Color - cyan trail fading out
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.5, 1.0, 1.0, 1.0))  # Bright cyan
	gradient.add_point(0.5, Color(0.2, 0.8, 1.0, 0.6))  # Cyan
	gradient.add_point(1.0, Color(0.1, 0.4, 0.6, 0.0))  # Dark/transparent
	trail.color_ramp = gradient

func spawn_muzzle_flash(position: Vector3, direction: Vector3) -> void:
	"""Spawn muzzle flash particle effect at gun barrel"""
	if not player or not player.get_parent():
		return

	# Create muzzle flash particles
	var muzzle_flash: CPUParticles3D = CPUParticles3D.new()
	muzzle_flash.name = "MuzzleFlash"
	player.get_parent().add_child(muzzle_flash)
	muzzle_flash.global_position = position

	# Configure muzzle flash - quick burst
	muzzle_flash.emitting = true
	muzzle_flash.amount = 15
	muzzle_flash.lifetime = 0.15
	muzzle_flash.one_shot = true
	muzzle_flash.explosiveness = 1.0
	muzzle_flash.randomness = 0.3
	muzzle_flash.local_coords = false

	# Set up particle mesh
	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.4, 0.4)
	muzzle_flash.mesh = particle_mesh

	# Create material for flash
	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.disable_receive_shadows = true
	muzzle_flash.mesh.material = particle_material

	# Emission shape - cone in fire direction
	muzzle_flash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	muzzle_flash.emission_sphere_radius = 0.2

	# Movement - burst outward in fire direction
	muzzle_flash.direction = direction
	muzzle_flash.spread = 25.0  # Cone spread
	muzzle_flash.gravity = Vector3.ZERO
	muzzle_flash.initial_velocity_min = 3.0
	muzzle_flash.initial_velocity_max = 8.0

	# Size over lifetime - quick flash and fade
	muzzle_flash.scale_amount_min = 2.0
	muzzle_flash.scale_amount_max = 3.5
	muzzle_flash.scale_amount_curve = Curve.new()
	muzzle_flash.scale_amount_curve.add_point(Vector2(0, 1.5))
	muzzle_flash.scale_amount_curve.add_point(Vector2(0.3, 1.0))
	muzzle_flash.scale_amount_curve.add_point(Vector2(1, 0.0))

	# Color - bright yellow/white flash
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 1.0, 0.8, 1.0))  # Bright white-yellow
	gradient.add_point(0.3, Color(1.0, 0.9, 0.5, 0.8))  # Yellow
	gradient.add_point(0.7, Color(0.8, 0.6, 0.3, 0.4))  # Orange
	gradient.add_point(1.0, Color(0.3, 0.2, 0.1, 0.0))  # Dark/transparent
	muzzle_flash.color_ramp = gradient

	# Auto-delete after lifetime
	get_tree().create_timer(muzzle_flash.lifetime + 0.5).timeout.connect(muzzle_flash.queue_free)
