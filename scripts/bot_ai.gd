extends Node

## Bot AI Controller - PRODUCTION VERSION v2.0
## Final polish with comprehensive validation and advanced mechanics
##
## FIXES APPLIED (v1.0):
## 1. Removed ALL await statements that freeze bots
## 2. Fixed RigidBody3D rotation using angular_velocity
## 3. Added ability charging validation (Cannon doesn't support charging)
## 4. Fixed teleport to use world.spawns instead of bot.spawns
## 5. Added bounce attack support for vertical combat/mobility
## 6. Added rail grinding support (GRIND state)
## 7. Improved state transitions with better threat assessment
## 8. Better obstacle avoidance and pathfinding
## 9. Fixed stuck detection thresholds
## 10. Performance optimizations for HTML5
##
## IMPROVEMENTS (v2.0):
## 11. Comprehensive property validation for all mechanics
## 12. Cache filtering for invalid nodes
## 13. Rail curve handling (Path3D/Curve3D)
## 14. Lead prediction for Cannon projectiles
## 15. Dynamic player avoidance in movement
## 16. Better state priority (combat over grind)
## 17. Visibility checks for collection targets
## 18. Dead code cleanup (unused variables)

@export var target_player: Node = null
@export var wander_radius: float = 30.0
@export var aggro_range: float = 40.0
@export var attack_range: float = 12.0

var bot: Node = null
var state: String = "WANDER"  # WANDER, CHASE, ATTACK, COLLECT_ABILITY, COLLECT_ORB, RETREAT, GRIND
var wander_target: Vector3 = Vector3.ZERO
var wander_timer: float = 0.0
var action_timer: float = 0.0
var target_ability: Node = null
var target_orb: Node = null
var ability_check_timer: float = 0.0
var orb_check_timer: float = 0.0
var player_search_timer: float = 0.0

# Advanced AI variables
var strafe_direction: float = 1.0
var strafe_timer: float = 0.0
var retreat_timer: float = 0.0
var ability_charge_timer: float = 0.0
var is_charging_ability: bool = false
var aggression_level: float = 0.7  # Used for ability usage probability

# Obstacle detection variables
var stuck_timer: float = 0.0
var last_position: Vector3 = Vector3.ZERO
var stuck_check_interval: float = 0.3
var is_stuck: bool = false
var unstuck_timer: float = 0.0
var obstacle_avoid_direction: Vector3 = Vector3.ZERO
var obstacle_jump_timer: float = 0.0
var consecutive_stuck_checks: int = 0
const MAX_STUCK_ATTEMPTS: int = 10

# Target timeout variables
var target_stuck_timer: float = 0.0
var target_stuck_position: Vector3 = Vector3.ZERO
const TARGET_STUCK_TIMEOUT: float = 4.0

# NEW: Rail grinding support
var target_rail: Node = null
var rail_check_timer: float = 0.0
var grinding_timer: float = 0.0
const RAIL_SEARCH_INTERVAL: float = 1.5
const MAX_GRIND_TIME: float = 3.0

# NEW: Bounce attack support
var bounce_cooldown_timer: float = 0.0
const BOUNCE_COOLDOWN: float = 0.5

# Ability optimal ranges
const CANNON_OPTIMAL_RANGE: float = 15.0
const SWORD_OPTIMAL_RANGE: float = 3.5
const DASH_ATTACK_OPTIMAL_RANGE: float = 8.0
const EXPLOSION_OPTIMAL_RANGE: float = 6.0

# IMPROVED: Cached group queries with filtering
var cached_players: Array[Node] = []
var cached_abilities: Array[Node] = []
var cached_orbs: Array[Node] = []
var cached_rails: Array[Node] = []
var cache_refresh_timer: float = 0.0
const CACHE_REFRESH_INTERVAL: float = 0.5

# NEW: Player avoidance
var player_avoidance_timer: float = 0.0
const PLAYER_AVOIDANCE_CHECK_INTERVAL: float = 0.2

# NEW: Proactive edge avoidance
var edge_check_timer: float = 0.0
const EDGE_CHECK_INTERVAL: float = 0.3

func _ready() -> void:
	bot = get_parent()
	if not bot:
		print("ERROR: BotAI could not find parent bot!")
		return

	wander_target = bot.global_position
	last_position = bot.global_position
	target_stuck_position = bot.global_position

	# Randomize aggression for personality variety
	aggression_level = randf_range(0.5, 0.9)

	# Initial cache refresh
	call_deferred("refresh_cached_groups")
	call_deferred("find_target")

func _physics_process(delta: float) -> void:
	if not bot or not is_instance_valid(bot):
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
	rail_check_timer -= delta
	strafe_timer -= delta
	retreat_timer -= delta
	ability_charge_timer -= delta
	stuck_timer += delta
	unstuck_timer -= delta
	obstacle_jump_timer -= delta
	bounce_cooldown_timer -= delta
	player_search_timer -= delta
	grinding_timer += delta
	cache_refresh_timer -= delta
	player_avoidance_timer -= delta
	edge_check_timer -= delta

	# IMPROVED: Refresh cached groups with filtering
	if cache_refresh_timer <= 0.0:
		refresh_cached_groups()
		cache_refresh_timer = CACHE_REFRESH_INTERVAL

	# Check if bot is stuck on obstacles
	if stuck_timer >= stuck_check_interval:
		check_if_stuck()
		stuck_timer = 0.0

	# Handle unstuck behavior
	if is_stuck and unstuck_timer > 0.0:
		handle_unstuck_movement(delta)
		return

	# NEW: Proactive edge avoidance check
	if edge_check_timer <= 0.0:
		check_nearby_edges()
		edge_check_timer = EDGE_CHECK_INTERVAL

	# Check if bot is stuck trying to reach a target
	check_target_timeout(delta)

	# Find nearest player with caching
	if not target_player or not is_instance_valid(target_player) or player_search_timer <= 0.0:
		find_target()
		player_search_timer = 0.8

	# Check for abilities periodically
	if ability_check_timer <= 0.0:
		find_nearest_ability()
		ability_check_timer = 1.2

	# Check for orbs periodically
	if orb_check_timer <= 0.0:
		find_nearest_orb()
		orb_check_timer = 1.0

	# Check for rails periodically
	if rail_check_timer <= 0.0:
		find_nearest_rail()
		rail_check_timer = RAIL_SEARCH_INTERVAL

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
		"GRIND":
			do_grind(delta)

	# Check state transitions
	update_state()

