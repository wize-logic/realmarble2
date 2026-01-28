extends Node
class_name UltSystem

## Ultimate Attack System
## Charges through combat and unleashes a devastating power dash!

# Ult charge settings
const MAX_ULT_CHARGE: float = 100.0
const CHARGE_PER_DAMAGE_DEALT: float = 15.0  # Charge gained when dealing damage
const CHARGE_PER_DAMAGE_TAKEN: float = 8.0   # Charge gained when taking damage
const CHARGE_PER_KILL: float = 25.0          # Bonus charge for kills
const CHARGE_DECAY_RATE: float = 0.0         # No decay - keep your charge!

# Ult attack settings
const ULT_DASH_FORCE: float = 400.0          # Extremely powerful dash
const ULT_DASH_DURATION: float = 0.6         # Duration of the dash
const ULT_DAMAGE: int = 2                     # Damage dealt to enemies hit
const ULT_KNOCKBACK: float = 300.0           # Massive knockback
const ULT_RADIUS: float = 4.0                # Hitbox radius during ult

# State
var player: Node = null
var ult_charge: float = 0.0
var is_ulting: bool = false
var ult_timer: float = 0.0
var ult_direction: Vector3 = Vector3.ZERO
var hit_players: Array = []

# Visual components
var ult_particles: CPUParticles3D = null
var power_aura: CPUParticles3D = null
var shockwave_ring: MeshInstance3D = null
var ult_light: OmniLight3D = null
var trail_particles: CPUParticles3D = null
var hitbox: Area3D = null

# UI components
var ult_meter_ui: Control = null
var ult_meter_bar: ProgressBar = null
var ult_meter_label: Label = null
var ult_ready_flash: float = 0.0

signal ult_activated
signal ult_charge_changed(new_charge: float)
signal ult_ready

func _ready() -> void:
	create_ult_meter_ui()
	create_hitbox()
	create_visual_effects()

func setup(p_player: Node) -> void:
	"""Initialize the ult system for a player"""
	player = p_player

func _process(delta: float) -> void:
	if not player:
		return

	# Update ult meter UI
	update_ult_meter_ui()

	# Handle ult state
	if is_ulting:
		ult_timer -= delta
		if ult_timer <= 0.0:
			end_ult()
		else:
			# Continue ult dash
			process_ult_dash(delta)

	# Flash effect when ult is ready
	if ult_charge >= MAX_ULT_CHARGE:
		ult_ready_flash += delta * 4.0
		if power_aura and not power_aura.emitting:
			power_aura.emitting = true

func add_charge(amount: float) -> void:
	"""Add charge to the ult meter"""
	if is_ulting:
		return  # Can't charge while ulting

	var old_charge: float = ult_charge
	ult_charge = min(ult_charge + amount, MAX_ULT_CHARGE)

	if ult_charge != old_charge:
		emit_signal("ult_charge_changed", ult_charge)

	# Check if just became ready
	if old_charge < MAX_ULT_CHARGE and ult_charge >= MAX_ULT_CHARGE:
		emit_signal("ult_ready")
		# Play ready sound/effect
		if player and player.has_method("add_camera_shake"):
			player.add_camera_shake(0.1)

func on_damage_dealt(damage: int) -> void:
	"""Called when player deals damage"""
	add_charge(CHARGE_PER_DAMAGE_DEALT * damage)

func on_damage_taken(damage: int) -> void:
	"""Called when player takes damage"""
	add_charge(CHARGE_PER_DAMAGE_TAKEN * damage)

func on_kill() -> void:
	"""Called when player gets a kill"""
	add_charge(CHARGE_PER_KILL)

func is_ready() -> bool:
	"""Check if ult is ready to use"""
	return ult_charge >= MAX_ULT_CHARGE and not is_ulting

func try_activate() -> bool:
	"""Try to activate the ult. Returns true if successful."""
	if not is_ready():
		return false

	activate_ult()
	return true

