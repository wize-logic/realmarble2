extends "res://scripts/bot_ai.gd"

## Bot AI Controller - TYPE A (Sonic-Style Arenas)
## Extends base BotAI with rail grinding system
## Optimized for Type A levels: rail grinding, ramps, slopes, vertical mobility

# ============================================================================
# RAIL GRINDING SYSTEM (Sonic-style)
# ============================================================================

var is_grinding: bool = false
var current_rail: GrindRail = null
var cached_rails: Array[GrindRail] = []
var target_rail: GrindRail = null
var rail_check_timer: float = 0.0
var rail_attach_cooldown: float = 0.0
var movement_input_direction: Vector3 = Vector3.ZERO

const RAIL_CHECK_INTERVAL: float = 2.0
const MAX_CACHED_RAILS: int = 12
const MAX_RAIL_DISTANCE: float = 50.0
const RAIL_ATTACH_COOLDOWN_TIME: float = 2.0

# Rail launch recovery system
var post_rail_launch: bool = false
var rail_launch_timer: float = 0.0
var safe_landing_target: Vector3 = Vector3.ZERO
const RAIL_LAUNCH_RECOVERY_TIME: float = 6.0
const SAFE_LANDING_SEARCH_RADIUS: float = 50.0

# ============================================================================
# OVERRIDES
# ============================================================================

func get_ai_type() -> String:
	return "Type A"

func _ready() -> void:
	super._ready()
	rail_check_timer = randf_range(0.0, RAIL_CHECK_INTERVAL)

func update_timers(delta: float) -> void:
	super.update_timers(delta)
	rail_check_timer -= delta
	rail_attach_cooldown -= delta
	rail_launch_timer += delta

func setup_arena_specific_caches() -> void:
	"""Cache rails for Type A arenas"""
	refresh_rail_cache()

func consider_arena_specific_navigation() -> void:
	"""Check for rail navigation opportunities"""
	# RAIL LAUNCH RECOVERY: Handle aerial navigation after rail launch (highest priority)
	if post_rail_launch:
		return  # Handled in custom _physics_process override

	# Check for rails periodically
	if rail_check_timer <= 0.0:
		consider_rail_navigation()
		rail_check_timer = RAIL_CHECK_INTERVAL

func handle_arena_specific_state_updates() -> void:
	"""No special state updates needed for Type A"""
	pass

# ============================================================================
# PHYSICS PROCESS OVERRIDE (for rail launch recovery)
# ============================================================================

func _physics_process(delta: float) -> void:
	if not bot or not is_instance_valid(bot):
		return

	var world: Node = get_tree().get_root().get_node_or_null("World")
	if not world or not world.game_active:
		return

	# RAIL LAUNCH RECOVERY: Override all AI while recovering from rail launch
	if post_rail_launch:
		update_timers(delta)
		handle_post_rail_launch_navigation(delta)
		return

	# Normal AI processing
	super._physics_process(delta)

# ============================================================================
# RAIL CACHING
# ============================================================================

func refresh_rail_cache() -> void:
	"""Cache nearby rails for performance"""
	cached_rails.clear()

	if not bot:
		return

	# Find all rails via group query (O(1) vs recursive DFS)
	var all_rails: Array[GrindRail] = []
	for node in get_tree().get_nodes_in_group("grind_rails"):
		if node is GrindRail:
			all_rails.append(node as GrindRail)
	var bot_pos: Vector3 = bot.global_position

	# Filter rails by distance
	for rail in all_rails:
		if not is_instance_valid(rail) or not rail.is_inside_tree():
			continue

		# Check if rail has a valid curve
		if not rail.curve or rail.curve.get_baked_length() <= 0:
			continue

		# Get closest point on rail
		var local_pos: Vector3 = rail.to_local(bot_pos)
		var closest_offset: float = rail.curve.get_closest_offset(local_pos)
		var closest_point: Vector3 = rail.to_global(rail.curve.sample_baked(closest_offset))
		var distance: float = bot_pos.distance_to(closest_point)

		# Only cache nearby rails
		if distance <= MAX_RAIL_DISTANCE:
			cached_rails.append(rail)

	# Limit cache size
	if cached_rails.size() > MAX_CACHED_RAILS:
		cached_rails.sort_custom(func(a, b):
			var dist_a: float = bot.global_position.distance_to(_get_closest_rail_point(a))
			var dist_b: float = bot.global_position.distance_to(_get_closest_rail_point(b))
			return dist_a < dist_b
		)
		cached_rails = cached_rails.slice(0, MAX_CACHED_RAILS)