func refresh_cached_groups() -> void:
	"""IMPROVED: Cache group queries with validity filtering"""
	# Filter out invalid nodes immediately
	cached_players = get_tree().get_nodes_in_group("players").filter(
		func(node): return is_instance_valid(node) and node.is_inside_tree()
	)
	cached_abilities = get_tree().get_nodes_in_group("ability_pickups").filter(
		func(node): return is_instance_valid(node) and node.is_inside_tree()
	)
	cached_orbs = get_tree().get_nodes_in_group("orbs").filter(
		func(node): return is_instance_valid(node) and node.is_inside_tree() and not ("is_collected" in node and node.is_collected)
	)
	cached_rails = get_tree().get_nodes_in_group("rails").filter(
		func(node): return is_instance_valid(node) and node.is_inside_tree()
	)

func update_state() -> void:
	"""IMPROVED: Better state prioritization with grind hysteresis"""

	# Priority 0: Exit grind if we've been on rail too long
	if state == "GRIND" and grinding_timer > MAX_GRIND_TIME:
		state = "WANDER"
		grinding_timer = 0.0
		exit_grind_safely()
		return

	# Check if we have a valid combat target
	var has_combat_target: bool = target_player and is_instance_valid(target_player)
	var distance_to_target: float = INF
	if has_combat_target:
		distance_to_target = bot.global_position.distance_to(target_player.global_position)

	# IMPROVED: Retreat at health <= 2, earlier escape
	if bot.health <= 2 and has_combat_target:
		if distance_to_target < aggro_range * 0.8:
			state = "RETREAT"
			retreat_timer = randf_range(2.5, 4.5)
			# IMPROVED: Use grind for escape if rail nearby
			if target_rail and is_instance_valid(target_rail):
				var dist_to_rail: float = bot.global_position.distance_to(get_rail_closest_point(target_rail))
				if dist_to_rail < 10.0:
					state = "GRIND"
					grinding_timer = 0.0
			return

	# Priority 1: CRITICAL - Get an ability if we don't have one
	if not bot.current_ability and target_ability and is_instance_valid(target_ability):
		var distance_to_ability: float = bot.global_position.distance_to(target_ability.global_position)
		# Don't suicide for abilities when enemy is very close
		if distance_to_ability < 60.0 and (not has_combat_target or distance_to_target > attack_range * 2.0):
			# IMPROVED: Visibility check
			if is_target_visible(target_ability.global_position):
				state = "COLLECT_ABILITY"
				return

	# Priority 2: COMBAT ALWAYS BEATS GRIND - Immediate combat if in attack range
	if bot.current_ability and has_combat_target and distance_to_target < attack_range * 1.2:
		state = "ATTACK"
		return

	# Priority 3: Collect orbs if safe
	if bot.level < bot.MAX_LEVEL and target_orb and is_instance_valid(target_orb):
		var distance_to_orb: float = bot.global_position.distance_to(target_orb.global_position)
		var orb_priority_range: float = 40.0
		if not has_combat_target or distance_to_target > aggro_range * 0.6:
			orb_priority_range = 50.0
		# Don't collect if enemy is attacking
		if distance_to_orb < orb_priority_range and (not has_combat_target or distance_to_target > attack_range * 2.5):
			# IMPROVED: Visibility check
			if is_target_visible(target_orb.global_position):
				state = "COLLECT_ORB"
				return

	# Priority 4: Chase if enemy in aggro range (BEATS GRIND)
	if bot.current_ability and has_combat_target and distance_to_target < aggro_range:
		state = "CHASE"
		return

	# Priority 5: GRIND ONLY when safe (no combat, for mobility)
	# IMPROVED: Use grind for vertical traversal when height diff large
	if target_rail and is_instance_valid(target_rail) and state != "GRIND":
		var rail_point: Vector3 = get_rail_closest_point(target_rail)
		var distance_to_rail: float = bot.global_position.distance_to(rail_point)
		var height_diff: float = rail_point.y - bot.global_position.y

		# Use rails when: not in combat OR enemy far + height advantage
		var should_grind: bool = false
		if not has_combat_target:
			should_grind = distance_to_rail < 15.0
		elif distance_to_target > aggro_range * 0.8 and height_diff > 5.0:
			# Use rail for vertical positioning advantage
			should_grind = distance_to_rail < 12.0

		if should_grind:
			state = "GRIND"
			grinding_timer = 0.0
			return

	# Priority 6: Combat if we HAVE an ability but enemy far
	if bot.current_ability and has_combat_target:
		if distance_to_target < attack_range * 1.2:
			state = "ATTACK"
		elif distance_to_target < aggro_range:
			state = "CHASE"
		else:
			state = "WANDER"
	else:
		state = "WANDER"

func do_wander(delta: float) -> void:
	"""Wander around while searching for targets"""
	if wander_timer <= 0.0:
		var angle: float = randf() * TAU
		var distance: float = randf_range(wander_radius * 0.5, wander_radius)
		wander_target = bot.global_position + Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		wander_timer = randf_range(2.5, 5.0)
		find_target()

	# Move with moderate speed
	move_towards(wander_target, 0.5)

	# Occasional jumps for variety
	if action_timer <= 0.0 and randf() < 0.12:
		bot_jump()
		action_timer = randf_range(1.2, 3.0)

