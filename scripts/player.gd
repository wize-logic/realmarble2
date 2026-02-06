extends RigidBody3D

# Preload orb scene for dropping on death
const OrbScene = preload("res://collectible_orb.tscn")
# Preload ability pickup scene for dropping on death
const AbilityPickupScene = preload("res://ability_pickup.tscn")
# Preload ability scenes for dropping
const DashAttackScene = preload("res://abilities/dash_attack.tscn")
const ExplosionScene = preload("res://abilities/explosion.tscn")
const CannonScene = preload("res://abilities/cannon.tscn")
const SwordScene = preload("res://abilities/sword.tscn")
const LightningStrikeScene = preload("res://abilities/lightning_strike.tscn")

# Ult system
const UltSystemScript = preload("res://scripts/ult_system.gd")

# Beam spawn effect
const BeamSpawnEffect = preload("res://scripts/beam_spawn_effect.gd")

# Marble material manager for unique player colors
var marble_material_manager = preload("res://scripts/marble_material_manager.gd").new()

# Custom color index set from customize panel (-1 means use default logic)
var custom_color_index: int = -1

@onready var camera: Camera3D = get_node_or_null("CameraArm/Camera3D")
@onready var camera_arm: Node3D = get_node_or_null("CameraArm")
@onready var ground_ray: RayCast3D = get_node_or_null("GroundRay")
@onready var marble_mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
@onready var jump_sound: AudioStreamPlayer3D = get_node_or_null("JumpSound")
@onready var spin_sound: AudioStreamPlayer3D = get_node_or_null("SpinSound")
@onready var land_sound: AudioStreamPlayer3D = get_node_or_null("LandSound")
@onready var bounce_sound: AudioStreamPlayer3D = get_node_or_null("BounceSound")
@onready var charge_sound: AudioStreamPlayer3D = get_node_or_null("ChargeSound")
@onready var hit_sound: AudioStreamPlayer3D = get_node_or_null("HitSound")
@onready var death_sound: AudioStreamPlayer3D = get_node_or_null("DeathSound")
@onready var spawn_sound: AudioStreamPlayer3D = get_node_or_null("SpawnSound")
@onready var teleport_sound: AudioStreamPlayer3D = get_node_or_null("TeleportSound")

# UI Elements
var rail_reticle_ui: Control = null  # Reticle for rail targeting

