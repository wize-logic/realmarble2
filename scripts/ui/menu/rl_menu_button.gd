extends Control
class_name RLMenuButton

## Rocket League-style menu button

signal button_pressed

@export var button_text: String = "BUTTON"
@export var subtitle_text: String = ""
@export var is_highlighted: bool = false

var is_hovered: bool = false
var is_focused: bool = false

@onready var main_label: Label = $MainLabel
@onready var subtitle_label: Label = $SubtitleLabel
@onready var highlight: ColorRect = $Highlight
@onready var edge_glow: ColorRect = $EdgeGlow

var hover_sound: AudioStreamPlayer
var select_sound: AudioStreamPlayer
var pulse_time: float = 0.0

func _ready() -> void:
	if main_label:
		main_label.text = button_text
	if subtitle_label:
		subtitle_label.text = subtitle_text
		subtitle_label.visible = subtitle_text != ""

	# Adjust label positions if subtitle exists
	if subtitle_text != "" and main_label:
		main_label.offset_top = -20.0
		main_label.offset_bottom = 4.0
		custom_minimum_size.y = 65.0

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

func _process(delta: float) -> void:
	var active: bool = is_hovered or is_focused or is_highlighted

	# Update highlight visibility
	if highlight:
		highlight.visible = active

	# Update edge glow with pulse animation
	if edge_glow:
		edge_glow.visible = active
		if active:
			pulse_time += delta
			var pulse: float = (sin(pulse_time * 3.0) + 1.0) * 0.5
			edge_glow.modulate = Color(1.0, 0.6, 0.2, 0.4 + pulse * 0.3)
		else:
			pulse_time = 0.0

func _on_mouse_entered() -> void:
	is_hovered = true
	if hover_sound:
		hover_sound.play()

func _on_mouse_exited() -> void:
	is_hovered = false

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_activate()

func focus_entered() -> void:
	is_focused = true
	if hover_sound:
		hover_sound.play()

func focus_exited() -> void:
	is_focused = false

func _activate() -> void:
	print("Button activated: ", name)
	if select_sound:
		select_sound.play()
	print("Emitting button_pressed signal")
	button_pressed.emit()

func set_sounds(hover: AudioStreamPlayer, select: AudioStreamPlayer) -> void:
	hover_sound = hover
	select_sound = select