func do_chase(delta: float) -> void:
	"""Chase target with tactical movement and facing"""
	if not target_player or not is_instance_valid(target_player):
		return

	var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)
	var height_diff: float = target_player.global_position.y - bot.global_position.y

	# Physics-safe rotation
	look_at_target_smooth(target_player.global_position, delta)

	# Determine optimal distance
	var optimal_distance: float = get_optimal_combat_distance()

	# Movement logic
	if distance_to_target > optimal_distance + 5.0:
		move_towards(target_player.global_position, 0.9)
	else:
		strafe_around_target(optimal_distance)

	# Use ability while chasing if in range
	if bot.current_ability and bot.current_ability.has_method("use"):
		use_ability_smart(distance_to_target)

	# Smart jumping for height differences
	if action_timer <= 0.0:
		if height_diff > 1.5:
			bot_jump()
			action_timer = randf_range(0.4, 0.7)
		elif height_diff > 0.7 and randf() < 0.6:
			bot_jump()
			action_timer = randf_range(0.5, 0.9)
		elif randf() < 0.2:
			bot_jump()
			action_timer = randf_range(0.6, 1.5)

	# NEW: Use bounce attack for vertical pursuit
	if height_diff < -2.0 and bounce_cooldown_timer <= 0.0 and randf() < 0.3:
		use_bounce_attack()

func do_attack(delta: float) -> void:
	"""Attack with smart positioning and ability usage"""
	if not target_player or not is_instance_valid(target_player):
		return

	var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)
	var height_diff: float = target_player.global_position.y - bot.global_position.y
	var optimal_distance: float = get_optimal_combat_distance()

	# Physics-safe rotation
	look_at_target_smooth(target_player.global_position, delta)

	# Tactical positioning
	if distance_to_target > optimal_distance + 2.0:
		move_towards(target_player.global_position, 0.7)
	elif distance_to_target < optimal_distance - 2.0:
		move_away_from(target_player.global_position, 0.5)
	else:
		strafe_around_target(optimal_distance)

	# Use ability intelligently
	if bot.current_ability and bot.current_ability.has_method("use"):
		use_ability_smart(distance_to_target)
	# Spin dash as mobility option
	elif action_timer <= 0.0 and validate_spin_dash_properties():
		if randf() < 0.12 * aggression_level and bot.spin_cooldown <= 0.0 and not bot.is_spin_dashing:
			initiate_spin_dash()
			action_timer = randf_range(2.5, 4.0)

	# Jump for height advantage
	if action_timer <= 0.0:
		if height_diff > 1.0:
			bot_jump()
			action_timer = randf_range(0.4, 0.8)
		elif height_diff > 0.5 and randf() < 0.5:
			bot_jump()
			action_timer = randf_range(0.5, 1.0)
		elif randf() < 0.15:
			bot_jump()
			action_timer = randf_range(0.5, 1.2)

	# NEW: Use bounce attack for aerial combat
	if height_diff > 1.5 and bounce_cooldown_timer <= 0.0 and randf() < 0.25 * aggression_level:
		use_bounce_attack()

func do_retreat(delta: float) -> void:
	"""Retreat from danger when low health"""
	if not target_player or not is_instance_valid(target_player) or retreat_timer <= 0.0:
		state = "WANDER"
		return

	# Move away from target
	move_away_from(target_player.global_position, 1.0)

	# Jump frequently to evade
	if action_timer <= 0.0 and randf() < 0.5:
		bot_jump()
		action_timer = randf_range(0.3, 0.7)

	# NEW: Use bounce attack for escape
	var height_diff: float = target_player.global_position.y - bot.global_position.y
	if height_diff < -2.0 and bounce_cooldown_timer <= 0.0 and randf() < 0.4:
		use_bounce_attack()

func do_collect_ability(delta: float) -> void:
	"""Move towards ability without await statements"""
	if not target_ability or not is_instance_valid(target_ability):
		target_ability = null
		state = "WANDER"
		return

	var distance: float = bot.global_position.distance_to(target_ability.global_position)
	var height_diff: float = target_ability.global_position.y - bot.global_position.y

	# Clear target by distance
	if distance < 2.5:
		if distance < 1.5:
			target_ability = null
		return

	# Move towards ability urgently
	move_towards(target_ability.global_position, 1.0)

	# Jump aggressively for elevated abilities
	if action_timer <= 0.0:
		if height_diff > 1.5:
			bot_jump()
			action_timer = randf_range(0.3, 0.5)
		elif height_diff > 0.7 or randf() < 0.4:
			bot_jump()
			action_timer = randf_range(0.4, 0.8)

func do_collect_orb(delta: float) -> void:
	"""Move towards orb without await statements"""
	if not target_orb or not is_instance_valid(target_orb):
		target_orb = null
		state = "WANDER"
		return

	# Check if collected by someone else
	if "is_collected" in target_orb and target_orb.is_collected:
		target_orb = null
		state = "WANDER"
		return

	var distance: float = bot.global_position.distance_to(target_orb.global_position)
	var height_diff: float = target_orb.global_position.y - bot.global_position.y

	# Clear target by distance
	if distance < 2.5:
		if distance < 1.5:
			target_orb = null
		return

	# Move towards orb
	move_towards(target_orb.global_position, 1.0)

	# Jump for elevated orbs
	if action_timer <= 0.0:
		if height_diff > 1.5:
			bot_jump()
			action_timer = randf_range(0.3, 0.5)
		elif height_diff > 0.7 or randf() < 0.35:
			bot_jump()
			action_timer = randf_range(0.4, 0.8)

func do_grind(delta: float) -> void:
	"""IMPROVED: Rail grinding with proper curve handling"""
	if not target_rail or not is_instance_valid(target_rail):
		state = "WANDER"
		grinding_timer = 0.0
		return

	# IMPROVED: Get closest point on rail curve
	var rail_point: Vector3 = get_rail_closest_point(target_rail)
	var distance_to_rail: float = bot.global_position.distance_to(rail_point)

	# If we're on the rail, let player.gd handle grinding
	if distance_to_rail < 3.0:
		# Bot is grinding, check if we should exit
		if grinding_timer > MAX_GRIND_TIME or randf() < 0.02:
			state = "WANDER"
			grinding_timer = 0.0
			exit_grind_safely()
			return
	else:
		# Move towards rail to start grinding
		move_towards(rail_point, 0.8)

		# Jump to reach rail if needed
		if action_timer <= 0.0 and randf() < 0.5:
			bot_jump()
			action_timer = randf_range(0.4, 0.8)

