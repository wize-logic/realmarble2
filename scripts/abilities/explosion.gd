extends Ability

## Explosion Ability
## Creates an explosion in place that launches the player upward and damages nearby enemies
## Like a rocket jump!

@export var explosion_damage: int = 2
@export var explosion_radius: float = 5.0
@export var upward_launch_force: float = 100.0
@export var knockback_force: float = 120.0  # Doubled from 60.0 for stronger impact
@onready var ability_sound: AudioStreamPlayer3D = $ExplosionSound

var is_exploding: bool = false
var explosion_duration: float = 0.3
var explosion_timer: float = 0.0

# Visual effects
var explosion_particles: CPUParticles3D = null
var explosion_area: Area3D = null
var hit_players: Array = []  # Track who we've hit

# Ground indicator for AoE radius
var radius_indicator: MeshInstance3D = null

func _ready() -> void:
	super._ready()
	ability_name = "Explosion"
	ability_color = Color.ORANGE
	cooldown_time = 2.5
	supports_charging = true  # Explosion supports charging for bigger boom
	max_charge_time = 2.0  # 2 seconds for max charge

	# Create explosion particle effect
	explosion_particles = CPUParticles3D.new()
	explosion_particles.name = "ExplosionParticles"
	add_child(explosion_particles)

	# Configure explosion particles
	explosion_particles.emitting = false
	explosion_particles.amount = 100
	explosion_particles.lifetime = 0.5
	explosion_particles.one_shot = true
	explosion_particles.explosiveness = 1.0
	explosion_particles.randomness = 0.5
	explosion_particles.local_coords = false

	# Set up particle mesh and material for visibility
	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.8, 0.8)
	explosion_particles.mesh = particle_mesh

	# Create material for additive blending (explosion effect)
	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.disable_receive_shadows = true
	particle_material.albedo_color = Color(1.0, 0.6, 0.1, 1.0)
	explosion_particles.mesh.material = particle_material

	# Emission shape - sphere explosion
	explosion_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	explosion_particles.emission_sphere_radius = 0.5

	# Movement - explode outward
	explosion_particles.direction = Vector3(0, 1, 0)
	explosion_particles.spread = 180.0  # Full sphere
	explosion_particles.gravity = Vector3(0, -15.0, 0)
	explosion_particles.initial_velocity_min = 8.0
	explosion_particles.initial_velocity_max = 15.0

	# Size over lifetime
	explosion_particles.scale_amount_min = 1.5
	explosion_particles.scale_amount_max = 3.0
	explosion_particles.scale_amount_curve = Curve.new()
	explosion_particles.scale_amount_curve.add_point(Vector2(0, 2.0))
	explosion_particles.scale_amount_curve.add_point(Vector2(0.3, 1.5))
	explosion_particles.scale_amount_curve.add_point(Vector2(1, 0.0))

	# Color - explosion (bright orange/yellow -> dark red)
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 1.0, 0.8, 1.0))  # Bright white-yellow
	gradient.add_point(0.2, Color(1.0, 0.7, 0.0, 1.0))  # Orange
	gradient.add_point(0.5, Color(1.0, 0.3, 0.0, 0.8))  # Red-orange
	gradient.add_point(1.0, Color(0.3, 0.0, 0.0, 0.0))  # Dark/transparent
	explosion_particles.color_ramp = gradient

	# Create magma chunk particle effect (scales with player level)
	var magma_particles: CPUParticles3D = CPUParticles3D.new()
	magma_particles.name = "MagmaParticles"
	add_child(magma_particles)

	# Configure magma particles - chunky projectiles
	magma_particles.emitting = false
	magma_particles.amount = 30  # Base amount, will scale with level
	magma_particles.lifetime = 1.5  # Magma chunks last longer
	magma_particles.one_shot = true
	magma_particles.explosiveness = 0.8  # Most spawn at once
	magma_particles.randomness = 0.4
	magma_particles.local_coords = false

	# Set up particle mesh - larger chunks
	var magma_mesh: QuadMesh = QuadMesh.new()
	magma_mesh.size = Vector2(0.4, 0.4)
	magma_particles.mesh = magma_mesh

	# Create material for magma chunks (glowing lava)
	var magma_material: StandardMaterial3D = StandardMaterial3D.new()
	magma_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	magma_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	magma_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	magma_material.vertex_color_use_as_albedo = true
	magma_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	magma_material.disable_receive_shadows = true
	magma_material.albedo_color = Color(1.0, 0.3, 0.0, 1.0)
	magma_particles.mesh.material = magma_material

	# Emission shape - sphere around player
	magma_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	magma_particles.emission_sphere_radius = 0.8

	# Movement - shoot outward like projectiles
	magma_particles.direction = Vector3(0, 0.3, 0)  # Slight upward bias
	magma_particles.spread = 180.0  # Full sphere
	magma_particles.gravity = Vector3(0, -20.0, 0)  # Fall down like real chunks
	magma_particles.initial_velocity_min = 6.0  # Fast shooting chunks
	magma_particles.initial_velocity_max = 12.0

	# Size over lifetime - start small, stay consistent
	magma_particles.scale_amount_min = 1.2
	magma_particles.scale_amount_max = 2.0
	magma_particles.scale_amount_curve = Curve.new()
	magma_particles.scale_amount_curve.add_point(Vector2(0, 1.0))
	magma_particles.scale_amount_curve.add_point(Vector2(0.5, 0.9))
	magma_particles.scale_amount_curve.add_point(Vector2(1, 0.3))

	# Color - lava/magma gradient (bright orange -> dark red)
	var magma_gradient: Gradient = Gradient.new()
	magma_gradient.add_point(0.0, Color(1.0, 0.9, 0.3, 1.0))  # Bright yellow-orange
	magma_gradient.add_point(0.3, Color(1.0, 0.4, 0.0, 1.0))  # Orange
	magma_gradient.add_point(0.7, Color(0.8, 0.1, 0.0, 0.8))  # Dark red
	magma_gradient.add_point(1.0, Color(0.2, 0.0, 0.0, 0.0))  # Black/transparent
	magma_particles.color_ramp = magma_gradient

	# Create damage area for detecting hits
	explosion_area = Area3D.new()
	explosion_area.name = "ExplosionArea"
	explosion_area.collision_layer = 0
	explosion_area.collision_mask = 2  # Detect players (layer 2)
	add_child(explosion_area)

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = explosion_radius
	collision_shape.shape = sphere_shape
	explosion_area.add_child(collision_shape)

	# Disable by default
	explosion_area.monitoring = false

	# Create radius indicator for visual feedback
	create_radius_indicator()

