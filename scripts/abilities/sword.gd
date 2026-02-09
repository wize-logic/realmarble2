extends Ability

## Sword Ability
## Performs a melee slash attack in an arc in front of the player
## High damage, close range, satisfying slash effect

@export var slash_damage: int = 2
@export var slash_range: float = 3.0  # Range of the sword swing
@export var slash_arc_angle: float = 90.0  # Degrees of arc (90 = quarter circle)
@export var slash_duration: float = 0.3  # How long the slash hitbox is active
@onready var ability_sound: AudioStreamPlayer3D = $SwordSound

var is_slashing: bool = false
var slash_timer: float = 0.0
var hit_players: Array = []  # Track who we've hit this slash

# Hitbox for detecting other players
var slash_hitbox: Area3D = null

# Slash visual effect
var slash_particles: CPUParticles3D = null

# Arc indicator for sword swing range
var arc_indicator: Node3D = null
var _ground_ray_timer: float = 0.0  # Throttle ground raycast for indicator
var _cached_ground_pos: Vector3 = Vector3.ZERO  # Cached ground hit position
var _indicator_ray_query: PhysicsRayQueryParameters3D = null  # Reuse query object

# PERF: Reusable pooled effects to avoid per-swing allocations/hitches
const SPIN_RING_POOL_SIZE: int = 2
const FLASH_POOL_SIZE: int = 2
var _spin_ring_pool: Array[CPUParticles3D] = []
var _spin_ring_pool_index: int = 0
var _flash_pool: Array[Dictionary] = []
var _flash_pool_index: int = 0
static var _spin_ring_mesh: QuadMesh = null
static var _spin_ring_gradient: Gradient = null
static var _flash_burst_gradient: Gradient = null

func _ready() -> void:
	super._ready()
	ability_name = "Sword"
	ability_color = Color.STEEL_BLUE
	cooldown_time = 1.0
	supports_charging = true  # Sword supports charging for more damage
	max_charge_time = 2.0  # 2 seconds for max charge

	# Create slash hitbox
	slash_hitbox = Area3D.new()
	slash_hitbox.name = "SwordSlashHitbox"
	slash_hitbox.collision_layer = 0
	slash_hitbox.collision_mask = 2  # Detect players (layer 2)
	add_child(slash_hitbox)

	# Create a box-shaped hitbox in front of player - flat and horizontal, no upward extension
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(slash_range * 2, 0.3, slash_range)  # Wide horizontal slash, minimal height
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0, 0, -slash_range / 2)  # Position in front of player
	slash_hitbox.add_child(collision_shape)

	# Connect hitbox signals
	slash_hitbox.body_entered.connect(_on_slash_hitbox_body_entered)

	# Disable hitbox by default
	slash_hitbox.monitoring = false

	# Create slash particle effect (visible attack effect - keep for bots)
	slash_particles = CPUParticles3D.new()
	slash_particles.name = "SlashParticles"
	add_child(slash_particles)

	# Configure slash particles - horizontal arc (enhanced for visual impact)
	slash_particles.emitting = false
	slash_particles.amount = 15 if _is_web else 30  # PERF: Reduced for performance
	slash_particles.lifetime = 0.4  # Slightly longer for visibility
	slash_particles.one_shot = true
	slash_particles.explosiveness = 1.0
	slash_particles.randomness = 0.3
	slash_particles.local_coords = false

	# PERF: Use shared particle mesh + material
	slash_particles.mesh = _shared_particle_quad_large

	# Emission shape - arc in front
	slash_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	slash_particles.emission_sphere_radius = 0.5  # Wider emission

	# Movement - slash arc with more energy
	slash_particles.direction = Vector3(0, 0, -1)  # Forward
	slash_particles.spread = slash_arc_angle / 2  # Spread in arc
	slash_particles.gravity = Vector3.ZERO
	slash_particles.initial_velocity_min = 12.0  # Faster particles
	slash_particles.initial_velocity_max = 20.0

	# Size over lifetime - bigger, more dramatic
	slash_particles.scale_amount_min = 3.0
	slash_particles.scale_amount_max = 6.0
	slash_particles.scale_amount_curve = Curve.new()
	slash_particles.scale_amount_curve.add_point(Vector2(0, 2.5))
	slash_particles.scale_amount_curve.add_point(Vector2(0.3, 1.5))
	slash_particles.scale_amount_curve.add_point(Vector2(1, 0.0))

	# Color - brighter, more vibrant sword slash
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.8, 0.95, 1.0, 1.0))  # Bright cyan-white
	gradient.add_point(0.2, Color(0.6, 0.85, 1.0, 1.0))  # Bright cyan-blue
	gradient.add_point(0.5, Color(0.5, 0.7, 1.0, 0.8))  # Light blue
	gradient.add_point(0.8, Color(0.4, 0.5, 0.9, 0.4))  # Darker blue
	gradient.add_point(1.0, Color(0.2, 0.3, 0.6, 0.0))  # Transparent
	slash_particles.color_ramp = gradient

	# Create arc indicator for sword swing range (human player only)
	if not _is_bot_owner():
		create_arc_indicator()

