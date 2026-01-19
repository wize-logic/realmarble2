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

# Audio context state (HTML5)
var audio_context_resumed: bool = false

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
var last_time_print: int = -1  # Track last printed time interval to prevent spam
var game_active: bool = false
var player_scores: Dictionary = {}  # player_id: score
var player_deaths: Dictionary = {}  # player_id: death_count
var countdown_active: bool = false
var countdown_time: float = 0.0

# Mid-round expansion system
var expansion_triggered: bool = false
var expansion_trigger_time: float = 150.0  # Trigger at 2.5 minutes (150 seconds remaining)
# NOTE: Expansion notification moved to game HUD (game_hud.gd)

# Bot system
var bot_counter: int = 0
var pending_bot_count: int = 0  # Bots to spawn when game becomes active
const BotAI = preload("res://scripts/bot_ai.gd")

# Bot count selection dialog state (instance variables for proper closure sharing)
var bot_count_dialog_closed: bool = false
var bot_count_selected: int = 3

# Level type selection dialog state
var level_type_dialog_closed: bool = false
var level_type_selected: String = "A"

# Debug menu
const DebugMenu = preload("res://debug_menu.tscn")

# Scoreboard
const Scoreboard = preload("res://scoreboard.tscn")

# Procedural level generation
const LevelGenerator = preload("res://scripts/level_generator.gd")
const LevelGeneratorQ3 = preload("res://scripts/level_generator_q3.gd")
const SkyboxGenerator = preload("res://scripts/skybox_generator.gd")
var level_generator: Node3D = null
var skybox_generator: Node3D = null

# GAME STATE: Current arena type (accessible from other scripts)
# "A" = Type A (Original: floating platforms, grind rails, Sonic-style)
# "B" = Type B (Quake 3 Arena: rooms, corridors, jump pads, teleporters)
var current_level_type: String = "A"

func _ready() -> void:
	# Generate procedural level (default to Type A)
	generate_procedural_level("A")

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
	# HTML5: Resume AudioContext on first user interaction (browser policy)
	if not audio_context_resumed and OS.has_feature("web"):
		if event is InputEventMouseButton or event is InputEventKey or event is InputEventJoypadButton:
			_resume_audio_context()
			audio_context_resumed = true

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
				# CRITICAL FIX: Reset HUD to find new player for this match
				if game_hud.has_method("reset_hud"):
					game_hud.reset_hud()
			print("GO! Match started! game_active is now: ", game_active)

			# Spawn pending bots now that match is active
			if pending_bot_count > 0:
				print("Spawning %d pending bots..." % pending_bot_count)
				spawn_pending_bots()
				pending_bot_count = 0

			# Spawn abilities and orbs now that match is active
			spawn_abilities_and_orbs()

			# Notify CrazyGames SDK that gameplay has started
			if CrazyGamesSDK:
				CrazyGamesSDK.gameplay_start()

	# Handle deathmatch timer
	if game_active:
		game_time_remaining -= delta
		# Log every 30 seconds (but only once per interval)
		var current_interval: int = int(game_time_remaining) / 30
		if current_interval != last_time_print and int(game_time_remaining) % 30 == 0 and game_time_remaining > 0 and game_time_remaining < 300:
			print("Match time remaining: %.1f seconds (%.1f minutes)" % [game_time_remaining, game_time_remaining / 60.0])
			last_time_print = current_interval

		# Mid-round expansion disabled - use debug menu (F3 -> Page 2) to trigger manually
		# # Check for mid-round expansion trigger
		# if not expansion_triggered and game_time_remaining <= expansion_trigger_time:
		# 	print("Mid-round expansion trigger reached!")
		# 	trigger_mid_round_expansion()

		if game_time_remaining <= 0:
			game_time_remaining = max(0.0, game_time_remaining)  # Clamp to 0 to prevent negative display
			print("Time's up! Ending deathmatch...")
			end_deathmatch()

# ============================================================================
# GAME STATE FUNCTIONS
# ============================================================================

func get_current_level_type() -> String:
	"""Get the current arena type being played
	Returns:
		"A" - Type A arena (Original: floating platforms, grind rails)
		"B" - Type B arena (Quake 3: rooms, corridors, jump pads, teleporters)
	"""
	return current_level_type

func is_type_a_arena() -> bool:
	"""Check if currently playing on Type A arena (original style)"""
	return current_level_type == "A"