func activate_ult() -> void:
	"""Activate the ultimate attack!"""
	if not player:
		return

	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "ULTIMATE ACTIVATED! POWER OVERWHELMING!", false, player.name.to_int())

	is_ulting = true
	ult_timer = ULT_DASH_DURATION
	hit_players.clear()
	ult_charge = 0.0  # Consume all charge

	# Get dash direction from camera
	var camera_arm: Node3D = player.get_node_or_null("CameraArm")
	var camera: Camera3D = player.get_node_or_null("CameraArm/Camera3D")

	if camera:
		ult_direction = -camera.global_transform.basis.z
		ult_direction.y = 0
		ult_direction = ult_direction.normalized()
	elif camera_arm:
		ult_direction = -camera_arm.global_transform.basis.z
		ult_direction.y = 0
		ult_direction = ult_direction.normalized()
	else:
		ult_direction = Vector3.FORWARD

	# Apply massive initial impulse
	if player is RigidBody3D:
		# Clear current velocity for clean dash
		var vel: Vector3 = player.linear_velocity
		vel.x = 0
		vel.z = 0
		player.linear_velocity = vel

		# Apply powerful dash impulse
		player.apply_central_impulse(ult_direction * ULT_DASH_FORCE)
		player.apply_central_impulse(Vector3.UP * 20.0)  # Slight lift

	# Enable hitbox
	if hitbox:
		hitbox.monitoring = true
		hitbox.global_position = player.global_position

	# Start visual effects
	spawn_activation_explosion()
	start_ult_visuals()

	# Camera shake
	if player.has_method("add_camera_shake"):
		player.add_camera_shake(0.3)

	emit_signal("ult_activated")

func process_ult_dash(delta: float) -> void:
	"""Process the ult dash state"""
	if not player:
		return

	# Keep applying force during dash
	if player is RigidBody3D:
		player.apply_central_force(ult_direction * ULT_DASH_FORCE * 0.3)

	# Update hitbox position
	if hitbox:
		hitbox.global_position = player.global_position

	# Update trail particles
	if trail_particles:
		trail_particles.global_position = player.global_position

	# Update light position
	if ult_light:
		ult_light.global_position = player.global_position

	# Spawn motion lines periodically
	spawn_motion_lines()

func end_ult() -> void:
	"""End the ultimate attack"""
	is_ulting = false
	hit_players.clear()

	# Disable hitbox
	if hitbox:
		hitbox.monitoring = false

	# Stop visual effects
	stop_ult_visuals()

	# Final shockwave
	spawn_end_shockwave()

	DebugLogger.dlog(DebugLogger.Category.ABILITIES, "Ultimate ended", false, player.name.to_int() if player else -1)

func _on_hitbox_body_entered(body: Node3D) -> void:
	"""Handle collision during ult dash"""
	if not is_ulting or not player:
		return

	# Don't hit ourselves
	if body == player:
		return

	# Don't hit the same player twice
	if body in hit_players:
		return

	# Check if it's another player
	if body is RigidBody3D and body.has_method("receive_damage_from"):
		hit_players.append(body)

		var damage: int = ULT_DAMAGE
		var owner_id: int = player.name.to_int()
		var target_id: int = body.get_multiplayer_authority()

		# Deal damage
		if target_id >= 9000 or player.multiplayer.multiplayer_peer == null or target_id == player.multiplayer.get_unique_id():
			body.receive_damage_from(damage, owner_id)
			DebugLogger.dlog(DebugLogger.Category.ABILITIES, "ULT HIT (local): %s | Damage: %d" % [body.name, damage], false, owner_id)
		else:
			body.receive_damage_from.rpc_id(target_id, damage, owner_id)
			DebugLogger.dlog(DebugLogger.Category.ABILITIES, "ULT HIT (RPC): %s | Damage: %d" % [body.name, damage], false, owner_id)

		# Apply massive knockback
		var knockback_dir: Vector3 = (body.global_position - player.global_position).normalized()
		knockback_dir.y = 0.4  # Strong upward component
		body.apply_central_impulse(knockback_dir * ULT_KNOCKBACK)

		# Spawn hit impact effect
		spawn_hit_impact(body.global_position)

		# Camera shake on hit
		if player.has_method("add_camera_shake"):
			player.add_camera_shake(0.15)

func reset() -> void:
	"""Reset ult charge (called on respawn)"""
	ult_charge = 0.0
	is_ulting = false
	ult_timer = 0.0
	hit_players.clear()

	if hitbox:
		hitbox.monitoring = false
	stop_ult_visuals()

func force_full_charge() -> void:
	"""Debug function to instantly charge ult"""
	ult_charge = MAX_ULT_CHARGE
	emit_signal("ult_charge_changed", ult_charge)
	emit_signal("ult_ready")

# ============================================================================
# VISUAL EFFECTS
# ============================================================================

