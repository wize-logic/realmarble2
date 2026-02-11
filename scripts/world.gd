extends Node

# UI References
@onready var main_menu: Control = $Menu/MainMenu if has_node("Menu/MainMenu") else null
@onready var options_menu: PanelContainer = $Menu/Options if has_node("Menu/Options") else null
@onready var pause_menu: PanelContainer = $Menu/PauseMenu if has_node("Menu/PauseMenu") else null
@onready var menu_music: AudioStreamPlayer = get_node_or_null("%MenuMusic")
@onready var gameplay_music: Node = get_node_or_null("GameplayMusic")
@onready var music_notification: Control = get_node_or_null("MusicNotification/NotificationUI")
@onready var game_hud: Control = get_node_or_null("GameHUD/HUD")
@onready var _blur_node: Node = $Menu/Blur if has_node("Menu/Blur") else null

# Multiplayer UI
var lobby_ui: Control = null
const LobbyUI = preload("res://lobby_ui.tscn")

# Profile and Friends UI
var profile_panel: PanelContainer = null
var friends_panel: PanelContainer = null
var customize_panel: PanelContainer = null
const ProfilePanelScript = preload("res://scripts/ui/profile_panel.gd")
const FriendsPanelScript = preload("res://scripts/ui/friends_panel.gd")
const CustomizePanelScript = preload("res://scripts/ui/customize_panel.gd")
const MarbleMaterialManagerScript = preload("res://scripts/marble_material_manager.gd")
const BeamSpawnEffectScript = preload("res://scripts/beam_spawn_effect.gd")
const AbilityBaseScript = preload("res://scripts/abilities/ability_base.gd")
const DashAttackScene = preload("res://abilities/dash_attack.tscn")
const ExplosionScene = preload("res://abilities/explosion.tscn")
const CannonScene = preload("res://abilities/cannon.tscn")
const SwordScene = preload("res://abilities/sword.tscn")
const LightningStrikeScene = preload("res://abilities/lightning_strike.tscn")
var marble_material_manager = MarbleMaterialManagerScript.new()

# Countdown UI (created dynamically)
var countdown_label: Label = null
var countdown_sound: AudioStreamPlayer = null

# Marble Preview (for main menu)
var marble_preview: Node3D = null
var preview_camera: Camera3D = null
var preview_light: DirectionalLight3D = null

# Audio context state (HTML5)
var audio_context_resumed: bool = false

# Cached has_method results for gameplay_music
var _music_has_pause: bool = false
var _music_has_resume: bool = false
var _music_has_start: bool = false
var _music_has_stop: bool = false

# PERF: Cached pause state for transition detection
var _was_paused: bool = false
# PERF: Cached multiplayer state (never changes mid-match)
var _is_multiplayer: bool = false
var _is_host: bool = false

# Game Settings
var sensitivity: float = 0.005
var controller_sensitivity: float = 0.010

# Multiplayer
const Player = preload("res://marble_player.tscn")  # Updated to marble player

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

# MULTIPLAYER SYNC: Periodic game timer sync from host to clients
var timer_sync_interval: float = 5.0  # Sync timer every 5 seconds
var timer_sync_accumulator: float = 0.0

# Mid-round expansion system
var expansion_triggered: bool = false
var expansion_trigger_time: float = 150.0  # Trigger at 2.5 minutes (150 seconds remaining)
# NOTE: Expansion notification moved to game HUD (game_hud.gd)

# Bot system
var bot_counter: int = 0
var pending_bot_count: int = 0  # Bots to spawn when game becomes active
# Bot AI scripts loaded dynamically based on level type
const BotAI_TypeB = preload("res://scripts/bot_ai_type_b.gd")

# Bot count selection dialog state (instance variables for proper closure sharing)
var bot_count_dialog_closed: bool = false
var bot_count_selected: int = 3

# Level type selection removed - Q3 is the only generator now

# Level configuration dialog state
var level_config_dialog_closed: bool = false
var level_config_size: int = 2  # 1=Small, 2=Medium, 3=Large, 4=Huge

# Player marble customization
var selected_marble_color_index: int = 0  # Default to first color (Ruby Red)
var level_config_time: float = 300.0  # Match duration in seconds (default 5 minutes)

# Time slider constants
const TIME_SLIDER_VALUES: Array[float] = [60.0, 180.0, 300.0, 600.0, 900.0]  # 1, 3, 5, 10, 15 minutes
const TIME_SLIDER_LABELS: Array[String] = ["1 Minute", "3 Minutes", "5 Minutes", "10 Minutes", "15 Minutes"]

# Debug menu
const DebugMenu = preload("res://debug_menu.tscn")

# Scoreboard
const Scoreboard = preload("res://scoreboard.tscn")

# Procedural level generation - Q3 generator only
const LevelGeneratorQ3 = preload("res://scripts/level_generator_q3.gd")
const SkyboxGenerator = preload("res://scripts/skybox_generator.gd")
var level_generator: Node3D = null
var skybox_generator: Node3D = null

# GAME STATE
var current_level_size: int = 2  # 1=Small, 2=Medium, 3=Large, 4=Huge
var current_arena_multiplier: float = 1.0  # Arena size multiplier for player speed scaling

func _ready() -> void:
	# Cache has_method results for gameplay_music
	if gameplay_music:
		_music_has_pause = gameplay_music.has_method("pause_playlist")
		_music_has_resume = gameplay_music.has_method("resume_playlist")
		_music_has_start = gameplay_music.has_method("start_playlist")
		_music_has_stop = gameplay_music.has_method("stop_playlist")

	# Load saved marble color preference from Global settings
	selected_marble_color_index = Global.marble_color_index
	_precache_visual_resources()

	# Generate menu preview level (floor + video walls only)
	generate_procedural_level(false, 2, false, true)

	# Initialize debug menu
	var debug_menu_instance: Control = DebugMenu.instantiate()
	add_child(debug_menu_instance)

	# Initialize scoreboard
	var scoreboard_instance: Control = Scoreboard.instantiate()
	add_child(scoreboard_instance)

	# Initialize lobby UI
	lobby_ui = LobbyUI.instantiate()
	# Add to Menu CanvasLayer (same as profile_panel and friends_panel) so it renders after blur
	if has_node("Menu"):
		get_node("Menu").add_child(lobby_ui)
	else:
		add_child(lobby_ui)
	lobby_ui.visible = false  # Hidden by default

	# Initialize profile panel
	_create_profile_panel()

	# Initialize friends panel
	_create_friends_panel()

	# Initialize customize panel
	_create_customize_panel()

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
		# Connect track control signals from notification
		if music_notification.has_signal("track_skip_requested"):
			music_notification.track_skip_requested.connect(_on_track_skip_requested)
		if music_notification.has_signal("track_prev_requested"):
			music_notification.track_prev_requested.connect(_on_track_prev_requested)

	# Auto-load music from default directory with fallback
	_auto_load_music()

	# Hide HUD initially (only shown during active gameplay)
	if game_hud:
		game_hud.visible = false

func _precache_visual_resources() -> void:
	"""Warm up shaders/materials/effects to avoid first-use hitching."""
	if MaterialPool:
		MaterialPool.precache_visual_resources()
	if marble_material_manager:
		marble_material_manager.precache_shader_materials()
	AbilityBaseScript._ensure_shared_resources()
	BeamSpawnEffectScript.precache_resources()
	_precache_ability_effects()
	# PERF: Force WebGL2 to compile all shader variants NOW instead of on first ability use.
	# Without this, the first ability activation freezes for ~1s as 5+ shader variants compile.
	if MaterialPool:
		MaterialPool.warm_web_shader_variants()

func _precache_ability_effects() -> void:
	"""Instantiate key abilities once to warm effect pools/materials."""
	var warmup_root := Node.new()
	warmup_root.name = "AbilityWarmup"
	add_child(warmup_root)

	var scenes: Array[PackedScene] = [
		DashAttackScene,
		ExplosionScene,
		CannonScene,
		SwordScene,
		LightningStrikeScene,
	]

	for scene in scenes:
		if scene:
			var instance := scene.instantiate()
			warmup_root.add_child(instance)

	get_tree().create_timer(0.2).timeout.connect(warmup_root.queue_free)

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
	if not paused and not countdown_active and not game_active:
		return

	# Handle pause menu - only apply on state transition (not every frame)
	if paused:
		if not _was_paused:
			_was_paused = true
			if pause_menu:
				if _blur_node:
					_blur_node.show()
				pause_menu.show()
				if !controller:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			# Pause gameplay music
			if gameplay_music and _music_has_pause:
				gameplay_music.pause_playlist()
		return  # PERF: Nothing else to do while paused

	# Track unpause transition
	if _was_paused:
		_was_paused = false

	# Handle countdown
	if countdown_active:
		countdown_time -= delta
		update_countdown_display()

		if countdown_time <= 0:
			# Countdown finished - start the game
			DebugLogger.dlog(DebugLogger.Category.WORLD, "Countdown finished! Starting match...")
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
			DebugLogger.dlog(DebugLogger.Category.WORLD, "GO! Match started! game_active is now: %s" % game_active)

			# Spawn pending bots now that match is active
			if pending_bot_count > 0:
				DebugLogger.dlog(DebugLogger.Category.WORLD, "Spawning %d pending bots..." % pending_bot_count)
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
			DebugLogger.dlog(DebugLogger.Category.WORLD, "Match time remaining: %.1f seconds (%.1f minutes)" % [game_time_remaining, game_time_remaining / 60.0])
			last_time_print = current_interval

		# MULTIPLAYER SYNC: Host periodically syncs game timer to prevent client drift
		if _is_multiplayer and _is_host:
			timer_sync_accumulator += delta
			if timer_sync_accumulator >= timer_sync_interval:
				timer_sync_accumulator = 0.0
				_sync_game_timer.rpc(game_time_remaining)

		if game_time_remaining <= 0:
			game_time_remaining = max(0.0, game_time_remaining)  # Clamp to 0 to prevent negative display
			# MULTIPLAYER SYNC FIX: Only host triggers match end in multiplayer
			# Clients receive match end via RPC to prevent desync
			if _is_multiplayer and not _is_host:
				pass  # Wait for host to send end_deathmatch RPC
			else:
				DebugLogger.dlog(DebugLogger.Category.WORLD, "Time's up! Ending deathmatch...")
				if _is_multiplayer and _is_host:
					_sync_end_deathmatch.rpc()
				end_deathmatch()

# ============================================================================
# GAME STATE FUNCTIONS
# ============================================================================

func get_current_level_type() -> String:
	"""Get the current arena type being played (always Q3 style now)"""
	return "Q3"

func is_type_a_arena() -> bool:
	"""Type A arena removed - always returns false"""
	return false

func is_type_b_arena() -> bool:
	"""Check if currently playing on Q3 arena (always true now)"""
	return true

# ============================================================================
# MENU FUNCTIONS
# ============================================================================

