extends Control
class_name RocketLeagueMenu

## Rocket League-style main menu with navigation

signal play_pressed
signal garage_pressed
signal profile_pressed
signal store_pressed
signal season_pass_pressed
signal settings_pressed
signal quit_pressed
signal multiplayer_pressed

@onready var buttons_container: VBoxContainer = $CenterContainer/VBoxContainer
@onready var logo: Control = $LogoContainer/Logo
@onready var xp_bar: ProgressBar = $BottomBar/MarginContainer/VBoxContainer/XPBar
@onready var xp_label: Label = $BottomBar/MarginContainer/VBoxContainer/XPLabel
@onready var hover_sound: AudioStreamPlayer = $HoverSound
@onready var select_sound: AudioStreamPlayer = $SelectSound

var menu_buttons: Array[MenuCardButton] = []
var current_focus_index: int = 0
var xp_progress: float = 0.45  # 45% through current level
var xp_animation_target: float = 0.45

func _ready() -> void:
	# Generate placeholder sounds
	generate_sounds()

	# Collect all menu card buttons
	collect_buttons()

	# Set up button sounds
	for button in menu_buttons:
		button.set_sounds(hover_sound, select_sound)

	# Focus first button
	if menu_buttons.size() > 0:
		focus_button(0)

	# Animate XP bar
	animate_xp_bar()

	# Set up logo shader animation
	setup_logo_shader()

func generate_sounds() -> void:
	# Generate placeholder sound effects
	const SoundGen = preload("res://scripts/ui/menu/sound_generator.gd")
	if hover_sound:
		hover_sound.stream = SoundGen.generate_hover_sound()
	if select_sound:
		select_sound.stream = SoundGen.generate_select_sound()

func _unhandled_input(event: InputEvent) -> void:
	# Handle keyboard/gamepad navigation
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
		if child is MenuCardButton:
			menu_buttons.append(child)
			# Connect signals
			child.card_pressed.connect(_on_card_pressed.bind(child))

func navigate_down() -> void:
	if menu_buttons.size() == 0:
		return

	# Remove focus from current
	if current_focus_index >= 0 and current_focus_index < menu_buttons.size():
		menu_buttons[current_focus_index].focus_exited()

	# Move to next
	current_focus_index = (current_focus_index + 1) % menu_buttons.size()
	focus_button(current_focus_index)

func navigate_up() -> void:
	if menu_buttons.size() == 0:
		return

	# Remove focus from current
	if current_focus_index >= 0 and current_focus_index < menu_buttons.size():
		menu_buttons[current_focus_index].focus_exited()

	# Move to previous
	current_focus_index = (current_focus_index - 1 + menu_buttons.size()) % menu_buttons.size()
	focus_button(current_focus_index)

func focus_button(index: int) -> void:
	if index >= 0 and index < menu_buttons.size():
		current_focus_index = index
		menu_buttons[index].focus_entered()

func activate_current_button() -> void:
	if current_focus_index >= 0 and current_focus_index < menu_buttons.size():
		menu_buttons[current_focus_index]._activate()

func _on_card_pressed(button: MenuCardButton) -> void:
	# Handle button press based on action
	match button.button_action:
		"play":
			play_pressed.emit()
		"multiplayer":
			multiplayer_pressed.emit()
		"garage":
			garage_pressed.emit()
		"profile":
			profile_pressed.emit()
		"store":
			store_pressed.emit()
		"season_pass":
			season_pass_pressed.emit()
		"settings":
			settings_pressed.emit()
		"quit":
			quit_pressed.emit()

func animate_xp_bar() -> void:
	# Animate XP bar filling
	var tween: Tween = create_tween()
	tween.set_loops()
	tween.tween_property(xp_bar, "value", xp_animation_target * 100.0, 2.0)
	tween.tween_interval(1.0)

	# Set initial value
	xp_bar.value = 0.0

	# Update label
	update_xp_label()

func update_xp_label() -> void:
	if xp_label:
		var level: int = 25  # Example level
		var xp_current: int = int(xp_progress * 1000)
		var xp_needed: int = 1000
		xp_label.text = "Level %d  •  %d / %d XP" % [level, xp_current, xp_needed]

func setup_logo_shader() -> void:
	if logo and logo.material:
		# Logo shader is already set up in the scene
		pass
