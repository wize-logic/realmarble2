extends Control

## Lobby UI
## Interface for creating/joining games and player ready system

@onready var main_lobby_panel: PanelContainer = $MainLobbyPanel
@onready var game_lobby_panel: PanelContainer = $GameLobbyPanel

# Main lobby elements
@onready var player_name_input: LineEdit = $MainLobbyPanel/MarginContainer/VBox/PlayerNameInput
@onready var create_game_button: Button = $MainLobbyPanel/MarginContainer/VBox/CreateGameButton
@onready var join_game_button: Button = $MainLobbyPanel/MarginContainer/VBox/JoinGameButton
@onready var quick_play_button: Button = $MainLobbyPanel/MarginContainer/VBox/QuickPlayButton
@onready var room_code_input: LineEdit = $MainLobbyPanel/MarginContainer/VBox/RoomCodeInput

# Game lobby elements
@onready var room_code_label: Label = $GameLobbyPanel/MarginContainer/VBox/RoomCodeLabel
@onready var player_list_container: VBoxContainer = $GameLobbyPanel/MarginContainer/VBox/ScrollContainer/PlayerList
@onready var ready_button: Button = $GameLobbyPanel/MarginContainer/VBox/ReadyButton
@onready var start_game_button: Button = $GameLobbyPanel/MarginContainer/VBox/StartGameButton
@onready var leave_lobby_button: Button = $GameLobbyPanel/MarginContainer/VBox/LeaveLobbyButton
@onready var status_label: Label = $GameLobbyPanel/MarginContainer/VBox/StatusLabel

var multiplayer_manager: Node = null
var is_ready: bool = false
var spawn_bot_button: Button = null  # Created programmatically

# Room settings UI (created programmatically)
var room_settings_container: VBoxContainer = null
var size_slider: HSlider = null
var size_value_label: Label = null
var time_slider: HSlider = null
var time_value_label: Label = null
var video_walls_checkbox: CheckBox = null
var settings_display_label: Label = null  # For clients to see current settings