func find_all_rails(node: Node) -> Array[GrindRail]:
	"""Recursively find all GrindRail nodes in the scene"""
	var rails: Array[GrindRail] = []

	if node is GrindRail:
		rails.append(node as GrindRail)

	for child in node.get_children():
		rails.append_array(find_all_rails(child))

	return rails

func _get_closest_rail_point(rail: GrindRail) -> Vector3:
	"""Helper: Get closest point on rail to bot"""
	if not rail or not rail.curve or rail.curve.get_baked_length() <= 0:
		return Vector3.ZERO

	var local_pos: Vector3 = rail.to_local(bot.global_position)
	var closest_offset: float = rail.curve.get_closest_offset(local_pos)
	return rail.to_global(rail.curve.sample_baked(closest_offset))

# ============================================================================
# RAIL NAVIGATION
# ============================================================================

func consider_rail_navigation() -> void:
	"""Evaluate whether to use a rail for the current situation"""
	if not bot or is_grinding:
		return  # Already grinding or no bot

	# Don't interfere with collection states
	if state == "ATTACK" or state == "COLLECT_ORB" or state == "COLLECT_ABILITY":
		target_rail = null
		return

	# Don't use rails while stabilizing on a platform
	if platform_stabilize_timer > 0.0:
		return

	# Don't attempt attachment if we recently failed
	if rail_attach_cooldown > 0.0:
		return

	# Find the best rail for current situation
	var best_rail: GrindRail = find_best_rail()
	if not best_rail:
		target_rail = null
		return

	# Decision: Should we attach to this rail now?
	var should_attach: bool = false

	# Always try to attach during RETREAT (rails are great for escaping)
	if state == "RETREAT":
		should_attach = true

	# Try to attach if rail significantly helps reach chase target
	elif state == "CHASE" and target_player and is_instance_valid(target_player):
		var bot_pos: Vector3 = bot.global_position
		var target_pos: Vector3 = target_player.global_position
		var rail_end: Vector3 = best_rail.to_global(best_rail.curve.sample_baked(best_rail.curve.get_baked_length()))

		var dist_now: float = bot_pos.distance_to(target_pos)
		var dist_via_rail: float = bot_pos.distance_to(rail_end) + rail_end.distance_to(target_pos)

		# Use rail if it's significantly better
		if dist_via_rail < dist_now * 0.8:
			should_attach = true

	# Try to attach if we're wandering (explore via rails)
	elif state == "WANDER":
		# 15% chance to use rails while wandering
		if randf() < 0.15:
			should_attach = true

	if should_attach:
		target_rail = best_rail
		# Try to attach if we're close enough
		var closest_point: Vector3 = _get_closest_rail_point(best_rail)
		var distance: float = bot.global_position.distance_to(closest_point)
		if distance <= 20.0:  # Within attachment range
			var success: bool = try_attach_to_rail(best_rail)
			if not success:
				# Failed to attach - set cooldown
				rail_attach_cooldown = RAIL_ATTACH_COOLDOWN_TIME
	else:
		target_rail = null

func find_best_rail() -> GrindRail:
	"""Find the best rail to use based on current situation"""
	if cached_rails.is_empty():
		return null

	var best_rail: GrindRail = null
	var best_score: float = 20.0  # Minimum score threshold

	for rail in cached_rails:
		if not is_instance_valid(rail):
			continue

		var score: float = evaluate_rail_score(rail)
		if score > best_score:
			best_score = score
			best_rail = rail

	return best_rail

