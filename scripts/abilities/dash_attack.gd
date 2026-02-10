extends Ability

## Dash Attack Ability
## Performs a powerful forward dash that damages enemies on contact
## Like Kirby's dash attack!

@export var dash_force: float = 130.0  # Reduced by 35% from 200.0 for better balance
@export var dash_duration: float = 0.4  # Reduced by 35% from 0.6 for better balance
@export var damage: int = 1  # Damage unchanged
@onready var ability_sound: AudioStreamPlayer3D = $DashSound

var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
var hit_players: Array = []  # Track who we've hit this dash
var dash_start_position: Vector3 = Vector3.ZERO  # For level-based effects

# Hitbox for detecting other players
var hitbox: Area3D = null

# Fire trail particle effect
var fire_trail: CPUParticles3D = null

# Direction indicator for dash targeting
var direction_indicator: MeshInstance3D = null

# Afterimage tracking for level 3
var afterimage_timer: float = 0.0
const AFTERIMAGE_INTERVAL: float = 0.05

const DASH_EXPLOSION_POOL_SIZE: int = 4
const AFTERIMAGE_POOL_SIZE: int = 8
var _dash_explosion_pool: Array[CPUParticles3D] = []
var _dash_explosion_pool_index: int = 0
var _dash_explosion_token: int = 0
var _dash_explosion_curve: Curve = null
var _dash_explosion_gradient: Gradient = null
var _dash_flash_container: Node3D = null
var _dash_flash_outer_mat: StandardMaterial3D = null
var _dash_flash_core_mat: StandardMaterial3D = null
var _dash_flash_tween: Tween = null
var _afterimage_pool: Array[MeshInstance3D] = []
var _afterimage_pool_index: int = 0
var _afterimage_tweens: Dictionary = {}
static var _shared_resources_ready: bool = false
static var _shared_indicator_mesh: SphereMesh = null
static var _shared_indicator_material: StandardMaterial3D = null
static var _shared_indicator_gradient: Gradient = null
static var _shared_fire_trail_curve: Curve = null
static var _shared_fire_trail_gradient: Gradient = null

func _ready() -> void:
	super._ready()
	_ensure_shared_dash_resources()
	ability_name = "Dash Attack"
	ability_color = Color.MAGENTA
	cooldown_time = 1.5
	supports_charging = true  # Dash attack supports charging for more speed/damage
	max_charge_time = 2.0  # 2 seconds for max charge

	# Create hitbox for detecting hits
	hitbox = Area3D.new()
	hitbox.name = "DashAttackHitbox"
	hitbox.collision_layer = 0
	hitbox.collision_mask = 2  # Detect players (layer 2)
	add_child(hitbox)

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = 1.5  # Increased from 1.2 for easier hits with powerful dash
	collision_shape.shape = sphere_shape
	hitbox.add_child(collision_shape)

	# Connect hitbox signals
	hitbox.body_entered.connect(_on_hitbox_body_entered)

	# Disable hitbox by default
	hitbox.monitoring = false

	# Create fire trail particle effect (visible attack effect - keep for bots)
	fire_trail = CPUParticles3D.new()
	fire_trail.name = "FireTrail"
	add_child(fire_trail)

	# Configure fire particles - Trail effect (enhanced for more powerful dash)
	fire_trail.emitting = false
	fire_trail.amount = 25 if OS.has_feature("web") else 60  # PERF: Significantly reduced for performance
	fire_trail.lifetime = 1.4  # Increased from 1.2s for longer lasting trail
	fire_trail.explosiveness = 0.0  # Continuous emission for smooth trail
	fire_trail.randomness = 0.3
	fire_trail.local_coords = false  # World space - particles stay where emitted

	# PERF: Use shared particle mesh + material
	fire_trail.mesh = _shared_particle_quad_large

	fire_trail.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH

	# Emission shape - emit from player center
	fire_trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire_trail.emission_sphere_radius = 0.4

	# Movement - minimal movement for trail effect
	fire_trail.direction = Vector3(0, 0.5, 0)  # Slight upward drift
	fire_trail.spread = 35.0  # Moderate spread for flame effect
	fire_trail.gravity = Vector3(0, 0.2, 0)  # Slight upward gravity (fire rises)
	fire_trail.initial_velocity_min = 0.3  # Very slow - particles stay in place
	fire_trail.initial_velocity_max = 1.2

	# Size over lifetime - start big, shrink gradually (enhanced for powerful dash)
	fire_trail.scale_amount_min = 3.5  # Increased from 2.5
	fire_trail.scale_amount_max = 5.5  # Increased from 4.0
	fire_trail.scale_amount_curve = _shared_fire_trail_curve

	# Color - magenta gradient (bright magenta -> pink -> purple -> dark)
	fire_trail.color_ramp = _shared_fire_trail_gradient

	# Create direction indicator for dash targeting (human player only)
	if not _is_bot_owner():
		create_direction_indicator()

	_build_dash_flash()
	_build_dash_explosion_pool()
	_build_afterimage_pool()

