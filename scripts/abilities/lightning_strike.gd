extends Ability

## Lightning Strike Ability
## Calls down a powerful lightning bolt from the sky to strike targets directly from above
## Works like cannon's auto-aim but the attack comes from the heavens!

@export var strike_damage: int = 1  # Base damage
@export var strike_delay: float = 0.55  # Delay before strike lands (warning flash gives time to react)
@export var lock_range: float = 40.0  # Auto-aim range (nerfed from 100)
@export var fire_rate: float = 1.75  # Cooldown between strikes
@onready var ability_sound: AudioStreamPlayer3D = $LightningSound

# Track strike targets
var pending_strikes: Array = []

# PERF: Shared lightning resources to avoid runtime allocations and shader recompiles
static var _shared_lightning_initialized: bool = false
static var _shared_warning_mesh: CylinderMesh = null
static var _shared_bolt_mesh: CylinderMesh = null
static var _shared_chain_mesh: CylinderMesh = null
static var _shared_warning_material: StandardMaterial3D = null
static var _shared_materials: Dictionary = {}
static var _shared_warning_gradient: Gradient = null
static var _shared_impact_gradient: Gradient = null
static var _shared_reticle_gradient: Gradient = null

# Reticle system for target lock visualization
var reticle: MeshInstance3D = null
var reticle_target: Node3D = null
var _target_scan_timer: float = 0.0  # Throttle find_nearest_player() calls

# Warning indicator that appears at strike location
var warning_indicator: MeshInstance3D = null

func _ready() -> void:
	super._ready()
	_ensure_shared_lightning_resources()
	ability_name = "Lightning"
	ability_color = Color(0.4, 0.8, 1.0)  # Electric cyan-blue
	cooldown_time = fire_rate
	supports_charging = true  # Must support charging for input to work
	max_charge_time = 0.01  # Instant fire - minimal charge time

	# Create reticle for target lock visualization (human player only)
	if not _is_bot_owner():
		create_reticle()

static func _ensure_shared_lightning_resources() -> void:
	if _shared_lightning_initialized:
		return
	_shared_lightning_initialized = true

	_shared_warning_mesh = CylinderMesh.new()
	_shared_warning_mesh.top_radius = 1.0
	_shared_warning_mesh.bottom_radius = 1.0
	_shared_warning_mesh.height = 0.1

	_shared_bolt_mesh = CylinderMesh.new()
	_shared_bolt_mesh.top_radius = 1.0
	_shared_bolt_mesh.bottom_radius = 1.0
	_shared_bolt_mesh.height = 1.0
	_shared_bolt_mesh.radial_segments = 4 if OS.has_feature("web") else 8

	_shared_chain_mesh = CylinderMesh.new()
	_shared_chain_mesh.top_radius = 1.0
	_shared_chain_mesh.bottom_radius = 1.0
	_shared_chain_mesh.height = 1.0
	_shared_chain_mesh.radial_segments = 3 if OS.has_feature("web") else 6

	_shared_warning_material = StandardMaterial3D.new()
	_shared_warning_material.albedo_color = Color(0.4, 0.8, 1.0, 0.5)  # Electric blue
	_shared_warning_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shared_warning_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shared_warning_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shared_warning_material.disable_receive_shadows = true

	_shared_warning_gradient = Gradient.new()
	_shared_warning_gradient.add_point(0.0, Color(0.6, 0.9, 1.0, 1.0))  # Bright cyan
	_shared_warning_gradient.add_point(0.5, Color(0.4, 0.8, 1.0, 0.8))  # Electric blue
	_shared_warning_gradient.add_point(1.0, Color(0.2, 0.4, 0.8, 0.0))  # Fade

	_shared_impact_gradient = Gradient.new()
	_shared_impact_gradient.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))  # White
	_shared_impact_gradient.add_point(0.3, Color(0.7, 0.85, 1.0, 0.8))  # Light blue
	_shared_impact_gradient.add_point(1.0, Color(0.3, 0.5, 0.8, 0.0))  # Fade

	_shared_reticle_gradient = Gradient.new()
	_shared_reticle_gradient.add_point(0.0, Color(0.8, 1.0, 1.0, 1.0))  # Bright cyan
	_shared_reticle_gradient.add_point(0.5, Color(0.4, 0.8, 1.0, 0.7))  # Electric blue
	_shared_reticle_gradient.add_point(1.0, Color(0.2, 0.5, 0.8, 0.0))  # Fade

