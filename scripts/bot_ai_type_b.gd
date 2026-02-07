extends "res://scripts/bot_ai.gd"

## Bot AI Controller - TYPE B (Quake 3-Style Arenas)
## Extends base BotAI with jump pads and teleporter systems
## Optimized for Type B levels: multi-tier platforms, jump pads, teleporters, tactical combat

# ============================================================================
# JUMP PAD SYSTEM (Quake 3-style vertical mobility)
# ============================================================================

var cached_jump_pads: Array[Node] = []
var target_jump_pad: Node = null
var jump_pad_check_timer: float = 0.0

const JUMP_PAD_CHECK_INTERVAL: float = 2.5
const MAX_CACHED_JUMP_PADS: int = 20
const MAX_JUMP_PAD_DISTANCE: float = 40.0

# ============================================================================
# TELEPORTER SYSTEM (Quake 3-style traversal)
# ============================================================================

var cached_teleporters: Array[Node] = []
var target_teleporter: Node = null
var teleporter_check_timer: float = 0.0
var teleporter_cooldown: float = 0.0

const TELEPORTER_CHECK_INTERVAL: float = 3.0
const MAX_CACHED_TELEPORTERS: int = 10
const TELEPORTER_USE_COOLDOWN: float = 2.0

# ============================================================================
# OVERRIDES
# ============================================================================

func get_ai_type() -> String:
	return "Type B"

func _ready() -> void:
	super._ready()
	jump_pad_check_timer = randf_range(0.0, JUMP_PAD_CHECK_INTERVAL)
	teleporter_check_timer = randf_range(0.0, TELEPORTER_CHECK_INTERVAL)

func update_timers(delta: float) -> void:
	super.update_timers(delta)
	jump_pad_check_timer -= delta
	teleporter_check_timer -= delta
	teleporter_cooldown -= delta

func setup_arena_specific_caches() -> void:
	"""Cache jump pads and teleporters for Type B arenas"""
	refresh_jump_pad_cache()
	refresh_teleporter_cache()

func consider_arena_specific_navigation() -> void:
	"""Check for jump pad and teleporter opportunities"""
	# Check for jump pads periodically
	if jump_pad_check_timer <= 0.0:
		consider_jump_pad_usage()
		jump_pad_check_timer = JUMP_PAD_CHECK_INTERVAL

	# Check for teleporters periodically (if not on cooldown)
	if teleporter_check_timer <= 0.0 and teleporter_cooldown <= 0.0:
		consider_teleporter_usage()
		teleporter_check_timer = TELEPORTER_CHECK_INTERVAL

func handle_arena_specific_state_updates() -> void:
	"""No special state updates needed for Type B"""
	pass

# ============================================================================
# JUMP PAD CACHING
# ============================================================================

func refresh_jump_pad_cache() -> void:
	"""Cache nearby jump pads for tactical mobility"""
	cached_jump_pads.clear()

	if not bot:
		return

	# Use inherited cached_world to avoid per-refresh tree traversal
	if not cached_world or not is_instance_valid(cached_world):
		cached_world = get_tree().get_root().get_node_or_null("World")
	if not cached_world:
		return

	# Find jump pads in scene
	var all_jump_pads: Array = get_tree().get_nodes_in_group("jump_pad")
	var bot_pos: Vector3 = bot.global_position

	# Filter by distance and validity
	for jump_pad in all_jump_pads:
		if not is_instance_valid(jump_pad) or not jump_pad.is_inside_tree():
			continue

		var distance: float = bot_pos.distance_to(jump_pad.global_position)
		if distance <= MAX_JUMP_PAD_DISTANCE:
			cached_jump_pads.append(jump_pad)

	# Limit cache size
	if cached_jump_pads.size() > MAX_CACHED_JUMP_PADS:
		cached_jump_pads.sort_custom(func(a, b):
			return bot_pos.distance_to(a.global_position) < bot_pos.distance_to(b.global_position)
		)
		cached_jump_pads = cached_jump_pads.slice(0, MAX_CACHED_JUMP_PADS)

# ============================================================================
# JUMP PAD NAVIGATION
# ============================================================================

