extends Ability

## Gun Ability
## Shoots projectiles that damage enemies
## Like a ranged attack!

@export var projectile_damage: int = 1
@export var projectile_speed: float = 40.0
@export var projectile_lifetime: float = 3.0
@export var fire_rate: float = 0.3  # Shots per second

func _ready() -> void:
	super._ready()
	ability_name = "Gun"
	ability_color = Color.CYAN
	cooldown_time = fire_rate

	# Create sound effect
	ability_sound = AudioStreamPlayer3D.new()
	ability_sound.name = "GunSound"
	add_child(ability_sound)
	ability_sound.max_distance = 35.0
	ability_sound.volume_db = 0.0

func activate() -> void:
	if not player:
		return

	print("BANG!")

	# Get firing direction from camera
	var camera_arm: Node3D = player.get_node_or_null("CameraArm")
	var fire_direction: Vector3 = Vector3.FORWARD

	if camera_arm:
		# Shoot in camera forward direction
		fire_direction = -camera_arm.global_transform.basis.z
	else:
		# Fallback: use player's velocity direction
		if player.linear_velocity.length() > 0.1:
			fire_direction = player.linear_velocity.normalized()

	# Spawn projectile
	var projectile: Node3D = create_projectile()
	if projectile:
		# Add to world FIRST
		player.get_parent().add_child(projectile)

		# Position at player (after adding to tree)
		projectile.global_position = player.global_position + Vector3.UP * 0.5

		# Set velocity (scaled with player level: 1.0 + 0.25 per level)
		if projectile.has_method("set_velocity"):
			var level_multiplier: float = 1.0
			if player and "level" in player:
				level_multiplier = 1.0 + (player.level * 0.25)
			projectile.set_velocity(fire_direction * projectile_speed * level_multiplier)

		# Set damage and owner
		if projectile.has_method("set_damage"):
			projectile.set_damage(projectile_damage)
		if projectile.has_method("set_owner_id"):
			var owner_id: int = player.name.to_int() if player else -1
			projectile.set_owner_id(owner_id)

	# Play gun sound
	if ability_sound:
		ability_sound.play()

func create_projectile() -> Node3D:
	"""Create a projectile node"""
	# Create a simple projectile
	var projectile: RigidBody3D = RigidBody3D.new()
	projectile.name = "Projectile"

	# Physics setup
	projectile.mass = 0.1
	projectile.gravity_scale = 0.0  # No gravity for projectiles
	projectile.continuous_cd = true
	projectile.collision_layer = 4  # Projectile layer
	projectile.collision_mask = 3   # Hit players (layer 2) and world (layer 1)

	# Create mesh
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	mesh_instance.mesh = sphere

	# Create glowing material
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color.CYAN
	mat.emission_enabled = true
	mat.emission = Color.CYAN
	mat.emission_energy_multiplier = 2.0
	mesh_instance.material_override = mat
	projectile.add_child(mesh_instance)

	# Create collision shape
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.15
	collision.shape = shape
	projectile.add_child(collision)

	# Add script for projectile behavior
	var script_text: String = """
extends RigidBody3D

var damage: int = 1
var owner_id: int = -1
var lifetime: float = 3.0

func _ready() -> void:
	# Auto-destroy after lifetime
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func set_velocity(vel: Vector3) -> void:
	linear_velocity = vel

func set_damage(dmg: int) -> void:
	damage = dmg

func set_owner_id(id: int) -> void:
	owner_id = id

func _on_body_entered(body: Node) -> void:
	# Don't hit the owner
	if body.name == str(owner_id):
		return

	# Check if it's a player
	if body.has_method('receive_damage_from'):
		var target_id: int = body.get_multiplayer_authority()
		# Check if target is a bot (ID >= 9000) or no multiplayer
		if target_id >= 9000 or multiplayer.multiplayer_peer == null:
			# Local call for bots or no multiplayer
			body.receive_damage_from(damage, owner_id)
		else:
			# RPC call for network players
			body.receive_damage_from.rpc_id(target_id, damage, owner_id)
		print('Projectile hit player: ', body.name)

	# Destroy projectile on hit
	queue_free()
"""

	var script: GDScript = GDScript.new()
	script.source_code = script_text
	script.reload()
	projectile.set_script(script)

	# Connect body entered signal
	projectile.body_entered.connect(projectile._on_body_entered)

	return projectile