static func _get_shared_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(), str(transparent)]
	if _shared_materials.has(key):
		return _shared_materials[key]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shared_materials[key] = mat
	return mat

func drop() -> void:
	"""Override drop to clean up reticle"""
	cleanup_reticle()
	super.drop()

func _exit_tree() -> void:
	"""Ensure reticle is cleaned up when ability is removed from scene"""
	cleanup_reticle()

func cleanup_reticle() -> void:
	"""Clean up the reticle when ability is dropped or destroyed"""
	if reticle and is_instance_valid(reticle):
		reticle.queue_free()
	reticle = null
	reticle_target = null

func find_nearest_player() -> Node3D:
	"""Find the nearest player to lock onto (excluding self) - prioritizes targets in forward cone"""
	if not player or not player.get_parent():
		return null

	var nearest: Node3D = null
	var nearest_distance: float = INF
	var max_lock_range: float = lock_range
	var max_angle_degrees: float = 90.0  # Wider cone than cannon since lightning comes from above
	# PERF: Precompute cosine threshold to avoid acos() per target
	var cos_max_angle: float = cos(deg_to_rad(max_angle_degrees))

	# Get player's forward direction
	var forward_direction: Vector3
	var camera_arm: Node3D = player.get_node_or_null("CameraArm")
	var camera: Camera3D = player.get_node_or_null("CameraArm/Camera3D")

	if camera:
		forward_direction = -camera.global_transform.basis.z
	elif camera_arm:
		forward_direction = -camera_arm.global_transform.basis.z

	forward_direction = forward_direction.normalized()

	# PERF: Use group instead of get_children() to avoid array allocation
	var forward_horizontal: Vector3 = forward_direction
	forward_horizontal.y = 0
	forward_horizontal = forward_horizontal.normalized()

	for potential_target in get_tree().get_nodes_in_group("players"):
		# Skip if it's ourselves
		if potential_target == player:
			continue

		# Check if it's a valid player (has health, not dead)
		if not potential_target.has_method('receive_damage_from'):
			continue

		# Check if player is alive
		if "health" in potential_target and potential_target.health <= 0:
			continue

		# Calculate direction to target (horizontal only for cone check)
		var to_target: Vector3 = (potential_target.global_position - player.global_position)
		to_target.y = 0
		to_target = to_target.normalized()

		# PERF: Use dot product directly instead of expensive acos() + rad_to_deg()
		var dot_product: float = forward_horizontal.dot(to_target)

		# Skip targets outside the forward cone (dot < cos(max_angle) means angle > max_angle)
		if dot_product < cos_max_angle:
			continue

		# Calculate distance
		var distance = player.global_position.distance_to(potential_target.global_position)

		# Check if within lock range and closer than current nearest
		if distance < max_lock_range and distance < nearest_distance:
			nearest = potential_target
			nearest_distance = distance

	return nearest