func _on_resume_pressed() -> void:
	if !options:
		if _blur_node:
			_blur_node.hide()
	if pause_menu:
		pause_menu.hide()
	if !controller:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	paused = false

	# Resume gameplay music if paused
	if gameplay_music and _music_has_resume:
		gameplay_music.resume_playlist()

func _on_options_pressed() -> void:
	_on_resume_pressed()
	if options_menu:
		options_menu.show()
	if _blur_node:
		_blur_node.show()
	var fullscreen_button: Button = get_node_or_null("%Fullscreen")
	if fullscreen_button:
		fullscreen_button.grab_focus()
	if !controller:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	options = true

func _on_back_pressed() -> void:
	if options:
		# Hide options menu
		if options_menu:
			options_menu.hide()
		# Always hide blur when closing options
		if _blur_node:
			_blur_node.hide()
		if !controller:
			# Only capture mouse if we're in-game (paused), not if we're in main menu
			if paused or game_active:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		options = false

func _on_return_to_title_pressed() -> void:
	"""Return to title screen from pause menu"""
	DebugLogger.dlog(DebugLogger.Category.UI, "Return to title screen pressed")

	# Unpause the game
	paused = false
	if pause_menu:
		pause_menu.hide()

	# Hide blur immediately when leaving menu
	if _blur_node:
		_blur_node.hide()

	# Stop gameplay music
	if gameplay_music and _music_has_stop:
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
	DebugLogger.dlog(DebugLogger.Category.WORLD, "======================================")
	DebugLogger.dlog(DebugLogger.Category.WORLD, "_on_practice_button_pressed() CALLED!")
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Current player count: %d" % get_tree().get_nodes_in_group("players").size())
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Current bot_counter: %d" % bot_counter)
	DebugLogger.dlog(DebugLogger.Category.WORLD, "game_active: %s | countdown_active: %s" % [game_active, countdown_active])
	DebugLogger.dlog(DebugLogger.Category.WORLD, "======================================")

	# Prevent starting practice mode if a game is already active or counting down
	if game_active or countdown_active:
		# Silently ignore - menu should be hidden during gameplay anyway
		return

	# Prevent starting if players already exist (game already started)
	var existing_players: int = get_tree().get_nodes_in_group("players").size()
	if existing_players > 0:
		DebugLogger.dlog(DebugLogger.Category.WORLD, "WARNING: Cannot start practice mode - %d players already in game!" % existing_players)
		DebugLogger.dlog(DebugLogger.Category.WORLD, "======================================")
		return

	# Ask user how many bots they want
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Calling ask_bot_count()...")
	var bot_count_choice = await ask_bot_count()
	DebugLogger.dlog(DebugLogger.Category.WORLD, "ask_bot_count() returned: %d" % bot_count_choice)
	if bot_count_choice < 0:
		# User cancelled or error
		DebugLogger.dlog(DebugLogger.Category.WORLD, "Practice mode cancelled")
		return

	# Ask user for level size/complexity and match duration
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Calling ask_level_config()...")
	var level_config = await ask_level_config()
	DebugLogger.dlog(DebugLogger.Category.WORLD, "ask_level_config() returned: %s" % level_config)
	if level_config.is_empty():
		# User cancelled or error
		DebugLogger.dlog(DebugLogger.Category.WORLD, "Practice mode cancelled")
		return

	# Now start practice mode with the chosen settings (Q3 generator only)
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Starting practice mode with %d bots, size %d, time %.0fs..." % [bot_count_choice, level_config.size, level_config.time])
	start_practice_mode(bot_count_choice, level_config.size, level_config.time)

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

	# Reset instance variables for this dialog
	bot_count_dialog_closed = false
	bot_count_selected = 3  # Default

	# Bot count options - cap at 7 bots (8 total with player) to prevent physics overload
	var bot_counts = [1, 3, 5, 7]

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
			DebugLogger.dlog(DebugLogger.Category.UI, "Bot count button clicked for count: %d" % count_value)
			bot_count_selected = count_value  # Use instance variable
			bot_count_dialog_closed = true  # Use instance variable
			dialog.hide()
		)
		grid.add_child(button)

	# Add bottom spacing
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(spacer)

	# Add dialog to Menu CanvasLayer so it renders after blur (not blurred itself)
	if has_node("Menu"):
		get_node("Menu").add_child(dialog)
	else:
		add_child(dialog)

	# Show blur to focus attention on dialog
	if _blur_node:
		_blur_node.show()

	# Connect close signals to handle cancellation
	dialog.close_requested.connect(func():
		bot_count_dialog_closed = true
		bot_count_selected = -1  # Indicate cancellation
		DebugLogger.dlog(DebugLogger.Category.UI, "Bot count dialog closed via X button or ESC")
	)

	# Ensure mouse is visible for dialog interaction
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	dialog.popup_centered()
	DebugLogger.dlog(DebugLogger.Category.UI, "Bot count dialog shown, waiting for user selection...")

	# Wait for user to select an option (flag-based waiting using instance variable)
	while not bot_count_dialog_closed:
		await get_tree().process_frame
		# Silently wait - no need to spam console

	DebugLogger.dlog(DebugLogger.Category.UI, "Bot count dialog closed flag detected, cleaning up...")
	# Clean up
	dialog.queue_free()

	# Hide blur after dialog is closed
	if _blur_node:
		_blur_node.hide()

	# Keep mouse visible (we're still in main menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	DebugLogger.dlog(DebugLogger.Category.UI, "Bot count selected: %d" % bot_count_selected)
	return bot_count_selected

func ask_level_config() -> Dictionary:
	"""Ask the user for level size/complexity and match duration.
	Returns a dictionary with 'size' (1-4) and 'time' (seconds), or empty dict if cancelled."""

	# Create a beautiful dialog matching main menu theme
	var dialog = AcceptDialog.new()
	dialog.title = "Level Configuration"
	dialog.dialog_hide_on_ok = false
	dialog.exclusive = true
	dialog.unresizable = false
	dialog.size = Vector2(650, 620)

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

	# Create main panel for contents
	var main_panel = PanelContainer.new()
	main_panel.add_theme_stylebox_override("panel", panel_style)
	dialog.add_child(main_panel)

	# Create margin container
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	main_panel.add_child(margin)

	# Create VBoxContainer for layout
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	margin.add_child(vbox)

	# Add title label
	var title_label = Label.new()
	title_label.text = "CONFIGURE YOUR MATCH"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1, 1))
	vbox.add_child(title_label)

	# Add separator
	var separator1 = HSeparator.new()
	separator1.add_theme_constant_override("separation", 2)
	vbox.add_child(separator1)

	# Reset instance variables for this dialog
	level_config_dialog_closed = false
	level_config_size = 2  # Default: Medium
	level_config_time = 300.0  # Default: 5 minutes

	# === LEVEL SIZE/COMPLEXITY SECTION ===
	var size_section = VBoxContainer.new()
	size_section.add_theme_constant_override("separation", 10)
	vbox.add_child(size_section)

	var size_title = Label.new()
	size_title.text = "LEVEL SIZE & COMPLEXITY"
	size_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	size_title.add_theme_font_size_override("font_size", 18)
	size_title.add_theme_color_override("font_color", Color(0.3, 0.7, 1, 1))
	size_section.add_child(size_title)

	# Size slider container
	var size_slider_container = HBoxContainer.new()
	size_slider_container.add_theme_constant_override("separation", 15)
	size_section.add_child(size_slider_container)

	var size_label_left = Label.new()
	size_label_left.text = "Small"
	size_label_left.add_theme_font_size_override("font_size", 14)
	size_label_left.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	size_slider_container.add_child(size_label_left)

	var size_slider = HSlider.new()
	size_slider.min_value = 1
	size_slider.max_value = 4
	size_slider.step = 1
	size_slider.value = 2  # Medium default
	size_slider.custom_minimum_size = Vector2(300, 30)
	size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Style the slider
	var slider_style = StyleBoxFlat.new()
	slider_style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	slider_style.set_corner_radius_all(4)
	size_slider.add_theme_stylebox_override("slider", slider_style)

	var grabber_style = StyleBoxFlat.new()
	grabber_style.bg_color = Color(0.3, 0.7, 1, 1)
	grabber_style.set_corner_radius_all(8)
	size_slider.add_theme_stylebox_override("grabber_area", grabber_style)
	size_slider.add_theme_stylebox_override("grabber_area_highlight", grabber_style)

	size_slider_container.add_child(size_slider)

	var size_label_right = Label.new()
	size_label_right.text = "Huge"
	size_label_right.add_theme_font_size_override("font_size", 14)
	size_label_right.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	size_slider_container.add_child(size_label_right)

	# Size value display
	var size_value_label = Label.new()
	size_value_label.text = "Medium"
	size_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	size_value_label.add_theme_font_size_override("font_size", 16)
	size_value_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	size_section.add_child(size_value_label)

	# Update size value display when slider changes
	# IMPORTANT: Use _update_level_config_size method to properly set instance variable
	size_slider.value_changed.connect(_on_size_slider_changed.bind(size_value_label))
	DebugLogger.dlog(DebugLogger.Category.UI, "Size slider connected. Initial value: %d, focusable: %s, editable: %s" % [size_slider.value, size_slider.focus_mode != Control.FOCUS_NONE, size_slider.editable])

	# Add separator
	var separator2 = HSeparator.new()
	separator2.add_theme_constant_override("separation", 2)
	vbox.add_child(separator2)

	# === MATCH TIME SECTION ===
	var time_section = VBoxContainer.new()
	time_section.add_theme_constant_override("separation", 10)
	vbox.add_child(time_section)

	var time_title = Label.new()
	time_title.text = "MATCH DURATION"
	time_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_title.add_theme_font_size_override("font_size", 18)
	time_title.add_theme_color_override("font_color", Color(0.3, 0.7, 1, 1))
	time_section.add_child(time_title)

	# Time slider container
	var time_slider_container = HBoxContainer.new()
	time_slider_container.add_theme_constant_override("separation", 15)
	time_section.add_child(time_slider_container)

	var time_label_left = Label.new()
	time_label_left.text = "1 min"
	time_label_left.add_theme_font_size_override("font_size", 14)
	time_label_left.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	time_slider_container.add_child(time_label_left)

	var time_slider = HSlider.new()
	time_slider.min_value = 1
	time_slider.max_value = 5
	time_slider.step = 1
	time_slider.value = 3  # 5 minutes default (index 3)
	time_slider.custom_minimum_size = Vector2(300, 30)
	time_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_slider.add_theme_stylebox_override("slider", slider_style)
	time_slider.add_theme_stylebox_override("grabber_area", grabber_style)
	time_slider.add_theme_stylebox_override("grabber_area_highlight", grabber_style)
	time_slider_container.add_child(time_slider)

	var time_label_right = Label.new()
	time_label_right.text = "10 min"
	time_label_right.add_theme_font_size_override("font_size", 14)
	time_label_right.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	time_slider_container.add_child(time_label_right)

	# Time value display
	var time_value_label = Label.new()
	time_value_label.text = "5 Minutes"
	time_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_value_label.add_theme_font_size_override("font_size", 16)
	time_value_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	time_section.add_child(time_value_label)

	# Update time value display when slider changes
	# IMPORTANT: Use _update_level_config_time method to properly set instance variable
	time_slider.value_changed.connect(_on_time_slider_changed.bind(time_value_label))
	DebugLogger.dlog(DebugLogger.Category.UI, "Time slider connected. Initial value: %d" % time_slider.value)

	# Add separator
	var separator3 = HSeparator.new()
	separator3.add_theme_constant_override("separation", 2)
	vbox.add_child(separator3)

	# Add separator before start button
	var separator4 = HSeparator.new()
	separator4.add_theme_constant_override("separation", 2)
	vbox.add_child(separator4)

	# === START BUTTON ===
	var button_container = CenterContainer.new()
	vbox.add_child(button_container)

	var start_button = Button.new()
	start_button.text = "START MATCH"
	start_button.custom_minimum_size = Vector2(200, 50)

	var start_button_style = StyleBoxFlat.new()
	start_button_style.bg_color = Color(0.2, 0.5, 0.3, 0.9)
	start_button_style.set_corner_radius_all(10)
	start_button_style.border_width_left = 2
	start_button_style.border_width_top = 2
	start_button_style.border_width_right = 2
	start_button_style.border_width_bottom = 2
	start_button_style.border_color = Color(0.3, 1.0, 0.5, 0.6)

	var start_button_hover = StyleBoxFlat.new()
	start_button_hover.bg_color = Color(0.3, 0.7, 0.4, 0.95)
	start_button_hover.set_corner_radius_all(10)
	start_button_hover.border_width_left = 3
	start_button_hover.border_width_top = 3
	start_button_hover.border_width_right = 3
	start_button_hover.border_width_bottom = 3
	start_button_hover.border_color = Color(0.3, 1.0, 0.5, 1.0)

	start_button.add_theme_font_size_override("font_size", 20)
	start_button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	start_button.add_theme_stylebox_override("normal", start_button_style)
	start_button.add_theme_stylebox_override("hover", start_button_hover)
	start_button.add_theme_stylebox_override("pressed", start_button_hover)

	start_button.pressed.connect(func():
		DebugLogger.dlog(DebugLogger.Category.UI, "Start Match button clicked - Size: %d, Time: %.0f seconds" % [level_config_size, level_config_time])
		level_config_dialog_closed = true
		dialog.hide()
	)
	button_container.add_child(start_button)

	# Add dialog to Menu CanvasLayer
	if has_node("Menu"):
		get_node("Menu").add_child(dialog)
	else:
		add_child(dialog)

	# Show blur to focus attention on dialog
	if _blur_node:
		_blur_node.show()

	# Connect close signals to handle cancellation
	dialog.close_requested.connect(func():
		level_config_dialog_closed = true
		level_config_size = -1  # Indicate cancellation
		DebugLogger.dlog(DebugLogger.Category.UI, "Level config dialog closed via X button or ESC")
	)

	# Ensure mouse is visible for dialog interaction
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	dialog.popup_centered()
	DebugLogger.dlog(DebugLogger.Category.UI, "Level config dialog shown, waiting for user selection...")

	# Wait for user to confirm or cancel
	while not level_config_dialog_closed:
		await get_tree().process_frame

	DebugLogger.dlog(DebugLogger.Category.UI, "Level config dialog closed, cleaning up...")
	dialog.queue_free()

	# Hide blur after dialog is closed
	if _blur_node:
		_blur_node.hide()

	# Keep mouse visible (we're still in main menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Return configuration or empty dict if cancelled
	if level_config_size == -1:
		DebugLogger.dlog(DebugLogger.Category.UI, "Level config cancelled")
		return {}

	DebugLogger.dlog(DebugLogger.Category.UI, "Level config final values - size: %d, time: %.0f" % [level_config_size, level_config_time])
	return {"size": level_config_size, "time": level_config_time}

