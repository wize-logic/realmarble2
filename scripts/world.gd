extends Node

# UI References
@onready var main_menu: Control = $Menu/MainMenu if has_node("Menu/MainMenu") else null
@onready var options_menu: PanelContainer = $Menu/Options if has_node("Menu/Options") else null
@onready var pause_menu: PanelContainer = $Menu/PauseMenu if has_node("Menu/PauseMenu") else null
@onready var address_entry: LineEdit = get_node_or_null("%AddressEntry")
@onready var menu_music: AudioStreamPlayer = get_node_or_null("%MenuMusic")
@onready var gameplay_music: Node = get_node_or_null("GameplayMusic")
@onready var music_notification: Control = get_node_or_null("MusicNotification/NotificationUI")
@onready var game_hud: Control = get_node_or_null("GameHUD/HUD")

# Multiplayer UI
var lobby_ui: Control = null
const LobbyUI = preload("res://lobby_ui.tscn")

# Profile and Friends UI
var profile_panel: PanelContainer = null
var friends_panel: PanelContainer = null
const ProfilePanelScript = preload("res://scripts/ui/profile_panel.gd")
const FriendsPanelScript = preload("res://scripts/ui/friends_panel.gd")

# Countdown UI (created dynamically)
var countdown_label: Label = null
var countdown_sound: AudioStreamPlayer = null

# Marble Preview (for main menu)
var marble_preview: Node3D = null
var preview_camera: Camera3D = null
var preview_light: DirectionalLight3D = null

# Game Settings
var sensitivity: float = 0.005
var controller_sensitivity: float = 0.010

# Multiplayer
const Player = preload("res://marble_player.tscn")  # Updated to marble player
const PORT = 9999
var enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()

# Menu State
var paused: bool = false
var options: bool = false
var controller: bool = false

# Deathmatch Game State
var game_time_remaining: float = 300.0  # 5 minutes in seconds
var game_active: bool = false
var player_scores: Dictionary = {}  # player_id: score
var player_deaths: Dictionary = {}  # player_id: death_count
var countdown_active: bool = false
var countdown_time: float = 0.0

# Bot system
var bot_counter: int = 0
const BotAI = preload("res://scripts/bot_ai.gd")

# Debug menu
const DebugMenu = preload("res://debug_menu.tscn")

# Scoreboard
const Scoreboard = preload("res://scoreboard.tscn")

# Procedural level generation
const LevelGenerator = preload("res://scripts/level_generator.gd")
const SkyboxGenerator = preload("res://scripts/skybox_generator.gd")
var level_generator: Node3D = null
var skybox_generator: Node3D = null

func _ready() -> void:
	# Generate procedural level
	generate_procedural_level()

	# Initialize debug menu
	var debug_menu_instance: Control = DebugMenu.instantiate()
	add_child(debug_menu_instance)

	# Initialize scoreboard
	var scoreboard_instance: Control = Scoreboard.instantiate()
	add_child(scoreboard_instance)

	# Initialize lobby UI
	lobby_ui = LobbyUI.instantiate()
	add_child(lobby_ui)
	lobby_ui.visible = false  # Hidden by default

	# Initialize profile panel
	_create_profile_panel()

	# Initialize friends panel
	_create_friends_panel()

	# Initialize marble preview (replaces dolly camera)
	_create_marble_preview()

	# Connect multiplayer manager signals
	if MultiplayerManager:
		MultiplayerManager.player_connected.connect(_on_multiplayer_player_connected)
		MultiplayerManager.player_disconnected.connect(_on_multiplayer_player_disconnected)

	# Create countdown UI
	create_countdown_ui()

	# Connect music notification
	if gameplay_music and music_notification and gameplay_music.has_signal("track_started"):
		gameplay_music.track_started.connect(_on_track_started)

	# Auto-load music from default directory with fallback
	_auto_load_music()

	# Hide HUD initially (only shown during active gameplay)
	if game_hud:
		game_hud.visible = false

func _unhandled_input(event: InputEvent) -> void:
	# Pause menu toggle - only allow pausing during active gameplay
	if main_menu and options_menu:
		var lobby_visible: bool = lobby_ui and lobby_ui.visible
		if Input.is_action_pressed("pause") and !main_menu.visible and !options_menu.visible and !lobby_visible and game_active:
			paused = !paused

	# Controller detection
	if event is InputEventJoypadMotion:
		controller = true
	elif event is InputEventMouseMotion:
		controller = false

func _process(delta: float) -> void:
	# Handle pause menu
	if paused and pause_menu:
		if has_node("Menu/Blur"):
			$Menu/Blur.show()
		pause_menu.show()
		if !controller:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

		# Pause gameplay music
		if gameplay_music and gameplay_music.has_method("pause_playlist"):
			gameplay_music.pause_playlist()

	# Handle countdown
	if countdown_active:
		countdown_time -= delta
		update_countdown_display()

		if countdown_time <= 0:
			# Countdown finished - start the game
			print("Countdown finished! Starting match...")
			countdown_active = false
			game_active = true
			if countdown_label:
				countdown_label.visible = false
			# Show HUD when game starts
			if game_hud:
				game_hud.visible = true
			print("GO! Match started! game_active is now: ", game_active)

			# Notify CrazyGames SDK that gameplay has started
			if CrazyGamesSDK:
				CrazyGamesSDK.gameplay_start()

	# Handle deathmatch timer
	if game_active:
		game_time_remaining -= delta
		# Log every 30 seconds
		if int(game_time_remaining) % 30 == 0 and game_time_remaining > 0 and game_time_remaining < 300:
			print("Match time remaining: %.1f seconds (%.1f minutes)" % [game_time_remaining, game_time_remaining / 60.0])
		if game_time_remaining <= 0:
			print("Time's up! Ending deathmatch...")
			end_deathmatch()

# ============================================================================
# MENU FUNCTIONS
# ============================================================================