static func _ensure_shared_dash_resources() -> void:
	if _shared_resources_ready:
		return
	_shared_resources_ready = true

	_shared_indicator_mesh = SphereMesh.new()
	_shared_indicator_mesh.radius = 1.5
	_shared_indicator_mesh.height = 3.0
	_shared_indicator_mesh.radial_segments = 12 if _is_web else 24
	_shared_indicator_mesh.rings = 6 if _is_web else 12

	_shared_indicator_material = StandardMaterial3D.new()
	_shared_indicator_material.albedo_color = Color(0.85, 0.75, 0.85, 0.15)  # Subtle neutral purple-pink
	_shared_indicator_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shared_indicator_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shared_indicator_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shared_indicator_material.disable_receive_shadows = true
	_shared_indicator_material.disable_fog = true
	_shared_indicator_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_shared_indicator_gradient = Gradient.new()
	_shared_indicator_gradient.add_point(0.0, Color(0.85, 0.8, 0.9, 0.35))
	_shared_indicator_gradient.add_point(0.5, Color(0.8, 0.75, 0.85, 0.25))
	_shared_indicator_gradient.add_point(1.0, Color(0.75, 0.7, 0.8, 0.0))

	_shared_fire_trail_curve = Curve.new()
	_shared_fire_trail_curve.add_point(Vector2(0, 1.0))
	_shared_fire_trail_curve.add_point(Vector2(0.4, 0.8))
	_shared_fire_trail_curve.add_point(Vector2(1, 0.1))

	_shared_fire_trail_gradient = Gradient.new()
	_shared_fire_trail_gradient.add_point(0.0, Color(1.0, 0.5, 1.0, 1.0))  # Bright magenta
	_shared_fire_trail_gradient.add_point(0.3, Color(1.0, 0.2, 0.8, 1.0))  # Hot pink
	_shared_fire_trail_gradient.add_point(0.6, Color(0.8, 0.1, 0.6, 0.8))  # Deep magenta
	_shared_fire_trail_gradient.add_point(1.0, Color(0.2, 0.0, 0.2, 0.0))  # Dark/transparent