func _on_size_slider_changed(value: float, label: Label) -> void:
	"""Callback for size slider - properly sets instance variable"""
	level_config_size = int(value)
	DebugLogger.dlog(DebugLogger.Category.UI, "Size slider changed to: %d" % level_config_size)
	match int(value):
		1: label.text = "Small (Compact arena)"
		2: label.text = "Medium (Standard arena)"
		3: label.text = "Large (Expanded arena)"
		4: label.text = "Huge (Massive arena)"

func _on_time_slider_changed(value: float, label: Label) -> void:
	"""Callback for time slider - properly sets instance variable"""
	var index: int = int(value) - 1
	level_config_time = TIME_SLIDER_VALUES[index]
	label.text = TIME_SLIDER_LABELS[index]
	DebugLogger.dlog(DebugLogger.Category.UI, "Time slider changed to: %.0f seconds (%s)" % [level_config_time, TIME_SLIDER_LABELS[index]])

func start_practice_mode(bot_count: int, level_size: int = 2, match_time: float = 300.0) -> void:
	"""Start practice mode with specified settings.
	Args:
		bot_count: Number of bots to spawn
		level_size: 1=Small, 2=Medium, 3=Large, 4=Huge
		match_time: Match duration in seconds
	"""
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Starting practice mode with %d bots, size %d, time %.0fs" % [bot_count, level_size, match_time])

	if main_menu:
		main_menu.hide()
		# Disable practice button to prevent spam during gameplay
		_set_practice_button_disabled(true)
	if _blur_node:
		_blur_node.hide()
	# CRITICAL HTML5 FIX: Destroy preview camera and marble preview completely
	if preview_camera and is_instance_valid(preview_camera):
		DebugLogger.dlog(DebugLogger.Category.WORLD, "[CAMERA] Destroying preview camera for practice mode")
		preview_camera.current = false
		preview_camera.queue_free()
		preview_camera = null

	if has_node("MarblePreview"):
		DebugLogger.dlog(DebugLogger.Category.WORLD, "[CAMERA] Destroying MarblePreview node")
		var marble_preview_node: Node = get_node("MarblePreview")
		marble_preview_node.queue_free()

	if menu_music:
		menu_music.stop()

	# Set match duration based on user selection
	game_time_remaining = match_time
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Match duration set to %.0f seconds (%.1f minutes)" % [match_time, match_time / 60.0])

	# Regenerate level with selected size and wall settings
	current_level_size = level_size
	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Regenerating level with size %d..." % level_size)
	await generate_procedural_level(true, level_size, false, false, 0, false)
	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Level regeneration complete!")

	# Capture mouse for gameplay
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Start gameplay music
	if gameplay_music and _music_has_start:
		gameplay_music.start_playlist()

	# Add local player without multiplayer
	var local_player: Node = Player.instantiate()
	local_player.name = "1"
	# Apply custom marble color from customize panel
	local_player.custom_color_index = selected_marble_color_index
	add_child(local_player)
	local_player.add_to_group("players")

	# Set arena size multiplier for movement speed scaling
	if local_player.has_method("set_arena_size_multiplier"):
		local_player.set_arena_size_multiplier(current_arena_multiplier)

	# Update player spawns from level generator (same as bots)
	if level_generator and level_generator.has_method("get_spawn_points"):
		var spawn_points: PackedVector3Array = level_generator.get_spawn_points()
		if spawn_points.size() > 0:
			local_player.spawns = spawn_points
			# Reposition player to correct spawn point
			var spawn_index: int = 1 % spawn_points.size()
			local_player.global_position = spawn_points[spawn_index]
			DebugLogger.dlog(DebugLogger.Category.PLAYER, "Player spawned at position %d: %s" % [spawn_index, local_player.global_position])

	player_scores[1] = 0
	player_deaths[1] = 0
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Local player added. Total players now: %d" % get_tree().get_nodes_in_group("players").size())

	# Store bot count to spawn after countdown
	pending_bot_count = bot_count
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Will spawn %d bots after countdown completes..." % bot_count)

	# Start the deathmatch (skip level regen since we already generated it above)
	start_deathmatch(true)

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
			DebugLogger.dlog(DebugLogger.Category.UI, "Practice button disabled (game active)")
		else:
			DebugLogger.dlog(DebugLogger.Category.UI, "Practice button enabled (game inactive)")

func _on_settings_pressed() -> void:
	"""Open settings menu from main menu"""
	_on_options_button_toggled(true)

func _on_quit_pressed() -> void:
	"""Quit the game"""
	get_tree().quit()

func _on_item_shop_pressed() -> void:
	"""Item Shop placeholder"""
	DebugLogger.dlog(DebugLogger.Category.UI, "Item Shop - Not implemented yet")

func _on_garage_pressed() -> void:
	"""Show customize panel"""
	if customize_panel:
		customize_panel.show_panel()
		if customize_panel.preview_viewport:
			customize_panel.preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if main_menu:
		main_menu.hide()
	# Show blur to focus attention on the panel
	if _blur_node:
		_blur_node.show()

func _on_profile_pressed() -> void:
	"""Show profile panel"""
	if profile_panel:
		profile_panel.show_panel()
	if main_menu:
		main_menu.hide()
	# Show blur to focus attention on the panel
	if _blur_node:
		_blur_node.show()

func _on_friends_pressed() -> void:
	"""Show friends panel"""
	if friends_panel:
		friends_panel.show_panel()
	if main_menu:
		main_menu.hide()
	# Show blur to focus attention on the panel
	if _blur_node:
		_blur_node.show()

