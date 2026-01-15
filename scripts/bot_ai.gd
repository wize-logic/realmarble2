extends Node

## Bot AI Controller
## Provides AI behavior for bot players with advanced combat tactics

@export var target_player: Node = null
@export var wander_radius: float = 30.0
@export var aggro_range: float = 40.0
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

# Obstacle detection variables
var stuck_timer: float = 0.0
var last_position: Vector3 = Vector3.ZERO
var stuck_check_interval: float = 0.2  # Check more frequently for faster response
var is_stuck: bool = false
var unstuck_timer: float = 0.0
var obstacle_avoid_direction: Vector3 = Vector3.ZERO
var obstacle_jump_timer: float = 0.0  # Separate timer for obstacle jumps
var consecutive_stuck_checks: int = 0  # Track how many times we've been stuck in a row

# Target timeout variables - for abandoning unreachable targets
var target_stuck_timer: float = 0.0
var target_stuck_position: Vector3 = Vector3.ZERO
const TARGET_STUCK_TIMEOUT: float = 5.0  # Abandon target after 5 seconds of no progress

# Ability preferences based on situation
const GUN_OPTIMAL_RANGE: float = 20.0
const SWORD_OPTIMAL_RANGE: float = 4.0
const DASH_ATTACK_OPTIMAL_RANGE: float = 8.0
const EXPLOSION_OPTIMAL_RANGE: float = 6.0

func _ready() -> void:
	bot = get_parent()
	if not bot:
		print("ERROR: BotAI could not find parent bot!")
		return

	print("BotAI ready for bot: ", bot.name)
	wander_target = bot.global_position
	last_position = bot.global_position
	target_stuck_position = bot.global_position
	# Randomize aggression for personality variety
	aggression_level = randf_range(0.5, 0.9)
	# Randomize reaction time for more human-like behavior
	reaction_time = randf_range(0.1, 0.3)
	print("BotAI initialized: aggression=%.2f, reaction_time=%.2f" % [aggression_level, reaction_time])
	call_deferred("find_target")

func _physics_process(delta: float) -> void:
	if not bot:
		print("ERROR: BotAI has no bot parent in _physics_process!")
		return

	if not is_instance_valid(bot):
		print("ERROR: BotAI bot parent is not valid!")
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
	stuck_timer += delta
	unstuck_timer -= delta
	obstacle_jump_timer -= delta

	# Check if bot is stuck on obstacles
	if stuck_timer >= stuck_check_interval:
		check_if_stuck()
		stuck_timer = 0.0

	# Handle unstuck behavior
	if is_stuck and unstuck_timer > 0.0:
		handle_unstuck_movement(delta)
		return  # Skip normal AI while unstucking

	# Check if bot is stuck trying to reach a target (ability/orb)
	check_target_timeout(delta)

	# Find nearest player - check more frequently and aggressively
	if not target_player or not is_instance_valid(target_player):
		find_target()
	# Re-check target periodically even if we have one (in case a closer target appears)
	elif action_timer <= 0.0 and randf() < 0.3:
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
	# Priority 0: Retreat if low health and enemy nearby (can retreat without ability)
	if bot.health <= 1 and target_player and is_instance_valid(target_player):
		var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)
		if distance_to_target < attack_range * 1.5:
			state = "RETREAT"
			retreat_timer = randf_range(2.0, 4.0)
			return

	# Check if we have a valid target player for combat decisions
	var has_combat_target: bool = target_player and is_instance_valid(target_player)
	var distance_to_target: float = INF
	if has_combat_target:
		distance_to_target = bot.global_position.distance_to(target_player.global_position)

	# Priority 1: CRITICAL - Get an ability if we don't have one (can't fight without it!)
	if not bot.current_ability and target_ability and is_instance_valid(target_ability):
		var distance_to_ability: float = bot.global_position.distance_to(target_ability.global_position)
		# Abilities are absolutely critical - prioritize above almost everything
		if distance_to_ability < 60.0:  # Increased range when we have no ability
			state = "COLLECT_ABILITY"
			return

	# Priority 2: Combat if we HAVE an ability and enemy is in immediate attack range
	if bot.current_ability and has_combat_target and distance_to_target < attack_range * 1.5:
		state = "ATTACK"
		return

	# Priority 3: Collect orbs if not max level and one is nearby
	if bot.level < bot.MAX_LEVEL and target_orb and is_instance_valid(target_orb):
		var distance_to_orb: float = bot.global_position.distance_to(target_orb.global_position)
		# Collect orbs more aggressively - bots need to level up
		var orb_priority_range: float = 35.0
		if not has_combat_target or distance_to_target > aggro_range * 0.5:
			orb_priority_range = 50.0
		# Don't collect orbs if enemy is actively attacking us (very close) and we have an ability
		if distance_to_orb < orb_priority_range and (not has_combat_target or distance_to_target > attack_range * 1.8 or not bot.current_ability):
			state = "COLLECT_ORB"
			return

	# Priority 4: Combat if we HAVE an ability and player is in aggro range
	if bot.current_ability and has_combat_target:
		if distance_to_target < attack_range * 1.5:
			state = "ATTACK"
		elif distance_to_target < aggro_range:
			state = "CHASE"
		else:
			# Player is far, consider collecting items or wandering
			if bot.level < bot.MAX_LEVEL and target_orb and is_instance_valid(target_orb):
				var distance_to_orb: float = bot.global_position.distance_to(target_orb.global_position)
				if distance_to_orb < 50.0:
					state = "COLLECT_ORB"
					return
			state = "WANDER"
	else:
		# No ability or no combat target, prioritize getting ability or collecting items
		if not bot.current_ability and target_ability and is_instance_valid(target_ability):
			var distance_to_ability: float = bot.global_position.distance_to(target_ability.global_position)
			if distance_to_ability < 60.0:
				state = "COLLECT_ABILITY"
				return
		if bot.level < bot.MAX_LEVEL and target_orb and is_instance_valid(target_orb):
			var distance_to_orb: float = bot.global_position.distance_to(target_orb.global_position)
			if distance_to_orb < 50.0:
				state = "COLLECT_ORB"
				return
		# Find targets while wandering
		find_target()
		state = "WANDER"

