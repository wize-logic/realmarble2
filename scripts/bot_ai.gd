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
var stuck_print_timer: float = 0.0  # Timer to throttle stuck debug prints
const MAX_STUCK_ATTEMPTS: int = 15  # Teleport bot after this many consecutive stuck checks

# Slope navigation variables
var is_on_slope: bool = false
var ground_normal: Vector3 = Vector3.UP
var slope_check_timer: float = 0.0

# Target timeout variables - for abandoning unreachable targets
var target_stuck_timer: float = 0.0
var target_stuck_position: Vector3 = Vector3.ZERO
const TARGET_STUCK_TIMEOUT: float = 2.5  # Abandon target after 2.5 seconds (reduced from 5.0)

# Line of sight tracking for targets
var target_blocked_timer: float = 0.0
const TARGET_BLOCKED_TIMEOUT: float = 1.5  # Abandon target after 1.5 seconds (reduced from 3.0)

# State transition cooldown to prevent analysis paralysis
var state_transition_cooldown: float = 0.0
const STATE_TRANSITION_DELAY: float = 0.3  # Only check state transitions every 0.3 seconds

# Ability preferences based on situation and hitbox awareness
const CANNON_OPTIMAL_RANGE: float = 20.0
const SWORD_OPTIMAL_RANGE: float = 4.0
const DASH_ATTACK_OPTIMAL_RANGE: float = 8.0
const EXPLOSION_OPTIMAL_RANGE: float = 6.0

# Ability hitbox sizes at different charge levels (for accurate positioning)
# Format: [charge_1, charge_2, charge_3]
const EXPLOSION_RADII: Array = [5.0, 7.5, 10.0]  # +50% per charge level
const SWORD_RANGES: Array = [3.0, 3.6, 4.2]  # +20% per charge level
const DASH_HITBOX_RADII: Array = [1.5, 1.95, 2.4]  # +30% per charge level

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
	# Randomize reaction time for more human-like behavior (reduced for less hesitation)
	reaction_time = randf_range(0.05, 0.15)
	print("BotAI initialized: aggression=%.2f, reaction_time=%.2f" % [aggression_level, reaction_time])
	call_deferred("find_target")

func _physics_process(delta: float) -> void:
	if not bot:
		print("ERROR: BotAI has no bot parent in _physics_process!")
		return

	if not is_instance_valid(bot):
		print("ERROR: BotAI bot parent is not valid!")
		return

	# Only run AI when the game is active
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if not world or not world.game_active:
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
	stuck_print_timer -= delta
	slope_check_timer -= delta
	target_blocked_timer += delta  # Increment when checking
	state_transition_cooldown -= delta

	# Check ground normal and slope status periodically
	if slope_check_timer <= 0.0:
		check_ground_status()
		slope_check_timer = 0.1  # Check frequently for responsive slope handling

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

	# Check state transitions (throttled to prevent analysis paralysis)
	if state_transition_cooldown <= 0.0:
		update_state()
		state_transition_cooldown = STATE_TRANSITION_DELAY

func update_state() -> void:
	## Update AI state based on conditions
	# PRIORITY 0 (HIGHEST): Get an ability if we don't have one - can't do anything without it!
	if not bot.current_ability:
		# CRITICAL: Clear player target in combat states only (prevents stalking/strafing)
		if state == "CHASE" or state == "ATTACK" or state == "RETREAT":
			target_player = null

		# Actively search for abilities - this is THE top priority
		find_nearest_ability()

		# If we found an ability, go get it immediately
		if target_ability and is_instance_valid(target_ability):
			state = "COLLECT_ABILITY"
			return

		# No abilities available, collect orbs to level up instead
		if bot.level < bot.MAX_LEVEL:
			find_nearest_orb()
			if target_orb and is_instance_valid(target_orb):
				state = "COLLECT_ORB"
				return

		# Nothing to collect, just wander and keep searching
		state = "WANDER"
		return

	# Priority 1: Retreat if low health and enemy nearby (only when we have an ability)
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

	# Priority 2: Collect orbs between abilities when below max level
	# If ability is on cooldown and bot needs levels, collect orbs
	if bot.current_ability and bot.level < bot.MAX_LEVEL:
		var is_ability_ready: bool = bot.current_ability.has_method("is_ready") and bot.current_ability.is_ready()
		if not is_ability_ready:  # Ability on cooldown, good time to collect orbs
			# Only collect if no immediate threat OR enemy is far away
			var safe_to_collect: bool = not has_combat_target or distance_to_target > attack_range * 2.0
			if safe_to_collect:
				find_nearest_orb()  # Search for orbs
				if target_orb and is_instance_valid(target_orb):
					var distance_to_orb: float = bot.global_position.distance_to(target_orb.global_position)
					if distance_to_orb < 40.0:
						state = "COLLECT_ORB"
						return

	# Priority 3: Combat if we HAVE an ability and enemy is in immediate attack range
	# CRITICAL: Only allow combat states if bot has an ability
	if bot.current_ability and has_combat_target and distance_to_target < attack_range * 1.5:
		state = "ATTACK"
		return

	# Priority 4: Collect orbs if not max level and one is nearby
	if bot.level < bot.MAX_LEVEL:
		find_nearest_orb()  # Search for orbs
		if target_orb and is_instance_valid(target_orb):
			var distance_to_orb: float = bot.global_position.distance_to(target_orb.global_position)
			# Collect orbs more aggressively - bots need to level up
			var orb_priority_range: float = 35.0
			if not has_combat_target or distance_to_target > aggro_range * 0.5:
				orb_priority_range = 50.0
			# Don't collect orbs if enemy is actively attacking us (very close) and we have an ability
			if distance_to_orb < orb_priority_range and (not has_combat_target or distance_to_target > attack_range * 1.8 or not bot.current_ability):
				state = "COLLECT_ORB"
				return

	# Priority 5: Combat if we HAVE an ability and player is in aggro range
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
	## Wander around randomly while actively searching for targets
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

	# Jump more frequently - especially when on slopes or moving slowly
	if action_timer <= 0.0:
		var should_jump: bool = false
		var jump_cooldown: float = randf_range(1.0, 3.0)

		# Jump if on a slope
		if is_on_slope and randf() < 0.5:
			should_jump = true
			jump_cooldown = randf_range(0.5, 1.5)
		# Jump if moving slowly (might be stuck on something)
		elif bot.linear_velocity.length() < 2.0 and randf() < 0.4:
			should_jump = true
			jump_cooldown = randf_range(0.5, 1.0)
		# Random jumps for exploration
		elif randf() < 0.25:
			should_jump = true

		if should_jump:
			bot_jump()
			action_timer = jump_cooldown