func create_visual_effects() -> void:
	"""Create all the visual effect nodes"""
	# Power aura (shows when ult is ready)
	power_aura = CPUParticles3D.new()
	power_aura.name = "PowerAura"
	add_child(power_aura)

	power_aura.emitting = false
	power_aura.amount = 40
	power_aura.lifetime = 1.0
	power_aura.explosiveness = 0.0
	power_aura.randomness = 0.3
	power_aura.local_coords = false

	var aura_mesh: QuadMesh = QuadMesh.new()
	aura_mesh.size = Vector2(0.4, 0.4)
	power_aura.mesh = aura_mesh

	var aura_material: StandardMaterial3D = StandardMaterial3D.new()
	aura_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aura_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	aura_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aura_material.vertex_color_use_as_albedo = true
	aura_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	power_aura.mesh.material = aura_material

	power_aura.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	power_aura.emission_sphere_radius = 1.5
	power_aura.direction = Vector3.UP
	power_aura.spread = 180.0
	power_aura.gravity = Vector3(0, 3.0, 0)
	power_aura.initial_velocity_min = 2.0
	power_aura.initial_velocity_max = 4.0
	power_aura.scale_amount_min = 1.5
	power_aura.scale_amount_max = 2.5

	var aura_gradient: Gradient = Gradient.new()
	aura_gradient.add_point(0.0, Color(1.0, 0.8, 0.2, 1.0))  # Golden
	aura_gradient.add_point(0.3, Color(1.0, 0.5, 0.1, 0.9))  # Orange
	aura_gradient.add_point(0.6, Color(1.0, 0.2, 0.1, 0.6))  # Red-orange
	aura_gradient.add_point(1.0, Color(0.8, 0.1, 0.1, 0.0))  # Fade
	power_aura.color_ramp = aura_gradient

	# Trail particles (during ult dash)
	trail_particles = CPUParticles3D.new()
	trail_particles.name = "UltTrail"
	add_child(trail_particles)

	trail_particles.emitting = false
	trail_particles.amount = 100
	trail_particles.lifetime = 0.8
	trail_particles.explosiveness = 0.0
	trail_particles.randomness = 0.2
	trail_particles.local_coords = false

	var trail_mesh: QuadMesh = QuadMesh.new()
	trail_mesh.size = Vector2(0.6, 0.6)
	trail_particles.mesh = trail_mesh
	trail_particles.mesh.material = aura_material  # Reuse material

	trail_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail_particles.emission_sphere_radius = 0.8
	trail_particles.direction = Vector3.ZERO
	trail_particles.spread = 180.0
	trail_particles.gravity = Vector3.ZERO
	trail_particles.initial_velocity_min = 1.0
	trail_particles.initial_velocity_max = 3.0
	trail_particles.scale_amount_min = 3.0
	trail_particles.scale_amount_max = 5.0

	var trail_gradient: Gradient = Gradient.new()
	trail_gradient.add_point(0.0, Color(1.0, 1.0, 0.8, 1.0))  # Bright white-yellow
	trail_gradient.add_point(0.2, Color(1.0, 0.8, 0.2, 1.0))  # Golden
	trail_gradient.add_point(0.5, Color(1.0, 0.4, 0.1, 0.8))  # Orange
	trail_gradient.add_point(0.8, Color(0.8, 0.2, 0.1, 0.4))  # Red
	trail_gradient.add_point(1.0, Color(0.3, 0.0, 0.0, 0.0))  # Fade
	trail_particles.color_ramp = trail_gradient

	# Ult light (bright during dash)
	ult_light = OmniLight3D.new()
	ult_light.name = "UltLight"
	add_child(ult_light)
	ult_light.light_color = Color(1.0, 0.7, 0.2)
	ult_light.light_energy = 0.0  # Start off
	ult_light.omni_range = 15.0
	ult_light.omni_attenuation = 1.5

func create_hitbox() -> void:
	"""Create the ult attack hitbox"""
	hitbox = Area3D.new()
	hitbox.name = "UltHitbox"
	hitbox.collision_layer = 0
	hitbox.collision_mask = 2  # Detect players
	add_child(hitbox)

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = ULT_RADIUS
	collision_shape.shape = sphere_shape
	hitbox.add_child(collision_shape)

	hitbox.body_entered.connect(_on_hitbox_body_entered)
	hitbox.monitoring = false

func start_ult_visuals() -> void:
	"""Start the ult dash visual effects"""
	if trail_particles:
		trail_particles.emitting = true
		trail_particles.global_position = player.global_position

	if ult_light:
		ult_light.light_energy = 10.0
		ult_light.global_position = player.global_position

	if power_aura:
		power_aura.emitting = false  # Stop ready aura during dash