func is_type_b_arena() -> bool:
	"""Check if currently playing on Type B arena (Quake 3 style)"""
	return current_level_type == "B"

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

	# Hide blur immediately when leaving menu
	if has_node("Menu/Blur"):
		$Menu/Blur.hide()

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
	await _on_practice_button_pressed()

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
		# Silently ignore - menu should be hidden during gameplay anyway
		return

	# Prevent starting if players already exist (game already started)
	var existing_players: int = get_tree().get_nodes_in_group("players").size()
	if existing_players > 0:
		print("WARNING: Cannot start practice mode - %d players already in game!" % existing_players)
		print("======================================")
		return

	# Ask user how many bots they want
	print("Calling ask_bot_count()...")
	var bot_count_choice = await ask_bot_count()
	print("ask_bot_count() returned: ", bot_count_choice)
	if bot_count_choice < 0:
		# User cancelled or error
		print("Practice mode cancelled")
		return

	# Ask user which level type they want (Type A or Type B)
	print("Calling ask_level_type()...")
	var level_type_choice = await ask_level_type()
	print("ask_level_type() returned: ", level_type_choice)
	if level_type_choice == "":
		# User cancelled or error
		print("Practice mode cancelled")
		return

	# Now start practice mode with the chosen bot count and level type
	print("Starting practice mode with %d bots and level type %s..." % [bot_count_choice, level_type_choice])
	start_practice_mode(bot_count_choice, level_type_choice)

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

	# Add HTML5 warning if on web
	if OS.has_feature("web"):
		var warning_label = Label.new()
		warning_label.text = "⚠ Web build recommended max: 8 bots"
		warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warning_label.add_theme_font_size_override("font_size", 14)
		warning_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2, 1))  # Orange warning color
		warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(warning_label)

	# Add separator for visual separation
	var separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 2)
	vbox.add_child(separator)

	# Reset instance variables for this dialog
	bot_count_dialog_closed = false
	bot_count_selected = 3  # Default

	# Bot count options - cap at 8 for HTML5 to prevent physics overload
	var bot_counts = [1, 3, 5, 7, 8] if OS.has_feature("web") else [1, 3, 5, 7, 10, 15]

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
			print("=== BUTTON PRESSED CALLBACK START ===")
			print("Button clicked for count: %d" % count_value)
			bot_count_selected = count_value  # Use instance variable
			print("bot_count_selected set to: %d" % bot_count_selected)
			bot_count_dialog_closed = true  # Use instance variable
			print("bot_count_dialog_closed set to: true")
			dialog.hide()
			print("dialog.hide() called")
			print("=== BUTTON PRESSED CALLBACK END ===")
		)
		grid.add_child(button)

	# Add bottom spacing
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(spacer)

	# Add dialog to scene
	add_child(dialog)

	# Show blur to focus attention on dialog
	if has_node("Menu/Blur"):
		$Menu/Blur.show()

	dialog.popup_centered()
	print("Dialog shown, waiting for user selection...")

	# Wait for user to select an option (flag-based waiting using instance variable)
	while not bot_count_dialog_closed:
		await get_tree().process_frame
		# Silently wait - no need to spam console

	print("Dialog closed flag detected, cleaning up...")
	# Clean up
	dialog.queue_free()

	# Hide blur after dialog is closed
	if has_node("Menu/Blur"):
		$Menu/Blur.hide()

	print("Bot count selected: %d" % bot_count_selected)
	return bot_count_selected

func ask_level_type() -> String:
	"""Ask the user which level generation type they want (Type A or Type B)"""
	# Create a beautiful dialog matching main menu theme
	var dialog = AcceptDialog.new()
	dialog.title = "Select Level Type"
	dialog.dialog_hide_on_ok = false
	dialog.exclusive = true
	dialog.unresizable = false
	dialog.size = Vector2(600, 400)

	# Create custom panel style matching main menu
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0.85)
	panel_style.set_corner_radius_all(12)
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.3, 0.7, 1, 0.6)
	dialog.add_theme_stylebox_override("panel", panel_style)

	# Hide default OK button
	dialog.get_ok_button().hide()

	# Create VBoxContainer for layout
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	dialog.add_child(vbox)

	# Add title label
	var title_label = Label.new()
	title_label.text = "Choose Your Arena Style"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1, 1))
	vbox.add_child(title_label)

	# Add separator
	var separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 2)
	vbox.add_child(separator)

	# Reset instance variables for this dialog
	level_type_dialog_closed = false
	level_type_selected = "A"  # Default

	# Create centered container for buttons
	var center_container = CenterContainer.new()
	vbox.add_child(center_container)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 30)
	center_container.add_child(hbox)

	# Type A Button
	var type_a_button = Button.new()
	type_a_button.text = "Type A\nOriginal Arena"
	type_a_button.custom_minimum_size = Vector2(200, 120)

	var button_style_a = StyleBoxFlat.new()
	button_style_a.bg_color = Color(0.15, 0.15, 0.2, 0.9)
	button_style_a.set_corner_radius_all(10)
	button_style_a.border_width_left = 2
	button_style_a.border_width_top = 2
	button_style_a.border_width_right = 2
	button_style_a.border_width_bottom = 2
	button_style_a.border_color = Color(0.3, 0.7, 1, 0.5)

	var button_hover_style_a = StyleBoxFlat.new()
	button_hover_style_a.bg_color = Color(0.25, 0.35, 0.5, 0.95)
	button_hover_style_a.set_corner_radius_all(10)
	button_hover_style_a.border_width_left = 3
	button_hover_style_a.border_width_top = 3
	button_hover_style_a.border_width_right = 3
	button_hover_style_a.border_width_bottom = 3
	button_hover_style_a.border_color = Color(0.3, 0.7, 1, 1)

	type_a_button.add_theme_font_size_override("font_size", 18)
	type_a_button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	type_a_button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	type_a_button.add_theme_stylebox_override("normal", button_style_a)
	type_a_button.add_theme_stylebox_override("hover", button_hover_style_a)
	type_a_button.add_theme_stylebox_override("pressed", button_hover_style_a)

	type_a_button.pressed.connect(func():
		print("Type A button clicked")
		level_type_selected = "A"
		level_type_dialog_closed = true
		dialog.hide()
	)
	hbox.add_child(type_a_button)

	# Type B Button
	var type_b_button = Button.new()
	type_b_button.text = "Type B\nQuake 3 Arena"
	type_b_button.custom_minimum_size = Vector2(200, 120)

	var button_style_b = StyleBoxFlat.new()
	button_style_b.bg_color = Color(0.15, 0.15, 0.2, 0.9)
	button_style_b.set_corner_radius_all(10)
	button_style_b.border_width_left = 2
	button_style_b.border_width_top = 2
	button_style_b.border_width_right = 2
	button_style_b.border_width_bottom = 2
	button_style_b.border_color = Color(1, 0.5, 0.2, 0.5)  # Orange border for Q3

	var button_hover_style_b = StyleBoxFlat.new()
	button_hover_style_b.bg_color = Color(0.5, 0.25, 0.15, 0.95)
	button_hover_style_b.set_corner_radius_all(10)
	button_hover_style_b.border_width_left = 3
	button_hover_style_b.border_width_top = 3
	button_hover_style_b.border_width_right = 3
	button_hover_style_b.border_width_bottom = 3
	button_hover_style_b.border_color = Color(1, 0.5, 0.2, 1)  # Orange border

	type_b_button.add_theme_font_size_override("font_size", 18)
	type_b_button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	type_b_button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	type_b_button.add_theme_stylebox_override("normal", button_style_b)
	type_b_button.add_theme_stylebox_override("hover", button_hover_style_b)
	type_b_button.add_theme_stylebox_override("pressed", button_hover_style_b)

	type_b_button.pressed.connect(func():
		print("Type B button clicked")
		level_type_selected = "B"
		level_type_dialog_closed = true
		dialog.hide()
	)
	hbox.add_child(type_b_button)

	# Add descriptions
	var desc_container = VBoxContainer.new()
	desc_container.add_theme_constant_override("separation", 10)
	vbox.add_child(desc_container)

	var desc_a = Label.new()
	desc_a.text = "Type A: Floating platforms, ramps, and Sonic-style grind rails"
	desc_a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_a.add_theme_font_size_override("font_size", 14)
	desc_a.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	desc_a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_container.add_child(desc_a)

	var desc_b = Label.new()
	desc_b.text = "Type B: Multi-tier arena with rooms, corridors, jump pads, and teleporters"
	desc_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_b.add_theme_font_size_override("font_size", 14)
	desc_b.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	desc_b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_container.add_child(desc_b)

	# Add dialog to scene
	add_child(dialog)

	# Show blur to focus attention on dialog
	if has_node("Menu/Blur"):
		$Menu/Blur.show()

	dialog.popup_centered()
	print("Level type dialog shown, waiting for user selection...")

	# Wait for user to select an option
	while not level_type_dialog_closed:
		await get_tree().process_frame

	print("Level type dialog closed, cleaning up...")
	dialog.queue_free()

	# Hide blur after dialog is closed
	if has_node("Menu/Blur"):
		$Menu/Blur.hide()

	print("Level type selected: %s" % level_type_selected)
	return level_type_selected

