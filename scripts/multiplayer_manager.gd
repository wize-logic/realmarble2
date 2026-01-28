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
var max_players: int = 8  # 1 player + up to 7 bots/other players

# Player info
var players: Dictionary = {}  # peer_id: {name: String, ready: bool, score: int}
var local_player_name: String = "Player"
var bot_counter: int = 0  # Counter for generating bot IDs

# WebSocket settings (for production, point to your relay server)
# CRITICAL HTML5 REQUIREMENT: MUST use WebSocket on HTML5 (ENet not supported in browsers)
var use_websocket: bool = OS.has_feature("web")  # Auto-detect HTML5 to force WebSocket
var relay_server_url: String = "ws://localhost:9080"  # Change to your server URL
var relay_server_port: int = 9080

# Connection retry settings
var connection_retry_count: int = 0
var max_connection_retries: int = 3
var connection_retry_delay: float = 2.0  # Seconds between retries (doubles each time)
var _pending_retry_room_code: String = ""

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

	# CRITICAL HTML5 FIX: Force WebSocket on HTML5 (ENet not supported in browsers)
	if OS.has_feature("web"):
		use_websocket = true

	# Create server
	if use_websocket:
		var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
		# Include room code in URL so relay server can route clients
		var url: String = relay_server_url + "?room=" + room_code
		var error: Error = peer.create_server(relay_server_port)
		if error != OK:
			DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Failed to create WebSocket server: %s" % error)
			network_mode = NetworkMode.OFFLINE
			return ""
		multiplayer.multiplayer_peer = peer
	else:
		var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		var error: Error = peer.create_server(enet_port, max_players)
		if error != OK:
			DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Failed to create ENet server: %s" % error)
			network_mode = NetworkMode.OFFLINE
			return ""
		multiplayer.multiplayer_peer = peer

	# Register self as host
	register_player(1, {
		"name": player_name,
		"ready": false,
		"score": 0
	})

	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Game created! Room code: %s" % room_code)
	lobby_created.emit(room_code)
	return room_code

func join_game(player_name: String, join_room_code: String, host_address: String = "127.0.0.1") -> bool:
	"""Join an existing game lobby
	Args:
		player_name: Display name for the joining player
		join_room_code: Room code to join
		host_address: Host IP address (used for ENet direct connections)
	"""
	local_player_name = player_name
	room_code = join_room_code
	network_mode = NetworkMode.CLIENT

	# Save room code for retry purposes
	_pending_retry_room_code = join_room_code

	# CRITICAL HTML5 FIX: Force WebSocket on HTML5 (ENet not supported in browsers)
	if OS.has_feature("web"):
		use_websocket = true

	if use_websocket:
		var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
		# Include room code in URL so relay server routes to the correct host
		var url: String = relay_server_url + "?room=" + join_room_code
		var error: Error = peer.create_client(url)
		if error != OK:
			DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Failed to connect to WebSocket server: %s" % error)
			network_mode = NetworkMode.OFFLINE
			return false
		multiplayer.multiplayer_peer = peer
	else:
		var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		var error: Error = peer.create_client(host_address, enet_port)
		if error != OK:
			DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Failed to connect to %s:%d - %s" % [host_address, enet_port, error])
			network_mode = NetworkMode.OFFLINE
			return false
		multiplayer.multiplayer_peer = peer

	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Attempting to join game %s at %s" % [room_code, host_address if not use_websocket else relay_server_url])
	return true

func quick_play(player_name: String) -> void:
	"""Quick play - creates a game and auto-fills with bots"""
	local_player_name = player_name

	# Create a new game
	var code: String = create_game(player_name)
	if code.is_empty():
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Quick play - failed to create game")
		connection_failed.emit()
		return

	# Auto-add bots to fill the lobby (3 bots for a quick game)
	var quick_play_bots: int = 3
	for i in range(quick_play_bots):
		add_bot()

	# Auto-ready the host
	set_player_ready(true)

	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Quick play - created game %s with %d bots" % [code, quick_play_bots])

func leave_game() -> void:
	"""Leave current game"""
	if network_mode == NetworkMode.OFFLINE:
		return

	# Notify others
	if network_mode == NetworkMode.HOST:
		# Host leaving - could implement host migration here
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Host leaving game")

	# Disconnect
	multiplayer.multiplayer_peer = null
	network_mode = NetworkMode.OFFLINE
	players.clear()
	room_code = ""
	bot_counter = 0  # Reset bot counter
	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Left game")

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
	# Validate that the sender is setting their own ready status (prevent spoofing)
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != peer_id:
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Warning: Peer %d tried to set ready status for peer %d - rejected" % [sender_id, peer_id])
		return

	if players.has(peer_id):
		players[peer_id].ready = ready
		player_list_changed.emit()

func all_players_ready() -> bool:
	"""Check if all players are ready"""
	if players.size() < 2:
		return false  # Need at least 2 players

	for player in players.values():
		if not player.ready:
			return false
	return true

func add_bot() -> bool:
	"""Add a bot player to the lobby (host only)"""
	if network_mode != NetworkMode.HOST:
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Only host can add bots")
		return false

	if get_player_count() >= max_players:
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Lobby full - cannot add bot")
		return false

	# Generate bot peer ID (IDs starting at 9000 for bots)
	bot_counter += 1
	var bot_peer_id: int = 9000 + bot_counter

	# Register bot in player list
	register_player(bot_peer_id, {
		"name": "Bot %d" % bot_counter,
		"ready": true,  # Bots are always ready
		"score": 0,
		"is_bot": true
	})

	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Bot added to lobby: %d" % bot_peer_id)
	return true

