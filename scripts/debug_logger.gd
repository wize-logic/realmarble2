extends Node
## Centralized Debug Logging System
## Provides categorized, toggleable debug output with in-game menu

# Debug categories
enum Category {
	WORLD,           # Game world, spawning, rounds, game state
	PLAYER,          # Player movement, physics, inputs
	BOT_AI,          # Bot AI behavior, decisions, state changes
	ABILITIES,       # Ability usage, cooldowns, effects
	LEVEL_GEN,       # Level generation, platforms, geometry
	MULTIPLAYER,     # Networking, sync, connections
	UI,              # UI updates, menus, HUD
	AUDIO,           # Music, sound effects
	SPAWNERS,        # Ability/orb spawner logic
	RAILS,           # Rail grinding mechanics
	PROFILE,         # Profile/friends management
	CRAZYGAMES,      # CrazyGames SDK integration
	PERFORMANCE,     # Performance metrics, frame times
	PHYSICS,         # Physics debugging, collisions
	OTHER            # Uncategorized
}

# Category display names for UI
const CATEGORY_NAMES: Dictionary = {
	Category.WORLD: "World & Game Logic",
	Category.PLAYER: "Player",
	Category.BOT_AI: "Bot AI",
	Category.ABILITIES: "Abilities",
	Category.LEVEL_GEN: "Level Generation",
	Category.MULTIPLAYER: "Multiplayer",
	Category.UI: "UI & Menus",
	Category.AUDIO: "Audio",
	Category.SPAWNERS: "Item Spawners",
	Category.RAILS: "Rail Grinding",
	Category.PROFILE: "Profile & Friends",
	Category.CRAZYGAMES: "CrazyGames SDK",
	Category.PERFORMANCE: "Performance",
	Category.PHYSICS: "Physics",
	Category.OTHER: "Other"
}

# Category colors for console output
const CATEGORY_COLORS: Dictionary = {
	Category.WORLD: "cyan",
	Category.PLAYER: "green",
	Category.BOT_AI: "yellow",
	Category.ABILITIES: "magenta",
	Category.LEVEL_GEN: "blue",
	Category.MULTIPLAYER: "red",
	Category.UI: "white",
	Category.AUDIO: "purple",
	Category.SPAWNERS: "orange",
	Category.RAILS: "teal",
	Category.PROFILE: "pink",
	Category.CRAZYGAMES: "lime",
	Category.PERFORMANCE: "gray",
	Category.PHYSICS: "brown",
	Category.OTHER: "white"
}

# Toggle state for each category (all OFF by default)
var enabled_categories: Dictionary = {}

# Global master toggle
var debug_enabled: bool = false

# Entity filtering (null = show all entities, otherwise show only specific entity ID)
var watched_entity_id: Variant = null

func _ready() -> void:
	# Initialize all categories as disabled
	for category in Category.values():
		enabled_categories[category] = false

	# Load saved debug preferences
	load_preferences()

func dlog(category: Category, message: String, force: bool = false, entity_id: Variant = null) -> void:
	"""Debug log a message if the category is enabled or force flag is set

	Args:
		category: The debug category
		message: The message to log
		force: If true, bypass all filters
		entity_id: Optional entity ID (player/bot ID). If set and watched_entity_id is set, only logs from watched entity show
	"""
	if not debug_enabled and not force:
		return

	if not enabled_categories.get(category, false) and not force:
		return

	# Entity filtering: if watched_entity_id is set, only show logs from that entity
	if not force and watched_entity_id != null and entity_id != null and entity_id != watched_entity_id:
		return

	var category_name: String = CATEGORY_NAMES.get(category, "UNKNOWN")
	var prefix: String = "[%s]" % category_name

	# Add entity ID prefix if provided
	if entity_id != null:
		var entity_name: String = ""
		var id_int: int = int(entity_id)
		if id_int >= 9000:
			entity_name = "Bot_%d" % (id_int - 9000)
		else:
			entity_name = "Player"
		prefix = "[%s][%s]" % [category_name, entity_name]

	print("%s %s" % [prefix, message])

func dlogf(category: Category, format: String, args: Array, force: bool = false, entity_id: Variant = null) -> void:
	"""Debug log a formatted message"""
	if not debug_enabled and not force:
		return

	if not enabled_categories.get(category, false) and not force:
		return

	var message: String = format % args
	dlog(category, message, true, entity_id)  # Already checked, pass force

func enable_category(category: Category) -> void:
	"""Enable logging for a specific category"""
	enabled_categories[category] = true
	save_preferences()

func disable_category(category: Category) -> void:
	"""Disable logging for a specific category"""
	enabled_categories[category] = false
	save_preferences()

func toggle_category(category: Category) -> void:
	"""Toggle logging for a specific category"""
	enabled_categories[category] = not enabled_categories.get(category, false)
	save_preferences()

func is_category_enabled(category: Category) -> bool:
	"""Check if a category is enabled"""
	return debug_enabled and enabled_categories.get(category, false)

func enable_all() -> void:
	"""Enable all debug categories"""
	debug_enabled = true
	for category in Category.values():
		enabled_categories[category] = true
	save_preferences()

func disable_all() -> void:
	"""Disable all debug categories"""
	for category in Category.values():
		enabled_categories[category] = false
	debug_enabled = false
	save_preferences()

func set_watched_entity(entity_id: int) -> void:
	"""Set which entity to watch (filter logs to only this entity)"""
	watched_entity_id = entity_id
	save_preferences()
	var entity_name: String = ""
	if entity_id >= 9000:
		entity_name = "Bot_%d" % (entity_id - 9000)
	else:
		entity_name = "Player"
	print("[DebugLogger] Now watching: %s (ID: %d)" % [entity_name, entity_id])

func clear_watched_entity() -> void:
	"""Clear entity filter (show all entities)"""
	watched_entity_id = null
	save_preferences()
	print("[DebugLogger] Now watching: All entities")

func get_watched_entity() -> Variant:
	"""Get the currently watched entity ID (null = all)"""
	return watched_entity_id

func is_watching_entity(entity_id: int) -> bool:
	"""Check if a specific entity is being watched"""
	return watched_entity_id == null or watched_entity_id == entity_id

func save_preferences() -> void:
	"""Save debug preferences to disk"""
	var config := ConfigFile.new()
	config.set_value("debug", "enabled", debug_enabled)
	config.set_value("debug", "watched_entity_id", watched_entity_id)
	for category in Category.values():
		config.set_value("debug", "category_%d" % category, enabled_categories.get(category, false))
	config.save("user://debug_preferences.cfg")

func load_preferences() -> void:
	"""Load debug preferences from disk"""
	var config := ConfigFile.new()
	var err := config.load("user://debug_preferences.cfg")
	if err != OK:
		return  # No saved preferences, use defaults

	debug_enabled = config.get_value("debug", "enabled", false)
	watched_entity_id = config.get_value("debug", "watched_entity_id", -1) if config.has_section_key("debug", "watched_entity_id") else null
	for category in Category.values():
		enabled_categories[category] = config.get_value("debug", "category_%d" % category, false)
