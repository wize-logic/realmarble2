extends Control

## Scoreboard
## Shows player stats (K/D ratios) when holding Tab key

@onready var player_list: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/PlayerList

var is_showing: bool = false

func _ready() -> void:
	visible = false
	is_showing = false

func _input(event: InputEvent) -> void:
	# Show scoreboard while Tab is held down
	if event is InputEventKey and event.keycode == KEY_TAB:
		if event.pressed and not event.echo:
			show_scoreboard()
		elif not event.pressed:
			hide_scoreboard()

func show_scoreboard() -> void:
	"""Show the scoreboard with current stats"""
	if is_showing:
		return

	is_showing = true
	visible = true

	# Update the scoreboard content
	update_scoreboard()

func hide_scoreboard() -> void:
	"""Hide the scoreboard"""
	is_showing = false
	visible = false

func update_scoreboard() -> void:
	"""Update scoreboard with current player stats"""
	# Clear existing entries
	for child in player_list.get_children():
		child.queue_free()

	# Get world reference
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if not world:
		return

	# Get all players
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	if players.size() == 0:
		return

	# Create a list of player stats
	var player_stats: Array = []
	for player in players:
		var player_id: int = player.name.to_int()
		var kills: int = world.get_score(player_id) if world.has_method("get_score") else 0
		var deaths: int = world.get_deaths(player_id) if world.has_method("get_deaths") else 0
		var kd_ratio: float = world.get_kd_ratio(player_id) if world.has_method("get_kd_ratio") else 0.0

		var player_name: String = get_player_name(player_id)

		player_stats.append({
			"id": player_id,
			"name": player_name,
			"kills": kills,
			"deaths": deaths,
			"kd_ratio": kd_ratio
		})

	# Sort by kills (descending)
	player_stats.sort_custom(func(a, b): return a["kills"] > b["kills"])

	# Create UI elements for each player
	for stats in player_stats:
		var row: HBoxContainer = HBoxContainer.new()

		# Player name
		var name_label: Label = Label.new()
		name_label.custom_minimum_size = Vector2(200, 0)
		name_label.text = stats["name"]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(name_label)

		# Kills
		var kills_label: Label = Label.new()
		kills_label.custom_minimum_size = Vector2(80, 0)
		kills_label.text = str(stats["kills"])
		kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(kills_label)

		# Deaths
		var deaths_label: Label = Label.new()
		deaths_label.custom_minimum_size = Vector2(80, 0)
		deaths_label.text = str(stats["deaths"])
		deaths_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(deaths_label)

		# K/D Ratio
		var kd_label: Label = Label.new()
		kd_label.custom_minimum_size = Vector2(120, 0)
		kd_label.text = "%.2f" % stats["kd_ratio"]
		kd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(kd_label)

		player_list.add_child(row)

func get_player_name(player_id: int) -> String:
	"""Get a display name for a player"""
	if player_id >= 9000:
		# Bot
		return "Bot %d" % (player_id - 9000)
	elif player_id == 1:
		# Local player
		return "You (Player 1)"
	else:
		# Other players
		return "Player %d" % player_id