func _ensure_spin_ring_pool(parent_node: Node) -> void:
	if _spin_ring_pool.size() > 0:
		return
	if _spin_ring_mesh == null:
		_spin_ring_mesh = QuadMesh.new()
		_spin_ring_mesh.size = Vector2(0.5, 0.2)
		_spin_ring_mesh.material = _shared_particle_mat_no_billboard
	if _spin_ring_gradient == null:
		_spin_ring_gradient = Gradient.new()
		_spin_ring_gradient.add_point(0.0, Color(0.7, 0.85, 1.0, 1.0))  # Bright cyan-blue
		_spin_ring_gradient.add_point(0.3, Color(0.6, 0.75, 1.0, 0.8))  # Light blue
		_spin_ring_gradient.add_point(0.7, Color(0.4, 0.5, 0.9, 0.4))  # Darker blue
		_spin_ring_gradient.add_point(1.0, Color(0.2, 0.3, 0.6, 0.0))  # Transparent
	for i in range(SPIN_RING_POOL_SIZE):
		var ring_particles := CPUParticles3D.new()
		ring_particles.name = "SpinAttackRing_%d" % i
		ring_particles.emitting = false
		ring_particles.amount = 15 if _is_web else 30  # PERF: Reduced for performance
		ring_particles.lifetime = 0.4
		ring_particles.one_shot = true
		ring_particles.explosiveness = 1.0
		ring_particles.randomness = 0.2
		ring_particles.local_coords = false
		ring_particles.mesh = _spin_ring_mesh
		ring_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		ring_particles.emission_ring_axis = Vector3.UP
		ring_particles.emission_ring_height = 0.2
		ring_particles.direction = Vector3(1, 0, 0)  # Outward
		ring_particles.spread = 30.0
		ring_particles.gravity = Vector3.ZERO
		ring_particles.initial_velocity_min = 8.0
		ring_particles.initial_velocity_max = 15.0
		ring_particles.scale_amount_min = 3.0
		ring_particles.scale_amount_max = 5.0
		ring_particles.color_ramp = _spin_ring_gradient
		parent_node.add_child(ring_particles)
		_spin_ring_pool.append(ring_particles)

