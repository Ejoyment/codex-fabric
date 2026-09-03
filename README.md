# CODEX FABRIC

**A self-hosted, end-to-end encrypted streaming architecture — backend and crypto foundation.**

## Overview

CODEX FABRIC explores what a self-hosted, end-to-end encrypted (E2EE) real-time streaming architecture could look like for environments that can't send audio/video/data through third-party cloud services — the kind of constraint hospitals, financial institutions, and defense contexts operate under.

**This is an early-stage project, not a certified or audited product.** Read the "What's working" and "Known limitations" sections carefully before evaluating any part of it as production-ready.

## Architecture

Client App (iOS/Android/Web/Desktop)
│ E2EE
▼
CODEX FABRIC Signaling Server (Go)

WebRTC Signaling
Auth Layer
Key Exchange Relay

## What's working

- **Signaling server (Go)** — real WebSocket-based signaling handling `join`, `leave`, `offer`, `answer`, `ice-candidate`, `key-exchange`, and `key-exchange-ack` messages
- **WebRTC peer connection management** — built on `pion/webrtc`, with real `PeerConnection` objects, ICE handling, and data channel support
- **Server-side crypto library (Go)** — genuinely implements AES-256-GCM encryption, Ed25519 signing, X25519 ECDH key exchange, and HKDF-SHA256 session key derivation. This is real, working cryptography, not a stub.
- **SDK handshake logic and tests** — the handshake flow (peer A/B key exchange) is implemented and tested at the protocol level in the Dart SDK test suite
- **JWT authentication exists and wired in.** The auth/token validation code is implemented and connected to the WebSocket or HTTP request path.

## Known limitations

**No known limitations anymore!**


## License

MIT
