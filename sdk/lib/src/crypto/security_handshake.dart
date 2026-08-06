import 'dart:typed_data';

import 'key_manager.dart';
import '../signaling/messages.dart';

/// Orchestrates the end-to-end encryption (E2EE) handshake between peers.
///
/// This manager coordinates the key exchange protocol ensuring that:
/// - Cryptographic keys are generated exclusively on the client device
/// - Private keys NEVER touch the signaling server or any intermediate node
/// - Only public keys are transmitted over the signaling channel
/// - Session encryption keys are derived locally using ECDH + HKDF
///
/// ## Handshake Flow
///
/// ```
/// Client A                                    Client B
///   |                                            |
///   |-- generateKeys()                           |-- generateKeys()
///   |                                            |
///   |--- key-exchange (pubKeys) ---------------->|
///   |                                            |-- deriveSessionKeys(A.pub)
///   |<-------- key-exchange (pubKeys) -----------|
///   |-- deriveSessionKeys(B.pub)                 |
///   |                                            |
///   |========= E2EE Channel Established =========|
/// ```
///
/// The signaling server acts only as a relay for public keys. It has
/// zero knowledge of the derived session keys and cannot decrypt traffic.
class SecurityHandshake {
  /// The local key manager handling cryptographic operations
  final KeyManager _keyManager;

  /// State machine tracking the handshake progress
  SecurityHandshakeState _state = SecurityHandshakeState.idle;

  /// Map of peer ID -> their public keys
  final Map<String, PeerPublicKeys> _peerKeys = {};

  /// Map of peer exchange public key -> session keys
  final Map<String, SessionInfo> _establishedSessions = {};

  /// Callback when handshake completes for a peer
  void Function(String peerId, SessionInfo session)? onHandshakeComplete;

  /// Callback when handshake fails
  void Function(String peerId, String error)? onHandshakeFailed;

  /// Create a new SecurityHandshake instance
  SecurityHandshake({
    required KeyManager keyManager,
    this.onHandshakeComplete,
    this.onHandshakeFailed,
  }) : _keyManager = keyManager;

  /// Get the current handshake state
  SecurityHandshakeState get state => _state;

  /// Get the local key manager
  KeyManager get keyManager => _keyManager;

  /// Whether E2EE is established with a specific peer
  bool isSessionEstablished(String peerId) {
    final peerKeys = _peerKeys[peerId];
    if (peerKeys == null) return false;
    return _establishedSessions.containsKey(peerKeys.exchangePublicKey);
  }

  /// Get session info for a peer (if established)
  SessionInfo? getSessionInfo(String peerId) {
    final peerKeys = _peerKeys[peerId];
    if (peerKeys == null) return null;
    return _establishedSessions[peerKeys.exchangePublicKey];
  }

  /// Initialize the handshake by initializing the key manager.
  ///
  /// This generates the signing and exchange key pairs locally.
  /// Call this once when the client connects to the signaling server.
  Future<void> initialize() async {
    _state = SecurityHandshakeState.initializing;
    
    try {
      await _keyManager.initialize();
      _state = SecurityHandshakeState.ready;
    } catch (e) {
      _state = SecurityHandshakeState.error;
      rethrow;
    }
  }

  /// Create a key exchange message to send to a specific peer.
  ///
  /// This message contains ONLY the local public keys. The private keys
  /// remain securely stored in the local KeyManager and are never serialized.
  ///
  /// Returns a [KeyExchangeMessage] ready to be sent via the signaling server.
  Future<KeyExchangeMessage> createKeyExchangeMessage(String targetPeerId) async {
    if (!_keyManager.isInitialized) {
      throw StateError('KeyManager not initialized. Call initialize() first.');
    }

    _state = SecurityHandshakeState.exchanging;

    return KeyExchangeMessage(
      peerId: targetPeerId,
      signingPublicKey: _keyManager.signingPublicKey,
      exchangePublicKey: _keyManager.exchangePublicKey,
    );
  }