func _on_resume_pressed() -> void:
	if !options:
		if has_node("Menu/Blur"):
			$Menu/Blur.hide()
	if pause_menu:
		pause_menu.hide()
	if !controller:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	paused = false

	# Resume gameplay music if paused
	if gameplay_music and gameplay_music.has_method("resume_playlist"):
		gameplay_music.resume_playlist()

func _on_options_pressed() -> void:
	_on_resume_pressed()
	if options_menu:
		options_menu.show()
	if has_node("Menu/Blur"):
		$Menu/Blur.show()
	var fullscreen_button: Button = get_node_or_null("%Fullscreen")
	if fullscreen_button:
		fullscreen_button.grab_focus()
	if !controller:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	options = true

func _on_back_pressed() -> void:
	if options:
		if has_node("Menu/Blur"):
			$Menu/Blur.hide()
		if !controller:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		options = false

func _on_return_to_title_pressed() -> void:
	"""Return to title screen from pause menu"""
	print("Return to title screen pressed")

	# Unpause the game
	paused = false
	if pause_menu:
		pause_menu.hide()

	# Stop gameplay music
	if gameplay_music and gameplay_music.has_method("stop_playlist"):
		gameplay_music.stop_playlist()

	# Hide scoreboard if it's visible
	var scoreboard: Control = get_node_or_null("Scoreboard")
	if scoreboard and scoreboard.has_method("hide_match_end_scoreboard"):
		scoreboard.hide_match_end_scoreboard()

	# Call return_to_main_menu to clean up game state
	return_to_main_menu()

func _on_music_toggle_toggled(toggled_on: bool) -> void:
	if menu_music:
		if !toggled_on:
			menu_music.stop()
		else:
			menu_music.play()

# ============================================================================
# MULTIPLAYER FUNCTIONS
# ============================================================================

func _on_multiplayer_button_pressed() -> void:
	"""Show the multiplayer lobby"""
	show_multiplayer_lobby()

func _on_play_pressed() -> void:
	"""Start practice mode with bots (renamed from practice button)"""
	_on_practice_button_pressed()

func _on_practice_button_pressed() -> void:
	"""Start practice mode with bots - ask for bot count first"""
	print("======================================")
	print("_on_practice_button_pressed() CALLED!")
	print("Current player count: ", get_tree().get_nodes_in_group("players").size())
	print("Current bot_counter: ", bot_counter)
	print("game_active: ", game_active, " | countdown_active: ", countdown_active)
	print("======================================")

	# Prevent starting practice mode if a game is already active or counting down
	if game_active or countdown_active:
		print("WARNING: Cannot start practice mode - game already active or counting down!")
		print("======================================")
		return

	# Prevent starting if players already exist (game already started)
	var existing_players: int = get_tree().get_nodes_in_group("players").size()
	if existing_players > 0:
		print("WARNING: Cannot start practice mode - %d players already in game!" % existing_players)
		print("======================================")
		return

	# Ask user how many bots they want
	var bot_count_choice = await ask_bot_count()
	if bot_count_choice < 0:
		# User cancelled or error
		print("Practice mode cancelled")
		return

	# Now start practice mode with the chosen bot count
	start_practice_mode(bot_count_choice)

func ask_bot_count() -> int:
	"""Ask the user how many bots they want to play against"""
	# Create a beautiful dialog matching main menu theme
	var dialog = AcceptDialog.new()
	dialog.title = "Practice Mode"
	dialog.dialog_hide_on_ok = false
	dialog.exclusive = true
	dialog.unresizable = false
	dialog.size = Vector2(600, 450)  # Slightly larger for better spacing

	# Create custom panel style matching main menu
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0.85)  # Dark semi-transparent
	panel_style.set_corner_radius_all(12)  # Rounded corners
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.3, 0.7, 1, 0.6)  # Blue border

	# Create main panel
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	dialog.add_child(panel)

	# Create main container with generous margins
	var margin_container = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_left", 50)
	margin_container.add_theme_constant_override("margin_right", 50)
	margin_container.add_theme_constant_override("margin_top", 40)
	margin_container.add_theme_constant_override("margin_bottom", 40)
	panel.add_child(margin_container)

	# Create VBoxContainer for organized layout
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 25)
	margin_container.add_child(vbox)

	# Add title label with larger font
	var title_label = Label.new()
	title_label.text = "SELECT NUMBER OF BOTS"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1, 1))  # Blue color
	vbox.add_child(title_label)

	# Add descriptive label
	var desc_label = Label.new()
	desc_label.text = "How many bots do you want to practice against?"
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_font_size_override("font_size", 16)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)

	# Add separator for visual separation
	var separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 2)
	vbox.add_child(separator)

	# Bot count options
	var bot_counts = [1, 3, 5, 7, 10, 15]
	var selected_count = 3  # Default

	# Create centered grid container for buttons (3 columns for better layout)
	var grid_container = CenterContainer.new()
	vbox.add_child(grid_container)

	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	grid_container.add_child(grid)

	# Create button style matching main menu
	var button_style = StyleBoxFlat.new()
	button_style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
	button_style.set_corner_radius_all(8)
	button_style.border_width_left = 2
	button_style.border_width_top = 2
	button_style.border_width_right = 2
	button_style.border_width_bottom = 2
	button_style.border_color = Color(0.3, 0.7, 1, 0.4)

	var button_hover_style = StyleBoxFlat.new()
	button_hover_style.bg_color = Color(0.3, 0.7, 1, 0.3)
	button_hover_style.set_corner_radius_all(8)
	button_hover_style.border_width_left = 2
	button_hover_style.border_width_top = 2
	button_hover_style.border_width_right = 2
	button_hover_style.border_width_bottom = 2
	button_hover_style.border_color = Color(0.3, 0.7, 1, 0.8)

	# Create buttons for each option with better styling
	for count in bot_counts:
		var button = Button.new()
		button.text = "%d Bot%s" % [count, "s" if count > 1 else ""]
		button.custom_minimum_size = Vector2(140, 60)
		button.add_theme_font_size_override("font_size", 20)
		button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
		button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		button.add_theme_stylebox_override("normal", button_style)
		button.add_theme_stylebox_override("hover", button_hover_style)
		button.add_theme_stylebox_override("pressed", button_hover_style)

		# FIX: Capture the value properly to avoid closure issue
		var count_value = count  # Capture the current count value
		button.pressed.connect(func():
			selected_count = count_value  # Use captured value
			dialog.hide()
		)
		grid.add_child(button)

	# Add bottom spacing
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(spacer)

	# Add dialog to scene
	add_child(dialog)
	dialog.popup_centered()

	# Wait for dialog to close
	await dialog.visibility_changed

	# Clean up
	dialog.queue_free()

	return selected_count

