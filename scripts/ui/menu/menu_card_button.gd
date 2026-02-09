extends PanelContainer
class_name MenuCardButton

## Rocket League-style glowing menu card button

signal card_pressed

@export var button_text: String = "BUTTON"
@export var is_large: bool = false
@export var button_action: String = ""

var is_hovered: bool = false
var is_focused: bool = false
var original_scale: Vector2 = Vector2.ONE
var target_scale: Vector2 = Vector2.ONE
var _cached_hover_state: bool = false

@onready var label: Label = $MarginContainer/Label
@onready var panel_material: ShaderMaterial = material as ShaderMaterial

# Sound effects (will be set by parent)
var hover_sound: AudioStreamPlayer
var select_sound: AudioStreamPlayer

func _ready() -> void:
	# Set up the button text
	if label:
		label.text = button_text

	# Store original scale for animations
	original_scale = scale
	target_scale = original_scale

	# Set up shader material
	if not material:
		material = ShaderMaterial.new()
		var shader: Shader = load("res://scripts/shaders/card_glow.gdshader")
		material.shader = shader

	panel_material = material as ShaderMaterial

	# Connect mouse signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

	# Set size based on is_large
	custom_minimum_size = Vector2(400, 80) if is_large else Vector2(350, 60)

	# Start with processing disabled - enabled on hover/focus
	set_process(false)

func _process(delta: float) -> void:
	# Smooth scale animation
	scale = lerp(scale, target_scale, delta * 10.0)

	# Update shader hover state only when changed
	var current_hover_state: bool = is_hovered or is_focused
	if current_hover_state != _cached_hover_state:
		_cached_hover_state = current_hover_state
		if panel_material:
			panel_material.set_shader_parameter("is_hovered", current_hover_state)

	# Disable processing when animation is done and not hovered/focused
	if not is_hovered and not is_focused and scale.is_equal_approx(target_scale):
		set_process(false)

func _on_mouse_entered() -> void:
	is_hovered = true
	target_scale = original_scale * 1.05
	set_process(true)
	if hover_sound:
		hover_sound.play()

func _on_mouse_exited() -> void:
	is_hovered = false
	target_scale = original_scale
	set_process(true)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_activate()

func focus_entered() -> void:
	is_focused = true
	target_scale = original_scale * 1.05
	set_process(true)
	if hover_sound:
		hover_sound.play()

func focus_exited() -> void:
	is_focused = false
	target_scale = original_scale
	set_process(true)

func _activate() -> void:
	if select_sound:
		select_sound.play()
	card_pressed.emit()

	# Scale punch effect
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", original_scale * 0.95, 0.1)
	tween.tween_property(self, "scale", original_scale, 0.1)

func set_sounds(hover: AudioStreamPlayer, select: AudioStreamPlayer) -> void:
	hover_sound = hover
	select_sound = select
