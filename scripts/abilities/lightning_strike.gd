extends Ability

## Lightning Strike Ability
## Calls down a powerful lightning bolt from the sky to strike targets directly from above
## Works like cannon's auto-aim but the attack comes from the heavens!

@export var strike_damage: int = 1  # Base damage
@export var strike_delay: float = 0.5  # Delay before strike lands (for dramatic effect)
@export var lock_range: float = 100.0  # Auto-aim range
@export var fire_rate: float = 1.8  # Cooldown between strikes
@onready var ability_sound: AudioStreamPlayer3D = $LightningSound

# Track strike targets
var pending_strikes: Array = []

# Reticle system for target lock visualization
var reticle: MeshInstance3D = null
var reticle_target: Node3D = null

# Warning indicator that appears at strike location
var warning_indicator: MeshInstance3D = null

func _ready() -> void:
	super._ready()
	ability_name = "Lightning"
	ability_color = Color(0.4, 0.8, 1.0)  # Electric cyan-blue
	cooldown_time = fire_rate
	supports_charging = true  # Must support charging for input to work
	max_charge_time = 0.01  # Instant fire - minimal charge time

	# Create reticle for target lock visualization
	create_reticle()

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

	# Get player's forward direction
	var forward_direction: Vector3
	var camera_arm: Node3D = player.get_node_or_null("CameraArm")
	var camera: Camera3D = player.get_node_or_null("CameraArm/Camera3D")

	if camera:
		forward_direction = -camera.global_transform.basis.z
	elif camera_arm:
		forward_direction = -camera_arm.global_transform.basis.z

	forward_direction = forward_direction.normalized()

	# Get all nodes in the Players container
	var players_container = player.get_parent()
	for potential_target in players_container.get_children():
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

		var forward_horizontal: Vector3 = forward_direction
		forward_horizontal.y = 0
		forward_horizontal = forward_horizontal.normalized()

		# Calculate angle between forward direction and target direction
		var dot_product: float = forward_horizontal.dot(to_target)
		var angle_radians: float = acos(clamp(dot_product, -1.0, 1.0))
		var angle_degrees: float = rad_to_deg(angle_radians)

		# Skip targets outside the forward cone
		if angle_degrees > max_angle_degrees:
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
			# Predict where they'll be
			strike_position += target.linear_velocity * strike_delay * 0.5

		# Delay additional strikes slightly for cascade effect
		if i > 0:
			var delay: float = i * 0.15
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
	var players_container = player.get_parent()

	for potential_target in players_container.get_children():
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

		var forward_horizontal: Vector3 = forward_direction
		forward_horizontal.y = 0
		forward_horizontal = forward_horizontal.normalized()

		var dot_product: float = forward_horizontal.dot(to_target)
		var angle_radians: float = acos(clamp(dot_product, -1.0, 1.0))
		var angle_degrees: float = rad_to_deg(angle_radians)

		if angle_degrees > max_angle_degrees:
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

	# Level-based strike radius scaling
	var base_strike_radius: float = 3.0
	var strike_radius: float = base_strike_radius + ((level - 1) * 0.5)  # +0.5 radius per level
	var aoe_radius: float = 2.5 + ((level - 1) * 0.3)  # +0.3 AoE per level

	# Spawn warning circle at strike location (scaled by level)
	spawn_warning_indicator(position, level)

	# Play charging sound
	if ability_sound:
		ability_sound.global_position = position
		ability_sound.pitch_scale = 1.5  # Higher pitch for charge-up
		ability_sound.play()

	# Delay then strike
	await get_tree().create_timer(strike_delay).timeout

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
	var players_container = player.get_parent()
	for potential_target in players_container.get_children():
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
		var chain_delay: float = 0.2
		await get_tree().create_timer(chain_delay).timeout
		spawn_chain_lightning(hit_targets, level)

