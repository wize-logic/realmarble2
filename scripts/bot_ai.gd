extends Node
class_name BotAI

## Bot AI Controller - BASE CLASS
## Shared functionality for all bot AI types
## Handles: state machine, stuck detection, personalities, movement, combat, collection
##
## Architecture:
## - bot_ai.gd: Base class with all shared logic
## - bot_ai_type_a.gd: Extends base for Sonic arenas (rails, ramps, slopes)
## - bot_ai_type_b.gd: Extends base for Quake arenas (platforms, jump pads, teleporters)
##
## IMPROVEMENTS:
## 1. Inheritance-based architecture eliminates duplication
## 2. Safe COLLECT_ABILITY state with timeout and exit conditions
## 3. Cache refresh reduced to 0.5s (was 0.1s - performance improvement)
## 4. Retreat behavior enabled (health <= 2 with caution modifier)
## 5. Bot-bot repulsion to prevent clumping
## 6. Wander biased to arena hotspots
## 7. Complete implementations of all functions
## 8. HTML5-safe (no awaits, proper physics handling)

# ============================================================================
# EXPORTS & CONFIGURATION
# ============================================================================

@export var target_player: Node = null
@export var wander_radius: float = 30.0
@export var aggro_range: float = 40.0
@export var attack_range: float = 12.0

# ============================================================================
# CORE STATE & REFERENCES
# ============================================================================

var bot: Node = null
var state: String = "WANDER"  # WANDER, CHASE, ATTACK, COLLECT_ORB, COLLECT_ABILITY, RETREAT
var previous_state: String = "WANDER"

# ============================================================================
# TIMERS
# ============================================================================

var wander_timer: float = 0.0
var action_timer: float = 0.0
var orb_check_timer: float = 0.0
var player_search_timer: float = 0.0
var strafe_timer: float = 0.0
var retreat_timer: float = 0.0
var retreat_cooldown: float = 0.0
var ability_charge_timer: float = 0.0
var stuck_timer: float = 0.0
var unstuck_timer: float = 0.0
var obstacle_jump_timer: float = 0.0
var bounce_cooldown_timer: float = 0.0
var cache_refresh_timer: float = 0.0
var player_avoidance_timer: float = 0.0
var edge_check_timer: float = 0.0
var platform_check_timer: float = 0.0
var platform_stabilize_timer: float = 0.0
var vision_update_timer: float = 0.0
var space_state_cache_timer: float = 0.0
var debug_log_timer: float = 0.0
var stuck_under_terrain_timer: float = 0.0
var target_stuck_timer: float = 0.0
var ability_check_timer: float = 0.0  # NEW: Timer for checking abilities
var death_pause_timer: float = 0.0  # NEW: Pause after death before resuming AI
var bot_repulsion_timer: float = 0.0  # NEW: Timer for bot-bot repulsion
var ult_check_timer: float = 0.0  # Timer for checking ult availability

# ============================================================================
# CONSTANTS
# ============================================================================

const DEBUG_LOG_INTERVAL: float = 2.0
const CACHE_REFRESH_INTERVAL: float = 0.75  # IMPROVED: Increased from 0.5s for better performance
const TARGET_STUCK_TIMEOUT: float = 4.0
const ABILITY_COLLECTION_TIMEOUT: float = 15.0  # Timeout for ability collection
const STUCK_UNDER_TERRAIN_TELEPORT_TIMEOUT: float = 3.0
const MAX_STUCK_ATTEMPTS: int = 10
const BOUNCE_COOLDOWN: float = 0.5
const PLAYER_AVOIDANCE_CHECK_INTERVAL: float = 0.3  # IMPROVED: Increased from 0.2s
const EDGE_CHECK_INTERVAL: float = 0.4  # IMPROVED: Increased from 0.3s
const PLATFORM_CHECK_INTERVAL: float = 2.0  # IMPROVED: Increased from 1.5s
const VISION_UPDATE_INTERVAL: float = 0.15  # IMPROVED: Increased from 0.1s
const SPACE_STATE_CACHE_REFRESH: float = 1.5  # IMPROVED: Increased from 1.0s
const VISION_HYSTERESIS_TIME: float = 0.5
const BOT_EYE_HEIGHT: float = 1.0
const MAX_CACHED_PLATFORMS: int = 20
const MAX_PLATFORM_DISTANCE: float = 40.0
const MIN_PLATFORM_HEIGHT: float = 2.0
const GOOD_ENOUGH_SCORE: float = 70.0
const MAX_BOTS_PER_PLATFORM: int = 2
const MIN_PLATFORM_SIZE_FOR_COMBAT: float = 8.0
const DEATH_PAUSE_DURATION: float = 1.0  # NEW: Pause 1s after death
const BOT_REPULSION_INTERVAL: float = 0.15  # NEW: Check bot repulsion frequently
const BOT_REPULSION_DISTANCE: float = 3.0  # NEW: Start repelling at 3 units
const ULT_CHECK_INTERVAL: float = 0.3  # Check ult availability frequently
const ULT_OPTIMAL_RANGE: float = 15.0  # Best range to activate ult for dash attack

# Ability optimal ranges
const CANNON_OPTIMAL_RANGE: float = 15.0
const SWORD_OPTIMAL_RANGE: float = 3.5
const DASH_ATTACK_OPTIMAL_RANGE: float = 8.0
const EXPLOSION_OPTIMAL_RANGE: float = 6.0
const LIGHTNING_OPTIMAL_RANGE: float = 18.0  # Lightning auto-aim (reduced with lock_range nerf)

# Ability proficiency scores
const ABILITY_SCORES: Dictionary = {
	"Cannon": 85,
	"Sword": 75,
	"Dash Attack": 80,
	"Explosion": 70,
	"Lightning": 90  # High score - powerful auto-aim ability
}

# ============================================================================
# STATE VARIABLES
# ============================================================================

var wander_target: Vector3 = Vector3.ZERO
var target_orb: Node = null
var target_ability: Node = null  # NEW: Target ability for collection
var strafe_direction: float = 1.0
var is_charging_ability: bool = false
var charge_locked_target: Node = null
var aggression_level: float = 0.7

# ============================================================================
# PERSONALITY TRAITS (OpenArena-inspired)
# ============================================================================

var bot_skill: float = 0.75
var aim_accuracy: float = 0.85
var turn_speed_factor: float = 1.0
var caution_level: float = 0.5
var strategic_preference: String = "balanced"  # "aggressive", "balanced", "defensive", "support"

# ============================================================================
# STUCK DETECTION
# ============================================================================

var last_position: Vector3 = Vector3.ZERO
var stuck_check_interval: float = 0.3
var is_stuck: bool = false
var obstacle_avoid_direction: Vector3 = Vector3.ZERO
var consecutive_stuck_checks: int = 0
var target_stuck_position: Vector3 = Vector3.ZERO

# ============================================================================
# CACHING SYSTEMS
# ============================================================================

var cached_players: Array[Node] = []
var cached_orbs: Array[Node] = []
var cached_abilities: Array[Node] = []  # NEW: Cache abilities
var cached_orb_positions: Dictionary = {}
var cached_ability_positions: Dictionary = {}  # NEW: Cache ability positions
var cached_platforms: Array[Dictionary] = []
var cached_space_state: PhysicsDirectSpaceState3D = null
var last_seen_targets: Dictionary = {}

