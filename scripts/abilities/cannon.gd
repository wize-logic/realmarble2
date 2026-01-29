extends Ability

## Cannon Ability
## Shoots powerful explosive projectiles that deal heavy damage
## Slower fire rate but much more impactful than a gun!

@export var projectile_damage: int = 1  # Base damage (same as gun)
@export var projectile_speed: float = 80.0  # Very fast for accurate shots (was 25.0)
@export var projectile_lifetime: float = 8.0  # Long range - doubled from 4.0
@export var fire_rate: float = 1.5  # Slower cooldown (increased from 1.0)
@export var max_active_projectiles: int = 3  # Fewer than gun's 5 (more powerful shots)
@onready var ability_sound: AudioStreamPlayer3D = $CannonSound

# Track active projectiles for this player
var active_projectiles: Array[Node3D] = []

# Reticle system for target lock visualization
var reticle: MeshInstance3D = null
var reticle_target: Node3D = null

func _ready() -> void:
	super._ready()
	ability_name = "Cannon"
	ability_color = Color(0.5, 1.0, 0.0)  # Lime green for high visibility
	cooldown_time = fire_rate
	supports_charging = true  # Must support charging for input to work
	max_charge_time = 0.01  # Instant fire - minimal charge time

	# Create reticle for target lock visualization
	create_reticle()

func drop() -> void:
	"""Override drop to clean up reticle"""
	cleanup_reticle()
	super.drop()

func _exit_tree() -> void:
	"""Ensure reticle is cleaned up when ability is removed from scene"""
	cleanup_reticle()

func cleanup_reticle() -> void:
	"""Clean up the reticle when ability is dropped or destroyed"""
	if reticle and is_instance_valid(reticle):
		# Remove from parent first to ensure it's detached
		if reticle.is_inside_tree():
			var parent = reticle.get_parent()
			if parent:
				parent.remove_child(reticle)
		# Then free it
		reticle.queue_free()
	reticle = null
	reticle_target = null

func find_nearest_player() -> Node3D:
	"""Find the nearest player to lock onto (excluding self) - only targets in forward cone"""
	if not player or not player.get_parent():
		return null

	var nearest: Node3D = null
	var nearest_distance: float = INF
	var max_lock_range: float = 100.0  # Long range targeting (doubled from 50.0)
	var max_angle_degrees: float = 70.0  # Only target within 70 degrees of forward (140 degree cone total) - improved accuracy

	# Get player's forward direction (based on camera or rotation) - full 3D
	var forward_direction: Vector3
	var camera_arm: Node3D = player.get_node_or_null("CameraArm")
	var camera: Camera3D = player.get_node_or_null("CameraArm/Camera3D")

	if camera:
		# Use camera's forward direction (full 3D - works for both players and bots)
		forward_direction = -camera.global_transform.basis.z
	elif camera_arm:
		# Fallback to camera_arm
		forward_direction = -camera_arm.global_transform.basis.z

	forward_direction = forward_direction.normalized()

	# Get all nodes in the Players container
	var players_container = player.get_parent()
	for potential_target in players_container.get_children():
		# Skip if it's ourselves
		if potential_target == player:
			continue

		# Check if it's a valid player (has health, not dead)
		if not potential_target.has_method('receive_damage_from'):
			continue

		# Check if player is alive (has health > 0)
		if "health" in potential_target and potential_target.health <= 0:
			continue

		# Calculate direction to target
		var to_target: Vector3 = (potential_target.global_position - player.global_position).normalized()

		# Calculate angle between forward direction and target direction
		var dot_product: float = forward_direction.dot(to_target)
		var angle_radians: float = acos(clamp(dot_product, -1.0, 1.0))
		var angle_degrees: float = rad_to_deg(angle_radians)

		# Skip targets outside the forward cone
		if angle_degrees > max_angle_degrees:
			continue

		# Calculate distance
		var distance = player.global_position.distance_to(potential_target.global_position)

		# Check if within lock range and closer than current nearest
		if distance < max_lock_range and distance < nearest_distance:
			nearest = potential_target
			nearest_distance = distance

	return nearest