func _ready() -> void:
	# Get multiplayer manager
	multiplayer_manager = get_node("/root/MultiplayerManager")

	# Connect signals
	create_game_button.pressed.connect(_on_create_game_pressed)
	join_game_button.pressed.connect(_on_join_game_pressed)
	quick_play_button.pressed.connect(_on_quick_play_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_game_button.pressed.connect(_on_start_game_pressed)
	leave_lobby_button.pressed.connect(_on_leave_lobby_pressed)

	# Create add bot button (host only)
	spawn_bot_button = Button.new()
	spawn_bot_button.text = "ADD BOT"
	spawn_bot_button.visible = false
	spawn_bot_button.pressed.connect(_on_add_bot_pressed)

	# Style the button to match theme
	spawn_bot_button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	spawn_bot_button.add_theme_font_size_override("font_size", 20)

	# Add it to the VBox before the start game button
	var vbox: VBoxContainer = $GameLobbyPanel/MarginContainer/VBox
	var start_button_index: int = start_game_button.get_index()
	vbox.add_child(spawn_bot_button)
	vbox.move_child(spawn_bot_button, start_button_index)

	# Add back button to main lobby
	var back_button: Button = $MainLobbyPanel/MarginContainer/VBox/BackButton if has_node("MainLobbyPanel/MarginContainer/VBox/BackButton") else null
	if back_button:
		back_button.pressed.connect(_on_back_to_main_menu_pressed)

	# Connect multiplayer signals
	if multiplayer_manager:
		multiplayer_manager.lobby_created.connect(_on_lobby_created)
		multiplayer_manager.lobby_joined.connect(_on_lobby_joined)
		multiplayer_manager.connection_failed.connect(_on_connection_failed)
		multiplayer_manager.player_list_changed.connect(_update_player_list)
		multiplayer_manager.room_settings_changed.connect(_on_room_settings_changed)

	# Create room settings UI
	_create_room_settings_ui()

	# Initial state
	show_main_lobby()

	# Load saved player name
	if Global.player_name != "":
		player_name_input.text = Global.player_name
	else:
		player_name_input.text = "Player" + str(randi() % 9999)

func show_main_lobby() -> void:
	"""Show the main lobby screen"""
	main_lobby_panel.visible = true
	game_lobby_panel.visible = false
	start_game_button.visible = false
	# Hide room settings UI when leaving game lobby
	if room_settings_container:
		room_settings_container.visible = false
	if settings_display_label:
		settings_display_label.visible = false

func show_game_lobby() -> void:
	"""Show the game lobby screen"""
	main_lobby_panel.visible = false
	game_lobby_panel.visible = true

	# Reset ready button state
	is_ready = false
	ready_button.text = "NOT READY"
	ready_button.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	# Update UI based on role
	if multiplayer_manager and multiplayer_manager.is_host():
		start_game_button.visible = true
		if spawn_bot_button:
			spawn_bot_button.visible = true
		# Show room settings controls for host
		if room_settings_container:
			room_settings_container.visible = true
		if settings_display_label:
			settings_display_label.visible = false
		# Reset sliders to current settings
		_update_settings_display(multiplayer_manager.get_room_settings())
	else:
		start_game_button.visible = false
		if spawn_bot_button:
			spawn_bot_button.visible = false
		# Hide room settings controls for clients, show display label instead
		if room_settings_container:
			room_settings_container.visible = false
		if settings_display_label:
			settings_display_label.visible = true
		# Update display with current settings
		if multiplayer_manager:
			_update_settings_display(multiplayer_manager.get_room_settings())

	_update_player_list()

func _unhandled_input(event: InputEvent) -> void:
	"""Handle ESC key to go back"""
	if not visible:
		return

	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
		# If in game lobby, go back to main lobby
		if game_lobby_panel.visible:
			_on_leave_lobby_pressed()
		# If in main lobby, go back to main menu
		elif main_lobby_panel.visible:
			_on_back_to_main_menu_pressed()
		get_viewport().set_input_as_handled()

func _on_back_to_main_menu_pressed() -> void:
	"""Return to the main menu"""
	visible = false
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if world and world.has_method("show_main_menu"):
		world.show_main_menu()

func _on_create_game_pressed() -> void:
	"""Create a new game"""
	var player_name: String = player_name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player" + str(randi() % 9999)

	# Save player name
	Global.player_name = player_name

	if multiplayer_manager:
		var code: String = multiplayer_manager.create_game(player_name)
		if code.is_empty():
			status_label.text = "Failed to create game!"
		else:
			print("Game created with code: ", code)

func _on_join_game_pressed() -> void:
	"""Join a game by room code"""
	var player_name: String = player_name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player" + str(randi() % 9999)

	var code: String = room_code_input.text.strip_edges().to_upper()
	if code.is_empty():
		status_label.text = "Please enter a room code!"
		return

	# Save player name
	Global.player_name = player_name

	if multiplayer_manager:
		var success: bool = multiplayer_manager.join_game(player_name, code)
		if not success:
			status_label.text = "Failed to join game!"

func _on_quick_play_pressed() -> void:
	"""Quick play matchmaking"""
	var player_name: String = player_name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player" + str(randi() % 9999)

	# Save player name
	Global.player_name = player_name

	if multiplayer_manager:
		multiplayer_manager.quick_play(player_name)

func _on_ready_pressed() -> void:
	"""Toggle ready status"""
	is_ready = !is_ready

	if multiplayer_manager:
		multiplayer_manager.set_player_ready(is_ready)

	# Update button
	if is_ready:
		ready_button.text = "READY ✓"
		ready_button.add_theme_color_override("font_color", Color(0.3, 1, 0.3, 1))
	else:
		ready_button.text = "NOT READY"
		ready_button.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	_update_player_list()

func _on_start_game_pressed() -> void:
	"""Start the game (host only)"""
	if multiplayer_manager and multiplayer_manager.is_host():
		if multiplayer_manager.all_players_ready():
			multiplayer_manager.start_game()
			# Hide lobby UI
			visible = false
		else:
			status_label.text = "Not all players are ready!"

func _on_add_bot_pressed() -> void:
	"""Add a bot to the lobby (host only)"""
	if not multiplayer_manager or not multiplayer_manager.is_host():
		return

	# Check if lobby is already at max capacity (8 total: 1 player + 7 bots/others)
	var player_count: int = multiplayer_manager.get_player_count()
	if player_count >= 8:
		status_label.text = "Cannot add bot - max 8 total (you + 7 bots) reached!"
		return

	# Add bot to the multiplayer manager
	if multiplayer_manager.has_method("add_bot"):
		var bot_added: bool = multiplayer_manager.add_bot()
		if bot_added:
			status_label.text = "Bot added to lobby!"
			_update_player_list()
		else:
			status_label.text = "Failed to add bot (lobby full?)"
	else:
		# Fallback: manually add a bot entry to the player list
		var bot_count: int = 0
		var players: Array = multiplayer_manager.get_player_list()
		for player in players:
			if player.name.begins_with("Bot "):
				bot_count += 1

		var bot_name: String = "Bot " + str(bot_count + 1)
		# Add bot directly to player list (this is a fallback if multiplayer_manager doesn't support add_bot)
		status_label.text = "Bot added: " + bot_name
		_update_player_list()

func _on_leave_lobby_pressed() -> void:
	"""Leave the current lobby"""
	if multiplayer_manager:
		multiplayer_manager.leave_game()

	is_ready = false
	ready_button.text = "NOT READY"
	ready_button.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	show_main_lobby()

func _on_lobby_created(code: String) -> void:
	"""Called when lobby is created"""
	room_code_label.text = "Room Code: " + code
	status_label.text = "Waiting for players..."
	show_game_lobby()

func _on_lobby_joined(code: String) -> void:
	"""Called when joined a lobby"""
	room_code_label.text = "Room Code: " + code
	status_label.text = "Connected!"
	show_game_lobby()

func _on_connection_failed() -> void:
	"""Called when connection fails"""
	status_label.text = "Connection failed! Check the room code and try again."
	show_main_lobby()

func _update_player_list() -> void:
	"""Update the player list display"""
	# Clear existing list
	for child in player_list_container.get_children():
		child.queue_free()

	if not multiplayer_manager:
		return

	# Add players
	var players: Array = multiplayer_manager.get_player_list()
	for player in players:
		var player_label: Label = Label.new()
		var ready_icon: String = " ✓" if player.ready else ""
		var host_icon: String = " 👑" if player.peer_id == 1 else ""
		player_label.text = player.name + host_icon + ready_icon
		player_label.add_theme_font_size_override("font_size", 16)

		if player.ready:
			player_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3, 1))
		else:
			player_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))

		player_list_container.add_child(player_label)

	# Update status
	var player_count: int = multiplayer_manager.get_player_count()
	status_label.text = "Players: " + str(player_count) + "/" + str(multiplayer_manager.max_players)

	# Update start button availability for host
	if multiplayer_manager.is_host() and start_game_button:
		start_game_button.disabled = not multiplayer_manager.all_players_ready()

