extends Control

## Music Notification Overlay
## Displays a semi-transparent notification with album art and metadata when a new song starts playing
## Production-ready with proper animation handling, null safety, and input support

signal notification_dismissed
signal track_skip_requested
signal track_prev_requested

@onready var panel: PanelContainer = $Panel
@onready var album_art: TextureRect = $Panel/MarginContainer/VBoxContainer/AlbumArt
@onready var artist_label: Label = $Panel/MarginContainer/VBoxContainer/Artist
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/Title

var tween: Tween
var display_duration: float = 4.0
var fade_duration: float = 0.5
var is_visible: bool = false
var is_mouse_over: bool = false

# Default placeholder for missing album art
var placeholder_texture: ImageTexture

# Current metadata for potential reuse
var current_metadata: Dictionary = {}

func _ready() -> void:
	# Start hidden
	modulate.a = 0.0
	hide()
	is_visible = false

	# Create a placeholder texture for songs without album art
	_create_placeholder_texture()

	# Connect mouse signals for hover behavior
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _create_placeholder_texture() -> void:
	"""Create a visually appealing placeholder image for songs without album art"""
	var img := Image.create(80, 80, false, Image.FORMAT_RGBA8)

	# Fill with dark gradient-like background
	for y in range(80):
		for x in range(80):
			var gradient_factor := float(y) / 80.0
			var color := Color(0.15 + gradient_factor * 0.1, 0.15 + gradient_factor * 0.08, 0.2 + gradient_factor * 0.1, 1.0)
			img.set_pixel(x, y, color)

	# Draw a simple music note icon in the center
	var note_color := Color(0.5, 0.5, 0.6, 1.0)
	# Note head (circle-ish)
	for y in range(45, 55):
		for x in range(30, 42):
			var dx := x - 36
			var dy := y - 50
			if dx * dx + dy * dy <= 36:
				img.set_pixel(x, y, note_color)
	# Note stem
	for y in range(25, 50):
		for x in range(40, 44):
			img.set_pixel(x, y, note_color)
	# Note flag
	for y in range(25, 35):
		for x in range(44, 52):
			if y - 25 < 52 - x:
				img.set_pixel(x, y, note_color)

	placeholder_texture = ImageTexture.create_from_image(img)

func _input(event: InputEvent) -> void:
	if not is_visible:
		return

	# Allow dismissing with Escape or clicking on the notification
	if event is InputEventMouseButton and event.pressed and is_mouse_over:
		if event.button_index == MOUSE_BUTTON_LEFT:
			hide_notification()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			track_prev_requested.emit()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			track_skip_requested.emit()
			get_viewport().set_input_as_handled()

func _on_mouse_entered() -> void:
	is_mouse_over = true
	# Pause the hide timer when hovering
	if tween and tween.is_valid() and is_visible:
		tween.pause()

func _on_mouse_exited() -> void:
	is_mouse_over = false
	# Resume the hide timer when not hovering
	if tween and tween.is_valid() and is_visible:
		tween.play()

func show_notification(metadata: Dictionary) -> void:
	"""Show a notification with song metadata including album art"""
	if not metadata or metadata.is_empty():
		return

	current_metadata = metadata
	var title: String = metadata.get("title", "Unknown Track")
	var artist: String = metadata.get("artist", "")
	var album_art_texture: Texture2D = metadata.get("album_art", null)

	# Validate UI elements exist
	if not title_label or not artist_label or not album_art:
		push_warning("MusicNotification: Missing UI elements")
		return

	# Set the song title (cap at 30 characters for better readability)
	if title.length() > 30:
		title_label.text = title.substr(0, 30) + "..."
	else:
		title_label.text = title

	# Set the artist (if available, cap at 27 characters)
	if artist and not artist.is_empty():
		if artist.length() > 27:
			artist_label.text = artist.substr(0, 27) + "..."
		else:
			artist_label.text = artist
		artist_label.show()
	else:
		artist_label.text = ""
		artist_label.hide()

	# Set album art or placeholder
	if album_art_texture and album_art_texture is Texture2D:
		album_art.texture = album_art_texture
	else:
		album_art.texture = placeholder_texture

	# Cancel any existing tween to prevent animation conflicts
	_cancel_tween()

	# Show and fade in
	show()
	is_visible = true
	tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Fade in
	tween.tween_property(self, "modulate:a", 1.0, fade_duration)
	# Hold (this can be paused on hover)
	tween.tween_interval(display_duration)
	# Fade out
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	# Hide when done
	tween.tween_callback(_on_tween_finished)

func hide_notification() -> void:
	"""Immediately hide the notification with a quick fade"""
	if not is_visible:
		return

	_cancel_tween()

	tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate:a", 0.0, fade_duration * 0.5)
	tween.tween_callback(_on_tween_finished)

func _cancel_tween() -> void:
	"""Safely cancel any existing tween"""
	if tween and tween.is_valid():
		tween.kill()
		tween = null

func _on_tween_finished() -> void:
	"""Called when the notification animation completes"""
	hide()
	is_visible = false
	notification_dismissed.emit()

func get_current_metadata() -> Dictionary:
	"""Get the currently displayed track metadata"""
	return current_metadata

func is_notification_visible() -> bool:
	"""Check if the notification is currently visible"""
	return is_visible
