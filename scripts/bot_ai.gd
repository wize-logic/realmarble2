extends Node

## Bot AI Controller
## Provides AI behavior for bot players

@export var target_player: Node = null
@export var wander_radius: float = 40.0
@export var aggro_range: float = 50.0
@export var attack_range: float = 12.0

var bot: Node = null
var state: String = "WANDER"  # WANDER, CHASE, ATTACK, COLLECT_ABILITY, COLLECT_ORB
var wander_target: Vector3 = Vector3.ZERO
var wander_timer: float = 0.0
var action_timer: float = 0.0
var target_ability: Node = null
var target_orb: Node = null
var ability_check_timer: float = 0.0
var orb_check_timer: float = 0.0

func _ready() -> void:
	bot = get_parent()
	wander_target = bot.global_position
	call_deferred("find_target")

func _physics_process(delta: float) -> void:
	if not bot:
		return

	# Freeze bots during countdown (same as player freeze)
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if world and world.get("countdown_active"):
		return  # Don't process AI during countdown

	# Update timers
	wander_timer -= delta
	action_timer -= delta
	ability_check_timer -= delta
	orb_check_timer -= delta

	# Find nearest player
	if not target_player or not is_instance_valid(target_player):
		find_target()

	# Check for abilities periodically
	if ability_check_timer <= 0.0:
		find_nearest_ability()
		ability_check_timer = 1.0  # Check every second

	# Check for orbs periodically
	if orb_check_timer <= 0.0:
		find_nearest_orb()
		orb_check_timer = 0.8  # Check slightly more often

	# State machine
	match state:
		"WANDER":
			do_wander(delta)
		"CHASE":
			do_chase(delta)
		"ATTACK":
			do_attack(delta)
		"COLLECT_ABILITY":
			do_collect_ability(delta)
		"COLLECT_ORB":
			do_collect_orb(delta)

	# Check state transitions
	update_state()

func update_state() -> void:
	"""Update AI state based on conditions"""
	# Priority 1: Collect orbs if not max level and one is nearby
	if bot.level < bot.MAX_LEVEL and target_orb and is_instance_valid(target_orb):
		var distance_to_orb: float = bot.global_position.distance_to(target_orb.global_position)
		if distance_to_orb < 25.0:  # Prioritize nearby orbs
			state = "COLLECT_ORB"
			return

	# Priority 2: Collect abilities if we don't have one and one is nearby
	if not bot.current_ability and target_ability and is_instance_valid(target_ability):
		var distance_to_ability: float = bot.global_position.distance_to(target_ability.global_position)
		if distance_to_ability < 30.0:  # Abilities are important, go for them from medium range
			state = "COLLECT_ABILITY"
			return

	# Priority 3: Combat if player is nearby
	if not target_player or not is_instance_valid(target_player):
		state = "WANDER"
		return

	var distance_to_target: float = bot.global_position.distance_to(target_player.global_position)

	if distance_to_target < attack_range:
		state = "ATTACK"
	elif distance_to_target < aggro_range:
		state = "CHASE"
	else:
		# Priority 4: Collect items while wandering
		if bot.level < bot.MAX_LEVEL and target_orb and is_instance_valid(target_orb):
			state = "COLLECT_ORB"
		elif not bot.current_ability and target_ability and is_instance_valid(target_ability):
			state = "COLLECT_ABILITY"
		else:
			state = "WANDER"

func do_wander(delta: float) -> void:
	"""Wander around randomly"""
	# Pick new wander target periodically
	if wander_timer <= 0.0:
		var angle: float = randf() * TAU
		var distance: float = randf() * wander_radius
		wander_target = bot.global_position + Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		wander_timer = randf_range(2.0, 5.0)

	# Move towards wander target
	move_towards(wander_target, delta, 0.3)  # Slow wander speed

	# Occasionally jump
	if action_timer <= 0.0 and randf() < 0.1:
		bot_jump()
		action_timer = randf_range(1.0, 3.0)

func do_chase(delta: float) -> void:
	"""Chase the target player"""
	if not target_player:
		return

	# Move towards target
	move_towards(target_player.global_position, delta, 0.8)  # Fast chase speed

	# Jump if target is higher or randomly
	if action_timer <= 0.0:
		if target_player.global_position.y > bot.global_position.y + 1.0 or randf() < 0.2:
			bot_jump()
		action_timer = randf_range(0.5, 1.5)

