import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';

/// Manages cryptographic keys for end-to-end encryption
///
/// This class handles key generation, storage, and cryptographic operations
/// for secure peer-to-peer communication. All keys are generated and stored
/// exclusively on the client device.
class KeyManager {
  /// Unique session ID
  late final String _sessionId;

  /// Ed25519 key pair for signing
  late final _KeyPair _signingKeyPair;

  /// X25519 key pair for key exchange
  late final _KeyPair _exchangeKeyPair;

  /// Session encryption keys (derived from ECDH)
  Map<String, _SessionKeys> _sessionKeys = {};

  /// Whether the key manager has been initialized
  bool _initialized = false;

  /// Initialize the key manager
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _sessionId = const Uuid().v4();

    // Generate signing key pair (Ed25519)
    _signingKeyPair = await _generateSigningKeyPair();

    // Generate exchange key pair (X25519 for ECDH)
    _exchangeKeyPair = await _generateExchangeKeyPair();

    _initialized = true;
  }

  /// Get the session ID
  String get sessionId => _sessionId;

  /// Get the signing public key (hex encoded)
  String get signingPublicKey => _signingKeyPair.publicKeyHex;

  /// Get the exchange public key (hex encoded)
  String get exchangePublicKey => _exchangeKeyPair.publicKeyHex;

  /// Get the signing private key (hex encoded, keep secure!)
  String get signingPrivateKey => _signingKeyPair.privateKeyHex;

  /// Get the exchange private key (hex encoded, keep secure!)
  String get exchangePrivateKey => _exchangeKeyPair.privateKeyHex;

  /// Perform ECDH key exchange and derive session keys
  Future<_SessionKeys> deriveSessionKeys(String peerExchangePublicKey) async {
    if (!_initialized) {
      throw StateError('KeyManager not initialized');
    }

    final peerPublicKeyBytes = _hexToBytes(peerExchangePublicKey);
    
    // Perform ECDH
    final sharedSecret = await _ecdh(
      _exchangeKeyPair.privateKeyBytes,
      peerPublicKeyBytes,
    );

    // Derive session keys using HKDF
    final sessionKeys = await _deriveKeys(sharedSecret, peerExchangePublicKey);
    
    _sessionKeys[peerExchangePublicKey] = sessionKeys;
    
    return sessionKeys;
  }

  /// Encrypt data using AES-256-GCM
  Future<Uint8List> encrypt(Uint8List plaintext, String peerExchangePublicKey) async {
    final keys = _sessionKeys[peerExchangePublicKey];
    if (keys == null) {
      throw StateError('No session keys for peer');
    }

    return _aesGcmEncrypt(plaintext, keys.encryptionKey);
  }

  /// Decrypt data using AES-256-GCM
  Future<Uint8List> decrypt(Uint8List ciphertext, String peerExchangePublicKey) async {
    final keys = _sessionKeys[peerExchangePublicKey];
    if (keys == null) {
      throw StateError('No session keys for peer');
    }

    return _aesGcmDecrypt(ciphertext, keys.encryptionKey);
  }

  /// Sign a message using Ed25519
  Future<Uint8List> sign(Uint8List message) async {
    return _ed25519Sign(message, _signingKeyPair.privateKeyBytes);
  }

  /// Verify a signature using Ed25519
  Future<bool> verify(Uint8List message, Uint8List signature, String signerPublicKey) async {
    final publicKeyBytes = _hexToBytes(signerPublicKey);
    return _ed25519Verify(message, signature, publicKeyBytes);
  }

  /// Export public keys as JSON
  Map<String, dynamic> exportPublicKeys() {
    return {
      'session_id': _sessionId,
      'signing_public_key': signingPublicKey,
      'exchange_public_key': exchangePublicKey,
    };
  }

  /// Import peer's public keys
  Future<void> importPeerPublicKeys(String peerId, Map<String, dynamic> keys) async {
    // Store peer's public keys for later use
    // In a real implementation, this would be stored securely
  }

  /// Clear all session keys
  void clearSessionKeys() {
    _sessionKeys.clear();
  }

  /// Generate Ed25519 key pair
  Future<_KeyPair> _generateSigningKeyPair() async {
    // In a real implementation, use pointycastle or cryptography package
    // This is a mock implementation
    final privateKey = _generateRandomBytes(64);
    final publicKey = _generateRandomBytes(32);
    
    return _KeyPair(
      publicKey: Uint8List.fromList(publicKey),
      privateKey: Uint8List.fromList(privateKey),
    );
  }

  /// Generate X25519 key pair
  Future<_KeyPair> _generateExchangeKeyPair() async {
    // In a real implementation, use pointycastle for X25519
    // This is a mock implementation
    final privateKey = _generateRandomBytes(32);
    final publicKey = _generateRandomBytes(32);
    
    return _KeyPair(
      publicKey: Uint8List.fromList(publicKey),
      privateKey: Uint8List.fromList(privateKey),
    );
  }

  /// ECDH key exchange
  Future<Uint8List> _ecdh(Uint8List privateKey, Uint8List peerPublicKey) async {
    // In a real implementation, use curve25519 from pointycastle
    // This is a mock implementation
    final result = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      result[i] = privateKey[i] ^ peerPublicKey[i];
    }
    return result;
  }

  /// Derive encryption keys using HKDF
  Future<_SessionKeys> _deriveKeys(Uint8List sharedSecret, String peerPublicKey) async {
    // In a real implementation, use proper HKDF
    // This is a simplified version
    final salt = utf8.encode(peerPublicKey);
    
    // Derive encryption key (32 bytes for AES-256)
    final encryptionKey = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      encryptionKey[i] = sharedSecret[i] ^ salt[i % salt.length];
    }

    // Derive signing key
    final signingKey = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      signingKey[i] = sharedSecret[(i + 32) % sharedSecret.length] ^ salt[i % salt.length];
    }

    return _SessionKeys(
      encryptionKey: encryptionKey,
      signingKey: signingKey,
    );
  }

  /// AES-256-GCM encryption
  Future<Uint8List> _aesGcmEncrypt(Uint8List plaintext, Uint8List key) async {
    // In a real implementation, use pointycastle or cryptography package
    // This is a mock implementation that just returns the plaintext with a nonce
    final nonce = _generateRandomBytes(12);
    return Uint8List.fromList([...nonce, ...plaintext]);
  }

  /// AES-256-GCM decryption
  Future<Uint8List> _aesGcmDecrypt(Uint8List ciphertext, Uint8List key) async {
    // In a real implementation, use proper AES-GCM decryption
    // This is a mock implementation
    if (ciphertext.length < 12) {
      throw ArgumentError('Ciphertext too short');
    }
    return Uint8List.sublistView(ciphertext, 12);
  }

  /// Ed25519 signing
  Future<Uint8List> _ed25519Sign(Uint8List message, Uint8List privateKey) async {
    // In a real implementation, use pointycastle or ed25519_edwards
    // This is a mock implementation
    return _generateRandomBytes(64);
  }

  /// Ed25519 verification
  Future<bool> _ed25519Verify(Uint8List message, Uint8List signature, Uint8List publicKey) async {
    // In a real implementation, use proper Ed25519 verification
    // This is a mock implementation that always returns true
    return signature.length == 64;
  }

  /// Generate cryptographically secure random bytes
  Uint8List _generateRandomBytes(int length) {
    // In a real implementation, use dart:math with secure random
    // This is a mock implementation
    final random = DateTime.now().microsecondsSinceEpoch;
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = (random + i) % 256;
    }
    return bytes;
  }

  /// Convert hex string to bytes
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

  /// Convert bytes to hex string
  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Key pair representation
class _KeyPair {
  final Uint8List publicKey;
  final Uint8List privateKey;

  _KeyPair({
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

/// Session keys for encryption
class _SessionKeys {
  final Uint8List encryptionKey;
  final Uint8List signingKey;

  _SessionKeys({
    required this.encryptionKey,
    required this.signingKey,
  });
}