extends Node

## Multiplayer Manager
## Handles networking, lobbies, and matchmaking for CrazyGames deployment

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal connection_succeeded()
signal server_disconnected()
signal lobby_created(room_code: String)
signal lobby_joined(room_code: String)
signal player_list_changed()

# Networking
enum NetworkMode { OFFLINE, HOST, CLIENT }
var network_mode: NetworkMode = NetworkMode.OFFLINE
var room_code: String = ""
var max_players: int = 16

# Player info
var players: Dictionary = {}  # peer_id: {name: String, ready: bool, score: int, is_bot: bool}
var local_player_name: String = "Player"
var bot_counter: int = 0  # Counter for bot IDs

# WebSocket settings (for production, point to your relay server)
var use_websocket: bool = true
var relay_server_url: String = "ws://localhost:9080"  # Change to your server URL
var relay_server_port: int = 9080

# ENet settings (for local testing)
var enet_port: int = 9999

func _ready() -> void:
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func create_game(player_name: String) -> String:
	"""Create a new game lobby as host"""
	local_player_name = player_name
	network_mode = NetworkMode.HOST

	# Generate random room code
	room_code = generate_room_code()

	# Create server
	if use_websocket:
		var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
		var error: Error = peer.create_server(relay_server_port)
		if error != OK:
			print("Failed to create WebSocket server: ", error)
			network_mode = NetworkMode.OFFLINE
			return ""
		multiplayer.multiplayer_peer = peer
	else:
		var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		var error: Error = peer.create_server(enet_port, max_players)
		if error != OK:
			print("Failed to create ENet server: ", error)
			network_mode = NetworkMode.OFFLINE
			return ""
		multiplayer.multiplayer_peer = peer

	# Register self as host
	register_player(1, {
		"name": player_name,
		"ready": false,
		"score": 0,
		"is_bot": false
	})

	print("Game created! Room code: ", room_code)
	lobby_created.emit(room_code)
	return room_code

func join_game(player_name: String, join_room_code: String) -> bool:
	"""Join an existing game lobby"""
	local_player_name = player_name
	room_code = join_room_code
	network_mode = NetworkMode.CLIENT

	# For this simple implementation, we use direct connection
	# In production, you'd query your relay server for the room's IP/port
	var host_address: String = "127.0.0.1"  # Change based on your matchmaking server

	if use_websocket:
		var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
		var url: String = relay_server_url
		var error: Error = peer.create_client(url)
		if error != OK:
			print("Failed to connect to WebSocket server: ", error)
			network_mode = NetworkMode.OFFLINE
			return false
		multiplayer.multiplayer_peer = peer
	else:
		var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		var error: Error = peer.create_client(host_address, enet_port)
		if error != OK:
			print("Failed to connect to server: ", error)
			network_mode = NetworkMode.OFFLINE
			return false
		multiplayer.multiplayer_peer = peer

	print("Attempting to join game with room code: ", room_code)
	return true

func quick_play(player_name: String) -> void:
	"""Quick play - auto-matchmaking"""
	# In a real implementation, this would query your matchmaking server
	# For now, just create a new game
	create_game(player_name)
	print("Quick play - created new game")

func leave_game() -> void:
	"""Leave current game"""
	if network_mode == NetworkMode.OFFLINE:
		return

	# Notify others
	if network_mode == NetworkMode.HOST:
		# Host leaving - could implement host migration here
		print("Host leaving game")

	# Disconnect
	multiplayer.multiplayer_peer = null
	network_mode = NetworkMode.OFFLINE
	players.clear()
	room_code = ""
	print("Left game")

func set_player_ready(ready: bool) -> void:
	"""Set local player ready status"""
	var peer_id: int = multiplayer.get_unique_id()
	if players.has(peer_id):
		players[peer_id].ready = ready
		rpc("sync_player_ready", peer_id, ready)
		player_list_changed.emit()

@rpc("any_peer", "reliable")
func sync_player_ready(peer_id: int, ready: bool) -> void:
	"""Sync player ready status across network"""
	if players.has(peer_id):
		players[peer_id].ready = ready
		player_list_changed.emit()

func all_players_ready() -> bool:
	"""Check if all players are ready"""
	if players.size() < 1:
		return false  # Need at least 1 player or bot

	# Check if all human players are ready (bots are always ready)
	for player in players.values():
		if not player.get("is_bot", false) and not player.ready:
			return false
	return true

func add_bot_to_lobby() -> void:
	"""Add a bot to the lobby (host only)"""
	if network_mode != NetworkMode.HOST:
		print("Only host can add bots")
		return

	bot_counter += 1
	var bot_id: int = 9000 + bot_counter  # Bot IDs start at 9000
	var bot_name: String = "Bot " + str(bot_counter)

	# Sync to all clients (including host via call_local)
	rpc("sync_bot_added", bot_id, bot_name)
	print("Bot added to lobby: ", bot_name)

