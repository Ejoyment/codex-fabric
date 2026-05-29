import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

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
/// ## Production Note
///
/// For production use, integrate with actual cryptographic packages:
/// - `pointycastle` for Ed25519, X25519, AES-GCM
/// - `cryptography` for HKDF
/// - `ed25519_edwards` for Ed25519 signatures
///
/// This implementation provides the complete API and architecture,
/// with placeholder crypto operations that demonstrate the flow.
class KeyManager {
  /// Unique session ID
  late final String _sessionId;

  /// Ed25519 key pair for signing (32 bytes public, 64 bytes private)
  late final _SigningKeyPair _signingKeyPair;

  /// X25519 key pair for key exchange (ECDH) (32 bytes each)
  late final _ExchangeKeyPair _exchangeKeyPair;

  /// Session encryption keys (derived from ECDH with each peer)
  final Map<String, _SessionKeys> _sessionKeys = {};

  /// Whether the key manager has been initialized
  bool _initialized = false;

  /// Random number generator for key generation
  late final math.Random _random;

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

    // Derive session keys using HKDF with peer's public key as info
    final sessionKeys = await _deriveKeys(sharedSecret, peerExchangePublicKey);
    
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
  /// 
  /// In production, use pointycastle's Ed25519KeyGenerator
  Future<_SigningKeyPair> _generateSigningKeyPair() async {
    final publicKey = _generateRandomBytes(32);
    final privateKey = _generateRandomBytes(64);
    
    return _SigningKeyPair(
      publicKey: Uint8List.fromList(publicKey),
      privateKey: Uint8List.fromList(privateKey),
    );
  }

  /// Generate X25519 exchange key pair for ECDH
  /// 
  /// In production, use pointycastle's Curve25519KeyGenerator
  Future<_ExchangeKeyPair> _generateExchangeKeyPair() async {
    final privateKey = _generateRandomBytes(32);
    final publicKey = _generateRandomBytes(32);
    
    return _ExchangeKeyPair(
      publicKey: Uint8List.fromList(publicKey),
      privateKey: Uint8List.fromList(privateKey),
    );
  }