func _process(delta: float) -> void:
	super._process(delta)

	if is_dashing:
		dash_timer -= delta

		if dash_timer <= 0.0:
			# End dash
			end_dash()
		else:
			# Continue dashing
			if player and player is RigidBody3D:
				# Keep the dash momentum going
				player.apply_central_force(dash_direction * dash_force * 0.5)

	# Update direction indicator visibility and orientation based on charging state
	# MULTIPLAYER FIX: Only show indicator to the local player using the ability
	if direction_indicator and player and is_instance_valid(player) and player.is_inside_tree():
		# PERF: Only show indicator for local human player (not bots)
		var is_local_player: bool = is_local_human_player()

		if is_charging and is_local_player:
			# Show indicator while charging (only to local player)
			if not direction_indicator.is_inside_tree():
				# Add indicator to world if not already added
				if player.get_parent():
					player.get_parent().add_child(direction_indicator)

			direction_indicator.visible = true

			# Position sphere at player's center (where the hitbox will be during dash)
			direction_indicator.global_position = player.global_position

			# Scale based on charge level AND player level
			var charge_scale: float = 1.0 + (charge_level - 1) * 0.3
			var player_level: int = player.level if "level" in player else 0
			var level_scale: float = 1.0 + ((player_level - 1) * 0.1)  # +10% per level above 1
			var scale_factor: float = charge_scale * level_scale
			direction_indicator.scale = Vector3(scale_factor, scale_factor, scale_factor)

			# Update indicator color based on level (more intense at higher levels)
			var mat: StandardMaterial3D = direction_indicator.material_override
			if mat:
				if player_level >= 3:
					# Level 3: Bright magenta (shows afterimage + double explosion)
					mat.albedo_color = Color(1.0, 0.4, 0.8, 0.25)
				elif player_level >= 2:
					# Level 2: Hot pink (shows double explosion)
					mat.albedo_color = Color(0.95, 0.5, 0.75, 0.22)
				elif player_level >= 1:
					# Level 1: Light magenta (shows end explosion)
					mat.albedo_color = Color(0.9, 0.6, 0.85, 0.18)
				else:
					# Level 0: Subtle neutral
					mat.albedo_color = Color(0.85, 0.75, 0.85, 0.15)

			# Pulse effect while charging (faster at higher levels)
			var pulse_speed: float = 0.008 + ((player_level - 1) * 0.002)
			var pulse = 1.0 + sin(Time.get_ticks_msec() * pulse_speed) * 0.15
			direction_indicator.scale *= pulse
		else:
			# Hide indicator when not charging or not local player
			direction_indicator.visible = false
	else:
		# Player is invalid - hide indicator
		if direction_indicator:
			direction_indicator.visible = false

func activate() -> void:
	if not player:
		return

	# Get charge multiplier for scaled force/knockback (damage stays constant at 1)
	var charge_multiplier: float = get_charge_multiplier()
	var charged_damage: int = damage  # Always 1, no charge scaling on damage
	var charged_dash_force: float = dash_force * charge_multiplier
	var charged_knockback: float = 117.0 * charge_multiplier  # Reduced by 35% from 180.0 for better balance

	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "DASH ATTACK! (Charge level %d, %.1fx power)" % [charge_level, charge_multiplier], false, get_entity_id())

	# Get player's camera/movement direction
	var camera_arm: Node3D = player.get_node_or_null("CameraArm")

	if camera_arm:
		# Dash in camera forward direction (works for both players and bots)
		dash_direction = -camera_arm.global_transform.basis.z
		dash_direction.y = 0
		dash_direction = dash_direction.normalized()

	# Apply initial dash impulse
	if player is RigidBody3D:
		# Clear current velocity for clean dash
		var vel: Vector3 = player.linear_velocity
		vel.x = 0
		vel.z = 0
		player.linear_velocity = vel

		# Scale dash force with player level (1.0 + 0.3 per level)
		var level_multiplier: float = 1.0
		if player and "level" in player:
			level_multiplier = 1.0 + ((player.level - 1) * 0.3)

		# Apply charged dash force
		player.apply_central_impulse(dash_direction * charged_dash_force * level_multiplier)

		# Small upward impulse for style
		player.apply_central_impulse(Vector3.UP * 5.0)

	# Start dash
	is_dashing = true
	dash_timer = dash_duration
	hit_players.clear()
	dash_start_position = player.global_position
	afterimage_timer = 0.0

	# Level-based effect: Level 2+ creates explosion at dash START
	var player_level: int = player.level if player and "level" in player else 0
	if player_level >= 2:
		spawn_dash_explosion(player.global_position, player_level)

	# Scale hitbox based on charge level AND player level to match visual indicator
	var charge_scale: float = 1.0 + (charge_level - 1) * 0.3
	var level_scale: float = 1.0 + ((player_level - 1) * 0.1)  # +10% per level above 1 (matches indicator)
	var base_hitbox_radius: float = 1.5
	var scaled_radius: float = base_hitbox_radius * charge_scale * level_scale

	# Enable hitbox
	if hitbox:
		# Update hitbox size to match charge level AND player level
		if hitbox.get_child_count() > 0:
			var collision_shape: CollisionShape3D = hitbox.get_child(0)
			if collision_shape and collision_shape.shape is SphereShape3D:
				collision_shape.shape.radius = scaled_radius

		hitbox.monitoring = true
		hitbox.global_position = player.global_position

	# Enable fire trail
	if fire_trail:
		fire_trail.emitting = true
		fire_trail.global_position = player.global_position

	# Play dash sound
	if ability_sound:
		ability_sound.play()