func strafe_around_target(preferred_distance: float) -> void:
	"""Strafe around target while maintaining distance"""
	if not target_player or not is_instance_valid(target_player):
		return

	# Change strafe direction periodically
	if strafe_timer <= 0.0:
		strafe_direction *= -1
		strafe_timer = randf_range(1.2, 2.8)

	# Calculate strafe direction
	var to_target: Vector3 = (target_player.global_position - bot.global_position).normalized()
	to_target.y = 0

	# Perpendicular vector for strafing
	var strafe_vec: Vector3 = Vector3(-to_target.z, 0, to_target.x) * strafe_direction

	# Combine forward/backward with strafing
	var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)
	var distance_adjustment: Vector3 = Vector3.ZERO

	if distance_to_target > preferred_distance + 1.0:
		distance_adjustment = to_target * 0.5
	elif distance_to_target < preferred_distance - 1.0:
		distance_adjustment = -to_target * 0.5

	# Apply combined movement
	var movement: Vector3 = (strafe_vec * 0.7 + distance_adjustment).normalized()
	if movement.length() > 0.1:
		# EDGE DETECTION FIX: Check for edges before strafing
		if check_for_edge(movement, 4.0):
			# Edge detected! Reverse strafe direction and apply braking
			strafe_direction *= -1
			movement = -movement  # Move away from edge
			# Apply braking force to reduce momentum
			if "linear_velocity" in bot:
				var braking_force: Vector3 = -bot.linear_velocity * 0.8
				braking_force.y = 0
				bot.apply_central_force(braking_force)
			return

		var force: float = bot.current_roll_force * 0.75
		bot.apply_central_force(movement * force)

func move_away_from(target_pos: Vector3, speed_mult: float = 1.0) -> void:
	"""Move bot away from a target position"""
	if not bot:
		return

	var direction: Vector3 = (bot.global_position - target_pos).normalized()
	direction.y = 0

	if direction.length() > 0.1:
		# EDGE DETECTION FIX: Check for edges when retreating
		if check_for_edge(direction, 4.0):
			# Edge detected while retreating! Find safe direction
			var safe_direction: Vector3 = find_safe_direction_from_edge(direction)
			if safe_direction != Vector3.ZERO:
				direction = safe_direction
				speed_mult *= 0.5  # Slow down near edges
			else:
				# No safe direction, stop and apply braking
				if "linear_velocity" in bot:
					var braking_force: Vector3 = -bot.linear_velocity * 1.2
					braking_force.y = 0
					bot.apply_central_force(braking_force)
				return

		var force: float = bot.current_roll_force * speed_mult
		bot.apply_central_force(direction * force)

func get_optimal_combat_distance() -> float:
	"""Get optimal combat distance based on current ability"""
	if not bot.current_ability:
		return DASH_ATTACK_OPTIMAL_RANGE

	if not "ability_name" in bot.current_ability:
		return 12.0

	var ability_name: String = bot.current_ability.ability_name

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
			return 12.0

func use_ability_smart(distance_to_target: float) -> void:
	"""IMPROVED: Smart ability usage with lead prediction for Cannon"""
	if not bot.current_ability or not bot.current_ability.has_method("is_ready"):
		is_charging_ability = false
		return

	if not bot.current_ability.is_ready():
		is_charging_ability = false
		return

	if not "ability_name" in bot.current_ability:
		return

	var ability_name: String = bot.current_ability.ability_name
	var should_use: bool = false
	var should_charge: bool = false

	# Check if ability supports charging
	var can_charge: bool = false
	if "supports_charging" in bot.current_ability:
		can_charge = bot.current_ability.supports_charging and bot.current_ability.max_charge_time > 0.1
	elif bot.current_ability.has_method("start_charge"):
		can_charge = true

	# IMPROVED: Ability-specific logic with lead prediction
	match ability_name:
		"Cannon":
			# IMPROVED: Lead prediction for moving targets
			if target_player and is_instance_valid(target_player):
				var predicted_distance: float = calculate_lead_distance()
				if predicted_distance > 4.0 and predicted_distance < 40.0:
					should_use = randf() < (0.7 + aggression_level * 0.3)  # Use aggression
					should_charge = false  # Never charge cannon
			elif distance_to_target > 4.0 and distance_to_target < 40.0:
				should_use = randf() < 0.6
				should_charge = false
		"Sword":
			if distance_to_target < 6.0:
				should_use = randf() < (0.6 + aggression_level * 0.4)
				should_charge = can_charge and distance_to_target > 3.0 and randf() < (0.3 + aggression_level * 0.2)
		"Dash Attack":
			if distance_to_target > 4.0 and distance_to_target < 18.0:
				should_use = randf() < (0.5 + aggression_level * 0.3)
				should_charge = can_charge and distance_to_target > 8.0 and randf() < (0.4 + aggression_level * 0.2)
		"Explosion":
			if distance_to_target < 10.0:
				should_use = randf() < (0.5 + aggression_level * 0.4)
				should_charge = can_charge and distance_to_target < 7.0 and randf() < (0.4 + aggression_level * 0.2)
		_:
			if distance_to_target < 20.0:
				should_use = randf() < 0.5

	# Charging logic
	if should_use and should_charge and can_charge and not is_charging_ability:
		if bot.current_ability.has_method("start_charge"):
			is_charging_ability = true
			ability_charge_timer = randf_range(0.6, 1.3)
			bot.current_ability.start_charge()

	# Release charged ability or use instantly
	if is_charging_ability and ability_charge_timer <= 0.0:
		is_charging_ability = false
		if bot.current_ability.has_method("release_charge"):
			bot.current_ability.release_charge()
		else:
			bot.current_ability.use()
		action_timer = randf_range(0.4, 1.2)
	elif should_use and not should_charge and not is_charging_ability:
		bot.current_ability.use()
		action_timer = randf_range(0.6, 1.5)