func start_practice_mode(bot_count: int, level_type: String = "A") -> void:
	"""Start practice mode with specified number of bots and level type"""
	print("Starting practice mode with %d bots and level type %s" % [bot_count, level_type])

	if main_menu:
		main_menu.hide()
		# Disable practice button to prevent spam during gameplay
		_set_practice_button_disabled(true)
	if has_node("Menu/Blur"):
		$Menu/Blur.hide()
	# CRITICAL HTML5 FIX: Destroy preview camera and marble preview completely
	if preview_camera and is_instance_valid(preview_camera):
		print("[CAMERA] Destroying preview camera for practice mode")
		preview_camera.current = false
		preview_camera.queue_free()
		preview_camera = null

	if has_node("MarblePreview"):
		print("[CAMERA] Destroying MarblePreview node")
		var marble_preview_node: Node = get_node("MarblePreview")
		marble_preview_node.queue_free()

	if menu_music:
		menu_music.stop()

	# Regenerate level with selected type
	current_level_type = level_type
	print("Regenerating level with type %s..." % level_type)
	await generate_procedural_level(level_type)
	print("Level regeneration complete!")

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

	# Update player spawns from level generator (same as bots)
	if level_generator and level_generator.has_method("get_spawn_points"):
		var spawn_points: PackedVector3Array = level_generator.get_spawn_points()
		if spawn_points.size() > 0:
			local_player.spawns = spawn_points
			# Reposition player to correct spawn point
			var spawn_index: int = 1 % spawn_points.size()
			local_player.global_position = spawn_points[spawn_index]
			print("Player spawned at position %d: %s" % [spawn_index, local_player.global_position])

	player_scores[1] = 0
	player_deaths[1] = 0
	print("Local player added. Total players now: ", get_tree().get_nodes_in_group("players").size())

	# Store bot count to spawn after countdown
	pending_bot_count = bot_count
	print("Will spawn %d bots after countdown completes..." % bot_count)

	# Start the deathmatch
	start_deathmatch()

func _set_practice_button_disabled(disabled: bool) -> void:
	"""Disable or enable the practice button to prevent spam during gameplay"""
	if not main_menu:
		return

	# Navigate to PracticeButton: MainMenu -> PlaySubmenu -> MarginContainer -> VBoxContainer -> SubmenuButtons -> PracticeButton
	var play_submenu: Node = main_menu.get_node_or_null("PlaySubmenu")
	if not play_submenu:
		return

	var margin: Node = play_submenu.get_node_or_null("MarginContainer")
	if not margin:
		return

	var vbox: Node = margin.get_node_or_null("VBoxContainer")
	if not vbox:
		return

	var submenu_buttons: Node = vbox.get_node_or_null("SubmenuButtons")
	if not submenu_buttons:
		return

	var practice_button: Node = submenu_buttons.get_node_or_null("PracticeButton")
	if not practice_button:
		return

	# Disable the button (or use visible = false if preferred)
	if "disabled" in practice_button:
		practice_button.disabled = disabled
		if disabled:
			print("[UI] Practice button disabled (game active)")
		else:
			print("[UI] Practice button enabled (game inactive)")

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
	# Show blur to focus attention on the panel
	if has_node("Menu/Blur"):
		$Menu/Blur.show()