func activate() -> void:
	if not player:
		return

	# Get player level for level-based effects
	var player_level: int = player.level if "level" in player else 0

	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "LIGHTNING STRIKE! Calling down thunder from above! (Level %d)" % player_level, false, get_entity_id())

	# Level 3: Triple strike - strike at 3 locations
	var num_strikes: int = 1
	if player_level >= 3:
		num_strikes = 3

	# Find targets
	var targets: Array = find_multiple_targets(num_strikes)

	if targets.is_empty():
		# No target - spawn lightning at crosshair position (raycast forward)
		var camera: Camera3D = player.get_node_or_null("CameraArm/Camera3D")
		if camera:
			var fire_direction: Vector3 = -camera.global_transform.basis.z
			fire_direction.y = 0
			fire_direction = fire_direction.normalized()

			var strike_position: Vector3 = player.global_position + fire_direction * 15.0
			strike_position.y = player.global_position.y

			# Raycast to find ground
			var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				strike_position + Vector3.UP * 50.0,
				strike_position + Vector3.DOWN * 100.0
			)
			query.collision_mask = 1  # World only
			var result: Dictionary = space_state.intersect_ray(query)
			if result:
				strike_position = result.position

			spawn_lightning_strike(strike_position, null, player_level)
		return

	# Strike at each target's position
	for i in range(targets.size()):
		var target = targets[i]
		var strike_position: Vector3 = target.global_position
		if target is RigidBody3D and target.linear_velocity.length() > 1.0:
			# Predict where they'll be for warning indicator placement
			strike_position += target.linear_velocity * strike_delay

		# Delay additional strikes slightly for cascade effect
		if i > 0:
			var delay: float = i * 0.3
			get_tree().create_timer(delay).timeout.connect(func():
				if is_instance_valid(player) and is_instance_valid(target):
					spawn_lightning_strike(strike_position, target, player_level)
			)
		else:
			# Spawn warning indicator then lightning
			spawn_lightning_strike(strike_position, target, player_level)

func find_multiple_targets(max_targets: int) -> Array:
	"""Find multiple nearest players to target (for level 3 multi-strike)"""
	if not player or not player.get_parent():
		return []

	var targets: Array = []
	var max_lock_range: float = lock_range
	var max_angle_degrees: float = 90.0
	# PERF: Precompute cosine threshold to avoid acos() per target
	var cos_max_angle: float = cos(deg_to_rad(max_angle_degrees))

	# Get player's forward direction
	var forward_direction: Vector3
	var camera_arm: Node3D = player.get_node_or_null("CameraArm")
	var camera: Camera3D = player.get_node_or_null("CameraArm/Camera3D")

	if camera:
		forward_direction = -camera.global_transform.basis.z
	elif camera_arm:
		forward_direction = -camera_arm.global_transform.basis.z

	forward_direction = forward_direction.normalized()

	# Build a list of valid targets sorted by distance
	var potential_targets: Array = []

	# PERF: Compute forward_horizontal once outside the loop
	var forward_horizontal: Vector3 = forward_direction
	forward_horizontal.y = 0
	forward_horizontal = forward_horizontal.normalized()

	# PERF: Use group instead of get_children() to avoid array allocation
	for potential_target in get_tree().get_nodes_in_group("players"):
		if potential_target == player:
			continue
		if not potential_target.has_method('receive_damage_from'):
			continue
		if "health" in potential_target and potential_target.health <= 0:
			continue

		# Calculate direction to target (horizontal only for cone check)
		var to_target: Vector3 = (potential_target.global_position - player.global_position)
		to_target.y = 0
		to_target = to_target.normalized()

		# PERF: Use dot product directly instead of expensive acos() + rad_to_deg()
		var dot_product: float = forward_horizontal.dot(to_target)

		# Skip targets outside the forward cone
		if dot_product < cos_max_angle:
			continue

		var distance = player.global_position.distance_to(potential_target.global_position)
		if distance < max_lock_range:
			potential_targets.append({"target": potential_target, "distance": distance})

	# Sort by distance and take up to max_targets
	potential_targets.sort_custom(func(a, b): return a.distance < b.distance)

	for i in range(mini(max_targets, potential_targets.size())):
		targets.append(potential_targets[i].target)

	return targets