func do_attack(delta: float) -> void:
	"""Attack the target player"""
	if not target_player:
		return

	# Move towards target
	move_towards(target_player.global_position, delta, 0.6)

	# Use ability if available
	if action_timer <= 0.0:
		if bot.current_ability and bot.current_ability.has_method("use"):
			if bot.current_ability.is_ready():
				bot.current_ability.use()
				action_timer = randf_range(1.5, 3.0)
		# Try spin dash - but much less often
		elif randf() < 0.1 and bot.spin_cooldown <= 0.0 and not bot.is_spin_dashing and not bot.is_charging_spin:
			# Charge and release spin dash (simplified)
			bot.is_charging_spin = true
			bot.spin_charge = randf_range(0.5, bot.max_spin_charge)
			get_tree().create_timer(0.3).timeout.connect(func(): release_spin_dash())
			action_timer = randf_range(2.0, 4.0)

func move_towards(target_pos: Vector3, delta: float, speed_mult: float = 1.0) -> void:
	"""Move the bot towards a target position"""
	if not bot:
		return

	var direction: Vector3 = (target_pos - bot.global_position).normalized()
	direction.y = 0  # Keep horizontal

	if direction.length() > 0.1:
		# Simulate input by applying force
		var force: float = bot.current_roll_force * speed_mult
		bot.apply_central_force(direction * force)

func bot_jump() -> void:
	"""Make the bot jump"""
	if not bot:
		return

	if bot.jump_count < bot.max_jumps:
		var jump_strength: float = bot.current_jump_impulse
		if bot.jump_count == 1:
			jump_strength *= 0.85

		var vel: Vector3 = bot.linear_velocity
		vel.y = 0
		bot.linear_velocity = vel
		bot.apply_central_impulse(Vector3.UP * jump_strength)
		bot.jump_count += 1

func release_spin_dash() -> void:
	"""Release spin dash"""
	if bot and bot.is_charging_spin:
		bot.is_charging_spin = false
		if bot.has_method("execute_spin_dash"):
			bot.execute_spin_dash()

func find_target() -> void:
	"""Find the nearest player to target"""
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	var closest_player: Node = null
	var closest_distance: float = INF

	for player in players:
		if player == bot:  # Don't target self
			continue
		if not is_instance_valid(player):
			continue

		var distance: float = bot.global_position.distance_to(player.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_player = player

	target_player = closest_player

func find_nearest_ability() -> void:
	"""Find the nearest ability pickup"""
	var abilities: Array[Node] = get_tree().get_nodes_in_group("ability_pickups")
	var closest_ability: Node = null
	var closest_distance: float = INF

	for ability in abilities:
		if not is_instance_valid(ability):
			continue

		var distance: float = bot.global_position.distance_to(ability.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_ability = ability

	target_ability = closest_ability

func do_collect_ability(delta: float) -> void:
	"""Move towards and collect an ability"""
	if not target_ability or not is_instance_valid(target_ability):
		target_ability = null
		state = "WANDER"
		return

	# Move towards ability
	move_towards(target_ability.global_position, delta, 1.0)  # Full speed to ability

	# Jump if ability is higher
	if action_timer <= 0.0:
		if target_ability.global_position.y > bot.global_position.y + 1.0:
			bot_jump()
			action_timer = randf_range(0.5, 1.0)

	# Check if we're close enough (pickup will happen automatically via Area3D)
	var distance: float = bot.global_position.distance_to(target_ability.global_position)
	if distance < 2.0:
		# Close enough, should collect automatically
		# Wait a moment then look for new targets
		await get_tree().create_timer(0.5).timeout
		target_ability = null

func find_nearest_orb() -> void:
	"""Find the nearest collectible orb"""
	var orbs: Array[Node] = get_tree().get_nodes_in_group("orbs")
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

	target_orb = closest_orb

func do_collect_orb(delta: float) -> void:
	"""Move towards and collect an orb"""
	if not target_orb or not is_instance_valid(target_orb):
		target_orb = null
		state = "WANDER"
		return

	# Check if orb was collected by someone else
	if "is_collected" in target_orb and target_orb.is_collected:
		target_orb = null
		state = "WANDER"
		return

	# Move towards orb
	move_towards(target_orb.global_position, delta, 1.0)  # Full speed to orb

	# Jump if orb is higher
	if action_timer <= 0.0:
		if target_orb.global_position.y > bot.global_position.y + 1.0:
			bot_jump()
			action_timer = randf_range(0.5, 1.0)

	# Check if we're close enough (pickup will happen automatically via Area3D)
	var distance: float = bot.global_position.distance_to(target_orb.global_position)
	if distance < 2.0:
		# Close enough, should collect automatically
		# Wait a moment then look for new targets
		await get_tree().create_timer(0.3).timeout
		target_orb = null