func do_chase(delta: float) -> void:
	## Chase the target player with tactical movement
	# CRITICAL: Absolutely no chasing without an ability!
	# Exit immediately before any movement or logic
	if not bot.current_ability:
		# Force state change and return - don't do any movement
		state = "WANDER"
		return

	if not target_player:
		return

	var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)
	var height_diff: float = target_player.global_position.y - bot.global_position.y

	# Check if we still have line of sight - if not for too long, find new target
	if not has_line_of_sight(target_player.global_position, 1.0):
		if target_blocked_timer >= TARGET_BLOCKED_TIMEOUT * 1.5:  # Give more time in combat
			print("Bot %s lost sight of target for too long, finding new target" % bot.name)
			find_target()  # Find a new visible target
			target_blocked_timer = 0.0
	else:
		target_blocked_timer = 0.0

	# CRITICAL: Make bot face the target for aiming with predictive targeting
	look_at_target(target_player.global_position, true)

	# Determine optimal distance based on current ability
	var optimal_distance: float = get_optimal_combat_distance()

	# Calculate chase buffer (larger than attack buffer to close distance aggressively)
	var chase_buffer: float = max(2.0, optimal_distance * 0.5)  # 50% of optimal, minimum 2.0

	# If we have a weapon and are too far, close in aggressively
	# If we're at good range, maintain distance with strafing
	if distance_to_target > optimal_distance + chase_buffer:
		# Close the distance - faster for short-range abilities
		var chase_speed: float = 1.0 if optimal_distance < 8.0 else 0.9  # Max speed for melee
		move_towards(target_player.global_position, delta, chase_speed)
		# Re-aim after moving
		look_at_target(target_player.global_position, true)
	else:
		# Close enough - strafe while maintaining distance (strafe function handles aiming)
		strafe_around_target(delta, optimal_distance)

	# Use abilities while chasing if in range
	if bot.current_ability and bot.current_ability.has_method("use"):
		use_ability_smart(distance_to_target)

	# Smart jumping - more aggressive when target is on higher ground, on slopes, or moving slowly
	if action_timer <= 0.0:
		var should_jump: bool = false
		var jump_cooldown: float = randf_range(0.5, 1.5)

		if height_diff > 1.0:
			# Target is significantly higher - jump frequently to reach them
			should_jump = true
			jump_cooldown = randf_range(0.3, 0.6)
		elif height_diff > 0.5 and randf() < 0.6:
			# Target is slightly higher - jump often
			should_jump = true
			jump_cooldown = randf_range(0.4, 0.8)
		elif is_on_slope and randf() < 0.7:
			# On a slope - jump to maintain momentum
			should_jump = true
			jump_cooldown = randf_range(0.3, 0.7)
		elif bot.linear_velocity.length() < 3.0 and randf() < 0.5:
			# Moving slowly - might be stuck, jump to clear obstacle
			should_jump = true
			jump_cooldown = randf_range(0.4, 0.8)
		elif randf() < 0.3:  # Random jumps for unpredictability (increased from 0.25)
			should_jump = true

		if should_jump:
			bot_jump()
			action_timer = jump_cooldown

func do_attack(delta: float) -> void:
	## Attack the target player with smart ability usage
	# CRITICAL: Absolutely no attacking without an ability!
	# Exit immediately before any movement or logic
	if not bot.current_ability:
		# Force state change and return - don't do any positioning or strafing
		state = "WANDER"
		return

	# CRITICAL: Can't attack if ability is on cooldown
	# Exit ATTACK state and do something else useful
	if not bot.current_ability.is_ready():
		# Ability is recharging - transition to different behavior
		if bot.level < bot.MAX_LEVEL:
			# Try to collect orbs while waiting for cooldown
			find_nearest_orb()
			if target_orb and is_instance_valid(target_orb):
				var distance_to_orb: float = bot.global_position.distance_to(target_orb.global_position)
				if distance_to_orb < 40.0:
					state = "COLLECT_ORB"
					return
		# Otherwise, maintain distance (chase state)
		state = "CHASE"
		return

	if not target_player:
		return

	var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)
	var height_diff: float = target_player.global_position.y - bot.global_position.y
	var optimal_distance: float = get_optimal_combat_distance()

	# Check if we still have line of sight - if not for too long, find new target
	if not has_line_of_sight(target_player.global_position, 1.0):
		if target_blocked_timer >= TARGET_BLOCKED_TIMEOUT * 1.5:  # Give more time in combat
			print("Bot %s lost sight of target for too long, finding new target" % bot.name)
			find_target()  # Find a new visible target
			target_blocked_timer = 0.0
	else:
		target_blocked_timer = 0.0

	# CRITICAL: Make bot face the target for aiming with predictive targeting
	look_at_target(target_player.global_position, true)

	# Check if we're properly aimed at target (for forward-facing abilities)
	var ability_name: String = bot.current_ability.ability_name if "ability_name" in bot.current_ability else ""
	var is_aimed_at_target: bool = false
	var needs_precise_aim: bool = ability_name in ["Cannon", "Dash Attack"]

	if needs_precise_aim:
		# For directional abilities, check aiming
		is_aimed_at_target = is_facing_target(target_player.global_position, 25.0)
	else:
		# For AoE/melee, just check rough facing
		is_aimed_at_target = is_facing_target(target_player.global_position, 60.0)

	# Calculate distance buffer based on optimal range and ability hitbox
	# Short-range weapons need tighter buffers, long-range can have larger buffers
	# For explosion, use larger buffer to account for AoE radius
	var distance_buffer: float = max(1.0, optimal_distance * 0.3)  # 30% of optimal, minimum 1.0
	if ability_name == "Explosion":
		# Use the explosion radius as the buffer instead
		if distance_to_target > 7.5:
			distance_buffer = 2.5  # Buffer for level 3 explosion (10.0 radius)
		elif distance_to_target > 5.0:
			distance_buffer = 2.0  # Buffer for level 2 explosion (7.5 radius)
		else:
			distance_buffer = 1.5  # Buffer for level 1 explosion (5.0 radius)

	# Tactical positioning - maintain optimal range while strafing
	if distance_to_target > optimal_distance + distance_buffer:
		# Too far, close in aggressively (especially for short-range abilities)
		var close_speed: float = 1.0 if optimal_distance < 8.0 else 0.7  # Faster for melee
		move_towards(target_player.global_position, delta, close_speed)
		# Re-aim after moving
		look_at_target(target_player.global_position, true)
	elif distance_to_target < optimal_distance - distance_buffer:
		# Too close, back up while strafing
		move_away_from(target_player.global_position, delta, 0.5)
		# Re-aim after moving
		look_at_target(target_player.global_position, true)
	else:
		# Good range - prioritize aiming for forward-facing abilities
		if needs_precise_aim and not is_aimed_at_target:
			# Stop moving, just rotate to aim (look_at_target already called above)
			# Reduce movement to allow rotation to complete
			pass
		else:
			# Properly aimed or doesn't need precise aim - strafe to be harder to hit
			strafe_around_target(delta, optimal_distance)

	# Use ability intelligently (function handles its own aiming)
	if bot.current_ability and bot.current_ability.has_method("use"):
		use_ability_smart(distance_to_target)
	# Spin dash as last resort or for mobility
	elif action_timer <= 0.0:
		if randf() < 0.15 and bot.spin_cooldown <= 0.0 and not bot.is_spin_dashing and not bot.is_charging_spin:
			# Use spin dash strategically
			bot.is_charging_spin = true
			bot.spin_charge = randf_range(0.3, bot.max_spin_charge * 0.7)
			get_tree().create_timer(randf_range(0.2, 0.5)).timeout.connect(func(): release_spin_dash())
			action_timer = randf_range(1.5, 2.5)  # Reduced for less hesitation

	# Jump tactically - more aggressive when target is higher, on slopes, or moving slowly
	if action_timer <= 0.0:
		var should_jump: bool = false
		var jump_cooldown: float = randf_range(0.4, 1.0)

		if height_diff > 0.8:
			# Target is higher - jump to reach them
			should_jump = true
			jump_cooldown = randf_range(0.3, 0.7)
		elif height_diff > 0.3 and randf() < 0.5:
			# Target is slightly higher - jump often
			should_jump = true
			jump_cooldown = randf_range(0.3, 0.8)
		elif is_on_slope and randf() < 0.6:
			# On a slope - jump to maintain momentum and positioning
			should_jump = true
			jump_cooldown = randf_range(0.3, 0.6)
		elif bot.linear_velocity.length() < 3.0 and randf() < 0.4:
			# Moving slowly - jump to clear obstacle
			should_jump = true
			jump_cooldown = randf_range(0.3, 0.7)
		elif randf() < 0.25:  # Random jumps for unpredictability (increased from 0.2)
			should_jump = true

		if should_jump:
			bot_jump()
			action_timer = jump_cooldown

