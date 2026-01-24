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
var state: String = "WANDER"  # WANDER, CHASE, ATTACK, COLLECT_ORB, RETREAT
var previous_state: String = "WANDER"  # Track state changes for debug logging

# DEBUG MODE - Enable for detailed bot behavior logging
# Debug logging timer (controlled by DebugLogger autoload)
var debug_log_timer: float = 0.0
const DEBUG_LOG_INTERVAL: float = 2.0  # Log state every 2 seconds

var wander_target: Vector3 = Vector3.ZERO
var wander_timer: float = 0.0
var action_timer: float = 0.0
var target_orb: Node = null
var orb_check_timer: float = 0.0
var player_search_timer: float = 0.0

# Advanced AI variables
var strafe_direction: float = 1.0
var strafe_timer: float = 0.0
var retreat_timer: float = 0.0
var retreat_cooldown: float = 0.0  # Prevents immediate re-entry into RETREAT after exiting
var ability_charge_timer: float = 0.0
var is_charging_ability: bool = false
var charge_locked_target: Node = null  # Aggressive target lock during ability charge
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
const ABILITY_COLLECTION_TIMEOUT: float = 15.0  # DESPERATE: Much longer timeout for ability collection

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

# IMPROVED: Cached group queries with filtering - CONSTANT AWARENESS MODE
var cached_players: Array[Node] = []
var cached_orbs: Array[Node] = []
# HYPER-AWARENESS: Store exact coordinates for all collectibles
var cached_orb_positions: Dictionary = {}  # {orb_node: Vector3}
var cache_refresh_timer: float = 0.0
const CACHE_REFRESH_INTERVAL: float = 0.1  # Update 10x per second for constant awareness!

# HYPER-FOCUS: Ability collection lock-on system

# ANTI-LOOP: Failed ability blacklist system - prevents infinite twitching

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
	orb_check_timer = randf_range(0.0, 1.0)
	player_search_timer = randf_range(0.0, 0.5)
	vision_update_timer = randf_range(0.0, VISION_UPDATE_INTERVAL)
	edge_check_timer = randf_range(0.0, EDGE_CHECK_INTERVAL)
	player_avoidance_timer = randf_range(0.0, PLAYER_AVOIDANCE_CHECK_INTERVAL)

	# Initial cache refresh
	call_deferred("refresh_cached_groups")
	call_deferred("find_target")

	# CRITICAL: Create CameraArm for bot aiming (same system as players)
	call_deferred("create_bot_camera")

	DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[Type B] Initialized - Skill: %.2f, Aggression: %.2f, Strategy: %s" % [bot_skill, aggression_level, strategic_preference], false, get_entity_id())

# ============================================================================
# CAMERA SYSTEM (for aiming)
# ============================================================================

func create_bot_camera() -> void:
	"""Create a CameraArm for bot aiming (same system as players)"""
	if not bot or not is_instance_valid(bot):
		return

	# Check if CameraArm already exists
	if bot.has_node("CameraArm"):
		return

	# Create CameraArm Node3D
	var camera_arm: Node3D = Node3D.new()
	camera_arm.name = "CameraArm"
	bot.add_child(camera_arm)

	# Create Camera3D child (same structure as player)
	var camera: Camera3D = Camera3D.new()
	camera.name = "Camera3D"
	# Position camera same as player: (0, 2.5, 5)
	camera.position = Vector3(0, 2.5, 5)
	# Don't make this the current camera (bots don't need to render)
	camera.current = false
	camera_arm.add_child(camera)

	DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[Type B] Created CameraArm for bot aiming", false, get_entity_id())

# ============================================================================
# DEBUG HELPERS
# ============================================================================

func get_entity_id() -> int:
	"""Get the bot's entity ID for debug logging"""
	if bot:
		return bot.name.to_int()
	return -1

func change_state(new_state: String, reason: String = "") -> void:
	"""Change state with debug logging"""
	if new_state != state:
		var ability_info: String = ""
		if bot and bot.current_ability and "ability_name" in bot.current_ability:
			ability_info = " [%s]" % bot.current_ability.ability_name
		var target_info: String = ""
		if target_player and is_instance_valid(target_player):
			var dist: float = bot.global_position.distance_to(target_player.global_position)
			target_info = " | Target: %.1fu, HP:%d" % [dist, target_player.health]
		DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[Type B] %s → %s%s%s | %s" % [state, new_state, ability_info, target_info, reason], false, get_entity_id())
		previous_state = state
		state = new_state

		# BUGFIX: Reset collection timer when entering COLLECT_ORB
		if new_state == "COLLECT_ORB":
			target_stuck_timer = 0.0

