import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:codex_fabric/src/crypto/key_manager.dart';

/// Convert a hex string to bytes.
Uint8List _hexToBytes(String hex) {
  if (hex.length.isOdd) {
    hex = '0$hex';
  }
  final bytes = Uint8List(hex.length ~/ 2);
  for (int i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

void main() {
  group('KeyManager', () {
    late KeyManager keyManager;

    setUp(() async {
      keyManager = KeyManager();
      await keyManager.initialize();
    });

    tearDown(() {
      keyManager.dispose();
    });

    group('Initialization', () {
      test('should initialize successfully', () {
        expect(keyManager.isInitialized, isTrue);
      });

      test('should generate a unique session ID', () {
        expect(keyManager.sessionId, isNotEmpty);
        expect(keyManager.sessionId.length, equals(36)); // UUID v4 format
      });

      test('should generate unique session IDs on subsequent inits', () async {
        final km2 = KeyManager();
        await km2.initialize();
        
        expect(keyManager.sessionId, isNot(equals(km2.sessionId)));
        km2.dispose();
      });

      test('should generate 64-character hex Ed25519 signing public key', () {
        // Ed25519 public key is 32 bytes = 64 hex chars
        expect(keyManager.signingPublicKey.length, equals(64));
      });

      test('should generate 64-character hex X25519 exchange public key', () {
        // X25519 public key is 32 bytes = 64 hex chars
        expect(keyManager.exchangePublicKey.length, equals(64));
      });

      test('should generate 128-character hex Ed25519 signing private key', () {
        // Ed25519 private key is 64 bytes = 128 hex chars
        expect(keyManager.signingPrivateKey.length, equals(128));
      });

      test('should generate 64-character hex X25519 exchange private key', () {
        // X25519 private key is 32 bytes = 64 hex chars
        expect(keyManager.exchangePrivateKey.length, equals(64));
      });

      test('should not re-initialize if already initialized', () async {
        final originalSessionId = keyManager.sessionId;
        await keyManager.initialize(); // Should be a no-op
        expect(keyManager.sessionId, equals(originalSessionId));
      });

      test('should have signing keys consistent with each other', () {
        // Ed25519 private key (64 bytes) is seed (32 bytes) || public key (32 bytes)
        final privateKeyBytes = _hexToBytes(keyManager.signingPrivateKey);
        final publicKeyBytes = _hexToBytes(keyManager.signingPublicKey);

        expect(privateKeyBytes.length, equals(64));
        expect(publicKeyBytes.length, equals(32));
        expect(privateKeyBytes.sublist(32), equals(publicKeyBytes));
      });
    });

    group('Public Key Export', () {
      test('should export public keys as valid JSON', () {
        final publicKeys = keyManager.exportPublicKeys();
        
        expect(publicKeys, contains('session_id'));
        expect(publicKeys, contains('signing_public_key'));
        expect(publicKeys, contains('exchange_public_key'));
      });

      test('should not include private keys in export', () {
        final publicKeys = keyManager.exportPublicKeys();
        
        expect(publicKeys.containsKey('signing_private_key'), isFalse);
        expect(publicKeys.containsKey('exchange_private_key'), isFalse);
      });
    });

    group('Key Exchange and ECDH', () {
      late KeyManager peerKeyManager;

      setUp(() async {
        peerKeyManager = KeyManager();
        await peerKeyManager.initialize();
      });

      tearDown(() {
        peerKeyManager.dispose();
      });

      test('should derive session keys from peer public key', () async {
        final sessionKeys = await keyManager.deriveSessionKeys(
          peerKeyManager.exchangePublicKey,
        );

        expect(sessionKeys, isNotNull);
      });

      test('should derive identical session keys from both sides', () async {
        // Both sides perform ECDH independently and should arrive at the same keys
        final keysA = await keyManager.deriveSessionKeys(
          peerKeyManager.exchangePublicKey,
        );

        final keysB = await peerKeyManager.deriveSessionKeys(
          keyManager.exchangePublicKey,
        );

        // Both should have derived the same session keys
        expect(
          keysA.encryptionKey,
          equals(keysB.encryptionKey),
        );
        expect(
          keysA.signingKey,
          equals(keysB.signingKey),
        );
      });

      test('should throw when deriving keys without initialization', () async {
        final uninitManager = KeyManager();
        expect(
          () => uninitManager.deriveSessionKeys(peerKeyManager.exchangePublicKey),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('Encryption / Decryption', () {
      late KeyManager peerKeyManager;

      setUp(() async {
        peerKeyManager = KeyManager();
        await peerKeyManager.initialize();
        
        // Establish session
        await keyManager.deriveSessionKeys(peerKeyManager.exchangePublicKey);
        await peerKeyManager.deriveSessionKeys(keyManager.exchangePublicKey);
      });

      tearDown(() {
        peerKeyManager.dispose();
      });

      test('should encrypt plaintext successfully', () async {
        final plaintext = utf8.encode('Hello, CODEX Fabric!');
        final ciphertext = await keyManager.encrypt(
          Uint8List.fromList(plaintext),
          peerKeyManager.exchangePublicKey,
        );

        expect(ciphertext, isNotNull);
        expect(ciphertext.length, greaterThan(plaintext.length));
      });

      test('should produce different ciphertext on each encryption (random nonce)', () async {
        final plaintext = utf8.encode('Test message');
        final ct1 = await keyManager.encrypt(
          Uint8List.fromList(plaintext),
          peerKeyManager.exchangePublicKey,
        );
        final ct2 = await keyManager.encrypt(
          Uint8List.fromList(plaintext),
          peerKeyManager.exchangePublicKey,
        );

        // Due to random nonces, ciphertext should differ each time
        expect(ct1, isNot(equals(ct2)));
      });

      test('should decrypt ciphertext to original plaintext (peer perspective)', () async {
        final plaintext = utf8.encode('Confidential message for peer');
        final ciphertext = await keyManager.encrypt(
          Uint8List.fromList(plaintext),
          peerKeyManager.exchangePublicKey,
        );

        // Peer decrypts using its own key manager
        final decrypted = await peerKeyManager.decrypt(
          ciphertext,
          keyManager.exchangePublicKey,
        );

        expect(utf8.decode(decrypted), equals('Confidential message for peer'));
      });

      test('should encrypt and decrypt round-trip', () async {
        final plaintext = utf8.encode('Bidirectional encryption test');
        
        // A encrypts -> B decrypts
        final ciphertextAB = await keyManager.encrypt(
          Uint8List.fromList(plaintext),
          peerKeyManager.exchangePublicKey,
        );
        final decryptedB = await peerKeyManager.decrypt(
          ciphertextAB,
          keyManager.exchangePublicKey,
        );
        expect(utf8.decode(decryptedB), equals('Bidirectional encryption test'));

        // B encrypts -> A decrypts
        final ciphertextBA = await peerKeyManager.encrypt(
          Uint8List.fromList(plaintext),
          keyManager.exchangePublicKey,
        );
        final decryptedA = await keyManager.decrypt(
          ciphertextBA,
          peerKeyManager.exchangePublicKey,
        );
        expect(utf8.decode(decryptedA), equals('Bidirectional encryption test'));
      });

      test('should fail to encrypt without session keys', () async {
        final freshManager = KeyManager();
        await freshManager.initialize();

        expect(
          () => freshManager.encrypt(
            Uint8List.fromList([1, 2, 3]),
            peerKeyManager.exchangePublicKey,
          ),
          throwsA(isA<StateError>()),
        );

        freshManager.dispose();
      });

      test('should fail to decrypt with wrong key', () async {
        final wrongKeyManager = KeyManager();
        await wrongKeyManager.initialize();

        final plaintext = utf8.encode('Secret data');
        final ciphertext = await keyManager.encrypt(
          Uint8List.fromList(plaintext),
          peerKeyManager.exchangePublicKey,
        );

        // Try to decrypt with a key manager that has different session keys
        await wrongKeyManager.deriveSessionKeys(peerKeyManager.exchangePublicKey);
        
        expect(
          () => wrongKeyManager.decrypt(ciphertext, peerKeyManager.exchangePublicKey),
          throwsA(isA<ArgumentError>()),
        );

        wrongKeyManager.dispose();
      });
    });

    group('Digital Signatures', () {
      test('should sign a message', () async {
        final message = utf8.encode('Important message to sign');
        final signature = await keyManager.sign(Uint8List.fromList(message));

        expect(signature, isNotNull);
        expect(signature.length, equals(64)); // Ed25519 signature is 64 bytes
      });

      test('should verify a valid signature', () async {
        final message = utf8.encode('Message to verify');
        final signature = await keyManager.sign(Uint8List.fromList(message));

        final isValid = await keyManager.verify(
          Uint8List.fromList(message),
          signature,
          keyManager.signingPublicKey,
        );

        expect(isValid, isTrue);
      });

      test('should reject a signature with wrong public key', () async {
        final message = utf8.encode('Message to verify');
        final signature = await keyManager.sign(Uint8List.fromList(message));

        final isValid = await keyManager.verify(
          Uint8List.fromList(message),
          signature,
          keyManager.exchangePublicKey, // Wrong key type
        );

        expect(isValid, isFalse);
      });
    });

    group('Session Management', () {
      test('should clear all session keys', () async {
        final peerKeyManager = KeyManager();
        await peerKeyManager.initialize();

        await keyManager.deriveSessionKeys(peerKeyManager.exchangePublicKey);
        keyManager.clearSessionKeys();

        // After clearing, should not be able to encrypt
        expect(
          () => keyManager.encrypt(
            Uint8List.fromList([1, 2, 3]),
            peerKeyManager.exchangePublicKey,
          ),
          throwsA(isA<StateError>()),
        );

        peerKeyManager.dispose();
      });

      test('should dispose and reset state', () async {
        keyManager.dispose();
        expect(keyManager.isInitialized, isFalse);

        // Should be re-initializable after dispose
        await keyManager.initialize();
        expect(keyManager.isInitialized, isTrue);
      });
    });

    group('Import Peer Public Keys', () {
      test('should accept valid peer public keys', () async {
        final validKeys = {
          'signing_public_key': keyManager.signingPublicKey,
          'exchange_public_key': keyManager.exchangePublicKey,
        };

        // Should not throw
        await keyManager.importPeerPublicKeys('peer-1', validKeys);
      });

      test('should reject keys with missing signing key', () async {
        final invalidKeys = {
          'exchange_public_key': keyManager.exchangePublicKey,
        };

        expect(
          () => keyManager.importPeerPublicKeys('peer-1', invalidKeys),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should reject keys with missing exchange key', () async {
        final invalidKeys = {
          'signing_public_key': keyManager.signingPublicKey,
        };

        expect(
          () => keyManager.importPeerPublicKeys('peer-1', invalidKeys),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Empty Edge Cases', () {
      test('should handle empty plaintext encryption', () async {
        final peerKeyManager = KeyManager();
        await peerKeyManager.initialize();

        await keyManager.deriveSessionKeys(peerKeyManager.exchangePublicKey);
        
        final ciphertext = await keyManager.encrypt(
          Uint8List(0),
          peerKeyManager.exchangePublicKey,
        );

        expect(ciphertext, isNotNull);
        peerKeyManager.dispose();
      });

      test('should handle large data encryption', () async {
        final peerKeyManager = KeyManager();
        await peerKeyManager.initialize();

        await keyManager.deriveSessionKeys(peerKeyManager.exchangePublicKey);

        final largeData = Uint8List(1024 * 1024); // 1MB
        for (int i = 0; i < largeData.length; i++) {
          largeData[i] = i % 256;
        }

        final ciphertext = await keyManager.encrypt(
          largeData,
          peerKeyManager.exchangePublicKey,
        );

        expect(ciphertext, isNotNull);
        expect(ciphertext.length, greaterThan(0));
        peerKeyManager.dispose();
      });
    });
  });
}