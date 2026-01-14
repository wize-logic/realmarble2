extends RigidBody3D

@onready var camera: Camera3D = get_node_or_null("CameraArm/Camera3D")
@onready var camera_arm: Node3D = get_node_or_null("CameraArm")
@onready var ground_ray: RayCast3D = get_node_or_null("GroundRay")
@onready var marble_mesh: MeshInstance3D = get_node_or_null("MarbleMesh")
@onready var jump_sound: AudioStreamPlayer3D = get_node_or_null("JumpSound")
@onready var spin_sound: AudioStreamPlayer3D = get_node_or_null("SpinSound")
@onready var land_sound: AudioStreamPlayer3D = get_node_or_null("LandSound")
@onready var bounce_sound: AudioStreamPlayer3D = get_node_or_null("BounceSound")
@onready var charge_sound: AudioStreamPlayer3D = get_node_or_null("ChargeSound")
@onready var hit_sound: AudioStreamPlayer3D = get_node_or_null("HitSound")
@onready var death_sound: AudioStreamPlayer3D = get_node_or_null("DeathSound")
@onready var spawn_sound: AudioStreamPlayer3D = get_node_or_null("SpawnSound")

# UI Elements
var charge_meter_ui: Control = null
var charge_meter_bar: ProgressBar = null
var charge_meter_label: Label = null

## Number of hits before respawn
@export var health: int = 3
## The xyz position of the random spawns, you can add as many as you want! (16 spawns for 16 players)
@export var spawns: PackedVector3Array = [
	Vector3(0, 2, 0),      # Center
	Vector3(10, 2, 0),     # Ring 1
	Vector3(-10, 2, 0),
	Vector3(0, 2, 10),
	Vector3(0, 2, -10),
	Vector3(10, 2, 10),    # Ring 2 (diagonals)
	Vector3(-10, 2, 10),
	Vector3(10, 2, -10),
	Vector3(-10, 2, -10),
	Vector3(20, 2, 0),     # Ring 3 (further out)
	Vector3(-20, 2, 0),
	Vector3(0, 2, 20),
	Vector3(0, 2, -20),
	Vector3(15, 2, 15),    # Ring 4 (additional positions)
	Vector3(-15, 2, -15),
	Vector3(15, 2, -15)
]

# Camera settings - 3rd person shooter style
var sensitivity: float = 0.005
var controller_sensitivity: float = 0.010
var axis_vector: Vector2
var mouse_captured: bool = true
var camera_distance: float = 5.0  # Closer for shooter feel
var camera_height: float = 2.5  # Lower for better view
var camera_pitch: float = 0.0  # Vertical camera angle
var camera_yaw: float = 0.0  # Horizontal camera angle
var camera_min_pitch: float = -60.0  # Max look down (degrees)
var camera_max_pitch: float = 45.0  # Max look up (degrees)

# Marble movement properties - Shooter style (responsive)
var marble_mass: float = 8.0  # Marbles are dense (glass/steel)
var base_roll_force: float = 300.0  # Significantly increased for climbing slopes
var base_jump_impulse: float = 70.0
var current_roll_force: float = 300.0
var current_jump_impulse: float = 70.0
var max_speed: float = 12.0  # Slightly higher max speed
var air_control: float = 0.4  # Better air control for shooter feel
var base_spin_dash_force: float = 150.0
var current_spin_dash_force: float = 150.0

# Jump system
var jump_count: int = 0
var max_jumps: int = 2  # Double jump!

# Bounce mechanic (Sonic Adventure 2 style)
var is_bouncing: bool = false  # Currently performing bounce attack
var bounce_velocity: float = 40.0  # Strong downward velocity
var bounce_back_impulse: float = 90.0  # Upward impulse on ground hit
var bounce_cooldown: float = 0.0  # Cooldown timer
var bounce_cooldown_time: float = 0.3  # Cooldown duration

# Spin dash properties
var is_charging_spin: bool = false
var is_spin_dashing: bool = false  # Actively spinning from spindash
var spin_dash_timer: float = 0.0  # How long the spin lasts
var spin_charge: float = 0.0
var max_spin_charge: float = 1.5  # Max charge time in seconds
var spin_cooldown: float = 0.0
var spin_cooldown_time: float = 0.8  # Cooldown in seconds (reduced from 1.0)
var charge_spin_rotation: float = 0.0  # For spin animation during charge

# Level up system (3 levels max)
var level: int = 0
const MAX_LEVEL: int = 3
const SPEED_BOOST_PER_LEVEL: float = 20.0  # Speed boost per level
const JUMP_BOOST_PER_LEVEL: float = 15.0   # Jump boost per level
const SPIN_BOOST_PER_LEVEL: float = 30.0   # Spin dash boost per level

# Ground detection
var is_grounded: bool = false

# Ability system
var current_ability: Node = null  # The currently equipped ability

# Death effects
var death_particles: CPUParticles3D = null  # Particle effect for death

# Visual effects
var aura_light: OmniLight3D = null  # Lighting effect around player for visibility

# Falling death state
var is_falling_to_death: bool = false
var fall_death_timer: float = 0.0
var fall_camera_detached: bool = false
var fall_camera_position: Vector3 = Vector3.ZERO