func _create_room_settings_ui() -> void:
	"""Create the room settings UI elements"""
	var vbox: VBoxContainer = $GameLobbyPanel/MarginContainer/VBox

	# Create container for room settings
	room_settings_container = VBoxContainer.new()
	room_settings_container.add_theme_constant_override("separation", 8)
	room_settings_container.visible = false

	# Find position after player list (before ready button)
	var ready_button_index: int = ready_button.get_index()
	vbox.add_child(room_settings_container)
	vbox.move_child(room_settings_container, ready_button_index)

	# Settings title
	var settings_title = Label.new()
	settings_title.text = "ROOM SETTINGS"
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_title.add_theme_font_size_override("font_size", 18)
	settings_title.add_theme_color_override("font_color", Color(0.3, 0.7, 1, 1))
	room_settings_container.add_child(settings_title)

	# Add separator
	var separator = HSeparator.new()
	room_settings_container.add_child(separator)

	# === LEVEL SIZE ===
	var size_section = VBoxContainer.new()
	size_section.add_theme_constant_override("separation", 4)
	room_settings_container.add_child(size_section)

	var size_label = Label.new()
	size_label.text = "Level Size"
	size_label.add_theme_font_size_override("font_size", 14)
	size_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	size_section.add_child(size_label)

	var size_hbox = HBoxContainer.new()
	size_hbox.add_theme_constant_override("separation", 10)
	size_section.add_child(size_hbox)

	var size_left = Label.new()
	size_left.text = "Small"
	size_left.add_theme_font_size_override("font_size", 12)
	size_left.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	size_hbox.add_child(size_left)

	size_slider = HSlider.new()
	size_slider.min_value = 1
	size_slider.max_value = 4
	size_slider.step = 1
	size_slider.value = 2
	size_slider.custom_minimum_size = Vector2(150, 20)
	size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_slider.value_changed.connect(_on_size_slider_changed)
	size_hbox.add_child(size_slider)

	var size_right = Label.new()
	size_right.text = "Huge"
	size_right.add_theme_font_size_override("font_size", 12)
	size_right.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	size_hbox.add_child(size_right)

	size_value_label = Label.new()
	size_value_label.text = "Medium"
	size_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	size_value_label.add_theme_font_size_override("font_size", 12)
	size_value_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	size_section.add_child(size_value_label)

	# === MATCH TIME ===
	var time_section = VBoxContainer.new()
	time_section.add_theme_constant_override("separation", 4)
	room_settings_container.add_child(time_section)

	var time_label = Label.new()
	time_label.text = "Match Duration"
	time_label.add_theme_font_size_override("font_size", 14)
	time_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	time_section.add_child(time_label)

	var time_hbox = HBoxContainer.new()
	time_hbox.add_theme_constant_override("separation", 10)
	time_section.add_child(time_hbox)

	var time_left = Label.new()
	time_left.text = "1 min"
	time_left.add_theme_font_size_override("font_size", 12)
	time_left.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	time_hbox.add_child(time_left)

	time_slider = HSlider.new()
	time_slider.min_value = 1
	time_slider.max_value = 5
	time_slider.step = 1
	time_slider.value = 3  # 5 minutes default
	time_slider.custom_minimum_size = Vector2(150, 20)
	time_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_slider.value_changed.connect(_on_time_slider_changed)
	time_hbox.add_child(time_slider)

	var time_right = Label.new()
	time_right.text = "15 min"
	time_right.add_theme_font_size_override("font_size", 12)
	time_right.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	time_hbox.add_child(time_right)

	time_value_label = Label.new()
	time_value_label.text = "5 Minutes"
	time_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_value_label.add_theme_font_size_override("font_size", 12)
	time_value_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	time_section.add_child(time_value_label)

	# === VIDEO WALLS ===
	var video_section = HBoxContainer.new()
	video_section.add_theme_constant_override("separation", 10)
	video_section.alignment = BoxContainer.ALIGNMENT_CENTER
	room_settings_container.add_child(video_section)

	video_walls_checkbox = CheckBox.new()
	video_walls_checkbox.text = "Enable Video Walls"
	video_walls_checkbox.button_pressed = false
	video_walls_checkbox.add_theme_font_size_override("font_size", 14)
	video_walls_checkbox.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	video_walls_checkbox.toggled.connect(_on_video_walls_toggled)
	video_section.add_child(video_walls_checkbox)

	# Add separator after settings
	var separator2 = HSeparator.new()
	room_settings_container.add_child(separator2)

	# === CLIENT-ONLY SETTINGS DISPLAY ===
	settings_display_label = Label.new()
	settings_display_label.text = ""
	settings_display_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_display_label.add_theme_font_size_override("font_size", 12)
	settings_display_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	settings_display_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_display_label.visible = false
	# Add to the main vbox, after room_settings_container position
	vbox.add_child(settings_display_label)
	vbox.move_child(settings_display_label, ready_button_index + 1)

