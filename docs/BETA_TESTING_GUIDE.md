# CODEX Fabric — Beta Testing Guide

## Overview

Week 11: External developer attempts blind integration using only the provided
documentation. Goal is to validate that integration takes < 30 minutes.

## Beta Tester Profile

- External developer (not on the CODEX team)
- Experience with WebRTC or real-time communication
- No prior knowledge of CODEX Fabric internals
- Has access to: Quick Start Guide, API Reference, SDK code

## Blind Integration Test Protocol

### Setup (5 minutes)

1. Provide beta tester with:
   - Repository access (read-only)
   - Quick Start Guide URL
   - API Reference URL
   - A running signaling server (pre-deployed)

2. Do NOT provide:
   - Architecture walkthroughs
   - Code explanations
   - Pair programming sessions

### Integration Task (25 minutes)

Ask the beta tester to complete these steps:

**Step 1: Server Connection** (5 min)
- Connect to the WebSocket signaling server
- Receive welcome message with client ID

**Step 2: Room Management** (5 min)
- Join a signaling room
- Confirm room join (receive `joined` message)

**Step 3: E2EE Handshake** (10 min)
- Generate cryptographic keys locally
- Initiate key exchange with a peer
- Complete the handshake (receive `key-exchange-ack`)
- Verify session is established

**Step 4: Encrypted Communication** (5 min)
- Encrypt a text message using session keys
- Send encrypted message to peer
- Decrypt message received from peer

### Success Criteria

| Metric | Target | Actual |
|--------|--------|--------|
| Total integration time | < 30 min | ___ min |
| Steps completed without help | 4/4 | ___/4 |
| Developer frustration (1-5) | < 2 | ___ |
| Documentation clarity (1-5) | > 4 | ___ |
| Would recommend (Y/N) | Y | ___ |

## Feedback Collection

### Questions for Beta Tester

1. **What was confusing about the documentation?**
   - 

2. **Were any API methods unclear or undocumented?**
   - 

3. **What errors did you encounter?**
   - 

4. **What would make integration faster?**
   - 

5. **Rate the overall developer experience (1-10):**
   - 

6. **Would you use this in production? Why or why not?**
   - 

## Bug Report Template

```markdown
## Bug Report

**Steps to reproduce:**
1. 
2. 
3. 

**Expected behavior:**

**Actual behavior:**

**Environment:**
- OS:
- Language/Runtime:
- SDK version:

**Severity:** [ ] Critical  [ ] Major  [ ] Minor  [ ] Cosmetic
```

## Post-Beta Actions

After beta testing is complete:

1. Fix all Critical and Major documentation issues
2. Update Quick Start Guide with any clarified steps
3. Add troubleshooting entries for common errors
4. Verify integration time meets < 30 min target
5. Sign off for Go-Live readiness