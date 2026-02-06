/**
 * Godot 4.x WebSocket Multiplayer Relay Server
 *
 * Implements the Godot WebSocketMultiplayerPeer binary protocol so that
 * HTML5 (Emscripten) clients can communicate in peer-to-peer style through
 * this central relay.
 *
 * Protocol (binary WebSocket frames):
 *   System messages (server → client, 5 bytes):
 *     [uint8 type] [uint32 LE peer_id]
 *     type 1 = SYS_ADD  (a peer joined)
 *     type 2 = SYS_DEL  (a peer left)
 *     type 3 = SYS_ID   (your assigned peer id)
 *
 *   Data messages (client → server → client(s), ≥9 bytes):
 *     [uint32 LE source] [uint32 LE dest] [uint8 channel] [payload…]
 *     dest=0 means broadcast to all peers in the room (except source).
 *     dest=1 means the message is for the host (peer 1).
 *     dest=N means forward to that specific peer.
 *
 * Query parameters on the connection URL:
 *   room  – room code (required)
 *   host  – if "true", this client becomes the host (peer ID 1)
 */

const { WebSocketServer } = require("ws");
const url = require("url");

const PORT = parseInt(process.env.PORT, 10) || 9080;

// Map<roomCode, { host: ws|null, nextPeerId: int, peers: Map<peerId, ws> }>
const rooms = new Map();

const SYS_ADD = 1;
const SYS_DEL = 2;
const SYS_ID = 3;

function makeSysPacket(type, peerId) {
  const buf = Buffer.alloc(5);
  buf.writeUInt8(type, 0);
  buf.writeUInt32LE(peerId, 1);
  return buf;
}

function readUInt32LE(data, offset) {
  return (
    (data[offset]) |
    (data[offset + 1] << 8) |
    (data[offset + 2] << 16) |
    ((data[offset + 3] << 24) >>> 0)
  ) >>> 0;
}

const wss = new WebSocketServer({ port: PORT });

console.log(`Godot WebSocket relay server listening on port ${PORT}`);

wss.on("connection", (ws, req) => {
  const params = new URL(req.url, `http://${req.headers.host}`).searchParams;
  const roomCode = params.get("room");
  const isHost = params.get("host") === "true";

  if (!roomCode) {
    console.log("Connection rejected: no room code");
    ws.close(4000, "Missing room parameter");
    return;
  }

  // Get or create room
  if (!rooms.has(roomCode)) {
    rooms.set(roomCode, { host: null, nextPeerId: 2, peers: new Map() });
  }
  const room = rooms.get(roomCode);

  // Assign peer ID
  let peerId;
  if (isHost) {
    if (room.host) {
      console.log(`Room ${roomCode}: host already exists, rejecting`);
      ws.close(4001, "Room already has a host");
      return;
    }
    peerId = 1;
    room.host = ws;
  } else {
    if (!room.host) {
      console.log(`Room ${roomCode}: no host yet, rejecting joiner`);
      ws.close(4002, "Room has no host");
      return;
    }
    peerId = room.nextPeerId++;
  }

  ws._peerId = peerId;
  ws._roomCode = roomCode;

  console.log(
    `Room ${roomCode}: peer ${peerId} connected (${isHost ? "host" : "client"})`
  );

  // 1) Tell the new client its peer ID
  ws.send(makeSysPacket(SYS_ID, peerId));

  // 2) Tell existing peers about the new peer
  for (const [existingId, existingWs] of room.peers) {
    if (existingWs.readyState === 1) {
      existingWs.send(makeSysPacket(SYS_ADD, peerId));
    }
  }

  // 3) Tell the new peer about all existing peers
  for (const [existingId] of room.peers) {
    ws.send(makeSysPacket(SYS_ADD, existingId));
  }

  // 4) Add to room
  room.peers.set(peerId, ws);

  // Handle incoming data
  ws.on("message", (data) => {
    if (!(data instanceof Buffer)) {
      data = Buffer.from(data);
    }

    // System messages from client are 5 bytes – ignore them (client-side bookkeeping)
    if (data.length === 5 && data[0] >= SYS_ADD) {
      return;
    }

    // Data packet: [source(4)] [dest(4)] [channel(1)] [payload...]
    if (data.length < 9) return;

    const dest = readUInt32LE(data, 4);

    if (dest === 0) {
      // Broadcast to all peers in the room except the sender
      for (const [id, peer] of room.peers) {
        if (id !== peerId && peer.readyState === 1) {
          peer.send(data);
        }
      }
    } else {
      // Forward to specific peer
      const target = room.peers.get(dest);
      if (target && target.readyState === 1) {
        target.send(data);
      }
    }
  });

  // Handle disconnect
  ws.on("close", () => {
    console.log(`Room ${roomCode}: peer ${peerId} disconnected`);

    room.peers.delete(peerId);

    // Notify remaining peers
    for (const [, peer] of room.peers) {
      if (peer.readyState === 1) {
        peer.send(makeSysPacket(SYS_DEL, peerId));
      }
    }

    // Clean up host reference
    if (peerId === 1) {
      room.host = null;
    }

    // Remove empty rooms
    if (room.peers.size === 0) {
      rooms.delete(roomCode);
      console.log(`Room ${roomCode}: empty, removed`);
    }
  });

  ws.on("error", (err) => {
    console.error(`Room ${roomCode}: peer ${peerId} error:`, err.message);
  });
});