# ============================================================================
# SEEDED RNG FOR MULTIPLAYER SYNC
# ============================================================================
# CRITICAL: All bot randomness must use this seeded RNG to ensure identical
# behavior across all clients in multiplayer. Using global randf()/randi()
# causes desync because each client generates different random numbers.

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# ============================================================================
# PLATFORM NAVIGATION
# ============================================================================

var target_platform: Dictionary = {}
var is_approaching_platform: bool = false
var platform_jump_prepared: bool = false
var on_platform: bool = false

# ============================================================================
# ABILITY COLLECTION (NEW - Safe Implementation)
# ============================================================================

var ability_collection_start_time: float = 0.0  # Track how long we've been collecting
var ability_blacklist: Array[Node] = []  # Abilities we've failed to collect (avoid retry)
var ability_blacklist_timer: float = 0.0  # Clear blacklist periodically

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	bot = get_parent()
	if not bot:
		push_error("ERROR: BotAI could not find parent bot!")
		return

	# CRITICAL MULTIPLAYER FIX: Seed RNG for deterministic behavior across all clients
	# Uses level_seed + bot entity ID to ensure each bot has unique but consistent behavior
	_initialize_seeded_rng()

	wander_target = bot.global_position
	last_position = bot.global_position
	target_stuck_position = bot.global_position

	# Randomize aggression for personality variety (using seeded RNG)
	aggression_level = rng.randf_range(0.6, 0.9)

	# Initialize personality traits
	initialize_personality()

	# Stagger timer initialization to prevent simultaneous processing (using seeded RNG)
	cache_refresh_timer = rng.randf_range(0.0, CACHE_REFRESH_INTERVAL)
	platform_check_timer = rng.randf_range(0.0, PLATFORM_CHECK_INTERVAL)
	orb_check_timer = rng.randf_range(0.0, 1.0)
	player_search_timer = rng.randf_range(0.0, 0.5)
	vision_update_timer = rng.randf_range(0.0, VISION_UPDATE_INTERVAL)
	edge_check_timer = rng.randf_range(0.0, EDGE_CHECK_INTERVAL)
	player_avoidance_timer = rng.randf_range(0.0, PLAYER_AVOIDANCE_CHECK_INTERVAL)
	ability_check_timer = rng.randf_range(0.0, 1.0)  # NEW
	bot_repulsion_timer = rng.randf_range(0.0, BOT_REPULSION_INTERVAL)  # NEW
	ult_check_timer = rng.randf_range(0.0, ULT_CHECK_INTERVAL)  # Stagger ult checks

	# Initial cache refresh
	call_deferred("refresh_cached_groups")
	call_deferred("find_target")

	# Create camera for aiming
	call_deferred("create_bot_camera")

	DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[%s] Initialized - Skill: %.2f, Aggression: %.2f, Strategy: %s" % [get_ai_type(), bot_skill, aggression_level, strategic_preference], false, get_entity_id())

func _initialize_seeded_rng() -> void:
	"""Initialize seeded RNG for deterministic multiplayer behavior"""
	# Get level seed from MultiplayerManager room settings, or use a default
	var level_seed: int = 0
	if MultiplayerManager and MultiplayerManager.room_settings.has("level_seed"):
		level_seed = MultiplayerManager.room_settings["level_seed"]

	# If no level_seed available (practice mode), get from World's level generator
	if level_seed == 0:
		var world: Node = get_tree().get_root().get_node_or_null("World")
		if world and world.level_generator and "level_seed" in world.level_generator:
			level_seed = world.level_generator.level_seed

	# Combine level_seed with bot's entity ID for unique but deterministic seed per bot
	var bot_id: int = get_entity_id()
	var combined_seed: int = level_seed ^ (bot_id * 31337)  # XOR with prime multiplied ID

	rng.seed = combined_seed
	DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[%s] RNG seeded with %d (level_seed=%d, bot_id=%d)" % [get_ai_type(), combined_seed, level_seed, bot_id], false, get_entity_id())

# ============================================================================
# VIRTUAL METHODS (Override in subclasses)
# ============================================================================

func get_ai_type() -> String:
	"""Override in subclasses to return 'Type A' or 'Type B'"""
	return "Base"

func setup_arena_specific_caches() -> void:
	"""Override in subclasses to cache arena-specific elements (rails, jump pads, etc.)"""
	pass

func consider_arena_specific_navigation() -> void:
	"""Override in subclasses for arena-specific movement (rails, jump pads, teleporters)"""
	pass

func handle_arena_specific_state_updates() -> void:
	"""Override in subclasses for arena-specific state transitions"""
	pass

# ============================================================================
# CAMERA SYSTEM
# ============================================================================

func create_bot_camera() -> void:
	"""Create a CameraArm for bot aiming (same system as players)"""
	if not bot or not is_instance_valid(bot):
		return

	if bot.has_node("CameraArm"):
		return

	var camera_arm: Node3D = Node3D.new()
	camera_arm.name = "CameraArm"
	bot.add_child(camera_arm)

	var camera: Camera3D = Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0, 2.5, 5)
	camera.current = false
	camera_arm.add_child(camera)

	DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[%s] Created CameraArm for aiming" % get_ai_type(), false, get_entity_id())

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
		DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[%s] %s → %s%s%s | %s" % [get_ai_type(), state, new_state, ability_info, target_info, reason], false, get_entity_id())
		previous_state = state
		state = new_state

		# Reset collection timers when entering collection states
		if new_state == "COLLECT_ORB":
			target_stuck_timer = 0.0
		elif new_state == "COLLECT_ABILITY":
			target_stuck_timer = 0.0
			ability_collection_start_time = Time.get_ticks_msec() / 1000.0

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
	DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[%s] State: %s | Ability: %s | Target: %s | Pos: (%.1f, %.1f, %.1f) | HP: %d" % [
		get_ai_type(), state, ability_name, target_info, pos.x, pos.y, pos.z, bot.health
	], false, get_entity_id())

# ============================================================================
# MAIN PHYSICS LOOP
# ============================================================================

func _physics_process(delta: float) -> void:
	if not bot or not is_instance_valid(bot):
		return

	# Only run AI when game is active
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if not world or not world.game_active:
		return

	# NEW: Pause after death to prevent immediate re-engagement
	if death_pause_timer > 0.0:
		death_pause_timer -= delta
		return

	# Update all timers
	update_timers(delta)

	# Periodic debug logging
	if DebugLogger.is_category_enabled(DebugLogger.Category.BOT_AI) and debug_log_timer >= DEBUG_LOG_INTERVAL:
		debug_log_periodic()
		debug_log_timer = 0.0

	# Update cached physics space state
	if space_state_cache_timer <= 0.0:
		if bot and bot is RigidBody3D:
			cached_space_state = bot.get_world_3d().direct_space_state
		space_state_cache_timer = SPACE_STATE_CACHE_REFRESH

	# Refresh cached groups
	if cache_refresh_timer <= 0.0:
		refresh_cached_groups()
		cache_refresh_timer = CACHE_REFRESH_INTERVAL

	# Check if stuck on obstacles
	if stuck_timer >= stuck_check_interval:
		check_if_stuck()
		stuck_timer = 0.0

	# Check for stuck under terrain
	handle_stuck_under_terrain(delta)

	# Handle unstuck behavior (overrides normal AI)
	if is_stuck and unstuck_timer > 0.0:
		handle_unstuck_movement(delta)
		return

	# Check target timeout
	check_target_timeout(delta)

	# NEW: Bot-bot repulsion to prevent clumping
	if bot_repulsion_timer <= 0.0:
		apply_bot_repulsion()
		bot_repulsion_timer = BOT_REPULSION_INTERVAL

	# Find nearest player
	if not target_player or not is_instance_valid(target_player) or player_search_timer <= 0.0:
		find_target()
		player_search_timer = 0.8

	# Check for orbs periodically
	if orb_check_timer <= 0.0:
		find_nearest_orb()
		orb_check_timer = 1.0

	# NEW: Check for abilities periodically
	if ability_check_timer <= 0.0:
		find_nearest_ability()
		ability_check_timer = 0.5  # Check abilities twice per second

	# Check for ult usage opportunity
	if ult_check_timer <= 0.0:
		try_use_ult()
		ult_check_timer = ULT_CHECK_INTERVAL

	# Check for platforms
	if platform_check_timer <= 0.0:
		find_best_platform()
		if state == "ATTACK" or state == "CHASE":
			platform_check_timer = PLATFORM_CHECK_INTERVAL * 2.0
		elif state == "RETREAT":
			platform_check_timer = PLATFORM_CHECK_INTERVAL * 0.5
		else:
			platform_check_timer = PLATFORM_CHECK_INTERVAL

	# Arena-specific navigation (rails, jump pads, teleporters)
	consider_arena_specific_navigation()

	# Execute state behavior
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
		"COLLECT_ABILITY":  # NEW
			do_collect_ability(delta)

	# Update state transitions
	update_state()