func _on_hitbox_body_entered(body: Node3D) -> void:
	if not is_dashing or not player:
		return

	# Don't hit ourselves
	if body == player:
		return

	# Don't hit the same player twice in one dash
	if body in hit_players:
		return

	# Check if it's another player
	if body is RigidBody3D and body.has_method("receive_damage_from"):
		# Get charge multiplier and player level multiplier for knockback scaling (damage always 1)
		var charge_multiplier: float = get_charge_multiplier()
		var player_level: int = player.level if player and "level" in player else 0
		var level_mult: float = 1.0 + ((player_level - 1) * 0.2)
		var charged_damage: int = damage  # Always 1, no charge scaling
		var charged_knockback: float = 180.0 * charge_multiplier * level_mult  # Increased from 100.0 for stronger impact

		# Deal damage
		var attacker_id: int = player.name.to_int() if player else -1
		var target_id: int = body.get_multiplayer_authority()

		# CRITICAL FIX: Don't call RPC on ourselves (check if target is local peer)
		if target_id >= 9000 or not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer == null or target_id == multiplayer.get_unique_id():
			# Local call for bots, no multiplayer, or local peer
			body.receive_damage_from(charged_damage, attacker_id)
			DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Dash attack hit player (local): %s | Damage: %d" % [body.name, charged_damage], false, get_entity_id())
		else:
			# RPC call for remote network players only
			body.receive_damage_from.rpc_id(target_id, charged_damage, attacker_id)
			DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Dash attack hit player (RPC): %s | Damage: %d" % [body.name, charged_damage], false, get_entity_id())

		hit_players.append(body)

		# Apply charged knockback to hit player
		var knockback_dir: Vector3 = (body.global_position - player.global_position).normalized()
		knockback_dir.y = 0.3  # Slight upward knockback
		body.apply_central_impulse(knockback_dir * charged_knockback)

		# Play attack hit sound (satisfying feedback for landing a hit)
		play_attack_hit_sound()

		DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Dash attack hit player: %s" % body.name, false, get_entity_id())

func end_dash() -> void:
	# Visual effect at dash END - always spawn explosion scaled by level
	if player and is_instance_valid(player):
		var player_level: int = player.level if "level" in player else 1
		spawn_dash_explosion(player.global_position, player_level)

	is_dashing = false
	hit_players.clear()

	# Disable hitbox
	if hitbox:
		hitbox.monitoring = false

	# Disable fire trail (particles will fade out naturally)
	if fire_trail:
		fire_trail.emitting = false

func _physics_process(delta: float) -> void:
	# Update hitbox and fire trail positions to follow player during dash
	if is_dashing and player:
		if hitbox:
			hitbox.global_position = player.global_position
		if fire_trail:
			fire_trail.global_position = player.global_position

		# Level 3: Spawn afterimages during dash
		# PERF: Skip afterimages for bots on web, and use longer interval on web
		var player_level: int = player.level if "level" in player else 0
		if player_level >= 3 and not (_is_web and _is_bot_owner()):
			afterimage_timer += delta
			var interval: float = 0.1 if _is_web else AFTERIMAGE_INTERVAL  # PERF: 2x longer interval on web
			if afterimage_timer >= interval:
				afterimage_timer = 0.0
				spawn_afterimage(player.global_position)

