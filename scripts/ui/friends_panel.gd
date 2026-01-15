extends PanelContainer

## Friends Panel UI
## Displays friends list and allows inviting friends to game

@onready var friends_list_container: VBoxContainer = $MarginContainer/VBox/ScrollContainer/FriendsList
@onready var online_count_label: Label = $MarginContainer/VBox/Header/OnlineCount
@onready var total_count_label: Label = $MarginContainer/VBox/Header/TotalCount
@onready var refresh_button: Button = $MarginContainer/VBox/Header/RefreshButton
@onready var close_button: Button = $MarginContainer/VBox/Header/CloseButton
@onready var no_friends_label: Label = $MarginContainer/VBox/NoFriends

signal closed

# Friend entry scene (will be created dynamically)
const FriendEntryScene = preload("res://scripts/ui/friend_entry.gd")

func _ready() -> void:
	# Connect signals
	if FriendsManager:
		FriendsManager.friends_list_updated.connect(_on_friends_list_updated)
		FriendsManager.friend_invited.connect(_on_friend_invited)

	# Connect button signals
	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_pressed)
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	# Load initial friends list
	_update_friends_display()

func _on_friends_list_updated(friends: Array) -> void:
	_update_friends_display()

func _on_friend_invited(friend_id: String, success: bool) -> void:
	if success:
		print("Friend invited successfully: ", friend_id)
		# Could show a notification here
	else:
		print("Failed to invite friend: ", friend_id)

func _update_friends_display() -> void:
	if not FriendsManager:
		return

	var friends = FriendsManager.get_friends()
	var online_count = FriendsManager.get_online_friend_count()

	# Update counts
	if online_count_label:
		online_count_label.text = "Online: %d" % online_count
	if total_count_label:
		total_count_label.text = "Total: %d" % friends.size()

	# Clear existing friend entries
	if friends_list_container:
		for child in friends_list_container.get_children():
			child.queue_free()

	# Show/hide no friends message
	if no_friends_label:
		no_friends_label.visible = (friends.size() == 0)

	# Add friend entries
	for friend in friends:
		_add_friend_entry(friend)

func _add_friend_entry(friend: Dictionary) -> void:
	if not friends_list_container:
		return

	# Create friend entry container
	var entry = PanelContainer.new()
	entry.custom_minimum_size = Vector2(0, 60)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	entry.add_child(margin)

	var hbox = HBoxContainer.new()
	margin.add_child(hbox)

	# Online indicator
	var online_indicator = ColorRect.new()
	online_indicator.custom_minimum_size = Vector2(12, 12)
	online_indicator.color = Color.GREEN if friend.get("online", false) else Color.GRAY
	hbox.add_child(online_indicator)

	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(10, 0)
	hbox.add_child(spacer1)

	# Friend info
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var username_label = Label.new()
	username_label.text = friend.get("username", "Unknown")
	username_label.add_theme_font_size_override("font_size", 18)
	info_vbox.add_child(username_label)

	var status_label = Label.new()
	if friend.get("inGame", false):
		status_label.text = "In Game"
		status_label.modulate = Color.YELLOW
	elif friend.get("online", false):
		status_label.text = "Online"
		status_label.modulate = Color.GREEN
	else:
		status_label.text = "Offline"
		status_label.modulate = Color.GRAY
	status_label.add_theme_font_size_override("font_size", 14)
	info_vbox.add_child(status_label)

	# Invite button
	if friend.get("online", false):
		var invite_button = Button.new()
		invite_button.text = "Invite"
		invite_button.custom_minimum_size = Vector2(100, 0)
		invite_button.pressed.connect(_on_invite_friend.bind(friend.get("id", "")))
		hbox.add_child(invite_button)

	friends_list_container.add_child(entry)

func _on_invite_friend(friend_id: String) -> void:
	if FriendsManager:
		FriendsManager.invite_to_game(friend_id)
		print("Inviting friend: ", friend_id)

func _on_refresh_pressed() -> void:
	if FriendsManager:
		FriendsManager.refresh_friends_list()

func _on_close_pressed() -> void:
	closed.emit()
	hide()

func show_panel() -> void:
	_update_friends_display()
	show()