func _ensure_flash_pool(parent_node: Node) -> void:
	if _flash_pool.size() > 0:
		return
	if _flash_burst_gradient == null:
		_flash_burst_gradient = Gradient.new()
		_flash_burst_gradient.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))  # White
		_flash_burst_gradient.add_point(0.3, Color(0.8, 0.9, 1.0, 0.8))  # Bright cyan
		_flash_burst_gradient.add_point(1.0, Color(0.4, 0.6, 1.0, 0.0))  # Fade to blue
	for i in range(FLASH_POOL_SIZE):
		var flash_container := Node3D.new()
		flash_container.name = "SlashFlash_%d" % i
		parent_node.add_child(flash_container)
		flash_container.visible = false

		var outer_flash := MeshInstance3D.new()
		var outer_sphere := SphereMesh.new()
		outer_flash.mesh = outer_sphere
		var outer_mat := StandardMaterial3D.new()
		outer_mat.albedo_color = Color(0.4, 0.6, 1.0, 0.3)
		outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		outer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		outer_flash.material_override = outer_mat
		flash_container.add_child(outer_flash)

		var middle_flash: MeshInstance3D = null
		var middle_sphere: SphereMesh = null
		var middle_mat: StandardMaterial3D = null
		if not _is_web:
			middle_flash = MeshInstance3D.new()
			middle_sphere = SphereMesh.new()
			middle_flash.mesh = middle_sphere
			middle_mat = StandardMaterial3D.new()
			middle_mat.albedo_color = Color(0.7, 0.85, 1.0, 0.6)
			middle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			middle_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			middle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			middle_flash.material_override = middle_mat
			flash_container.add_child(middle_flash)

		var core_flash := MeshInstance3D.new()
		var core_sphere := SphereMesh.new()
		core_flash.mesh = core_sphere
		var core_mat := StandardMaterial3D.new()
		core_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
		core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		core_flash.material_override = core_mat
		flash_container.add_child(core_flash)

		var burst_particles := CPUParticles3D.new()
		burst_particles.name = "FlashBurst"
		burst_particles.emitting = false
		burst_particles.one_shot = true
		burst_particles.explosiveness = 1.0
		burst_particles.local_coords = false
		burst_particles.mesh = _shared_particle_quad_medium
		burst_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		burst_particles.emission_sphere_radius = 0.3
		burst_particles.direction = Vector3.UP
		burst_particles.spread = 180.0
		burst_particles.gravity = Vector3.ZERO
		burst_particles.initial_velocity_min = 10.0
		burst_particles.initial_velocity_max = 20.0
		burst_particles.scale_amount_min = 2.0
		burst_particles.scale_amount_max = 4.0
		burst_particles.color_ramp = _flash_burst_gradient
		flash_container.add_child(burst_particles)

		_flash_pool.append({
			"container": flash_container,
			"outer_sphere": outer_sphere,
			"outer_mat": outer_mat,
			"middle_sphere": middle_sphere,
			"middle_mat": middle_mat,
			"core_sphere": core_sphere,
			"core_mat": core_mat,
			"burst": burst_particles,
		})

func _process(delta: float) -> void:
	super._process(delta)

	if is_slashing:
		slash_timer -= delta

		if slash_timer <= 0.0:
			# End slash
			end_slash()

	# Update arc indicator visibility and orientation based on charging state
	# MULTIPLAYER FIX: Only show indicator to the local player using the ability
	if arc_indicator and player and is_instance_valid(player) and player.is_inside_tree():
		# PERF: Only show indicator for local human player (not bots)
		var is_local_player: bool = is_local_human_player()

		if is_charging and is_local_player:
			# Show indicator while charging (only to local player)
			if not arc_indicator.is_inside_tree():
				# Add indicator to world if not already added
				if player.get_parent():
					player.get_parent().add_child(arc_indicator)

			arc_indicator.visible = true

			# Get player level for level-based indicator changes
			var player_level: int = player.level if "level" in player else 0
			var is_spin_attack: bool = player_level >= 3

			# Get player's camera/movement direction
			var camera_arm: Node3D = player.get_node_or_null("CameraArm")
			var slash_direction: Vector3 = Vector3.FORWARD

			if camera_arm:
				# Arc in camera forward direction (works for both players and bots)
				slash_direction = -camera_arm.global_transform.basis.z
				slash_direction.y = 0
				slash_direction = slash_direction.normalized()

			# Position at player's center (mesh child is already offset forward)
			# Throttle ground raycast to 4Hz and cache query object (was every frame)
			var base_position = player.global_position
			_ground_ray_timer -= delta
			if _ground_ray_timer <= 0.0:
				_ground_ray_timer = 0.25
				if not _indicator_ray_query:
					_indicator_ray_query = PhysicsRayQueryParameters3D.new()
					_indicator_ray_query.exclude = [player]
					_indicator_ray_query.collision_mask = 1
				_indicator_ray_query.from = base_position + Vector3.UP * 50.0
				_indicator_ray_query.to = base_position + Vector3.DOWN * 100.0
				var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
				var result: Dictionary = space_state.intersect_ray(_indicator_ray_query)
				if result:
					_cached_ground_pos = result.position + Vector3.UP * 0.15
				else:
					_cached_ground_pos = base_position

			arc_indicator.global_position = _cached_ground_pos

			# Update indicator mesh based on level (spin attack vs forward arc)
			var mesh_instance: MeshInstance3D = arc_indicator.get_child(0) if arc_indicator.get_child_count() > 0 else null
			if mesh_instance:
				if is_spin_attack:
					# Level 3: Circular indicator for spin attack (if not already a cylinder)
					if not mesh_instance.mesh is CylinderMesh:
						var cylinder: CylinderMesh = CylinderMesh.new()
						cylinder.top_radius = slash_range * 1.2
						cylinder.bottom_radius = slash_range * 1.2
						cylinder.height = 0.1
						mesh_instance.mesh = cylinder
						mesh_instance.position = Vector3.ZERO  # Centered on player

					# Don't orient - spin attack is 360 degrees
					arc_indicator.rotation = Vector3.ZERO
					# Rotate for visual effect
					arc_indicator.rotation.y += delta * 2.0
				else:
					# Level 0-2: Forward arc (if not already a box)
					if not mesh_instance.mesh is BoxMesh:
						var box: BoxMesh = BoxMesh.new()
						box.size = Vector3(slash_range * 2, 0.1, slash_range)
						mesh_instance.mesh = box
						mesh_instance.position = Vector3(0, 0, -slash_range / 2)

					# Orient indicator to face slash direction
					arc_indicator.look_at(arc_indicator.global_position + slash_direction * 5.0, Vector3.UP)

			# Update indicator color based on level
			if mesh_instance and mesh_instance.material_override:
				var mat: StandardMaterial3D = mesh_instance.material_override
				if player_level >= 3:
					# Level 3: Bright blue (spin attack)
					mat.albedo_color = Color(0.6, 0.8, 1.0, 0.25)
				elif player_level >= 2:
					# Level 2: Brighter blue (shockwave)
					mat.albedo_color = Color(0.7, 0.85, 0.95, 0.2)
				elif player_level >= 1:
					# Level 1: Light blue (wider arc)
					mat.albedo_color = Color(0.75, 0.85, 0.92, 0.18)
				else:
					# Level 0: Subtle cool
					mat.albedo_color = Color(0.8, 0.85, 0.9, 0.15)

			# Scale based on charge level AND player level
			var charge_scale: float = 1.0 + (charge_level - 1) * 0.2
			var level_scale: float = 1.0 + ((player_level - 1) * 0.15)
			var scale_factor: float = charge_scale * level_scale
			arc_indicator.scale = Vector3(scale_factor, scale_factor, scale_factor)

			# Pulse effect while charging (faster at higher levels)
			var pulse_speed: float = 0.008 + ((player_level - 1) * 0.002)
			var pulse = 1.0 + sin(Time.get_ticks_msec() * pulse_speed) * 0.12
			arc_indicator.scale *= pulse
		else:
			# Hide indicator when not charging or not local player
			arc_indicator.visible = false
	else:
		# Player is invalid - hide indicator
		if arc_indicator:
			arc_indicator.visible = false

