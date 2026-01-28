extends Node

## CrazyGames SDK Bridge for Godot
## Full implementation of CrazyGames SDK v3 API:
## - User (auth, profile, tokens, system info)
## - Video Ads (midgame, rewarded, adblock detection)
## - Banner Ads (static, responsive, container management)
## - Game Lifecycle (gameplay, loading, settings, multiplayer invites)
## - Data / Cloud Saves (getItem, setItem, removeItem, clear)
## - In-Game Purchases (Xsolla token, order tracking)

# SDK lifecycle
signal sdk_initialized(success: bool)

# User module
signal user_info_loaded(user_info: Dictionary)
signal auth_completed(success: bool)
signal auth_state_changed()
signal account_linked(success: bool)
signal user_token_received(success: bool, token: String)
signal system_info_loaded(info: Dictionary)

# Friends module
signal friends_loaded(friends: Array)
signal friend_invited(friend_id: String, success: bool)

# Video Ads module
signal ad_started(ad_type: String)
signal ad_finished(success: bool, ad_type: String)
signal ad_error(ad_type: String, error_code: String, error_message: String)
signal adblock_result(has_adblock: bool)

# Banner Ads module
signal banner_shown(success: bool, container_id: String)
signal banner_error(container_id: String, error_code: String, error_message: String)

# Game settings
signal settings_loaded(settings: Dictionary)
signal settings_changed(settings: Dictionary)

# Multiplayer / Invites
signal invite_link_result(success: bool, link: String)
signal invite_param_result(key: String, value: String)
signal invite_button_shown(success: bool)

# Data / Cloud Saves
signal data_get_result(key: String, value)
signal data_set_result(key: String, success: bool)
signal data_remove_result(key: String, success: bool)
signal data_clear_result(success: bool)
signal data_error(operation: String, key: String, error_code: String, error_message: String)

# In-Game Purchases
signal xsolla_token_result(success: bool, token: String)
signal track_order_result(success: bool)

var is_initialized: bool = false
var user_info: Dictionary = {}
var system_info: Dictionary = {}
var friends_list: Array = []
var game_settings: Dictionary = {"disableChat": false, "muteAudio": false}

# Check if running in web browser
var is_web: bool = OS.has_feature("web")

func _ready() -> void:
	if is_web:
		_setup_javascript_bridge()
		await get_tree().create_timer(0.5).timeout
	else:
		print("CrazyGames SDK: Not running in web browser, using mock mode")
		is_initialized = true
		sdk_initialized.emit(true)

