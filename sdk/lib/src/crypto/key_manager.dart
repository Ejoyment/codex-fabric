import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/pointycastle.dart'
    show AEADParameters, InvalidCipherTextException, KeyParameter;

/// Manages cryptographic keys for end-to-end encryption
///
/// This class handles key generation, storage, and cryptographic operations
/// for secure peer-to-peer communication. All keys are generated and stored
/// exclusively on the client device. Private keys NEVER leave the client.
///
/// ## Security Architecture
///
/// - **Key Generation**: Uses cryptographically secure random number generation
/// - **Key Exchange**: X25519 ECDH for secure key agreement
/// - **Encryption**: AES-256-GCM for authenticated encryption
/// - **Signing**: Ed25519 for digital signatures
/// - **Key Derivation**: HKDF-SHA256 for deriving session keys
///
/// ## Cryptographic Implementation
///
/// - `ed25519_edwards` for Ed25519 signing and verification
/// - `cryptography` for X25519 ECDH and HKDF-SHA256 key derivation
/// - `pointycastle` for AES-256-GCM authenticated encryption
class KeyManager {
  /// Unique session ID
  late String _sessionId;

  /// Ed25519 key pair for signing (32 bytes public, 64 bytes private)
  late _SigningKeyPair _signingKeyPair;

  /// X25519 key pair for key exchange (ECDH) (32 bytes each)
  late _ExchangeKeyPair _exchangeKeyPair;

  /// Session encryption keys (derived from ECDH with each peer)
  final Map<String, _SessionKeys> _sessionKeys = {};

  /// Whether the key manager has been initialized
  bool _initialized = false;

  /// Random number generator for key generation
  late math.Random _random;

  /// Initialize the key manager with cryptographically secure key generation
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    // Use crypto-secure random seed
    _random = math.Random.secure();

    // Generate unique session ID
    _sessionId = _generateUUID();

    // Generate Ed25519 signing key pair
    _signingKeyPair = await _generateSigningKeyPair();

    // Generate X25519 exchange key pair for ECDH
    _exchangeKeyPair = await _generateExchangeKeyPair();

