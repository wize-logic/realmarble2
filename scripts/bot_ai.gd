extends Node

## Bot AI Controller
## Provides AI behavior for bot players with advanced combat tactics

@export var target_player: Node = null
@export var wander_radius: float = 40.0
@export var aggro_range: float = 50.0
@export var attack_range: float = 12.0

var bot: Node = null
var state: String = "WANDER"  # WANDER, CHASE, ATTACK, COLLECT_ABILITY, COLLECT_ORB, RETREAT
var wander_target: Vector3 = Vector3.ZERO
var wander_timer: float = 0.0
var action_timer: float = 0.0
var target_ability: Node = null
var target_orb: Node = null
var ability_check_timer: float = 0.0
var orb_check_timer: float = 0.0

# Advanced AI variables
var strafe_direction: float = 1.0  # 1 for right, -1 for left
var strafe_timer: float = 0.0
var retreat_timer: float = 0.0
var ability_charge_timer: float = 0.0
var is_charging_ability: bool = false
var preferred_combat_distance: float = 15.0  # Distance bot tries to maintain in combat
var reaction_time: float = 0.0  # Small delay to simulate human reaction
var dodge_timer: float = 0.0
var aggression_level: float = 0.7  # 0-1, how aggressive the bot is

# Ability preferences based on situation
const GUN_OPTIMAL_RANGE: float = 20.0
const SWORD_OPTIMAL_RANGE: float = 4.0
const DASH_ATTACK_OPTIMAL_RANGE: float = 8.0
const EXPLOSION_OPTIMAL_RANGE: float = 6.0

func _ready() -> void:
	bot = get_parent()
	wander_target = bot.global_position
	# Randomize aggression for personality variety
	aggression_level = randf_range(0.5, 0.9)
	# Randomize reaction time for more human-like behavior
	reaction_time = randf_range(0.1, 0.3)
	call_deferred("find_target")

func _physics_process(delta: float) -> void:
	if not bot:
		return

	# Update timers
	wander_timer -= delta
	action_timer -= delta
	ability_check_timer -= delta
	orb_check_timer -= delta
	strafe_timer -= delta
	retreat_timer -= delta
	ability_charge_timer -= delta
	dodge_timer -= delta
	reaction_time -= delta

	# Find nearest player
	if not target_player or not is_instance_valid(target_player):
		find_target()

	# Check for abilities periodically
	if ability_check_timer <= 0.0:
		find_nearest_ability()
		ability_check_timer = 1.0  # Check every second

	# Check for orbs periodically
	if orb_check_timer <= 0.0:
		find_nearest_orb()
		orb_check_timer = 0.8  # Check slightly more often

	# State machine
	match state:
		"WANDER":
			do_wander(delta)
		"CHASE":
			do_chase(delta)
		"ATTACK":
			do_attack(delta)
		"RETREAT":
			do_retreat(delta)
		"COLLECT_ABILITY":
			do_collect_ability(delta)
		"COLLECT_ORB":
			do_collect_orb(delta)

	# Check state transitions
	update_state()

func update_state() -> void:
	"""Update AI state based on conditions"""
	# Priority 0: Retreat if low health and enemy nearby
	if bot.health <= 1 and target_player and is_instance_valid(target_player):
		var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)
		if distance_to_target < attack_range * 1.5:
			state = "RETREAT"
			retreat_timer = randf_range(2.0, 4.0)
			return

	# Priority 1: Collect orbs if not max level and one is nearby
	if bot.level < bot.MAX_LEVEL and target_orb and is_instance_valid(target_orb):
		var distance_to_orb: float = bot.global_position.distance_to(target_orb.global_position)
		# Higher priority for orbs when not in immediate combat
		var orb_priority_range: float = 25.0
		if not target_player or not is_instance_valid(target_player):
			orb_priority_range = 50.0
		if distance_to_orb < orb_priority_range:
			state = "COLLECT_ORB"
			return

	# Priority 2: Collect abilities if we don't have one and one is nearby
	if not bot.current_ability and target_ability and is_instance_valid(target_ability):
		var distance_to_ability: float = bot.global_position.distance_to(target_ability.global_position)
		# Abilities are very important, prioritize them highly
		if distance_to_ability < 40.0:
			state = "COLLECT_ABILITY"
			return

	# Priority 3: Combat if player is nearby
	if not target_player or not is_instance_valid(target_player):
		state = "WANDER"
		return

	var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)

	# More nuanced combat states
	if distance_to_target < attack_range * 1.5:
		state = "ATTACK"
	elif distance_to_target < aggro_range:
		state = "CHASE"
	else:
		# Priority 4: Collect items while wandering
		if bot.level < bot.MAX_LEVEL and target_orb and is_instance_valid(target_orb):
			state = "COLLECT_ORB"
		elif not bot.current_ability and target_ability and is_instance_valid(target_ability):
			state = "COLLECT_ABILITY"
		else:
			state = "WANDER"