# Debug/cheat properties
var god_mode: bool = false

func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())

func _ready() -> void:
	# Set up RigidBody3D physics properties - shooter style
	mass = marble_mass  # Marbles are dense (glass/steel)
	gravity_scale = 2.5  # Marble gravity - dense and heavy
	linear_damp = 0.5   # Moderate damp for better momentum and ramming
	angular_damp = 0.3   # Low rolling resistance but some friction

	# Physics material properties
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.4  # Higher friction for better control
	physics_material_override.bounce = 0.6     # More bounce for marble ramming and interaction
	physics_material_override.rough = false    # Smooth surface

	# Enable continuous collision detection for fast movement
	continuous_cd = true

	# Lock all rotation to prevent spinning (no torque-based movement)
	lock_rotation = true

	# Set collision layers for player interaction
	collision_layer = 2  # Player layer
	collision_mask = 7   # Collide with world (1), players (2), projectiles (4)

	# Make camera arm ignore parent rotation (prevents rolling with marble)
	if camera_arm:
		camera_arm.top_level = true

	# Set up ground detection raycast
	if not ground_ray:
		ground_ray = RayCast3D.new()
		ground_ray.name = "GroundRay"
		add_child(ground_ray)

	ground_ray.enabled = true
	ground_ray.target_position = Vector3.DOWN * 0.6  # Cast down 0.6 units (slightly more than radius)
	ground_ray.collision_mask = 0xFFFFFFFF  # Check all layers
	ground_ray.collide_with_areas = false
	ground_ray.collide_with_bodies = true

	# Set up sound effects (create nodes if they don't exist)
	if not jump_sound:
		jump_sound = AudioStreamPlayer3D.new()
		jump_sound.name = "JumpSound"
		add_child(jump_sound)
		jump_sound.max_distance = 20.0
		jump_sound.volume_db = -5.0

	if not spin_sound:
		spin_sound = AudioStreamPlayer3D.new()
		spin_sound.name = "SpinSound"
		add_child(spin_sound)
		spin_sound.max_distance = 25.0
		spin_sound.volume_db = 0.0

	if not land_sound:
		land_sound = AudioStreamPlayer3D.new()
		land_sound.name = "LandSound"
		add_child(land_sound)
		land_sound.max_distance = 15.0
		land_sound.volume_db = -8.0

	if not bounce_sound:
		bounce_sound = AudioStreamPlayer3D.new()
		bounce_sound.name = "BounceSound"
		add_child(bounce_sound)
		bounce_sound.max_distance = 20.0
		bounce_sound.volume_db = -2.0

	if not charge_sound:
		charge_sound = AudioStreamPlayer3D.new()
		charge_sound.name = "ChargeSound"
		add_child(charge_sound)
		charge_sound.max_distance = 20.0
		charge_sound.volume_db = -3.0

	if not hit_sound:
		hit_sound = AudioStreamPlayer3D.new()
		hit_sound.name = "HitSound"
		add_child(hit_sound)
		hit_sound.max_distance = 25.0
		hit_sound.volume_db = 0.0

	if not death_sound:
		death_sound = AudioStreamPlayer3D.new()
		death_sound.name = "DeathSound"
		add_child(death_sound)
		death_sound.max_distance = 50.0  # Louder and further reaching
		death_sound.volume_db = 5.0  # Louder than other sounds

	if not spawn_sound:
		spawn_sound = AudioStreamPlayer3D.new()
		spawn_sound.name = "SpawnSound"
		add_child(spawn_sound)
		spawn_sound.max_distance = 30.0
		spawn_sound.volume_db = 0.0

	# Create death particle effect
	if not death_particles:
		death_particles = CPUParticles3D.new()
		death_particles.name = "DeathParticles"
		add_child(death_particles)

		# Configure death particles - explosive burst
		death_particles.emitting = false
		death_particles.amount = 200  # Lots of particles for dramatic effect
		death_particles.lifetime = 2.5
		death_particles.one_shot = true
		death_particles.explosiveness = 1.0
		death_particles.randomness = 0.4
		death_particles.local_coords = false

		# Set up particle mesh
		var particle_mesh: QuadMesh = QuadMesh.new()
		particle_mesh.size = Vector2(0.3, 0.3)
		death_particles.mesh = particle_mesh

		# Create material for particles
		var particle_material: StandardMaterial3D = StandardMaterial3D.new()
		particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		particle_material.vertex_color_use_as_albedo = true
		particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		particle_material.disable_receive_shadows = true
		death_particles.mesh.material = particle_material

		# Emission shape - sphere burst
		death_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		death_particles.emission_sphere_radius = 0.5

		# Movement - explosive burst
		death_particles.direction = Vector3(0, 1, 0)
		death_particles.spread = 180.0  # Full sphere
		death_particles.gravity = Vector3(0, -15.0, 0)
		death_particles.initial_velocity_min = 10.0
		death_particles.initial_velocity_max = 20.0

		# Size over lifetime
		death_particles.scale_amount_min = 2.0
		death_particles.scale_amount_max = 4.0
		death_particles.scale_amount_curve = Curve.new()
		death_particles.scale_amount_curve.add_point(Vector2(0, 1.5))
		death_particles.scale_amount_curve.add_point(Vector2(0.3, 1.0))
		death_particles.scale_amount_curve.add_point(Vector2(1, 0.0))

		# Color gradient - will be set based on player vs bot in spawn_death_particles()
		var gradient: Gradient = Gradient.new()
		gradient.add_point(0.0, Color(1.0, 0.8, 0.2, 1.0))  # Gold
		gradient.add_point(0.3, Color(1.0, 0.3, 0.1, 1.0))  # Red-orange
		gradient.add_point(0.7, Color(0.8, 0.1, 0.1, 0.6))  # Dark red
		gradient.add_point(1.0, Color(0.2, 0.0, 0.0, 0.0))  # Transparent
		death_particles.color_ramp = gradient

	# Set up marble mesh and texture
	if not marble_mesh:
		marble_mesh = MeshInstance3D.new()
		marble_mesh.name = "MarbleMesh"
		add_child(marble_mesh)

		# Create sphere mesh
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		marble_mesh.mesh = sphere

		# Create material with texture
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.9, 1.0)  # Slight blue tint
		mat.metallic = 0.3
		mat.roughness = 0.4
		mat.uv1_scale = Vector3(2.0, 2.0, 2.0)  # Tile the texture

		# Add a procedural texture pattern
		var noise_tex: NoiseTexture2D = NoiseTexture2D.new()
		var noise: FastNoiseLite = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.frequency = 0.05
		noise_tex.noise = noise
		noise_tex.width = 512
		noise_tex.height = 512
		mat.albedo_texture = noise_tex

		marble_mesh.material_override = mat

	# Set up aura light effect for player visibility
	if not aura_light:
		aura_light = OmniLight3D.new()
		aura_light.name = "AuraLight"
		add_child(aura_light)

		# Configure light properties
		aura_light.light_color = Color(0.6, 0.8, 1.0)  # Soft cyan-white
		aura_light.light_energy = 1.5  # Moderate brightness
		aura_light.omni_range = 3.5  # Illumination radius around player
		aura_light.omni_attenuation = 2.0  # Smooth falloff

		# Shadow settings - disable for performance
		aura_light.shadow_enabled = false

	if not is_multiplayer_authority():
		return

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if camera:
		camera.current = true

	# Create charge meter UI
	create_charge_meter_ui()

	# Spawn at fixed position based on player ID
	var player_id: int = str(name).to_int()
	var spawn_index: int = player_id % spawns.size()
	global_position = spawns[spawn_index]

	# Reset velocity on spawn
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func _process(delta: float) -> void:
	# Handle falling death state - MUST run for ALL entities (players AND bots)
	if is_falling_to_death:
		fall_death_timer += delta

		# For players with cameras: keep camera watching the fall
		if is_multiplayer_authority() and camera and camera_arm:
			if not fall_camera_detached:
				fall_camera_position = camera_arm.global_position
				fall_camera_detached = true

			camera_arm.global_position = fall_camera_position
			camera.look_at(global_position, Vector3.UP)

		# Respawn after 2 seconds (works for both players and bots)
		if fall_death_timer >= 2.0:
			print("Fall death timer reached 2.0s, respawning %s" % name)
			respawn()
			is_falling_to_death = false
			fall_camera_detached = false
			fall_death_timer = 0.0
		return  # Skip normal processing while falling to death

	# Early return for non-authority (bots)
	if not is_multiplayer_authority():
		return

	if not camera or not camera_arm:
		return

	sensitivity = Global.sensitivity
	controller_sensitivity = Global.controller_sensitivity

	# Read controller input continuously
	axis_vector = Input.get_vector("look_left", "look_right", "look_up", "look_down")

	# 3rd person shooter camera - Update from controller input
	if axis_vector.length() > 0.0:
		camera_yaw -= axis_vector.x * controller_sensitivity * delta * 60.0
		camera_pitch -= axis_vector.y * controller_sensitivity * delta * 60.0
		camera_pitch = clamp(camera_pitch, camera_min_pitch, camera_max_pitch)

	# Position camera arm at player
	camera_arm.global_position = global_position

	# Apply yaw rotation to camera arm (horizontal look)
	camera_arm.global_rotation = Vector3(0, deg_to_rad(camera_yaw), 0)

	# Calculate camera position - shooter style over-the-shoulder view
	var pitch_rad: float = deg_to_rad(camera_pitch)
	var offset: Vector3 = Vector3(0, camera_height, camera_distance)

	# Apply pitch rotation to offset
	var rotated_offset: Vector3 = Vector3(
		offset.x,
		offset.y * cos(pitch_rad) - offset.z * sin(pitch_rad),
		offset.y * sin(pitch_rad) + offset.z * cos(pitch_rad)
	)

	# Camera occlusion - raycast to prevent clipping through walls
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		camera_arm.global_position,
		camera_arm.global_position + camera_arm.global_transform.basis * rotated_offset
	)
	query.exclude = [self]  # Don't hit the player
	query.collision_mask = 1  # Only check world geometry (layer 1)

	var result: Dictionary = space_state.intersect_ray(query)
	var final_offset: Vector3 = rotated_offset

	if result:
		# Hit something - move camera closer
		var hit_point: Vector3 = result.position
		var local_hit: Vector3 = camera_arm.global_transform.inverse() * hit_point
		# Pull camera back slightly from hit point to avoid clipping
		final_offset = local_hit - (local_hit.normalized() * 0.2)

	# Position camera
	camera.position = final_offset

	# Make camera look at player
	camera.look_at(camera_arm.global_position + Vector3.UP * 0.5, Vector3.UP)

	# Update charge meter UI (for abilities and spin dash)
	update_charge_meter_ui()

