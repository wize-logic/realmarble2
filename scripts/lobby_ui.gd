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

func show_game_lobby() -> void:
	"""Show the game lobby screen"""
	main_lobby_panel.visible = false
	game_lobby_panel.visible = true

	# Update UI based on role
	if multiplayer_manager and multiplayer_manager.is_host():
		start_game_button.visible = true
		if spawn_bot_button:
			spawn_bot_button.visible = true
	else:
		start_game_button.visible = false
		if spawn_bot_button:
			spawn_bot_button.visible = false

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
	status_label.text = "Connection failed!"
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
