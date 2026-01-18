extends Area3D

## Ability pickup that grants players a Kirby-style ability
## Randomly spawns after being collected

@export var ability_scene: PackedScene  # The ability to grant
@export var ability_name: String = "Unknown Ability"
@export var ability_color: Color = Color.WHITE

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var pickup_sound: AudioStreamPlayer3D = $PickupSound

# Visual properties
var base_height: float = 0.0
var bob_speed: float = 2.5
var bob_amount: float = 0.25
var rotation_speed: float = 3.0
var time: float = 0.0

# Respawn properties
var respawn_time: float = 20.0  # Respawn after 20 seconds
var is_collected: bool = false
var respawn_timer: float = 0.0

# Visual effects
var glow_material: StandardMaterial3D
var aura_light: OmniLight3D

func _ready() -> void:
	# Add to ability pickups group for bot AI
	add_to_group("ability_pickups")

	# Store initial height
	base_height = global_position.y

	# Set up collision detection
	body_entered.connect(_on_body_entered)

	# Set up visual appearance
	if mesh_instance and mesh_instance.mesh:
		# Create glowing material based on ability color
		glow_material = StandardMaterial3D.new()
		glow_material.albedo_color = ability_color
		glow_material.emission_enabled = true
		glow_material.emission = ability_color
		glow_material.emission_energy_multiplier = 1.0
		glow_material.metallic = 0.5
		glow_material.roughness = 0.1
		mesh_instance.material_override = glow_material

	# Randomize starting animation phase
	time = randf() * TAU

	# Set up aura light effect for better visibility
	if not aura_light:
		aura_light = OmniLight3D.new()
		aura_light.name = "AuraLight"
		add_child(aura_light)

		# Configure light properties using ability color
		aura_light.light_color = ability_color
		aura_light.light_energy = 1.0  # Moderate brightness
		aura_light.omni_range = 4.0  # Larger radius for pickups
		aura_light.omni_attenuation = 1.5  # Moderate falloff

		# Shadow settings - disable for performance
		aura_light.shadow_enabled = false

func _process(delta: float) -> void:
	if is_collected:
		# Check if game is active before respawning
		var world: Node = get_parent()
		if world and world.has_method("is_game_active") and world.is_game_active():
			# Handle respawn timer only during active gameplay
			respawn_timer -= delta
			if respawn_timer <= 0.0:
				respawn_pickup()
		return

	# Update animation time
	time += delta

	# Bob up and down
	var new_pos: Vector3 = global_position
	new_pos.y = base_height + sin(time * bob_speed) * bob_amount
	global_position = new_pos

	# Rotate
	if mesh_instance:
		mesh_instance.rotation.y += rotation_speed * delta
		mesh_instance.rotation.x = sin(time * 1.5) * 0.2  # Slight tilt

		# Pulse emission
		if glow_material:
			var pulse: float = 0.8 + sin(time * 4.0) * 0.4
			glow_material.emission_energy_multiplier = pulse

func _on_body_entered(body: Node3D) -> void:
	# Check if it's a player and not already collected
	if is_collected:
		return

	# Check if body is a player
	if body is RigidBody3D and body.has_method("pickup_ability"):
		collect(body)

func collect(player: Node) -> void:
	"""Handle ability pickup collection"""
	# Give player the ability
	if ability_scene:
		player.pickup_ability(ability_scene, ability_name)
	else:
		print("Warning: Ability pickup has no ability_scene assigned!")

	# Play pickup sound
	if pickup_sound and pickup_sound.stream:
		play_pickup_sound.rpc()

	# Mark as collected
	is_collected = true
	respawn_timer = respawn_time

	# Hide the pickup
	if mesh_instance:
		mesh_instance.visible = false
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if aura_light:
		aura_light.visible = false

	print("Ability '%s' collected by player! Respawning in %.1f seconds" % [ability_name, respawn_time])

func respawn_pickup() -> void:
	"""Respawn the ability pickup"""
	is_collected = false

	# Show the pickup again
	if mesh_instance:
		mesh_instance.visible = true
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	if aura_light:
		aura_light.visible = true

	# Reset animation phase slightly for variety
	time += randf() * 2.0

	print("Ability pickup '%s' respawned!" % ability_name)

@rpc("call_local")
func play_pickup_sound() -> void:
	"""Play pickup sound effect"""
	if pickup_sound and pickup_sound.stream:
		pickup_sound.pitch_scale = randf_range(1.0, 1.2)
		pickup_sound.play()