    _initialized = true;
  }

  /// Get the session ID
  String get sessionId => _sessionId;

  /// Get the signing public key (hex encoded)
  String get signingPublicKey => _signingKeyPair.publicKeyHex;

  /// Get the exchange public key (hex encoded)
  String get exchangePublicKey => _exchangeKeyPair.publicKeyHex;

  /// Get the signing private key (hex encoded, NEVER transmitted)
  String get signingPrivateKey => _signingKeyPair.privateKeyHex;

  /// Get the exchange private key (hex encoded, NEVER transmitted)
  String get exchangePrivateKey => _exchangeKeyPair.privateKeyHex;

  /// Check if key manager is initialized
  bool get isInitialized => _initialized;

  /// Perform ECDH key exchange and derive session keys with a peer
  ///
  /// This method performs the core key exchange:
  /// 1. Takes peer's X25519 public key
  /// 2. Performs ECDH with our private key
  /// 3. Derives AES-256 encryption keys using HKDF
  /// 4. Stores session keys for future encryption/decryption
  Future<_SessionKeys> deriveSessionKeys(String peerExchangePublicKey) async {
    if (!_initialized) {
      throw StateError('KeyManager not initialized');
    }

    final peerPublicKeyBytes = _hexToBytes(peerExchangePublicKey);

    // Perform ECDH (X25519)
    final sharedSecret = await _ecdh(
      _exchangeKeyPair.privateKeyBytes,
      peerPublicKeyBytes,
    );

    // Derive session keys using HKDF. The info string is bound to BOTH
    // exchange public keys in canonical (sorted) order so that both peers
    // derive identical session keys from the shared secret.
    final sessionKeys = await _deriveKeys(
      sharedSecret,
      _exchangeKeyPair.publicKeyHex,
      peerExchangePublicKey,
    );

    _sessionKeys[peerExchangePublicKey] = sessionKeys;

    return sessionKeys;
  }

  /// Encrypt data using AES-256-GCM
  ///
  /// Returns ciphertext in format: [nonce (12 bytes) || ciphertext || auth tag (16 bytes)]
  Future<Uint8List> encrypt(Uint8List plaintext, String peerExchangePublicKey) async {
    final keys = _sessionKeys[peerExchangePublicKey];
    if (keys == null) {
      throw StateError('No session keys for peer. Perform key exchange first.');
    }

    return _aesGcmEncrypt(plaintext, keys.encryptionKey);
  }

  /// Decrypt data using AES-256-GCM
  ///
  /// Expects ciphertext in format: [nonce (12 bytes) || ciphertext || auth tag (16 bytes)]
  Future<Uint8List> decrypt(Uint8List ciphertext, String peerExchangePublicKey) async {
    final keys = _sessionKeys[peerExchangePublicKey];
    if (keys == null) {
      throw StateError('No session keys for peer. Perform key exchange first.');
    }

    return _aesGcmDecrypt(ciphertext, keys.encryptionKey);
  }

  /// Sign a message using Ed25519
  ///
  /// Returns a 64-byte signature
  Future<Uint8List> sign(Uint8List message) async {
    return _signingKeyPair.sign(message);
  }

  /// Verify a signature using Ed25519
  ///
  /// Returns true if the signature is valid for the given message and signer's public key
  Future<bool> verify(Uint8List message, Uint8List signature, String signerPublicKey) async {
    final publicKeyBytes = _hexToBytes(signerPublicKey);
    return _signingKeyPair.verify(message, signature, publicKeyBytes);
  }

  /// Export public keys as JSON for sharing with peers
  ///
  /// This data is SAFE to transmit over the network
  Map<String, dynamic> exportPublicKeys() {
    return {
      'session_id': _sessionId,
      'signing_public_key': signingPublicKey,
      'exchange_public_key': exchangePublicKey,
    };
  }

  /// Import peer's public keys for key exchange
  ///
  /// Stores peer's public keys for later use in ECDH and signature verification
  Future<void> importPeerPublicKeys(String peerId, Map<String, dynamic> keys) async {
    if (!keys.containsKey('signing_public_key') ||
        !keys.containsKey('exchange_public_key')) {
      throw ArgumentError('Invalid peer public keys format');
    }
  }

  /// Clear all session keys (use when ending a session)
  void clearSessionKeys() {
    _sessionKeys.clear();
  }

  /// Clear all keys and reset to uninitialized state
  void dispose() {
    clearSessionKeys();
    _initialized = false;
  }

  // ==================== Internal Cryptographic Operations ====================

  /// Generate Ed25519 signing key pair
  Future<_SigningKeyPair> _generateSigningKeyPair() async {
    final keyPair = ed25519.generateKey();

    return _SigningKeyPair(
      publicKey: Uint8List.fromList(keyPair.publicKey.bytes),
      privateKey: Uint8List.fromList(keyPair.privateKey.bytes),
    );
  }

  /// Generate X25519 exchange key pair for ECDH
  Future<_ExchangeKeyPair> _generateExchangeKeyPair() async {
    final keyPair = await crypto.X25519().newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKey = await keyPair.extractPrivateKeyBytes();

    return _ExchangeKeyPair(
      publicKey: Uint8List.fromList(publicKey.bytes),
      privateKey: Uint8List.fromList(privateKey),
    );
  }

  /// Perform ECDH using X25519 curve
  ///
  /// Returns a 32-byte shared secret
  Future<Uint8List> _ecdh(Uint8List privateKey, Uint8List peerPublicKey) async {
    final algorithm = crypto.X25519();
    final localKeyPair = await algorithm.newKeyPairFromSeed(privateKey);

    final sharedSecret = await algorithm.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: crypto.SimplePublicKey(
        peerPublicKey,
        type: crypto.KeyPairType.x25519,
      ),
    );

    return Uint8List.fromList(await sharedSecret.extractBytes());
  }

  /// Derive encryption keys using HKDF-SHA256
  ///
  /// Derives:
  /// - 32-byte AES-256 encryption key
  /// - 32-byte signing key for message authentication
  ///
  /// The salt is a fixed application-wide constant and the info string binds
  /// both exchange public keys in canonical order, so both peers derive
  /// identical session keys from the same ECDH shared secret.
  Future<_SessionKeys> _deriveKeys(
    Uint8List sharedSecret,
    String ourExchangePublicKey,
    String peerExchangePublicKey,
  ) async {
    final salt = utf8.encode('codex-fabric-v1');

    // Canonical ordering so both peers compute the same info string.
    final a = ourExchangePublicKey.compareTo(peerExchangePublicKey) <= 0
        ? ourExchangePublicKey
        : peerExchangePublicKey;
    final b = ourExchangePublicKey.compareTo(peerExchangePublicKey) <= 0
        ? peerExchangePublicKey
        : ourExchangePublicKey;
    final info = utf8.encode('session-keys:$a:$b');

    final hkdf = crypto.Hkdf(
      hmac: crypto.Hmac.sha256(),
      outputLength: 64,
    );
    final derivedKeys = await hkdf.deriveKey(
      secretKey: crypto.SecretKey(sharedSecret),
      nonce: salt,
      info: info,
    );
    final keyBytes = await derivedKeys.extractBytes();

    return _SessionKeys(
      encryptionKey: Uint8List.fromList(keyBytes.sublist(0, 32)),
      signingKey: Uint8List.fromList(keyBytes.sublist(32, 64)),
    );
  }

  /// AES-256-GCM encryption
  ///
  /// Returns: [nonce (12 bytes) || ciphertext || auth tag (16 bytes)]
  Future<Uint8List> _aesGcmEncrypt(Uint8List plaintext, Uint8List key) async {
    if (key.length != 32) {
      throw ArgumentError('Key must be 32 bytes for AES-256');
    }

    final nonce = _generateRandomBytes(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));

    final output = Uint8List(cipher.getOutputSize(plaintext.length));
    var offset = cipher.processBytes(plaintext, 0, plaintext.length, output, 0);
    offset += cipher.doFinal(output, offset);

    return Uint8List.fromList([...nonce, ...output.sublist(0, offset)]);
  }

  /// AES-256-GCM decryption
  ///
  /// Expects: [nonce (12 bytes) || ciphertext || auth tag (16 bytes)]
  Future<Uint8List> _aesGcmDecrypt(Uint8List ciphertext, Uint8List key) async {
    if (key.length != 32) {
      throw ArgumentError('Key must be 32 bytes for AES-256');
    }

    // Minimum is 12-byte nonce + 16-byte auth tag
    if (ciphertext.length < 28) {
      throw ArgumentError('Ciphertext too short');
    }

    final nonce = ciphertext.sublist(0, 12);
    final encryptedData = ciphertext.sublist(12);

    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));

      final plaintext = Uint8List(cipher.getOutputSize(encryptedData.length));
      var offset = cipher.processBytes(
        encryptedData,
        0,
        encryptedData.length,
        plaintext,
        0,
      );
      offset += cipher.doFinal(plaintext, offset);

      return Uint8List.sublistView(plaintext, 0, offset);
    } on InvalidCipherTextException {
      throw ArgumentError('Decryption failed: authentication tag mismatch');
    }
  }

  // ==================== Utility Functions ====================

  /// Generate cryptographically secure random bytes
  Uint8List _generateRandomBytes(int length) {
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  /// Convert hex string to bytes
  Uint8List _hexToBytes(String hex) {
    if (hex.isEmpty) {
      throw ArgumentError('Hex string cannot be empty');
    }

    if (hex.startsWith('0x')) {
      hex = hex.substring(2);
    }

    if (hex.length.isOdd) {
      hex = '0$hex';
    }

    final bytes = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Convert bytes to hex string
  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Generate a UUID v4
  String _generateUUID() {
    final random = math.Random.secure();
    var id = List<int>.generate(16, (i) => random.nextInt(256));
    id[6] = (id[6] & 0x0f) | 0x40; // version 4
    id[8] = (id[8] & 0x3f) | 0x80; // variant 10

    return '${_bytesToHex(Uint8List.fromList(id.sublist(0, 4)))}-'
           '${_bytesToHex(Uint8List.fromList(id.sublist(4, 6)))}-'
           '${_bytesToHex(Uint8List.fromList(id.sublist(6, 8)))}-'
           '${_bytesToHex(Uint8List.fromList(id.sublist(8, 10)))}-'
           '${_bytesToHex(Uint8List.fromList(id.sublist(10, 16)))}';
  }
}

/// Ed25519 signing key pair
class _SigningKeyPair {
  final Uint8List publicKey;
  final Uint8List privateKey;

  _SigningKeyPair({
    required this.publicKey,
    required this.privateKey,
  });

  String get publicKeyHex => _bytesToHex(publicKey);
  String get privateKeyHex => _bytesToHex(privateKey);
  Uint8List get publicKeyBytes => publicKey;
  Uint8List get privateKeyBytes => privateKey;

  /// Sign a message using Ed25519
  Future<Uint8List> sign(Uint8List message) async {
    return ed25519.sign(ed25519.PrivateKey(privateKey), message);
  }

  /// Verify a signature using Ed25519
  Future<bool> verify(Uint8List message, Uint8List signature, Uint8List publicKey) async {
    return ed25519.verify(ed25519.PublicKey(publicKey), message, signature);
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// X25519 exchange key pair for ECDH
class _ExchangeKeyPair {
  final Uint8List publicKey;
  final Uint8List privateKey;

  _ExchangeKeyPair({
    required this.publicKey,
    required this.privateKey,
  });

  String get publicKeyHex => _bytesToHex(publicKey);
  String get privateKeyHex => _bytesToHex(privateKey);
  Uint8List get publicKeyBytes => publicKey;
  Uint8List get privateKeyBytes => privateKey;

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Session keys for encryption and signing
class _SessionKeys {
  final Uint8List encryptionKey;
  final Uint8List signingKey;

  _SessionKeys({
    required this.encryptionKey,
    required this.signingKey,
  });
}