# MARBLE ROLLING ANIMATION - Always update for all marbles (including bots)
func _physics_process_marble_roll(delta: float) -> void:
	"""Update marble rolling animation based on velocity"""
	if not marble_mesh:
		return

	if is_spin_dashing:
		# RAPID SPINNING during spindash - spin on all axes
		marble_mesh.rotate_x(delta * 30.0)  # Fast forward spin
		marble_mesh.rotate_y(delta * 25.0)  # Add some tumble
	elif not is_charging_spin:
		# Normal rolling based on movement
		var horizontal_vel: Vector3 = Vector3(linear_velocity.x, 0, linear_velocity.z)
		var speed: float = horizontal_vel.length()

		if speed > 0.1:  # Only roll if moving
			# Calculate roll axis (perpendicular to movement direction)
			var move_dir: Vector3 = horizontal_vel.normalized()
			var roll_axis: Vector3 = Vector3(move_dir.z, 0, -move_dir.x)  # 90 degree rotation (inverted for correct direction)

			# Roll speed based on velocity (marble radius is 0.5)
			var roll_speed: float = speed / 0.5  # Angular velocity = linear velocity / radius

			# Apply rotation
			marble_mesh.rotate(roll_axis.normalized(), roll_speed * delta)

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Mouse look - 3rd person shooter style (handled in _input for priority)
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if camera and camera_arm:
				# Update yaw (horizontal) and pitch (vertical) from mouse movement
				camera_yaw -= event.relative.x * sensitivity * 57.2958  # Convert to degrees
				camera_pitch -= event.relative.y * sensitivity * 57.2958
				camera_pitch = clamp(camera_pitch, camera_min_pitch, camera_max_pitch)
				# Mark event as handled so it doesn't propagate further
				get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Respawn on command
	if Input.is_action_just_pressed("respawn"):
		receive_damage(health)

	# Mouse capture toggle
	if Input.is_action_just_pressed("capture"):
		if mouse_captured:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			mouse_captured = false
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			mouse_captured = true

	# Jump - Space key (with double jump)
	if event is InputEventKey and event.keycode == KEY_SPACE:
		print("Space key detected! Pressed: ", event.pressed, " | Grounded: ", is_grounded, " | Jumps: ", jump_count, "/", max_jumps)
		if event.pressed and not event.echo:
			if jump_count < max_jumps:
				var jump_strength: float = current_jump_impulse
				# Second jump is slightly weaker
				if jump_count == 1:
					jump_strength *= 0.85

				print("JUMPING! (Jump #", jump_count + 1, ") Impulse: ", jump_strength)

				# Cancel vertical velocity for consistent jumps
				var vel: Vector3 = linear_velocity
				vel.y = 0
				linear_velocity = vel

				apply_central_impulse(Vector3.UP * jump_strength)
				jump_count += 1

				# Play jump sound
				if jump_sound and jump_sound.stream:
					play_jump_sound.rpc()
			else:
				print("Can't jump - no jumps remaining (", jump_count, "/", max_jumps, ")")

	# Bounce attack - Right mouse button (Sonic Adventure 2 style)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			# Can only bounce in the air and if not on cooldown
			if not is_grounded and bounce_cooldown <= 0.0 and not is_bouncing:
				print("BOUNCE ATTACK!")
				start_bounce()
			else:
				if is_grounded:
					print("Can't bounce - on ground")
				elif bounce_cooldown > 0.0:
					print("Can't bounce - on cooldown (%.2f)" % bounce_cooldown)
				elif is_bouncing:
					print("Already bouncing")

	# Use ability - E key or controller X button (with charging support)
	if Input.is_action_just_pressed("use_ability"):
		# Start charging the ability
		if current_ability and current_ability.has_method("start_charge"):
			current_ability.start_charge()
	elif Input.is_action_just_released("use_ability"):
		# Release the charged ability
		if current_ability and current_ability.has_method("release_charge"):
			current_ability.release_charge()

	# Drop ability - O key
	if event is InputEventKey and event.keycode == KEY_O:
		if event.pressed and not event.echo:
			if current_ability:
				print("Dropping ability!")
				drop_ability()

	# Spin dash - start charging (Shift key)
	if event is InputEventKey and event.keycode == KEY_SHIFT:
		print("Shift key detected! Pressed: ", event.pressed, " | Grounded: ", is_grounded, " | Cooldown: ", spin_cooldown)
		if event.pressed and not event.echo:
			# Check if game is active
			var world: Node = get_tree().get_root().get_node_or_null("World")
			var game_is_active: bool = world and world.get("game_active")

			if not game_is_active:
				print("Can't spin dash - game not started yet")
			elif is_grounded and spin_cooldown <= 0.0:
				print("Starting spin dash charge!")
				is_charging_spin = true
				spin_charge = 0.0
			else:
				if not is_grounded:
					print("Can't spin dash - not grounded")
				if spin_cooldown > 0.0:
					print("Can't spin dash - on cooldown")

		# Spin dash - release to dash (Shift key)
		if not event.pressed:
			print("Shift released! Charging: ", is_charging_spin, " | Charge amount: ", spin_charge)
			# Check if game is active
			var world: Node = get_tree().get_root().get_node_or_null("World")
			var game_is_active: bool = world and world.get("game_active")

			if is_charging_spin and spin_charge > 0.1 and game_is_active:  # Minimum charge threshold
				print("Executing spin dash!")
				execute_spin_dash()
			elif is_charging_spin:
				if not game_is_active:
					print("Can't spin dash - game not started yet")
				else:
					print("Charge too low: ", spin_charge)
			is_charging_spin = false
			spin_charge = 0.0