func activate() -> void:
	if not player:
		return

	# Cannon always does exactly 1 damage (no charge scaling)
	var damage: int = 1  # Fixed damage, never modified
	var speed: float = projectile_speed

	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "BOOM! (Instant fire)", false, get_entity_id())

	# Get initial firing direction from camera
	var camera_arm: Node3D = player.get_node_or_null("CameraArm")
	var camera: Camera3D = player.get_node_or_null("CameraArm/Camera3D")
	var fire_direction: Vector3 = Vector3.FORWARD

	# Auto-aim: Find nearest player and adjust fire direction
	var nearest_player = find_nearest_player()
	if nearest_player:
		# AUTO-AIM: Aim at the nearest player's position in FULL 3D (including up/down)
		var target_pos = nearest_player.global_position
		# Predict where the player will be based on their velocity (95% prediction for near-perfect accuracy)
		if nearest_player is RigidBody3D and nearest_player.linear_velocity.length() > 0:
			var distance = player.global_position.distance_to(target_pos)
			var time_to_hit = distance / speed
			# Increased prediction for near-perfect accuracy
			target_pos += nearest_player.linear_velocity * time_to_hit * 0.95

		# Calculate direction to target (full 3D - can aim up or down at targets)
		fire_direction = (target_pos - player.global_position).normalized()
	else:
		# MANUAL AIM: No target found - shoot horizontally forward based on camera direction
		if camera:
			# Get camera's forward direction (works for both players and bots)
			fire_direction = -camera.global_transform.basis.z
		elif camera_arm:
			# Fallback to camera_arm if camera not found
			fire_direction = -camera_arm.global_transform.basis.z

		# Flatten to horizontal plane for manual aim (no up/down)
		fire_direction.y = 0
		fire_direction = fire_direction.normalized()

	# Calculate cannon barrel position (offset further in front for larger weapon)
	var barrel_offset: float = 1.5  # Increased from gun's 1.0
	var barrel_position: Vector3 = player.global_position + Vector3.UP * 0.5 + fire_direction * barrel_offset

	# Raycast from cannon barrel in camera direction for targeting feedback
	var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		barrel_position,
		barrel_position + fire_direction * 100.0
	)
	query.exclude = [player]
	query.collision_mask = 3  # Check world (1) and players (2)
	var result: Dictionary = space_state.intersect_ray(query)

	# Clean up invalid projectiles from tracking array
	active_projectiles = active_projectiles.filter(func(p): return is_instance_valid(p) and p.is_inside_tree())

	# Check if we've hit the projectile limit - free oldest if needed
	if active_projectiles.size() >= max_active_projectiles:
		var oldest_projectile: Node3D = active_projectiles[0]
		if is_instance_valid(oldest_projectile):
			oldest_projectile.queue_free()
		active_projectiles.remove_at(0)
		if OS.is_debug_build():
			DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Cannon: Projectile limit reached (%d), freed oldest" % max_active_projectiles, false, get_entity_id())

	# Spawn projectile
	var projectile: Node3D = create_projectile()
	if projectile:
		# Add to world FIRST
		player.get_parent().add_child(projectile)

		# Track this projectile
		active_projectiles.append(projectile)

		# Position at cannon barrel (after adding to tree)
		projectile.global_position = barrel_position

		# Set velocity - inherit player velocity + projectile velocity in fire direction
		var level_multiplier: float = 1.0
		if player and "level" in player:
			level_multiplier = 1.0 + (player.level * 0.25)

		# Projectile velocity = player velocity + fire direction * speed
		var projectile_velocity: Vector3 = player.linear_velocity + (fire_direction * speed * level_multiplier)
		if projectile is RigidBody3D:
			projectile.linear_velocity = projectile_velocity

		# Set damage, owner, and player level via metadata (damage is always 1)
		var owner_id: int = player.name.to_int() if player else -1
		var player_level: int = player.level if player and "level" in player else 0
		projectile.set_meta("damage", damage)
		projectile.set_meta("owner_id", owner_id)
		projectile.set_meta("player_level", player_level)

		# Auto-destroy after lifetime
		get_tree().create_timer(projectile_lifetime).timeout.connect(projectile.queue_free)

	# Spawn muzzle flash particles at barrel position
	spawn_muzzle_flash(barrel_position, fire_direction)

	# Play cannon sound
	if ability_sound:
		ability_sound.global_position = barrel_position
		ability_sound.play()

