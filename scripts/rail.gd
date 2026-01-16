extends Path3D
class_name Rail

@export var rail_speed: float = 15.0
@export var rail_boost: float = 1.3  # Speed multiplier when grinding
@export var rail_width: float = 0.3

var rail_mesh: MeshInstance3D
var rail_material: StandardMaterial3D
var detection_area: Area3D
var grinding_players: Array = []

func _ready():
	add_to_group("rails")
	create_rail_visual()
	create_detection_area()

func create_rail_visual():
	# Create the visual rail mesh using CSGCylinder3D for the tube
	var csg_path = CSGPolygon3D.new()
	csg_path.polygon = PackedVector2Array([
		Vector2(-rail_width/2, 0),
		Vector2(rail_width/2, 0)
	])
	csg_path.mode = CSGPolygon3D.MODE_PATH
	csg_path.path_node = get_path()
	csg_path.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	csg_path.path_interval = 0.5
	csg_path.path_rotation = CSGPolygon3D.PATH_ROTATION_POLYGON

	# Create material for the rail
	rail_material = StandardMaterial3D.new()
	rail_material.albedo_color = Color(0.8, 0.8, 0.9)  # Light gray/silver
	rail_material.metallic = 0.9
	rail_material.roughness = 0.3
	rail_material.emission_enabled = true
	rail_material.emission = Color(0.3, 0.5, 1.0)  # Blue glow
	rail_material.emission_energy_multiplier = 0.5

	csg_path.material = rail_material
	add_child(csg_path)

func create_detection_area():
	# Create an Area3D that follows the path for player detection
	var path_follow = PathFollow3D.new()
	path_follow.loop = false
	add_child(path_follow)

	detection_area = Area3D.new()
	detection_area.collision_layer = 0
	detection_area.collision_mask = 2  # Detect players on layer 2
	path_follow.add_child(detection_area)

	# Create multiple collision shapes along the path
	var num_segments = max(10, int(curve.get_baked_length() / 2.0))
	for i in range(num_segments):
		var t = float(i) / float(num_segments - 1)
		var segment_follow = PathFollow3D.new()
		segment_follow.progress_ratio = t
		segment_follow.loop = false
		add_child(segment_follow)

		var area = Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		segment_follow.add_child(area)

		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(2.0, 2.0, 2.0)  # Detection box around rail
		collision.shape = shape
		area.add_child(collision)

		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)

func _on_body_entered(body):
	if body.has_method("start_grinding"):
		if not body in grinding_players:
			grinding_players.append(body)
			body.start_grinding(self)

func _on_body_exited(body):
	if body in grinding_players:
		grinding_players.erase(body)
		if body.has_method("stop_grinding"):
			body.stop_grinding()

func get_nearest_point_on_rail(global_pos: Vector3) -> Dictionary:
	# Find the nearest point on the rail curve
	var nearest_offset = curve.get_closest_offset(to_local(global_pos))
	var nearest_point = curve.sample_baked(nearest_offset)
	var forward = curve.sample_baked(nearest_offset + 0.1) - nearest_point
	forward = forward.normalized()

	return {
		"position": to_global(nearest_point),
		"offset": nearest_offset,
		"forward": forward,
		"progress": nearest_offset / curve.get_baked_length()
	}

func apply_grinding_effect(player_pos: Vector3):
	# Make the rail glow when being grinded
	if rail_material:
		rail_material.emission_energy_multiplier = lerp(rail_material.emission_energy_multiplier, 2.0, 0.1)

func _process(delta):
	# Fade rail glow back to normal
	if rail_material and grinding_players.is_empty():
		rail_material.emission_energy_multiplier = lerp(rail_material.emission_energy_multiplier, 0.5, 0.05)