func _physics_process(delta: float) -> void:
	# Update marble rolling for ALL marbles (players and bots)
	_physics_process_marble_roll(delta)

	if multiplayer.multiplayer_peer != null:
		if not is_multiplayer_authority():
			return

	# Check if marble is on ground using raycast
	check_ground()

	# Update bounce cooldown
	if bounce_cooldown > 0.0:
		bounce_cooldown -= delta

	# Update spin dash cooldown
	if spin_cooldown > 0.0:
		spin_cooldown -= delta

	# Update spin dash timer (for visual spinning)
	if spin_dash_timer > 0.0:
		spin_dash_timer -= delta
		if spin_dash_timer <= 0.0:
			is_spin_dashing = false

	# Charge spin dash if holding button
	if is_charging_spin:
		spin_charge += delta
		spin_charge = min(spin_charge, max_spin_charge)

		# Spin the marble mesh during charge (gets faster as charge increases)
		if marble_mesh:
			charge_spin_rotation += delta * 20.0 * (1.0 + spin_charge * 3.0)  # Accelerates with charge
			marble_mesh.rotation.y = charge_spin_rotation

		# Play charge sound (looping)
		if charge_sound and not charge_sound.playing:
			charge_sound.play()

		# Don't allow movement while charging
		return
	else:
		# Stop charge sound when not charging
		if charge_sound and charge_sound.playing:
			charge_sound.stop()
		charge_spin_rotation = 0.0

	# Freeze movement until game starts (but allow charging and other systems above)
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if world and not world.get("game_active"):
		return  # Don't process movement until game is active

	# Get input direction relative to camera
	var input_dir := Input.get_vector("left", "right", "up", "down")

	if input_dir != Vector2.ZERO:
		var move_direction: Vector3

		if camera_arm:
			# Get camera's forward direction (ignore Y to keep movement horizontal)
			var cam_forward: Vector3 = -camera_arm.global_transform.basis.z
			cam_forward.y = 0
			cam_forward = cam_forward.normalized()

			var cam_right: Vector3 = camera_arm.global_transform.basis.x
			cam_right.y = 0
			cam_right = cam_right.normalized()

			# Calculate movement direction relative to camera
			# Negate input_dir.y because Input.get_vector returns negative when pressing "up"
			move_direction = (cam_forward * -input_dir.y + cam_right * input_dir.x).normalized()
		else:
			# Fallback: use global directions if no camera
			move_direction = Vector3(input_dir.x, 0, input_dir.y).normalized()

		# Get current horizontal speed
		var horizontal_velocity: Vector3 = Vector3(linear_velocity.x, 0, linear_velocity.z)
		var current_speed: float = horizontal_velocity.length()

		# Apply movement force with reduced control in air
		var control_multiplier: float = 1.0 if is_grounded else air_control
		var force_to_apply: float = current_roll_force * control_multiplier

		# Only apply force if below max speed (or allow air control regardless)
		if current_speed < max_speed or not is_grounded:
			# Apply central force for movement (no torque to prevent spinning)
			apply_central_force(move_direction * force_to_apply)