func _on_options_button_toggled(toggled_on: bool) -> void:
	if options_menu:
		if toggled_on:
			options_menu.show()
			options = true  # Set options flag so back button works correctly
			# Show blur when options menu opens from main menu
			if _blur_node:
				_blur_node.show()
			# Ensure mouse is visible when opening options from main menu
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			options_menu.hide()
			options = false
			# Hide blur when options menu closes
			if _blur_node:
				_blur_node.hide()
			# Keep mouse visible when closing (still in main menu)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func add_player(peer_id: int) -> void:
	var player: Node = Player.instantiate()
	player.name = str(peer_id)

	# Get color from MultiplayerManager's synced player data
	var player_color: int = -1
	if MultiplayerManager.players.has(peer_id):
		var player_info: Dictionary = MultiplayerManager.players[peer_id]
		if player_info.has("color_index"):
			player_color = player_info["color_index"]

	# Apply the synced color (or local selection as fallback for local player)
	var local_peer_id: int = 1
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		local_peer_id = multiplayer.get_unique_id()
	var is_local_player = (peer_id == local_peer_id)
	if player_color >= 0:
		player.custom_color_index = player_color
	elif is_local_player:
		player.custom_color_index = selected_marble_color_index

	add_child(player)

	# Add to players group for AI targeting
	player.add_to_group("players")

	# Set arena size multiplier for movement speed scaling
	if player.has_method("set_arena_size_multiplier"):
		player.set_arena_size_multiplier(current_arena_multiplier)

	# Check if this is a bot (IDs >= 9000 are bots)
	var is_bot: bool = peer_id >= 9000
	if is_bot:
		# Add AI controller to bot
		var ai: Node = BotAI_TypeB.new()
		ai.name = "BotAI"
		player.add_child(ai)
		DebugLogger.dlog(DebugLogger.Category.BOT_AI, "Added BotAI to multiplayer bot %d" % peer_id)

	# Update player spawns from level generator (same as bots)
	if level_generator and level_generator.has_method("get_spawn_points"):
		var spawn_points: PackedVector3Array = level_generator.get_spawn_points()
		if spawn_points.size() > 0:
			player.spawns = spawn_points
			# Reposition player to correct spawn point
			var spawn_index: int = peer_id % spawn_points.size()
			player.global_position = spawn_points[spawn_index]
			DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Multiplayer %s %d spawned at position %d: %s" % ["bot" if is_bot else "player", peer_id, spawn_index, player.global_position])

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
	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Multiplayer player connected: %d - %s" % [peer_id, player_info])
	# DON'T spawn player here - they're just joining the lobby!
	# Players will be spawned when the game actually starts

func _on_multiplayer_player_disconnected(peer_id: int) -> void:
	"""Called when a player disconnects via multiplayer manager"""
	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Multiplayer player disconnected: %d" % peer_id)
	# Only remove if game is active (player exists in scene)
	if game_active or countdown_active:
		remove_player(peer_id)

func show_multiplayer_lobby(show_game_lobby: bool = false) -> void:
	"""Show the multiplayer lobby UI
	Args:
		show_game_lobby: If true, show the game lobby panel (for returning from match).
		                 If false, show the main lobby panel (for opening from main menu).
	"""
	if lobby_ui:
		lobby_ui.visible = true
		# Show the appropriate panel
		if show_game_lobby and lobby_ui.has_method("show_game_lobby"):
			lobby_ui.show_game_lobby()
		elif lobby_ui.has_method("show_main_lobby"):
			lobby_ui.show_main_lobby()
		# Hide main menu
		if main_menu:
			main_menu.visible = false
		# Show blur to focus attention on lobby
		if _blur_node:
			_blur_node.show()
		# Hide marble preview when showing lobby and disable its processing to prevent camera errors
		if has_node("MarblePreview"):
			var marble_preview_container = get_node("MarblePreview")
			marble_preview_container.visible = false
			# Find the PreviewMarble and disable its processing
			var preview_marble = marble_preview_container.get_node_or_null("PreviewMarble")
			if preview_marble:
				preview_marble.set_process(false)
				preview_marble.set_physics_process(false)
		# Show mouse cursor
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func hide_multiplayer_lobby() -> void:
	"""Hide the multiplayer lobby UI"""
	if lobby_ui:
		lobby_ui.visible = false
	# Hide blur when hiding lobby
	if _blur_node:
		_blur_node.hide()

func show_main_menu() -> void:
	"""Show the main menu (without regenerating map - just shows existing preview)"""
	if main_menu:
		main_menu.visible = true

	# Hide blur when returning to main menu
	if _blur_node:
		_blur_node.hide()

	# Show marble preview again (it was hidden when entering lobby) and re-enable if needed
	if has_node("MarblePreview"):
		var marble_preview_container = get_node("MarblePreview")
		marble_preview_container.visible = true
		# Re-enable the PreviewMarble if it was disabled
		var preview_marble = marble_preview_container.get_node_or_null("PreviewMarble")
		if preview_marble and preview_marble.process_mode == Node.PROCESS_MODE_DISABLED:
			# Don't re-enable processing - it should stay disabled
			# The camera is on the preview_camera, not the marble
			pass

	# Ensure mouse is visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ============================================================================
# DEATHMATCH GAME LOGIC
# ============================================================================

func start_multiplayer_match(settings: Dictionary) -> void:
	"""Start a multiplayer match with the specified room settings.
	Args:
		settings: Dictionary with level_size, match_time, and level_seed
	"""
	var level_size: int = settings.get("level_size", 2)
	var match_time: float = settings.get("match_time", 300.0)
	var level_seed: int = settings.get("level_seed", 0)

	DebugLogger.dlog(DebugLogger.Category.WORLD, "start_multiplayer_match() - size: %d, time: %.0f, seed: %d" % [level_size, match_time, level_seed])

	# Store settings for level generation
	current_level_size = level_size

	# Prevent starting a new match if one is already active or counting down
	if game_active or countdown_active:
		DebugLogger.dlog(DebugLogger.Category.WORLD, "WARNING: Match already active or counting down! Ignoring start_multiplayer_match() call.")
		return

	# Hide lobby UI and show game
	hide_multiplayer_lobby()

	# Destroy preview camera and marble since we're starting the game
	if preview_camera and is_instance_valid(preview_camera):
		DebugLogger.dlog(DebugLogger.Category.WORLD, "[CAMERA] Destroying preview camera for multiplayer match")
		preview_camera.current = false
		preview_camera.queue_free()
		preview_camera = null

	if has_node("MarblePreview"):
		DebugLogger.dlog(DebugLogger.Category.WORLD, "[CAMERA] Destroying MarblePreview node")
		var marble_preview_node: Node = get_node("MarblePreview")
		marble_preview_node.queue_free()

	# Hide main menu
	if main_menu:
		main_menu.hide()

	# Stop menu music, start gameplay music
	if menu_music:
		menu_music.stop()
	if gameplay_music and _music_has_start:
		gameplay_music.start_playlist()

	# Regenerate level with multiplayer settings (using shared seed for sync)
	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Regenerating level for multiplayer match (Size %d, Seed: %d)..." % [level_size, level_seed])
	await generate_procedural_level(true, level_size, false, false, level_seed, false)
	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Level regeneration complete!")

	# Capture mouse for gameplay
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Spawn all players from multiplayer manager
	if MultiplayerManager and MultiplayerManager.players:
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Spawning %d multiplayer players..." % MultiplayerManager.players.size())
		for peer_id in MultiplayerManager.players.keys():
			add_player(peer_id)

	game_active = false  # Don't start until countdown finishes
	game_time_remaining = match_time  # Use the time setting from room
	timer_sync_accumulator = 0.0  # Reset timer sync for clean start
	player_scores.clear()
	player_deaths.clear()

	# Notify CrazyGames SDK that gameplay is about to start
	if CrazyGamesSDK:
		CrazyGamesSDK.gameplay_stop()  # Ensure clean state

	# Start countdown
	countdown_active = true
	countdown_time = 2.0  # 2 seconds: "READY" (1s), "GO!" (1s)
	if countdown_label:
		countdown_label.visible = true
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Starting countdown with %.0f second match time..." % match_time)

func start_deathmatch(skip_level_regen: bool = false) -> void:
	"""Start a 5-minute deathmatch with countdown
	Args:
		skip_level_regen: If true, don't regenerate the level (practice mode already did)
	"""
	DebugLogger.dlog(DebugLogger.Category.WORLD, "start_deathmatch() CALLED! skip_level_regen=%s" % skip_level_regen)
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Current game_active: %s | countdown_active: %s" % [game_active, countdown_active])

	# Prevent starting a new match if one is already active or counting down
	if game_active or countdown_active:
		DebugLogger.dlog(DebugLogger.Category.WORLD, "WARNING: Match already active or counting down! Ignoring start_deathmatch() call.")
		return

	# Hide lobby UI and show game
	hide_multiplayer_lobby()

	# Destroy preview camera and marble since we're starting the game
	if preview_camera and is_instance_valid(preview_camera):
		DebugLogger.dlog(DebugLogger.Category.WORLD, "[CAMERA] Destroying preview camera for multiplayer match")
		preview_camera.current = false
		preview_camera.queue_free()
		preview_camera = null

	if has_node("MarblePreview"):
		DebugLogger.dlog(DebugLogger.Category.WORLD, "[CAMERA] Destroying MarblePreview node")
		var marble_preview_node: Node = get_node("MarblePreview")
		marble_preview_node.queue_free()

	# Hide main menu
	if main_menu:
		main_menu.hide()

	# Stop menu music, start gameplay music
	if menu_music:
		menu_music.stop()
	if gameplay_music and _music_has_start:
		gameplay_music.start_playlist()

	# Regenerate level ONLY for multiplayer matches (practice mode already generated it)
	if not skip_level_regen and multiplayer.has_multiplayer_peer():
		# FIX: Pass video/music wall settings from room_settings for multiplayer fallback path
		var fallback_seed: int = 0
		if MultiplayerManager:
			fallback_seed = MultiplayerManager.room_settings.get("level_seed", 0)
		DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Regenerating level for multiplayer match (Size %d)..." % current_level_size)
		await generate_procedural_level(true, current_level_size, false, false, fallback_seed, false)
		DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Level regeneration complete!")
	elif skip_level_regen:
		DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Skipping level regeneration (practice mode already generated level)")

	# Capture mouse for gameplay
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Spawn all players from multiplayer manager
	if MultiplayerManager and MultiplayerManager.players:
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Spawning %d multiplayer players..." % MultiplayerManager.players.size())
		for peer_id in MultiplayerManager.players.keys():
			add_player(peer_id)

	game_active = false  # Don't start until countdown finishes
	# FIX: Only reset game_time_remaining if not already set by caller (e.g. practice mode)
	# When skip_level_regen is true, practice mode already set the correct match time
	if not skip_level_regen:
		game_time_remaining = 300.0
	timer_sync_accumulator = 0.0  # Reset timer sync for clean start
	player_scores.clear()
	player_deaths.clear()

	# Notify CrazyGames SDK that gameplay is about to start
	if CrazyGamesSDK:
		CrazyGamesSDK.gameplay_stop()  # Ensure clean state

	# PERF: Cache multiplayer state (never changes mid-match)
	_is_multiplayer = multiplayer.has_multiplayer_peer()
	_is_host = _is_multiplayer and multiplayer.is_server()

	# Start countdown
	countdown_active = true
	countdown_time = 2.0  # 2 seconds: "READY" (1s), "GO!" (1s)
	if countdown_label:
		countdown_label.visible = true
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Starting countdown (match time: %.0fs)..." % game_time_remaining)

func is_game_active() -> bool:
	"""Check if the game is currently active"""
	return game_active