func _process(delta: float) -> void:
	super._process(delta)

	if is_exploding:
		explosion_timer -= delta
		if explosion_timer <= 0.0:
			end_explosion()

	# Update radius indicator visibility and scale based on charging state
	if radius_indicator and player and is_instance_valid(player) and player.is_inside_tree():
		if is_charging:
			# Show indicator while charging
			if not radius_indicator.is_inside_tree():
				# Add indicator to world if not already added
				if player.get_parent():
					player.get_parent().add_child(radius_indicator)

			radius_indicator.visible = true

			# Position at player's feet using raycasting to find ground
			var base_position = player.global_position
			var indicator_position = base_position

			# Raycast downward to find ground below player
			var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				base_position + Vector3.UP * 50.0,  # Start well above
				base_position + Vector3.DOWN * 100.0  # Check far below
			)
			query.exclude = [player]
			query.collision_mask = 1  # Only check world geometry (layer 1)
			var result: Dictionary = space_state.intersect_ray(query)

			if result:
				# Ground found - position indicator slightly above it
				indicator_position = result.position + Vector3.UP * 0.1
			else:
				# No ground found - keep at player's Y level
				indicator_position.y = player.global_position.y

			radius_indicator.global_position = indicator_position

			# Scale indicator based on charge level (radius increases with charge)
			var current_radius = explosion_radius * (1.0 + (charge_level - 1) * 0.5)  # +50% per level
			var scale_factor = current_radius / explosion_radius
			radius_indicator.scale = Vector3(scale_factor, 1.0, scale_factor)

			# Pulse effect while charging
			var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.005) * 0.1
			radius_indicator.scale *= pulse

			# Rotate indicator slowly for visual effect
			radius_indicator.rotation.y += delta * 0.5
		else:
			# Hide indicator when not charging
			radius_indicator.visible = false
	else:
		# Player is invalid - hide indicator
		if radius_indicator:
			radius_indicator.visible = false

