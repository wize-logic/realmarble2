extends Node

## Procedural Material Manager
## Creates and applies beautiful context-aware materials to level geometry

# Pre-load the shader
const PROCEDURAL_SHADER = preload("res://scripts/shaders/procedural_surface.gdshader")

# Material presets for different surface types
const MATERIAL_PRESETS = {
	"floor": {
		"base_color": Color(0.35, 0.38, 0.42),  # Cool gray
		"accent_color": Color(0.25, 0.28, 0.32),
		"roughness": 0.85,
		"metallic": 0.15,
		"scale": 3.0,
		"pattern_mix": 0.6,
		"detail_strength": 0.4,
		"wear_amount": 0.3
	},
	"wall": {
		"base_color": Color(0.45, 0.42, 0.38),  # Warm concrete
		"accent_color": Color(0.35, 0.32, 0.28),
		"roughness": 0.9,
		"metallic": 0.0,
		"scale": 2.5,
		"pattern_mix": 0.4,
		"detail_strength": 0.5,
		"wear_amount": 0.4
	},
	"platform": {
		"base_color": Color(0.28, 0.42, 0.52),  # Blue-gray metal
		"accent_color": Color(0.18, 0.32, 0.42),
		"roughness": 0.7,
		"metallic": 0.4,
		"scale": 4.0,
		"pattern_mix": 0.7,
		"detail_strength": 0.35,
		"wear_amount": 0.25
	},
	"ramp": {
		"base_color": Color(0.48, 0.38, 0.28),  # Rust/copper
		"accent_color": Color(0.38, 0.28, 0.18),
		"roughness": 0.75,
		"metallic": 0.3,
		"scale": 3.5,
		"pattern_mix": 0.5,
		"detail_strength": 0.4,
		"wear_amount": 0.35
	},
	"pillar": {
		"base_color": Color(0.38, 0.35, 0.32),  # Dark stone
		"accent_color": Color(0.28, 0.25, 0.22),
		"roughness": 0.95,
		"metallic": 0.0,
		"scale": 2.0,
		"pattern_mix": 0.3,
		"detail_strength": 0.6,
		"wear_amount": 0.5
	},
	"cover": {
		"base_color": Color(0.42, 0.38, 0.32),  # Military gray-brown
		"accent_color": Color(0.32, 0.28, 0.22),
		"roughness": 0.8,
		"metallic": 0.2,
		"scale": 5.0,
		"pattern_mix": 0.45,
		"detail_strength": 0.3,
		"wear_amount": 0.4
	},
	"room_floor": {
		"base_color": Color(0.32, 0.35, 0.38),  # Cool industrial
		"accent_color": Color(0.22, 0.25, 0.28),
		"roughness": 0.85,
		"metallic": 0.1,
		"scale": 4.5,
		"pattern_mix": 0.65,
		"detail_strength": 0.45,
		"wear_amount": 0.35
	},
	"room_wall": {
		"base_color": Color(0.38, 0.42, 0.45),  # Tech facility
		"accent_color": Color(0.28, 0.32, 0.35),
		"roughness": 0.8,
		"metallic": 0.25,
		"scale": 3.0,
		"pattern_mix": 0.55,
		"detail_strength": 0.4,
		"wear_amount": 0.3
	},
	"corridor": {
		"base_color": Color(0.35, 0.38, 0.40),  # Neutral corridor
		"accent_color": Color(0.25, 0.28, 0.30),
		"roughness": 0.85,
		"metallic": 0.15,
		"scale": 3.5,
		"pattern_mix": 0.5,
		"detail_strength": 0.35,
		"wear_amount": 0.3
	}
}

func create_material(preset_name: String, color_variation: float = 0.0) -> ShaderMaterial:
	"""Create a procedural material from a preset with optional color variation"""
	var material = ShaderMaterial.new()
	material.shader = PROCEDURAL_SHADER

	var preset = MATERIAL_PRESETS.get(preset_name, MATERIAL_PRESETS["floor"])

	# Apply preset values
	material.set_shader_parameter("base_color", preset.base_color)
	material.set_shader_parameter("accent_color", preset.accent_color)
	material.set_shader_parameter("roughness", preset.roughness)
	material.set_shader_parameter("metallic", preset.metallic)
	material.set_shader_parameter("scale", preset.scale)
	material.set_shader_parameter("pattern_mix", preset.pattern_mix)
	material.set_shader_parameter("detail_strength", preset.detail_strength)
	material.set_shader_parameter("wear_amount", preset.wear_amount)

	# Add color variation if specified
	if color_variation > 0.0:
		var varied_base = Color(
			preset.base_color.r + randf_range(-color_variation, color_variation),
			preset.base_color.g + randf_range(-color_variation, color_variation),
			preset.base_color.b + randf_range(-color_variation, color_variation)
		)
		var varied_accent = Color(
			preset.accent_color.r + randf_range(-color_variation, color_variation),
			preset.accent_color.g + randf_range(-color_variation, color_variation),
			preset.accent_color.b + randf_range(-color_variation, color_variation)
		)
		material.set_shader_parameter("base_color", varied_base)
		material.set_shader_parameter("accent_color", varied_accent)

	return material

func apply_material_by_name(mesh_instance: MeshInstance3D) -> void:
	"""Apply appropriate material based on mesh name"""
	if not mesh_instance:
		return

	var name = mesh_instance.name.to_lower()
	var material: ShaderMaterial

	# Determine material type from name
	if name.contains("floor") or name.contains("mainarena"):
		if name.contains("room") or name.contains("secondary"):
			material = create_material("room_floor", 0.05)
		else:
			material = create_material("floor", 0.05)
	elif name.contains("wall"):
		if name.contains("room") or name.contains("wall_"):
			material = create_material("room_wall", 0.03)
		else:
			material = create_material("wall", 0.03)
	elif name.contains("platform"):
		material = create_material("platform", 0.08)
	elif name.contains("ramp"):
		material = create_material("ramp", 0.06)
	elif name.contains("pillar"):
		material = create_material("pillar", 0.04)
	elif name.contains("cover"):
		material = create_material("cover", 0.07)
	elif name.contains("corridor"):
		material = create_material("corridor", 0.04)
	elif name.contains("ceiling"):
		material = create_material("room_wall", 0.05)
	else:
		# Default material with variation
		material = create_material("floor", 0.1)

	mesh_instance.material_override = material

func apply_materials_to_level(level_generator: Node3D) -> void:
	"""Apply materials to all geometry in a level generator"""
	if not level_generator:
		return

	var applied_count = 0

	# Recursively find all MeshInstance3D nodes
	for child in level_generator.get_children():
		if child is MeshInstance3D:
			# Skip special meshes (jump pads, teleporters have custom materials)
			if not child.name.contains("JumpPad") and not child.name.contains("Teleporter"):
				apply_material_by_name(child)
				applied_count += 1

	print("Applied procedural materials to %d objects" % applied_count)
