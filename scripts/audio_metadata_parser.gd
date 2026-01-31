## Audio Metadata Parser
## Extracts metadata (title, artist, album art) from MP3, OGG, and WAV files
## Production-ready with comprehensive error handling and format support

class_name AudioMetadataParser

## Metadata container
class AudioMetadata:
	var title: String = ""
	var artist: String = ""
	var album: String = ""
	var album_art: ImageTexture = null
	var duration: float = 0.0
	var year: String = ""
	var genre: String = ""

	func _init(p_title: String = "", p_artist: String = "", p_album: String = "") -> void:
		title = p_title
		artist = p_artist
		album = p_album

	func to_dictionary() -> Dictionary:
		return {
			"title": title,
			"artist": artist,
			"album": album,
			"album_art": album_art,
			"duration": duration,
			"year": year,
			"genre": genre
		}

## Extract metadata from an audio file
static func extract_metadata(file_path: String) -> AudioMetadata:
	var metadata := AudioMetadata.new()

	# Validate file path
	if file_path.is_empty():
		return metadata

	# Determine file type
	var ext := file_path.get_extension().to_lower()

	match ext:
		"mp3":
			return _extract_mp3_metadata(file_path)
		"ogg":
			return _extract_ogg_metadata(file_path)
		"wav":
			return _extract_wav_metadata(file_path)
		"flac":
			return _extract_flac_metadata(file_path)
		_:
			# Fallback: use filename as title
			metadata.title = _clean_filename(file_path.get_file().get_basename())
			return metadata

## Extract metadata from MP3 files (ID3v2 tags)
static func _extract_mp3_metadata(file_path: String) -> AudioMetadata:
	var metadata := AudioMetadata.new()
	var file := FileAccess.open(file_path, FileAccess.READ)

	if not file:
		metadata.title = _clean_filename(file_path.get_file().get_basename())
		return metadata

	# Check for ID3v2 tag (first 3 bytes should be "ID3")
	var header := file.get_buffer(3)
	if header.size() < 3 or header.get_string_from_ascii() != "ID3":
		# Try ID3v1 at the end of the file
		metadata = _try_id3v1(file, file_path)
		file.close()
		return metadata

	# Read ID3v2 version
	var version_major := file.get_8()
	var _version_minor := file.get_8()
	var flags := file.get_8()

	# Check for unsynchronization flag
	var _unsync := (flags & 0x80) != 0

	# Read tag size (synchsafe integer)
	var size := _read_synchsafe_int(file)

	if size <= 0 or size > file.get_length():
		metadata.title = _clean_filename(file_path.get_file().get_basename())
		file.close()
		return metadata

	# Check for extended header
	if (flags & 0x40) != 0 and version_major >= 3:
		# Skip extended header
		var ext_header_size: int
		if version_major == 4:
			ext_header_size = _read_synchsafe_int(file)
		else:
			ext_header_size = file.get_32()
		if ext_header_size > 0:
			file.seek(file.get_position() + ext_header_size - 4)

	# Store position after header
	var tag_start := file.get_position()
	var tag_end := tag_start + size

	# Parse frames
	while file.get_position() < tag_end - 10:
		# Check if we have enough space for a frame header
		if file.get_position() + 10 > tag_end:
			break

		# Read frame header (10 bytes in ID3v2.3/v2.4)
		var frame_id_bytes := file.get_buffer(4)
		if frame_id_bytes.size() < 4:
			break

		var frame_id := frame_id_bytes.get_string_from_ascii()

		# Check for padding (null bytes or invalid frame ID)
		if frame_id.is_empty() or frame_id.unicode_at(0) == 0 or not _is_valid_frame_id(frame_id):
			break

		# Read frame size
		var frame_size: int
		if version_major == 4:
			frame_size = _read_synchsafe_int(file)
		else:
			frame_size = file.get_32()

		var _frame_flags := file.get_16()

		# Validate frame size
		if frame_size <= 0 or file.get_position() + frame_size > tag_end:
			break

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
			"TYER", "TDRC":  # Year (ID3v2.3 / ID3v2.4)
				metadata.year = _read_text_frame(file, frame_size)
			"TCON":  # Genre
				metadata.genre = _parse_genre(_read_text_frame(file, frame_size))
			"APIC":  # Attached picture (album art)
				if not metadata.album_art:  # Only read first image
					metadata.album_art = _read_apic_frame(file, frame_size)

		# Always move to next frame position
		file.seek(frame_data_pos + frame_size)

	file.close()

	# Fallback to filename if no title found
	if metadata.title.is_empty():
		metadata.title = _clean_filename(file_path.get_file().get_basename())

	return metadata