func activate() -> void:
	if not player:
		return

	# Get charge multiplier for scaled damage
	var charge_multiplier: float = get_charge_multiplier()
	var charged_damage: int = int(slash_damage * charge_multiplier)
	var charged_knockback: float = 70.0 * charge_multiplier  # Increased from 30.0 for stronger impact

	# Get player level for level-based effects
	var player_level: int = player.level if "level" in player else 0

	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "SWORD SLASH! (Charge level %d, %.1fx damage, player level %d)" % [charge_level, charge_multiplier, player_level], false, get_entity_id())

	# Get player's camera/movement direction
	var camera_arm: Node3D = player.get_node_or_null("CameraArm")
	var slash_direction: Vector3 = Vector3.FORWARD

	if camera_arm:
		# Slash in camera forward direction (works for both players and bots)
		slash_direction = -camera_arm.global_transform.basis.z
		slash_direction.y = 0
		slash_direction = slash_direction.normalized()

	# Start slash
	is_slashing = true
	slash_timer = slash_duration
	hit_players.clear()

	# Scale hitbox based on charge level and player level
	var charge_scale: float = 1.0 + (charge_level - 1) * 0.2
	var level_scale: float = 1.0 + ((player_level - 1) * 0.15)  # +15% range per level
	var scaled_range: float = slash_range * charge_scale * level_scale

	# Level 3: SPIN ATTACK - 360 degree attack instead of forward arc
	var is_spin_attack: bool = player_level >= 3

	# Position and orient hitbox in front of player
	if slash_hitbox and player:
		# Update hitbox size to match charge level and level scaling
		if slash_hitbox.get_child_count() > 0:
			var collision_shape: CollisionShape3D = slash_hitbox.get_child(0)
			if collision_shape and collision_shape.shape is BoxShape3D:
				if is_spin_attack:
					# For spin attack, use a larger box that covers all around the player
					collision_shape.shape.size = Vector3(scaled_range * 2.5, 0.5, scaled_range * 2.5)
					collision_shape.position = Vector3.ZERO  # Centered on player
				else:
					collision_shape.shape.size = Vector3(scaled_range * 2, 0.3, scaled_range)
					collision_shape.position = Vector3(0, 0, -scaled_range / 2)

		slash_hitbox.global_position = player.global_position
		if not is_spin_attack:
			slash_hitbox.look_at(player.global_position + slash_direction, Vector3.UP)
		slash_hitbox.monitoring = true

	# Trigger slash particles - enhanced at higher levels
	if slash_particles and player:
		# Level 1+: More particles (PERF: halved on web)
		var base_amount: int = 15 if _is_web else 30
		var level_bonus: int = 5 if _is_web else 10
		slash_particles.amount = base_amount + ((player_level - 1) * level_bonus)

		if is_spin_attack:
			# Spin attack: particles emit in all directions
			slash_particles.spread = 180.0
			slash_particles.global_position = player.global_position + Vector3.UP * 0.5
			slash_particles.global_rotation = Vector3.ZERO
			spawn_spin_attack_effect(player.global_position, scaled_range)
		else:
			slash_particles.spread = slash_arc_angle / 2
			slash_particles.global_position = player.global_position + Vector3.UP * 0.5 + slash_direction * 1.5
			slash_particles.global_rotation = slash_hitbox.global_rotation

		slash_particles.emitting = true
		slash_particles.restart()

	# Add a brief light flash for visual impact
	spawn_slash_flash(player.global_position + Vector3.UP * 0.5 + slash_direction * 1.0, player_level)

	# Play slash sound
	if ability_sound:
		ability_sound.global_position = player.global_position
		# Higher pitch for spin attack
		ability_sound.pitch_scale = 1.3 if is_spin_attack else 1.0
		ability_sound.play()

	# Level 2+: Spawn shockwave projectile that travels forward
	if player_level >= 2 and not is_spin_attack:
		spawn_sword_shockwave(player.global_position + Vector3.UP * 0.5, slash_direction, player_level)

