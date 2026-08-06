# CODEX FABRIC

**A self-hosted, end-to-end encrypted streaming architecture — backend and crypto foundation, with SDKs still in progress.**

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

- **Flutter SDK crypto is placeholder, not production-grade.** It defines the correct API shape but uses simplified crypto operations for architecture demonstration. Comments in the code note that production use requires real libraries (`pointycastle`, `cryptography`, `ed25519_edwards`) — this hasn't been done yet.
- **JS SDK crypto is also placeholder.** It currently generates fake keys and uses XOR instead of real encryption. This needs to be replaced with the Web Crypto API or a real crypto library (e.g. `@noble/ed25519`) before any client can safely rely on it.
- **The demo app (`poc-app/`) is a static UI mockup**, not a working connected application — it doesn't currently load the SDK or make real signaling/WebRTC connections.
- **No independent security audit has been performed.** The included penetration test script is a self-written smoke test with several hardcoded pass conditions, not a substitute for real audit or certification.
- **Not compliant with HIPAA, SOC 2, GDPR, FedRAMP, or PCI DSS.** These require formal certification processes this project hasn't gone through. Don't use this for regulated data.

## Roadmap

- Replace Flutter and JS SDK crypto with real implementations
- Wire JWT auth into the signaling server request path
- Connect `poc-app` to a real, working SDK integration
- Independent security review before any production consideration

## License

MIT