func spawn_warning_indicator(position: Vector3, level: int = 0) -> void:
	"""Spawn a warning circle at the strike location, scaled by level"""
	if not player or not player.get_parent():
		return

	# Scale indicator with level
	var radius_scale: float = 1.0 + ((level - 1) * 0.15)

	var indicator: MeshInstance3D = MeshInstance3D.new()
	indicator.name = "LightningWarning"

	# Create a disc/cylinder mesh for the warning
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = 2.5 * radius_scale
	cylinder.bottom_radius = 2.5 * radius_scale
	cylinder.height = 0.1
	indicator.mesh = cylinder

	# Pulsing electric material
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.8, 1.0, 0.5)  # Electric blue
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	indicator.material_override = mat

	player.get_parent().add_child(indicator)
	indicator.global_position = position + Vector3.UP * 0.1

	# Add warning particles
	var warning_particles: CPUParticles3D = CPUParticles3D.new()
	warning_particles.name = "WarningParticles"
	indicator.add_child(warning_particles)

	warning_particles.emitting = true
	warning_particles.amount = 20
	warning_particles.lifetime = 0.5
	warning_particles.explosiveness = 0.5
	warning_particles.randomness = 0.3
	warning_particles.local_coords = false

	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.2, 0.2)

	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_mesh.material = particle_material
	warning_particles.mesh = particle_mesh

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

	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.6, 0.9, 1.0, 1.0))  # Bright cyan
	gradient.add_point(0.5, Color(0.4, 0.8, 1.0, 0.8))  # Electric blue
	gradient.add_point(1.0, Color(0.2, 0.4, 0.8, 0.0))  # Fade
	warning_particles.color_ramp = gradient

	# Remove after strike
	get_tree().create_timer(strike_delay + 0.1).timeout.connect(indicator.queue_free)