func activate() -> void:
	if not player:
		return

	# Get charge multiplier for scaled damage/radius/force
	var charge_multiplier: float = get_charge_multiplier()

	print("EXPLOSION! (Charge level %d, %.1fx power)" % [charge_level, charge_multiplier])

	# Start explosion
	is_exploding = true
	explosion_timer = explosion_duration
	hit_players.clear()

	# Position effects at player
	var player_pos: Vector3 = player.global_position

	# Trigger explosion particles
	if explosion_particles:
		explosion_particles.global_position = player_pos
		explosion_particles.emitting = true
		explosion_particles.restart()

	# Trigger magma particles (scaled with player level)
	var magma_particles: CPUParticles3D = get_node_or_null("MagmaParticles")
	if magma_particles:
		# Scale particle amount with player level (30 base, +20 per level)
		var level_multiplier: int = 0
		if player and "level" in player:
			level_multiplier = player.level
		magma_particles.amount = 30 + (level_multiplier * 20)  # Level 0: 30, Level 3: 90

		# Also scale velocity slightly with level
		magma_particles.initial_velocity_min = 6.0 + (level_multiplier * 1.5)
		magma_particles.initial_velocity_max = 12.0 + (level_multiplier * 2.0)

		magma_particles.global_position = player_pos
		magma_particles.emitting = true
		magma_particles.restart()

	# Play explosion sound
	if ability_sound:
		ability_sound.global_position = player_pos
		ability_sound.play()

	# Enable damage area temporarily
	if explosion_area:
		explosion_area.global_position = player_pos
		explosion_area.monitoring = true

		# Check for nearby players and damage them
		await get_tree().create_timer(0.05).timeout  # Small delay for effect
		damage_nearby_players()

	# Launch player upward (rocket jump effect) - scaled by charge
	if player is RigidBody3D:
		var charged_launch_force: float = upward_launch_force * charge_multiplier
		player.apply_central_impulse(Vector3.UP * charged_launch_force)
		print("Player launched upward with %.1fx force!" % charge_multiplier)

func damage_nearby_players() -> void:
	"""Damage all players in explosion radius"""
	if not explosion_area or not player:
		return

	# Get charge multiplier from base ability class
	var charge_mult: float = get_charge_multiplier()

	# Scale explosion radius with charge level (charge level 3 = AoE expansion)
	var current_radius: float = explosion_radius * (1.0 + (charge_level - 1) * 0.5)  # +50% per level
	if explosion_area.get_child(0) and explosion_area.get_child(0).shape is SphereShape3D:
		explosion_area.get_child(0).shape.radius = current_radius

	# Get all bodies in the explosion area
	var bodies: Array[Node3D] = explosion_area.get_overlapping_bodies()

	for body in bodies:
		# Don't damage ourselves
		if body == player:
			continue

		# Don't hit the same player twice
		if body in hit_players:
			continue

		# Check if it's another player
		if body is RigidBody3D and body.has_method("receive_damage_from"):
			# Calculate knockback direction (away from explosion center)
			var knockback_dir: Vector3 = (body.global_position - explosion_area.global_position).normalized()
			knockback_dir.y = 0.5  # Add upward component

			# Deal damage scaled by charge multiplier
			var scaled_damage: int = int(explosion_damage * charge_mult)
			var attacker_id: int = player.name.to_int() if player else -1
			var target_id: int = body.get_multiplayer_authority()

			# CRITICAL FIX: Don't call RPC on ourselves (check if target is local peer)
			if target_id >= 9000 or multiplayer.multiplayer_peer == null or target_id == multiplayer.get_unique_id():
				# Local call for bots, no multiplayer, or local peer
				body.receive_damage_from(scaled_damage, attacker_id)
				print("Explosion hit player (local): ", body.name, " | Damage: ", scaled_damage, " (charge x%.1f)" % charge_mult)
			else:
				# RPC call for remote network players only
				body.receive_damage_from.rpc_id(target_id, scaled_damage, attacker_id)
				print("Explosion hit player (RPC): ", body.name, " | Damage: ", scaled_damage, " (charge x%.1f)" % charge_mult)

			# Apply knockback scaled by charge and player level
			var player_level: int = player.level if player and "level" in player else 0
			var level_mult: float = 1.0 + (player_level * 0.2)
			var scaled_knockback: float = knockback_force * charge_mult * level_mult
			body.apply_central_impulse(knockback_dir * scaled_knockback)

			# Play attack hit sound (satisfying feedback for landing a hit)
			play_attack_hit_sound()

			hit_players.append(body)

