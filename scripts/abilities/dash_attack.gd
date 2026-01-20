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

# Hitbox for detecting other players
var hitbox: Area3D = null

# Fire trail particle effect
var fire_trail: CPUParticles3D = null

# Direction indicator for dash targeting
var direction_indicator: MeshInstance3D = null

func _ready() -> void:
	super._ready()
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

	# Create fire trail particle effect
	fire_trail = CPUParticles3D.new()
	fire_trail.name = "FireTrail"
	add_child(fire_trail)

	# Configure fire particles - Trail effect (enhanced for more powerful dash)
	fire_trail.emitting = false
	fire_trail.amount = 180  # Increased from 120 for more intense trail
	fire_trail.lifetime = 1.4  # Increased from 1.2s for longer lasting trail
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

	# Size over lifetime - start big, shrink gradually (enhanced for powerful dash)
	fire_trail.scale_amount_min = 3.5  # Increased from 2.5
	fire_trail.scale_amount_max = 5.5  # Increased from 4.0
	fire_trail.scale_amount_curve = Curve.new()
	fire_trail.scale_amount_curve.add_point(Vector2(0, 1.0))
	fire_trail.scale_amount_curve.add_point(Vector2(0.4, 0.8))
	fire_trail.scale_amount_curve.add_point(Vector2(1, 0.1))

	# Color - magenta gradient (bright magenta -> pink -> purple -> dark)
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.5, 1.0, 1.0))  # Bright magenta
	gradient.add_point(0.3, Color(1.0, 0.2, 0.8, 1.0))  # Hot pink
	gradient.add_point(0.6, Color(0.8, 0.1, 0.6, 0.8))  # Deep magenta
	gradient.add_point(1.0, Color(0.2, 0.0, 0.2, 0.0))  # Dark/transparent
	fire_trail.color_ramp = gradient

	# Create direction indicator for dash targeting
	create_direction_indicator()

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
		# Check if this player is the local player (has multiplayer authority)
		var is_local_player: bool = player.is_multiplayer_authority()

		if is_charging and is_local_player:
			# Show indicator while charging (only to local player)
			if not direction_indicator.is_inside_tree():
				# Add indicator to world if not already added
				if player.get_parent():
					player.get_parent().add_child(direction_indicator)

			direction_indicator.visible = true

			# Get player's camera/movement direction
			var camera_arm: Node3D = player.get_node_or_null("CameraArm")
			var target_direction: Vector3 = Vector3.FORWARD

			if camera_arm:
				# Point in camera forward direction
				target_direction = -camera_arm.global_transform.basis.z
				target_direction.y = 0
				target_direction = target_direction.normalized()
			else:
				# Fallback for bots: use player's facing direction
				target_direction = Vector3(sin(player.rotation.y), 0, cos(player.rotation.y))

			# Position at player's feet, offset in dash direction
			# Use raycasting to find ground below the indicator position
			var base_position = player.global_position + target_direction * 2.0
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

			direction_indicator.global_position = indicator_position

			# Orient indicator to point in dash direction
			direction_indicator.look_at(player.global_position + target_direction * 5.0, Vector3.UP)

			# Scale based on charge level (longer arrow for higher charge)
			var scale_factor = 1.0 + (charge_level - 1) * 0.3
			direction_indicator.scale = Vector3(scale_factor, scale_factor, scale_factor)

			# Pulse effect while charging
			var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.15
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

	# Scale hitbox based on charge level to match visual indicator (+30% per level)
	var charge_scale: float = 1.0 + (charge_level - 1) * 0.3
	var base_hitbox_radius: float = 1.5
	var scaled_radius: float = base_hitbox_radius * charge_scale

	# Enable hitbox
	if hitbox:
		# Update hitbox size to match charge level
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
		var level_mult: float = 1.0 + (player_level * 0.2)
		var charged_damage: int = damage  # Always 1, no charge scaling
		var charged_knockback: float = 180.0 * charge_multiplier * level_mult  # Increased from 100.0 for stronger impact

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

func create_direction_indicator() -> void:
	"""Create an arrow indicator that shows the dash direction while charging"""
	direction_indicator = MeshInstance3D.new()
	direction_indicator.name = "DashDirectionIndicator"

	# Create a cone mesh for the arrow (pointing forward)
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.8
	cone.height = 1.5
	cone.radial_segments = 16
	direction_indicator.mesh = cone

	# Rotate so cone points in the -Z direction (forward)
	direction_indicator.rotation_degrees = Vector3(90, 0, 0)

	# Create material - very subtle, transparent, non-distracting
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.75, 0.85, 0.15)  # Subtle neutral purple-pink, 15% opacity
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	mat.disable_fog = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides
	direction_indicator.material_override = mat

	# Add particles for extra visual feedback
	var arrow_particles: CPUParticles3D = CPUParticles3D.new()
	arrow_particles.name = "ArrowParticles"
	direction_indicator.add_child(arrow_particles)

	# Configure particles - very subtle flowing forward
	arrow_particles.emitting = true
	arrow_particles.amount = 12  # Reduced from 20 for subtlety
	arrow_particles.lifetime = 0.6
	arrow_particles.explosiveness = 0.0
	arrow_particles.randomness = 0.2
	arrow_particles.local_coords = false

	# Set up particle mesh
	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.15, 0.15)
	arrow_particles.mesh = particle_mesh

	# Create material for particles
	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.disable_receive_shadows = true
	arrow_particles.mesh.material = particle_material

	# Emission shape - sphere at arrow tip
	arrow_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	arrow_particles.emission_sphere_radius = 0.3

	# Movement - flow forward along the arrow
	arrow_particles.direction = Vector3(0, 0, -1)  # Forward
	arrow_particles.spread = 15.0
	arrow_particles.gravity = Vector3.ZERO
	arrow_particles.initial_velocity_min = 1.0
	arrow_particles.initial_velocity_max = 2.0

	# Size
	arrow_particles.scale_amount_min = 1.0
	arrow_particles.scale_amount_max = 1.5

	# Color - very subtle neutral purple gradient
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.85, 0.8, 0.9, 0.35))  # Subtle neutral purple
	gradient.add_point(0.5, Color(0.8, 0.75, 0.85, 0.25))  # Very subtle
	gradient.add_point(1.0, Color(0.75, 0.7, 0.8, 0.0))  # Transparent
	arrow_particles.color_ramp = gradient

	# Initially hidden (will show when charging)
	direction_indicator.visible = false

func drop() -> void:
	"""Override drop to clean up indicator"""
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