func spawn_lightning_bolt(position: Vector3, level: int = 0) -> void:
	"""Spawn the dramatic lightning bolt effect, scaled by level"""
	if not player or not player.get_parent():
		return

	# Scale bolt intensity with level
	var intensity_scale: float = 1.0 + ((level - 1) * 0.2)
	var bolt_height: float = 80.0  # Height of the lightning bolt

	# Create main bolt line using multiple segments
	var bolt_container: Node3D = Node3D.new()
	bolt_container.name = "LightningBolt"
	player.get_parent().add_child(bolt_container)
	bolt_container.global_position = position

	# Create bright core flash at impact (scaled by level)
	var impact_flash: OmniLight3D = OmniLight3D.new()
	impact_flash.name = "ImpactFlash"
	bolt_container.add_child(impact_flash)
	impact_flash.light_color = Color(0.7, 0.9, 1.0)
	impact_flash.light_energy = 15.0 * intensity_scale
	impact_flash.omni_range = 20.0 * intensity_scale
	impact_flash.omni_attenuation = 1.0

	# Create bolt segments (jagged lightning)
	var num_segments: int = 12
	var segment_height: float = bolt_height / num_segments
	var current_pos: Vector3 = Vector3.ZERO

	for i in range(num_segments):
		var segment: MeshInstance3D = MeshInstance3D.new()
		segment.name = "BoltSegment_%d" % i

		# Calculate next position with random offset for jagged look
		var next_pos: Vector3 = current_pos + Vector3.UP * segment_height
		if i < num_segments - 1:  # Don't offset the top
			next_pos.x += randf_range(-1.5, 1.5)
			next_pos.z += randf_range(-1.5, 1.5)

		# Create cylinder mesh for segment
		var cylinder: CylinderMesh = CylinderMesh.new()
		cylinder.top_radius = 0.2 + (i * 0.02)  # Thinner at top
		cylinder.bottom_radius = 0.3 - (i * 0.015)  # Thicker at bottom
		cylinder.height = current_pos.distance_to(next_pos)
		segment.mesh = cylinder

		# Bright electric material
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.85, 1.0)  # Electric blue core (no white)
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.8, 1.0)  # Electric blue glow
		mat.emission_energy_multiplier = 5.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		segment.material_override = mat

		bolt_container.add_child(segment)

		# Position and orient segment
		var mid_point: Vector3 = (current_pos + next_pos) / 2.0
		segment.position = mid_point
		segment.look_at(bolt_container.global_position + next_pos, Vector3.FORWARD)
		segment.rotation.x += PI / 2.0

		current_pos = next_pos

	# Spawn impact explosion particles
	var impact_particles: CPUParticles3D = CPUParticles3D.new()
	impact_particles.name = "ImpactParticles"
	bolt_container.add_child(impact_particles)

	impact_particles.emitting = true
	impact_particles.amount = 60
	impact_particles.lifetime = 0.8
	impact_particles.one_shot = true
	impact_particles.explosiveness = 1.0
	impact_particles.randomness = 0.4
	impact_particles.local_coords = false

	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.5, 0.5)

	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_mesh.material = particle_material
	impact_particles.mesh = particle_mesh

	impact_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	impact_particles.emission_sphere_radius = 1.0

	impact_particles.direction = Vector3.UP
	impact_particles.spread = 180.0
	impact_particles.gravity = Vector3(0, -5.0, 0)
	impact_particles.initial_velocity_min = 8.0
	impact_particles.initial_velocity_max = 15.0

	impact_particles.scale_amount_min = 2.0
	impact_particles.scale_amount_max = 4.0

	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.7, 0.9, 1.0, 1.0))  # Electric cyan-blue (no white)
	gradient.add_point(0.2, Color(0.7, 0.9, 1.0, 1.0))  # Light cyan
	gradient.add_point(0.5, Color(0.4, 0.7, 1.0, 0.8))  # Electric blue
	gradient.add_point(0.8, Color(0.3, 0.5, 0.9, 0.4))  # Blue
	gradient.add_point(1.0, Color(0.1, 0.2, 0.5, 0.0))  # Fade
	impact_particles.color_ramp = gradient

	# Spawn electric arc particles along bolt
	var arc_particles: CPUParticles3D = CPUParticles3D.new()
	arc_particles.name = "ArcParticles"
	bolt_container.add_child(arc_particles)
	arc_particles.position = Vector3.UP * (bolt_height / 2.0)

	arc_particles.emitting = true
	arc_particles.amount = 100
	arc_particles.lifetime = 0.4
	arc_particles.one_shot = true
	arc_particles.explosiveness = 0.8
	arc_particles.randomness = 0.5
	arc_particles.local_coords = false

	var arc_mesh: QuadMesh = QuadMesh.new()
	arc_mesh.size = Vector2(0.15, 0.15)
	arc_mesh.material = particle_material  # Reuse material
	arc_particles.mesh = arc_mesh

	arc_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	arc_particles.emission_box_extents = Vector3(2.0, bolt_height / 2.0, 2.0)

	arc_particles.direction = Vector3(1, 0, 0)
	arc_particles.spread = 180.0
	arc_particles.gravity = Vector3.ZERO
	arc_particles.initial_velocity_min = 5.0
	arc_particles.initial_velocity_max = 10.0

	arc_particles.scale_amount_min = 1.0
	arc_particles.scale_amount_max = 2.0
	arc_particles.color_ramp = gradient

	# Play thunder sound (louder, lower pitch)
	if ability_sound:
		ability_sound.pitch_scale = 0.6  # Deep thunder
		ability_sound.volume_db = 6.0
		ability_sound.play()

	# Camera shake for nearby players
	if player and player.has_method("add_camera_shake"):
		player.add_camera_shake(0.15)

	# Fade out and clean up
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(impact_flash, "light_energy", 0.0, 0.4)
	tween.tween_callback(bolt_container.queue_free)