func spawn_lightning_strike(position: Vector3, target: Node3D, level: int = 0) -> void:
	"""Spawn the lightning strike effect and deal damage, with level-based enhancements"""
	if not player or not player.get_parent():
		return

	# Level-based strike radius scaling (clamped so level 0 doesn't shrink below baseline)
	var base_strike_radius: float = 4.0
	var strike_radius: float = base_strike_radius + (maxi(level - 1, 0) * 0.5)  # +0.5 radius per level above 1
	var aoe_radius: float = 3.5 + (maxi(level - 1, 0) * 0.3)  # +0.3 AoE per level above 1

	# Spawn warning circle at strike location (scaled by level)
	spawn_warning_indicator(position, level)

	# Play charging sound
	if ability_sound:
		ability_sound.global_position = position
		ability_sound.pitch_scale = 1.5  # Higher pitch for charge-up
		ability_sound.play()

	# Delay then strike
	await get_tree().create_timer(strike_delay).timeout

	# Strike lands where the warning appeared - no re-targeting so players can dodge
	# Spawn the actual lightning bolt (scaled by level)
	spawn_lightning_bolt(position, level)

	# Track who we've hit for chain lightning
	var hit_targets: Array = []

	# Deal damage to target if valid
	if target and is_instance_valid(target) and target.is_inside_tree():
		var distance_to_strike: float = target.global_position.distance_to(position)
		if distance_to_strike < strike_radius:
			var damage: int = strike_damage
			var owner_id: int = player.name.to_int() if player else -1
			var target_id: int = target.get_multiplayer_authority()

			if target_id >= 9000 or multiplayer.multiplayer_peer == null or target_id == multiplayer.get_unique_id():
				target.receive_damage_from(damage, owner_id)
				DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Lightning struck player (local): %s | Damage: %d" % [target.name, damage], false, get_entity_id())
			else:
				target.receive_damage_from.rpc_id(target_id, damage, owner_id)
				DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Lightning struck player (RPC): %s | Damage: %d" % [target.name, damage], false, get_entity_id())

			hit_targets.append(target)

			# Strong upward knockback from lightning (scaled by level)
			var level_mult: float = 1.0 + ((level - 1) * 0.2)
			var knockback: float = 120.0 * level_mult
			target.apply_central_impulse(Vector3.UP * knockback * 0.7 + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * knockback * 0.3)

	# Also check for any players in the strike radius
	# PERF: Cache group lookup and reuse for chain lightning
	var all_players: Array = get_tree().get_nodes_in_group("players")
	for potential_target in all_players:
		if potential_target == player:
			continue
		if potential_target in hit_targets:
			continue  # Already handled
		if not potential_target.has_method('receive_damage_from'):
			continue
		if "health" in potential_target and potential_target.health <= 0:
			continue

		var distance: float = potential_target.global_position.distance_to(position)
		if distance < aoe_radius:
			var damage: int = strike_damage
			var owner_id: int = player.name.to_int() if player else -1
			var target_id: int = potential_target.get_multiplayer_authority()

			if target_id >= 9000 or multiplayer.multiplayer_peer == null or target_id == multiplayer.get_unique_id():
				potential_target.receive_damage_from(damage, owner_id)
			else:
				potential_target.receive_damage_from.rpc_id(target_id, damage, owner_id)

			hit_targets.append(potential_target)

			# Knockback
			var knockback_dir: Vector3 = (potential_target.global_position - position).normalized()
			knockback_dir.y = 0.5
			potential_target.apply_central_impulse(knockback_dir * 80.0)

	# Level 2+: Chain lightning to nearby enemies
	if level >= 2 and hit_targets.size() > 0:
		var chain_delay: float = 0.4
		await get_tree().create_timer(chain_delay).timeout
		spawn_chain_lightning(hit_targets, level, all_players)

