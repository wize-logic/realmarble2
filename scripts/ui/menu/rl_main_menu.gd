extends Control
class_name RLMainMenu

## Rocket League-style main menu positioned in bottom left

signal practice_pressed
signal multiplayer_pressed
signal item_shop_pressed
signal garage_pressed
signal profile_pressed
signal friends_pressed
signal options_pressed
signal quit_pressed

@onready var main_buttons_container: VBoxContainer = $BottomLeftMenu/MarginContainer/VBoxContainer/MenuButtons
@onready var submenu_buttons_container: VBoxContainer = $PlaySubmenu/MarginContainer/VBoxContainer/SubmenuButtons
@onready var play_submenu: PanelContainer = $PlaySubmenu
@onready var player_name_label: Label = $BottomLeftMenu/MarginContainer/VBoxContainer/PlayerInfo/VBox/PlayerName
@onready var player_level_label: Label = $BottomLeftMenu/MarginContainer/VBoxContainer/PlayerInfo/VBox/Level
@onready var music_notification: PanelContainer = $BottomRight/MusicNotification
@onready var track_title_label: Label = $BottomRight/MusicNotification/MarginContainer/VBoxOuter/HBox/VBox/TrackTitle
@onready var track_artist_label: Label = $BottomRight/MusicNotification/MarginContainer/VBoxOuter/HBox/VBox/TrackArtist
@onready var album_art_rect: TextureRect = $BottomRight/MusicNotification/MarginContainer/VBoxOuter/HBox/AlbumArt
@onready var hover_sound: AudioStreamPlayer = $HoverSound
@onready var select_sound: AudioStreamPlayer = $SelectSound

var menu_buttons: Array[RLMenuButton] = []
var submenu_buttons: Array[RLMenuButton] = []
var current_focus_index: int = 0
var in_submenu: bool = false

# Music notification state
var music_notification_tween: Tween
var music_notification_visible: bool = false
var placeholder_texture: ImageTexture

func _ready() -> void:
	# Generate placeholder sounds
	generate_sounds()

	# Collect menu buttons
	collect_buttons()

	# Set up button sounds
	for button in menu_buttons:
		button.set_sounds(hover_sound, select_sound)
	for button in submenu_buttons:
		button.set_sounds(hover_sound, select_sound)

	# Focus first button
	if menu_buttons.size() > 0:
		focus_button(0)

	# Set up player card
	setup_player_card()

	# Initially hide submenu and music notification
	if play_submenu:
		play_submenu.visible = false
	if music_notification:
		music_notification.modulate.a = 0.0
		music_notification.visible = false

	# Create placeholder texture for album art
	_create_placeholder_texture()

func generate_sounds() -> void:
	const SoundGen = preload("res://scripts/ui/menu/sound_generator.gd")
	if hover_sound:
		hover_sound.stream = SoundGen.generate_hover_sound()
	if select_sound:
		select_sound.stream = SoundGen.generate_select_sound()

func _unhandled_input(event: InputEvent) -> void:
	# Only process input if menu is visible
	if not visible:
		return

	if event.is_action_pressed("ui_down"):
		navigate_down()
		accept_event()
	elif event.is_action_pressed("ui_up"):
		navigate_up()
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		activate_current_button()
		accept_event()
	elif event.is_action_pressed("ui_cancel"):
		if in_submenu:
			hide_submenu()
			accept_event()

func collect_buttons() -> void:
	menu_buttons.clear()
	print("Collecting main menu buttons...")
	for child in main_buttons_container.get_children():
		print("  Found child: ", child.name, " (type: ", child.get_class(), ")")
		if child is RLMenuButton:
			menu_buttons.append(child)
			child.button_pressed.connect(_on_main_button_pressed.bind(child))
			print("  Added button: ", child.name)
	print("Total main menu buttons: ", menu_buttons.size())

	submenu_buttons.clear()
	print("Collecting submenu buttons...")
	for child in submenu_buttons_container.get_children():
		print("  Found submenu child: ", child.name, " (type: ", child.get_class(), ")")
		if child is RLMenuButton:
			submenu_buttons.append(child)
			child.button_pressed.connect(_on_submenu_button_pressed.bind(child))
			print("  Added submenu button: ", child.name)
	print("Total submenu buttons: ", submenu_buttons.size())

func navigate_down() -> void:
	var buttons: Array[RLMenuButton] = submenu_buttons if in_submenu else menu_buttons
	if buttons.size() == 0:
		return
	if current_focus_index >= 0 and current_focus_index < buttons.size():
		buttons[current_focus_index].focus_exited()
	current_focus_index = (current_focus_index + 1) % buttons.size()
	focus_button(current_focus_index)

func navigate_up() -> void:
	var buttons: Array[RLMenuButton] = submenu_buttons if in_submenu else menu_buttons
	if buttons.size() == 0:
		return
	if current_focus_index >= 0 and current_focus_index < buttons.size():
		buttons[current_focus_index].focus_exited()
	current_focus_index = (current_focus_index - 1 + buttons.size()) % buttons.size()
	focus_button(current_focus_index)

func focus_button(index: int) -> void:
	var buttons: Array[RLMenuButton] = submenu_buttons if in_submenu else menu_buttons
	if index >= 0 and index < buttons.size():
		current_focus_index = index
		buttons[index].focus_entered()

func activate_current_button() -> void:
	var buttons: Array[RLMenuButton] = submenu_buttons if in_submenu else menu_buttons
	if current_focus_index >= 0 and current_focus_index < buttons.size():
		buttons[current_focus_index]._activate()

