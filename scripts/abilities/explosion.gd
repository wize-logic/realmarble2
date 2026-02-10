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
const SECONDARY_EXPLOSION_POOL_SIZE: int = 6
const LINGERING_FIRE_POOL_SIZE: int = 6
var _flash_container: Node3D = null
var _flash_outer_mat: StandardMaterial3D = null
var _flash_middle_mat: StandardMaterial3D = null
var _flash_core_mat: StandardMaterial3D = null
var _flash_wave_mat: StandardMaterial3D = null
var _flash_shockwave: MeshInstance3D = null
var _flash_tween: Tween = null
var _secondary_explosion_pool: Array[CPUParticles3D] = []
var _secondary_explosion_pool_index: int = 0
var _secondary_explosion_token: int = 0
var _secondary_explosion_gradient: Gradient = null
var _secondary_explosion_curve: Curve = null
var _lingering_fire_pool: Array[CPUParticles3D] = []
var _lingering_fire_pool_index: int = 0
var _lingering_fire_token: int = 0
var _lingering_fire_gradient: Gradient = null
static var _shared_resources_ready: bool = false
static var _shared_indicator_mesh: SphereMesh = null
static var _shared_indicator_material: StandardMaterial3D = null
static var _shared_indicator_gradient: Gradient = null
static var _shared_magma_curve: Curve = null
static var _shared_magma_gradient: Gradient = null

func _ready() -> void:
	super._ready()
	_ensure_shared_explosion_resources()
	ability_name = "Explosion"
	ability_color = Color.ORANGE
	cooldown_time = 2.5
	supports_charging = true  # Explosion supports charging for bigger boom
	max_charge_time = 2.0  # 2 seconds for max charge

	# Create explosion particle effects (visible attack effects - keep for all players)
	_create_explosion_particles()
	_create_magma_particles()
	_build_explosion_flash()
	_build_secondary_explosion_pool()
	_build_lingering_fire_pool()

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

static func _ensure_shared_explosion_resources() -> void:
	if _shared_resources_ready:
		return
	_shared_resources_ready = true

	_shared_indicator_mesh = SphereMesh.new()
	_shared_indicator_mesh.radius = 1.0
	_shared_indicator_mesh.height = 2.0
	_shared_indicator_mesh.radial_segments = 8 if _is_web else 16
	_shared_indicator_mesh.rings = 4 if _is_web else 8

	_shared_indicator_material = StandardMaterial3D.new()
	_shared_indicator_material.albedo_color = Color(0.9, 0.75, 0.6, 0.12)
	_shared_indicator_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shared_indicator_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shared_indicator_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shared_indicator_material.disable_receive_shadows = true
	_shared_indicator_material.disable_fog = true
	_shared_indicator_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_shared_indicator_gradient = Gradient.new()
	_shared_indicator_gradient.add_point(0.0, Color(0.9, 0.8, 0.7, 0.3))
	_shared_indicator_gradient.add_point(0.5, Color(0.85, 0.75, 0.65, 0.2))
	_shared_indicator_gradient.add_point(1.0, Color(0.8, 0.7, 0.6, 0.0))

	_shared_magma_curve = Curve.new()
	_shared_magma_curve.add_point(Vector2(0, 1.0))
	_shared_magma_curve.add_point(Vector2(0.5, 0.7))
	_shared_magma_curve.add_point(Vector2(1, 0.0))

	_shared_magma_gradient = Gradient.new()
	_shared_magma_gradient.add_point(0.0, Color(1.0, 0.9, 0.3, 1.0))
	_shared_magma_gradient.add_point(0.3, Color(1.0, 0.4, 0.0, 1.0))
	_shared_magma_gradient.add_point(0.7, Color(0.8, 0.1, 0.0, 0.8))
	_shared_magma_gradient.add_point(1.0, Color(0.2, 0.0, 0.0, 0.0))

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
			var base_scale: float = explosion_radius * scale_factor
			radius_indicator.scale = Vector3(base_scale, base_scale, base_scale)

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
		magma_particles.amount = 15 + (level_multiplier * 8)  # Level 0: 15, Level 3: 39

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
		# PERF: Use deferred call instead of blocking await for damage check
		get_tree().create_timer(0.05).timeout.connect(damage_nearby_players)

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
			if target_id >= 9000 or not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED or target_id == multiplayer.get_unique_id():
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
	# PERF: Use pooled hit sound instead of creating new AudioStreamPlayer3D per hit
	if player:
		play_pooled_hit_sound(player.global_position)

