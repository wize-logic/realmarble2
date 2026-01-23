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

	# Create slash particle effect
	slash_particles = CPUParticles3D.new()
	slash_particles.name = "SlashParticles"
	add_child(slash_particles)

	# Configure slash particles - horizontal arc
	slash_particles.emitting = false
	slash_particles.amount = 40
	slash_particles.lifetime = 0.3
	slash_particles.one_shot = true
	slash_particles.explosiveness = 1.0
	slash_particles.randomness = 0.2
	slash_particles.local_coords = false

	# Set up particle mesh
	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.4, 0.1)  # Thin slashes
	slash_particles.mesh = particle_mesh

	# Create material for slash effect
	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED  # Orient with slash
	particle_material.disable_receive_shadows = true
	slash_particles.mesh.material = particle_material

	# Emission shape - arc in front
	slash_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	slash_particles.emission_sphere_radius = 0.3

	# Movement - slash arc
	slash_particles.direction = Vector3(0, 0, -1)  # Forward
	slash_particles.spread = slash_arc_angle / 2  # Spread in arc
	slash_particles.gravity = Vector3.ZERO
	slash_particles.initial_velocity_min = 8.0
	slash_particles.initial_velocity_max = 15.0

	# Size over lifetime - quick slash
	slash_particles.scale_amount_min = 2.0
	slash_particles.scale_amount_max = 4.0
	slash_particles.scale_amount_curve = Curve.new()
	slash_particles.scale_amount_curve.add_point(Vector2(0, 2.0))
	slash_particles.scale_amount_curve.add_point(Vector2(0.5, 1.0))
	slash_particles.scale_amount_curve.add_point(Vector2(1, 0.0))

	# Color - silver/blue sword slash
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.9, 0.9, 1.0, 1.0))  # Bright white-blue
	gradient.add_point(0.3, Color(0.7, 0.8, 1.0, 0.8))  # Light blue
	gradient.add_point(0.7, Color(0.5, 0.6, 0.9, 0.4))  # Darker blue
	gradient.add_point(1.0, Color(0.3, 0.4, 0.6, 0.0))  # Transparent
	slash_particles.color_ramp = gradient

	# Create arc indicator for sword swing range
	create_arc_indicator()

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
		# Check if this player is the local player (has multiplayer authority)
		var is_local_player: bool = player.is_multiplayer_authority()

		if is_charging and is_local_player:
			# Show indicator while charging (only to local player)
			if not arc_indicator.is_inside_tree():
				# Add indicator to world if not already added
				if player.get_parent():
					player.get_parent().add_child(arc_indicator)

			arc_indicator.visible = true

			# Get player's camera/movement direction
			var camera_arm: Node3D = player.get_node_or_null("CameraArm")
			var slash_direction: Vector3 = Vector3.FORWARD

			if camera_arm:
				# Arc in camera forward direction
				slash_direction = -camera_arm.global_transform.basis.z
				slash_direction.y = 0
				slash_direction = slash_direction.normalized()
			else:
				# For bots: aim directly at their current target for accurate hits
				var bot_ai: Node = player.get_node_or_null("BotAI")
				if bot_ai and "target_player" in bot_ai and bot_ai.target_player and is_instance_valid(bot_ai.target_player):
					# Aim at bot's target
					slash_direction = (bot_ai.target_player.global_position - player.global_position).normalized()
					slash_direction.y = 0
					if slash_direction.length() < 0.1:
						# Target too close, use rotation fallback
						slash_direction = Vector3(sin(player.rotation.y), 0, cos(player.rotation.y))
				else:
					# Fallback: use player's facing direction
					slash_direction = Vector3(sin(player.rotation.y), 0, cos(player.rotation.y))

			# Position at player's feet, offset in slash direction
			# Use raycasting to find ground below the indicator position
			var base_position = player.global_position + slash_direction * (slash_range / 2)
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
				indicator_position = result.position + Vector3.UP * 0.15
			else:
				# No ground found - keep at player's Y level
				indicator_position.y = player.global_position.y

			arc_indicator.global_position = indicator_position

			# Orient indicator to face slash direction
			arc_indicator.look_at(player.global_position + slash_direction * 5.0, Vector3.UP)

			# Scale based on charge level (larger arc for higher charge)
			var scale_factor = 1.0 + (charge_level - 1) * 0.2
			arc_indicator.scale = Vector3(scale_factor, scale_factor, scale_factor)

			# Pulse effect while charging
			var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.12
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

	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "SWORD SLASH! (Charge level %d, %.1fx damage)" % [charge_level, charge_multiplier], false, get_entity_id())

	# Get player's camera/movement direction
	var camera_arm: Node3D = player.get_node_or_null("CameraArm")
	var slash_direction: Vector3 = Vector3.FORWARD

	if camera_arm:
		# Slash in camera forward direction
		slash_direction = -camera_arm.global_transform.basis.z
		slash_direction.y = 0
		slash_direction = slash_direction.normalized()
	else:
		# For bots: aim directly at their current target for accurate hits (full 3D aiming)
		var bot_ai: Node = player.get_node_or_null("BotAI")
		if bot_ai and "target_player" in bot_ai and bot_ai.target_player and is_instance_valid(bot_ai.target_player):
			# Aim at bot's target in full 3D (no y-flattening for near-perfect vertical aim)
			slash_direction = (bot_ai.target_player.global_position - player.global_position).normalized()
			if slash_direction.length() < 0.1:
				# Target too close, use rotation fallback
				slash_direction = Vector3(sin(player.rotation.y), 0, cos(player.rotation.y))
		else:
			# Fallback: use player's facing direction (rotation.y)
			slash_direction = Vector3(sin(player.rotation.y), 0, cos(player.rotation.y))

	# Start slash
	is_slashing = true
	slash_timer = slash_duration
	hit_players.clear()

	# Scale hitbox based on charge level to match visual indicator (+20% per level)
	var charge_scale: float = 1.0 + (charge_level - 1) * 0.2
	var scaled_range: float = slash_range * charge_scale

	# Position and orient hitbox in front of player
	if slash_hitbox and player:
		# Update hitbox size to match charge level
		if slash_hitbox.get_child_count() > 0:
			var collision_shape: CollisionShape3D = slash_hitbox.get_child(0)
			if collision_shape and collision_shape.shape is BoxShape3D:
				collision_shape.shape.size = Vector3(scaled_range * 2, 0.3, scaled_range)
				collision_shape.position = Vector3(0, 0, -scaled_range / 2)

		slash_hitbox.global_position = player.global_position
		slash_hitbox.look_at(player.global_position + slash_direction, Vector3.UP)
		slash_hitbox.monitoring = true

	# Trigger slash particles
	if slash_particles and player:
		slash_particles.global_position = player.global_position + Vector3.UP * 0.5 + slash_direction * 1.5
		slash_particles.global_rotation = slash_hitbox.global_rotation
		slash_particles.emitting = true
		slash_particles.restart()

	# Play slash sound
	if ability_sound:
		ability_sound.global_position = player.global_position
		ability_sound.play()

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
		var level_mult: float = 1.0 + (player_level * 0.2)
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