func remove_bot(bot_id: int) -> bool:
	"""Remove a bot from the lobby (host only)"""
	if network_mode != NetworkMode.HOST:
		return false

	if not players.has(bot_id):
		return false

	# Only allow removing bots (IDs >= 9000)
	if bot_id < 9000:
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Cannot remove non-bot player")
		return false

	unregister_player(bot_id)
	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Bot removed from lobby: %d" % bot_id)
	return true

func reset_bots() -> void:
	"""Reset bot counter (call when leaving lobby)"""
	bot_counter = 0

func start_game() -> void:
	"""Start the game (host only)"""
	if network_mode != NetworkMode.HOST:
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Only host can start game")
		return

	if not all_players_ready():
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Not all players ready")
		return

	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Starting game!")
	rpc("on_game_started")

@rpc("authority", "call_local", "reliable")
func on_game_started() -> void:
	"""Called on all peers when game starts"""
	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Game starting!")
	# Signal to world to start match
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if world and world.has_method("start_deathmatch"):
		world.start_deathmatch()

func register_player(peer_id: int, player_info: Dictionary) -> void:
	"""Register a new player"""
	players[peer_id] = player_info
	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Player registered: %d - %s" % [peer_id, player_info.name])
	player_connected.emit(peer_id, player_info)
	player_list_changed.emit()

func unregister_player(peer_id: int) -> void:
	"""Unregister a player"""
	if players.has(peer_id):
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Player unregistered: %d" % peer_id)
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
	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Peer connected: %d" % peer_id)

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
func register_new_player(peer_id: int, player_name: String, client_room_code: String = "") -> void:
	"""Register a new player across the network"""
	# Validate that the sender is registering themselves (prevent spoofing)
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != peer_id:
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Warning: Peer %d tried to register peer %d - rejected" % [sender_id, peer_id])
		return

	# Validate room code if we're the host and client sent one
	if network_mode == NetworkMode.HOST and client_room_code != "" and client_room_code != room_code:
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Peer %d sent wrong room code '%s' (expected '%s') - rejecting" % [peer_id, client_room_code, room_code])
		# Notify the client they joined the wrong room
		rpc_id(peer_id, "_on_wrong_room_code")
		return

	register_player(peer_id, {
		"name": player_name,
		"ready": false,
		"score": 0
	})

@rpc("authority", "reliable")
func _on_wrong_room_code() -> void:
	"""Called on client when host rejects due to wrong room code"""
	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Rejected by host - wrong room code")
	multiplayer.multiplayer_peer = null
	network_mode = NetworkMode.OFFLINE
	connection_failed.emit()

func _on_peer_disconnected(peer_id: int) -> void:
	"""Called when a peer disconnects"""
	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Peer disconnected: %d" % peer_id)
	unregister_player(peer_id)

	# If host disconnected, handle host migration
	if peer_id == 1 and network_mode == NetworkMode.CLIENT:
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Host disconnected - attempting host migration...")
		attempt_host_migration()

func _on_connected_to_server() -> void:
	"""Called when successfully connected to server as client"""
	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Connected to server!")

	# Reset retry state on successful connection
	connection_retry_count = 0
	_pending_retry_room_code = ""

	# Register ourselves with the host, including room code for validation
	var peer_id: int = multiplayer.get_unique_id()
	rpc_id(1, "register_new_player", peer_id, local_player_name, room_code)

	connection_succeeded.emit()
	lobby_joined.emit(room_code)

func _on_connection_failed() -> void:
	"""Called when connection to server fails"""
	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Connection failed! Retry %d/%d" % [connection_retry_count, max_connection_retries])

	# Attempt retry if we haven't exceeded max retries
	if connection_retry_count < max_connection_retries:
		connection_retry_count += 1
		var retry_delay: float = connection_retry_delay * pow(2, connection_retry_count - 1)  # Exponential backoff
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Retrying connection in %.1f seconds..." % retry_delay)

		# Schedule retry
		var timer: SceneTreeTimer = get_tree().create_timer(retry_delay)
		timer.timeout.connect(_retry_connection)
	else:
		# Max retries exceeded - give up
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Max connection retries exceeded. Giving up.")
		connection_retry_count = 0
		_pending_retry_room_code = ""
		network_mode = NetworkMode.OFFLINE
		connection_failed.emit()

func _retry_connection() -> void:
	"""Retry the last connection attempt"""
	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Retrying connection (attempt %d)..." % connection_retry_count)

	# Clean up old peer
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	# Retry joining the game
	if _pending_retry_room_code != "":
		join_game(local_player_name, _pending_retry_room_code)
	else:
		# No room code saved - just emit failure
		connection_retry_count = 0
		network_mode = NetworkMode.OFFLINE
		connection_failed.emit()

func _on_server_disconnected() -> void:
	"""Called when disconnected from server"""
	DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Disconnected from server")
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
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "Becoming new host!")
		# We're the new host - recreate server
		create_game(local_player_name)
	else:
		DebugLogger.dlog(DebugLogger.Category.MULTIPLAYER, "New host is: %d" % new_host_id)

func is_host() -> bool:
	"""Check if local player is host"""
	return network_mode == NetworkMode.HOST

func is_online() -> bool:
	"""Check if in an online game"""
	return network_mode != NetworkMode.OFFLINE