func do_retreat(delta: float) -> void:
	## Retreat from danger when low health while keeping aim
	if not target_player or retreat_timer <= 0.0:
		state = "WANDER"
		return

	# Keep aiming at target even while retreating (for defensive shots)
	look_at_target(target_player.global_position, true)

	# Move away from target (function also handles aiming)
	move_away_from(target_player.global_position, delta, 1.0)

	# Can still use abilities while retreating if available
	if bot.current_ability and bot.current_ability.has_method("use"):
		var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)
		if distance_to_target < 30.0:  # Use abilities if in range
			use_ability_smart(distance_to_target)

	# Jump frequently to evade - very aggressive jumping when retreating
	if action_timer <= 0.0:
		var should_jump: bool = false
		var jump_cooldown: float = randf_range(0.3, 0.8)

		if is_on_slope and randf() < 0.8:
			# On slope - jump very often to escape quickly
			should_jump = true
			jump_cooldown = randf_range(0.2, 0.5)
		elif bot.linear_velocity.length() < 4.0 and randf() < 0.6:
			# Moving slowly - jump to escape faster
			should_jump = true
			jump_cooldown = randf_range(0.3, 0.6)
		elif randf() < 0.5:  # Jump often when retreating (increased from 0.4)
			should_jump = true

		if should_jump:
			bot_jump()
			action_timer = jump_cooldown

func strafe_around_target(delta: float, preferred_distance: float) -> void:
	## Strafe around target while maintaining distance and keeping aim
	if not target_player:
		return

	# Always aim at target while strafing for accurate shots
	look_at_target(target_player.global_position, true)

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
	## Move the bot away from a target position while maintaining aim
	if not bot:
		return

	# Keep aiming at target even while retreating
	if target_player:
		look_at_target(target_player.global_position, true)

	var direction: Vector3 = (bot.global_position - target_pos).normalized()
	direction.y = 0  # Keep horizontal

	if direction.length() > 0.1:
		var force: float = bot.current_roll_force * speed_mult
		bot.apply_central_force(direction * force)

func get_optimal_combat_distance() -> float:
	## Get the optimal combat distance based on current ability and target distance
	if not bot.current_ability:
		return DASH_ATTACK_OPTIMAL_RANGE  # Default to medium range

	var ability_name: String = bot.current_ability.ability_name if "ability_name" in bot.current_ability else ""

	# For distance-based abilities, calculate optimal range based on intended charge level
	if target_player and is_instance_valid(target_player):
		var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)

		match ability_name:
			"Explosion":
				# Position based on intended charge level for optimal coverage
				# If target is far, position for charged explosion (larger radius)
				if distance_to_target > 7.5:
					return 8.0  # Position for level 3 charge (10.0 radius)
				elif distance_to_target > 5.0:
					return 6.0  # Position for level 2 charge (7.5 radius)
				else:
					return 4.5  # Position for level 1 (5.0 radius)
			"Sword":
				# Position based on sword range and charge
				if distance_to_target > 3.6:
					return 3.8  # Position for charged sword (4.2 range)
				else:
					return 3.2  # Position for uncharged sword (3.0 range)

	# Default optimal ranges for other abilities
	match ability_name:
		"Cannon":
			return CANNON_OPTIMAL_RANGE
		"Sword":
			return SWORD_OPTIMAL_RANGE
		"Dash Attack":
			return DASH_ATTACK_OPTIMAL_RANGE
		"Explosion":
			return EXPLOSION_OPTIMAL_RANGE
		_:
			return preferred_combat_distance