func _on_slash_hitbox_body_entered(body: Node3D) -> void:
	if not is_slashing or not player:
		return

	# Don't hit ourselves
	if body == player:
		return

	# Don't hit the same player twice in one slash
	if body in hit_players:
		return

	# Check if it's another player
	if body is RigidBody3D and body.has_method("receive_damage_from"):
		# Get charge multiplier and player level multiplier for this hit
		var charge_multiplier: float = get_charge_multiplier()
		var player_level: int = player.level if player and "level" in player else 0
		var level_mult: float = 1.0 + ((player_level - 1) * 0.2)
		var charged_damage: int = int(slash_damage * charge_multiplier)
		var charged_knockback: float = 70.0 * charge_multiplier * level_mult  # Increased from 30.0 for stronger impact

		# Deal damage
		var attacker_id: int = player.name.to_int() if player else -1
		var target_id: int = body.get_multiplayer_authority()

		# CRITICAL FIX: Don't call RPC on ourselves (check if target is local peer)
		if target_id >= 9000 or multiplayer.multiplayer_peer == null or target_id == multiplayer.get_unique_id():
			# Local call for bots, no multiplayer, or local peer
			body.receive_damage_from(charged_damage, attacker_id)
			DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Sword slash hit player (local): %s | Damage: %d" % [body.name, charged_damage], false, get_entity_id())
		else:
			# RPC call for remote network players only
			body.receive_damage_from.rpc_id(target_id, charged_damage, attacker_id)
			DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Sword slash hit player (RPC): %s | Damage: %d" % [body.name, charged_damage], false, get_entity_id())

		hit_players.append(body)

		# Apply knockback to hit player (scaled by charge)
		var knockback_dir: Vector3 = (body.global_position - player.global_position).normalized()
		knockback_dir.y = 0.2  # Slight upward knockback
		body.apply_central_impulse(knockback_dir * charged_knockback)

		# Play attack hit sound (satisfying feedback for landing a hit)
		play_attack_hit_sound()

		DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Sword slash hit player: %s" % body.name, false, get_entity_id())

func end_slash() -> void:
	is_slashing = false
	hit_players.clear()

	# Disable hitbox
	if slash_hitbox:
		slash_hitbox.monitoring = false

