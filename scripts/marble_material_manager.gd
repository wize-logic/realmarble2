extends Node

## Marble Material Manager
## Creates beautiful, unique marble materials for each player

# Pre-load the marble shader
const MARBLE_SHADER = preload("res://scripts/shaders/marble_shader.gdshader")
const ROLL_TEXTURE = preload("res://textures/kenney_prototype_textures/orange/texture_07.png")
const COMPATIBILITY_RENDERER_SETTING := "rendering/renderer/rendering_method"

# Predefined color schemes for variety - all highly distinct
const COLOR_SCHEMES = [
	# Primary vibrant colors - very distinct from each other
	{"name": "Ruby Red", "primary": Color(1.0, 0.0, 0.1), "secondary": Color(1.0, 0.2, 0.25), "swirl": Color(1.0, 0.5, 0.55)},
	{"name": "Sapphire Blue", "primary": Color(0.0, 0.2, 1.0), "secondary": Color(0.2, 0.4, 1.0), "swirl": Color(0.5, 0.7, 1.0)},
	{"name": "Emerald Green", "primary": Color(0.0, 0.9, 0.2), "secondary": Color(0.2, 1.0, 0.4), "swirl": Color(0.5, 1.0, 0.7)},
	{"name": "Bright Purple", "primary": Color(0.7, 0.0, 1.0), "secondary": Color(0.8, 0.3, 1.0), "swirl": Color(0.9, 0.6, 1.0)},
	{"name": "Vivid Orange", "primary": Color(1.0, 0.45, 0.0), "secondary": Color(1.0, 0.65, 0.2), "swirl": Color(1.0, 0.8, 0.5)},
	{"name": "Hot Pink", "primary": Color(1.0, 0.0, 0.5), "secondary": Color(1.0, 0.3, 0.7), "swirl": Color(1.0, 0.6, 0.85)},
	{"name": "Bright Cyan", "primary": Color(0.0, 0.9, 1.0), "secondary": Color(0.3, 1.0, 1.0), "swirl": Color(0.6, 1.0, 1.0)},
	{"name": "Sunny Yellow", "primary": Color(1.0, 0.9, 0.0), "secondary": Color(1.0, 1.0, 0.3), "swirl": Color(1.0, 1.0, 0.6)},

	# Pure primary colors (maximum saturation)
	{"name": "Blood Red", "primary": Color(0.8, 0.0, 0.0), "secondary": Color(0.9, 0.1, 0.1), "swirl": Color(1.0, 0.3, 0.3)},
	{"name": "Deep Blue", "primary": Color(0.0, 0.0, 1.0), "secondary": Color(0.1, 0.1, 1.0), "swirl": Color(0.3, 0.3, 1.0)},
	{"name": "Poison Green", "primary": Color(0.6, 1.0, 0.0), "secondary": Color(0.75, 1.0, 0.2), "swirl": Color(0.85, 1.0, 0.4)},
	{"name": "Pure Yellow", "primary": Color(1.0, 1.0, 0.0), "secondary": Color(1.0, 1.0, 0.15), "swirl": Color(1.0, 1.0, 0.4)},

	# Distinct darks (high contrast)
	{"name": "Midnight Black", "primary": Color(0.05, 0.05, 0.08), "secondary": Color(0.1, 0.1, 0.15), "swirl": Color(0.2, 0.2, 0.25)},
	{"name": "Navy Blue", "primary": Color(0.0, 0.0, 0.5), "secondary": Color(0.1, 0.1, 0.65), "swirl": Color(0.2, 0.2, 0.8)},
	{"name": "Chocolate Brown", "primary": Color(0.5, 0.25, 0.1), "secondary": Color(0.65, 0.35, 0.2), "swirl": Color(0.8, 0.5, 0.35)},

	# Unique tones (distinct pastels and vivids)
	{"name": "Salmon Pink", "primary": Color(1.0, 0.55, 0.45), "secondary": Color(1.0, 0.7, 0.6), "swirl": Color(1.0, 0.85, 0.8)},
	{"name": "Jade Green", "primary": Color(0.0, 0.65, 0.5), "secondary": Color(0.2, 0.8, 0.65), "swirl": Color(0.4, 0.95, 0.8)},
	{"name": "Lavender", "primary": Color(0.7, 0.5, 1.0), "secondary": Color(0.8, 0.65, 1.0), "swirl": Color(0.9, 0.8, 1.0)},
	{"name": "Mint Green", "primary": Color(0.4, 1.0, 0.7), "secondary": Color(0.55, 1.0, 0.8), "swirl": Color(0.7, 1.0, 0.9)},

	# Additional special colors
	{"name": "Deep Black", "primary": Color(0.1, 0.1, 0.15), "secondary": Color(0.2, 0.2, 0.3), "swirl": Color(0.35, 0.35, 0.45)},
	{"name": "Pearl", "primary": Color(0.92, 0.9, 0.95), "secondary": Color(0.88, 0.88, 0.95), "swirl": Color(0.82, 0.82, 0.9)},  # Pearlescent (not pure white)
	{"name": "Bright Gold", "primary": Color(1.0, 0.75, 0.0), "secondary": Color(1.0, 0.85, 0.2), "swirl": Color(1.0, 0.95, 0.5)},
	{"name": "Chrome Silver", "primary": Color(0.65, 0.7, 0.75), "secondary": Color(0.8, 0.85, 0.9), "swirl": Color(0.9, 0.95, 1.0)},

	# Bold unique colors
	{"name": "Electric Magenta", "primary": Color(1.0, 0.0, 0.8), "secondary": Color(1.0, 0.2, 0.9), "swirl": Color(1.0, 0.5, 1.0)},
	{"name": "Electric Lime", "primary": Color(0.5, 1.0, 0.0), "secondary": Color(0.7, 1.0, 0.3), "swirl": Color(0.8, 1.0, 0.6)},
	{"name": "Teal", "primary": Color(0.0, 0.7, 0.65), "secondary": Color(0.2, 0.85, 0.8), "swirl": Color(0.5, 1.0, 0.95)},
	{"name": "Deep Indigo", "primary": Color(0.2, 0.0, 0.6), "secondary": Color(0.35, 0.2, 0.75), "swirl": Color(0.5, 0.4, 0.9)},
]