func spawn_chain_lightning(hit_targets: Array, level: int) -> void:
	"""Spawn chain lightning to nearby enemies (Level 2+ effect)"""
	if not player or not player.get_parent():
		return

	var chain_range: float = 8.0 + ((level - 1) * 2.0)  # Chain range increases with level
	var num_chains: int = 1 + (level - 2)  # Level 2: 1 chain, Level 3: 2 chains
	var owner_id: int = player.name.to_int() if player else -1
	var players_container = player.get_parent()

	# For each hit target, find nearby enemies to chain to
	var chained_targets: Array = []
	for source_target in hit_targets:
		if not is_instance_valid(source_target):
			continue

		var chains_spawned: int = 0
		for potential_target in players_container.get_children():
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
	"""Spawn a visual lightning arc between two positions"""
	if not player or not player.get_parent():
		return

	# Create particle effect for the chain
	var chain_particles: CPUParticles3D = CPUParticles3D.new()
	chain_particles.name = "ChainLightning"
	player.get_parent().add_child(chain_particles)

	# Position at midpoint
	var midpoint: Vector3 = (from_pos + to_pos) / 2.0
	chain_particles.global_position = midpoint

	chain_particles.emitting = true
	chain_particles.amount = 30
	chain_particles.lifetime = 0.3
	chain_particles.one_shot = true
	chain_particles.explosiveness = 0.8
	chain_particles.randomness = 0.4
	chain_particles.local_coords = false

	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.2, 0.2)

	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_mesh.material = particle_material
	chain_particles.mesh = particle_mesh

	# Emit along the line between the two targets
	var direction: Vector3 = (to_pos - from_pos).normalized()
	var distance: float = from_pos.distance_to(to_pos)

	chain_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	chain_particles.emission_box_extents = Vector3(0.5, 0.5, distance / 2.0)

	# Orient the emission box along the chain direction
	chain_particles.look_at(chain_particles.global_position + direction, Vector3.UP)

	chain_particles.direction = direction
	chain_particles.spread = 20.0
	chain_particles.gravity = Vector3.ZERO
	chain_particles.initial_velocity_min = 2.0
	chain_particles.initial_velocity_max = 5.0

	chain_particles.scale_amount_min = 1.5
	chain_particles.scale_amount_max = 2.5

	# Electric cyan gradient
	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.8, 1.0, 1.0, 1.0))  # Bright cyan
	gradient.add_point(0.3, Color(0.5, 0.9, 1.0, 0.9))  # Electric blue
	gradient.add_point(0.7, Color(0.3, 0.7, 1.0, 0.5))  # Blue
	gradient.add_point(1.0, Color(0.1, 0.3, 0.6, 0.0))  # Fade
	chain_particles.color_ramp = gradient

	# Also create a brief light flash along the chain
	var chain_light: OmniLight3D = OmniLight3D.new()
	chain_light.name = "ChainLight"
	chain_particles.add_child(chain_light)
	chain_light.light_color = Color(0.6, 0.9, 1.0)
	chain_light.light_energy = 5.0
	chain_light.omni_range = distance * 0.5

	# Auto-cleanup
	get_tree().create_timer(chain_particles.lifetime + 0.3).timeout.connect(func():
		if is_instance_valid(chain_particles):
			chain_particles.queue_free()
	)

func create_reticle() -> void:
	"""Create a 3D reticle that follows the locked target"""
	cleanup_reticle()

	reticle = MeshInstance3D.new()
	reticle.name = "LightningReticle"

	# Create a lightning bolt shaped reticle (diamond pattern)
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.6
	torus.outer_radius = 1.0
	torus.rings = 4  # Diamond shape
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
	particles.amount = 15
	particles.lifetime = 0.5
	particles.explosiveness = 0.0
	particles.randomness = 0.3
	particles.local_coords = true

	var particle_mesh: QuadMesh = QuadMesh.new()
	particle_mesh.size = Vector2(0.1, 0.1)

	var particle_material: StandardMaterial3D = StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.vertex_color_use_as_albedo = true
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_mesh.material = particle_material
	particles.mesh = particle_mesh

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

	var gradient: Gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.8, 1.0, 1.0, 1.0))  # Bright cyan
	gradient.add_point(0.5, Color(0.4, 0.8, 1.0, 0.7))  # Electric blue
	gradient.add_point(1.0, Color(0.2, 0.5, 0.8, 0.0))  # Fade
	particles.color_ramp = gradient

	reticle.visible = false

func _process(delta: float) -> void:
	super._process(delta)

	if not reticle or not is_instance_valid(reticle):
		return

	if player and is_instance_valid(player) and player.is_inside_tree():
		var is_local_player: bool = player.is_multiplayer_authority()

		if is_local_player:
			# Get player level for level-based indicator
			var player_level: int = player.level if "level" in player else 0

			var target = find_nearest_player()

			if target and is_instance_valid(target):
				if not reticle.is_inside_tree():
					if player.get_parent():
						player.get_parent().add_child(reticle)

				reticle.visible = true
				reticle_target = target

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