func play_attack_hit_sound() -> void:
	"""Play satisfying hit sound when attack lands on enemy"""
	# PERF: Use pooled hit sound instead of creating new AudioStreamPlayer3D per hit
	if player:
		play_pooled_hit_sound(player.global_position)

func spawn_sword_shockwave(start_position: Vector3, direction: Vector3, level: int) -> void:
	"""Spawn a shockwave projectile that travels forward (Level 2+ effect)"""
	if not player or not player.get_parent():
		return

	# Create shockwave container
	var shockwave: Node3D = Node3D.new()
	shockwave.name = "SwordShockwave"
	player.get_parent().add_child(shockwave)
	shockwave.global_position = start_position

	# Create the visual wave effect (a stretched cylinder/disc)
	var wave_mesh: MeshInstance3D = MeshInstance3D.new()
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = 0.8
	cylinder.bottom_radius = 0.8
	cylinder.height = 0.1
	wave_mesh.mesh = cylinder
	shockwave.add_child(wave_mesh)

	# Rotate to face forward direction
	wave_mesh.rotation.x = PI / 2

	# Create material - steel blue energy wave (GL Compatibility - no emission)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.9, 1.0, 0.85)  # Brighter color to compensate for no emission
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wave_mesh.material_override = mat

	# Add inner brighter core ring for layered glow effect
	var inner_wave: MeshInstance3D = MeshInstance3D.new()
	var inner_cylinder: CylinderMesh = CylinderMesh.new()
	inner_cylinder.top_radius = 0.5
	inner_cylinder.bottom_radius = 0.5
	inner_cylinder.height = 0.15
	inner_wave.mesh = inner_cylinder
	inner_wave.rotation.x = PI / 2
	shockwave.add_child(inner_wave)

	var inner_mat: StandardMaterial3D = StandardMaterial3D.new()
	inner_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)  # White core
	inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inner_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	inner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	inner_wave.material_override = inner_mat

	# Add trailing particles
	var trail: CPUParticles3D = CPUParticles3D.new()
	trail.name = "ShockwaveTrail"
	shockwave.add_child(trail)

	trail.emitting = true
	trail.amount = 8 if _is_web else 15  # PERF: Reduced for performance
	trail.lifetime = 0.4
	trail.explosiveness = 0.0
	trail.randomness = 0.2
	trail.local_coords = false

	# PERF: Use shared particle mesh + material
	trail.mesh = _shared_particle_quad_medium

	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 0.5

	trail.direction = Vector3.ZERO
	trail.spread = 180.0
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.5
	trail.initial_velocity_max = 2.0

	trail.scale_amount_min = 1.5
	trail.scale_amount_max = 2.5

	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.7, 0.85, 1.0, 0.9))  # Bright blue
	gradient.add_point(0.4, Color(0.5, 0.7, 1.0, 0.7))  # Steel blue
	gradient.add_point(1.0, Color(0.3, 0.5, 0.8, 0.0))  # Fade
	trail.color_ramp = gradient

	# Move the shockwave forward over time
	var shockwave_speed: float = 25.0 + ((level - 1) * 5.0)  # Faster at higher levels
	var shockwave_duration: float = 0.6
	var shockwave_damage: int = 1
	var owner_id: int = player.name.to_int() if player else -1
	var hit_targets: Array = []

	# Use a tween to move the shockwave
	var tween: Tween = get_tree().create_tween()
	var end_position: Vector3 = start_position + direction * (shockwave_speed * shockwave_duration)
	tween.tween_property(shockwave, "global_position", end_position, shockwave_duration)
	tween.tween_callback(func():
		if is_instance_valid(shockwave):
			shockwave.queue_free()
	)

	# PERF: Use Area3D for shockwave hit detection instead of polling loop
	var shockwave_area: Area3D = Area3D.new()
	shockwave_area.name = "ShockwaveHitArea"
	shockwave_area.collision_layer = 0
	shockwave_area.collision_mask = 2  # Detect players (layer 2)
	shockwave.add_child(shockwave_area)

	var hit_shape: CollisionShape3D = CollisionShape3D.new()
	var hit_sphere: SphereShape3D = SphereShape3D.new()
	hit_sphere.radius = 2.0  # Hit radius
	hit_shape.shape = hit_sphere
	shockwave_area.add_child(hit_shape)
	shockwave_area.monitoring = true

	# Connect body_entered for event-driven hit detection (no polling needed)
	shockwave_area.body_entered.connect(func(body: Node3D) -> void:
		if not is_instance_valid(player):
			return
		if body == player:
			return
		if body in hit_targets:
			return
		if not body.has_method('receive_damage_from'):
			return
		if "health" in body and body.health <= 0:
			return

		hit_targets.append(body)

		# Deal damage
		var target_id: int = body.get_multiplayer_authority()
		if target_id >= 9000 or multiplayer.multiplayer_peer == null or target_id == multiplayer.get_unique_id():
			body.receive_damage_from(shockwave_damage, owner_id)
		else:
			body.receive_damage_from.rpc_id(target_id, shockwave_damage, owner_id)

		# Apply knockback
		var knockback_dir: Vector3 = direction
		knockback_dir.y = 0.3
		body.apply_central_impulse(knockback_dir * 80.0)
	)