func evaluate_rail_score(rail: GrindRail) -> float:
	"""Evaluate how valuable a rail is for the bot's current goals"""
	if not bot or not rail or not rail.curve:
		return 0.0

	var score: float = 0.0
	var bot_pos: Vector3 = bot.global_position

	# Get rail info
	var rail_length: float = rail.curve.get_baked_length()
	if rail_length <= 0:
		return 0.0

	var rail_start: Vector3 = rail.to_global(rail.curve.sample_baked(0))
	var rail_end: Vector3 = rail.to_global(rail.curve.sample_baked(rail_length))
	var closest_point: Vector3 = _get_closest_rail_point(rail)

	# Factor 1: Accessibility
	var distance_to_rail: float = bot_pos.distance_to(closest_point)
	if distance_to_rail > MAX_RAIL_DISTANCE:
		return 0.0

	var accessibility_score: float = 100.0 - (distance_to_rail / MAX_RAIL_DISTANCE * 50.0)
	score += accessibility_score

	# Factor 2: Height advantage
	var rail_avg_height: float = (rail_start.y + rail_end.y) / 2.0
	var height_diff: float = rail_avg_height - bot_pos.y

	if height_diff > 2.0:
		score += 30.0  # Elevated rail
	elif height_diff < -5.0:
		score -= 20.0  # Rail below us

	# Factor 3: Rail length
	if rail_length > 30.0:
		score += 25.0
	elif rail_length > 15.0:
		score += 15.0
	else:
		score += 5.0

	# Factor 4: Tactical value based on state
	if state == "CHASE" and target_player and is_instance_valid(target_player):
		var target_pos: Vector3 = target_player.global_position
		var dist_to_target_now: float = bot_pos.distance_to(target_pos)
		var dist_from_rail_end: float = rail_end.distance_to(target_pos)

		if dist_from_rail_end < dist_to_target_now:
			score += 40.0  # Rail brings us closer
		else:
			score -= 20.0  # Rail takes us away

	elif state == "RETREAT":
		score += 50.0  # Rails great for escaping
		if target_player and is_instance_valid(target_player):
			var target_pos: Vector3 = target_player.global_position
			var dist_from_rail_end: float = rail_end.distance_to(target_pos)
			var dist_now: float = bot_pos.distance_to(target_pos)
			if dist_from_rail_end > dist_now:
				score += 30.0  # Rail helps escape

	elif state == "COLLECT_ORB":
		if target_orb and is_instance_valid(target_orb):
			var collectible_pos: Vector3 = target_orb.global_position
			var dist_to_collectible_now: float = bot_pos.distance_to(collectible_pos)
			var dist_from_rail_end: float = rail_end.distance_to(collectible_pos)

			if dist_from_rail_end < dist_to_collectible_now * 0.7:
				score += 35.0  # Rail helps reach orb

	# Factor 5: Rail occupancy
	var occupancy: int = count_bots_on_rail(rail)
	if occupancy >= 2:
		score -= 100.0  # Crowded
	elif occupancy == 1:
		score -= 30.0  # One bot on rail

	return score

func count_bots_on_rail(rail: GrindRail) -> int:
	"""Count how many bots are currently grinding on a rail"""
	if not rail or not "active_grinders" in rail:
		return 0

	var count: int = 0
	for grinder in rail.active_grinders:
		if is_instance_valid(grinder) and grinder != bot:
			count += 1

	return count

func try_attach_to_rail(rail: GrindRail) -> bool:
	"""Attempt to attach to a rail"""
	if not rail or not bot:
		return false

	if is_grinding:
		return false

	if not rail.has_method("try_attach_player"):
		return false

	# Verify we're close enough
	var closest_point: Vector3 = _get_closest_rail_point(rail)
	var distance: float = bot.global_position.distance_to(closest_point)
	if distance > 20.0:
		return false

	# Attempt attachment
	var success: bool = rail.try_attach_player(bot)
	if success:
		target_rail = rail
		return true

	return false

# ============================================================================
# RAIL CALLBACKS (called by GrindRail)
# ============================================================================

func start_grinding(rail: GrindRail) -> void:
	"""Called when bot enters grinding state (synced from player.gd)"""
	if is_grinding:
		return

	is_grinding = true
	current_rail = rail
	target_rail = rail

	# Cancel aerial recovery if we attached to a new rail
	post_rail_launch = false
	rail_launch_timer = 0.0

	DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[Type A] Started grinding on rail", false, get_entity_id())


func stop_grinding() -> void:
	"""Called when bot exits grinding state (synced from player.gd)"""
	if not is_grinding:
		return

	is_grinding = false
	current_rail = null

	DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[Type A] Stopped grinding", false, get_entity_id())

func launch_from_rail(velocity: Vector3) -> void:
	"""Called when bot is launched from rail end - activates aerial recovery
	Note: This is now called by player.gd after stop_grinding(), so is_grinding may already be false.
	We still want to activate aerial recovery mode regardless."""

	# Ensure grinding state is cleared (may already be done by player.gd sync)
	if is_grinding:
		stop_grinding()

	# Find safe landing zone FIRST
	find_safe_landing_zone()

	# Apply launch impulse
	if bot and bot is RigidBody3D:
		# Upward boost
		bot.apply_central_impulse(Vector3.UP * 15.0)

		# Horizontal impulse toward platform target
		var bot_pos: Vector3 = bot.global_position
		var direction_to_platform: Vector3 = (safe_landing_target - bot_pos).normalized()
		direction_to_platform.y = 0

		bot.apply_central_impulse(direction_to_platform * 30.0)

	# Activate aerial recovery mode
	post_rail_launch = true
	rail_launch_timer = 0.0

	DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[Type A] Launched from rail - aerial recovery active", false, get_entity_id())

# ============================================================================
# RAIL LAUNCH RECOVERY
# ============================================================================