func calculate_lead_distance() -> float:
	"""NEW: Calculate distance for lead prediction (Cannon projectiles)"""
	if not target_player or not is_instance_valid(target_player):
		return INF

	# Get target velocity
	var target_velocity: Vector3 = Vector3.ZERO
	if "linear_velocity" in target_player:
		target_velocity = target_player.linear_velocity

	# Skip lead if target not moving much
	if target_velocity.length() < 2.0:
		return bot.global_position.distance_to(target_player.global_position)

	# Simple lead prediction: assume projectile speed ~80 (Cannon speed)
	var projectile_speed: float = 80.0
	var current_distance: float = bot.global_position.distance_to(target_player.global_position)
	var time_to_hit: float = current_distance / projectile_speed

	# Predict target position
	var predicted_pos: Vector3 = target_player.global_position + target_velocity * time_to_hit * 0.5  # 50% prediction

	return bot.global_position.distance_to(predicted_pos)

func move_towards(target_pos: Vector3, speed_mult: float = 1.0) -> void:
	"""IMPROVED: Move bot towards target with obstacle and player avoidance"""
	if not bot:
		return

	var direction: Vector3 = (target_pos - bot.global_position).normalized()
	direction.y = 0

	var height_diff: float = target_pos.y - bot.global_position.y

	if direction.length() > 0.1:
		# NEW: Player avoidance - check for nearby players
		if player_avoidance_timer <= 0.0:
			var avoidance_force: Vector3 = get_player_avoidance_force()
			if avoidance_force.length() > 0.1:
				direction = (direction * 0.7 + avoidance_force * 0.3).normalized()
			player_avoidance_timer = PLAYER_AVOIDANCE_CHECK_INTERVAL

		# Check for dangerous edges (IMPROVED: increased distance and better braking)
		if check_for_edge(direction, 4.0):
			var safe_direction: Vector3 = find_safe_direction_from_edge(direction)
			if safe_direction != Vector3.ZERO:
				direction = safe_direction
				speed_mult *= 0.5  # Slow down more near edges
			else:
				# No safe direction found - apply emergency braking!
				if "linear_velocity" in bot:
					var braking_force: Vector3 = -bot.linear_velocity * 1.5
					braking_force.y = 0
					bot.apply_central_force(braking_force)
				# Also apply backward force
				bot.apply_central_force(-direction * bot.current_roll_force * 1.2)
				return

		# Check for obstacles
		var obstacle_info: Dictionary = check_obstacle_in_direction(direction, 2.5)

		if obstacle_info.has_obstacle:
			# Handle slopes/platforms - jump onto them
			if obstacle_info.is_slope or obstacle_info.is_platform:
				if obstacle_jump_timer <= 0.0:
					bot_jump()
					obstacle_jump_timer = 0.3
					bot.apply_central_force(direction * bot.current_roll_force * speed_mult * 1.2)
					return
				else:
					bot.apply_central_force(direction * bot.current_roll_force * speed_mult)
					return

			# Handle walls - back up or jump
			if "is_wall" in obstacle_info and obstacle_info.is_wall:
				if obstacle_info.can_jump and obstacle_jump_timer <= 0.0:
					bot_jump()
					obstacle_jump_timer = 0.5
				else:
					direction = -direction
					speed_mult *= 0.5
			else:
				if obstacle_info.can_jump and obstacle_jump_timer <= 0.0:
					bot_jump()
					obstacle_jump_timer = 0.4
				else:
					direction = -direction
					speed_mult *= 0.5

		# Jump for elevated targets
		elif height_diff > 1.5 and obstacle_jump_timer <= 0.0 and randf() < 0.5:
			bot_jump()
			obstacle_jump_timer = 0.5

		# Apply movement force
		var force: float = bot.current_roll_force * speed_mult
		bot.apply_central_force(direction * force)

func get_player_avoidance_force() -> Vector3:
	"""NEW: Calculate avoidance force to prevent player clumping"""
	var avoidance: Vector3 = Vector3.ZERO
	var avoidance_radius: float = 3.0  # Meters to avoid

	for player in cached_players:
		if player == bot or not is_instance_valid(player):
			continue

		var to_player: Vector3 = player.global_position - bot.global_position
		var distance: float = to_player.length()

		if distance < avoidance_radius and distance > 0.1:
			# Repel from player (inverse square)
			var repel_strength: float = (avoidance_radius - distance) / avoidance_radius
			avoidance += -to_player.normalized() * repel_strength

	return avoidance.normalized()

func check_nearby_edges() -> void:
	"""NEW: Proactively check for nearby edges and apply corrective force"""
	if not bot or not "linear_velocity" in bot:
		return

	# Check in all cardinal directions for nearby edges
	var directions_to_check: Array = [
		Vector3.FORWARD,
		Vector3.BACK,
		Vector3.LEFT,
		Vector3.RIGHT
	]

	var safe_direction: Vector3 = Vector3.ZERO
	var closest_edge_distance: float = INF

	for dir in directions_to_check:
		# Rotate direction based on bot's facing
		var world_dir: Vector3 = dir.rotated(Vector3.UP, bot.rotation.y)
		world_dir.y = 0

		# Check if there's an edge in this direction
		if check_for_edge(world_dir, 3.5):
			# Edge detected in this direction
			var edge_distance: float = 3.5  # Approximate distance

			if edge_distance < closest_edge_distance:
				closest_edge_distance = edge_distance
				# Safe direction is opposite to the edge
				safe_direction = -world_dir

	# If we found an edge nearby and bot is moving, apply corrective force
	if safe_direction != Vector3.ZERO and bot.linear_velocity.length() > 1.0:
		var horizontal_velocity: Vector3 = Vector3(bot.linear_velocity.x, 0, bot.linear_velocity.z)

		# Check if bot is moving toward the edge
		var velocity_dir: Vector3 = horizontal_velocity.normalized()
		var dot_to_edge: float = velocity_dir.dot(-safe_direction)

		if dot_to_edge > 0.3:  # Moving toward edge
			# Apply corrective force away from edge
			var corrective_force: Vector3 = safe_direction * bot.current_roll_force * 0.4
			bot.apply_central_force(corrective_force)

			# Also apply braking if moving fast toward edge
			if horizontal_velocity.length() > 5.0:
				var braking_force: Vector3 = -horizontal_velocity * 0.5
				bot.apply_central_force(braking_force)