func spawn_spin_attack_effect(position: Vector3, radius: float) -> void:
	"""Spawn a circular slash effect for spin attack (Level 3 effect)"""
	if not player or not player.get_parent():
		return

	# Reuse pooled ring particles to avoid per-use allocations.
	_ensure_spin_ring_pool(player.get_parent())
	var ring_particles: CPUParticles3D = _spin_ring_pool[_spin_ring_pool_index]
	_spin_ring_pool_index = (_spin_ring_pool_index + 1) % _spin_ring_pool.size()
	ring_particles.global_position = position

	# Emit in a ring around player
	ring_particles.emission_ring_radius = radius * 0.8
	ring_particles.emission_ring_inner_radius = 0.5

	ring_particles.emitting = true
	ring_particles.restart()

	# Auto-cleanup
	get_tree().create_timer(ring_particles.lifetime + 0.5).timeout.connect(func():
		if is_instance_valid(ring_particles):
			ring_particles.emitting = false
	)

func spawn_slash_flash(position: Vector3, level: int) -> void:
	"""Spawn a bright flash effect at the slash position (GL Compatibility friendly)"""
	if not player or not player.get_parent():
		return

	# PERF: Skip flash for bots on web - visual only, not gameplay-critical
	if _is_web and _is_bot_owner():
		return

	# Reuse pooled flash containers to avoid per-swing allocations.
	_ensure_flash_pool(player.get_parent())
	var flash_data: Dictionary = _flash_pool[_flash_pool_index]
	_flash_pool_index = (_flash_pool_index + 1) % _flash_pool.size()
	var flash_container: Node3D = flash_data["container"]
	flash_container.global_position = position
	flash_container.visible = true

	# Create multi-layer flash effect using geometry (no lights)
	var flash_size: float = 2.0 + ((level - 1) * 0.5)
	# PERF: Fewer segments on web
	var radial_segs: int = 8 if _is_web else 16
	var ring_count: int = 4 if _is_web else 8

	# Layer 1: Outer glow sphere
	var outer_sphere: SphereMesh = flash_data["outer_sphere"]
	outer_sphere.radius = flash_size * 1.5
	outer_sphere.height = flash_size * 3.0
	outer_sphere.radial_segments = radial_segs
	outer_sphere.rings = ring_count
	var outer_mat: StandardMaterial3D = flash_data["outer_mat"]
	outer_mat.albedo_color = Color(0.4, 0.6, 1.0, 0.3)

	# PERF: On web, skip middle layer - outer + core is sufficient
	var middle_mat: StandardMaterial3D = flash_data["middle_mat"]
	var middle_sphere: SphereMesh = flash_data["middle_sphere"]
	if middle_sphere:
		middle_sphere.radius = flash_size * 0.8
		middle_sphere.height = flash_size * 1.6
		middle_sphere.radial_segments = radial_segs
		middle_sphere.rings = ring_count
		if middle_mat:
			middle_mat.albedo_color = Color(0.7, 0.85, 1.0, 0.6)

	# Layer 3: Bright white core
	var core_sphere: SphereMesh = flash_data["core_sphere"]
	core_sphere.radius = flash_size * 0.3
	core_sphere.height = flash_size * 0.6
	core_sphere.radial_segments = 8 if _is_web else 12
	core_sphere.rings = 4 if _is_web else 6
	var core_mat: StandardMaterial3D = flash_data["core_mat"]
	core_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)

	# Add burst particles for extra impact
	var burst_particles: CPUParticles3D = flash_data["burst"]
	burst_particles.amount = (8 + (level * 2)) if _is_web else (15 + (level * 5))  # PERF: Reduced for performance
	burst_particles.lifetime = 0.25
	burst_particles.emitting = true
	burst_particles.restart()

	# Animate and cleanup
	var tween: Tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(outer_mat, "albedo_color:a", 0.0, 0.2)
	if middle_mat:
		tween.tween_property(middle_mat, "albedo_color:a", 0.0, 0.15)
	tween.tween_property(core_mat, "albedo_color:a", 0.0, 0.1)
	tween.set_parallel(false)
	tween.tween_interval(0.25)
	tween.tween_callback(func():
		flash_container.visible = false
		burst_particles.emitting = false
	)