## Try to read ID3v1 tag at the end of the file
static func _try_id3v1(file: FileAccess, file_path: String) -> AudioMetadata:
	var metadata := AudioMetadata.new()

	if file.get_length() < 128:
		metadata.title = _clean_filename(file_path.get_file().get_basename())
		return metadata

	file.seek(file.get_length() - 128)
	var tag_header := file.get_buffer(3)

	if tag_header.get_string_from_ascii() != "TAG":
		metadata.title = _clean_filename(file_path.get_file().get_basename())
		return metadata

	# ID3v1 format: 30 bytes title, 30 bytes artist, 30 bytes album, 4 bytes year, etc.
	metadata.title = file.get_buffer(30).get_string_from_ascii().strip_edges()
	metadata.artist = file.get_buffer(30).get_string_from_ascii().strip_edges()
	metadata.album = file.get_buffer(30).get_string_from_ascii().strip_edges()
	metadata.year = file.get_buffer(4).get_string_from_ascii().strip_edges()

	if metadata.title.is_empty():
		metadata.title = _clean_filename(file_path.get_file().get_basename())

	return metadata

## Extract metadata from OGG Vorbis files
static func _extract_ogg_metadata(file_path: String) -> AudioMetadata:
	var metadata := AudioMetadata.new()
	var file := FileAccess.open(file_path, FileAccess.READ)

	if not file:
		metadata.title = _clean_filename(file_path.get_file().get_basename())
		return metadata

	# Read OGG page header
	var capture_pattern := file.get_buffer(4)
	if capture_pattern.size() < 4 or capture_pattern.get_string_from_ascii() != "OggS":
		file.close()
		metadata.title = _clean_filename(file_path.get_file().get_basename())
		return metadata

	# Skip to find the Vorbis comment header
	# OGG files have multiple pages, we need to find the one with comments
	file.seek(0)

	var file_size := file.get_length()
	var max_search: int = min(file_size, 65536)  # Search first 64KB

	# Look for vorbis comment marker
	var found_comments := false
	while file.get_position() < max_search - 7:
		var pos := file.get_position()
		var marker := file.get_buffer(7)
		if marker.size() < 7:
			break

		# Check for vorbis comment header (0x03 + "vorbis")
		if marker[0] == 0x03 and marker.slice(1, 7).get_string_from_ascii() == "vorbis":
			found_comments = true
			break

		# Move forward by 1 byte (sliding window)
		file.seek(pos + 1)

	if found_comments:
		# Read vendor length
		var vendor_length := file.get_32()
		if vendor_length > 0 and vendor_length < 1024:
			file.seek(file.get_position() + vendor_length)  # Skip vendor string

		# Read user comment list length
		var comment_count := file.get_32()

		for i in range(min(comment_count, 100)):  # Limit to 100 comments
			if file.get_position() >= file_size - 4:
				break

			var comment_length := file.get_32()
			if comment_length <= 0 or comment_length > 10000 or file.get_position() + comment_length > file_size:
				break

			var comment_data := file.get_buffer(comment_length)
			var comment := comment_data.get_string_from_utf8()

			# Parse key=value format
			var eq_pos := comment.find("=")
			if eq_pos > 0:
				var key := comment.substr(0, eq_pos).to_upper()
				var value := comment.substr(eq_pos + 1)

				match key:
					"TITLE":
						metadata.title = value
					"ARTIST":
						metadata.artist = value
					"ALBUM":
						metadata.album = value
					"DATE", "YEAR":
						metadata.year = value
					"GENRE":
						metadata.genre = value

	file.close()

	# Check for cover art in separate file (common convention)
	if not metadata.album_art:
		metadata.album_art = _try_load_cover_art(file_path)

	# Fallback to filename if no title found
	if metadata.title.is_empty():
		metadata.title = _clean_filename(file_path.get_file().get_basename())

	return metadata

