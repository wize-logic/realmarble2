# Multiplayer System

## Quick Start

### Playing Locally (Testing)

1. Run the game
2. Click "Create Game" - Note the room code
3. Run a second instance
4. Click "Join Game" and enter the room code
5. Both players click "Ready"
6. Host clicks "Start Game"

### Playing Online

1. Set up a WebSocket relay server (see CRAZYGAMES_DEPLOYMENT.md)
2. Update `relay_server_url` in `scripts/multiplayer_manager.gd`
3. Set `use_websocket = true` in multiplayer_manager.gd
4. Export and deploy!

## Features

### Lobby System
- **Create Game**: Generates a 6-character room code
- **Join Game**: Enter a room code to join
- **Quick Play**: Auto-match (currently just creates a game)
- **Player List**: See all players and their ready status
- **Ready System**: All players must ready up before starting

### In-Game
- Up to 8 players per match (you + 7 bots/others)
- 5-minute deathmatch
- Procedurally generated arenas
- Bot AI support
- Player scores and leaderboard
- Host migration (basic implementation)

## Architecture

```
Global (Autoload)
  ├─ Settings
  └─ Player Name

MultiplayerManager (Autoload)
  ├─ Network Mode (Host/Client/Offline)
  ├─ Player List
  ├─ Room Codes
  └─ Matchmaking

World
  ├─ LobbyUI
  ├─ Players
  ├─ Level Generator
  └─ Game Logic
```

## Files

- `scripts/multiplayer_manager.gd` - Core networking and matchmaking
- `scripts/lobby_ui.gd` - UI for creating/joining games
- `lobby_ui.tscn` - Lobby UI scene
- `scripts/global.gd` - Global settings and player data

## Configuration

### MultiplayerManager Settings

```gdscript
var use_websocket: bool = false        # Use WebSocket (true for browsers)
var relay_server_url: String = "..."  # Your relay server
var max_players: int = 8               # Max players per game (you + 7 bots/others)
```

### For Local Testing
```gdscript
use_websocket = false  # Uses ENet
```

### For Browser/CrazyGames
```gdscript
use_websocket = true
relay_server_url = "ws://your-server.com:9080"
```

## API

### MultiplayerManager

```gdscript
# Create a game
var code = MultiplayerManager.create_game("PlayerName")

# Join a game
MultiplayerManager.join_game("PlayerName", "ABC123")

# Quick play
MultiplayerManager.quick_play("PlayerName")

# Set ready status
MultiplayerManager.set_player_ready(true)

# Start game (host only)
MultiplayerManager.start_game()

# Leave game
MultiplayerManager.leave_game()
```

### Signals

```gdscript
# Connection events
player_connected(peer_id, player_info)
player_disconnected(peer_id)
connection_failed()
connection_succeeded()
server_disconnected()

# Lobby events
lobby_created(room_code)
lobby_joined(room_code)
player_list_changed()
```

## Extending

### Adding Matchmaking

Update `quick_play()` in multiplayer_manager.gd:
```gdscript
func quick_play(player_name: String) -> void:
    # Query your matchmaking server
    var available_rooms = query_matchmaking_server()

    if available_rooms.size() > 0:
        join_game(player_name, available_rooms[0])
    else:
        create_game(player_name)
```

### Custom Player Data

Update player registration in multiplayer_manager.gd:
```gdscript
register_player(peer_id, {
    "name": player_name,
    "ready": false,
    "score": 0,
    "level": 1,              # Add custom fields
    "skin": "default",       # Add custom fields
    "ping": 0                # Add custom fields
})
```

### Server Browser

Add to lobby_ui.gd:
```gdscript
func show_server_browser() -> void:
    # Query your server for active rooms
    # Display list of rooms
    # Let player click to join
```

## Troubleshooting

### "Connection Failed"
- Check server is running
- Verify `relay_server_url` is correct
- Check firewall settings

### "Room Code Invalid"
- Ensure room codes match exactly
- Check if host is still connected
- Verify server is handling room codes

### "Lag/Stutter"
- Reduce `max_players`
- Optimize network sends
- Use unreliable RPCs where possible
- Check network latency

### "Host Disconnect"
- Host migration will attempt to transfer to next player
- If it fails, all players are kicked
- Consider using dedicated servers for production

## Best Practices

1. **Always validate room codes** before attempting connection
2. **Provide clear feedback** to users during connection
3. **Handle disconnections gracefully** with proper UI messages
4. **Test with real internet latency** (100-200ms)
5. **Implement reconnection logic** for temporary disconnects
6. **Use server authority** for critical game logic (scores, kills, etc.)
7. **Add timeouts** for connection attempts
8. **Log network events** for debugging

## Future Improvements

- [ ] Ranked matchmaking
- [ ] Skill-based matching
- [ ] Region selection
- [ ] Server browser UI
- [ ] Party system (friends play together)
- [ ] Spectator mode
- [ ] Replay system
- [ ] Anti-cheat basics
- [ ] Connection quality indicator
- [ ] Reconnect after disconnect

## Resources

- [Godot Multiplayer Docs](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)
- [WebSocket Docs](https://docs.godotengine.org/en/stable/classes/class_websocketmultiplayerpeer.html)
- CrazyGames_DEPLOYMENT.md (detailed deployment guide)
