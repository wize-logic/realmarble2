@tool
extends Node3D

## =============================================================================
## SONIC 3D-STYLE ARENA GENERATOR (BSP-Based)
## =============================================================================
## Procedurally generates Sonic 3D-style multiplayer arenas using Binary Space
## Partitioning for dynamic zone creation. Features layered platforms, grind
## rails, loops, springs, and all classic Sonic elements adapted for arena combat.
##
## ARCHITECTURE:
## - BSPNode: Binary Space Partitioning for zone subdivision
## - PlatformBuilder: Creates CSG/mesh-based platforms with noise perturbation
## - RailGenerator: Creates grind rails with curves and variations
## - EntityPlacer: Handles spawns, collectibles, power-ups, enemies
##
## SONIC ADAPTATIONS:
## - Grind rail physics: lerp velocity along tangent for smooth grinding
## - Loop momentum: toroidal meshes for speed trick opportunities
## - Spring impulses: Area3D triggers for bouncy jump mechanics
## - Layered platforms: Multi-level stacking mimicking Sonic's vertical design
## =============================================================================

# =============================================================================
# EXPORTED PARAMETERS
# =============================================================================

@export var level_seed: int = 0
@export var arena_size: float = 120.0  # Base arena size - scales with difficulty
@export var complexity: int = 2  # 1=Low, 2=Medium, 3=High, 4=Extreme

@export_group("Editor Controls")
@export var regenerate_level: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			generate_level()
		regenerate_level = false

@export var save_as_scene: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_save_generated_scene()
		save_as_scene = false

# =============================================================================
# INTERNAL STATE
# =============================================================================

# Calculated counts (set by configure_for_complexity)
var platform_count: int = 12
var ramp_count: int = 8
var grind_rail_count: int = 6
var vertical_rail_count: int = 3
var loop_count: int = 2
var spring_count: int = 8
var ring_count: int = 24
var powerup_count: int = 4

var noise: FastNoiseLite
var platforms: Array = []
var geometry_bounds: Array[Dictionary] = []
var bsp_root: BSPNode = null
var bsp_leaves: Array[BSPNode] = []
var zone_graph: Dictionary = {}  # Zone connections for path generation

var material_manager = preload("res://scripts/procedural_material_manager.gd").new()

# =============================================================================
# BSP NODE CLASS
# =============================================================================

class BSPNode:
	"""Binary Space Partitioning node for arena zone subdivision.
	Uses Rect2 for 2D floorplan (extendable to AABB for full 3D).
	Recursively splits to create room-sized zones for platform placement."""

	var bounds: Rect2  # 2D floorplan bounds
	var height_offset: float = 0.0  # Vertical offset for multi-level stacking
	var left: BSPNode = null
	var right: BSPNode = null
	var zone_id: int = -1  # Assigned to leaves only
	var platform_rect: Rect2  # Inset rect for actual platform placement
	var center: Vector3  # 3D center point for path generation
	var is_mirrored: bool = false  # For arena symmetry
	var min_zone_size: float = 200.0  # Dynamic: scales with arena (set by generator)

	# Platform inset: 75-90% of zone size leaves 10-25% margin for walls/edges
	const PLATFORM_INSET_MIN: float = 0.75
	const PLATFORM_INSET_MAX: float = 0.90
	# Height variation: 0-128 units creates multi-level Sonic-style stacking
	const HEIGHT_VARIATION_MIN: float = 0.0
	const HEIGHT_VARIATION_MAX: float = 128.0

	func _init(rect: Rect2, height: float = 0.0, min_size: float = 200.0):
		bounds = rect
		height_offset = height
		min_zone_size = min_size

	func is_leaf() -> bool:
		return left == null and right == null

	func can_split() -> bool:
		# Ensure sub-areas are >= min_zone_size (scales with arena)
		return bounds.size.x >= min_zone_size * 2 or bounds.size.y >= min_zone_size * 2

	func split(horizontal: bool, rng: RandomNumberGenerator) -> bool:
		"""Split this node horizontally or vertically.
		Returns true if split was successful."""
		if not can_split():
			return false

		# Split ratio 0.4-0.6 ensures neither child is too small/large
		var split_ratio: float = rng.randf_range(0.4, 0.6)

		if horizontal and bounds.size.y >= min_zone_size * 2:
			var split_y: float = bounds.position.y + bounds.size.y * split_ratio
			var height_left: float = rng.randf_range(HEIGHT_VARIATION_MIN, HEIGHT_VARIATION_MAX)
			var height_right: float = rng.randf_range(HEIGHT_VARIATION_MIN, HEIGHT_VARIATION_MAX)

			left = BSPNode.new(
				Rect2(bounds.position.x, bounds.position.y, bounds.size.x, split_y - bounds.position.y),
				height_left,
				min_zone_size  # Propagate min_zone_size to children
			)
			right = BSPNode.new(
				Rect2(bounds.position.x, split_y, bounds.size.x, bounds.end.y - split_y),
				height_right,
				min_zone_size
			)
			return true

		elif not horizontal and bounds.size.x >= min_zone_size * 2:
			var split_x: float = bounds.position.x + bounds.size.x * split_ratio
			var height_left: float = rng.randf_range(HEIGHT_VARIATION_MIN, HEIGHT_VARIATION_MAX)
			var height_right: float = rng.randf_range(HEIGHT_VARIATION_MIN, HEIGHT_VARIATION_MAX)

			left = BSPNode.new(
				Rect2(bounds.position.x, bounds.position.y, split_x - bounds.position.x, bounds.size.y),
				height_left,
				min_zone_size
			)
			right = BSPNode.new(
				Rect2(split_x, bounds.position.y, bounds.end.x - split_x, bounds.size.y),
				height_right,
				min_zone_size
			)
			return true

		return false

	func finalize_zone(id: int, rng: RandomNumberGenerator) -> void:
		"""Called on leaf nodes to finalize zone properties."""
		zone_id = id

		# Create inset platform rect (75-90% of zone size)
		var inset_factor: float = rng.randf_range(PLATFORM_INSET_MIN, PLATFORM_INSET_MAX)
		var inset_x: float = bounds.size.x * (1.0 - inset_factor) / 2.0
		var inset_y: float = bounds.size.y * (1.0 - inset_factor) / 2.0

		platform_rect = Rect2(
			bounds.position.x + inset_x,
			bounds.position.y + inset_y,
			bounds.size.x * inset_factor,
			bounds.size.y * inset_factor
		)

		# Calculate 3D center
		center = Vector3(
			bounds.position.x + bounds.size.x / 2.0,
			height_offset,
			bounds.position.y + bounds.size.y / 2.0  # Z is Y in 2D floorplan
		)

	func get_all_leaves() -> Array[BSPNode]:
		"""Recursively collect all leaf nodes."""
		var leaves: Array[BSPNode] = []
		if is_leaf():
			leaves.append(self)
		else:
			if left:
				leaves.append_array(left.get_all_leaves())
			if right:
				leaves.append_array(right.get_all_leaves())
		return leaves

# =============================================================================
# PLATFORM BUILDER CLASS
# =============================================================================

