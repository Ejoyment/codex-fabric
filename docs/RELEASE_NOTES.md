# CODEX Fabric v0.1.0 — Release Notes

**Release Date:** Week 12 of MVP Sprint
**Codename:** "First Handshake"

## What is CODEX Fabric?

A self-hosted, zero-trust E2EE video and data streaming SDK for high-security enterprise environments: Healthcare, FinTech, and Defense.

## What's New in v0.1.0

### E2EE Architecture
- **Client-side key generation** — Ed25519 + X25519 key pairs generated on client devices only
- **Zero-knowledge server** — Server relays public keys; never sees private keys
- **AES-256-GCM encryption** — Authenticated encryption with random nonces
- **ECDH + HKDF** — X25519 key exchange with HKDF-SHA256 key derivation

### Signaling Server (Go)
- WebSocket signaling for WebRTC peer connections
- Room-based peer management
- E2EE key-exchange message relay
- Connection limits, rate limiting, JWT auth
- Prometheus metrics

### Flutter/Dart SDK
- Complete E2EE client (KeyManager + SecurityHandshake)
- Cross-platform: iOS, Android, Web, Desktop
- < 5 lines to integrate

### JavaScript/TypeScript SDK
- Full E2EE client for React, React Native, Node.js
- Ready for npm: `@codex-fabric/sdk`

### Security
- 7 automated penetration tests
- No private key transmission in protocol

### Documentation
- Quick Start Guide (< 30 min integration)
- API Reference (Flutter + JS + Go)
- Deployment Guide (Docker + air-gapped)
- Security Architecture document

### Demo Application
- White-labeled "SecureClinic" telemedicine UI

## Pricing

| Tier | Annual | Features |
|------|--------|----------|
| Growth | $15,000/yr | SDK access, 500 streams, public cloud |
| Enterprise | $50K-$120K+/yr | Unlimited streams, on-premise, 24/7 support |

## Known Limitations
- Crypto uses simplified placeholders (production: pointycastle/cryptography)
- Single-server deployment (no horizontal scaling yet)
- No TURN server in Docker Compose

## Next Steps
- Production-grade crypto implementations
- WebRTC data channel E2EE integration
- Horizontal scaling with Redis
- Enterprise SSO/SAML