func play_attack_hit_sound() -> void:
	"""Play satisfying hit sound when attack lands on enemy"""
	# PERF: Use pooled hit sound instead of creating new AudioStreamPlayer3D per hit
	if player:
		play_pooled_hit_sound(player.global_position)

func spawn_dash_explosion(position: Vector3, level: int) -> void:
	"""Spawn a magenta explosion effect at the given position (level-based effect)"""
	if not player or not player.get_parent():
		return

	# PERF: Skip flash for bots on web - visual only, not gameplay-critical
	if _is_web and _is_bot_owner():
		return

	# Scale effect with level
	var scale_mult: float = 0.9 + ((level - 1) * 0.2)  # Level 1: 0.9, Level 2: 1.1, Level 3: 1.3

	_play_dash_flash(position, scale_mult)

	var explosion: CPUParticles3D = _dash_explosion_pool[_dash_explosion_pool_index]
	_dash_explosion_pool_index = (_dash_explosion_pool_index + 1) % _dash_explosion_pool.size()
	explosion.global_position = position

	# Configure explosion particles
	explosion.emitting = true
	var base_amount: int = 10 if _is_web else 20  # PERF: Reduced for performance
	explosion.amount = int(base_amount * scale_mult)
	explosion.lifetime = 0.4
	explosion.one_shot = true
	explosion.explosiveness = 1.0
	explosion.randomness = 0.4
	explosion.local_coords = false

	# PERF: Use shared particle mesh + material
	explosion.mesh = _shared_particle_quad_large

	# Emission shape - sphere burst
	explosion.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	explosion.emission_sphere_radius = 0.3 * scale_mult

	# Movement - explosive outward burst
	explosion.direction = Vector3.ZERO
	explosion.spread = 180.0
	explosion.gravity = Vector3(0, -3.0, 0)
	explosion.initial_velocity_min = 5.0 * scale_mult
	explosion.initial_velocity_max = 12.0 * scale_mult

	# Size over lifetime
	explosion.scale_amount_min = 2.0 * scale_mult
	explosion.scale_amount_max = 4.0 * scale_mult
	explosion.scale_amount_curve = _dash_explosion_curve
	explosion.color_ramp = _dash_explosion_gradient
	explosion.restart()

	_dash_explosion_token += 1
	var token := _dash_explosion_token
	explosion.set_meta("dash_explosion_token", token)
	get_tree().create_timer(explosion.lifetime + 0.5).timeout.connect(func():
		if is_instance_valid(explosion) and explosion.get_meta("dash_explosion_token", -1) == token:
			explosion.emitting = false
	)

func spawn_afterimage(position: Vector3) -> void:
	"""Spawn a ghostly afterimage at the given position (level 3 effect)"""
	if not player or not player.get_parent():
		return

	var afterimage: MeshInstance3D = _afterimage_pool[_afterimage_pool_index]
	_afterimage_pool_index = (_afterimage_pool_index + 1) % _afterimage_pool.size()
	afterimage.global_position = position
	afterimage.scale = Vector3.ONE
	afterimage.visible = true

	# Fade out and shrink the afterimage
	var mat := afterimage.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color.a = 0.6
	if _afterimage_tweens.has(afterimage) and is_instance_valid(_afterimage_tweens[afterimage]):
		_afterimage_tweens[afterimage].kill()
	var tween: Tween = get_tree().create_tween()
	_afterimage_tweens[afterimage] = tween
	tween.set_parallel(true)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tween.tween_property(afterimage, "scale", Vector3(0.3, 0.3, 0.3), 0.3)
	tween.set_parallel(false)
	tween.tween_callback(func():
		afterimage.visible = false
	)