## Extract metadata from WAV files
static func _extract_wav_metadata(file_path: String) -> AudioMetadata:
	var metadata := AudioMetadata.new()
	var file := FileAccess.open(file_path, FileAccess.READ)

	if not file:
		metadata.title = _clean_filename(file_path.get_file().get_basename())
		return metadata

	# Check RIFF header
	var riff := file.get_buffer(4)
	if riff.size() < 4 or riff.get_string_from_ascii() != "RIFF":
		file.close()
		metadata.title = _clean_filename(file_path.get_file().get_basename())
		return metadata

	var _file_size := file.get_32()
	var wave := file.get_buffer(4)

	if wave.size() < 4 or wave.get_string_from_ascii() != "WAVE":
		file.close()
		metadata.title = _clean_filename(file_path.get_file().get_basename())
		return metadata

	# Look for LIST chunk with INFO
	while file.get_position() < file.get_length() - 8:
		var chunk_id := file.get_buffer(4).get_string_from_ascii()
		var chunk_size := file.get_32()

		if chunk_id == "LIST":
			var list_type := file.get_buffer(4).get_string_from_ascii()
			if list_type == "INFO":
				# Parse INFO sub-chunks
				var info_end := file.get_position() + chunk_size - 4
				while file.get_position() < info_end - 8:
					var info_id := file.get_buffer(4).get_string_from_ascii()
					var info_size := file.get_32()
					if info_size > 0 and file.get_position() + info_size <= info_end:
						var info_data := file.get_buffer(info_size).get_string_from_utf8().strip_edges()
						match info_id:
							"INAM":
								metadata.title = info_data
							"IART":
								metadata.artist = info_data
							"IPRD":
								metadata.album = info_data
							"ICRD":
								metadata.year = info_data
							"IGNR":
								metadata.genre = info_data
					# Align to word boundary
					if info_size % 2 == 1:
						file.seek(file.get_position() + 1)
				break
			else:
				file.seek(file.get_position() + chunk_size - 4)
		else:
			file.seek(file.get_position() + chunk_size)
			# Align to word boundary
			if chunk_size % 2 == 1:
				file.seek(file.get_position() + 1)

	file.close()

	if metadata.title.is_empty():
		metadata.title = _clean_filename(file_path.get_file().get_basename())

	return metadata

## Extract metadata from FLAC files
static func _extract_flac_metadata(file_path: String) -> AudioMetadata:
	var metadata := AudioMetadata.new()
	var file := FileAccess.open(file_path, FileAccess.READ)

	if not file:
		metadata.title = _clean_filename(file_path.get_file().get_basename())
		return metadata

	# Check fLaC marker
	var marker := file.get_buffer(4)
	if marker.size() < 4 or marker.get_string_from_ascii() != "fLaC":
		file.close()
		metadata.title = _clean_filename(file_path.get_file().get_basename())
		return metadata

	# Read metadata blocks
	var last_block := false
	while not last_block and file.get_position() < file.get_length() - 4:
		var block_header := file.get_8()
		last_block = (block_header & 0x80) != 0
		var block_type := block_header & 0x7F

		# Read block size (24-bit big-endian)
		var size_bytes := file.get_buffer(3)
		var block_size: int = (size_bytes[0] << 16) | (size_bytes[1] << 8) | size_bytes[2]

		if block_size <= 0 or file.get_position() + block_size > file.get_length():
			break

		if block_type == 4:  # VORBIS_COMMENT
			# Similar to OGG Vorbis comments
			var vendor_length := file.get_32()
			if vendor_length > 0 and vendor_length < block_size:
				file.seek(file.get_position() + vendor_length)

			var comment_count := file.get_32()
			for i in range(min(comment_count, 100)):
				var comment_length := file.get_32()
				if comment_length <= 0 or comment_length > 10000:
					break
				var comment := file.get_buffer(comment_length).get_string_from_utf8()
				var eq_pos := comment.find("=")
				if eq_pos > 0:
					var key := comment.substr(0, eq_pos).to_upper()
					var value := comment.substr(eq_pos + 1)
					match key:
						"TITLE":
							metadata.title = value
						"ARTIST":
							metadata.artist = value
						"ALBUM":
							metadata.album = value
						"DATE", "YEAR":
							metadata.year = value
						"GENRE":
							metadata.genre = value
		elif block_type == 6:  # PICTURE
			metadata.album_art = _read_flac_picture(file, block_size)
		else:
			file.seek(file.get_position() + block_size)

	file.close()

	if metadata.title.is_empty():
		metadata.title = _clean_filename(file_path.get_file().get_basename())

	return metadata

