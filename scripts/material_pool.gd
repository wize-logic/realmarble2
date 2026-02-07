extends Node

## MaterialPool
## Centralized material management for reusable StandardMaterial3D and procedural materials.

const PROCEDURAL_MANAGER_PATH := "res://scripts/procedural_material_manager.gd"

var _standard_materials: Dictionary = {}
var _hazard_fallbacks: Dictionary = {}
var _procedural_manager: Node = null

func _ready() -> void:
	_build_standard_materials()
	_build_hazard_fallbacks()

func _build_standard_materials() -> void:
	_standard_materials["floor"] = _create_standard_material(
		Color(0.4, 0.4, 0.45),
		0.8,
		0.0,
		BaseMaterial3D.SHADING_MODE_PER_PIXEL
	)
	_standard_materials["wall"] = _create_standard_material(
		Color(0.5, 0.45, 0.4),
		0.9,
		0.0,
		BaseMaterial3D.SHADING_MODE_PER_PIXEL
	)
	_standard_materials["ceiling"] = _create_standard_material(
		Color(0.35, 0.35, 0.4),
		0.85,
		0.0,
		BaseMaterial3D.SHADING_MODE_PER_PIXEL
	)

func _build_hazard_fallbacks() -> void:
	var lava := _create_standard_material(
		Color(0.9, 0.25, 0.0),
		0.6,
		0.0,
		BaseMaterial3D.SHADING_MODE_UNSHADED
	)
	lava.emission_enabled = true
	lava.emission = Color(1.0, 0.4, 0.05)
	lava.emission_energy_multiplier = 2.8

	var slime := _create_standard_material(
		Color(0.15, 0.65, 0.15),
		0.7,
		0.0,
		BaseMaterial3D.SHADING_MODE_UNSHADED
	)
	slime.emission_enabled = true
	slime.emission = Color(0.1, 0.5, 0.1)
	slime.emission_energy_multiplier = 1.5

	_hazard_fallbacks[0] = lava
	_hazard_fallbacks[1] = slime

func _create_standard_material(color: Color, roughness: float, metallic: float, shading_mode: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	material.shading_mode = shading_mode
	return material

func get_standard_material(name: String) -> StandardMaterial3D:
	return _standard_materials.get(name)

func get_hazard_fallback_material(hazard_type: int) -> StandardMaterial3D:
	return _hazard_fallbacks.get(hazard_type, _hazard_fallbacks.get(0))

func get_procedural_manager() -> Node:
	if _procedural_manager != null:
		return _procedural_manager

	if ResourceLoader.exists(PROCEDURAL_MANAGER_PATH):
		var manager_script = load(PROCEDURAL_MANAGER_PATH)
		if manager_script:
			_procedural_manager = manager_script.new()

	return _procedural_manager

func get_procedural_material(preset_name: String, color_variation: float = 0.0) -> ShaderMaterial:
	var manager = get_procedural_manager()
	if manager:
		return manager.create_material(preset_name, color_variation)
	return null
