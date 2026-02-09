extends Node

## MaterialPool
## Centralized material management for reusable StandardMaterial3D and procedural materials.

const PROCEDURAL_MANAGER_PATH := "res://scripts/procedural_material_manager.gd"
const SHADER_PATHS: Array[String] = [
	"res://scripts/shaders/marble_shader.gdshader",
	"res://scripts/shaders/procedural_surface.gdshader",
	"res://scripts/shaders/hazard_surface.gdshader",
	"res://scripts/shaders/heat_distortion.gdshader",
	"res://scripts/shaders/video_wall.gdshader",
	"res://scripts/shaders/visualizer_wmp9.gdshader",
	"res://scripts/shaders/blur.gdshader",
	"res://scripts/shaders/plasma_glow.gdshader",
	"res://scripts/shaders/card_glow.gdshader",
	"res://scripts/shaders/screen_effects.gdshader",
]

var _standard_materials: Dictionary = {}
var _hazard_fallbacks: Dictionary = {}
var _procedural_manager: Node = null
var _precache_initialized: bool = false
var _precache_materials: Array[Material] = []
var _shader_warmup_done: bool = false

func _ready() -> void:
	_build_standard_materials()
	_build_hazard_fallbacks()
	precache_visual_resources()

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

func precache_visual_resources() -> void:
	"""Pre-cache shaders and procedural materials to avoid first-use hitches."""
	if _precache_initialized:
		return
	_precache_initialized = true
	_precache_shaders()
	_precache_procedural_materials()

func _precache_shaders() -> void:
	for path in SHADER_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var shader := load(path)
		if shader:
			var material := ShaderMaterial.new()
			material.shader = shader
			_precache_materials.append(material)

func _precache_procedural_materials() -> void:
	var manager = get_procedural_manager()
	if not manager:
		return
	for preset_name in manager.get_preset_names():
		manager.create_material(preset_name, 0.0)

func warm_web_shader_variants() -> void:
	"""Force WebGL2 to compile all StandardMaterial3D shader variants used by effects.
	On WebGL2, shader compilation is synchronous and blocks the main thread (~100-300ms
	per unique variant). Without this warmup, the first ability use triggers compilation
	of 3-5+ variants simultaneously, causing a ~1 second freeze.
	This creates a tiny SubViewport and renders one mesh per variant to force compilation."""
	if _shader_warmup_done:
		return
	_shader_warmup_done = true

	if not OS.has_feature("web"):
		return

	# Create a tiny offscreen SubViewport to render warmup meshes.
	# This works because SubViewport shares the same WebGL2 context,
	# so any shader compiled here is cached for the main viewport too.
	var viewport := SubViewport.new()
	viewport.name = "ShaderWarmup"
	viewport.size = Vector2i(2, 2)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = true
	add_child(viewport)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 3)
	viewport.add_child(camera)

	# Shared tiny mesh for all warmup instances
	var warmup_sphere := SphereMesh.new()
	warmup_sphere.radius = 0.1
	warmup_sphere.height = 0.2
	warmup_sphere.radial_segments = 4
	warmup_sphere.rings = 2

	# Warm each unique StandardMaterial3D shader variant used by ability effects
	for mat in _get_warmup_material_variants():
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = warmup_sphere
		mesh_inst.material_override = mat
		viewport.add_child(mesh_inst)

	# Also warm the precached custom ShaderMaterials (gdshader files)
	for shader_mat in _precache_materials:
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = warmup_sphere
		mesh_inst.material_override = shader_mat
		viewport.add_child(mesh_inst)

	# Also warm the standard materials (floor/wall/ceiling) and hazard materials
	for mat_key in _standard_materials:
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = warmup_sphere
		mesh_inst.material_override = _standard_materials[mat_key]
		viewport.add_child(mesh_inst)
	for hazard_key in _hazard_fallbacks:
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = warmup_sphere
		mesh_inst.material_override = _hazard_fallbacks[hazard_key]
		viewport.add_child(mesh_inst)

	# Also warm GPUParticles3D shader (ParticleProcessMaterial) used by marble trails
	var gpu_particle_warmup := GPUParticles3D.new()
	gpu_particle_warmup.amount = 1
	gpu_particle_warmup.lifetime = 0.1
	gpu_particle_warmup.one_shot = true
	gpu_particle_warmup.emitting = true
	var particle_mat := ParticleProcessMaterial.new()
	particle_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	gpu_particle_warmup.process_material = particle_mat
	var particle_draw_mesh := QuadMesh.new()
	var particle_draw_mat := StandardMaterial3D.new()
	particle_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_draw_mesh.material = particle_draw_mat
	gpu_particle_warmup.draw_pass_1 = particle_draw_mesh
	viewport.add_child(gpu_particle_warmup)

	# Clean up after enough frames for rendering to complete
	get_tree().create_timer(0.2).timeout.connect(viewport.queue_free)