func do_wander(delta: float) -> void:
	"""Wander around randomly"""
	# Pick new wander target periodically
	if wander_timer <= 0.0:
		var angle: float = randf() * TAU
		var distance: float = randf() * wander_radius
		wander_target = bot.global_position + Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		wander_timer = randf_range(2.0, 5.0)

	# Move towards wander target
	move_towards(wander_target, delta, 0.4)  # Moderate wander speed

	# Occasionally jump - more varied timing
	if action_timer <= 0.0 and randf() < 0.15:
		bot_jump()
		action_timer = randf_range(1.0, 3.0)

func do_chase(delta: float) -> void:
	"""Chase the target player with tactical movement"""
	if not target_player:
		return

	var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)

	# Determine optimal distance based on current ability
	var optimal_distance: float = get_optimal_combat_distance()

	# If we have a weapon and are too far, close in aggressively
	# If we're at good range, maintain distance with strafing
	if distance_to_target > optimal_distance + 5.0:
		# Close the distance
		move_towards(target_player.global_position, delta, 0.9)
	else:
		# Strafe while maintaining distance
		strafe_around_target(delta, optimal_distance)

	# Smart jumping - jump if target is higher or to maintain momentum
	if action_timer <= 0.0:
		if target_player.global_position.y > bot.global_position.y + 1.0:
			bot_jump()
			action_timer = randf_range(0.4, 1.0)
		elif randf() < 0.25:  # Random jumps for unpredictability
			bot_jump()
			action_timer = randf_range(0.5, 1.5)

func do_attack(delta: float) -> void:
	"""Attack the target player with smart ability usage"""
	if not target_player:
		return

	var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)
	var optimal_distance: float = get_optimal_combat_distance()

	# Tactical positioning - maintain optimal range while strafing
	if distance_to_target > optimal_distance + 2.0:
		# Too far, close in
		move_towards(target_player.global_position, delta, 0.7)
	elif distance_to_target < optimal_distance - 2.0:
		# Too close, back up while strafing
		move_away_from(target_player.global_position, delta, 0.5)
	else:
		# Good range, strafe to be harder to hit
		strafe_around_target(delta, optimal_distance)

	# Use ability intelligently
	if bot.current_ability and bot.current_ability.has_method("use"):
		use_ability_smart(distance_to_target)
	# Spin dash as last resort or for mobility
	elif action_timer <= 0.0:
		if randf() < 0.15 and bot.spin_cooldown <= 0.0 and not bot.is_spin_dashing and not bot.is_charging_spin:
			# Use spin dash strategically
			bot.is_charging_spin = true
			bot.spin_charge = randf_range(0.3, bot.max_spin_charge * 0.7)
			get_tree().create_timer(randf_range(0.2, 0.5)).timeout.connect(func(): release_spin_dash())
			action_timer = randf_range(2.0, 3.5)

	# Jump tactically - when target jumps or randomly to dodge
	if action_timer <= 0.0:
		if target_player.global_position.y > bot.global_position.y + 0.5:
			bot_jump()
			action_timer = randf_range(0.3, 0.8)
		elif randf() < 0.2:
			bot_jump()
			action_timer = randf_range(0.4, 1.0)

func do_retreat(delta: float) -> void:
	"""Retreat from danger when low health"""
	if not target_player or retreat_timer <= 0.0:
		state = "WANDER"
		return

	# Move away from target
	move_away_from(target_player.global_position, delta, 1.0)

	# Jump frequently to evade
	if action_timer <= 0.0 and randf() < 0.4:
		bot_jump()
		action_timer = randf_range(0.3, 0.8)