@rpc("authority", "call_local", "reliable")
func sync_bot_added(bot_id: int, bot_name: String) -> void:
	"""Sync bot addition across network"""
	if not players.has(bot_id):
		register_player(bot_id, {
			"name": bot_name,
			"ready": true,
			"score": 0,
			"is_bot": true
		})

func start_game() -> void:
	"""Start the game (host only)"""
	if network_mode != NetworkMode.HOST:
		print("Only host can start game")
		return

	if not all_players_ready():
		print("Not all players ready")
		return

	print("Starting game!")
	rpc("on_game_started")

@rpc("authority", "call_local", "reliable")
func on_game_started() -> void:
	"""Called on all peers when game starts"""
	print("Game starting!")
	# Signal to world to start match and spawn bots
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if world:
		# Spawn bots from lobby list (host only)
		if network_mode == NetworkMode.HOST and world.has_method("spawn_bots_from_lobby"):
			world.spawn_bots_from_lobby(get_bot_list())

		if world.has_method("start_deathmatch"):
			world.start_deathmatch()

func get_bot_list() -> Array:
	"""Get list of bot player IDs"""
	var bot_list: Array = []
	for peer_id in players.keys():
		if players[peer_id].get("is_bot", false):
			bot_list.append({
				"id": peer_id,
				"name": players[peer_id].name
			})
	return bot_list

func register_player(peer_id: int, player_info: Dictionary) -> void:
	"""Register a new player"""
	players[peer_id] = player_info
	print("Player registered: ", peer_id, " - ", player_info.name)
	player_connected.emit(peer_id, player_info)
	player_list_changed.emit()

func unregister_player(peer_id: int) -> void:
	"""Unregister a player"""
	if players.has(peer_id):
		print("Player unregistered: ", peer_id)
		players.erase(peer_id)
		player_disconnected.emit(peer_id)
		player_list_changed.emit()

func generate_room_code() -> String:
	"""Generate a random 6-character room code"""
	var chars: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # Avoid confusing chars
	var code: String = ""
	for i in range(6):
		code += chars[randi() % chars.length()]
	return code

func get_player_count() -> int:
	"""Get current player count"""
	return players.size()

func get_player_list() -> Array:
	"""Get list of player info dictionaries"""
	var player_list: Array = []
	for peer_id in players.keys():
		var player: Dictionary = players[peer_id].duplicate()
		player["peer_id"] = peer_id
		player_list.append(player)
	return player_list

# Network callbacks
func _on_peer_connected(peer_id: int) -> void:
	"""Called when a peer connects"""
	print("Peer connected: ", peer_id)

	# If we're the host, send them our player list
	if network_mode == NetworkMode.HOST:
		# Send existing players to new peer
		rpc_id(peer_id, "receive_player_list", players)

@rpc("any_peer", "reliable")
func receive_player_list(player_list: Dictionary) -> void:
	"""Receive the player list from host"""
	players = player_list
	player_list_changed.emit()

@rpc("any_peer", "reliable")
func register_new_player(peer_id: int, player_name: String) -> void:
	"""Register a new player across the network"""
	register_player(peer_id, {
		"name": player_name,
		"ready": false,
		"score": 0
	})

func _on_peer_disconnected(peer_id: int) -> void:
	"""Called when a peer disconnects"""
	print("Peer disconnected: ", peer_id)
	unregister_player(peer_id)

	# If host disconnected, handle host migration
	if peer_id == 1 and network_mode == NetworkMode.CLIENT:
		print("Host disconnected - attempting host migration...")
		attempt_host_migration()

func _on_connected_to_server() -> void:
	"""Called when successfully connected to server as client"""
	print("Connected to server!")

	# Register ourselves with the host
	var peer_id: int = multiplayer.get_unique_id()
	rpc_id(1, "register_new_player", peer_id, local_player_name)

	connection_succeeded.emit()
	lobby_joined.emit(room_code)

func _on_connection_failed() -> void:
	"""Called when connection to server fails"""
	print("Connection failed!")
	network_mode = NetworkMode.OFFLINE
	connection_failed.emit()

func _on_server_disconnected() -> void:
	"""Called when disconnected from server"""
	print("Disconnected from server")
	network_mode = NetworkMode.OFFLINE
	server_disconnected.emit()

func attempt_host_migration() -> void:
	"""Attempt to migrate host to another player"""
	# Simple host migration - lowest peer ID becomes new host
	if players.size() == 0:
		leave_game()
		return

	var peer_ids: Array = players.keys()
	peer_ids.sort()

	var new_host_id: int = peer_ids[0]
	var local_id: int = multiplayer.get_unique_id()

	if local_id == new_host_id:
		print("Becoming new host!")
		# We're the new host - recreate server
		create_game(local_player_name)
	else:
		print("New host is: ", new_host_id)

func is_host() -> bool:
	"""Check if local player is host"""
	return network_mode == NetworkMode.HOST

func is_online() -> bool:
	"""Check if in an online game"""
	return network_mode != NetworkMode.OFFLINE
