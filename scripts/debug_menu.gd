extends Control

## Debug Menu
## Provides debugging tools and cheats

@onready var panel: PanelContainer = $Panel
@onready var spawn_bot_button: Button = $Panel/VBoxContainer/SpawnBotButton
@onready var god_mode_button: Button = $Panel/VBoxContainer/GodModeButton
@onready var max_level_button: Button = $Panel/VBoxContainer/MaxLevelButton
@onready var teleport_button: Button = $Panel/VBoxContainer/TeleportButton
@onready var clear_abilities_button: Button = $Panel/VBoxContainer/ClearAbilitiesButton
@onready var spawn_ability_button: Button = $Panel/VBoxContainer/SpawnAbilityButton
@onready var kill_player_button: Button = $Panel/VBoxContainer/KillPlayerButton
@onready var add_score_button: Button = $Panel/VBoxContainer/AddScoreButton
@onready var reset_timer_button: Button = $Panel/VBoxContainer/ResetTimerButton
@onready var collision_shapes_button: Button = $Panel/VBoxContainer/CollisionShapesButton
@onready var regenerate_level_button: Button = $Panel/VBoxContainer/RegenerateLevelButton
@onready var change_skybox_button: Button = $Panel/VBoxContainer/ChangeSkyboxButton
@onready var speed_mult_slider: HSlider = $Panel/VBoxContainer/SpeedMultiplier/Slider
@onready var speed_label: Label = $Panel/VBoxContainer/SpeedMultiplier/Label

var is_visible: bool = false
var god_mode_enabled: bool = false
var collision_shapes_visible: bool = false
var speed_multiplier: float = 1.0

func _ready() -> void:
	visible = false
	panel.visible = false

	# Connect signals
	if spawn_bot_button:
		spawn_bot_button.pressed.connect(_on_spawn_bot_pressed)
	if god_mode_button:
		god_mode_button.pressed.connect(_on_god_mode_pressed)
	if max_level_button:
		max_level_button.pressed.connect(_on_max_level_pressed)
	if teleport_button:
		teleport_button.pressed.connect(_on_teleport_pressed)
	if clear_abilities_button:
		clear_abilities_button.pressed.connect(_on_clear_abilities_pressed)
	if spawn_ability_button:
		spawn_ability_button.pressed.connect(_on_spawn_ability_pressed)
	if kill_player_button:
		kill_player_button.pressed.connect(_on_kill_player_pressed)
	if add_score_button:
		add_score_button.pressed.connect(_on_add_score_pressed)
	if reset_timer_button:
		reset_timer_button.pressed.connect(_on_reset_timer_pressed)
	if collision_shapes_button:
		collision_shapes_button.pressed.connect(_on_collision_shapes_pressed)
	if regenerate_level_button:
		regenerate_level_button.pressed.connect(_on_regenerate_level_pressed)
	if change_skybox_button:
		change_skybox_button.pressed.connect(_on_change_skybox_pressed)
	if speed_mult_slider:
		speed_mult_slider.value_changed.connect(_on_speed_changed)
		speed_mult_slider.value = 1.0

func _input(event: InputEvent) -> void:
	# Toggle debug menu with F3
	if event is InputEventKey and event.keycode == KEY_F3 and event.pressed and not event.echo:
		toggle_menu()

func toggle_menu() -> void:
	"""Toggle debug menu visibility"""
	is_visible = !is_visible
	visible = is_visible
	panel.visible = is_visible

	# Only change mouse mode during active gameplay
	var world: Node = get_tree().get_root().get_node_or_null("World")
	var in_gameplay: bool = world and world.get("game_active")

	if in_gameplay:
		if is_visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_spawn_bot_pressed() -> void:
	"""Spawn a bot player"""
	print("Spawning bot...")
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if world and world.has_method("spawn_bot"):
		world.spawn_bot()
	else:
		print("Error: Could not spawn bot - World node not found or missing spawn_bot method")