func _get_warmup_material_variants() -> Array[StandardMaterial3D]:
	"""Return one StandardMaterial3D per unique shader variant configuration used by effects.
	Each unique combination of transparency/blend/shading/billboard/emission/vertex_color/cull
	generates a different GLSL shader that WebGL2 must compile independently."""
	var variants: Array[StandardMaterial3D] = []

	# 1: Additive + Billboard Particles + Vertex Color (ability particles, CPUParticles3D meshes)
	var v1 := StandardMaterial3D.new()
	v1.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	v1.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	v1.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	v1.vertex_color_use_as_albedo = true
	v1.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	v1.disable_receive_shadows = true
	variants.append(v1)

	# 2: Additive + No Billboard + Vertex Color (sword spin ring particles)
	var v2 := StandardMaterial3D.new()
	v2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	v2.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	v2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	v2.vertex_color_use_as_albedo = true
	v2.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	v2.disable_receive_shadows = true
	variants.append(v2)

	# 3: Additive + Unshaded (flash spheres, shockwaves, bolt glow, lightning indicators)
	var v3 := StandardMaterial3D.new()
	v3.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	v3.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	v3.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	variants.append(v3)

	# 4: Opaque + Unshaded (lightning bolt cores, cannonball meshes)
	var v4 := StandardMaterial3D.new()
	v4.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	variants.append(v4)

	# 5: Additive + Unshaded + Cull Disabled (explosion/dash/sword charge indicators)
	var v5 := StandardMaterial3D.new()
	v5.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	v5.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	v5.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	v5.cull_mode = BaseMaterial3D.CULL_DISABLED
	variants.append(v5)

	# 6: Additive + Billboard Fixed-Y + Unshaded (cannon reticle)
	var v6 := StandardMaterial3D.new()
	v6.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	v6.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	v6.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	v6.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	variants.append(v6)

	# 7: Emission + Transparency + Unshaded (ult ring, ult motion lines, ult end shockwave)
	var v7 := StandardMaterial3D.new()
	v7.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	v7.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	v7.emission_enabled = true
	v7.emission = Color(1.0, 0.6, 0.1)
	v7.emission_energy_multiplier = 2.0
	variants.append(v7)

	# 8: Additive + Billboard Particles without vertex color (ult aura/trail, beam spawn)
	var v8 := StandardMaterial3D.new()
	v8.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	v8.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	v8.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	v8.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	variants.append(v8)

	# 9: Standard per-pixel shading with emission (marble material fallback on GL Compat)
	var v9 := StandardMaterial3D.new()
	v9.emission_enabled = true
	v9.emission = Color.WHITE * 0.12
	v9.roughness = 0.7
	variants.append(v9)

	# 10: Additive + Unshaded + Emission (hazard overlay variant)
	var v10 := StandardMaterial3D.new()
	v10.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	v10.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	v10.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	v10.emission_enabled = true
	v10.emission = Color(1.0, 0.4, 0.1)
	v10.emission_energy_multiplier = 3.0
	variants.append(v10)

	return variants