func is_facing_target(target_position: Vector3, required_angle_degrees: float = 30.0) -> bool:
	## Check if bot is facing the target within a given angle tolerance
	## Required for forward-facing abilities like Cannon and Dash Attack
	## Returns true if target is within the required cone angle
	if not bot or not target_position:
		return false

	# Get bot's forward direction (based on rotation)
	var forward_direction: Vector3 = Vector3(-sin(bot.rotation.y), 0, -cos(bot.rotation.y))

	# Get direction to target
	var to_target: Vector3 = (target_position - bot.global_position).normalized()
	to_target.y = 0  # Only check horizontal angle
	forward_direction.y = 0

	# Calculate angle between forward and target direction
	var dot_product: float = forward_direction.dot(to_target)
	var angle_radians: float = acos(clamp(dot_product, -1.0, 1.0))
	var angle_degrees: float = rad_to_deg(angle_radians)

	# Return true if target is within the required angle cone
	return angle_degrees <= required_angle_degrees

func will_hitbox_reach_target(ability_name: String, charge_level: int, distance_to_target: float) -> bool:
	## Check if an ability's hitbox will actually reach the target at the given charge level
	## charge_level: 1 (no charge), 2 (partial charge), 3 (full charge)
	## Returns true if the hitbox will reach, false otherwise

	match ability_name:
		"Sword":
			# Sword hitbox ranges: [3.0, 3.6, 4.2]
			var sword_range: float = SWORD_RANGES[charge_level - 1]
			return distance_to_target <= sword_range
		"Explosion":
			# Explosion radii: [5.0, 7.5, 10.0]
			var explosion_radius: float = EXPLOSION_RADII[charge_level - 1]
			return distance_to_target <= explosion_radius
		"Dash Attack":
			# Dash has hitbox but also moves toward target
			# Dash hitbox radii: [1.5, 1.95, 2.4]
			# Plus dash travel distance based on charge (roughly 5-15 units)
			var dash_radius: float = DASH_HITBOX_RADII[charge_level - 1]
			var dash_travel: float = 5.0 + (charge_level - 1) * 5.0  # ~5, 10, 15 units
			var effective_range: float = dash_travel + dash_radius
			return distance_to_target <= effective_range
		"Cannon":
			# Cannon is projectile-based, has very long range (50+ units)
			# Just check if in reasonable range
			return distance_to_target <= 50.0
		_:
			# Unknown ability, assume it can reach
			return true

func determine_optimal_charge_level(ability_name: String, distance_to_target: float) -> int:
	## Determine the optimal charge level (1-3) needed to hit target at given distance
	## Returns the minimum charge level that will reach the target

	match ability_name:
		"Sword":
			# Find minimum charge level that reaches target
			if distance_to_target <= SWORD_RANGES[0]:  # 3.0
				return 1
			elif distance_to_target <= SWORD_RANGES[1]:  # 3.6
				return 2
			elif distance_to_target <= SWORD_RANGES[2]:  # 4.2
				return 3
			else:
				return 0  # Out of range
		"Explosion":
			# Find minimum charge level that reaches target
			if distance_to_target <= EXPLOSION_RADII[0]:  # 5.0
				return 1
			elif distance_to_target <= EXPLOSION_RADII[1]:  # 7.5
				return 2
			elif distance_to_target <= EXPLOSION_RADII[2]:  # 10.0
				return 3
			else:
				return 0  # Out of range
		"Dash Attack":
			# Dash benefits from charging for distance and damage
			# Always prefer charge level 2-3 for reliability
			var dash_radius_1: float = DASH_HITBOX_RADII[0] + 5.0   # ~6.5
			var dash_radius_2: float = DASH_HITBOX_RADII[1] + 10.0  # ~12
			var dash_radius_3: float = DASH_HITBOX_RADII[2] + 15.0  # ~17.4

			if distance_to_target <= dash_radius_1:
				return 1
			elif distance_to_target <= dash_radius_2:
				return 2
			elif distance_to_target <= dash_radius_3:
				return 3
			else:
				return 0  # Out of range
		"Cannon":
			# Cannon benefits from charging but has long range regardless
			if distance_to_target > 20.0:
				return 2  # Charge for long distance
			else:
				return 1  # Don't need charge at close range
		_:
			return 1  # Default to no charge

