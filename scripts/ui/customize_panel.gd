extends PanelContainer

## Customize Panel UI
## Allows players to customize their marble appearance

signal closed
signal color_selected(color_index: int)

# References to UI elements
var close_button: Button = null
var color_grid: GridContainer = null
var color_name_label: Label = null
var preview_viewport: SubViewport = null
var preview_marble_mesh: MeshInstance3D = null
var preview_camera: Camera3D = null
var preview_light: DirectionalLight3D = null

# Material manager reference
var marble_material_manager = preload("res://scripts/marble_material_manager.gd").new()

# Currently selected color index
var selected_color_index: int = 0
var color_buttons: Array[Button] = []

# Preview rotation
var preview_rotation_speed: float = 0.5

func _ready() -> void:
	# Node references are set up by world.gd during creation
	pass

func _process(delta: float) -> void:
	# Rotate the preview marble
	if preview_marble_mesh and is_instance_valid(preview_marble_mesh):
		preview_marble_mesh.rotate_y(preview_rotation_speed * delta)

func setup_color_grid() -> void:
	"""Set up the color selection grid with all available colors"""
	if not color_grid:
		return

	# Clear existing buttons
	for child in color_grid.get_children():
		child.queue_free()
	color_buttons.clear()

	var color_count = marble_material_manager.get_color_scheme_count()

	for i in range(color_count):
		var color_btn = Button.new()
		color_btn.custom_minimum_size = Vector2(50, 50)
		color_btn.tooltip_text = marble_material_manager.get_color_scheme_name(i)

		# Get the primary color from the scheme for the button background
		var scheme = marble_material_manager.COLOR_SCHEMES[i]
		var primary_color: Color = scheme.primary

		# Create button style with the marble color
		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = primary_color
		btn_style.set_corner_radius_all(8)
		btn_style.border_color = Color(0.3, 0.7, 1, 0.4)
		btn_style.set_border_width_all(2)

		var btn_hover = StyleBoxFlat.new()
		btn_hover.bg_color = primary_color.lightened(0.2)
		btn_hover.set_corner_radius_all(8)
		btn_hover.border_color = Color(0.3, 0.7, 1, 0.8)
		btn_hover.set_border_width_all(2)

		var btn_pressed = StyleBoxFlat.new()
		btn_pressed.bg_color = primary_color.lightened(0.3)
		btn_pressed.set_corner_radius_all(8)
		btn_pressed.border_color = Color(0.4, 0.8, 1, 1)
		btn_pressed.set_border_width_all(3)

		color_btn.add_theme_stylebox_override("normal", btn_style)
		color_btn.add_theme_stylebox_override("hover", btn_hover)
		color_btn.add_theme_stylebox_override("pressed", btn_pressed)
		color_btn.add_theme_stylebox_override("focus", btn_hover)

		color_btn.pressed.connect(_on_color_selected.bind(i))
		color_grid.add_child(color_btn)
		color_buttons.append(color_btn)

	# Highlight the currently selected color
	_update_selection_highlight()

func _on_color_selected(index: int) -> void:
	"""Handle color selection"""
	selected_color_index = index

	# Update the preview marble material
	if preview_marble_mesh and is_instance_valid(preview_marble_mesh):
		var material = marble_material_manager.create_marble_material(index)
		preview_marble_mesh.material_override = material

	# Update color name label
	if color_name_label:
		color_name_label.text = marble_material_manager.get_color_scheme_name(index)

	# Update selection highlight
	_update_selection_highlight()

	# Emit signal
	color_selected.emit(index)

func _update_selection_highlight() -> void:
	"""Update the visual highlight on the selected color button"""
	for i in range(color_buttons.size()):
		var btn = color_buttons[i]
		if not is_instance_valid(btn):
			continue

		var scheme = marble_material_manager.COLOR_SCHEMES[i]
		var primary_color: Color = scheme.primary

		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = primary_color
		btn_style.set_corner_radius_all(8)

		if i == selected_color_index:
			# Selected - bright border
			btn_style.border_color = Color(1, 1, 1, 1)
			btn_style.set_border_width_all(4)
		else:
			# Not selected - subtle border
			btn_style.border_color = Color(0.3, 0.7, 1, 0.4)
			btn_style.set_border_width_all(2)

		btn.add_theme_stylebox_override("normal", btn_style)

func set_selected_color(index: int) -> void:
	"""Set the selected color index and update UI"""
	if index >= 0 and index < marble_material_manager.get_color_scheme_count():
		selected_color_index = index
		_on_color_selected(index)

func get_selected_color() -> int:
	"""Get the currently selected color index"""
	return selected_color_index

func show_panel() -> void:
	"""Show the customize panel"""
	show()

	# Apply material to preview marble with current selection
	if preview_marble_mesh and is_instance_valid(preview_marble_mesh):
		var material = marble_material_manager.create_marble_material(selected_color_index)
		preview_marble_mesh.material_override = material

	# Update color name
	if color_name_label:
		color_name_label.text = marble_material_manager.get_color_scheme_name(selected_color_index)

	# Update selection highlight
	_update_selection_highlight()

func _on_close_pressed() -> void:
	closed.emit()
	hide()
