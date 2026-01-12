# Marble Multiplayer - CrazyGames Deployment Guide

## Overview

This game uses a **WebSocket-based multiplayer system** optimized for browser deployment on CrazyGames. The system includes:

- Room code-based matchmaking
- Quick play auto-matchmaking
- Player ready system
- Host migration support
- Up to 8 players per game

## Architecture

### Networking Mode
The game supports two networking modes:
1. **WebSocket** (recommended for production) - Works perfectly in browsers
2. **ENet** (for local testing only) - Won't work in browser builds

### Current Setup
- **Mode**: Can toggle between WebSocket and ENet in `multiplayer_manager.gd`
- **Default**: Uses ENet for local testing (set `use_websocket = false`)
- **Production**: Set `use_websocket = true` for browser deployment

## Deployment Options

### Option 1: Simple P2P with Signaling Server (Recommended for Small Scale)

**How it works:**
- One player acts as host, others connect directly
- Requires a lightweight signaling server for initial connection
- No ongoing server costs during gameplay

**Implementation:**
1. Set up a simple WebSocket signaling server (Node.js example provided below)
2. Update `relay_server_url` in `multiplayer_manager.gd`
3. Export game as HTML5
4. Upload to CrazyGames

**Pros:**
- Very low cost (tiny signaling server)
- Minimal setup required
- Good for 2-8 players

**Cons:**
- Host leaving ends the game (unless host migration works)
- NAT traversal issues possible
- Host needs good connection

### Option 2: Dedicated Relay Server (Recommended for Scale)

**How it works:**
- All players connect to a central server
- Server relays messages between players
- More reliable than P2P

**Implementation:**
1. Deploy a WebSocket relay server (Godot Headless or custom)
2. Update `relay_server_url` to point to your server
3. Handle room codes on server side
4. Export and deploy

**Pros:**
- More reliable
- Better for many concurrent games
- No host dependency

**Cons:**
- Requires hosting a server (costs $5-20/month)
- Slightly more complex setup

### Option 3: Use CrazyGames SDK (If Available)

Check if CrazyGames provides multiplayer infrastructure. If they do, integrate their SDK instead.

## Quick Setup for Testing

### 1. Local Testing (No Server Required)

```gdscript
# In multiplayer_manager.gd, set:
var use_websocket: bool = false  # Use ENet for local testing
```

- Run two instances of the game
- One creates, one joins
- Works great for development

### 2. Browser Testing (Simple Signaling Server)

Create a simple Node.js signaling server:

```javascript
// signaling-server.js
const WebSocket = require('ws');
const wss = new WebSocket.Server({ port: 9080 });

const rooms = new Map();

wss.on('connection', (ws) => {
  console.log('Client connected');

  ws.on('message', (message) => {
    const data = JSON.parse(message);

    if (data.type === 'create_room') {
      rooms.set(data.room_code, [ws]);
      ws.room_code = data.room_code;
      ws.send(JSON.stringify({ type: 'room_created', code: data.room_code }));
    }
    else if (data.type === 'join_room') {
      const room = rooms.get(data.room_code);
      if (room) {
        room.push(ws);
        ws.room_code = data.room_code;
        // Relay join to all in room
        room.forEach(client => {
          if (client !== ws && client.readyState === WebSocket.OPEN) {
            client.send(JSON.stringify({ type: 'player_joined' }));
          }
        });
      }
    }
    else {
      // Relay all other messages to room
      const room = rooms.get(ws.room_code);
      if (room) {
        room.forEach(client => {
          if (client !== ws && client.readyState === WebSocket.OPEN) {
            client.send(message);
          }
        });
      }
    }
  });

  ws.on('close', () => {
    console.log('Client disconnected');
    if (ws.room_code) {
      const room = rooms.get(ws.room_code);
      if (room) {
        const index = room.indexOf(ws);
        if (index > -1) room.splice(index, 1);
        if (room.length === 0) rooms.delete(ws.room_code);
      }
    }
  });
});

console.log('Signaling server running on port 9080');
```

Run with: `node signaling-server.js`

Update in `multiplayer_manager.gd`:
```gdscript
var use_websocket: bool = true
var relay_server_url: String = "ws://your-server.com:9080"
```

## Godot Export Settings

### HTML5 Export

1. **Project Settings** → **Export**
2. Add HTML5 template
3. **Runnable** → Enable
4. **Head Include** → Add CrazyGames SDK if needed:
```html
<script src="https://sdk.crazygames.com/crazygames-sdk-v1.js"></script>
```

