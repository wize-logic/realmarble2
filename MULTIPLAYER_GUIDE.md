# Multiplayer Guide

## Architecture

The game uses Godot's built-in peer-to-peer multiplayer. One player acts as the **host** and other players connect as **clients**.

- **Desktop**: Uses ENet for direct P2P connections (no relay server needed)
- **Web/HTML5**: Uses WebSocket through a relay server (ENet is not supported in browsers)

### Relay Server (HTML5)

Browsers cannot open server sockets, so HTML5 multiplayer requires a **WebSocket relay server**. Both the host and clients connect to the relay as WebSocket clients. The relay groups players by room code, assigns peer IDs, and forwards packets between them.

The relay server is located in the `server/` directory. See [Relay Server Setup](#relay-server-setup) below.

## How to Play

### Quick Play

1. Click **PLAY** on the main menu
2. Click **MULTIPLAYER**
3. Click **QUICK PLAY**
4. A game is created with 3 bots automatically added
5. Configure room settings (level size, match duration)
6. Click **START GAME** when ready

### Hosting a Game

1. Click **PLAY** > **MULTIPLAYER**
2. Click **CREATE GAME**
3. Share the 6-character **Room Code** with friends
4. Configure **Room Settings** (see below)
5. Optionally click **ADD BOT** to fill slots with AI opponents (up to 7 total)
6. Click **READY** when you're set
7. Click **START GAME** once all players are ready

### Joining a Game

1. Click **PLAY** > **MULTIPLAYER**
2. Enter the host's **Room Code**
3. Click **JOIN GAME**
4. View the host's room settings (displayed as read-only)
5. Click **READY** when you're set
6. Wait for the host to start the game

## Room Settings

The host can configure match settings before starting. These settings are automatically synced to all connected players.

### Level Size
Controls the arena dimensions and complexity:
| Setting | Description |
|---------|-------------|
| **Small** | Compact arena (0.7x size) |
| **Medium** | Standard arena (default) |
| **Large** | Expanded arena (1.5x size) |
| **Huge** | Massive arena (2x size) |

### Match Duration
| Setting | Time |
|---------|------|
| 1 | 1 minute |
| 2 | 3 minutes |
| 3 | 5 minutes (default) |
| 4 | 10 minutes |
| 5 | 15 minutes |

### Level Synchronization
When the game starts, the host generates a random seed that is shared with all players. This ensures everyone generates the exact same level layout despite using procedural generation.

## Connecting

### Web/HTML5

HTML5 multiplayer works automatically through the relay server. Players only need a room code to connect — no IP addresses or port forwarding required.

The relay server URL is configured in `scripts/multiplayer_manager.gd` via the `RELAY_SERVER_URL_DEFAULT` constant. You can also override it at runtime by setting `window.RELAY_SERVER_URL` in the HTML page before the game loads.

### Desktop — Local Network (LAN)

Players on the same local network can connect directly. The joining player needs the host's local IP address (e.g. `192.168.1.x`). The game connects on port `9999` by default using ENet.

### Desktop — Over the Internet

For internet play, the host needs to either:

- **Port forward** port `9999` (UDP) on their router to their local machine
- Use a VPN/tunnel service (e.g. ZeroTier, Tailscale, Radmin VPN) so all players appear on the same virtual LAN

## Relay Server Setup

The `server/` directory contains a Node.js WebSocket relay server that implements the Godot `WebSocketMultiplayerPeer` binary protocol.

### Running Locally

```bash
cd server
npm install
npm start
```

The server listens on port `9080` by default. Set the `PORT` environment variable to change it.

### Deploying for Production

The relay server can be deployed to any platform that supports Node.js and WebSockets:

1. **Deploy** the `server/` directory to your hosting provider (Render, Railway, Fly.io, a VPS, etc.)
2. **Update the game URL** — set `RELAY_SERVER_URL_DEFAULT` in `scripts/multiplayer_manager.gd` to your deployed server (e.g. `wss://your-relay.onrender.com`), or set `window.RELAY_SERVER_URL` in the HTML shell
3. **Re-export** the Godot project for HTML5

The relay server must use `wss://` (WebSocket Secure) when the game is served over HTTPS, since browsers block mixed content.

## Game Flow

```
Main Menu > PLAY > MULTIPLAYER > Create/Join/Quick Play
    |
    v
Game Lobby (configure settings, add bots, ready up)
    |
    v
Deathmatch (1-15 minutes based on room settings)
    |
    v
Scoreboard (10 seconds)
    |
    v
Back to Game Lobby (ready up for next match)
```

After a multiplayer match ends, all players return to the game lobby automatically so you can start another round without re-joining.

Practice mode (bots only, no multiplayer) returns to the main menu instead.

## Lobby Rules

- Maximum 8 players total (any mix of humans and bots)
- At least 2 players required to start (humans or bots)
- All players must be ready before the host can click START GAME
- Bots are always ready
- Only the host can add bots and start the game

## Room Codes

- 6 characters, letters and numbers (e.g. `A3X9K2`)
- Excludes confusing characters (I, O, 0, 1)
- Used to validate that joining players connect to the correct game
- Displayed in the game lobby for sharing

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Invalid URL" error in browser console | Ensure the relay server URL includes a path (e.g. `wss://host:9080/`, not `wss://host:9080`) |
| "Connection failed" | Verify the room code is correct and the host's game is still open |
| Can't connect on HTML5 | Make sure the relay server is running and reachable; check the browser console for WebSocket errors |
| Mixed content blocked | The relay must use `wss://` when the game is served over HTTPS |
| Can't connect over internet (desktop) | Host needs to port forward UDP 9999, or use a VPN/tunnel |
| Game lags | The host's connection quality affects all players since they act as the server |
| Host disconnects mid-game | The game attempts host migration to the next player automatically |
| Bots don't move | Verify the game has fully started (countdown finished) |
