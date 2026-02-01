extends Node

## Procedural Material Manager
## Creates and applies beautiful context-aware materials to level geometry
## Enhanced with Quake 3-style lighting: bright surfaces with no dark spots

# Pre-load the shader
const PROCEDURAL_SHADER = preload("res://scripts/shaders/procedural_surface.gdshader")

# Q3-style material presets - reduced AO, increased emission, brighter overall
const MATERIAL_PRESETS = {
	"floor": {
		"base_color": Color(0.42, 0.45, 0.50),  # Brighter cool gray
		"accent_color": Color(0.32, 0.35, 0.40),
		"roughness": 0.85,
		"metallic": 0.15,
		"scale": 3.0,
		"pattern_mix": 0.6,
		"detail_strength": 0.4,
		"wear_amount": 0.25,
		"edge_wear_strength": 0.35,
		"ao_strength": 0.2,  # Reduced for Q3-style
		"wet_area_amount": 0.12,
		"color_variation": 0.06,
		"emission_strength": 0.04,  # Increased for Q3-style
		"emission_tint": Color(0.7, 0.75, 0.8),
		"min_brightness": 0.15,
		"ambient_boost": 0.1
	},
	"wall": {
		"base_color": Color(0.52, 0.50, 0.46),  # Brighter warm concrete
		"accent_color": Color(0.42, 0.40, 0.36),
		"roughness": 0.9,
		"metallic": 0.0,
		"scale": 2.5,
		"pattern_mix": 0.4,
		"detail_strength": 0.5,
		"wear_amount": 0.35,
		"edge_wear_strength": 0.5,
		"ao_strength": 0.25,  # Reduced for Q3-style
		"wet_area_amount": 0.08,
		"color_variation": 0.05,
		"emission_strength": 0.03,  # Increased for Q3-style
		"emission_tint": Color(0.75, 0.7, 0.65),
		"min_brightness": 0.15,
		"ambient_boost": 0.1
	},
	"platform": {
		"base_color": Color(0.38, 0.52, 0.62),  # Brighter blue-gray metal
		"accent_color": Color(0.28, 0.42, 0.52),
		"roughness": 0.7,
		"metallic": 0.5,
		"scale": 4.0,
		"pattern_mix": 0.7,
		"detail_strength": 0.35,
		"wear_amount": 0.2,
		"edge_wear_strength": 0.6,
		"ao_strength": 0.2,  # Reduced for Q3-style
		"wet_area_amount": 0.2,
		"color_variation": 0.08,
		"emission_strength": 0.05,  # Increased for Q3-style
		"emission_tint": Color(0.6, 0.8, 0.95),
		"min_brightness": 0.15,
		"ambient_boost": 0.12
	},
	"ramp": {
		"base_color": Color(0.55, 0.45, 0.35),  # Brighter rust/copper
		"accent_color": Color(0.45, 0.35, 0.25),
		"roughness": 0.75,
		"metallic": 0.35,
		"scale": 3.5,
		"pattern_mix": 0.5,
		"detail_strength": 0.4,
		"wear_amount": 0.3,
		"edge_wear_strength": 0.55,
		"ao_strength": 0.2,  # Reduced for Q3-style
		"wet_area_amount": 0.1,
		"color_variation": 0.1,
		"emission_strength": 0.04,  # Increased for Q3-style
		"emission_tint": Color(0.8, 0.65, 0.5),
		"min_brightness": 0.15,
		"ambient_boost": 0.1
	},
	"pillar": {
		"base_color": Color(0.48, 0.45, 0.42),  # Brighter dark stone
		"accent_color": Color(0.38, 0.35, 0.32),
		"roughness": 0.95,
		"metallic": 0.05,
		"scale": 2.0,
		"pattern_mix": 0.3,
		"detail_strength": 0.6,
		"wear_amount": 0.4,
		"edge_wear_strength": 0.7,
		"ao_strength": 0.25,  # Reduced for Q3-style
		"wet_area_amount": 0.05,
		"color_variation": 0.04,
		"emission_strength": 0.03,  # Added emission for Q3-style
		"emission_tint": Color(0.65, 0.65, 0.65),
		"min_brightness": 0.18,
		"ambient_boost": 0.12
	},
	"cover": {
		"base_color": Color(0.50, 0.46, 0.40),  # Brighter military gray-brown
		"accent_color": Color(0.40, 0.36, 0.30),
		"roughness": 0.8,
		"metallic": 0.25,
		"scale": 5.0,
		"pattern_mix": 0.45,
		"detail_strength": 0.3,
		"wear_amount": 0.35,
		"edge_wear_strength": 0.5,
		"ao_strength": 0.22,  # Reduced for Q3-style
		"wet_area_amount": 0.15,
		"color_variation": 0.07,
		"emission_strength": 0.035,  # Increased for Q3-style
		"emission_tint": Color(0.7, 0.65, 0.6),
		"min_brightness": 0.15,
		"ambient_boost": 0.1
	},
	"room_floor": {
		"base_color": Color(0.42, 0.45, 0.48),  # Brighter cool industrial
		"accent_color": Color(0.32, 0.35, 0.38),
		"roughness": 0.85,
		"metallic": 0.15,
		"scale": 4.5,
		"pattern_mix": 0.65,
		"detail_strength": 0.45,
		"wear_amount": 0.3,
		"edge_wear_strength": 0.4,
		"ao_strength": 0.2,  # Reduced for Q3-style
		"wet_area_amount": 0.18,
		"color_variation": 0.06,
		"emission_strength": 0.04,  # Increased for Q3-style
		"emission_tint": Color(0.65, 0.7, 0.8),
		"min_brightness": 0.15,
		"ambient_boost": 0.1
	},
	"room_wall": {
		"base_color": Color(0.48, 0.52, 0.55),  # Brighter tech facility
		"accent_color": Color(0.38, 0.42, 0.45),
		"roughness": 0.8,
		"metallic": 0.3,
		"scale": 3.0,
		"pattern_mix": 0.55,
		"detail_strength": 0.4,
		"wear_amount": 0.25,
		"edge_wear_strength": 0.45,
		"ao_strength": 0.2,  # Reduced for Q3-style
		"wet_area_amount": 0.1,
		"color_variation": 0.05,
		"emission_strength": 0.045,  # Increased for Q3-style
		"emission_tint": Color(0.7, 0.8, 0.9),
		"min_brightness": 0.15,
		"ambient_boost": 0.1
	},
	"corridor": {
		"base_color": Color(0.45, 0.48, 0.50),  # Brighter neutral corridor
		"accent_color": Color(0.35, 0.38, 0.40),
		"roughness": 0.85,
		"metallic": 0.2,
		"scale": 3.5,
		"pattern_mix": 0.5,
		"detail_strength": 0.35,
		"wear_amount": 0.25,
		"edge_wear_strength": 0.4,
		"ao_strength": 0.2,  # Reduced for Q3-style
		"wet_area_amount": 0.15,
		"color_variation": 0.05,
		"emission_strength": 0.04,  # Increased for Q3-style
		"emission_tint": Color(0.7, 0.75, 0.85),
		"min_brightness": 0.15,
		"ambient_boost": 0.1
	},
	"halfpipe": {
		"base_color": Color(0.52, 0.55, 0.60),  # Brighter smooth concrete
		"accent_color": Color(0.42, 0.45, 0.50),
		"roughness": 0.55,
		"metallic": 0.15,
		"scale": 4.0,
		"pattern_mix": 0.3,
		"detail_strength": 0.25,
		"wear_amount": 0.15,
		"edge_wear_strength": 0.3,
		"ao_strength": 0.18,  # Reduced for Q3-style
		"wet_area_amount": 0.25,
		"color_variation": 0.04,
		"emission_strength": 0.04,  # Increased for Q3-style
		"emission_tint": Color(0.75, 0.8, 0.9),
		"min_brightness": 0.15,
		"ambient_boost": 0.1
	},
	"spring": {
		"base_color": Color(0.80, 0.28, 0.28),  # Brighter red base
		"accent_color": Color(0.60, 0.18, 0.18),
		"roughness": 0.35,
		"metallic": 0.6,
		"scale": 2.0,
		"pattern_mix": 0.2,
		"detail_strength": 0.3,
		"wear_amount": 0.1,
		"edge_wear_strength": 0.5,
		"ao_strength": 0.15,  # Reduced for Q3-style
		"wet_area_amount": 0.3,
		"color_variation": 0.08,
		"emission_strength": 0.06,  # Increased for Q3-style
		"emission_tint": Color(0.95, 0.5, 0.4),
		"min_brightness": 0.2,
		"ambient_boost": 0.12
	},
	"metal_grate": {
		"base_color": Color(0.40, 0.42, 0.45),  # Brighter dark metal
		"accent_color": Color(0.30, 0.32, 0.35),
		"roughness": 0.6,
		"metallic": 0.7,
		"scale": 6.0,
		"pattern_mix": 0.8,
		"detail_strength": 0.5,
		"wear_amount": 0.3,
		"edge_wear_strength": 0.65,
		"ao_strength": 0.22,  # Reduced for Q3-style
		"wet_area_amount": 0.2,
		"color_variation": 0.05,
		"emission_strength": 0.04,  # Increased for Q3-style
		"emission_tint": Color(0.6, 0.65, 0.75),
		"min_brightness": 0.15,
		"ambient_boost": 0.1
	},
	"tech_panel": {
		"base_color": Color(0.35, 0.45, 0.55),  # Brighter tech blue
		"accent_color": Color(0.25, 0.35, 0.45),
		"roughness": 0.5,
		"metallic": 0.55,
		"scale": 5.0,
		"pattern_mix": 0.75,
		"detail_strength": 0.3,
		"wear_amount": 0.12,
		"edge_wear_strength": 0.4,
		"ao_strength": 0.18,  # Reduced for Q3-style
		"wet_area_amount": 0.3,
		"color_variation": 0.06,
		"emission_strength": 0.06,  # Increased for Q3-style
		"emission_tint": Color(0.5, 0.7, 0.95),
		"min_brightness": 0.18,
		"ambient_boost": 0.12
	},
	"rusty_metal": {
		"base_color": Color(0.55, 0.42, 0.28),  # Brighter rusty orange-brown
		"accent_color": Color(0.42, 0.28, 0.18),
		"roughness": 0.9,
		"metallic": 0.3,
		"scale": 2.5,
		"pattern_mix": 0.5,
		"detail_strength": 0.65,
		"wear_amount": 0.5,
		"edge_wear_strength": 0.75,
		"ao_strength": 0.25,  # Reduced for Q3-style
		"wet_area_amount": 0.05,
		"color_variation": 0.12,
		"emission_strength": 0.025,  # Added emission for Q3-style
		"emission_tint": Color(0.7, 0.5, 0.4),
		"min_brightness": 0.15,
		"ambient_boost": 0.1
	}
}