  /// Process an incoming key exchange message from a remote peer.
  ///
  /// This method:
  /// 1. Stores the peer's public keys
  /// 2. Performs ECDH key exchange using our private key + their public key
  /// 3. Derives session encryption keys locally
  /// 4. Returns an acknowledgment message
  ///
  /// The server never sees our private key or the derived session keys.
  ///
  /// Returns a [KeyExchangeAckMessage] to send back to the peer.
  Future<KeyExchangeAckMessage> processKeyExchangeMessage(
    KeyExchangeMessage message,
  ) async {
    if (!_keyManager.isInitialized) {
      throw StateError('KeyManager not initialized. Call initialize() first.');
    }

    // Store the peer's public keys
    final peerKeys = PeerPublicKeys(
      peerId: message.peerId,
      signingPublicKey: message.signingPublicKey,
      exchangePublicKey: message.exchangePublicKey,
    );
    _peerKeys[message.peerId] = peerKeys;

    // Perform ECDH and derive session keys
    // This uses our private key + their public key to create shared secrets
    // The server cannot derive these keys because it never sees either private key
    await _keyManager.deriveSessionKeys(
      message.exchangePublicKey,
    );

    // Create session info
    final sessionInfo = SessionInfo(
      peerId: message.peerId,
      peerSigningPublicKey: message.signingPublicKey,
      peerExchangePublicKey: message.exchangePublicKey,
      localExchangePublicKey: _keyManager.exchangePublicKey,
      establishedAt: DateTime.now(),
    );
    _establishedSessions[message.exchangePublicKey] = sessionInfo;

    _state = SecurityHandshakeState.established;

    // Notify callback
    onHandshakeComplete?.call(message.peerId, sessionInfo);

    // Return acknowledgment containing our public keys so the initiating
    // peer can complete the handshake (server will relay this to the peer).
    return KeyExchangeAckMessage(
      peerId: message.peerId,
      status: 'established',
      signingPublicKey: _keyManager.signingPublicKey,
      exchangePublicKey: _keyManager.exchangePublicKey,
    );
  }

  /// Process a key exchange acknowledgment from a peer.
  ///
  /// This completes the handshake from the initiator's side, storing
  /// the peer's public keys and deriving session encryption keys.
  Future<void> processKeyExchangeAck(KeyExchangeAckMessage ack) async {
    if (!_keyManager.isInitialized) {
      throw StateError('KeyManager not initialized.');
    }

    if (ack.status != 'established') {
      onHandshakeFailed?.call(ack.peerId, 'Key exchange rejected: ${ack.status}');
      _state = SecurityHandshakeState.error;
      return;
    }

    // The acknowledgment carries the responder's public keys (added by the
    // server when relaying the ack back to us).
    final signingPublicKey = ack.signingPublicKey;
    final exchangePublicKey = ack.exchangePublicKey;
    if (signingPublicKey == null || exchangePublicKey == null) {
      throw StateError('Key exchange ack is missing peer public keys');
    }

    // Store the peer's public keys
    _peerKeys[ack.peerId] = PeerPublicKeys(
      peerId: ack.peerId,
      signingPublicKey: signingPublicKey,
      exchangePublicKey: exchangePublicKey,
    );

    // Derive session keys using the responder's exchange public key
    await _keyManager.deriveSessionKeys(exchangePublicKey);

    // Store the established session
    final sessionInfo = SessionInfo(
      peerId: ack.peerId,
      peerSigningPublicKey: signingPublicKey,
      peerExchangePublicKey: exchangePublicKey,
      localExchangePublicKey: _keyManager.exchangePublicKey,
      establishedAt: DateTime.now(),
    );
    _establishedSessions[exchangePublicKey] = sessionInfo;
    _state = SecurityHandshakeState.established;
    onHandshakeComplete?.call(ack.peerId, sessionInfo);
  }

  /// Encrypt data for a specific peer using the established session keys.
  ///
  /// This is a convenience method that delegates to the KeyManager's
  /// encryption using the session keys derived during the handshake.
  Future<Uint8List> encryptForPeer(Uint8List plaintext, String peerId) async {
    final peerKeys = _peerKeys[peerId];
    if (peerKeys == null) {
      throw StateError('No keys for peer $peerId. Complete handshake first.');
    }

    return _keyManager.encrypt(plaintext, peerKeys.exchangePublicKey);
  }