func _on_size_slider_changed(value: float) -> void:
	"""Handle size slider value change"""
	if not multiplayer_manager or not multiplayer_manager.is_host():
		return

	var size_names: Array[String] = ["", "Small", "Medium", "Large", "Huge"]
	if size_value_label:
		size_value_label.text = size_names[int(value)]

	multiplayer_manager.set_room_setting("level_size", int(value))

func _on_time_slider_changed(value: float) -> void:
	"""Handle time slider value change"""
	if not multiplayer_manager or not multiplayer_manager.is_host():
		return

	var time_values: Array[float] = [60.0, 180.0, 300.0, 600.0, 900.0]
	var time_labels: Array[String] = ["1 Minute", "3 Minutes", "5 Minutes", "10 Minutes", "15 Minutes"]
	var index: int = int(value) - 1

	if time_value_label:
		time_value_label.text = time_labels[index]

	multiplayer_manager.set_room_setting("match_time", time_values[index])

func _on_video_walls_toggled(enabled: bool) -> void:
	"""Handle video walls checkbox toggle"""
	if not multiplayer_manager or not multiplayer_manager.is_host():
		return

	multiplayer_manager.set_room_setting("video_walls", enabled)

func _on_room_settings_changed(settings: Dictionary) -> void:
	"""Called when room settings are updated (host or received from host)"""
	_update_settings_display(settings)

