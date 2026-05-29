/**
 * CODEX Fabric - Security Handshake
 * 
 * Orchestrates E2EE key exchange between peers.
 * Private keys NEVER leave the client device.
 */

import { KeyManager } from '../crypto/key_manager';
import { SignalingClient } from '../signaling/signaling_client';

export interface PeerKeys {
  peerId: string;
  signingPublicKey: string;
  exchangePublicKey: string;
}

export interface SessionInfo {
  peerId: string;
  peerSigningPublicKey: string;
  peerExchangePublicKey: string;
  localExchangePublicKey: string;
  establishedAt: Date;
}

export type HandshakeState = 'idle' | 'initializing' | 'ready' | 'exchanging' | 'established' | 'error';

/**
 * Manages the E2EE handshake protocol.
 * 
 * Flow:
 * 1. Each client generates key pairs locally
 * 2. Client A sends public keys to Client B via signaling server
 * 3. Client B receives, performs ECDH locally, derives session keys
 * 4. Client B sends acknowledgment back to Client A
 * 5. Client A also derives session keys independently
 * 6. Both peers now share identical session keys for AES-256-GCM encryption
 */
export class SecurityHandshake {
  private _keyManager: KeyManager;
  private _signaling: SignalingClient;
  private _state: HandshakeState = 'idle';
  private _peerKeys: Map<string, PeerKeys> = new Map();
  private _sessions: Map<string, SessionInfo> = new Map();

  onHandshakeComplete?: (peerId: string, session: SessionInfo) => void;
  onHandshakeFailed?: (peerId: string, error: string) => void;

  constructor(keyManager: KeyManager, signaling: SignalingClient) {
    this._keyManager = keyManager;
    this._signaling = signaling;
    this._setupListeners();
  }

  get state(): HandshakeState { return this._state; }

  async initialize(): Promise<void> {
    this._state = 'initializing';
    await this._keyManager.initialize();
    this._state = 'ready';
  }

  initiateKeyExchange(targetPeerId: string): void {
    if (!this._keyManager.isInitialized) throw new Error('Not initialized');
    this._state = 'exchanging';
    this._signaling.sendKeyExchange(
      targetPeerId,
      this._keyManager.signingPublicKey,
      this._keyManager.exchangePublicKey,
    );
  }

  async processKeyExchange(msg: {
    peer_id: string;
    signing_public_key: string;
    exchange_public_key: string;
  }): Promise<void> {
    if (!this._keyManager.isInitialized) throw new Error('Not initialized');

    this._peerKeys.set(msg.peer_id, {
      peerId: msg.peer_id,
      signingPublicKey: msg.signing_public_key,
      exchangePublicKey: msg.exchange_public_key,
    });

    await this._keyManager.deriveSessionKeys(msg.exchange_public_key);

    this._sessions.set(msg.peer_id, {
      peerId: msg.peer_id,
      peerSigningPublicKey: msg.signing_public_key,
      peerExchangePublicKey: msg.exchange_public_key,
      localExchangePublicKey: this._keyManager.exchangePublicKey,
      establishedAt: new Date(),
    });

    this._state = 'established';
    this._signaling.sendKeyExchangeAck(msg.peer_id, 'established');
    this.onHandshakeComplete?.call(this, msg.peer_id, this._sessions.get(msg.peer_id)!);
  }

  async processKeyExchangeAck(msg: { peer_id: string; status: string }): Promise<void> {
    if (msg.status !== 'established') {
      this._state = 'error';
      this.onHandshakeFailed?.call(this, msg.peer_id, 'Key exchange rejected');
      return;
    }

    const peerKeys = this._peerKeys.get(msg.peer_id);
    if (peerKeys) {
      await this._keyManager.deriveSessionKeys(peerKeys.exchangePublicKey);
      this._sessions.set(msg.peer_id, {
        peerId: msg.peer_id,
        peerSigningPublicKey: peerKeys.signingPublicKey,
        peerExchangePublicKey: peerKeys.exchangePublicKey,
        localExchangePublicKey: this._keyManager.exchangePublicKey,
        establishedAt: new Date(),
      });
      this._state = 'established';
      this.onHandshakeComplete?.call(this, msg.peer_id, this._sessions.get(msg.peer_id)!);
    }
  }

  encryptForPeer(plaintext: Buffer, peerId: string): Buffer {
    const peerKeys = this._peerKeys.get(peerId);
    if (!peerKeys) throw new Error(`No session with ${peerId}`);
    return this._keyManager.encrypt(plaintext, peerKeys.exchangePublicKey);
  }

  decryptFromPeer(ciphertext: Buffer, peerId: string): Buffer {
    const peerKeys = this._peerKeys.get(peerId);
    if (!peerKeys) throw new Error(`No session with ${peerId}`);
    return this._keyManager.decrypt(ciphertext, peerKeys.exchangePublicKey);
  }

  isSessionEstablished(peerId: string): boolean {
    return this._sessions.has(peerId);
  }

  clearSessions(): void {
    this._keyManager.clearSessionKeys();
    this._peerKeys.clear();
    this._sessions.clear();
    this._state = 'idle';
  }

  private _setupListeners(): void {
    this._signaling.on('key-exchange', (msg) => {
      this.processKeyExchange(msg as any);
    });
    this._signaling.on('key-exchange-ack', (msg) => {
      this.processKeyExchangeAck(msg as any);
    });
  }
}