## Read FLAC picture block
static func _read_flac_picture(file: FileAccess, _block_size: int) -> ImageTexture:
	var _picture_type := file.get_32()  # Big-endian

	# Read MIME type length and string
	var mime_length := file.get_32()
	var mime_type := ""
	if mime_length > 0 and mime_length < 256:
		mime_type = file.get_buffer(mime_length).get_string_from_ascii()

	# Read description length and skip
	var desc_length := file.get_32()
	if desc_length > 0:
		file.seek(file.get_position() + desc_length)

	# Skip width, height, color depth, colors used
	file.seek(file.get_position() + 16)

	# Read picture data
	var data_length := file.get_32()
	if data_length <= 0 or data_length > 10000000:  # 10MB limit
		return null

	var image_data := file.get_buffer(data_length)
	return _create_texture_from_data(image_data, mime_type)

## Helper to validate frame ID (alphanumeric)
static func _is_valid_frame_id(frame_id: String) -> bool:
	if frame_id.length() != 4:
		return false
	for i in range(4):
		var c := frame_id.unicode_at(i)
		if not ((c >= 65 and c <= 90) or (c >= 48 and c <= 57)):  # A-Z or 0-9
			return false
	return true

## Clean up filename for display
static func _clean_filename(filename: String) -> String:
	# Remove common prefixes like track numbers
	var cleaned := filename
	# Remove patterns like "01 - ", "01. ", "01_"
	var regex := RegEx.new()
	if regex.compile("^\\d{1,3}[\\s._-]+") == OK:
		var result := regex.search(cleaned)
		if result:
			cleaned = cleaned.substr(result.get_end())
	return cleaned.strip_edges()

## Parse genre string (handle ID3v1 genre codes)
static func _parse_genre(genre_str: String) -> String:
	if genre_str.is_empty():
		return ""

	# Check for numeric genre code like "(17)" or "17"
	var regex := RegEx.new()
	if regex.compile("^\\(?\\d+\\)?$") == OK:
		var result := regex.search(genre_str.strip_edges())
		if result:
			var code := genre_str.replace("(", "").replace(")", "").to_int()
			return _get_genre_name(code)

	# Handle mixed format like "(17)Rock"
	if regex.compile("^\\(\\d+\\)(.+)$") == OK:
		var result := regex.search(genre_str)
		if result:
			return result.get_string(1)

	return genre_str

## Get genre name from ID3v1 code
static func _get_genre_name(code: int) -> String:
	var genres := [
		"Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge",
		"Hip-Hop", "Jazz", "Metal", "New Age", "Oldies", "Other", "Pop", "R&B",
		"Rap", "Reggae", "Rock", "Techno", "Industrial", "Alternative", "Ska",
		"Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient",
		"Trip-Hop", "Vocal", "Jazz+Funk", "Fusion", "Trance", "Classical",
		"Instrumental", "Acid", "House", "Game", "Sound Clip", "Gospel",
		"Noise", "Alternative Rock", "Bass", "Soul", "Punk", "Space",
		"Meditative", "Instrumental Pop", "Instrumental Rock", "Ethnic",
		"Gothic", "Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk",
		"Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
		"Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native US",
		"Cabaret", "New Wave", "Psychedelic", "Rave", "Showtunes", "Trailer",
		"Lo-Fi", "Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro",
		"Musical", "Rock & Roll", "Hard Rock"
	]
	if code >= 0 and code < genres.size():
		return genres[code]
	return "Unknown"

## Read a synchsafe integer (used in ID3v2)
static func _read_synchsafe_int(file: FileAccess) -> int:
	var bytes := file.get_buffer(4)
	if bytes.size() < 4:
		return 0
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
			return _decode_utf16_with_bom(text_buffer).strip_edges()
		2:  # UTF-16BE without BOM
			return text_buffer.get_string_from_utf16().strip_edges()
		3:  # UTF-8
			return text_buffer.get_string_from_utf8().strip_edges()
		_:
			return text_buffer.get_string_from_utf8().strip_edges()