func end_deathmatch() -> void:
	"""End the deathmatch and show results"""
	DebugLogger.dlog(DebugLogger.Category.WORLD, "end_deathmatch() CALLED! Game time was: %.2f seconds" % max(0.0, game_time_remaining))

	# Prevent ending if already ended
	if not game_active and not countdown_active:
		DebugLogger.dlog(DebugLogger.Category.WORLD, "WARNING: Match already ended! Ignoring end_deathmatch() call.")
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
	DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Cleared %d ability pickups from world" % all_abilities.size())

	# Clear ALL orbs (both spawned and dropped by players)
	var all_orbs: Array[Node] = get_tree().get_nodes_in_group("orbs")
	for orb in all_orbs:
		if orb:
			orb.queue_free()
	DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Cleared %d orbs from world" % all_orbs.size())

	# Also tell spawners to clear their tracking arrays
	var ability_spawner: Node = get_node_or_null("AbilitySpawner")
	if ability_spawner and ability_spawner.has_method("clear_all"):
		ability_spawner.clear_all()

	var orb_spawner: Node = get_node_or_null("OrbSpawner")
	if orb_spawner and orb_spawner.has_method("clear_all"):
		orb_spawner.clear_all()

	DebugLogger.dlog(DebugLogger.Category.WORLD, "Deathmatch ended!")

	# Notify CrazyGames SDK that gameplay has stopped
	if CrazyGamesSDK:
		CrazyGamesSDK.gameplay_stop()

	# Stop gameplay music
	if gameplay_music and _music_has_stop:
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
		DebugLogger.dlog(DebugLogger.Category.WORLD, "Winner: Player %d%s with %d points!" % [winner_id, winner_type, highest_score])
	else:
		DebugLogger.dlog(DebugLogger.Category.WORLD, "Match ended - no scores recorded")

	# Show scoreboard for 10 seconds
	var scoreboard: Control = get_node_or_null("Scoreboard")
	if scoreboard and scoreboard.has_method("show_match_end_scoreboard"):
		scoreboard.show_match_end_scoreboard()

	# Release mouse so scoreboard is visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Wait 10 seconds
	await get_tree().create_timer(10.0).timeout

	# Return to lobby if multiplayer, otherwise main menu
	if MultiplayerManager and MultiplayerManager.is_online():
		return_to_multiplayer_lobby()
	else:
		return_to_main_menu()

func return_to_multiplayer_lobby() -> void:
	"""Return to multiplayer lobby after match ends"""
	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Returning to multiplayer lobby...")

	# Hide scoreboard
	var scoreboard: Control = get_node_or_null("Scoreboard")
	if scoreboard and scoreboard.has_method("hide_match_end_scoreboard"):
		scoreboard.hide_match_end_scoreboard()

	# Remove all players (including bots)
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	for player in players:
		player.queue_free()

	# Clear ALL ability pickups
	var all_abilities: Array[Node] = get_tree().get_nodes_in_group("ability_pickups")
	for ability in all_abilities:
		if ability:
			ability.queue_free()

	# Clear ALL orbs
	var all_orbs: Array[Node] = get_tree().get_nodes_in_group("orbs")
	for orb in all_orbs:
		if orb:
			orb.queue_free()

	# Clear spawner tracking
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
	last_time_print = -1

	# Reset mid-round expansion
	expansion_triggered = false

	# Reset bot counter locally (MultiplayerManager keeps its own for lobby)
	bot_counter = 0

	# Hide countdown label and HUD
	if countdown_label:
		countdown_label.visible = false
	if game_hud:
		game_hud.visible = false

	# Wait for cleanup to complete
	await get_tree().process_frame

	# Regenerate map for lobby preview
	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Regenerating map for lobby preview")
	await generate_procedural_level(false)

	# Show the multiplayer lobby (game lobby panel, not main lobby)
	show_multiplayer_lobby(true)

	# Reset player ready status for next match
	if MultiplayerManager:
		MultiplayerManager.set_player_ready(false)
		# MULTIPLAYER SYNC FIX: Host resets ALL players' ready states (including bots)
		# so the lobby correctly shows everyone as not ready for the next match
		if MultiplayerManager.is_host():
			var local_peer_id: int = 1
			if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
				local_peer_id = multiplayer.get_unique_id()
			for peer_id in MultiplayerManager.players.keys():
				if peer_id != local_peer_id:
					MultiplayerManager.players[peer_id].ready = false
			# Re-ready bots since they should always be ready
			for peer_id in MultiplayerManager.players.keys():
				if peer_id >= 9000:
					MultiplayerManager.players[peer_id].ready = true
			MultiplayerManager.player_list_changed.emit()
			# Sync updated player list to all clients
			MultiplayerManager.rpc("receive_player_list", MultiplayerManager.players)
			# Re-sync room settings to clients so lobby displays correctly
			MultiplayerManager.rpc("sync_room_settings", MultiplayerManager.room_settings)

	# Start menu music
	if menu_music:
		menu_music.play()

	# Make sure mouse is visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Returned to multiplayer lobby")

func return_to_main_menu() -> void:
	"""Return to main menu after match ends"""
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Returning to main menu...")

	# Hide scoreboard
	var scoreboard: Control = get_node_or_null("Scoreboard")
	if scoreboard and scoreboard.has_method("hide_match_end_scoreboard"):
		scoreboard.hide_match_end_scoreboard()

	# Remove all players (including bots)
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	for player in players:
		player.queue_free()

	# Clear ALL ability pickups (both spawned and dropped by players)
	var all_abilities2: Array[Node] = get_tree().get_nodes_in_group("ability_pickups")
	for ability in all_abilities2:
		if ability:
			ability.queue_free()
	DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Cleared %d ability pickups from world" % all_abilities2.size())

	# Clear ALL orbs (both spawned and dropped by players)
	var all_orbs2: Array[Node] = get_tree().get_nodes_in_group("orbs")
	for orb in all_orbs2:
		if orb:
			orb.queue_free()
	DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Cleared %d orbs from world" % all_orbs2.size())

	# Also tell spawners to clear their tracking arrays
	var ability_spawner2: Node = get_node_or_null("AbilitySpawner")
	if ability_spawner2 and ability_spawner2.has_method("clear_all"):
		ability_spawner2.clear_all()

	var orb_spawner2: Node = get_node_or_null("OrbSpawner")
	if orb_spawner2 and orb_spawner2.has_method("clear_all"):
		orb_spawner2.clear_all()

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
	if _blur_node:
		_blur_node.hide()

	# Wait a frame for all queue_free() calls to complete
	await get_tree().process_frame

	# Regenerate menu preview level (floor + video walls only)
	DebugLogger.dlog(DebugLogger.Category.UI, "Regenerating menu preview")
	await generate_procedural_level(false, 2, false, true)

	# Recreate marble preview after level regeneration
	DebugLogger.dlog(DebugLogger.Category.WORLD, "[CAMERA] Recreating marble preview for main menu")
	_create_marble_preview()

	# Start menu music
	if menu_music:
		menu_music.play()

	# Make sure mouse is visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	DebugLogger.dlog(DebugLogger.Category.WORLD, "Returned to main menu")

func add_score(player_id: int, points: int = 1) -> void:
	"""Add points to a player's score - syncs across network"""
	# In multiplayer, only authority should initiate score updates
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		# Client - request server to add score
		_request_add_score.rpc_id(1, player_id, points)
		return

	# Server or offline - apply locally and sync to clients
	_apply_score(player_id, points)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_score.rpc(player_id, player_scores.get(player_id, 0))

func _apply_score(player_id: int, points: int) -> void:
	"""Internal: Apply score change locally"""
	if not player_scores.has(player_id):
		player_scores[player_id] = 0
	player_scores[player_id] += points
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Player %d scored! Total: %d" % [player_id, player_scores[player_id]])

@rpc("any_peer", "reliable")
func _request_add_score(player_id: int, points: int) -> void:
	"""RPC: Client requests server to add score"""
	if not multiplayer.is_server():
		return
	add_score(player_id, points)

@rpc("authority", "call_local", "reliable")
func _sync_score(player_id: int, total_score: int) -> void:
	"""RPC: Server syncs score to all clients"""
	player_scores[player_id] = total_score
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Score synced - Player %d: %d" % [player_id, total_score])

func add_death(player_id: int) -> void:
	"""Add a death to a player's death count - syncs across network"""
	# In multiplayer, only authority should initiate death updates
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		# Client - request server to add death
		_request_add_death.rpc_id(1, player_id)
		return

	# Server or offline - apply locally and sync to clients
	_apply_death(player_id)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_death.rpc(player_id, player_deaths.get(player_id, 0))

func _apply_death(player_id: int) -> void:
	"""Internal: Apply death count change locally"""
	if not player_deaths.has(player_id):
		player_deaths[player_id] = 0
	player_deaths[player_id] += 1
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Player %d died! Total deaths: %d" % [player_id, player_deaths[player_id]])

@rpc("any_peer", "reliable")
func _request_add_death(player_id: int) -> void:
	"""RPC: Client requests server to add death"""
	if not multiplayer.is_server():
		return
	add_death(player_id)

@rpc("authority", "call_local", "reliable")
func _sync_death(player_id: int, total_deaths: int) -> void:
	"""RPC: Server syncs death count to all clients"""
	player_deaths[player_id] = total_deaths
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Death synced - Player %d: %d" % [player_id, total_deaths])

@rpc("authority", "reliable")
func _sync_game_timer(time_remaining: float) -> void:
	"""RPC: Host syncs game timer to all clients to prevent drift/desync"""
	# Only accept timer sync if we're not the server (server is authoritative)
	if multiplayer.is_server():
		return
	var drift: float = abs(game_time_remaining - time_remaining)
	if drift > 0.5:
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Game timer synced from host: %.1f (drift was %.1fs)" % [time_remaining, drift])
	game_time_remaining = time_remaining

@rpc("authority", "reliable")
func _sync_end_deathmatch() -> void:
	"""RPC: Host notifies all clients that the match has ended"""
	if multiplayer.is_server():
		return  # Server already called end_deathmatch locally
	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Received match end from host")
	game_time_remaining = 0.0
	end_deathmatch()

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
		DebugLogger.dlog(DebugLogger.Category.AUDIO, "No music found in %s, falling back to res://music" % music_dir)
		songs_loaded = _load_music_from_directory("res://music")

	if songs_loaded > 0:
		DebugLogger.dlog(DebugLogger.Category.AUDIO, "Auto-loaded %d songs from music directory" % songs_loaded)
	elif not OS.has_feature("web"):
		# Only print error for non-HTML5 builds (HTML5 won't have music files in res://)
		DebugLogger.dlog(DebugLogger.Category.AUDIO, "No music files found in either %s or res://music" % music_dir)