func start_practice_mode(bot_count: int) -> void:
	"""Start practice mode with specified number of bots"""
	print("Starting practice mode with %d bots" % bot_count)

	if main_menu:
		main_menu.hide()
	if has_node("Menu/Blur"):
		$Menu/Blur.hide()
	# Hide marble preview when starting gameplay
	if has_node("MarblePreview"):
		get_node("MarblePreview").visible = false
	if menu_music:
		menu_music.stop()

	# Capture mouse for gameplay
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Start gameplay music
	if gameplay_music and gameplay_music.has_method("start_playlist"):
		gameplay_music.start_playlist()

	# Add local player without multiplayer
	var local_player: Node = Player.instantiate()
	local_player.name = "1"
	add_child(local_player)
	local_player.add_to_group("players")
	player_scores[1] = 0
	player_deaths[1] = 0
	print("Local player added. Total players now: ", get_tree().get_nodes_in_group("players").size())

	# Spawn requested number of bots for practice
	print("Spawning %d bots for practice mode..." % bot_count)
	for i in range(bot_count):
		await get_tree().create_timer(0.5).timeout
		spawn_bot()
	print("Bot spawning complete. Total players now: ", get_tree().get_nodes_in_group("players").size())

	# Start the deathmatch
	start_deathmatch()

func _on_settings_pressed() -> void:
	"""Open settings menu from main menu"""
	_on_options_button_toggled(true)

func _on_quit_pressed() -> void:
	"""Quit the game"""
	get_tree().quit()

func _on_item_shop_pressed() -> void:
	"""Item Shop placeholder"""
	print("Item Shop - Not implemented yet")

func _on_garage_pressed() -> void:
	"""Garage placeholder"""
	print("Garage - Not implemented yet")

func _on_profile_pressed() -> void:
	"""Show profile panel"""
	if profile_panel:
		profile_panel.show_panel()
	if main_menu:
		main_menu.hide()

func _on_friends_pressed() -> void:
	"""Show friends panel"""
	if friends_panel:
		friends_panel.show_panel()
	if main_menu:
		main_menu.hide()

func _on_host_button_pressed() -> void:
	if main_menu:
		main_menu.hide()
	if has_node("Menu/Blur"):
		$Menu/Blur.hide()
	# Hide marble preview when starting gameplay
	if has_node("MarblePreview"):
		get_node("MarblePreview").visible = false
	if menu_music:
		menu_music.stop()

	# Capture mouse for gameplay
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Start gameplay music
	if gameplay_music and gameplay_music.has_method("start_playlist"):
		gameplay_music.start_playlist()

	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)

	if options_menu and options_menu.visible:
		options_menu.hide()

	add_player(multiplayer.get_unique_id())

	# Start the deathmatch
	start_deathmatch()

	upnp_setup()

func _on_join_button_pressed() -> void:
	if main_menu:
		main_menu.hide()
	if has_node("Menu/Blur"):
		$Menu/Blur.hide()
	# Hide marble preview when starting gameplay
	if has_node("MarblePreview"):
		get_node("MarblePreview").visible = false
	if menu_music:
		menu_music.stop()

	# Capture mouse for gameplay
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Start gameplay music
	if gameplay_music and gameplay_music.has_method("start_playlist"):
		gameplay_music.start_playlist()

	enet_peer.create_client(address_entry.text if address_entry else "127.0.0.1", PORT)
	if options_menu and options_menu.visible:
		options_menu.hide()
	multiplayer.multiplayer_peer = enet_peer

func _on_options_button_toggled(toggled_on: bool) -> void:
	if options_menu:
		if toggled_on:
			options_menu.show()
		else:
			options_menu.hide()

func add_player(peer_id: int) -> void:
	var player: Node = Player.instantiate()
	player.name = str(peer_id)
	add_child(player)

	# Add to players group for AI targeting
	player.add_to_group("players")

	# Initialize player score and deaths
	player_scores[peer_id] = 0
	player_deaths[peer_id] = 0

func remove_player(peer_id: int) -> void:
	var player: Node = get_node_or_null(str(peer_id))
	if player:
		player.queue_free()

	# Remove from scores
	if player_scores.has(peer_id):
		player_scores.erase(peer_id)

# New multiplayer manager handlers
func _on_multiplayer_player_connected(peer_id: int, player_info: Dictionary) -> void:
	"""Called when a player connects via multiplayer manager"""
	print("Multiplayer player connected: ", peer_id, " - ", player_info)
	add_player(peer_id)

func _on_multiplayer_player_disconnected(peer_id: int) -> void:
	"""Called when a player disconnects via multiplayer manager"""
	print("Multiplayer player disconnected: ", peer_id)
	remove_player(peer_id)

func show_multiplayer_lobby() -> void:
	"""Show the multiplayer lobby UI"""
	if lobby_ui:
		lobby_ui.visible = true
		# Hide main menu
		if main_menu:
			main_menu.visible = false
		# Hide blur
		if has_node("Menu/Blur"):
			$Menu/Blur.hide()
		# Hide marble preview when showing lobby
		if has_node("MarblePreview"):
			get_node("MarblePreview").visible = false
		# Show mouse cursor
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func hide_multiplayer_lobby() -> void:
	"""Hide the multiplayer lobby UI"""
	if lobby_ui:
		lobby_ui.visible = false

