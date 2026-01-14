extends Camera3D
class_name OrbitCamera

## Slowly orbiting camera for main menu

@export var orbit_radius: float = 15.0
@export var orbit_height: float = 5.0
@export var orbit_speed: float = 0.05  # Radians per second
@export var look_at_target: Vector3 = Vector3.ZERO
@export var vertical_bob_amount: float = 2.0
@export var vertical_bob_speed: float = 0.3

var orbit_angle: float = 0.0

func _process(delta: float) -> void:
	# Update orbit angle
	orbit_angle += orbit_speed * delta

	# Calculate camera position in orbit
	var x: float = cos(orbit_angle) * orbit_radius
	var z: float = sin(orbit_angle) * orbit_radius
	var y: float = orbit_height + sin(orbit_angle * 2.0 + vertical_bob_speed) * vertical_bob_amount

	# Set position
	global_position = Vector3(x, y, z)

	# Look at center
	look_at(look_at_target, Vector3.UP)