func _on_friends_pressed() -> void:
	"""Show friends panel"""
	if friends_panel:
		friends_panel.show_panel()
	if main_menu:
		main_menu.hide()
	# Show blur to focus attention on the panel
	if has_node("Menu/Blur"):
		$Menu/Blur.show()

func _on_host_button_pressed() -> void:
	if main_menu:
		main_menu.hide()
		# Disable practice button to prevent spam during gameplay
		_set_practice_button_disabled(true)
	if has_node("Menu/Blur"):
		$Menu/Blur.hide()

	# CRITICAL HTML5 FIX: Destroy preview camera and marble preview completely
	if preview_camera and is_instance_valid(preview_camera):
		print("[CAMERA] Destroying preview camera for host mode")
		preview_camera.current = false
		preview_camera.queue_free()
		preview_camera = null

	if has_node("MarblePreview"):
		print("[CAMERA] Destroying MarblePreview node")
		var marble_preview_node: Node = get_node("MarblePreview")
		marble_preview_node.queue_free()

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
		# Disable practice button to prevent spam during gameplay
		_set_practice_button_disabled(true)
	if has_node("Menu/Blur"):
		$Menu/Blur.hide()

	# CRITICAL HTML5 FIX: Destroy preview camera and marble preview completely
	if preview_camera and is_instance_valid(preview_camera):
		print("[CAMERA] Destroying preview camera for join mode")
		preview_camera.current = false
		preview_camera.queue_free()
		preview_camera = null

	if has_node("MarblePreview"):
		print("[CAMERA] Destroying MarblePreview node")
		var marble_preview_node: Node = get_node("MarblePreview")
		marble_preview_node.queue_free()

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
			# Show blur when options menu opens from main menu
			if has_node("Menu/Blur"):
				$Menu/Blur.show()
		else:
			options_menu.hide()
			# Hide blur when options menu closes
			if has_node("Menu/Blur"):
				$Menu/Blur.hide()

func add_player(peer_id: int) -> void:
	var player: Node = Player.instantiate()
	player.name = str(peer_id)
	add_child(player)

	# Add to players group for AI targeting
	player.add_to_group("players")

	# Update player spawns from level generator (same as bots)
	if level_generator and level_generator.has_method("get_spawn_points"):
		var spawn_points: PackedVector3Array = level_generator.get_spawn_points()
		if spawn_points.size() > 0:
			player.spawns = spawn_points
			# Reposition player to correct spawn point
			var spawn_index: int = peer_id % spawn_points.size()
			player.global_position = spawn_points[spawn_index]
			print("Multiplayer player %d spawned at position %d: %s" % [peer_id, spawn_index, player.global_position])

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

	# CRITICAL FIX: Regenerate map with Type A for menu preview (without spawning collectibles)
	print("[MENU] Regenerating map preview with Type A")
	await generate_procedural_level("A", false)

	# Recreate marble preview after level regeneration
	print("[CAMERA] Recreating marble preview for main menu")
	_create_marble_preview()

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

func is_game_active() -> bool:
	"""Check if the game is currently active"""
	return game_active