func _load_music_from_directory(dir: String) -> int:
	"""Load all music files from a directory and return count of songs loaded"""
	var dir_access: DirAccess = DirAccess.open(dir)
	if not dir_access:
		# Only print error if not HTML5 trying to access non-res:// path
		if not (OS.has_feature("web") and not dir.begins_with("res://")):
			DebugLogger.dlog(DebugLogger.Category.AUDIO, "Failed to open music directory: %s" % dir)
		return 0

	DebugLogger.dlog(DebugLogger.Category.AUDIO, "[MUSIC] Scanning directory: %s" % dir)
	dir_access.list_dir_begin()
	var file_name: String = dir_access.get_next()
	var songs_loaded: int = 0
	var loaded_files: Dictionary = {}  # Track loaded files to prevent duplicates

	while file_name != "":
		if not dir_access.current_is_dir():
			# Determine the actual audio filename (strip .import if present)
			var audio_filename: String = file_name
			if file_name.ends_with(".import"):
				audio_filename = file_name.trim_suffix(".import")

			var ext: String = audio_filename.get_extension().to_lower()

			# Check if it's a supported audio format
			if ext in ["mp3", "ogg", "wav"]:
				# Skip if we've already loaded this audio file
				if loaded_files.has(audio_filename):
					file_name = dir_access.get_next()
					continue

				DebugLogger.dlog(DebugLogger.Category.AUDIO, "[MUSIC] Found audio file: %s" % audio_filename)
				var file_path: String = dir.path_join(audio_filename)
				DebugLogger.dlog(DebugLogger.Category.AUDIO, "[MUSIC] Attempting to load: %s" % file_path)
				var audio_stream: AudioStream = _load_audio_file(file_path, ext)

				if audio_stream and gameplay_music.has_method("add_song"):
					gameplay_music.add_song(audio_stream, file_path)
					songs_loaded += 1
					loaded_files[audio_filename] = true  # Mark as loaded
					DebugLogger.dlog(DebugLogger.Category.AUDIO, "[MUSIC] ✅ Successfully loaded: %s" % audio_filename)
				else:
					DebugLogger.dlog(DebugLogger.Category.AUDIO, "[MUSIC] ❌ Failed to load: %s (stream=%s)" % [audio_filename, "null" if not audio_stream else "exists"])

		file_name = dir_access.get_next()

	dir_access.list_dir_end()

	DebugLogger.dlog(DebugLogger.Category.AUDIO, "[MUSIC] Scan complete. Songs loaded: %d" % songs_loaded)
	return songs_loaded

func _on_music_directory_button_pressed() -> void:
	"""Open file dialog to select music directory"""
	var dialog: FileDialog = get_node_or_null("Menu/MusicDirectoryDialog")
	if dialog:
		dialog.popup_centered()

func _on_music_directory_selected(dir: String) -> void:
	"""Load all music files from selected directory"""
	DebugLogger.dlog(DebugLogger.Category.AUDIO, "Loading music from directory: %s" % dir)

	if not gameplay_music:
		DebugLogger.dlog(DebugLogger.Category.AUDIO, "Error: GameplayMusic node not found")
		return

	# Clear existing playlist
	if gameplay_music.has_method("clear_playlist"):
		gameplay_music.clear_playlist()

	# Load music from selected directory
	var songs_loaded: int = _load_music_from_directory(dir)
	DebugLogger.dlog(DebugLogger.Category.AUDIO, "Music directory loaded: %d songs added to playlist" % songs_loaded)

	# Save this as the new music directory
	Global.music_directory = dir
	Global.save_settings()

func _load_audio_file(file_path: String, extension: String) -> AudioStream:
	"""Load an audio file and return an AudioStream"""
	var audio_stream: AudioStream = null

	# For res:// paths, try ResourceLoader first (for imported files)
	if file_path.begins_with("res://"):
		DebugLogger.dlog(DebugLogger.Category.AUDIO, "[MUSIC] Trying ResourceLoader.load(%s)..." % file_path)
		audio_stream = ResourceLoader.load(file_path)
		if audio_stream:
			DebugLogger.dlog(DebugLogger.Category.AUDIO, "[MUSIC] ✅ ResourceLoader succeeded: %s" % file_path)
			return audio_stream
		else:
			DebugLogger.dlog(DebugLogger.Category.AUDIO, "[MUSIC] ⚠️ ResourceLoader failed for %s, trying FileAccess fallback..." % file_path)
			# Fall through to FileAccess method below

	# For external files (or res:// files that aren't imported), use FileAccess
	DebugLogger.dlog(DebugLogger.Category.AUDIO, "[MUSIC] Trying FileAccess for %s extension..." % extension)
	match extension:
		"mp3":
			var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
			if file:
				DebugLogger.dlog(DebugLogger.Category.AUDIO, "[MUSIC] FileAccess opened successfully, loading MP3 data...")
				var mp3_stream: AudioStreamMP3 = AudioStreamMP3.new()
				mp3_stream.data = file.get_buffer(file.get_length())
				file.close()
				audio_stream = mp3_stream
				DebugLogger.dlog(DebugLogger.Category.AUDIO, "[MUSIC] ✅ MP3 stream created successfully")
			else:
				DebugLogger.dlog(DebugLogger.Category.AUDIO, "[MUSIC] ❌ FileAccess.open failed for: %s" % file_path)

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
		DebugLogger.dlog(DebugLogger.Category.AUDIO, "Warning: Could not load audio file: %s" % file_path)

	return audio_stream

# ============================================================================
# BOT SYSTEM
# ============================================================================

func spawn_bot() -> void:
	"""Spawn an AI-controlled bot player"""
	DebugLogger.dlog(DebugLogger.Category.WORLD, "--- spawn_bot() called ---")
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Bot counter before: %d" % bot_counter)
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Current players in game: %d" % get_tree().get_nodes_in_group("players").size())

	# Check if we're already at max capacity (8 total: 1 player + 7 bots)
	var current_player_count: int = get_tree().get_nodes_in_group("players").size()
	if current_player_count >= 8:
		DebugLogger.dlog(DebugLogger.Category.WORLD, "Cannot spawn bot - max 8 total (1 player + 7 bots) reached!")
		return

	bot_counter += 1
	var bot_id: int = 9000 + bot_counter  # Bot IDs start at 9000

	var bot: Node = Player.instantiate()
	bot.name = str(bot_id)

	# Assign random color to bot
	bot.custom_color_index = randi() % 28  # 28 color schemes available

	add_child(bot)

	# Set arena size multiplier for movement speed scaling
	if bot.has_method("set_arena_size_multiplier"):
		bot.set_arena_size_multiplier(current_arena_multiplier)

	# Update bot spawns from level generator
	if level_generator and level_generator.has_method("get_spawn_points"):
		var spawn_points: PackedVector3Array = level_generator.get_spawn_points()
		if spawn_points.size() > 0:
			bot.spawns = spawn_points
			# Spawn at appropriate position
			var spawn_index: int = bot_id % spawn_points.size()
			bot.global_position = spawn_points[spawn_index]
			DebugLogger.dlog(DebugLogger.Category.WORLD, "Bot %d spawned at position %d: %s" % [bot_id, spawn_index, bot.global_position])

	# Add AI controller to bot (Q3 style only)
	var ai: Node = BotAI_TypeB.new()
	ai.name = "BotAI"
	bot.add_child(ai)
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Added BotAI_TypeB to bot %d" % bot_id)

	# Add bot to players group
	bot.add_to_group("players")

	# Initialize bot score and deaths
	player_scores[bot_id] = 0
	player_deaths[bot_id] = 0

	DebugLogger.dlog(DebugLogger.Category.WORLD, "Spawned bot with ID: %d | Total players now: %d" % [bot_id, get_tree().get_nodes_in_group("players").size()])
	DebugLogger.dlog(DebugLogger.Category.WORLD, "--- spawn_bot() complete ---")

func spawn_pending_bots() -> void:
	"""Spawn all pending bots (called when match becomes active)"""
	DebugLogger.dlog(DebugLogger.Category.WORLD, "spawn_pending_bots() called - spawning %d bots" % pending_bot_count)
	for i in range(pending_bot_count):
		DebugLogger.dlog(DebugLogger.Category.WORLD, "Spawning bot %d of %d" % [i + 1, pending_bot_count])
		spawn_bot()
		# Small delay between spawns for visual effect
		if i < pending_bot_count - 1:  # Don't wait after last bot
			await get_tree().create_timer(0.1).timeout
	DebugLogger.dlog(DebugLogger.Category.WORLD, "All pending bots spawned. Total players: %d" % get_tree().get_nodes_in_group("players").size())

func despawn_all_bots() -> void:
	"""Remove all bot players from the game"""
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	var bots_removed: int = 0

	for player in players:
		if player:
			# Check if this is a bot (ID >= 9000)
			var player_id: int = str(player.name).to_int()
			if player_id >= 9000:
				DebugLogger.dlog(DebugLogger.Category.BOT_AI, "Despawning bot: %s (ID: %d)" % [player.name, player_id])
				# Keep scores/deaths on leaderboard - don't erase them
				# Remove from scene
				player.queue_free()
				bots_removed += 1

	bot_counter = 0
	pending_bot_count = 0
	DebugLogger.dlog(DebugLogger.Category.BOT_AI, "Despawned %d bots. Remaining players: %d" % [bots_removed, get_tree().get_nodes_in_group("players").size() - bots_removed])

func spawn_abilities_and_orbs() -> void:
	"""Trigger spawning of abilities and orbs when match becomes active"""
	# Find and trigger ability spawner
	var ability_spawner3: Node = get_node_or_null("AbilitySpawner")
	if ability_spawner3 and ability_spawner3.has_method("spawn_abilities"):
		ability_spawner3.spawn_abilities()
		DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Triggered ability spawning")

	# Find and trigger orb spawner
	var orb_spawner3: Node = get_node_or_null("OrbSpawner")
	if orb_spawner3 and orb_spawner3.has_method("spawn_orbs"):
		orb_spawner3.spawn_orbs()
		DebugLogger.dlog(DebugLogger.Category.SPAWNERS, "Triggered orb spawning")

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

	DebugLogger.dlog(DebugLogger.Category.UI, "Profile panel created")

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

	DebugLogger.dlog(DebugLogger.Category.UI, "Friends panel created")