func do_wander(delta: float) -> void:
	"""Wander around randomly while actively searching for targets"""
	# Pick new wander target periodically
	if wander_timer <= 0.0:
		var angle: float = randf() * TAU
		var distance: float = randf() * wander_radius
		wander_target = bot.global_position + Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		wander_timer = randf_range(2.0, 5.0)
		# Actively search for targets when picking new wander location
		find_target()

	# Move towards wander target with moderate speed
	move_towards(wander_target, delta, 0.5)  # Slightly increased wander speed

	# Occasionally jump - more varied timing
	if action_timer <= 0.0 and randf() < 0.15:
		bot_jump()
		action_timer = randf_range(1.0, 3.0)

func do_chase(delta: float) -> void:
	"""Chase the target player with tactical movement"""
	if not target_player:
		return

	var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)
	var height_diff: float = target_player.global_position.y - bot.global_position.y

	# CRITICAL: Make bot face the target for aiming
	look_at_target(target_player.global_position)

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

	# Use abilities while chasing if in range
	if bot.current_ability and bot.current_ability.has_method("use"):
		use_ability_smart(distance_to_target)

	# Smart jumping - more aggressive when target is on higher ground
	if action_timer <= 0.0:
		if height_diff > 1.0:
			# Target is significantly higher - jump frequently to reach them
			bot_jump()
			action_timer = randf_range(0.3, 0.6)
		elif height_diff > 0.5 and randf() < 0.6:
			# Target is slightly higher - jump often
			bot_jump()
			action_timer = randf_range(0.4, 0.8)
		elif randf() < 0.25:  # Random jumps for unpredictability
			bot_jump()
			action_timer = randf_range(0.5, 1.5)

