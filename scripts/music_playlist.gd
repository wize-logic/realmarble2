extends Node

## Music Playlist Manager - Rocket League style
## Plays background music during gameplay with playlist support
## Production-ready with proper error handling, track progress, and controls

signal track_started(metadata: Dictionary)
signal track_finished
signal playlist_finished
signal shuffle_changed(enabled: bool)

@export var playlist: Array[AudioStream] = []  # Add songs here in the editor
@export var shuffle: bool = true  # Shuffle playlist
@export var volume_db: float = -15.0  # Music volume
@export var fade_in_duration: float = 2.0  # Fade in when starting
@export var fade_out_duration: float = 1.5  # Fade out when stopping
@export var loop_playlist: bool = true  # Whether to loop playlist when finished

var audio_player: AudioStreamPlayer
var current_track_index: int = 0
var is_playing: bool = false
var is_paused: bool = false
var is_fading: bool = false
var fade_timer: float = 0.0
var target_volume: float = 0.0
var start_volume: float = 0.0

# Shuffled playlist order
var shuffled_indices: Array[int] = []

# Metadata storage (parallel array to playlist)
# Each entry is a Dictionary with: title, artist, album, album_art (ImageTexture)
var metadata_list: Array[Dictionary] = []

# Track skip protection (prevent infinite recursion)
var _skip_attempts: int = 0
const MAX_SKIP_ATTEMPTS: int = 50

func _ready() -> void:
	# Create audio player
	audio_player = AudioStreamPlayer.new()
	audio_player.name = "PlaylistPlayer"
	audio_player.bus = "Music"
	add_child(audio_player)

	# Connect finished signal
	audio_player.finished.connect(_on_track_finished)

	# Initialize shuffled order (needed even for non-shuffle mode)
	_initialize_indices()

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

func _initialize_indices() -> void:
	"""Initialize the indices array for playlist"""
	shuffled_indices.clear()
	for i in range(playlist.size()):
		shuffled_indices.append(i)

func start_playlist() -> void:
	"""Start playing the playlist"""
	if playlist.is_empty():
		DebugLogger.dlog(DebugLogger.Category.AUDIO, "Music playlist is empty - playing in silence")
		return

	if is_playing and not is_paused:
		return

	is_playing = true
	is_paused = false
	_skip_attempts = 0

	# Ensure indices are initialized
	if shuffled_indices.size() != playlist.size():
		_initialize_indices()

	# Start with a random track if shuffle is enabled
	if shuffle and playlist.size() > 0:
		current_track_index = randi() % playlist.size()
	else:
		current_track_index = 0

	_play_current_track()

func stop_playlist() -> void:
	"""Stop the playlist with fade out"""
	if not is_playing and not is_paused:
		return

	is_playing = false
	is_paused = false
	_fade_out()

func pause_playlist() -> void:
	"""Pause the current track"""
	if audio_player.playing and not audio_player.stream_paused:
		audio_player.stream_paused = true
		is_paused = true

func resume_playlist() -> void:
	"""Resume the current track"""
	if audio_player.stream_paused:
		audio_player.stream_paused = false
		is_paused = false
	elif not is_playing and playlist.size() > 0:
		# If stopped, restart from current position
		start_playlist()

func next_track() -> void:
	"""Skip to next track"""
	if playlist.is_empty():
		return

	_skip_attempts = 0
	_advance_track()
	if is_playing or is_paused:
		is_paused = false
		_play_current_track()

func previous_track() -> void:
	"""Go to previous track"""
	if playlist.is_empty():
		return

	_skip_attempts = 0

	# If we're more than 3 seconds into the track, restart it instead
	if audio_player.playing and audio_player.get_playback_position() > 3.0:
		audio_player.seek(0.0)
		return

	current_track_index -= 1
	if current_track_index < 0:
		current_track_index = playlist.size() - 1

	if is_playing or is_paused:
		is_paused = false
		_play_current_track()

func toggle_shuffle() -> void:
	"""Toggle shuffle mode"""
	shuffle = not shuffle
	if shuffle and playlist.size() > 0:
		_shuffle_playlist()
	shuffle_changed.emit(shuffle)

func set_shuffle(enabled: bool) -> void:
	"""Set shuffle mode"""
	if shuffle != enabled:
		shuffle = enabled
		if shuffle and playlist.size() > 0:
			_shuffle_playlist()
		shuffle_changed.emit(shuffle)

func set_volume(volume: float) -> void:
	"""Set the playback volume (in dB)"""
	volume_db = volume
	if not is_fading and audio_player:
		audio_player.volume_db = volume_db

func get_playback_position() -> float:
	"""Get current playback position in seconds"""
	if audio_player and audio_player.playing:
		return audio_player.get_playback_position()
	return 0.0

func get_track_duration() -> float:
	"""Get current track duration in seconds"""
	if audio_player and audio_player.stream:
		return audio_player.stream.get_length()
	return 0.0

func get_playback_progress() -> float:
	"""Get playback progress as a value between 0.0 and 1.0"""
	var duration := get_track_duration()
	if duration > 0.0:
		return get_playback_position() / duration
	return 0.0

func seek(position: float) -> void:
	"""Seek to a position in the current track (in seconds)"""
	if audio_player and audio_player.playing:
		var duration := get_track_duration()
		audio_player.seek(clampf(position, 0.0, duration))

func seek_percent(percent: float) -> void:
	"""Seek to a percentage of the track (0.0 to 1.0)"""
	var duration := get_track_duration()
	seek(duration * clampf(percent, 0.0, 1.0))