class PlatformBuilder:
	"""Creates CSG/mesh-based platforms with noise perturbation for organic shapes."""

	var parent_node: Node3D
	var noise: FastNoiseLite
	var geometry_bounds: Array[Dictionary]

	func _init(parent: Node3D, noise_gen: FastNoiseLite, bounds_ref: Array[Dictionary]):
		parent_node = parent
		noise = noise_gen
		geometry_bounds = bounds_ref

	func create_platform(rect: Rect2, height: float, name_prefix: String, index: int, use_noise_edges: bool = true) -> MeshInstance3D:
		"""Create a platform from a Rect2 with optional organic edge perturbation.
		When use_noise_edges=true, applies FastNoiseLite to create wavy island-like edges."""
		var size: Vector3 = Vector3(rect.size.x, 2.0, rect.size.y)
		var pos: Vector3 = Vector3(
			rect.position.x + rect.size.x / 2.0,
			height,
			rect.position.y + rect.size.y / 2.0
		)

		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.name = name_prefix + str(index)
		mesh_instance.position = pos

		if use_noise_edges and noise:
			# Create ArrayMesh with noise-perturbed vertices for organic shapes
			var array_mesh: ArrayMesh = _create_noise_perturbed_box(size, pos, index)
			mesh_instance.mesh = array_mesh
		else:
			# Standard box mesh
			var mesh: BoxMesh = BoxMesh.new()
			mesh.size = size
			mesh.subdivide_width = 4
			mesh.subdivide_height = 2
			mesh.subdivide_depth = 4
			mesh_instance.mesh = mesh

		parent_node.add_child(mesh_instance)

		# Add collision (uses unperturbed box for simplicity - physics stays stable)
		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		static_body.add_child(collision)
		mesh_instance.add_child(static_body)

		# Register geometry bounds
		geometry_bounds.append({
			"position": pos,
			"size": size
		})

		return mesh_instance

	func _create_noise_perturbed_box(size: Vector3, world_pos: Vector3, seed_offset: int) -> ArrayMesh:
		"""Create a box mesh with noise-perturbed edges for organic island-like shapes.
		Perturbs horizontal edges (X/Z) while keeping top/bottom flat for playability."""
		var mesh: ArrayMesh = ArrayMesh.new()
		var surface_tool: SurfaceTool = SurfaceTool.new()
		surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

		var half: Vector3 = size / 2.0
		# Noise perturbation strength: 10% of smallest dimension for subtle organic feel
		var perturb_strength: float = min(size.x, size.z) * 0.1

		# Generate vertices for a box with perturbed horizontal positions
		# Top face (Y+) - flat for gameplay
		var top_verts: Array[Vector3] = []
		var subdivisions: int = 4
		for iz in range(subdivisions + 1):
			for ix in range(subdivisions + 1):
				var u: float = float(ix) / subdivisions
				var v: float = float(iz) / subdivisions
				var x: float = lerp(-half.x, half.x, u)
				var z: float = lerp(-half.z, half.z, v)

				# Apply noise to edge vertices only (not center)
				var edge_factor: float = 1.0 - (1.0 - abs(u - 0.5) * 2.0) * (1.0 - abs(v - 0.5) * 2.0)
				var noise_val: float = noise.get_noise_2d(world_pos.x + x + seed_offset, world_pos.z + z)
				x += noise_val * perturb_strength * edge_factor
				z += noise_val * perturb_strength * edge_factor * 0.7  # Slightly less on Z

				top_verts.append(Vector3(x, half.y, z))

		# Add top face triangles
		surface_tool.set_normal(Vector3.UP)
		for iz in range(subdivisions):
			for ix in range(subdivisions):
				var i0: int = iz * (subdivisions + 1) + ix
				var i1: int = i0 + 1
				var i2: int = i0 + (subdivisions + 1)
				var i3: int = i2 + 1

				surface_tool.add_vertex(top_verts[i0])
				surface_tool.add_vertex(top_verts[i2])
				surface_tool.add_vertex(top_verts[i1])

				surface_tool.add_vertex(top_verts[i1])
				surface_tool.add_vertex(top_verts[i2])
				surface_tool.add_vertex(top_verts[i3])

		# Bottom face (Y-) - flat
		surface_tool.set_normal(Vector3.DOWN)
		var bottom_verts: Array[Vector3] = []
		for v in top_verts:
			bottom_verts.append(Vector3(v.x, -half.y, v.z))

		for iz in range(subdivisions):
			for ix in range(subdivisions):
				var i0: int = iz * (subdivisions + 1) + ix
				var i1: int = i0 + 1
				var i2: int = i0 + (subdivisions + 1)
				var i3: int = i2 + 1

				surface_tool.add_vertex(bottom_verts[i0])
				surface_tool.add_vertex(bottom_verts[i1])
				surface_tool.add_vertex(bottom_verts[i2])

				surface_tool.add_vertex(bottom_verts[i1])
				surface_tool.add_vertex(bottom_verts[i3])
				surface_tool.add_vertex(bottom_verts[i2])

		# Side faces - connect top and bottom with perturbed edges
		_add_side_faces(surface_tool, top_verts, bottom_verts, subdivisions)

		surface_tool.generate_normals()
		return surface_tool.commit()

	func _add_side_faces(st: SurfaceTool, top: Array[Vector3], bottom: Array[Vector3], subdivs: int) -> void:
		"""Add side faces connecting perturbed top/bottom vertices."""
		var stride: int = subdivs + 1

		# Front face (Z+)
		for ix in range(subdivs):
			var t0: Vector3 = top[subdivs * stride + ix]
			var t1: Vector3 = top[subdivs * stride + ix + 1]
			var b0: Vector3 = bottom[subdivs * stride + ix]
			var b1: Vector3 = bottom[subdivs * stride + ix + 1]
			st.add_vertex(t0); st.add_vertex(b0); st.add_vertex(t1)
			st.add_vertex(t1); st.add_vertex(b0); st.add_vertex(b1)

		# Back face (Z-)
		for ix in range(subdivs):
			var t0: Vector3 = top[ix]
			var t1: Vector3 = top[ix + 1]
			var b0: Vector3 = bottom[ix]
			var b1: Vector3 = bottom[ix + 1]
			st.add_vertex(t0); st.add_vertex(t1); st.add_vertex(b0)
			st.add_vertex(t1); st.add_vertex(b1); st.add_vertex(b0)

		# Right face (X+)
		for iz in range(subdivs):
			var t0: Vector3 = top[iz * stride + subdivs]
			var t1: Vector3 = top[(iz + 1) * stride + subdivs]
			var b0: Vector3 = bottom[iz * stride + subdivs]
			var b1: Vector3 = bottom[(iz + 1) * stride + subdivs]
			st.add_vertex(t0); st.add_vertex(t1); st.add_vertex(b0)
			st.add_vertex(t1); st.add_vertex(b1); st.add_vertex(b0)

		# Left face (X-)
		for iz in range(subdivs):
			var t0: Vector3 = top[iz * stride]
			var t1: Vector3 = top[(iz + 1) * stride]
			var b0: Vector3 = bottom[iz * stride]
			var b1: Vector3 = bottom[(iz + 1) * stride]
			st.add_vertex(t0); st.add_vertex(b0); st.add_vertex(t1)
			st.add_vertex(t1); st.add_vertex(b0); st.add_vertex(b1)

	func create_sloped_ramp(start_pos: Vector3, end_pos: Vector3, width: float, name_prefix: String, index: int) -> MeshInstance3D:
		"""Create a sloped ramp between two heights for speed boosts."""
		var direction: Vector3 = (end_pos - start_pos)
		var length: float = direction.length()
		var height_diff: float = end_pos.y - start_pos.y
		var angle: float = atan2(height_diff, sqrt(direction.x * direction.x + direction.z * direction.z))
		var facing: float = atan2(direction.x, direction.z)

		var size: Vector3 = Vector3(width, 0.5, length)
		var center: Vector3 = start_pos.lerp(end_pos, 0.5)

		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = size

		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = mesh
		mesh_instance.name = name_prefix + str(index)
		mesh_instance.position = center
		mesh_instance.rotation = Vector3(-angle, facing, 0)
		parent_node.add_child(mesh_instance)

		# Add collision
		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		static_body.add_child(collision)
		mesh_instance.add_child(static_body)

		# Register with larger bounds due to rotation
		geometry_bounds.append({
			"position": center,
			"size": size * 1.5
		})

		return mesh_instance

	func create_loop(center: Vector3, radius: float, name_prefix: String, index: int) -> Node3D:
		"""Create a toroidal loop for momentum tricks (Sonic-style).
		Uses CSGTorus3D for visual with full collision coverage for player contact."""
		var loop_node: Node3D = Node3D.new()
		loop_node.name = name_prefix + str(index)
		loop_node.position = center
		parent_node.add_child(loop_node)

		# Create outer torus using CSGTorus3D
		# inner_radius = hole size, outer_radius = tube thickness
		var outer_torus: CSGTorus3D = CSGTorus3D.new()
		outer_torus.name = "OuterTorus"
		outer_torus.inner_radius = radius
		outer_torus.outer_radius = radius + 8.0  # 8 unit thick tube for player to run through
		outer_torus.sides = 24  # Ring smoothness
		outer_torus.ring_sides = 16  # Tube cross-section smoothness
		# Rotate to stand vertically (loop plane perpendicular to ground)
		outer_torus.rotation_degrees = Vector3(90, 0, 0)
		loop_node.add_child(outer_torus)

		# Add static body for FULL loop collision (not just bottom arc)
		var static_body: StaticBody3D = StaticBody3D.new()
		static_body.name = "LoopCollision"
		loop_node.add_child(static_body)

		# Create collision segments around the ENTIRE loop (16 segments for full coverage)
		# This prevents players from clipping through any part of the loop
		var num_segments: int = 16
		for i in range(num_segments):
			var angle: float = (float(i) / num_segments) * TAU  # Full 360 degrees
			var collision: CollisionShape3D = CollisionShape3D.new()
			var box: BoxShape3D = BoxShape3D.new()
			# Box size: width=tube thickness, height=segment arc, depth=track width
			box.size = Vector3(10.0, 4.0, 12.0)
			collision.shape = box
			# Position on the tube surface (inside of torus where player runs)
			collision.position = Vector3(0, cos(angle) * radius, sin(angle) * radius)
			collision.rotation = Vector3(angle, 0, 0)
			static_body.add_child(collision)

		return loop_node

