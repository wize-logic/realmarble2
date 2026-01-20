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

# Kill notification
var kill_notification_label: Label = null
var kill_notification_timer: float = 0.0
var kill_notification_duration: float = 2.0

# Killstreak notification
var killstreak_notification_label: Label = null
var killstreak_notification_timer: float = 0.0
var killstreak_notification_duration: float = 3.0

func _ready() -> void:
	# Find world and player references
	world = get_tree().root.get_node_or_null("World")

	# Create expansion notification label
	create_expansion_notification()

	# Create kill notification label
	create_kill_notification()

	# Create killstreak notification label
	create_killstreak_notification()

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
	update_kill_notification(delta)
	update_killstreak_notification(delta)

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

func create_kill_notification() -> void:
	"""Create the kill notification label"""
	kill_notification_label = Label.new()
	kill_notification_label.name = "KillNotification"
	kill_notification_label.text = ""
	kill_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kill_notification_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	# Position at center of screen
	kill_notification_label.set_anchors_preset(Control.PRESET_CENTER)
	kill_notification_label.anchor_left = 0.3
	kill_notification_label.anchor_right = 0.7
	kill_notification_label.anchor_top = 0.4
	kill_notification_label.anchor_bottom = 0.45
	kill_notification_label.offset_left = 0
	kill_notification_label.offset_right = 0
	kill_notification_label.offset_top = 0
	kill_notification_label.offset_bottom = 0

	# Style the label - medium size, red color
	kill_notification_label.add_theme_font_size_override("font_size", 36)
	kill_notification_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))  # Red color
	kill_notification_label.add_theme_color_override("font_outline_color", Color.BLACK)
	kill_notification_label.add_theme_constant_override("outline_size", 4)

	# Start hidden
	kill_notification_label.visible = false
	add_child(kill_notification_label)
	print("Kill notification added to game HUD")

func update_kill_notification(delta: float) -> void:
	"""Update the kill notification timer"""
	if not kill_notification_label or not kill_notification_label.visible:
		return

	kill_notification_timer -= delta

	# Fade out effect
	if kill_notification_timer <= 0.5:
		var alpha: float = kill_notification_timer / 0.5
		var color = kill_notification_label.get_theme_color("font_color", "Label")
		color.a = alpha
		kill_notification_label.add_theme_color_override("font_color", color)

	# Hide after duration
	if kill_notification_timer <= 0:
		kill_notification_label.visible = false
		# Reset color alpha
		var color = kill_notification_label.get_theme_color("font_color", "Label")
		color.a = 1.0
		kill_notification_label.add_theme_color_override("font_color", color)

func show_kill_notification(victim_name: String) -> void:
	"""Show the kill notification with skull symbol and victim name"""
	if not kill_notification_label:
		return

	# Use skull emoji (💀) or symbol
	kill_notification_label.text = "💀 " + victim_name
	kill_notification_label.visible = true
	kill_notification_timer = kill_notification_duration
	print("Showing kill notification: ", victim_name)

func create_killstreak_notification() -> void:
	"""Create the killstreak notification label"""
	killstreak_notification_label = Label.new()
	killstreak_notification_label.name = "KillstreakNotification"
	killstreak_notification_label.text = ""
	killstreak_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	killstreak_notification_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	# Position at top center of screen (below expansion notification)
	killstreak_notification_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	killstreak_notification_label.anchor_top = 0.25
	killstreak_notification_label.anchor_bottom = 0.30
	killstreak_notification_label.offset_top = 0
	killstreak_notification_label.offset_bottom = 0

	# Style the label - large, bold, golden color
	killstreak_notification_label.add_theme_font_size_override("font_size", 56)
	killstreak_notification_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0, 1.0))  # Gold color
	killstreak_notification_label.add_theme_color_override("font_outline_color", Color.BLACK)
	killstreak_notification_label.add_theme_constant_override("outline_size", 8)

	# Start hidden
	killstreak_notification_label.visible = false
	add_child(killstreak_notification_label)
	print("Killstreak notification added to game HUD")

func update_killstreak_notification(delta: float) -> void:
	"""Update the killstreak notification with pulse effect"""
	if not killstreak_notification_label or not killstreak_notification_label.visible:
		return

	killstreak_notification_timer -= delta

	# Pulse effect - oscillate scale
	var pulse_frequency: float = 3.0
	var scale_factor: float = 1.0 + 0.1 * sin(killstreak_notification_timer * pulse_frequency * TAU)
	killstreak_notification_label.scale = Vector2(scale_factor, scale_factor)

	# Fade out effect in last second
	if killstreak_notification_timer <= 1.0:
		var alpha: float = killstreak_notification_timer / 1.0
		var color = killstreak_notification_label.get_theme_color("font_color", "Label")
		color.a = alpha
		killstreak_notification_label.add_theme_color_override("font_color", color)

	# Hide after duration
	if killstreak_notification_timer <= 0:
		killstreak_notification_label.visible = false
		killstreak_notification_label.scale = Vector2.ONE
		# Reset color alpha
		var color = killstreak_notification_label.get_theme_color("font_color", "Label")
		color.a = 1.0
		killstreak_notification_label.add_theme_color_override("font_color", color)

func show_killstreak_notification(streak: int) -> void:
	"""Show the killstreak notification for milestones"""
	if not killstreak_notification_label:
		return

	var message: String = ""
	if streak == 5:
		message = "KILLING SPREE!"
	elif streak == 10:
		message = "UNSTOPPABLE!"
	else:
		message = "KILLSTREAK: %d" % streak

	killstreak_notification_label.text = message
	killstreak_notification_label.visible = true
	killstreak_notification_timer = killstreak_notification_duration
	print("Showing killstreak notification: ", message)
