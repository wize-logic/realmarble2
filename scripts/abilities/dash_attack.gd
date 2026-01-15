extends Ability

## Dash Attack Ability
## Performs a powerful forward dash that damages enemies on contact
## Like Kirby's dash attack!

@export var dash_force: float = 80.0
@export var dash_duration: float = 0.5
@export var damage: int = 1
@onready var ability_sound: AudioStreamPlayer3D = $DashSound

var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
var hit_players: Array = []  # Track who we've hit this dash

# Hitbox for detecting other players
var hitbox: Area3D = null

# Fire trail particle effect
var fire_trail: CPUParticles3D = null

func _ready() -> void:
	super._ready()
	ability_name = "Dash Attack"
	ability_color = Color.ORANGE_RED
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
	sphere_shape.radius = 1.2  # Slightly larger than player for good hit detection
	collision_shape.shape = sphere_shape
	hitbox.add_child(collision_shape)

	# Connect hitbox signals
	hitbox.body_entered.connect(_on_hitbox_body_entered)

	# Disable hitbox by default
	hitbox.monitoring = false

	# Create fire trail particle effect
	fire_trail = CPUParticles3D.new()
	fire_trail.name = "FireTrail"
	add_child(fire_trail)

	# Configure fire particles - Trail effect
	fire_trail.emitting = false
	fire_trail.amount = 120  # More particles for better trail visibility
	fire_trail.lifetime = 1.2  # Longer lifetime so trail persists
	fire_trail.explosiveness = 0.0  # Continuous emission for smooth trail
	fire_trail.randomness = 0.3
	fire_trail.local_coords = false  # World space - particles stay where emitted

	# Set up particle mesh and material for visibility
	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.5, 0.5)
	fire_trail.mesh = particle_mesh

	# Create material for additive blending (fire effect)
	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.disable_receive_shadows = true
	particle_material.albedo_color = Color(1.0, 0.8, 0.3, 1.0)
	fire_trail.mesh.material = particle_material

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

	# Size over lifetime - start big, shrink gradually
	fire_trail.scale_amount_min = 2.5
	fire_trail.scale_amount_max = 4.0
	fire_trail.scale_amount_curve = Curve.new()
	fire_trail.scale_amount_curve.add_point(Vector2(0, 1.0))
	fire_trail.scale_amount_curve.add_point(Vector2(0.4, 0.8))
	fire_trail.scale_amount_curve.add_point(Vector2(1, 0.1))

	# Color - fire gradient (yellow -> orange -> red -> black)
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 1.0, 0.5, 1.0))  # Bright yellow
	gradient.add_point(0.3, Color(1.0, 0.6, 0.2, 1.0))  # Orange
	gradient.add_point(0.6, Color(1.0, 0.2, 0.1, 0.8))  # Red
	gradient.add_point(1.0, Color(0.2, 0.0, 0.0, 0.0))  # Dark/transparent
	fire_trail.color_ramp = gradient

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

func activate() -> void:
	if not player:
		return

	# Get charge multiplier for scaled damage/force
	var charge_multiplier: float = get_charge_multiplier()
	var charged_damage: int = int(damage * charge_multiplier)
	var charged_dash_force: float = dash_force * charge_multiplier
	var charged_knockback: float = 40.0 * charge_multiplier

	print("DASH ATTACK! (Charge level %d, %.1fx power)" % [charge_level, charge_multiplier])

	# Get player's camera/movement direction
	var camera_arm: Node3D = player.get_node_or_null("CameraArm")

	if camera_arm:
		# Dash in camera forward direction
		dash_direction = -camera_arm.global_transform.basis.z
		dash_direction.y = 0
		dash_direction = dash_direction.normalized()
	else:
		# Fallback for bots: use player's facing direction (rotation.y)
		dash_direction = Vector3(sin(player.rotation.y), 0, cos(player.rotation.y))

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
			level_multiplier = 1.0 + (player.level * 0.3)

		# Apply charged dash force
		player.apply_central_impulse(dash_direction * charged_dash_force * level_multiplier)

		# Small upward impulse for style
		player.apply_central_impulse(Vector3.UP * 5.0)

	# Start dash
	is_dashing = true
	dash_timer = dash_duration
	hit_players.clear()

	# Enable hitbox
	if hitbox:
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
		# Get charge multiplier and player level multiplier for damage/knockback scaling
		var charge_multiplier: float = get_charge_multiplier()
		var player_level: int = player.level if player and "level" in player else 0
		var level_mult: float = 1.0 + (player_level * 0.2)
		var charged_damage: int = int(damage * charge_multiplier)
		var charged_knockback: float = 40.0 * charge_multiplier * level_mult

		# Deal damage
		var attacker_id: int = player.name.to_int() if player else -1
		var target_id: int = body.get_multiplayer_authority()

		# CRITICAL FIX: Don't call RPC on ourselves (check if target is local peer)
		if target_id >= 9000 or multiplayer.multiplayer_peer == null or target_id == multiplayer.get_unique_id():
			# Local call for bots, no multiplayer, or local peer
			body.receive_damage_from(charged_damage, attacker_id)
			print("Dash attack hit player (local): ", body.name, " | Damage: ", charged_damage)
		else:
			# RPC call for remote network players only
			body.receive_damage_from.rpc_id(target_id, charged_damage, attacker_id)
			print("Dash attack hit player (RPC): ", body.name, " | Damage: ", charged_damage)

		hit_players.append(body)

		# Apply charged knockback to hit player
		var knockback_dir: Vector3 = (body.global_position - player.global_position).normalized()
		knockback_dir.y = 0.3  # Slight upward knockback
		body.apply_central_impulse(knockback_dir * charged_knockback)

		# Play attack hit sound (satisfying feedback for landing a hit)
		play_attack_hit_sound()

		print("Dash attack hit player: ", body.name)

func end_dash() -> void:
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