func create_arc_indicator() -> void:
	"""Create a box indicator that shows the sword hitbox area while charging"""
	arc_indicator = Node3D.new()
	arc_indicator.name = "SwordHitboxIndicator"

	# Create a box mesh matching the actual hitbox dimensions
	# Hitbox is: Vector3(slash_range * 2, 0.3, slash_range) = Vector3(6.0, 0.3, 3.0)
	var mesh_instance = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(slash_range * 2, 0.1, slash_range)  # Match hitbox width and depth, thin for visibility
	mesh_instance.mesh = box

	# Create material - very subtle, transparent, non-distracting
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.85, 0.9, 0.15)  # Subtle cool tone, 15% opacity
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	mat.disable_fog = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides
	mesh_instance.material_override = mat

	# Position in front of player to match hitbox position
	# Hitbox collision_shape.position = Vector3(0, 0, -slash_range / 2)
	mesh_instance.position = Vector3(0, 0, -slash_range / 2)

	arc_indicator.add_child(mesh_instance)

	# Add particles along the edges for extra visual feedback
	var edge_particles: CPUParticles3D = CPUParticles3D.new()
	edge_particles.name = "EdgeParticles"
	arc_indicator.add_child(edge_particles)

	# Configure particles - along the front edge of the hitbox
	edge_particles.emitting = true
	edge_particles.amount = 5 if _is_web else 10  # PERF: Reduced for performance
	edge_particles.lifetime = 0.8
	edge_particles.explosiveness = 0.0
	edge_particles.randomness = 0.15
	edge_particles.local_coords = true

	# PERF: Use shared particle mesh + material
	edge_particles.mesh = _shared_particle_quad_small

	# Emission shape - box matching the hitbox area
	edge_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	edge_particles.emission_box_extents = Vector3(slash_range, 0.1, slash_range / 2)
	edge_particles.position = Vector3(0, 0, -slash_range / 2)  # Match hitbox position

	# Movement - slow upward drift
	edge_particles.direction = Vector3(0, 1, 0)
	edge_particles.spread = 30.0
	edge_particles.gravity = Vector3.ZERO
	edge_particles.initial_velocity_min = 0.3
	edge_particles.initial_velocity_max = 0.8

	# Size
	edge_particles.scale_amount_min = 1.0
	edge_particles.scale_amount_max = 1.5

	# Color - very subtle cool gradient
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.85, 0.9, 0.95, 0.35))  # Subtle cool tone
	gradient.add_point(0.5, Color(0.8, 0.85, 0.9, 0.25))   # Very subtle
	gradient.add_point(1.0, Color(0.75, 0.8, 0.85, 0.0))   # Transparent
	edge_particles.color_ramp = gradient

	# Initially hidden (will show when charging)
	arc_indicator.visible = false

func pickup(p_player: Node) -> void:
	"""Override pickup to pre-initialize effect pools (avoids first-use hitch)"""
	super.pickup(p_player)
	# PERF: Pre-initialize pools now instead of on first activation.
	# On WebGL2, deferred pool creation causes hitches from node allocation + material setup.
	if player and player.get_parent() and not (_is_web and _is_bot_owner()):
		_ensure_flash_pool(player.get_parent())
		_ensure_spin_ring_pool(player.get_parent())

func drop() -> void:
	"""Override drop to clean up indicator"""
	# Call parent drop first to handle ability drop logic
	if has_method("super"):
		super.drop()
	cleanup_indicator()

func cleanup_indicator() -> void:
	"""Clean up the indicator when ability is dropped or destroyed"""
	if arc_indicator and is_instance_valid(arc_indicator):
		if arc_indicator.is_inside_tree():
			arc_indicator.queue_free()
		arc_indicator = null