func _on_god_mode_pressed() -> void:
	"""Toggle god mode for local player"""
	god_mode_enabled = !god_mode_enabled

	var player: Node = get_local_player()
	if player:
		if god_mode_enabled:
			player.set("god_mode", true)
			god_mode_button.text = "God Mode: ON"
			print("God mode enabled")
		else:
			player.set("god_mode", false)
			god_mode_button.text = "God Mode: OFF"
			print("God mode disabled")

func _on_max_level_pressed() -> void:
	"""Set player to max level"""
	var player: Node = get_local_player()
	if player and player.has_method("collect_orb"):
		while player.level < player.MAX_LEVEL:
			player.collect_orb()
		print("Set player to max level")

func _on_teleport_pressed() -> void:
	"""Teleport player to random spawn"""
	var player: Node = get_local_player()
	if player:
		var spawn_pos: Vector3 = player.spawns[randi() % player.spawns.size()]
		player.global_position = spawn_pos
		player.linear_velocity = Vector3.ZERO
		print("Teleported to: ", spawn_pos)

func _on_clear_abilities_pressed() -> void:
	"""Remove all abilities from map"""
	var pickups: Array[Node] = get_tree().get_nodes_in_group("ability_pickups")
	for pickup in pickups:
		pickup.queue_free()
	print("Cleared all ability pickups")

func _on_speed_changed(value: float) -> void:
	"""Change game speed multiplier"""
	speed_multiplier = value
	Engine.time_scale = value
	if speed_label:
		speed_label.text = "Speed: %.1fx" % value
	print("Game speed set to: %.1fx" % value)

func _on_spawn_ability_pressed() -> void:
	"""Spawn a random ability pickup at player location"""
	var player: Node = get_local_player()
	if not player:
		print("Error: No local player found")
		return

	var world: Node = get_tree().get_root().get_node_or_null("World")
	if not world:
		print("Error: World node not found")
		return

	var ability_spawner: Node = world.get_node_or_null("AbilitySpawner")
	if not ability_spawner or not ability_spawner.has_method("spawn_random_ability"):
		print("Error: AbilitySpawner not found")
		return

	# Spawn at player position with slight offset
	var spawn_pos: Vector3 = player.global_position + Vector3(randf_range(-2, 2), 2, randf_range(-2, 2))
	ability_spawner.spawn_random_ability(spawn_pos)
	print("Spawned random ability at: ", spawn_pos)

func _on_kill_player_pressed() -> void:
	"""Kill and respawn the local player"""
	var player: Node = get_local_player()
	if player and player.has_method("respawn"):
		player.respawn()
		print("Player killed - respawning...")

func _on_add_score_pressed() -> void:
	"""Add score to local player"""
	var player: Node = get_local_player()
	if player:
		var player_id: int = player.name.to_int()
		var world: Node = get_tree().get_root().get_node_or_null("World")
		if world and world.has_method("add_score"):
			world.add_score(player_id, 5)
			print("Added 5 score to player")

func _on_reset_timer_pressed() -> void:
	"""Reset the match timer"""
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if world:
		world.game_time_remaining = 300.0
		print("Match timer reset to 5 minutes")

func _on_collision_shapes_pressed() -> void:
	"""Toggle collision shape visualization"""
	collision_shapes_visible = !collision_shapes_visible

	# Use the setter method instead of direct assignment
	var tree: SceneTree = get_tree()
	tree.set_debug_collisions_hint(collision_shapes_visible)

	if collision_shapes_visible:
		collision_shapes_button.text = "Show Collision: ON"
		print("Collision shapes visible")
	else:
		collision_shapes_button.text = "Show Collision: OFF"
		print("Collision shapes hidden")

func _on_regenerate_level_pressed() -> void:
	"""Regenerate the procedural level"""
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if world and world.has_method("generate_procedural_level"):
		print("Regenerating level...")
		world.generate_procedural_level()

func _on_change_skybox_pressed() -> void:
	"""Change skybox color palette"""
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if world and "skybox_generator" in world:
		var skybox: Node = world.skybox_generator
		if skybox and skybox.has_method("randomize_colors"):
			skybox.randomize_colors()
			print("Skybox colors randomized!")

func get_local_player() -> Node:
	"""Get the local player"""
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.is_multiplayer_authority():
			return player
	return null