func use_ability_smart(distance_to_target: float) -> void:
	## Use ability with smart timing and charging
	if not bot.current_ability or not bot.current_ability.is_ready():
		is_charging_ability = false
		return

	var ability_name: String = bot.current_ability.ability_name if "ability_name" in bot.current_ability else ""
	var should_use: bool = false
	var should_charge: bool = false

	# CRITICAL: Check if bot is facing target (required for directional abilities)
	var is_aimed: bool = false
	if target_player and is_instance_valid(target_player):
		# Different abilities need different aiming precision
		match ability_name:
			"Cannon":
				is_aimed = is_facing_target(target_player.global_position, 25.0)  # 25° cone for cannon
			"Dash Attack":
				is_aimed = is_facing_target(target_player.global_position, 30.0)  # 30° cone for dash
			"Sword":
				is_aimed = is_facing_target(target_player.global_position, 45.0)  # 45° cone for sword (melee)
			"Explosion":
				is_aimed = true  # AoE doesn't need precise aiming
			_:
				is_aimed = is_facing_target(target_player.global_position, 35.0)  # Default 35° cone

	# IMPROVED LOGIC: Use helper functions to accurately determine if we can hit
	# Step 1: Determine what charge level we need to reach the target
	var required_charge_level: int = determine_optimal_charge_level(ability_name, distance_to_target)

	# Step 2: If we can't reach even with full charge, don't attack
	if required_charge_level == 0:
		# Target is out of range
		should_use = false
		should_charge = false
	else:
		# Step 3: We can reach - decide whether to use and charge
		# Must be aimed for directional abilities
		match ability_name:
			"Cannon":
				# CRITICAL: Cannon is forward-facing only - MUST be aimed!
				if distance_to_target > 3.0 and is_aimed:
					should_use = true
					# Charge based on what's needed to reach
					should_charge = (required_charge_level >= 2)
			"Sword":
				# Sword needs to be facing target
				if is_aimed:
					should_use = true
					# Charge based on what's needed to reach, with some randomness
					if required_charge_level == 1:
						# Can hit without charging, rarely charge anyway
						should_charge = randf() < 0.2
					elif required_charge_level == 2:
						# Need charge level 2, charge most of the time
						should_charge = randf() < 0.8
					else:
						# Need full charge to reach
						should_charge = randf() < 0.95
			"Dash Attack":
				# CRITICAL: Dash attack is forward-facing - MUST be aimed!
				if distance_to_target > 2.0 and is_aimed:
					should_use = true
					# Dash benefits from charging for distance and damage
					if required_charge_level == 1:
						# Can hit but prefer some charge for speed
						should_charge = randf() < 0.5
					else:
						# Need charge to reach
						should_charge = randf() < 0.9
			"Explosion":
				# Explosion is AoE, doesn't need precise aiming
				should_use = true
				# Charge based on what's needed to reach the target
				if required_charge_level == 1:
					# Can hit without charging, rarely charge anyway
					should_charge = randf() < 0.15
				elif required_charge_level == 2:
					# Need charge level 2 to reach
					should_charge = randf() < 0.8
				else:
					# Need full charge to reach
					should_charge = randf() < 0.95
			_:
				# Default: use when in reasonable range and aimed
				if distance_to_target < 25.0 and is_aimed:
					should_use = randf() < 0.5
					should_charge = randf() < 0.6

	# Charging logic
	if should_use and should_charge and not is_charging_ability:
		# Aim at target before charging
		if target_player:
			look_at_target(target_player.global_position, true)
		# Start charging
		if bot.current_ability.has_method("start_charging"):
			is_charging_ability = true
			# Charge duration based on ability and intended charge level
			if ability_name == "Dash Attack":
				ability_charge_timer = randf_range(0.8, 1.3)  # Longer charge for dash
			elif ability_name == "Explosion":
				# Charge based on distance for optimal explosion radius
				if distance_to_target > 7.5:
					ability_charge_timer = randf_range(1.0, 1.5)  # Long charge for level 3
				elif distance_to_target > 5.0:
					ability_charge_timer = randf_range(0.6, 1.0)  # Medium charge for level 2
				else:
					ability_charge_timer = randf_range(0.3, 0.6)  # Short charge for level 1
			elif ability_name == "Sword":
				# Charge based on distance for optimal sword reach
				if distance_to_target > 3.6:
					ability_charge_timer = randf_range(0.8, 1.2)  # Long charge for extra reach
				elif distance_to_target > 3.0:
					ability_charge_timer = randf_range(0.5, 0.9)  # Medium charge
				else:
					ability_charge_timer = randf_range(0.3, 0.6)  # Short charge
			else:
				ability_charge_timer = randf_range(0.5, 1.2)
			bot.current_ability.start_charging()

	# Keep aiming at target while charging
	if is_charging_ability and target_player:
		look_at_target(target_player.global_position, true)

	# Release charged ability or use instantly
	if is_charging_ability and ability_charge_timer <= 0.0:
		# Final aim adjustment before releasing
		if target_player:
			look_at_target(target_player.global_position, true)
		# Release charge
		is_charging_ability = false
		bot.current_ability.use()
		action_timer = randf_range(0.2, 0.7)  # Reduced for less hesitation
	elif should_use and not should_charge and not is_charging_ability:
		# Aim at target before instant firing
		if target_player:
			look_at_target(target_player.global_position, true)
		# Use immediately without charging
		bot.current_ability.use()
		action_timer = randf_range(0.3, 1.0)  # Reduced for less hesitation

func move_towards(target_pos: Vector3, delta: float, speed_mult: float = 1.0) -> void:
	## Move the bot towards a target position with obstacle detection
	if not bot:
		return

	var direction: Vector3 = (target_pos - bot.global_position).normalized()
	direction.y = 0  # Keep horizontal

	# Check if target is significantly above us (platform or higher ground)
	var height_diff: float = target_pos.y - bot.global_position.y

	if direction.length() > 0.1:
		# Check for dangerous edges first - HIGHEST PRIORITY - EXTRA CAREFUL
		if check_for_edge(direction, 4.5):  # Increased from 3.5 to 4.5 for earlier detection
			# There's an edge ahead - find a safe direction or stop
			var safe_direction: Vector3 = find_safe_direction_from_edge(direction)
			if safe_direction != Vector3.ZERO:
				direction = safe_direction
				speed_mult *= 0.5  # Slow down more when avoiding edges (was 0.6)
			else:
				# No safe direction, STOP COMPLETELY and move backwards
				var backwards: Vector3 = -direction
				bot.apply_central_force(backwards * bot.current_roll_force * 1.2)  # Stronger backwards force
				# Jump backwards to escape the edge
				if obstacle_jump_timer <= 0.0:
					bot_jump()
					obstacle_jump_timer = 0.3
				print("Bot %s: Edge detected, moving backwards and jumping!" % bot.name)
				return

		# If we're on a slope, add upward force to help climb
		if is_on_slope:
			var slope_assist_force: float = bot.current_roll_force * 0.4
			bot.apply_central_force(Vector3.UP * slope_assist_force)
			# Jump more frequently on slopes to maintain momentum
			if obstacle_jump_timer <= 0.0 and randf() < 0.6:
				bot_jump()
				obstacle_jump_timer = 0.15  # Very short cooldown on slopes

		# First, check for platforms ahead that we can jump onto
		var platform_info: Dictionary = detect_platform_ahead(direction, 6.0)
		if platform_info.has_platform and obstacle_jump_timer <= 0.0:
			# Platform detected ahead - jump proactively to get on it
			bot_jump()
			obstacle_jump_timer = 0.1  # Very short cooldown - reduced from 0.2
			# Push forward while jumping
			var force: float = bot.current_roll_force * speed_mult * 1.3
			var climb_direction: Vector3 = direction + Vector3.UP * 0.25
			bot.apply_central_force(climb_direction.normalized() * force)
			return

		# Check for obstacles in the path with improved detection
		# Scan further ahead (4.0 instead of default 3.0) to give more time to react
		var obstacle_info: Dictionary = check_obstacle_in_direction(direction, 4.0)

		if obstacle_info.has_obstacle:
			# Handle slopes and platforms - try to jump onto them
			if obstacle_info.is_slope or obstacle_info.is_platform:
				# Jump onto slopes and platforms proactively - reduced cooldown
				if obstacle_jump_timer <= 0.0:
					bot_jump()
					obstacle_jump_timer = 0.1  # Very aggressive jumping - reduced from 0.15
					# Continue moving forward while jumping to get on the slope with extra force
					var force: float = bot.current_roll_force * speed_mult * 1.5  # Increased from 1.3
					# Add upward component to force to help climb
					var climb_direction: Vector3 = direction + Vector3.UP * 0.3
					bot.apply_central_force(climb_direction.normalized() * force)
					return
				else:
					# Even if on cooldown, keep moving toward the slope with upward force
					var force: float = bot.current_roll_force * speed_mult * 1.2
					var climb_direction: Vector3 = direction + Vector3.UP * 0.2
					bot.apply_central_force(climb_direction.normalized() * force)
					return

			# For walls and other obstacles - MOVE OPPOSITE DIRECTION
			# This prevents getting stuck trying to navigate around
			if "is_wall" in obstacle_info and obstacle_info.is_wall:
				# Wall detected - try to jump over it first if it's low
				if obstacle_info.can_jump and obstacle_jump_timer <= 0.0:
					bot_jump()
					obstacle_jump_timer = 0.2  # Reduced from 0.4 for more frequent wall jumps
					# Push forward while jumping
					var force: float = bot.current_roll_force * speed_mult * 0.8
					bot.apply_central_force(direction * force)
				else:
					# Can't jump or on cooldown - move in opposite direction
					print("Bot %s: Wall detected, moving backwards" % bot.name)
					direction = -direction  # Complete opposite
					speed_mult *= 0.5  # Slow down while backing up
			else:
				# Other obstacle - try jumping first, then go opposite if can't jump
				if obstacle_info.can_jump and obstacle_jump_timer <= 0.0:
					bot_jump()
					obstacle_jump_timer = 0.15  # Reduced from 0.3 for more frequent jumps
					# Push forward while jumping
					var force: float = bot.current_roll_force * speed_mult * 0.8
					bot.apply_central_force(direction * force)
				else:
					# Can't jump - move in opposite direction
					direction = -direction
					speed_mult *= 0.5

		# If target is above us and no obstacle blocking, jump to gain height
		elif height_diff > 1.0 and obstacle_jump_timer <= 0.0 and randf() < 0.7:  # Increased from 0.5
			bot_jump()
			obstacle_jump_timer = 0.3  # Reduced from 0.5

		# CRITICAL: Jump proactively if bot is moving very slowly (likely stuck on geometry)
		# This catches cases where obstacle detection might miss small geometry
		if bot.linear_velocity.length() < 1.5 and obstacle_jump_timer <= 0.0 and randf() < 0.4:
			bot_jump()
			obstacle_jump_timer = 0.25  # Short cooldown for frequent geometry clearing

		# Apply movement force
		var force: float = bot.current_roll_force * speed_mult
		bot.apply_central_force(direction * force)

