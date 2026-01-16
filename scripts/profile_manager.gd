extends Node

## User Profile Manager
## Manages user profiles using CrazyGames SDK

signal profile_updated(profile: Dictionary)
signal profile_loaded(profile: Dictionary)

var current_profile: Dictionary = {
	"id": "",
	"username": "Guest",
	"profilePictureUrl": "",
	"isAuthenticated": false,
	"stats": {
		"total_kills": 0,
		"total_deaths": 0,
		"total_matches": 0,
		"total_wins": 0,
		"favorite_ability": "",
		"play_time_seconds": 0
	},
	"preferences": {
		"sensitivity": 0.005,
		"controller_sensitivity": 0.010,
		"music_directory": "res://music",
		"sfx_enabled": true,
		"music_enabled": true
	}
}

func _ready() -> void:
	# Connect to CrazyGames SDK signals
	if CrazyGamesSDK:
		CrazyGamesSDK.sdk_initialized.connect(_on_sdk_initialized)
		CrazyGamesSDK.user_info_loaded.connect(_on_user_info_loaded)
		CrazyGamesSDK.auth_completed.connect(_on_auth_completed)

	# Load local profile data
	_load_local_profile()

func _on_sdk_initialized(success: bool) -> void:
	if success:
		print("ProfileManager: SDK initialized, loading user info...")
		CrazyGamesSDK.get_user_info()

func _on_user_info_loaded(user_info: Dictionary) -> void:
	print("ProfileManager: User info loaded from SDK")
	current_profile["id"] = user_info.get("id", "")
	current_profile["username"] = user_info.get("username", "Guest")
	current_profile["profilePictureUrl"] = user_info.get("profilePictureUrl", "")
	current_profile["isAuthenticated"] = user_info.get("isAuthenticated", false)

	# Update Global.player_name with CrazyGames username
	if current_profile["username"] != "Guest" and Global:
		Global.player_name = current_profile["username"]

	profile_loaded.emit(current_profile)

func _on_auth_completed(success: bool) -> void:
	if success:
		print("ProfileManager: Auth completed successfully")
		CrazyGamesSDK.get_user_info()

# Get current profile
func get_profile() -> Dictionary:
	return current_profile

# Get username
func get_username() -> String:
	return current_profile.get("username", "Guest")

# Check if user is authenticated
func is_authenticated() -> bool:
	return current_profile.get("isAuthenticated", false)

# Show authentication prompt
func show_login() -> void:
	if CrazyGamesSDK:
		CrazyGamesSDK.show_auth_prompt()
	else:
		print("ProfileManager: CrazyGames SDK not available")

# Show account linking prompt
func show_account_link() -> void:
	if CrazyGamesSDK:
		CrazyGamesSDK.show_account_link_prompt()
	else:
		print("ProfileManager: CrazyGames SDK not available")

# Update stats
func update_stats(stat_name: String, value: int) -> void:
	if current_profile["stats"].has(stat_name):
		current_profile["stats"][stat_name] = value
		_save_local_profile()
		profile_updated.emit(current_profile)

func increment_stat(stat_name: String, amount: int = 1) -> void:
	if current_profile["stats"].has(stat_name):
		current_profile["stats"][stat_name] += amount
		_save_local_profile()
		profile_updated.emit(current_profile)

# Record match results
func record_match_result(kills: int, deaths: int, won: bool) -> void:
	increment_stat("total_kills", kills)
	increment_stat("total_deaths", deaths)
	increment_stat("total_matches", 1)
	if won:
		increment_stat("total_wins", 1)

# Get K/D ratio
func get_kd_ratio() -> float:
	var deaths = current_profile["stats"]["total_deaths"]
	if deaths == 0:
		return float(current_profile["stats"]["total_kills"])
	return float(current_profile["stats"]["total_kills"]) / float(deaths)

# Update preferences
func update_preference(pref_name: String, value) -> void:
	if current_profile["preferences"].has(pref_name):
		current_profile["preferences"][pref_name] = value
		_save_local_profile()
		profile_updated.emit(current_profile)

# Get preference
func get_preference(pref_name: String, default_value = null):
	return current_profile["preferences"].get(pref_name, default_value)

# Save profile to local storage
func _save_local_profile() -> void:
	var config = ConfigFile.new()

	# Save stats
	for key in current_profile["stats"]:
		config.set_value("stats", key, current_profile["stats"][key])

	# Save preferences
	for key in current_profile["preferences"]:
		config.set_value("preferences", key, current_profile["preferences"][key])

	var err = config.save("user://profile.cfg")
	if err != OK:
		print("ProfileManager: Failed to save profile: ", err)

# Load profile from local storage
func _load_local_profile() -> void:
	var config = ConfigFile.new()
	var err = config.load("user://profile.cfg")

	if err != OK:
		print("ProfileManager: No local profile found, using defaults")
		return

	# Load stats
	for key in current_profile["stats"]:
		if config.has_section_key("stats", key):
			current_profile["stats"][key] = config.get_value("stats", key)

	# Load preferences
	for key in current_profile["preferences"]:
		if config.has_section_key("preferences", key):
			current_profile["preferences"][key] = config.get_value("preferences", key)

	# Sync with Global settings
	if Global:
		Global.sensitivity = current_profile["preferences"]["sensitivity"]
		Global.controller_sensitivity = current_profile["preferences"]["controller_sensitivity"]
		Global.music_directory = current_profile["preferences"]["music_directory"]

	print("ProfileManager: Local profile loaded")
	profile_loaded.emit(current_profile)

# Reset stats (for testing or player request)
func reset_stats() -> void:
	for key in current_profile["stats"]:
		current_profile["stats"][key] = 0
	_save_local_profile()
	profile_updated.emit(current_profile)