# =============================================================================
# RAIL GENERATOR CLASS
# =============================================================================

class RailGenerator:
	"""Generates grind rails with curves, branches, and variations.
	Rails use Path3D with Curve3D for smooth grinding physics."""

	var parent_node: Node3D
	var rng: RandomNumberGenerator
	var GrindRailScript = preload("res://scripts/grind_rail.gd")

	const RAIL_MIN_LENGTH: float = 100.0
	const RAIL_MAX_LENGTH: float = 300.0
	const RAIL_ELEVATION: float = 32.0
	const RAIL_RADIUS: float = 0.15

	func _init(parent: Node3D, random: RandomNumberGenerator):
		parent_node = parent
		rng = random

	func create_curved_rail(start: Vector3, end: Vector3, curve_height: float, name_str: String) -> Path3D:
		"""Create a curved grind rail between two points with Bezier-style curves."""
		var rail: Path3D = GrindRailScript.new()
		rail.name = name_str
		rail.curve = Curve3D.new()

		var distance: float = start.distance_to(end)
		var num_points: int = max(10, int(distance / 15.0))
		var mid: Vector3 = start.lerp(end, 0.5)

		for i in range(num_points):
			var t: float = float(i) / (num_points - 1)
			var pos: Vector3 = start.lerp(end, t)

			# Add curve height using sine wave
			pos.y += sin(t * PI) * curve_height

			# Add lateral variation using randomized Bezier-like curves
			var lateral_offset: float = sin(t * PI * 2.0) * rng.randf_range(-5.0, 5.0)
			var perpendicular: Vector3 = (end - start).cross(Vector3.UP).normalized()
			pos += perpendicular * lateral_offset

			rail.curve.add_point(pos)

		_set_rail_tangents(rail)
		parent_node.add_child(rail)
		_create_rail_visual(rail)

		return rail

	func create_spiral_rail(center: Vector3, start_height: float, end_height: float,
							radius: float, turns: float, name_str: String) -> Path3D:
		"""Create a spiral rail for vertical transitions."""
		var rail: Path3D = GrindRailScript.new()
		rail.name = name_str
		rail.curve = Curve3D.new()

		var num_points: int = int(turns * 16)

		for i in range(num_points):
			var t: float = float(i) / (num_points - 1)
			var angle: float = t * turns * TAU
			var height: float = lerp(start_height, end_height, t)
			var current_radius: float = radius * (1.0 - t * 0.3)  # Spiral inward slightly

			var pos: Vector3 = center + Vector3(
				cos(angle) * current_radius,
				height,
				sin(angle) * current_radius
			)
			rail.curve.add_point(pos)

		_set_rail_tangents(rail)
		parent_node.add_child(rail)
		_create_rail_visual(rail)

		return rail

	func create_branching_rail(start: Vector3, branch_point: Vector3,
							   end_a: Vector3, end_b: Vector3, name_str: String) -> Array[Path3D]:
		"""Create a branching rail system with two paths from a common point."""
		var rails: Array[Path3D] = []

		# Main rail to branch point
		rails.append(create_curved_rail(start, branch_point, 10.0, name_str + "_main"))

		# Branch A
		rails.append(create_curved_rail(branch_point, end_a, 8.0, name_str + "_branch_a"))

		# Branch B
		rails.append(create_curved_rail(branch_point, end_b, 8.0, name_str + "_branch_b"))

		return rails

	func _set_rail_tangents(rail: Path3D) -> void:
		"""Set smooth tangents for rail curves."""
		for j in range(rail.curve.point_count):
			var tangent: Vector3
			if j == 0:
				tangent = (rail.curve.get_point_position(j + 1) - rail.curve.get_point_position(j)).normalized()
			elif j == rail.curve.point_count - 1:
				tangent = (rail.curve.get_point_position(j) - rail.curve.get_point_position(j - 1)).normalized()
			else:
				var prev_to_curr: Vector3 = rail.curve.get_point_position(j) - rail.curve.get_point_position(j - 1)
				var curr_to_next: Vector3 = rail.curve.get_point_position(j + 1) - rail.curve.get_point_position(j)
				tangent = (prev_to_curr + curr_to_next).normalized()

			rail.curve.set_point_in(j, -tangent * 0.5)
			rail.curve.set_point_out(j, tangent * 0.5)

	func _create_rail_visual(rail: Path3D) -> void:
		"""Create visual mesh for the rail using ImmediateMesh for tube geometry.
		Handles edge cases: short rails, flat segments, and near-vertical sections."""
		if not rail.curve or rail.curve.get_baked_length() < 1.0:
			return  # Skip rails too short to render

		var rail_visual: MeshInstance3D = MeshInstance3D.new()
		rail_visual.name = "RailVisual"

		var immediate_mesh: ImmediateMesh = ImmediateMesh.new()
		rail_visual.mesh = immediate_mesh

		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.7, 0.75, 0.85)  # Steel blue-gray
		material.metallic = 0.85
		material.roughness = 0.3
		material.emission_enabled = true
		material.emission = Color(0.3, 0.35, 0.45)  # Subtle glow
		material.emission_energy_multiplier = 0.3

		immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)

		var radial_segments: int = 8
		var rail_length: float = rail.curve.get_baked_length()
		# Clamp segments: min 4 for short rails, max 200 to prevent high vertex count
		var length_segments: int = clampi(int(rail_length * 0.5), 4, 200)

		# Track last valid frame to avoid degenerate segments
		var last_right: Vector3 = Vector3.RIGHT
		var last_up: Vector3 = Vector3.UP

		for i in range(length_segments):
			var offset: float = (float(i) / length_segments) * rail_length
			var next_offset: float = (float(i + 1) / length_segments) * rail_length

			var pos: Vector3 = rail.curve.sample_baked(offset)
			var next_pos: Vector3 = rail.curve.sample_baked(next_offset)

			var forward: Vector3 = (next_pos - pos)
			# Skip degenerate segments where positions are nearly identical
			if forward.length_squared() < 0.001:
				continue
			forward = forward.normalized()

			# Compute orthonormal frame, handling near-vertical rails
			var right: Vector3 = forward.cross(Vector3.UP)
			if right.length_squared() < 0.01:
				# Rail is nearly vertical - use last valid right or fallback
				right = forward.cross(last_right)
				if right.length_squared() < 0.01:
					right = forward.cross(Vector3.RIGHT)
			right = right.normalized()
			var up: Vector3 = right.cross(forward).normalized()

			# Cache valid frame for continuity
			last_right = right
			last_up = up

			for j in range(radial_segments):
				var angle_curr: float = (float(j) / radial_segments) * TAU
				var angle_next: float = (float(j + 1) / radial_segments) * TAU

				var offset_curr: Vector3 = (right * cos(angle_curr) + up * sin(angle_curr)) * RAIL_RADIUS
				var offset_next: Vector3 = (right * cos(angle_next) + up * sin(angle_next)) * RAIL_RADIUS

				var v1: Vector3 = pos + offset_curr
				var v2: Vector3 = pos + offset_next
				var v3: Vector3 = next_pos + offset_curr
				var v4: Vector3 = next_pos + offset_next

				immediate_mesh.surface_add_vertex(v1)
				immediate_mesh.surface_add_vertex(v2)
				immediate_mesh.surface_add_vertex(v3)

				immediate_mesh.surface_add_vertex(v2)
				immediate_mesh.surface_add_vertex(v4)
				immediate_mesh.surface_add_vertex(v3)

		immediate_mesh.surface_end()
		rail.add_child(rail_visual)