func check_ground() -> void:
	# Use RayCast3D node for ground detection
	if not ground_ray:
		is_grounded = false
		return

	# Force raycast update
	ground_ray.force_raycast_update()

	var was_grounded: bool = is_grounded
	is_grounded = ground_ray.is_colliding()

	# Handle bounce landing
	if is_grounded and not was_grounded and is_bouncing:
		print("BOUNCE IMPACT! Launching upward with impulse: %.1f" % bounce_back_impulse)

		# Cancel vertical velocity and apply strong upward impulse
		var vel: Vector3 = linear_velocity
		vel.y = 0
		linear_velocity = vel
		apply_central_impulse(Vector3.UP * bounce_back_impulse)

		# End bounce state and start cooldown
		is_bouncing = false
		bounce_cooldown = bounce_cooldown_time

		# Play bounce sound again for impact
		if bounce_sound and bounce_sound.stream:
			play_bounce_sound.rpc()

		print("Bounce complete! Cooldown started")

	# Reset jump count when landing
	if is_grounded and not was_grounded:
		jump_count = 0
		print("Landed! Jump count reset")

		# Play landing sound (only if not bouncing, since bounce has its own sound)
		if land_sound and land_sound.stream and not is_bouncing:
			play_land_sound.rpc()

	# Debug logging every 60 frames (about once per second)
	if Engine.get_physics_frames() % 60 == 0:
		print("Ground check: ", is_grounded, " | Y-pos: ", global_position.y, " | Jumps: ", jump_count, "/", max_jumps)
		if is_grounded:
			print("  Hit: ", ground_ray.get_collider(), " at distance: ", ground_ray.get_collision_point().distance_to(global_position))
		else:
			print("  No ground detected under marble")

	# Log ground state changes
	if was_grounded != is_grounded:
		print("Ground state changed: ", is_grounded, " | Position: ", global_position)

