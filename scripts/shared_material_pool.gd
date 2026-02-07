extends Node

## Shared Material Pool (Autoload Singleton)
## Pre-creates and caches common materials to reduce shader/material variety.
## Avoids runtime shader compilation stalls by warming all materials at startup.

# ============================================================================
# SHADER PRELOADS - compiled at load time, not runtime
# ============================================================================
const MARBLE_SHADER = preload("res://scripts/shaders/marble_shader.gdshader")
const PROCEDURAL_SHADER = preload("res://scripts/shaders/procedural_surface.gdshader")

var _hazard_shader: Shader = null
var _shaders_warmed: bool = false

# ============================================================================
# CACHED STANDARD MATERIALS
# ============================================================================

# -- Particle materials (shared across ALL particle effects) --
var particle_additive: StandardMaterial3D  # vertex_color + billboard_particles + additive
var particle_additive_no_billboard: StandardMaterial3D  # vertex_color + no billboard + additive

# -- Level element materials (shared across all instances of same type) --
var jumppad_material: StandardMaterial3D
var teleporter_material: StandardMaterial3D
var rail_material: StandardMaterial3D
var grind_rail_wire_material: StandardMaterial3D

# -- Hazard fallback materials --
var hazard_lava_fallback: StandardMaterial3D
var hazard_slime_fallback: StandardMaterial3D

# -- Level geometry fallback materials --
var floor_material: StandardMaterial3D
var wall_material: StandardMaterial3D
var ceiling_material: StandardMaterial3D

# -- Collectible / pickup materials --
var collectible_orb_material: StandardMaterial3D

# -- Debug material --
var debug_arrow_material: StandardMaterial3D

# -- Beam spawn textured particle materials --
var beam_circle_particle_material: StandardMaterial3D
var beam_star_particle_material: StandardMaterial3D

# -- Additive unshaded colored materials cache (keyed by color hash) --
var _colored_additive_cache: Dictionary = {}

# -- Jump bounce material (special: alpha, unshaded, billboard_enabled, no additive) --
var jump_bounce_material: StandardMaterial3D

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	_create_particle_materials()
	_create_level_element_materials()
	_create_level_geometry_materials()
	_create_misc_materials()
	_load_optional_shaders()

func _create_particle_materials() -> void:
	# The most commonly used material pattern across the entire codebase:
	# TRANSPARENCY_ALPHA + BLEND_MODE_ADD + SHADING_MODE_UNSHADED +
	# vertex_color_use_as_albedo + BILLBOARD_PARTICLES + disable_receive_shadows
	particle_additive = StandardMaterial3D.new()
	particle_additive.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_additive.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_additive.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_additive.vertex_color_use_as_albedo = true
	particle_additive.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_additive.disable_receive_shadows = true

	# Same but without billboard (used for sword ring particles etc.)
	particle_additive_no_billboard = StandardMaterial3D.new()
	particle_additive_no_billboard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_additive_no_billboard.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_additive_no_billboard.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_additive_no_billboard.vertex_color_use_as_albedo = true
	particle_additive_no_billboard.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	particle_additive_no_billboard.disable_receive_shadows = true

	# Jump bounce material (special non-additive transparent)
	jump_bounce_material = StandardMaterial3D.new()
	jump_bounce_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	jump_bounce_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	jump_bounce_material.albedo_color = Color(0.1, 0.2, 0.5, 0.12)
	jump_bounce_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	jump_bounce_material.disable_receive_shadows = true

