# Multiplayer Guide

## Architecture

The game uses Godot's built-in peer-to-peer multiplayer. One player acts as the **host** (server) and other players connect directly to them as **clients**. No dedicated server is required.

- **Desktop**: Uses ENet for direct P2P connections
- **Web/HTML5**: Uses WebSocket (ENet is not supported in browsers)

## How to Play

### Quick Play

1. Click **PLAY** on the main menu
2. Click **MULTIPLAYER**
3. Click **QUICK PLAY**
4. A game is created with 3 bots automatically added
5. You are auto-readied as host - click **START GAME** when ready

### Hosting a Game

1. Click **PLAY** > **MULTIPLAYER**
2. Click **CREATE GAME**
3. Share the 6-character **Room Code** with friends
4. Optionally click **ADD BOT** to fill slots with AI opponents (up to 7 total)
5. Click **READY** when you're set
6. Click **START GAME** once all players are ready

### Joining a Game

1. Click **PLAY** > **MULTIPLAYER**
2. Enter the host's **Room Code**
3. Click **JOIN GAME**
4. Click **READY** when you're set
5. Wait for the host to start the game

### Connecting on a Local Network (LAN)

Players on the same local network can connect directly. The joining player needs the host's local IP address (e.g. `192.168.1.x`). The game connects on port `9999` by default using ENet.

### Connecting Over the Internet

For internet play, the host needs to either:

- **Port forward** port `9999` (UDP) on their router to their local machine
- Use a VPN/tunnel service (e.g. ZeroTier, Tailscale, Radmin VPN) so all players appear on the same virtual LAN

## Game Flow

```
Main Menu > PLAY > MULTIPLAYER > Create/Join/Quick Play
    |
    v
Game Lobby (add bots, ready up, start game)
    |
    v
Deathmatch (5 minutes)
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
| "Connection failed" | Verify the room code is correct and the host's game is still open |
| Can't connect over internet | Host needs to port forward UDP 9999, or use a VPN/tunnel |
| Game lags | The host's connection quality affects all players since they act as the server |
| Host disconnects mid-game | The game attempts host migration to the next player automatically |
| Bots don't move | Verify the game has fully started (countdown finished) |