func do_attack(delta: float) -> void:
	"""Attack the target player with smart ability usage"""
	if not target_player:
		return

	var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)
	var height_diff: float = target_player.global_position.y - bot.global_position.y
	var optimal_distance: float = get_optimal_combat_distance()

	# CRITICAL: Make bot face the target for aiming
	look_at_target(target_player.global_position)

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

	# Jump tactically - more aggressive when target is higher
	if action_timer <= 0.0:
		if height_diff > 0.8:
			# Target is higher - jump to reach them
			bot_jump()
			action_timer = randf_range(0.3, 0.7)
		elif height_diff > 0.3 and randf() < 0.5:
			# Target is slightly higher - jump often
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
			# Use gun at almost any range - guns are versatile
			if distance_to_target > 3.0 and distance_to_target < 50.0:
				should_use = true
				should_charge = distance_to_target > 12.0 and randf() < 0.5
		"Sword":
			# Use sword at close to medium range
			if distance_to_target < 8.0:
				should_use = true
				should_charge = distance_to_target > 4.0 and randf() < 0.3
		"Dash Attack":
			# Use dash attack more liberally - it's good for mobility
			if distance_to_target > 3.0 and distance_to_target < 20.0:
				should_use = true
				should_charge = distance_to_target > 8.0 and randf() < 0.4
		"Explosion":
			# Use explosion at close to medium range
			if distance_to_target < 12.0:
				should_use = true
				should_charge = distance_to_target < 6.0 and randf() < 0.5
		_:
			# Default: use when in reasonable range
			if distance_to_target < 25.0:
				should_use = randf() < 0.5

	# Charging logic
	if should_use and should_charge and not is_charging_ability:
		# Start charging
		if bot.current_ability.has_method("start_charging"):
			is_charging_ability = true
			ability_charge_timer = randf_range(0.5, 1.2)  # Shorter charge time for faster attacks
			bot.current_ability.start_charging()

	# Release charged ability or use instantly
	if is_charging_ability and ability_charge_timer <= 0.0:
		# Release charge
		is_charging_ability = false
		bot.current_ability.use()
		action_timer = randf_range(0.3, 1.0)
	elif should_use and not should_charge and not is_charging_ability:
		# Use immediately without charging
		bot.current_ability.use()
		action_timer = randf_range(0.5, 1.5)

func move_towards(target_pos: Vector3, delta: float, speed_mult: float = 1.0) -> void:
	"""Move the bot towards a target position with obstacle detection"""
	if not bot:
		return

	var direction: Vector3 = (target_pos - bot.global_position).normalized()
	direction.y = 0  # Keep horizontal

	# Check if target is significantly above us (platform or higher ground)
	var height_diff: float = target_pos.y - bot.global_position.y

	if direction.length() > 0.1:
		# Check for dangerous edges first - HIGHEST PRIORITY - EXTRA CAREFUL
		if check_for_edge(direction, 3.5):
			# There's an edge ahead - find a safe direction or stop
			var safe_direction: Vector3 = find_safe_direction_from_edge(direction)
			if safe_direction != Vector3.ZERO:
				direction = safe_direction
				speed_mult *= 0.6  # Slow down when avoiding edges
			else:
				# No safe direction, STOP COMPLETELY and move backwards
				var backwards: Vector3 = -direction
				bot.apply_central_force(backwards * bot.current_roll_force * 0.8)
				print("Bot %s: Edge detected, moving backwards!" % bot.name)
				return

		# Check for obstacles in the path with improved detection
		var obstacle_info: Dictionary = check_obstacle_in_direction(direction)

		if obstacle_info.has_obstacle:
			# Handle slopes and platforms - try to jump onto them
			if obstacle_info.is_slope or obstacle_info.is_platform:
				# Jump onto slopes and platforms proactively - reduced cooldown
				if obstacle_jump_timer <= 0.0:
					bot_jump()
					obstacle_jump_timer = 0.25  # Very short cooldown for slopes/platforms
					# Continue moving forward while jumping to get on the slope with extra force
					var force: float = bot.current_roll_force * speed_mult * 1.3
					bot.apply_central_force(direction * force)
					return
				else:
					# Even if on cooldown, keep moving toward the slope
					var force: float = bot.current_roll_force * speed_mult
					bot.apply_central_force(direction * force)
					return

			# For walls and other obstacles - MOVE OPPOSITE DIRECTION
			# This prevents getting stuck trying to navigate around
			if "is_wall" in obstacle_info and obstacle_info.is_wall:
				# Wall detected - move in opposite direction
				print("Bot %s: Wall detected, moving backwards" % bot.name)
				direction = -direction  # Complete opposite
				speed_mult *= 0.5  # Slow down while backing up

				# Try to jump if wall is low
				if obstacle_info.can_jump and obstacle_jump_timer <= 0.0:
					bot_jump()
					obstacle_jump_timer = 0.5
			else:
				# Other obstacle - try jumping first, then go opposite if can't jump
				if obstacle_info.can_jump and obstacle_jump_timer <= 0.0:
					bot_jump()
					obstacle_jump_timer = 0.4
				else:
					# Can't jump - move in opposite direction
					direction = -direction
					speed_mult *= 0.5

		# If target is above us and no obstacle blocking, jump to gain height
		elif height_diff > 1.0 and obstacle_jump_timer <= 0.0 and randf() < 0.5:
			bot_jump()
			obstacle_jump_timer = 0.5

		# Apply movement force
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

