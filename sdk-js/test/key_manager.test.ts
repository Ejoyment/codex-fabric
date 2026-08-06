/**
 * Tests for the CODEX Fabric JS SDK KeyManager.
 *
 * Validates that:
 * 1. Real key pairs are generated (valid sizes, consistent signatures)
 * 2. Both peers derive identical session keys from ECDH
 * 3. AES-256-GCM encryption/decryption round-trips across peers
 * 4. Wrong keys fail to decrypt (authenticated encryption)
 * 5. Ed25519 signatures sign and verify
 */

import { KeyManager } from '../src/crypto/key_manager';

describe('KeyManager', () => {
  let manager: KeyManager;

  beforeEach(async () => {
    manager = new KeyManager();
    await manager.initialize();
  });

  describe('initialization', () => {
    test('generates valid keys and a UUID session id', () => {
      expect(manager.isInitialized).toBe(true);
      expect(manager.signingPublicKey).toHaveLength(64);
      expect(manager.exchangePublicKey).toHaveLength(64);
      expect(manager.sessionId).toMatch(
        /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
      );
    });

    test('is a no-op when called again', async () => {
      const sessionId = manager.sessionId;
      await manager.initialize();
      expect(manager.sessionId).toBe(sessionId);
    });
  });

  describe('public key export', () => {
    test('exports only public keys', () => {
      const exported = manager.exportPublicKeys();
      expect(exported.sessionId).toBe(manager.sessionId);
      expect(exported.signingPublicKey).toBe(manager.signingPublicKey);
      expect(exported.exchangePublicKey).toBe(manager.exchangePublicKey);
      expect(JSON.stringify(exported)).not.toContain('private');
    });
  });

  describe('key exchange and ECDH', () => {
    let peer: KeyManager;

    beforeEach(async () => {
      peer = new KeyManager();
      await peer.initialize();
    });

    afterEach(() => {
      peer.clearSessionKeys();
    });

    test('derives session keys from a peer public key', async () => {
      const keys = await manager.deriveSessionKeys(peer.exchangePublicKey);
      expect(keys.encryptionKey).toHaveLength(32);
      expect(keys.signingKey).toHaveLength(32);
    });

    test('derives identical session keys on both sides', async () => {
      const keysA = await manager.deriveSessionKeys(peer.exchangePublicKey);
      const keysB = await peer.deriveSessionKeys(manager.exchangePublicKey);

      expect(keysA.encryptionKey.equals(keysB.encryptionKey)).toBe(true);
      expect(keysA.signingKey.equals(keysB.signingKey)).toBe(true);
    });

    test('throws when deriving keys without initialization', async () => {
      const uninitialized = new KeyManager();
      await expect(
        uninitialized.deriveSessionKeys(peer.exchangePublicKey),
      ).rejects.toThrow('KeyManager not initialized');
    });
  });

  describe('encryption / decryption', () => {
    let peer: KeyManager;

    beforeEach(async () => {
      peer = new KeyManager();
      await peer.initialize();
      await manager.deriveSessionKeys(peer.exchangePublicKey);
      await peer.deriveSessionKeys(manager.exchangePublicKey);
    });

    afterEach(() => {
      peer.clearSessionKeys();
    });

    test('encrypts and decrypts round-trip in both directions', () => {
      const plaintext = Buffer.from('Bidirectional encryption test');

      const ciphertextAB = manager.encrypt(plaintext, peer.exchangePublicKey);
      const decryptedB = peer.decrypt(ciphertextAB, manager.exchangePublicKey);
      expect(decryptedB.toString()).toBe('Bidirectional encryption test');

      const ciphertextBA = peer.encrypt(plaintext, manager.exchangePublicKey);
      const decryptedA = manager.decrypt(ciphertextBA, peer.exchangePublicKey);
      expect(decryptedA.toString()).toBe('Bidirectional encryption test');
    });

    test('produces different ciphertext each time (random nonce)', () => {
      const plaintext = Buffer.from('Test message');
      const ct1 = manager.encrypt(plaintext, peer.exchangePublicKey);
      const ct2 = manager.encrypt(plaintext, peer.exchangePublicKey);

      expect(ct1.equals(ct2)).toBe(false);
    });

    test('fails to encrypt without session keys', () => {
      const fresh = new KeyManager();
      expect(() => fresh.encrypt(Buffer.from('x'), peer.exchangePublicKey)).toThrow(
        'No session keys for peer',
      );
    });

    test('fails to decrypt with the wrong key', async () => {
      const wrong = new KeyManager();
      await wrong.initialize();
      await wrong.deriveSessionKeys(peer.exchangePublicKey);

      const ciphertext = manager.encrypt(Buffer.from('Secret data'), peer.exchangePublicKey);
      expect(() => wrong.decrypt(ciphertext, peer.exchangePublicKey)).toThrow();

      wrong.clearSessionKeys();
    });

    test('handles empty plaintext', () => {
      const ciphertext = manager.encrypt(Buffer.alloc(0), peer.exchangePublicKey);
      expect(ciphertext).toHaveLength(28); // nonce + tag
      const decrypted = peer.decrypt(ciphertext, manager.exchangePublicKey);
      expect(decrypted).toHaveLength(0);
    });

    test('handles large data', () => {
      const large = Buffer.alloc(1024 * 1024);
      for (let i = 0; i < large.length; i++) large[i] = i % 256;

      const ciphertext = manager.encrypt(large, peer.exchangePublicKey);
      const decrypted = peer.decrypt(ciphertext, manager.exchangePublicKey);
      expect(decrypted.equals(large)).toBe(true);
    });
  });

  describe('digital signatures', () => {
    test('signs and verifies a message', async () => {
      const message = Buffer.from('Important message to sign');
      const signature = await manager.sign(message);

      expect(signature).toHaveLength(64);
      const valid = await manager.verify(message, signature, manager.signingPublicKey);
      expect(valid).toBe(true);
    });

    test('rejects a signature with the wrong public key', async () => {
      const other = new KeyManager();
      await other.initialize();

      const message = Buffer.from('Message to verify');
      const signature = await manager.sign(message);

      const valid = await manager.verify(message, signature, other.signingPublicKey);
      expect(valid).toBe(false);
      other.clearSessionKeys();
    });
  });
});