func show_main_menu() -> void:
	"""Show the main menu"""
	if main_menu:
		main_menu.visible = true
	# Show marble preview and make camera current
	if has_node("MarblePreview"):
		get_node("MarblePreview").visible = true
	if preview_camera:
		preview_camera.make_current()

func upnp_setup() -> void:
	var upnp: UPNP = UPNP.new()

	upnp.discover()
	upnp.add_port_mapping(PORT)

	var ip: String = upnp.query_external_address()
	if ip == "":
		print("Failed to establish upnp connection!")
	else:
		print("Success! Join Address: %s" % upnp.query_external_address())

# ============================================================================
# DEATHMATCH GAME LOGIC
# ============================================================================

func start_deathmatch() -> void:
	"""Start a 5-minute deathmatch with countdown"""
	print("======================================")
	print("start_deathmatch() CALLED!")
	print("Stack trace:")
	print_stack()
	print("Current game_active: ", game_active)
	print("Current countdown_active: ", countdown_active)
	print("======================================")

	# Prevent starting a new match if one is already active or counting down
	if game_active or countdown_active:
		print("WARNING: Match already active or counting down! Ignoring start_deathmatch() call.")
		print("======================================")
		return

	game_active = false  # Don't start until countdown finishes
	game_time_remaining = 300.0
	player_scores.clear()
	player_deaths.clear()

	# Notify CrazyGames SDK that gameplay is about to start
	if CrazyGamesSDK:
		CrazyGamesSDK.gameplay_stop()  # Ensure clean state

	# Start countdown
	countdown_active = true
	countdown_time = 3.0  # 3 seconds: "READY" (1s), "SET" (1s), "GO!" (1s)
	if countdown_label:
		countdown_label.visible = true
	print("Starting countdown...")

func end_deathmatch() -> void:
	"""End the deathmatch and show results"""
	print("======================================")
	print("end_deathmatch() CALLED!")
	print("Game time was: %.2f seconds" % game_time_remaining)
	print("======================================")

	# Prevent ending if already ended
	if not game_active and not countdown_active:
		print("WARNING: Match already ended! Ignoring end_deathmatch() call.")
		print("======================================")
		return

	game_active = false
	countdown_active = false  # Make sure countdown is also stopped
	# Hide HUD when game ends
	if game_hud:
		game_hud.visible = false
	print("Deathmatch ended!")

	# Notify CrazyGames SDK that gameplay has stopped
	if CrazyGamesSDK:
		CrazyGamesSDK.gameplay_stop()

	# Stop gameplay music
	if gameplay_music and gameplay_music.has_method("stop_playlist"):
		gameplay_music.stop_playlist()

	# Find winner
	var winner_id: int = -1
	var highest_score: int = -1

	for player_id: int in player_scores:
		if player_scores[player_id] > highest_score:
			highest_score = player_scores[player_id]
			winner_id = player_id

	if winner_id != -1:
		print("Winner: Player %d with %d kills!" % [winner_id, highest_score])
	else:
		print("No winner - no kills recorded!")

	# Show scoreboard for 10 seconds
	var scoreboard: Control = get_node_or_null("Scoreboard")
	if scoreboard and scoreboard.has_method("show_match_end_scoreboard"):
		scoreboard.show_match_end_scoreboard()

	# Release mouse so scoreboard is visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Wait 10 seconds
	await get_tree().create_timer(10.0).timeout

	# Return to main menu
	return_to_main_menu()

func return_to_main_menu() -> void:
	"""Return to main menu after match ends"""
	print("Returning to main menu...")

	# Hide scoreboard
	var scoreboard: Control = get_node_or_null("Scoreboard")
	if scoreboard and scoreboard.has_method("hide_match_end_scoreboard"):
		scoreboard.hide_match_end_scoreboard()

	# Remove all players
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	for player in players:
		player.queue_free()

	# Clear scores and deaths
	player_scores.clear()
	player_deaths.clear()

	# Reset game state
	game_active = false
	countdown_active = false
	game_time_remaining = 300.0

	# Reset bot counter
	bot_counter = 0

	# Hide countdown label and HUD if visible
	if countdown_label:
		countdown_label.visible = false
	if game_hud:
		game_hud.visible = false

	# Show main menu
	if main_menu:
		main_menu.show()

	# Show marble preview and make camera current
	if has_node("MarblePreview"):
		get_node("MarblePreview").visible = true
	if preview_camera:
		preview_camera.make_current()

	# Start menu music
	if menu_music:
		menu_music.play()

	# Make sure mouse is visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	print("Returned to main menu")

func add_score(player_id: int, points: int = 1) -> void:
	"""Add points to a player's score"""
	if not player_scores.has(player_id):
		player_scores[player_id] = 0
	player_scores[player_id] += points
	print("Player %d scored! Total: %d" % [player_id, player_scores[player_id]])

func add_death(player_id: int) -> void:
	"""Add a death to a player's death count"""
	if not player_deaths.has(player_id):
		player_deaths[player_id] = 0
	player_deaths[player_id] += 1
	print("Player %d died! Total deaths: %d" % [player_id, player_deaths[player_id]])

func get_score(player_id: int) -> int:
	"""Get a player's current score"""
	return player_scores.get(player_id, 0)

func get_deaths(player_id: int) -> int:
	"""Get a player's death count"""
	return player_deaths.get(player_id, 0)

func get_kd_ratio(player_id: int) -> float:
	"""Get a player's K/D ratio"""
	var kills: int = get_score(player_id)
	var deaths: int = get_deaths(player_id)
	if deaths == 0:
		return float(kills)  # If no deaths, return kills as ratio
	return float(kills) / float(deaths)

func get_time_remaining_formatted() -> String:
	"""Get formatted time string (MM:SS)"""
	var minutes: int = int(game_time_remaining) / 60
	var seconds: int = int(game_time_remaining) % 60
	return "%02d:%02d" % [minutes, seconds]

