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

	# PERF: Skip all particle effects for bots on HTML5
	if not _is_bot_owner():
		_create_explosion_particles()
		_create_magma_particles()

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

	# Create radius indicator for visual feedback (human player only)
	if not _is_bot_owner():
		create_radius_indicator()

func _process(delta: float) -> void:
	super._process(delta)

	if is_exploding:
		explosion_timer -= delta
		if explosion_timer <= 0.0:
			end_explosion()

	# Update radius indicator visibility and scale based on charging state
	# MULTIPLAYER FIX: Only show indicator to the local player using the ability
	if radius_indicator and player and is_instance_valid(player) and player.is_inside_tree():
		# PERF: Only show indicator for local human player (not bots)
		var is_local_player: bool = is_local_human_player()

		if is_charging and is_local_player:
			# Show indicator while charging (only to local player)
			if not radius_indicator.is_inside_tree():
				# Add indicator to world if not already added
				if player.get_parent():
					player.get_parent().add_child(radius_indicator)

			radius_indicator.visible = true

			# Position sphere at player's center (where explosion hitbox will be)
			radius_indicator.global_position = player.global_position

			# Get player level for level-based scaling
			var player_level: int = player.level if "level" in player else 0

			# Scale indicator based on charge level AND player level
			var charge_scale: float = 1.0 + (charge_level - 1) * 0.5
			var level_scale: float = 1.0 + ((player_level - 1) * 0.15)  # +15% radius per level
			var scale_factor: float = charge_scale * level_scale
			radius_indicator.scale = Vector3(scale_factor, scale_factor, scale_factor)

			# Update indicator color based on level (more intense at higher levels)
			var mat: StandardMaterial3D = radius_indicator.material_override
			if mat:
				if player_level >= 3:
					# Level 3: Bright orange (secondary explosions)
					mat.albedo_color = Color(1.0, 0.5, 0.1, 0.2)
				elif player_level >= 2:
					# Level 2: Hot orange (lingering fire)
					mat.albedo_color = Color(1.0, 0.6, 0.2, 0.17)
				elif player_level >= 1:
					# Level 1: Warm orange (more particles)
					mat.albedo_color = Color(0.95, 0.7, 0.4, 0.15)
				else:
					# Level 0: Subtle warm
					mat.albedo_color = Color(0.9, 0.75, 0.6, 0.12)

			# Pulse effect while charging (faster at higher levels)
			var pulse_speed: float = 0.005 + ((player_level - 1) * 0.002)
			var pulse = 1.0 + sin(Time.get_ticks_msec() * pulse_speed) * 0.1
			radius_indicator.scale *= pulse

			# Rotate indicator slowly for visual effect (faster at higher levels)
			radius_indicator.rotation.y += delta * (0.5 + (player_level - 1) * 0.2)
		else:
			# Hide indicator when not charging or not local player
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

	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "EXPLOSION! (Charge level %d, %.1fx power)" % [charge_level, charge_multiplier], false, get_entity_id())

	# Start explosion
	is_exploding = true
	explosion_timer = explosion_duration
	hit_players.clear()

	# Position effects at player
	var player_pos: Vector3 = player.global_position

	# Get player level for level-based effects
	var player_level: int = player.level if player and "level" in player else 0

	# Trigger explosion particles
	if explosion_particles:
		explosion_particles.global_position = player_pos
		explosion_particles.emitting = true
		explosion_particles.restart()

	# Spawn bright flash effect at center (GL Compatibility friendly)
	spawn_explosion_flash(player_pos, player_level)

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
		DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Player launched upward with %.1fx force!" % charge_multiplier, false, get_entity_id())

	# Level-based effects
	# Level 2+: Spawn lingering fire patches on the ground
	if player_level >= 2:
		spawn_lingering_fire(player_pos, player_level)

	# Level 3: Spawn secondary explosions in a ring around main explosion
	if player_level >= 3:
		spawn_secondary_explosions(player_pos)

