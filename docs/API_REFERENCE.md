# CODEX Fabric — API Reference

## Dart/Flutter SDK

### KeyManager

Core cryptographic key management. All keys generated and stored on client device.

```dart
class KeyManager {
  /// Initialize the key manager (generates Ed25519 + X25519 key pairs)
  Future<void> initialize();

  /// Getters
  String get sessionId;
  String get signingPublicKey;     // hex, 64 chars
  String get exchangePublicKey;    // hex, 64 chars
  bool get isInitialized;

  /// Perform ECDH key exchange and derive session keys
  Future<_SessionKeys> deriveSessionKeys(String peerExchangePublicKey);

  /// AES-256-GCM encryption/decryption
  Future<Uint8List> encrypt(Uint8List plaintext, String peerExchangePublicKey);
  Future<Uint8List> decrypt(Uint8List ciphertext, String peerExchangePublicKey);

  /// Ed25519 digital signatures
  Future<Uint8List> sign(Uint8List message);
  Future<bool> verify(Uint8List message, Uint8List signature, String signerPublicKey);

  /// Export public keys (SAFE to transmit)
  Map<String, dynamic> exportPublicKeys();

  /// Lifecycle
  void clearSessionKeys();
  void dispose();
}
```

### SecurityHandshake

Orchestrates E2EE key exchange between peers.

```dart
class SecurityHandshake {
  /// Callbacks
  void Function(String peerId, SessionInfo session)? onHandshakeComplete;
  void Function(String peerId, String error)? onHandshakeFailed;

  /// Initialize (generates keys locally)
  Future<void> initialize();

  /// Initiate key exchange with a peer
  Future<KeyExchangeMessage> createKeyExchangeMessage(String targetPeerId);

  /// Process incoming key exchange from a peer
  Future<KeyExchangeAckMessage> processKeyExchangeMessage(KeyExchangeMessage message);

  /// Process key exchange acknowledgment
  Future<void> processKeyExchangeAck(KeyExchangeAckMessage ack);

  /// Encrypt/decrypt per peer
  Future<Uint8List> encryptForPeer(Uint8List plaintext, String peerId);
  Future<Uint8List> decryptFromPeer(Uint8List ciphertext, String peerId);

  /// Sign/verify
  Future<Uint8List> signData(Uint8List data);
  Future<bool> verifyPeerSignature(Uint8List data, Uint8List signature, String peerId);

  /// Session management
  bool isSessionEstablished(String peerId);
  SessionInfo? getSessionInfo(String peerId);
  void clearSessions();
  void dispose();
}
```

### SessionInfo

```dart
class SessionInfo {
  final String peerId;
  final String peerSigningPublicKey;
  final String peerExchangePublicKey;
  final String localExchangePublicKey;
  final DateTime establishedAt;
  Duration get uptime;
}
```

---

## JavaScript/TypeScript SDK

### KeyManager

```typescript
class KeyManager {
  get isInitialized(): boolean;
  get sessionId(): string;
  get signingPublicKey(): string;    // hex, 64 chars
  get exchangePublicKey(): string;   // hex, 64 chars

  initialize(): Promise<void>;
  deriveSessionKeys(peerExchangePublicKey: string): Promise<SessionKeys>;
  encrypt(plaintext: Buffer, peerExchangePublicKey: string): Buffer;
  decrypt(ciphertext: Buffer, peerExchangePublicKey: string): Buffer;
  exportPublicKeys(): { sessionId: string; signingPublicKey: string; exchangePublicKey: string };
  clearSessionKeys(): void;
}
```

### SecurityHandshake

```typescript
class SecurityHandshake {
  onHandshakeComplete?: (peerId: string, session: SessionInfo) => void;
  onHandshakeFailed?: (peerId: string, error: string) => void;

  get state(): HandshakeState;

  initialize(): Promise<void>;
  initiateKeyExchange(targetPeerId: string): void;
  processKeyExchange(msg: { peer_id: string; signing_public_key: string; exchange_public_key: string }): Promise<void>;
  processKeyExchangeAck(msg: { peer_id: string; status: string; signing_public_key?: string; exchange_public_key?: string }): Promise<void>;
  encryptForPeer(plaintext: Buffer, peerId: string): Buffer;
  decryptFromPeer(ciphertext: Buffer, peerId: string): Buffer;
  isSessionEstablished(peerId: string): boolean;
  clearSessions(): void;
}
```