func look_at_target(target_position: Vector3) -> void:
	"""Rotate bot to face target for aiming"""
	if not bot:
		return

	# Calculate direction to target (only horizontal rotation)
	var target_dir: Vector3 = target_position - bot.global_position
	target_dir.y = 0  # Keep rotation horizontal only

	if target_dir.length() > 0.1:
		# Calculate the angle to face the target
		var desired_rotation: float = atan2(target_dir.x, target_dir.z)

		# Smoothly rotate toward target (instant rotation for now, can be smoothed later)
		bot.rotation.y = desired_rotation

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

	var height_diff: float = target_ability.global_position.y - bot.global_position.y

	# Move towards ability with urgency
	move_towards(target_ability.global_position, delta, 1.0)

	# Jump more aggressively if ability is on higher ground
	if action_timer <= 0.0:
		if height_diff > 1.0:
			# Ability is significantly higher - jump frequently
			bot_jump()
			action_timer = randf_range(0.3, 0.5)
		elif height_diff > 0.5 or randf() < 0.4:
			# Ability is slightly higher or random jump
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

	var height_diff: float = target_orb.global_position.y - bot.global_position.y

	# Move towards orb with high priority
	move_towards(target_orb.global_position, delta, 1.0)

	# Jump more aggressively if orb is on higher ground
	if action_timer <= 0.0:
		if height_diff > 1.0:
			# Orb is significantly higher - jump frequently
			bot_jump()
			action_timer = randf_range(0.3, 0.5)
		elif height_diff > 0.5 or randf() < 0.35:
			# Orb is slightly higher or random jump
			bot_jump()
			action_timer = randf_range(0.4, 0.9)

	# Check if we're close enough (pickup will happen automatically via Area3D)
	var distance: float = bot.global_position.distance_to(target_orb.global_position)
	if distance < 2.0:
		# Close enough, should collect automatically
		# Wait a moment then look for new targets
		await get_tree().create_timer(0.3).timeout
		target_orb = null

## ============================================================================
## OBSTACLE DETECTION AND AVOIDANCE FUNCTIONS
## ============================================================================

func check_for_edge(direction: Vector3, check_distance: float = 3.0) -> bool:
	"""
	Check if there's a dangerous edge/drop-off in the given direction
	Returns true if there's an edge that the bot should avoid
	"""
	if not bot:
		return false

	var space_state: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state

	# First, check current ground level for reference
	var current_ground_check: Vector3 = bot.global_position + Vector3.UP * 0.5
	var current_ground_end: Vector3 = bot.global_position + Vector3.DOWN * 3.0

	var current_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(current_ground_check, current_ground_end)
	current_query.exclude = [bot]
	current_query.collision_mask = 1

	var current_result: Dictionary = space_state.intersect_ray(current_query)

	# If bot isn't even on ground, don't do edge checks (prevents false positives)
	if not current_result:
		return false

	var current_ground_y: float = current_result.position.y

	# Now check ahead for edges
	var forward_point: Vector3 = bot.global_position + direction.normalized() * check_distance
	var ray_start: Vector3 = forward_point + Vector3.UP * 0.5
	var ray_end: Vector3 = forward_point + Vector3.DOWN * 10.0

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [bot]
	query.collision_mask = 1

	var result: Dictionary = space_state.intersect_ray(query)

	# If no ground found ahead, there's definitely an edge
	if not result:
		return true

	# Compare ground ahead to current ground level
	var ahead_ground_y: float = result.position.y
	var ground_drop: float = current_ground_y - ahead_ground_y

	# Only consider it an edge if the drop is significant (4 units or more)
	# This prevents false positives on normal slopes
	return ground_drop > 4.0