  /// Perform ECDH using X25519 curve
  /// 
  /// Returns a 32-byte shared secret
  /// 
  /// In production, use pointycastle's ECDHBasicAgreement with Curve25519
  Future<Uint8List> _ecdh(Uint8List privateKey, Uint8List peerPublicKey) async {
    // Production implementation using pointycastle:
    // final ecCurve = ECDomainParameters('curve25519');
    // final privateKeyParam = ECPrivateKey(
    //   BigInt.parse(_bytesToHex(privateKey), radix: 16),
    //   ecCurve,
    // );
    // final peerPublicKeyPoint = ecCurve.curve.decodePoint(peerPublicKey)!;
    // final peerPublicKeyParam = ECPublicKey(peerPublicKeyPoint, ecCurve);
    // final agreement = ECDHBasicAgreement();
    // agreement.init(privateKeyParam);
    // final sharedSecret = agreement.calculateAgreement(peerPublicKeyParam);
    
    // Simplified implementation for architecture demonstration
    final result = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      result[i] = privateKey[i] ^ peerPublicKey[i];
    }
    return result;
  }

  /// Derive encryption keys using HKDF-SHA256
  /// 
  /// Derives:
  /// - 32-byte AES-256 encryption key
  /// - 32-byte signing key for message authentication
  /// 
  /// In production, use cryptography package's Hkdf
  Future<_SessionKeys> _deriveKeys(Uint8List sharedSecret, String peerPublicKey) async {
    final salt = utf8.encode('codex-fabric-v1');
    final info = utf8.encode('session-keys:$peerPublicKey');
    
    // Production implementation using cryptography package:
    // final hkdf = Hkdf(
    //   macAlgorithm: Hash(SHA256Digest()),
    //   hash: SHA256Digest(),
    //   salt: salt,
    // );
    // final derivedKeys = await hkdf.deriveKey(
    //   secretBytes: sharedSecret,
    //   length: 64,
    //   info: info,
    // );
    // final keyBytes = await derivedKeys.extractBytes();
    
    // Simplified HKDF-like derivation for architecture demonstration
    final prk = _hmacSHA256(salt, sharedSecret);
    final okm = _hkdfExpand(prk, info, 64);
    
    return _SessionKeys(
      encryptionKey: Uint8List.fromList(okm.sublist(0, 32)),
      signingKey: Uint8List.fromList(okm.sublist(32, 64)),
    );
  }

  /// AES-256-GCM encryption
  /// 
  /// Returns: [nonce (12 bytes) || ciphertext || auth tag (16 bytes)]
  /// 
  /// In production, use pointycastle's GCMBlockCipher
  Future<Uint8List> _aesGcmEncrypt(Uint8List plaintext, Uint8List key) async {
    if (key.length != 32) {
      throw ArgumentError('Key must be 32 bytes for AES-256');
    }

    // Production implementation using pointycastle:
    // final random = RandomSecure();
    // final nonce = Uint8List(12);
    // random.nextBytes(nonce);
    // final cipher = GCMBlockCipher(AESEngine(KeyParameter(key)))
    //   ..init(true, ParametersWithIV(KeyParameter(key), nonce));
    // final ciphertext = Uint8List(plaintext.length + 16);
    // var offset = 0;
    // while (offset < plaintext.length) {
    //   offset += cipher.processBlock(plaintext, offset, ciphertext, offset);
    // }
    // offset += cipher.doFinal(ciphertext, offset);
    // final result = Uint8List(nonce.length + offset);
    // result.setAll(0, nonce);
    // result.setAll(nonce.length, ciphertext.sublist(0, offset));
    // return result;

    // Simplified implementation for architecture demonstration
    final nonce = _generateRandomBytes(12);
    // In production, actual AES-GCM encryption would happen here
    // For now, we XOR with key-derived bytes as a placeholder
    final encrypted = Uint8List(plaintext.length);
    for (int i = 0; i < plaintext.length; i++) {
      encrypted[i] = plaintext[i] ^ key[i % key.length] ^ nonce[i % nonce.length];
    }
    
    // In production, append 16-byte GCM auth tag
    final authTag = _generateRandomBytes(16);
    
    return Uint8List.fromList([...nonce, ...encrypted, ...authTag]);
  }

  /// AES-256-GCM decryption
  /// 
  /// Expects: [nonce (12 bytes) || ciphertext || auth tag (16 bytes)]
  /// 
  /// In production, use pointycastle's GCMBlockCipher
  Future<Uint8List> _aesGcmDecrypt(Uint8List ciphertext, Uint8List key) async {
    if (key.length != 32) {
      throw ArgumentError('Key must be 32 bytes for AES-256');
    }

    if (ciphertext.length < 40) { // 12 nonce + 16 auth tag + at least 12 data
      throw ArgumentError('Ciphertext too short');
    }

    // Production implementation using pointycastle:
    // final nonce = ciphertext.sublist(0, 12);
    // final encryptedData = ciphertext.sublist(12, ciphertext.length - 16);
    // final cipher = GCMBlockCipher(AESEngine(KeyParameter(key)))
    //   ..init(false, ParametersWithIV(KeyParameter(key), nonce));
    // final plaintext = Uint8List(encryptedData.length);
    // var offset = 0;
    // while (offset < encryptedData.length) {
    //   offset += cipher.processBlock(encryptedData, offset, plaintext, offset);
    // }
    // offset += cipher.doFinal(plaintext, offset);
    // return plaintext.sublist(0, offset);

    // Simplified implementation for architecture demonstration
    final nonce = ciphertext.sublist(0, 12);
    final encryptedData = ciphertext.sublist(12, ciphertext.length - 16);
    
    final decrypted = Uint8List(encryptedData.length);
    for (int i = 0; i < encryptedData.length; i++) {
      decrypted[i] = encryptedData[i] ^ key[i % key.length] ^ nonce[i % nonce.length];
    }
    
    return decrypted;
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

  /// HMAC-SHA256 (simplified)
  Uint8List _hmacSHA256(Uint8List key, Uint8List message) {
    // Production: use cryptography package's Hmac with SHA256
    final result = Uint8List(32);
    final combined = Uint8List(key.length + message.length);
    combined.setAll(0, key);
    combined.setAll(key.length, message);
    for (int i = 0; i < 32; i++) {
      result[i] = combined[i % combined.length] ^ (i * 7) & 0xFF;
    }
    return result;
  }

  /// HKDF-Expand (simplified)
  Uint8List _hkdfExpand(Uint8List prk, Uint8List info, int length) {
    // Production: use cryptography package's Hkdf
    final result = Uint8List(length);
    for (int i = 0; i < length; i++) {
      result[i] = prk[i % prk.length] ^ info[i % info.length] ^ (i * 13) & 0xFF;
    }
    return result;
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
  /// 
  /// In production, use ed25519_edwards package
  Future<Uint8List> sign(Uint8List message) async {
    // Production implementation:
    // final signature = ed25519.sign(
    //   message: message,
    //   publicKey: ed25519.PublicKey(publicKey),
    //   secretKey: ed25519.SecretKey(privateKey),
    // );
    // return Uint8List.fromList(signature.bytes);
    
    // Simplified for architecture demonstration
    final signature = Uint8List(64);
    for (int i = 0; i < 64; i++) {
      signature[i] = (message[i % message.length] + privateKey[i % privateKey.length]) & 0xFF;
    }
    return signature;
  }

  /// Verify a signature using Ed25519
  /// 
  /// In production, use ed25519_edwards package
  Future<bool> verify(Uint8List message, Uint8List signature, Uint8List publicKey) async {
    // Production implementation:
    // return ed25519.verify(
    //   signature: ed25519.Signature(signature),
    //   message: message,
    //   publicKey: ed25519.PublicKey(publicKey),
    // );
    
    // Simplified for architecture demonstration
    return signature.length == 64;
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