func execute_spin_dash() -> void:
	"""Execute a Sonic-style spin dash"""
	# Calculate dash direction based on camera or input
	var dash_direction: Vector3 = Vector3.ZERO

	# Try to use current input direction
	var input_dir := Input.get_vector("left", "right", "up", "down")

	if input_dir != Vector2.ZERO and camera_arm:
		# Dash in input direction
		var cam_forward: Vector3 = -camera_arm.global_transform.basis.z
		cam_forward.y = 0
		cam_forward = cam_forward.normalized()

		var cam_right: Vector3 = camera_arm.global_transform.basis.x
		cam_right.y = 0
		cam_right = cam_right.normalized()

		dash_direction = (cam_forward * -input_dir.y + cam_right * input_dir.x).normalized()
	elif camera_arm:
		# No input - dash forward relative to camera
		dash_direction = -camera_arm.global_transform.basis.z
		dash_direction.y = 0
		dash_direction = dash_direction.normalized()
	else:
		# Fallback - dash in current velocity direction or forward
		if linear_velocity.length() > 0.1:
			dash_direction = linear_velocity.normalized()
			dash_direction.y = 0
		else:
			dash_direction = Vector3.FORWARD

	# Calculate dash force based on charge (50% to 100% of max force)
	var charge_multiplier: float = 0.5 + (spin_charge / max_spin_charge) * 0.5
	var dash_impulse: float = current_spin_dash_force * charge_multiplier

	# Apply the dash impulse
	apply_central_impulse(dash_direction * dash_impulse)

	# Add small upward impulse for extra flair
	apply_central_impulse(Vector3.UP * 2.5)

	# Start spinning animation
	is_spin_dashing = true
	spin_dash_timer = 1.0  # Spin for 1 second

	# Start cooldown
	spin_cooldown = spin_cooldown_time

	# Play spin dash sound
	if spin_sound and spin_sound.stream:
		play_spin_sound.rpc()

	print("Spin dash! Charge: %.1f%% | Force: %.1f" % [charge_multiplier * 100, dash_impulse])

func start_bounce() -> void:
	"""Start the bounce attack - Sonic Adventure 2 style"""
	if is_bouncing:
		return

	print("Starting bounce attack!")
	is_bouncing = true

	# Cancel all horizontal velocity and apply strong downward velocity
	var vel: Vector3 = linear_velocity
	vel.x = 0
	vel.z = 0
	vel.y = -bounce_velocity  # Strong downward velocity
	linear_velocity = vel

	# Play bounce sound
	if bounce_sound and bounce_sound.stream:
		play_bounce_sound.rpc()

	print("Bounce velocity applied: y=%.1f" % vel.y)

@rpc("any_peer")
func receive_damage(damage: int = 1) -> void:
	if god_mode:
		return  # Immune to damage
	health -= damage
	if health <= 0:
		respawn()

@rpc("any_peer")
func receive_damage_from(damage: int, attacker_id: int) -> void:
	"""Receive damage from a specific player"""
	if god_mode:
		return  # Immune to damage

	health -= damage
	print("Received %d damage from player %d! Health: %d" % [damage, attacker_id, health])

	# Play hit sound
	if hit_sound and hit_sound.stream:
		play_hit_sound.rpc()

	if health <= 0:
		# Notify world of kill
		var world: Node = get_parent()
		if world and world.has_method("add_score"):
			world.add_score(attacker_id, 1)

		# Play death effects before respawning
		spawn_death_particles()
		play_death_sound.rpc()

		# Delay respawn slightly for death effects to be visible
		await get_tree().create_timer(0.1).timeout
		respawn()
		print("Killed by player %d!" % attacker_id)

func respawn() -> void:
	health = 3
	level = 0  # Reset level on death
	jump_count = 0  # Reset jumps
	update_stats()

	# Reset death state
	is_falling_to_death = false
	fall_camera_detached = false
	fall_death_timer = 0.0

	# Reset physics
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	# Move to fixed spawn based on player ID
	var player_id: int = str(name).to_int()
	var is_bot: bool = player_id >= 9000

	if spawns.size() > 0:
		var spawn_index: int = player_id % spawns.size()
		global_position = spawns[spawn_index]
		print("Player %s respawned at spawn %d (is_bot: %s)" % [name, spawn_index, is_bot])
	else:
		print("ERROR: No spawn points available for player %s!" % name)

	# Play spawn sound effect
	if spawn_sound:
		play_spawn_sound.rpc()

