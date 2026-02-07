extends Node

## Procedural Material Manager
## Creates and applies context-aware StandardMaterial3D to level geometry

# Material cache: keyed by preset name, shared across identical geometry
var _material_cache: Dictionary = {}

# Material presets - simple color/roughness/metallic definitions
const MATERIAL_PRESETS = {
	"floor": {"base_color": Color(0.38, 0.40, 0.44), "roughness": 0.85, "metallic": 0.15},
	"wall": {"base_color": Color(0.48, 0.45, 0.40), "roughness": 0.9, "metallic": 0.0},
	"platform": {"base_color": Color(0.32, 0.45, 0.55), "roughness": 0.7, "metallic": 0.5},
	"ramp": {"base_color": Color(0.50, 0.40, 0.30), "roughness": 0.75, "metallic": 0.35},
	"pillar": {"base_color": Color(0.40, 0.38, 0.35), "roughness": 0.95, "metallic": 0.05},
	"cover": {"base_color": Color(0.44, 0.40, 0.35), "roughness": 0.8, "metallic": 0.25},
	"room_floor": {"base_color": Color(0.35, 0.38, 0.42), "roughness": 0.85, "metallic": 0.15},
	"room_wall": {"base_color": Color(0.42, 0.45, 0.48), "roughness": 0.8, "metallic": 0.3},
	"corridor": {"base_color": Color(0.38, 0.40, 0.44), "roughness": 0.85, "metallic": 0.2},
	"halfpipe": {"base_color": Color(0.48, 0.50, 0.55), "roughness": 0.55, "metallic": 0.15},
	"spring": {"base_color": Color(0.75, 0.22, 0.22), "roughness": 0.35, "metallic": 0.6},
	"metal_grate": {"base_color": Color(0.32, 0.34, 0.38), "roughness": 0.6, "metallic": 0.7},
	"tech_panel": {"base_color": Color(0.28, 0.38, 0.48), "roughness": 0.5, "metallic": 0.55},
	"rusty_metal": {"base_color": Color(0.48, 0.35, 0.22), "roughness": 0.9, "metallic": 0.3},
}

func create_material(preset_name: String, color_variation: float = 0.0) -> StandardMaterial3D:
	"""Create a StandardMaterial3D from a preset with optional color variation"""
	# Return cached material for zero-variation presets (shared across meshes = fewer draw calls)
	if color_variation == 0.0 and _material_cache.has(preset_name):
		return _material_cache[preset_name]

	var preset = MATERIAL_PRESETS.get(preset_name, MATERIAL_PRESETS["floor"])

	var material = StandardMaterial3D.new()
	var base_color: Color = preset.base_color

	# Add color variation if specified
	if color_variation > 0.0:
		base_color = Color(
			clampf(base_color.r + randf_range(-color_variation, color_variation), 0.0, 1.0),
			clampf(base_color.g + randf_range(-color_variation, color_variation), 0.0, 1.0),
			clampf(base_color.b + randf_range(-color_variation, color_variation), 0.0, 1.0)
		)

	material.albedo_color = base_color
	material.roughness = preset.roughness
	material.metallic = preset.metallic

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

	var material: StandardMaterial3D

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
		material = create_material("floor", 0.1)

	mesh_instance.material_override = material

func apply_materials_to_level(level_generator: Node3D) -> void:
	"""Apply materials to all geometry in a level generator"""
	if not level_generator:
		return

	var applied_count = _apply_materials_recursive(level_generator)
	print("Applied materials to %d objects" % applied_count)

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