## Number of hits before respawn
@export var health: int = 3
## The xyz position of the random spawns, you can add as many as you want! (16 spawn points available for up to 8 total players)
## Y=4 (raised from 3, originally 2) to prevent bots sinking through floor on spawn at high player density
@export var spawns: PackedVector3Array = [
	Vector3(0, 4, 0),      # Center
	Vector3(10, 4, 0),     # Ring 1
	Vector3(-10, 4, 0),
	Vector3(0, 4, 10),
	Vector3(0, 4, -10),
	Vector3(10, 4, 10),    # Ring 2 (diagonals)
	Vector3(-10, 4, 10),
	Vector3(10, 4, -10),
	Vector3(-10, 4, -10),
	Vector3(20, 4, 0),     # Ring 3 (further out)
	Vector3(-20, 4, 0),
	Vector3(0, 4, 20),
	Vector3(0, 4, -20),
	Vector3(15, 4, 15),    # Ring 4 (additional positions)
	Vector3(-15, 4, -15),
	Vector3(15, 4, -15)
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
var base_roll_force: float = 300.0
var base_jump_impulse: float = 70.0
var current_roll_force: float = 300.0
var current_jump_impulse: float = 70.0
var base_max_speed: float = 12.0  # Base max speed (scales with arena size)
var max_speed: float = 12.0  # Current max speed (scaled)
var air_control: float = 0.4  # Better air control for shooter feel
var base_spin_dash_force: float = 250.0  # Increased from 150.0 for more power
var current_spin_dash_force: float = 250.0

# Arena size scaling - larger arenas need faster movement
var arena_size_multiplier: float = 1.0  # Set by world based on level size

# Jump system
var jump_count: int = 0
var max_jumps: int = 2  # Double jump!

# Bounce mechanic (Sonic Adventure 2 style)
var is_bouncing: bool = false  # Currently performing bounce attack
var bounce_velocity: float = 40.0  # Strong downward velocity
var base_bounce_back_impulse: float = 90.0  # Base upward impulse on ground hit
var current_bounce_back_impulse: float = 90.0  # Current bounce impulse (scales with level)
var bounce_cooldown: float = 0.0  # Cooldown timer
var bounce_cooldown_time: float = 0.3  # Cooldown duration
var bounce_count: int = 0  # Consecutive bounce counter
var max_bounce_count: int = 3  # Maximum consecutive bounces for scaling
var bounce_scale_per_count: float = 1.3  # Multiplier per consecutive bounce (30% increase)

# Rail grinding (Sonic series style) - simplified system
var is_grinding: bool = false  # Currently grinding on a rail
var current_rail: GrindRail = null  # The rail we're currently grinding on
var grind_particles: CPUParticles3D = null  # Spark particles while grinding
var targeted_rail: GrindRail = null  # The rail currently being looked at
var cached_rails: Array[GrindRail] = []  # Cached list of rails in scene (refreshed periodically)
var rails_cache_timer: float = 0.0  # Timer for refreshing rail cache
var rail_targeting_timer: float = 0.0  # Throttle rail targeting checks (perf: was every frame)
var movement_input_direction: Vector3 = Vector3.ZERO  # Stores current movement input (used by rails)
var post_rail_detach_frames: int = 0  # Grace period frames after detaching from rail
var consecutive_air_frames: int = 0  # Counter for consecutive frames in the air

# Jump pad system (Q3 Arena style)
var jump_pad_cooldown: float = 0.0  # Cooldown to prevent repeated triggering
var jump_pad_cooldown_time: float = 1.0  # Cooldown duration
var jump_pad_boost_force: float = 300.0  # Upward boost force (strong launch!)

# Teleporter system (Q3 Arena style)
var teleporter_cooldown: float = 0.0  # Cooldown to prevent repeated triggering
var teleporter_cooldown_time: float = 2.0  # Cooldown duration
var area_detector: Area3D = null  # Area3D for detecting jump pads and teleporters

# Spin dash properties
var is_charging_spin: bool = false
var is_spin_dashing: bool = false  # Actively spinning from spindash
var spin_dash_timer: float = 0.0  # How long the spin lasts
var spin_charge: float = 0.0
var max_spin_charge: float = 1.5  # Max charge time in seconds
var spin_cooldown: float = 0.0
var spin_cooldown_time: float = 0.8  # Cooldown in seconds (reduced from 1.0)
var charge_spin_rotation: float = 0.0  # For spin animation during charge
var spin_dash_target_rotation: float = 0.0  # Target Y rotation during spin dash (faces reticle)

# Level up system (3 levels max)
var level: int = 0
const MAX_LEVEL: int = 3
const SPEED_BOOST_PER_LEVEL: float = 12.5  # Roll force boost per level
const MAX_SPEED_BOOST_PER_LEVEL: float = 1.25  # Max speed boost per level
const JUMP_BOOST_PER_LEVEL: float = 15.0   # Jump boost per level
const SPIN_BOOST_PER_LEVEL: float = 25.0   # Spin dash boost per level
const BOUNCE_BOOST_PER_LEVEL: float = 20.0  # Bounce impulse boost per level

# Killstreak system
var killstreak: int = 0  # Current killstreak count
var last_attacker_id: int = -1  # ID of last player who damaged us
var last_attacker_time: float = 0.0  # Time when last attacked
const ATTACKER_TIMEOUT: float = 5.0  # Seconds before last_attacker is cleared

# Ground detection
var is_grounded: bool = false

# Ability system
var current_ability: Node = null  # The currently equipped ability

# Ultimate system
var ult_system: Node = null

# Death effects
var death_particles: CPUParticles3D = null  # Particle effect for death

# Collection effects
var collection_particles: CPUParticles3D = null  # Particle effect for collecting orbs/abilities

# Visual effects
var aura_light: OmniLight3D = null  # Lighting effect around player for visibility
var jump_bounce_particles: CPUParticles3D = null  # Particle effect for jumps and bounces

# Falling death state
var is_falling_to_death: bool = false
var fall_death_timer: float = 0.0
var fall_camera_detached: bool = false
var fall_camera_position: Vector3 = Vector3.ZERO

# Debug/cheat properties
var god_mode: bool = false

# ============================================================================
# MULTIPLAYER POSITION SYNC
# ============================================================================
# CRITICAL FIX: Periodic position synchronization to prevent desync
# Bots and remote players need their positions broadcast to all clients

const POSITION_SYNC_INTERVAL: float = 0.1  # Sync position 10 times per second
var position_sync_timer: float = 0.0
var target_sync_position: Vector3 = Vector3.ZERO  # Position to interpolate to (for non-authority)
var target_sync_velocity: Vector3 = Vector3.ZERO  # Velocity for prediction
var has_received_sync: bool = false  # True after first sync received

# ============================================================================
# DEBUG HELPERS
# ============================================================================

func get_entity_id() -> int:
	"""Get the player/bot's entity ID for debug logging"""
	return name.to_int()

func is_bot() -> bool:
	"""Check if this entity is a bot"""
	return get_entity_id() >= 9000

# ============================================================================
# MULTIPLAYER POSITION SYNC METHODS
# ============================================================================

func _sync_position_to_clients(delta: float) -> void:
	"""Called by authority to periodically broadcast position to all clients"""
	if not multiplayer.has_multiplayer_peer():
		return

	# Only the authority should broadcast position
	if not is_multiplayer_authority():
		return

	position_sync_timer += delta
	if position_sync_timer >= POSITION_SYNC_INTERVAL:
		position_sync_timer = 0.0
		# Broadcast position and velocity to all clients
		_receive_position_sync.rpc(global_position, linear_velocity)

@rpc("authority", "unreliable_ordered", "call_remote")
func _receive_position_sync(pos: Vector3, vel: Vector3) -> void:
	"""Called on non-authority clients to receive position updates"""
	target_sync_position = pos
	target_sync_velocity = vel
	has_received_sync = true

func _apply_position_sync(delta: float) -> void:
	"""Called by non-authority to interpolate toward synced position"""
	if not has_received_sync:
		return

	# Predict position based on velocity
	var predicted_pos: Vector3 = target_sync_position + target_sync_velocity * delta

	# Interpolate toward predicted position (smooth correction)
	var distance: float = global_position.distance_to(predicted_pos)

	# If too far off, snap to position (teleport threshold)
	if distance > 5.0:
		global_position = predicted_pos
		linear_velocity = target_sync_velocity
	else:
		# Smooth interpolation for small corrections
		global_position = global_position.lerp(predicted_pos, 10.0 * delta)
		# Also sync velocity for better physics prediction
		linear_velocity = linear_velocity.lerp(target_sync_velocity, 5.0 * delta)

# ============================================================================
# LIFECYCLE
# ============================================================================

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
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "[CAMERA] Camera arm top_level set to true", false, get_entity_id())

	# Set up ground detection raycast
	if not ground_ray:
		ground_ray = RayCast3D.new()
		ground_ray.name = "GroundRay"
		add_child(ground_ray)

	ground_ray.enabled = true
	ground_ray.target_position = Vector3.DOWN * 0.85  # Cast down 0.85 units to detect ground on slopes up to 45°
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

	# Create collection particle effect (blue aura rising upward)
	if not collection_particles:
		collection_particles = CPUParticles3D.new()
		collection_particles.name = "CollectionParticles"
		add_child(collection_particles)

		# Configure collection particles - upward blue aura
		collection_particles.emitting = false
		collection_particles.amount = 80  # Moderate amount for smooth aura
		collection_particles.lifetime = 1.5  # Duration of effect
		collection_particles.one_shot = true
		collection_particles.explosiveness = 0.2  # Slightly delayed emission for flowing effect
		collection_particles.randomness = 0.3
		collection_particles.local_coords = false

		# Set up particle mesh
		var collection_particle_mesh: QuadMesh = QuadMesh.new()
		collection_particle_mesh.size = Vector2(0.2, 0.2)
		collection_particles.mesh = collection_particle_mesh

		# Create material for particles
		var collection_particle_material: StandardMaterial3D = StandardMaterial3D.new()
		collection_particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		collection_particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD  # Additive blending for glow
		collection_particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		collection_particle_material.vertex_color_use_as_albedo = true
		collection_particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		collection_particle_material.disable_receive_shadows = true
		collection_particles.mesh.material = collection_particle_material

		# Emission shape - ring at base of player
		collection_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		collection_particles.emission_ring_axis = Vector3.UP
		collection_particles.emission_ring_height = 0.1
		collection_particles.emission_ring_radius = 0.6  # Slightly larger than player radius
		collection_particles.emission_ring_inner_radius = 0.3

		# Movement - upward flow from ground
		collection_particles.direction = Vector3.UP
		collection_particles.spread = 15.0  # Slight spread for natural look
		collection_particles.gravity = Vector3(0, -2.0, 0)  # Slight downward gravity for arc
		collection_particles.initial_velocity_min = 4.0
		collection_particles.initial_velocity_max = 6.0

		# Size over lifetime - start small, grow, then shrink
		collection_particles.scale_amount_min = 1.5
		collection_particles.scale_amount_max = 2.5
		var scale_curve: Curve = Curve.new()
		scale_curve.add_point(Vector2(0, 0.3))
		scale_curve.add_point(Vector2(0.2, 1.2))
		scale_curve.add_point(Vector2(0.6, 1.0))
		scale_curve.add_point(Vector2(1, 0.0))
		collection_particles.scale_amount_curve = scale_curve

		# Color gradient - bright blue aura fading out
		var collection_gradient: Gradient = Gradient.new()
		collection_gradient.add_point(0.0, Color(0.3, 0.7, 1.0, 1.0))  # Bright cyan-blue
		collection_gradient.add_point(0.2, Color(0.4, 0.8, 1.0, 0.9))  # Light blue
		collection_gradient.add_point(0.5, Color(0.5, 0.9, 1.0, 0.7))  # Lighter blue
		collection_gradient.add_point(0.8, Color(0.6, 0.95, 1.0, 0.3))  # Very light blue, fading
		collection_gradient.add_point(1.0, Color(0.7, 1.0, 1.0, 0.0))  # Transparent
		collection_particles.color_ramp = collection_gradient

	# Create jump/bounce particle effect (Sonic Adventure 2 style blue circles)
	if not jump_bounce_particles:
		jump_bounce_particles = CPUParticles3D.new()
		jump_bounce_particles.name = "JumpBounceParticles"
		add_child(jump_bounce_particles)

		# Configure jump/bounce particles - 3 dark blue circles that trail below player
		jump_bounce_particles.emitting = false
		jump_bounce_particles.amount = 3  # Only 3 circles like SA2
		jump_bounce_particles.lifetime = 0.6  # Shorter lifetime for tighter trail
		jump_bounce_particles.one_shot = true
		jump_bounce_particles.explosiveness = 0.9  # Very slight staggered spawn for delayed movement
		jump_bounce_particles.randomness = 0.0  # No randomness
		jump_bounce_particles.local_coords = true  # Local space - aggressively follow player while trailing

		# Set up particle mesh - use sphere for perfect circles (not squares)
		var jump_particle_mesh: SphereMesh = SphereMesh.new()
		jump_particle_mesh.radius = 0.5  # Same as marble radius
		jump_particle_mesh.height = 1.0  # Same as marble diameter
		jump_particle_mesh.radial_segments = 16  # Smooth circle
		jump_particle_mesh.rings = 8
		jump_bounce_particles.mesh = jump_particle_mesh

		# Create material for dark blue semi-transparent circles
		var jump_particle_material: StandardMaterial3D = StandardMaterial3D.new()
		jump_particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		jump_particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		jump_particle_material.albedo_color = Color(0.1, 0.2, 0.5, 0.12)  # Dark blue, almost entirely transparent
		jump_particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		jump_particle_material.disable_receive_shadows = true
		jump_bounce_particles.mesh.material = jump_particle_material

		# Emission shape - point below player
		jump_bounce_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT

		# Movement - particles trail behind player motion at moderate speed
		jump_bounce_particles.direction = Vector3.DOWN  # Default direction (set dynamically)
		jump_bounce_particles.spread = 0.0  # No spread - keep circles in a straight line
		jump_bounce_particles.gravity = Vector3(0, -3.0, 0)  # Moderate gravity for natural arc
		jump_bounce_particles.initial_velocity_min = 1.5  # Trail behind player at moderate speed
		jump_bounce_particles.initial_velocity_max = 2.5

		# Size - constant, same as marble
		jump_bounce_particles.scale_amount_min = 1.0  # Match marble size
		jump_bounce_particles.scale_amount_max = 1.0

		# Fade curve - stay visible then fade at end
		var jump_scale_curve: Curve = Curve.new()
		jump_scale_curve.add_point(Vector2(0, 1.0))  # Full size
		jump_scale_curve.add_point(Vector2(0.5, 1.0))  # Stay full size
		jump_scale_curve.add_point(Vector2(1, 0.0))  # Fade out
		jump_bounce_particles.scale_amount_curve = jump_scale_curve

		# Color gradient - dark blue staying visible then fading
		var jump_gradient: Gradient = Gradient.new()
		jump_gradient.add_point(0.0, Color(0.1, 0.2, 0.5, 0.12))  # Dark blue, almost entirely transparent
		jump_gradient.add_point(0.5, Color(0.1, 0.2, 0.5, 0.12))  # Stay dark blue
		jump_gradient.add_point(1.0, Color(0.1, 0.2, 0.5, 0.0))  # Fade to transparent
		jump_bounce_particles.color_ramp = jump_gradient

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

	# Apply beautiful procedural marble material
	apply_marble_material()

	# Set up aura light effect for player visibility - makes marbles stand out
	if not aura_light:
		aura_light = OmniLight3D.new()
		aura_light.name = "AuraLight"
		add_child(aura_light)

		# Configure light properties - enhanced for marble visibility
		aura_light.light_color = Color(0.6, 0.8, 1.0)  # Will be updated to match marble color
		aura_light.light_energy = 2.5  # Brighter to make marble stand out
		aura_light.omni_range = 5.0  # Larger illumination radius
		aura_light.omni_attenuation = 1.5  # Softer falloff for wider glow

		# Shadow settings - disable for performance
		aura_light.shadow_enabled = false

	# Create grind spark particles (Sonic series style)
	if not grind_particles:
		grind_particles = CPUParticles3D.new()
		grind_particles.name = "GrindParticles"
		add_child(grind_particles)

		# Configure grind particles - sparks flying backward
		grind_particles.emitting = false
		# HTML5 optimization: Reduce particle count for better performance in browsers
		grind_particles.amount = 8 if OS.has_feature("web") else 30
		grind_particles.lifetime = 0.6
		grind_particles.one_shot = false  # Continuous emission while grinding
		grind_particles.explosiveness = 0.1
		grind_particles.randomness = 0.4
		grind_particles.local_coords = false

		# Set up particle mesh
		var grind_particle_mesh: QuadMesh = QuadMesh.new()
		grind_particle_mesh.size = Vector2(0.15, 0.15)
		grind_particles.mesh = grind_particle_mesh

		# Create material for bright spark particles
		var grind_particle_material: StandardMaterial3D = StandardMaterial3D.new()
		grind_particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		grind_particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD  # Additive for bright sparks
		grind_particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		grind_particle_material.vertex_color_use_as_albedo = true
		grind_particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		grind_particle_material.disable_receive_shadows = true
		grind_particles.mesh.material = grind_particle_material

		# Emission shape - point below player
		grind_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT

		# Movement - sparks fly backward and down
		grind_particles.direction = Vector3(0, -1, -1)  # Down and back
		grind_particles.spread = 25.0
		grind_particles.gravity = Vector3(0, -20.0, 0)
		grind_particles.initial_velocity_min = 3.0
		grind_particles.initial_velocity_max = 6.0

		# Size over lifetime
		grind_particles.scale_amount_min = 1.0
		grind_particles.scale_amount_max = 1.5
		var grind_scale_curve: Curve = Curve.new()
		grind_scale_curve.add_point(Vector2(0, 1.2))
		grind_scale_curve.add_point(Vector2(0.3, 1.0))
		grind_scale_curve.add_point(Vector2(1, 0.0))
		grind_particles.scale_amount_curve = grind_scale_curve

		# Color gradient - bright yellow/orange sparks (no white)
		var grind_gradient: Gradient = Gradient.new()
		grind_gradient.add_point(0.0, Color(1.0, 0.9, 0.4, 1.0))  # Bright golden-yellow (no white)
		grind_gradient.add_point(0.2, Color(1.0, 0.8, 0.2, 1.0))  # Yellow
		grind_gradient.add_point(0.5, Color(1.0, 0.4, 0.1, 0.8))  # Orange
		grind_gradient.add_point(1.0, Color(0.5, 0.0, 0.0, 0.0))  # Dark red fade
		grind_particles.color_ramp = grind_gradient

	# Create area detector for jump pads and teleporters (ALL players including bots)
	create_area_detector()

	# In practice mode (no multiplayer peer), we're always the authority
	# Otherwise, only run for nodes we have authority over
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Create ult system
	create_ult_system()

	# Create rail reticle UI
	create_rail_reticle_ui()

	# Spawn at fixed position based on player ID
	var player_id: int = str(name).to_int()
	if spawns.size() > 0:
		var spawn_index: int = player_id % spawns.size()
		global_position = spawns[spawn_index]
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "Player %s spawned at spawn point %d: %s" % [name, spawn_index, global_position], false, get_entity_id())
	else:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "WARNING: No spawn points available! Player %s using default position." % name, false, get_entity_id())
		global_position = Vector3(0, 2, 0)  # Fallback spawn position

	# Reset velocity on spawn
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	# Spawn beam effect on initial spawn
	# Delay slightly to ensure the player is fully set up
	await get_tree().create_timer(0.1).timeout
	spawn_beam_effect()

	# CRITICAL HTML5 FIX: Set camera immediately and use deferred call for persistence
	if camera and camera_arm:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "[CAMERA] Player %s initializing camera. Camera valid: %s" % [name, is_instance_valid(camera)], false, get_entity_id())
		# Position camera arm at player immediately
		camera_arm.global_position = global_position
		# Set camera as current
		camera.current = true
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "[CAMERA] Player %s camera.current set to: %s" % [name, camera.current], false, get_entity_id())
		# Use deferred call to re-confirm after full scene initialization (HTML5 compatibility)
		call_deferred("_force_camera_activation")