func _on_projectile_body_entered(body: Node, projectile: Node3D) -> void:
	"""Handle projectile collision with another body"""
	# CRITICAL FIX: Validate BOTH body and projectile FIRST
	# Multiple projectiles can hit simultaneously - first might free the body!
	if not body or not is_instance_valid(body) or not body.is_inside_tree():
		return  # Body already freed or invalid (killed by another bullet)

	if not projectile or not is_instance_valid(projectile) or not projectile.is_inside_tree():
		return  # Projectile already freed or invalid

	# Cache projectile data immediately to prevent issues if it gets freed
	var projectile_position: Vector3 = projectile.global_position
	var projectile_velocity: Vector3 = projectile.linear_velocity

	# Get projectile metadata
	var damage: int = projectile.get_meta("damage", 1)
	var owner_id: int = projectile.get_meta("owner_id", -1)

	# Don't hit the owner
	if body.name == str(owner_id):
		return

	# Spawn explosion effect at impact point (before damaging)
	spawn_explosion_effect(projectile_position)

	# Check if it's a player
	if body.has_method('receive_damage_from'):
		var target_id: int = body.get_multiplayer_authority()
		# CRITICAL FIX: Don't call RPC on ourselves (check if target is local peer)
		if target_id >= 9000 or multiplayer.multiplayer_peer == null or target_id == multiplayer.get_unique_id():
			# Local call for bots, no multiplayer, or local peer
			body.receive_damage_from(damage, owner_id)
			DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Cannonball hit player (local): %s | Damage: %d" % [body.name, damage], false, get_entity_id())
		else:
			# RPC call for remote network players only
			body.receive_damage_from.rpc_id(target_id, damage, owner_id)
			DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Cannonball hit player (RPC): %s | Damage: %d" % [body.name, damage], false, get_entity_id())

		# Apply stronger knockback from cannonball impact
		# Get player level multiplier from projectile metadata
		var player_level: int = projectile.get_meta("player_level", 0)
		var level_mult: float = 1.0 + (player.level * 0.2)

		# Calculate knockback (base 150.0, slightly nerfed for better balance, scaled by level)
		var base_knockback: float = 150.0
		var total_knockback: float = base_knockback * level_mult

		# Apply knockback in projectile direction with slight upward component
		# Use cached velocity to avoid accessing freed projectile
		var knockback_dir: Vector3 = projectile_velocity.normalized()
		knockback_dir.y = 0.2  # Slightly stronger upward knockback than gun
		body.apply_central_impulse(knockback_dir * total_knockback)

		# Play attack hit sound (deeper, more satisfying than gun)
		# Use cached position to avoid accessing freed projectile
		var hit_sound: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		hit_sound.max_distance = 30.0  # Louder than gun (was 20.0)
		hit_sound.volume_db = 6.0  # Louder than gun (was 3.0)
		hit_sound.pitch_scale = randf_range(0.8, 1.0)  # Deeper than gun (was 1.2-1.4)
		if player and player.get_parent():
			player.get_parent().add_child(hit_sound)
			hit_sound.global_position = projectile_position  # Set position after adding to tree
			hit_sound.play()
			# Sound will auto-cleanup when it finishes

	# Destroy projectile on hit
	if projectile and is_instance_valid(projectile):
		projectile.queue_free()