func strafe_around_target(delta: float, preferred_distance: float) -> void:
	"""Strafe around target while maintaining distance"""
	if not target_player:
		return

	# Change strafe direction periodically
	if strafe_timer <= 0.0:
		strafe_direction *= -1
		strafe_timer = randf_range(1.0, 2.5)

	# Calculate strafe direction (perpendicular to target direction)
	var to_target: Vector3 = (target_player.global_position - bot.global_position).normalized()
	to_target.y = 0

	# Perpendicular vector for strafing
	var strafe_vec: Vector3 = Vector3(-to_target.z, 0, to_target.x) * strafe_direction

	# Combine forward/backward movement with strafing
	var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)
	var distance_adjustment: Vector3 = Vector3.ZERO

	if distance_to_target > preferred_distance:
		distance_adjustment = to_target * 0.4
	elif distance_to_target < preferred_distance - 2.0:
		distance_adjustment = -to_target * 0.4

	# Apply combined movement
	var movement: Vector3 = (strafe_vec * 0.6 + distance_adjustment).normalized()
	if movement.length() > 0.1:
		var force: float = bot.current_roll_force * 0.8
		bot.apply_central_force(movement * force)

func move_away_from(target_pos: Vector3, delta: float, speed_mult: float = 1.0) -> void:
	"""Move the bot away from a target position"""
	if not bot:
		return

	var direction: Vector3 = (bot.global_position - target_pos).normalized()
	direction.y = 0  # Keep horizontal

	if direction.length() > 0.1:
		var force: float = bot.current_roll_force * speed_mult
		bot.apply_central_force(direction * force)

func get_optimal_combat_distance() -> float:
	"""Get the optimal combat distance based on current ability"""
	if not bot.current_ability:
		return DASH_ATTACK_OPTIMAL_RANGE  # Default to medium range

	var ability_name: String = bot.current_ability.ability_name if "ability_name" in bot.current_ability else ""

	match ability_name:
		"Gun":
			return GUN_OPTIMAL_RANGE
		"Sword":
			return SWORD_OPTIMAL_RANGE
		"Dash Attack":
			return DASH_ATTACK_OPTIMAL_RANGE
		"Explosion":
			return EXPLOSION_OPTIMAL_RANGE
		_:
			return preferred_combat_distance

func use_ability_smart(distance_to_target: float) -> void:
	"""Use ability with smart timing and charging"""
	if not bot.current_ability or not bot.current_ability.is_ready():
		is_charging_ability = false
		return

	var ability_name: String = bot.current_ability.ability_name if "ability_name" in bot.current_ability else ""
	var should_use: bool = false
	var should_charge: bool = false

	# Determine if we should use ability based on distance and ability type
	match ability_name:
		"Gun":
			# Use gun at medium to long range
			if distance_to_target > 8.0 and distance_to_target < 40.0:
				should_use = true
				should_charge = distance_to_target > 15.0 and randf() < 0.6
		"Sword":
			# Use sword at close range
			if distance_to_target < 5.0:
				should_use = true
				should_charge = randf() < 0.4
		"Dash Attack":
			# Use dash attack to close distance or escape
			if distance_to_target > 5.0 and distance_to_target < 15.0:
				should_use = true
				should_charge = distance_to_target > 10.0 and randf() < 0.5
		"Explosion":
			# Use explosion at close range or when cornered
			if distance_to_target < 8.0:
				should_use = true
				should_charge = distance_to_target < 5.0 and randf() < 0.7
		_:
			# Default: use when in reasonable range
			if distance_to_target < 20.0:
				should_use = randf() < 0.3

	# Charging logic
	if should_use and should_charge and not is_charging_ability:
		# Start charging
		if bot.current_ability.has_method("start_charging"):
			is_charging_ability = true
			ability_charge_timer = randf_range(0.8, 1.8)  # Charge for 0.8-1.8 seconds
			bot.current_ability.start_charging()

	# Release charged ability or use instantly
	if is_charging_ability and ability_charge_timer <= 0.0:
		# Release charge
		is_charging_ability = false
		bot.current_ability.use()
		action_timer = randf_range(0.5, 1.5)
	elif should_use and not should_charge and not is_charging_ability:
		# Use immediately without charging
		bot.current_ability.use()
		action_timer = randf_range(0.8, 2.0)

