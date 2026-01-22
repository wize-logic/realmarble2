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

func _ready() -> void:
	# Initialize all categories as disabled
	for category in Category.values():
		enabled_categories[category] = false

	# Load saved debug preferences
	load_preferences()

func log(category: Category, message: String, force: bool = false) -> void:
	"""Log a message if the category is enabled or force flag is set"""
	if not debug_enabled and not force:
		return

	if not enabled_categories.get(category, false) and not force:
		return

	var category_name: String = CATEGORY_NAMES.get(category, "UNKNOWN")
	var prefix: String = "[%s]" % category_name
	print("%s %s" % [prefix, message])

func logf(category: Category, format: String, args: Array, force: bool = false) -> void:
	"""Log a formatted message"""
	if not debug_enabled and not force:
		return

	if not enabled_categories.get(category, false) and not force:
		return

	var message: String = format % args
	log(category, message, true)  # Already checked, pass force

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

func save_preferences() -> void:
	"""Save debug preferences to disk"""
	var config := ConfigFile.new()
	config.set_value("debug", "enabled", debug_enabled)
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
	for category in Category.values():
		enabled_categories[category] = config.get_value("debug", "category_%d" % category, false)