func find_safe_direction_from_edge(dangerous_direction: Vector3) -> Vector3:
	"""
	Find a safe direction to move when the desired direction leads to an edge
	Tries angles perpendicular and away from the edge
	"""
	if not bot:
		return Vector3.ZERO

	# Try angles moving away from the edge
	var angles_to_try: Array = [90, -90, 120, -120, 150, -150, 180]

	for angle_deg in angles_to_try:
		var test_direction: Vector3 = dangerous_direction.rotated(Vector3.UP, deg_to_rad(angle_deg))
		# Check if this direction is safe from edges
		if not check_for_edge(test_direction, 2.0):
			# Also check it doesn't lead to obstacles
			var obstacle_check: Dictionary = check_obstacle_in_direction(test_direction, 2.0)
			if not obstacle_check.has_obstacle or obstacle_check.can_jump:
				return test_direction

	# No safe direction found
	return Vector3.ZERO

func check_obstacle_in_direction(direction: Vector3, check_distance: float = 3.0) -> Dictionary:
	"""
	Check if there's an obstacle in the given direction using multiple raycasts
	Returns a dictionary with: {has_obstacle: bool, can_jump: bool, is_slope: bool, hit_point: Vector3}
	"""
	if not bot:
		return {"has_obstacle": false, "can_jump": false, "is_slope": false, "hit_point": Vector3.ZERO}

	var space_state: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state

	# Use multiple raycasts at different heights to better detect slopes and walls
	var check_heights: Array = [0.1, 0.3, 0.6, 1.0, 1.5, 2.0]  # More comprehensive height checks
	var obstacle_detected: bool = false
	var closest_hit: Vector3 = Vector3.ZERO
	var lowest_obstacle_height: float = INF
	var highest_obstacle_height: float = -INF
	var hits_at_height: Array = []
	var hit_count: int = 0

	for height in check_heights:
		var start_pos: Vector3 = bot.global_position + Vector3.UP * height
		var end_pos: Vector3 = start_pos + direction * check_distance

		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
		query.exclude = [bot]
		query.collision_mask = 1  # Only check world geometry (layer 1)

		var result: Dictionary = space_state.intersect_ray(query)

		if result:
			obstacle_detected = true
			hit_count += 1
			var hit_point: Vector3 = result.position
			var obstacle_height: float = hit_point.y - bot.global_position.y

			hits_at_height.append({"height": height, "obstacle_height": obstacle_height, "hit_point": hit_point})

			if obstacle_height < lowest_obstacle_height:
				lowest_obstacle_height = obstacle_height
				closest_hit = hit_point
			if obstacle_height > highest_obstacle_height:
				highest_obstacle_height = obstacle_height

	if obstacle_detected:
		# Detect if this is a slope by checking if higher raycasts hit at higher Y positions
		var is_slope: bool = false
		var is_platform: bool = false
		var is_wall: bool = false

		# If we hit at multiple heights and the obstacle gets higher, it's likely a slope or platform
		if hits_at_height.size() >= 2:
			var height_diff: float = highest_obstacle_height - lowest_obstacle_height
			# If obstacle height varies significantly across our check heights, it's a slope
			if height_diff > 0.3:
				is_slope = true
			# If the lowest hit is above ground level, it's a platform edge
			if lowest_obstacle_height > 0.2 and lowest_obstacle_height < 2.5:
				is_platform = true
			# If we hit at all heights, it's likely a vertical wall
			if hit_count >= check_heights.size() - 1:
				is_wall = true

		# Check if we can jump onto this obstacle
		var distance_to_obstacle: float = bot.global_position.distance_to(closest_hit)

		# More aggressive jump detection for slopes and platforms
		var can_jump: bool = false
		if is_slope or is_platform:
			# For slopes/platforms, be more aggressive about jumping
			can_jump = lowest_obstacle_height < 4.0 and lowest_obstacle_height > -0.5 and distance_to_obstacle > 0.5
		elif is_wall:
			# For walls, only jump if they're low enough
			can_jump = lowest_obstacle_height < 2.0 and lowest_obstacle_height > -0.5 and distance_to_obstacle > 0.8
		else:
			# For other obstacles, use moderate jump detection
			can_jump = lowest_obstacle_height < 2.5 and lowest_obstacle_height > -0.5 and distance_to_obstacle > 0.6

		return {
			"has_obstacle": true,
			"can_jump": can_jump,
			"is_slope": is_slope,
			"is_platform": is_platform,
			"is_wall": is_wall,
			"hit_point": closest_hit,
			"obstacle_height": lowest_obstacle_height,
			"distance_to_obstacle": distance_to_obstacle
		}

	return {"has_obstacle": false, "can_jump": false, "is_slope": false, "is_platform": false, "is_wall": false, "hit_point": Vector3.ZERO}