func create_direction_indicator() -> void:
	"""Create a sphere indicator that shows the dash hitbox area while charging"""
	direction_indicator = MeshInstance3D.new()
	direction_indicator.name = "DashHitboxIndicator"

	# Create a sphere mesh matching the hitbox radius (1.5)
	direction_indicator.mesh = _shared_indicator_mesh

	# Create material - very subtle, transparent, non-distracting
	direction_indicator.material_override = _shared_indicator_material

	# Add particles around the sphere for extra visual feedback
	var sphere_particles: CPUParticles3D = CPUParticles3D.new()
	sphere_particles.name = "SphereParticles"
	direction_indicator.add_child(sphere_particles)

	# Configure particles - orbiting around the sphere
	sphere_particles.emitting = true
	sphere_particles.amount = 4 if _is_web else 8  # PERF: Reduced for performance
	sphere_particles.lifetime = 0.8
	sphere_particles.explosiveness = 0.0
	sphere_particles.randomness = 0.2
	sphere_particles.local_coords = true

	# PERF: Use shared particle mesh + material
	sphere_particles.mesh = _shared_particle_quad_small

	# Emission shape - sphere surface matching hitbox
	sphere_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	sphere_particles.emission_sphere_radius = 1.5  # Match hitbox radius

	# Movement - slow drift outward
	sphere_particles.direction = Vector3(0, 0, 0)
	sphere_particles.spread = 180.0
	sphere_particles.gravity = Vector3.ZERO
	sphere_particles.initial_velocity_min = 0.3
	sphere_particles.initial_velocity_max = 0.8

	# Size
	sphere_particles.scale_amount_min = 1.0
	sphere_particles.scale_amount_max = 1.5

	# Color - very subtle neutral purple gradient
	sphere_particles.color_ramp = _shared_indicator_gradient

func _build_dash_flash() -> void:
	if _dash_flash_container:
		return

	_dash_flash_container = Node3D.new()
	_dash_flash_container.name = "DashFlash"
	add_child(_dash_flash_container)
	_dash_flash_container.visible = false

	var flash_size: float = 1.5
	var radial_segs: int = 6 if _is_web else 12
	var ring_count: int = 3 if _is_web else 6

	var outer_flash: MeshInstance3D = MeshInstance3D.new()
	var outer_sphere: SphereMesh = SphereMesh.new()
	outer_sphere.radius = flash_size * 2.0
	outer_sphere.height = flash_size * 4.0
	outer_sphere.radial_segments = radial_segs
	outer_sphere.rings = ring_count
	outer_flash.mesh = outer_sphere
	_dash_flash_outer_mat = StandardMaterial3D.new()
	_dash_flash_outer_mat.albedo_color = Color(0.8, 0.2, 0.6, 0.3)
	_dash_flash_outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dash_flash_outer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_dash_flash_outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outer_flash.material_override = _dash_flash_outer_mat
	_dash_flash_container.add_child(outer_flash)

	var core_flash: MeshInstance3D = MeshInstance3D.new()
	var core_sphere: SphereMesh = SphereMesh.new()
	core_sphere.radius = flash_size * 0.8
	core_sphere.height = flash_size * 1.6
	core_sphere.radial_segments = radial_segs
	core_sphere.rings = ring_count
	core_flash.mesh = core_sphere
	_dash_flash_core_mat = StandardMaterial3D.new()
	_dash_flash_core_mat.albedo_color = Color(1.0, 0.7, 0.95, 0.8)
	_dash_flash_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dash_flash_core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_dash_flash_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_flash.material_override = _dash_flash_core_mat
	_dash_flash_container.add_child(core_flash)