func stop_ult_visuals() -> void:
	"""Stop the ult dash visual effects"""
	if trail_particles:
		trail_particles.emitting = false

	if ult_light:
		# Fade out light
		var tween: Tween = get_tree().create_tween()
		tween.tween_property(ult_light, "light_energy", 0.0, 0.3)

	if power_aura:
		power_aura.emitting = false

func spawn_activation_explosion() -> void:
	"""Spawn the explosive activation effect"""
	if not player or not player.get_parent():
		return

	# Create explosion container
	var explosion_container: Node3D = Node3D.new()
	explosion_container.name = "UltActivation"
	player.get_parent().add_child(explosion_container)
	explosion_container.global_position = player.global_position

	# Central flash
	var flash_light: OmniLight3D = OmniLight3D.new()
	flash_light.light_color = Color(1.0, 0.9, 0.5)
	flash_light.light_energy = 20.0
	flash_light.omni_range = 25.0
	explosion_container.add_child(flash_light)

	# Expanding shockwave ring
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 16
	ring.mesh = torus

	var ring_mat: StandardMaterial3D = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.8, 0.2, 0.9)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.6, 0.1)
	ring_mat.emission_energy_multiplier = 3.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat
	explosion_container.add_child(ring)

	# Burst particles
	var burst: CPUParticles3D = CPUParticles3D.new()
	burst.emitting = true
	burst.amount = 80
	burst.lifetime = 0.6
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.randomness = 0.4
	burst.local_coords = false

	var burst_mesh: QuadMesh = QuadMesh.new()
	burst_mesh.size = Vector2(0.5, 0.5)
	burst.mesh = burst_mesh

	var burst_material: StandardMaterial3D = StandardMaterial3D.new()
	burst_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	burst_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	burst_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	burst_material.vertex_color_use_as_albedo = true
	burst_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	burst.mesh.material = burst_material

	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 1.0
	burst.direction = Vector3.ZERO
	burst.spread = 180.0
	burst.gravity = Vector3.ZERO
	burst.initial_velocity_min = 15.0
	burst.initial_velocity_max = 25.0
	burst.scale_amount_min = 3.0
	burst.scale_amount_max = 5.0

	var burst_gradient: Gradient = Gradient.new()
	burst_gradient.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))  # White center
	burst_gradient.add_point(0.2, Color(1.0, 0.9, 0.3, 1.0))  # Yellow
	burst_gradient.add_point(0.5, Color(1.0, 0.5, 0.1, 0.8))  # Orange
	burst_gradient.add_point(0.8, Color(1.0, 0.2, 0.0, 0.4))  # Red
	burst_gradient.add_point(1.0, Color(0.5, 0.0, 0.0, 0.0))  # Fade
	burst.color_ramp = burst_gradient
	explosion_container.add_child(burst)

	# Animate ring expansion and cleanup
	var tween: Tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(15, 15, 15), 0.5)
	tween.tween_property(ring_mat, "albedo_color:a", 0.0, 0.5)
	tween.tween_property(flash_light, "light_energy", 0.0, 0.3)
	tween.set_parallel(false)
	tween.tween_callback(explosion_container.queue_free)

func spawn_motion_lines() -> void:
	"""Spawn speed lines during ult dash"""
	if not player or not player.get_parent():
		return

	# Only spawn occasionally
	if randf() > 0.3:
		return

	var line: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.05, 0.05, randf_range(2.0, 4.0))
	line.mesh = box

	var line_mat: StandardMaterial3D = StandardMaterial3D.new()
	line_mat.albedo_color = Color(1.0, 0.8, 0.3, 0.8)
	line_mat.emission_enabled = true
	line_mat.emission = Color(1.0, 0.6, 0.1)
	line_mat.emission_energy_multiplier = 2.0
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.material_override = line_mat

	player.get_parent().add_child(line)

	# Position behind player with random offset
	var offset: Vector3 = Vector3(
		randf_range(-2, 2),
		randf_range(-1, 2),
		randf_range(-1, 1)
	)
	line.global_position = player.global_position - ult_direction * 2.0 + offset
	line.look_at(line.global_position + ult_direction, Vector3.UP)

	# Animate and cleanup
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(line_mat, "albedo_color:a", 0.0, 0.3)
	tween.tween_callback(line.queue_free)