func find_clear_direction(desired_direction: Vector3) -> Vector3:
	"""
	Find a clear direction to move when the desired path is blocked
	Tries multiple angles to find the best path around obstacles
	"""
	if not bot:
		return Vector3.ZERO

	# Try angles in order of preference (smaller angles first to stay closer to target)
	var angles_to_try: Array = [30, -30, 60, -60, 90, -90, 120, -120, 150, -150]

	for angle_deg in angles_to_try:
		var test_direction: Vector3 = desired_direction.rotated(Vector3.UP, deg_to_rad(angle_deg))
		var check_dist: float = 2.0  # Shorter check distance for more immediate avoidance
		var check: Dictionary = check_obstacle_in_direction(test_direction, check_dist)

		if not check.has_obstacle:
			return test_direction

	# If no clear path found, try backing up slightly at an angle
	var retreat_angle: float = deg_to_rad(randf_range(-45, 45))
	return -desired_direction.rotated(Vector3.UP, retreat_angle) * 0.6

func check_target_timeout(delta: float) -> void:
	"""Check if bot is stuck trying to reach a collectible target for too long"""
	if not bot:
		return

	# Only check when trying to collect abilities or orbs
	if state in ["COLLECT_ABILITY", "COLLECT_ORB"]:
		var current_pos: Vector3 = bot.global_position
		var distance_moved: float = current_pos.distance_to(target_stuck_position)

		# If bot hasn't moved much, increment timer
		if distance_moved < 0.5:
			target_stuck_timer += delta

			# After timeout, abandon the target
			if target_stuck_timer >= TARGET_STUCK_TIMEOUT:
				print("Bot %s abandoning unreachable target after %0.1f seconds" % [bot.name, target_stuck_timer])

				# Clear the current target
				if state == "COLLECT_ABILITY":
					target_ability = null
				elif state == "COLLECT_ORB":
					target_orb = null

				# Force state update to find new target
				target_stuck_timer = 0.0
				state = "WANDER"
				find_target()  # Look for combat targets
		else:
			# Bot is making progress, reset timer
			target_stuck_timer = 0.0
			target_stuck_position = current_pos
	else:
		# Not collecting, reset timer
		target_stuck_timer = 0.0
		target_stuck_position = bot.global_position

func check_if_stuck() -> void:
	"""Check if the bot hasn't moved much and might be stuck on an obstacle"""
	if not bot:
		return

	var current_pos: Vector3 = bot.global_position
	var distance_moved: float = current_pos.distance_to(last_position)

	# More sensitive stuck detection: check if bot is trying to move but not making progress
	var is_trying_to_move: bool = state in ["CHASE", "ATTACK", "COLLECT_ABILITY", "COLLECT_ORB"]

	# Detect stuck based on movement - lowered threshold for faster detection
	if distance_moved < 0.15 and is_trying_to_move:
		consecutive_stuck_checks += 1

		# Trigger stuck state after 2 consecutive failed movement checks
		if consecutive_stuck_checks >= 2 and not is_stuck:
			is_stuck = true
			unstuck_timer = randf_range(1.0, 2.0)

			# PRIORITY: Move in OPPOSITE direction of current facing
			# This is the simplest and most effective escape strategy
			var opposite_dir: Vector3 = Vector3(-sin(bot.rotation.y), 0, -cos(bot.rotation.y))

			# Check if stuck under terrain/slope
			if is_stuck_under_terrain():
				# Stuck under slope - move perpendicular AND backwards
				var random_side: float = 1.0 if randf() > 0.5 else -1.0
				var perpendicular: Vector3 = Vector3(-sin(bot.rotation.y), 0, cos(bot.rotation.y)) * random_side
				# Mix perpendicular with backwards movement
				obstacle_avoid_direction = (opposite_dir + perpendicular).normalized()
				print("Bot %s is stuck UNDER terrain! Moving backwards and sideways" % bot.name)
			else:
				# Normal stuck - just go BACKWARDS (opposite direction)
				obstacle_avoid_direction = opposite_dir
				print("Bot %s is stuck! Moving in OPPOSITE direction (moved only %0.2f units)" % [bot.name, distance_moved])
	else:
		# Reset stuck counter if we've moved well
		if distance_moved > 0.3:
			consecutive_stuck_checks = 0
			is_stuck = false

	last_position = current_pos

