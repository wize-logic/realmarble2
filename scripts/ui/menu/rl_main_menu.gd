extends Control
class_name RLMainMenu

## True Rocket League-style main menu with left sidebar

signal play_pressed
signal item_shop_pressed
signal garage_pressed
signal profile_pressed
signal options_pressed
signal quit_pressed
signal multiplayer_pressed

@onready var buttons_container: VBoxContainer = $LeftSidebar/MenuButtons
@onready var player_card: Control = $BottomLeft/PlayerCard
@onready var player_name_label: Label = $BottomLeft/PlayerCard/PlayerName
@onready var player_level_label: Label = $BottomLeft/PlayerCard/Level
@onready var music_notification: PanelContainer = $BottomRight/MusicNotification
@onready var track_title_label: Label = $BottomRight/MusicNotification/HBox/VBox/TrackTitle
@onready var track_artist_label: Label = $BottomRight/MusicNotification/HBox/VBox/TrackArtist
@onready var hover_sound: AudioStreamPlayer = $HoverSound
@onready var select_sound: AudioStreamPlayer = $SelectSound

var menu_buttons: Array[RLMenuButton] = []
var current_focus_index: int = 0

func _ready() -> void:
	# Generate placeholder sounds
	generate_sounds()

	# Collect menu buttons
	collect_buttons()

	# Set up button sounds
	for button in menu_buttons:
		button.set_sounds(hover_sound, select_sound)

	# Focus first button
	if menu_buttons.size() > 0:
		focus_button(0)

	# Set up player card
	setup_player_card()

	# Initially hide music notification
	if music_notification:
		music_notification.visible = false

func generate_sounds() -> void:
	const SoundGen = preload("res://scripts/ui/menu/sound_generator.gd")
	if hover_sound:
		hover_sound.stream = SoundGen.generate_hover_sound()
	if select_sound:
		select_sound.stream = SoundGen.generate_select_sound()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		navigate_down()
		accept_event()
	elif event.is_action_pressed("ui_up"):
		navigate_up()
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		activate_current_button()
		accept_event()

func collect_buttons() -> void:
	menu_buttons.clear()
	for child in buttons_container.get_children():
		if child is RLMenuButton:
			menu_buttons.append(child)
			child.button_pressed.connect(_on_button_pressed.bind(child))

func navigate_down() -> void:
	if menu_buttons.size() == 0:
		return
	if current_focus_index >= 0 and current_focus_index < menu_buttons.size():
		menu_buttons[current_focus_index].focus_exited()
	current_focus_index = (current_focus_index + 1) % menu_buttons.size()
	focus_button(current_focus_index)

func navigate_up() -> void:
	if menu_buttons.size() == 0:
		return
	if current_focus_index >= 0 and current_focus_index < menu_buttons.size():
		menu_buttons[current_focus_index].focus_exited()
	current_focus_index = (current_focus_index - 1 + menu_buttons.size()) % menu_buttons.size()
	focus_button(current_focus_index)

func focus_button(index: int) -> void:
	if index >= 0 and index < menu_buttons.size():
		current_focus_index = index
		menu_buttons[index].focus_entered()

func activate_current_button() -> void:
	if current_focus_index >= 0 and current_focus_index < menu_buttons.size():
		menu_buttons[current_focus_index]._activate()

func _on_button_pressed(button: RLMenuButton) -> void:
	match button.name:
		"PlayButton":
			play_pressed.emit()
		"ItemShopButton":
			item_shop_pressed.emit()
		"GarageButton":
			garage_pressed.emit()
		"ProfileButton":
			profile_pressed.emit()
		"OptionsButton":
			options_pressed.emit()
		"QuitButton":
			quit_pressed.emit()

func setup_player_card() -> void:
	if player_name_label:
		player_name_label.text = "Player"
	if player_level_label:
		player_level_label.text = "25"

func show_music_notification(track_title: String, artist: String) -> void:
	if music_notification and track_title_label and track_artist_label:
		track_title_label.text = track_title
		track_artist_label.text = artist
		music_notification.visible = true

		# Auto-hide after 5 seconds
		await get_tree().create_timer(5.0).timeout
		if music_notification:
			music_notification.visible = false