# Track used color indices to avoid duplicates when possible
var used_colors: Array = []

func create_marble_material(color_index: int = -1) -> Material:
	"""Create a unique marble material with optional specific color index"""
	if _should_use_standard_material():
		return _create_standard_marble_material(color_index)

	var material = ShaderMaterial.new()
	material.shader = MARBLE_SHADER

	# Select color scheme
	var scheme := _resolve_color_scheme(color_index)
	var boosted_primary := _boost_color(scheme.primary)
	var boosted_secondary := _boost_color(scheme.secondary)
	var boosted_swirl := _boost_color(scheme.swirl)

	# Apply color scheme
	material.set_shader_parameter("primary_color", boosted_primary)
	material.set_shader_parameter("secondary_color", boosted_secondary)
	material.set_shader_parameter("swirl_color", boosted_swirl)

	# Set material properties with slight randomization
	material.set_shader_parameter("glossiness", randf_range(0.4, 0.6))
	material.set_shader_parameter("metallic_amount", randf_range(0.05, 0.15))
	material.set_shader_parameter("transparency", 0.02)  # Fixed low transparency for opaque marbles

	# Randomize pattern properties for uniqueness
	material.set_shader_parameter("swirl_scale", randf_range(1.5, 2.5))
	material.set_shader_parameter("swirl_intensity", randf_range(0.5, 0.7))
	material.set_shader_parameter("bubble_density", randf_range(0.3, 0.5))
	material.set_shader_parameter("time_speed", randf_range(0.15, 0.25))

	# Special marble lighting - subtle glow to help marbles stand out (reduced from previous bright values)
	material.set_shader_parameter("glow_strength", randf_range(0.08, 0.15))
	material.set_shader_parameter("glow_pulse_speed", randf_range(1.0, 1.4))
	material.set_shader_parameter("glow_pulse_amount", randf_range(0.05, 0.1))
	material.set_shader_parameter("outer_rim_power", randf_range(2.0, 2.5))
	material.set_shader_parameter("outer_rim_intensity", randf_range(0.15, 0.25))
	material.set_shader_parameter("rim_intensity", randf_range(0.12, 0.2))

	return material