func _force_camera_activation() -> void:
	"""Force camera to be active - called via deferred to ensure it happens after full initialization (HTML5 fix)"""
	# CRITICAL: Only local player with authority should activate camera
	# Bots must NEVER activate their cameras or they'll hijack the player camera
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "[CAMERA] Player %s: Skipping camera activation (not authority)" % name, false, get_entity_id())
		return

	if not camera or not camera_arm:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "[CAMERA ERROR] _force_camera_activation: Camera or CameraArm is null for player %s" % name, false, get_entity_id())
		return

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "[CAMERA] _force_camera_activation called for LOCAL PLAYER %s" % name, false, get_entity_id())

	# Position camera arm at current player position
	camera_arm.global_position = global_position

	# Get list of all cameras in the scene
	var all_cameras: Array[Camera3D] = []
	_find_all_cameras(get_tree().root, all_cameras)

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "[CAMERA] Found %d cameras in scene. Setting player %s camera as current..." % [all_cameras.size(), name], false, get_entity_id())

	# Disable all other cameras
	for other_camera in all_cameras:
		if other_camera != camera and other_camera.current:
			DebugLogger.dlog(DebugLogger.Category.PLAYER, "[CAMERA] Disabling other camera: %s" % other_camera.get_path(), false, get_entity_id())
			other_camera.current = false

	# Force our camera to be current
	camera.current = true

	# Force update the transform
	camera_arm.force_update_transform()
	camera.force_update_transform()

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "[CAMERA] Player %s camera.current = %s, global_position = %s" % [name, camera.current, camera.global_position], false, get_entity_id())

func _find_all_cameras(node: Node, camera_list: Array[Camera3D]) -> void:
	"""Recursively find all Camera3D nodes in the scene"""
	if node is Camera3D:
		camera_list.append(node)

	for child in node.get_children():
		_find_all_cameras(child, camera_list)

func _process(delta: float) -> void:
	# CRITICAL HTML5 FIX: Position camera arm FIRST, before ANY other code
	# This MUST run every frame for the camera to follow the player
	if camera_arm and is_instance_valid(camera_arm):
		camera_arm.global_position = global_position
	else:
		if not camera_arm:
			DebugLogger.dlog(DebugLogger.Category.PLAYER, "[CAMERA ERROR] Player %s: camera_arm is NULL in _process!" % name, false, get_entity_id())

	# CRITICAL FIX: Only force camera for local player with authority (not bots!)
	# Bots must NEVER activate their cameras or they'll hijack the player camera
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		# Skip camera activation for bots and non-authority players
		pass
	elif camera and is_instance_valid(camera):
		if not camera.current:
			camera.current = true
			DebugLogger.dlog(DebugLogger.Category.PLAYER, "[CAMERA FIX] Player %s: Forced camera.current = true in _process" % name, false, get_entity_id())
	else:
		if not camera:
			DebugLogger.dlog(DebugLogger.Category.PLAYER, "[CAMERA ERROR] Player %s: camera is NULL in _process!" % name, false, get_entity_id())

	# Handle last attacker timeout
	if last_attacker_id != -1:
		var current_time: float = Time.get_ticks_msec() / 1000.0
		if (current_time - last_attacker_time) > ATTACKER_TIMEOUT:
			last_attacker_id = -1
			last_attacker_time = 0.0

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
			DebugLogger.dlog(DebugLogger.Category.PLAYER, "Fall death timer reached 2.0s, respawning %s" % name, false, get_entity_id())
			respawn()
			is_falling_to_death = false
			fall_camera_detached = false
			fall_death_timer = 0.0
		return  # Skip normal processing while falling to death

	# Early return for non-authority (bots)
	# In practice mode (no multiplayer peer), we're always the authority
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return

	if not camera or not camera_arm:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "[CAMERA ERROR] Player %s: Camera or CameraArm is null! Cannot update camera." % name, false, get_entity_id())
		return

	# CRITICAL HTML5 FIX: Force camera to be current every frame
	sensitivity = Global.sensitivity
	controller_sensitivity = Global.controller_sensitivity

	# Read controller input continuously
	axis_vector = Input.get_vector("look_left", "look_right", "look_up", "look_down")

	# 3rd person shooter camera - Update from controller input
	if axis_vector.length() > 0.0:
		camera_yaw -= axis_vector.x * controller_sensitivity * delta * 60.0
		camera_pitch -= axis_vector.y * controller_sensitivity * delta * 60.0
		camera_pitch = clamp(camera_pitch, camera_min_pitch, camera_max_pitch)

	# NOTE: Camera arm positioning moved to TOP of _process() for HTML5 compatibility

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

	# Update rail targeting (throttled to 4Hz - was every frame doing 30×N curve samples)
	rail_targeting_timer -= delta
	if rail_targeting_timer <= 0.0:
		update_rail_targeting()
		rail_targeting_timer = 0.25

# MARBLE ROLLING ANIMATION - Always update for all marbles (including bots)
func _physics_process_marble_roll(delta: float) -> void:
	"""Update marble rolling animation based on velocity"""
	if not marble_mesh:
		return

	# Use normal rolling for both regular movement AND spin dash
	if not is_charging_spin:
		# Normal rolling based on movement
		var horizontal_vel: Vector3 = Vector3(linear_velocity.x, 0, linear_velocity.z)
		var speed: float = horizontal_vel.length()

		if speed > 0.1:  # Only roll if moving
			# Calculate roll axis (perpendicular to movement direction)
			var move_dir: Vector3 = horizontal_vel.normalized()
			var roll_axis: Vector3 = Vector3(move_dir.z, 0, -move_dir.x)  # 90 degree rotation (inverted for correct direction)

			# Roll speed based on velocity (marble radius is 0.5)
			# During spin dash, multiply by 3 for faster visual effect
			var roll_speed: float = speed / 0.5  # Angular velocity = linear velocity / radius
			if is_spin_dashing:
				roll_speed *= 3.0

			# Apply rotation
			marble_mesh.rotate(roll_axis.normalized(), roll_speed * delta)

func _input(event: InputEvent) -> void:
	# In practice mode (no multiplayer peer), we're always the authority
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
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
	# In practice mode (no multiplayer peer), we're always the authority
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
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

	# Jump - Space key (with double jump, and jumping off rails)
	if event is InputEventKey and event.keycode == KEY_SPACE:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "Space key detected! Pressed: %s | Grounded: %s | Jumps: %d/%d | Grinding: %s" % [event.pressed, is_grounded, jump_count, max_jumps, is_grinding], false, get_entity_id())
		if event.pressed and not event.echo:
			# Jump off rail if grinding
			if is_grinding:
				DebugLogger.dlog(DebugLogger.Category.PLAYER, "JUMPING OFF RAIL!", false, get_entity_id())
				jump_off_rail()
				return

			if jump_count < max_jumps:
				var jump_strength: float = current_jump_impulse
				# Second jump is slightly weaker
				if jump_count == 1:
					jump_strength *= 0.85

				DebugLogger.dlog(DebugLogger.Category.PLAYER, "JUMPING! (Jump #%d) Impulse: %.1f" % [jump_count + 1, jump_strength], false, get_entity_id())

				# Cancel vertical velocity for consistent jumps
				var vel: Vector3 = linear_velocity
				vel.y = 0
				linear_velocity = vel

				apply_central_impulse(Vector3.UP * jump_strength)
				jump_count += 1

				# Play jump sound
				if jump_sound and jump_sound.stream:
					play_jump_sound.rpc()

				# Spawn jump particle effect
				spawn_jump_bounce_effect(1.0)
			else:
				DebugLogger.dlog(DebugLogger.Category.PLAYER, "Can't jump - no jumps remaining (%d/%d)" % [jump_count, max_jumps], false, get_entity_id())

	# Bounce attack - Right mouse button (Sonic Adventure 2 style)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			# Can only bounce in the air and if not on cooldown (not while grinding)
			if not is_grounded and not is_grinding and bounce_cooldown <= 0.0 and not is_bouncing:
				DebugLogger.dlog(DebugLogger.Category.PLAYER, "BOUNCE ATTACK!", false, get_entity_id())
				start_bounce()
			else:
				if is_grounded:
					DebugLogger.dlog(DebugLogger.Category.PLAYER, "Can't bounce - on ground", false, get_entity_id())
				elif is_grinding:
					DebugLogger.dlog(DebugLogger.Category.PLAYER, "Can't bounce - grinding on rail", false, get_entity_id())
				elif bounce_cooldown > 0.0:
					DebugLogger.dlog(DebugLogger.Category.PLAYER, "Can't bounce - on cooldown (%.2f)" % bounce_cooldown, false, get_entity_id())
				elif is_bouncing:
					DebugLogger.dlog(DebugLogger.Category.PLAYER, "Already bouncing", false, get_entity_id())

	# Use ability - E key or controller X button (with charging support)
	# PRIORITY: If looking at a rail, attach to it instead
	if Input.is_action_just_pressed("use_ability"):
		# Check if we're targeting a rail and can attach
		if targeted_rail and not is_grinding:
			DebugLogger.dlog(DebugLogger.Category.RAILS, "[RAIL] E pressed - attempting to attach to %s" % targeted_rail.name, false, get_entity_id())
			if targeted_rail.has_method("try_attach_player"):
				if targeted_rail.try_attach_player(self):
					DebugLogger.dlog(DebugLogger.Category.RAILS, "[RAIL] Successfully attached to rail via E key!", false, get_entity_id())
					return  # Don't use ability
				else:
					DebugLogger.dlog(DebugLogger.Category.RAILS, "[RAIL] Failed to attach to rail", false, get_entity_id())
			else:
				DebugLogger.dlog(DebugLogger.Category.RAILS, "[RAIL] Rail doesn't have try_attach_player method", false, get_entity_id())

		# Otherwise, start charging the ability
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
				DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Dropping ability!", false, get_entity_id())
				drop_ability()

	# Ultimate attack - Q key
	if event is InputEventKey and event.keycode == KEY_Q:
		if event.pressed and not event.echo:
			if ult_system and ult_system.has_method("try_activate"):
				# Check if game is active
				var world: Node = get_tree().get_root().get_node_or_null("World")
				var game_is_active: bool = world and world.get("game_active")
				if game_is_active:
					if ult_system.try_activate():
						DebugLogger.dlog(DebugLogger.Category.ABILITIES, "ULTIMATE ACTIVATED!", false, get_entity_id())
					else:
						DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Ult not ready yet!", false, get_entity_id())

	# Spin dash - start charging (Shift key)
	if event is InputEventKey and event.keycode == KEY_SHIFT:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "Shift key detected! Pressed: %s | Grounded: %s | Cooldown: %s" % [event.pressed, is_grounded, spin_cooldown], false, get_entity_id())
		if event.pressed and not event.echo:
			# Check if game is active
			var world: Node = get_tree().get_root().get_node_or_null("World")
			var game_is_active: bool = world and world.get("game_active")

			if not game_is_active:
				DebugLogger.dlog(DebugLogger.Category.PLAYER, "Can't spin dash - game not started yet", false, get_entity_id())
			elif is_grounded and spin_cooldown <= 0.0:
				DebugLogger.dlog(DebugLogger.Category.PLAYER, "Starting spin dash charge!", false, get_entity_id())
				is_charging_spin = true
				spin_charge = 0.0
			else:
				if not is_grounded:
					DebugLogger.dlog(DebugLogger.Category.PLAYER, "Can't spin dash - not grounded", false, get_entity_id())
				if spin_cooldown > 0.0:
					DebugLogger.dlog(DebugLogger.Category.PLAYER, "Can't spin dash - on cooldown", false, get_entity_id())

		# Spin dash - release to dash (Shift key)
		if not event.pressed:
			DebugLogger.dlog(DebugLogger.Category.PLAYER, "Shift released! Charging: %s | Charge amount: %s" % [is_charging_spin, spin_charge], false, get_entity_id())
			# Check if game is active
			var world: Node = get_tree().get_root().get_node_or_null("World")
			var game_is_active: bool = world and world.get("game_active")

			if is_charging_spin and spin_charge > 0.1 and game_is_active:  # Minimum charge threshold
				DebugLogger.dlog(DebugLogger.Category.PLAYER, "Executing spin dash!", false, get_entity_id())
				execute_spin_dash()
			elif is_charging_spin:
				if not game_is_active:
					DebugLogger.dlog(DebugLogger.Category.PLAYER, "Can't spin dash - game not started yet", false, get_entity_id())
				else:
					DebugLogger.dlog(DebugLogger.Category.PLAYER, "Charge too low: %s" % spin_charge, false, get_entity_id())
			is_charging_spin = false
			spin_charge = 0.0