# ============================================================================
# MUSIC DIRECTORY FUNCTIONS
# ============================================================================

func _auto_load_music() -> void:
	"""Auto-load music from default directory with fallback to res://music"""
	if not gameplay_music:
		return

	var music_dir: String = Global.music_directory
	var songs_loaded: int = _load_music_from_directory(music_dir)

	# Fallback to res://music if no songs were found (and we're not already using it)
	if songs_loaded == 0 and music_dir != "res://music":
		print("No music found in %s, falling back to res://music" % music_dir)
		songs_loaded = _load_music_from_directory("res://music")

	if songs_loaded > 0:
		print("Auto-loaded %d songs from music directory" % songs_loaded)
	else:
		print("No music files found in either %s or res://music" % music_dir)

func _load_music_from_directory(dir: String) -> int:
	"""Load all music files from a directory and return count of songs loaded"""
	print("Attempting to open directory: %s" % dir)
	var dir_access: DirAccess = DirAccess.open(dir)
	if not dir_access:
		print("Failed to open directory: %s" % dir)
		return 0

	print("Successfully opened directory: %s" % dir)
	dir_access.list_dir_begin()
	var file_name: String = dir_access.get_next()
	var songs_loaded: int = 0
	var files_found: int = 0

	while file_name != "":
		if not dir_access.current_is_dir():
			files_found += 1
			var ext: String = file_name.get_extension().to_lower()
			print("Found file: %s (extension: %s)" % [file_name, ext])

			# Check if it's a supported audio format
			if ext in ["mp3", "ogg", "wav"]:
				var file_path: String = dir.path_join(file_name)
				print("Attempting to load audio file: %s" % file_path)
				var audio_stream: AudioStream = _load_audio_file(file_path, ext)

				if audio_stream and gameplay_music.has_method("add_song"):
					gameplay_music.add_song(audio_stream, file_path)
					songs_loaded += 1
					print("Successfully loaded: %s" % file_name)
				else:
					print("Failed to load or add: %s" % file_name)

		file_name = dir_access.get_next()

	dir_access.list_dir_end()
	print("Directory scan complete. Files found: %d, Songs loaded: %d" % [files_found, songs_loaded])
	return songs_loaded

func _on_music_directory_button_pressed() -> void:
	"""Open file dialog to select music directory"""
	var dialog: FileDialog = get_node_or_null("Menu/MusicDirectoryDialog")
	if dialog:
		dialog.popup_centered()

func _on_music_directory_selected(dir: String) -> void:
	"""Load all music files from selected directory"""
	print("Loading music from directory: %s" % dir)

	if not gameplay_music:
		print("Error: GameplayMusic node not found")
		return

	# Clear existing playlist
	if gameplay_music.has_method("clear_playlist"):
		gameplay_music.clear_playlist()

	# Load music from selected directory
	var songs_loaded: int = _load_music_from_directory(dir)
	print("Music directory loaded: %d songs added to playlist" % songs_loaded)

	# Save this as the new music directory
	Global.music_directory = dir
	Global.save_settings()

func _load_audio_file(file_path: String, extension: String) -> AudioStream:
	"""Load an audio file and return an AudioStream"""
	var audio_stream: AudioStream = null

	# For res:// paths, try ResourceLoader first (for imported files)
	if file_path.begins_with("res://"):
		audio_stream = ResourceLoader.load(file_path)
		if audio_stream:
			print("Loaded via ResourceLoader: %s" % file_path)
			return audio_stream
		else:
			print("ResourceLoader failed for %s, trying FileAccess fallback..." % file_path)
			# Fall through to FileAccess method below

	# For external files (or res:// files that aren't imported), use FileAccess
	match extension:
		"mp3":
			var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
			if file:
				var mp3_stream: AudioStreamMP3 = AudioStreamMP3.new()
				mp3_stream.data = file.get_buffer(file.get_length())
				file.close()
				audio_stream = mp3_stream

		"ogg":
			var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
			if file:
				var ogg_stream: AudioStreamOggVorbis = AudioStreamOggVorbis.new()
				ogg_stream.packet_sequence = OggPacketSequence.new()
				# Load from file - Godot 4 method
				var packet_data: PackedByteArray = file.get_buffer(file.get_length())
				file.close()

				# Try to load the OGG file
				var temp_file_path: String = "user://temp_music.ogg"
				var temp_file: FileAccess = FileAccess.open(temp_file_path, FileAccess.WRITE)
				if temp_file:
					temp_file.store_buffer(packet_data)
					temp_file.close()

					ogg_stream = AudioStreamOggVorbis.load_from_file(temp_file_path)
					audio_stream = ogg_stream

		"wav":
			# WAV files can be loaded as resources
			audio_stream = ResourceLoader.load(file_path)

	if not audio_stream:
		print("Warning: Could not load audio file: %s" % file_path)

	return audio_stream

# ============================================================================
# BOT SYSTEM
# ============================================================================

func spawn_bot() -> void:
	"""Spawn an AI-controlled bot player"""
	print("--- spawn_bot() called ---")
	print("Bot counter before: ", bot_counter)
	print("Current players in game: ", get_tree().get_nodes_in_group("players").size())

	bot_counter += 1
	var bot_id: int = 9000 + bot_counter  # Bot IDs start at 9000

	var bot: Node = Player.instantiate()
	bot.name = str(bot_id)
	add_child(bot)

	# Update bot spawns from level generator
	if level_generator and level_generator.has_method("get_spawn_points"):
		var spawn_points: PackedVector3Array = level_generator.get_spawn_points()
		if spawn_points.size() > 0:
			bot.spawns = spawn_points
			# Spawn at appropriate position
			var spawn_index: int = bot_id % spawn_points.size()
			bot.global_position = spawn_points[spawn_index]
			print("Bot %d spawned at position %d: %s" % [bot_id, spawn_index, bot.global_position])

	# Add AI controller to bot
	var ai: Node = BotAI.new()
	ai.name = "BotAI"
	bot.add_child(ai)
	print("BotAI added to bot %d" % bot_id)

	# Add bot to players group
	bot.add_to_group("players")

	# Initialize bot score and deaths
	player_scores[bot_id] = 0
	player_deaths[bot_id] = 0

	print("Spawned bot with ID: %d | Total players now: %d" % [bot_id, get_tree().get_nodes_in_group("players").size()])
	print("--- spawn_bot() complete ---")