func spawn_explosion_flash(position: Vector3, level: int) -> void:
	"""Spawn a bright flash effect at the explosion center (GL Compatibility friendly)"""
	if not player or not player.get_parent():
		return

	# PERF: Skip flash for bots on web - visual only, not gameplay-critical
	if _is_web and _is_bot_owner():
		return

	if not _flash_container:
		return

	var flash_size: float = 3.0 + (level * 0.5)
	var flash_scale: float = flash_size / 3.0
	_flash_container.global_position = position
	_flash_container.scale = Vector3.ONE * flash_scale
	_flash_container.visible = true

	_flash_outer_mat.albedo_color.a = 0.35
	if _flash_middle_mat:
		_flash_middle_mat.albedo_color.a = 0.6
	_flash_core_mat.albedo_color.a = 0.9
	if _flash_wave_mat:
		_flash_wave_mat.albedo_color.a = 0.7
	if _flash_shockwave:
		_flash_shockwave.scale = Vector3.ONE

	if _flash_tween and is_instance_valid(_flash_tween):
		_flash_tween.kill()
	_flash_tween = get_tree().create_tween()
	_flash_tween.set_parallel(true)
	_flash_tween.tween_property(_flash_outer_mat, "albedo_color:a", 0.0, 0.3)
	if _flash_middle_mat:
		_flash_tween.tween_property(_flash_middle_mat, "albedo_color:a", 0.0, 0.2)
	_flash_tween.tween_property(_flash_core_mat, "albedo_color:a", 0.0, 0.15)
	if _flash_shockwave and _flash_wave_mat:
		_flash_tween.tween_property(_flash_shockwave, "scale", Vector3(4.0, 4.0, 4.0), 0.4)
		_flash_tween.tween_property(_flash_wave_mat, "albedo_color:a", 0.0, 0.4)
	_flash_tween.set_parallel(false)
	_flash_tween.tween_interval(0.4)
	_flash_tween.tween_callback(func():
		if _flash_container:
			_flash_container.visible = false
	)