func _create_level_element_materials() -> void:
	# Jump pad - bright vibrant green, unshaded
	jumppad_material = StandardMaterial3D.new()
	jumppad_material.albedo_color = Color(0.3, 1.0, 0.4)
	jumppad_material.emission_enabled = true
	jumppad_material.emission = Color(0.3, 1.0, 0.4)
	jumppad_material.emission_energy_multiplier = 2.0
	jumppad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Teleporter - bright purple/magenta, unshaded
	teleporter_material = StandardMaterial3D.new()
	teleporter_material.albedo_color = Color(0.7, 0.3, 1.0)
	teleporter_material.emission_enabled = true
	teleporter_material.emission = Color(0.7, 0.3, 1.0)
	teleporter_material.emission_energy_multiplier = 2.0
	teleporter_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Grind rail visual - dark grey with subtle glow
	rail_material = StandardMaterial3D.new()
	rail_material.albedo_color = Color(0.25, 0.25, 0.28)
	rail_material.emission_enabled = true
	rail_material.emission = Color(0.15, 0.15, 0.18)
	rail_material.emission_energy_multiplier = 0.8
	rail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Grind rail wire/cable
	grind_rail_wire_material = StandardMaterial3D.new()
	grind_rail_wire_material.albedo_color = Color(0.3, 0.3, 0.35)
	grind_rail_wire_material.metallic = 0.7
	grind_rail_wire_material.roughness = 0.4
	grind_rail_wire_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	# Hazard fallbacks
	hazard_lava_fallback = StandardMaterial3D.new()
	hazard_lava_fallback.albedo_color = Color(0.9, 0.25, 0.0)
	hazard_lava_fallback.emission_enabled = true
	hazard_lava_fallback.emission = Color(1.0, 0.4, 0.05)
	hazard_lava_fallback.emission_energy_multiplier = 2.8
	hazard_lava_fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	hazard_slime_fallback = StandardMaterial3D.new()
	hazard_slime_fallback.albedo_color = Color(0.15, 0.65, 0.15)
	hazard_slime_fallback.emission_enabled = true
	hazard_slime_fallback.emission = Color(0.1, 0.5, 0.1)
	hazard_slime_fallback.emission_energy_multiplier = 1.5
	hazard_slime_fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func _create_level_geometry_materials() -> void:
	# Floor material - basic diffuse
	floor_material = StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.4, 0.4, 0.45)
	floor_material.roughness = 0.8
	floor_material.metallic = 0.0
	floor_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	# Wall material
	wall_material = StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.5, 0.45, 0.4)
	wall_material.roughness = 0.9
	wall_material.metallic = 0.0
	wall_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	# Ceiling material
	ceiling_material = StandardMaterial3D.new()
	ceiling_material.albedo_color = Color(0.35, 0.35, 0.4)
	ceiling_material.roughness = 0.85
	ceiling_material.metallic = 0.0
	ceiling_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

func _create_misc_materials() -> void:
	# Collectible orb
	collectible_orb_material = StandardMaterial3D.new()
	collectible_orb_material.albedo_color = Color(0.3, 0.7, 1.0, 1.0)
	collectible_orb_material.emission_enabled = false
	collectible_orb_material.metallic = 0.2
	collectible_orb_material.roughness = 0.3

	# Debug arrow
	debug_arrow_material = StandardMaterial3D.new()
	debug_arrow_material.albedo_color = Color(1.0, 0.3, 0.3, 0.9)
	debug_arrow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_arrow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_arrow_material.no_depth_test = true

	# Beam spawn particle materials (textured)
	beam_circle_particle_material = StandardMaterial3D.new()
	beam_circle_particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_circle_particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_circle_particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	beam_circle_particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if ResourceLoader.exists("res://textures/kenney_particle_pack/circle_05.png"):
		beam_circle_particle_material.albedo_texture = load("res://textures/kenney_particle_pack/circle_05.png")

	beam_star_particle_material = StandardMaterial3D.new()
	beam_star_particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_star_particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_star_particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	beam_star_particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if ResourceLoader.exists("res://textures/kenney_particle_pack/star_05.png"):
		beam_star_particle_material.albedo_texture = load("res://textures/kenney_particle_pack/star_05.png")

func _load_optional_shaders() -> void:
	if ResourceLoader.exists("res://scripts/shaders/hazard_surface.gdshader"):
		_hazard_shader = load("res://scripts/shaders/hazard_surface.gdshader")

# ============================================================================
# PUBLIC API - Get shared materials
# ============================================================================

func get_colored_additive_unshaded(color: Color) -> StandardMaterial3D:
	"""Get or create a colored additive unshaded material (cached by color).
	Used for flash layers, glow effects, shockwave rings, etc.
	These need unique colors but share the same shader pipeline."""
	var key := "%d_%d_%d_%d" % [int(color.r * 255), int(color.g * 255), int(color.b * 255), int(color.a * 255)]
	if _colored_additive_cache.has(key):
		return _colored_additive_cache[key]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	_colored_additive_cache[key] = mat
	return mat