func _update_settings_display(settings: Dictionary) -> void:
	"""Update the UI to show current room settings"""
	var level_size: int = settings.get("level_size", 2)
	var match_time: float = settings.get("match_time", 300.0)
	var video_walls: bool = settings.get("video_walls", false)

	# Update sliders/checkbox if we're host
	if multiplayer_manager and multiplayer_manager.is_host():
		if size_slider and int(size_slider.value) != level_size:
			size_slider.value = level_size
		if time_slider:
			var time_index: int = _time_to_slider_index(match_time)
			if int(time_slider.value) != time_index:
				time_slider.value = time_index
		if video_walls_checkbox and video_walls_checkbox.button_pressed != video_walls:
			video_walls_checkbox.button_pressed = video_walls

	# Update value labels
	var size_names: Array[String] = ["", "Small", "Medium", "Large", "Huge"]
	var size_display: String = size_names[level_size] if level_size >= 0 and level_size < size_names.size() else "Medium"
	if size_value_label:
		size_value_label.text = size_display

	var time_labels: Array[String] = ["1 Minute", "3 Minutes", "5 Minutes", "10 Minutes", "15 Minutes"]
	var time_index: int = _time_to_slider_index(match_time) - 1  # Convert slider index (1-5) to array index (0-4)
	if time_value_label and time_index >= 0 and time_index < time_labels.size():
		time_value_label.text = time_labels[time_index]

	# Update client display label
	if settings_display_label:
		var video_str: String = "On" if video_walls else "Off"
		var time_display: String = time_labels[time_index] if time_index >= 0 and time_index < time_labels.size() else "5 Minutes"
		settings_display_label.text = "Settings: %s map, %s, Video Walls: %s" % [size_display, time_display, video_str]

func _time_to_slider_index(time: float) -> int:
	"""Convert time in seconds to slider index (1-5)"""
	var time_values: Array[float] = [60.0, 180.0, 300.0, 600.0, 900.0]
	for i in range(time_values.size()):
		if abs(time - time_values[i]) < 1.0:
			return i + 1
	return 3  # Default to 5 minutes