# =============================================================================
# ENTITY PLACER CLASS
# =============================================================================

class EntityPlacer:
	"""Handles placement of spawns, collectibles, power-ups, and enemies.
	Uses zone graph for balanced distribution via AStar3D pathfinding.
	Includes ground-snapping via raycast for proper entity placement."""

	var parent_node: Node3D
	var rng: RandomNumberGenerator
	var zones: Array[BSPNode]
	var astar: AStar3D
	var geometry_bounds_ref: Array  # Reference to level geometry for snapping

	func _init(parent: Node3D, random: RandomNumberGenerator, zone_list: Array[BSPNode]):
		parent_node = parent
		rng = random
		zones = zone_list
		astar = AStar3D.new()
		# Get geometry bounds from parent if available
		if parent.has_method("get") and parent.get("geometry_bounds"):
			geometry_bounds_ref = parent.geometry_bounds
		_build_zone_graph()

	func _build_zone_graph() -> void:
		"""Build AStar3D graph from zone centers for balanced item distribution.
		Connection threshold 300 units ensures reasonable path density."""
		for i in range(zones.size()):
			astar.add_point(i, zones[i].center)

		# Connect zones within reasonable distance for pathfinding
		for i in range(zones.size()):
			for j in range(i + 1, zones.size()):
				var dist: float = zones[i].center.distance_to(zones[j].center)
				if dist < 300.0:  # 300 unit threshold balances connectivity vs path complexity
					astar.connect_points(i, j)

	func snap_to_ground(pos: Vector3, default_height: float = 0.0) -> Vector3:
		"""Snap a position down to the nearest ground surface using geometry bounds.
		Falls back to default_height if no ground found."""
		var best_y: float = default_height
		var found_ground: bool = false

		for geo in geometry_bounds_ref:
			var geo_pos: Vector3 = geo.get("position", Vector3.ZERO)
			var geo_size: Vector3 = geo.get("size", Vector3.ONE)

			# Check if pos is within horizontal bounds of this geometry
			if abs(pos.x - geo_pos.x) < geo_size.x / 2.0 + 1.0 and \
			   abs(pos.z - geo_pos.z) < geo_size.z / 2.0 + 1.0:
				# Calculate top surface of this geometry
				var surface_y: float = geo_pos.y + geo_size.y / 2.0
				# Only snap if surface is below our current position
				if surface_y < pos.y and surface_y > best_y:
					best_y = surface_y
					found_ground = true

		return Vector3(pos.x, best_y + 0.1 if found_ground else default_height, pos.z)

	func create_player_spawn(position: Vector3, index: int) -> Marker3D:
		"""Create a player spawn point as Marker3D with PlayerSpawn group."""
		var spawn: Marker3D = Marker3D.new()
		spawn.name = "PlayerSpawn" + str(index)
		spawn.position = position + Vector3(0, 2, 0)  # Slightly above ground
		spawn.add_to_group("PlayerSpawn")
		parent_node.add_child(spawn)
		return spawn

	func create_ring(position: Vector3, index: int) -> Area3D:
		"""Create a collectible ring as Area3D with coin-like mesh."""
		var ring: Area3D = Area3D.new()
		ring.name = "Ring" + str(index)
		ring.position = position
		ring.collision_layer = 0
		ring.collision_mask = 2
		ring.add_to_group("collectible")
		ring.add_to_group("ring")
		parent_node.add_child(ring)

		# Create torus mesh for ring
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 0.3
		torus.outer_radius = 0.6
		mesh_instance.mesh = torus
		mesh_instance.rotation_degrees = Vector3(90, 0, 0)
		ring.add_child(mesh_instance)

		# Gold material
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.85, 0.0)
		material.metallic = 1.0
		material.roughness = 0.2
		material.emission_enabled = true
		material.emission = Color(1.0, 0.8, 0.0)
		material.emission_energy_multiplier = 0.5
		mesh_instance.material_override = material

		# Collision
		var collision: CollisionShape3D = CollisionShape3D.new()
		var sphere: SphereShape3D = SphereShape3D.new()
		sphere.radius = 0.8
		collision.shape = sphere
		ring.add_child(collision)

		# Attach ring collection script
		ring.set_script(_create_ring_script())

		return ring

	func create_powerup(position: Vector3, powerup_type: String, index: int) -> Area3D:
		"""Create a power-up (e.g., speed shoes) as Area3D with temporary buff."""
		var powerup: Area3D = Area3D.new()
		powerup.name = "PowerUp_" + powerup_type + "_" + str(index)
		powerup.position = position
		powerup.collision_layer = 0
		powerup.collision_mask = 2
		powerup.add_to_group("powerup")
		powerup.add_to_group("powerup_" + powerup_type)
		parent_node.add_child(powerup)

		# Create box mesh for power-up
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(1.5, 1.5, 1.5)
		mesh_instance.mesh = box
		powerup.add_child(mesh_instance)

		# Color based on type
		var material: StandardMaterial3D = StandardMaterial3D.new()
		match powerup_type:
			"speed":
				material.albedo_color = Color(0.0, 0.8, 1.0)
				material.emission = Color(0.0, 0.5, 0.8)
			"invincibility":
				material.albedo_color = Color(1.0, 1.0, 0.0)
				material.emission = Color(0.8, 0.8, 0.0)
			"magnet":
				material.albedo_color = Color(1.0, 0.0, 1.0)
				material.emission = Color(0.6, 0.0, 0.6)
			_:
				material.albedo_color = Color(0.5, 0.5, 0.5)
		material.metallic = 0.7
		material.roughness = 0.3
		material.emission_enabled = true
		material.emission_energy_multiplier = 0.6
		mesh_instance.material_override = material

		# Collision
		var collision: CollisionShape3D = CollisionShape3D.new()
		var sphere: SphereShape3D = SphereShape3D.new()
		sphere.radius = 1.2
		collision.shape = sphere
		powerup.add_child(collision)

		return powerup

	func create_spring(position: Vector3, impulse_strength: float, index: int) -> Area3D:
		"""Create a spring pad for jump impulses (Sonic-style bouncy mechanic)."""
		var spring: Area3D = Area3D.new()
		spring.name = "Spring" + str(index)
		spring.position = position
		spring.collision_layer = 0
		spring.collision_mask = 2
		spring.add_to_group("spring")
		parent_node.add_child(spring)

		# Base platform
		var base: MeshInstance3D = MeshInstance3D.new()
		var cylinder: CylinderMesh = CylinderMesh.new()
		cylinder.top_radius = 2.0
		cylinder.bottom_radius = 2.5
		cylinder.height = 0.5
		base.mesh = cylinder
		base.position = Vector3(0, 0.25, 0)
		spring.add_child(base)

		# Spring coil (simplified as cylinder)
		var coil: MeshInstance3D = MeshInstance3D.new()
		var coil_mesh: CylinderMesh = CylinderMesh.new()
		coil_mesh.top_radius = 1.0
		coil_mesh.bottom_radius = 1.0
		coil_mesh.height = 1.5
		coil.mesh = coil_mesh
		coil.position = Vector3(0, 1.25, 0)
		spring.add_child(coil)

		# Top cap
		var cap: MeshInstance3D = MeshInstance3D.new()
		var cap_mesh: CylinderMesh = CylinderMesh.new()
		cap_mesh.top_radius = 2.0
		cap_mesh.bottom_radius = 2.0
		cap_mesh.height = 0.3
		cap.mesh = cap_mesh
		cap.position = Vector3(0, 2.15, 0)
		spring.add_child(cap)

		# Materials
		var red_mat: StandardMaterial3D = StandardMaterial3D.new()
		red_mat.albedo_color = Color(1.0, 0.2, 0.2)
		red_mat.metallic = 0.5
		red_mat.roughness = 0.4
		base.material_override = red_mat
		cap.material_override = red_mat

		var yellow_mat: StandardMaterial3D = StandardMaterial3D.new()
		yellow_mat.albedo_color = Color(1.0, 0.9, 0.0)
		yellow_mat.metallic = 0.8
		yellow_mat.roughness = 0.2
		coil.material_override = yellow_mat

		# Collision
		var collision: CollisionShape3D = CollisionShape3D.new()
		var cyl_shape: CylinderShape3D = CylinderShape3D.new()
		cyl_shape.radius = 2.5
		cyl_shape.height = 2.5
		collision.shape = cyl_shape
		collision.position = Vector3(0, 1.25, 0)
		spring.add_child(collision)

		# Store impulse strength as metadata
		spring.set_meta("impulse_strength", impulse_strength)

		# Attach spring script
		spring.set_script(_create_spring_script())

		return spring

	func create_enemy_placeholder(position: Vector3, enemy_type: String, index: int) -> CharacterBody3D:
		"""Create an enemy placeholder (Badnik-style) as CharacterBody3D."""
		var enemy: CharacterBody3D = CharacterBody3D.new()
		enemy.name = "Enemy_" + enemy_type + "_" + str(index)
		enemy.position = position
		enemy.add_to_group("enemy")
		enemy.add_to_group("enemy_" + enemy_type)
		parent_node.add_child(enemy)

		# Simple spherical body for now
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 1.5
		sphere.height = 3.0
		mesh_instance.mesh = sphere
		enemy.add_child(mesh_instance)

		# Red metallic material (Badnik style)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.8, 0.2, 0.2)
		material.metallic = 0.6
		material.roughness = 0.3
		mesh_instance.material_override = material

		# Collision
		var collision: CollisionShape3D = CollisionShape3D.new()
		var sphere_shape: SphereShape3D = SphereShape3D.new()
		sphere_shape.radius = 1.5
		collision.shape = sphere_shape
		enemy.add_child(collision)

		return enemy

	func _create_ring_script() -> GDScript:
		"""Create inline script for ring collection."""
		var script: GDScript = GDScript.new()
		script.source_code = """
extends Area3D

var rotation_speed: float = 2.0
var bob_speed: float = 3.0
var bob_amount: float = 0.3
var initial_y: float = 0.0

func _ready() -> void:
	initial_y = position.y
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	rotation.y += rotation_speed * delta
	position.y = initial_y + sin(Time.get_ticks_msec() / 1000.0 * bob_speed) * bob_amount

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("collect_ring"):
		body.collect_ring()
	queue_free()
"""
		return script

	func _create_spring_script() -> GDScript:
		"""Create inline script for spring impulse."""
		var script: GDScript = GDScript.new()
		script.source_code = """
extends Area3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	var impulse: float = get_meta("impulse_strength", 300.0)
	if body is RigidBody3D:
		body.apply_central_impulse(Vector3.UP * impulse)
	elif body.has_method("apply_spring_impulse"):
		body.apply_spring_impulse(Vector3.UP * impulse)
"""
		return script

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # Don't auto-generate in editor
	configure_for_complexity()
	generate_level()

