extends Node

## Procedural Material Manager
## Creates and applies context-aware ShaderMaterial to level geometry
## Uses a lightweight procedural surface shader with tile grid + noise

# Pre-load the shader
const PROCEDURAL_SHADER = preload("res://scripts/shaders/procedural_surface.gdshader")

# Material cache: keyed by preset name, shared across identical geometry
var _material_cache: Dictionary = {}

# Material presets - color/roughness/metallic + pattern params
const MATERIAL_PRESETS = {
	"floor": {"base_color": Color(0.18, 0.10, 0.30), "accent_color": Color(0.08, 0.34, 0.42), "roughness": 0.72, "metallic": 0.24, "scale": 3.9, "pattern_mix": 0.68, "detail_strength": 0.5, "wear_amount": 0.16},
	"wall": {"base_color": Color(0.24, 0.17, 0.36), "accent_color": Color(0.10, 0.20, 0.42), "roughness": 0.8, "metallic": 0.2, "scale": 3.0, "pattern_mix": 0.52, "detail_strength": 0.48, "wear_amount": 0.3},
	"platform": {"base_color": Color(0.16, 0.38, 0.55), "accent_color": Color(0.42, 0.14, 0.52), "roughness": 0.58, "metallic": 0.62, "scale": 4.6, "pattern_mix": 0.76, "detail_strength": 0.45, "wear_amount": 0.14},
	"accent": {"base_color": Color(0.73, 0.27, 0.79), "accent_color": Color(0.16, 0.86, 0.78), "roughness": 0.36, "metallic": 0.66, "scale": 5.8, "pattern_mix": 0.82, "detail_strength": 0.4, "wear_amount": 0.08},
	"ramp": {"base_color": Color(0.44, 0.18, 0.34), "accent_color": Color(0.16, 0.46, 0.44), "roughness": 0.68, "metallic": 0.4, "scale": 3.7, "pattern_mix": 0.56, "detail_strength": 0.42, "wear_amount": 0.28},
	"pillar": {"base_color": Color(0.40, 0.38, 0.35), "accent_color": Color(0.30, 0.28, 0.25), "roughness": 0.95, "metallic": 0.05, "scale": 2.0, "pattern_mix": 0.3, "detail_strength": 0.6, "wear_amount": 0.45},
	"cover": {"base_color": Color(0.44, 0.40, 0.35), "accent_color": Color(0.34, 0.30, 0.25), "roughness": 0.8, "metallic": 0.25, "scale": 5.0, "pattern_mix": 0.45, "detail_strength": 0.3, "wear_amount": 0.38},
	"room_floor": {"base_color": Color(0.16, 0.15, 0.31), "accent_color": Color(0.12, 0.30, 0.46), "roughness": 0.76, "metallic": 0.3, "scale": 5.0, "pattern_mix": 0.7, "detail_strength": 0.45, "wear_amount": 0.22},
	"room_wall": {"base_color": Color(0.26, 0.24, 0.40), "accent_color": Color(0.16, 0.32, 0.50), "roughness": 0.76, "metallic": 0.32, "scale": 3.2, "pattern_mix": 0.58, "detail_strength": 0.42, "wear_amount": 0.24},
	"corridor": {"base_color": Color(0.22, 0.23, 0.40), "accent_color": Color(0.14, 0.28, 0.46), "roughness": 0.78, "metallic": 0.26, "scale": 3.8, "pattern_mix": 0.56, "detail_strength": 0.38, "wear_amount": 0.24},
	"halfpipe": {"base_color": Color(0.48, 0.50, 0.55), "accent_color": Color(0.38, 0.40, 0.45), "roughness": 0.55, "metallic": 0.15, "scale": 4.0, "pattern_mix": 0.3, "detail_strength": 0.25, "wear_amount": 0.18},
	"spring": {"base_color": Color(0.75, 0.22, 0.22), "accent_color": Color(0.55, 0.12, 0.12), "roughness": 0.35, "metallic": 0.6, "scale": 2.0, "pattern_mix": 0.2, "detail_strength": 0.3, "wear_amount": 0.12},
	"metal_grate": {"base_color": Color(0.32, 0.34, 0.38), "accent_color": Color(0.22, 0.24, 0.28), "roughness": 0.6, "metallic": 0.7, "scale": 6.0, "pattern_mix": 0.8, "detail_strength": 0.5, "wear_amount": 0.32},
	"tech_panel": {"base_color": Color(0.28, 0.38, 0.48), "accent_color": Color(0.18, 0.28, 0.38), "roughness": 0.5, "metallic": 0.55, "scale": 5.0, "pattern_mix": 0.75, "detail_strength": 0.3, "wear_amount": 0.15},
	"rusty_metal": {"base_color": Color(0.48, 0.35, 0.22), "accent_color": Color(0.38, 0.22, 0.12), "roughness": 0.9, "metallic": 0.3, "scale": 2.5, "pattern_mix": 0.5, "detail_strength": 0.65, "wear_amount": 0.55},
}