func bot_jump() -> void:
	## Make the bot jump
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

func look_at_target(target_position: Vector3, use_prediction: bool = true) -> void:
	## Rotate bot to face target for aiming with optional predictive targeting
	if not bot:
		return

	var aim_position: Vector3 = target_position

	# Add predictive aiming if target is a player with velocity
	if use_prediction and target_player and is_instance_valid(target_player):
		if "linear_velocity" in target_player:
			var target_velocity: Vector3 = target_player.linear_velocity
			var distance_to_target: float = bot.global_position.distance_to(target_position)

			# Estimate time for projectile/attack to reach target based on distance
			# Assumes average projectile speed or dash speed
			var time_to_impact: float = distance_to_target / 30.0  # 30 units/sec average

			# Predict where target will be
			var predicted_offset: Vector3 = target_velocity * time_to_impact

			# Only use horizontal prediction (ignore Y velocity for simplicity)
			predicted_offset.y = 0

			# Limit prediction distance to avoid over-leading
			if predicted_offset.length() > distance_to_target * 0.5:
				predicted_offset = predicted_offset.normalized() * distance_to_target * 0.5

			aim_position = target_position + predicted_offset

	# Calculate direction to aim position (only horizontal rotation)
	var target_dir: Vector3 = aim_position - bot.global_position
	target_dir.y = 0  # Keep rotation horizontal only

	if target_dir.length() > 0.1:
		# Calculate the angle to face the target
		var desired_rotation: float = atan2(target_dir.x, target_dir.z)

		# Smoothly rotate toward target (instant rotation for now, can be smoothed later)
		bot.rotation.y = desired_rotation

func release_spin_dash() -> void:
	## Release spin dash
	if bot and bot.is_charging_spin:
		bot.is_charging_spin = false
		if bot.has_method("execute_spin_dash"):
			bot.execute_spin_dash()

func find_target() -> void:
	## Find the nearest player to target with preference for visible targets
	# CRITICAL: Don't target players if we don't have an ability
	# This prevents stalking behavior where bots follow players around without weapons
	if not bot.current_ability:
		target_player = null
		return

	var players: Array = get_tree().get_nodes_in_group("players")
	var closest_player: Node = null
	var closest_distance: float = INF
	var closest_visible_player: Node = null
	var closest_visible_distance: float = INF

	for player in players:
		if player == bot:  # Don't target self
			continue
		if not is_instance_valid(player):
			continue

		var distance: float = bot.global_position.distance_to(player.global_position)

		# Track closest overall
		if distance < closest_distance:
			closest_distance = distance
			closest_player = player

		# Prioritize visible players
		if distance < aggro_range and has_line_of_sight(player.global_position, 1.0):
			if distance < closest_visible_distance:
				closest_visible_distance = distance
				closest_visible_player = player

	# Prefer visible players, but fall back to closest if none visible
	if closest_visible_player:
		target_player = closest_visible_player
	else:
		target_player = closest_player

func find_nearest_ability() -> void:
	## Find the nearest ability pickup with line of sight
	var abilities: Array = get_tree().get_nodes_in_group("ability_pickups")
	var closest_ability: Node = null
	var closest_distance: float = INF

	for ability in abilities:
		if not is_instance_valid(ability):
			continue

		var distance: float = bot.global_position.distance_to(ability.global_position)

		# Only consider abilities within reasonable range and with line of sight
		if distance < 70.0 and distance < closest_distance:
			# Check line of sight to ability
			if has_line_of_sight(ability.global_position, 0.5):
				closest_distance = distance
				closest_ability = ability

	target_ability = closest_ability