func consider_jump_pad_usage() -> void:
	"""Evaluate whether to use a jump pad for the current situation"""
	if not bot:
		return

	# Don't use jump pads while stabilizing on a platform
	if platform_stabilize_timer > 0.0:
		return

	# Find best jump pad for current situation
	var best_jump_pad: Node = find_best_jump_pad()
	if not best_jump_pad:
		target_jump_pad = null
		return

	# Decision: Should we use this jump pad?
	var should_use: bool = false
	var distance_to_pad: float = bot.global_position.distance_to(best_jump_pad.global_position)

	# Use jump pads during RETREAT (great for escaping)
	if state == "RETREAT" and distance_to_pad < 15.0:
		should_use = true

	# Use jump pads if they help reach elevated targets
	elif state == "CHASE" and target_player and is_instance_valid(target_player):
		var target_pos: Vector3 = target_player.global_position
		# If target is above us and jump pad is nearby
		if target_pos.y > bot.global_position.y + 5.0 and distance_to_pad < 12.0:
			should_use = true

	# Use jump pads for reaching elevated items
	elif (state == "COLLECT_ORB" or state == "COLLECT_ABILITY"):
		var collectible: Node = target_orb if state == "COLLECT_ORB" else target_ability
		if collectible and is_instance_valid(collectible):
			var item_pos: Vector3 = collectible.global_position
			# If item is elevated and jump pad is nearby
			if item_pos.y > bot.global_position.y + 5.0 and distance_to_pad < 12.0:
				should_use = true

	if should_use:
		target_jump_pad = best_jump_pad
		# Move toward jump pad
		if distance_to_pad > 3.0:
			move_towards(best_jump_pad.global_position, 1.0)
	else:
		target_jump_pad = null

func find_best_jump_pad() -> Node:
	"""Find the best jump pad to use based on current situation"""
	if cached_jump_pads.is_empty():
		return null

	var best_pad: Node = null
	var best_score: float = 30.0  # Minimum score threshold

	for jump_pad in cached_jump_pads:
		if not is_instance_valid(jump_pad):
			continue

		var score: float = evaluate_jump_pad_score(jump_pad)
		if score > best_score:
			best_score = score
			best_pad = jump_pad

	return best_pad

func evaluate_jump_pad_score(jump_pad: Node) -> float:
	"""Evaluate how useful a jump pad is for the current situation"""
	if not bot or not jump_pad:
		return 0.0

	var score: float = 0.0
	var bot_pos: Vector3 = bot.global_position
	var pad_pos: Vector3 = jump_pad.global_position

	# Factor 1: Accessibility (closer is better)
	var distance: float = bot_pos.distance_to(pad_pos)
	if distance > MAX_JUMP_PAD_DISTANCE:
		return 0.0

	score += (MAX_JUMP_PAD_DISTANCE - distance) / MAX_JUMP_PAD_DISTANCE * 40.0

	# Factor 2: Tactical value based on state
	if state == "RETREAT":
		# Jump pads are excellent for escaping
		score += 50.0

	elif state == "CHASE" and target_player and is_instance_valid(target_player):
		# Check if jump pad helps reach elevated target
		var target_pos: Vector3 = target_player.global_position
		var height_diff: float = target_pos.y - bot_pos.y

		if height_diff > 5.0:  # Target is significantly above us
			score += 40.0

	elif (state == "COLLECT_ORB" or state == "COLLECT_ABILITY"):
		var collectible: Node = target_orb if state == "COLLECT_ORB" else target_ability
		if collectible and is_instance_valid(collectible):
			# Check if jump pad helps reach elevated item
			var item_pos: Vector3 = collectible.global_position
			var height_diff: float = item_pos.y - bot_pos.y

			if height_diff > 5.0:  # Item is significantly above us
				score += 35.0

	# Factor 3: Height gain (assume jump pads launch upward ~15-20 units)
	var estimated_launch_height: float = 15.0
	var final_height: float = pad_pos.y + estimated_launch_height

	# Prefer jump pads that put us on higher tiers (Y=8, 15, 22 in Type B)
	if final_height >= 20.0:
		score += 25.0  # Reaches tier 3 (Y=22)
	elif final_height >= 13.0:
		score += 20.0  # Reaches tier 2 (Y=15)
	elif final_height >= 6.0:
		score += 10.0  # Reaches tier 1 (Y=8)

	return score

# ============================================================================
# TELEPORTER CACHING
# ============================================================================

func refresh_teleporter_cache() -> void:
	"""Cache nearby teleporters for tactical traversal"""
	cached_teleporters.clear()

	if not bot:
		return

	# Use inherited cached_world to avoid per-refresh tree traversal
	if not cached_world or not is_instance_valid(cached_world):
		cached_world = get_tree().get_root().get_node_or_null("World")
	if not cached_world:
		return

	# Find teleporters in scene
	var all_teleporters: Array = get_tree().get_nodes_in_group("teleporter")

	# Filter by validity and add to cache
	for teleporter in all_teleporters:
		if not is_instance_valid(teleporter) or not teleporter.is_inside_tree():
			continue

		cached_teleporters.append(teleporter)

	# Limit cache size
	if cached_teleporters.size() > MAX_CACHED_TELEPORTERS:
		cached_teleporters = cached_teleporters.slice(0, MAX_CACHED_TELEPORTERS)