func damage_nearby_players() -> void:
	"""Damage all players in explosion radius"""
	if not explosion_area or not player:
		return

	# Get charge multiplier from base ability class
	var charge_mult: float = get_charge_multiplier()

	# Get player level for level-based scaling
	var player_level: int = player.level if player and "level" in player else 0

	# Scale explosion radius with charge level AND player level (matches indicator)
	var charge_scale: float = 1.0 + (charge_level - 1) * 0.5  # +50% per charge level
	var level_scale: float = 1.0 + ((player_level - 1) * 0.15)  # +15% per player level
	var current_radius: float = explosion_radius * charge_scale * level_scale
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
				DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Explosion hit player (local): %s | Damage: %d (charge x%.1f)" % [body.name, scaled_damage, charge_mult], false, get_entity_id())
			else:
				# RPC call for remote network players only
				body.receive_damage_from.rpc_id(target_id, scaled_damage, attacker_id)
				DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Explosion hit player (RPC): %s | Damage: %d (charge x%.1f)" % [body.name, scaled_damage, charge_mult], false, get_entity_id())

			# Apply knockback scaled by charge and player level
			var level_mult: float = 1.0 + ((player_level - 1) * 0.2)
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

func spawn_explosion_flash(position: Vector3, level: int) -> void:
	"""Spawn a bright flash effect at the explosion center (GL Compatibility friendly)"""
	if not player or not player.get_parent():
		return

	var flash_container: Node3D = Node3D.new()
	flash_container.name = "ExplosionFlash"
	player.get_parent().add_child(flash_container)
	flash_container.global_position = position

	var flash_size: float = 3.0 + (level * 0.5)

	# Layer 1: Outer orange glow
	var outer_flash: MeshInstance3D = MeshInstance3D.new()
	var outer_sphere: SphereMesh = SphereMesh.new()
	outer_sphere.radius = flash_size * 2.0
	outer_sphere.height = flash_size * 4.0
	outer_sphere.radial_segments = 16
	outer_sphere.rings = 8
	outer_flash.mesh = outer_sphere

	var outer_mat: StandardMaterial3D = StandardMaterial3D.new()
	outer_mat.albedo_color = Color(1.0, 0.4, 0.0, 0.35)
	outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outer_flash.material_override = outer_mat
	flash_container.add_child(outer_flash)

	# Layer 2: Middle yellow layer
	var middle_flash: MeshInstance3D = MeshInstance3D.new()
	var middle_sphere: SphereMesh = SphereMesh.new()
	middle_sphere.radius = flash_size * 1.2
	middle_sphere.height = flash_size * 2.4
	middle_sphere.radial_segments = 16
	middle_sphere.rings = 8
	middle_flash.mesh = middle_sphere

	var middle_mat: StandardMaterial3D = StandardMaterial3D.new()
	middle_mat.albedo_color = Color(1.0, 0.8, 0.2, 0.6)
	middle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	middle_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	middle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	middle_flash.material_override = middle_mat
	flash_container.add_child(middle_flash)

	# Layer 3: Bright white-yellow core
	var core_flash: MeshInstance3D = MeshInstance3D.new()
	var core_sphere: SphereMesh = SphereMesh.new()
	core_sphere.radius = flash_size * 0.5
	core_sphere.height = flash_size * 1.0
	core_sphere.radial_segments = 12
	core_sphere.rings = 6
	core_flash.mesh = core_sphere

	var core_mat: StandardMaterial3D = StandardMaterial3D.new()
	core_mat.albedo_color = Color(1.0, 1.0, 0.9, 0.9)
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_flash.material_override = core_mat
	flash_container.add_child(core_flash)

	# Add shockwave ring effect
	var shockwave: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = flash_size * 0.8
	torus.outer_radius = flash_size * 1.2
	torus.rings = 16
	torus.ring_segments = 24
	shockwave.mesh = torus
	shockwave.rotation.x = PI / 2  # Lay flat

	var wave_mat: StandardMaterial3D = StandardMaterial3D.new()
	wave_mat.albedo_color = Color(1.0, 0.6, 0.1, 0.7)
	wave_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wave_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	wave_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shockwave.material_override = wave_mat
	flash_container.add_child(shockwave)

	# Animate flash fading and shockwave expanding
	var tween: Tween = get_tree().create_tween()
	tween.set_parallel(true)

	# Flash fades out
	tween.tween_property(outer_mat, "albedo_color:a", 0.0, 0.3)
	tween.tween_property(middle_mat, "albedo_color:a", 0.0, 0.2)
	tween.tween_property(core_mat, "albedo_color:a", 0.0, 0.15)

	# Shockwave expands outward
	tween.tween_property(shockwave, "scale", Vector3(4.0, 4.0, 4.0), 0.4)
	tween.tween_property(wave_mat, "albedo_color:a", 0.0, 0.4)

	tween.set_parallel(false)
	tween.tween_interval(0.4)
	tween.tween_callback(flash_container.queue_free)

