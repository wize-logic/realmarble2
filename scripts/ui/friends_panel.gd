extends PanelContainer

## Friends Panel UI
## Displays friends list and allows inviting friends to game

# Use get_node_or_null to avoid errors if nodes don't exist
var friends_list_container: VBoxContainer = null
var online_count_label: Label = null
var total_count_label: Label = null
var refresh_button: Button = null
var close_button: Button = null
var no_friends_label: Label = null

signal closed

func _ready() -> void:
	# Initialize node references (safely)
	friends_list_container = get_node_or_null("MarginContainer/VBox/ScrollContainer/FriendsList")
	online_count_label = get_node_or_null("MarginContainer/VBox/Header/OnlineCount")
	total_count_label = get_node_or_null("MarginContainer/VBox/Header/TotalCount")
	refresh_button = get_node_or_null("MarginContainer/VBox/Header/RefreshButton")
	close_button = get_node_or_null("MarginContainer/VBox/Header/CloseButton")
	no_friends_label = get_node_or_null("MarginContainer/VBox/NoFriends")

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

	# Create friend entry container with style guide styling
	var entry = PanelContainer.new()
	entry.custom_minimum_size = Vector2(0, 70)

	# Apply panel style from style guide
	var entry_style = StyleBoxFlat.new()
	entry_style.bg_color = Color(0.15, 0.15, 0.2, 0.6)
	entry_style.set_corner_radius_all(8)
	entry_style.border_color = Color(0.3, 0.7, 1, 0.3)
	entry_style.set_border_width_all(1)
	entry.add_theme_stylebox_override("panel", entry_style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	entry.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	# Online indicator
	var online_indicator = ColorRect.new()
	online_indicator.custom_minimum_size = Vector2(14, 14)
	online_indicator.color = Color(0.3, 1, 0.3, 1) if friend.get("online", false) else Color(0.5, 0.5, 0.5, 1)
	hbox.add_child(online_indicator)

	# Friend info
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(info_vbox)

	var username_label = Label.new()
	username_label.text = friend.get("username", "Unknown")
	username_label.add_theme_font_size_override("font_size", 18)
	username_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	info_vbox.add_child(username_label)

	var status_label = Label.new()
	if friend.get("inGame", false):
		status_label.text = "IN GAME"
		status_label.add_theme_color_override("font_color", Color(1, 0.8, 0, 1))
	elif friend.get("online", false):
		status_label.text = "ONLINE"
		status_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3, 1))
	else:
		status_label.text = "OFFLINE"
		status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	status_label.add_theme_font_size_override("font_size", 14)
	info_vbox.add_child(status_label)

	# Invite button
	if friend.get("online", false):
		var invite_button = Button.new()
		invite_button.text = "INVITE"
		invite_button.custom_minimum_size = Vector2(100, 40)

		# Apply button style from style guide
		var button_normal = StyleBoxFlat.new()
		button_normal.bg_color = Color(0.15, 0.15, 0.2, 0.8)
		button_normal.set_corner_radius_all(8)
		button_normal.border_color = Color(0.3, 0.7, 1, 0.4)
		button_normal.set_border_width_all(2)

		var button_hover = StyleBoxFlat.new()
		button_hover.bg_color = Color(0.2, 0.3, 0.4, 0.9)
		button_hover.set_corner_radius_all(8)
		button_hover.border_color = Color(0.3, 0.7, 1, 0.8)
		button_hover.set_border_width_all(2)

		var button_pressed = StyleBoxFlat.new()
		button_pressed.bg_color = Color(0.3, 0.5, 0.7, 1)
		button_pressed.set_corner_radius_all(8)
		button_pressed.border_color = Color(0.4, 0.8, 1, 1)
		button_pressed.set_border_width_all(2)

		invite_button.add_theme_stylebox_override("normal", button_normal)
		invite_button.add_theme_stylebox_override("hover", button_hover)
		invite_button.add_theme_stylebox_override("pressed", button_pressed)
		invite_button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		invite_button.add_theme_font_size_override("font_size", 16)

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