func _physics_process(delta: float) -> void:
	# CRITICAL HTML5 FIX: Also position camera arm in physics_process as fallback
	if camera_arm and is_instance_valid(camera_arm):
		camera_arm.global_position = global_position

	# Update marble rolling for ALL marbles (players and bots)
	_physics_process_marble_roll(delta)

	# MULTIPLAYER POSITION SYNC FIX: Handle position synchronization
	if multiplayer.multiplayer_peer != null:
		if is_multiplayer_authority():
			# Authority broadcasts position to all clients
			_sync_position_to_clients(delta)
		else:
			# Non-authority applies interpolated position from sync
			_apply_position_sync(delta)
			return  # Non-authority doesn't process physics locally

	# Check if marble is on ground using raycast
	check_ground()

	# Update bounce cooldown
	if bounce_cooldown > 0.0:
		bounce_cooldown -= delta

	# Update spin dash cooldown
	if spin_cooldown > 0.0:
		spin_cooldown -= delta

	# Update jump pad cooldown
	if jump_pad_cooldown > 0.0:
		jump_pad_cooldown -= delta

	# Update teleporter cooldown
	if teleporter_cooldown > 0.0:
		teleporter_cooldown -= delta

	# Update spin dash timer (for visual spinning)
	if spin_dash_timer > 0.0:
		spin_dash_timer -= delta
		if spin_dash_timer <= 0.0:
			is_spin_dashing = false

		# Apply small continuous force towards reticle during spin dash to maintain rolling direction
		if is_spin_dashing:
			var reticle_direction: Vector3 = Vector3.FORWARD
			if camera:
				reticle_direction = -camera.global_transform.basis.z
				reticle_direction.y = 0
				reticle_direction = reticle_direction.normalized()
			elif camera_arm:
				reticle_direction = -camera_arm.global_transform.basis.z
				reticle_direction.y = 0
				reticle_direction = reticle_direction.normalized()

			# Apply gentle force to maintain direction (10% of normal roll force)
			apply_central_force(reticle_direction * current_roll_force * 0.1)

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
		if charge_sound and is_instance_valid(charge_sound) and charge_sound.playing:
			charge_sound.stop()
		charge_spin_rotation = 0.0

	# Freeze movement until game starts (but allow charging and other systems above)
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if world and not world.get("game_active"):
		return  # Don't process movement until game is active

	# Get input direction relative to camera (calculate even while grinding for rail control)
	var input_dir := Input.get_vector("left", "right", "up", "down")

	if input_dir != Vector2.ZERO:
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
			movement_input_direction = (cam_forward * -input_dir.y + cam_right * input_dir.x).normalized()
		else:
			# Fallback: use global directions if no camera
			movement_input_direction = Vector3(input_dir.x, 0, input_dir.y).normalized()
	else:
		# No input - clear the direction
		movement_input_direction = Vector3.ZERO

	# Don't apply movement force while grinding - rail physics handles everything
	# But we still calculated movement_input_direction above for the rail to use
	if is_grinding:
		# Safety check: ensure rail is still valid to prevent getting stuck
		if not is_instance_valid(current_rail) or current_rail == null:
			DebugLogger.dlog(DebugLogger.Category.RAILS, "SAFETY: Rail became invalid while grinding - forcing stop_grinding()", false, get_entity_id())
			stop_grinding()
			jump_count = 0  # Give full recovery jumps
			# Don't return - allow normal movement to resume immediately
		else:
			return

	# Additional safety: if is_grinding is false but we think we have a rail, clear it
	if current_rail != null and not is_grinding:
		DebugLogger.dlog(DebugLogger.Category.RAILS, "SAFETY: Clearing stale rail reference", false, get_entity_id())
		current_rail = null

	# Apply movement force if there's input
	if input_dir != Vector2.ZERO:
		# Get current horizontal speed
		var horizontal_velocity: Vector3 = Vector3(linear_velocity.x, 0, linear_velocity.z)
		var current_speed: float = horizontal_velocity.length()

		# Apply movement force with reduced control in air
		var control_multiplier: float = 1.0 if is_grounded else air_control
		var force_to_apply: float = current_roll_force * control_multiplier

		# Only apply force if below max speed (or allow air control regardless)
		if current_speed < max_speed or not is_grounded:
			# Apply central force for movement (no torque to prevent spinning)
			apply_central_force(movement_input_direction * force_to_apply)

func check_ground() -> void:
	# Use RayCast3D node for ground detection
	if not ground_ray:
		is_grounded = false
		return

	# While grinding, we're not grounded but also not in normal air state
	# Rail handles all physics, so skip ground check entirely
	if is_grinding:
		# Safety: verify rail is still valid
		if not is_instance_valid(current_rail) or current_rail == null:
			DebugLogger.dlog(DebugLogger.Category.RAILS, "SAFETY: Rail invalid while grinding - forcing stop", false, get_entity_id())
			stop_grinding()
			jump_count = 0
		else:
			is_grounded = false
			return

	# Force raycast update
	ground_ray.force_raycast_update()

	var was_grounded: bool = is_grounded
	is_grounded = ground_ray.is_colliding()

	# Track if we just landed from a bounce (before modifying is_bouncing)
	var just_bounce_landed: bool = false

	# Handle bounce landing
	if is_grounded and not was_grounded and is_bouncing:
		just_bounce_landed = true

		# Increment bounce counter (caps at max_bounce_count)
		bounce_count = min(bounce_count + 1, max_bounce_count)

		# Calculate scaled bounce impulse based on consecutive bounces
		var bounce_multiplier: float = pow(bounce_scale_per_count, bounce_count - 1)
		var scaled_impulse: float = current_bounce_back_impulse * bounce_multiplier

		DebugLogger.dlog(DebugLogger.Category.PLAYER, "BOUNCE IMPACT #%d! Multiplier: %.2fx | Impulse: %.1f" % [bounce_count, bounce_multiplier, scaled_impulse], false, get_entity_id())

		# Cancel vertical velocity and apply scaled upward impulse
		var vel: Vector3 = linear_velocity
		vel.y = 0
		linear_velocity = vel
		apply_central_impulse(Vector3.UP * scaled_impulse)

		# End bounce state and start cooldown
		is_bouncing = false
		bounce_cooldown = bounce_cooldown_time

		# Play bounce sound again for impact (higher pitch for higher bounces)
		if bounce_sound and bounce_sound.stream:
			# Pitch increases with each consecutive bounce (1.0, 1.15, 1.3)
			var pitch_multiplier: float = 1.0 + (bounce_count - 1) * 0.15
			play_bounce_sound_with_pitch.rpc(pitch_multiplier)

		# Spawn bounce landing particle effect (scales with consecutive bounces)
		var particle_intensity: float = 1.0 + (bounce_count - 1) * 0.3  # 1.0, 1.3, 1.6
		spawn_jump_bounce_effect(particle_intensity)

		DebugLogger.dlog(DebugLogger.Category.PLAYER, "Bounce complete! Total bounces: %d/%d | Cooldown started" % [bounce_count, max_bounce_count], false, get_entity_id())

	# Reset jump count when landing (transition from air to ground)
	if is_grounded and not was_grounded:
		jump_count = 0

		# CRITICAL: Clear post-rail-detach grace period when we successfully land
		# This confirms the ground detection is working properly after rail detachment
		if post_rail_detach_frames > 0:
			DebugLogger.dlog(DebugLogger.Category.RAILS, "Post-rail landing confirmed! Clearing grace period (had %d frames left)" % post_rail_detach_frames, false, get_entity_id())
			post_rail_detach_frames = 0

		# Clear particle trails immediately on landing - hide and stop emission
		if jump_bounce_particles:
			jump_bounce_particles.emitting = false
			jump_bounce_particles.visible = false

		# Reset bounce counter if landing normally (not from a bounce)
		if not just_bounce_landed:
			if bounce_count > 0:
				DebugLogger.dlog(DebugLogger.Category.PLAYER, "Landed normally! Jump count reset | Bounce streak ended: %d bounces" % bounce_count, false, get_entity_id())
			else:
				DebugLogger.dlog(DebugLogger.Category.PLAYER, "Landed! Jump count reset", false, get_entity_id())
			bounce_count = 0

		# Play landing sound (only if not from a bounce, since bounce has its own sound)
		if land_sound and land_sound.stream and not just_bounce_landed:
			play_land_sound.rpc()

	# SAFETY: Always ensure jump_count is 0 while grounded (catches stuck states)
	if is_grounded and jump_count > 0:
		jump_count = 0

	# SAFETY: Clear is_bouncing if grounded for consecutive frames (catches stuck bounce state)
	# The bounce landing detection (above) should handle normal cases, but this catches edge cases
	# where was_grounded was somehow already true when landing
	if is_grounded and was_grounded and is_bouncing:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "SAFETY: Clearing stuck bounce state (grounded for consecutive frames)", false, get_entity_id())
		is_bouncing = false
		bounce_count = 0

	# Debug logging every 60 frames (about once per second)
	if Engine.get_physics_frames() % 60 == 0:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "Ground check: %s | Y-pos: %.11f | Jumps: %d/%d" % [is_grounded, global_position.y, jump_count, max_jumps], false, get_entity_id())
		if is_grounded:
			DebugLogger.dlog(DebugLogger.Category.PLAYER, "  Hit: %s at distance: %.11f" % [ground_ray.get_collider(), ground_ray.get_collision_point().distance_to(global_position)], false, get_entity_id())
		else:
			DebugLogger.dlog(DebugLogger.Category.PLAYER, "  No ground detected under marble", false, get_entity_id())

	# Log ground state changes
	if was_grounded != is_grounded:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "Ground state changed: %s | Position: %s" % [is_grounded, global_position], false, get_entity_id())