func spawn_hit_impact(position: Vector3) -> void:
	"""Spawn impact effect when hitting an enemy"""
	if not player or not player.get_parent():
		return

	var impact: CPUParticles3D = CPUParticles3D.new()
	impact.name = "UltHitImpact"
	player.get_parent().add_child(impact)
	impact.global_position = position

	impact.emitting = true
	impact.amount = 40
	impact.lifetime = 0.4
	impact.one_shot = true
	impact.explosiveness = 1.0
	impact.randomness = 0.3
	impact.local_coords = false

	var impact_mesh: QuadMesh = QuadMesh.new()
	impact_mesh.size = Vector2(0.4, 0.4)
	impact.mesh = impact_mesh

	var impact_material: StandardMaterial3D = StandardMaterial3D.new()
	impact_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	impact_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	impact_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	impact_material.vertex_color_use_as_albedo = true
	impact_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	impact.mesh.material = impact_material

	impact.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	impact.emission_sphere_radius = 0.5
	impact.direction = Vector3.ZERO
	impact.spread = 180.0
	impact.gravity = Vector3.ZERO
	impact.initial_velocity_min = 8.0
	impact.initial_velocity_max = 15.0
	impact.scale_amount_min = 2.0
	impact.scale_amount_max = 4.0

	var impact_gradient: Gradient = Gradient.new()
	impact_gradient.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))
	impact_gradient.add_point(0.3, Color(1.0, 0.7, 0.2, 1.0))
	impact_gradient.add_point(0.7, Color(1.0, 0.3, 0.1, 0.5))
	impact_gradient.add_point(1.0, Color(0.5, 0.0, 0.0, 0.0))
	impact.color_ramp = impact_gradient

	get_tree().create_timer(0.5).timeout.connect(impact.queue_free)

func spawn_end_shockwave() -> void:
	"""Spawn final shockwave when ult ends"""
	if not player or not player.get_parent():
		return

	# Create ground shockwave
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.name = "EndShockwave"
	player.get_parent().add_child(ring)
	ring.global_position = player.global_position

	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.6
	ring.mesh = torus

	var ring_mat: StandardMaterial3D = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.6, 0.2, 0.8)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.4, 0.1)
	ring_mat.emission_energy_multiplier = 2.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat

	# Animate expansion
	var tween: Tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(10, 10, 10), 0.4)
	tween.tween_property(ring_mat, "albedo_color:a", 0.0, 0.4)
	tween.set_parallel(false)
	tween.tween_callback(ring.queue_free)

# ============================================================================
# UI
# ============================================================================

func create_ult_meter_ui() -> void:
	"""Create the ult charge meter UI"""
	# Check if we have a player with a valid canvas layer
	# We'll add this to the player's UI later
	pass  # UI will be created when added to player

func update_ult_meter_ui() -> void:
	"""Update the ult meter display"""
	if not ult_meter_ui or not ult_meter_bar:
		return

	# Update bar value
	var charge_percent: float = (ult_charge / MAX_ULT_CHARGE) * 100.0
	ult_meter_bar.value = charge_percent

	# Update style based on charge level
	var style_box_fill: StyleBoxFlat = ult_meter_bar.get_theme_stylebox("fill")
	if style_box_fill:
		if ult_charge >= MAX_ULT_CHARGE:
			# Ready - pulsing gold
			var pulse: float = (sin(ult_ready_flash) + 1.0) / 2.0
			style_box_fill.bg_color = Color(1.0, 0.8 + pulse * 0.2, 0.2, 1.0)
		elif charge_percent >= 75.0:
			style_box_fill.bg_color = Color(1.0, 0.6, 0.1, 0.9)  # Orange
		elif charge_percent >= 50.0:
			style_box_fill.bg_color = Color(1.0, 0.8, 0.2, 0.9)  # Yellow
		elif charge_percent >= 25.0:
			style_box_fill.bg_color = Color(0.8, 0.8, 0.3, 0.9)  # Yellow-green
		else:
			style_box_fill.bg_color = Color(0.5, 0.5, 0.5, 0.9)  # Gray

	# Update label
	if ult_meter_label:
		if ult_charge >= MAX_ULT_CHARGE:
			ult_meter_label.text = "Q - ULTIMATE READY!"
		else:
			ult_meter_label.text = "ULT: %d%%" % int(charge_percent)

func set_ui_references(ui: Control, bar: ProgressBar, label: Label) -> void:
	"""Set UI references for the ult meter"""
	ult_meter_ui = ui
	ult_meter_bar = bar
	ult_meter_label = label
