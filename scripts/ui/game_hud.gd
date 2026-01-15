extends Control

## Game HUD for displaying timer, score, level, and ability info

@onready var timer_label: Label = $MarginContainer/VBoxContainer/TimerLabel
@onready var score_label: Label = $MarginContainer/VBoxContainer/ScoreLabel
@onready var level_label: Label = $MarginContainer/VBoxContainer/LevelLabel
@onready var ability_label: Label = $MarginContainer/VBoxContainer/AbilityLabel
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthLabel

var world: Node = null
var player: Node = null

func _ready() -> void:
	# Find world and player references
	world = get_tree().root.get_node_or_null("World")

	# Try to find the local player
	call_deferred("find_local_player")

func find_local_player() -> void:
	"""Find the local player node"""
	if not world:
		return

	# In practice mode (no multiplayer), the player is always named "1"
	# In multiplayer mode, use the peer ID
	var peer_id: int = 1  # Default to player 1 for practice mode

	# Check if we're in multiplayer mode
	if multiplayer.has_multiplayer_peer():
		peer_id = multiplayer.get_unique_id()

	player = world.get_node_or_null(str(peer_id))

	if not player:
		# Retry in a moment if player not spawned yet
		await get_tree().create_timer(0.5).timeout
		find_local_player()

func _process(_delta: float) -> void:
	update_hud()

func update_hud() -> void:
	"""Update all HUD elements"""
	# Update timer
	if world and world.has_method("get_time_remaining_formatted"):
		if world.game_active:
			timer_label.text = "Time: " + world.get_time_remaining_formatted()
		else:
			timer_label.text = "Time: --:--"
	else:
		timer_label.text = "Time: --:--"

	# Update score
	if world and world.has_method("get_score"):
		# Use player 1 for practice mode, or multiplayer peer ID for multiplayer
		var peer_id: int = 1
		if multiplayer.has_multiplayer_peer():
			peer_id = multiplayer.get_unique_id()
		var score: int = world.get_score(peer_id)
		score_label.text = "Kills: %d" % score
	else:
		score_label.text = "Kills: 0"

	# Update level
	if player and "level" in player:
		level_label.text = "Level: %d/%d" % [player.level, player.MAX_LEVEL]
	else:
		level_label.text = "Level: 0/3"

	# Update ability
	if player and "current_ability" in player and player.current_ability:
		if "ability_name" in player.current_ability:
			var ability_ready_text: String = ""
			if player.current_ability.has_method("is_ready"):
				if player.current_ability.is_ready():
					ability_ready_text = " [READY]"
				else:
					var cooldown: float = player.current_ability.cooldown_timer if "cooldown_timer" in player.current_ability else 0.0
					ability_ready_text = " [%.1fs]" % cooldown
			ability_label.text = "Ability: %s%s" % [player.current_ability.ability_name, ability_ready_text]
		else:
			ability_label.text = "Ability: Unknown"
	else:
		ability_label.text = "Ability: None (Press E to use)"

	# Update health
	if player and "health" in player:
		health_label.text = "Health: %d" % player.health
	else:
		health_label.text = "Health: 3"