func do_collect_ability(delta: float) -> void:
	## Move towards and collect an ability
	if not target_ability or not is_instance_valid(target_ability):
		target_ability = null
		target_blocked_timer = 0.0
		state = "WANDER"
		return

	var distance: float = bot.global_position.distance_to(target_ability.global_position)

	# Quick abandon if too far or blocked
	if distance > 70.0 or (not has_line_of_sight(target_ability.global_position, 0.5) and target_blocked_timer > 1.5):
		target_ability = null
		target_blocked_timer = 0.0
		state = "WANDER"
		return

	var height_diff: float = target_ability.global_position.y - bot.global_position.y

	# CRITICAL: Slow down when approaching to avoid overshooting
	var speed_mult: float = 1.0
	if distance < 6.0:
		speed_mult = 0.3  # Very slow for precision
	elif distance < 12.0:
		speed_mult = 0.6  # Moderate speed

	move_towards(target_ability.global_position, delta, speed_mult)

	# Simplified jump logic
	if action_timer <= 0.0 and (height_diff > 0.8 or is_on_slope or bot.linear_velocity.length() < 2.0):
		bot_jump()
		action_timer = 0.5

	# Check if we're close enough (pickup will happen automatically via Area3D)
	# Note: distance already declared at top of function, just check the value
	if distance < 2.0:
		# Close enough, should collect automatically
		# Wait a moment then look for new targets
		await get_tree().create_timer(0.5).timeout
		target_ability = null

func find_nearest_orb() -> void:
	## Find the nearest collectible orb with line of sight
	var orbs: Array = get_tree().get_nodes_in_group("orbs")
	var closest_orb: Node = null
	var closest_distance: float = INF

	for orb in orbs:
		if not is_instance_valid(orb):
			continue
		# Skip collected orbs
		if "is_collected" in orb and orb.is_collected:
			continue

		var distance: float = bot.global_position.distance_to(orb.global_position)

		# Only consider orbs within reasonable range and with line of sight
		if distance < 60.0 and distance < closest_distance:
			# Check line of sight to orb
			if has_line_of_sight(orb.global_position, 0.5):
				closest_distance = distance
				closest_orb = orb

	target_orb = closest_orb

func do_collect_orb(delta: float) -> void:
	## Move towards and collect an orb
	if not target_orb or not is_instance_valid(target_orb):
		target_orb = null
		target_blocked_timer = 0.0
		state = "WANDER"
		return

	# Check if orb was collected by someone else
	if "is_collected" in target_orb and target_orb.is_collected:
		target_orb = null
		target_blocked_timer = 0.0
		state = "WANDER"
		return

	var distance: float = bot.global_position.distance_to(target_orb.global_position)

	# Quick abandon if too far or blocked
	if distance > 60.0 or (not has_line_of_sight(target_orb.global_position, 0.5) and target_blocked_timer > 1.5):
		target_orb = null
		target_blocked_timer = 0.0
		state = "WANDER"
		return

	var height_diff: float = target_orb.global_position.y - bot.global_position.y

	# CRITICAL: Slow down when approaching to avoid overshooting
	var speed_mult: float = 1.0
	if distance < 6.0:
		speed_mult = 0.3  # Very slow for precision
	elif distance < 12.0:
		speed_mult = 0.6  # Moderate speed

	move_towards(target_orb.global_position, delta, speed_mult)

	# Simplified jump logic
	if action_timer <= 0.0 and (height_diff > 0.8 or is_on_slope or bot.linear_velocity.length() < 2.0):
		bot_jump()
		action_timer = 0.5

	# Check if we're close enough (pickup will happen automatically via Area3D)
	# Note: distance already declared at top of function, just check the value
	if distance < 2.0:
		# Close enough, should collect automatically
		# Wait a moment then look for new targets
		await get_tree().create_timer(0.3).timeout
		target_orb = null

## ============================================================================
## OBSTACLE DETECTION AND AVOIDANCE FUNCTIONS
## ============================================================================

func has_line_of_sight(target_position: Vector3, check_height: float = 1.0) -> bool:
	## Check if there's a clear line of sight to the target position
	## Returns true if we can see the target, false if blocked by walls/obstacles
	if not bot:
		return false

	var space_state: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state

	# Cast ray from bot to target at chest height
	var start_pos: Vector3 = bot.global_position + Vector3.UP * check_height
	var end_pos: Vector3 = target_position + Vector3.UP * check_height

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
	query.exclude = [bot]
	query.collision_mask = 1  # Only check world geometry (layer 1)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result: Dictionary = space_state.intersect_ray(query)

	# If we hit something, there's an obstacle in the way
	return not result

func detect_platform_ahead(direction: Vector3, scan_distance: float = 5.0) -> Dictionary:
	## Detect if there's a platform ahead that the bot can jump onto
	## Returns dictionary with: {has_platform: bool, platform_height: float, distance: float}
	if not bot:
		return {"has_platform": false, "platform_height": 0.0, "distance": 0.0}

	var space_state: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state

	# Cast multiple horizontal rays at different heights to detect platforms
	var heights_to_check: Array = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]
	var platform_detected: bool = false
	var platform_height: float = 0.0
	var platform_distance: float = 0.0

	for height in heights_to_check:
		var start_pos: Vector3 = bot.global_position + Vector3.UP * height
		var end_pos: Vector3 = start_pos + direction.normalized() * scan_distance

		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
		query.exclude = [bot]
		query.collision_mask = 1
		query.collide_with_areas = false
		query.collide_with_bodies = true

		var result: Dictionary = space_state.intersect_ray(query)

		if result:
			# Found an obstacle - check if it's a platform we can jump onto
			var hit_point: Vector3 = result.position
			var obstacle_height: float = hit_point.y - bot.global_position.y

			# If obstacle is between 0.5 and 4 units high, it's a jumpable platform
			if obstacle_height > 0.3 and obstacle_height < 4.5:
				platform_detected = true
				platform_height = obstacle_height
				platform_distance = bot.global_position.distance_to(hit_point)
				break

	return {
		"has_platform": platform_detected,
		"platform_height": platform_height,
		"distance": platform_distance
	}

