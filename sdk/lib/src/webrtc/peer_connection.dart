import 'dart:async';
import 'package:logger/logger.dart';
import '../config.dart';
import '../types.dart';
import '../events.dart';
import '../signaling/signaling_client.dart';
import '../crypto/key_manager.dart';

/// Manages WebRTC peer connections
class PeerConnectionManager {
  /// Configuration
  final FabricConfig config;

  /// Signaling client
  final SignalingClient signalingClient;

  /// Key manager for E2EE
  final KeyManager? keyManager;

  /// Logger
  final Logger logger;

  /// Active peer connections
  final Map<String, PeerConnectionWrapper> _connections = {};

  /// Local media stream
  dynamic _localStream;

  /// Event emitter
  final EventEmitter _events = EventEmitter();

  /// Create a new peer connection manager
  PeerConnectionManager({
    required this.config,
    required this.signalingClient,
    this.keyManager,
    required this.logger,
  });

  /// Start local media (audio/video)
  Future<void> startLocalMedia({bool audio = true, bool video = true}) async {
    logger.i('Starting local media: audio=$audio, video=$video');

    try {
      // In a real implementation, this would use flutter_webrtc
      // to get the actual media stream
      //
      // final stream = await navigator.mediaDevices.getUserMedia({
      //   'audio': audio,
      //   'video': video ? {'width': 1280, 'height': 720} : false,
      // });
      // _localStream = stream;

      logger.i('Local media started');
    } catch (e) {
      throw Exception('Failed to get local media: $e');
    }
  }

  /// Stop local media
  Future<void> stopLocalMedia() async {
    logger.i('Stopping local media');

    if (_localStream != null) {
      // In a real implementation:
      // _localStream.getTracks().forEach((track) => track.stop());
      _localStream = null;
    }

    logger.i('Local media stopped');
  }

  /// Subscribe to a peer's media
  Future<void> subscribe(String peerId) async {
    logger.i('Subscribing to peer: $peerId');

    if (_connections.containsKey(peerId)) {
      logger.w('Already subscribed to peer: $peerId');
      return;
    }

    try {
      // Create peer connection
      final connection = await _createPeerConnection(peerId);
      _connections[peerId] = connection;

      // Create offer
      final offer = await connection.createOffer();

      // Send offer to peer
      await signalingClient.sendOffer(
        signalingClient.toString(), // This would be the room ID
        peerId,
        offer,
      );

      logger.i('Subscribed to peer: $peerId');
    } catch (e) {
      throw Exception('Failed to subscribe to peer: $e');
    }
  }

  /// Unsubscribe from a peer
  Future<void> unsubscribe(String peerId) async {
    logger.i('Unsubscribing from peer: $peerId');

    if (_connections.containsKey(peerId)) {
      await _connections[peerId]!.close();
      _connections.remove(peerId);
    }

    logger.i('Unsubscribed from peer: $peerId');
  }

  /// Send data to a peer
  Future<void> sendData(String peerId, dynamic message) async {
    final connection = _connections[peerId];
    if (connection == null) {
      throw StateError('No connection to peer: $peerId');
    }

    await connection.sendData(message);
  }

  /// Handle signaling messages
  void handleSignalingMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;
    final peerId = message['peer_id'] as String?;

    if (peerId == null) {
      logger.w('Received message without peer_id');
      return;
    }