### SignalingClient

```typescript
class SignalingClient {
  get clientId(): string;
  get connected(): boolean;

  constructor(config: SignalingConfig);

  connect(): Promise<void>;
  joinRoom(roomId: string): Promise<void>;
  sendKeyExchange(targetPeerId: string, signingPublicKey: string, exchangePublicKey: string): void;
  sendKeyExchangeAck(targetPeerId: string, status: string): void;
  send(msg: SignalingMessage): void;
  on(type: string, handler: (msg: SignalingMessage) => void): void;
  onState(handler: (state: string) => void): void;
  disconnect(): void;
}
```

### SignalingConfig

```typescript
interface SignalingConfig {
  url: string;                    // WebSocket server URL
  roomId: string;                 // Room to join
  peerId?: string;                // Optional peer ID
  reconnectAttempts?: number;     // Default: 5
  reconnectDelay?: number;        // Default: 1000ms
}
```

---

## Go Backend

### Signaling Server

```go
// Server manages WebSocket connections and signaling
type Server struct {
    // Configurable via config.yaml
}

// NewServer creates a new signaling server
func NewServer(cfg config.SignalingConfig, webrtcMgr *webrtc.Manager, logger *zap.Logger) (*Server, error)

// HandleWebSocket handles incoming WebSocket connections
func (s *Server) HandleWebSocket(w http.ResponseWriter, r *http.Request)

// GetStats returns server statistics
func (s *Server) GetStats() map[string]interface{}
```

### Crypto Package

```go
// GenerateKeyPair generates a new Ed25519 key pair
func GenerateKeyPair() (*KeyPair, error)

// ECDH performs X25519 key exchange
func ECDH(privateKey, peerPublicKey []byte) ([]byte, error)

// GenerateSessionKeys creates session keys using HKDF
func GenerateSessionKeys(sharedSecret []byte, info []byte) (*SessionKeys, error)

// Encrypt/Decrypt using AES-256-GCM
func Encrypt(plaintext, key []byte) ([]byte, error)
func Decrypt(ciphertext, key []byte) ([]byte, error)

// Sign/Verify using Ed25519
func Sign(message []byte, privateKey ed25519.PrivateKey) []byte
func Verify(message, signature []byte, publicKey ed25519.PublicKey) bool
```

---

## WebSocket Protocol

### Client → Server

| Type | Required Fields | Description |
|------|----------------|-------------|
| `join` | `room_id`, `peer_id` | Join a signaling room |
| `leave` | `room_id` | Leave a room |
| `offer` | `room_id`, `peer_id`, `sdp` | Send WebRTC offer |
| `answer` | `room_id`, `peer_id`, `sdp` | Send WebRTC answer |
| `ice-candidate` | `room_id`, `peer_id`, `candidate` | Send ICE candidate |
| `key-exchange` | `peer_id`, `signing_public_key`, `exchange_public_key` | Initiate E2EE handshake |
| `key-exchange-ack` | `peer_id`, `status`, `signing_public_key`, `exchange_public_key` | Acknowledge key exchange with responder's public keys |
| `ping` | — | Keep-alive |

### Server → Client

| Type | Fields | Description |
|------|--------|-------------|
| `welcome` | `id` | Client ID assigned |
| `joined` | `room_id`, `peer_id` | Room join confirmed |
| `ready` | `peer_id` | New peer in room |
| `offer`/`answer`/`ice-candidate` | `peer_id`, content | Relayed from peer |
| `key-exchange` | `peer_id`, `signing_public_key`, `exchange_public_key` | Relay from peer |
| `key-exchange-ack` | `peer_id`, `status`, `signing_public_key`, `exchange_public_key` | Relay from peer |
| `pong` | — | Pong response |
| `error` | `error` | Error message |
| `disconnect` | `peer_id`, `room_id` | Peer disconnected |