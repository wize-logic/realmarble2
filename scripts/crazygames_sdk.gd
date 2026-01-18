extends Node

## CrazyGames SDK Bridge for Godot
## Provides interface to CrazyGames SDK JavaScript functions

signal sdk_initialized(success: bool)
signal user_info_loaded(user_info: Dictionary)
signal auth_completed(success: bool)
signal account_linked(success: bool)
signal friends_loaded(friends: Array)
signal friend_invited(friend_id: String, success: bool)
signal ad_finished(success: bool, ad_type: String)
signal banner_shown(success: bool)

var is_initialized: bool = false
var user_info: Dictionary = {}
var friends_list: Array = []

# Check if running in web browser
var is_web: bool = OS.has_feature("web")

func _ready() -> void:
	if is_web:
		_setup_javascript_bridge()
		# Wait a moment for the SDK to initialize
		await get_tree().create_timer(0.5).timeout
	else:
		print("CrazyGames SDK: Not running in web browser, using mock mode")
		is_initialized = true
		sdk_initialized.emit(true)

func _setup_javascript_bridge() -> void:
	if not is_web:
		return

	var js_code = """
		window.godotCallbacks.onCrazyGamesEvent = function(eventType, dataJson) {
			// Send event to Godot
			if (window.godotInstance) {
				window.godotInstance.callGodotCallback(eventType, dataJson);
			}
		};
	"""
	JavaScriptBridge.eval(js_code, true)
	print("CrazyGames SDK: JavaScript bridge initialized")

# Called from JavaScript when events occur
func _on_crazygames_event(event_type: String, data_json: String) -> void:
	var data = JSON.parse_string(data_json)
	if data == null:
		data = {}

	match event_type:
		"sdk_initialized":
			is_initialized = data.get("success", false)
			sdk_initialized.emit(is_initialized)
			print("CrazyGames SDK initialized: ", is_initialized)

		"user_info_loaded":
			user_info = data
			user_info_loaded.emit(user_info)
			print("User info loaded: ", user_info)

		"auth_completed":
			auth_completed.emit(data.get("success", false))
			print("Auth completed: ", data.get("success", false))

		"account_linked":
			account_linked.emit(data.get("success", false))
			print("Account linked: ", data.get("success", false))

		"friends_loaded":
			friends_list = data.get("friends", [])
			friends_loaded.emit(friends_list)
			print("Friends loaded: ", friends_list.size(), " friends")

		"friend_invited":
			friend_invited.emit(data.get("friendId", ""), data.get("success", false))
			print("Friend invited: ", data)

		"ad_finished":
			ad_finished.emit(data.get("success", false), data.get("type", "midgame"))
			print("Ad finished: ", data)

		"banner_shown":
			banner_shown.emit(data.get("success", false))
			print("Banner shown: ", data.get("success", false))

# User methods
func get_user_info() -> Dictionary:
	if not is_web:
		return _get_mock_user_info()

	var js_code = "window.CrazyGamesSDK.getUserInfo();"
	var result = JavaScriptBridge.eval(js_code, true)
	return user_info if user_info.size() > 0 else {}

func is_user_authenticated() -> bool:
	return user_info.get("isAuthenticated", false)

func show_auth_prompt() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock auth prompt shown")
		await get_tree().create_timer(0.5).timeout
		auth_completed.emit(true)
		return

	var js_code = "window.CrazyGamesSDK.showAuthPrompt();"
	JavaScriptBridge.eval(js_code, true)

func show_account_link_prompt() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock account link prompt shown")
		await get_tree().create_timer(0.5).timeout
		account_linked.emit(true)
		return

	var js_code = "window.CrazyGamesSDK.showAccountLinkPrompt();"
	JavaScriptBridge.eval(js_code, true)

# Friends methods
func get_friends() -> Array:
	if not is_web:
		return _get_mock_friends()

	var js_code = "window.CrazyGamesSDK.getFriends();"
	JavaScriptBridge.eval(js_code, true)
	return friends_list

func invite_friend(friend_id: String) -> void:
	if not is_web:
		print("CrazyGames SDK: Mock friend invite sent to ", friend_id)
		await get_tree().create_timer(0.5).timeout
		friend_invited.emit(friend_id, true)
		return

	var js_code = "window.CrazyGamesSDK.inviteFriend('" + friend_id + "');"
	JavaScriptBridge.eval(js_code, true)

# Ad methods
func show_ad(ad_type: String = "midgame") -> void:
	if not is_web:
		print("CrazyGames SDK: Mock ad shown (", ad_type, ")")
		await get_tree().create_timer(2.0).timeout
		ad_finished.emit(true, ad_type)
		return

	var js_code = "window.CrazyGamesSDK.showAd('" + ad_type + "');"
	JavaScriptBridge.eval(js_code, true)

# Game lifecycle methods
func gameplay_start() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock gameplay started")
		return

	# Safe JS call - check if SDK exists before calling
	var js_code = """
		if (typeof window.CrazyGamesSDK !== 'undefined' && typeof window.CrazyGamesSDK.gameplayStart === 'function') {
			window.CrazyGamesSDK.gameplayStart();
		}
	"""
	JavaScriptBridge.eval(js_code, true)

func gameplay_stop() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock gameplay stopped")
		return

	# Safe JS call - check if SDK exists before calling
	var js_code = """
		if (typeof window.CrazyGamesSDK !== 'undefined' && typeof window.CrazyGamesSDK.gameplayStop === 'function') {
			window.CrazyGamesSDK.gameplayStop();
		}
	"""
	JavaScriptBridge.eval(js_code, true)

func happytime() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock happytime!")
		return

	var js_code = "window.CrazyGamesSDK.happytime();"
	JavaScriptBridge.eval(js_code, true)

# Banner methods
func show_banner() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock banner shown")
		await get_tree().create_timer(0.5).timeout
		banner_shown.emit(true)
		return

	var js_code = "window.CrazyGamesSDK.showBanner();"
	JavaScriptBridge.eval(js_code, true)

func clear_banner() -> void:
	if not is_web:
		return

	var js_code = "window.CrazyGamesSDK.clearBanner();"
	JavaScriptBridge.eval(js_code, true)

func clear_all_banners() -> void:
	if not is_web:
		return

	var js_code = "window.CrazyGamesSDK.clearAllBanners();"
	JavaScriptBridge.eval(js_code, true)

# Mock data for testing outside of CrazyGames
func _get_mock_user_info() -> Dictionary:
	return {
		"id": "mock_user_123",
		"username": "TestPlayer",
		"profilePictureUrl": "",
		"isAuthenticated": false
	}

func _get_mock_friends() -> Array:
	return [
		{"id": "friend_1", "username": "Friend1", "online": true},
		{"id": "friend_2", "username": "Friend2", "online": false},
		{"id": "friend_3", "username": "Friend3", "online": true}
	]