func spawn_lingering_fire(position: Vector3, level: int) -> void:
	"""Spawn lingering fire patches on the ground (Level 2+ effect)"""
	if not player or not player.get_parent():
		return

	var num_patches: int = 3 + (level - 2) * 2  # Level 2: 3 patches, Level 3: 5 patches

	for i in range(num_patches):
		# Random position around explosion center
		var offset: Vector3 = Vector3(
			randf_range(-3.0, 3.0),
			0.0,
			randf_range(-3.0, 3.0)
		)
		var fire_pos: Vector3 = position + offset

		# Raycast to find ground
		var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			fire_pos + Vector3.UP * 10.0,
			fire_pos + Vector3.DOWN * 20.0
		)
		query.collision_mask = 1  # World only
		var result: Dictionary = space_state.intersect_ray(query)
		if result:
			fire_pos = result.position + Vector3.UP * 0.1

		# Create fire particle
		var fire: CPUParticles3D = CPUParticles3D.new()
		fire.name = "LingeringFire"
		player.get_parent().add_child(fire)
		fire.global_position = fire_pos

		# Configure lingering fire
		fire.emitting = true
		fire.amount = 10 if OS.has_feature("web") else 20
		fire.lifetime = 1.5
		fire.explosiveness = 0.0
		fire.randomness = 0.3
		fire.local_coords = false

		var particle_mesh: QuadMesh = QuadMesh.new()
		particle_mesh.size = Vector2(0.4, 0.4)
		var particle_material: StandardMaterial3D = StandardMaterial3D.new()
		particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		particle_material.vertex_color_use_as_albedo = true
		particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		particle_mesh.material = particle_material
		fire.mesh = particle_mesh

		fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		fire.emission_sphere_radius = 0.5

		fire.direction = Vector3.UP
		fire.spread = 30.0
		fire.gravity = Vector3(0, 1.0, 0)  # Fire rises
		fire.initial_velocity_min = 1.0
		fire.initial_velocity_max = 3.0

		fire.scale_amount_min = 1.5
		fire.scale_amount_max = 2.5

		# Orange-red fire gradient
		var gradient: Gradient = Gradient.new()
		gradient.add_point(0.0, Color(1.0, 0.8, 0.2, 0.9))  # Bright yellow
		gradient.add_point(0.3, Color(1.0, 0.5, 0.0, 0.8))  # Orange
		gradient.add_point(0.6, Color(0.8, 0.2, 0.0, 0.5))  # Red
		gradient.add_point(1.0, Color(0.3, 0.0, 0.0, 0.0))  # Dark/transparent
		fire.color_ramp = gradient

		# Stop emitting after duration, then cleanup
		var fire_duration: float = 1.5 + randf_range(0.0, 0.5)
		get_tree().create_timer(fire_duration).timeout.connect(func():
			if is_instance_valid(fire):
				fire.emitting = false
		)
		get_tree().create_timer(fire_duration + fire.lifetime + 0.5).timeout.connect(func():
			if is_instance_valid(fire):
				fire.queue_free()
		)

func spawn_secondary_explosions(center_position: Vector3) -> void:
	"""Spawn secondary explosions in a ring around the main explosion (Level 3 effect)"""
	if not player or not player.get_parent():
		return

	var num_explosions: int = 4  # 4 secondary explosions in a ring
	var ring_radius: float = 4.0

	for i in range(num_explosions):
		var angle: float = (i / float(num_explosions)) * TAU  # Evenly spaced around circle
		var offset: Vector3 = Vector3(
			cos(angle) * ring_radius,
			0.0,
			sin(angle) * ring_radius
		)

		# Delay each secondary explosion slightly for cascade effect
		var delay: float = 0.1 + (i * 0.08)

		get_tree().create_timer(delay).timeout.connect(func():
			if not is_instance_valid(player) or not player.get_parent():
				return
			spawn_single_secondary_explosion(center_position + offset)
		)