func _create_customize_panel() -> void:
	"""Create the customize panel UI following style guide"""
	# Create the panel
	customize_panel = PanelContainer.new()
	customize_panel.name = "CustomizePanel"
	customize_panel.set_script(CustomizePanelScript)

	# Center the panel (700x650px for marble preview + color grid)
	customize_panel.set_anchors_preset(Control.PRESET_CENTER)
	customize_panel.anchor_left = 0.5
	customize_panel.anchor_right = 0.5
	customize_panel.anchor_top = 0.5
	customize_panel.anchor_bottom = 0.5
	customize_panel.offset_left = -350
	customize_panel.offset_right = 350
	customize_panel.offset_top = -325
	customize_panel.offset_bottom = 325
	customize_panel.custom_minimum_size = Vector2(700, 650)

	# Apply panel style from style guide
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0.85)
	panel_style.set_corner_radius_all(12)
	panel_style.border_color = Color(0.3, 0.7, 1, 0.6)
	panel_style.set_border_width_all(3)
	customize_panel.add_theme_stylebox_override("panel", panel_style)

	# 25px margins as per style guide
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 25)
	margin.add_theme_constant_override("margin_right", 25)
	margin.add_theme_constant_override("margin_top", 25)
	margin.add_theme_constant_override("margin_bottom", 25)
	customize_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)

	# Header with title
	var header = HBoxContainer.new()
	header.name = "Header"
	vbox.add_child(header)

	var title_label = Label.new()
	title_label.text = "CUSTOMIZE"
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1, 1))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	# Close button with style
	var close_btn = Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(50, 50)
	_apply_button_style(close_btn, 20)
	close_btn.pressed.connect(_on_customize_panel_close_pressed)
	header.add_child(close_btn)

	# Separator
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Create HBox for preview and colors
	var content_hbox = HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 20)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content_hbox)

	# Left side: Marble Preview using SubViewportContainer
	var preview_container = VBoxContainer.new()
	preview_container.add_theme_constant_override("separation", 10)
	preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(preview_container)

	var preview_label = Label.new()
	preview_label.text = "PREVIEW"
	preview_label.add_theme_font_size_override("font_size", 20)
	preview_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1, 1))
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_container.add_child(preview_label)

	# SubViewportContainer for 3D marble preview
	var viewport_container = SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(280, 280)
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.stretch = true

	# Style the viewport container background
	var viewport_panel = PanelContainer.new()
	var viewport_style = StyleBoxFlat.new()
	viewport_style.bg_color = Color(0.05, 0.05, 0.1, 1)
	viewport_style.set_corner_radius_all(8)
	viewport_style.border_color = Color(0.3, 0.7, 1, 0.4)
	viewport_style.set_border_width_all(2)
	viewport_panel.add_theme_stylebox_override("panel", viewport_style)
	preview_container.add_child(viewport_panel)

	viewport_panel.add_child(viewport_container)

	# Create SubViewport for 3D rendering
	var sub_viewport = SubViewport.new()
	sub_viewport.size = Vector2i(280, 280)
	sub_viewport.transparent_bg = false
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	sub_viewport.own_world_3d = true
	viewport_container.add_child(sub_viewport)

	# Create 3D scene inside SubViewport
	var scene_root = Node3D.new()
	scene_root.name = "PreviewScene"
	sub_viewport.add_child(scene_root)

	# Add WorldEnvironment for proper shader rendering in isolated viewport
	var world_env = WorldEnvironment.new()
	world_env.name = "PreviewWorldEnvironment"
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.1, 1)  # Match viewport panel background
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.5)  # Soft ambient for marble visibility
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 3.6
	world_env.environment = env
	scene_root.add_child(world_env)

	# Create the marble preview mesh
	var marble_mesh = MeshInstance3D.new()
	marble_mesh.name = "PreviewMarble"
	marble_mesh.mesh = SphereMesh.new()
	marble_mesh.mesh.radius = 0.5
	marble_mesh.mesh.height = 1.0
	marble_mesh.mesh.radial_segments = 32
	marble_mesh.mesh.rings = 16
	marble_mesh.position = Vector3(0, 0, 0)
	scene_root.add_child(marble_mesh)

	# Apply initial material to the marble preview immediately (prevents grey sphere)
	marble_mesh.material_override = marble_material_manager.create_marble_material(selected_marble_color_index)

	# Create camera for the preview
	var preview_cam = Camera3D.new()
	preview_cam.name = "PreviewCamera"
	preview_cam.position = Vector3(0, 0.3, 1.8)
	scene_root.add_child(preview_cam)
	preview_cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	preview_cam.current = true

	# Create lighting for the preview
	var light = DirectionalLight3D.new()
	light.name = "PreviewLight"
	light.position = Vector3(2, 3, 2)
	light.light_energy = 0.85
	scene_root.add_child(light)
	light.look_at(Vector3(0, 0, 0), Vector3.UP)

	# Add ambient light
	var ambient_light = DirectionalLight3D.new()
	ambient_light.name = "AmbientLight"
	ambient_light.position = Vector3(-2, 1, -2)
	ambient_light.light_energy = 0.22
	scene_root.add_child(ambient_light)
	ambient_light.look_at(Vector3(0, 0, 0), Vector3.UP)

	# Store references in the panel script
	customize_panel.preview_viewport = sub_viewport
	customize_panel.preview_marble_mesh = marble_mesh
	customize_panel.preview_camera = preview_cam
	customize_panel.preview_light = light

	# Color name label
	var color_name = Label.new()
	color_name.name = "ColorName"
	color_name.text = "Ruby Red"
	color_name.add_theme_font_size_override("font_size", 18)
	color_name.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	color_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_container.add_child(color_name)
	customize_panel.color_name_label = color_name

	# Right side: Color selection grid
	var colors_container = VBoxContainer.new()
	colors_container.add_theme_constant_override("separation", 10)
	colors_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(colors_container)

	var colors_label = Label.new()
	colors_label.text = "COLORS"
	colors_label.add_theme_font_size_override("font_size", 20)
	colors_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1, 1))
	colors_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	colors_container.add_child(colors_label)

	# Scroll container for color grid (in case there are many colors)
	var color_scroll = ScrollContainer.new()
	color_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	color_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	colors_container.add_child(color_scroll)

	# Color grid (6 columns x 5 rows = 30 slots, we have 27 colors)
	var color_grid = GridContainer.new()
	color_grid.name = "ColorGrid"
	color_grid.columns = 5
	color_grid.add_theme_constant_override("h_separation", 8)
	color_grid.add_theme_constant_override("v_separation", 8)
	color_scroll.add_child(color_grid)
	customize_panel.color_grid = color_grid

	# Set up the color grid with buttons
	customize_panel.setup_color_grid()

	# Initialize with saved color preference
	customize_panel.set_selected_color(selected_marble_color_index)

	# Set mouse filter to stop clicks from going through
	customize_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Connect close button reference
	customize_panel.close_button = close_btn

	# Add panel to Menu CanvasLayer (same as options_menu and pause_menu)
	if has_node("Menu"):
		get_node("Menu").add_child(customize_panel)
	else:
		add_child(customize_panel)

	# Start hidden
	customize_panel.visible = false

	# Connect color selected signal to update player's preference
	customize_panel.color_selected.connect(_on_marble_color_selected)

	DebugLogger.dlog(DebugLogger.Category.UI, "Customize panel created")

func _on_customize_panel_close_pressed() -> void:
	"""Handle customize panel close"""
	if customize_panel:
		customize_panel.hide()
		if customize_panel.preview_viewport:
			customize_panel.preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if main_menu:
		main_menu.show()
	# Hide blur
	if _blur_node:
		_blur_node.hide()

func _on_marble_color_selected(color_index: int) -> void:
	"""Handle marble color selection - store player preference"""
	DebugLogger.dlog(DebugLogger.Category.UI, "Marble color selected: %d" % color_index)
	# Store the selected color for spawning (both locally and in Global for persistence)
	selected_marble_color_index = color_index
	Global.marble_color_index = color_index
	Global.save_settings()

	# Update main menu marble preview with new color
	if marble_preview and is_instance_valid(marble_preview):
		var material = marble_material_manager.create_marble_material(color_index)
		marble_preview.material_override = material
		DebugLogger.dlog(DebugLogger.Category.UI, "Updated main menu preview with color: %d" % color_index)

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
		DebugLogger.dlog(DebugLogger.Category.WORLD, "Ground found at: %s" % ground_position)
	else:
		DebugLogger.dlog(DebugLogger.Category.WORLD, "No ground found, using default position")

	# Instantiate an actual player marble
	var marble = Player.instantiate()
	marble.name = "PreviewMarble"
	# Position marble on ground (add 0.5 for marble radius so it sits on top)
	marble.position = ground_position + Vector3(0, 0.5, 0)

	# Disable physics and input for preview (it's just for display)
	if marble is RigidBody3D:
		marble.freeze = true  # Freeze physics
		marble.process_mode = Node.PROCESS_MODE_DISABLED  # Completely disable processing
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

	# Set the saved color before adding to tree (so _ready uses correct color)
	marble.custom_color_index = selected_marble_color_index

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
	preview_light.light_energy = 0.85
	preview_light.rotation_degrees = Vector3(-45, 45, 0)
	preview_light.shadow_enabled = true
	preview_container.add_child(preview_light)

	# Add an additional fill light for better showcase
	var fill_light = OmniLight3D.new()
	fill_light.name = "FillLight"
	fill_light.light_energy = 0.12
	fill_light.position = Vector3(2, 1, 2)
	preview_container.add_child(fill_light)

	# Add to World root (Menu is a CanvasLayer for UI, can't hold 3D nodes)
	add_child(preview_container)

	DebugLogger.dlog(DebugLogger.Category.UI, "Marble preview created")

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
	DebugLogger.dlog(DebugLogger.Category.AUDIO, "[HTML5] Attempted to resume AudioContext")

func _on_profile_panel_close_pressed() -> void:
	"""Handle profile panel close button pressed"""
	if profile_panel:
		profile_panel.hide()
	# Hide blur when closing panel
	if _blur_node:
		_blur_node.hide()
	if main_menu:
		main_menu.show()

func _on_friends_panel_close_pressed() -> void:
	"""Handle friends panel close button pressed"""
	if friends_panel:
		friends_panel.hide()
	# Hide blur when closing panel
	if _blur_node:
		_blur_node.hide()
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
		DebugLogger.dlog(DebugLogger.Category.AUDIO, "Created countdown sound player (no audio file loaded)")

	DebugLogger.dlog(DebugLogger.Category.UI, "Countdown UI created")

func update_countdown_display() -> void:
	if not countdown_label:
		return
	var new_text: String = "READY" if countdown_time > 1.0 else "GO!"
	if countdown_label.text == new_text:
		return
	var prev_text: String = countdown_label.text
	countdown_label.text = new_text
	if countdown_time > 1.0:
		countdown_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		countdown_label.add_theme_color_override("font_color", Color.GREEN)

	# Play sound when text changes
	if prev_text != new_text and countdown_sound:
		play_countdown_beep(new_text)

func play_countdown_beep(text: String) -> void:
	"""Play a procedural beep sound for countdown"""
	if not countdown_sound:
		return

	# Generate procedural sound
	var audio_stream = AudioStreamGenerator.new()
	audio_stream.mix_rate = 22050.0
	audio_stream.buffer_length = 0.2  # 200ms buffer

	countdown_sound.stream = audio_stream
	countdown_sound.volume_db = -5.0

	# Different pitches for READY vs GO
	if text == "READY":
		countdown_sound.pitch_scale = 0.8  # Lower pitch for READY
	elif text == "GO!":
		countdown_sound.pitch_scale = 1.3  # Higher pitch for GO

	countdown_sound.play()

	# Generate the tone
	var playback: AudioStreamGeneratorPlayback = countdown_sound.get_stream_playback()
	if playback:
		var frequency = 600.0 if text == "READY" else 900.0  # Different frequencies
		var sample_hz = audio_stream.mix_rate
		var pulse_hz = frequency
		var samples_to_fill = int(sample_hz * 0.15)  # 150ms of audio

		for i in range(samples_to_fill):
			var phase = float(i) / sample_hz * pulse_hz * TAU
			var amplitude = 0.4 * (1.0 - float(i) / samples_to_fill)  # Fade out
			var value = sin(phase) * amplitude
			playback.push_frame(Vector2(value, value))