func _create_standard_marble_material(color_index: int = -1) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var scheme := _resolve_color_scheme(color_index)
	material.albedo_color = _boost_color(scheme.primary)
	material.albedo_texture = ROLL_TEXTURE
	material.emission_enabled = true
	material.emission = material.albedo_color * 0.2
	material.roughness = randf_range(0.6, 0.75)
	material.metallic = randf_range(0.0, 0.05)
	material.specular = 0.1
	material.uv1_scale = Vector3(2.0, 2.0, 2.0)
	return material

func _resolve_color_scheme(color_index: int = -1) -> Dictionary:
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
	return scheme

func _should_use_standard_material() -> bool:
	if not ProjectSettings.has_setting(COMPATIBILITY_RENDERER_SETTING):
		return false
	var rendering_method := str(ProjectSettings.get_setting(COMPATIBILITY_RENDERER_SETTING))
	return rendering_method == "compatibility" or rendering_method == "gl_compatibility"

func create_marble_material_from_hue(hue: float) -> Material:
	"""Create a marble material from a specific hue value (0.0 to 1.0)"""
	if _should_use_standard_material():
		var material := StandardMaterial3D.new()
		material.albedo_color = _boost_color(Color.from_hsv(hue, 0.85, 0.9))
		material.albedo_texture = ROLL_TEXTURE
		material.emission_enabled = true
		material.emission = material.albedo_color * 0.2
		material.roughness = 0.7
		material.metallic = 0.05
		material.specular = 0.1
		material.uv1_scale = Vector3(2.0, 2.0, 2.0)
		return material

	var material = ShaderMaterial.new()
	material.shader = MARBLE_SHADER

	# Generate colors from hue
	var primary = Color.from_hsv(hue, 0.85, 0.9)
	var secondary = Color.from_hsv(hue, 0.7, 1.0)
	var swirl = Color.from_hsv(hue, 0.4, 1.0)

	material.set_shader_parameter("primary_color", _boost_color(primary))
	material.set_shader_parameter("secondary_color", _boost_color(secondary))
	material.set_shader_parameter("swirl_color", _boost_color(swirl))

	# Set material properties
	material.set_shader_parameter("glossiness", 0.5)
	material.set_shader_parameter("metallic_amount", 0.1)
	material.set_shader_parameter("transparency", 0.02)  # Much less translucent
	material.set_shader_parameter("swirl_scale", 2.0)
	material.set_shader_parameter("swirl_intensity", 0.6)
	material.set_shader_parameter("bubble_density", 0.4)
	material.set_shader_parameter("time_speed", 0.2)

	# Special marble lighting - subtle glow to help marbles stand out (reduced from previous bright values)
	material.set_shader_parameter("glow_strength", 0.12)
	material.set_shader_parameter("glow_pulse_speed", 1.2)
	material.set_shader_parameter("glow_pulse_amount", 0.08)
	material.set_shader_parameter("outer_rim_power", 2.2)
	material.set_shader_parameter("outer_rim_intensity", 0.2)
	material.set_shader_parameter("rim_intensity", 0.15)

	return material

func get_random_marble_material() -> Material:
	"""Get a completely random marble material"""
	return create_marble_material(-1)

func _boost_color(color: Color) -> Color:
	var h := color.h
	var s := minf(color.s * 1.4, 1.0)
	var v := minf(color.v * 1.35, 1.0)
	return Color.from_hsv(h, s, v)

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
