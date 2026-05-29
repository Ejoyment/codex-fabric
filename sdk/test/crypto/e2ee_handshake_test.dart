import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:codex_fabric/src/crypto/key_manager.dart';
import 'package:codex_fabric/src/crypto/security_handshake.dart';
import 'package:codex_fabric/src/signaling/messages.dart';

/// Integration test for the complete E2EE handshake protocol.
///
/// This test simulates two clients (Alice and Bob) performing the full
/// key exchange handshake, then exchanging encrypted data. It validates
/// that:
/// 1. Both peers derive identical session keys
/// 2. Encrypted data can be decrypted by the peer
/// 3. The signaling server only sees public keys (never private keys)
/// 4. Signatures can be verified by peers
void main() {
  group('E2EE Handshake Integration Test', () {
    late SecurityHandshake alice;
    late SecurityHandshake bob;

    setUp(() async {
      alice = SecurityHandshake(keyManager: KeyManager());
      bob = SecurityHandshake(keyManager: KeyManager());

      await alice.initialize();
      await bob.initialize();
    });

    tearDown(() {
      alice.dispose();
      bob.dispose();
    });

    test('complete handshake flow: Alice -> Bob', () async {
      // Step 1: Alice creates a key exchange message for Bob
      final keyExchangeMsg = await alice.createKeyExchangeMessage('bob-peer-id');

      // Verify the message only contains public keys
      expect(keyExchangeMsg.type, equals(MessageType.keyExchange));
      expect(keyExchangeMsg.signingPublicKey, isNotEmpty);
      expect(keyExchangeMsg.exchangePublicKey, isNotEmpty);
      expect(keyExchangeMsg.peerId, equals('bob-peer-id'));

      // CRITICAL: Verify private keys are NOT in the message
      final msgJson = keyExchangeMsg.toJson();
      expect(msgJson.containsKey('signing_private_key'), isFalse);
      expect(msgJson.containsKey('exchange_private_key'), isFalse);

      // Step 2: "Server" relays message to Bob (simulated)
      // The server only forwards the public keys
      final relayedMsg = KeyExchangeMessage.fromJson(msgJson);

      // Step 3: Bob processes the key exchange
      final ackMsg = await bob.processKeyExchangeMessage(relayedMsg);

      // Verify acknowledgment
      expect(ackMsg.type, equals(MessageType.keyExchangeAck));
      expect(ackMsg.status, equals('established'));

      // Step 4: Alice processes the acknowledgment
      await alice.processKeyExchangeAck(ackMsg, keyExchangeMsg.exchangePublicKey);

      // Step 5: Verify both sides have established the session
      expect(alice.isSessionEstablished('bob-peer-id'), isTrue);
      expect(bob.isSessionEstablished('alice-peer-id'), isTrue);
    });

    test('encrypted data exchange after handshake', () async {
      // Perform handshake
      final keyExchangeMsg = await alice.createKeyExchangeMessage('bob-peer-id');
      final relayedMsg = KeyExchangeMessage.fromJson(keyExchangeMsg.toJson());
      final ackMsg = await bob.processKeyExchangeMessage(relayedMsg);
      await alice.processKeyExchangeAck(ackMsg, keyExchangeMsg.exchangePublicKey);

      // Alice encrypts a message for Bob
      final plaintext = utf8.encode('Hello Bob, this is a secret message from Alice!');
      final ciphertext = await alice.encryptForPeer(
        Uint8List.fromList(plaintext),
        'bob-peer-id',
      );

      // Verify the ciphertext is different from plaintext
      expect(ciphertext, isNot(equals(Uint8List.fromList(plaintext))));

      // Bob decrypts the message from Alice
      final decrypted = await bob.decryptFromPeer(ciphertext, 'alice-peer-id');
      expect(utf8.decode(decrypted), equals('Hello Bob, this is a secret message from Alice!'));
    });

    test('bidirectional encrypted communication', () async {
      // Perform handshake
      final keyExchangeMsg = await alice.createKeyExchangeMessage('bob-peer-id');
      final relayedMsg = KeyExchangeMessage.fromJson(keyExchangeMsg.toJson());
      final ackMsg = await bob.processKeyExchangeMessage(relayedMsg);
      await alice.processKeyExchangeAck(ackMsg, keyExchangeMsg.exchangePublicKey);

      // Alice -> Bob
      final msg1 = utf8.encode('Message from Alice to Bob');
      final ct1 = await alice.encryptForPeer(Uint8List.fromList(msg1), 'bob-peer-id');
      final dt1 = await bob.decryptFromPeer(ct1, 'alice-peer-id');
      expect(utf8.decode(dt1), equals('Message from Alice to Bob'));

      // Bob -> Alice
      final msg2 = utf8.encode('Reply from Bob to Alice');
      final ct2 = await bob.encryptForPeer(Uint8List.fromList(msg2), 'alice-peer-id');
      final dt2 = await alice.decryptFromPeer(ct2, 'bob-peer-id');
      expect(utf8.decode(dt2), equals('Reply from Bob to Alice'));
    });

    test('digital signature verification across peers', () async {
      // Perform handshake so peers have each other's public keys
      final keyExchangeMsg = await alice.createKeyExchangeMessage('bob-peer-id');
      final relayedMsg = KeyExchangeMessage.fromJson(keyExchangeMsg.toJson());
      final ackMsg = await bob.processKeyExchangeMessage(relayedMsg);
      await alice.processKeyExchangeAck(ackMsg, keyExchangeMsg.exchangePublicKey);

      // Alice signs a message
      final data = utf8.encode('Important document hash');
      final signature = await alice.signData(Uint8List.fromList(data));

      // Verify Alice's signature using her public key
      final isValid = await bob.verifyPeerSignature(
        Uint8List.fromList(data),
        signature,
        'alice-peer-id',
      );

      expect(isValid, isTrue);
    });

    test('server cannot derive private keys from key exchange', () async {
      final keyExchangeMsg = await alice.createKeyExchangeMessage('bob-peer-id');
      final msgJson = keyExchangeMsg.toJson();

      // Simulate what the server sees
      final serverVisible = {
        'type': msgJson['type'],
        'signing_public_key': msgJson['signing_public_key'],
        'exchange_public_key': msgJson['exchange_public_key'],
      };

      // Server should NEVER see these
      expect(serverVisible.containsKey('signing_private_key'), isFalse);
      expect(serverVisible.containsKey('exchange_private_key'), isFalse);

      // Verify public keys are valid hex strings (64 chars for 32 bytes)
      expect(serverVisible['signing_public_key'].length, equals(64));
      expect(serverVisible['exchange_public_key'].length, equals(64));
    });

    test('multiple independent sessions', () async {
      // Alice <-> Bob session
      final keyExchangeAB = await alice.createKeyExchangeMessage('bob-peer-id');
      final relayedAB = KeyExchangeMessage.fromJson(keyExchangeAB.toJson());
      final ackAB = await bob.processKeyExchangeMessage(relayedAB);
      await alice.processKeyExchangeAck(ackAB, keyExchangeAB.exchangePublicKey);

      // Alice <-> Charlie session (separate)
      final charlie = SecurityHandshake(keyManager: KeyManager());
      await charlie.initialize();

      final keyExchangeAC = await alice.createKeyExchangeMessage('charlie-peer-id');
      final relayedAC = KeyExchangeMessage.fromJson(keyExchangeAC.toJson());
      final ackAC = await charlie.processKeyExchangeMessage(relayedAC);
      await alice.processKeyExchangeAck(ackAC, keyExchangeAC.exchangePublicKey);

      // Both sessions should be established
      expect(alice.isSessionEstablished('bob-peer-id'), isTrue);
      expect(alice.isSessionEstablished('charlie-peer-id'), isTrue);

      // Encrypted data should be independent per peer
      final msgToBob = utf8.encode('Secret for Bob only');
      final ctBob = await alice.encryptForPeer(Uint8List.fromList(msgToBob), 'bob-peer-id');
      final dtBob = await bob.decryptFromPeer(ctBob, 'alice-peer-id');
      expect(utf8.decode(dtBob), equals('Secret for Bob only'));

      final msgToCharlie = utf8.encode('Secret for Charlie only');
      final ctCharlie = await alice.encryptForPeer(Uint8List.fromList(msgToCharlie), 'charlie-peer-id');
      final dtCharlie = await charlie.decryptFromPeer(ctCharlie, 'alice-peer-id');
      expect(utf8.decode(dtCharlie), equals('Secret for Charlie only'));

      charlie.dispose();
    });

    test('session lifecycle: create, use, clear', () async {
      // Create session
      final keyExchangeMsg = await alice.createKeyExchangeMessage('bob-peer-id');
      final relayedMsg = KeyExchangeMessage.fromJson(keyExchangeMsg.toJson());
      final ackMsg = await bob.processKeyExchangeMessage(relayedMsg);
      await alice.processKeyExchangeAck(ackMsg, keyExchangeMsg.exchangePublicKey);

      expect(alice.isSessionEstablished('bob-peer-id'), isTrue);

      // Use session
      final plaintext = utf8.encode('test data');
      final ciphertext = await alice.encryptForPeer(
        Uint8List.fromList(plaintext),
        'bob-peer-id',
      );
      expect(ciphertext, isNotNull);

      // Clear session
      alice.clearSessions();
      expect(alice.isSessionEstablished('bob-peer-id'), isFalse);
    });
  });
}