func spawn_single_secondary_explosion(position: Vector3) -> void:
	"""Spawn a single secondary explosion effect"""
	if not player or not player.get_parent():
		return

	# Create secondary explosion particles (smaller than main)
	var explosion: CPUParticles3D = CPUParticles3D.new()
	explosion.name = "SecondaryExplosion"
	player.get_parent().add_child(explosion)
	explosion.global_position = position

	explosion.emitting = true
	explosion.amount = 20 if OS.has_feature("web") else 50
	explosion.lifetime = 0.4
	explosion.one_shot = true
	explosion.explosiveness = 1.0
	explosion.randomness = 0.4
	explosion.local_coords = false

	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.5, 0.5)

	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_mesh.material = particle_material
	explosion.mesh = particle_mesh

	explosion.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	explosion.emission_sphere_radius = 0.3

	explosion.direction = Vector3.UP
	explosion.spread = 180.0
	explosion.gravity = Vector3(0, -10.0, 0)
	explosion.initial_velocity_min = 5.0
	explosion.initial_velocity_max = 10.0

	explosion.scale_amount_min = 1.5
	explosion.scale_amount_max = 3.0

	# Orange explosion gradient
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.9, 0.4, 1.0))  # Bright yellow
	gradient.add_point(0.2, Color(1.0, 0.6, 0.0, 1.0))  # Orange
	gradient.add_point(0.5, Color(1.0, 0.3, 0.0, 0.8))  # Red-orange
	gradient.add_point(1.0, Color(0.3, 0.0, 0.0, 0.0))  # Dark/transparent
	explosion.color_ramp = gradient

	# Auto-delete
	get_tree().create_timer(explosion.lifetime + 0.5).timeout.connect(func():
		if is_instance_valid(explosion):
			explosion.queue_free()
	)

func _create_explosion_particles() -> void:
	explosion_particles = CPUParticles3D.new()
	explosion_particles.name = "ExplosionParticles"
	add_child(explosion_particles)
	explosion_particles.emitting = false
	explosion_particles.amount = 40 if OS.has_feature("web") else 100
	explosion_particles.lifetime = 0.5
	explosion_particles.one_shot = true
	explosion_particles.explosiveness = 1.0
	explosion_particles.randomness = 0.5
	explosion_particles.local_coords = false
	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.8, 0.8)
	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.disable_receive_shadows = true
	particle_material.albedo_color = Color(1.0, 0.6, 0.1, 1.0)
	particle_mesh.material = particle_material
	explosion_particles.mesh = particle_mesh
	explosion_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	explosion_particles.emission_sphere_radius = 0.5
	explosion_particles.direction = Vector3(0, 1, 0)
	explosion_particles.spread = 180.0
	explosion_particles.gravity = Vector3(0, -15.0, 0)
	explosion_particles.initial_velocity_min = 8.0
	explosion_particles.initial_velocity_max = 15.0
	explosion_particles.scale_amount_min = 1.5
	explosion_particles.scale_amount_max = 3.0
	explosion_particles.scale_amount_curve = Curve.new()
	explosion_particles.scale_amount_curve.add_point(Vector2(0, 2.0))
	explosion_particles.scale_amount_curve.add_point(Vector2(0.3, 1.5))
	explosion_particles.scale_amount_curve.add_point(Vector2(1, 0.0))
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.9, 0.35, 1.0))
	gradient.add_point(0.2, Color(1.0, 0.7, 0.0, 1.0))
	gradient.add_point(0.5, Color(1.0, 0.3, 0.0, 0.8))
	gradient.add_point(1.0, Color(0.3, 0.0, 0.0, 0.0))
	explosion_particles.color_ramp = gradient