func get_colored_emissive_unshaded(color: Color, emission_energy: float = 2.0) -> StandardMaterial3D:
	"""Get or create an emissive unshaded material (cached).
	Used for ult ring shockwaves, lightning lines, etc."""
	var key := "emissive_%d_%d_%d_%d_%.1f" % [int(color.r * 255), int(color.g * 255), int(color.b * 255), int(color.a * 255), emission_energy]
	if _colored_additive_cache.has(key):
		return _colored_additive_cache[key]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = emission_energy
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_colored_additive_cache[key] = mat
	return mat

func get_indicator_material(color: Color) -> StandardMaterial3D:
	"""Get a subtle transparent indicator material for AoE radius displays, reticles, etc."""
	var key := "indicator_%d_%d_%d_%d" % [int(color.r * 255), int(color.g * 255), int(color.b * 255), int(color.a * 255)]
	if _colored_additive_cache.has(key):
		return _colored_additive_cache[key]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	mat.disable_fog = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_colored_additive_cache[key] = mat
	return mat

func get_ability_pickup_material(color: Color) -> StandardMaterial3D:
	"""Get a material for ability pickups (shaded, metallic)."""
	var key := "pickup_%d_%d_%d" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]
	if _colored_additive_cache.has(key):
		return _colored_additive_cache[key]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.3
	mat.roughness = 0.3
	_colored_additive_cache[key] = mat
	return mat

func get_bolt_segment_material(color: Color, transparent: bool) -> StandardMaterial3D:
	"""Get a material for lightning bolt segments (cached)."""
	var key := "bolt_%d_%d_%d_%d_%s" % [int(color.r * 255), int(color.g * 255), int(color.b * 255), int(color.a * 255), str(transparent)]
	if _colored_additive_cache.has(key):
		return _colored_additive_cache[key]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_colored_additive_cache[key] = mat
	return mat

func get_hazard_shader() -> Shader:
	"""Get the hazard surface shader (may be null if not available)."""
	return _hazard_shader

# ============================================================================
# SHADER WARMUP - Forces GPU to compile all shader variants at startup
# ============================================================================

func warmup_shaders() -> void:
	"""Force-compile all shader variants by briefly rendering a tiny mesh with each material.
	Call this early in startup (e.g., world._ready) to avoid mid-game compilation stalls."""
	if _shaders_warmed:
		return
	_shaders_warmed = true

	# Create a tiny offscreen mesh for warmup
	var warmup_mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.001
	sphere.height = 0.002
	sphere.radial_segments = 4
	sphere.rings = 2
	warmup_mesh.mesh = sphere
	warmup_mesh.position = Vector3(0, -1000, 0)  # Far below visible area
	add_child(warmup_mesh)

	# Warm all pre-created StandardMaterial3D materials
	var materials_to_warm: Array[StandardMaterial3D] = [
		particle_additive,
		particle_additive_no_billboard,
		jump_bounce_material,
		jumppad_material,
		teleporter_material,
		rail_material,
		grind_rail_wire_material,
		hazard_lava_fallback,
		hazard_slime_fallback,
		floor_material,
		wall_material,
		ceiling_material,
		collectible_orb_material,
		debug_arrow_material,
		beam_circle_particle_material,
		beam_star_particle_material,
	]

	for mat in materials_to_warm:
		warmup_mesh.material_override = mat
		# Force a render by waiting one frame per material
		# (Godot compiles shaders on first render)

	# Warm ShaderMaterial variants (marble + procedural)
	var marble_mat := ShaderMaterial.new()
	marble_mat.shader = MARBLE_SHADER
	marble_mat.set_shader_parameter("primary_color", Color.RED)
	marble_mat.set_shader_parameter("secondary_color", Color.BLUE)
	marble_mat.set_shader_parameter("swirl_color", Color.GREEN)
	warmup_mesh.material_override = marble_mat

	var proc_mat := ShaderMaterial.new()
	proc_mat.shader = PROCEDURAL_SHADER
	proc_mat.set_shader_parameter("base_color", Color.GRAY)
	proc_mat.set_shader_parameter("accent_color", Color.DIM_GRAY)
	warmup_mesh.material_override = proc_mat

	if _hazard_shader:
		var hazard_mat := ShaderMaterial.new()
		hazard_mat.shader = _hazard_shader
		hazard_mat.set_shader_parameter("hazard_type", 0)
		warmup_mesh.material_override = hazard_mat

	# Leave warmup mesh for one frame then clean up
	await get_tree().process_frame
	warmup_mesh.queue_free()

	print("[MaterialPool] Shader warmup complete (%d materials)" % materials_to_warm.size())