func end_explosion() -> void:
	is_exploding = false
	hit_players.clear()

	# Disable damage area
	if explosion_area:
		explosion_area.monitoring = false

func play_attack_hit_sound() -> void:
	"""Play satisfying hit sound when attack lands on enemy"""
	if not ability_sound:
		return

	# Create a separate AudioStreamPlayer3D for hit confirmation
	var hit_sound: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	hit_sound.name = "AttackHitSound"
	add_child(hit_sound)
	hit_sound.max_distance = 20.0
	hit_sound.volume_db = 3.0  # Slightly louder for satisfaction
	hit_sound.pitch_scale = randf_range(1.2, 1.4)  # Higher pitch for "ding" effect

	# Use same stream as ability sound if available, otherwise skip
	if ability_sound.stream:
		hit_sound.stream = ability_sound.stream
		hit_sound.play()

		# Auto-cleanup after sound finishes
		await hit_sound.finished
		hit_sound.queue_free()

func create_radius_indicator() -> void:
	"""Create a ground circle indicator that shows the explosion radius while charging"""
	radius_indicator = MeshInstance3D.new()
	radius_indicator.name = "ExplosionRadiusIndicator"

	# Create a cylinder mesh for the ground circle (very flat)
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = explosion_radius
	cylinder.bottom_radius = explosion_radius
	cylinder.height = 0.05  # Very flat - just a ground decal
	cylinder.radial_segments = 32
	radius_indicator.mesh = cylinder

	# Create material - very subtle, transparent, non-distracting
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.75, 0.6, 0.12)  # Subtle warm tone, 12% opacity
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	mat.disable_fog = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides
	radius_indicator.material_override = mat

	# Add inner ring particles for extra visual feedback
	var ring_particles: CPUParticles3D = CPUParticles3D.new()
	ring_particles.name = "RingParticles"
	radius_indicator.add_child(ring_particles)

	# Configure particles - very subtle rotating around the edge
	ring_particles.emitting = true
	ring_particles.amount = 18  # Reduced from 30 for subtlety
	ring_particles.lifetime = 1.0
	ring_particles.explosiveness = 0.0
	ring_particles.randomness = 0.1
	ring_particles.local_coords = true

	# Set up particle mesh
	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.2, 0.2)
	ring_particles.mesh = particle_mesh

	# Create material for particles
	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.disable_receive_shadows = true
	ring_particles.mesh.material = particle_material

	# Emission shape - ring around the edge of the circle
	ring_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	ring_particles.emission_ring_axis = Vector3(0, 1, 0)
	ring_particles.emission_ring_height = 0.1
	ring_particles.emission_ring_radius = explosion_radius
	ring_particles.emission_ring_inner_radius = explosion_radius - 0.3

	# Movement - orbit around the circle
	ring_particles.direction = Vector3(0, 0, 0)
	ring_particles.spread = 0.0
	ring_particles.gravity = Vector3.ZERO
	ring_particles.initial_velocity_min = 0.3
	ring_particles.initial_velocity_max = 0.8

	# Size
	ring_particles.scale_amount_min = 1.0
	ring_particles.scale_amount_max = 1.5

	# Color - very subtle warm gradient
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.9, 0.8, 0.7, 0.3))  # Subtle warm tone
	gradient.add_point(0.5, Color(0.85, 0.75, 0.65, 0.2))  # Very subtle
	gradient.add_point(1.0, Color(0.8, 0.7, 0.6, 0.0))  # Transparent
	ring_particles.color_ramp = gradient

	# Initially hidden (will show when charging)
	radius_indicator.visible = false

func drop() -> void:
	"""Override drop to clean up indicator"""
	super.drop()
	cleanup_indicator()

func cleanup_indicator() -> void:
	"""Clean up the indicator when ability is dropped or destroyed"""
	if radius_indicator and is_instance_valid(radius_indicator):
		if radius_indicator.is_inside_tree():
			radius_indicator.queue_free()
		radius_indicator = null