func create_material(preset_name: String, color_variation: float = 0.0) -> ShaderMaterial:
	"""Create a procedural material from a preset with optional color variation"""
	var material = ShaderMaterial.new()
	material.shader = PROCEDURAL_SHADER

	var preset = MATERIAL_PRESETS.get(preset_name, MATERIAL_PRESETS["floor"])

	# Apply all preset values including new enhanced parameters
	material.set_shader_parameter("base_color", preset.base_color)
	material.set_shader_parameter("accent_color", preset.accent_color)
	material.set_shader_parameter("roughness", preset.roughness)
	material.set_shader_parameter("metallic", preset.metallic)
	material.set_shader_parameter("scale", preset.scale)
	material.set_shader_parameter("pattern_mix", preset.pattern_mix)
	material.set_shader_parameter("detail_strength", preset.detail_strength)
	material.set_shader_parameter("wear_amount", preset.wear_amount)

	# New enhanced parameters
	material.set_shader_parameter("edge_wear_strength", preset.edge_wear_strength)
	material.set_shader_parameter("ao_strength", preset.ao_strength)
	material.set_shader_parameter("wet_area_amount", preset.wet_area_amount)
	material.set_shader_parameter("color_variation", preset.color_variation)
	material.set_shader_parameter("emission_strength", preset.emission_strength)
	material.set_shader_parameter("emission_tint", preset.emission_tint)

	# Q3-style lighting parameters
	material.set_shader_parameter("min_brightness", preset.min_brightness)
	material.set_shader_parameter("ambient_boost", preset.ambient_boost)

	# Add color variation if specified (additional to preset variation)
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
		material.set_shader_parameter("base_color", varied_base.clamp())
		material.set_shader_parameter("accent_color", varied_accent.clamp())

	return material