# ============================================================================
# COUNTDOWN SYSTEM
# ============================================================================

func _apply_button_style(button: Button, font_size: int = 20) -> void:
	"""Apply style guide button styling to a button"""
	# Normal state
	var button_normal = StyleBoxFlat.new()
	button_normal.bg_color = Color(0.15, 0.15, 0.2, 0.8)
	button_normal.set_corner_radius_all(8)
	button_normal.border_color = Color(0.3, 0.7, 1, 0.4)
	button_normal.set_border_width_all(2)

	# Hover state
	var button_hover = StyleBoxFlat.new()
	button_hover.bg_color = Color(0.2, 0.3, 0.4, 0.9)
	button_hover.set_corner_radius_all(8)
	button_hover.border_color = Color(0.3, 0.7, 1, 0.8)
	button_hover.set_border_width_all(2)

	# Pressed state
	var button_pressed = StyleBoxFlat.new()
	button_pressed.bg_color = Color(0.3, 0.5, 0.7, 1)
	button_pressed.set_corner_radius_all(8)
	button_pressed.border_color = Color(0.4, 0.8, 1, 1)
	button_pressed.set_border_width_all(2)

	# Apply styles
	button.add_theme_stylebox_override("normal", button_normal)
	button.add_theme_stylebox_override("hover", button_hover)
	button.add_theme_stylebox_override("pressed", button_pressed)
	button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	button.add_theme_font_size_override("font_size", font_size)

func _create_profile_panel() -> void:
	"""Create the profile panel UI following style guide"""
	# Create the panel
	profile_panel = PanelContainer.new()
	profile_panel.name = "ProfilePanel"
	profile_panel.set_script(ProfilePanelScript)

	# Center the panel (600x700px as per style guide)
	profile_panel.set_anchors_preset(Control.PRESET_CENTER)
	profile_panel.anchor_left = 0.5
	profile_panel.anchor_right = 0.5
	profile_panel.anchor_top = 0.5
	profile_panel.anchor_bottom = 0.5
	profile_panel.offset_left = -300
	profile_panel.offset_right = 300
	profile_panel.offset_top = -350
	profile_panel.offset_bottom = 350
	profile_panel.custom_minimum_size = Vector2(600, 700)

	# Apply panel style from style guide
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0.85)
	panel_style.set_corner_radius_all(12)
	panel_style.border_color = Color(0.3, 0.7, 1, 0.6)
	panel_style.set_border_width_all(3)
	profile_panel.add_theme_stylebox_override("panel", panel_style)

	# 25px margins as per style guide
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 25)
	margin.add_theme_constant_override("margin_right", 25)
	margin.add_theme_constant_override("margin_top", 25)
	margin.add_theme_constant_override("margin_bottom", 25)
	profile_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)

	# Header with title
	var header = HBoxContainer.new()
	header.name = "Header"
	vbox.add_child(header)

	var username_label = Label.new()
	username_label.name = "Username"
	username_label.text = "PROFILE"
	username_label.add_theme_font_size_override("font_size", 32)
	username_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1, 1))
	username_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(username_label)

	# Close button with style
	var close_btn = Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(50, 50)
	_apply_button_style(close_btn, 20)
	close_btn.pressed.connect(_on_profile_panel_close_pressed)
	header.add_child(close_btn)

	# Separator
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Auth section
	var auth_hbox = HBoxContainer.new()
	auth_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(auth_hbox)

	var auth_status = Label.new()
	auth_status.name = "AuthStatus"
	auth_status.text = "GUEST"
	auth_status.add_theme_font_size_override("font_size", 16)
	auth_status.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	auth_hbox.add_child(auth_status)

	var spacer1 = Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auth_hbox.add_child(spacer1)

	var login_btn = Button.new()
	login_btn.name = "LoginButton"
	login_btn.text = "LOGIN"
	login_btn.custom_minimum_size = Vector2(120, 40)
	_apply_button_style(login_btn, 18)
	auth_hbox.add_child(login_btn)

	var link_btn = Button.new()
	link_btn.name = "LinkAccountButton"
	link_btn.text = "LINK ACCOUNT"
	link_btn.custom_minimum_size = Vector2(150, 40)
	link_btn.visible = false
	_apply_button_style(link_btn, 18)
	auth_hbox.add_child(link_btn)

	# Placeholder for profile picture
	var pic = TextureRect.new()
	pic.name = "ProfilePicture"
	pic.custom_minimum_size = Vector2(100, 100)
	pic.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	vbox.add_child(pic)

	# Stats section header
	var stats_header = Label.new()
	stats_header.text = "STATISTICS"
	stats_header.add_theme_font_size_override("font_size", 24)
	stats_header.add_theme_color_override("font_color", Color(0.3, 0.7, 1, 1))
	stats_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats_header)

	# Separator
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	# Stats grid
	var stats_grid = GridContainer.new()
	stats_grid.name = "Stats"
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 20)
	stats_grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(stats_grid)

	# Add stat labels with proper styling
	var stat_names = ["KILLS", "DEATHS", "K/D RATIO", "MATCHES", "WINS", "WIN RATE"]
	var stat_keys = ["Kills", "Deaths", "KD", "Matches", "Wins", "WinRate"]

	for i in stat_names.size():
		var label = Label.new()
		label.text = stat_names[i] + ":"
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(0.3, 0.7, 1, 1))
		stats_grid.add_child(label)

		var value = Label.new()
		value.name = stat_keys[i] + "Value"
		value.text = "0"
		value.add_theme_font_size_override("font_size", 18)
		value.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		stats_grid.add_child(value)

	# Set mouse filter to stop clicks from going through
	profile_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Add panel to Menu CanvasLayer (same as options_menu and pause_menu)
	if has_node("Menu"):
		get_node("Menu").add_child(profile_panel)
	else:
		add_child(profile_panel)

	# Start hidden
	profile_panel.visible = false

	print("Profile panel created")