func update_timers(delta: float) -> void:
	"""Update all timers in one place"""
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
	space_state_cache_timer -= delta
	debug_log_timer += delta
	ability_check_timer -= delta
	death_pause_timer -= delta
	bot_repulsion_timer -= delta
	ability_blacklist_timer -= delta
	ult_check_timer -= delta

	# Clear ability blacklist every 30 seconds
	if ability_blacklist_timer <= 0.0:
		ability_blacklist.clear()
		ability_blacklist_timer = 30.0

# ============================================================================
# PERSONALITY INITIALIZATION
# ============================================================================

func initialize_personality() -> void:
	"""Initialize bot personality traits (OpenArena-inspired) - uses seeded RNG for multiplayer sync"""
	bot_skill = rng.randf_range(0.5, 0.95)
	aim_accuracy = rng.randf_range(0.70, 0.95)
	turn_speed_factor = rng.randf_range(0.8, 1.2)
	caution_level = rng.randf_range(0.2, 0.8)

	var preference_roll: float = rng.randf()
	if preference_roll < 0.25:
		strategic_preference = "aggressive"
		aggression_level = rng.randf_range(0.75, 0.95)
		caution_level = rng.randf_range(0.2, 0.4)
	elif preference_roll < 0.5:
		strategic_preference = "defensive"
		aggression_level = rng.randf_range(0.5, 0.7)
		caution_level = rng.randf_range(0.6, 0.85)
	elif preference_roll < 0.75:
		strategic_preference = "support"
		aggression_level = rng.randf_range(0.55, 0.75)
		caution_level = rng.randf_range(0.5, 0.7)
	else:
		strategic_preference = "balanced"
		aggression_level = rng.randf_range(0.6, 0.85)
		caution_level = rng.randf_range(0.4, 0.6)

# ============================================================================
# CACHING SYSTEMS
# ============================================================================

func refresh_cached_groups() -> void:
	"""Cache all entities with filtering - runs every 0.5s"""
	cached_players = get_tree().get_nodes_in_group("players").filter(
		func(node): return is_instance_valid(node) and node.is_inside_tree()
	)

	cached_orbs = get_tree().get_nodes_in_group("orbs").filter(
		func(node): return is_instance_valid(node) and node.is_inside_tree() and not ("is_collected" in node and node.is_collected)
	)

	# NEW: Cache abilities
	cached_abilities = get_tree().get_nodes_in_group("ability_pickups").filter(
		func(node): return is_instance_valid(node) and node.is_inside_tree() and ability_blacklist.find(node) == -1
	)

	# Store exact coordinates
	cached_orb_positions.clear()
	for orb in cached_orbs:
		if is_instance_valid(orb) and "global_position" in orb:
			cached_orb_positions[orb] = orb.global_position

	# NEW: Store ability coordinates
	cached_ability_positions.clear()
	for ability in cached_abilities:
		if is_instance_valid(ability) and "global_position" in ability:
			cached_ability_positions[ability] = ability.global_position

	# Cache platforms
	refresh_platform_cache()

	# Arena-specific caches (rails, jump pads, teleporters)
	setup_arena_specific_caches()

func refresh_platform_cache() -> void:
	"""Cache platform positions with filtering for performance"""
	cached_platforms.clear()

	if not bot:
		return

	var world: Node = get_tree().get_root().get_node_or_null("World")
	if not world:
		return

	var level_gen: Node = world.get_node_or_null("LevelGenerator")
	if not level_gen:
		level_gen = world.get_node_or_null("LevelGeneratorQ3")

	if not level_gen or not "platforms" in level_gen:
		return

	var bot_pos: Vector3 = bot.global_position
	var candidate_platforms: Array[Dictionary] = []

	for platform_node in level_gen.platforms:
		if not is_instance_valid(platform_node) or not platform_node.is_inside_tree():
			continue

		var platform_pos: Vector3 = platform_node.global_position

		# Only cache elevated platforms
		if platform_pos.y < MIN_PLATFORM_HEIGHT:
			continue

		# Only cache nearby platforms
		var distance: float = bot_pos.distance_to(platform_pos)
		if distance > MAX_PLATFORM_DISTANCE:
			continue

		var platform_size: Vector3 = Vector3(8, 1, 8)
		if platform_node is MeshInstance3D and platform_node.mesh:
			if platform_node.mesh is BoxMesh:
				platform_size = platform_node.mesh.size

		candidate_platforms.append({
			"node": platform_node,
			"position": platform_pos,
			"size": platform_size,
			"height": platform_pos.y,
			"distance": distance
		})

	# Sort by distance and keep closest
	if candidate_platforms.size() > MAX_CACHED_PLATFORMS:
		candidate_platforms.sort_custom(func(a, b): return a.distance < b.distance)
		candidate_platforms = candidate_platforms.slice(0, MAX_CACHED_PLATFORMS)

	for platform_data in candidate_platforms:
		cached_platforms.append({
			"node": platform_data.node,
			"position": platform_data.position,
			"size": platform_data.size,
			"height": platform_data.height
		})

# ============================================================================
# TARGET FINDING
# ============================================================================

func find_target() -> void:
	"""Find nearest valid player target"""
	if cached_players.is_empty():
		target_player = null
		return

	var best_target: Node = null
	var best_score: float = -INF

	for player in cached_players:
		if player == bot or not is_instance_valid(player):
			continue

		# Skip dead players
		if "health" in player and player.health <= 0:
			continue

		var score: float = evaluate_target_priority(player)
		if score > best_score:
			best_score = score
			best_target = player

	target_player = best_target

func evaluate_target_priority(player: Node) -> float:
	"""Evaluate target priority score (OpenArena-inspired)"""
	if not player or not is_instance_valid(player):
		return -INF

	var score: float = 0.0
	var distance: float = bot.global_position.distance_to(player.global_position)

	# Distance scoring (closer = better)
	if distance < 20.0:
		score += 100.0 - (distance * 3.0)
	else:
		score += 40.0 - (distance * 1.0)

	# Health-based threat assessment
	if "health" in player:
		var player_health: int = player.health
		var bot_health: int = get_bot_health()

		# Prefer weak targets
		if player_health == 1:
			score += 50.0
		elif player_health == 2:
			score += 25.0

		# Avoid strong targets if we're weak
		if bot_health <= 2 and player_health >= 3:
			score -= 40.0

	# Visibility bonus
	if can_see_target(player):
		score += 30.0

	return score