func configure_for_complexity() -> void:
	"""Configure parameters based on complexity. Arena size is set externally."""

	# Complexity affects DENSITY, not size
	var base_platforms: Dictionary = {1: 6, 2: 10, 3: 14, 4: 18}
	var base_ramps: Dictionary = {1: 4, 2: 6, 3: 8, 4: 10}
	var base_grind_rails: Dictionary = {1: 4, 2: 6, 3: 8, 4: 10}
	var base_vertical_rails: Dictionary = {1: 2, 2: 3, 3: 4, 4: 5}
	var base_loops: Dictionary = {1: 1, 2: 2, 3: 3, 4: 4}
	var base_springs: Dictionary = {1: 4, 2: 8, 3: 12, 4: 16}
	var base_rings: Dictionary = {1: 16, 2: 24, 3: 32, 4: 48}
	var base_powerups: Dictionary = {1: 2, 2: 4, 3: 6, 4: 8}

	var c: int = clampi(complexity, 1, 4)
	platform_count = base_platforms[c]
	ramp_count = base_ramps[c]
	grind_rail_count = base_grind_rails[c]
	vertical_rail_count = base_vertical_rails[c]
	loop_count = base_loops[c]
	spring_count = base_springs[c]
	ring_count = base_rings[c]
	powerup_count = base_powerups[c]

	print("=== SONIC BSP ARENA CONFIG ===")
	print("Arena Size: %.1f (BSP root: %.1f x %.1f)" % [arena_size, arena_size * 8.0, arena_size * 8.0])
	print("Complexity: %d" % complexity)
	print("Platforms: %d, Ramps: %d, Rails: %d, Loops: %d" % [platform_count, ramp_count, grind_rail_count, loop_count])
	print("Springs: %d, Rings: %d, PowerUps: %d" % [spring_count, ring_count, powerup_count])

# =============================================================================
# LEVEL GENERATION
# =============================================================================

func generate_level() -> void:
	"""Generate a complete procedural level using BSP subdivision."""
	print("Generating Sonic BSP-style arena...")
	print("Arena size parameter: %.1f" % arena_size)

	# Initialize RNG
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = level_seed if level_seed != 0 else int(Time.get_unix_time_from_system())

	noise = FastNoiseLite.new()
	noise.seed = rng.seed
	noise.frequency = 0.05

	clear_level()

	# Phase 1: BSP Subdivision
	_generate_bsp_tree(rng)

	# Phase 2: Create main floor and zone platforms
	_generate_main_floor()
	_generate_zone_platforms(rng)

	# Phase 3: Connect zones with paths and ramps
	_generate_zone_connections(rng)

	# Phase 4: Add Sonic elements
	_generate_grind_rails(rng)
	_generate_loops(rng)
	_generate_springs(rng)

	# Phase 5: Place entities
	_generate_player_spawns(rng)
	_generate_collectibles(rng)
	_generate_powerups(rng)

	# Phase 6: Environment
	_generate_outer_walls()
	_generate_death_zone()
	_generate_lighting()
	_generate_navigation_mesh()

	# Apply materials
	apply_procedural_textures()

	print("BSP Arena generation complete! Zones: %d" % bsp_leaves.size())

func clear_level() -> void:
	"""Clear all generated content."""
	for child in get_children():
		child.queue_free()
	platforms.clear()
	geometry_bounds.clear()
	bsp_leaves.clear()
	zone_graph.clear()
	bsp_root = null

# =============================================================================
# BSP GENERATION
# =============================================================================

func _generate_bsp_tree(rng: RandomNumberGenerator) -> void:
	"""Generate BSP tree with 8-16 leaves for room-sized zones."""
	# BSP area = arena_size * 4.0: provides enough space for 8-16 zones
	# when subdivided. This multiplier balances zone count vs zone size.
	var bsp_size: float = arena_size * 4.0
	var initial_rect: Rect2 = Rect2(-bsp_size / 2, -bsp_size / 2, bsp_size, bsp_size)

	# Dynamic min_zone_size: scales with arena (20% of arena_size)
	# Small arenas (60): min=12, Large arenas (240): min=48
	# This ensures proper subdivision regardless of arena scale
	var dynamic_min_zone: float = arena_size * 0.2

	bsp_root = BSPNode.new(initial_rect, 0.0, dynamic_min_zone)

	var nodes_to_split: Array[BSPNode] = [bsp_root]
	var target_leaves: int = rng.randi_range(8, 16)
	var max_iterations: int = 50
	var iteration: int = 0

	while bsp_leaves.size() + nodes_to_split.size() < target_leaves and iteration < max_iterations:
		iteration += 1

		if nodes_to_split.is_empty():
			break

		var node: BSPNode = nodes_to_split.pop_front()

		if not node.can_split():
			bsp_leaves.append(node)
			continue

		# 50% chance horizontal vs vertical split
		var horizontal: bool = rng.randf() > 0.5

		# Try split, if fails try other direction
		if not node.split(horizontal, rng):
			if not node.split(not horizontal, rng):
				bsp_leaves.append(node)
				continue

		# Add children to split queue
		nodes_to_split.append(node.left)
		nodes_to_split.append(node.right)

	# Any remaining nodes become leaves
	for node in nodes_to_split:
		bsp_leaves.append(node)

	# Finalize all leaves with zone IDs and platform rects
	for i in range(bsp_leaves.size()):
		bsp_leaves[i].finalize_zone(i, rng)

	# Apply symmetry for arena fairness (mirror half the zones)
	_apply_arena_symmetry(rng)

	print("BSP generated %d zones" % bsp_leaves.size())

