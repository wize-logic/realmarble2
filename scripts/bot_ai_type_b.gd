extends Node

## Bot AI Controller - TYPE B (Quake 3-Style Arenas) v4.0
## Optimized for Type B levels: multi-tier platforms, jump pads, teleporters, tactical combat
## OpenArena-inspired improvements + aggressive stuck-under-ramp prevention
##
## FIXES APPLIED (v1.0):
## 1. Removed ALL await statements that freeze bots
## 2. Fixed RigidBody3D rotation using angular_velocity
## 3. Added ability charging validation (Cannon doesn't support charging)
## 4. Fixed teleport to use world.spawns instead of bot.spawns
## 5. Added bounce attack support for vertical combat/mobility
## 6. Improved state transitions with better threat assessment
## 7. Better obstacle avoidance and pathfinding
## 8. Fixed stuck detection thresholds
## 9. Performance optimizations for HTML5
##
## IMPROVEMENTS (v2.0):
## 10. Comprehensive property validation for all mechanics
## 11. Cache filtering for invalid nodes
## 12. Lead prediction for Cannon projectiles
## 13. Dynamic player avoidance in movement
## 14. Better state priority for combat
## 15. Visibility checks for collection targets
## 16. Dead code cleanup (unused variables)
## 17. Removed all rail grinding logic (bots no longer use rails)
## 18. Improved slope detection to prevent getting stuck under slopes
##
## CRITICAL FIXES (v2.0 Refined):
## 19. Fixed rotation overshoot: Added damping/lerp to angular_velocity (prevents oscillation)
## 20. Fixed weapon missing: Alignment check before cannon fires (prevents premature shots)
## 21. Fixed lead prediction: Returns predicted position instead of distance (near-perfect aim)
## 22. Fixed slope-stuck: Lowered threshold to 0.1, added horizontal velocity check
## 23. Fixed slope-stuck: Added WANDER state to stuck detection
## 24. Fixed slope-stuck: Proactive is_stuck_under_terrain check in _physics_process
## 25. Fixed slope-stuck: Always apply downward force + torque in unstuck movement
## 26. Fixed slope-stuck: Reduced unstuck timeout to 0.8-1.5s (was 1.2-2.2s)
## 27. Fixed awareness: Proactive overhead slope avoidance in all movement functions
## 28. Fixed balance: Aggression randomized to 0.6-0.9 (was 0.9-1.0)
## 29. Fixed robustness: Teleport fail-safe for missing spawns (+10 units up)
## 30. Fixed collect: Allow if visible OR distance < 15 (better item awareness)
##
## OPENARENA-INSPIRED IMPROVEMENTS (v3.0):
## 31. Advanced target prioritization: Weighted scoring based on threat, distance, health
## 32. Weapon proficiency system: Ability scoring for intelligent selection
## 33. Dynamic aggression: Real-time risk assessment based on health ratios
## 34. Skill-based accuracy: Varying aim quality per bot (0.7-0.95 compensation)
## 35. Personality traits: Turn speed, caution level, and strategic preference
## 36. Combat evaluators: Separate retreat/chase decision functions
## 37. Enhanced strafe timing: Skill-based unpredictability
##
## STUCK-UNDER-RAMP FIXES (v4.0):
## 38. More aggressive overhead detection: 9 check points (was 5), lower threshold 2.3 (was 1.8)
## 39. Extended look-ahead distance: 1.8x check distance to catch ramps earlier
## 40. Low-clearance tracking: Detects danger zones where bots can get wedged
## 41. Forced teleport timeout: Auto-teleport after 3 seconds stuck under terrain
## 42. Improved obstacle classification: Better overhead slope vs platform detection

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
var player_search_timer: float = 0.0

# Advanced AI variables
var strafe_direction: float = 1.0
var strafe_timer: float = 0.0
var retreat_timer: float = 0.0
var ability_charge_timer: float = 0.0
var is_charging_ability: bool = false
var aggression_level: float = 0.7  # Used for ability usage probability

# NEW: OpenArena-inspired personality traits
var bot_skill: float = 0.75  # 0.0 (novice) to 1.0 (expert) - affects accuracy & timing
var aim_accuracy: float = 0.85  # Base accuracy multiplier for this bot
var turn_speed_factor: float = 1.0  # Personality-based turning speed (0.7-1.3)
var caution_level: float = 0.5  # How cautious the bot is (0.0 aggressive - 1.0 defensive)
var strategic_preference: String = "balanced"  # "aggressive", "balanced", "defensive", "support"

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

# NEW v4: Stuck under terrain timeout
var stuck_under_terrain_timer: float = 0.0
const STUCK_UNDER_TERRAIN_TELEPORT_TIMEOUT: float = 3.0  # Force teleport after 3s under terrain

# Target timeout variables
var target_stuck_timer: float = 0.0
var target_stuck_position: Vector3 = Vector3.ZERO
const TARGET_STUCK_TIMEOUT: float = 4.0

# NEW: Bounce attack support
var bounce_cooldown_timer: float = 0.0
const BOUNCE_COOLDOWN: float = 0.5

# Ability optimal ranges
const CANNON_OPTIMAL_RANGE: float = 15.0
const SWORD_OPTIMAL_RANGE: float = 3.5
const DASH_ATTACK_OPTIMAL_RANGE: float = 8.0
const EXPLOSION_OPTIMAL_RANGE: float = 6.0

# NEW: Weapon/Ability proficiency scores (OpenArena-style)
const ABILITY_SCORES: Dictionary = {
	"Cannon": 85,      # Long-range projectile
	"Sword": 75,       # Close-range melee
	"Dash Attack": 80, # Mid-range mobility
	"Explosion": 70    # Close-range AoE
}

# IMPROVED: Cached group queries with filtering
var cached_players: Array[Node] = []
var cached_abilities: Array[Node] = []
var cached_orbs: Array[Node] = []
var cache_refresh_timer: float = 0.0
const CACHE_REFRESH_INTERVAL: float = 0.5

# NEW: Platform navigation system
var cached_platforms: Array[Dictionary] = []  # Stores {node, position, size, height}
var target_platform: Dictionary = {}  # Current platform target
var platform_check_timer: float = 0.0
const PLATFORM_CHECK_INTERVAL: float = 1.5
var is_approaching_platform: bool = false  # Special navigation mode
var platform_jump_prepared: bool = false  # Ready to jump onto platform

# SAFETY: Platform landing stabilization
var platform_stabilize_timer: float = 0.0  # Time to stabilize after landing
const PLATFORM_STABILIZE_TIME: float = 0.8  # How long to stabilize
var on_platform: bool = false  # Currently standing on a platform

# OPTIMIZATION: Performance limits for platform system
const MAX_CACHED_PLATFORMS: int = 20  # Limit cache size for performance
const MAX_PLATFORM_DISTANCE: float = 40.0  # Only consider nearby platforms
const MIN_PLATFORM_HEIGHT: float = 2.0  # Only cache elevated platforms (ignore floor)
const GOOD_ENOUGH_SCORE: float = 70.0  # Early exit threshold

# SAFETY: Platform occupancy limits
const MAX_BOTS_PER_PLATFORM: int = 2  # Max bots that can share a platform
const MIN_PLATFORM_SIZE_FOR_COMBAT: float = 8.0  # Minimum platform size for combat positioning

# VISION: Stable line of sight system
const BOT_EYE_HEIGHT: float = 1.0  # Eye position above bot center
const VISION_HYSTERESIS_TIME: float = 0.5  # Keep seeing target for 0.5s after obstruction
var last_seen_targets: Dictionary = {}  # Tracks when targets were last visible {node: timestamp}
var vision_update_timer: float = 0.0
const VISION_UPDATE_INTERVAL: float = 0.1  # Update vision cache every 0.1s for stability
# NOTE: Marbles have 360° awareness (spherical sensors), no FOV restrictions

# TYPE B: Jump pad system (Quake 3-style mobility)
var cached_jump_pads: Array[Node] = []  # Cached list of jump pads in scene
var target_jump_pad: Node = null  # Jump pad bot wants to use
var jump_pad_check_timer: float = 0.0
const JUMP_PAD_CHECK_INTERVAL: float = 2.5  # Check for jump pads every 2.5 seconds
const MAX_CACHED_JUMP_PADS: int = 20  # Max jump pads to cache
const MAX_JUMP_PAD_DISTANCE: float = 40.0  # Only consider nearby jump pads

# TYPE B: Teleporter system (Quake 3-style traversal)
var cached_teleporters: Array[Node] = []  # Cached list of teleporters
var target_teleporter: Node = null  # Teleporter bot wants to use
var teleporter_check_timer: float = 0.0
const TELEPORTER_CHECK_INTERVAL: float = 3.0  # Check teleporters every 3 seconds
const MAX_CACHED_TELEPORTERS: int = 10  # Max teleporters to cache
var teleporter_cooldown: float = 0.0  # Cooldown after using teleporter
const TELEPORTER_USE_COOLDOWN: float = 2.0  # Wait 2s before considering teleporters again

# NEW: Player avoidance
var player_avoidance_timer: float = 0.0
const PLAYER_AVOIDANCE_CHECK_INTERVAL: float = 0.2

