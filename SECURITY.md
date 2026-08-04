# Security

CODEX FABRIC is an early-stage project, not a certified or audited product.

## Current status

- **Backend crypto (Go)** — real, working implementations of AES-256-GCM, Ed25519, X25519 ECDH, and HKDF-SHA256. This is genuine cryptography, not a placeholder.
- **Client SDK crypto (Flutter and JS)** — currently placeholder implementations for architecture demonstration. They do not provide real encryption yet. See the main README's "Known limitations" for details.
- **No independent security audit or penetration test has been performed.** The `tests/security/` script is a self-written smoke test, not a substitute for real review.

## Scope

This document covers the cryptographic and signaling components of CODEX FABRIC specifically. It does not cover the demo app (`poc-app/`), which is a static UI mockup with no live connections.

## Do not use this for

Real sensitive, regulated, or production data — including anything that would need HIPAA, SOC 2, GDPR, FedRAMP, or PCI DSS compliance. This project has not gone through any formal certification process.

## Reporting a vulnerability

Please open a GitHub issue. This is a solo, early-stage project, so response times are best-effort rather than guaranteed.