func _setup_javascript_bridge() -> void:
	if not is_web:
		return

	var js_code = """
		if (typeof window.godotCallbacks === 'undefined') {
			window.godotCallbacks = {};
		}
		window.godotCallbacks.onCrazyGamesEvent = function(eventType, dataJson) {
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
			if is_initialized:
				# Auto-register settings listener
				_js_call("window.CrazyGamesSDK.addSettingsChangeListener();")
				_js_call("window.CrazyGamesSDK.getSettings();")
			print("CrazyGames SDK initialized: ", is_initialized)

		# User events
		"user_info_loaded":
			user_info = data
			user_info_loaded.emit(user_info)
		"auth_completed":
			auth_completed.emit(data.get("success", false))
		"auth_state_changed":
			auth_state_changed.emit()
		"account_linked":
			account_linked.emit(data.get("success", false))
		"user_token_received":
			user_token_received.emit(data.get("success", false), data.get("token", ""))
		"system_info_loaded":
			system_info = data
			system_info_loaded.emit(system_info)

		# Friends events
		"friends_loaded":
			friends_list = data.get("friends", [])
			friends_loaded.emit(friends_list)
		"friend_invited":
			friend_invited.emit(data.get("friendId", ""), data.get("success", false))

		# Ad events
		"ad_started":
			ad_started.emit(data.get("type", "midgame"))
		"ad_finished":
			ad_finished.emit(data.get("success", false), data.get("type", "midgame"))
		"ad_error":
			ad_error.emit(data.get("type", "midgame"), data.get("code", "other"), data.get("error", ""))
		"adblock_result":
			adblock_result.emit(data.get("hasAdblock", false))

		# Banner events
		"banner_shown":
			banner_shown.emit(data.get("success", false), data.get("containerId", ""))
		"banner_error":
			banner_error.emit(data.get("containerId", ""), data.get("code", "other"), data.get("error", ""))

		# Settings events
		"settings_loaded":
			game_settings = data
			settings_loaded.emit(game_settings)
		"settings_changed":
			game_settings = data
			settings_changed.emit(game_settings)

		# Invite events
		"invite_link_result":
			invite_link_result.emit(data.get("success", false), data.get("link", ""))
		"invite_param_result":
			invite_param_result.emit(data.get("key", ""), data.get("value", ""))
		"invite_button_shown":
			invite_button_shown.emit(data.get("success", false))

		# Data events
		"data_get_result":
			if data.has("error"):
				data_error.emit("get", data.get("key", ""), data.get("code", "other"), data.get("error", ""))
			data_get_result.emit(data.get("key", ""), data.get("value"))
		"data_set_result":
			if data.has("error"):
				data_error.emit("set", data.get("key", ""), data.get("code", "other"), data.get("error", ""))
			data_set_result.emit(data.get("key", ""), data.get("success", false))
		"data_remove_result":
			if data.has("error"):
				data_error.emit("remove", data.get("key", ""), data.get("code", "other"), data.get("error", ""))
			data_remove_result.emit(data.get("key", ""), data.get("success", false))
		"data_clear_result":
			if data.has("error"):
				data_error.emit("clear", "", data.get("code", "other"), data.get("error", ""))
			data_clear_result.emit(data.get("success", false))

		# In-Game Purchases events
		"xsolla_token_result":
			xsolla_token_result.emit(data.get("success", false), data.get("token", ""))
		"track_order_result":
			track_order_result.emit(data.get("success", false))

# =====================
# User Methods
# =====================

func get_user_info() -> Dictionary:
	if not is_web:
		return _get_mock_user_info()
	_js_call("window.CrazyGamesSDK.getUserInfo();")
	return user_info if user_info.size() > 0 else {}

func is_user_authenticated() -> bool:
	return user_info.get("isAuthenticated", false)

func is_user_account_available() -> bool:
	if not is_web:
		return true
	var result = JavaScriptBridge.eval("window.CrazyGamesSDK.isUserAccountAvailable();", true)
	return result if result is bool else false

func show_auth_prompt() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock auth prompt shown")
		await get_tree().create_timer(0.5).timeout
		auth_completed.emit(true)
		return
	_js_call("window.CrazyGamesSDK.showAuthPrompt();")

func show_account_link_prompt() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock account link prompt shown")
		await get_tree().create_timer(0.5).timeout
		account_linked.emit(true)
		return
	_js_call("window.CrazyGamesSDK.showAccountLinkPrompt();")

func get_user_token() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock user token request")
		await get_tree().create_timer(0.3).timeout
		user_token_received.emit(true, "mock_token_abc123")
		return
	_js_call("window.CrazyGamesSDK.getUserToken();")

func get_system_info() -> Dictionary:
	if not is_web:
		return _get_mock_system_info()
	_js_call("window.CrazyGamesSDK.getSystemInfo();")
	return system_info

# =====================
# Friends Methods
# =====================

func get_friends() -> Array:
	if not is_web:
		return _get_mock_friends()
	_js_call("window.CrazyGamesSDK.getFriends();")
	return friends_list

func invite_friend(friend_id: String) -> void:
	if not is_web:
		print("CrazyGames SDK: Mock friend invite sent to ", friend_id)
		await get_tree().create_timer(0.5).timeout
		friend_invited.emit(friend_id, true)
		return
	_js_call("window.CrazyGamesSDK.inviteFriend('" + _escape_js(friend_id) + "');")

# =====================
# Video Ad Methods
# =====================

func request_ad(ad_type: String = "midgame") -> void:
	if not is_web:
		print("CrazyGames SDK: Mock ad requested (", ad_type, ")")
		await get_tree().create_timer(0.5).timeout
		ad_started.emit(ad_type)
		await get_tree().create_timer(2.0).timeout
		ad_finished.emit(true, ad_type)
		return
	_js_call("window.CrazyGamesSDK.requestAd('" + _escape_js(ad_type) + "');")

## Legacy alias for request_ad
func show_ad(ad_type: String = "midgame") -> void:
	request_ad(ad_type)

func has_adblock() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock adblock check")
		await get_tree().create_timer(0.3).timeout
		adblock_result.emit(false)
		return
	_js_call("window.CrazyGamesSDK.hasAdblock();")

# =====================
# Banner Ad Methods
# =====================

func request_banner(options: Dictionary = {}) -> void:
	if not is_web:
		print("CrazyGames SDK: Mock banner requested")
		await get_tree().create_timer(0.5).timeout
		banner_shown.emit(true, options.get("id", ""))
		return
	var opts_json = JSON.stringify(options)
	_js_call("window.CrazyGamesSDK.requestBanner(" + opts_json + ");")

func request_responsive_banner(container_id: String) -> void:
	if not is_web:
		print("CrazyGames SDK: Mock responsive banner requested for ", container_id)
		await get_tree().create_timer(0.5).timeout
		banner_shown.emit(true, container_id)
		return
	_js_call("window.CrazyGamesSDK.requestResponsiveBanner('" + _escape_js(container_id) + "');")

## Legacy alias for request_banner
func show_banner(options: Dictionary = {}) -> void:
	request_banner(options)

func clear_banner(container_id: String = "") -> void:
	if not is_web:
		return
	if container_id.is_empty():
		_js_call("window.CrazyGamesSDK.clearBanner();")
	else:
		_js_call("window.CrazyGamesSDK.clearBanner('" + _escape_js(container_id) + "');")

func clear_all_banners() -> void:
	if not is_web:
		return
	_js_call("window.CrazyGamesSDK.clearAllBanners();")

# =====================
# Game Lifecycle Methods
# =====================

func gameplay_start() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock gameplay started")
		return
	_js_safe_call("gameplayStart")

func gameplay_stop() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock gameplay stopped")
		return
	_js_safe_call("gameplayStop")

func loading_start() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock loading started")
		return
	_js_safe_call("loadingStart")

func loading_stop() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock loading stopped")
		return
	_js_safe_call("loadingStop")

func happytime() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock happytime!")
		return
	_js_call("window.CrazyGamesSDK.happytime();")

# =====================
# Settings Methods
# =====================

func get_settings() -> Dictionary:
	if not is_web:
		return game_settings
	_js_call("window.CrazyGamesSDK.getSettings();")
	return game_settings

func is_chat_disabled() -> bool:
	return game_settings.get("disableChat", false)

func is_audio_muted() -> bool:
	return game_settings.get("muteAudio", false)

# =====================
# Multiplayer / Invite Methods
# =====================

func is_instant_multiplayer() -> bool:
	if not is_web:
		return false
	var result = JavaScriptBridge.eval("window.CrazyGamesSDK.isInstantMultiplayer();", true)
	return result if result is bool else false

func invite_link(params: Dictionary = {}) -> void:
	if not is_web:
		print("CrazyGames SDK: Mock invite link generated")
		await get_tree().create_timer(0.3).timeout
		invite_link_result.emit(true, "https://crazygames.com/invite/mock_link")
		return
	var params_json = JSON.stringify(params)
	_js_call("window.CrazyGamesSDK.inviteLink(" + params_json + ");")

func get_invite_param(key: String) -> void:
	if not is_web:
		print("CrazyGames SDK: Mock invite param for ", key)
		await get_tree().create_timer(0.1).timeout
		invite_param_result.emit(key, "")
		return
	_js_call("window.CrazyGamesSDK.getInviteParam('" + _escape_js(key) + "');")

func show_invite_button(params: Dictionary = {}) -> void:
	if not is_web:
		print("CrazyGames SDK: Mock invite button shown")
		invite_button_shown.emit(true)
		return
	var params_json = JSON.stringify(params)
	_js_call("window.CrazyGamesSDK.showInviteButton(" + params_json + ");")

func hide_invite_button() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock invite button hidden")
		return
	_js_call("window.CrazyGamesSDK.hideInviteButton();")

# =====================
# Data / Cloud Saves Methods
# =====================

func data_get_item(key: String) -> void:
	if not is_web:
		print("CrazyGames SDK: Mock data get for key: ", key)
		await get_tree().create_timer(0.1).timeout
		data_get_result.emit(key, null)
		return
	_js_call("window.CrazyGamesSDK.dataGetItem('" + _escape_js(key) + "');")

func data_set_item(key: String, value: String) -> void:
	if not is_web:
		print("CrazyGames SDK: Mock data set for key: ", key)
		await get_tree().create_timer(0.1).timeout
		data_set_result.emit(key, true)
		return
	_js_call("window.CrazyGamesSDK.dataSetItem('" + _escape_js(key) + "', '" + _escape_js(value) + "');")

func data_remove_item(key: String) -> void:
	if not is_web:
		print("CrazyGames SDK: Mock data remove for key: ", key)
		await get_tree().create_timer(0.1).timeout
		data_remove_result.emit(key, true)
		return
	_js_call("window.CrazyGamesSDK.dataRemoveItem('" + _escape_js(key) + "');")

func data_clear() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock data clear")
		await get_tree().create_timer(0.1).timeout
		data_clear_result.emit(true)
		return
	_js_call("window.CrazyGamesSDK.dataClear();")

# =====================
# In-Game Purchases Methods
# =====================

func get_xsolla_user_token() -> void:
	if not is_web:
		print("CrazyGames SDK: Mock Xsolla token request")
		await get_tree().create_timer(0.3).timeout
		xsolla_token_result.emit(true, "mock_xsolla_token_abc123")
		return
	_js_call("window.CrazyGamesSDK.getXsollaUserToken();")

func track_order(provider: String = "xsolla", order_data: Dictionary = {}) -> void:
	if not is_web:
		print("CrazyGames SDK: Mock order tracked: ", provider)
		await get_tree().create_timer(0.1).timeout
		track_order_result.emit(true)
		return
	var order_json = JSON.stringify(order_data)
	_js_call("window.CrazyGamesSDK.trackOrder('" + _escape_js(provider) + "', " + order_json + ");")

# =====================
# Utility Methods
# =====================

## Safe JavaScript call with SDK existence check
func _js_safe_call(method_name: String) -> void:
	var js_code = """
		if (typeof window.CrazyGamesSDK !== 'undefined' && typeof window.CrazyGamesSDK.%s === 'function') {
			window.CrazyGamesSDK.%s();
		}
	""" % [method_name, method_name]
	JavaScriptBridge.eval(js_code, true)

## Direct JavaScript call
func _js_call(js_code: String) -> void:
	JavaScriptBridge.eval(js_code, true)

## Escape string for safe JavaScript injection
func _escape_js(value: String) -> String:
	return value.replace("\\", "\\\\").replace("'", "\\'").replace("\"", "\\\"").replace("\n", "\\n")

# =====================
# Mock Data (for testing outside CrazyGames)
# =====================

func _get_mock_user_info() -> Dictionary:
	return {
		"id": "mock_user_123",
		"username": "TestPlayer",
		"profilePictureUrl": "",
		"isAuthenticated": false
	}

func _get_mock_system_info() -> Dictionary:
	return {
		"countryCode": "US",
		"locale": "en-US",
		"device": {"type": "desktop"},
		"os": {"name": "Mock OS"},
		"browser": {"name": "Mock Browser"},
		"appType": "game"
	}

func _get_mock_friends() -> Array:
	return [
		{"id": "friend_1", "username": "Friend1", "online": true},
		{"id": "friend_2", "username": "Friend2", "online": false},
		{"id": "friend_3", "username": "Friend3", "online": true}
	]