# PERFORMANCE: Cached PhysicsDirectSpaceState3D for raycast operations
var cached_space_state: PhysicsDirectSpaceState3D = null
var space_state_cache_timer: float = 0.0
const SPACE_STATE_CACHE_REFRESH: float = 1.0  # Refresh physics space state every 1s

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

	# FIXED: Randomize aggression for personality variety (0.6-0.9 for more varied behavior)
	aggression_level = randf_range(0.6, 0.9)

	# NEW: Initialize personality traits (OpenArena-inspired)
	initialize_personality()

	# PERFORMANCE: Stagger timer initialization to prevent all bots from processing simultaneously
	# This reduces frame time spikes in HTML5 with 7 bots
	cache_refresh_timer = randf_range(0.0, CACHE_REFRESH_INTERVAL)
	platform_check_timer = randf_range(0.0, PLATFORM_CHECK_INTERVAL)
	jump_pad_check_timer = randf_range(0.0, JUMP_PAD_CHECK_INTERVAL)
	teleporter_check_timer = randf_range(0.0, TELEPORTER_CHECK_INTERVAL)
	ability_check_timer = randf_range(0.0, 1.2)
	orb_check_timer = randf_range(0.0, 1.0)
	player_search_timer = randf_range(0.0, 0.5)
	vision_update_timer = randf_range(0.0, VISION_UPDATE_INTERVAL)
	edge_check_timer = randf_range(0.0, EDGE_CHECK_INTERVAL)
	player_avoidance_timer = randf_range(0.0, PLAYER_AVOIDANCE_CHECK_INTERVAL)

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
	strafe_timer -= delta
	retreat_timer -= delta
	ability_charge_timer -= delta
	stuck_timer += delta
	unstuck_timer -= delta
	obstacle_jump_timer -= delta
	bounce_cooldown_timer -= delta
	player_search_timer -= delta
	cache_refresh_timer -= delta
	player_avoidance_timer -= delta
	edge_check_timer -= delta
	platform_check_timer -= delta
	platform_stabilize_timer -= delta
	vision_update_timer -= delta
	jump_pad_check_timer -= delta
	teleporter_check_timer -= delta
	teleporter_cooldown -= delta
	space_state_cache_timer -= delta

	# PERFORMANCE: Update cached physics space state
	if space_state_cache_timer <= 0.0:
		if bot and bot is RigidBody3D:
			cached_space_state = bot.get_world_3d().direct_space_state
		space_state_cache_timer = SPACE_STATE_CACHE_REFRESH

	# IMPROVED: Refresh cached groups with filtering
	if cache_refresh_timer <= 0.0:
		refresh_cached_groups()
		cache_refresh_timer = CACHE_REFRESH_INTERVAL

	# Check if bot is stuck on obstacles
	if stuck_timer >= stuck_check_interval:
		check_if_stuck()
		stuck_timer = 0.0

	# FIXED: Proactive check for being stuck under terrain/slopes
	var currently_stuck_under_terrain: bool = is_stuck_under_terrain()

	if currently_stuck_under_terrain:
		# NEW v4: Track time stuck under terrain
		stuck_under_terrain_timer += delta

		# NEW v4: Force teleport if stuck under terrain too long
		if stuck_under_terrain_timer >= STUCK_UNDER_TERRAIN_TELEPORT_TIMEOUT:
			print("[BotAI] ", bot.name, " stuck under terrain for ", stuck_under_terrain_timer, "s - forcing teleport")
			teleport_to_safe_position()
			stuck_under_terrain_timer = 0.0
			is_stuck = false
			consecutive_stuck_checks = 0
			return

		# Trigger unstuck behavior if not already stuck
		if not is_stuck:
			is_stuck = true
			unstuck_timer = randf_range(0.8, 1.5)
			consecutive_stuck_checks = max(consecutive_stuck_checks, 3)  # Mark as stuck
			# Set escape direction backward
			var opposite_dir: Vector3 = Vector3(-sin(bot.rotation.y), 0, -cos(bot.rotation.y))
			var random_side: float = 1.0 if randf() > 0.5 else -1.0
			var perpendicular: Vector3 = Vector3(-sin(bot.rotation.y), 0, cos(bot.rotation.y)) * random_side
			obstacle_avoid_direction = (opposite_dir + perpendicular).normalized()
	else:
		# Reset timer when not stuck under terrain
		stuck_under_terrain_timer = 0.0

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

	# OPTIMIZED: Check for platforms with context-aware frequency
	if platform_check_timer <= 0.0:
		find_best_platform()
		# Less frequent checks during combat for performance
		if state == "ATTACK" or state == "CHASE":
			platform_check_timer = PLATFORM_CHECK_INTERVAL * 2.0  # 3 seconds during combat
		elif state == "RETREAT":
			platform_check_timer = PLATFORM_CHECK_INTERVAL * 0.5  # 0.75 seconds when retreating (urgent)
		else:
			platform_check_timer = PLATFORM_CHECK_INTERVAL  # 1.5 seconds default

	# TYPE B: Check for jump pads periodically (Quake 3 mobility)
	if jump_pad_check_timer <= 0.0:
		consider_jump_pad_usage()
		jump_pad_check_timer = JUMP_PAD_CHECK_INTERVAL

	# TYPE B: Check for teleporters periodically (Quake 3 traversal)
	if teleporter_check_timer <= 0.0 and teleporter_cooldown <= 0.0:
		consider_teleporter_usage()
		teleporter_check_timer = TELEPORTER_CHECK_INTERVAL

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

func initialize_personality() -> void:
	"""NEW: Initialize bot personality traits (OpenArena-inspired)"""
	# Skill level affects accuracy and decision speed
	bot_skill = randf_range(0.5, 0.95)

	# Aim accuracy varies per bot (70%-95% compensation)
	aim_accuracy = randf_range(0.70, 0.95)

	# Turn speed personality (some bots turn faster/slower)
	turn_speed_factor = randf_range(0.8, 1.2)

	# Caution level (affects retreat threshold and risk-taking)
	caution_level = randf_range(0.2, 0.8)

	# Strategic preference affects behavior patterns
	var preference_roll: float = randf()
	if preference_roll < 0.25:
		strategic_preference = "aggressive"  # Rushes combat, takes risks
		aggression_level = randf_range(0.75, 0.95)
		caution_level = randf_range(0.2, 0.4)
	elif preference_roll < 0.5:
		strategic_preference = "defensive"   # Plays safe, retreats early
		aggression_level = randf_range(0.5, 0.7)
		caution_level = randf_range(0.6, 0.85)
	elif preference_roll < 0.75:
		strategic_preference = "support"     # Collects items, avoids direct combat
		aggression_level = randf_range(0.55, 0.75)
		caution_level = randf_range(0.5, 0.7)
	else:
		strategic_preference = "balanced"    # Standard behavior
		aggression_level = randf_range(0.6, 0.85)
		caution_level = randf_range(0.4, 0.6)

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

	# NEW: Cache platforms from level generators
	refresh_platform_cache()

	# TYPE B: Cache jump pads and teleporters from level generators (Quake 3 arenas)
	refresh_jump_pad_cache()
	refresh_teleporter_cache()

func refresh_platform_cache() -> void:
	"""OPTIMIZED: Cache platform positions with filtering for performance

	Performance characteristics:
	- Max 20 platforms cached (reduced from potentially 50+)
	- Only elevated platforms (Y > 2.0) - ignores floor/walls
	- Only platforms within 40 units - spatial filtering
	- Sorted by distance - keeps closest platforms
	- Called every 0.5 seconds (shared with other caches)
	- Estimated cost: <0.5ms per bot per refresh
	"""
	cached_platforms.clear()

	if not bot:
		return

	# Get World node to access level generator
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if not world:
		return

	# Try to find level generator (Type A or Type B)
	var level_gen: Node = world.get_node_or_null("LevelGenerator")
	if not level_gen:
		level_gen = world.get_node_or_null("LevelGeneratorQ3")

	if not level_gen or not "platforms" in level_gen:
		return

	var bot_pos: Vector3 = bot.global_position
	var candidate_platforms: Array[Dictionary] = []

	# OPTIMIZATION: Pre-filter platforms by height and distance
	for platform_node in level_gen.platforms:
		if not is_instance_valid(platform_node) or not platform_node.is_inside_tree():
			continue

		var platform_pos: Vector3 = platform_node.global_position

		# FILTER 1: Only cache elevated platforms (ignore floor/walls)
		if platform_pos.y < MIN_PLATFORM_HEIGHT:
			continue

		# FILTER 2: Only cache platforms within reasonable distance
		var distance: float = bot_pos.distance_to(platform_pos)
		if distance > MAX_PLATFORM_DISTANCE:
			continue

		# Get platform size
		var platform_size: Vector3 = Vector3(8, 1, 8)  # Default size
		if platform_node is MeshInstance3D and platform_node.mesh:
			if platform_node.mesh is BoxMesh:
				platform_size = platform_node.mesh.size

		# Add to candidates with distance for sorting
		candidate_platforms.append({
			"node": platform_node,
			"position": platform_pos,
			"size": platform_size,
			"height": platform_pos.y,
			"distance": distance
		})

	# OPTIMIZATION: Sort by distance and keep only closest MAX_CACHED_PLATFORMS
	if candidate_platforms.size() > MAX_CACHED_PLATFORMS:
		candidate_platforms.sort_custom(func(a, b): return a.distance < b.distance)
		candidate_platforms = candidate_platforms.slice(0, MAX_CACHED_PLATFORMS)

	# Store filtered platforms (remove distance field as it's no longer needed)
	for platform_data in candidate_platforms:
		cached_platforms.append({
			"node": platform_data.node,
			"position": platform_data.position,
			"size": platform_data.size,
			"height": platform_data.height
		})


func find_best_platform() -> void:
	"""OPTIMIZED: Find the best platform with early exit for performance

	Performance characteristics:
	- Max 20 platforms evaluated (from cache)
	- Early exit when score >= 70.0 (stops searching)
	- Simplified scoring - no loops through items
	- Context-aware frequency: 3s combat, 1.5s wander, 0.75s retreat
	- Estimated cost: <0.3ms per bot per check (worst case)
	"""
	if cached_platforms.is_empty():
		target_platform = {}
		return

	var best_platform: Dictionary = {}
	var best_score: float = -INF

	# OPTIMIZATION: Early exit if we find a "good enough" platform
	for platform_data in cached_platforms:
		var score: float = evaluate_platform_score(platform_data)

		if score > best_score:
			best_score = score
			best_platform = platform_data

			# EARLY EXIT: If platform is good enough, stop searching
			if best_score >= GOOD_ENOUGH_SCORE:
				break

	# Only target platform if score is high enough
	if best_score > 30.0:  # Threshold for platform consideration
		target_platform = best_platform
	else:
		target_platform = {}