func execute_spin_dash() -> void:
	"""Execute a Sonic-style spin dash - Always dash towards reticle position"""
	var dash_direction: Vector3 = Vector3.FORWARD

	# ALWAYS use camera/reticle direction for the dash
	if camera:
		# Use camera forward direction (reticle position) including pitch
		dash_direction = -camera.global_transform.basis.z
		# Keep horizontal component only for dash direction
		dash_direction.y = 0
		dash_direction = dash_direction.normalized()
	elif camera_arm:
		# Fallback to camera_arm if camera not found
		dash_direction = -camera_arm.global_transform.basis.z
		dash_direction.y = 0
		dash_direction = dash_direction.normalized()

	# Calculate target rotation to face the dash direction (for fallback rolling only)
	# Use atan2 to get the angle on the Y axis (horizontal rotation)
	var target_rotation_y: float = atan2(dash_direction.x, dash_direction.z)

	# Store the target rotation for maintaining orientation during spin dash
	spin_dash_target_rotation = target_rotation_y

	# RESET marble mesh rotation completely to prevent any accumulated rotation from charging
	if marble_mesh:
		marble_mesh.rotation = Vector3.ZERO

	# Calculate dash force based on charge (50% to 100% of max force)
	var charge_multiplier: float = 0.5 + (spin_charge / max_spin_charge) * 0.5
	var dash_impulse: float = current_spin_dash_force * charge_multiplier

	# Apply the dash impulse in the camera/reticle direction
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

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "Spin dash towards reticle! Direction: %s | Rotation: %.1f° | Charge: %.1f%% | Force: %.1f" % [dash_direction, rad_to_deg(target_rotation_y), charge_multiplier * 100, dash_impulse], false, get_entity_id())

func start_bounce() -> void:
	"""Start the bounce attack - Sonic Adventure 2 style"""
	if is_bouncing:
		return

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "Starting bounce attack!", false, get_entity_id())
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

	# Spawn bounce particle effect (initiating bounce)
	spawn_jump_bounce_effect(1.2)

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "Bounce velocity applied: y=%.1f" % vel.y, false, get_entity_id())

@rpc("any_peer")
func receive_damage(damage: int = 1) -> void:
	if god_mode:
		return  # Immune to damage
	health -= damage
	if health <= 0:
		# Track death
		var world: Node = get_parent()
		if world and world.has_method("add_death"):
			var player_id: int = name.to_int()
			world.add_death(player_id)

		# Drop orbs and ability before respawning
		spawn_death_orb()
		drop_ability()
		respawn()

@rpc("any_peer")
func receive_damage_from(damage: int, attacker_id: int) -> void:
	"""Receive damage from a specific player"""
	if god_mode:
		return  # Immune to damage

	# MULTIPLAYER SYNC FIX: Validate damage by checking attacker distance
	# This prevents invalid damage from desync or exploits
	var world: Node = get_parent()
	if world and multiplayer.has_multiplayer_peer():
		var attacker: Node = world.get_node_or_null(str(attacker_id))
		if attacker and is_instance_valid(attacker):
			var distance: float = global_position.distance_to(attacker.global_position)
			# Maximum valid attack distance - must accommodate ranged abilities
			# (lightning lock_range=40, cannon projectiles travel far from shooter)
			const MAX_VALID_ATTACK_DISTANCE: float = 80.0
			if distance > MAX_VALID_ATTACK_DISTANCE:
				DebugLogger.dlog(DebugLogger.Category.PLAYER, "DAMAGE REJECTED: Attacker %d too far (%.1f > %.1f)" % [attacker_id, distance, MAX_VALID_ATTACK_DISTANCE], false, get_entity_id())
				return  # Reject damage from too far

	# Track last attacker for knockoff kills
	last_attacker_id = attacker_id
	last_attacker_time = Time.get_ticks_msec() / 1000.0

	health -= damage
	DebugLogger.dlog(DebugLogger.Category.PLAYER, "Received %d damage from player %d! Health: %d" % [damage, attacker_id, health], false, get_entity_id())

	# Charge ult when taking damage (for this player)
	if ult_system and ult_system.has_method("on_damage_taken"):
		ult_system.on_damage_taken(damage)

	# Give attacker ult charge for dealing damage
	if world:
		var attacker: Node = world.get_node_or_null(str(attacker_id))
		if attacker and "ult_system" in attacker and attacker.ult_system:
			if attacker.ult_system.has_method("on_damage_dealt"):
				attacker.ult_system.on_damage_dealt(damage)

	# Play hit sound
	if hit_sound and hit_sound.stream:
		play_hit_sound.rpc()

	if health <= 0:
		# Drop orbs and ability before death
		spawn_death_orb()
		drop_ability()

		# Notify world of kill and death
		# (reuse world variable from above)
		if world:
			if world.has_method("add_score"):
				world.add_score(attacker_id, 1)
			if world.has_method("add_death"):
				var player_id: int = name.to_int()
				world.add_death(player_id)

			# Update attacker's killstreak and notify
			var attacker: Node = world.get_node_or_null(str(attacker_id))
			DebugLogger.dlog(DebugLogger.Category.WORLD, "[KILL] Looking for attacker node: %d - Found: %s" % [attacker_id, attacker != null])
			if attacker and "killstreak" in attacker:
				attacker.killstreak += 1
				DebugLogger.dlog(DebugLogger.Category.WORLD, "[KILL] Attacker killstreak is now: %d" % attacker.killstreak)

				# Give attacker ult charge for the kill
				if "ult_system" in attacker and attacker.ult_system and attacker.ult_system.has_method("on_kill"):
					attacker.ult_system.on_kill()

				# Notify HUD of kill with victim's name (call on attacker's node)
				if attacker.has_method("notify_kill"):
					DebugLogger.dlog(DebugLogger.Category.WORLD, "[KILL] Calling notify_kill on attacker node")
					attacker.notify_kill(attacker_id, name.to_int())
				else:
					DebugLogger.dlog(DebugLogger.Category.WORLD, "[KILL] ERROR: Attacker doesn't have notify_kill method!")

				# Notify about killstreak milestones
				if attacker.killstreak == 5 or attacker.killstreak == 10:
					if attacker.has_method("notify_killstreak"):
						attacker.notify_killstreak(attacker_id, attacker.killstreak)

		# Play death effects before respawning
		spawn_death_particles()
		play_death_sound.rpc()

		# Delay respawn slightly for death effects to be visible
		await get_tree().create_timer(0.1).timeout
		respawn()
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "Killed by player %d!" % attacker_id, false, get_entity_id())

func respawn() -> void:
	health = 3
	level = 0  # Reset level on death
	jump_count = 0  # Reset jumps
	bounce_count = 0  # Reset bounce streak
	update_stats()

	# Reset killstreak and last attacker on death
	killstreak = 0
	last_attacker_id = -1
	last_attacker_time = 0.0

	# Reset death state
	is_falling_to_death = false
	fall_camera_detached = false
	fall_death_timer = 0.0

	# CRITICAL: Always clear ability on respawn (fixes bug where fall deaths keep ability)
	if current_ability:
		current_ability.queue_free()
		current_ability = null
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "Cleared ability on respawn for %s" % name, false, get_entity_id())

	# CRITICAL: Reset all movement states that could get stuck
	is_bouncing = false
	is_grinding = false
	current_rail = null
	is_charging_spin = false
	is_spin_dashing = false
	spin_charge = 0.0
	spin_dash_timer = 0.0
	post_rail_detach_frames = 0  # Clear any pending grace period
	consecutive_air_frames = 0  # Clear air frame counter

	# CRITICAL: Force grounded state on respawn (we spawn on ground)
	# This fixes the stuck AIR state bug after grinding
	is_grounded = true

	# Reset all cooldowns
	bounce_cooldown = 0.0
	spin_cooldown = 0.0
	jump_pad_cooldown = 0.0
	teleporter_cooldown = 0.0

	# Reset ult system on death
	if ult_system and ult_system.has_method("reset"):
		ult_system.reset()

	# CRITICAL: Restore normal physics damping (fixes slowness if died while grinding)
	linear_damp = 0.5
	angular_damp = 0.3

	# Reset physics
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	# Move to fixed spawn based on player ID
	var player_id: int = str(name).to_int()
	var is_bot: bool = player_id >= 9000

	if spawns.size() > 0:
		var spawn_index: int = player_id % spawns.size()
		global_position = spawns[spawn_index]
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "Player %s respawned at spawn %d (is_bot: %s)" % [name, spawn_index, is_bot], false, get_entity_id())
	else:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "WARNING: No spawn points available for player %s! Using fallback position." % name, false, get_entity_id())
		global_position = Vector3(0, 2, 0)  # Fallback spawn position

	# Play spawn sound effect
	if spawn_sound:
		play_spawn_sound.rpc()

	# Spawn beam effect
	spawn_beam_effect()