func create_projectile() -> Node3D:
	"""Create a cannonball projectile node"""
	# Create a simple projectile
	var projectile: RigidBody3D = RigidBody3D.new()
	projectile.name = "Cannonball"

	# Physics setup - heavier but no gravity for straight shots
	projectile.mass = 0.5  # Much heavier than gun (was 0.1)
	projectile.gravity_scale = 0.0  # No gravity for laser-straight accuracy
	projectile.continuous_cd = true
	projectile.collision_layer = 4  # Projectile layer
	projectile.collision_mask = 3   # Hit players (layer 2) and world (layer 1)
	projectile.contact_monitor = true  # Enable contact monitoring for collision detection
	projectile.max_contacts_reported = 10  # Allow reporting up to 10 contacts

	# Create mesh - larger cannonball
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.4  # Much larger than gun (was 0.15)
	sphere.height = 0.8
	mesh_instance.mesh = sphere

	# Create material - lime green for visibility
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 1.0, 0.0)  # Lime green
	mat.metallic = 0.3
	mat.roughness = 0.3
	mesh_instance.material_override = mat
	projectile.add_child(mesh_instance)

	# Create collision shape - larger
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.4  # Match mesh radius
	collision.shape = shape
	projectile.add_child(collision)

	# Store projectile data as metadata (no dynamic script needed)
	projectile.set_meta("damage", 1)
	projectile.set_meta("owner_id", -1)
	projectile.set_meta("lifetime", projectile_lifetime)

	# Connect body_entered signal to Cannon ability's handler
	# Use Callable.bind to pass projectile reference to the handler
	projectile.body_entered.connect(_on_projectile_body_entered.bind(projectile))

	# Add trail particles to projectile
	add_projectile_trail(projectile)

	return projectile

func add_projectile_trail(projectile: Node3D) -> void:
	"""Add visual trail effect to cannonball - fiery smoke trail"""
	var trail: CPUParticles3D = CPUParticles3D.new()
	trail.name = "Trail"
	projectile.add_child(trail)

	# Configure trail particles - thicker, more dramatic than gun
	trail.emitting = true
	trail.amount = 50  # More particles than gun (was 30)
	trail.lifetime = 0.6  # Longer lifetime than gun (was 0.4)
	trail.explosiveness = 0.0  # Continuous emission
	trail.randomness = 0.3
	trail.local_coords = false  # World space - particles stay where emitted

	# Set up particle mesh - larger
	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.3, 0.3)  # Larger than gun (was 0.15)
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

	# Movement - more spread for smoke effect
	trail.direction = Vector3.ZERO
	trail.spread = 10.0  # More spread than gun (was 5.0)
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 1.0

	# Size over lifetime - grow then shrink (smoke effect)
	trail.scale_amount_min = 2.0
	trail.scale_amount_max = 3.0
	trail.scale_amount_curve = Curve.new()
	trail.scale_amount_curve.add_point(Vector2(0, 0.5))
	trail.scale_amount_curve.add_point(Vector2(0.3, 1.2))  # Grow
	trail.scale_amount_curve.add_point(Vector2(0.7, 0.8))
	trail.scale_amount_curve.add_point(Vector2(1, 0.0))

	# Color - lime green to dark trail
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.7, 1.0, 0.3, 1.0))  # Bright lime green
	gradient.add_point(0.3, Color(0.5, 1.0, 0.2, 0.8))  # Green
	gradient.add_point(0.6, Color(0.3, 0.6, 0.2, 0.5))  # Dark green
	gradient.add_point(1.0, Color(0.1, 0.2, 0.1, 0.0))  # Dark/transparent
	trail.color_ramp = gradient