func bot_jump() -> void:
	"""Make bot jump"""
	if not bot or not "jump_count" in bot:
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

func use_bounce_attack() -> void:
	"""IMPROVED: Use bounce attack with comprehensive validation"""
	if not bot or bounce_cooldown_timer > 0.0:
		return

	# Comprehensive validation
	if not bot.has_method("bounce_attack"):
		return

	# IMPROVED: Check required properties exist
	if not ("linear_velocity" in bot and "jump_count" in bot):
		return

	# Trigger bounce attack
	bot.bounce_attack()
	bounce_cooldown_timer = BOUNCE_COOLDOWN

func validate_spin_dash_properties() -> bool:
	"""IMPROVED: Comprehensive spin dash validation"""
	if not bot or not bot.has_method("execute_spin_dash"):
		return false

	# Check all required properties exist
	var required_props: Array = ["is_charging_spin", "spin_cooldown", "is_spin_dashing", "spin_charge", "max_spin_charge"]
	for prop in required_props:
		if not prop in bot:
			return false

	return true

func initiate_spin_dash() -> void:
	"""Initiate spin dash without await in callback"""
	if not validate_spin_dash_properties():
		return

	# Start charging
	bot.is_charging_spin = true
	bot.spin_charge = randf_range(0.4, bot.max_spin_charge * 0.7)

	# Schedule release WITHOUT await
	var release_time: float = randf_range(0.25, 0.6)
	var timer: SceneTreeTimer = get_tree().create_timer(release_time)

	# Use lambda without await
	timer.timeout.connect(func():
		if bot and is_instance_valid(bot) and "is_charging_spin" in bot:
			bot.is_charging_spin = false
			if bot.has_method("execute_spin_dash"):
				bot.execute_spin_dash()
	)

func exit_grind_safely() -> void:
	"""IMPROVED: Safe grind exit with validation"""
	if not bot:
		return

	if bot.has_method("exit_grind"):
		bot.exit_grind()

func look_at_target_smooth(target_position: Vector3, delta: float) -> void:
	"""Physics-safe rotation for RigidBody3D using angular velocity"""
	if not bot:
		return

	var target_dir: Vector3 = target_position - bot.global_position
	target_dir.y = 0

	if target_dir.length() < 0.1:
		return

	var desired_angle: float = atan2(target_dir.x, target_dir.z)
	var current_angle: float = bot.rotation.y

	var angle_diff: float = desired_angle - current_angle

	# Normalize angle to [-PI, PI]
	while angle_diff > PI:
		angle_diff -= TAU
	while angle_diff < -PI:
		angle_diff += TAU

	# Use angular_velocity for physics-safe rotation
	var rotation_speed: float = 8.0
	var target_angular_velocity: float = angle_diff * rotation_speed

	target_angular_velocity = clamp(target_angular_velocity, -12.0, 12.0)

	bot.angular_velocity.y = target_angular_velocity

func get_rail_closest_point(rail: Node) -> Vector3:
	"""IMPROVED: Get closest point on rail curve (Path3D/Curve3D)"""
	if not rail or not is_instance_valid(rail):
		return bot.global_position if bot else Vector3.ZERO

	# Check if rail is Path3D with curve
	if rail is Path3D and rail.curve:
		var local_pos: Vector3 = rail.to_local(bot.global_position)
		var closest_offset: float = rail.curve.get_closest_offset(local_pos)
		var closest_point_local: Vector3 = rail.curve.sample_baked(closest_offset)
		return rail.to_global(closest_point_local)

	# Fallback to rail position
	return rail.global_position

func is_target_visible(target_pos: Vector3) -> bool:
	"""NEW: Check if target is visible (raycast line-of-sight)"""
	if not bot:
		return false

	var space_state: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state
	var start: Vector3 = bot.global_position + Vector3.UP * 0.5
	var end: Vector3 = target_pos

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, end)
	query.exclude = [bot]
	query.collision_mask = 1  # Only world geometry blocks

	var result: Dictionary = space_state.intersect_ray(query)

	# Visible if no hit or hit is very close to target (within pickup range)
	if not result:
		return true

	var hit_distance: float = start.distance_to(result.position)
	var target_distance: float = start.distance_to(target_pos)

	return hit_distance >= target_distance - 1.0