func _apply_prebaked_lighting_profile(menu_preview: bool) -> void:
	## Simple static lighting profile to emulate pre-baked feel (minimal dynamic sun influence).
	var world_env: WorldEnvironment = get_node_or_null("WorldEnvironment")
	if world_env:
		var env: Environment = world_env.environment
		if not env:
			env = Environment.new()
			world_env.environment = env
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.56, 0.56, 0.56)
		env.ambient_light_energy = 0.42
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_white = 2.6

	var sun_light: DirectionalLight3D = get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun_light:
		sun_light.light_energy = 0.22
		sun_light.light_indirect_energy = 0.15
		sun_light.shadow_enabled = false

# ============================================================================
# PROCEDURAL LEVEL GENERATION
# ============================================================================

func generate_procedural_level(spawn_collectibles: bool = true, level_size: int = 2, video_walls: bool = false, menu_preview: bool = false, level_seed: int = 0, music_walls: bool = false) -> void:
	"""Generate a procedural Q3-style level with skybox
	Args:
		spawn_collectibles: Whether to spawn abilities and orbs (false for menu preview)
		level_size: 1=Small, 2=Medium, 3=Large, 4=Huge (affects arena_size AND complexity)
		video_walls: Enable video on perimeter walls
		menu_preview: If true, only generates floor + video walls for main menu background
		level_seed: Seed for level generation (0 = random, use same seed for multiplayer sync)
		music_walls: Enable WMP9-style music visualizer on walls
	"""
	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Generating level - size: %d, spawn_collectibles: %s, video_walls: %s, music_walls: %s, menu_preview: %s, seed: %d" % [level_size, spawn_collectibles, video_walls, music_walls, menu_preview, level_seed])

	# Size multipliers for arena dimensions
	var arena_multipliers: Dictionary = {
		1: 1.0,   # Small - compact arena
		2: 1.1,   # Medium - standard arena (default)
		3: 1.2,   # Large - significantly expanded
		4: 1.3    # Huge - massive arena
	}
	var arena_mult: float = arena_multipliers.get(level_size, 1.0)
	current_arena_multiplier = arena_mult  # Store for player speed scaling

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

	# Create Q3-style level generator
	level_generator = Node3D.new()
	level_generator.name = "LevelGenerator"
	level_generator.set_script(LevelGeneratorQ3)
	level_generator.arena_size = 140.0 * arena_mult
	level_generator.complexity = level_size
	level_generator.level_seed = level_seed  # Set seed for deterministic generation (0 = random)
	# Pre-baked lighting approach: rely on static world lighting profile, not generated dynamic light grids.
	level_generator.generate_lights = false

	# Configure video walls if enabled
	if video_walls:
		level_generator.enable_video_walls = true
		DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Video walls enabled")

	# Configure music walls if enabled (mutually exclusive with video walls)
	if music_walls and not video_walls:
		level_generator.enable_visualizer_walls = true
		DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Music visualizer walls enabled")

	# Menu preview mode: only floor + video walls
	if menu_preview:
		level_generator.menu_preview_mode = true
		DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Menu preview mode enabled")

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Using Q3 Arena-style level generator (arena_size: %.1f, complexity: %d)" % [level_generator.arena_size, level_generator.complexity])

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
	skybox_generator.menu_static_mode = true
	skybox_generator.menu_static_palette = 1
	add_child(skybox_generator)
	await get_tree().process_frame

	_apply_prebaked_lighting_profile(menu_preview)

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Procedural level generation complete!")

func update_player_spawns() -> void:
	"""Update all player spawn points from generated level"""
	if not level_generator or not level_generator.has_method("get_spawn_points"):
		return

	var new_spawns: PackedVector3Array = level_generator.get_spawn_points()
	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Updating player spawns: %d spawn points" % new_spawns.size())

	# Update all existing players
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	for player in players:
		if "spawns" in player:
			player.spawns = new_spawns
		# Update arena size multiplier for movement speed scaling
		if player.has_method("set_arena_size_multiplier"):
			player.set_arena_size_multiplier(current_arena_multiplier)
		DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Updated spawns and arena size for player: %s" % player.name)

func _on_track_started(metadata: Dictionary) -> void:
	"""Called when a new music track starts playing"""
	if music_notification and music_notification.has_method("show_notification"):
		music_notification.show_notification(metadata)

func _on_track_skip_requested() -> void:
	"""Called when user requests to skip to next track"""
	if gameplay_music and gameplay_music.has_method("next_track"):
		gameplay_music.next_track()

func _on_track_prev_requested() -> void:
	"""Called when user requests to go to previous track"""
	if gameplay_music and gameplay_music.has_method("previous_track"):
		gameplay_music.previous_track()

# ============================================================================
# MID-ROUND EXPANSION SYSTEM
# ============================================================================

func trigger_mid_round_expansion() -> void:
	"""Trigger the mid-round expansion - show notification, spawn new area, connect with rail"""
	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "TRIGGERING MID-ROUND EXPANSION!")

	expansion_triggered = true

	# Show notification in HUD
	if game_hud and game_hud.has_method("show_expansion_notification"):
		game_hud.show_expansion_notification()

	# Calculate position for secondary arena (1000 feet = 304.8 meters away)
	var expansion_offset: Vector3 = Vector3(304.8, 0, 0)  # 1000 feet to the right

	# Wait 1 second for dramatic effect
	await get_tree().create_timer(1.0).timeout

	# Generate secondary arena
	if level_generator and level_generator.has_method("generate_secondary_map"):
		level_generator.generate_secondary_map(expansion_offset)
		DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Secondary arena generated at offset: %s" % expansion_offset)

		# Apply textures to new platforms (only new ones, not regenerating entire map)
		if level_generator.has_method("apply_procedural_textures"):
			level_generator.apply_procedural_textures()

		# Generate connecting rail from main arena to secondary arena
		var start_rail_pos: Vector3 = Vector3(60, 5, 0)  # Edge of main arena
		var end_rail_pos: Vector3 = expansion_offset + Vector3(-60, 5, 0)  # Edge of secondary arena

		if level_generator.has_method("generate_connecting_rail"):
			level_generator.generate_connecting_rail(start_rail_pos, end_rail_pos)
			DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Connecting rail generated!")

	# Showcase the new arena with a dolly camera
	await showcase_new_arena(expansion_offset)

	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "MID-ROUND EXPANSION COMPLETE!")

func showcase_new_arena(arena_position: Vector3) -> void:
	"""Temporarily show all players the new arena with a dolly camera"""
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Starting arena showcase...")

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

	DebugLogger.dlog(DebugLogger.Category.WORLD, "FREEZING %d PLAYERS FOR SHOWCASE" % players.size())

	for player in players:
		var state: Dictionary = {}

		DebugLogger.dlog(DebugLogger.Category.WORLD, "Storing state for player: %s" % player.name)

		# Store position and transform
		if player is Node3D:
			state["position"] = player.global_position
			state["rotation"] = player.global_rotation
			state["visible"] = player.visible

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

		# Freeze player physics (RigidBody3D)
		if player is RigidBody3D:
			state["original_freeze"] = player.freeze
			state["original_linear_velocity"] = player.linear_velocity
			state["original_angular_velocity"] = player.angular_velocity
			player.freeze = true
			player.linear_velocity = Vector3.ZERO
			player.angular_velocity = Vector3.ZERO

		# Disable player input processing
		state["original_process_mode"] = player.process_mode
		player.set_process_input(false)
		player.set_process_unhandled_input(false)

		player_states[player] = state

	DebugLogger.dlog(DebugLogger.Category.WORLD, "All players frozen and stored")

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
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		local_player_id = multiplayer.get_unique_id()
	var local_player_name: String = str(local_player_id)
	DebugLogger.dlog(DebugLogger.Category.WORLD, "Identifying local player: %s" % local_player_name)

	# Restore all player states
	for player in player_states.keys():
		if not is_instance_valid(player):
			DebugLogger.dlog(DebugLogger.Category.WORLD, "Warning: Player instance invalid during restoration")
			continue

		var state: Dictionary = player_states[player]
		var is_local_player: bool = (player.name == local_player_name)

		DebugLogger.dlog(DebugLogger.Category.WORLD, "Restoring player: %s (is_local: %s)" % [player.name, is_local_player])

		# Restore position and visibility
		if player is Node3D:
			if state.has("position"):
				player.global_position = state["position"]
			if state.has("rotation"):
				player.global_rotation = state["rotation"]
			if state.has("visible"):
				player.visible = state["visible"]

		# Unfreeze player physics FIRST
		if player is RigidBody3D and state.has("original_freeze"):
			player.freeze = state["original_freeze"]
			# Ensure player is not stuck
			if not player.freeze:
				player.linear_velocity = Vector3.ZERO
				player.angular_velocity = Vector3.ZERO

		# Re-enable player input processing
		player.set_process_input(true)
		player.set_process_unhandled_input(true)
		player.set_process(true)
		player.set_physics_process(true)

		# Ensure all child meshes are visible
		for child in player.get_children():
			if child is MeshInstance3D:
				child.visible = true

		# Restore camera - ALWAYS restore for local player (do this LAST)
		if state.has("camera") and is_instance_valid(state["camera"]):
			var camera = state["camera"]

			# First restore CameraArm position (it has top_level = true)
			if state.has("camera_arm") and is_instance_valid(state["camera_arm"]):
				var camera_arm = state["camera_arm"]
				if state.has("camera_arm_position"):
					camera_arm.global_position = state["camera_arm_position"]
				if state.has("camera_arm_rotation"):
					camera_arm.global_rotation = state["camera_arm_rotation"]

			# Then restore camera's local transform (position relative to CameraArm)
			if state.has("camera_transform"):
				camera.transform = state["camera_transform"]
			elif state.has("camera_position") and state.has("camera_rotation"):
				camera.position = state["camera_position"]
				camera.rotation = state["camera_rotation"]

			# Always activate camera for local player
			if is_local_player:
				camera.current = true
				# Force camera to update its transform
				camera.force_update_transform()
				DebugLogger.dlog(DebugLogger.Category.WORLD, "Restored camera for LOCAL player: %s" % player.name)
			elif state.get("was_current", false):
				camera.current = true
				camera.force_update_transform()

	# Wait another frame to ensure everything is properly restored
	await get_tree().process_frame

	DebugLogger.dlog(DebugLogger.Category.WORLD, "Arena showcase complete - control returned to players")