func spawn_muzzle_flash(position: Vector3, direction: Vector3) -> void:
	"""Spawn large muzzle flash particle effect at cannon barrel"""
	if not player or not player.get_parent():
		return

	# Create muzzle flash particles - much larger and more dramatic than gun
	var muzzle_flash: CPUParticles3D = CPUParticles3D.new()
	muzzle_flash.name = "MuzzleFlash"
	player.get_parent().add_child(muzzle_flash)
	muzzle_flash.global_position = position

	# Configure muzzle flash - bigger burst than gun
	muzzle_flash.emitting = true
	muzzle_flash.amount = 30  # More than gun (was 15)
	muzzle_flash.lifetime = 0.25  # Longer than gun (was 0.15)
	muzzle_flash.one_shot = true
	muzzle_flash.explosiveness = 1.0
	muzzle_flash.randomness = 0.4
	muzzle_flash.local_coords = false

	# Set up particle mesh - larger
	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.8, 0.8)  # Much larger than gun (was 0.4)
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

	# Emission shape - larger sphere
	muzzle_flash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	muzzle_flash.emission_sphere_radius = 0.4  # Larger than gun (was 0.2)

	# Movement - stronger burst
	muzzle_flash.direction = direction
	muzzle_flash.spread = 30.0  # More spread than gun (was 25.0)
	muzzle_flash.gravity = Vector3.ZERO
	muzzle_flash.initial_velocity_min = 5.0  # Faster than gun (was 3.0)
	muzzle_flash.initial_velocity_max = 12.0  # Faster than gun (was 8.0)

	# Size over lifetime - bigger flash
	muzzle_flash.scale_amount_min = 3.0  # Larger than gun (was 2.0)
	muzzle_flash.scale_amount_max = 5.0  # Larger than gun (was 3.5)
	muzzle_flash.scale_amount_curve = Curve.new()
	muzzle_flash.scale_amount_curve.add_point(Vector2(0, 2.0))
	muzzle_flash.scale_amount_curve.add_point(Vector2(0.3, 1.2))
	muzzle_flash.scale_amount_curve.add_point(Vector2(1, 0.0))

	# Color - bright lime green flash
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.6, 0.95, 0.5, 1.0))  # Bright lime-green (no white)
	gradient.add_point(0.3, Color(0.6, 1.0, 0.3, 0.9))  # Lime green
	gradient.add_point(0.6, Color(0.4, 0.9, 0.2, 0.6))  # Green
	gradient.add_point(1.0, Color(0.1, 0.3, 0.1, 0.0))  # Dark/transparent
	muzzle_flash.color_ramp = gradient

	# Auto-delete after lifetime
	get_tree().create_timer(muzzle_flash.lifetime + 0.5).timeout.connect(muzzle_flash.queue_free)

func spawn_explosion_effect(position: Vector3) -> void:
	"""Spawn explosion particle effect at impact point"""
	if not player or not player.get_parent():
		return

	# Create explosion particles
	var explosion: CPUParticles3D = CPUParticles3D.new()
	explosion.name = "CannonExplosion"
	player.get_parent().add_child(explosion)
	explosion.global_position = position

	# Configure explosion - dramatic burst
	explosion.emitting = true
	explosion.amount = 40
	explosion.lifetime = 0.5
	explosion.one_shot = true
	explosion.explosiveness = 1.0
	explosion.randomness = 0.4
	explosion.local_coords = false

	# Set up particle mesh
	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.6, 0.6)
	explosion.mesh = particle_mesh

	# Create material for explosion
	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.disable_receive_shadows = true
	explosion.mesh.material = particle_material

	# Emission shape - sphere burst
	explosion.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	explosion.emission_sphere_radius = 0.3

	# Movement - explosive outward burst
	explosion.direction = Vector3.ZERO
	explosion.spread = 180.0  # Full sphere
	explosion.gravity = Vector3(0, -5.0, 0)  # Gravity pulls particles down
	explosion.initial_velocity_min = 4.0
	explosion.initial_velocity_max = 10.0

	# Size over lifetime - expand and fade
	explosion.scale_amount_min = 2.0
	explosion.scale_amount_max = 4.0
	explosion.scale_amount_curve = Curve.new()
	explosion.scale_amount_curve.add_point(Vector2(0, 1.5))
	explosion.scale_amount_curve.add_point(Vector2(0.2, 1.8))
	explosion.scale_amount_curve.add_point(Vector2(0.6, 1.0))
	explosion.scale_amount_curve.add_point(Vector2(1, 0.0))

	# Color - lime green explosion
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.65, 1.0, 0.7, 1.0))  # Bright green center (no white)
	gradient.add_point(0.2, Color(0.7, 1.0, 0.3, 1.0))  # Bright lime green
	gradient.add_point(0.5, Color(0.4, 0.9, 0.2, 0.7))  # Green
	gradient.add_point(0.8, Color(0.2, 0.4, 0.2, 0.3))  # Dark green smoke
	gradient.add_point(1.0, Color(0.1, 0.2, 0.1, 0.0))  # Transparent
	explosion.color_ramp = gradient

	# Auto-delete after lifetime
	get_tree().create_timer(explosion.lifetime + 0.5).timeout.connect(explosion.queue_free)