func evaluate_platform_score(platform_data: Dictionary) -> float:
	"""NEW: Score a platform based on tactical value, safety, and accessibility"""
	if not bot or platform_data.is_empty():
		return -INF

	var score: float = 0.0
	var platform_pos: Vector3 = platform_data.position
	var platform_height: float = platform_data.height
	var distance: float = bot.global_position.distance_to(platform_pos)

	# CRITICAL FIX: Don't target platform we're already on/very close to
	# Horizontal distance check to see if we're standing on this platform
	var horizontal_dist: float = Vector2(platform_pos.x - bot.global_position.x, platform_pos.z - bot.global_position.z).length()
	var vertical_diff: float = abs(platform_height - bot.global_position.y)

	# If we're very close horizontally and at similar height, we're on this platform - skip it
	if horizontal_dist < 4.0 and vertical_diff < 2.0:
		return -INF  # Never target platform we're already on

	# Base accessibility score (prefer closer platforms, but not too far)
	if distance < 15.0:
		score += 50.0 - (distance * 2.0)
	elif distance < 30.0:
		score += 30.0 - (distance * 1.0)
	else:
		score -= (distance - 30.0) * 0.5  # Penalize very far platforms

	# Height advantage bonus (tactical value)
	var height_diff: float = platform_height - bot.global_position.y
	if height_diff > 2.0:
		# High ground advantage
		if target_player and is_instance_valid(target_player):
			# Extra bonus if enemy is below us
			var enemy_height: float = target_player.global_position.y
			if platform_height > enemy_height + 2.0:
				score += 40.0  # Significant tactical advantage
			else:
				score += 20.0  # Still good high ground
		else:
			score += 15.0  # General exploration bonus
	elif height_diff < -2.0:
		# Platform is below us - less valuable
		score -= 10.0

	# Reachability check (can we jump there?)
	var is_reachable: bool = can_reach_platform(platform_data)
	if not is_reachable:
		score -= 100.0  # Heavily penalize unreachable platforms

	# SAFETY: Platform size scoring (prefer larger platforms)
	var platform_size: Vector3 = platform_data.size
	var platform_area: float = platform_size.x * platform_size.z
	if platform_area >= 100.0:  # Large platforms (10x10 or bigger)
		score += 15.0  # Bonus for spacious platforms
	elif platform_area <= 50.0:  # Small platforms (7x7 or smaller)
		score -= 15.0  # Penalty for cramped platforms
		# Extra penalty for small platforms during combat
		if state == "ATTACK" or state == "CHASE":
			score -= 10.0  # Too small for combat maneuvering

	# SAFETY: Platform occupancy check (avoid crowded platforms)
	var occupancy: int = count_bots_on_platform(platform_data)
	if occupancy >= MAX_BOTS_PER_PLATFORM:
		score -= 60.0  # Heavy penalty - platform is full
	elif occupancy > 0:
		score -= 20.0  # Moderate penalty - platform has other bots
		# Small platforms become much worse when occupied
		if platform_area <= 64.0:  # 8x8 or smaller
			score -= 30.0  # Very cramped with another bot

	# Strategic preference bonuses (OPTIMIZED: removed expensive loops)
	match strategic_preference:
		"aggressive":
			# Aggressive bots prefer platforms near enemies
			if target_player and is_instance_valid(target_player):
				var dist_to_enemy: float = platform_pos.distance_to(target_player.global_position)
				if dist_to_enemy < 20.0:
					score += 25.0
		"defensive":
			# Defensive bots prefer safe, high platforms far from combat
			if target_player and is_instance_valid(target_player):
				var dist_to_enemy: float = platform_pos.distance_to(target_player.global_position)
				if dist_to_enemy > 25.0 and height_diff > 5.0:
					score += 30.0
		"support":
			# OPTIMIZED: Support bots prefer platforms near their current targets
			# Instead of looping through all items, just check current targets
			if target_ability and is_instance_valid(target_ability):
				var dist_to_ability: float = platform_pos.distance_to(target_ability.global_position)
				if dist_to_ability < 15.0:
					score += 20.0  # Platform near ability = good
			if target_orb and is_instance_valid(target_orb):
				var dist_to_orb: float = platform_pos.distance_to(target_orb.global_position)
				if dist_to_orb < 15.0:
					score += 15.0  # Platform near orb = good

	# Combat state modifiers
	if state == "RETREAT" and bot.health < 2:
		# Retreating bots heavily prioritize high ground for escape
		if height_diff > 3.0:
			score += 50.0
	elif state == "ATTACK" and bot.current_ability:
		# Attacking bots want high ground advantage
		if height_diff > 2.0:
			score += 30.0

	return score

func can_reach_platform(platform_data: Dictionary) -> bool:
	"""NEW: Check if bot can physically reach a platform with available movement"""
	if not bot or platform_data.is_empty():
		return false

	var platform_pos: Vector3 = platform_data.position
	var height_diff: float = platform_pos.y - bot.global_position.y
	var horizontal_dist: float = Vector2(platform_pos.x - bot.global_position.x, platform_pos.z - bot.global_position.z).length()

	# Check vertical reachability
	var max_single_jump_height: float = 6.0  # Approximate max height with one jump
	var max_double_jump_height: float = 10.0  # Approximate max height with double jump
	var max_bounce_height: float = 15.0  # Approximate max height with bounce attack

	if height_diff > max_bounce_height:
		return false  # Too high even with bounce

	# Check horizontal distance (don't want platforms too far away)
	if horizontal_dist > 20.0:
		return false  # Too far to navigate reasonably

	# Platform is reachable
	return true

func count_bots_on_platform(platform_data: Dictionary) -> int:
	"""SAFETY: Count how many bots are currently on or near a platform"""
	if platform_data.is_empty():
		return 0

	var platform_pos: Vector3 = platform_data.position
	var platform_size: Vector3 = platform_data.size
	var platform_height: float = platform_data.height

	var bot_count: int = 0

	# Check all cached players (includes bots and human players)
	for player in cached_players:
		if player == bot or not is_instance_valid(player):
			continue

		var player_pos: Vector3 = player.global_position

		# Check if player is on this platform (within bounds and at similar height)
		var horizontal_dist: float = Vector2(
			player_pos.x - platform_pos.x,
			player_pos.z - platform_pos.z
		).length()

		var height_diff: float = abs(player_pos.y - platform_height)

		# Player is on platform if:
		# - Within platform horizontal bounds (with small margin)
		# - At similar height (within 3 units above platform)
		var half_size: float = max(platform_size.x, platform_size.z) * 0.5
		if horizontal_dist <= half_size and height_diff <= 3.0:
			bot_count += 1

	return bot_count

func find_platform_for_position(item_pos: Vector3) -> Dictionary:
	"""ELEVATED ITEMS: Find which platform (if any) an item is sitting on"""
	if cached_platforms.is_empty():
		return {}

	# Check each cached platform to see if item is on it
	for platform_data in cached_platforms:
		var platform_pos: Vector3 = platform_data.position
		var platform_size: Vector3 = platform_data.size
		var platform_height: float = platform_data.height

		# Check horizontal bounds
		var horizontal_dist: float = Vector2(
			item_pos.x - platform_pos.x,
			item_pos.z - platform_pos.z
		).length()

		# Check height (item should be slightly above platform surface)
		var height_diff: float = item_pos.y - platform_height

		# Item is on platform if:
		# - Within platform horizontal bounds
		# - Height is 0.5-4 units above platform (item floating slightly, or on surface)
		var half_size: float = max(platform_size.x, platform_size.z) * 0.5
		if horizontal_dist <= half_size and height_diff >= -0.5 and height_diff <= 4.0:
			return platform_data

	return {}  # Item not on any known platform

# ============================================================================
# JUMP PAD SYSTEM (Quake 3-style vertical mobility)
# ============================================================================

func refresh_jump_pad_cache() -> void:
	"""Cache nearby jump pads for tactical mobility"""
	cached_jump_pads.clear()

	if not bot:
		return

	var world: Node = get_tree().get_root().get_node_or_null("World")
	if not world:
		return

	# Find jump pads in scene (assumed to be in "jump_pads" group)
	var all_jump_pads: Array = get_tree().get_nodes_in_group("jump_pads")
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
	elif (state == "COLLECT_ABILITY" or state == "COLLECT_ORB"):
		var collectible: Node = target_ability if target_ability and is_instance_valid(target_ability) else target_orb
		if not collectible or not is_instance_valid(collectible):
			return
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

	elif (state == "COLLECT_ABILITY" or state == "COLLECT_ORB"):
		var collectible: Node = target_ability if target_ability and is_instance_valid(target_ability) else target_orb
		if not collectible or not is_instance_valid(collectible):
			return score
		var target_collectible = collectible
		# Check if jump pad helps reach elevated item
		var item_pos: Vector3 = target_collectible.global_position
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
# TELEPORTER SYSTEM (Quake 3-style traversal)
# ============================================================================

func refresh_teleporter_cache() -> void:
	"""Cache nearby teleporters for tactical traversal"""
	cached_teleporters.clear()

	if not bot:
		return

	var world: Node = get_tree().get_root().get_node_or_null("World")
	if not world:
		return

	# Find teleporters in scene (assumed to be in "teleporters" group)
	var all_teleporters: Array = get_tree().get_nodes_in_group("teleporters")

	# Filter by validity and add to cache
	for teleporter in all_teleporters:
		if not is_instance_valid(teleporter) or not teleporter.is_inside_tree():
			continue

		cached_teleporters.append(teleporter)

	# Limit cache size
	if cached_teleporters.size() > MAX_CACHED_TELEPORTERS:
		cached_teleporters = cached_teleporters.slice(0, MAX_CACHED_TELEPORTERS)

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
	elif (state == "CHASE" or state == "COLLECT_ABILITY" or state == "COLLECT_ORB"):
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
		elif (state == "COLLECT_ABILITY" or state == "COLLECT_ORB"):
			var collectible: Node = target_ability if target_ability and is_instance_valid(target_ability) else target_orb
			if not collectible or not is_instance_valid(collectible):
				return score
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

func validate_bounce_properties() -> bool:
	"""VALIDATION: Check if bot has required properties for bounce attack"""
	if not bot:
		return false
	return "is_bouncing" in bot and bot.has_method("start_bounce")

# ============================================================================
# VALIDATION HELPERS (for safe property/method access)
# ============================================================================

func get_bot_health() -> int:
	"""VALIDATION: Safely get bot health with fallback"""
	if not bot or not "health" in bot:
		return 5  # Default healthy value
	return bot.health

func get_player_health(player: Node) -> int:
	"""VALIDATION: Safely get player health with fallback"""
	if not player or not is_instance_valid(player) or not "health" in player:
		return 5  # Default value
	return player.health

