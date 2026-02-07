extends Node

## Marble Material Manager
## Creates distinct colored marble materials for each player using StandardMaterial3D
## Generates a stripe texture so rolling is visible

# Predefined color schemes for variety - all highly distinct
const COLOR_SCHEMES = [
	# Primary vibrant colors
	{"name": "Ruby Red", "primary": Color(1.0, 0.0, 0.1)},
	{"name": "Sapphire Blue", "primary": Color(0.0, 0.2, 1.0)},
	{"name": "Emerald Green", "primary": Color(0.0, 0.9, 0.2)},
	{"name": "Bright Purple", "primary": Color(0.7, 0.0, 1.0)},
	{"name": "Vivid Orange", "primary": Color(1.0, 0.45, 0.0)},
	{"name": "Hot Pink", "primary": Color(1.0, 0.0, 0.5)},
	{"name": "Bright Cyan", "primary": Color(0.0, 0.9, 1.0)},
	{"name": "Sunny Yellow", "primary": Color(1.0, 0.9, 0.0)},

	# Pure primary colors
	{"name": "Blood Red", "primary": Color(0.8, 0.0, 0.0)},
	{"name": "Deep Blue", "primary": Color(0.0, 0.0, 1.0)},
	{"name": "Poison Green", "primary": Color(0.6, 1.0, 0.0)},
	{"name": "Pure Yellow", "primary": Color(1.0, 1.0, 0.0)},

	# Distinct darks
	{"name": "Midnight Black", "primary": Color(0.05, 0.05, 0.08)},
	{"name": "Navy Blue", "primary": Color(0.0, 0.0, 0.5)},
	{"name": "Chocolate Brown", "primary": Color(0.5, 0.25, 0.1)},

	# Unique tones
	{"name": "Salmon Pink", "primary": Color(1.0, 0.55, 0.45)},
	{"name": "Jade Green", "primary": Color(0.0, 0.65, 0.5)},
	{"name": "Lavender", "primary": Color(0.7, 0.5, 1.0)},
	{"name": "Mint Green", "primary": Color(0.4, 1.0, 0.7)},

	# Special colors
	{"name": "Deep Black", "primary": Color(0.1, 0.1, 0.15)},
	{"name": "Pearl", "primary": Color(0.92, 0.9, 0.95)},
	{"name": "Bright Gold", "primary": Color(1.0, 0.75, 0.0)},
	{"name": "Chrome Silver", "primary": Color(0.65, 0.7, 0.75)},

	# Bold unique colors
	{"name": "Electric Magenta", "primary": Color(1.0, 0.0, 0.8)},
	{"name": "Electric Lime", "primary": Color(0.5, 1.0, 0.0)},
	{"name": "Teal", "primary": Color(0.0, 0.7, 0.65)},
	{"name": "Deep Indigo", "primary": Color(0.2, 0.0, 0.6)},
]

# Track used color indices to avoid duplicates when possible
var used_colors: Array = []

# Texture cache so we don't regenerate for the same color
var _texture_cache: Dictionary = {}

func _generate_stripe_texture(primary: Color) -> ImageTexture:
	"""Generate a simple stripe texture so rolling is visible"""
	var cache_key: int = primary.to_rgba32()
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]

	var size: int = 64
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)

	# Derive a contrasting stripe color from the primary
	var stripe: Color
	var brightness: float = primary.r * 0.299 + primary.g * 0.587 + primary.b * 0.114
	if brightness > 0.5:
		# Dark stripe on light marble
		stripe = primary.darkened(0.35)
	else:
		# Light stripe on dark marble
		stripe = primary.lightened(0.35)

	# Paint horizontal stripes (4 bands visible on the sphere)
	var band_count: int = 4
	var band_height: int = size / (band_count * 2)
	for y in range(size):
		var in_stripe: bool = (y / band_height) % 2 == 1
		var color: Color = stripe if in_stripe else primary
		for x in range(size):
			img.set_pixel(x, y, color)

	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_texture_cache[cache_key] = tex
	return tex

func create_marble_material(color_index: int = -1) -> StandardMaterial3D:
	"""Create a unique marble material with optional specific color index"""
	var scheme: Dictionary
	if color_index >= 0 and color_index < COLOR_SCHEMES.size():
		scheme = COLOR_SCHEMES[color_index]
	else:
		var available_colors = []
		for i in range(COLOR_SCHEMES.size()):
			if not used_colors.has(i):
				available_colors.append(i)

		if available_colors.is_empty():
			color_index = randi() % COLOR_SCHEMES.size()
		else:
			color_index = available_colors[randi() % available_colors.size()]

		scheme = COLOR_SCHEMES[color_index]
		used_colors.append(color_index)

	var material = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE  # Texture provides the color
	material.albedo_texture = _generate_stripe_texture(scheme.primary)
	material.metallic = 0.3
	material.roughness = 0.15
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return material

func create_marble_material_from_hue(hue: float) -> StandardMaterial3D:
	"""Create a marble material from a specific hue value (0.0 to 1.0)"""
	var primary: Color = Color.from_hsv(hue, 0.85, 0.9)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.albedo_texture = _generate_stripe_texture(primary)
	material.metallic = 0.3
	material.roughness = 0.15
	return material

func get_random_marble_material() -> StandardMaterial3D:
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
