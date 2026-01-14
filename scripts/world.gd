extends Node

# UI References
@onready var main_menu: PanelContainer = $Menu/MainMenu if has_node("Menu/MainMenu") else null
@onready var options_menu: PanelContainer = $Menu/Options if has_node("Menu/Options") else null
@onready var pause_menu: PanelContainer = $Menu/PauseMenu if has_node("Menu/PauseMenu") else null
@onready var address_entry: LineEdit = get_node_or_null("%AddressEntry")
@onready var menu_music: AudioStreamPlayer = get_node_or_null("%MenuMusic")
@onready var gameplay_music: Node = get_node_or_null("GameplayMusic")
@onready var music_notification: Control = get_node_or_null("MusicNotification/NotificationUI")

# Multiplayer UI
var lobby_ui: Control = null
const LobbyUI = preload("res://lobby_ui.tscn")

# Countdown UI (created dynamically)
var countdown_label: Label = null
var countdown_sound: AudioStreamPlayer = null

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
var countdown_active: bool = false
var countdown_time: float = 0.0

# Bot system
var bot_counter: int = 0
const BotAI = preload("res://scripts/bot_ai.gd")

# Debug menu
const DebugMenu = preload("res://debug_menu.tscn")

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

	# Initialize lobby UI
	lobby_ui = LobbyUI.instantiate()
	add_child(lobby_ui)
	lobby_ui.visible = false  # Hidden by default

	# Connect multiplayer manager signals
	if MultiplayerManager:
		MultiplayerManager.player_connected.connect(_on_multiplayer_player_connected)
		MultiplayerManager.player_disconnected.connect(_on_multiplayer_player_disconnected)

	# Create countdown UI
	create_countdown_ui()

	# Connect music notification
	if gameplay_music and music_notification and gameplay_music.has_signal("track_started"):
		gameplay_music.track_started.connect(_on_track_started)

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
			countdown_active = false
			game_active = true
			if countdown_label:
				countdown_label.visible = false
			print("GO! Match started!")

	# Handle deathmatch timer
	if game_active:
		game_time_remaining -= delta
		if game_time_remaining <= 0:
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

func _on_practice_button_pressed() -> void:
	"""Start practice mode with bots"""
	if main_menu:
		main_menu.hide()
	if has_node("Menu/DollyCamera"):
		$Menu/DollyCamera.hide()
	if has_node("Menu/Blur"):
		$Menu/Blur.hide()
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

	# Spawn some bots for practice
	for i in range(3):
		await get_tree().create_timer(0.5).timeout
		spawn_bot()

	# Start the deathmatch
	start_deathmatch()

func _on_host_button_pressed() -> void:
	if main_menu:
		main_menu.hide()
	if has_node("Menu/DollyCamera"):
		$Menu/DollyCamera.hide()
	if has_node("Menu/Blur"):
		$Menu/Blur.hide()
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

	# Initialize player score
	player_scores[peer_id] = 0

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
		# Hide blur and camera
		if has_node("Menu/Blur"):
			$Menu/Blur.hide()
		if has_node("Menu/DollyCamera"):
			$Menu/DollyCamera.hide()
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
	# Show blur and camera
	if has_node("Menu/Blur"):
		$Menu/Blur.show()
	if has_node("Menu/DollyCamera"):
		$Menu/DollyCamera.show()

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
	game_active = false  # Don't start until countdown finishes
	game_time_remaining = 300.0
	player_scores.clear()

	# Start countdown
	countdown_active = true
	countdown_time = 3.0  # 3 seconds: "READY" (1s), "SET" (1s), "GO!" (1s)
	if countdown_label:
		countdown_label.visible = true
	print("Starting countdown...")

func end_deathmatch() -> void:
	"""End the deathmatch and show results"""
	game_active = false
	print("Deathmatch ended!")

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

	# TODO: Display winner screen UI

func add_score(player_id: int, points: int = 1) -> void:
	"""Add points to a player's score"""
	if not player_scores.has(player_id):
		player_scores[player_id] = 0
	player_scores[player_id] += points
	print("Player %d scored! Total: %d" % [player_id, player_scores[player_id]])

func get_score(player_id: int) -> int:
	"""Get a player's current score"""
	return player_scores.get(player_id, 0)

func get_time_remaining_formatted() -> String:
	"""Get formatted time string (MM:SS)"""
	var minutes: int = int(game_time_remaining) / 60
	var seconds: int = int(game_time_remaining) % 60
	return "%02d:%02d" % [minutes, seconds]

# ============================================================================
# MUSIC DIRECTORY FUNCTIONS
# ============================================================================

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

	# Scan directory for music files
	var dir_access: DirAccess = DirAccess.open(dir)
	if not dir_access:
		print("Error: Could not open directory %s" % dir)
		return

	dir_access.list_dir_begin()
	var file_name: String = dir_access.get_next()
	var songs_loaded: int = 0

	while file_name != "":
		if not dir_access.current_is_dir():
			var ext: String = file_name.get_extension().to_lower()

			# Check if it's a supported audio format
			if ext in ["mp3", "ogg", "wav"]:
				var file_path: String = dir.path_join(file_name)
				var audio_stream: AudioStream = _load_audio_file(file_path, ext)

				if audio_stream and gameplay_music.has_method("add_song"):
					gameplay_music.add_song(audio_stream)
					songs_loaded += 1
					print("Loaded: %s" % file_name)

		file_name = dir_access.get_next()

	dir_access.list_dir_end()
	print("Music directory loaded: %d songs added to playlist" % songs_loaded)

func _load_audio_file(file_path: String, extension: String) -> AudioStream:
	"""Load an audio file and return an AudioStream"""
	var audio_stream: AudioStream = null

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

	# Add AI controller to bot
	var ai: Node = BotAI.new()
	ai.name = "BotAI"
	bot.add_child(ai)

	# Add bot to players group
	bot.add_to_group("players")

	# Initialize bot score
	player_scores[bot_id] = 0

	print("Spawned bot with ID: %d" % bot_id)

# ============================================================================
# COUNTDOWN SYSTEM
# ============================================================================

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

func _on_track_started(track_name: String) -> void:
	"""Called when a new music track starts playing"""
	if music_notification and music_notification.has_method("show_notification"):
		music_notification.show_notification("♪ " + track_name)
