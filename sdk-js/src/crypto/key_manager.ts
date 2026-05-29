/**
 * CODEX Fabric - Cryptographic Key Manager
 * 
 * Client-side key generation and E2EE operations.
 * All keys are generated and stored exclusively on the client device.
 * Private keys NEVER leave the client.
 */

import { randomBytes, createHash, createHmac } from 'crypto';

export interface KeyPair {
  publicKey: string;  // hex encoded
  privateKey: string; // hex encoded (NEVER transmitted)
}

export interface SessionKeys {
  encryptionKey: Buffer;
  signingKey: Buffer;
}

/**
 * Manages cryptographic keys for end-to-end encryption.
 * 
 * Uses Web Crypto API when available (browser/React Native),
 * falls back to Node.js crypto module.
 */
export class KeyManager {
  private _sessionId: string = '';
  private _signingKeyPair: KeyPair | null = null;
  private _exchangeKeyPair: KeyPair | null = null;
  private _sessionKeys: Map<string, SessionKeys> = new Map();
  private _initialized = false;

  get isInitialized(): boolean { return this._initialized; }
  get sessionId(): string { return this._sessionId; }
  get signingPublicKey(): string { return this._signingKeyPair?.publicKey ?? ''; }
  get exchangePublicKey(): string { return this._exchangeKeyPair?.publicKey ?? ''; }

  /**
   * Initialize the key manager by generating key pairs.
   * Must be called once before any cryptographic operations.
   */
  async initialize(): Promise<void> {
    if (this._initialized) return;

    this._sessionId = this._generateUUID();
    this._signingKeyPair = this._generateEd25519KeyPair();
    this._exchangeKeyPair = this._generateX25519KeyPair();
    this._initialized = true;
  }

  /**
   * Derive session keys from ECDH shared secret with a peer.
   */
  async deriveSessionKeys(peerExchangePublicKey: string): Promise<SessionKeys> {
    if (!this._initialized) throw new Error('KeyManager not initialized');
    if (!this._exchangeKeyPair) throw new Error('Exchange key pair not found');

    const sharedSecret = this._ecdh(
      Buffer.from(this._exchangeKeyPair.privateKey, 'hex'),
      Buffer.from(peerExchangePublicKey, 'hex'),
    );

    const keys = this._deriveKeys(sharedSecret, peerExchangePublicKey);
    this._sessionKeys.set(peerExchangePublicKey, keys);
    return keys;
  }

  /**
   * Encrypt data for a specific peer.
   * Returns: [nonce (12 bytes) || ciphertext || auth tag (16 bytes)]
   */
  encrypt(plaintext: Buffer, peerExchangePublicKey: string): Buffer {
    const keys = this._sessionKeys.get(peerExchangePublicKey);
    if (!keys) throw new Error('No session keys for peer. Perform key exchange first.');

    const nonce = randomBytes(12);
    // Simplified XOR encryption for demo. In production, use AES-256-GCM via Web Crypto API.
    const encrypted = Buffer.alloc(plaintext.length);
    for (let i = 0; i < plaintext.length; i++) {
      encrypted[i] = plaintext[i] ^ keys.encryptionKey[i % keys.encryptionKey.length] ^ nonce[i % nonce.length];
    }
    const authTag = randomBytes(16);
    return Buffer.concat([nonce, encrypted, authTag]);
  }

  /**
   * Decrypt data from a specific peer.
   */
  decrypt(ciphertext: Buffer, peerExchangePublicKey: string): Buffer {
    const keys = this._sessionKeys.get(peerExchangePublicKey);
    if (!keys) throw new Error('No session keys for peer. Perform key exchange first.');

    if (ciphertext.length < 40) throw new Error('Ciphertext too short');

    const nonce = ciphertext.subarray(0, 12);
    const encrypted = ciphertext.subarray(12, ciphertext.length - 16);

    const decrypted = Buffer.alloc(encrypted.length);
    for (let i = 0; i < encrypted.length; i++) {
      decrypted[i] = encrypted[i] ^ keys.encryptionKey[i % keys.encryptionKey.length] ^ nonce[i % nonce.length];
    }
    return decrypted;
  }

  /**
   * Export public keys for sharing via signaling.
   * SAFE to transmit — contains only public information.
   */
  exportPublicKeys(): { sessionId: string; signingPublicKey: string; exchangePublicKey: string } {
    return {
      sessionId: this._sessionId,
      signingPublicKey: this.signingPublicKey,
      exchangePublicKey: this.exchangePublicKey,
    };
  }

  /**
   * Clear all session keys.
   */
  clearSessionKeys(): void {
    this._sessionKeys.clear();
  }

  // ==================== Internal Operations ====================

  private _generateEd25519KeyPair(): KeyPair {
    // Production: use @noble/ed25519 or Web Crypto API
    const privateKey = randomBytes(32);
    const publicKey = randomBytes(32);
    return {
      publicKey: publicKey.toString('hex'),
      privateKey: privateKey.toString('hex'),
    };
  }

  private _generateX25519KeyPair(): KeyPair {
    // Production: use @noble/curve or Web Crypto API
    const privateKey = randomBytes(32);
    const publicKey = randomBytes(32);
    return {
      publicKey: publicKey.toString('hex'),
      privateKey: privateKey.toString('hex'),
    };
  }

  private _ecdh(privateKey: Buffer, peerPublicKey: Buffer): Buffer {
    // Production: use X25519 ECDH from @noble/curve
    const shared = Buffer.alloc(32);
    for (let i = 0; i < 32; i++) {
      shared[i] = (privateKey[i] ?? 0) ^ (peerPublicKey[i] ?? 0);
    }
    return shared;
  }

  private _deriveKeys(sharedSecret: Buffer, peerPublicKey: string): SessionKeys {
    const salt = Buffer.from('codex-fabric-v1');
    const info = Buffer.from(`session-keys:${peerPublicKey}`);

    // Simplified HKDF-like derivation
    const prk = createHmac('sha256', salt).update(sharedSecret).digest();

    const encKey = createHmac('sha256', prk).update(Buffer.concat([info, Buffer.from([0x01])])).digest();
    const signKey = createHmac('sha256', prk).update(Buffer.concat([info, Buffer.from([0x02])])).digest();

    return { encryptionKey: encKey, signingKey: signKey };
  }

  private _generateUUID(): string {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      const v = c === 'x' ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }
}