func apply_material_by_name(mesh_instance: MeshInstance3D) -> void:
	"""Apply appropriate material based on mesh name"""
	if not mesh_instance:
		return

	var mesh_name = mesh_instance.name.to_lower()
	# Also check parent name for nested meshes
	var parent_name = ""
	if mesh_instance.get_parent():
		parent_name = mesh_instance.get_parent().name.to_lower()

	var material: ShaderMaterial

	# Determine material type from name (check both mesh and parent names)
	if mesh_name.contains("floor") or mesh_name.contains("mainarena"):
		if mesh_name.contains("room") or mesh_name.contains("secondary"):
			material = create_material("room_floor", 0.05)
		else:
			material = create_material("floor", 0.05)
	elif mesh_name.contains("wall"):
		if mesh_name.contains("room") or mesh_name.contains("wall_"):
			material = create_material("room_wall", 0.03)
		else:
			material = create_material("wall", 0.03)
	elif mesh_name.contains("platform"):
		material = create_material("platform", 0.08)
	elif mesh_name.contains("ramp"):
		material = create_material("ramp", 0.06)
	elif mesh_name.contains("pillar"):
		material = create_material("pillar", 0.04)
	elif mesh_name.contains("cover"):
		material = create_material("cover", 0.07)
	elif mesh_name.contains("corridor"):
		material = create_material("corridor", 0.04)
	elif mesh_name.contains("ceiling"):
		material = create_material("room_wall", 0.05)
	elif mesh_name.contains("halfpipe") or parent_name.contains("halfpipe"):
		material = create_material("halfpipe", 0.04)
	elif mesh_name.contains("grate") or mesh_name.contains("metal"):
		material = create_material("metal_grate", 0.05)
	elif mesh_name.contains("tech") or mesh_name.contains("panel"):
		material = create_material("tech_panel", 0.06)
	elif mesh_name.contains("rust"):
		material = create_material("rusty_metal", 0.08)
	else:
		# Default material with variation
		material = create_material("floor", 0.1)

	mesh_instance.material_override = material