func has_property(node: Node, property: String) -> bool:
	"""VALIDATION: Safely check if node has a property"""
	if not node or not is_instance_valid(node):
		return false
	return property in node

func has_method_safe(node: Node, method: String) -> bool:
	"""VALIDATION: Safely check if node has a method"""
	if not node or not is_instance_valid(node):
		return false
	return node.has_method(method)

# ============================================================================
# AGGRESSION & DECISION MAKING
# ============================================================================

func calculate_current_aggression() -> float:
	"""NEW: Dynamic aggression calculation (OpenArena-inspired) with validation guards"""
	var current_aggression: float = aggression_level

	# VALIDATION: Health penalty (low health reduces aggression)
	var bot_health: int = get_bot_health()
	if bot_health < 3:
		current_aggression *= 0.3  # Severe penalty
	elif bot_health < 5:
		current_aggression *= 0.6  # Moderate penalty

	# VALIDATION: Enemy health bonus (if we're healthier, be more aggressive)
	if target_player and is_instance_valid(target_player):
		var enemy_health: int = get_player_health(target_player)
		if bot_health > enemy_health + 2:
			current_aggression *= 1.3  # We have advantage!
		elif bot_health < enemy_health - 2:
			current_aggression *= 0.7  # Enemy has advantage

	# Caution level affects aggression
	current_aggression *= (1.0 - caution_level * 0.3)

	return clamp(current_aggression, 0.1, 1.5)

func should_retreat() -> bool:
	"""NEW: Comprehensive retreat evaluation (OpenArena-inspired) with validation guards"""
	if not target_player or not is_instance_valid(target_player):
		return false

	var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)

	# VALIDATION: Critical health retreat
	var bot_health: int = get_bot_health()
	if bot_health <= 2:
		return distance_to_target < aggro_range * 0.9

	# VALIDATION: Health-based retreat threshold (affected by caution)
	var retreat_health_threshold: int = int(3 + caution_level * 2)  # 3-5 health
	if bot_health <= retreat_health_threshold:
		# Check enemy health advantage
		var enemy_health: int = get_player_health(target_player)
		if enemy_health >= bot_health + 2:
			return distance_to_target < aggro_range * 0.7

	# VALIDATION: No ability = retreat if enemy is close
	if not has_property(bot, "current_ability") or not bot.current_ability:
		if distance_to_target < attack_range * 1.5:
			return true

	# Defensive bots retreat earlier
	if strategic_preference == "defensive" and bot_health <= 4:
		return distance_to_target < aggro_range * 0.8

	return false

func should_chase() -> bool:
	"""NEW: Chase evaluation (OpenArena-inspired) with validation guards"""
	if not target_player or not is_instance_valid(target_player):
		return false

	# VALIDATION: Check if bot has ability
	if not has_property(bot, "current_ability") or not bot.current_ability:
		return false

	var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)

	# VALIDATION: Always chase if enemy is weak and we're healthy
	var enemy_health: int = get_player_health(target_player)
	var bot_health: int = get_bot_health()
	if enemy_health <= 2 and bot_health >= 4:
		return distance_to_target < aggro_range * 1.5

	# Aggressive bots chase more eagerly
	if strategic_preference == "aggressive":
		return distance_to_target < aggro_range * 1.2

	# Standard chase range
	return distance_to_target < aggro_range

func should_use_platform_in_combat() -> bool:
	"""NEW: Determine if we should seek platform during combat"""
	if target_platform.is_empty() or not target_player or not is_instance_valid(target_player):
		return false

	var platform_pos: Vector3 = target_platform.position
	var platform_height: float = target_platform.height

	# Check if platform gives tactical advantage
	var enemy_height: float = target_player.global_position.y
	var height_advantage: float = platform_height - enemy_height

	# Prefer platforms if they give significant height advantage
	if height_advantage > 3.0:
		# Defensive bots always prefer high ground
		if strategic_preference == "defensive":
			return true
		# Others prefer it probabilistically based on health
		if bot.health <= 2:
			return randf() < 0.8  # Low health = seek safety
		else:
			return randf() < 0.4  # Moderate chance

	return false

func update_state() -> void:
	"""IMPROVED: Better state prioritization with combat evaluators"""

	# PRIORITY 0: ABSOLUTE #1 - GET AN ABILITY IMMEDIATELY IF WE DON'T HAVE ONE
	# Without an ability, the bot CANNOT attack and is useless in combat
	# This overrides EVERYTHING including retreat, combat, and all other states
	if not bot.current_ability:
		# If we have a target ability, go get it NOW
		if target_ability and is_instance_valid(target_ability):
			state = "COLLECT_ABILITY"
			return
		else:
			# No ability and no target ability - search for one immediately
			find_nearest_ability()
			if target_ability and is_instance_valid(target_ability):
				state = "COLLECT_ABILITY"
				return
			# Still no ability found - wander to search for one
			state = "WANDER"
			return

	# Check if we have a valid combat target (only relevant after we have an ability)
	var has_combat_target: bool = target_player and is_instance_valid(target_player)
	var distance_to_target: float = INF
	if has_combat_target:
		distance_to_target = bot.global_position.distance_to(target_player.global_position)

	# Priority 1: Use retreat evaluator (now that we have an ability)
	if has_combat_target and should_retreat():
		state = "RETREAT"
		retreat_timer = randf_range(2.5, 4.5)
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
			# IMPROVED: Visibility check with hysteresis
			if is_target_visible(target_orb.global_position, target_orb):
				state = "COLLECT_ORB"
				return

	# Priority 4: Chase if enemy in aggro range (use evaluator)
	if bot.current_ability and has_combat_target and should_chase():
		# NEW: Check if we should seek high ground instead of direct chase
		if not target_platform.is_empty() and should_use_platform_in_combat():
			is_approaching_platform = true
			# Continue to CHASE but with platform navigation overlay
		state = "CHASE"
		return

	# NEW: Priority 4.5: Navigate to tactical platform during retreat
	if state == "RETREAT" and not target_platform.is_empty():
		# Use platform navigation during retreat for escape/high ground
		is_approaching_platform = true

	# Priority 5: Combat if we HAVE an ability but enemy far
	if bot.current_ability and has_combat_target:
		if distance_to_target < attack_range * 1.2:
			state = "ATTACK"
		elif distance_to_target < aggro_range:
			state = "CHASE"
		else:
			# NEW: Consider platform navigation when wandering
			if not target_platform.is_empty() and randf() < 0.3:
				is_approaching_platform = true
			state = "WANDER"
	else:
		# NEW: No combat - explore platforms more actively
		if not target_platform.is_empty() and randf() < 0.4:
			is_approaching_platform = true
		state = "WANDER"

func do_wander(delta: float) -> void:
	"""FIXED: Wander with overhead slope avoidance and platform navigation"""
	# NEW: Check if we should navigate to a platform
	if is_approaching_platform and not target_platform.is_empty():
		navigate_to_platform(delta)
		return

	if wander_timer <= 0.0:
		var angle: float = randf() * TAU
		var distance: float = randf_range(wander_radius * 0.5, wander_radius)
		wander_target = bot.global_position + Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		wander_timer = randf_range(2.5, 5.0)
		find_target()

	# FIXED: Check for overhead slopes before moving
	var direction: Vector3 = (wander_target - bot.global_position).normalized()
	direction.y = 0

	if direction.length() > 0.1:
		var obstacle_info: Dictionary = check_obstacle_in_direction(direction, 2.5)

		# FIXED: If overhead slope detected, find new wander target
		if obstacle_info.has_obstacle and "is_overhead_slope" in obstacle_info and obstacle_info.is_overhead_slope:
			# Pick a new wander direction away from overhead slope
			var safe_dir: Vector3 = find_safe_direction_from_edge(direction)
			if safe_dir != Vector3.ZERO:
				wander_target = bot.global_position + safe_dir * wander_radius * 0.7
				wander_timer = randf_range(2.5, 5.0)

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

	# NEW: If seeking high ground platform, navigate there first
	if is_approaching_platform and not target_platform.is_empty():
		navigate_to_platform(delta)
		# Still look at enemy while navigating
		look_at_target_smooth(target_player.global_position, delta)
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
		is_approaching_platform = false  # Reset platform navigation
		return

	# NEW: If we have a safe platform to retreat to, navigate there
	if is_approaching_platform and not target_platform.is_empty():
		navigate_to_platform(delta)
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

