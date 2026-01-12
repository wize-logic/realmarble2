extends Node3D

## Spawns collectible orbs at predefined locations in the map

const OrbScene = preload("res://collectible_orb.tscn")

# Orb spawn locations (spread around the map)
@export var orb_positions: PackedVector3Array = [
	Vector3(0, 2, 0),      # Center
	Vector3(10, 3, 10),    # Top right
	Vector3(-10, 3, 10),   # Top left
	Vector3(10, 3, -10),   # Bottom right
	Vector3(-10, 3, -10),  # Bottom left
	Vector3(15, 4, 0),     # Right side
	Vector3(-15, 4, 0),    # Left side
	Vector3(0, 4, 15),     # Top
	Vector3(0, 4, -15),    # Bottom
]

var spawned_orbs: Array[Area3D] = []

func _ready() -> void:
	# Spawn orbs at all positions
	call_deferred("spawn_orbs")

func spawn_orbs() -> void:
	"""Spawn orbs at all predefined positions"""
	for pos in orb_positions:
		spawn_orb_at_position(pos)

	print("Spawned %d orbs in the map" % spawned_orbs.size())

func spawn_orb_at_position(pos: Vector3) -> void:
	"""Spawn a single orb at the given position"""
	var orb: Area3D = OrbScene.instantiate()
	add_child(orb)
	orb.global_position = pos
	spawned_orbs.append(orb)
