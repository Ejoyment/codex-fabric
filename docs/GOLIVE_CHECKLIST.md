# CODEX Fabric — Go-Live Checklist

## Week 12: Final Security Freeze & Launch

---

## Part 1: Security Freeze

### Code Freeze Verification

- [ ] All feature branches merged to main
- [ ] No open `TODO` or `FIXME` in production code
- [ ] No hardcoded secrets, test keys, or debug logging
- [ ] All `.env` files in `.gitignore`
- [ ] Dependencies audited (`go mod verify`, `npm audit`)

### Security Audit Sign-Off

- [ ] E2EE handshake tested end-to-end (Flutter + Go)
- [ ] Penetration test script passes all 7 tests
- [ ] No private keys ever transmitted (protocol verified)
- [ ] MITM resistance validated (key substitution detection)
- [ ] Replay attack resistance confirmed (ephemeral keys)
- [ ] Input validation on all message types
- [ ] Rate limiting enabled on signaling server
- [ ] Connection limits enforced

### Cryptographic Validation

- [ ] Ed25519 signing key generation verified
- [ ] X25519 ECDH key exchange verified
- [ ] HKDF-SHA256 key derivation verified
- [ ] AES-256-GCM encryption/decryption verified
- [ ] Random nonce generation verified (no reuse)

---

## Part 2: Infrastructure Readiness

### Staging Environment

- [ ] Docker Compose deployed to staging server
- [ ] Health check endpoint responding
- [ ] WebSocket connections stable under load
- [ ] Prometheus metrics collecting
- [ ] Grafana dashboards configured
- [ ] Log aggregation working

### Production Environment

- [ ] TLS 1.3 certificate installed (WSS)
- [ ] DNS configured for signaling domain
- [ ] TURN server deployed (coturn)
- [ ] Firewall rules applied
- [ ] Backup strategy documented
- [ ] Monitoring alerts configured

### Performance Targets

| Metric | Target | Actual |
|--------|--------|--------|
| Max concurrent connections | 10,000 | ___ |
| Message latency (p95) | < 50ms | ___ |
| Key exchange latency | < 100ms | ___ |
| Server uptime | 99.9% | ___ |
| Memory per connection | < 50KB | ___ |

---

## Part 3: Documentation Complete

- [ ] Quick Start Guide (< 30 min integration verified)
- [ ] API Reference (Dart + JS + Go documented)
- [ ] Deployment Guide (Docker + manual)
- [ ] Security Architecture document
- [ ] Signaling Protocol specification
- [ ] Beta Testing Guide
- [ ] Troubleshooting section

---

## Part 4: Sales Readiness

### Demo Materials

- [ ] PoC telemedicine app deployed (`poc-app/index.html`)
- [ ] 60-second demo video recorded
- [ ] One-pager PDF created
- [ ] Pricing page finalized (Growth + Enterprise tiers)

### Target List

- [ ] 50 mid-sized companies identified (Telehealth, FinTech, Logistics)
- [ ] VP Engineering / CISO / CTO contacts sourced
- [ ] CRM populated with target accounts
- [ ] Email sequences drafted

### 14-Day PoC Process

- [ ] PoC token generation system ready
- [ ] Onboarding email template
- [ ] 14-day access portal
- [ ] Success metrics tracking

---

## Part 5: Launch Day

### Morning of Launch

- [ ] Server monitoring dashboards open
- [ ] On-call team briefed
- [ ] Support channels ready (email, Slack)
- [ ] Launch announcement queued

### Outbound Sales Begins

- [ ] First batch of 10 outreach emails sent
- [ ] LinkedIn connection requests to CISOs
- [ ] Follow-up calls scheduled

### Post-Launch Monitoring (First 24 Hours)

- [ ] Connection stability monitored
- [ ] Error rates tracked
- [ ] User feedback collected
- [ ] Any critical issues triaged immediately

---

## Sign-Off

| Role | Name | Date | Signed |
|------|------|------|--------|
| Lead Engineer | | | ☐ |
| Security Lead | | | ☐ |
| Product Owner | | | ☐ |
| DevOps | | | ☐ |