func _play_current_track() -> void:
	"""Play the current track in the playlist"""
	if playlist.is_empty():
		return

	# Prevent infinite recursion if all tracks are invalid
	if _skip_attempts >= MAX_SKIP_ATTEMPTS or _skip_attempts >= playlist.size():
		push_warning("MusicPlaylist: All tracks appear to be invalid, stopping playlist")
		is_playing = false
		return

	# Validate index
	if current_track_index < 0 or current_track_index >= playlist.size():
		current_track_index = 0

	if shuffled_indices.is_empty() or shuffled_indices.size() != playlist.size():
		_initialize_indices()

	var track_index: int = shuffled_indices[current_track_index] if shuffle else current_track_index

	# Validate track_index
	if track_index < 0 or track_index >= playlist.size():
		track_index = current_track_index

	var track: AudioStream = playlist[track_index]

	if not track:
		DebugLogger.dlog(DebugLogger.Category.AUDIO, "Invalid track at index %d, skipping" % track_index)
		_skip_attempts += 1
		_advance_track()
		_play_current_track()
		return

	_skip_attempts = 0
	DebugLogger.dlog(DebugLogger.Category.AUDIO, "Now playing: Track %d/%d" % [current_track_index + 1, playlist.size()])

	# Set up audio player
	audio_player.stream = track
	audio_player.play()

	# Fade in
	_fade_in()

	# Emit signal with track metadata
	track_started.emit(get_current_track_metadata())

func _advance_track() -> void:
	"""Move to next track in playlist"""
	if shuffle and playlist.size() > 1:
		# Pick a random track (avoid playing the same track twice in a row)
		var previous_index: int = current_track_index
		var attempts: int = 0
		while attempts < 10:
			current_track_index = randi() % playlist.size()
			if current_track_index != previous_index:
				break
			attempts += 1
	else:
		# Sequential playback
		current_track_index += 1

		# Loop back to start if at end
		if current_track_index >= playlist.size():
			current_track_index = 0

			if not loop_playlist:
				is_playing = false
				playlist_finished.emit()
				return

func _shuffle_playlist() -> void:
	"""Shuffle the playlist order"""
	if playlist.is_empty():
		return

	# Remember current track if playing
	var current_actual_index: int = -1
	if is_playing and shuffled_indices.size() > current_track_index:
		current_actual_index = shuffled_indices[current_track_index]

	_initialize_indices()

	# Fisher-Yates shuffle
	for i in range(shuffled_indices.size() - 1, 0, -1):
		var j: int = randi() % (i + 1)
		var temp: int = shuffled_indices[i]
		shuffled_indices[i] = shuffled_indices[j]
		shuffled_indices[j] = temp

	# If we had a current track, move it to the front so it continues playing
	if current_actual_index >= 0 and is_playing:
		var current_pos := shuffled_indices.find(current_actual_index)
		if current_pos > 0:
			shuffled_indices.remove_at(current_pos)
			shuffled_indices.insert(0, current_actual_index)
			current_track_index = 0

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
	track_finished.emit()

	if not is_playing:
		return

	# Auto-advance to next track
	_advance_track()

	# Only continue if still playing (might have been stopped by playlist_finished)
	if is_playing:
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

		# Update indices if needed
		if shuffled_indices.size() < playlist.size():
			shuffled_indices.append(playlist.size() - 1)

		DebugLogger.dlog(DebugLogger.Category.AUDIO, "Added song to playlist: %s (total: %d)" % [metadata["title"], playlist.size()])

func remove_song(index: int) -> void:
	"""Remove a song from the playlist"""
	if index >= 0 and index < playlist.size():
		playlist.remove_at(index)
		if index < metadata_list.size():
			metadata_list.remove_at(index)

		# Rebuild indices
		_initialize_indices()
		if shuffle:
			_shuffle_playlist()

		# Adjust current track index if necessary
		if current_track_index >= playlist.size():
			current_track_index = max(0, playlist.size() - 1)

		DebugLogger.dlog(DebugLogger.Category.AUDIO, "Removed song from playlist (total: %d)" % playlist.size())

func clear_playlist() -> void:
	"""Clear all songs from playlist"""
	var was_playing := is_playing
	if was_playing:
		stop_playlist()

	playlist.clear()
	metadata_list.clear()
	shuffled_indices.clear()
	current_track_index = 0
	_skip_attempts = 0
	DebugLogger.dlog(DebugLogger.Category.AUDIO, "Playlist cleared")

func get_current_track_metadata() -> Dictionary:
	"""Get the metadata of the currently playing track"""
	if playlist.is_empty() or current_track_index < 0:
		return {
			"title": "No track",
			"artist": "",
			"album": "",
			"album_art": null,
			"track_number": 0,
			"total_tracks": 0
		}

	var track_index: int
	if shuffle and shuffled_indices.size() > current_track_index:
		track_index = shuffled_indices[current_track_index]
	else:
		track_index = current_track_index

	var metadata: Dictionary = {}
	if track_index >= 0 and track_index < metadata_list.size():
		metadata = metadata_list[track_index].duplicate()
	else:
		metadata = {
			"title": "Unknown track",
			"artist": "",
			"album": "",
			"album_art": null
		}

	# Add track number info
	metadata["track_number"] = current_track_index + 1
	metadata["total_tracks"] = playlist.size()

	return metadata

func get_playlist_info() -> Dictionary:
	"""Get information about the current playlist state"""
	return {
		"total_tracks": playlist.size(),
		"current_track": current_track_index + 1,
		"is_playing": is_playing,
		"is_paused": is_paused,
		"shuffle_enabled": shuffle,
		"loop_enabled": loop_playlist
	}

func is_playlist_playing() -> bool:
	"""Check if the playlist is currently playing"""
	return is_playing and not is_paused

func is_playlist_paused() -> bool:
	"""Check if the playlist is paused"""
	return is_paused