func apply_materials_to_level(level_generator: Node3D) -> void:
	"""Apply materials to all geometry in a level generator"""
	if not level_generator:
		return

	var applied_count = _apply_materials_recursive(level_generator)
	print("Applied procedural materials to %d objects" % applied_count)

func _apply_materials_recursive(node: Node, depth: int = 0) -> int:
	"""Recursively apply materials to all MeshInstance3D children"""
	var applied_count = 0

	for child in node.get_children():
		if child is MeshInstance3D:
			var child_name = child.name.to_lower()
			# Skip special meshes that have custom materials
			# (jump pads, teleporters, springs, rails have their own materials)
			if not child_name.contains("jumppad") and \
			   not child_name.contains("teleporter") and \
			   not child_name.contains("spring") and \
			   not child_name.contains("rail") and \
			   not child_name.contains("hazard") and \
			   not child.material_override:  # Don't override existing materials
				apply_material_by_name(child)
				applied_count += 1

		# Recursively process children (e.g., for HalfPipe nodes with nested meshes)
		if child.get_child_count() > 0 and depth < 5:  # Limit recursion depth
			applied_count += _apply_materials_recursive(child, depth + 1)

	return applied_count

func get_preset_names() -> Array[String]:
	"""Get all available preset names"""
	var names: Array[String] = []
	for key in MATERIAL_PRESETS.keys():
		names.append(key)
	return names
