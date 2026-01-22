extends Label3D
## Debug Nametag
## Shows player/bot name and status above their head

var target_player: Node = null
var update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.1  # Update 10 times per second

func _ready() -> void:
	# Configure label appearance
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	pixel_size = 0.01  # Much larger for visibility
	outline_size = 16  # Thicker outline
	outline_modulate = Color(0, 0, 0, 0.9)
	modulate = Color(1, 1, 1, 1)
	font_size = 32  # Larger font

	# Position higher above player head
	position = Vector3(0, 3.5, 0)

func setup(player: Node) -> void:
	"""Initialize nametag for a specific player"""
	target_player = player
	if target_player:
		update_nametag()

func _process(delta: float) -> void:
	if not target_player or not is_instance_valid(target_player):
		queue_free()
		return

	update_timer += delta
	if update_timer >= UPDATE_INTERVAL:
		update_timer = 0.0
		update_nametag()

func update_nametag() -> void:
	"""Update the nametag text with current info"""
	if not target_player:
		return

	var player_name: String = target_player.name
	var player_id: int = player_name.to_int()
	var is_bot: bool = player_id >= 9000

	# Base name
	var display_name: String = ""
	if is_bot:
		display_name = "Bot_%d" % (player_id - 9000)
	else:
		display_name = "Player"

	# Health
	var health_text: String = ""
	if "health" in target_player:
		health_text = " | HP: %d" % target_player.health

	# Ability
	var ability_text: String = ""
	if "current_ability" in target_player and target_player.current_ability:
		if "ability_name" in target_player.current_ability:
			ability_text = " | %s" % target_player.current_ability.ability_name
		else:
			ability_text = " | Ability"
	else:
		ability_text = " | No Ability"

	# Bot state (if available)
	var state_text: String = ""
	if is_bot:
		var bot_ai: Node = target_player.get_node_or_null("BotAI")
		if bot_ai and "state" in bot_ai:
			state_text = "\n[%s]" % bot_ai.state

	# Combine all info
	text = display_name + health_text + ability_text + state_text

	# Color code by type
	if is_bot:
		modulate = Color(1.0, 0.8, 0.2)  # Yellow for bots
	else:
		modulate = Color(0.2, 1.0, 0.4)  # Green for player
