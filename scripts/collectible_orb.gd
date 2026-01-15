extends Area3D

## Collectible orb that grants level ups
## Players can collect up to 3 orbs for maximum power

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var collection_sound: AudioStreamPlayer3D = $CollectionSound

# Visual properties
var base_height: float = 0.0
var bob_speed: float = 2.0
var bob_amount: float = 0.3
var rotation_speed: float = 2.0
var time: float = 0.0

# Respawn properties
var respawn_time: float = 15.0  # Respawn after 15 seconds
var is_collected: bool = false
var respawn_timer: float = 0.0

# Visual effects
var glow_material: StandardMaterial3D
var aura_light: OmniLight3D

func _ready() -> void:
	# Add to orbs group for bot AI
	add_to_group("orbs")

	# Store initial height
	base_height = global_position.y

	# Set up collision detection
	body_entered.connect(_on_body_entered)

	# Set up visual appearance if mesh exists
	if mesh_instance and mesh_instance.mesh:
		# Create glowing material for orb
		glow_material = StandardMaterial3D.new()
		glow_material.albedo_color = Color(0.3, 0.7, 1.0, 1.0)  # Cyan/blue color
		glow_material.emission_enabled = true
		glow_material.emission = Color(0.5, 0.8, 1.0)
		glow_material.emission_energy_multiplier = 2.0
		glow_material.metallic = 0.3
		glow_material.roughness = 0.2
		mesh_instance.material_override = glow_material

	# Randomize starting animation phase
	time = randf() * TAU

	# Set up aura light effect for better visibility
	if not aura_light:
		aura_light = OmniLight3D.new()
		aura_light.name = "AuraLight"
		add_child(aura_light)

		# Configure light properties - bright cyan for orbs
		aura_light.light_color = Color(0.5, 0.9, 1.0)  # Bright cyan
		aura_light.light_energy = 2.5  # Brightest to make orbs very visible
		aura_light.omni_range = 4.5  # Large radius for high visibility
		aura_light.omni_attenuation = 1.5  # Moderate falloff

		# Shadow settings - disable for performance
		aura_light.shadow_enabled = false

func _process(delta: float) -> void:
	if is_collected:
		# Handle respawn timer
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			respawn_orb()
		return

	# Update animation time
	time += delta

	# Bob up and down
	var new_pos: Vector3 = global_position
	new_pos.y = base_height + sin(time * bob_speed) * bob_amount
	global_position = new_pos

	# Rotate slowly
	if mesh_instance:
		mesh_instance.rotation.y += rotation_speed * delta

		# Pulse emission for extra effect
		if glow_material:
			var pulse: float = 1.5 + sin(time * 3.0) * 0.5
			glow_material.emission_energy_multiplier = pulse

func _on_body_entered(body: Node3D) -> void:
	# Check if it's a player and not already collected
	if is_collected:
		return

	# Check if body is a player (RigidBody3D with player script)
	# Allow collection regardless of level - even max level players can collect orbs
	if body is RigidBody3D and body.has_method("collect_orb"):
		collect(body)

func collect(player: Node) -> void:
	"""Handle orb collection"""
	# Call player's collect method
	player.collect_orb()

	# Play collection sound
	if collection_sound and collection_sound.stream:
		play_collection_sound.rpc()

	# Mark as collected
	is_collected = true
	respawn_timer = respawn_time

	# Hide the orb
	if mesh_instance:
		mesh_instance.visible = false
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if aura_light:
		aura_light.visible = false

	print("Orb collected by player! Respawning in %.1f seconds" % respawn_time)

func respawn_orb() -> void:
	"""Respawn the orb"""
	is_collected = false

	# Show the orb again
	if mesh_instance:
		mesh_instance.visible = true
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	if aura_light:
		aura_light.visible = true

	# Reset animation phase slightly for variety
	time += randf() * 2.0

	print("Orb respawned!")

@rpc("call_local")
func play_collection_sound() -> void:
	"""Play collection sound effect"""
	if collection_sound and collection_sound.stream:
		collection_sound.pitch_scale = randf_range(0.9, 1.1)
		collection_sound.play()