func fall_death() -> void:
	"""Called when player falls off the map"""
	var player_id: int = str(name).to_int()
	var is_bot: bool = player_id >= 9000

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "fall_death() called for %s (is_bot: %s, position: %s)" % [name, is_bot, global_position], false, get_entity_id())

	if is_falling_to_death:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "  Already falling to death, ignoring", false, get_entity_id())
		return

	if god_mode:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "  God mode enabled, ignoring", false, get_entity_id())
		return

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "  Starting fall death sequence", false, get_entity_id())

	# Track death
	var world: Node = get_parent()
	if world and world.has_method("add_death"):
		world.add_death(player_id)

	# Check if there was a recent attacker who should get credit for the knockoff kill
	var current_time: float = Time.get_ticks_msec() / 1000.0
	if last_attacker_id != -1 and (current_time - last_attacker_time) <= ATTACKER_TIMEOUT:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "  Knockoff kill credited to player %d" % last_attacker_id, false, get_entity_id())
		# Give attacker credit for the kill
		if world and world.has_method("add_score"):
			world.add_score(last_attacker_id, 1)

		# Update attacker's killstreak and notify
		var attacker: Node = world.get_node_or_null(str(last_attacker_id))
		if attacker and "killstreak" in attacker:
			attacker.killstreak += 1
			# Notify HUD of kill with victim's name (call on attacker's node)
			if attacker.has_method("notify_kill"):
				attacker.notify_kill(last_attacker_id, name.to_int())

			# Notify about killstreak milestones
			if attacker.killstreak == 5 or attacker.killstreak == 10:
				if attacker.has_method("notify_killstreak"):
					attacker.notify_killstreak(last_attacker_id, attacker.killstreak)

	# Don't drop orbs or abilities when falling to death
	# (Players lose their items in the void)

	is_falling_to_death = true
	fall_death_timer = 0.0
	fall_camera_detached = false

	# Let physics continue so marble keeps falling

func collect_orb() -> void:
	"""Call this when player collects a level-up orb"""
	# Spawn collection effect
	spawn_collection_effect()

	if level < MAX_LEVEL:
		level += 1
		update_stats()
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "⭐ LEVEL UP! New level: %d | Roll Force: %.1f | Max Speed: %.1f | Jump: %.1f | Spin: %.1f" % [level, current_roll_force, max_speed, current_jump_impulse, current_spin_dash_force], false, get_entity_id())
	else:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "Already at MAX_LEVEL (%d)" % MAX_LEVEL, false, get_entity_id())

func update_stats() -> void:
	"""Update movement stats based on current level and arena size"""
	# Base stats + level bonuses, then scaled by arena size
	current_roll_force = (base_roll_force + (level * SPEED_BOOST_PER_LEVEL)) * arena_size_multiplier
	current_jump_impulse = base_jump_impulse + (level * JUMP_BOOST_PER_LEVEL)
	current_spin_dash_force = (base_spin_dash_force + (level * SPIN_BOOST_PER_LEVEL)) * arena_size_multiplier
	current_bounce_back_impulse = base_bounce_back_impulse + (level * BOUNCE_BOOST_PER_LEVEL)
	# Max speed scales with arena size and level
	max_speed = (base_max_speed + (level * MAX_SPEED_BOOST_PER_LEVEL)) * arena_size_multiplier

func set_arena_size_multiplier(multiplier: float) -> void:
	"""Set the arena size multiplier and update stats accordingly"""
	arena_size_multiplier = multiplier
	update_stats()
	DebugLogger.dlog(DebugLogger.Category.PLAYER, "Arena size multiplier set to %.2f | Max Speed: %.1f | Roll Force: %.1f" % [multiplier, max_speed, current_roll_force], false, get_entity_id())

func pickup_ability(ability_scene: PackedScene, ability_name: String) -> void:
	"""Pickup a new ability"""
	# Spawn collection effect
	spawn_collection_effect()

	# Remove current ability if we have one (without dropping it)
	if current_ability:
		# Tell the ability it was dropped
		if current_ability.has_method("drop"):
			current_ability.drop()

		# Remove the ability from player (just disappear, don't spawn pickup)
		current_ability.queue_free()
		current_ability = null
		DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Removed previous ability (disappeared)", false, get_entity_id())

	# Instantiate and equip the new ability
	current_ability = ability_scene.instantiate()
	add_child(current_ability)

	# Tell the ability it was picked up
	if current_ability.has_method("pickup"):
		current_ability.pickup(self)

	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Picked up ability: %s" % ability_name, false, get_entity_id())

func drop_ability() -> void:
	"""Drop the current ability and spawn it as a pickup on the ground"""
	if not current_ability:
		return

	# Get ability properties before removing it
	var ability_name: String = current_ability.ability_name if "ability_name" in current_ability else "Unknown"
	var ability_color: Color = current_ability.ability_color if "ability_color" in current_ability else Color.WHITE

	# Map ability name to scene
	var ability_scene: PackedScene = get_ability_scene_from_name(ability_name)

	# Tell the ability it was dropped
	if current_ability.has_method("drop"):
		current_ability.drop()

	# Remove the ability from player
	current_ability.queue_free()
	current_ability = null

	# Spawn the ability pickup on the ground if we have a valid scene
	if ability_scene:
		spawn_ability_pickup(ability_scene, ability_name, ability_color)
		DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Dropped ability: %s" % ability_name, false, get_entity_id())
	else:
		DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Dropped ability but couldn't spawn pickup: %s" % ability_name, false, get_entity_id())

func get_ability_scene_from_name(ability_name: String) -> PackedScene:
	"""Map ability name to its scene"""
	match ability_name:
		"Dash Attack":
			return DashAttackScene
		"Explosion":
			return ExplosionScene
		"Cannon":
			return CannonScene
		"Sword":
			return SwordScene
		_:
			DebugLogger.dlog(DebugLogger.Category.ABILITIES, "WARNING: Unknown ability name: %s" % ability_name)
			return null

func spawn_ability_pickup(ability_scene: PackedScene, ability_name: String, ability_color: Color) -> void:
	"""Spawn an ability pickup on the ground near the player"""
	# Get the world node (parent) to add the pickup to
	var world: Node = get_parent()
	if not world:
		DebugLogger.dlog(DebugLogger.Category.ABILITIES, "ERROR: No parent node to spawn ability pickup into!")
		return

	# Find ground position near player
	var placement_offset: Vector3 = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
	var raycast_start: Vector3 = global_position + placement_offset + Vector3.UP * 10.0
	var raycast_end: Vector3 = global_position + placement_offset + Vector3.DOWN * 20.0

	# Raycast down to find ground
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(raycast_start, raycast_end)
	query.collision_mask = 1  # Only check world geometry (layer 1)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result: Dictionary = space_state.intersect_ray(query)

	# Determine spawn position
	var spawn_pos: Vector3
	if result:
		# Found ground - spawn 1 unit above it
		spawn_pos = result.position + Vector3.UP * 1.0
	else:
		# No ground found - use current height as fallback
		spawn_pos = global_position + placement_offset

	# Don't spawn abilities in or near the death zone
	const MIN_SAFE_Y: float = -40.0
	if spawn_pos.y < MIN_SAFE_Y:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "Cannot spawn ability pickup - too close to death zone (Y: %.1f)" % spawn_pos.y, false, get_entity_id())
		return

	# Instantiate the ability pickup
	var pickup: Area3D = AbilityPickupScene.instantiate()
	pickup.ability_scene = ability_scene
	pickup.ability_name = ability_name
	pickup.ability_color = ability_color
	pickup.position = spawn_pos

	# Add the pickup to the world
	world.add_child(pickup)

	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Ability pickup '%s' spawned on ground at position %s" % [ability_name, spawn_pos], false, get_entity_id())

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
func play_bounce_sound_with_pitch(pitch_multiplier: float = 1.0) -> void:
	if bounce_sound and bounce_sound.stream:
		# Base pitch with variation, scaled by bounce count
		var base_pitch: float = randf_range(0.9, 1.0)
		bounce_sound.pitch_scale = base_pitch * pitch_multiplier
		bounce_sound.play()

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

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "Death particles spawned for %s (player: %s)" % [name, "human" if not is_bot else "bot"], false, get_entity_id())

func spawn_collection_effect() -> void:
	"""Spawn blue aura collection effect rising from beneath the player"""
	if not collection_particles:
		return

	# Position particles at base of player (slightly below for upward flow)
	collection_particles.global_position = global_position + Vector3(0, -0.4, 0)
	collection_particles.emitting = true
	collection_particles.restart()

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "Collection effect spawned for %s at position %s" % [name, global_position], false, get_entity_id())

func spawn_jump_bounce_effect(intensity_multiplier: float = 1.0) -> void:
	"""Spawn 3 dark blue circles that trail behind player motion (Sonic Adventure 2 style)"""
	if not jump_bounce_particles:
		return

	# Trail in the opposite direction of player's velocity to show motion through air
	var trail_direction: Vector3
	if linear_velocity.length() > 0.5:
		# Player is moving - trail in opposite direction of movement
		trail_direction = -linear_velocity.normalized()
	else:
		# Player barely moving - default to downward trail
		trail_direction = Vector3.DOWN

	jump_bounce_particles.direction = trail_direction

	# Position particles inside the marble's center
	jump_bounce_particles.global_position = global_position  # Inside the marble
	jump_bounce_particles.visible = true  # Make visible when spawning
	jump_bounce_particles.emitting = true
	jump_bounce_particles.restart()

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "Jump/Bounce effect (3 dark blue circles trailing behind motion) spawned for %s (intensity: %.2fx, dir: %s)" % [name, intensity_multiplier, trail_direction], false, get_entity_id())

func spawn_beam_effect() -> void:
	"""Spawn Star Trek-style beam effect at player spawn position"""
	# Get the world node (parent) to add the effect to
	var world: Node = get_parent()
	if not world:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "ERROR: No parent node to spawn beam effect into!", false, get_entity_id())
		return

	# Create the beam effect instance
	var beam_effect = BeamSpawnEffect.new()
	world.add_child(beam_effect)

	# Position the effect at the player's spawn position
	# Offset down so the beam rises up from below
	beam_effect.global_position = global_position + Vector3(0, -4, 0)

	# Play the beam effect
	beam_effect.play_beam()

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "Beam spawn effect created for %s at position %s" % [name, beam_effect.global_position], false, get_entity_id())