func fall_death() -> void:
	"""Called when player falls off the map"""
	var player_id: int = str(name).to_int()
	var is_bot: bool = player_id >= 9000

	print("fall_death() called for %s (is_bot: %s, position: %s)" % [name, is_bot, global_position])

	if is_falling_to_death:
		print("  Already falling to death, ignoring")
		return

	if god_mode:
		print("  God mode enabled, ignoring")
		return

	print("  Starting fall death sequence")
	is_falling_to_death = true
	fall_death_timer = 0.0
	fall_camera_detached = false

	# Let physics continue so marble keeps falling

func collect_orb() -> void:
	"""Call this when player collects a level-up orb"""
	if level < MAX_LEVEL:
		level += 1
		update_stats()
		print("⭐ LEVEL UP! New level: %d | Speed: %.1f | Jump: %.1f | Spin: %.1f" % [level, current_roll_force, current_jump_impulse, current_spin_dash_force])
		# Play jump sound as level up feedback (temporary)
		if jump_sound and jump_sound.stream:
			play_jump_sound.rpc()
	else:
		print("Already at MAX_LEVEL (%d)" % MAX_LEVEL)

func update_stats() -> void:
	"""Update movement stats based on current level"""
	current_roll_force = base_roll_force + (level * SPEED_BOOST_PER_LEVEL)
	current_jump_impulse = base_jump_impulse + (level * JUMP_BOOST_PER_LEVEL)
	current_spin_dash_force = base_spin_dash_force + (level * SPIN_BOOST_PER_LEVEL)

func pickup_ability(ability_scene: PackedScene, ability_name: String) -> void:
	"""Pickup a new ability"""
	# Drop current ability if we have one
	if current_ability:
		drop_ability()

	# Instantiate and equip the new ability
	current_ability = ability_scene.instantiate()
	add_child(current_ability)

	# Tell the ability it was picked up
	if current_ability.has_method("pickup"):
		current_ability.pickup(self)

	print("Picked up ability: ", ability_name)

func drop_ability() -> void:
	"""Drop the current ability"""
	if not current_ability:
		return

	# Tell the ability it was dropped
	if current_ability.has_method("drop"):
		current_ability.drop()

	# Remove the ability
	current_ability.queue_free()
	current_ability = null

	print("Dropped ability")

@rpc("call_local")
func use_ability() -> void:
	"""Use the current ability"""
	if current_ability and current_ability.has_method("use"):
		current_ability.use()

# Sound effect RPCs
@rpc("call_local")
func play_jump_sound() -> void:
	if jump_sound and jump_sound.stream:
		jump_sound.pitch_scale = randf_range(0.9, 1.1)  # Slight pitch variation
		jump_sound.play()

@rpc("call_local")
func play_spin_sound() -> void:
	if spin_sound and spin_sound.stream:
		spin_sound.pitch_scale = randf_range(0.95, 1.05)
		spin_sound.play()

@rpc("call_local")
func play_land_sound() -> void:
	if land_sound and land_sound.stream:
		land_sound.pitch_scale = randf_range(0.85, 1.15)
		land_sound.play()

@rpc("call_local")
func play_bounce_sound() -> void:
	if bounce_sound and bounce_sound.stream:
		bounce_sound.pitch_scale = randf_range(0.9, 1.2)
		bounce_sound.play()

@rpc("call_local")
func play_hit_sound() -> void:
	if hit_sound and hit_sound.stream:
		hit_sound.pitch_scale = randf_range(0.9, 1.1)
		hit_sound.play()

@rpc("call_local")
func play_death_sound() -> void:
	"""Play death sound effect - explosion + shatter"""
	if death_sound and death_sound.stream:
		death_sound.pitch_scale = randf_range(0.8, 1.0)  # Lower pitch for dramatic effect
		death_sound.play()

@rpc("call_local")
func play_spawn_sound() -> void:
	"""Play spawn sound effect - whoosh/pop"""
	if spawn_sound and spawn_sound.stream:
		spawn_sound.pitch_scale = randf_range(0.9, 1.2)  # Random pitch variation
		spawn_sound.play()

func spawn_death_particles() -> void:
	"""Spawn death particle effect based on player type (player vs bot)"""
	if not death_particles:
		return

	# Determine if this is a bot (ID >= 9000) or player
	var player_id: int = str(name).to_int()
	var is_bot: bool = player_id >= 9000

	# Set particle colors based on player type
	var gradient: Gradient = Gradient.new()
	if is_bot:
		# Bot death: Blue/gray particles
		gradient.add_point(0.0, Color(0.5, 0.7, 1.0, 1.0))  # Light blue
		gradient.add_point(0.3, Color(0.3, 0.5, 0.9, 1.0))  # Blue
		gradient.add_point(0.7, Color(0.2, 0.3, 0.6, 0.6))  # Dark blue
		gradient.add_point(1.0, Color(0.1, 0.1, 0.2, 0.0))  # Transparent
	else:
		# Player death: Red/gold particles
		gradient.add_point(0.0, Color(1.0, 0.8, 0.2, 1.0))  # Gold
		gradient.add_point(0.3, Color(1.0, 0.3, 0.1, 1.0))  # Red-orange
		gradient.add_point(0.7, Color(0.8, 0.1, 0.1, 0.6))  # Dark red
		gradient.add_point(1.0, Color(0.2, 0.0, 0.0, 0.0))  # Transparent

	death_particles.color_ramp = gradient

	# Trigger particle burst at current position
	death_particles.global_position = global_position
	death_particles.emitting = true
	death_particles.restart()

	print("Death particles spawned for %s (player: %s)" % [name, "human" if not is_bot else "bot"])

