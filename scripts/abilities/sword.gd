extends Ability

## Sword Ability
## Performs a melee slash attack in an arc in front of the player
## High damage, close range, satisfying slash effect

@export var slash_damage: int = 2
@export var slash_range: float = 3.0  # Range of the sword swing
@export var slash_arc_angle: float = 90.0  # Degrees of arc (90 = quarter circle)
@export var slash_duration: float = 0.3  # How long the slash hitbox is active

var is_slashing: bool = false
var slash_timer: float = 0.0
var hit_players: Array = []  # Track who we've hit this slash

# Hitbox for detecting other players
var slash_hitbox: Area3D = null

# Slash visual effect
var slash_particles: CPUParticles3D = null

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

	# Create a box-shaped hitbox in front of player
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(slash_range * 2, 2.0, slash_range)  # Wide horizontal slash
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

## Override pickup to reference player's ability sound
func pickup(p_player: Node) -> void:
	super.pickup(p_player)
	# Reference the player's shared ability sound node
	if player:
		ability_sound = player.get_node_or_null("AbilitySound")

func _process(delta: float) -> void:
	super._process(delta)

	if is_slashing:
		slash_timer -= delta

		if slash_timer <= 0.0:
			# End slash
			end_slash()

func activate() -> void:
	if not player:
		return

	# Get charge multiplier for scaled damage
	var charge_multiplier: float = get_charge_multiplier()
	var charged_damage: int = int(slash_damage * charge_multiplier)
	var charged_knockback: float = 30.0 * charge_multiplier

	print("SWORD SLASH! (Charge level %d, %.1fx damage)" % [charge_level, charge_multiplier])

	# Get player's camera/movement direction
	var camera_arm: Node3D = player.get_node_or_null("CameraArm")
	var slash_direction: Vector3 = Vector3.FORWARD

	if camera_arm:
		# Slash in camera forward direction
		slash_direction = -camera_arm.global_transform.basis.z
		slash_direction.y = 0
		slash_direction = slash_direction.normalized()
	else:
		# Fallback for bots: use player's facing direction (rotation.y)
		slash_direction = Vector3(sin(player.rotation.y), 0, cos(player.rotation.y))

	# Start slash
	is_slashing = true
	slash_timer = slash_duration
	hit_players.clear()

	# Position and orient hitbox in front of player
	if slash_hitbox and player:
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
		# Get charge multiplier for this hit
		var charge_multiplier: float = get_charge_multiplier()
		var charged_damage: int = int(slash_damage * charge_multiplier)
		var charged_knockback: float = 30.0 * charge_multiplier

		# Deal damage
		var attacker_id: int = player.name.to_int() if player else -1
		var target_id: int = body.get_multiplayer_authority()

		# CRITICAL FIX: Don't call RPC on ourselves (check if target is local peer)
		if target_id >= 9000 or multiplayer.multiplayer_peer == null or target_id == multiplayer.get_unique_id():
			# Local call for bots, no multiplayer, or local peer
			body.receive_damage_from(charged_damage, attacker_id)
			print("Sword slash hit player (local): ", body.name, " | Damage: ", charged_damage)
		else:
			# RPC call for remote network players only
			body.receive_damage_from.rpc_id(target_id, charged_damage, attacker_id)
			print("Sword slash hit player (RPC): ", body.name, " | Damage: ", charged_damage)

		hit_players.append(body)

		# Apply knockback to hit player (scaled by charge)
		var knockback_dir: Vector3 = (body.global_position - player.global_position).normalized()
		knockback_dir.y = 0.2  # Slight upward knockback
		body.apply_central_impulse(knockback_dir * charged_knockback)

		# Play attack hit sound (satisfying feedback for landing a hit)
		play_attack_hit_sound()

		print("Sword slash hit player: ", body.name)

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