func spawn_lingering_fire(position: Vector3, level: int) -> void:
	"""Spawn lingering fire patches on the ground (Level 2+ effect)"""
	if not player or not player.get_parent():
		return

	# PERF: Fewer fire patches on web, skip entirely for bots
	if _is_web and _is_bot_owner():
		return
	var num_patches: int = 3 + (level - 2) * 2  # Level 2: 3 patches, Level 3: 5 patches
	if _is_web:
		num_patches = mini(num_patches, 2)  # PERF: Max 2 patches on web

	# PERF: Reuse raycast query and space_state across all fire patches
	var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	query.collision_mask = 1  # World only

	for i in range(num_patches):
		# Random position around explosion center
		var offset: Vector3 = Vector3(
			randf_range(-3.0, 3.0),
			0.0,
			randf_range(-3.0, 3.0)
		)
		var fire_pos: Vector3 = position + offset

		# Raycast to find ground (reuse query object)
		query.from = fire_pos + Vector3.UP * 10.0
		query.to = fire_pos + Vector3.DOWN * 20.0
		var result: Dictionary = space_state.intersect_ray(query)
		if result:
			fire_pos = result.position + Vector3.UP * 0.1

		if _lingering_fire_pool.is_empty():
			return
		var fire: CPUParticles3D = _lingering_fire_pool[_lingering_fire_pool_index]
		_lingering_fire_pool_index = (_lingering_fire_pool_index + 1) % _lingering_fire_pool.size()
		fire.global_position = fire_pos

		# Configure lingering fire
		fire.emitting = true
		fire.amount = 4 if _is_web else 10  # PERF: Reduced for performance
		fire.lifetime = 1.5
		fire.explosiveness = 0.0
		fire.randomness = 0.3
		fire.local_coords = false

		# PERF: Use shared particle mesh + material
		fire.mesh = _shared_particle_quad_medium

		fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		fire.emission_sphere_radius = 0.5

		fire.direction = Vector3.UP
		fire.spread = 30.0
		fire.gravity = Vector3(0, 1.0, 0)  # Fire rises
		fire.initial_velocity_min = 1.0
		fire.initial_velocity_max = 3.0

		fire.scale_amount_min = 1.5
		fire.scale_amount_max = 2.5

		fire.color_ramp = _lingering_fire_gradient
		fire.restart()

		# Stop emitting after duration, then cleanup
		var fire_duration: float = 1.5 + randf_range(0.0, 0.5)
		_lingering_fire_token += 1
		var token := _lingering_fire_token
		fire.set_meta("lingering_fire_token", token)
		get_tree().create_timer(fire_duration).timeout.connect(func():
			if is_instance_valid(fire) and fire.get_meta("lingering_fire_token", -1) == token:
				fire.emitting = false
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

	if _secondary_explosion_pool.is_empty():
		return
	var explosion: CPUParticles3D = _secondary_explosion_pool[_secondary_explosion_pool_index]
	_secondary_explosion_pool_index = (_secondary_explosion_pool_index + 1) % _secondary_explosion_pool.size()
	explosion.global_position = position

	explosion.emitting = true
	explosion.amount = 8 if _is_web else 20  # PERF: Reduced for performance
	explosion.lifetime = 0.4
	explosion.one_shot = true
	explosion.explosiveness = 1.0
	explosion.randomness = 0.4
	explosion.local_coords = false

	# PERF: Use shared particle mesh + material
	explosion.mesh = _shared_particle_quad_large

	explosion.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	explosion.emission_sphere_radius = 0.3

	explosion.direction = Vector3.UP
	explosion.spread = 180.0
	explosion.gravity = Vector3(0, -10.0, 0)
	explosion.initial_velocity_min = 5.0
	explosion.initial_velocity_max = 10.0

	explosion.scale_amount_min = 1.5
	explosion.scale_amount_max = 3.0
	explosion.scale_amount_curve = _secondary_explosion_curve
	explosion.color_ramp = _secondary_explosion_gradient
	explosion.restart()

	_secondary_explosion_token += 1
	var token := _secondary_explosion_token
	explosion.set_meta("secondary_explosion_token", token)
	get_tree().create_timer(explosion.lifetime + 0.5).timeout.connect(func():
		if is_instance_valid(explosion) and explosion.get_meta("secondary_explosion_token", -1) == token:
			explosion.emitting = false
	)

func _create_explosion_particles() -> void:
	explosion_particles = CPUParticles3D.new()
	explosion_particles.name = "ExplosionParticles"
	add_child(explosion_particles)
	explosion_particles.emitting = false
	explosion_particles.amount = 12 if _is_web else 40  # PERF: Reduced for performance
	explosion_particles.lifetime = 0.5
	explosion_particles.one_shot = true
	explosion_particles.explosiveness = 1.0
	explosion_particles.randomness = 0.5
	explosion_particles.local_coords = false
	# PERF: Use shared particle mesh + material
	explosion_particles.mesh = _shared_particle_quad_xlarge
	explosion_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	explosion_particles.emission_sphere_radius = 0.5
	explosion_particles.direction = Vector3(0, 1, 0)
	explosion_particles.spread = 180.0
	explosion_particles.gravity = Vector3(0, -15.0, 0)
	explosion_particles.initial_velocity_min = 8.0
	explosion_particles.initial_velocity_max = 15.0
	explosion_particles.scale_amount_min = 1.5
	explosion_particles.scale_amount_max = 3.0
	var explosion_curve := Curve.new()
	explosion_curve.add_point(Vector2(0, 2.0))
	explosion_curve.add_point(Vector2(0.3, 1.5))
	explosion_curve.add_point(Vector2(1, 0.0))
	explosion_particles.scale_amount_curve = explosion_curve
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
	magma_particles.amount = 6 if _is_web else 15  # PERF: Reduced for performance
	magma_particles.lifetime = 1.5
	magma_particles.one_shot = true
	magma_particles.explosiveness = 0.8
	magma_particles.randomness = 0.4
	magma_particles.local_coords = false
	# PERF: Use shared particle mesh + material
	magma_particles.mesh = _shared_particle_quad_medium
	magma_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	magma_particles.emission_sphere_radius = 0.8
	magma_particles.direction = Vector3(0, 0.3, 0)
	magma_particles.spread = 180.0
	magma_particles.gravity = Vector3(0, -20.0, 0)
	magma_particles.initial_velocity_min = 6.0
	magma_particles.initial_velocity_max = 12.0
	magma_particles.scale_amount_min = 1.2
	magma_particles.scale_amount_max = 2.0
	magma_particles.scale_amount_curve = _shared_magma_curve
	magma_particles.color_ramp = _shared_magma_gradient

func create_radius_indicator() -> void:
	"""Create a sphere indicator that shows the explosion hitbox while charging"""
	radius_indicator = MeshInstance3D.new()
	radius_indicator.name = "ExplosionRadiusIndicator"

	# Create a sphere mesh matching the actual hitbox (sphere with radius explosion_radius)
	radius_indicator.mesh = _shared_indicator_mesh
	radius_indicator.scale = Vector3.ONE * explosion_radius

	# Create material - very subtle, transparent, non-distracting
	radius_indicator.material_override = _shared_indicator_material

	# Add particles around the sphere surface for extra visual feedback
	var sphere_particles: CPUParticles3D = CPUParticles3D.new()
	sphere_particles.name = "SphereParticles"
	radius_indicator.add_child(sphere_particles)

	# Configure particles - on the sphere surface
	sphere_particles.emitting = true
	sphere_particles.amount = 6 if _is_web else 12  # PERF: Reduced for performance
	sphere_particles.lifetime = 1.0
	sphere_particles.explosiveness = 0.0
	sphere_particles.randomness = 0.1
	sphere_particles.local_coords = true

	# PERF: Use shared particle mesh + material
	sphere_particles.mesh = _shared_particle_quad_small

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
	sphere_particles.color_ramp = _shared_indicator_gradient

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

func _build_explosion_flash() -> void:
	if _flash_container:
		return

	_flash_container = Node3D.new()
	_flash_container.name = "ExplosionFlash"
	add_child(_flash_container)
	_flash_container.visible = false

	var flash_size: float = 3.0
	var radial_segs: int = 6 if _is_web else 8
	var ring_count: int = 3 if _is_web else 4

	var outer_flash: MeshInstance3D = MeshInstance3D.new()
	var outer_sphere: SphereMesh = SphereMesh.new()
	outer_sphere.radius = flash_size * 2.0
	outer_sphere.height = flash_size * 4.0
	outer_sphere.radial_segments = radial_segs
	outer_sphere.rings = ring_count
	outer_flash.mesh = outer_sphere
	_flash_outer_mat = StandardMaterial3D.new()
	_flash_outer_mat.albedo_color = Color(1.0, 0.4, 0.0, 0.35)
	_flash_outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_outer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outer_flash.material_override = _flash_outer_mat
	_flash_container.add_child(outer_flash)

	if not _is_web:
		var middle_flash: MeshInstance3D = MeshInstance3D.new()
		var middle_sphere: SphereMesh = SphereMesh.new()
		middle_sphere.radius = flash_size * 1.2
		middle_sphere.height = flash_size * 2.4
		middle_sphere.radial_segments = radial_segs
		middle_sphere.rings = ring_count
		middle_flash.mesh = middle_sphere
		_flash_middle_mat = StandardMaterial3D.new()
		_flash_middle_mat.albedo_color = Color(1.0, 0.8, 0.2, 0.6)
		_flash_middle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_middle_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_middle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		middle_flash.material_override = _flash_middle_mat
		_flash_container.add_child(middle_flash)

	var core_flash: MeshInstance3D = MeshInstance3D.new()
	var core_sphere: SphereMesh = SphereMesh.new()
	core_sphere.radius = flash_size * 0.5
	core_sphere.height = flash_size * 1.0
	core_sphere.radial_segments = 6 if _is_web else 8
	core_sphere.rings = 3 if _is_web else 4
	core_flash.mesh = core_sphere
	_flash_core_mat = StandardMaterial3D.new()
	_flash_core_mat.albedo_color = Color(1.0, 1.0, 0.9, 0.9)
	_flash_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_flash.material_override = _flash_core_mat
	_flash_container.add_child(core_flash)

	_flash_shockwave = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = flash_size * 0.8
	torus.outer_radius = flash_size * 1.2
	torus.rings = 6 if _is_web else 8
	torus.ring_segments = 6 if _is_web else 12
	_flash_shockwave.mesh = torus
	_flash_shockwave.rotation.x = PI / 2
	_flash_wave_mat = StandardMaterial3D.new()
	_flash_wave_mat.albedo_color = Color(1.0, 0.6, 0.1, 0.7)
	_flash_wave_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_wave_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_wave_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_shockwave.material_override = _flash_wave_mat
	_flash_container.add_child(_flash_shockwave)

func _build_secondary_explosion_pool() -> void:
	if _secondary_explosion_pool.size() > 0:
		return

	_secondary_explosion_curve = Curve.new()
	_secondary_explosion_curve.add_point(Vector2(0, 1.5))
	_secondary_explosion_curve.add_point(Vector2(0.3, 1.2))
	_secondary_explosion_curve.add_point(Vector2(1, 0.0))

	_secondary_explosion_gradient = Gradient.new()
	_secondary_explosion_gradient.add_point(0.0, Color(1.0, 0.9, 0.4, 1.0))
	_secondary_explosion_gradient.add_point(0.2, Color(1.0, 0.6, 0.0, 1.0))
	_secondary_explosion_gradient.add_point(0.5, Color(1.0, 0.3, 0.0, 0.8))
	_secondary_explosion_gradient.add_point(1.0, Color(0.3, 0.0, 0.0, 0.0))

	for i in range(SECONDARY_EXPLOSION_POOL_SIZE):
		var explosion: CPUParticles3D = CPUParticles3D.new()
		explosion.name = "SecondaryExplosion_%d" % i
		add_child(explosion)
		explosion.emitting = false
		explosion.one_shot = true
		explosion.explosiveness = 1.0
		explosion.randomness = 0.4
		explosion.local_coords = false
		explosion.mesh = _shared_particle_quad_large
		explosion.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		explosion.emission_sphere_radius = 0.3
		explosion.direction = Vector3.UP
		explosion.spread = 180.0
		explosion.gravity = Vector3(0, -10.0, 0)
		explosion.initial_velocity_min = 5.0
		explosion.initial_velocity_max = 10.0
		explosion.scale_amount_curve = _secondary_explosion_curve
		explosion.color_ramp = _secondary_explosion_gradient
		_secondary_explosion_pool.append(explosion)

func _build_lingering_fire_pool() -> void:
	if _lingering_fire_pool.size() > 0:
		return

	_lingering_fire_gradient = Gradient.new()
	_lingering_fire_gradient.add_point(0.0, Color(1.0, 0.8, 0.2, 0.9))
	_lingering_fire_gradient.add_point(0.3, Color(1.0, 0.5, 0.0, 0.8))
	_lingering_fire_gradient.add_point(0.6, Color(0.8, 0.2, 0.0, 0.5))
	_lingering_fire_gradient.add_point(1.0, Color(0.3, 0.0, 0.0, 0.0))

	for i in range(LINGERING_FIRE_POOL_SIZE):
		var fire: CPUParticles3D = CPUParticles3D.new()
		fire.name = "LingeringFire_%d" % i
		add_child(fire)
		fire.emitting = false
		fire.amount = 4 if _is_web else 10
		fire.lifetime = 1.5
		fire.explosiveness = 0.0
		fire.randomness = 0.3
		fire.local_coords = false
		fire.mesh = _shared_particle_quad_medium
		fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		fire.emission_sphere_radius = 0.5
		fire.direction = Vector3.UP
		fire.spread = 30.0
		fire.gravity = Vector3(0, 1.0, 0)
		fire.initial_velocity_min = 1.0
		fire.initial_velocity_max = 3.0
		fire.scale_amount_min = 1.5
		fire.scale_amount_max = 2.5
		fire.color_ramp = _lingering_fire_gradient
		_lingering_fire_pool.append(fire)
