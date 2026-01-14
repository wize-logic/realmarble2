extends Node

## Music Playlist Manager - Rocket League style
## Plays background music during gameplay with playlist support

signal track_started(metadata: Dictionary)

@export var playlist: Array[AudioStream] = []  # Add songs here in the editor
@export var shuffle: bool = true  # Shuffle playlist
@export var volume_db: float = -15.0  # Music volume
@export var fade_in_duration: float = 2.0  # Fade in when starting
@export var fade_out_duration: float = 1.5  # Fade out when stopping

var audio_player: AudioStreamPlayer
var current_track_index: int = 0
var is_playing: bool = false
var is_fading: bool = false
var fade_timer: float = 0.0
var target_volume: float = 0.0
var start_volume: float = 0.0

# Shuffled playlist order
var shuffled_indices: Array[int] = []

# Metadata storage (parallel array to playlist)
# Each entry is a Dictionary with: title, artist, album, album_art (ImageTexture)
var metadata_list: Array[Dictionary] = []

func _ready() -> void:
	# Create audio player
	audio_player = AudioStreamPlayer.new()
	audio_player.name = "PlaylistPlayer"
	audio_player.bus = "Music"
	add_child(audio_player)

	# Connect finished signal
	audio_player.finished.connect(_on_track_finished)

	# Initialize shuffled order
	if shuffle:
		_shuffle_playlist()

func _process(delta: float) -> void:
	# Handle volume fading
	if is_fading:
		fade_timer += delta
		var fade_duration: float = fade_in_duration if is_playing else fade_out_duration
		var fade_progress: float = min(fade_timer / fade_duration, 1.0)

		# Smooth fade curve
		var smooth_progress: float = ease(fade_progress, -2.0) if is_playing else ease(fade_progress, 2.0)
		audio_player.volume_db = lerp(start_volume, target_volume, smooth_progress)

		if fade_progress >= 1.0:
			is_fading = false

			# Stop audio if fading out
			if not is_playing and audio_player.playing:
				audio_player.stop()

func start_playlist() -> void:
	"""Start playing the playlist"""
	if playlist.is_empty():
		print("Music playlist is empty - playing in silence")
		return

	if is_playing:
		return

	is_playing = true
	current_track_index = 0

	if shuffle:
		_shuffle_playlist()

	_play_current_track()

func stop_playlist() -> void:
	"""Stop the playlist with fade out"""
	if not is_playing:
		return

	is_playing = false
	_fade_out()

func pause_playlist() -> void:
	"""Pause the current track"""
	if audio_player.playing and not audio_player.stream_paused:
		audio_player.stream_paused = true

func resume_playlist() -> void:
	"""Resume the current track"""
	if audio_player.stream_paused:
		audio_player.stream_paused = false

func next_track() -> void:
	"""Skip to next track"""
	if playlist.is_empty():
		return

	_advance_track()
	_play_current_track()

func previous_track() -> void:
	"""Go to previous track"""
	if playlist.is_empty():
		return

	current_track_index -= 1
	if current_track_index < 0:
		current_track_index = playlist.size() - 1

	_play_current_track()

func _play_current_track() -> void:
	"""Play the current track in the playlist"""
	if playlist.is_empty():
		return

	var track_index: int = shuffled_indices[current_track_index] if shuffle else current_track_index
	var track: AudioStream = playlist[track_index]

	if not track:
		print("Invalid track at index %d, skipping" % track_index)
		_advance_track()
		_play_current_track()
		return

	print("Now playing: Track %d/%d" % [current_track_index + 1, playlist.size()])

	# Set up audio player
	audio_player.stream = track
	audio_player.play()

	# Fade in
	_fade_in()

	# Emit signal with track metadata
	track_started.emit(get_current_track_metadata())

func _advance_track() -> void:
	"""Move to next track in playlist"""
	current_track_index += 1

	# Loop back to start if at end
	if current_track_index >= playlist.size():
		current_track_index = 0

		# Re-shuffle if enabled
		if shuffle:
			_shuffle_playlist()

func _shuffle_playlist() -> void:
	"""Shuffle the playlist order"""
	shuffled_indices.clear()

	# Create array of indices
	for i in range(playlist.size()):
		shuffled_indices.append(i)

	# Fisher-Yates shuffle
	for i in range(shuffled_indices.size() - 1, 0, -1):
		var j: int = randi() % (i + 1)
		var temp: int = shuffled_indices[i]
		shuffled_indices[i] = shuffled_indices[j]
		shuffled_indices[j] = temp

func _fade_in() -> void:
	"""Fade in the music"""
	is_fading = true
	fade_timer = 0.0
	start_volume = -80.0  # Start silent
	target_volume = volume_db
	audio_player.volume_db = start_volume

func _fade_out() -> void:
	"""Fade out the music"""
	is_fading = true
	fade_timer = 0.0
	start_volume = audio_player.volume_db
	target_volume = -80.0  # Fade to silence

func _on_track_finished() -> void:
	"""Called when a track finishes playing"""
	if not is_playing:
		return

	# Auto-advance to next track
	_advance_track()
	_play_current_track()

func add_song(song: AudioStream, file_path: String = "") -> void:
	"""Add a song to the playlist with metadata extraction"""
	if song:
		playlist.append(song)

		# Extract metadata from file
		var metadata: Dictionary = {}
		if file_path and not file_path.is_empty():
			var parsed_metadata = AudioMetadataParser.extract_metadata(file_path)
			metadata["title"] = parsed_metadata.title
			metadata["artist"] = parsed_metadata.artist
			metadata["album"] = parsed_metadata.album
			metadata["album_art"] = parsed_metadata.album_art
		else:
			# Fallback: use resource path if available
			if song.resource_path:
				metadata["title"] = song.resource_path.get_file().get_basename()
			else:
				metadata["title"] = "Unknown"
			metadata["artist"] = ""
			metadata["album"] = ""
			metadata["album_art"] = null

		metadata_list.append(metadata)
		print("Added song to playlist: %s (total: %d)" % [metadata["title"], playlist.size()])

func remove_song(index: int) -> void:
	"""Remove a song from the playlist"""
	if index >= 0 and index < playlist.size():
		playlist.remove_at(index)
		metadata_list.remove_at(index)
		print("Removed song from playlist (total: %d)" % playlist.size())

func clear_playlist() -> void:
	"""Clear all songs from playlist"""
	playlist.clear()
	metadata_list.clear()
	shuffled_indices.clear()
	print("Playlist cleared")

func get_current_track_metadata() -> Dictionary:
	"""Get the metadata of the currently playing track"""
	if playlist.is_empty() or current_track_index >= playlist.size():
		return {
			"title": "No track",
			"artist": "",
			"album": "",
			"album_art": null
		}

	var track_index: int = shuffled_indices[current_track_index] if shuffle else current_track_index

	if track_index < metadata_list.size():
		return metadata_list[track_index]

	return {
		"title": "Unknown track",
		"artist": "",
		"album": "",
		"album_art": null
	}