func navigate_to_platform(delta: float) -> void:
	"""SAFETY: Navigate to target platform with smart jumping and landing stabilization"""
	if target_platform.is_empty():
		is_approaching_platform = false
		platform_jump_prepared = false
		on_platform = false
		return

	var platform_pos: Vector3 = target_platform.position
	var platform_height: float = target_platform.height
	var platform_size: Vector3 = target_platform.size

	var bot_pos: Vector3 = bot.global_position
	var horizontal_dist: float = Vector2(platform_pos.x - bot_pos.x, platform_pos.z - bot_pos.z).length()
	var height_diff: float = platform_height - bot_pos.y

	# SAFETY: Check if we've reached the platform
	if horizontal_dist < platform_size.x * 0.4 and abs(height_diff) < 2.0:
		# Successfully on platform! Start stabilization period
		if not on_platform:
			on_platform = true
			platform_stabilize_timer = PLATFORM_STABILIZE_TIME

		# STABILIZATION: Reduce movement during stabilization period
		if platform_stabilize_timer > 0.0:
			# Apply gentle braking to slow down
			if "linear_velocity" in bot:
				var horizontal_vel: Vector3 = Vector3(bot.linear_velocity.x, 0, bot.linear_velocity.z)
				if horizontal_vel.length() > 2.0:
					var braking: Vector3 = -horizontal_vel.normalized() * bot.current_roll_force * 0.3
					bot.apply_central_force(braking)
			return  # Don't move while stabilizing
		else:
			# Stabilization complete - clear platform navigation
			is_approaching_platform = false
			platform_jump_prepared = false
			on_platform = false
			target_platform = {}  # Clear target
			return

	# Cancel if platform is too far (re-evaluate)
	if horizontal_dist > 30.0:
		is_approaching_platform = false
		platform_jump_prepared = false
		on_platform = false
		return

	# Look at platform while navigating
	look_at_target_smooth(platform_pos, delta)

	# SAFETY: Adjust approach speed based on platform size
	var platform_area: float = platform_size.x * platform_size.z
	var approach_speed_mult: float = 1.0
	if platform_area <= 50.0:  # Small platforms (7x7 or smaller)
		approach_speed_mult = 0.6  # Much slower approach
	elif platform_area <= 80.0:  # Medium platforms (9x9 or smaller)
		approach_speed_mult = 0.8  # Moderately slower approach

	# Approach logic based on height difference
	if height_diff > 1.0:
		# Platform is above us - need to jump onto it
		if horizontal_dist > 8.0:
			# Far away - move closer before jumping
			move_towards(platform_pos, 0.8 * approach_speed_mult)
			platform_jump_prepared = false
		elif horizontal_dist > 3.0:
			# Medium distance - prepare to jump
			move_towards(platform_pos, 0.6 * approach_speed_mult)

			# Execute jump based on height
			if not platform_jump_prepared and obstacle_jump_timer <= 0.0:
				platform_jump_prepared = true

				if height_diff > 10.0:
					# Very high - use bounce attack
					if bounce_cooldown_timer <= 0.0:
						use_bounce_attack()
						obstacle_jump_timer = 0.5
				elif height_diff > 6.0:
					# High - use double jump (first jump, second will happen automatically when needed)
					bot_jump()
					# Second jump will be triggered by height check in subsequent frames
					obstacle_jump_timer = 0.3  # Short cooldown for immediate second jump
				else:
					# Medium height - single jump should work
					bot_jump()
					obstacle_jump_timer = 0.5
		else:
			# Very close - jump straight up
			if not platform_jump_prepared:
				bot_jump()
				platform_jump_prepared = true
				obstacle_jump_timer = 0.5
			# Apply upward force while jumping (very gentle for small platforms)
			move_towards(platform_pos, 0.4 * approach_speed_mult)
	elif height_diff < -2.0:
		# Platform is below us - carefully approach edge
		if horizontal_dist > 5.0:
			move_towards(platform_pos, 0.7 * approach_speed_mult)
		else:
			# At edge - drop down very carefully (especially on small platforms)
			move_towards(platform_pos, 0.3 * approach_speed_mult)
	else:
		# Platform at similar height - just move toward it
		move_towards(platform_pos, 0.8 * approach_speed_mult)

		# Small jump if there's a slight elevation
		if height_diff > 0.5 and obstacle_jump_timer <= 0.0:
			bot_jump()
			obstacle_jump_timer = 0.4

func do_collect_ability(delta: float) -> void:
	"""Move towards ability with elevated surface handling"""
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

	# ELEVATED ITEM HANDLING: Check if ability is on a platform we need to reach
	if height_diff > 4.0 and not is_approaching_platform:
		# Item is significantly elevated - check if it's on a known platform
		var platform_for_item: Dictionary = find_platform_for_position(target_ability.global_position)
		if not platform_for_item.is_empty():
			# Item is on a platform! Navigate to platform first
			target_platform = platform_for_item
			is_approaching_platform = true
			navigate_to_platform(delta)
			return

	# If we're already approaching platform, continue that navigation
	if is_approaching_platform and not target_platform.is_empty():
		navigate_to_platform(delta)
		return

	# Move towards ability urgently
	move_towards(target_ability.global_position, 1.0)

	# ENHANCED: Height-based jumping for elevated items
	if action_timer <= 0.0:
		if height_diff > 10.0:
			# Very high - use bounce attack
			if bounce_cooldown_timer <= 0.0:
				use_bounce_attack()
				action_timer = randf_range(0.5, 0.8)
		elif height_diff > 5.0:
			# High - use double jump
			if bot.jump_count == 0:
				bot_jump()
				action_timer = 0.2  # Quick follow-up for second jump
			elif bot.jump_count < bot.max_jumps:
				bot_jump()
				action_timer = randf_range(0.4, 0.6)
		elif height_diff > 1.5:
			# Medium elevation - single jump
			bot_jump()
			action_timer = randf_range(0.3, 0.5)
		elif height_diff > 0.7 or randf() < 0.4:
			# Small elevation - occasional jump
			bot_jump()
			action_timer = randf_range(0.4, 0.8)

func do_collect_orb(delta: float) -> void:
	"""Move towards orb with elevated surface handling"""
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

	# ELEVATED ITEM HANDLING: Check if orb is on a platform we need to reach
	if height_diff > 4.0 and not is_approaching_platform:
		# Item is significantly elevated - check if it's on a known platform
		var platform_for_item: Dictionary = find_platform_for_position(target_orb.global_position)
		if not platform_for_item.is_empty():
			# Item is on a platform! Navigate to platform first
			target_platform = platform_for_item
			is_approaching_platform = true
			navigate_to_platform(delta)
			return

	# If we're already approaching platform, continue that navigation
	if is_approaching_platform and not target_platform.is_empty():
		navigate_to_platform(delta)
		return

	# Move towards orb
	move_towards(target_orb.global_position, 1.0)

	# ENHANCED: Height-based jumping for elevated items
	if action_timer <= 0.0:
		if height_diff > 10.0:
			# Very high - use bounce attack
			if bounce_cooldown_timer <= 0.0:
				use_bounce_attack()
				action_timer = randf_range(0.5, 0.8)
		elif height_diff > 5.0:
			# High - use double jump
			if bot.jump_count == 0:
				bot_jump()
				action_timer = 0.2  # Quick follow-up for second jump
			elif bot.jump_count < bot.max_jumps:
				bot_jump()
				action_timer = randf_range(0.4, 0.6)
		elif height_diff > 1.5:
			# Medium elevation - single jump
			bot_jump()
			action_timer = randf_range(0.3, 0.5)
		elif height_diff > 0.7 or randf() < 0.35:
			# Small elevation - occasional jump
			bot_jump()
			action_timer = randf_range(0.4, 0.8)

func strafe_around_target(preferred_distance: float) -> void:
	"""Strafe around target while maintaining distance"""
	if not target_player or not is_instance_valid(target_player):
		return

	# NEW: Skill-based strafe timing (OpenArena formula: 0.4 + (1 - skill) * 0.2)
	if strafe_timer <= 0.0:
		strafe_direction *= -1
		var base_strafe_time: float = 0.4 + (1.0 - bot_skill) * 0.2
		var variation: float = randf_range(-0.15, 0.15)
		strafe_timer = base_strafe_time + variation

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
		# FIXED: Check for overhead slopes before moving
		var obstacle_info: Dictionary = check_obstacle_in_direction(movement, 2.5)
		if obstacle_info.has_obstacle and "is_overhead_slope" in obstacle_info and obstacle_info.is_overhead_slope:
			# Overhead slope detected! Reverse strafe and find safe direction
			strafe_direction *= -1
			var safe_dir: Vector3 = find_safe_direction_from_edge(movement)
			if safe_dir != Vector3.ZERO:
				movement = safe_dir
			else:
				# Apply braking
				if "linear_velocity" in bot:
					var braking_force: Vector3 = -bot.linear_velocity * 1.2
					braking_force.y = 0
					bot.apply_central_force(braking_force)
				return

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

func get_ability_proficiency_score(ability_name: String, distance: float) -> float:
	"""NEW: Calculate ability proficiency score (OpenArena-inspired weapon scoring)"""
	var base_score: float = ABILITY_SCORES.get(ability_name, 50.0)

	# Distance optimization (prefer abilities at their optimal range)
	var optimal_range: float = get_optimal_combat_distance()
	var distance_diff: float = abs(distance - optimal_range)
	var distance_penalty: float = distance_diff * 2.0  # Lose 2 points per unit away from optimal
	var distance_score: float = max(0.0, base_score - distance_penalty)

	# Skill affects proficiency (expert bots use all weapons better)
	var skill_multiplier: float = 0.7 + (bot_skill * 0.5)  # 0.7x to 1.2x
	distance_score *= skill_multiplier

	# Strategic preference affects weapon choice
	match strategic_preference:
		"aggressive":
			# Prefer close-range abilities
			if ability_name in ["Sword", "Explosion"]:
				distance_score *= 1.2
		"defensive":
			# Prefer long-range abilities
			if ability_name in ["Cannon"]:
				distance_score *= 1.25
		"balanced":
			# Prefer mid-range abilities
			if ability_name in ["Dash Attack"]:
				distance_score *= 1.15

	return distance_score

