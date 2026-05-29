# CODEX Fabric — Quick Start Guide

**Integration time: < 30 minutes**

## Prerequisites

- Go 1.21+ (for the signaling server)
- Flutter 3.10+ or Node.js 18+ (for the client SDK)
- Docker (for deployment)

## Step 1: Run the Signaling Server (2 minutes)

```bash
git clone https://github.com/Ejoyment/codex-fabric.git
cd codex-fabric/backend
go build -o codex-server ./cmd/server
./codex-server
```

The server starts on `ws://localhost:8080/ws`.

## Step 2: Install the SDK (3 minutes)

### Option A: Flutter/Dart SDK

```bash
cd codex-fabric/sdk
flutter pub add codex_fabric
```

### Option B: JavaScript/TypeScript SDK

```bash
cd codex-fabric/sdk-js
npm install @codex-fabric/sdk
```

## Step 3: Connect to the Server (5 minutes)

### Flutter/Dart

```dart
import 'package:codex_fabric/codex_fabric.dart';

final fabric = CodexFabric();
await fabric.initialize();
await fabric.connect(url: 'ws://localhost:8080/ws');
await fabric.joinRoom('my-secure-room');
```

### JavaScript/TypeScript

```typescript
import { SignalingClient, SecurityHandshake, KeyManager } from '@codex-fabric/sdk';

const keyManager = new KeyManager();
const signaling = new SignalingClient({
  url: 'ws://localhost:8080/ws',
  roomId: 'my-secure-room',
});

await signaling.connect();
await signaling.joinRoom('my-secure-room');
```

## Step 4: Establish E2EE Session (5 minutes)

### Flutter/Dart

```dart
final handshake = SecurityHandshake(keyManager: KeyManager());
await handshake.initialize();

handshake.onHandshakeComplete = (peerId, session) {
  print('E2EE established with $peerId');
};

handshake.initiateKeyExchange('peer-id-from-ready-event');
```

### JavaScript/TypeScript

```typescript
const handshake = new SecurityHandshake(keyManager, signaling);
await handshake.initialize();

handshake.onHandshakeComplete = (peerId, session) => {
  console.log(`E2EE established with ${peerId}`);
};

handshake.initiateKeyExchange('peer-id-from-ready-event');
```

## Step 5: Send Encrypted Data (5 minutes)

### Flutter/Dart

```dart
import 'dart:convert';
import 'dart:typed_data';

final plaintext = utf8.encode('Secret message');
final ciphertext = await handshake.encryptForPeer(
  Uint8List.fromList(plaintext), 'peer-id',
);
```

### JavaScript/TypeScript

```typescript
const plaintext = Buffer.from('Secret message');
const ciphertext = handshake.encryptForPeer(plaintext, 'peer-id');
```

## Step 6: Decrypt Received Data (5 minutes)

### Flutter/Dart

```dart
final decrypted = await handshake.decryptFromPeer(
  Uint8List.fromList(receivedCiphertext), 'sender-peer-id',
);
print('Decrypted: ${utf8.decode(decrypted)}');
```

### JavaScript/TypeScript

```typescript
const decrypted = handshake.decryptFromPeer(
  Buffer.from(receivedCiphertext), 'sender-peer-id',
);
console.log('Decrypted:', decrypted.toString());
```

## What Just Happened?

1. Your client generated Ed25519 + X25519 key pairs locally
2. Public keys were exchanged via the signaling server
3. Each peer independently performed ECDH to derive shared session keys
4. Session keys were derived using HKDF-SHA256
5. Data is encrypted with AES-256-GCM

**The server never saw private keys or session keys.**

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "KeyManager not initialized" | Call `initialize()` before any crypto operations |
| "No session keys for peer" | Complete the key exchange handshake first |
| WebSocket connection refused | Ensure the Go server is running on the correct port |
| "peer not found in room" | Both peers must join the same room before key exchange |