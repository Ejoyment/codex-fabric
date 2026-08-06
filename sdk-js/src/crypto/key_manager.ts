/**
 * CODEX Fabric - Cryptographic Key Manager
 * 
 * Client-side key generation and E2EE operations.
 * All keys are generated and stored exclusively on the client device.
 * Private keys NEVER leave the client.
 * 
 * Uses Node.js's built-in crypto module for all primitives:
 * - Ed25519 for signing and verification
 * - X25519 for ECDH key agreement
 * - AES-256-GCM for authenticated encryption
 * - HKDF-SHA256 for session key derivation
 */

import {
  createCipheriv,
  createDecipheriv,
  createPrivateKey,
  createPublicKey,
  diffieHellman,
  generateKeyPairSync,
  hkdfSync,
  randomBytes,
  randomUUID,
  sign,
  verify,
  type JsonWebKey as NodeJsonWebKey,
} from 'crypto';

export interface KeyPair {
  publicKey: string;  // hex encoded
  privateKey: string; // hex encoded (NEVER transmitted)
}

export interface SessionKeys {
  encryptionKey: Buffer;
  signingKey: Buffer;
}

type OkpCurve = 'Ed25519' | 'X25519';

/** Build an OKP JWK containing a private key. */
function privateJwk(crv: OkpCurve, privateBytes: Buffer, publicBytes: Buffer): NodeJsonWebKey {
  return {
    kty: 'OKP',
    crv,
    d: privateBytes.toString('base64url'),
    x: publicBytes.toString('base64url'),
  };
}

/** Build an OKP JWK containing only a public key. */
function publicJwk(crv: OkpCurve, publicBytes: Buffer): NodeJsonWebKey {
  return {
    kty: 'OKP',
    crv,
    x: publicBytes.toString('base64url'),
  };
}

/**
 * Manages cryptographic keys for end-to-end encryption.
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

    this._sessionId = randomUUID();
    this._signingKeyPair = this._generateKeyPair('ed25519');
    this._exchangeKeyPair = this._generateKeyPair('x25519');
    this._initialized = true;
  }

  /**
   * Derive session keys from ECDH shared secret with a peer.
   */
  async deriveSessionKeys(peerExchangePublicKey: string): Promise<SessionKeys> {
    if (!this._initialized) throw new Error('KeyManager not initialized');
    if (!this._exchangeKeyPair) throw new Error('Exchange key pair not found');

    const sharedSecret = this._ecdh(this._exchangeKeyPair, peerExchangePublicKey);

    const keys = this._deriveKeys(sharedSecret, this._exchangeKeyPair.publicKey, peerExchangePublicKey);
    this._sessionKeys.set(peerExchangePublicKey, keys);
    return keys;
  }

  /**
   * Encrypt data for a specific peer using AES-256-GCM.
   * Returns: [nonce (12 bytes) || ciphertext || auth tag (16 bytes)]
   */
  encrypt(plaintext: Buffer, peerExchangePublicKey: string): Buffer {
    const keys = this._sessionKeys.get(peerExchangePublicKey);
    if (!keys) throw new Error('No session keys for peer. Perform key exchange first.');

    return this._aesGcmEncrypt(plaintext, keys.encryptionKey);
  }

  /**
   * Decrypt data from a specific peer using AES-256-GCM.
   * Expects: [nonce (12 bytes) || ciphertext || auth tag (16 bytes)]
   */
  decrypt(ciphertext: Buffer, peerExchangePublicKey: string): Buffer {
    const keys = this._sessionKeys.get(peerExchangePublicKey);
    if (!keys) throw new Error('No session keys for peer. Perform key exchange first.');

    return this._aesGcmDecrypt(ciphertext, keys.encryptionKey);
  }

  /**
   * Sign a message using the local Ed25519 signing key.
   * Returns a 64-byte signature.
   */
  async sign(message: Buffer): Promise<Buffer> {
    if (!this._signingKeyPair) throw new Error('KeyManager not initialized');

    const key = createPrivateKey({
      key: privateJwk(
        'Ed25519',
        Buffer.from(this._signingKeyPair.privateKey, 'hex'),
        Buffer.from(this._signingKeyPair.publicKey, 'hex'),
      ),
      format: 'jwk',
    });
    return sign(null, message, key);
  }

  /**
   * Verify a signature against a message and the signer's public key.
   */
  async verify(message: Buffer, signature: Buffer, signerPublicKey: string): Promise<boolean> {
    const key = createPublicKey({
      key: publicJwk('Ed25519', Buffer.from(signerPublicKey, 'hex')),
      format: 'jwk',
    });
    return verify(null, message, key, signature);
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

  private _generateKeyPair(kind: 'ed25519' | 'x25519'): KeyPair {
    const { privateKey } =
      kind === 'ed25519'
        ? generateKeyPairSync('ed25519')
        : generateKeyPairSync('x25519');
    const jwk = privateKey.export({ format: 'jwk' });
    const privateBytes = Buffer.from(jwk.d!, 'base64url');
    const publicBytes = Buffer.from(jwk.x!, 'base64url');

    return {
      publicKey: publicBytes.toString('hex'),
      privateKey: privateBytes.toString('hex'),
    };
  }

  private _ecdh(local: KeyPair, peerExchangePublicKey: string): Buffer {
    const privateKey = createPrivateKey({
      key: privateJwk(
        'X25519',
        Buffer.from(local.privateKey, 'hex'),
        Buffer.from(local.publicKey, 'hex'),
      ),
      format: 'jwk',
    });
    const peerPublicKey = createPublicKey({
      key: publicJwk('X25519', Buffer.from(peerExchangePublicKey, 'hex')),
      format: 'jwk',
    });

    return diffieHellman({ privateKey, publicKey: peerPublicKey });
  }

  private _deriveKeys(
    sharedSecret: Buffer,
    ourExchangePublicKey: string,
    peerExchangePublicKey: string,
  ): SessionKeys {
    const salt = Buffer.from('codex-fabric-v1');

    // Canonical ordering so both peers compute the same info string.
    const [a, b] = [ourExchangePublicKey, peerExchangePublicKey].sort();
    const info = Buffer.from(`session-keys:${a}:${b}`);

    const okm = Buffer.from(hkdfSync('sha256', sharedSecret, salt, info, 64));
    return {
      encryptionKey: okm.subarray(0, 32),
      signingKey: okm.subarray(32, 64),
    };
  }

  private _aesGcmEncrypt(plaintext: Buffer, key: Buffer): Buffer {
    if (key.length !== 32) throw new Error('Key must be 32 bytes for AES-256');

    const nonce = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', key, nonce);
    const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    const authTag = cipher.getAuthTag();

    return Buffer.concat([nonce, encrypted, authTag]);
  }

  private _aesGcmDecrypt(ciphertext: Buffer, key: Buffer): Buffer {
    if (key.length !== 32) throw new Error('Key must be 32 bytes for AES-256');
    // Minimum is 12-byte nonce + 16-byte auth tag
    if (ciphertext.length < 28) throw new Error('Ciphertext too short');

    const nonce = ciphertext.subarray(0, 12);
    const authTag = ciphertext.subarray(ciphertext.length - 16);
    const encrypted = ciphertext.subarray(12, ciphertext.length - 16);

    const decipher = createDecipheriv('aes-256-gcm', key, nonce);
    decipher.setAuthTag(authTag);
    return Buffer.concat([decipher.update(encrypted), decipher.final()]);
  }
}
