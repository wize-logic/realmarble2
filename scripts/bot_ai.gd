extends Node

## Minimal Bot AI - Simple and debuggable

var bot: Node = null
var state: String = "WANDER"  # WANDER, CHASE, ATTACK, COLLECT
var target_player: Node = null
var target_collectible: Node = null  # For abilities/orbs
var wander_target: Vector3 = Vector3.ZERO
var action_timer: float = 0.0

# Stuck detection
var last_position: Vector3 = Vector3.ZERO
var stuck_timer: float = 0.0
var stuck_recovery_stage: int = 0  # 0 = not stuck, 1 = spin dash, 2 = jump, 3 = respawn

# Constants
const AGGRO_RANGE: float = 40.0
const ATTACK_RANGE: float = 15.0

# Ability hitbox ranges (max reach for each ability)
const ABILITY_RANGES: Dictionary = {
	"Sword": 4.2,        # Max sword range at full charge
	"Explosion": 10.0,   # Max explosion radius at full charge
	"Dash Attack": 18.0, # Dash travel + hitbox
	"Cannon": 50.0       # Long range projectile
}

func _ready() -> void:
	bot = get_parent()
	if not bot:
		print("ERROR: BotAI has no parent bot")
		return

	print("BotAI ready for: ", bot.name)
	wander_target = bot.global_position
	last_position = bot.global_position

func _physics_process(delta: float) -> void:
	if not bot or not is_instance_valid(bot):
		return

	# Update timers
	if action_timer > 0.0:
		action_timer -= delta

	# Check if stuck
	check_if_stuck(delta)

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

	# ALWAYS face player before attacking
	look_at_target(target_player.global_position)

	# Only attack if: ability ready, within hitbox range, and aimed at target
	if bot.current_ability.is_ready() and action_timer <= 0.0:
		# Check if target is within ability range
		if is_target_in_ability_range(distance):
			# Check if we're aimed at target
			if is_aimed_at_target(target_player.global_position):
				bot.current_ability.use()
				action_timer = 0.5  # Cooldown between actions
			else:
				# Not aimed yet, keep rotating
				pass
		else:
			# Out of range, chase closer
			state = "CHASE"

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

func is_target_in_ability_range(distance_to_target: float) -> bool:
	## Check if target is within the ability's maximum hitbox range
	if not bot.current_ability:
		return false

	var ability_name: String = bot.current_ability.ability_name if "ability_name" in bot.current_ability else ""

	# Get max range for this ability
	var max_range: float = ABILITY_RANGES.get(ability_name, 15.0)

	return distance_to_target <= max_range

func is_aimed_at_target(target_pos: Vector3) -> bool:
	## Check if bot is aimed at target within acceptable angle
	if not bot:
		return false

	# Get bot's forward direction
	var forward: Vector3 = Vector3(-sin(bot.rotation.y), 0, -cos(bot.rotation.y))

	# Get direction to target
	var to_target: Vector3 = (target_pos - bot.global_position).normalized()
	to_target.y = 0

	# Calculate angle between forward and target
	var dot: float = forward.dot(to_target)
	var angle_deg: float = rad_to_deg(acos(clamp(dot, -1.0, 1.0)))

	# Allow 30 degree cone (generous for simple aiming)
	return angle_deg <= 30.0

func check_if_stuck(delta: float) -> void:
	## Detect if bot is stuck and attempt recovery
	if not bot:
		return

	var current_pos: Vector3 = bot.global_position
	var distance_moved: float = current_pos.distance_to(last_position)

	# If bot hasn't moved much (less than 0.2 units per frame)
	if distance_moved < 0.2:
		stuck_timer += delta

		# After 5 seconds, start recovery
		if stuck_timer >= 5.0:
			print("Bot %s stuck for %.1f seconds - starting recovery stage %d" % [bot.name, stuck_timer, stuck_recovery_stage])
			attempt_unstuck_recovery()
	else:
		# Bot is moving, reset stuck detection
		stuck_timer = 0.0
		stuck_recovery_stage = 0

	# ALWAYS update last_position to track movement frame-by-frame
	last_position = current_pos

func attempt_unstuck_recovery() -> void:
	## Try to get unstuck using 3-stage recovery
	if not bot:
		return

	match stuck_recovery_stage:
		0:
			# Stage 1: Fire 70% spin dash
			print("Bot %s attempting spin dash escape" % bot.name)
			if not bot.is_charging_spin and bot.spin_cooldown <= 0.0:
				bot.is_charging_spin = true
				bot.spin_charge = bot.max_spin_charge * 0.7
				# Release after short delay
				get_tree().create_timer(0.3).timeout.connect(func():
					if bot and bot.is_charging_spin:
						bot.is_charging_spin = false
				)
			stuck_recovery_stage = 1
			stuck_timer = 0.0  # Reset timer to give spin dash time to work

		1:
			# Stage 2: Jump forward aggressively
			print("Bot %s attempting jump escape" % bot.name)
			if bot.jump_count < bot.max_jumps:
				# Jump
				bot.linear_velocity.y = bot.current_jump_impulse
				bot.jump_count += 1
				# Apply forward force
				var forward: Vector3 = Vector3(-sin(bot.rotation.y), 0, -cos(bot.rotation.y))
				bot.apply_central_impulse(forward * bot.current_roll_force * 2.0)
			stuck_recovery_stage = 2
			stuck_timer = 0.0  # Reset timer to give jump time to work

		2:
			# Stage 3: Respawn
			print("Bot %s failed to escape - respawning" % bot.name)
			respawn_bot()
			stuck_recovery_stage = 0
			stuck_timer = 0.0

func respawn_bot() -> void:
	## Teleport bot to a random spawn position
	if not bot:
		return

	# Find all spawn points
	var spawn_points: Array = get_tree().get_nodes_in_group("spawn_points")

	if spawn_points.size() > 0:
		# Pick random spawn point
		var spawn: Node = spawn_points[randi() % spawn_points.size()]
		bot.global_position = spawn.global_position
		bot.linear_velocity = Vector3.ZERO
		bot.angular_velocity = Vector3.ZERO
		print("Bot %s respawned at %s" % [bot.name, spawn.name])
	else:
		# No spawn points, just move up
		bot.global_position = Vector3(bot.global_position.x, bot.global_position.y + 10.0, bot.global_position.z)
		bot.linear_velocity = Vector3.ZERO
		bot.angular_velocity = Vector3.ZERO
		print("Bot %s respawned at elevated position" % bot.name)