func spawn_warning_indicator(position: Vector3, level: int = 0) -> void:
	"""Spawn a warning circle at the strike location, scaled by level"""
	if not player or not player.get_parent():
		return

	# Scale indicator with level
	var radius_scale: float = 1.0 + ((level - 1) * 0.15)

	var indicator: MeshInstance3D = MeshInstance3D.new()
	indicator.name = "LightningWarning"

	# Shared mesh/material for warning disc
	indicator.mesh = _shared_warning_mesh
	indicator.material_override = _shared_warning_material

	player.get_parent().add_child(indicator)
	indicator.global_position = position + Vector3.UP * 0.1
	indicator.scale = Vector3(2.5 * radius_scale, 1.0, 2.5 * radius_scale)

	# Add warning particles
	var warning_particles: CPUParticles3D = CPUParticles3D.new()
	warning_particles.name = "WarningParticles"
	indicator.add_child(warning_particles)

	warning_particles.emitting = true
	warning_particles.amount = 5 if _is_web else 10  # PERF: Reduced for performance
	warning_particles.lifetime = 0.5
	warning_particles.explosiveness = 0.5
	warning_particles.randomness = 0.3
	warning_particles.local_coords = false

	# PERF: Use shared particle mesh + material
	warning_particles.mesh = _shared_particle_quad_small

	warning_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	warning_particles.emission_ring_axis = Vector3.UP
	warning_particles.emission_ring_height = 0.1
	warning_particles.emission_ring_radius = 2.0
	warning_particles.emission_ring_inner_radius = 0.5

	warning_particles.direction = Vector3.UP
	warning_particles.spread = 30.0
	warning_particles.gravity = Vector3.ZERO
	warning_particles.initial_velocity_min = 2.0
	warning_particles.initial_velocity_max = 4.0

	warning_particles.color_ramp = _shared_warning_gradient

	# Remove after strike
	get_tree().create_timer(strike_delay + 0.1).timeout.connect(indicator.queue_free)

func create_bolt_layer(container: Node3D, path: Array[Vector3], radius: float, color: Color, _emission_energy: float, transparent: bool) -> void:
	"""Create a single layer of the lightning bolt (GL Compatibility friendly - no emission)"""
	var shared_mat: StandardMaterial3D = _get_shared_material(color, transparent)

	for i in range(path.size() - 1):
		var segment: MeshInstance3D = MeshInstance3D.new()
		segment.name = "BoltLayer_%d" % i

		var start_pos: Vector3 = path[i]
		var end_pos: Vector3 = path[i + 1]

		# Shared mesh, scale per segment
		var taper: float = float(i) / float(path.size())  # Taper towards top
		var segment_radius: float = radius * (1.0 - taper * 0.25)
		var segment_height: float = start_pos.distance_to(end_pos)
		segment.mesh = _shared_bolt_mesh
		segment.material_override = shared_mat
		segment.scale = Vector3(segment_radius, segment_height, segment_radius)

		container.add_child(segment)

		# Position and orient segment
		var mid_point: Vector3 = (start_pos + end_pos) / 2.0
		segment.position = mid_point
		segment.look_at(container.global_position + end_pos, Vector3.FORWARD)
		segment.rotation.x += PI / 2.0