func _on_main_button_pressed(button: RLMenuButton) -> void:
	print("Main button pressed: ", button.name)
	match button.name:
		"PlayButton":
			print("Showing submenu")
			show_submenu()
		"ItemShopButton":
			item_shop_pressed.emit()
		"GarageButton":
			garage_pressed.emit()
		"ProfileButton":
			profile_pressed.emit()
		"FriendsButton":
			friends_pressed.emit()
		"OptionsButton":
			options_pressed.emit()
		"QuitButton":
			quit_pressed.emit()

func _on_submenu_button_pressed(button: RLMenuButton) -> void:
	match button.name:
		"PracticeButton":
			practice_pressed.emit()
			hide_submenu()
		"MultiplayerButton":
			multiplayer_pressed.emit()
			hide_submenu()
		"BackButton":
			hide_submenu()

func show_submenu() -> void:
	print("show_submenu called")
	in_submenu = true
	if play_submenu:
		print("Setting play_submenu visible")
		play_submenu.visible = true
		print("Submenu is now visible: ", play_submenu.visible)

	# Clear focus from main menu
	if current_focus_index >= 0 and current_focus_index < menu_buttons.size():
		menu_buttons[current_focus_index].focus_exited()

	# Focus first submenu button
	current_focus_index = 0
	if submenu_buttons.size() > 0:
		print("Focusing first submenu button")
		submenu_buttons[0].focus_entered()
	else:
		print("No submenu buttons found!")

func hide_submenu() -> void:
	in_submenu = false
	if play_submenu:
		play_submenu.visible = false

	# Clear focus from submenu
	if current_focus_index >= 0 and current_focus_index < submenu_buttons.size():
		submenu_buttons[current_focus_index].focus_exited()

	# Focus first main menu button
	current_focus_index = 0
	if menu_buttons.size() > 0:
		menu_buttons[0].focus_entered()

func setup_player_card() -> void:
	if player_name_label:
		player_name_label.text = "Player"
	if player_level_label:
		player_level_label.text = "Level 25"

func _create_placeholder_texture() -> void:
	"""Create a simple placeholder for songs without album art"""
	var img := Image.create(50, 50, false, Image.FORMAT_RGBA8)

	# Fill with gradient background
	for y in range(50):
		for x in range(50):
			var gradient := float(y) / 50.0
			var color := Color(0.15 + gradient * 0.1, 0.15 + gradient * 0.08, 0.2 + gradient * 0.1, 1.0)
			img.set_pixel(x, y, color)

	# Draw simple music note
	var note_color := Color(0.5, 0.5, 0.6, 1.0)
	for y in range(28, 36):
		for x in range(18, 28):
			var dx := x - 23
			var dy := y - 32
			if dx * dx + dy * dy <= 20:
				img.set_pixel(x, y, note_color)
	for y in range(15, 32):
		for x in range(26, 29):
			img.set_pixel(x, y, note_color)

	placeholder_texture = ImageTexture.create_from_image(img)

func show_music_notification(track_title: String, artist: String, album_art: Texture2D = null) -> void:
	"""Show music notification with proper tween animation"""
	if not music_notification or not track_title_label or not track_artist_label:
		return

	# Cancel any existing tween
	if music_notification_tween and music_notification_tween.is_valid():
		music_notification_tween.kill()

	# Cap text length for display
	if track_title.length() > 35:
		track_title_label.text = track_title.substr(0, 35) + "..."
	else:
		track_title_label.text = track_title

	if artist.length() > 30:
		track_artist_label.text = artist.substr(0, 30) + "..."
	else:
		track_artist_label.text = artist if not artist.is_empty() else "Unknown Artist"

	# Set album art if available
	if album_art_rect:
		if album_art and album_art is Texture2D:
			album_art_rect.texture = album_art
		elif placeholder_texture:
			album_art_rect.texture = placeholder_texture

	# Show and animate
	music_notification.visible = true
	music_notification_visible = true

	music_notification_tween = create_tween()
	music_notification_tween.set_ease(Tween.EASE_OUT)
	music_notification_tween.set_trans(Tween.TRANS_CUBIC)

	# Fade in
	music_notification_tween.tween_property(music_notification, "modulate:a", 1.0, 0.4)
	# Hold for display
	music_notification_tween.tween_interval(4.5)
	# Fade out
	music_notification_tween.set_ease(Tween.EASE_IN)
	music_notification_tween.tween_property(music_notification, "modulate:a", 0.0, 0.4)
	# Hide when done
	music_notification_tween.tween_callback(_on_music_notification_finished)

func show_music_notification_with_metadata(metadata: Dictionary) -> void:
	"""Show music notification using metadata dictionary (for integration with music player)"""
	var title: String = metadata.get("title", "Unknown Track")
	var artist: String = metadata.get("artist", "")
	var album_art: Texture2D = metadata.get("album_art", null)
	show_music_notification(title, artist, album_art)

func hide_music_notification() -> void:
	"""Immediately hide the music notification"""
	if not music_notification_visible:
		return

	if music_notification_tween and music_notification_tween.is_valid():
		music_notification_tween.kill()

	music_notification_tween = create_tween()
	music_notification_tween.set_ease(Tween.EASE_IN)
	music_notification_tween.set_trans(Tween.TRANS_CUBIC)
	music_notification_tween.tween_property(music_notification, "modulate:a", 0.0, 0.2)
	music_notification_tween.tween_callback(_on_music_notification_finished)

func _on_music_notification_finished() -> void:
	"""Called when music notification animation completes"""
	if music_notification:
		music_notification.visible = false
	music_notification_visible = false