func end_deathmatch() -> void:
	"""End the deathmatch and show results"""
	print("======================================")
	print("end_deathmatch() CALLED!")
	print("Game time was: %.2f seconds" % max(0.0, game_time_remaining))
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

	# Despawn all bots
	despawn_all_bots()

	# Clear ALL ability pickups (both spawned and dropped by players)
	var all_abilities: Array[Node] = get_tree().get_nodes_in_group("ability_pickups")
	for ability in all_abilities:
		if ability:
			ability.queue_free()
	print("Cleared %d ability pickups from world" % all_abilities.size())

	# Clear ALL orbs (both spawned and dropped by players)
	var all_orbs: Array[Node] = get_tree().get_nodes_in_group("orbs")
	for orb in all_orbs:
		if orb:
			orb.queue_free()
	print("Cleared %d orbs from world" % all_orbs.size())

	# Also tell spawners to clear their tracking arrays
	var ability_spawner: Node = get_node_or_null("AbilitySpawner")
	if ability_spawner and ability_spawner.has_method("clear_all"):
		ability_spawner.clear_all()

	var orb_spawner: Node = get_node_or_null("OrbSpawner")
	if orb_spawner and orb_spawner.has_method("clear_all"):
		orb_spawner.clear_all()

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
		# Determine bot or player
		var winner_type: String = " (Bot)" if winner_id >= 9000 else ""
		print("🏆 Winner: Player %d%s with %d points!" % [winner_id, winner_type, highest_score])
	else:
		print("Match ended - no scores recorded")

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

	# Remove all players (including bots)
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	for player in players:
		player.queue_free()

	# Clear ALL ability pickups (both spawned and dropped by players)
	var all_abilities: Array[Node] = get_tree().get_nodes_in_group("ability_pickups")
	for ability in all_abilities:
		if ability:
			ability.queue_free()
	print("Cleared %d ability pickups from world" % all_abilities.size())

	# Clear ALL orbs (both spawned and dropped by players)
	var all_orbs: Array[Node] = get_tree().get_nodes_in_group("orbs")
	for orb in all_orbs:
		if orb:
			orb.queue_free()
	print("Cleared %d orbs from world" % all_orbs.size())

	# Also tell spawners to clear their tracking arrays
	var ability_spawner: Node = get_node_or_null("AbilitySpawner")
	if ability_spawner and ability_spawner.has_method("clear_all"):
		ability_spawner.clear_all()

	var orb_spawner: Node = get_node_or_null("OrbSpawner")
	if orb_spawner and orb_spawner.has_method("clear_all"):
		orb_spawner.clear_all()

	# Clear scores and deaths
	player_scores.clear()
	player_deaths.clear()

	# Reset game state
	game_active = false
	countdown_active = false
	game_time_remaining = 300.0
	last_time_print = -1  # Reset time print tracker

	# Reset mid-round expansion
	expansion_triggered = false

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
		# Re-enable practice button now that we're back in menu
		_set_practice_button_disabled(false)

	# Hide blur effect
	if has_node("Menu/Blur"):
		$Menu/Blur.hide()

	# Wait a frame for all queue_free() calls to complete
	await get_tree().process_frame

	# CRITICAL FIX: Regenerate map with Type A for menu preview (without spawning collectibles)
	print("[MENU] Regenerating map preview with Type A")
	await generate_procedural_level("A", false)

	# Recreate marble preview after level regeneration
	print("[CAMERA] Recreating marble preview for main menu")
	_create_marble_preview()

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
	var time_clamped: float = max(0.0, game_time_remaining)  # Clamp to 0 to prevent negative display
	var minutes: int = int(time_clamped) / 60
	var seconds: int = int(time_clamped) % 60
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
	elif not OS.has_feature("web"):
		# Only print error for non-HTML5 builds (HTML5 won't have music files in res://)
		print("No music files found in either %s or res://music" % music_dir)

func _load_music_from_directory(dir: String) -> int:
	"""Load all music files from a directory and return count of songs loaded"""
	var dir_access: DirAccess = DirAccess.open(dir)
	if not dir_access:
		# Only print error if not HTML5 trying to access non-res:// path
		if not (OS.has_feature("web") and not dir.begins_with("res://")):
			print("Failed to open music directory: %s" % dir)
		return 0

	print("[MUSIC] Scanning directory: %s" % dir)
	dir_access.list_dir_begin()
	var file_name: String = dir_access.get_next()
	var songs_loaded: int = 0

	while file_name != "":
		if not dir_access.current_is_dir():
			# Skip .import files - we want the original audio files
			if file_name.ends_with(".import"):
				# Extract the original filename (remove .import extension)
				var original_name: String = file_name.trim_suffix(".import")
				var ext: String = original_name.get_extension().to_lower()
				print("[MUSIC] Found imported file: %s -> original: %s (ext: %s)" % [file_name, original_name, ext])

				# Check if it's a supported audio format
				if ext in ["mp3", "ogg", "wav"]:
					# Use the ORIGINAL filename (without .import) for loading
					var file_path: String = dir.path_join(original_name)
					print("[MUSIC] Attempting to load: %s" % file_path)
					var audio_stream: AudioStream = _load_audio_file(file_path, ext)

					if audio_stream and gameplay_music.has_method("add_song"):
						gameplay_music.add_song(audio_stream, file_path)
						songs_loaded += 1
						print("[MUSIC] ✅ Successfully loaded: %s" % original_name)
					else:
						print("[MUSIC] ❌ Failed to load: %s (stream=%s)" % [original_name, "null" if not audio_stream else "exists"])
			else:
				# Non-imported file (external music directory)
				var ext: String = file_name.get_extension().to_lower()
				print("[MUSIC] Found file: %s (extension: %s)" % [file_name, ext])

				# Check if it's a supported audio format
				if ext in ["mp3", "ogg", "wav"]:
					var file_path: String = dir.path_join(file_name)
					print("[MUSIC] Attempting to load: %s" % file_path)
					var audio_stream: AudioStream = _load_audio_file(file_path, ext)

					if audio_stream and gameplay_music.has_method("add_song"):
						gameplay_music.add_song(audio_stream, file_path)
						songs_loaded += 1
						print("[MUSIC] ✅ Successfully loaded: %s" % file_name)
					else:
						print("[MUSIC] ❌ Failed to load: %s (stream=%s)" % [file_name, "null" if not audio_stream else "exists"])

		file_name = dir_access.get_next()

	dir_access.list_dir_end()

	print("[MUSIC] Scan complete. Songs loaded: %d" % songs_loaded)
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
		print("[MUSIC] Trying ResourceLoader.load(%s)..." % file_path)
		audio_stream = ResourceLoader.load(file_path)
		if audio_stream:
			print("[MUSIC] ✅ ResourceLoader succeeded: %s" % file_path)
			return audio_stream
		else:
			print("[MUSIC] ⚠️ ResourceLoader failed for %s, trying FileAccess fallback..." % file_path)
			# Fall through to FileAccess method below

	# For external files (or res:// files that aren't imported), use FileAccess
	print("[MUSIC] Trying FileAccess for %s extension..." % extension)
	match extension:
		"mp3":
			var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
			if file:
				print("[MUSIC] FileAccess opened successfully, loading MP3 data...")
				var mp3_stream: AudioStreamMP3 = AudioStreamMP3.new()
				mp3_stream.data = file.get_buffer(file.get_length())
				file.close()
				audio_stream = mp3_stream
				print("[MUSIC] ✅ MP3 stream created successfully")
			else:
				print("[MUSIC] ❌ FileAccess.open failed for: %s" % file_path)

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