func find_nearest_orb() -> void:
	"""Find nearest orb for collection"""
	if cached_orbs.is_empty():
		target_orb = null
		return

	var nearest_orb: Node = null
	var nearest_dist: float = INF

	for orb in cached_orbs:
		if not is_instance_valid(orb):
			continue

		var distance: float = bot.global_position.distance_to(orb.global_position)

		# Prefer visible or nearby orbs
		if distance < 15.0 or can_see_target(orb):
			if distance < nearest_dist:
				nearest_dist = distance
				nearest_orb = orb

	target_orb = nearest_orb

func find_nearest_ability() -> void:
	"""NEW: Find nearest ability for collection"""
	# Don't look for abilities if we already have one
	if bot.current_ability:
		target_ability = null
		return

	if cached_abilities.is_empty():
		target_ability = null
		return

	var nearest_ability: Node = null
	var nearest_dist: float = INF

	for ability in cached_abilities:
		if not is_instance_valid(ability):
			continue

		var distance: float = bot.global_position.distance_to(ability.global_position)

		# Prioritize visible or nearby abilities
		if distance < 15.0 or can_see_target(ability):
			if distance < nearest_dist:
				nearest_dist = distance
				nearest_ability = ability

	target_ability = nearest_ability

# ============================================================================
# STUCK DETECTION & HANDLING
# ============================================================================

func check_if_stuck() -> void:
	"""Check if bot is stuck and needs unstuck behavior"""
	if not bot:
		return

	var current_pos: Vector3 = bot.global_position
	var moved_distance: float = current_pos.distance_to(last_position)

	# Check if bot hasn't moved much
	if moved_distance < 0.5 and bot.linear_velocity.length() < 1.0:
		consecutive_stuck_checks += 1

		if consecutive_stuck_checks >= 3:
			is_stuck = true
			unstuck_timer = rng.randf_range(0.8, 1.5)

			# Set random escape direction (using seeded RNG)
			var opposite_dir: Vector3 = bot.global_transform.basis.z
			opposite_dir.y = 0
			opposite_dir = opposite_dir.normalized()
			var random_side: float = 1.0 if rng.randf() > 0.5 else -1.0
			var perpendicular: Vector3 = bot.global_transform.basis.x * random_side
			perpendicular.y = 0
			perpendicular = perpendicular.normalized()
			obstacle_avoid_direction = (opposite_dir + perpendicular).normalized()

			DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[%s] Stuck detected! Unstuck timer: %.1fs" % [get_ai_type(), unstuck_timer], false, get_entity_id())
	else:
		consecutive_stuck_checks = 0
		if is_stuck and unstuck_timer <= 0.0:
			is_stuck = false

	last_position = current_pos

func handle_stuck_under_terrain(delta: float) -> void:
	"""Check and handle being stuck under terrain/slopes"""
	var currently_stuck_under_terrain: bool = is_stuck_under_terrain()

	if currently_stuck_under_terrain:
		stuck_under_terrain_timer += delta

		# Force teleport if stuck too long
		if stuck_under_terrain_timer >= STUCK_UNDER_TERRAIN_TELEPORT_TIMEOUT:
			DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[%s] Stuck under terrain for %.1fs - teleporting" % [get_ai_type(), stuck_under_terrain_timer], false, get_entity_id())
			teleport_to_safe_position()
			stuck_under_terrain_timer = 0.0
			is_stuck = false
			consecutive_stuck_checks = 0
			return

		# Trigger unstuck if not already
		if not is_stuck:
			is_stuck = true
			unstuck_timer = rng.randf_range(0.8, 1.5)
			consecutive_stuck_checks = max(consecutive_stuck_checks, 3)

			var opposite_dir: Vector3 = bot.global_transform.basis.z
			opposite_dir.y = 0
			opposite_dir = opposite_dir.normalized()
			var random_side: float = 1.0 if rng.randf() > 0.5 else -1.0
			var perpendicular: Vector3 = bot.global_transform.basis.x * random_side
			perpendicular.y = 0
			perpendicular = perpendicular.normalized()
			obstacle_avoid_direction = (opposite_dir + perpendicular).normalized()
	else:
		stuck_under_terrain_timer = 0.0

func is_stuck_under_terrain() -> bool:
	"""Check if bot is stuck under terrain using 9-point overhead detection"""
	if not bot or not cached_space_state:
		return false

	var bot_pos: Vector3 = bot.global_position
	var check_distance: float = 1.5

	# 9 check points (center + 8 cardinal/diagonal directions)
	var check_points: Array[Vector3] = [
		Vector3.ZERO,  # Center
		Vector3(check_distance, 0, 0),
		Vector3(-check_distance, 0, 0),
		Vector3(0, 0, check_distance),
		Vector3(0, 0, -check_distance),
		Vector3(check_distance, 0, check_distance),
		Vector3(-check_distance, 0, check_distance),
		Vector3(check_distance, 0, -check_distance),
		Vector3(-check_distance, 0, -check_distance)
	]

	var stuck_count: int = 0

	for offset in check_points:
		var check_pos: Vector3 = bot_pos + offset
		var ray_start: Vector3 = check_pos + Vector3(0, BOT_EYE_HEIGHT, 0)
		var ray_end: Vector3 = ray_start + Vector3(0, 2.3, 0)  # Check 2.3 units above

		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.exclude = [bot]
		query.collision_mask = 1  # World layer

		var result: Dictionary = cached_space_state.intersect_ray(query)
		if result:
			stuck_count += 1

	# If more than 4 points hit overhead terrain, we're stuck
	return stuck_count > 4

func handle_unstuck_movement(delta: float) -> void:
	"""Apply aggressive unstuck forces"""
	if not bot or unstuck_timer <= 0.0:
		is_stuck = false
		return

	# Apply strong force in escape direction
	var escape_force: Vector3 = obstacle_avoid_direction * current_roll_force * 1.5
	escape_force.y = current_jump_impulse * 0.5  # Add upward component
	bot.apply_central_force(escape_force)

	# Apply downward torque to help escape
	var torque: Vector3 = -bot.global_transform.basis.x * 50.0
	bot.apply_torque(torque)

	# Try jumping if grounded
	if obstacle_jump_timer <= 0.0:
		bot_jump()
		obstacle_jump_timer = 0.5

	# Reduce consecutvie stuck checks to eventually exit
	if consecutive_stuck_checks > 0:
		consecutive_stuck_checks -= 1

func teleport_to_safe_position() -> void:
	"""Teleport bot to a safe spawn position"""
	if not bot:
		return

	var world: Node = get_tree().get_root().get_node_or_null("World")
	if not world:
		return

	# Try to use world spawns (using seeded RNG for deterministic spawn selection)
	if "spawns" in world and world.spawns.size() > 0:
		var spawn_pos: Vector3 = world.spawns[rng.randi() % world.spawns.size()]
		bot.global_position = spawn_pos
		bot.linear_velocity = Vector3.ZERO
		bot.angular_velocity = Vector3.ZERO
		DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[%s] Teleported to spawn: %v" % [get_ai_type(), spawn_pos], false, get_entity_id())
	else:
		# Failsafe: teleport upward
		bot.global_position = bot.global_position + Vector3(0, 10, 0)
		bot.linear_velocity = Vector3.ZERO
		bot.angular_velocity = Vector3.ZERO
		DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[%s] Teleported upward (failsafe)" % get_ai_type(), false, get_entity_id())