# ============================================================================
# TELEPORTER NAVIGATION
# ============================================================================

func consider_teleporter_usage() -> void:
	"""Evaluate whether to use a teleporter for the current situation"""
	if not bot or teleporter_cooldown > 0.0:
		return

	# Find best teleporter for current situation
	var best_teleporter: Node = find_best_teleporter()
	if not best_teleporter:
		target_teleporter = null
		return

	# Decision: Should we use this teleporter?
	var should_use: bool = false
	var distance_to_teleporter: float = bot.global_position.distance_to(best_teleporter.global_position)

	# Use teleporters during RETREAT (quick escape)
	if state == "RETREAT" and distance_to_teleporter < 10.0:
		should_use = true

	# Use teleporters if destination helps reach targets
	elif (state == "CHASE" or state == "COLLECT_ORB" or state == "COLLECT_ABILITY"):
		# Only use if teleporter is very close (within 8 units)
		if distance_to_teleporter < 8.0:
			should_use = true

	if should_use:
		target_teleporter = best_teleporter
		# Move toward teleporter
		if distance_to_teleporter > 2.0:
			move_towards(best_teleporter.global_position, 1.0)
		# Teleporter will activate automatically when bot enters its area
	else:
		target_teleporter = null

func find_best_teleporter() -> Node:
	"""Find the best teleporter to use based on current situation"""
	if cached_teleporters.is_empty():
		return null

	var best_teleporter: Node = null
	var best_score: float = 20.0  # Minimum score threshold

	for teleporter in cached_teleporters:
		if not is_instance_valid(teleporter):
			continue

		var score: float = evaluate_teleporter_score(teleporter)
		if score > best_score:
			best_score = score
			best_teleporter = teleporter

	return best_teleporter

func evaluate_teleporter_score(teleporter: Node) -> float:
	"""Evaluate how useful a teleporter is for the current situation"""
	if not bot or not teleporter:
		return 0.0

	var score: float = 0.0
	var bot_pos: Vector3 = bot.global_position
	var teleporter_pos: Vector3 = teleporter.global_position

	# Factor 1: Accessibility (must be reasonably close)
	var distance: float = bot_pos.distance_to(teleporter_pos)
	if distance > 30.0:
		return 0.0  # Too far to consider

	score += (30.0 - distance) / 30.0 * 30.0

	# Factor 2: Destination usefulness (if teleporter has destination info)
	if "destination" in teleporter and teleporter.destination:
		var dest_pos: Vector3 = teleporter.destination.global_position

		# RETREAT: Prefer teleporters that take us far from enemies
		if state == "RETREAT" and target_player and is_instance_valid(target_player):
			var enemy_pos: Vector3 = target_player.global_position
			var dist_from_enemy_now: float = bot_pos.distance_to(enemy_pos)
			var dist_from_enemy_after: float = dest_pos.distance_to(enemy_pos)

			if dist_from_enemy_after > dist_from_enemy_now:
				score += 50.0  # Teleporter helps us escape

		# CHASE: Prefer teleporters that bring us closer to target
		elif state == "CHASE" and target_player and is_instance_valid(target_player):
			var target_pos: Vector3 = target_player.global_position
			var dist_to_target_now: float = bot_pos.distance_to(target_pos)
			var dist_to_target_after: float = dest_pos.distance_to(target_pos)

			if dist_to_target_after < dist_to_target_now * 0.7:
				score += 40.0  # Teleporter significantly shortens distance

		# COLLECT: Prefer teleporters that bring us closer to items
		elif (state == "COLLECT_ORB" or state == "COLLECT_ABILITY"):
			var collectible: Node = target_orb if state == "COLLECT_ORB" else target_ability
			if collectible and is_instance_valid(collectible):
				var item_pos: Vector3 = collectible.global_position
				var dist_to_item_now: float = bot_pos.distance_to(item_pos)
				var dist_to_item_after: float = dest_pos.distance_to(item_pos)

				if dist_to_item_after < dist_to_item_now * 0.7:
					score += 35.0  # Teleporter significantly shortens distance

	# Factor 3: Combat risk (avoid teleporters near enemies)
	if target_player and is_instance_valid(target_player):
		var enemy_dist_to_teleporter: float = teleporter_pos.distance_to(target_player.global_position)
		if enemy_dist_to_teleporter < 10.0:
			score -= 30.0  # Enemy camping teleporter

	return score
