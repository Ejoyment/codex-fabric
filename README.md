# CODEX FABRIC

**Self-Hosted, Zero-Trust Video & Data Streaming SDK for High-Security Enterprise Environments**

[![License: MIT](https://img.shields.io/badge/License-Enterprise-blue.svg)](LICENSE)
[![Go Report Card](https://goreportcard.com/badge/github.com/Ejoyment/codex-fabric/backend)](https://goreportcard.com/report/github.com/Ejoyment/codex-fabric/backend)
[![Security Audit](https://img.shields.io/badge/Security-OSCP--Grade-brightgreen.svg)](SECURITY.md)

## Overview

CODEX FABRIC is a self-hosted, end-to-end encrypted (E2EE) streaming infrastructure designed exclusively for high-security enterprise environments including Healthcare, FinTech, and Defense sectors.

### The Problem

Enterprises are bleeding sensitive data through third-party cloud communication APIs. Standard cloud APIs are vulnerable to interception and compliance breaches, putting patient data, financial information, and classified communications at risk.

### The Solution

CODEX FABRIC allows enterprises to host their own zero-trust streaming infrastructure, ensuring:

- **100% Data Sovereignty** - All data remains within your controlled infrastructure
- **End-to-End Encryption** - Cryptographic keys are generated and stored exclusively on client devices
- **Regulatory Compliance** - Built for HIPAA, SOC2, GDPR, and FedRAMP requirements
- **Ultra-Low Latency** - Go-powered backend handling thousands of concurrent WebRTC connections

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Client App    │    │   Client App    │    │   Client App    │
│  (iOS/Android)  │    │     (Web)       │    │  (Desktop)      │
│                 │    │                 │    │                 │
│  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │
│  │  Flutter  │  │    │  │  Flutter  │  │    │  │  Flutter  │  │
│  │    SDK    │  │    │  │    SDK    │  │    │  │    SDK    │  │
│  └─────┬─────┘  │    │  └─────┬─────┘  │    │  └─────┬─────┘  │
└────────┼────────┘    └────────┼────────┘    └────────┼────────┘
         │                      │                      │
         │         E2EE         │         E2EE         │
         │                      │                      │
         ▼                      ▼                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                        CODEX FABRIC                              │
│                     Signaling Server (Go)                        │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │   WebRTC    │  │    Auth     │  │   Anomaly   │              │
│  │  Signaling  │  │   Layer     │  │  Detection  │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
└─────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
codex-fabric/
├── backend/                    # Go signaling server
│   ├── cmd/server/             # Application entry point
│   ├── internal/signaling/     # WebSocket signaling + E2EE relay
│   ├── internal/webrtc/        # WebRTC connection management
│   ├── internal/auth/          # JWT authentication
│   ├── pkg/crypto/             # Server-side crypto (AES-GCM, Ed25519, X25519, HKDF)
│   └── config.yaml             # Server configuration
├── sdk/                        # Flutter/Dart SDK (iOS, Android, Web, Desktop)
│   ├── lib/src/crypto/         # E2EE key management + handshake
│   ├── lib/src/signaling/      # WebSocket signaling client
│   ├── lib/src/webrtc/         # WebRTC peer connections
│   └── test/crypto/            # E2EE integration tests
├── sdk-js/                     # JavaScript/TypeScript SDK (React, React Native, Node.js)
│   └── src/                    # Crypto, signaling, and handshake modules
├── poc-app/                    # White-labeled telemedicine demo app
├── tests/
│   ├── load/                   # Python load testing suite
│   └── security/               # Security audit / penetration tests
├── docs/                       # Documentation
│   ├── QUICKSTART.md           # < 30 min integration guide
│   ├── API_REFERENCE.md        # Flutter + JS + Go API docs
│   ├── DEPLOYMENT.md           # Docker + air-gapped deployment
│   ├── E2EE_SECURITY_ARCHITECTURE.md
│   ├── SIGNALING_PROTOCOL.md
│   ├── BETA_TESTING_GUIDE.md
│   ├── GOLIVE_CHECKLIST.md
│   ├── SALES_OUTREACH_TEMPLATES.md
│   └── RELEASE_NOTES.md
└── .github/workflows/ci.yml   # CI/CD pipeline
```

## Quick Start

### Prerequisites

- Go 1.21+
- Flutter 3.x+
- Docker & Docker Compose
- OpenSSL 3.x+

### Running the Backend

```bash
cd backend
go mod download
go run cmd/server/main.go
```

### Integrating the SDK

**Flutter/Dart** — Add to your `pubspec.yaml`:

```yaml
dependencies:
  codex_fabric:
    git:
      url: https://github.com/Ejoyment/codex-fabric.git
      path: sdk
```

```dart
import 'package:codex_fabric/codex_fabric.dart';

final handshake = SecurityHandshake(keyManager: KeyManager());
await handshake.initialize();
await handshake.initiateKeyExchange('peer-id');
```

**JavaScript/TypeScript** — `npm install @codex-fabric/sdk`:

```typescript
import { KeyManager, SecurityHandshake, SignalingClient } from '@codex-fabric/sdk';

const km = new KeyManager();
const signaling = new SignalingClient({ url: 'wss://your-server.com', roomId: 'room-1' });
const handshake = new SecurityHandshake(km, signaling);
await handshake.initialize();
handshake.initiateKeyExchange('peer-id');
```

See [Quick Start Guide](docs/QUICKSTART.md) for the full 30-minute walkthrough.

## Security

CODEX FABRIC is engineered from an offensive security perspective with OSCP-grade security protocols:

- **Zero-Trust Architecture** - Never trust, always verify
- **Client-Side Key Generation** - Keys never leave the client device
- **Perfect Forward Secrecy** - Each session uses unique encryption keys
- **Certificate Pinning** - Prevents man-in-the-middle attacks
- **Regular Penetration Testing** - Baked into CI/CD pipeline

See [SECURITY.md](SECURITY.md) for detailed security documentation.

## Documentation

- [Quick Start Guide](docs/QUICKSTART.md) — < 30 minute integration
- [API Reference](docs/API_REFERENCE.md) — Flutter + JS + Go
- [E2EE Security Architecture](docs/E2EE_SECURITY_ARCHITECTURE.md)
- [Signaling Protocol](docs/SIGNALING_PROTOCOL.md)
- [Deployment Guide](docs/DEPLOYMENT.md) — Docker, air-gapped, systemd
- [Security Audit](docs/SECURITY.md) — Penetration test results
- [Beta Testing Guide](docs/BETA_TESTING_GUIDE.md)
- [Go-Live Checklist](docs/GOLIVE_CHECKLIST.md)
- [Sales Outreach Templates](docs/SALES_OUTREACH_TEMPLATES.md)
- [Release Notes](docs/RELEASE_NOTES.md)

## Pricing & Licensing

CODEX FABRIC is a commercial enterprise product. See [PRICING.md](PRICING.md) for details.

| Tier | Annual Pricing | Features |
|------|----------------|----------|
| Growth | $15,000/year | Up to 500 active streams, Public cloud deployment |
| Enterprise | $50,000-$120,000+/year | Unlimited streams, On-Premise/Air-gapped deployment |

## Support

Enterprise customers receive dedicated support:

- **Growth Tier**: Standard business hours support
- **Enterprise Tier**: 24/7 dedicated support with 15-minute SLA

Contact: security@codex.inc

## Compliance

CODEX FABRIC is designed to help enterprises meet:

- **HIPAA** - Healthcare data protection
- **SOC 2 Type II** - Security, availability, and confidentiality
- **GDPR** - EU data protection regulation
- **FedRAMP** - US government cloud security (Enterprise tier)
- **PCI DSS** - Payment card industry data security

## Contributing

CODEX FABRIC is a commercial product. External contributions are accepted under our CLA process. Please contact opensource@codex.inc for contribution guidelines.

## License

Proprietary enterprise software. See [LICENSE](LICENSE) for terms.

---

**v0.1.0 "First Handshake"** — 12-week MVP complete. See [Release Notes](docs/RELEASE_NOTES.md).

© 2024 CODEX INC ENTERPRISE. All rights reserved. CODEX FABRIC is a trademark of CODEX Inc.
