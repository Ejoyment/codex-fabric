# CODEX Fabric Signaling Protocol

## Overview

The CODEX Fabric Signaling Protocol is a WebSocket-based protocol for establishing peer-to-peer WebRTC connections between clients. It handles the exchange of SDP offers/answers and ICE candidates required for WebRTC peer connection establishment.

## Connection

Clients connect to the signaling server via WebSocket:

```
ws:// signaling-server:8080/ws
```

## Message Format

All messages are JSON-encoded with the following base structure:

```json
{
  "type": "message_type",
  "id": "client_id",
  "room_id": "room_identifier",
  "peer_id": "target_peer_id",
  "sdp": { "type": "offer/answer", "sdp": "..." },
  "candidate": { "candidate": "...", "sdpMid": "0", "sdpMLineIndex": 0 },
  "error": "error_message",
  "message": "info_message",
  "timestamp": 1234567890
}
```

## Message Types

### Client → Server Messages

#### 1. Join Room
Request to join a signaling room.

```json
{
  "type": "join",
  "room_id": "room-123",
  "peer_id": "my-peer-id"
}
```

#### 2. Leave Room
Request to leave the current room.

```json
{
  "type": "leave",
  "room_id": "room-123"
}
```

#### 3. Offer
Send a WebRTC offer to a peer.

```json
{
  "type": "offer",
  "room_id": "room-123",
  "peer_id": "target-peer-id",
  "sdp": {
    "type": "offer",
    "sdp": "v=0\r\no=- ..."
  }
}
```

#### 4. Answer
Send a WebRTC answer to a peer.

```json
{
  "type": "answer",
  "room_id": "room-123",
  "peer_id": "target-peer-id",
  "sdp": {
    "type": "answer",
    "sdp": "v=0\r\no=- ..."
  }
}
```

#### 5. ICE Candidate
Send an ICE candidate to a peer.

```json
{
  "type": "ice-candidate",
  "room_id": "room-123",
  "peer_id": "target-peer-id",
  "candidate": {
    "candidate": "candidate:12345 ...",
    "sdpMid": "0",
    "sdpMLineIndex": 0
  }
}
```

#### 6. Ping
Keep-alive ping message.

```json
{
  "type": "ping"
}
```

#### 7. Key Exchange (E2EE Handshake)
Initiate end-to-end encryption key exchange with a peer. This message contains
the sender's public keys for establishing E2EE. Only public keys are transmitted;
private keys NEVER leave the client device.

```json
{
  "type": "key-exchange",
  "peer_id": "target-peer-id",
  "signing_public_key": "a1b2c3d4e5f6...",
  "exchange_public_key": "f6e5d4c3b2a1...",
  "signature": "optional_signature_for_authentication"
}
```

**Fields:**
- `signing_public_key`: Ed25519 public key for signature verification (hex encoded, 64 chars)
- `exchange_public_key`: X25519 public key for ECDH key exchange (hex encoded, 64 chars)
- `signature`: Optional Ed25519 signature for authentication

### Server → Client Messages

#### 1. Welcome
Sent immediately upon connection. Contains the client's unique ID.

```json
{
  "type": "welcome",
  "id": "client-uuid-1234",
  "timestamp": 1234567890
}
```

#### 2. Joined
Confirmation that the client has joined a room.

```json
{
  "type": "joined",
  "room_id": "room-123",
  "peer_id": "client-uuid-1234",
  "timestamp": 1234567890
}
```

#### 3. Ready
Notification that another peer has joined the room.

```json
{
  "type": "ready",
  "peer_id": "new-peer-uuid",
  "timestamp": 1234567890
}
```

#### 4. Offer/Answer/ICE Candidate
Forwarded messages from other peers.

```json
{
  "type": "offer",
  "peer_id": "sender-peer-uuid",
  "sdp": { "type": "offer", "sdp": "..." },
  "timestamp": 1234567890
}
```

#### 5. Disconnect
Notification that a peer has disconnected.

```json
{
  "type": "disconnect",
  "peer_id": "disconnected-peer-uuid",
  "room_id": "room-123",
  "timestamp": 1234567890
}
```

#### 6. Pong
Response to ping message.

```json
{
  "type": "pong",
  "timestamp": 1234567890
}
```

#### 7. Error
Error message.

```json
{
  "type": "error",
  "error": "error description",
  "timestamp": 1234567890
}
```

## Connection Flow

### Typical Peer-to-Peer Connection Flow

```
Client A                           Server                          Client B
    |                                |                                |
    |---------- WebSocket ---------->|                                |
    |<--------- Welcome -------------|                                |
    |                                |                                |
    |-------- Join Room ------------>|                                |
    |<-------- Joined ----------------|                                |
    |                                |                                |
    |                                |<-------- WebSocket -----------|
    |                                |-------- Welcome ------------->|
    |                                |                                |
    |                                |<-------- Join Room -----------|
    |<-------- Ready (B joined) -----|-------- Joined ------------->|
    |                                |                                |
    |-------- Offer (to B) --------->|                                |
    |                                |-------- Offer (from A) ------>|
    |                                |                                |
    |                                |<-------- Answer (from B) ----|
    |<-------- Answer (from B) ------|                                |
    |                                |                                |
    |-------- ICE Candidate ------->|                                |
    |                                |-------- ICE Candidate ------->|
    |                                |                                |
    |<------- ICE Candidate --------|                                |
    |                                |<------- ICE Candidate -------|
    |                                |                                |
    |<============= Direct P2P Connection Established ==============>|
```

## Room Management

- Rooms are created automatically when the first client joins
- Rooms are deleted when the last client leaves
- Clients can only communicate with other clients in the same room
- A client can only be in one room at a time

## Security Considerations

1. **Authentication**: Optional JWT-based authentication can be enabled
2. **CORS**: Origin validation is performed based on configured allowed origins
3. **Rate Limiting**: Connection limits can be configured per server
4. **TLS**: Production deployments should use WSS (WebSocket Secure)

## Configuration

Key configuration options in `config.yaml`:

```yaml
signaling:
  allowed_origins:
    - "https://your-domain.com"
  max_message_size: 1048576  # 1MB
  handshake_timeout: "10s"
  ping_interval: "30s"
  pong_wait: "60s"
  max_connections: 10000
  enable_compression: true

webrtc:
  stun_servers:
    - "stun:stun.l.google.com:19302"
  turn_servers:
    - url: "turn:your-turn-server:5349"
      username: "user"
      password: "password"
  enable_turn: true
  connection_timeout: "30s"
  enable_data_channel: true
```

## Error Codes

| Error | Description |
|-------|-------------|
| `room_id is required` | Room ID not provided in join message |
| `room not found` | Specified room doesn't exist |
| `peer not found in room` | Target peer not in the room |
| `unknown message type` | Invalid message type received |
| `Server at capacity` | Maximum connections reached |

## Best Practices

1. **Always handle reconnection**: Implement automatic reconnection with exponential backoff
2. **Use ping/pong**: Keep connections alive with periodic ping messages
3. **Clean up resources**: Always leave rooms and close connections properly
4. **Handle errors gracefully**: Implement proper error handling for all message types
5. **Validate SDP**: Validate SDP content before sending to prevent malformed offers/answers

## Example Implementation

See the Flutter SDK implementation in `sdk/lib/src/signaling/signaling_client.dart` for a complete client implementation example.