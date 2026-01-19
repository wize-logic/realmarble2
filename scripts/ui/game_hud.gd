extends Control

## Game HUD for displaying timer, score, level, and ability info

@onready var timer_label: Label = $MarginContainer/VBoxContainer/TimerLabel
@onready var score_label: Label = $MarginContainer/VBoxContainer/ScoreLabel
@onready var level_label: Label = $MarginContainer/VBoxContainer/LevelLabel
@onready var ability_label: Label = $MarginContainer/VBoxContainer/AbilityLabel
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthLabel

var world: Node = null
var player: Node = null

# Expansion notification
var expansion_notification_label: Label = null
var expansion_flash_timer: float = 0.0
var expansion_flash_duration: float = 5.0
var is_expansion_flashing: bool = false

func _ready() -> void:
	# Find world and player references
	world = get_tree().root.get_node_or_null("World")

	# Create expansion notification label
	create_expansion_notification()

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

func reset_hud() -> void:
	"""Reset HUD and find local player again - call this when starting a new match"""
	print("[HUD] Resetting HUD for new match")
	player = null
	world = get_tree().root.get_node_or_null("World")
	call_deferred("find_local_player")

func _process(delta: float) -> void:
	update_hud()
	update_expansion_notification(delta)

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

func create_expansion_notification() -> void:
	"""Create the expansion notification label"""
	expansion_notification_label = Label.new()
	expansion_notification_label.name = "ExpansionNotification"
	expansion_notification_label.text = "NEW AREA AVAILABLE"
	expansion_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	expansion_notification_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	# Position at top center of screen
	expansion_notification_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	expansion_notification_label.anchor_top = 0.15
	expansion_notification_label.anchor_bottom = 0.15
	expansion_notification_label.offset_top = -30
	expansion_notification_label.offset_bottom = 30

	# Style the label - large, bold, attention-grabbing
	expansion_notification_label.add_theme_font_size_override("font_size", 48)
	expansion_notification_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0, 1.0))  # Gold color
	expansion_notification_label.add_theme_color_override("font_outline_color", Color.BLACK)
	expansion_notification_label.add_theme_constant_override("outline_size", 6)

	# Start hidden
	expansion_notification_label.visible = false
	add_child(expansion_notification_label)
	print("Expansion notification added to game HUD")

func update_expansion_notification(delta: float) -> void:
	"""Update the expansion notification flash effect"""
	if not is_expansion_flashing or not expansion_notification_label:
		return

	expansion_flash_timer -= delta

	# Flash effect - oscillate alpha
	var flash_frequency: float = 4.0  # Flashes per second
	var alpha: float = 0.5 + 0.5 * sin(expansion_flash_timer * flash_frequency * TAU)

	var color = expansion_notification_label.get_theme_color("font_color", "Label")
	color.a = alpha
	expansion_notification_label.add_theme_color_override("font_color", color)

	# Stop flashing after duration
	if expansion_flash_timer <= 0:
		stop_expansion_notification()

func show_expansion_notification() -> void:
	"""Show the expansion notification with flashing effect"""
	if not expansion_notification_label:
		return

	expansion_notification_label.visible = true
	is_expansion_flashing = true
	expansion_flash_timer = expansion_flash_duration
	print("Showing expansion notification in HUD: NEW AREA AVAILABLE")

func stop_expansion_notification() -> void:
	"""Stop the flashing effect and hide the notification"""
	if not expansion_notification_label:
		return

	is_expansion_flashing = false
	expansion_notification_label.visible = false
	print("Expansion notification hidden from HUD")