func create_arc_indicator() -> void:
	"""Create an arc indicator that shows the sword swing range while charging"""
	arc_indicator = Node3D.new()
	arc_indicator.name = "SwordArcIndicator"

	# Create a wedge/cone shape to represent the sword arc (90 degree sweep)
	# We'll use a flat cylinder as a wedge pointing forward
	var mesh_instance = MeshInstance3D.new()
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = 0.0  # Point at the player
	cylinder.bottom_radius = slash_range  # Wide arc at max range
	cylinder.height = slash_range  # Distance from player
	cylinder.radial_segments = 16
	cylinder.cap_bottom = true
	cylinder.cap_top = false
	mesh_instance.mesh = cylinder

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

	# Rotate to be horizontal (ground plane) and position forward
	mesh_instance.rotation_degrees = Vector3(90, 0, 0)
	mesh_instance.position = Vector3(0, 0, -slash_range / 2)  # Move forward so point is at origin

	# Scale to make it a narrow arc (90 degrees)
	mesh_instance.scale = Vector3(0.5, 1.0, 1.0)  # Narrow in X to create ~90 degree arc

	arc_indicator.add_child(mesh_instance)

	# Add particles along the arc for extra visual feedback
	var arc_particles: CPUParticles3D = CPUParticles3D.new()
	arc_particles.name = "ArcParticles"
	arc_indicator.add_child(arc_particles)

	# Configure particles - very subtle flowing along the arc
	arc_particles.emitting = true
	arc_particles.amount = 15  # Reduced from 25 for subtlety
	arc_particles.lifetime = 0.8
	arc_particles.explosiveness = 0.0
	arc_particles.randomness = 0.15
	arc_particles.local_coords = true

	# Set up particle mesh
	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.15, 0.15)
	arc_particles.mesh = particle_mesh

	# Create material for particles
	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.disable_receive_shadows = true
	arc_particles.mesh.material = particle_material

	# Emission shape - sphere at the arc edge
	arc_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	arc_particles.emission_sphere_radius = slash_range * 0.4

	# Movement - orbit around the arc
	arc_particles.direction = Vector3(0, 0, 0)
	arc_particles.spread = 0.0
	arc_particles.gravity = Vector3.ZERO
	arc_particles.initial_velocity_min = 0.4
	arc_particles.initial_velocity_max = 1.0

	# Size
	arc_particles.scale_amount_min = 1.0
	arc_particles.scale_amount_max = 1.5

	# Color - very subtle cool gradient
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.85, 0.9, 0.95, 0.35))  # Subtle cool tone
	gradient.add_point(0.5, Color(0.8, 0.85, 0.9, 0.25))   # Very subtle
	gradient.add_point(1.0, Color(0.75, 0.8, 0.85, 0.0))   # Transparent
	arc_particles.color_ramp = gradient

	# Initially hidden (will show when charging)
	arc_indicator.visible = false

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