func _create_friends_panel() -> void:
	"""Create the friends panel UI following style guide"""
	# Create the panel
	friends_panel = PanelContainer.new()
	friends_panel.name = "FriendsPanel"
	friends_panel.set_script(FriendsPanelScript)

	# Center the panel (600x700px as per style guide)
	friends_panel.set_anchors_preset(Control.PRESET_CENTER)
	friends_panel.anchor_left = 0.5
	friends_panel.anchor_right = 0.5
	friends_panel.anchor_top = 0.5
	friends_panel.anchor_bottom = 0.5
	friends_panel.offset_left = -300
	friends_panel.offset_right = 300
	friends_panel.offset_top = -350
	friends_panel.offset_bottom = 350
	friends_panel.custom_minimum_size = Vector2(600, 700)

	# Apply panel style from style guide
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0.85)
	panel_style.set_corner_radius_all(12)
	panel_style.border_color = Color(0.3, 0.7, 1, 0.6)
	panel_style.set_border_width_all(3)
	friends_panel.add_theme_stylebox_override("panel", panel_style)

	# 25px margins as per style guide
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 25)
	margin.add_theme_constant_override("margin_right", 25)
	margin.add_theme_constant_override("margin_top", 25)
	margin.add_theme_constant_override("margin_bottom", 25)
	friends_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)

	# Header
	var header = HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	var title = Label.new()
	title.text = "FRIENDS"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.3, 0.7, 1, 1))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var refresh_btn = Button.new()
	refresh_btn.name = "RefreshButton"
	refresh_btn.text = "REFRESH"
	refresh_btn.custom_minimum_size = Vector2(100, 40)
	_apply_button_style(refresh_btn, 16)
	header.add_child(refresh_btn)

	var close_btn = Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(50, 50)
	_apply_button_style(close_btn, 20)
	close_btn.pressed.connect(_on_friends_panel_close_pressed)
	header.add_child(close_btn)

	# Separator
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Friend count section
	var count_hbox = HBoxContainer.new()
	count_hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(count_hbox)

	var online_count = Label.new()
	online_count.name = "OnlineCount"
	online_count.text = "ONLINE: 0"
	online_count.add_theme_font_size_override("font_size", 16)
	online_count.add_theme_color_override("font_color", Color(0.3, 1, 0.3, 1))
	count_hbox.add_child(online_count)

	var total_count = Label.new()
	total_count.name = "TotalCount"
	total_count.text = "TOTAL: 0"
	total_count.add_theme_font_size_override("font_size", 16)
	total_count.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	count_hbox.add_child(total_count)

	# Separator
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	# No friends message
	var no_friends = Label.new()
	no_friends.name = "NoFriends"
	no_friends.text = "NO FRIENDS YET\nAdd friends on CrazyGames!"
	no_friends.add_theme_font_size_override("font_size", 18)
	no_friends.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	no_friends.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_friends.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	no_friends.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(no_friends)

	# Scroll container for friends list
	var scroll = ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var friends_list = VBoxContainer.new()
	friends_list.name = "FriendsList"
	friends_list.add_theme_constant_override("separation", 8)
	scroll.add_child(friends_list)

	# Set mouse filter to stop clicks from going through
	friends_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Add panel to Menu CanvasLayer (same as options_menu and pause_menu)
	if has_node("Menu"):
		get_node("Menu").add_child(friends_panel)
	else:
		add_child(friends_panel)

	# Start hidden
	friends_panel.visible = false

	print("Friends panel created")

func _create_marble_preview() -> void:
	"""Create marble preview for main menu - matches player's actual marble"""
	# Create a container for the marble preview
	var preview_container = Node3D.new()
	preview_container.name = "MarblePreview"

	# Create the marble mesh matching the player's marble
	marble_preview = MeshInstance3D.new()
	marble_preview.name = "Marble"
	var sphere = SphereMesh.new()
	sphere.radius = 0.5  # Same as player marble
	sphere.height = 1.0  # Same as player marble
	marble_preview.mesh = sphere
	marble_preview.position = Vector3(0, 1.0, 0)  # Raised above ground for proper display

	# Create material matching the player's marble (from player.gd line 426-442)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.9, 1.0)  # Slight blue tint - same as player
	mat.metallic = 0.3
	mat.roughness = 0.4
	mat.uv1_scale = Vector3(2.0, 2.0, 2.0)  # Tile the texture

	# Add procedural noise texture pattern (same as player)
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.5
	var noise_tex = NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.width = 512
	noise_tex.height = 512
	mat.albedo_texture = noise_tex

	marble_preview.material_override = mat

	preview_container.add_child(marble_preview)

	# Add aura light effect (same as player marble - from player.gd line 445-456)
	var aura_light = OmniLight3D.new()
	aura_light.name = "AuraLight"
	aura_light.light_color = Color(0.6, 0.8, 1.0)  # Soft cyan-white
	aura_light.light_energy = 1.5  # Moderate brightness
	aura_light.omni_range = 3.5  # Illumination radius around marble
	aura_light.omni_attenuation = 2.0  # Smooth falloff
	aura_light.shadow_enabled = false  # Disable for performance
	marble_preview.add_child(aura_light)

	# Create preview camera positioned like Rocket League showcase
	preview_camera = Camera3D.new()
	preview_camera.name = "PreviewCamera"
	# Position camera to showcase the marble (slightly above and in front)
	preview_camera.position = Vector3(-2, 1.5, 3)
	# Look at the marble (at its raised position)
	preview_camera.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	preview_container.add_child(preview_camera)
	# Make this the current camera
	preview_camera.make_current()

	# Create directional light for good lighting
	preview_light = DirectionalLight3D.new()
	preview_light.name = "PreviewLight"
	preview_light.light_energy = 1.2
	preview_light.rotation_degrees = Vector3(-45, 45, 0)
	preview_light.shadow_enabled = true
	preview_container.add_child(preview_light)

	# Add an additional fill light for better showcase
	var fill_light = OmniLight3D.new()
	fill_light.name = "FillLight"
	fill_light.light_energy = 0.5
	fill_light.position = Vector3(2, 1, 2)
	preview_container.add_child(fill_light)

	# Add to World root (Menu is a CanvasLayer for UI, can't hold 3D nodes)
	add_child(preview_container)

	print("Marble preview created")