func spawn_pending_bots() -> void:
	"""Spawn all pending bots (called when match becomes active)"""
	print("spawn_pending_bots() called - spawning %d bots" % pending_bot_count)
	for i in range(pending_bot_count):
		print("Spawning bot %d of %d" % [i + 1, pending_bot_count])
		spawn_bot()
		# Small delay between spawns for visual effect
		if i < pending_bot_count - 1:  # Don't wait after last bot
			await get_tree().create_timer(0.1).timeout
	print("All pending bots spawned. Total players: ", get_tree().get_nodes_in_group("players").size())

func despawn_all_bots() -> void:
	"""Remove all bot players from the game"""
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	var bots_removed: int = 0

	for player in players:
		if player:
			# Check if this is a bot (ID >= 9000)
			var player_id: int = str(player.name).to_int()
			if player_id >= 9000:
				print("Despawning bot: %s (ID: %d)" % [player.name, player_id])
				# Keep scores/deaths on leaderboard - don't erase them
				# Remove from scene
				player.queue_free()
				bots_removed += 1

	bot_counter = 0
	pending_bot_count = 0
	print("Despawned %d bots. Remaining players: %d" % [bots_removed, get_tree().get_nodes_in_group("players").size() - bots_removed])

func spawn_abilities_and_orbs() -> void:
	"""Trigger spawning of abilities and orbs when match becomes active"""
	# Find and trigger ability spawner
	var ability_spawner: Node = get_node_or_null("AbilitySpawner")
	if ability_spawner and ability_spawner.has_method("spawn_abilities"):
		ability_spawner.spawn_abilities()
		print("Triggered ability spawning")

	# Find and trigger orb spawner
	var orb_spawner: Node = get_node_or_null("OrbSpawner")
	if orb_spawner and orb_spawner.has_method("spawn_orbs"):
		orb_spawner.spawn_orbs()
		print("Triggered orb spawning")

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
	"""Create marble preview for main menu - actual player marble"""
	# Create a container for the marble preview
	var preview_container = Node3D.new()
	preview_container.name = "MarblePreview"

	# Use raycast to find ground position
	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(Vector3(0, 100, 0), Vector3(0, -100, 0))
	var result = space_state.intersect_ray(query)

	var ground_position = Vector3(0, 0, 0)
	if result:
		ground_position = result.position
		print("Ground found at: ", ground_position)
	else:
		print("No ground found, using default position")

	# Instantiate an actual player marble
	var marble = Player.instantiate()
	marble.name = "PreviewMarble"
	# Position marble on ground (add 0.5 for marble radius so it sits on top)
	marble.position = ground_position + Vector3(0, 0.5, 0)

	# Disable physics and input for preview (it's just for display)
	if marble is RigidBody3D:
		marble.freeze = true  # Freeze physics
		marble.set_process(false)  # Disable processing
		marble.set_physics_process(false)  # Disable physics processing
		marble.set_process_input(false)  # Disable input
		marble.set_process_unhandled_input(false)  # Disable unhandled input

	# Disable camera and UI elements from the marble
	var marble_camera = marble.get_node_or_null("CameraArm/Camera3D")
	if marble_camera:
		marble_camera.queue_free()  # Remove the marble's camera
	var crosshair = marble.get_node_or_null("TextureRect")
	if crosshair:
		crosshair.queue_free()  # Remove crosshair UI

	preview_container.add_child(marble)
	marble_preview = marble.get_node_or_null("MeshInstance3D")
	if not marble_preview:
		marble_preview = marble.get_node_or_null("MarbleMesh")

	# Create preview camera positioned like Rocket League showcase
	preview_camera = Camera3D.new()
	preview_camera.name = "PreviewCamera"
	# Position camera to showcase the marble (slightly above and in front)
	var marble_y = ground_position.y + 0.5
	preview_camera.position = Vector3(-2, marble_y + 0.5, 3)
	# Add to tree first before calling look_at
	preview_container.add_child(preview_camera)
	# Look at the marble at its actual position (after adding to tree)
	if preview_camera.is_inside_tree():
		preview_camera.look_at(ground_position + Vector3(0, 0.5, 0), Vector3.UP)
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

func _resume_audio_context() -> void:
	"""Resume AudioContext on first user interaction (HTML5 browser policy fix)"""
	if not OS.has_feature("web"):
		return

	var js_code = """
		if (typeof AudioContext !== 'undefined' || typeof webkitAudioContext !== 'undefined') {
			var AudioContext = window.AudioContext || window.webkitAudioContext;
			if (typeof window._godotAudioContext !== 'undefined' && window._godotAudioContext) {
				window._godotAudioContext.resume().then(function() {
					console.log('[Godot] AudioContext resumed successfully');
				}).catch(function(err) {
					console.log('[Godot] Failed to resume AudioContext:', err);
				});
			}
		}
	"""
	JavaScriptBridge.eval(js_code, true)
	print("[HTML5] Attempted to resume AudioContext")

func _on_profile_panel_close_pressed() -> void:
	"""Handle profile panel close button pressed"""
	if profile_panel:
		profile_panel.hide()
	# Hide blur when closing panel
	if has_node("Menu/Blur"):
		$Menu/Blur.hide()
	if main_menu:
		main_menu.show()

