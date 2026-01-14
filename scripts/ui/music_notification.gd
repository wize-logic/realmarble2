extends Control

## Music Notification Overlay
## Displays a semi-transparent notification with album art and metadata when a new song starts playing

@onready var panel: PanelContainer = $Panel
@onready var container: VBoxContainer = $Panel/MarginContainer/VBoxContainer
@onready var album_art: TextureRect = $Panel/MarginContainer/VBoxContainer/AlbumArt
@onready var artist_label: Label = $Panel/MarginContainer/VBoxContainer/Artist
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/Title

var tween: Tween
var display_duration: float = 4.0
var fade_duration: float = 0.5

# Default placeholder for missing album art
var placeholder_texture: ImageTexture

func _ready() -> void:
	# Start hidden
	modulate.a = 0.0
	hide()

	# Create a placeholder texture for songs without album art
	_create_placeholder_texture()

func _create_placeholder_texture() -> void:
	"""Create a simple placeholder image for songs without album art"""
	var img := Image.create(80, 80, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.2, 0.2, 1.0))  # Dark gray
	placeholder_texture = ImageTexture.create_from_image(img)

func show_notification(metadata: Dictionary) -> void:
	"""Show a notification with song metadata including album art"""
	if not metadata or metadata.is_empty():
		return

	var title: String = metadata.get("title", "Unknown")
	var artist: String = metadata.get("artist", "")
	var album_art_texture: ImageTexture = metadata.get("album_art", null)

	# Set the song title (cap at 20 characters)
	if title.length() > 20:
		title_label.text = title.substr(0, 20) + "..."
	else:
		title_label.text = title

	# Set the artist (if available, cap at 18 characters)
	if artist and not artist.is_empty():
		if artist.length() > 18:
			artist_label.text = artist.substr(0, 18) + "..."
		else:
			artist_label.text = artist
		artist_label.show()
	else:
		artist_label.hide()

	# Set album art or placeholder
	if album_art_texture:
		album_art.texture = album_art_texture
	else:
		album_art.texture = placeholder_texture

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
