extends Node

## Global
## Singleton for global game state and settings

# Player settings
var player_name: String = "Player"
var sensitivity: float = 0.005
var controller_sensitivity: float = 0.010
var marble_color_index: int = 0  # Selected marble color (0 = Ruby Red)

# Game settings
var music_directory: String = _get_default_music_directory()

# Performance settings (0=Low, 1=Medium, 2=High)
# Low = maximum FPS, High = best visuals
var graphics_quality: int = 1  # Controls shader quality
var lighting_quality: int = 1  # Controls number of lights
var visualizer_quality: int = 1  # Controls visualizer shader quality
var visualizer_update_rate: int = 1  # 0=15fps, 1=30fps, 2=60fps

# Signal for when settings change
signal graphics_quality_changed(new_quality: int)
signal performance_settings_changed

func _get_default_music_directory() -> String:
	"""Get the default music directory based on whether we're in editor or exported"""
	# HTML5 builds must use res:// paths only (no filesystem access)
	if OS.has_feature("web"):
		return "res://music"

	var exe_path: String = OS.get_executable_path()

	# In editor, exe_path is empty, so use res://music
	if exe_path.is_empty():
		return "res://music"

	# In exported build, use folder next to executable
	return exe_path.get_base_dir() + "/music"

func _ready() -> void:
	# Load settings from file if exists
	load_settings()

func save_settings() -> void:
	"""Save settings to file"""
	var config: ConfigFile = ConfigFile.new()

	config.set_value("player", "name", player_name)
	config.set_value("player", "marble_color", marble_color_index)
	config.set_value("settings", "sensitivity", sensitivity)
	config.set_value("settings", "controller_sensitivity", controller_sensitivity)
	config.set_value("settings", "music_directory", music_directory)

	# Performance settings
	config.set_value("performance", "graphics_quality", graphics_quality)
	config.set_value("performance", "lighting_quality", lighting_quality)
	config.set_value("performance", "visualizer_quality", visualizer_quality)
	config.set_value("performance", "visualizer_update_rate", visualizer_update_rate)

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
	marble_color_index = config.get_value("player", "marble_color", 0)
	sensitivity = config.get_value("settings", "sensitivity", 0.005)
	controller_sensitivity = config.get_value("settings", "controller_sensitivity", 0.010)
	music_directory = config.get_value("settings", "music_directory", _get_default_music_directory())

	# Performance settings
	graphics_quality = config.get_value("performance", "graphics_quality", 1)
	lighting_quality = config.get_value("performance", "lighting_quality", 1)
	visualizer_quality = config.get_value("performance", "visualizer_quality", 1)
	visualizer_update_rate = config.get_value("performance", "visualizer_update_rate", 1)

## Set all performance quality levels at once (convenience function)
func set_performance_preset(preset: int) -> void:
	"""Set all performance settings to a preset: 0=Low, 1=Medium, 2=High"""
	graphics_quality = preset
	lighting_quality = preset
	visualizer_quality = preset
	visualizer_update_rate = preset
	graphics_quality_changed.emit(preset)
	performance_settings_changed.emit()
	save_settings()

## Get visualizer update interval based on rate setting
func get_visualizer_update_interval() -> float:
	"""Returns the update interval for visualizer based on quality setting"""
	match visualizer_update_rate:
		0: return 1.0 / 15.0  # 15 fps
		1: return 1.0 / 30.0  # 30 fps
		2: return 0.0  # Every frame
		_: return 1.0 / 30.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_settings()