func debug_log_periodic() -> void:
	"""Periodic debug logging of bot state"""
	if not bot:
		return

	var ability_name: String = "None"
	if bot.current_ability and "ability_name" in bot.current_ability:
		ability_name = bot.current_ability.ability_name

	var target_info: String = "None"
	if target_player and is_instance_valid(target_player):
		var dist: float = bot.global_position.distance_to(target_player.global_position)
		target_info = "%s (%.1fu, HP:%d)" % [target_player.name, dist, target_player.health]

	var pos: Vector3 = bot.global_position
	DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[Type B] State: %s | Ability: %s | Target: %s | Pos: (%.1f, %.1f, %.1f) | HP: %d" % [
		state, ability_name, target_info, pos.x, pos.y, pos.z, bot.health
	], false, get_entity_id())

# ============================================================================
# MAIN LOOP
# ============================================================================

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
	orb_check_timer -= delta
	strafe_timer -= delta
	retreat_timer -= delta
	retreat_cooldown -= delta
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
	debug_log_timer += delta

	# HYPER-FOCUS: Check if ability was successfully collected - unlock if so

	# DEBUG: Periodic state logging
	if DebugLogger.is_category_enabled(DebugLogger.Category.BOT_AI) and debug_log_timer >= DEBUG_LOG_INTERVAL:
		debug_log_periodic()
		debug_log_timer = 0.0

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
			# Set escape direction backward using transform (not rotation.y)
			var opposite_dir: Vector3 = bot.global_transform.basis.z  # Backward
			opposite_dir.y = 0
			opposite_dir = opposite_dir.normalized()
			var random_side: float = 1.0 if randf() > 0.5 else -1.0
			var perpendicular: Vector3 = bot.global_transform.basis.x * random_side  # Left or right
			perpendicular.y = 0
			perpendicular = perpendicular.normalized()
			obstacle_avoid_direction = (opposite_dir + perpendicular).normalized()
	else:
		# Reset timer when not stuck under terrain
		stuck_under_terrain_timer = 0.0

	# Handle unstuck behavior
	if is_stuck and unstuck_timer > 0.0:
		handle_unstuck_movement(delta)
		return

	# NEW: Proactive edge avoidance check
	# DISABLED: This was causing bots to become passive on small arenas
	# Edge checking runs every 0.3s and applies forces OUTSIDE state machine
	# On 84x84 floor (42u radius), bots are constantly near edges
	# Corrective forces (40% roll force) override state machine behavior
	# Result: Bots roll around passively with constant edge corrections
	# FIX: Edge detection should ONLY be used within state machine movement,
	#      not as a separate system applying forces
	# if edge_check_timer <= 0.0:
	# 	check_nearby_edges()
	# 	edge_check_timer = EDGE_CHECK_INTERVAL

	# Check if bot is stuck trying to reach a target
	check_target_timeout(delta)

	# Find nearest player with caching
	if not target_player or not is_instance_valid(target_player) or player_search_timer <= 0.0:
		find_target()
		player_search_timer = 0.8

	# Check for abilities periodically (UNLESS locked onto one!)
	# CRITICAL: Don't re-evaluate abilities when locked on - prevents target switching

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
	"""HYPER-AWARENESS: Cache ALL entities with exact positions - constant tracking"""
	# Filter out invalid nodes immediately
	cached_players = get_tree().get_nodes_in_group("players").filter(
		func(node): return is_instance_valid(node) and node.is_inside_tree()
	)
	)
	cached_orbs = get_tree().get_nodes_in_group("orbs").filter(
		func(node): return is_instance_valid(node) and node.is_inside_tree() and not ("is_collected" in node and node.is_collected)
	)

	# HYPER-AWARENESS: Store exact coordinates for ALL abilities and orbs
	cached_ability_positions.clear()

	cached_orb_positions.clear()
	for orb in cached_orbs:
		if is_instance_valid(orb) and "global_position" in orb:
			cached_orb_positions[orb] = orb.global_position

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
	elif (state == "COLLECT_ORB"):
		var collectible: Node = target_orb
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

	elif (state == "COLLECT_ORB"):
		var collectible: Node = target_orb
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
	elif (state == "CHASE" or state == "COLLECT_ORB"):
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
		elif (state == "COLLECT_ORB"):
			var collectible: Node = target_orb
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
	if bot_health <= 1:
		current_aggression *= 0.3  # Severe penalty (critical health)
	elif bot_health == 2:
		current_aggression *= 0.6  # Moderate penalty (low health)

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
	"""Bots never retreat - they fight to the death!"""
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
	if enemy_health <= 1 and bot_health >= 3:
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
	"""HYPER-FOCUS: State prioritization with ability collection lock"""

	# PRIORITY -1: HYPER-FOCUS LOCK - If collecting ability, NEVER switch states!
	# Bot is locked onto a specific ability and will not be distracted by anything
