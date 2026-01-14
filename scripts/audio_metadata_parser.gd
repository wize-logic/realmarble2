## Audio Metadata Parser
## Extracts metadata (title, artist, album art) from MP3 and OGG files

class_name AudioMetadataParser

## Metadata container
class AudioMetadata:
	var title: String = ""
	var artist: String = ""
	var album: String = ""
	var album_art: ImageTexture = null

	func _init(p_title: String = "", p_artist: String = "", p_album: String = "") -> void:
		title = p_title
		artist = p_artist
		album = p_album

## Extract metadata from an audio file
static func extract_metadata(file_path: String) -> AudioMetadata:
	var metadata := AudioMetadata.new()

	# Determine file type
	var ext := file_path.get_extension().to_lower()

	match ext:
		"mp3":
			return _extract_mp3_metadata(file_path)
		"ogg":
			return _extract_ogg_metadata(file_path)
		_:
			# Fallback: use filename as title
			metadata.title = file_path.get_file().get_basename()
			return metadata

	return metadata

## Extract metadata from MP3 files (ID3v2 tags)
static func _extract_mp3_metadata(file_path: String) -> AudioMetadata:
	var metadata := AudioMetadata.new()
	var file := FileAccess.open(file_path, FileAccess.READ)

	if not file:
		metadata.title = file_path.get_file().get_basename()
		return metadata

	# Check for ID3v2 tag (first 3 bytes should be "ID3")
	var header := file.get_buffer(3)
	if header.get_string_from_ascii() != "ID3":
		# No ID3v2 tag, use filename
		metadata.title = file_path.get_file().get_basename()
		file.close()
		return metadata

	# Read ID3v2 version
	var version_major := file.get_8()
	var version_minor := file.get_8()
	var flags := file.get_8()

	# Read tag size (synchsafe integer)
	var size := _read_synchsafe_int(file)

	# Store position after header
	var tag_start := file.get_position()
	var tag_end := tag_start + size

	# Parse frames
	while file.get_position() < tag_end:
		# Read frame header (10 bytes in ID3v2.3/v2.4)
		var frame_id := file.get_buffer(4).get_string_from_ascii()

		# Check for padding (null bytes)
		if frame_id.is_empty() or frame_id.unicode_at(0) == 0:
			break

		# Read frame size
		var frame_size: int
		if version_major == 4:
			frame_size = _read_synchsafe_int(file)
		else:
			frame_size = file.get_32()

		var frame_flags := file.get_16()

		# Store frame data position
		var frame_data_pos := file.get_position()

		# Parse specific frames
		match frame_id:
			"TIT2":  # Title
				metadata.title = _read_text_frame(file, frame_size)
			"TPE1":  # Artist
				metadata.artist = _read_text_frame(file, frame_size)
			"TALB":  # Album
				metadata.album = _read_text_frame(file, frame_size)
			"APIC":  # Attached picture (album art)
				metadata.album_art = _read_apic_frame(file, frame_size)

		# Move to next frame
		file.seek(frame_data_pos + frame_size)

	file.close()

	# Fallback to filename if no title found
	if metadata.title.is_empty():
		metadata.title = file_path.get_file().get_basename()

	return metadata