func check_target_timeout(delta: float) -> void:
	"""Check if bot is stuck trying to reach a target"""
	var current_target: Node = null
	var timeout: float = TARGET_STUCK_TIMEOUT

	if state == "COLLECT_ORB":
		current_target = target_orb
	elif state == "COLLECT_ABILITY":
		current_target = target_ability
		timeout = ABILITY_COLLECTION_TIMEOUT
	elif state == "CHASE" or state == "ATTACK":
		current_target = target_player

	if current_target and is_instance_valid(current_target):
		var current_pos: Vector3 = bot.global_position
		var moved_dist: float = current_pos.distance_to(target_stuck_position)

		if moved_dist < 1.0:
			target_stuck_timer += delta

			if target_stuck_timer >= timeout:
				DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[%s] Target timeout - clearing target" % get_ai_type(), false, get_entity_id())

				# Clear the stuck target
				if state == "COLLECT_ORB":
					target_orb = null
				elif state == "COLLECT_ABILITY":
					target_ability = null
					# Add to blacklist
					if current_target not in ability_blacklist:
						ability_blacklist.append(current_target)
				elif state == "CHASE" or state == "ATTACK":
					target_player = null

				target_stuck_timer = 0.0
				change_state("WANDER", "Target timeout")
		else:
			target_stuck_timer = 0.0
			target_stuck_position = current_pos
	else:
		target_stuck_timer = 0.0

# ============================================================================
# MOVEMENT HELPERS
# ============================================================================

func move_towards(target_pos: Vector3, speed_multiplier: float = 1.0) -> void:
	"""Move bot toward a target position"""
	if not bot:
		return

	var direction: Vector3 = (target_pos - bot.global_position).normalized()
	direction.y = 0  # Keep movement horizontal

	if direction.length() < 0.01:
		return

	var move_force: Vector3 = direction * current_roll_force * speed_multiplier
	bot.apply_central_force(move_force)

	# Rotate toward movement direction
	rotate_to_direction(direction)

func rotate_to_target(target_pos: Vector3) -> void:
	"""Rotate bot to face target position"""
	if not bot:
		return

	var direction: Vector3 = (target_pos - bot.global_position).normalized()
	direction.y = 0

	if direction.length() < 0.01:
		return

	rotate_to_direction(direction)

func rotate_to_direction(direction: Vector3) -> void:
	"""Rotate bot to face a direction using angular velocity"""
	if not bot:
		return

	var forward: Vector3 = -bot.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()

	var target_dir: Vector3 = direction
	target_dir.y = 0
	target_dir = target_dir.normalized()

	if target_dir.length() < 0.01:
		return

	# Calculate angle difference
	var angle_diff: float = forward.signed_angle_to(target_dir, Vector3.UP)

	# Apply angular velocity with personality-based turn speed
	var turn_strength: float = 15.0 * turn_speed_factor
	var angular_vel: Vector3 = Vector3(0, angle_diff * turn_strength, 0)

	# Damping to prevent oscillation
	bot.angular_velocity = bot.angular_velocity.lerp(angular_vel, 0.3)

func bot_jump() -> void:
	"""Make bot jump"""
	if not bot:
		return

	# Check if bot can jump
	if "jump_count" in bot and "max_jumps" in bot:
		if bot.jump_count >= bot.max_jumps:
			return

	# Apply jump impulse
	bot.apply_central_impulse(Vector3(0, current_jump_impulse, 0))

	# Increment jump count
	if "jump_count" in bot:
		bot.jump_count += 1

func bot_bounce() -> void:
	"""Make bot perform bounce attack"""
	if not bot or bounce_cooldown_timer > 0.0:
		return

	# Validate bounce properties
	if not validate_bounce_properties():
		return

	# Start bounce
	if bot.has_method("start_bounce"):
		bot.start_bounce()
		bounce_cooldown_timer = BOUNCE_COOLDOWN

# ============================================================================
# VISION & AWARENESS
# ============================================================================

func can_see_target(target: Node) -> bool:
	"""Check if bot has line of sight to target"""
	if not bot or not target or not is_instance_valid(target) or not cached_space_state:
		return false

	var bot_eye: Vector3 = bot.global_position + Vector3(0, BOT_EYE_HEIGHT, 0)
	var target_pos: Vector3 = target.global_position
	if "global_position" in target:
		target_pos = target.global_position

	# Add eye height to target if it's a player
	if target.is_in_group("players"):
		target_pos += Vector3(0, BOT_EYE_HEIGHT, 0)

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(bot_eye, target_pos)
	query.exclude = [bot]
	query.collision_mask = 1  # World layer only

	var result: Dictionary = cached_space_state.intersect_ray(query)
	return not result  # No obstruction = can see

# ============================================================================
# BOT REPULSION (NEW)
# ============================================================================

func apply_bot_repulsion() -> void:
	"""NEW: Apply repulsion force to prevent bots from clumping together"""
	if not bot:
		return

	var repulsion_force: Vector3 = Vector3.ZERO
	var bot_count: int = 0

	for player in cached_players:
		if player == bot or not is_instance_valid(player):
			continue

		# Skip human players
		if not player.is_in_group("bots"):
			continue

		var distance: float = bot.global_position.distance_to(player.global_position)

		# Apply repulsion if too close
		if distance < BOT_REPULSION_DISTANCE and distance > 0.1:
			var direction: Vector3 = (bot.global_position - player.global_position).normalized()
			direction.y = 0  # Keep horizontal

			# Stronger repulsion when closer
			var strength: float = (BOT_REPULSION_DISTANCE - distance) / BOT_REPULSION_DISTANCE
			repulsion_force += direction * strength * current_roll_force * 0.3
			bot_count += 1

	# Apply averaged repulsion force
	if bot_count > 0:
		bot.apply_central_force(repulsion_force)

# ============================================================================
# PLATFORM NAVIGATION
# ============================================================================

func find_best_platform() -> void:
	"""Find the best platform with early exit for performance"""
	if cached_platforms.is_empty():
		target_platform = {}
		return

	var best_platform: Dictionary = {}
	var best_score: float = -INF

	for platform_data in cached_platforms:
		var score: float = evaluate_platform_score(platform_data)

		if score > best_score:
			best_score = score
			best_platform = platform_data

			# Early exit if good enough
			if best_score >= GOOD_ENOUGH_SCORE:
				break

	if best_score > 30.0:
		target_platform = best_platform
	else:
		target_platform = {}