func spawn_lightning_bolt(position: Vector3, level: int = 0) -> void:
	"""Spawn a clean lightning bolt effect (GL Compatibility friendly)"""
	if not player or not player.get_parent():
		return

	var bolt_height: float = 80.0

	var bolt_container: Node3D = Node3D.new()
	bolt_container.name = "LightningBolt"
	player.get_parent().add_child(bolt_container)
	bolt_container.global_position = position

	# Generate main bolt path with sharp zigzag pattern
	var bolt_path: Array[Vector3] = []
	var current_pos: Vector3 = Vector3.ZERO
	var num_segments: int = 8 if OS.has_feature("web") else 16
	var segment_height: float = bolt_height / num_segments

	bolt_path.append(current_pos)
	for i in range(num_segments):
		var next_pos: Vector3 = current_pos + Vector3.UP * segment_height
		if i < num_segments - 1:
			# Sharp zigzag offsets for lightning look
			next_pos.x += randf_range(-2.5, 2.5)
			next_pos.z += randf_range(-2.5, 2.5)
		bolt_path.append(next_pos)
		current_pos = next_pos

	# Simple 2-layer bolt: subtle glow + bright white core
	create_bolt_layer(bolt_container, bolt_path, 1.0, Color(0.5, 0.7, 1.0, 0.4), 0.0, true)  # Subtle blue glow
	create_bolt_layer(bolt_container, bolt_path, 0.3, Color(1.0, 1.0, 1.0, 1.0), 0.0, false)  # White core

	# Add 1-2 small branches (skip branches on web for performance)
	var num_branches: int = 0 if _is_web else (1 + int(level * 0.5))  # PERF: No branches on web
	for b in range(num_branches):
		var branch_start_idx: int = randi_range(4, num_segments - 5)
		var branch_start: Vector3 = bolt_path[branch_start_idx]

		var branch_path: Array[Vector3] = []
		var branch_pos: Vector3 = branch_start
		var branch_segments: int = randi_range(3, 5)
		var branch_dir: Vector3 = Vector3(randf_range(-1, 1), -0.3, randf_range(-1, 1)).normalized()

		branch_path.append(branch_pos)
		for s in range(branch_segments):
			var branch_next: Vector3 = branch_pos + branch_dir * randf_range(4.0, 7.0)
			branch_next.x += randf_range(-1.5, 1.5)
			branch_next.z += randf_range(-1.5, 1.5)
			branch_path.append(branch_next)
			branch_pos = branch_next
			branch_dir.y -= 0.15

		# Thinner branch layers
		create_bolt_layer(bolt_container, branch_path, 0.5, Color(0.6, 0.8, 1.0, 0.35), 0.0, true)
		create_bolt_layer(bolt_container, branch_path, 0.15, Color(1.0, 1.0, 1.0, 0.9), 0.0, false)

	# Small impact spark particles at ground
	var impact_particles: CPUParticles3D = CPUParticles3D.new()
	impact_particles.name = "ImpactParticles"
	bolt_container.add_child(impact_particles)

	impact_particles.emitting = true
	impact_particles.amount = 6 if _is_web else 12  # PERF: Reduced for performance
	impact_particles.lifetime = 0.4
	impact_particles.one_shot = true
	impact_particles.explosiveness = 1.0
	impact_particles.randomness = 0.4
	impact_particles.local_coords = false

	# PERF: Use shared particle mesh + material
	impact_particles.mesh = _shared_particle_quad_medium

	impact_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	impact_particles.emission_sphere_radius = 0.5

	impact_particles.direction = Vector3.UP
	impact_particles.spread = 120.0
	impact_particles.gravity = Vector3(0, -12.0, 0)
	impact_particles.initial_velocity_min = 8.0
	impact_particles.initial_velocity_max = 15.0

	impact_particles.scale_amount_min = 1.5
	impact_particles.scale_amount_max = 3.0

	impact_particles.color_ramp = _shared_impact_gradient

	# Play thunder sound
	if ability_sound:
		ability_sound.pitch_scale = 0.7
		ability_sound.volume_db = 5.0
		ability_sound.play()

	# Camera shake
	if player and player.has_method("add_camera_shake"):
		player.add_camera_shake(0.15)

	# Clean up after effect ends
	get_tree().create_timer(0.6).timeout.connect(bolt_container.queue_free)