func use_ability_smart(distance_to_target: float) -> void:
	"""IMPROVED: Smart ability usage with proficiency scoring and lead prediction"""
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

	# NEW: Calculate proficiency score for this ability at current distance
	var proficiency_score: float = get_ability_proficiency_score(ability_name, distance_to_target)
	var usage_threshold: float = 50.0  # Minimum score to use ability

	# Check if ability supports charging
	var can_charge: bool = false
	if "supports_charging" in bot.current_ability:
		can_charge = bot.current_ability.supports_charging and bot.current_ability.max_charge_time > 0.1
	elif bot.current_ability.has_method("start_charge"):
		can_charge = true

	# NEW: Use current aggression for decision-making
	var current_aggression: float = calculate_current_aggression()

	# IMPROVED: Ability-specific logic with proficiency scoring
	# FIXED: Reduced randomness - bots now use abilities much more consistently when conditions are met
	match ability_name:
		"Cannon":
			# Lead prediction + alignment check before firing
			if target_player and is_instance_valid(target_player):
				var predicted_pos: Vector3 = calculate_lead_position()
				var predicted_distance: float = bot.global_position.distance_to(predicted_pos)

				if predicted_distance > 4.0 and predicted_distance < 40.0 and is_aligned_with_target(predicted_pos, 10.0):
					# INCREASED: Much higher usage chance for cannons (projectile weapon should fire often)
					var usage_chance: float = (proficiency_score / 100.0) * 0.95  # 95% at max proficiency
					should_use = randf() < usage_chance
					should_charge = false  # Never charge cannon
			elif distance_to_target > 4.0 and distance_to_target < 40.0 and is_aligned_with_target(target_player.global_position, 10.0):
				should_use = randf() < (proficiency_score / 100.0) * 0.9
				should_charge = false
		"Sword":
			# Sword requires close range AND proper alignment with target
			# CRITICAL: Check height difference - melee doesn't work well from above
			if target_player and is_instance_valid(target_player):
				var height_diff: float = abs(target_player.global_position.y - bot.global_position.y)
				# Only use sword if height difference is small (< 3 units)
				if distance_to_target < 6.0 and height_diff < 3.0 and proficiency_score > usage_threshold:
					# Check if we're facing the target (important for melee!)
					if is_aligned_with_target(target_player.global_position, 20.0):
						# INCREASED: Swing sword much more reliably when in range and aligned
						var usage_chance: float = (proficiency_score / 100.0) * 0.9  # 90% at max proficiency
						should_use = randf() < usage_chance
						should_charge = can_charge and distance_to_target > 3.0 and randf() < 0.6
		"Dash Attack":
			# Dash attack needs tight alignment - bot must be facing target before dashing
			# CRITICAL: Check height difference - dashing from high platforms is ineffective
			if target_player and is_instance_valid(target_player):
				var height_diff: float = abs(target_player.global_position.y - bot.global_position.y)
				# Only dash if height difference is reasonable (< 4 units)
				if distance_to_target > 4.0 and distance_to_target < 18.0 and height_diff < 4.0 and proficiency_score > usage_threshold:
					# Tighter alignment requirement (10°) for dash attack to look natural
					if is_aligned_with_target(target_player.global_position, 10.0):
						# INCREASED: Dash much more reliably when aligned (was too passive)
						var usage_chance: float = (proficiency_score / 100.0) * 0.85  # 85% at max proficiency
						should_use = randf() < usage_chance
						should_charge = can_charge and distance_to_target > 8.0 and randf() < 0.7
		"Explosion":
			# Explosion is AoE but still benefits from rough alignment
			# CRITICAL: Check height difference - explosion doesn't reach far vertically
			if target_player and is_instance_valid(target_player):
				var height_diff: float = abs(target_player.global_position.y - bot.global_position.y)
				# Only explode if height difference is small (< 3 units)
				if distance_to_target < 8.0 and height_diff < 3.0 and proficiency_score > usage_threshold:
					if is_aligned_with_target(target_player.global_position, 30.0):
						# INCREASED: Use explosion more often (was way too passive at 50%)
						var usage_chance: float = (proficiency_score / 100.0) * 0.8  # 80% at max proficiency
						should_use = randf() < usage_chance
						should_charge = can_charge and distance_to_target < 7.0 and randf() < 0.5
		_:
			if distance_to_target < 20.0 and proficiency_score > usage_threshold:
				# INCREASED: Generic abilities should be used more often
				should_use = randf() < (proficiency_score / 100.0) * 0.7

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

func calculate_lead_position() -> Vector3:
	"""IMPROVED: Skill-based lead prediction (OpenArena-inspired accuracy variation)"""
	if not target_player or not is_instance_valid(target_player):
		return bot.global_position

	# Get target velocity
	var target_velocity: Vector3 = Vector3.ZERO
	if "linear_velocity" in target_player:
		target_velocity = target_player.linear_velocity

	# Skip lead if target not moving much
	if target_velocity.length() < 2.0:
		return target_player.global_position

	# NEW: Only predict if bot skill is high enough (OpenArena uses > 0.8 threshold)
	if bot_skill < 0.65:
		# Low-skill bots don't predict well
		return target_player.global_position

	# Lead prediction with proper projectile speed
	var projectile_speed: float = 50.0  # Average cannon projectile speed
	var current_distance: float = bot.global_position.distance_to(target_player.global_position)
	var time_to_hit: float = current_distance / projectile_speed

	# NEW: Skill-based compensation (70%-95% based on aim_accuracy)
	var predicted_pos: Vector3 = target_player.global_position + target_velocity * time_to_hit * aim_accuracy

	return predicted_pos

func move_towards(target_pos: Vector3, speed_mult: float = 1.0) -> void:
	"""IMPROVED: Move bot towards target with obstacle and player avoidance"""
	if not bot:
		return

	var direction: Vector3 = (target_pos - bot.global_position).normalized()
	direction.y = 0


	var height_diff: float = target_pos.y - bot.global_position.y

	if direction.length() > 0.1:
		# REMOVED: Player avoidance was causing bot clustering/huddling
		# Bots were repelling from each other, creating oscillating huddles
		# In FPS games, bots SHOULD cluster around objectives - that's normal behavior

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
			# IMPROVED: Avoid overhead slopes that could trap the bot
			if "is_overhead_slope" in obstacle_info and obstacle_info.is_overhead_slope:
				# Dangerous overhead slope - find safe direction
				var safe_dir: Vector3 = find_safe_direction_from_edge(direction)
				if safe_dir != Vector3.ZERO:
					direction = safe_dir
					speed_mult *= 0.4  # Move slowly when avoiding overhead slopes
				else:
					# No safe direction - reverse and brake
					if "linear_velocity" in bot:
						var braking_force: Vector3 = -bot.linear_velocity * 1.5
						braking_force.y = 0
						bot.apply_central_force(braking_force)
					bot.apply_central_force(-direction * bot.current_roll_force * 1.0)
					return

			# Handle slopes/platforms - jump onto them (only if NOT overhead)
			elif obstacle_info.is_slope or obstacle_info.is_platform:
				if obstacle_jump_timer <= 0.0:
					bot_jump()
					obstacle_jump_timer = 0.3
					bot.apply_central_force(direction * bot.current_roll_force * speed_mult * 1.2)
					return
				else:
					bot.apply_central_force(direction * bot.current_roll_force * speed_mult)
					return

			# Handle walls - back up or jump
			elif "is_wall" in obstacle_info and obstacle_info.is_wall:
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

func is_aligned_with_target(target_position: Vector3, tolerance_degrees: float = 15.0) -> bool:
	"""NEW: Check if bot is aligned with target within tolerance (prevents premature firing)"""
	if not bot:
		return false

	var target_dir: Vector3 = target_position - bot.global_position
	target_dir.y = 0

	if target_dir.length() < 0.1:
		return false

	var desired_angle: float = atan2(target_dir.x, target_dir.z)
	var current_angle: float = bot.rotation.y

	var angle_diff: float = desired_angle - current_angle

	# Normalize angle to [-PI, PI]
	while angle_diff > PI:
		angle_diff -= TAU
	while angle_diff < -PI:
		angle_diff += TAU

	# Check if within tolerance
	return abs(angle_diff) < deg_to_rad(tolerance_degrees)

func look_at_target_smooth(target_position: Vector3, delta: float) -> void:
	"""IMPROVED: Physics-safe rotation with personality-based turn speed"""
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

	# NEW: Apply personality-based turn speed factor
	var turn_multiplier: float = 10.0 * turn_speed_factor
	var max_turn_speed: float = 15.0 * turn_speed_factor

	# Calculate target angular velocity with personality
	var target_angular_velocity: float = clamp(angle_diff * turn_multiplier / delta, -max_turn_speed, max_turn_speed)

	# Lerp current angular velocity toward target for smooth damping
	bot.angular_velocity.y = lerp(bot.angular_velocity.y, target_angular_velocity, 0.3)

func get_eye_position() -> Vector3:
	"""VISION: Get stable eye position for line of sight checks"""
	if not bot:
		return Vector3.ZERO
	return bot.global_position + Vector3.UP * BOT_EYE_HEIGHT

func is_in_field_of_view(target_pos: Vector3) -> bool:
	"""VISION: Check if target is within bot's field of view

	NOTE: Marbles are spherical and can perceive in all directions.
	This function returns true for 360° awareness - kept for future
	directional constraints if needed (e.g., sensors, camera attachments).
	"""
	if not bot:
		return false

	# Marbles have 360° awareness - no directional restrictions
	return true

func raycast_line_of_sight(target_pos: Vector3) -> bool:
	"""VISION: Perform actual raycast to check obstruction (uses cached space_state for performance)"""
	if not bot:
		return false

	# PERFORMANCE: Use cached space state if available
	var space_state: PhysicsDirectSpaceState3D = cached_space_state
	if not space_state:
		space_state = bot.get_world_3d().direct_space_state

	var start: Vector3 = get_eye_position()
	var end: Vector3 = target_pos

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, end)
	query.exclude = [bot]
	query.collision_mask = 1  # Only world geometry blocks vision

	var result: Dictionary = space_state.intersect_ray(query)

	# Visible if no hit or hit is very close to target (within pickup range)
	if not result:
		return true

	var hit_distance: float = start.distance_to(result.position)
	var target_distance: float = start.distance_to(target_pos)

	return hit_distance >= target_distance - 1.0

func is_target_visible(target_pos: Vector3, target_node: Node = null) -> bool:
	"""VISION: Check if target is visible with hysteresis for stability

	Uses three-stage check:
	1. Field of view (can bot see this direction?)
	2. Raycast line of sight (is path clear?)
	3. Hysteresis (keep seeing briefly after obstruction)
	"""
	if not bot:
		return false

	var current_time: float = Time.get_ticks_msec() / 1000.0

	# Stage 1: Field of view check (fast rejection)
	if not is_in_field_of_view(target_pos):
		# Target behind bot - not visible
		if target_node and target_node in last_seen_targets:
			last_seen_targets.erase(target_node)
		return false

	# Stage 2: Raycast line of sight check
	var has_line_of_sight: bool = raycast_line_of_sight(target_pos)

	if has_line_of_sight:
		# Can see target - update last seen time
		if target_node:
			last_seen_targets[target_node] = current_time
		return true

	# Stage 3: Hysteresis - check if we saw it recently
	if target_node and target_node in last_seen_targets:
		var time_since_seen: float = current_time - last_seen_targets[target_node]
		if time_since_seen < VISION_HYSTERESIS_TIME:
			# Still within hysteresis window - treat as visible
			return true
		else:
			# Hysteresis expired - no longer visible
			last_seen_targets.erase(target_node)
			return false

	# Not visible and no recent sighting
	return false

func find_target() -> void:
	"""NEW: Advanced target prioritization (OpenArena-inspired weighted scoring)"""
	var best_player: Node = null
	var best_score: float = -INF

	for player in cached_players:
		if player == bot or not is_instance_valid(player):
			continue

		var score: float = calculate_target_priority(player)
		if score > best_score:
			best_score = score
			best_player = player

	target_player = best_player