func check_ground_status() -> void:
	## Check the ground beneath the bot to detect slopes and update ground normal
	if not bot:
		return

	var space_state: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state

	# Cast a ray downward to check ground
	var ray_start: Vector3 = bot.global_position + Vector3.UP * 0.5
	var ray_end: Vector3 = bot.global_position + Vector3.DOWN * 2.0

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [bot]
	query.collision_mask = 1

	var result: Dictionary = space_state.intersect_ray(query)

	if result:
		# Get the ground normal
		ground_normal = result.normal

		# Check if we're on a slope (normal isn't pointing straight up)
		var slope_angle: float = rad_to_deg(acos(ground_normal.dot(Vector3.UP)))

		# Consider it a slope if angle is between 10 and 60 degrees
		is_on_slope = slope_angle > 10.0 and slope_angle < 60.0
	else:
		# Not on ground
		ground_normal = Vector3.UP
		is_on_slope = false

func check_for_edge(direction: Vector3, check_distance: float = 3.0) -> bool:
	## Check if there's a dangerous edge/drop-off in the given direction
	## Returns true if there's an edge that the bot should avoid
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

	# Consider it an edge if the drop is significant (2.5 units or more)
	# Reduced from 4.0 to be more cautious and prevent falling off stage
	# Also check if the ground ahead is significantly below the bot
	var bot_to_ground_ahead: float = bot.global_position.y - ahead_ground_y

	# Edge if: drop is significant OR ground ahead is far below the bot
	return ground_drop > 2.5 or bot_to_ground_ahead > 5.0

func find_safe_direction_from_edge(dangerous_direction: Vector3) -> Vector3:
	## Find a safe direction to move when the desired direction leads to an edge
	## Tries angles perpendicular and away from the edge
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
	## Check if there's an obstacle in the given direction using multiple raycasts
	## Returns a dictionary with: {has_obstacle: bool, can_jump: bool, is_slope: bool, hit_point: Vector3}
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
			if height_diff > 0.3 and height_diff < 2.5:
				is_slope = true
			# If the lowest hit is above ground level, it's a platform edge
			if lowest_obstacle_height > 0.3 and lowest_obstacle_height < 3.5:
				is_platform = true
			# If we hit at most heights (4+) consistently, it's likely a vertical wall
			if hit_count >= 4 and height_diff < 0.5:
				is_wall = true
			# Additional check: if we hit at all heights with minimal variance, definitely a wall
			if hit_count >= check_heights.size() - 1 and height_diff < 1.0:
				is_wall = true

		# Check if we can jump onto this obstacle
		var distance_to_obstacle: float = bot.global_position.distance_to(closest_hit)

		# More aggressive jump detection for slopes and platforms
		var can_jump: bool = false
		if is_slope or is_platform:
			# For slopes/platforms, be very aggressive about jumping
			# These are meant to be traversed
			can_jump = lowest_obstacle_height < 4.5 and lowest_obstacle_height > -0.5 and distance_to_obstacle > 0.3
		elif is_wall:
			# For walls, only jump if they're low enough (under 2.5 units)
			# Most walls are too high to jump over
			can_jump = lowest_obstacle_height < 2.5 and lowest_obstacle_height > -0.5 and distance_to_obstacle > 0.8
		else:
			# For other obstacles, use moderate jump detection
			can_jump = lowest_obstacle_height < 3.0 and lowest_obstacle_height > -0.5 and distance_to_obstacle > 0.5

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
	## Find a clear direction to move when the desired path is blocked
	## Tries multiple angles to find the best path around obstacles
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
	## Check if bot is stuck trying to reach a collectible target for too long
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
	## Check if the bot hasn't moved much and might be stuck on an obstacle
	if not bot:
		return

	var current_pos: Vector3 = bot.global_position
	var distance_moved: float = current_pos.distance_to(last_position)

	# More sensitive stuck detection: check if bot is trying to move but not making progress
	var is_trying_to_move: bool = state in ["CHASE", "ATTACK", "COLLECT_ABILITY", "COLLECT_ORB"]

	# Detect stuck based on movement - lowered threshold for faster detection
	if distance_moved < 0.15 and is_trying_to_move:
		consecutive_stuck_checks += 1

		# EMERGENCY: Teleport bot if stuck for too long (prevents infinite stuck loops)
		if consecutive_stuck_checks >= MAX_STUCK_ATTEMPTS:
			print("Bot %s EXTREMELY STUCK (%d attempts)! Emergency teleport to spawn" % [bot.name, consecutive_stuck_checks])
			teleport_to_safe_position()
			consecutive_stuck_checks = 0
			is_stuck = false
			return

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
				# Throttle print to once every 3 seconds
				if stuck_print_timer <= 0:
					print("Bot %s is stuck UNDER terrain! Moving backwards and sideways" % bot.name)
					stuck_print_timer = 3.0
			else:
				# Normal stuck - just go BACKWARDS (opposite direction)
				obstacle_avoid_direction = opposite_dir
				# Throttle print to once every 3 seconds
				if stuck_print_timer <= 0:
					print("Bot %s is stuck! Moving in OPPOSITE direction (moved only %0.2f units)" % [bot.name, distance_moved])
					stuck_print_timer = 3.0
	else:
		# Reset stuck counter if we've moved well
		if distance_moved > 0.3:
			consecutive_stuck_checks = 0
			is_stuck = false

	last_position = current_pos

func is_stuck_under_terrain() -> bool:
	## Check if bot is stuck underneath terrain/slope
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

func teleport_to_safe_position() -> void:
	## Teleport bot to a safe spawn position when extremely stuck
	if not bot or not is_instance_valid(bot):
		return

	# Check if bot has spawns property
	if not "spawns" in bot:
		print("Bot %s has no spawns property!" % bot.name)
		return

	# Get a random spawn point
	if bot.spawns.size() > 0:
		var spawn_index: int = randi() % bot.spawns.size()
		var spawn_pos: Vector3 = bot.spawns[spawn_index]

		# Teleport bot
		bot.global_position = spawn_pos
		bot.linear_velocity = Vector3.ZERO
		bot.angular_velocity = Vector3.ZERO

		print("Bot %s teleported to spawn %d: %s" % [bot.name, spawn_index, spawn_pos])

func handle_unstuck_movement(delta: float) -> void:
	## Handle movement when bot is stuck - try to get unstuck
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

	# Use spin dash more often to break free - 50% charged for unstuck power
	if unstuck_timer > 0.3 and not bot.is_charging_spin and bot.spin_cooldown <= 0.0 and randf() < 0.25:
		bot.is_charging_spin = true
		bot.spin_charge = bot.max_spin_charge * 0.5  # 50% charge for unstuck power
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
			# Already throttled by the direction change logic (every 0.3 seconds)

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