func spawn_chain_lightning(hit_targets: Array, level: int, cached_players: Array = []) -> void:
	"""Spawn chain lightning to nearby enemies (Level 2+ effect)"""
	if not player or not player.get_parent():
		return

	var chain_range: float = 8.0 + ((level - 1) * 2.0)  # Chain range increases with level
	var num_chains: int = 1 + (level - 2)  # Level 2: 1 chain, Level 3: 2 chains
	var owner_id: int = player.name.to_int() if player else -1

	# For each hit target, find nearby enemies to chain to
	var chained_targets: Array = []
	for source_target in hit_targets:
		if not is_instance_valid(source_target):
			continue

		var chains_spawned: int = 0
		# PERF: Use cached player list instead of querying group again
		var player_list: Array = cached_players if cached_players.size() > 0 else get_tree().get_nodes_in_group("players")
		for potential_target in player_list:
			if chains_spawned >= num_chains:
				break
			if potential_target == player:
				continue
			if potential_target in hit_targets:
				continue  # Already hit by main strike
			if potential_target in chained_targets:
				continue  # Already chained
			if not potential_target.has_method('receive_damage_from'):
				continue
			if "health" in potential_target and potential_target.health <= 0:
				continue

			var distance: float = potential_target.global_position.distance_to(source_target.global_position)
			if distance < chain_range:
				chained_targets.append(potential_target)
				chains_spawned += 1

				# Spawn visual chain effect
				spawn_chain_arc(source_target.global_position, potential_target.global_position)

				# Deal reduced damage
				var chain_damage: int = 1
				var target_id: int = potential_target.get_multiplayer_authority()

				if target_id >= 9000 or multiplayer.multiplayer_peer == null or target_id == multiplayer.get_unique_id():
					potential_target.receive_damage_from(chain_damage, owner_id)
					DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Chain lightning hit (local): %s" % potential_target.name, false, get_entity_id())
				else:
					potential_target.receive_damage_from.rpc_id(target_id, chain_damage, owner_id)
					DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Chain lightning hit (RPC): %s" % potential_target.name, false, get_entity_id())

				# Apply knockback
				var knockback_dir: Vector3 = (potential_target.global_position - source_target.global_position).normalized()
				knockback_dir.y = 0.3
				potential_target.apply_central_impulse(knockback_dir * 60.0)

func spawn_chain_arc(from_pos: Vector3, to_pos: Vector3) -> void:
	"""Spawn a visual lightning arc between two positions (GL Compatibility friendly)"""
	if not player or not player.get_parent():
		return

	# Create container for chain effect
	var chain_container: Node3D = Node3D.new()
	chain_container.name = "ChainLightning"
	player.get_parent().add_child(chain_container)

	# Position at midpoint
	var midpoint: Vector3 = (from_pos + to_pos) / 2.0
	chain_container.global_position = midpoint

	var direction: Vector3 = (to_pos - from_pos).normalized()
	var distance: float = from_pos.distance_to(to_pos)

	# Generate jagged chain path
	var chain_path: Array[Vector3] = []
	var num_chain_segments: int = 4 if _is_web else 8  # PERF: Fewer segments on web
	var segment_length: float = distance / num_chain_segments
	var chain_pos: Vector3 = from_pos - midpoint  # Relative to container

	chain_path.append(chain_pos)
	for i in range(num_chain_segments):
		var next_chain_pos: Vector3 = chain_pos + direction * segment_length
		if i < num_chain_segments - 1:
			# Add jaggedness
			next_chain_pos += Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0))
		chain_path.append(next_chain_pos)
		chain_pos = next_chain_pos

	# Simple 2-layer chain: subtle glow + white core
	create_chain_layer(chain_container, chain_path, 0.4, Color(0.5, 0.7, 1.0, 0.35))
	create_chain_layer(chain_container, chain_path, 0.12, Color(1.0, 1.0, 1.0, 1.0))

	# Auto-cleanup
	get_tree().create_timer(0.3).timeout.connect(chain_container.queue_free)

func create_chain_layer(container: Node3D, path: Array[Vector3], radius: float, color: Color) -> void:
	"""Create a single layer for chain lightning (GL Compatibility friendly)"""
	var shared_mat: StandardMaterial3D = _get_shared_material(color, color.a < 1.0)

	for i in range(path.size() - 1):
		var segment: MeshInstance3D = MeshInstance3D.new()
		segment.name = "ChainLayer_%d" % i

		var start_pos: Vector3 = path[i]
		var end_pos: Vector3 = path[i + 1]

		var segment_height: float = start_pos.distance_to(end_pos)
		segment.mesh = _shared_chain_mesh
		segment.material_override = shared_mat
		segment.scale = Vector3(radius, segment_height, radius)

		container.add_child(segment)

		var mid_point: Vector3 = (start_pos + end_pos) / 2.0
		segment.position = mid_point
		segment.look_at(container.global_position + end_pos, Vector3.FORWARD)
		segment.rotation.x += PI / 2.0