    switch (type) {
      case 'offer':
        _handleOffer(peerId, message);
        break;
      case 'answer':
        _handleAnswer(peerId, message);
        break;
      case 'ice-candidate':
        _handleICECandidate(peerId, message);
        break;
    }
  }

  /// Handle incoming offer
  Future<void> _handleOffer(String peerId, Map<String, dynamic> message) async {
    logger.i('Received offer from: $peerId');

    try {
      // Create peer connection
      final connection = await _createPeerConnection(peerId);
      _connections[peerId] = connection;

      // Set remote description
      await connection.setRemoteDescription(message['sdp'] as Map<String, dynamic>);

      // Create answer
      final answer = await connection.createAnswer();

      // Send answer
      await signalingClient.sendAnswer(
        signalingClient.toString(),
        peerId,
        answer,
      );

      logger.i('Answer sent to: $peerId');
    } catch (e) {
      logger.e('Failed to handle offer: $e');
    }
  }

  /// Handle incoming answer
  Future<void> _handleAnswer(String peerId, Map<String, dynamic> message) async {
    logger.i('Received answer from: $peerId');

    final connection = _connections[peerId];
    if (connection == null) {
      logger.w('No connection for peer: $peerId');
      return;
    }

    try {
      await connection.setRemoteDescription(message['sdp'] as Map<String, dynamic>);
      logger.i('Remote description set for: $peerId');
    } catch (e) {
      logger.e('Failed to handle answer: $e');
    }
  }

  /// Handle incoming ICE candidate
  Future<void> _handleICECandidate(String peerId, Map<String, dynamic> message) async {
    final connection = _connections[peerId];
    if (connection == null) {
      logger.w('No connection for peer: $peerId');
      return;
    }

    try {
      await connection.addICECandidate(message['candidate'] as Map<String, dynamic>);
    } catch (e) {
      logger.e('Failed to add ICE candidate: $e');
    }
  }

  /// Create a peer connection
  Future<PeerConnectionWrapper> _createPeerConnection(String peerId) async {
    final connection = PeerConnectionWrapper(
      peerId: peerId,
      config: config,
      keyManager: keyManager,
      logger: logger,
    );

    // Set up event handlers
    connection.onICECandidate = (candidate) async {
      await signalingClient.sendICECandidate(
        signalingClient.toString(),
        peerId,
        candidate,
      );
    };

    connection.onStateChange = (state) {
      _events.emit(PeerConnectedEvent(
        peer: Participant(id: peerId, state: state),
      ));
    };

    await connection.initialize();
    return connection;
  }

  /// Close all connections
  Future<void> closeAll() async {
    logger.i('Closing all peer connections');

    for (final entry in _connections.entries.toList()) {
      await entry.value.close();
      _connections.remove(entry.key);
    }

    logger.i('All peer connections closed');
  }

  /// Close the manager
  Future<void> close() async {
    await stopLocalMedia();
    await closeAll();
  }

  /// Get connection stats
  Map<String, dynamic> getStats() {
    return {
      'active_connections': _connections.length,
      'connections': _connections.values.map((c) => c.getStats()).toList(),
    };
  }
}

/// Wrapper for a WebRTC peer connection
class PeerConnectionWrapper {
  /// Peer ID
  final String peerId;

  /// Configuration
  final FabricConfig config;

  /// Key manager
  final KeyManager? keyManager;

  /// Logger
  final Logger logger;

  /// Connection state
  PeerState _state = PeerState.newPeer;

  /// ICE candidate callback
  Function(Map<String, dynamic>)? onICECandidate;

  /// State change callback
  Function(PeerState)? onStateChange;

  /// Data channel
  dynamic _dataChannel;

  /// Create a new peer connection wrapper
  PeerConnectionWrapper({
    required this.peerId,
    required this.config,
    this.keyManager,
    required this.logger,
  });

  /// Get connection state
  PeerState get state => _state;

  /// Initialize the peer connection
  Future<void> initialize() async {
    logger.d('Initializing peer connection: $peerId');
    _updateState(PeerState.connecting);

    // In a real implementation, this would create the actual
    // RTCPeerConnection using flutter_webrtc

    _updateState(PeerState.connected);
    logger.d('Peer connection initialized: $peerId');
  }

  /// Create an offer
  Future<Map<String, dynamic>> createOffer() async {
    logger.d('Creating offer for: $peerId');

    // In a real implementation:
    // final offer = await _pc.createOffer();
    // await _pc.setLocalDescription(offer);
    // return offer.toMap();

    return {
      'type': 'offer',
      'sdp': 'mock-sdp-offer',
    };
  }

  /// Create an answer
  Future<Map<String, dynamic>> createAnswer() async {
    logger.d('Creating answer for: $peerId');

    return {
      'type': 'answer',
      'sdp': 'mock-sdp-answer',
    };
  }

  /// Set remote description
  Future<void> setRemoteDescription(Map<String, dynamic> sdp) async {
    logger.d('Setting remote description for: $peerId');

    // In a real implementation:
    // await _pc.setRemoteDescription(RTCSessionDescription(sdp['sdp'], sdp['type']));
  }

  /// Add ICE candidate
  Future<void> addICECandidate(Map<String, dynamic> candidate) async {
    logger.d('Adding ICE candidate for: $peerId');

    // In a real implementation:
    // await _pc.addCandidate(RTCIceCandidate(candidate['candidate'], candidate['sdpMid'], candidate['sdpMLineIndex']));
  }

  /// Send data
  Future<void> sendData(dynamic message) async {
    if (_dataChannel == null) {
      throw StateError('Data channel not open');
    }

    // In a real implementation:
    // _dataChannel.send(message);
    logger.d('Sending data to: $peerId');
  }

  /// Close the connection
  Future<void> close() async {
    logger.d('Closing peer connection: $peerId');

    // In a real implementation:
    // await _pc.close();

    _updateState(PeerState.closed);
  }

  /// Get connection statistics
  Map<String, dynamic> getStats() {
    return {
      'peer_id': peerId,
      'state': state.index,
      'has_data_channel': _dataChannel != null,
    };
  }

  /// Update state
  void _updateState(PeerState newState) {
    _state = newState;
    onStateChange?.call(newState);
  }
}