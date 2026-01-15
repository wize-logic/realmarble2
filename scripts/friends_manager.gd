extends Node

## Friends Manager
## Manages friends list using CrazyGames SDK

signal friends_list_updated(friends: Array)
signal friend_invited(friend_id: String, success: bool)
signal friend_online_status_changed(friend_id: String, online: bool)

var friends_list: Array = []
var pending_invites: Array = []

func _ready() -> void:
	# Connect to CrazyGames SDK signals
	if CrazyGamesSDK:
		CrazyGamesSDK.sdk_initialized.connect(_on_sdk_initialized)
		CrazyGamesSDK.friends_loaded.connect(_on_friends_loaded)
		CrazyGamesSDK.friend_invited.connect(_on_friend_invited)

func _on_sdk_initialized(success: bool) -> void:
	if success:
		print("FriendsManager: SDK initialized, loading friends...")
		refresh_friends_list()

func _on_friends_loaded(friends: Array) -> void:
	print("FriendsManager: Friends list loaded (", friends.size(), " friends)")
	friends_list = friends
	friends_list_updated.emit(friends_list)

func _on_friend_invited(friend_id: String, success: bool) -> void:
	print("FriendsManager: Friend invite result - ", friend_id, " success: ", success)
	friend_invited.emit(friend_id, success)

	if success:
		# Remove from pending
		pending_invites.erase(friend_id)

# Get friends list
func get_friends() -> Array:
	return friends_list

# Get online friends
func get_online_friends() -> Array:
	var online: Array = []
	for friend in friends_list:
		if friend.get("online", false):
			online.append(friend)
	return online

# Get offline friends
func get_offline_friends() -> Array:
	var offline: Array = []
	for friend in friends_list:
		if not friend.get("online", false):
			offline.append(friend)
	return offline

# Refresh friends list from SDK
func refresh_friends_list() -> void:
	if CrazyGamesSDK:
		CrazyGamesSDK.get_friends()
	else:
		print("FriendsManager: CrazyGames SDK not available")
		# Load mock data for testing
		_load_mock_friends()

# Invite friend to game
func invite_to_game(friend_id: String) -> void:
	if CrazyGamesSDK:
		if not pending_invites.has(friend_id):
			pending_invites.append(friend_id)
		CrazyGamesSDK.invite_friend(friend_id)
	else:
		print("FriendsManager: Mock invite sent to ", friend_id)
		friend_invited.emit(friend_id, true)

# Check if friend is online
func is_friend_online(friend_id: String) -> bool:
	for friend in friends_list:
		if friend.get("id", "") == friend_id:
			return friend.get("online", false)
	return false

# Get friend by ID
func get_friend(friend_id: String) -> Dictionary:
	for friend in friends_list:
		if friend.get("id", "") == friend_id:
			return friend
	return {}

# Get friend count
func get_friend_count() -> int:
	return friends_list.size()

# Get online friend count
func get_online_friend_count() -> int:
	var count = 0
	for friend in friends_list:
		if friend.get("online", false):
			count += 1
	return count

# Check if pending invite
func has_pending_invite(friend_id: String) -> bool:
	return pending_invites.has(friend_id)

# Load mock friends for testing (when not on CrazyGames)
func _load_mock_friends() -> void:
	friends_list = [
		{
			"id": "friend_001",
			"username": "SpeedyMarble",
			"profilePictureUrl": "",
			"online": true,
			"inGame": false
		},
		{
			"id": "friend_002",
			"username": "RollingThunder",
			"profilePictureUrl": "",
			"online": true,
			"inGame": true
		},
		{
			"id": "friend_003",
			"username": "MarbleMaster",
			"profilePictureUrl": "",
			"online": false,
			"inGame": false
		},
		{
			"id": "friend_004",
			"username": "BounceKing",
			"profilePictureUrl": "",
			"online": false,
			"inGame": false
		},
		{
			"id": "friend_005",
			"username": "DashDemon",
			"profilePictureUrl": "",
			"online": true,
			"inGame": false
		}
	]
	friends_list_updated.emit(friends_list)