func find_target() -> void:
	"""Find nearest player using cached groups"""
	var closest_player: Node = null
	var closest_distance: float = INF

	for player in cached_players:
		if player == bot or not is_instance_valid(player):
			continue

		var distance: float = bot.global_position.distance_to(player.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_player = player

	target_player = closest_player

func find_nearest_ability() -> void:
	"""IMPROVED: Find nearest visible ability"""
	var closest_ability: Node = null
	var closest_distance: float = INF

	for ability in cached_abilities:
		if not is_instance_valid(ability):
			continue

		var distance: float = bot.global_position.distance_to(ability.global_position)
		if distance < closest_distance:
			# Prefer visible abilities
			if is_target_visible(ability.global_position) or distance < 20.0:
				closest_distance = distance
				closest_ability = ability

	target_ability = closest_ability

func find_nearest_orb() -> void:
	"""IMPROVED: Find nearest visible orb"""
	var closest_orb: Node = null
	var closest_distance: float = INF

	for orb in cached_orbs:
		if not is_instance_valid(orb):
			continue
		if "is_collected" in orb and orb.is_collected:
			continue

		var distance: float = bot.global_position.distance_to(orb.global_position)
		if distance < closest_distance:
			# Prefer visible orbs
			if is_target_visible(orb.global_position) or distance < 15.0:
				closest_distance = distance
				closest_orb = orb

	target_orb = closest_orb

func find_nearest_rail() -> void:
	"""IMPROVED: Find nearest rail with curve-aware distance"""
	var closest_rail: Node = null
	var closest_distance: float = INF

	for rail in cached_rails:
		if not is_instance_valid(rail):
			continue

		var rail_point: Vector3 = get_rail_closest_point(rail)
		var distance: float = bot.global_position.distance_to(rail_point)
		if distance < closest_distance and distance < 20.0:
			closest_distance = distance
			closest_rail = rail

	target_rail = closest_rail

## ============================================================================
## OBSTACLE DETECTION AND AVOIDANCE
## ============================================================================

func check_for_edge(direction: Vector3, check_distance: float = 4.0) -> bool:
	"""IMPROVED: Check for dangerous edge/drop-off with momentum compensation"""
	if not bot:
		return false

	var space_state: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state

	# Check current ground level
	var current_ground_check: Vector3 = bot.global_position + Vector3.UP * 0.5
	var current_ground_end: Vector3 = bot.global_position + Vector3.DOWN * 3.0

	var current_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(current_ground_check, current_ground_end)
	current_query.exclude = [bot]
	current_query.collision_mask = 1

	var current_result: Dictionary = space_state.intersect_ray(current_query)

	if not current_result:
		return false

	var current_ground_y: float = current_result.position.y

	# IMPROVED: Increase check distance based on bot's velocity (momentum compensation)
	var velocity_multiplier: float = 1.0
	if "linear_velocity" in bot:
		var horizontal_speed: float = Vector2(bot.linear_velocity.x, bot.linear_velocity.z).length()
		velocity_multiplier = 1.0 + min(horizontal_speed / 20.0, 1.5)  # Up to 2.5x for fast bots

	var adjusted_check_distance: float = check_distance * velocity_multiplier

	# Check ahead for edges
	var forward_point: Vector3 = bot.global_position + direction.normalized() * adjusted_check_distance
	var ray_start: Vector3 = forward_point + Vector3.UP * 0.5
	var ray_end: Vector3 = forward_point + Vector3.DOWN * 10.0

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [bot]
	query.collision_mask = 1

	var result: Dictionary = space_state.intersect_ray(query)

	if not result:
		return true

	var ahead_ground_y: float = result.position.y
	var ground_drop: float = current_ground_y - ahead_ground_y

	# IMPROVED: Lower threshold from 4.5 to 3.0 for more sensitive edge detection
	return ground_drop > 3.0

func find_safe_direction_from_edge(dangerous_direction: Vector3) -> Vector3:
	"""Find safe direction away from edge"""
	if not bot:
		return Vector3.ZERO

	var angles_to_try: Array = [90, -90, 120, -120, 150, -150, 180]

	for angle_deg in angles_to_try:
		var test_direction: Vector3 = dangerous_direction.rotated(Vector3.UP, deg_to_rad(angle_deg))
		if not check_for_edge(test_direction, 2.0):
			var obstacle_check: Dictionary = check_obstacle_in_direction(test_direction, 2.0)
			if not obstacle_check.has_obstacle or obstacle_check.can_jump:
				return test_direction

	return Vector3.ZERO

func check_obstacle_in_direction(direction: Vector3, check_distance: float = 2.5) -> Dictionary:
	"""Check for obstacle using multiple raycasts"""
	if not bot:
		return {"has_obstacle": false, "can_jump": false, "is_slope": false, "is_platform": false, "is_wall": false}

	var space_state: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state

	# Optimized for HTML5: 4 raycasts instead of 6
	var check_heights: Array = [0.2, 0.5, 1.0, 1.8]
	var obstacle_detected: bool = false
	var closest_hit: Vector3 = Vector3.ZERO
	var lowest_obstacle_height: float = INF
	var highest_obstacle_height: float = -INF
	var hit_count: int = 0

	for height in check_heights:
		var start_pos: Vector3 = bot.global_position + Vector3.UP * height
		var end_pos: Vector3 = start_pos + direction * check_distance

		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
		query.exclude = [bot]
		query.collision_mask = 1

		var result: Dictionary = space_state.intersect_ray(query)

		if result:
			obstacle_detected = true
			hit_count += 1
			var hit_point: Vector3 = result.position
			var obstacle_height: float = hit_point.y - bot.global_position.y

			if obstacle_height < lowest_obstacle_height:
				lowest_obstacle_height = obstacle_height
				closest_hit = hit_point
			if obstacle_height > highest_obstacle_height:
				highest_obstacle_height = obstacle_height

	if obstacle_detected:
		var is_slope: bool = false
		var is_platform: bool = false
		var is_wall: bool = false

		# Detect obstacle type
		var height_diff: float = highest_obstacle_height - lowest_obstacle_height
		if height_diff > 0.4:
			is_slope = true
		if lowest_obstacle_height > 0.3 and lowest_obstacle_height < 2.5:
			is_platform = true
		if hit_count >= check_heights.size() - 1:
			is_wall = true

		# Determine if bot can jump over
		var can_jump: bool = false

		if is_slope or is_platform:
			can_jump = lowest_obstacle_height < 4.0 and lowest_obstacle_height > -0.5
		elif is_wall:
			can_jump = lowest_obstacle_height < 2.0 and lowest_obstacle_height > -0.5
		else:
			can_jump = lowest_obstacle_height < 2.5 and lowest_obstacle_height > -0.5

		return {
			"has_obstacle": true,
			"can_jump": can_jump,
			"is_slope": is_slope,
			"is_platform": is_platform,
			"is_wall": is_wall,
			"hit_point": closest_hit,
			"obstacle_height": lowest_obstacle_height
		}

	return {"has_obstacle": false, "can_jump": false, "is_slope": false, "is_platform": false, "is_wall": false}

func check_target_timeout(delta: float) -> void:
	"""Check if bot is stuck trying to reach target"""
	if not bot:
		return

	if state in ["COLLECT_ABILITY", "COLLECT_ORB", "CHASE", "ATTACK"]:
		var current_pos: Vector3 = bot.global_position
		var distance_moved: float = current_pos.distance_to(target_stuck_position)

		if distance_moved < 0.8:
			target_stuck_timer += delta

			if target_stuck_timer >= TARGET_STUCK_TIMEOUT:
				# Abandon target
				if state == "COLLECT_ABILITY":
					target_ability = null
				elif state == "COLLECT_ORB":
					target_orb = null
				elif state in ["CHASE", "ATTACK"]:
					find_target()

				target_stuck_timer = 0.0
				state = "WANDER"
		else:
			target_stuck_timer = 0.0
			target_stuck_position = current_pos
	else:
		target_stuck_timer = 0.0
		target_stuck_position = bot.global_position

func check_if_stuck() -> void:
	"""Better stuck detection with improved thresholds"""
	if not bot:
		return

	var current_pos: Vector3 = bot.global_position
	var distance_moved: float = current_pos.distance_to(last_position)

	var is_trying_to_move: bool = state in ["CHASE", "ATTACK", "COLLECT_ABILITY", "COLLECT_ORB", "GRIND"]

	if distance_moved < 0.25 and is_trying_to_move:
		consecutive_stuck_checks += 1

		# EMERGENCY: Teleport if stuck too long
		if consecutive_stuck_checks >= MAX_STUCK_ATTEMPTS:
			teleport_to_safe_position()
			consecutive_stuck_checks = 0
			is_stuck = false
			return

		# Trigger stuck state after 3 checks
		if consecutive_stuck_checks >= 3 and not is_stuck:
			is_stuck = true
			unstuck_timer = randf_range(1.2, 2.2)

			# Move opposite to current facing
			var opposite_dir: Vector3 = Vector3(-sin(bot.rotation.y), 0, -cos(bot.rotation.y))

			if is_stuck_under_terrain():
				var random_side: float = 1.0 if randf() > 0.5 else -1.0
				var perpendicular: Vector3 = Vector3(-sin(bot.rotation.y), 0, cos(bot.rotation.y)) * random_side
				obstacle_avoid_direction = (opposite_dir + perpendicular).normalized()
			else:
				obstacle_avoid_direction = opposite_dir
	else:
		if distance_moved > 0.5:
			consecutive_stuck_checks = 0
			is_stuck = false

	last_position = current_pos

func is_stuck_under_terrain() -> bool:
	"""Check if stuck under terrain/slope"""
	if not bot:
		return false

	var space_state: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state

	var ray_start: Vector3 = bot.global_position + Vector3.UP * 0.5
	var ray_end: Vector3 = bot.global_position + Vector3.UP * 2.5

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [bot]
	query.collision_mask = 1

	var result: Dictionary = space_state.intersect_ray(query)

	return result.size() > 0

func teleport_to_safe_position() -> void:
	"""Teleport using world.spawns instead of bot.spawns"""
	if not bot or not is_instance_valid(bot):
		return

	var world: Node = get_tree().get_root().get_node_or_null("World")
	if not world:
		return

	# Try to get spawns from level generator
	var spawns: Array = []
	var level_gen = world.get_node_or_null("LevelGenerator")
	if level_gen and "spawn_points" in level_gen:
		spawns = level_gen.spawn_points
	elif "spawns" in world:
		spawns = world.spawns
	elif "spawns" in bot:
		spawns = bot.spawns

	if spawns.size() > 0:
		var spawn_index: int = randi() % spawns.size()
		var spawn_pos: Vector3 = spawns[spawn_index]

		bot.global_position = spawn_pos
		bot.linear_velocity = Vector3.ZERO
		bot.angular_velocity = Vector3.ZERO

		print("[BotAI] Emergency teleport for ", bot.name, " to ", spawn_pos)

func handle_unstuck_movement(delta: float) -> void:
	"""Handle movement when stuck"""
	if not bot:
		return

	var under_terrain: bool = is_stuck_under_terrain()

	# Apply unstuck force
	var force: float = bot.current_roll_force * 1.5
	bot.apply_central_force(obstacle_avoid_direction * force)

	# Jump frequently (more aggressive if under terrain)
	var jump_chance: float = 0.75 if under_terrain else 0.55
	if "jump_count" in bot and "max_jumps" in bot:
		if bot.jump_count < bot.max_jumps and randf() < jump_chance:
			bot_jump()

	# Use spin dash to break free
	if unstuck_timer > 0.4 and validate_spin_dash_properties():
		if not bot.is_charging_spin and bot.spin_cooldown <= 0.0 and randf() < 0.2:
			initiate_spin_dash()

	# IMPROVED: Try grind if stuck near rail
	if target_rail and is_instance_valid(target_rail) and randf() < 0.15:
		var rail_point: Vector3 = get_rail_closest_point(target_rail)
		var dist_to_rail: float = bot.global_position.distance_to(rail_point)
		if dist_to_rail < 8.0:
			# Try grinding to escape
			state = "GRIND"
			grinding_timer = 0.0
			is_stuck = false
			unstuck_timer = 0.0
			consecutive_stuck_checks = 0
			return

	# Change direction periodically
	var time_slot: int = int(unstuck_timer * 10)
	if time_slot % 4 == 0 and time_slot != int((unstuck_timer + delta) * 10) % 4:
		var new_angle: float = randf() * TAU
		obstacle_avoid_direction = Vector3(cos(new_angle), 0, sin(new_angle))

	# Try moving backward
	if randf() < 0.12:
		bot.apply_central_force(-obstacle_avoid_direction * force * 0.5)

	# Exit unstuck mode
	if unstuck_timer <= 0.0:
		is_stuck = false
		unstuck_timer = 0.0
		consecutive_stuck_checks = 0

		if state in ["CHASE", "ATTACK"]:
			var escape_angle: float = randf() * TAU
			var escape_distance: float = randf_range(12.0, 22.0)
			wander_target = bot.global_position + Vector3(cos(escape_angle) * escape_distance, 0, sin(escape_angle) * escape_distance)
			state = "WANDER"
			wander_timer = randf_range(2.5, 4.5)