func spawn_death_orb() -> void:
	"""Spawn orbs at the player's death position - places them on the ground nearby"""
	# Only spawn orbs if player has collected any (level > 0)
	if level <= 0:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "No orbs to drop - player level is 0", false, get_entity_id())
		return

	# Get the world node (parent) to add the orbs to
	var world: Node = get_parent()
	if not world:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "ERROR: No parent node to spawn orbs into!", false, get_entity_id())
		return

	# Spawn one orb for each level (1-3 orbs)
	var num_orbs: int = level
	var placement_radius: float = 1.5  # How far from death point to place orbs (on ground)

	for i in range(num_orbs):
		# Calculate angle for even distribution around the death point
		var angle: float = (TAU / num_orbs) * i + randf_range(-0.2, 0.2)  # Add slight randomness

		# Calculate horizontal offset position (ground placement in a circle)
		var horizontal_offset: Vector3 = Vector3(
			cos(angle) * placement_radius,
			0,
			sin(angle) * placement_radius
		)

		# Start position for raycast (high above death point + offset)
		var raycast_start: Vector3 = global_position + horizontal_offset + Vector3.UP * 10.0
		var raycast_end: Vector3 = global_position + horizontal_offset + Vector3.DOWN * 20.0

		# Raycast down to find ground
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(raycast_start, raycast_end)
		query.collision_mask = 1  # Only check world geometry (layer 1)
		query.collide_with_areas = false
		query.collide_with_bodies = true

		var result: Dictionary = space_state.intersect_ray(query)

		# Determine spawn position
		var spawn_pos: Vector3
		if result:
			# Found ground - spawn 1 unit above it
			spawn_pos = result.position + Vector3.UP * 1.0
		else:
			# No ground found - use current height as fallback
			spawn_pos = global_position + horizontal_offset

		# Don't spawn orbs in or near the death zone
		const MIN_SAFE_Y: float = -40.0
		if spawn_pos.y < MIN_SAFE_Y:
			DebugLogger.dlog(DebugLogger.Category.PLAYER, "Skipping orb spawn - too close to death zone (Y: %.1f)" % spawn_pos.y, false, get_entity_id())
			continue

		# Instantiate the orb
		var orb: Area3D = OrbScene.instantiate()
		orb.position = spawn_pos

		# Add the orb to the world
		world.add_child(orb)

		DebugLogger.dlog(DebugLogger.Category.PLAYER, "Orb #%d placed on ground at position %s (angle: %.1f°)" % [i + 1, spawn_pos, rad_to_deg(angle)], false, get_entity_id())

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "Total %d orbs dropped by player %s" % [num_orbs, name], false, get_entity_id())

# ============================================================================
# UI SYSTEM
# ============================================================================

func create_ult_system() -> void:
	"""Create and initialize the ult system"""
	ult_system = UltSystemScript.new()
	ult_system.name = "UltSystem"
	add_child(ult_system)

	# Set up the ult system
	if ult_system.has_method("setup"):
		ult_system.setup(self)

	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Ult system created for player %s" % name, false, get_entity_id())

func create_rail_reticle_ui() -> void:
	"""Create the rail targeting prompt UI (text only, no visual reticle)"""
	# Create container
	rail_reticle_ui = Control.new()
	rail_reticle_ui.name = "RailReticleUI"
	rail_reticle_ui.set_anchors_preset(Control.PRESET_CENTER)
	rail_reticle_ui.anchor_left = 0.5
	rail_reticle_ui.anchor_right = 0.5
	rail_reticle_ui.anchor_top = 0.5
	rail_reticle_ui.anchor_bottom = 0.5
	rail_reticle_ui.offset_left = -100
	rail_reticle_ui.offset_right = 100
	rail_reticle_ui.offset_top = -15
	rail_reticle_ui.offset_bottom = 15
	rail_reticle_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail_reticle_ui.visible = false
	add_child(rail_reticle_ui)

	# Create label only (no visual reticle elements)
	var label: Label = Label.new()
	label.name = "AttachLabel"
	label.text = "[E] ATTACH TO RAIL"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Match HUD style: Rajdhani-Bold, accent blue, outline + shadow
	var hud_font: Font = load("res://fonts/Rajdhani-Bold.ttf")
	if hud_font:
		label.add_theme_font_override("font", hud_font)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.3, 0.7, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.position = Vector2(0, 0)
	label.size = Vector2(200, 30)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail_reticle_ui.add_child(label)

	DebugLogger.dlog(DebugLogger.Category.UI, "Rail attachment prompt UI created (text only)", false, get_entity_id())


func find_all_rails(node: Node) -> Array[GrindRail]:
	"""Recursively find all GrindRail nodes in the scene"""
	var rails: Array[GrindRail] = []

	if node is GrindRail:
		rails.append(node as GrindRail)

	for child in node.get_children():
		rails.append_array(find_all_rails(child))

	return rails

func update_rail_targeting() -> void:
	"""Update rail targeting system - check if player is looking at a rail"""
	if not camera or not rail_reticle_ui:
		return

	# Don't show reticle while grinding
	if is_grinding:
		rail_reticle_ui.visible = false
		targeted_rail = null
		return

	# Raycast from camera to detect rails
	var ray_origin: Vector3 = camera.global_position
	var ray_direction: Vector3 = -camera.global_transform.basis.z

	# Check for rails in the scene
	var found_rail: GrindRail = null
	var closest_distance: float = INF
	var max_target_distance: float = 50.0  # Maximum distance to target rails

	# Find all rails in the scene (recursively search)
	# Refresh rail cache every 2 seconds or if empty
	rails_cache_timer += get_process_delta_time()
	if cached_rails.is_empty() or rails_cache_timer >= 2.0:
		var world: Node = get_tree().root.get_node_or_null("World")
		if not world:
			world = get_parent()

		if world:
			var prev_count: int = cached_rails.size()
			cached_rails = find_all_rails(world)
			# Clean up invalid rails during cache refresh (not every targeting call)
			cached_rails = cached_rails.filter(func(r): return r and is_instance_valid(r) and r.is_inside_tree())
			if prev_count == 0 and cached_rails.size() > 0:
				DebugLogger.dlog(DebugLogger.Category.RAILS, "[RAIL] Found %d rails in scene" % cached_rails.size(), false, get_entity_id())
			elif cached_rails.size() == 0:
				DebugLogger.dlog(DebugLogger.Category.RAILS, "[RAIL] WARNING: No rails found in scene!", false, get_entity_id())
			rails_cache_timer = 0.0

	for rail in cached_rails:
		# Validate rail is still valid and in the scene
		if not rail or not is_instance_valid(rail) or not rail.is_inside_tree():
			continue

		# Get closest point on rail path to camera ray
		var rail_curve: Curve3D = rail.curve
		if not rail_curve or rail_curve.get_baked_length() <= 0:
			continue

		# Sample points along the rail and find closest to ray
		var sample_count: int = 10  # Reduced from 30 - sufficient for UI targeting reticle
		for i in range(sample_count):
			var t: float = float(i) / float(sample_count - 1)
			var offset: float = t * rail_curve.get_baked_length()
			var point_local: Vector3 = rail_curve.sample_baked(offset)
			var point_world: Vector3 = rail.to_global(point_local)

			# Calculate distance from camera ray to this point
			var to_point: Vector3 = point_world - ray_origin
			var projection: float = to_point.dot(ray_direction)

			# Only consider points in front of camera and within range
			if projection > 0 and projection < max_target_distance:
				var closest_on_ray: Vector3 = ray_origin + ray_direction * projection
				var distance_to_ray: float = point_world.distance_to(closest_on_ray)

				# Distance from player to the rail point
				var distance_from_player: float = global_position.distance_to(point_world)

				# Check if this is close enough to the ray (within targeting radius)
				var targeting_radius: float = 5.0  # Increased for easier targeting
				# Only allow targeting if rail is within reasonable distance (30 units)
				if distance_to_ray < targeting_radius and projection < closest_distance and distance_from_player < 30.0:
					# Check if we're actually in range to attach (nearby_players check)
					if rail.has_method("can_attach"):
						# For display purposes, we're more lenient
						# We show the reticle even if slightly out of range
						found_rail = rail
						closest_distance = projection

	# Update targeted rail and prompt visibility
	var prev_targeted: GrindRail = targeted_rail
	targeted_rail = found_rail

	if targeted_rail and not prev_targeted:
		DebugLogger.dlog(DebugLogger.Category.RAILS, "[RAIL] Targeting rail: %s" % targeted_rail.name, false, get_entity_id())

	if targeted_rail:
		rail_reticle_ui.visible = true

		# Update label text and color (show attach prompt only)
		var label: Control = rail_reticle_ui.get_node_or_null("AttachLabel")
		if label is Label:
			(label as Label).text = "[E] ATTACH TO RAIL"
			(label as Label).add_theme_color_override("font_color", Color(0.3, 0.7, 1, 1))
	else:
		rail_reticle_ui.visible = false

# ============================================================================
# RAIL GRINDING SYSTEM (Simplified - rail handles physics)
# ============================================================================

func start_grinding(rail: GrindRail) -> void:
	"""Called by rail when player attaches"""
	if is_grinding and current_rail == rail:
		return  # Already grinding on this rail

	if is_grinding and current_rail != rail:
		stop_grinding()  # Switch rails

	DebugLogger.dlog(DebugLogger.Category.RAILS, "Started grinding!", false, get_entity_id())
	is_grinding = true
	current_rail = rail
	jump_count = 0
	is_bouncing = false
	bounce_count = 0

	# Start spark particles
	if grind_particles:
		grind_particles.emitting = true

	# Play grind sound
	if spin_sound and spin_sound.stream:
		spin_sound.pitch_scale = 0.8
		spin_sound.play()

	# Sync bot AI
	var bot_ai: Node = get_node_or_null("BotAI")
	if bot_ai and bot_ai.has_method("start_grinding"):
		bot_ai.start_grinding(rail)


func stop_grinding() -> void:
	"""Called by rail when player detaches"""
	var was_grinding: bool = is_grinding
	current_rail = null
	is_grinding = false

	if not was_grinding:
		return

	DebugLogger.dlog(DebugLogger.Category.RAILS, "Stopped grinding!", false, get_entity_id())
	jump_count = 0  # Full recovery jumps available

	# Stop spark particles
	if grind_particles:
		grind_particles.emitting = false

	# Sync bot AI
	var bot_ai: Node = get_node_or_null("BotAI")
	if bot_ai and bot_ai.has_method("stop_grinding"):
		bot_ai.stop_grinding()


func launch_from_rail(velocity: Vector3) -> void:
	"""Called by rail when player reaches the end"""
	DebugLogger.dlog(DebugLogger.Category.RAILS, "Launched from rail! velocity: %s" % velocity, false, get_entity_id())

	# Rail already applies velocity, just sync bot AI
	var bot_ai: Node = get_node_or_null("BotAI")
	if bot_ai and bot_ai.has_method("launch_from_rail"):
		bot_ai.launch_from_rail(velocity)

func jump_off_rail() -> void:
	"""Player manually jumps off the rail"""
	# Store reference before clearing state
	var rail_ref = current_rail
	var was_grinding = is_grinding

	# If we have a rail reference, detach from it
	if rail_ref and is_instance_valid(rail_ref):
		rail_ref.detach_grinder(self)

	# Always call stop_grinding to ensure clean state
	stop_grinding()

	# If we weren't actually grinding, just do a normal jump instead
	if not was_grinding:
		if jump_count < max_jumps:
			var vel: Vector3 = linear_velocity
			vel.y = 0
			linear_velocity = vel
			apply_central_impulse(Vector3.UP * current_jump_impulse)
			jump_count += 1
			if jump_sound and jump_sound.stream:
				play_jump_sound.rpc()
			spawn_jump_bounce_effect(1.0)
		return

	# Set jump_count to 1 - the rail jump counts as first jump, leaving double jump available
	jump_count = 1

	# Apply jump impulse upward (player keeps their grinding momentum)
	var jump_strength: float = current_jump_impulse * 1.2  # Bonus for rail jump
	apply_central_impulse(Vector3.UP * jump_strength)

	# Play jump sound
	if jump_sound and jump_sound.stream:
		play_jump_sound.rpc()

	# Spawn jump particle effect
	spawn_jump_bounce_effect(1.2)

	DebugLogger.dlog(DebugLogger.Category.RAILS, "Jumped off rail! Velocity: %s, jump_count: %d" % [linear_velocity, jump_count], false, get_entity_id())