func _apply_arena_symmetry(_rng: RandomNumberGenerator) -> void:
	"""Mirror zones across X=0 plane for multiplayer fairness.
	Creates symmetric pairs: for each zone with X>0, there's a matching zone at X<0."""
	# First pass: mark zones as sources (X>0) or targets (X<0)
	var source_zones: Array[BSPNode] = []
	var target_zones: Array[BSPNode] = []

	for zone in bsp_leaves:
		if zone.center.x > 5.0:  # Small threshold to avoid center zones
			zone.is_mirrored = true
			source_zones.append(zone)
		elif zone.center.x < -5.0:
			target_zones.append(zone)

	# Second pass: adjust target zones to mirror source zones
	# This creates balanced item/spawn distribution
	for i in range(min(source_zones.size(), target_zones.size())):
		var source: BSPNode = source_zones[i]
		var target: BSPNode = target_zones[i]
		# Mirror the height offset for visual symmetry
		target.height_offset = source.height_offset

# =============================================================================
# PLATFORM GENERATION
# =============================================================================

func _generate_main_floor() -> void:
	"""Generate the main central arena floor."""
	# Floor is 70% of arena_size: leaves 30% margin for perimeter elements (ramps, rails)
	var floor_size: float = arena_size * 0.7

	print("Creating main floor: %.1f x %.1f" % [floor_size, floor_size])

	var floor_mesh: BoxMesh = BoxMesh.new()
	# Height 2.0: thick enough to prevent tunneling, thin enough to be unobtrusive
	floor_mesh.size = Vector3(floor_size, 2.0, floor_size)
	# Subdivision 4x2x4: provides enough vertices for material variation without performance hit
	floor_mesh.subdivide_width = 4
	floor_mesh.subdivide_height = 2
	floor_mesh.subdivide_depth = 4

	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.name = "MainFloor"
	# Position Y=-1: centers the 2-unit thick floor so top surface is at Y=0
	floor_instance.position = Vector3(0, -1, 0)
	add_child(floor_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = floor_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	floor_instance.add_child(static_body)

	platforms.append(floor_instance)

func _generate_zone_platforms(rng: RandomNumberGenerator) -> void:
	"""Generate platforms from BSP zone leaves."""
	var builder: PlatformBuilder = PlatformBuilder.new(self, noise, geometry_bounds)
	# size_scale: ratio to default arena (120). Affects all spatial calculations.
	var size_scale: float = arena_size / 120.0

	# Dynamic platform size limits based on arena scale
	# Small arena (60): min=2.5, max=12.5
	# Default (120): min=5, max=25
	# Large (240): min=10, max=50
	var min_platform_size: float = 5.0 * size_scale
	var max_platform_size: float = 25.0 * size_scale

	for i in range(min(bsp_leaves.size(), platform_count)):
		var zone: BSPNode = bsp_leaves[i]

		# Scale platform rect: 0.3 for position, 0.15 for size
		# These multipliers convert BSP coordinates to arena scale
		var scaled_rect: Rect2 = Rect2(
			zone.platform_rect.position * size_scale * 0.3,
			zone.platform_rect.size * size_scale * 0.15
		)

		# Clamp to arena-scaled platform sizes
		scaled_rect.size.x = clampf(scaled_rect.size.x, min_platform_size, max_platform_size)
		scaled_rect.size.y = clampf(scaled_rect.size.y, min_platform_size, max_platform_size)

		# Height: base from zone offset + random variation (3-15 units default)
		var height: float = zone.height_offset * size_scale * 0.1 + rng.randf_range(3.0, 15.0) * size_scale

		var platform: MeshInstance3D = builder.create_platform(
			scaled_rect,
			height,
			"Platform",
			i,
			true
		)
		platforms.append(platform)

	print("Generated %d zone platforms" % min(bsp_leaves.size(), platform_count))

func _generate_zone_connections(rng: RandomNumberGenerator) -> void:
	"""Generate paths/ramps between connected zones."""
	var builder: PlatformBuilder = PlatformBuilder.new(self, noise, geometry_bounds)
	var size_scale: float = arena_size / 120.0
	var floor_radius: float = (arena_size * 0.7) / 2.0

	# Generate speed ramps at perimeter
	print("Placing %d speed ramps" % ramp_count)

	for i in range(ramp_count):
		var angle: float = (float(i) / ramp_count) * TAU + rng.randf_range(-0.1, 0.1)
		var ramp_distance: float = floor_radius * 0.75

		var x: float = cos(angle) * ramp_distance
		var z: float = sin(angle) * ramp_distance

		var ramp_length: float = (10.0 + rng.randf() * 4.0) * size_scale
		var ramp_width: float = (6.0 + rng.randf() * 2.0) * size_scale
		var ramp_size: Vector3 = Vector3(ramp_width, 0.5, ramp_length)

		var ramp_pos: Vector3 = Vector3(x, ramp_length * 0.15, z)
		var angle_to_center: float = atan2(-x, -z)
		var tilt: float = 15.0 + rng.randf() * 10.0

		var ramp_mesh: BoxMesh = BoxMesh.new()
		ramp_mesh.size = ramp_size

		var ramp_instance: MeshInstance3D = MeshInstance3D.new()
		ramp_instance.mesh = ramp_mesh
		ramp_instance.name = "Ramp" + str(i)
		ramp_instance.position = ramp_pos
		ramp_instance.rotation_degrees = Vector3(-tilt, rad_to_deg(angle_to_center), 0)
		add_child(ramp_instance)

		var static_body: StaticBody3D = StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = ramp_mesh.size
		collision.shape = shape
		static_body.add_child(collision)
		ramp_instance.add_child(static_body)

		platforms.append(ramp_instance)
		register_geometry(ramp_pos, ramp_size * 1.5)

	print("Generated %d speed ramps" % ramp_count)

# =============================================================================
# GRIND RAIL GENERATION
# =============================================================================

func _generate_grind_rails(rng: RandomNumberGenerator) -> void:
	"""Generate grind rails with perimeter, vertical, and connecting variations."""
	var rail_gen: RailGenerator = RailGenerator.new(self, rng)
	# Rail distance 45% of arena: places rails between floor edge (35%) and walls (90%)
	var rail_distance: float = arena_size * 0.45
	# Base rail height 2.5% of arena: ensures rails are reachable but elevated
	var base_rail_height: float = arena_size * 0.025

	print("Generating %d perimeter grind rails" % grind_rail_count)

	# Perimeter rails (curved arcs around arena)
	for i in range(grind_rail_count):
		# Evenly distribute rails around the perimeter
		var angle_start: float = (float(i) / grind_rail_count) * TAU
		# Arc spans 70% of segment: leaves gaps for jumps between rails
		var angle_end: float = angle_start + (TAU / grind_rail_count) * 0.7
		# Height cycles through 3 levels (i % 3): creates vertical variety
		# 2% of arena per level creates noticeable but traversable height differences
		var height: float = base_rail_height + (i % 3) * (arena_size * 0.02)

		var start_pos: Vector3 = Vector3(
			cos(angle_start) * rail_distance,
			height,
			sin(angle_start) * rail_distance
		)
		var end_pos: Vector3 = Vector3(
			cos(angle_end) * rail_distance,
			height + rng.randf_range(-5, 5),
			sin(angle_end) * rail_distance
		)

		rail_gen.create_curved_rail(start_pos, end_pos, arena_size * 0.01, "GrindRail" + str(i))

	# Vertical rails (spiral transitions)
	print("Generating %d vertical rails" % vertical_rail_count)

	for i in range(vertical_rail_count):
		var angle: float = (float(i) / vertical_rail_count) * TAU + PI / vertical_rail_count
		var center: Vector3 = Vector3(
			cos(angle) * rail_distance * 0.8,
			0,
			sin(angle) * rail_distance * 0.8
		)

		rail_gen.create_spiral_rail(
			center,
			arena_size * 0.015,
			arena_size * 0.08 + complexity * (arena_size * 0.02),
			10.0,
			0.5 + rng.randf() * 0.5,
			"VerticalRail" + str(i)
		)

	# Branching rails at chokepoints (complexity 3+)
	if complexity >= 3:
		var branch_count: int = complexity - 2
		for i in range(branch_count):
			var angle: float = rng.randf() * TAU
			var start: Vector3 = Vector3(
				cos(angle) * rail_distance * 0.5,
				5.0,
				sin(angle) * rail_distance * 0.5
			)
			var branch: Vector3 = Vector3(
				cos(angle) * rail_distance * 0.75,
				10.0,
				sin(angle) * rail_distance * 0.75
			)
			var end_a: Vector3 = Vector3(
				cos(angle + 0.3) * rail_distance,
				15.0,
				sin(angle + 0.3) * rail_distance
			)
			var end_b: Vector3 = Vector3(
				cos(angle - 0.3) * rail_distance,
				12.0,
				sin(angle - 0.3) * rail_distance
			)

			rail_gen.create_branching_rail(start, branch, end_a, end_b, "BranchRail" + str(i))

	print("Grind rail generation complete")

# =============================================================================
# SONIC ELEMENTS (LOOPS, SPRINGS)
# =============================================================================

func _generate_loops(rng: RandomNumberGenerator) -> void:
	"""Generate toroidal loops for momentum tricks."""
	var builder: PlatformBuilder = PlatformBuilder.new(self, noise, geometry_bounds)
	var floor_radius: float = (arena_size * 0.7) / 2.0

	print("Generating %d loops" % loop_count)

	for i in range(loop_count):
		var angle: float = (float(i) / loop_count) * TAU + TAU / (loop_count * 2)
		var distance: float = floor_radius * 0.6

		var center: Vector3 = Vector3(
			cos(angle) * distance,
			15.0 + rng.randf_range(0, 10),
			sin(angle) * distance
		)

		var loop_radius: float = 12.0 + rng.randf_range(0, 8)
		builder.create_loop(center, loop_radius, "Loop", i)

	print("Loop generation complete")

func _generate_springs(rng: RandomNumberGenerator) -> void:
	"""Generate spring pads for jump impulses."""
	var placer: EntityPlacer = EntityPlacer.new(self, rng, bsp_leaves)
	placer.geometry_bounds_ref = geometry_bounds  # Enable ground snapping
	var floor_radius: float = (arena_size * 0.7) / 2.0

	print("Generating %d springs" % spring_count)

	for i in range(spring_count):
		# Distribute springs around arena with slight angular randomization (±0.2 rad)
		var angle: float = (float(i) / spring_count) * TAU + rng.randf_range(-0.2, 0.2)
		# Distance 30-80% of floor radius: avoids center clutter and edge clipping
		var distance: float = rng.randf_range(floor_radius * 0.3, floor_radius * 0.8)

		var pos: Vector3 = Vector3(
			cos(angle) * distance,
			50.0,  # Start high for ground snapping
			sin(angle) * distance
		)

		# Snap spring to ground surface
		pos = placer.snap_to_ground(pos, 0.0)

		# Impulse strength: base 200 + random 0-150 + 30 per complexity level
		# Results in: C1=200-380, C2=230-410, C3=260-440, C4=290-470
		var impulse: float = 200.0 + rng.randf_range(0, 150) + complexity * 30.0
		placer.create_spring(pos, impulse, i)

	print("Spring generation complete")

# =============================================================================
# ENTITY PLACEMENT
# =============================================================================

func _generate_player_spawns(rng: RandomNumberGenerator) -> void:
	"""Generate player spawn points distributed across zones."""
	var placer: EntityPlacer = EntityPlacer.new(self, rng, bsp_leaves)
	var floor_radius: float = (arena_size * 0.7) / 2.0

	# Center spawn
	placer.create_player_spawn(Vector3.ZERO, 0)

	# Ring spawns
	var ring1_dist: float = floor_radius * 0.25
	var ring2_dist: float = floor_radius * 0.5

	for i in range(4):
		var angle: float = (float(i) / 4) * TAU
		placer.create_player_spawn(Vector3(cos(angle) * ring1_dist, 0, sin(angle) * ring1_dist), i + 1)
		placer.create_player_spawn(Vector3(cos(angle) * ring2_dist, 0, sin(angle) * ring2_dist), i + 5)

	# Zone-based spawns
	for i in range(min(bsp_leaves.size(), 8)):
		var zone: BSPNode = bsp_leaves[i]
		var spawn_pos: Vector3 = zone.center * (arena_size / 480.0)  # Scale to arena
		spawn_pos.y = zone.height_offset * 0.1 + 3.0
		placer.create_player_spawn(spawn_pos, i + 9)

func _generate_collectibles(rng: RandomNumberGenerator) -> void:
	"""Generate collectible rings scattered throughout arena."""
	var placer: EntityPlacer = EntityPlacer.new(self, rng, bsp_leaves)
	var floor_radius: float = (arena_size * 0.7) / 2.0

	print("Generating %d rings" % ring_count)

	for i in range(ring_count):
		var angle: float = rng.randf() * TAU
		var distance: float = rng.randf_range(5.0, floor_radius * 0.9)
		var height: float = rng.randf_range(2.0, 20.0)

		var pos: Vector3 = Vector3(
			cos(angle) * distance,
			height,
			sin(angle) * distance
		)

		# Check if position is clear
		if is_position_clear(pos, 2.0):
			placer.create_ring(pos, i)

func _generate_powerups(rng: RandomNumberGenerator) -> void:
	"""Generate power-ups at strategic chokepoints."""
	var placer: EntityPlacer = EntityPlacer.new(self, rng, bsp_leaves)
	var floor_radius: float = (arena_size * 0.7) / 2.0

	var powerup_types: Array[String] = ["speed", "invincibility", "magnet"]

	print("Generating %d power-ups" % powerup_count)

	for i in range(powerup_count):
		var angle: float = (float(i) / powerup_count) * TAU + rng.randf_range(-0.3, 0.3)
		var distance: float = floor_radius * 0.5
		var height: float = 5.0 + rng.randf_range(0, 15)

		var pos: Vector3 = Vector3(
			cos(angle) * distance,
			height,
			sin(angle) * distance
		)

		var powerup_type: String = powerup_types[rng.randi() % powerup_types.size()]
		placer.create_powerup(pos, powerup_type, i)

# =============================================================================
# ENVIRONMENT GENERATION
# =============================================================================

func _generate_outer_walls() -> void:
	"""Generate outer arena walls with collision for enclosure."""
	var wall_height: float = 50.0
	var wall_thickness: float = 5.0
	var arena_bounds: float = arena_size * 0.9

	# Create 4 walls around the arena
	var wall_positions: Array[Dictionary] = [
		{"pos": Vector3(0, wall_height / 2, arena_bounds), "size": Vector3(arena_bounds * 2, wall_height, wall_thickness)},
		{"pos": Vector3(0, wall_height / 2, -arena_bounds), "size": Vector3(arena_bounds * 2, wall_height, wall_thickness)},
		{"pos": Vector3(arena_bounds, wall_height / 2, 0), "size": Vector3(wall_thickness, wall_height, arena_bounds * 2)},
		{"pos": Vector3(-arena_bounds, wall_height / 2, 0), "size": Vector3(wall_thickness, wall_height, arena_bounds * 2)},
	]

	for i in range(wall_positions.size()):
		var wall_data: Dictionary = wall_positions[i]
		var wall: StaticBody3D = StaticBody3D.new()
		wall.name = "OuterWall" + str(i)
		wall.position = wall_data.pos
		add_child(wall)

		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = wall_data.size
		collision.shape = shape
		wall.add_child(collision)

		# Optional: Add invisible wall mesh for debugging
		# var mesh: MeshInstance3D = MeshInstance3D.new()
		# mesh.mesh = BoxMesh.new()
		# mesh.mesh.size = wall_data.size
		# wall.add_child(mesh)

func _generate_death_zone() -> void:
	"""Generate death zone below arena."""
	var death_zone: Area3D = Area3D.new()
	death_zone.name = "DeathZone"
	death_zone.position = Vector3(0, -50, 0)
	death_zone.collision_layer = 0
	death_zone.collision_mask = 2
	death_zone.add_to_group("death_zone")
	add_child(death_zone)

	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(arena_size * 2, 10, arena_size * 2)
	collision.shape = shape
	death_zone.add_child(collision)

	death_zone.body_entered.connect(_on_death_zone_entered)

func _on_death_zone_entered(body: Node3D) -> void:
	if body.has_method("fall_death"):
		body.fall_death()
	elif body.has_method("respawn"):
		body.respawn()

func _generate_lighting() -> void:
	"""Add strategic lighting for arena visibility."""
	# Main directional light (sun-like)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.98, 0.95)
	sun.shadow_enabled = true
	add_child(sun)

	# Ambient fill lights at corners
	var corner_positions: Array[Vector3] = [
		Vector3(arena_size * 0.4, 30, arena_size * 0.4),
		Vector3(-arena_size * 0.4, 30, arena_size * 0.4),
		Vector3(arena_size * 0.4, 30, -arena_size * 0.4),
		Vector3(-arena_size * 0.4, 30, -arena_size * 0.4),
	]

	for i in range(corner_positions.size()):
		var light: OmniLight3D = OmniLight3D.new()
		light.name = "CornerLight" + str(i)
		light.position = corner_positions[i]
		light.light_energy = 0.4
		light.light_color = Color(0.9, 0.95, 1.0)
		light.omni_range = arena_size * 0.8
		light.omni_attenuation = 1.5
		add_child(light)

func _generate_navigation_mesh() -> void:
	"""Generate navigation mesh for AI bots."""
	var nav_region: NavigationRegion3D = NavigationRegion3D.new()
	nav_region.name = "NavigationRegion"
	add_child(nav_region)

	var nav_mesh: NavigationMesh = NavigationMesh.new()
	nav_mesh.agent_radius = 1.0
	nav_mesh.agent_height = 2.0
	nav_mesh.agent_max_climb = 1.0
	nav_mesh.agent_max_slope = 45.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25

	nav_region.navigation_mesh = nav_mesh

	# Bake navigation in next frame (after geometry is ready)
	call_deferred("_bake_navigation", nav_region)

func _bake_navigation(nav_region: NavigationRegion3D) -> void:
	"""Bake navigation mesh after geometry is placed."""
	if not Engine.is_editor_hint():
		nav_region.bake_navigation_mesh()
		print("Navigation mesh baked")

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

func register_geometry(pos: Vector3, size: Vector3) -> void:
	"""Register geometry bounds for interactive object placement."""
	geometry_bounds.append({
		"position": pos,
		"size": size
	})

func is_position_clear(pos: Vector3, radius: float, check_height: bool = true) -> bool:
	"""Check if a position is clear of geometry."""
	for geo in geometry_bounds:
		var geo_pos: Vector3 = geo.position
		var geo_size: Vector3 = geo.size

		var margin: float = radius + 2.0
		if abs(pos.x - geo_pos.x) < (geo_size.x / 2.0 + margin) and \
		   abs(pos.z - geo_pos.z) < (geo_size.z / 2.0 + margin):
			if check_height and abs(pos.y - geo_pos.y) < (geo_size.y / 2.0 + margin):
				return false
			elif not check_height:
				return false
	return true

func apply_procedural_textures() -> void:
	"""Apply procedural materials to all geometry."""
	material_manager.apply_materials_to_level(self)

func get_spawn_points() -> PackedVector3Array:
	"""Get all player spawn points for multiplayer."""
	var spawns: PackedVector3Array = PackedVector3Array()
	var floor_radius: float = (arena_size * 0.7) / 2.0

	# Center spawn
	spawns.append(Vector3(0, 2, 0))

	# Ring spawns that SCALE with arena size
	var ring1_dist: float = floor_radius * 0.25
	var ring2_dist: float = floor_radius * 0.5

	for i in range(4):
		var angle: float = (float(i) / 4) * TAU
		spawns.append(Vector3(cos(angle) * ring1_dist, 2, sin(angle) * ring1_dist))
		spawns.append(Vector3(cos(angle) * ring2_dist, 2, sin(angle) * ring2_dist))

	# Platform spawns
	for platform in platforms:
		if platform.name.begins_with("Platform"):
			var spawn_pos: Vector3 = platform.position
			spawn_pos.y += 3.0
			spawns.append(spawn_pos)

	# Zone-based spawns from BSP
	for zone in bsp_leaves:
		var spawn_pos: Vector3 = zone.center * (arena_size / 480.0)
		spawn_pos.y = zone.height_offset * 0.1 + 5.0
		spawns.append(spawn_pos)

	return spawns

# =============================================================================
# EXPANSION SYSTEM (for mid-round expansion)
# =============================================================================

func generate_secondary_map(offset: Vector3) -> void:
	"""Generate secondary arena at offset position."""
	print("Generating secondary map at offset: ", offset)
	var secondary_seed: int = noise.seed + 1000
	var old_seed: int = noise.seed
	noise.seed = secondary_seed

	# Secondary floor
	var floor_size: float = arena_size * 0.7
	var floor_mesh: BoxMesh = BoxMesh.new()
	floor_mesh.size = Vector3(floor_size, 2.0, floor_size)

	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.name = "SecondaryFloor"
	floor_instance.position = offset + Vector3(0, -1, 0)
	add_child(floor_instance)

	var static_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = floor_mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	floor_instance.add_child(static_body)
	platforms.append(floor_instance)

	noise.seed = old_seed
	print("Secondary map generation complete")

func generate_connecting_rail(start_pos: Vector3, end_pos: Vector3) -> void:
	"""Generate connecting rail between main and secondary arenas."""
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = noise.seed + 2000

	var rail_gen: RailGenerator = RailGenerator.new(self, rng)
	rail_gen.create_curved_rail(start_pos, end_pos, 15.0, "ConnectingRail")

# =============================================================================
# TESTING & VALIDATION
# =============================================================================

func test_level_enclosure() -> bool:
	"""Test level for proper enclosure using raycasts."""
	var space_state = get_world_3d().direct_space_state
	var test_passed: bool = true

	# Test points around the arena perimeter
	var test_points: int = 16
	var test_radius: float = arena_size * 0.85

	for i in range(test_points):
		var angle: float = (float(i) / test_points) * TAU
		var origin: Vector3 = Vector3(
			cos(angle) * test_radius,
			10.0,
			sin(angle) * test_radius
		)

		# Cast ray outward
		var query = PhysicsRayQueryParameters3D.create(
			origin,
			origin + Vector3(cos(angle), 0, sin(angle)) * 50.0
		)
		var result = space_state.intersect_ray(query)

		if result.is_empty():
			print("WARNING: Enclosure leak detected at angle %.1f" % rad_to_deg(angle))
			test_passed = false

	if test_passed:
		print("Level enclosure test PASSED")
	else:
		print("Level enclosure test FAILED - check outer walls")

	return test_passed

func _save_generated_scene() -> void:
	"""Save the generated level as a PackedScene."""
	var packed_scene: PackedScene = PackedScene.new()
	packed_scene.pack(self)

	var error = ResourceSaver.save(packed_scene, "res://generated_level.tscn")
	if error == OK:
		print("Level saved to res://generated_level.tscn")
	else:
		print("Failed to save level: ", error)

# =============================================================================
# DEBUG FUNCTIONS
# =============================================================================

func debug_print_bsp_tree() -> void:
	"""Print BSP tree structure for debugging."""
	print("=== BSP TREE DEBUG ===")
	print("Total zones: %d" % bsp_leaves.size())
	for zone in bsp_leaves:
		print("Zone %d: bounds=%s, height=%.1f, center=%s" % [
			zone.zone_id,
			zone.bounds,
			zone.height_offset,
			zone.center
		])

func debug_validate_paths() -> void:
	"""Validate that all zones are reachable via the graph."""
	if bsp_leaves.is_empty():
		print("No zones to validate")
		return

	var placer: EntityPlacer = EntityPlacer.new(self, RandomNumberGenerator.new(), bsp_leaves)

	# Check connectivity from zone 0 to all others
	var reachable: int = 0
	for i in range(1, bsp_leaves.size()):
		var path = placer.astar.get_id_path(0, i)
		if not path.is_empty():
			reachable += 1
		else:
			print("WARNING: Zone %d not reachable from zone 0" % i)

	print("Path validation: %d/%d zones reachable" % [reachable, bsp_leaves.size() - 1])