func create_material(preset_name: String, color_variation: float = 0.0) -> ShaderMaterial:
	"""Create a ShaderMaterial from a preset with optional color variation"""
	# Return cached material for zero-variation presets
	if color_variation == 0.0 and _material_cache.has(preset_name):
		return _material_cache[preset_name]

	var preset = MATERIAL_PRESETS.get(preset_name, MATERIAL_PRESETS["floor"])

	var material = ShaderMaterial.new()
	material.shader = PROCEDURAL_SHADER

	var base_color: Color = preset.base_color
	var accent_color: Color = preset.accent_color

	# Add color variation if specified
	if color_variation > 0.0:
		base_color = Color(
			clampf(base_color.r + randf_range(-color_variation, color_variation), 0.0, 1.0),
			clampf(base_color.g + randf_range(-color_variation, color_variation), 0.0, 1.0),
			clampf(base_color.b + randf_range(-color_variation, color_variation), 0.0, 1.0)
		)
		accent_color = Color(
			clampf(accent_color.r + randf_range(-color_variation, color_variation), 0.0, 1.0),
			clampf(accent_color.g + randf_range(-color_variation, color_variation), 0.0, 1.0),
			clampf(accent_color.b + randf_range(-color_variation, color_variation), 0.0, 1.0)
		)

	material.set_shader_parameter("base_color", base_color)
	material.set_shader_parameter("accent_color", accent_color)
	material.set_shader_parameter("roughness", preset.roughness)
	material.set_shader_parameter("metallic", preset.metallic)
	material.set_shader_parameter("scale", preset.scale)
	material.set_shader_parameter("pattern_mix", preset.pattern_mix)
	material.set_shader_parameter("detail_strength", preset.detail_strength)
	material.set_shader_parameter("wear_amount", preset.wear_amount)

	# Cache zero-variation materials for reuse
	if color_variation == 0.0:
		_material_cache[preset_name] = material

	return material

func apply_material_by_name(mesh_instance: MeshInstance3D) -> void:
	"""Apply appropriate material based on mesh name"""
	if not mesh_instance:
		return

	var mesh_name = mesh_instance.name.to_lower()
	var parent_name = ""
	if mesh_instance.get_parent():
		parent_name = mesh_instance.get_parent().name.to_lower()

	var material: ShaderMaterial

	if mesh_name.contains("accent"):
		material = create_material("accent", 0.05)
	elif mesh_name.contains("floor") or mesh_name.contains("mainarena"):
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
		material = create_material("floor", 0.1)

	mesh_instance.material_override = material

func apply_materials_to_level(level_generator: Node3D) -> void:
	"""Apply materials to all geometry in a level generator"""
	if not level_generator:
		return

	var applied_count = _apply_materials_recursive(level_generator)
	DebugLogger.dlog(DebugLogger.Category.LEVEL_GEN, "Applied procedural materials to %d objects" % applied_count)

func _apply_materials_recursive(node: Node, depth: int = 0) -> int:
	"""Recursively apply materials to all MeshInstance3D children"""
	var applied_count = 0

	for child in node.get_children():
		if child is MeshInstance3D:
			var child_name = child.name.to_lower()
			if not child_name.contains("jumppad") and \
			   not child_name.contains("teleporter") and \
			   not child_name.contains("spring") and \
			   not child_name.contains("rail") and \
			   not child_name.contains("hazard") and \
			   not child.material_override:
				apply_material_by_name(child)
				applied_count += 1

		if child.get_child_count() > 0 and depth < 5:
			applied_count += _apply_materials_recursive(child, depth + 1)

	return applied_count

func get_preset_names() -> Array[String]:
	"""Get all available preset names"""
	var names: Array[String] = []
	for key in MATERIAL_PRESETS.keys():
		names.append(key)
	return names