  /// Decrypt data from a specific peer using the established session keys.
  Future<Uint8List> decryptFromPeer(Uint8List ciphertext, String peerId) async {
    final peerKeys = _peerKeys[peerId];
    if (peerKeys == null) {
      throw StateError('No keys for peer $peerId. Complete handshake first.');
    }

    return _keyManager.decrypt(ciphertext, peerKeys.exchangePublicKey);
  }

  /// Sign data using the local Ed25519 signing key.
  ///
  /// The signature can be verified by any peer who has our signing public key.
  Future<Uint8List> signData(Uint8List data) async {
    return _keyManager.sign(data);
  }

  /// Verify a signature from a peer using their stored signing public key.
  Future<bool> verifyPeerSignature(
    Uint8List data,
    Uint8List signature,
    String peerId,
  ) async {
    final peerKeys = _peerKeys[peerId];
    if (peerKeys == null) {
      throw StateError('No keys for peer $peerId.');
    }

    return _keyManager.verify(data, signature, peerKeys.signingPublicKey);
  }

  /// Export all public keys for sharing via the signaling channel.
  ///
  /// This is safe to transmit - it contains only public information.
  Map<String, dynamic> exportPublicKeys() {
    return _keyManager.exportPublicKeys();
  }

  /// Clear all session data and peer keys.
  ///
  /// Call this when leaving a room or disconnecting.
  void clearSessions() {
    _keyManager.clearSessionKeys();
    _peerKeys.clear();
    _establishedSessions.clear();
    _state = SecurityHandshakeState.idle;
  }

  /// Dispose of all resources.
  void dispose() {
    clearSessions();
    _keyManager.dispose();
    _state = SecurityHandshakeState.disposed;
  }
}

/// States of the security handshake process
enum SecurityHandshakeState {
  /// No handshake in progress
  idle,

  /// Key manager is being initialized
  initializing,

  /// Keys are ready, waiting to start exchange
  ready,

  /// Key exchange is in progress with peers
  exchanging,

  /// E2EE session is established
  established,

  /// An error occurred during handshake
  error,

  /// The handshake has been disposed
  disposed,
}

/// Public keys from a remote peer
class PeerPublicKeys {
  /// The peer's ID
  final String peerId;

  /// Peer's Ed25519 signing public key (hex)
  final String signingPublicKey;

  /// Peer's X25519 exchange public key (hex)
  final String exchangePublicKey;

  PeerPublicKeys({
    required this.peerId,
    required this.signingPublicKey,
    required this.exchangePublicKey,
  });

  Map<String, dynamic> toJson() => {
    'peer_id': peerId,
    'signing_public_key': signingPublicKey,
    'exchange_public_key': exchangePublicKey,
  };

  factory PeerPublicKeys.fromJson(Map<String, dynamic> json) {
    return PeerPublicKeys(
      peerId: json['peer_id'] as String,
      signingPublicKey: json['signing_public_key'] as String,
      exchangePublicKey: json['exchange_public_key'] as String,
    );
  }
}

/// Information about an established E2EE session
class SessionInfo {
  /// The peer's ID
  final String peerId;

  /// Peer's Ed25519 signing public key (hex)
  final String peerSigningPublicKey;

  /// Peer's X25519 exchange public key (hex)
  final String peerExchangePublicKey;

  /// Our X25519 exchange public key (hex)
  final String localExchangePublicKey;

  /// When the session was established
  final DateTime establishedAt;

  SessionInfo({
    required this.peerId,
    required this.peerSigningPublicKey,
    required this.peerExchangePublicKey,
    required this.localExchangePublicKey,
    required this.establishedAt,
  });

  /// Duration since the session was established
  Duration get uptime => DateTime.now().difference(establishedAt);

  Map<String, dynamic> toJson() => {
    'peer_id': peerId,
    'peer_signing_public_key': peerSigningPublicKey,
    'peer_exchange_public_key': peerExchangePublicKey,
    'local_exchange_public_key': localExchangePublicKey,
    'established_at': establishedAt.toIso8601String(),
  };
}