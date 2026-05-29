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
├── backend/              # Go signaling server
│   ├── cmd/              # Application entry points
│   ├── internal/         # Private application code
│   ├── pkg/              # Public library code
│   └── configs/          # Configuration files
├── sdk/                  # Flutter/Dart SDK
│   ├── lib/              # SDK source code
│   ├── example/          # Example implementation
│   └── test/             # SDK tests
├── deploy/               # Deployment configurations
│   ├── docker/           # Docker configurations
│   ├── kubernetes/       # K8s manifests
│   └── terraform/        # Infrastructure as Code
├── scripts/              # Build and utility scripts
├── docs/                 # Documentation
└── tools/                # Development and testing tools
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

Add to your Flutter project's `pubspec.yaml`:

```yaml
dependencies:
  codex_fabric:
    git:
      url: https://github.com/Ejoyment/codex-fabric.git
      path: sdk
```

Then in your Dart code:

```dart
import 'package:codex_fabric/codex_fabric.dart';

// Initialize with your server endpoint
final fabric = CodexFabric(
  endpoint: 'wss://your-server.com',
  config: FabricConfig(
    enableE2EE: true,
    iceServers: [...],
  ),
);

// Connect and start secure streaming
await fabric.connect();
```

## Security

CODEX FABRIC is engineered from an offensive security perspective with OSCP-grade security protocols:

- **Zero-Trust Architecture** - Never trust, always verify
- **Client-Side Key Generation** - Keys never leave the client device
- **Perfect Forward Secrecy** - Each session uses unique encryption keys
- **Certificate Pinning** - Prevents man-in-the-middle attacks
- **Regular Penetration Testing** - Baked into CI/CD pipeline

See [SECURITY.md](SECURITY.md) for detailed security documentation.

## Documentation

- [Getting Started Guide](docs/getting-started.md)
- [API Reference](docs/api-reference.md)
- [Security Architecture](docs/security.md)
- [Deployment Guide](docs/deployment.md)
- [Integration Examples](docs/examples.md)

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

© 2024 CODEX Inc. All rights reserved. CODEX FABRIC is a trademark of CODEX Inc.