# ============================================================================
# UI SYSTEM
# ============================================================================

func create_charge_meter_ui() -> void:
	"""Create the charge meter UI that shows spin dash charge"""
	# Create container
	charge_meter_ui = Control.new()
	charge_meter_ui.name = "ChargeMeterUI"
	charge_meter_ui.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	charge_meter_ui.anchor_left = 0.5
	charge_meter_ui.anchor_right = 0.5
	charge_meter_ui.anchor_top = 1.0
	charge_meter_ui.anchor_bottom = 1.0
	charge_meter_ui.offset_left = -150
	charge_meter_ui.offset_right = 150
	charge_meter_ui.offset_top = -120
	charge_meter_ui.offset_bottom = -80
	charge_meter_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_meter_ui.visible = false
	add_child(charge_meter_ui)

	# Create label
	charge_meter_label = Label.new()
	charge_meter_label.name = "ChargeLabel"
	charge_meter_label.text = "CHARGE"
	charge_meter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	charge_meter_label.add_theme_font_size_override("font_size", 18)
	charge_meter_label.add_theme_color_override("font_color", Color.WHITE)
	charge_meter_label.add_theme_color_override("font_outline_color", Color.BLACK)
	charge_meter_label.add_theme_constant_override("outline_size", 4)
	charge_meter_label.position = Vector2(0, 0)
	charge_meter_label.size = Vector2(300, 20)
	charge_meter_ui.add_child(charge_meter_label)

	# Create progress bar
	charge_meter_bar = ProgressBar.new()
	charge_meter_bar.name = "ChargeBar"
	charge_meter_bar.min_value = 0.0
	charge_meter_bar.max_value = 100.0
	charge_meter_bar.value = 0.0
	charge_meter_bar.show_percentage = false
	charge_meter_bar.position = Vector2(0, 22)
	charge_meter_bar.size = Vector2(300, 18)

	# Style the progress bar
	var style_box_bg: StyleBoxFlat = StyleBoxFlat.new()
	style_box_bg.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	style_box_bg.border_width_left = 2
	style_box_bg.border_width_right = 2
	style_box_bg.border_width_top = 2
	style_box_bg.border_width_bottom = 2
	style_box_bg.border_color = Color.WHITE
	charge_meter_bar.add_theme_stylebox_override("background", style_box_bg)

	var style_box_fill: StyleBoxFlat = StyleBoxFlat.new()
	style_box_fill.bg_color = Color(0.2, 0.8, 1.0, 0.9)  # Cyan
	charge_meter_bar.add_theme_stylebox_override("fill", style_box_fill)

	charge_meter_ui.add_child(charge_meter_bar)

	print("Charge meter UI created")

func update_charge_meter_ui() -> void:
	"""Update the charge meter display"""
	if not charge_meter_ui or not charge_meter_bar or not charge_meter_label:
		return

	# Check if charging ability
	var is_charging_ability: bool = current_ability and current_ability.get("is_charging") == true

	if is_charging_ability:
		# Show meter for ability charging
		charge_meter_ui.visible = true
		charge_meter_label.text = current_ability.ability_name.to_upper()

		var max_charge: float = current_ability.get("max_charge_time") if "max_charge_time" in current_ability else 2.0
		var current_charge: float = current_ability.get("charge_time") if "charge_time" in current_ability else 0.0
		var charge_percent: float = (current_charge / max_charge) * 100.0
		charge_meter_bar.value = charge_percent

		# Change color based on charge level
		var style_box_fill: StyleBoxFlat = charge_meter_bar.get_theme_stylebox("fill")
		if style_box_fill:
			if charge_percent < 50.0:
				style_box_fill.bg_color = Color(1.0, 0.3, 0.3, 0.9)  # Red - level 1
			elif charge_percent < 100.0:
				style_box_fill.bg_color = Color(1.0, 0.8, 0.2, 0.9)  # Yellow - level 2
			else:
				style_box_fill.bg_color = Color(0.2, 1.0, 0.3, 0.9)  # Green - level 3 (max)
	elif is_charging_spin:
		# Show meter for spin dash charging
		charge_meter_ui.visible = true
		charge_meter_label.text = "SPIN DASH"
		var charge_percent: float = (spin_charge / max_spin_charge) * 100.0
		charge_meter_bar.value = charge_percent

		# Change color based on charge level
		var style_box_fill: StyleBoxFlat = charge_meter_bar.get_theme_stylebox("fill")
		if style_box_fill:
			if charge_percent < 33.0:
				style_box_fill.bg_color = Color(1.0, 0.3, 0.3, 0.9)  # Red - low charge
			elif charge_percent < 66.0:
				style_box_fill.bg_color = Color(1.0, 0.8, 0.2, 0.9)  # Yellow - medium charge
			else:
				style_box_fill.bg_color = Color(0.2, 1.0, 0.3, 0.9)  # Green - high charge
	else:
		# Hide meter when not charging anything
		charge_meter_ui.visible = false