func _on_profile_panel_close_pressed() -> void:
	"""Handle profile panel close button pressed"""
	if profile_panel:
		profile_panel.hide()
	if main_menu:
		main_menu.show()

func _on_friends_panel_close_pressed() -> void:
	"""Handle friends panel close button pressed"""
	if friends_panel:
		friends_panel.hide()
	if main_menu:
		main_menu.show()

func create_countdown_ui() -> void:
	"""Create the countdown UI elements"""
	# Create a control node for the countdown
	var countdown_control: Control = Control.new()
	countdown_control.name = "CountdownUI"
	countdown_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	countdown_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(countdown_control)

	# Create countdown label
	countdown_label = Label.new()
	countdown_label.name = "CountdownLabel"
	countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	countdown_label.anchor_left = 0.5
	countdown_label.anchor_right = 0.5
	countdown_label.anchor_top = 0.4
	countdown_label.anchor_bottom = 0.4
	countdown_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	countdown_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Style the label - huge font
	countdown_label.add_theme_font_size_override("font_size", 120)
	countdown_label.add_theme_color_override("font_color", Color.WHITE)
	countdown_label.add_theme_color_override("font_outline_color", Color.BLACK)
	countdown_label.add_theme_constant_override("outline_size", 10)

	countdown_label.text = "READY"
	countdown_label.visible = false
	countdown_control.add_child(countdown_label)

	# Try to find existing countdown sound node, or create one
	countdown_sound = get_node_or_null("CountdownSound")
	if not countdown_sound:
		countdown_sound = AudioStreamPlayer.new()
		countdown_sound.name = "CountdownSound"
		countdown_sound.volume_db = 0.0
		add_child(countdown_sound)
		print("Created countdown sound player (no audio file loaded)")

	print("Countdown UI created")

func update_countdown_display() -> void:
	"""Update countdown display based on remaining time"""
	if not countdown_label:
		return

	var prev_text: String = countdown_label.text

	# Update text based on time remaining
	if countdown_time > 2.0:
		countdown_label.text = "READY"
		countdown_label.add_theme_color_override("font_color", Color.YELLOW)
	elif countdown_time > 1.0:
		countdown_label.text = "SET"
		countdown_label.add_theme_color_override("font_color", Color.ORANGE)
	else:
		countdown_label.text = "GO!"
		countdown_label.add_theme_color_override("font_color", Color.GREEN)

	# Play sound when text changes
	if prev_text != countdown_label.text and countdown_sound:
		play_countdown_beep()

func play_countdown_beep() -> void:
	"""Play a beep sound for countdown"""
	if not countdown_sound:
		return

	# Only play if a sound file is loaded
	if countdown_sound.stream:
		countdown_sound.pitch_scale = 1.0
		countdown_sound.play()
	# If no sound file is loaded, silently skip
	# To add a countdown sound: load an audio file in the World scene and assign it to CountdownSound node

# ============================================================================
# PROCEDURAL LEVEL GENERATION
# ============================================================================

func generate_procedural_level() -> void:
	"""Generate a procedural level with skybox"""
	print("Generating procedural arena...")

	# Remove old level generator if it exists
	if level_generator:
		level_generator.queue_free()
		level_generator = null

	# Remove old skybox generator if it exists
	if skybox_generator:
		skybox_generator.queue_free()
		skybox_generator = null

	# Wait a frame for cleanup
	await get_tree().process_frame

	# Create level generator
	level_generator = Node3D.new()
	level_generator.name = "LevelGenerator"
	level_generator.set_script(LevelGenerator)
	add_child(level_generator)

	# Wait a frame for level to generate
	await get_tree().process_frame

	# Apply procedural textures
	if level_generator.has_method("apply_procedural_textures"):
		level_generator.apply_procedural_textures()

	# Update player spawn points from generated level
	update_player_spawns()

	# Respawn all orbs and abilities on the new level
	var orb_spawner: Node = get_node_or_null("OrbSpawner")
	if orb_spawner and orb_spawner.has_method("respawn_all"):
		orb_spawner.respawn_all()

	var ability_spawner: Node = get_node_or_null("AbilitySpawner")
	if ability_spawner and ability_spawner.has_method("respawn_all"):
		ability_spawner.respawn_all()

	# Create skybox
	skybox_generator = Node3D.new()
	skybox_generator.name = "SkyboxGenerator"
	skybox_generator.set_script(SkyboxGenerator)
	add_child(skybox_generator)

	print("Procedural level generation complete!")

func update_player_spawns() -> void:
	"""Update all player spawn points from generated level"""
	if not level_generator or not level_generator.has_method("get_spawn_points"):
		return

	var new_spawns: PackedVector3Array = level_generator.get_spawn_points()
	print("Updating player spawns: ", new_spawns.size(), " spawn points")

	# Update all existing players
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	for player in players:
		if "spawns" in player:
			player.spawns = new_spawns
			print("Updated spawns for player: ", player.name)

func _on_track_started(metadata: Dictionary) -> void:
	"""Called when a new music track starts playing"""
	if music_notification and music_notification.has_method("show_notification"):
		music_notification.show_notification(metadata)