func is_stuck_under_terrain() -> bool:
	"""Check if bot is stuck underneath terrain/slope"""
	if not bot:
		return false

	var space_state: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state

	# Check if there's terrain directly above the bot (within 2 units)
	var ray_start: Vector3 = bot.global_position + Vector3.UP * 0.5
	var ray_end: Vector3 = bot.global_position + Vector3.UP * 2.5

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [bot]
	query.collision_mask = 1  # Only check world geometry

	var result: Dictionary = space_state.intersect_ray(query)

	# If we hit something above us, we're stuck under terrain
	return result.size() > 0

func handle_unstuck_movement(delta: float) -> void:
	"""Handle movement when bot is stuck - try to get unstuck"""
	if not bot:
		return

	# Check if we're stuck under terrain
	var under_terrain: bool = is_stuck_under_terrain()

	# More aggressive unstuck behavior - try multiple things at once

	# Always try to move in the avoid direction with extra force
	var force: float = bot.current_roll_force * 1.5  # Increased force to break free
	bot.apply_central_force(obstacle_avoid_direction * force)

	# Jump very frequently to get over obstacles - VERY aggressive if under terrain
	var jump_chance: float = 0.7 if under_terrain else 0.5
	if bot.jump_count < bot.max_jumps and randf() < jump_chance:
		bot_jump()

	# Use spin dash more often to break free
	if unstuck_timer > 0.3 and not bot.is_charging_spin and bot.spin_cooldown <= 0.0 and randf() < 0.25:
		bot.is_charging_spin = true
		bot.spin_charge = bot.max_spin_charge * 0.7
		get_tree().create_timer(0.25).timeout.connect(func(): release_spin_dash())

	# Change direction more frequently while stuck (every 0.3 seconds)
	var time_slot: int = int(unstuck_timer * 10)
	if time_slot % 3 == 0 and time_slot != int((unstuck_timer + delta) * 10) % 3:
		# Find a completely different direction
		var new_angle: float = randf() * TAU
		var new_avoid_dir: Vector3 = Vector3(cos(new_angle), 0, sin(new_angle))
		var clear_dir: Vector3 = find_clear_direction(new_avoid_dir)
		if clear_dir != Vector3.ZERO:
			obstacle_avoid_direction = clear_dir
			print("Bot %s changing unstuck direction" % bot.name)

	# Also try moving backward occasionally
	if randf() < 0.1:
		bot.apply_central_force(-obstacle_avoid_direction * force * 0.5)

	# If stuck for too long, give up on current target
	if unstuck_timer <= 0.0:
		print("Bot %s successfully unstuck or timeout, resuming normal behavior" % bot.name)
		is_stuck = false
		unstuck_timer = 0.0
		consecutive_stuck_checks = 0
		# Clear current targets to force re-evaluation
		if state == "CHASE" or state == "ATTACK":
			# Move to a different area
			var escape_angle: float = randf() * TAU
			var escape_distance: float = randf_range(10.0, 20.0)
			wander_target = bot.global_position + Vector3(cos(escape_angle) * escape_distance, 0, sin(escape_angle) * escape_distance)
			state = "WANDER"
			wander_timer = randf_range(2.0, 4.0)