func _play_dash_flash(position: Vector3, scale_mult: float) -> void:
	if not _dash_flash_container:
		return
	_dash_flash_container.global_position = position
	_dash_flash_container.scale = Vector3.ONE * scale_mult
	_dash_flash_container.visible = true

	if _dash_flash_outer_mat:
		_dash_flash_outer_mat.albedo_color.a = 0.3
	if _dash_flash_core_mat:
		_dash_flash_core_mat.albedo_color.a = 0.8
	if _dash_flash_tween and is_instance_valid(_dash_flash_tween):
		_dash_flash_tween.kill()
	_dash_flash_tween = get_tree().create_tween()
	_dash_flash_tween.set_parallel(true)
	_dash_flash_tween.tween_property(_dash_flash_outer_mat, "albedo_color:a", 0.0, 0.25)
	_dash_flash_tween.tween_property(_dash_flash_core_mat, "albedo_color:a", 0.0, 0.15)
	_dash_flash_tween.set_parallel(false)
	_dash_flash_tween.tween_interval(0.25)
	_dash_flash_tween.tween_callback(func():
		if _dash_flash_container:
			_dash_flash_container.visible = false
	)

func _build_dash_explosion_pool() -> void:
	if _dash_explosion_pool.size() > 0:
		return

	_dash_explosion_curve = Curve.new()
	_dash_explosion_curve.add_point(Vector2(0, 1.5))
	_dash_explosion_curve.add_point(Vector2(0.3, 1.2))
	_dash_explosion_curve.add_point(Vector2(1, 0.0))

	_dash_explosion_gradient = Gradient.new()
	_dash_explosion_gradient.add_point(0.0, Color(1.0, 0.6, 1.0, 1.0))
	_dash_explosion_gradient.add_point(0.2, Color(1.0, 0.3, 0.8, 1.0))
	_dash_explosion_gradient.add_point(0.5, Color(0.8, 0.1, 0.6, 0.7))
	_dash_explosion_gradient.add_point(1.0, Color(0.3, 0.0, 0.2, 0.0))

	for i in range(DASH_EXPLOSION_POOL_SIZE):
		var explosion: CPUParticles3D = CPUParticles3D.new()
		explosion.name = "DashExplosion_%d" % i
		add_child(explosion)
		explosion.emitting = false
		explosion.one_shot = true
		explosion.explosiveness = 1.0
		explosion.randomness = 0.4
		explosion.local_coords = false
		explosion.mesh = _shared_particle_quad_large
		explosion.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		explosion.direction = Vector3.ZERO
		explosion.spread = 180.0
		explosion.gravity = Vector3(0, -3.0, 0)
		explosion.scale_amount_curve = _dash_explosion_curve
		explosion.color_ramp = _dash_explosion_gradient
		_dash_explosion_pool.append(explosion)

func _build_afterimage_pool() -> void:
	if _afterimage_pool.size() > 0:
		return

	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8 if _is_web else 16
	sphere.rings = 4 if _is_web else 8

	for i in range(AFTERIMAGE_POOL_SIZE):
		var afterimage: MeshInstance3D = MeshInstance3D.new()
		afterimage.name = "DashAfterimage_%d" % i
		afterimage.mesh = sphere
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.3, 0.8, 0.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.disable_receive_shadows = true
		afterimage.material_override = mat
		afterimage.visible = false
		add_child(afterimage)
		_afterimage_pool.append(afterimage)

	# Initially hidden (will show when charging)
	direction_indicator.visible = false

func drop() -> void:
	"""Override drop to clean up indicator and dash state"""
	# BUGFIX: End dash if currently dashing (fixes stuck dash attack state)
	if is_dashing:
		end_dash()

	# Call parent drop first to handle ability drop logic
	if has_method("super"):
		super.drop()
	cleanup_indicator()

func cleanup_indicator() -> void:
	"""Clean up the indicator when ability is dropped or destroyed"""
	if direction_indicator and is_instance_valid(direction_indicator):
		if direction_indicator.is_inside_tree():
			direction_indicator.queue_free()
		direction_indicator = null
