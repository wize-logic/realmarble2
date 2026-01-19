extends Node

## Marble Material Manager
## Creates beautiful, unique marble materials for each player

# Pre-load the marble shader
const MARBLE_SHADER = preload("res://scripts/shaders/marble_shader.gdshader")

# Predefined color schemes for variety
const COLOR_SCHEMES = [
	# Classic vibrant colors
	{"name": "Ruby Red", "primary": Color(0.9, 0.1, 0.15), "secondary": Color(1.0, 0.3, 0.35), "swirl": Color(1.0, 0.6, 0.65)},
	{"name": "Sapphire Blue", "primary": Color(0.1, 0.3, 0.9), "secondary": Color(0.3, 0.5, 1.0), "swirl": Color(0.6, 0.75, 1.0)},
	{"name": "Emerald Green", "primary": Color(0.1, 0.8, 0.3), "secondary": Color(0.3, 0.95, 0.5), "swirl": Color(0.6, 1.0, 0.75)},
	{"name": "Amethyst Purple", "primary": Color(0.6, 0.2, 0.9), "secondary": Color(0.75, 0.4, 1.0), "swirl": Color(0.85, 0.65, 1.0)},
	{"name": "Topaz Orange", "primary": Color(1.0, 0.5, 0.1), "secondary": Color(1.0, 0.7, 0.3), "swirl": Color(1.0, 0.85, 0.6)},
	{"name": "Aquamarine", "primary": Color(0.2, 0.8, 0.85), "secondary": Color(0.4, 0.9, 0.95), "swirl": Color(0.7, 1.0, 1.0)},
	{"name": "Rose Quartz", "primary": Color(0.95, 0.5, 0.7), "secondary": Color(1.0, 0.7, 0.85), "swirl": Color(1.0, 0.85, 0.95)},
	{"name": "Citrine Yellow", "primary": Color(0.95, 0.85, 0.2), "secondary": Color(1.0, 0.95, 0.4), "swirl": Color(1.0, 1.0, 0.7)},

	# Metallic/Special colors
	{"name": "Obsidian Black", "primary": Color(0.15, 0.15, 0.2), "secondary": Color(0.25, 0.25, 0.35), "swirl": Color(0.4, 0.4, 0.5)},
	{"name": "Pearl White", "primary": Color(0.9, 0.9, 0.95), "secondary": Color(0.95, 0.95, 1.0), "swirl": Color(1.0, 1.0, 1.0)},
	{"name": "Gold", "primary": Color(0.85, 0.65, 0.15), "secondary": Color(0.95, 0.8, 0.3), "swirl": Color(1.0, 0.95, 0.6)},
	{"name": "Silver", "primary": Color(0.7, 0.75, 0.8), "secondary": Color(0.85, 0.88, 0.9), "swirl": Color(0.95, 0.97, 1.0)},

	# Exotic colors
	{"name": "Magenta Dream", "primary": Color(0.9, 0.2, 0.7), "secondary": Color(1.0, 0.4, 0.85), "swirl": Color(1.0, 0.7, 0.95)},
	{"name": "Lime Burst", "primary": Color(0.6, 0.95, 0.2), "secondary": Color(0.75, 1.0, 0.4), "swirl": Color(0.85, 1.0, 0.7)},
	{"name": "Turquoise", "primary": Color(0.2, 0.8, 0.7), "secondary": Color(0.4, 0.95, 0.85), "swirl": Color(0.7, 1.0, 0.95)},
	{"name": "Violet Storm", "primary": Color(0.4, 0.15, 0.7), "secondary": Color(0.6, 0.35, 0.85), "swirl": Color(0.75, 0.6, 0.95)},
]

# Track used color indices to avoid duplicates when possible
var used_colors: Array = []

func create_marble_material(color_index: int = -1) -> ShaderMaterial:
	"""Create a unique marble material with optional specific color index"""
	var material = ShaderMaterial.new()
	material.shader = MARBLE_SHADER

	# Select color scheme
	var scheme: Dictionary
	if color_index >= 0 and color_index < COLOR_SCHEMES.size():
		scheme = COLOR_SCHEMES[color_index]
	else:
		# Pick a random unused color, or random if all used
		var available_colors = []
		for i in range(COLOR_SCHEMES.size()):
			if not used_colors.has(i):
				available_colors.append(i)

		if available_colors.is_empty():
			# All colors used, pick random
			color_index = randi() % COLOR_SCHEMES.size()
		else:
			# Pick random from available
			color_index = available_colors[randi() % available_colors.size()]

		scheme = COLOR_SCHEMES[color_index]
		used_colors.append(color_index)

	# Apply color scheme
	material.set_shader_parameter("primary_color", scheme.primary)
	material.set_shader_parameter("secondary_color", scheme.secondary)
	material.set_shader_parameter("swirl_color", scheme.swirl)

	# Set material properties with slight randomization
	material.set_shader_parameter("glossiness", randf_range(0.8, 0.95))
	material.set_shader_parameter("metallic_amount", randf_range(0.2, 0.4))
	material.set_shader_parameter("transparency", randf_range(0.1, 0.2))

	# Randomize pattern properties for uniqueness
	material.set_shader_parameter("swirl_scale", randf_range(1.5, 2.5))
	material.set_shader_parameter("swirl_intensity", randf_range(0.5, 0.7))
	material.set_shader_parameter("bubble_density", randf_range(0.3, 0.5))
	material.set_shader_parameter("time_speed", randf_range(0.15, 0.25))

	return material

func create_marble_material_from_hue(hue: float) -> ShaderMaterial:
	"""Create a marble material from a specific hue value (0.0 to 1.0)"""
	var material = ShaderMaterial.new()
	material.shader = MARBLE_SHADER

	# Generate colors from hue
	var primary = Color.from_hsv(hue, 0.85, 0.9)
	var secondary = Color.from_hsv(hue, 0.7, 1.0)
	var swirl = Color.from_hsv(hue, 0.4, 1.0)

	material.set_shader_parameter("primary_color", primary)
	material.set_shader_parameter("secondary_color", secondary)
	material.set_shader_parameter("swirl_color", swirl)

	# Set material properties
	material.set_shader_parameter("glossiness", 0.85)
	material.set_shader_parameter("metallic_amount", 0.3)
	material.set_shader_parameter("transparency", 0.15)
	material.set_shader_parameter("swirl_scale", 2.0)
	material.set_shader_parameter("swirl_intensity", 0.6)
	material.set_shader_parameter("bubble_density", 0.4)
	material.set_shader_parameter("time_speed", 0.2)

	return material

func get_random_marble_material() -> ShaderMaterial:
	"""Get a completely random marble material"""
	return create_marble_material(-1)

func reset_used_colors() -> void:
	"""Reset the used colors tracker"""
	used_colors.clear()

func get_color_scheme_name(index: int) -> String:
	"""Get the name of a color scheme by index"""
	if index >= 0 and index < COLOR_SCHEMES.size():
		return COLOR_SCHEMES[index].name
	return "Unknown"

func get_color_scheme_count() -> int:
	"""Get the total number of available color schemes"""
	return COLOR_SCHEMES.size()