func evaluate_platform_score(platform_data: Dictionary) -> float:
	"""Score a platform based on tactical value"""
	if not bot or platform_data.is_empty():
		return -INF

	var score: float = 0.0
	var platform_pos: Vector3 = platform_data.position
	var platform_height: float = platform_data.height
	var distance: float = bot.global_position.distance_to(platform_pos)

	# Don't target platform we're already on
	var horizontal_dist: float = Vector2(platform_pos.x - bot.global_position.x, platform_pos.z - bot.global_position.z).length()
	var vertical_diff: float = abs(platform_height - bot.global_position.y)

	if horizontal_dist < 4.0 and vertical_diff < 2.0:
		return -INF

	# Base accessibility score
	if distance < 15.0:
		score += 50.0 - (distance * 2.0)
	elif distance < 30.0:
		score += 30.0 - (distance * 1.0)
	else:
		score -= (distance - 30.0) * 0.5

	# Height advantage bonus
	var height_diff: float = platform_height - bot.global_position.y
	if height_diff > 2.0:
		if target_player and is_instance_valid(target_player):
			var enemy_height: float = target_player.global_position.y
			if platform_height > enemy_height + 2.0:
				score += 40.0
			else:
				score += 20.0
		else:
			score += 15.0
	elif height_diff < -2.0:
		score -= 10.0

	# Reachability check
	var is_reachable: bool = can_reach_platform(platform_data)
	if not is_reachable:
		score -= 100.0

	# Platform size scoring
	var platform_size: Vector3 = platform_data.size
	var platform_area: float = platform_size.x * platform_size.z
	if platform_area >= 100.0:
		score += 15.0
	elif platform_area <= 50.0:
		score -= 15.0
		if state == "ATTACK" or state == "CHASE":
			score -= 10.0

	# Platform occupancy check
	var occupancy: int = count_bots_on_platform(platform_data)
	if occupancy >= MAX_BOTS_PER_PLATFORM:
		score -= 60.0
	elif occupancy > 0:
		score -= 20.0
		if platform_area <= 64.0:
			score -= 30.0

	# Strategic preference bonuses
	match strategic_preference:
		"aggressive":
			if target_player and is_instance_valid(target_player):
				var dist_to_enemy: float = platform_pos.distance_to(target_player.global_position)
				if dist_to_enemy < 20.0:
					score += 25.0
		"defensive":
			if target_player and is_instance_valid(target_player):
				var dist_to_enemy: float = platform_pos.distance_to(target_player.global_position)
				if dist_to_enemy > 25.0 and height_diff > 5.0:
					score += 30.0

	# Combat state modifiers
	if state == "RETREAT" and bot.health < 2:
		if height_diff > 3.0:
			score += 50.0
	elif state == "ATTACK" and bot.current_ability:
		if height_diff > 2.0:
			score += 30.0

	return score

func can_reach_platform(platform_data: Dictionary) -> bool:
	"""Check if bot can physically reach a platform"""
	if not bot or platform_data.is_empty():
		return false

	var platform_pos: Vector3 = platform_data.position
	var height_diff: float = platform_pos.y - bot.global_position.y
	var horizontal_dist: float = Vector2(platform_pos.x - bot.global_position.x, platform_pos.z - bot.global_position.z).length()

	# Check vertical reachability
	var max_bounce_height: float = 15.0

	if height_diff > max_bounce_height:
		return false

	# Check horizontal distance
	if horizontal_dist > 20.0:
		return false

	return true

func count_bots_on_platform(platform_data: Dictionary) -> int:
	"""Count how many bots are currently on a platform"""
	if platform_data.is_empty():
		return 0

	var platform_pos: Vector3 = platform_data.position
	var platform_size: Vector3 = platform_data.size
	var platform_height: float = platform_data.height

	var bot_count: int = 0

	for player in cached_players:
		if player == bot or not is_instance_valid(player):
			continue

		var player_pos: Vector3 = player.global_position

		var horizontal_dist: float = Vector2(
			player_pos.x - platform_pos.x,
			player_pos.z - platform_pos.z
		).length()

		var height_diff: float = abs(player_pos.y - platform_height)

		var half_size: float = max(platform_size.x, platform_size.z) * 0.5
		if horizontal_dist <= half_size and height_diff <= 3.0:
			bot_count += 1

	return bot_count

# ============================================================================
# STATE BEHAVIORS
# ============================================================================

func do_wander(delta: float) -> void:
	"""Wander behavior with hotspot bias - uses seeded RNG for multiplayer sync"""
	if wander_timer <= 0.0:
		# NEW: Bias wander toward arena hotspots (orbs, abilities, high ground)
		var use_hotspot: bool = rng.randf() < 0.6  # 60% chance to wander toward hotspot

		if use_hotspot and (target_orb or target_ability):
			# Wander toward collectible
			var target_pos: Vector3 = target_orb.global_position if target_orb else target_ability.global_position
			var offset: Vector3 = Vector3(rng.randf_range(-10, 10), 0, rng.randf_range(-10, 10))
			wander_target = target_pos + offset
		elif use_hotspot and not cached_platforms.is_empty():
			# Wander toward a random elevated platform
			var random_platform: Dictionary = cached_platforms[rng.randi() % cached_platforms.size()]
			var offset: Vector3 = Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
			wander_target = random_platform.position + offset
		else:
			# Random wander
			var random_offset: Vector3 = Vector3(
				rng.randf_range(-wander_radius, wander_radius),
				0,
				rng.randf_range(-wander_radius, wander_radius)
			)
			wander_target = bot.global_position + random_offset

		wander_timer = rng.randf_range(3.0, 6.0)

	# Move toward wander target
	move_towards(wander_target, 0.7)

	# Look around for targets
	if target_player and is_instance_valid(target_player):
		rotate_to_target(target_player.global_position)

func do_chase(delta: float) -> void:
	"""Chase target player"""
	if not target_player or not is_instance_valid(target_player):
		change_state("WANDER", "Lost chase target")
		return

	var distance: float = bot.global_position.distance_to(target_player.global_position)

	# Move toward target
	move_towards(target_player.global_position, 1.0)
	rotate_to_target(target_player.global_position)

	# Use bounce for vertical mobility
	if distance > 8.0 and target_player.global_position.y > bot.global_position.y + 5.0:
		if bounce_cooldown_timer <= 0.0:
			bot_bounce()

	# Consider using ult to close distance quickly (aggressive chase)
	if "ult_system" in bot and bot.ult_system and bot.ult_system.is_ready():
		# Use ult to catch up to fleeing enemies
		if distance > attack_range and distance < ULT_OPTIMAL_RANGE * 1.5:
			var enemy_health: int = get_player_health(target_player)
			# More likely to ult-chase if enemy is weak
			var chase_ult_chance: float = 0.3 if enemy_health > 2 else 0.6
			if strategic_preference == "aggressive":
				chase_ult_chance += 0.2
			if rng.randf() < chase_ult_chance:
				activate_bot_ult()

func do_attack(delta: float) -> void:
	"""Attack target player"""
	if not target_player or not is_instance_valid(target_player):
		change_state("WANDER", "Lost attack target")
		return

	var distance: float = bot.global_position.distance_to(target_player.global_position)

	# Check if we have lightning - it has longer optimal range
	var has_lightning: bool = false
	var optimal_distance: float = attack_range
	if bot.current_ability and "ability_name" in bot.current_ability:
		if bot.current_ability.ability_name == "Lightning":
			has_lightning = true
			optimal_distance = LIGHTNING_OPTIMAL_RANGE

	# Strafe around target (using seeded RNG)
	if strafe_timer <= 0.0:
		strafe_direction = 1.0 if rng.randf() > 0.5 else -1.0
		strafe_timer = rng.randf_range(1.0, 2.5)

	# Calculate strafe position - stay at optimal range for current ability
	var to_target: Vector3 = target_player.global_position - bot.global_position
	to_target.y = 0
	to_target = to_target.normalized()

	var strafe_offset: Vector3 = to_target.cross(Vector3.UP) * strafe_direction * 5.0

	# If we have lightning, maintain optimal distance instead of closing in
	if has_lightning and distance < optimal_distance * 0.7:
		# Back up slightly to maintain lightning range
		strafe_offset -= to_target * 3.0

	var strafe_pos: Vector3 = target_player.global_position + strafe_offset

	move_towards(strafe_pos, 0.8)
	rotate_to_target(target_player.global_position)

	# Priority 1: Try to use ult if ready and good opportunity (using seeded RNG)
	if "ult_system" in bot and bot.ult_system and bot.ult_system.is_ready():
		if distance < ULT_OPTIMAL_RANGE and rng.randf() < aggression_level:
			activate_bot_ult()
			return

	# Priority 2: Use ability
	use_ability_smart()