func create_reticle() -> void:
	"""Create a 3D reticle that follows the locked target"""
	# Clean up any existing reticle first
	cleanup_reticle()

	reticle = MeshInstance3D.new()
	reticle.name = "CannonReticle"

	# Create a torus (ring) mesh for the reticle
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.2
	torus.rings = 32
	torus.ring_segments = 16
	reticle.mesh = torus

	# Create material - subtle lime green, transparent, with additive blending
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 1.0, 0.0, 0.4)  # Lime green, 40% opacity
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	mat.disable_fog = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y  # Face camera but stay horizontal
	reticle.material_override = mat

	# Add particle effect to reticle for extra visual feedback
	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.name = "ReticleParticles"
	reticle.add_child(particles)

	# Configure particles - subtle rotating glow
	particles.emitting = true
	particles.amount = 20
	particles.lifetime = 0.8
	particles.explosiveness = 0.0
	particles.randomness = 0.2
	particles.local_coords = true

	# Set up particle mesh
	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.15, 0.15)
	particles.mesh = particle_mesh

	# Create material for particles
	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.disable_receive_shadows = true
	particles.mesh.material = particle_material

	# Emission shape - ring around reticle
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	particles.emission_ring_axis = Vector3(0, 1, 0)
	particles.emission_ring_height = 0.1
	particles.emission_ring_radius = 1.0
	particles.emission_ring_inner_radius = 0.8

	# Movement - orbit around reticle
	particles.direction = Vector3(0, 0, 0)
	particles.spread = 0.0
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = 0.5
	particles.initial_velocity_max = 1.0

	# Size
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 1.5

	# Color - lime green fade
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.7, 1.0, 0.3, 0.8))  # Bright lime green
	gradient.add_point(0.5, Color(0.5, 1.0, 0.2, 0.6))  # Green
	gradient.add_point(1.0, Color(0.3, 0.6, 0.1, 0.0))  # Transparent
	particles.color_ramp = gradient

	# Initially hidden (will show when target is locked)
	reticle.visible = false

func _process(delta: float) -> void:
	super._process(delta)

	# Update reticle position to follow locked target
	# Only show reticle to the local player who has the cannon
	if not reticle or not is_instance_valid(reticle):
		return  # Reticle was destroyed, skip processing

	if player and is_instance_valid(player) and player.is_inside_tree():
		# Check if this player is the local player (has multiplayer authority)
		var is_local_player: bool = player.is_multiplayer_authority()

		if is_local_player:
			# Find the nearest player in the auto-aim cone
			var target = find_nearest_player()

			if target and is_instance_valid(target):
				# We have a lock - show reticle and update position
				if not reticle.is_inside_tree():
					# Add reticle to world if not already added
					if player.get_parent():
						player.get_parent().add_child(reticle)

				reticle.visible = true
				reticle_target = target

				# Position reticle above target with smooth interpolation
				var target_position = target.global_position + Vector3(0, 1.5, 0)
				reticle.global_position = reticle.global_position.lerp(target_position, delta * 10.0)

				# Rotate reticle for visual effect
				reticle.rotation.y += delta * 2.0
			else:
				# No lock - hide reticle
				reticle.visible = false
				reticle_target = null
		else:
			# Not local player - hide reticle
			reticle.visible = false
			reticle_target = null
	else:
		# Player is invalid - hide reticle and clean up
		reticle.visible = false
		reticle_target = null