5. **SharedArrayBuffer Support** → Enable (for threading)
6. **Thread Support** → Enable

### Important Export Options

- **Export Type**: HTML5
- **Orientation**: Landscape
- **Thread Support**: Yes
- **GDExtension Support**: No (keeps file size small)

## CrazyGames Integration

### 1. Add CrazyGames SDK (Optional)

Create `crazygames_sdk.gd`:
```gdscript
extends Node

var sdk_available: bool = false

func _ready() -> void:
	# Check if SDK is available
	if JavaScript.eval("typeof window.CrazyGames !== 'undefined'"):
		sdk_available = true
		print("CrazyGames SDK available")

func game_start() -> void:
	if sdk_available:
		JavaScript.eval("window.CrazyGames.SDK.game.gameplayStart()")

func game_end() -> void:
	if sdk_available:
		JavaScript.eval("window.CrazyGames.SDK.game.gameplayStop()")

func show_ad() -> void:
	if sdk_available:
		JavaScript.eval("window.CrazyGames.SDK.ad.requestAd('midgame')")
```

### 2. Integrate with Your Game

```gdscript
# In world.gd
func start_deathmatch() -> void:
	if CrazyGamesSDK:
		CrazyGamesSDK.game_start()
	# ... rest of function

func end_deathmatch() -> void:
	if CrazyGamesSDK:
		CrazyGamesSDK.game_end()
	# ... rest of function
```

## Deployment Checklist

- [ ] Set `use_websocket = true` in multiplayer_manager.gd
- [ ] Update `relay_server_url` to production server
- [ ] Test multiplayer with 4+ players
- [ ] Export as HTML5
- [ ] Test exported build locally
- [ ] Verify room codes work
- [ ] Test quick play matchmaking
- [ ] Verify host migration works
- [ ] Check performance (60 FPS minimum)
- [ ] Test on different browsers (Chrome, Firefox, Safari)
- [ ] Upload to CrazyGames
- [ ] Submit for review

## Server Hosting Recommendations

### Free/Cheap Options:
1. **Heroku** (Free tier) - Good for testing
2. **Railway** ($5/month) - Easy deployment
3. **DigitalOcean** ($5/month) - Reliable droplet
4. **AWS EC2** (Free tier for 1 year)
5. **Google Cloud Run** (Pay per use, very cheap)

### Server Requirements:
- Minimal CPU (512 MB RAM sufficient)
- WebSocket support
- Low latency (<100ms to players)
- Reliable uptime

## Matchmaking Server (Optional Advanced)

For larger scale, implement a proper matchmaking server:

**Features:**
- Room creation/listing
- Player matching by skill
- Server browser
- Region-based matching
- Anti-cheat basics

**Tech Stack:**
- Node.js or Godot Headless
- Redis for room state
- WebSocket for connections
- Optional REST API

## Testing Strategy

1. **Local Test**: 2 instances, same PC
2. **LAN Test**: 2 PCs, same network
3. **Internet Test**: 2 different networks
4. **Browser Test**: HTML5 build, 2 browsers
5. **Load Test**: 8 players simultaneously
6. **Stress Test**: Multiple concurrent games

## Common Issues & Solutions

### Issue: "Connection Failed"
**Solution**: Check `relay_server_url` is correct and server is running

### Issue: "Can't Join Room"
**Solution**: Verify room code system is working, check server logs

### Issue: "Host Migration Failing"
**Solution**: Ensure all clients receive host disconnect signal properly

### Issue: "Lag/Desync"
**Solution**: Reduce physics sends, optimize RPCs, use server authority

### Issue: "WebSocket Not Working in Browser"
**Solution**: Ensure proper CORS headers, use WSS (secure) for HTTPS sites

## Performance Optimization

- Minimize RPC calls
- Use unreliable RPCs for non-critical data
- Compress network data
- Reduce physics sync frequency
- Use client-side prediction
- Implement lag compensation

## Support & Updates

For issues or questions:
1. Check Godot multiplayer documentation
2. Review CrazyGames developer guidelines
3. Test thoroughly before submission

## Final Notes

- Always test with real internet latency
- Have a fallback for connection failures
- Provide clear UI feedback for connection status
- Consider adding a "Practice vs Bots" mode for offline play
- Monitor player feedback after launch

Good luck with your deployment! 🎮