func do_retreat(delta: float) -> void:
	"""NEW: Retreat from danger when low on health"""
	if not target_player or not is_instance_valid(target_player):
		change_state("WANDER", "No threat to retreat from")
		return

	var distance: float = bot.global_position.distance_to(target_player.global_position)

	# Find retreat direction (away from target)
	var to_enemy: Vector3 = target_player.global_position - bot.global_position
	to_enemy.y = 0
	to_enemy = to_enemy.normalized()

	var retreat_dir: Vector3 = -to_enemy
	var retreat_target: Vector3 = bot.global_position + retreat_dir * 20.0

	# Move away from enemy
	move_towards(retreat_target, 1.2)

	# Still face the enemy (retreat while watching)
	rotate_to_target(target_player.global_position)

	# Try to reach high ground
	if not target_platform.is_empty():
		move_towards(target_platform.position, 1.0)

	# Desperation ult: If enemy is close while retreating, counter with ult (using seeded RNG)
	if "ult_system" in bot and bot.ult_system and bot.ult_system.is_ready():
		if distance < ULT_OPTIMAL_RANGE * 0.8:
			# Last resort counter-attack
			var counter_chance: float = 0.5
			if strategic_preference == "aggressive":
				counter_chance = 0.7
			elif strategic_preference == "defensive":
				counter_chance = 0.4  # Even defensive bots will ult as last resort
			if rng.randf() < counter_chance:
				DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[%s] Desperation ult during retreat!" % get_ai_type(), false, get_entity_id())
				activate_bot_ult()
				return

	# Use defensive abilities (including lightning to keep distance)
	if bot.current_ability and rng.randf() < 0.3:
		use_ability_smart()

	# Stop retreating after timer
	if retreat_timer <= 0.0:
		retreat_cooldown = 3.0
		change_state("WANDER", "Retreat complete")

func do_collect_orb(delta: float) -> void:
	"""Collect orb behavior"""
	if not target_orb or not is_instance_valid(target_orb):
		change_state("WANDER", "Lost orb target")
		return

	var distance: float = bot.global_position.distance_to(target_orb.global_position)

	# Clear target if collected
	if distance < 1.5:
		target_orb = null
		change_state("WANDER", "Orb collected")
		return

	# Move toward orb
	move_towards(target_orb.global_position, 1.0)
	rotate_to_target(target_orb.global_position)

	# Jump if orb is above us
	var height_diff: float = target_orb.global_position.y - bot.global_position.y
	if height_diff > 2.0 and obstacle_jump_timer <= 0.0:
		bot_jump()
		obstacle_jump_timer = 0.5

func do_collect_ability(delta: float) -> void:
	"""NEW: Collect ability behavior with safety mechanisms"""
	if not target_ability or not is_instance_valid(target_ability):
		change_state("WANDER", "Lost ability target")
		return

	# Check timeout (15 seconds max)
	var current_time: float = Time.get_ticks_msec() / 1000.0
	var collection_duration: float = current_time - ability_collection_start_time

	if collection_duration >= ABILITY_COLLECTION_TIMEOUT:
		DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[%s] Ability collection timeout (%.1fs)" % [get_ai_type(), collection_duration], false, get_entity_id())

		# Add to blacklist
		if target_ability not in ability_blacklist:
			ability_blacklist.append(target_ability)

		target_ability = null
		change_state("WANDER", "Ability collection timeout")
		return

	var distance: float = bot.global_position.distance_to(target_ability.global_position)

	# Clear target if collected (very close or we have an ability now)
	if distance < 1.5 or bot.current_ability:
		target_ability = null
		change_state("WANDER", "Ability collected")
		return

	# Move toward ability
	move_towards(target_ability.global_position, 1.0)
	rotate_to_target(target_ability.global_position)

	# Jump if ability is above us
	var height_diff: float = target_ability.global_position.y - bot.global_position.y
	if height_diff > 2.0 and obstacle_jump_timer <= 0.0:
		bot_jump()
		obstacle_jump_timer = 0.5

# ============================================================================
# STATE MACHINE
# ============================================================================

func update_state() -> void:
	"""Update state based on priorities"""
	# PRIORITY 1: Retreat if low health and cautious (using seeded RNG)
	if should_retreat() and retreat_cooldown <= 0.0:
		if state != "RETREAT":
			retreat_timer = rng.randf_range(4.0, 7.0)
			change_state("RETREAT", "Low health retreat")
		return

	# PRIORITY 2: Collect abilities if we don't have one
	if not bot.current_ability and target_ability and is_instance_valid(target_ability):
		var distance: float = bot.global_position.distance_to(target_ability.global_position)

		# Prioritize abilities if visible or close
		if distance < 15.0 or can_see_target(target_ability):
			if state != "COLLECT_ABILITY":
				change_state("COLLECT_ABILITY", "Ability %.1fu away" % distance)
			return

	# PRIORITY 3: Attack if in range and have ability
	if target_player and is_instance_valid(target_player) and bot.current_ability:
		var distance: float = bot.global_position.distance_to(target_player.global_position)

		# Determine effective attack range based on ability
		var effective_attack_range: float = attack_range
		if "ability_name" in bot.current_ability:
			match bot.current_ability.ability_name:
				"Lightning":
					effective_attack_range = LIGHTNING_OPTIMAL_RANGE  # Lightning has long range
				"Cannon":
					effective_attack_range = CANNON_OPTIMAL_RANGE

		if distance < effective_attack_range:
			if state != "ATTACK":
				change_state("ATTACK", "Target in attack range (%.1fu)" % distance)
			return

	# PRIORITY 4: Chase if target found and we have ability
	if should_chase():
		if state != "CHASE":
			change_state("CHASE", "Chasing target")
		return

	# PRIORITY 5: Collect orbs for leveling
	if target_orb and is_instance_valid(target_orb):
		var distance: float = bot.global_position.distance_to(target_orb.global_position)

		# Only collect orbs if no combat and they're close
		if distance < 20.0 and (not target_player or not is_instance_valid(target_player)):
			if state != "COLLECT_ORB":
				change_state("COLLECT_ORB", "Collecting orb")
			return

	# PRIORITY 6: Arena-specific state updates
	handle_arena_specific_state_updates()

	# DEFAULT: Wander
	if state != "WANDER":
		change_state("WANDER", "No priority targets")

# ============================================================================
# DECISION MAKING
# ============================================================================

func should_retreat() -> bool:
	"""NEW: Determine if bot should retreat (health <= 2 with caution modifier) - uses seeded RNG"""
	if not bot:
		return false

	var bot_health: int = get_bot_health()

	# Retreat if health is critically low
	if bot_health <= 1:
		return true

	# Retreat if health is low and bot is cautious (using seeded RNG)
	if bot_health == 2:
		# Caution level affects retreat threshold
		# High caution (0.8) = 80% chance to retreat
		# Low caution (0.2) = 20% chance to retreat
		return rng.randf() < caution_level

	return false

