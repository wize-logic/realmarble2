extends Control

## Expansion Notification UI
## Displays "NEW AREA AVAILABLE" notification with flashing effect

@onready var notification_label: Label = null
var flash_timer: float = 0.0
var flash_duration: float = 5.0  # Flash for 5 seconds
var is_flashing: bool = false

func _ready() -> void:
	# Set up full screen control
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create notification label
	notification_label = Label.new()
	notification_label.name = "NotificationLabel"
	notification_label.text = "NEW AREA AVAILABLE"
	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Position at top center of screen
	notification_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	notification_label.anchor_left = 0.0
	notification_label.anchor_right = 1.0
	notification_label.anchor_top = 0.15
	notification_label.anchor_bottom = 0.15
	notification_label.offset_top = -50
	notification_label.offset_bottom = 50

	# Style the label - large, bold, attention-grabbing
	notification_label.add_theme_font_size_override("font_size", 72)
	notification_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0, 1.0))  # Gold color
	notification_label.add_theme_color_override("font_outline_color", Color.BLACK)
	notification_label.add_theme_constant_override("outline_size", 8)

	# Create a glow effect panel behind the text
	var glow_panel = PanelContainer.new()
	glow_panel.name = "GlowPanel"
	glow_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	glow_panel.anchor_left = 0.3
	glow_panel.anchor_right = 0.7
	glow_panel.anchor_top = 0.15
	glow_panel.anchor_bottom = 0.15
	glow_panel.offset_top = -60
	glow_panel.offset_bottom = 60
	glow_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Apply glowing panel style
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	panel_style.set_corner_radius_all(15)
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(1.0, 0.8, 0.0, 0.8)  # Gold border
	glow_panel.add_theme_stylebox_override("panel", panel_style)

	add_child(glow_panel)
	add_child(notification_label)

	# Start hidden
	visible = false

func _process(delta: float) -> void:
	if is_flashing:
		flash_timer -= delta

		# Flash effect - oscillate alpha
		var flash_frequency: float = 4.0  # Flashes per second
		var alpha: float = 0.5 + 0.5 * sin(flash_timer * flash_frequency * TAU)

		if notification_label:
			var color = notification_label.get_theme_color("font_color", "Label")
			color.a = alpha
			notification_label.add_theme_color_override("font_color", color)

		# Stop flashing after duration
		if flash_timer <= 0:
			stop_flashing()

func show_notification() -> void:
	"""Show the expansion notification with flashing effect"""
	visible = true
	is_flashing = true
	flash_timer = flash_duration
	print("Showing expansion notification: NEW AREA AVAILABLE")

func stop_flashing() -> void:
	"""Stop the flashing effect and hide the notification"""
	is_flashing = false
	visible = false
	print("Expansion notification hidden")
