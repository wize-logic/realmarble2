extends Node
class_name SoundGenerator

## Generates simple placeholder sound effects for menu

static func generate_hover_sound() -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	var sample_rate: int = 22050
	var duration: float = 0.1
	var frequency: float = 800.0

	var data: PackedByteArray = PackedByteArray()
	var sample_count: int = int(sample_rate * duration)

	for i in range(sample_count):
		var t: float = float(i) / sample_rate
		var envelope: float = 1.0 - (t / duration)  # Fade out
		var sample: float = sin(t * frequency * TAU) * envelope * 0.3
		var sample_int: int = int(clamp(sample, -1.0, 1.0) * 32767.0)

		# Write 16-bit stereo samples (little-endian)
		data.append(sample_int & 0xFF)
		data.append((sample_int >> 8) & 0xFF)
		data.append(sample_int & 0xFF)
		data.append((sample_int >> 8) & 0xFF)

	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = true

	return stream

static func generate_select_sound() -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	var sample_rate: int = 22050
	var duration: float = 0.15
	var start_freq: float = 600.0
	var end_freq: float = 800.0

	var data: PackedByteArray = PackedByteArray()
	var sample_count: int = int(sample_rate * duration)

	for i in range(sample_count):
		var t: float = float(i) / sample_rate
		var progress: float = t / duration
		var envelope: float = 1.0 - progress  # Fade out
		var frequency: float = lerp(start_freq, end_freq, progress)
		var sample: float = sin(t * frequency * TAU) * envelope * 0.4
		var sample_int: int = int(clamp(sample, -1.0, 1.0) * 32767.0)

		# Write 16-bit stereo samples (little-endian)
		data.append(sample_int & 0xFF)
		data.append((sample_int >> 8) & 0xFF)
		data.append(sample_int & 0xFF)
		data.append((sample_int >> 8) & 0xFF)

	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = true

	return stream