func should_chase() -> bool:
	"""Determine if bot should chase target"""
	if not target_player or not is_instance_valid(target_player):
		return false

	# Don't chase without an ability
	if not has_property(bot, "current_ability") or not bot.current_ability:
		return false

	var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)

	# Always chase if enemy is weak and we're healthy
	var enemy_health: int = get_player_health(target_player)
	var bot_health: int = get_bot_health()
	if enemy_health <= 1 and bot_health >= 3:
		return distance_to_target < aggro_range * 1.5

	# Aggressive bots chase more eagerly
	if strategic_preference == "aggressive":
		return distance_to_target < aggro_range * 1.2

	# Standard chase range
	return distance_to_target < aggro_range

func use_ability_smart() -> void:
	"""Use bot's ability intelligently based on situation"""
	if not bot or not bot.current_ability:
		return

	if not bot.current_ability.has_method("use"):
		return

	# Don't spam abilities
	if action_timer > 0.0:
		return

	# Get ability name for smart usage
	var ability_name: String = ""
	if "ability_name" in bot.current_ability:
		ability_name = bot.current_ability.ability_name

	# Lightning-specific logic: use when target is in range and visible (using seeded RNG)
	if ability_name == "Lightning":
		if target_player and is_instance_valid(target_player):
			var distance: float = bot.global_position.distance_to(target_player.global_position)
			# Lightning has great range (100 units) but optimal around 25 units
			if distance < LIGHTNING_OPTIMAL_RANGE * 2.0:
				# Higher chance to use lightning due to auto-aim
				var use_chance: float = aggression_level + 0.15  # +15% for auto-aim
				if rng.randf() < use_chance:
					bot.current_ability.use()
					action_timer = rng.randf_range(1.5, 2.5)  # Slightly longer cooldown
					return
		return  # Don't use lightning without a target

	# Default ability usage based on aggression (using seeded RNG)
	var should_use: bool = rng.randf() < aggression_level

	if should_use:
		bot.current_ability.use()
		action_timer = rng.randf_range(0.5, 1.5)

func try_use_ult() -> void:
	"""Check and attempt to use ultimate attack"""
	if not bot:
		return

	# Check if bot has ult system
	if not "ult_system" in bot or not bot.ult_system:
		return

	var ult_system = bot.ult_system

	# Check if ult is ready
	if not ult_system.has_method("is_ready") or not ult_system.is_ready():
		return

	# Evaluate if this is a good time to ult
	if should_use_ult():
		activate_bot_ult()

func should_use_ult() -> bool:
	"""Determine if bot should use ultimate attack now"""
	if not bot or not "ult_system" in bot or not bot.ult_system:
		return false

	# Must have a target to ult effectively
	if not target_player or not is_instance_valid(target_player):
		return false

	var distance: float = bot.global_position.distance_to(target_player.global_position)

	# Don't ult if target is too far (ult is a dash attack)
	if distance > ULT_OPTIMAL_RANGE * 2.0:
		return false

	# Aggressive bots use ult more readily
	var base_chance: float = 0.0

	match strategic_preference:
		"aggressive":
			# Aggressive: Use ult when in optimal range
			if distance < ULT_OPTIMAL_RANGE:
				base_chance = 0.8
			else:
				base_chance = 0.5
		"defensive":
			# Defensive: Use ult mainly for finishing or escape
			var bot_health: int = get_bot_health()
			var enemy_health: int = get_player_health(target_player)

			# Use to finish low-health enemies
			if enemy_health <= 2 and distance < ULT_OPTIMAL_RANGE:
				base_chance = 0.9
			# Use when low health for aggressive counter
			elif bot_health <= 2:
				base_chance = 0.6
			else:
				base_chance = 0.3
		"support":
			# Support: Use ult opportunistically
			if distance < ULT_OPTIMAL_RANGE:
				base_chance = 0.5
			else:
				base_chance = 0.3
		_:  # "balanced"
			# Balanced: Standard usage
			if distance < ULT_OPTIMAL_RANGE:
				base_chance = 0.65
			else:
				base_chance = 0.4

	# Additional factors
	var enemy_health: int = get_player_health(target_player)

	# Bonus chance if enemy is weak
	if enemy_health <= 1:
		base_chance += 0.2

	# Bonus if target is visible and reachable
	if can_see_target(target_player):
		base_chance += 0.1

	# Clamp to valid range
	base_chance = clamp(base_chance, 0.0, 0.95)

	return rng.randf() < base_chance

func activate_bot_ult() -> void:
	"""Activate the bot's ultimate attack"""
	if not bot or not "ult_system" in bot or not bot.ult_system:
		return

	var ult_system = bot.ult_system

	# Make bot look at target before ulting (for better dash direction)
	if target_player and is_instance_valid(target_player):
		rotate_to_target(target_player.global_position)

		# Update camera arm to face target (ult uses camera direction)
		var camera_arm: Node3D = bot.get_node_or_null("CameraArm")
		if camera_arm:
			var direction: Vector3 = (target_player.global_position - bot.global_position).normalized()
			direction.y = 0
			if direction.length() > 0.01:
				# Set camera arm rotation to face target
				camera_arm.rotation.y = atan2(direction.x, direction.z)

	# Try to activate
	if ult_system.has_method("try_activate"):
		var success: bool = ult_system.try_activate()
		if success:
			DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[%s] ULTIMATE ACTIVATED! Dashing toward target!" % get_ai_type(), false, get_entity_id())
	elif ult_system.has_method("activate_ult"):
		ult_system.activate_ult()
		DebugLogger.dlog(DebugLogger.Category.BOT_AI, "[%s] ULTIMATE ACTIVATED! Dashing toward target!" % get_ai_type(), false, get_entity_id())

# ============================================================================
# VALIDATION HELPERS
# ============================================================================

func get_bot_health() -> int:
	"""Safely get bot health with fallback"""
	if not bot or not "health" in bot:
		return 5
	return bot.health

func get_player_health(player: Node) -> int:
	"""Safely get player health with fallback"""
	if not player or not is_instance_valid(player) or not "health" in player:
		return 5
	return player.health

func has_property(node: Node, property: String) -> bool:
	"""Safely check if node has a property"""
	if not node or not is_instance_valid(node):
		return false
	return property in node

func has_method_safe(node: Node, method: String) -> bool:
	"""Safely check if node has a method"""
	if not node or not is_instance_valid(node):
		return false
	return node.has_method(method)

func validate_bounce_properties() -> bool:
	"""Check if bot has required properties for bounce attack"""
	if not bot:
		return false
	return "is_bouncing" in bot and bot.has_method("start_bounce")

# ============================================================================
# DYNAMIC PROPERTIES (scale with level/abilities)
# ============================================================================

var current_roll_force: float = 300.0
var current_jump_impulse: float = 70.0
var current_spin_dash_force: float = 250.0
var current_bounce_back_impulse: float = 90.0

# ============================================================================
# EVENT HANDLERS (override when bot state changes)
# ============================================================================

func on_bot_death() -> void:
	"""Called when bot dies - pause AI briefly"""
	death_pause_timer = DEATH_PAUSE_DURATION
	target_player = null
	target_orb = null
	target_ability = null
	is_stuck = false
	consecutive_stuck_checks = 0
	change_state("WANDER", "Death reset")
