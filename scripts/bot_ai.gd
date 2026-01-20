extends Node

## Minimal Bot AI - Simple and debuggable

var bot: Node = null
var state: String = "WANDER"  # WANDER, CHASE, ATTACK, COLLECT
var target_player: Node = null
var target_collectible: Node = null  # For abilities/orbs
var wander_target: Vector3 = Vector3.ZERO
var action_timer: float = 0.0

# Constants
const AGGRO_RANGE: float = 40.0
const ATTACK_RANGE: float = 15.0

func _ready() -> void:
	bot = get_parent()
	if not bot:
		print("ERROR: BotAI has no parent bot")
		return

	print("BotAI ready for: ", bot.name)
	wander_target = bot.global_position

func _physics_process(delta: float) -> void:
	if not bot or not is_instance_valid(bot):
		return

	# Update timers
	if action_timer > 0.0:
		action_timer -= delta

	# Update state
	update_state()

	# Execute state behavior
	match state:
		"WANDER":
			do_wander(delta)
		"CHASE":
			do_chase(delta)
		"ATTACK":
			do_attack(delta)
		"COLLECT":
			do_collect(delta)

func update_state() -> void:
	## Update state based on priorities

	# Priority 1: Get an ability if we don't have one
	if not bot.current_ability:
		find_collectible()
		if target_collectible and is_instance_valid(target_collectible):
			state = "COLLECT"
			return

	# Priority 2: Find players to attack if we have an ability
	if bot.current_ability:
		find_nearest_player()
		if target_player and is_instance_valid(target_player):
			var distance: float = bot.global_position.distance_to(target_player.global_position)

			if distance < ATTACK_RANGE:
				state = "ATTACK"
				return
			elif distance < AGGRO_RANGE:
				state = "CHASE"
				return

	# Default: Wander
	state = "WANDER"

func do_wander(delta: float) -> void:
	## Wander randomly around the map

	# Pick new wander target occasionally
	var distance_to_wander: float = bot.global_position.distance_to(wander_target)
	if distance_to_wander < 3.0:
		# Reached target, pick new one
		var random_angle: float = randf() * TAU
		var random_distance: float = randf_range(10.0, 30.0)
		wander_target = bot.global_position + Vector3(
			cos(random_angle) * random_distance,
			0,
			sin(random_angle) * random_distance
		)

	# Move toward wander target
	move_toward_position(wander_target, delta)

func do_chase(delta: float) -> void:
	## Chase target player
	if not target_player or not is_instance_valid(target_player):
		state = "WANDER"
		return

	# Move toward player
	move_toward_position(target_player.global_position, delta)

	# Face player
	look_at_target(target_player.global_position)

func do_attack(delta: float) -> void:
	## Attack target player
	if not target_player or not is_instance_valid(target_player):
		state = "WANDER"
		return

	if not bot.current_ability:
		state = "WANDER"
		return

	var distance: float = bot.global_position.distance_to(target_player.global_position)

	# If too far, go back to chase
	if distance > ATTACK_RANGE * 1.5:
		state = "CHASE"
		return

	# Face player
	look_at_target(target_player.global_position)

	# Use ability when ready
	if bot.current_ability.is_ready() and action_timer <= 0.0:
		bot.current_ability.use()
		action_timer = 0.5  # Cooldown between actions

func do_collect(delta: float) -> void:
	## Collect ability or orb
	if not target_collectible or not is_instance_valid(target_collectible):
		state = "WANDER"
		return

	# Move toward collectible
	move_toward_position(target_collectible.global_position, delta)

	# Check if close enough (auto-pickup)
	var distance: float = bot.global_position.distance_to(target_collectible.global_position)
	if distance < 2.0:
		target_collectible = null
		state = "WANDER"

func move_toward_position(target_pos: Vector3, delta: float) -> void:
	## Move bot toward a position
	if not bot:
		return

	var direction: Vector3 = (target_pos - bot.global_position).normalized()
	direction.y = 0  # Keep horizontal

	if direction.length() > 0.1:
		var force: float = bot.current_roll_force
		bot.apply_central_force(direction * force)

func look_at_target(target_pos: Vector3) -> void:
	## Rotate bot to face target
	if not bot:
		return

	var direction: Vector3 = target_pos - bot.global_position
	direction.y = 0

	if direction.length() > 0.1:
		var angle: float = atan2(direction.x, direction.z)
		bot.rotation.y = angle

func find_nearest_player() -> void:
	## Find closest player to target
	var players: Array = get_tree().get_nodes_in_group("players")
	var closest_player: Node = null
	var closest_distance: float = INF

	for player in players:
		if not is_instance_valid(player):
			continue
		if player == bot:
			continue  # Don't target self

		var distance: float = bot.global_position.distance_to(player.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_player = player

	target_player = closest_player

func find_collectible() -> void:
	## Find nearest ability or orb to collect

	# Prioritize abilities if we don't have one
	var abilities: Array = get_tree().get_nodes_in_group("ability_pickups")
	if abilities.size() > 0:
		var closest_ability: Node = null
		var closest_distance: float = INF

		for ability in abilities:
			if not is_instance_valid(ability):
				continue

			var distance: float = bot.global_position.distance_to(ability.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_ability = ability

		if closest_ability:
			target_collectible = closest_ability
			return

	# If no abilities, look for orbs if not max level
	if bot.level < bot.MAX_LEVEL:
		var orbs: Array = get_tree().get_nodes_in_group("orbs")
		var closest_orb: Node = null
		var closest_distance: float = INF

		for orb in orbs:
			if not is_instance_valid(orb):
				continue

			# Skip collected orbs
			if "is_collected" in orb and orb.is_collected:
				continue

			var distance: float = bot.global_position.distance_to(orb.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_orb = orb

		target_collectible = closest_orb