## Extract metadata from OGG files (Vorbis comments)
static func _extract_ogg_metadata(file_path: String) -> AudioMetadata:
	var metadata := AudioMetadata.new()
	var file := FileAccess.open(file_path, FileAccess.READ)

	if not file:
		metadata.title = file_path.get_file().get_basename()
		return metadata

	# OGG uses Vorbis comments which are more complex to parse
	# For now, we'll use a simplified approach
	# TODO: Implement full OGG Vorbis comment parsing

	# Try to find common comment patterns in the file
	var file_size := file.get_length()
	var search_size: int = min(file_size, 100000)  # Search first 100KB
	var buffer := file.get_buffer(search_size)
	var buffer_str := buffer.get_string_from_utf8()

	# Look for TITLE= tag
	var title_idx := buffer_str.find("TITLE=")
	if title_idx >= 0:
		var start := title_idx + 6
		var end := _find_null_or_newline(buffer_str, start)
		if end > start:
			metadata.title = buffer_str.substr(start, end - start)

	# Look for ARTIST= tag
	var artist_idx := buffer_str.find("ARTIST=")
	if artist_idx >= 0:
		var start := artist_idx + 7
		var end := _find_null_or_newline(buffer_str, start)
		if end > start:
			metadata.artist = buffer_str.substr(start, end - start)

	# Look for ALBUM= tag
	var album_idx := buffer_str.find("ALBUM=")
	if album_idx >= 0:
		var start := album_idx + 6
		var end := _find_null_or_newline(buffer_str, start)
		if end > start:
			metadata.album = buffer_str.substr(start, end - start)

	file.close()

	# Fallback to filename if no title found
	if metadata.title.is_empty():
		metadata.title = file_path.get_file().get_basename()

	return metadata

## Helper function to find null character or newline in a string
static func _find_null_or_newline(text: String, start: int) -> int:
	for i in range(start, text.length()):
		var code := text.unicode_at(i)
		if code == 0 or code == 10:  # null or newline
			return i
	return text.length()

## Read a synchsafe integer (used in ID3v2)
static func _read_synchsafe_int(file: FileAccess) -> int:
	var bytes := file.get_buffer(4)
	return (bytes[0] << 21) | (bytes[1] << 14) | (bytes[2] << 7) | bytes[3]

## Read a text frame from ID3v2
static func _read_text_frame(file: FileAccess, size: int) -> String:
	if size <= 0:
		return ""

	# First byte is text encoding
	var encoding := file.get_8()
	var text_size := size - 1

	if text_size <= 0:
		return ""

	var text_buffer := file.get_buffer(text_size)

	# Decode based on encoding
	match encoding:
		0:  # ISO-8859-1
			return text_buffer.get_string_from_ascii().strip_edges()
		1:  # UTF-16 with BOM
			return text_buffer.get_string_from_utf16().strip_edges()
		2:  # UTF-16BE without BOM
			return text_buffer.get_string_from_utf16().strip_edges()
		3:  # UTF-8
			return text_buffer.get_string_from_utf8().strip_edges()
		_:
			return text_buffer.get_string_from_utf8().strip_edges()

## Read an APIC frame (album art) from ID3v2
static func _read_apic_frame(file: FileAccess, size: int) -> ImageTexture:
	if size <= 0:
		return null

	var start_pos := file.get_position()

	# First byte is text encoding
	var encoding := file.get_8()

	# Read MIME type (null-terminated string)
	var mime_type := ""
	while true:
		var byte := file.get_8()
		if byte == 0:
			break
		mime_type += char(byte)

	# Read picture type
	var picture_type := file.get_8()

	# Read description (null-terminated string)
	while true:
		var byte := file.get_8()
		if byte == 0:
			break

	# Calculate image data size
	var bytes_read := file.get_position() - start_pos
	var image_size := size - bytes_read

	if image_size <= 0:
		return null

	# Read image data
	var image_data := file.get_buffer(image_size)

	# Create image from data
	var image := Image.new()
	var err: Error

	# Try to load based on MIME type or by trying different formats
	if "jpeg" in mime_type.to_lower() or "jpg" in mime_type.to_lower():
		err = image.load_jpg_from_buffer(image_data)
	elif "png" in mime_type.to_lower():
		err = image.load_png_from_buffer(image_data)
	else:
		# Try PNG first, then JPEG
		err = image.load_png_from_buffer(image_data)
		if err != OK:
			err = image.load_jpg_from_buffer(image_data)

	if err != OK:
		return null

	# Create texture from image
	return ImageTexture.create_from_image(image)