# ============================================================================
# JUMP PAD & TELEPORTER SYSTEM (Q3 ARENA STYLE)
# ============================================================================

func create_area_detector() -> void:
	"""Create Area3D for detecting jump pads and teleporters"""
	area_detector = Area3D.new()
	area_detector.name = "AreaDetector"
	add_child(area_detector)

	# Create collision shape for area detection (slightly larger than player)
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.6  # Slightly larger than player radius
	collision_shape.shape = shape
	area_detector.add_child(collision_shape)

	# Set up collision layers - detect areas but not other players
	area_detector.collision_layer = 0  # Don't report our presence
	area_detector.collision_mask = 8  # Detect layer 8 (pickups/areas)
	area_detector.monitorable = false  # Don't need other areas to detect us

	# Connect signals
	area_detector.area_entered.connect(_on_area_entered)

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "Area detector created for jump pads and teleporters", false, get_entity_id())

func _on_area_entered(area: Area3D) -> void:
	"""Handle entering areas (jump pads, teleporters, etc.)"""
	# Allow local player AND bots to use jump pads/teleporters
	if not is_multiplayer_authority() and not is_bot():
		return  # Only process for local player or bots

	# Check if this is a jump pad
	if area.is_in_group("jump_pad"):
		activate_jump_pad(area)

	# Check if this is a teleporter
	elif area.is_in_group("teleporter") and area.has_meta("destination"):
		var destination: Vector3 = area.get_meta("destination")
		activate_teleporter(destination)

func activate_jump_pad(area: Area3D = null) -> void:
	"""Apply jump pad boost to player"""
	if jump_pad_cooldown > 0.0:
		return  # Still on cooldown

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "Jump pad activated! Applying boost...", false, get_entity_id())

	# Cancel downward velocity and apply strong upward boost
	var vel: Vector3 = linear_velocity
	vel.y = 0  # Cancel any downward momentum
	linear_velocity = vel

	# Get custom boost force from jump pad if available, otherwise use default
	var boost: float = jump_pad_boost_force
	if area and area.has_meta("boost_force"):
		boost = area.get_meta("boost_force")
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "Using custom boost force: %.1f (target height: %.1f)" % [boost, area.get_meta("target_height") if area.has_meta("target_height") else 0.0], false, get_entity_id())

	# Apply strong upward impulse
	apply_central_impulse(Vector3.UP * boost)

	# Reset bounce state (jump pad interrupts bounce)
	is_bouncing = false
	bounce_count = 0

	# Reset double jump
	jump_count = 0

	# Play bounce sound (reuse for jump pad)
	if bounce_sound and bounce_sound.stream:
		bounce_sound.pitch_scale = 1.5  # Higher pitch for jump pad
		bounce_sound.play()

	# Spawn BRIGHT GREEN particle explosion effect
	spawn_jump_pad_effect()

	# Set cooldown to prevent rapid re-triggering
	jump_pad_cooldown = jump_pad_cooldown_time

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "Jump pad boost applied! New velocity: %s" % linear_velocity, false, get_entity_id())

func activate_teleporter(destination: Vector3) -> void:
	"""Teleport player to destination"""
	if teleporter_cooldown > 0.0:
		return  # Still on cooldown

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "Teleporter activated! Teleporting to: %s" % destination, false, get_entity_id())

	# Teleport player (add height offset to ensure above ground)
	global_position = destination + Vector3(0, 2, 0)

	# Reset velocity to prevent momentum issues
	linear_velocity = Vector3.ZERO

	# Reset bounce state
	is_bouncing = false
	bounce_count = 0

	# Play teleport sound effect (placeholder - needs audio file)
	if teleport_sound and teleport_sound.stream:
		teleport_sound.play()
	# TODO: Add teleport sound audio file to TeleportSound node in marble_player.tscn

	# Spawn BRIGHT PURPLE particle swirl effect at destination
	spawn_teleporter_effect()

	# Set cooldown to prevent rapid re-triggering
	teleporter_cooldown = teleporter_cooldown_time

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "Teleported to: %s" % global_position, false, get_entity_id())

func spawn_jump_pad_effect() -> void:
	"""Spawn BRIGHT GREEN explosive particle effect for jump pad activation"""
	if not death_particles:
		return

	# Temporarily change death particles to bright green for jump pad effect
	var jump_pad_gradient: Gradient = Gradient.new()
	jump_pad_gradient.add_point(0.0, Color(0.2, 1.0, 0.3, 1.0))  # Bright green
	jump_pad_gradient.add_point(0.3, Color(0.4, 1.0, 0.5, 0.9))  # Lighter green
	jump_pad_gradient.add_point(0.7, Color(0.6, 1.0, 0.7, 0.5))  # Very light green
	jump_pad_gradient.add_point(1.0, Color(0.8, 1.0, 0.9, 0.0))  # Transparent

	death_particles.color_ramp = jump_pad_gradient
	death_particles.initial_velocity_min = 15.0  # Faster burst
	death_particles.initial_velocity_max = 25.0
	death_particles.amount = 150  # Lots of particles

	# Trigger particle burst at current position
	death_particles.global_position = global_position
	death_particles.emitting = true
	death_particles.restart()

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "BRIGHT GREEN jump pad particle explosion spawned!", false, get_entity_id())

func spawn_teleporter_effect() -> void:
	"""Spawn BRIGHT PURPLE/BLUE swirling particle effect for teleporter activation"""
	if not death_particles:
		return

	# Temporarily change death particles to bright purple/blue for teleporter effect
	var teleporter_gradient: Gradient = Gradient.new()
	teleporter_gradient.add_point(0.0, Color(0.5, 0.3, 1.0, 1.0))  # Bright purple
	teleporter_gradient.add_point(0.3, Color(0.6, 0.5, 1.0, 0.9))  # Lighter purple
	teleporter_gradient.add_point(0.7, Color(0.7, 0.7, 1.0, 0.5))  # Light blue-purple
	teleporter_gradient.add_point(1.0, Color(0.8, 0.8, 1.0, 0.0))  # Transparent

	death_particles.color_ramp = teleporter_gradient
	death_particles.initial_velocity_min = 12.0  # Swirling motion
	death_particles.initial_velocity_max = 20.0
	death_particles.amount = 200  # Many particles for swirl effect

	# Trigger particle burst at destination position
	death_particles.global_position = global_position
	death_particles.emitting = true
	death_particles.restart()

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "BRIGHT PURPLE teleporter particle swirl spawned!", false, get_entity_id())

func apply_marble_material() -> void:
	"""Apply a unique procedural marble material to this player"""
	if not marble_mesh:
		return

	# Generate unique material based on player ID or custom selection
	var material: ShaderMaterial

	# Check if a custom color was set from the customize panel
	if custom_color_index >= 0:
		material = marble_material_manager.create_marble_material(custom_color_index)
	# Try to use a consistent color for the same player
	elif name.is_valid_int():
		var player_id = int(name)
		material = marble_material_manager.create_marble_material(player_id % marble_material_manager.get_color_scheme_count())
	elif str(multiplayer.get_unique_id()) != "0":
		# Use multiplayer ID for consistent color across sessions
		var peer_id = multiplayer.get_unique_id()
		material = marble_material_manager.create_marble_material(peer_id % marble_material_manager.get_color_scheme_count())
	else:
		# Fallback to random material
		material = marble_material_manager.get_random_marble_material()

	# Apply the material
	marble_mesh.material_override = material

	# Ensure shadow casting is enabled for proper lighting
	marble_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# Update aura light color to match marble - enhanced for visibility
	if aura_light and material:
		var primary_color = material.get_shader_parameter("primary_color")
		var secondary_color = material.get_shader_parameter("secondary_color")
		if primary_color:
			# Blend primary and secondary for a more vibrant glow
			var glow_color: Color = primary_color
			if secondary_color:
				glow_color = primary_color.lerp(secondary_color, 0.3)
			# Boost saturation and brightness for visibility
			var h: float = glow_color.h
			var s: float = minf(glow_color.s * 1.2, 1.0)  # Boost saturation
			var v: float = minf(glow_color.v * 1.3, 1.0)  # Boost brightness
			aura_light.light_color = Color.from_hsv(h, s, v)

	DebugLogger.dlog(DebugLogger.Category.PLAYER, "Applied marble material to player: %s" % name, false, get_entity_id())

func notify_kill(killer_id: int, victim_id: int) -> void:
	"""Notify the HUD about a kill - should be called on the killer's player node"""
	DebugLogger.dlog(DebugLogger.Category.PLAYER, "[NOTIFY_KILL] Called with killer_id: %d, victim_id: %d" % [killer_id, victim_id], false, get_entity_id())

	# Only show if this is the local player (has authority)
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "[NOTIFY_KILL] Skipping - not authority", false, get_entity_id())
		return  # Skip for non-authority players (bots, other players)

	var world: Node = get_parent()
	if not world:
		DebugLogger.dlog(DebugLogger.Category.PLAYER, "[NOTIFY_KILL] ERROR: No world node!", false, get_entity_id())
		return

	# Get the victim's name
	var victim: Node = world.get_node_or_null(str(victim_id))
	var victim_name: String = "Player"
	if victim:
		# Check if it's a bot (ID >= 9000) or player
		if victim_id >= 9000:
			victim_name = "Bot"
		else:
			victim_name = "Player %d" % victim_id

	# Find the HUD and show kill notification
	# HUD is at GameHUD/HUD path (see world.gd line 11)
	var game_hud = world.get_node_or_null("GameHUD/HUD")
	if game_hud and game_hud.has_method("show_kill_notification"):
		DebugLogger.dlog(DebugLogger.Category.UI, "[NOTIFY_KILL] Calling show_kill_notification for: %s" % victim_name, false, get_entity_id())
		game_hud.show_kill_notification(victim_name)
	else:
		DebugLogger.dlog(DebugLogger.Category.UI, "[NOTIFY_KILL] ERROR: GameHUD or method not found!", false, get_entity_id())

func notify_killstreak(player_id: int, streak: int) -> void:
	"""Notify the HUD about a killstreak milestone - should be called on the player's node"""
	# Only show if this is the local player (has authority)
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return  # Skip for non-authority players (bots, other players)

	var world: Node = get_parent()
	if not world:
		return

	# Find the HUD and show killstreak notification
	# HUD is at GameHUD/HUD path (see world.gd line 11)
	var game_hud = world.get_node_or_null("GameHUD/HUD")
	if game_hud and game_hud.has_method("show_killstreak_notification"):
		DebugLogger.dlog(DebugLogger.Category.UI, "Calling show_killstreak_notification for streak: %d" % streak, false, get_entity_id())
		game_hud.show_killstreak_notification(streak)