func _on_friends_panel_close_pressed() -> void:
	"""Handle friends panel close button pressed"""
	if friends_panel:
		friends_panel.hide()
	# Hide blur when closing panel
	if has_node("Menu/Blur"):
		$Menu/Blur.hide()
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

func generate_procedural_level(level_type: String = "A", spawn_collectibles: bool = true) -> void:
	"""Generate a procedural level with skybox
	Args:
		level_type: "A" for original generator, "B" for Quake 3 arena style
		spawn_collectibles: Whether to spawn abilities and orbs (false for menu preview)
	"""
	if OS.is_debug_build():
		print("Generating procedural arena (Type %s)..." % level_type)

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

	# Create level generator based on selected type
	level_generator = Node3D.new()
	level_generator.name = "LevelGenerator"

	if level_type == "B":
		# Use Quake 3 Arena-style generator
		level_generator.set_script(LevelGeneratorQ3)
		print("Using Quake 3 Arena-style level generator")
	else:
		# Use original generator (Type A)
		level_generator.set_script(LevelGenerator)
		print("Using original level generator")

	add_child(level_generator)

	# Wait a frame for level to generate
	await get_tree().process_frame

	# Apply procedural textures
	if level_generator.has_method("apply_procedural_textures"):
		level_generator.apply_procedural_textures()

	# Update player spawn points from generated level
	update_player_spawns()

	# Respawn all orbs and abilities on the new level (only if spawn_collectibles is true)
	if spawn_collectibles:
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

# ============================================================================
# MID-ROUND EXPANSION SYSTEM
# ============================================================================

func trigger_mid_round_expansion() -> void:
	"""Trigger the mid-round expansion - show notification, spawn new area, connect with rail"""
	print("======================================")
	print("TRIGGERING MID-ROUND EXPANSION!")
	print("======================================")

	expansion_triggered = true

	# Show notification in HUD
	if game_hud and game_hud.has_method("show_expansion_notification"):
		game_hud.show_expansion_notification()

	# Calculate position for secondary arena (1000 feet = 304.8 meters away)
	var expansion_offset: Vector3 = Vector3(304.8, 0, 0)  # 1000 feet to the right

	# Wait 1 second for dramatic effect
	await get_tree().create_timer(1.0).timeout

	# Spawn POOF particle effect at the secondary arena location
	var PoofEffect = preload("res://scripts/poof_particle_effect.gd")
	var poof = Node3D.new()
	poof.set_script(PoofEffect)
	add_child(poof)
	poof.global_position = expansion_offset
	# Trigger the effect
	if poof.has_method("play_poof"):
		poof.play_poof()

	# Wait a brief moment for the POOF to be visible
	await get_tree().create_timer(0.3).timeout

	# Generate secondary arena
	if level_generator and level_generator.has_method("generate_secondary_map"):
		level_generator.generate_secondary_map(expansion_offset)
		print("Secondary arena generated at offset: ", expansion_offset)

		# Apply textures to new platforms (only new ones, not regenerating entire map)
		if level_generator.has_method("apply_procedural_textures"):
			level_generator.apply_procedural_textures()

		# Generate connecting rail from main arena to secondary arena
		var start_rail_pos: Vector3 = Vector3(60, 5, 0)  # Edge of main arena
		var end_rail_pos: Vector3 = expansion_offset + Vector3(-60, 5, 0)  # Edge of secondary arena

		if level_generator.has_method("generate_connecting_rail"):
			level_generator.generate_connecting_rail(start_rail_pos, end_rail_pos)
			print("Connecting rail generated!")

	# Showcase the new arena with a dolly camera
	await showcase_new_arena(expansion_offset)

	print("======================================")
	print("MID-ROUND EXPANSION COMPLETE!")
	print("======================================")

