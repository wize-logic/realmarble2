extends Control

## Music Notification Overlay
## Displays a semi-transparent notification when a new song starts playing

@onready var panel: PanelContainer = $Panel
@onready var label: Label = $Panel/MarginContainer/Label

var tween: Tween
var display_duration: float = 4.0
var fade_duration: float = 0.5

func _ready() -> void:
	# Start hidden
	modulate.a = 0.0
	hide()

func show_notification(song_name: String) -> void:
	"""Show a notification with the song name"""
	if not song_name or song_name.is_empty():
		return

	# Set the song name
	label.text = song_name

	# Cancel any existing tween
	if tween and tween.is_valid():
		tween.kill()

	# Show and fade in
	show()
	tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Fade in
	tween.tween_property(self, "modulate:a", 1.0, fade_duration)
	# Hold
	tween.tween_interval(display_duration)
	# Fade out
	tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	# Hide when done
	tween.tween_callback(hide)