func calculate_target_priority(player: Node) -> float:
	"""NEW: Calculate target priority score (OpenArena-inspired)"""
	var score: float = 100.0

	# Distance factor (closer = higher priority)
	var distance: float = bot.global_position.distance_to(player.global_position)
	var distance_score: float = max(0.0, 100.0 - distance * 2.0)  # Lose 2 points per unit
	score += distance_score

	# Health differential (weaker enemies = higher priority for aggressive bots)
	if "health" in player:
		var enemy_health: float = player.health
		if enemy_health < bot.health:
			score += (bot.health - enemy_health) * 10.0 * aggression_level
		else:
			# Penalize stronger enemies if we're cautious
			score -= (enemy_health - bot.health) * 5.0 * caution_level

	# Visibility bonus
	if is_target_visible(player.global_position):
		score += 50.0

	# Attack range bonus (prioritize enemies in optimal attack range)
	var optimal_distance: float = get_optimal_combat_distance()
	if abs(distance - optimal_distance) < 5.0:
		score += 40.0

	# Strategic preference modifiers
	match strategic_preference:
		"aggressive":
			# Prefer closer targets for rushing
			if distance < 15.0:
				score += 30.0
		"defensive":
			# Prefer targets at safer distances
			if distance > 10.0 and distance < 25.0:
				score += 25.0
		"support":
			# Prefer weaker targets
			if "health" in player and player.health < 4:
				score += 35.0

	return score

func calculate_item_acquisition_cost(item_pos: Vector3) -> float:
	"""COST-BENEFIT: Calculate effort/risk required to reach an item (with aggression scaling)"""
	if not bot:
		return INF

	var cost: float = 0.0

	# NEW: Aggression-based cost multiplier
	# Aggressive bots (0.8-0.9) care less about risks: 0.7-0.76x cost
	# Defensive bots (0.6-0.7) are more cautious: 1.0-1.12x cost
	# Formula: 1.0 - (aggression_level - 0.6) * 0.75 = maps 0.6→1.0, 0.9→0.775
	var aggression_mult: float = 1.0 - (aggression_level - 0.6) * 0.75
	aggression_mult = clamp(aggression_mult, 0.7, 1.2)

	# Factor 1: Distance cost (travel time) - scaled by aggression
	var distance: float = bot.global_position.distance_to(item_pos)
	cost += distance * 2.0 * aggression_mult  # Each unit of distance = 2 cost points

	# Factor 2: Height/elevation cost (difficulty) - scaled by aggression
	var height_diff: float = item_pos.y - bot.global_position.y
	if height_diff > 0.0:
		if height_diff > 15.0:
			cost += 60.0 * aggression_mult  # Very high - requires bounce attack + platform navigation
		elif height_diff > 8.0:
			cost += 40.0 * aggression_mult  # High - requires platform navigation
		elif height_diff > 4.0:
			cost += 20.0 * aggression_mult  # Medium - requires double jump or platform
		else:
			cost += height_diff * 3.0 * aggression_mult  # Small elevation - proportional cost

	# Factor 3: Platform-specific costs (if item is on a platform) - scaled by aggression
	var platform_for_item: Dictionary = find_platform_for_position(item_pos)
	if not platform_for_item.is_empty():
		var platform_size: Vector3 = platform_for_item.size
		var platform_area: float = platform_size.x * platform_size.z

		# Small platforms are harder/riskier (aggressive bots less deterred)
		if platform_area <= 50.0:
			cost += 30.0 * aggression_mult  # Very small platform (6x6, 7x7) - high risk
		elif platform_area <= 80.0:
			cost += 15.0 * aggression_mult  # Medium platform (8x8, 9x9) - moderate risk

		# Occupied platforms are contested/dangerous (aggressive bots less deterred)
		var occupancy: int = count_bots_on_platform(platform_for_item)
		if occupancy >= 2:
			cost += 100.0 * aggression_mult  # Full platform - likely impossible to access
		elif occupancy == 1:
			cost += 40.0 * aggression_mult  # 1 bot present - contested, might lead to combat

	# Factor 4: Combat proximity cost (danger zone) - scaled by aggression
	if target_player and is_instance_valid(target_player):
		var dist_to_enemy: float = item_pos.distance_to(target_player.global_position)
		if dist_to_enemy < 10.0:
			cost += 50.0 * aggression_mult  # Item very close to enemy - high risk
		elif dist_to_enemy < 20.0:
			cost += 25.0 * aggression_mult  # Item near enemy - moderate risk

	# Factor 5: Visibility cost (if can't see it, it's harder) - scaled by aggression
	if not is_target_visible(item_pos):
		cost += 15.0 * aggression_mult  # Can't see item - need to navigate blind

	return cost

func calculate_ability_value() -> float:
	"""COST-BENEFIT: Calculate value of acquiring an ability"""
	var value: float = 0.0

	# Base value: Abilities are always valuable
	value += 100.0

	# CRITICAL: No ability = extremely high value
	if not bot.current_ability:
		value += 150.0  # Total 250 - will pursue almost any ability

	# Strategic preference bonuses
	match strategic_preference:
		"aggressive":
			value += 30.0  # Aggressive bots highly value abilities for combat
		"support":
			value += 20.0  # Support bots value abilities for team utility
		"defensive":
			value += 15.0  # Defensive bots moderately value abilities

	# Health-based value (low health = need ability for defense)
	if bot.health <= 2:
		value += 40.0  # Vulnerable - need combat capability

	return value

func calculate_orb_value() -> float:
	"""COST-BENEFIT: Calculate value of acquiring an orb"""
	var value: float = 0.0

	# Check current level
	if not "level" in bot or not "MAX_LEVEL" in bot:
		return 50.0  # Default moderate value

	var level: int = bot.level
	var max_level: int = bot.MAX_LEVEL

	# Level-based value (diminishing returns)
	if level == 0:
		value += 80.0  # Level 0->1 is very valuable (first stat boost)
	elif level == 1:
		value += 60.0  # Level 1->2 is quite valuable
	elif level == 2:
		value += 40.0  # Level 2->3 is moderately valuable
	elif level >= max_level:
		return 10.0  # Already max level - orbs nearly worthless

	# Strategic preference modifiers
	match strategic_preference:
		"aggressive":
			value += 15.0  # Aggressive bots want stat boosts for combat
		"support":
			value += 25.0  # Support bots highly value power-ups
		"defensive":
			value += 10.0  # Defensive bots moderately value orbs

	# Combat state modifiers
	if state == "RETREAT" or bot.health <= 2:
		value -= 20.0  # Low priority when retreating or low health
	elif state == "ATTACK" or state == "CHASE":
		value -= 10.0  # Lower priority during active combat

	return value

func find_nearest_ability() -> void:
	"""COST-BENEFIT: Find ability with best value/effort ratio"""
	var best_ability: Node = null
	var best_score: float = -INF

	# Calculate value once (same for all abilities)
	var ability_value: float = calculate_ability_value()

	for ability in cached_abilities:
		if not is_instance_valid(ability):
			continue

		var ability_pos: Vector3 = ability.global_position

		# Skip if too far away or not visible (unless very close)
		var distance: float = bot.global_position.distance_to(ability_pos)
		if distance > 60.0:  # Hard limit - too far to consider
			continue
		if distance > 15.0 and not is_target_visible(ability_pos, ability):
			continue  # Not visible and not close - skip

		# Calculate acquisition cost for this ability
		var cost: float = calculate_item_acquisition_cost(ability_pos)

		# Calculate net benefit (value - cost)
		var net_benefit: float = ability_value - cost

		# Choose ability with best net benefit
		if net_benefit > best_score:
			best_score = net_benefit
			best_ability = ability

	# Only set target if net benefit is positive (worth pursuing)
	if best_score > 0.0:
		target_ability = best_ability
	else:
		target_ability = null  # No ability worth the effort

func find_nearest_orb() -> void:
	"""COST-BENEFIT: Find orb with best value/effort ratio"""
	var best_orb: Node = null
	var best_score: float = -INF

	# Calculate value once (same for all orbs)
	var orb_value: float = calculate_orb_value()

	# If already max level, skip orb search entirely
	if orb_value <= 10.0:
		target_orb = null
		return

	for orb in cached_orbs:
		if not is_instance_valid(orb):
			continue
		if "is_collected" in orb and orb.is_collected:
			continue

		var orb_pos: Vector3 = orb.global_position

		# Skip if too far away or not visible (unless very close)
		var distance: float = bot.global_position.distance_to(orb_pos)
		if distance > 50.0:  # Hard limit - too far to consider
			continue
		if distance > 15.0 and not is_target_visible(orb_pos, orb):
			continue  # Not visible and not close - skip

		# Calculate acquisition cost for this orb
		var cost: float = calculate_item_acquisition_cost(orb_pos)

		# Calculate net benefit (value - cost)
		var net_benefit: float = orb_value - cost

		# Choose orb with best net benefit
		if net_benefit > best_score:
			best_score = net_benefit
			best_orb = orb

	# Only set target if net benefit is positive (worth pursuing)
	if best_score > 0.0:
		target_orb = best_orb
	else:
		target_orb = null  # No orb worth the effort

## ============================================================================
## OBSTACLE DETECTION AND AVOIDANCE
## ============================================================================