func showcase_new_arena(arena_position: Vector3) -> void:
	"""Temporarily show all players the new arena with a dolly camera"""
	print("Starting arena showcase...")

	# Create a showcase camera
	var showcase_camera = Camera3D.new()
	showcase_camera.name = "ShowcaseCamera"
	add_child(showcase_camera)

	# Position camera to orbit around the new arena
	var orbit_radius: float = 100.0
	var orbit_height: float = 40.0
	var orbit_duration: float = 4.0  # 4 seconds of showcase

	# Store player states and freeze them
	var player_states: Dictionary = {}
	var players: Array[Node] = get_tree().get_nodes_in_group("players")

	print("======================================")
	print("FREEZING ", players.size(), " PLAYERS FOR SHOWCASE")
	print("======================================")

	for player in players:
		var state: Dictionary = {}

		print("Storing state for player: ", player.name)

		# Store position and transform
		if player is Node3D:
			state["position"] = player.global_position
			state["rotation"] = player.global_rotation
			state["visible"] = player.visible
			print("  Position: ", player.global_position)
			print("  Visible: ", player.visible)

		# Store and disable camera
		if player.has_node("CameraArm/Camera3D"):
			var camera = player.get_node("CameraArm/Camera3D")
			var camera_arm = player.get_node("CameraArm")

			state["camera"] = camera
			state["camera_arm"] = camera_arm
			state["was_current"] = camera.current

			# Store camera local transform (relative to CameraArm)
			state["camera_position"] = camera.position
			state["camera_rotation"] = camera.rotation
			state["camera_transform"] = camera.transform

			# Store CameraArm global position (it has top_level = true)
			state["camera_arm_position"] = camera_arm.global_position
			state["camera_arm_rotation"] = camera_arm.global_rotation

			camera.current = false
			print("  Camera stored (was_current: ", state["was_current"], ")")
			print("  Camera local position: ", camera.position)
			print("  CameraArm global position: ", camera_arm.global_position)

		# Freeze player physics (RigidBody3D)
		if player is RigidBody3D:
			state["original_freeze"] = player.freeze
			state["original_linear_velocity"] = player.linear_velocity
			state["original_angular_velocity"] = player.angular_velocity
			player.freeze = true
			player.linear_velocity = Vector3.ZERO
			player.angular_velocity = Vector3.ZERO
			print("  Physics frozen (was frozen: ", state["original_freeze"], ")")

		# Disable player input processing
		state["original_process_mode"] = player.process_mode
		player.set_process_input(false)
		player.set_process_unhandled_input(false)
		print("  Input disabled")

		player_states[player] = state

	print("All players frozen and stored")

	# Make showcase camera active
	showcase_camera.current = true

	# Animate the dolly camera orbiting around the new arena
	var start_time: float = Time.get_ticks_msec() / 1000.0
	var elapsed: float = 0.0

	while elapsed < orbit_duration:
		var current_time: float = Time.get_ticks_msec() / 1000.0
		elapsed = current_time - start_time

		# Calculate orbit position (circular path around arena)
		var orbit_progress: float = elapsed / orbit_duration
		var angle: float = orbit_progress * PI  # Half circle (180 degrees)

		var x: float = arena_position.x + cos(angle) * orbit_radius
		var z: float = arena_position.z + sin(angle) * orbit_radius
		var y: float = arena_position.y + orbit_height

		showcase_camera.global_position = Vector3(x, y, z)
		showcase_camera.look_at(arena_position + Vector3(0, 10, 0), Vector3.UP)

		await get_tree().process_frame

	# Clean up showcase camera first
	showcase_camera.queue_free()

	# Wait a frame for showcase camera cleanup
	await get_tree().process_frame

	# Identify the local player (same logic as game_hud.gd)
	var local_player_id: int = 1  # Default to player 1 for practice mode
	if multiplayer.has_multiplayer_peer():
		local_player_id = multiplayer.get_unique_id()
	var local_player_name: String = str(local_player_id)
	print("Identifying local player: ", local_player_name)

	# Restore all player states
	for player in player_states.keys():
		if not is_instance_valid(player):
			print("Warning: Player instance invalid during restoration")
			continue

		var state: Dictionary = player_states[player]
		var is_local_player: bool = (player.name == local_player_name)

		print("Processing player: ", player.name, " (is_local: ", is_local_player, ")")

		# Restore position and visibility
		if player is Node3D:
			if state.has("position"):
				player.global_position = state["position"]
				print("✓ Restored position: ", state["position"])
			if state.has("rotation"):
				player.global_rotation = state["rotation"]
			if state.has("visible"):
				player.visible = state["visible"]
				print("✓ Restored visibility: ", state["visible"])

		# Unfreeze player physics FIRST
		if player is RigidBody3D and state.has("original_freeze"):
			player.freeze = state["original_freeze"]
			# Ensure player is not stuck
			if not player.freeze:
				player.linear_velocity = Vector3.ZERO
				player.angular_velocity = Vector3.ZERO
			print("✓ Unfroze player: ", player.name, " (freeze: ", player.freeze, ")")

		# Re-enable player input processing
		player.set_process_input(true)
		player.set_process_unhandled_input(true)
		player.set_process(true)
		player.set_physics_process(true)
		print("✓ Re-enabled processing for player: ", player.name)

		# Ensure all child meshes are visible
		for child in player.get_children():
			if child is MeshInstance3D:
				child.visible = true
				print("✓ Made mesh visible: ", child.name)

		# Restore camera - ALWAYS restore for local player (do this LAST)
		if state.has("camera") and is_instance_valid(state["camera"]):
			var camera = state["camera"]

			# First restore CameraArm position (it has top_level = true)
			if state.has("camera_arm") and is_instance_valid(state["camera_arm"]):
				var camera_arm = state["camera_arm"]
				if state.has("camera_arm_position"):
					camera_arm.global_position = state["camera_arm_position"]
					print("  Restored CameraArm global position: ", camera_arm.global_position)
				if state.has("camera_arm_rotation"):
					camera_arm.global_rotation = state["camera_arm_rotation"]
					print("  Restored CameraArm global rotation")

			# Then restore camera's local transform (position relative to CameraArm)
			if state.has("camera_transform"):
				camera.transform = state["camera_transform"]
				print("  Restored camera local transform")
			elif state.has("camera_position") and state.has("camera_rotation"):
				camera.position = state["camera_position"]
				camera.rotation = state["camera_rotation"]
				print("  Restored camera local position: ", camera.position)

			# Always activate camera for local player
			if is_local_player:
				camera.current = true
				# Force camera to update its transform
				camera.force_update_transform()
				print("✓ Restored camera for LOCAL player: ", player.name)
				print("  Camera global position: ", camera.global_position)
				print("  Player position: ", player.global_position)
				print("  Camera local position: ", camera.position)
			elif state.get("was_current", false):
				camera.current = true
				camera.force_update_transform()
				print("✓ Restored camera for player: ", player.name, " (was current before)")

	# Wait another frame to ensure everything is properly restored
	await get_tree().process_frame

	print("======================================")
	print("Arena showcase complete - control returned to players")
	print("======================================")