## Decode UTF-16 with BOM handling
static func _decode_utf16_with_bom(buffer: PackedByteArray) -> String:
	if buffer.size() < 2:
		return buffer.get_string_from_utf8()

	# Check BOM
	if buffer[0] == 0xFF and buffer[1] == 0xFE:
		# Little-endian UTF-16
		return buffer.slice(2).get_string_from_utf16()
	elif buffer[0] == 0xFE and buffer[1] == 0xFF:
		# Big-endian UTF-16 - need to swap bytes
		var swapped := PackedByteArray()
		for i in range(2, buffer.size() - 1, 2):
			swapped.append(buffer[i + 1])
			swapped.append(buffer[i])
		return swapped.get_string_from_utf16()
	else:
		return buffer.get_string_from_utf16()

## Read an APIC frame (album art) from ID3v2
static func _read_apic_frame(file: FileAccess, size: int) -> ImageTexture:
	if size <= 0:
		return null

	var start_pos := file.get_position()

	# First byte is text encoding
	var _encoding := file.get_8()

	# Read MIME type (null-terminated string)
	var mime_type := ""
	var bytes_read := 1
	while bytes_read < size:
		var byte := file.get_8()
		bytes_read += 1
		if byte == 0:
			break
		mime_type += char(byte)

	if bytes_read >= size:
		return null

	# Read picture type
	var _picture_type := file.get_8()
	bytes_read += 1

	# Read description (null-terminated string, may be UTF-16)
	while bytes_read < size:
		var byte := file.get_8()
		bytes_read += 1
		if byte == 0:
			break

	# Calculate image data size
	var image_size := size - bytes_read

	if image_size <= 0:
		return null

	# Read image data
	var image_data := file.get_buffer(image_size)

	return _create_texture_from_data(image_data, mime_type)

## Create texture from image data
static func _create_texture_from_data(image_data: PackedByteArray, mime_type: String) -> ImageTexture:
	if image_data.is_empty():
		return null

	var image := Image.new()
	var err: Error

	# Try to load based on MIME type or by trying different formats
	mime_type = mime_type.to_lower()
	if "jpeg" in mime_type or "jpg" in mime_type:
		err = image.load_jpg_from_buffer(image_data)
	elif "png" in mime_type:
		err = image.load_png_from_buffer(image_data)
	elif "webp" in mime_type:
		err = image.load_webp_from_buffer(image_data)
	elif "bmp" in mime_type:
		err = image.load_bmp_from_buffer(image_data)
	else:
		# Try to detect format from magic bytes
		if image_data.size() >= 3:
			if image_data[0] == 0xFF and image_data[1] == 0xD8:
				err = image.load_jpg_from_buffer(image_data)
			elif image_data[0] == 0x89 and image_data[1] == 0x50:
				err = image.load_png_from_buffer(image_data)
			else:
				# Try PNG first, then JPEG
				err = image.load_png_from_buffer(image_data)
				if err != OK:
					err = image.load_jpg_from_buffer(image_data)
		else:
			err = image.load_png_from_buffer(image_data)
			if err != OK:
				err = image.load_jpg_from_buffer(image_data)

	if err != OK:
		return null

	# Resize if too large (for memory efficiency)
	if image.get_width() > 512 or image.get_height() > 512:
		image.resize(512, 512, Image.INTERPOLATE_LANCZOS)

	return ImageTexture.create_from_image(image)

## Try to load cover art from common file names in the same directory
static func _try_load_cover_art(audio_file_path: String) -> ImageTexture:
	var dir := audio_file_path.get_base_dir()
	var cover_names := ["cover", "folder", "album", "front", "art", "albumart"]
	var extensions := [".jpg", ".jpeg", ".png", ".webp"]

	for cover_name in cover_names:
		for ext in extensions:
			var cover_path := dir.path_join(cover_name + ext)
			if FileAccess.file_exists(cover_path):
				var image := Image.new()
				if image.load(cover_path) == OK:
					if image.get_width() > 512 or image.get_height() > 512:
						image.resize(512, 512, Image.INTERPOLATE_LANCZOS)
					return ImageTexture.create_from_image(image)
			# Try uppercase
			cover_path = dir.path_join(cover_name.to_upper() + ext.to_upper())
			if FileAccess.file_exists(cover_path):
				var image := Image.new()
				if image.load(cover_path) == OK:
					if image.get_width() > 512 or image.get_height() > 512:
						image.resize(512, 512, Image.INTERPOLATE_LANCZOS)
					return ImageTexture.create_from_image(image)

	return null
