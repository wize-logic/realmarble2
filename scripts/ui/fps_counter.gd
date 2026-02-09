extends Label

var fps_bool := false
var ping_bool := false
var _update_timer: float = 0.0

func _process(delta: float) -> void:
	if not fps_bool and not ping_bool:
		text = ""
		return
	_update_timer += delta
	if _update_timer < 0.5:
		return
	_update_timer = 0.0
	var fps: String = "FPS " + str(Engine.get_frames_per_second()) + "\n" if fps_bool else ""
	var ping: String = ""
	if ping_bool:
		# Get actual round-trip time from the multiplayer peer
		var mp_peer = multiplayer.multiplayer_peer
		if mp_peer is ENetMultiplayerPeer:
			var enet_host: ENetConnection = mp_peer.get_host()
			if enet_host:
				var peers: Array = enet_host.get_peers()
				if peers.size() > 0:
					ping = "PING %dms" % peers[0].get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
				else:
					ping = "PING N/A"
			else:
				ping = "PING N/A"
		elif mp_peer is WebSocketMultiplayerPeer:
			# WebSocket doesn't expose RTT directly
			ping = "PING (WS)"
		else:
			ping = "PING N/A"
	text = fps + ping

func _on_fps_counter_toggled(toggled_on: bool) -> void:
	if toggled_on:
		fps_bool = true
	else:
		fps_bool = false

func _on_ping_toggled(toggled_on: bool) -> void:
	if toggled_on:
		ping_bool = true
	else:
		ping_bool = false