func find_safe_landing_zone() -> void:
	"""Find a safe place to land after being launched from a rail"""
	if not bot:
		return

	var bot_pos: Vector3 = bot.global_position
	var best_landing_score: float = -INF
	var best_landing_pos: Vector3 = Vector3(0, 1.5, 0)  # Stage center fallback

	# Prioritize platforms heavily
	var expanded_search_radius: float = SAFE_LANDING_SEARCH_RADIUS * 2.0

	for platform_data in cached_platforms:
		if not is_instance_valid(platform_data.node):
			continue

		var platform_pos: Vector3 = platform_data.position
		var distance: float = Vector2(bot_pos.x - platform_pos.x, bot_pos.z - platform_pos.z).length()

		if distance > expanded_search_radius:
			continue

		# Huge bonus for platforms
		var score: float = 500.0

		# Prefer platforms below us
		var height_diff: float = platform_pos.y - bot_pos.y
		if height_diff < 0:
			score += 200.0
			score += min(abs(height_diff) * 10.0, 300.0)
		else:
			score += 100.0
			score -= height_diff * 5.0

		score += (expanded_search_radius - distance) * 5.0

		# Prefer larger platforms
		var platform_size: Vector3 = platform_data.size
		var platform_area: float = platform_size.x * platform_size.z
		score += platform_area * 2.0

		# Light occupancy penalty
		var occupancy: int = count_bots_on_platform(platform_data)
		if occupancy >= 3:
			score -= 50.0
		elif occupancy >= 2:
			score -= 20.0

		if score > best_landing_score:
			best_landing_score = score
			best_landing_pos = platform_pos

	safe_landing_target = best_landing_pos

func handle_post_rail_launch_navigation(delta: float) -> void:
	"""Handle aerial navigation to return to stage after rail launch"""
	if not bot or not bot is RigidBody3D:
		post_rail_launch = false
		return

	# Check timeout
	if rail_launch_timer >= RAIL_LAUNCH_RECOVERY_TIME:
		post_rail_launch = false
		rail_launch_timer = 0.0
		return

	# Check if we've landed
	var is_grounded: bool = false
	if "is_grounded" in bot:
		is_grounded = bot.is_grounded

	# Alternative grounded check
	if not is_grounded and "linear_velocity" in bot:
		if abs(bot.linear_velocity.y) < 1.0:
			var ground_check_result: Dictionary = check_ground_below(2.0)
			if ground_check_result.has("grounded") and ground_check_result.grounded:
				is_grounded = true

	if is_grounded:
		# Successfully landed
		post_rail_launch = false
		rail_launch_timer = 0.0
		DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[Type A] Rail recovery complete - landed", false, get_entity_id())
		return

	# Still airborne - apply aerial correction
	var bot_pos: Vector3 = bot.global_position
	var direction_to_safe_zone: Vector3 = (safe_landing_target - bot_pos).normalized()
	direction_to_safe_zone.y = 0

	if direction_to_safe_zone.length() > 0.1:
		# Apply aggressive aerial correction
		var aerial_force: float = current_roll_force * 1.5
		bot.apply_central_force(direction_to_safe_zone * aerial_force)

		# Extra boost if far from target
		var distance_to_target: float = bot_pos.distance_to(safe_landing_target)
		if distance_to_target > 20.0:
			if fmod(rail_launch_timer, 0.5) < delta:
				bot.apply_central_impulse(direction_to_safe_zone * 8.0)

	# Rotate toward landing target
	rotate_to_direction(direction_to_safe_zone)

	# Use double jump if needed
	if "jump_count" in bot and "max_jumps" in bot:
		var falling_fast: bool = bot.linear_velocity.y < -10.0
		var far_from_target: bool = bot_pos.distance_to(safe_landing_target) > 15.0

		if falling_fast and far_from_target and bot.jump_count < bot.max_jumps:
			if obstacle_jump_timer <= 0.0:
				bot_jump()
				obstacle_jump_timer = 0.5

	# Use bounce attack for downward control if very high
	if rail_launch_timer > 0.8 and bot_pos.y > safe_landing_target.y + 10.0:
		if validate_bounce_properties() and bounce_cooldown_timer <= 0.0:
			bot_bounce()

func check_ground_below(max_distance: float = 2.0) -> Dictionary:
	"""Check if there's ground below the bot"""
	if not bot or not cached_space_state:
		return {"grounded": false}

	var bot_pos: Vector3 = bot.global_position
	var ray_start: Vector3 = bot_pos
	var ray_end: Vector3 = bot_pos + Vector3(0, -max_distance, 0)

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [bot]
	query.collision_mask = 1  # World layer

	var result: Dictionary = cached_space_state.intersect_ray(query)
	if result:
		return {"grounded": true, "position": result.position}

	return {"grounded": false}
