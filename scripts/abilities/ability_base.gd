extends Node3D
class_name Ability

## Base class for all Kirby-style abilities
## Abilities can be picked up, used, and dropped by players

@export var ability_name: String = "Ability"
@export var ability_color: Color = Color.WHITE
@export var cooldown_time: float = 2.0

var player: Node = null  # Reference to the player who has this ability
var is_on_cooldown: bool = false
var cooldown_timer: float = 0.0
var ability_sound: AudioStreamPlayer3D = null  # Sound effect for this ability

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	# Handle cooldown
	if is_on_cooldown:
		cooldown_timer -= delta
		if cooldown_timer <= 0.0:
			is_on_cooldown = false

## Called when the ability is picked up by a player
func pickup(p_player: Node) -> void:
	player = p_player
	print("Player picked up: ", ability_name)

## Called when the ability is dropped by the player
func drop() -> void:
	player = null
	print("Player dropped: ", ability_name)

## Called when the player uses the ability
func use() -> void:
	if is_on_cooldown:
		print("Ability on cooldown! %.1fs remaining" % cooldown_timer)
		return

	# Call the specific ability implementation
	activate()

	# Start cooldown
	is_on_cooldown = true
	cooldown_timer = cooldown_time

## Override this in specific abilities
func activate() -> void:
	print("Ability activated: ", ability_name)

## Check if the ability is ready to use
func is_ready() -> bool:
	return not is_on_cooldown