func move_towards(target_pos: Vector3, delta: float, speed_mult: float = 1.0) -> void:
	"""Move the bot towards a target position"""
	if not bot:
		return

	var direction: Vector3 = (target_pos - bot.global_position).normalized()
	direction.y = 0  # Keep horizontal

	if direction.length() > 0.1:
		# Simulate input by applying force
		var force: float = bot.current_roll_force * speed_mult
		bot.apply_central_force(direction * force)

func bot_jump() -> void:
	"""Make the bot jump"""
	if not bot:
		return

	if bot.jump_count < bot.max_jumps:
		var jump_strength: float = bot.current_jump_impulse
		if bot.jump_count == 1:
			jump_strength *= 0.85

		var vel: Vector3 = bot.linear_velocity
		vel.y = 0
		bot.linear_velocity = vel
		bot.apply_central_impulse(Vector3.UP * jump_strength)
		bot.jump_count += 1

func release_spin_dash() -> void:
	"""Release spin dash"""
	if bot and bot.is_charging_spin:
		bot.is_charging_spin = false
		if bot.has_method("execute_spin_dash"):
			bot.execute_spin_dash()

func find_target() -> void:
	"""Find the nearest player to target"""
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	var closest_player: Node = null
	var closest_distance: float = INF

	for player in players:
		if player == bot:  # Don't target self
			continue
		if not is_instance_valid(player):
			continue

		var distance: float = bot.global_position.distance_to(player.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_player = player

	target_player = closest_player

func find_nearest_ability() -> void:
	"""Find the nearest ability pickup"""
	var abilities: Array[Node] = get_tree().get_nodes_in_group("ability_pickups")
	var closest_ability: Node = null
	var closest_distance: float = INF

	for ability in abilities:
		if not is_instance_valid(ability):
			continue

		var distance: float = bot.global_position.distance_to(ability.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_ability = ability

	target_ability = closest_ability

func do_collect_ability(delta: float) -> void:
	"""Move towards and collect an ability"""
	if not target_ability or not is_instance_valid(target_ability):
		target_ability = null
		state = "WANDER"
		return

	# Move towards ability with urgency
	move_towards(target_ability.global_position, delta, 1.0)

	# Jump if ability is higher or obstacles in the way
	if action_timer <= 0.0:
		if target_ability.global_position.y > bot.global_position.y + 1.0 or randf() < 0.3:
			bot_jump()
			action_timer = randf_range(0.4, 0.9)

	# Check if we're close enough (pickup will happen automatically via Area3D)
	var distance: float = bot.global_position.distance_to(target_ability.global_position)
	if distance < 2.0:
		# Close enough, should collect automatically
		# Wait a moment then look for new targets
		await get_tree().create_timer(0.5).timeout
		target_ability = null

func find_nearest_orb() -> void:
	"""Find the nearest collectible orb"""
	var orbs: Array[Node] = get_tree().get_nodes_in_group("orbs")
	var closest_orb: Node = null
	var closest_distance: float = INF

	for orb in orbs:
		if not is_instance_valid(orb):
			continue
		# Skip collected orbs
		if "is_collected" in orb and orb.is_collected:
			continue

		var distance: float = bot.global_position.distance_to(orb.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_orb = orb

	target_orb = closest_orb

func do_collect_orb(delta: float) -> void:
	"""Move towards and collect an orb"""
	if not target_orb or not is_instance_valid(target_orb):
		target_orb = null
		state = "WANDER"
		return

	# Check if orb was collected by someone else
	if "is_collected" in target_orb and target_orb.is_collected:
		target_orb = null
		state = "WANDER"
		return

	# Move towards orb with high priority
	move_towards(target_orb.global_position, delta, 1.0)

	# Jump if orb is higher
	if action_timer <= 0.0:
		if target_orb.global_position.y > bot.global_position.y + 1.0 or randf() < 0.25:
			bot_jump()
			action_timer = randf_range(0.4, 0.9)

	# Check if we're close enough (pickup will happen automatically via Area3D)
	var distance: float = bot.global_position.distance_to(target_orb.global_position)
	if distance < 2.0:
		# Close enough, should collect automatically
		# Wait a moment then look for new targets
		await get_tree().create_timer(0.3).timeout
		target_orb = null
