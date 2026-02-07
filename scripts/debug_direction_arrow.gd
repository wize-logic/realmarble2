extends Node3D
## Debug Direction Arrow
## Shows a visual arrow in front of bots to indicate their facing direction

var target_bot: Node = null
var arrow_mesh: MeshInstance3D = null
var update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.016  # Update every frame (~60fps)
const ARROW_DISTANCE: float = 3.0  # Distance in front of bot
const ARROW_HEIGHT_OFFSET: float = 0.5  # Height above bot center

func _ready() -> void:
	# Create arrow mesh
	arrow_mesh = MeshInstance3D.new()
	add_child(arrow_mesh)

	# Create arrow geometry using ImmediateMesh for a simple arrow shape
	var mesh = ImmediateMesh.new()
	arrow_mesh.mesh = mesh

	# Use shared debug arrow material from pool
	arrow_mesh.material_override = MaterialPool.debug_arrow_material

	# Build the arrow shape
	build_arrow_mesh()

func build_arrow_mesh() -> void:
	"""Build a simple arrow mesh pointing forward (+Z direction)"""
	var mesh = arrow_mesh.mesh as ImmediateMesh
	if not mesh:
		return

	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	# Arrow dimensions
	var arrow_length: float = 1.0
	var arrow_width: float = 0.3
	var arrow_head_length: float = 0.4
	var arrow_head_width: float = 0.6

	# Arrow shaft (rectangle)
	var shaft_half: float = arrow_width / 2.0
	var shaft_end: float = arrow_length - arrow_head_length

	# Shaft front face
	mesh.surface_add_vertex(Vector3(-shaft_half, shaft_half, 0))
	mesh.surface_add_vertex(Vector3(shaft_half, shaft_half, 0))
	mesh.surface_add_vertex(Vector3(shaft_half, shaft_half, shaft_end))

	mesh.surface_add_vertex(Vector3(-shaft_half, shaft_half, 0))
	mesh.surface_add_vertex(Vector3(shaft_half, shaft_half, shaft_end))
	mesh.surface_add_vertex(Vector3(-shaft_half, shaft_half, shaft_end))

	# Shaft back face
	mesh.surface_add_vertex(Vector3(-shaft_half, -shaft_half, 0))
	mesh.surface_add_vertex(Vector3(shaft_half, -shaft_half, shaft_end))
	mesh.surface_add_vertex(Vector3(shaft_half, -shaft_half, 0))

	mesh.surface_add_vertex(Vector3(-shaft_half, -shaft_half, 0))
	mesh.surface_add_vertex(Vector3(-shaft_half, -shaft_half, shaft_end))
	mesh.surface_add_vertex(Vector3(shaft_half, -shaft_half, shaft_end))

	# Shaft left face
	mesh.surface_add_vertex(Vector3(-shaft_half, -shaft_half, 0))
	mesh.surface_add_vertex(Vector3(-shaft_half, shaft_half, 0))
	mesh.surface_add_vertex(Vector3(-shaft_half, shaft_half, shaft_end))

	mesh.surface_add_vertex(Vector3(-shaft_half, -shaft_half, 0))
	mesh.surface_add_vertex(Vector3(-shaft_half, shaft_half, shaft_end))
	mesh.surface_add_vertex(Vector3(-shaft_half, -shaft_half, shaft_end))

	# Shaft right face
	mesh.surface_add_vertex(Vector3(shaft_half, -shaft_half, 0))
	mesh.surface_add_vertex(Vector3(shaft_half, shaft_half, shaft_end))
	mesh.surface_add_vertex(Vector3(shaft_half, shaft_half, 0))

	mesh.surface_add_vertex(Vector3(shaft_half, -shaft_half, 0))
	mesh.surface_add_vertex(Vector3(shaft_half, -shaft_half, shaft_end))
	mesh.surface_add_vertex(Vector3(shaft_half, shaft_half, shaft_end))

	# Arrow head (triangle/cone)
	var head_half: float = arrow_head_width / 2.0
	var tip: Vector3 = Vector3(0, 0, arrow_length)

	# Head top face
	mesh.surface_add_vertex(Vector3(-head_half, shaft_half, shaft_end))
	mesh.surface_add_vertex(Vector3(head_half, shaft_half, shaft_end))
	mesh.surface_add_vertex(tip)

	# Head bottom face
	mesh.surface_add_vertex(Vector3(-head_half, -shaft_half, shaft_end))
	mesh.surface_add_vertex(tip)
	mesh.surface_add_vertex(Vector3(head_half, -shaft_half, shaft_end))

	# Head left face
	mesh.surface_add_vertex(Vector3(-head_half, -shaft_half, shaft_end))
	mesh.surface_add_vertex(Vector3(-head_half, shaft_half, shaft_end))
	mesh.surface_add_vertex(tip)

	# Head right face
	mesh.surface_add_vertex(Vector3(head_half, -shaft_half, shaft_end))
	mesh.surface_add_vertex(tip)
	mesh.surface_add_vertex(Vector3(head_half, shaft_half, shaft_end))

	mesh.surface_end()

func setup(bot: Node) -> void:
	"""Initialize arrow for a specific bot"""
	target_bot = bot
	if target_bot:
		update_arrow_position()

func _process(delta: float) -> void:
	if not target_bot or not is_instance_valid(target_bot):
		queue_free()
		return

	update_timer += delta
	if update_timer >= UPDATE_INTERVAL:
		update_timer = 0.0
		update_arrow_position()

func update_arrow_position() -> void:
	"""Update the arrow position and rotation to show bot's facing direction"""
	if not target_bot:
		return

	# Get bot's forward direction from its transform
	# In Godot, -Z is forward by default, but we want to show where the bot is actually facing
	var forward: Vector3 = -target_bot.global_transform.basis.z
	forward.y = 0  # Keep arrow horizontal
	forward = forward.normalized()

	# Position arrow in front of bot
	var arrow_position: Vector3 = target_bot.global_position + forward * ARROW_DISTANCE
	arrow_position.y = target_bot.global_position.y + ARROW_HEIGHT_OFFSET

	global_position = arrow_position

	# Rotate arrow to point in the forward direction
	# We need to align our arrow's +Z axis with the forward direction
	if forward.length() > 0.001:
		var target_rotation = Basis.looking_at(forward, Vector3.UP)
		global_transform.basis = target_rotation