func create_reticle() -> void:
	"""Create a 3D reticle that follows the locked target"""
	cleanup_reticle()

	reticle = MeshInstance3D.new()
	reticle.name = "LightningReticle"

	# Create a lightning bolt shaped reticle (diamond pattern)
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.6
	torus.outer_radius = 1.0
	torus.rings = 4  # Diamond shape - already low poly
	torus.ring_segments = 4
	reticle.mesh = torus

	# Electric blue material
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.8, 1.0, 0.5)  # Electric cyan
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	mat.disable_fog = true
	reticle.material_override = mat

	# Add electric spark particles
	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.name = "ReticleParticles"
	reticle.add_child(particles)

	particles.emitting = true
	particles.amount = 4 if _is_web else 8  # PERF: Reduced for performance
	particles.lifetime = 0.5
	particles.explosiveness = 0.0
	particles.randomness = 0.3
	particles.local_coords = true

	# PERF: Use shared particle mesh + material
	particles.mesh = _shared_particle_quad_small

	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	particles.emission_ring_axis = Vector3(0, 1, 0)
	particles.emission_ring_height = 0.1
	particles.emission_ring_radius = 0.8
	particles.emission_ring_inner_radius = 0.5

	particles.direction = Vector3.UP
	particles.spread = 60.0
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = 1.0
	particles.initial_velocity_max = 2.0

	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 1.5

	particles.color_ramp = _shared_reticle_gradient

	reticle.visible = false

func _process(delta: float) -> void:
	super._process(delta)

	if not reticle or not is_instance_valid(reticle):
		return

	if player and is_instance_valid(player) and player.is_inside_tree():
		# PERF: Only show indicator for local human player (not bots)
		var is_local_player: bool = is_local_human_player()

		if is_local_player:
			# Get player level for level-based indicator
			var player_level: int = player.level if "level" in player else 0

			# Throttle find_nearest_player() to 8Hz (was every frame with O(N) acos per player)
			_target_scan_timer -= delta
			if _target_scan_timer <= 0.0:
				reticle_target = find_nearest_player()
				_target_scan_timer = 0.125
			var target = reticle_target

			if target and is_instance_valid(target):
				if not reticle.is_inside_tree():
					if player.get_parent():
						player.get_parent().add_child(reticle)

				reticle.visible = true

				# Position reticle ABOVE target (lightning comes from above!)
				var target_position = target.global_position + Vector3(0, 3.0, 0)
				reticle.global_position = reticle.global_position.lerp(target_position, delta * 8.0)

				# Scale reticle based on level (larger strike area at higher levels)
				var level_scale: float = 1.0 + ((player_level - 1) * 0.15)
				reticle.scale = Vector3(level_scale, level_scale, level_scale)

				# Update reticle color based on level
				var mat: StandardMaterial3D = reticle.material_override
				if mat:
					if player_level >= 3:
						# Level 3: Bright cyan (triple strike)
						mat.albedo_color = Color(0.3, 0.9, 1.0, 0.6)
					elif player_level >= 2:
						# Level 2: Brighter cyan (chain lightning)
						mat.albedo_color = Color(0.35, 0.85, 1.0, 0.55)
					elif player_level >= 1:
						# Level 1: Light cyan (larger area)
						mat.albedo_color = Color(0.4, 0.8, 1.0, 0.5)
					else:
						# Level 0: Standard cyan
						mat.albedo_color = Color(0.4, 0.8, 1.0, 0.5)

				# Rotate and pulse for electric effect (faster at higher levels)
				var rotation_speed: float = 4.0 + ((player_level - 1) * 1.0)
				reticle.rotation.y += delta * rotation_speed
				reticle.rotation.x = sin(Time.get_ticks_msec() * 0.01) * 0.2
			else:
				reticle.visible = false
				reticle_target = null
		else:
			reticle.visible = false
			reticle_target = null
	else:
		reticle.visible = false
		reticle_target = null