func _create_magma_particles() -> void:
	var magma_particles: CPUParticles3D = CPUParticles3D.new()
	magma_particles.name = "MagmaParticles"
	add_child(magma_particles)
	magma_particles.emitting = false
	magma_particles.amount = 15 if OS.has_feature("web") else 30
	magma_particles.lifetime = 1.5
	magma_particles.one_shot = true
	magma_particles.explosiveness = 0.8
	magma_particles.randomness = 0.4
	magma_particles.local_coords = false
	var magma_mesh: QuadMesh = QuadMesh.new()
	magma_mesh.size = Vector2(0.4, 0.4)
	var magma_material: StandardMaterial3D = StandardMaterial3D.new()
	magma_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	magma_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	magma_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	magma_material.vertex_color_use_as_albedo = true
	magma_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	magma_material.disable_receive_shadows = true
	magma_material.albedo_color = Color(1.0, 0.3, 0.0, 1.0)
	magma_mesh.material = magma_material
	magma_particles.mesh = magma_mesh
	magma_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	magma_particles.emission_sphere_radius = 0.8
	magma_particles.direction = Vector3(0, 0.3, 0)
	magma_particles.spread = 180.0
	magma_particles.gravity = Vector3(0, -20.0, 0)
	magma_particles.initial_velocity_min = 6.0
	magma_particles.initial_velocity_max = 12.0
	magma_particles.scale_amount_min = 1.2
	magma_particles.scale_amount_max = 2.0
	magma_particles.scale_amount_curve = Curve.new()
	magma_particles.scale_amount_curve.add_point(Vector2(0, 1.0))
	magma_particles.scale_amount_curve.add_point(Vector2(0.5, 0.7))
	magma_particles.scale_amount_curve.add_point(Vector2(1, 0.0))
	var magma_gradient: Gradient = Gradient.new()
	magma_gradient.add_point(0.0, Color(1.0, 0.9, 0.3, 1.0))
	magma_gradient.add_point(0.3, Color(1.0, 0.4, 0.0, 1.0))
	magma_gradient.add_point(0.7, Color(0.8, 0.1, 0.0, 0.8))
	magma_gradient.add_point(1.0, Color(0.2, 0.0, 0.0, 0.0))
	magma_particles.color_ramp = magma_gradient

func create_radius_indicator() -> void:
	"""Create a sphere indicator that shows the explosion hitbox while charging"""
	radius_indicator = MeshInstance3D.new()
	radius_indicator.name = "ExplosionRadiusIndicator"

	# Create a sphere mesh matching the actual hitbox (sphere with radius explosion_radius)
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = explosion_radius  # Match hitbox radius
	sphere.height = explosion_radius * 2  # Diameter
	sphere.radial_segments = 32
	sphere.rings = 16
	radius_indicator.mesh = sphere

	# Create material - very subtle, transparent, non-distracting
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.75, 0.6, 0.12)  # Subtle warm tone, 12% opacity
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	mat.disable_fog = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides (inside and out)
	radius_indicator.material_override = mat

	# Add particles around the sphere surface for extra visual feedback
	var sphere_particles: CPUParticles3D = CPUParticles3D.new()
	sphere_particles.name = "SphereParticles"
	radius_indicator.add_child(sphere_particles)

	# Configure particles - on the sphere surface
	sphere_particles.emitting = true
	sphere_particles.amount = 24
	sphere_particles.lifetime = 1.0
	sphere_particles.explosiveness = 0.0
	sphere_particles.randomness = 0.1
	sphere_particles.local_coords = true

	# Set up particle mesh
	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.2, 0.2)
	# Create material for particles
	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.disable_receive_shadows = true
	particle_mesh.material = particle_material
	sphere_particles.mesh = particle_mesh

	# Emission shape - sphere surface matching the hitbox
	sphere_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	sphere_particles.emission_sphere_radius = explosion_radius

	# Movement - slow drift outward
	sphere_particles.direction = Vector3(0, 0, 0)
	sphere_particles.spread = 180.0
	sphere_particles.gravity = Vector3.ZERO
	sphere_particles.initial_velocity_min = 0.2
	sphere_particles.initial_velocity_max = 0.6

	# Size
	sphere_particles.scale_amount_min = 1.0
	sphere_particles.scale_amount_max = 1.5

	# Color - very subtle warm gradient
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.9, 0.8, 0.7, 0.3))  # Subtle warm tone
	gradient.add_point(0.5, Color(0.85, 0.75, 0.65, 0.2))  # Very subtle
	gradient.add_point(1.0, Color(0.8, 0.7, 0.6, 0.0))  # Transparent
	sphere_particles.color_ramp = gradient

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
