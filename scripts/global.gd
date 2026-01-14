extends Node

## Global
## Singleton for global game state and settings

# Player settings
var player_name: String = "Player"
var sensitivity: float = 0.005
var controller_sensitivity: float = 0.010

# Game settings
var music_directory: String = OS.get_executable_path().get_base_dir() + "/music"

func _ready() -> void:
	# Load settings from file if exists
	load_settings()

func save_settings() -> void:
	"""Save settings to file"""
	var config: ConfigFile = ConfigFile.new()

	config.set_value("player", "name", player_name)
	config.set_value("settings", "sensitivity", sensitivity)
	config.set_value("settings", "controller_sensitivity", controller_sensitivity)
	config.set_value("settings", "music_directory", music_directory)

	var error: Error = config.save("user://settings.cfg")
	if error != OK:
		print("Failed to save settings: ", error)

func load_settings() -> void:
	"""Load settings from file"""
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load("user://settings.cfg")

	if error != OK:
		print("No settings file found, using defaults")
		return

	player_name = config.get_value("player", "name", "Player")
	sensitivity = config.get_value("settings", "sensitivity", 0.005)
	controller_sensitivity = config.get_value("settings", "controller_sensitivity", 0.010)
	music_directory = config.get_value("settings", "music_directory", OS.get_executable_path().get_base_dir() + "/music")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_settings()