func check_for_edge(direction: Vector3, check_distance: float = 4.0) -> bool:
	"""IMPROVED: Check for dangerous edge/drop-off with momentum compensation (uses cached space_state)"""
	if not bot:
		return false

	# PERFORMANCE: Use cached space state if available
	var space_state: PhysicsDirectSpaceState3D = cached_space_state
	if not space_state:
		space_state = bot.get_world_3d().direct_space_state

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

	# REDUCED: Less aggressive velocity multiplier to prevent paralysis
	# Was causing bots to detect "edges" everywhere and constantly brake
	var velocity_multiplier: float = 1.0
	if "linear_velocity" in bot:
		var horizontal_speed: float = Vector2(bot.linear_velocity.x, bot.linear_velocity.z).length()
		velocity_multiplier = 1.0 + min(horizontal_speed / 30.0, 0.5)  # Up to 1.5x for fast bots (was 2.5x)

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

	# BALANCED: 4.0 unit threshold - sensitive enough for safety, not so sensitive it paralyzes
	# Was 3.0 which was too aggressive and caused constant braking on platforms
	return ground_drop > 4.0

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
	"""IMPROVED v4: More aggressive overhead detection to prevent getting stuck under ramps (uses cached space_state)"""
	if not bot:
		return {"has_obstacle": false, "can_jump": false, "is_slope": false, "is_platform": false, "is_wall": false, "is_overhead_slope": false}

	# PERFORMANCE: Use cached space state if available
	var space_state: PhysicsDirectSpaceState3D = cached_space_state
	if not space_state:
		space_state = bot.get_world_3d().direct_space_state

	# IMPROVED v4: Check further ahead and at more heights
	var extended_check_distance: float = check_distance * 1.8  # Look further ahead
	var check_heights: Array = [0.2, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]  # More height points
	var obstacle_detected: bool = false
	var closest_hit: Vector3 = Vector3.ZERO
	var lowest_obstacle_height: float = INF
	var highest_obstacle_height: float = -INF
	var hit_count: int = 0
	var overhead_hit: bool = false
	var low_clearance_hit: bool = false

	for height in check_heights:
		var start_pos: Vector3 = bot.global_position + Vector3.UP * height
		var end_pos: Vector3 = start_pos + direction * extended_check_distance

		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
		query.exclude = [bot]
		query.collision_mask = 1

		var result: Dictionary = space_state.intersect_ray(query)

		if result:
			obstacle_detected = true
			hit_count += 1
			var hit_point: Vector3 = result.position
			var obstacle_height: float = hit_point.y - bot.global_position.y

			# Track overhead hits (above bot's center)
			if height > 1.3:
				overhead_hit = true

			# NEW v4: Track low clearance hits (danger zone for getting wedged)
			if height > 0.5 and height < 2.5 and obstacle_height < 2.5:
				low_clearance_hit = true

			if obstacle_height < lowest_obstacle_height:
				lowest_obstacle_height = obstacle_height
				closest_hit = hit_point
			if obstacle_height > highest_obstacle_height:
				highest_obstacle_height = obstacle_height

	if obstacle_detected:
		var is_slope: bool = false
		var is_platform: bool = false
		var is_wall: bool = false
		var is_overhead_slope: bool = false

		# Detect obstacle type
		var height_diff: float = highest_obstacle_height - lowest_obstacle_height
		if height_diff > 0.4:
			is_slope = true
			# IMPROVED v4: More aggressive overhead slope detection
			# Mark as overhead slope if: overhead hit + (low clearance OR low obstacle height)
			if overhead_hit and (lowest_obstacle_height < 2.0 or low_clearance_hit):
				is_overhead_slope = true
		if lowest_obstacle_height > 0.3 and lowest_obstacle_height < 2.5:
			is_platform = true
		if hit_count >= check_heights.size() - 2:
			is_wall = true

		# Determine if bot can jump over (but NOT if overhead slope - dangerous!)
		var can_jump: bool = false

		if is_overhead_slope:
			can_jump = false  # Never try to go under overhead slopes
		elif is_slope or is_platform:
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
			"is_overhead_slope": is_overhead_slope,
			"hit_point": closest_hit,
			"obstacle_height": lowest_obstacle_height
		}

	return {"has_obstacle": false, "can_jump": false, "is_slope": false, "is_platform": false, "is_wall": false, "is_overhead_slope": false}

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
	"""FIXED: Better stuck detection with lower thresholds and horizontal velocity check"""
	if not bot:
		return

	var current_pos: Vector3 = bot.global_position
	var distance_moved: float = current_pos.distance_to(last_position)

	# FIXED: Added WANDER state and lowered threshold from 0.25 to 0.1
	var is_trying_to_move: bool = state in ["CHASE", "ATTACK", "COLLECT_ABILITY", "COLLECT_ORB", "WANDER"]

	# FIXED: Check both position change AND horizontal velocity (catches slow sliding under slopes)
	var horizontal_velocity: float = 0.0
	if "linear_velocity" in bot:
		horizontal_velocity = Vector2(bot.linear_velocity.x, bot.linear_velocity.z).length()

	# FIXED: Stuck if barely moving OR horizontal velocity very low
	if (distance_moved < 0.1 or horizontal_velocity < 1.0) and is_trying_to_move:
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
			# FIXED: Reduced timeout from 1.2-2.2 to 0.8-1.5 for faster recovery
			unstuck_timer = randf_range(0.8, 1.5)

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
	"""IMPROVED v4: More aggressive overhead detection with lower threshold + performance pre-filtering"""
	if not bot:
		return false

	# PERFORMANCE: Pre-filter - only run expensive 9-ray check if bot is moving slowly
	# This prevents unnecessary raycasts when bot is moving normally
	if "linear_velocity" in bot:
		var horizontal_velocity: Vector3 = Vector3(bot.linear_velocity.x, 0, bot.linear_velocity.z)
		if horizontal_velocity.length() > 2.0:
			return false  # Bot moving normally, unlikely to be wedged

	# PERFORMANCE: Use cached space state if available
	var space_state: PhysicsDirectSpaceState3D = cached_space_state
	if not space_state:
		space_state = bot.get_world_3d().direct_space_state

	# IMPROVED: More check points for better coverage
	var check_points: Array = [
		Vector3.ZERO,           # Center
		Vector3(0.6, 0, 0),     # Right
		Vector3(-0.6, 0, 0),    # Left
		Vector3(0, 0, 0.6),     # Forward
		Vector3(0, 0, -0.6),    # Back
		Vector3(0.4, 0, 0.4),   # Front-right
		Vector3(-0.4, 0, 0.4),  # Front-left
		Vector3(0.4, 0, -0.4),  # Back-right
		Vector3(-0.4, 0, -0.4)  # Back-left
	]

	var overhead_hits: int = 0
	var lowest_overhead_height: float = INF

	for offset in check_points:
		var ray_start: Vector3 = bot.global_position + offset + Vector3.UP * 0.3
		var ray_end: Vector3 = bot.global_position + offset + Vector3.UP * 3.5

		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.exclude = [bot]
		query.collision_mask = 1

		var result: Dictionary = space_state.intersect_ray(query)

		if result.size() > 0:
			overhead_hits += 1
			var hit_height: float = result.position.y - bot.global_position.y
			if hit_height < lowest_overhead_height:
				lowest_overhead_height = hit_height

	# IMPROVED: More aggressive thresholds
	# Stuck if: 2+ overhead hits OR any hit below 2.3 units clearance (was 1.8)
	return overhead_hits >= 2 or (overhead_hits > 0 and lowest_overhead_height < 2.3)

func teleport_to_safe_position() -> void:
	"""FIXED: Teleport with fail-safe for missing spawns"""
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
	else:
		# FIXED: Fail-safe if no spawns exist - move up and reset velocity
		bot.global_position.y += 10.0
		bot.linear_velocity = Vector3.ZERO
		bot.angular_velocity = Vector3.ZERO
		print("[BotAI] WARNING: No spawns available, moving ", bot.name, " up by 10 units")

func handle_unstuck_movement(delta: float) -> void:
	"""FIXED: Handle movement when stuck - always apply downward force and torque"""
	if not bot:
		return

	var under_terrain: bool = is_stuck_under_terrain()

	# IMPROVED: More aggressive force when stuck under terrain
	var force_multiplier: float = 2.0 if under_terrain else 1.5
	var force: float = bot.current_roll_force * force_multiplier

	# IMPROVED: When under terrain, prioritize moving backward/sideways
	if under_terrain:
		# Move perpendicular to current direction more often
		if randf() < 0.4:
			var perpendicular: Vector3 = Vector3(-obstacle_avoid_direction.z, 0, obstacle_avoid_direction.x)
			if randf() < 0.5:
				perpendicular = -perpendicular
			obstacle_avoid_direction = perpendicular

		# Apply strong backward force
		bot.apply_central_force(obstacle_avoid_direction * force)
	else:
		bot.apply_central_force(obstacle_avoid_direction * force)

	# FIXED: Always apply downward force to help settle and escape geometry
	if "linear_velocity" in bot:
		# Apply downward force regardless of vertical velocity
		bot.apply_central_force(Vector3.DOWN * bot.current_roll_force * 0.6)

		# FIXED: Add torque to help bot roll out of stuck positions
		if "apply_torque" in bot:
			var torque_direction: float = 1.0 if randf() > 0.5 else -1.0
			bot.apply_torque(Vector3(torque_direction * 2.0, 0, 0))

	# Jump frequently (more aggressive if under terrain)
	var jump_chance: float = 0.85 if under_terrain else 0.55
	if "jump_count" in bot and "max_jumps" in bot:
		if bot.jump_count < bot.max_jumps and randf() < jump_chance:
			bot_jump()

	# Use spin dash to break free (more often when under terrain)
	var spin_chance: float = 0.35 if under_terrain else 0.2
	if unstuck_timer > 0.4 and validate_spin_dash_properties():
		if not bot.is_charging_spin and bot.spin_cooldown <= 0.0 and randf() < spin_chance:
			initiate_spin_dash()

	# Change direction periodically (more often when under terrain)
	var direction_change_interval: int = 2 if under_terrain else 4
	var time_slot: int = int(unstuck_timer * 10)
	if time_slot % direction_change_interval == 0 and time_slot != int((unstuck_timer + delta) * 10) % direction_change_interval:
		var new_angle: float = randf() * TAU
		obstacle_avoid_direction = Vector3(cos(new_angle), 0, sin(new_angle))

	# Try moving backward (more often when under terrain)
	var backward_chance: float = 0.25 if under_terrain else 0.12
	if randf() < backward_chance:
		bot.apply_central_force(-obstacle_avoid_direction * force * 0.7)

	# Exit unstuck mode
	if unstuck_timer <= 0.0:
		is_stuck = false
		unstuck_timer = 0.0
		# DON'T reset consecutive_stuck_checks here - let it accumulate to trigger teleport
		# Only reset when bot actually moves (in check_if_stuck)

		if state in ["CHASE", "ATTACK"]:
			var escape_angle: float = randf() * TAU
			var escape_distance: float = randf_range(12.0, 22.0)
			wander_target = bot.global_position + Vector3(cos(escape_angle) * escape_distance, 0, sin(escape_angle) * escape_distance)
			state = "WANDER"
			wander_timer = randf_range(2.5, 4.5)
