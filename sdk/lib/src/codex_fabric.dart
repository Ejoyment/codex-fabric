import 'config.dart';
import 'events.dart';
import 'exceptions.dart';
import 'types.dart';
import 'signaling/signaling_client.dart';
import 'webrtc/peer_connection.dart';
import 'crypto/key_manager.dart';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';

/// CODEX Fabric SDK - Main entry point
///
/// This class provides the primary interface for connecting to the CODEX Fabric
/// signaling server and managing secure peer-to-peer connections.
///
/// ## Example Usage
///
/// ```dart
/// // Initialize the SDK
/// final fabric = CodexFabric(
///   endpoint: 'wss://your-server.com',
///   config: FabricConfig(enableE2EE: true),
/// );
///
/// // Connect
/// await fabric.connect();
///
/// // Join a room
/// final room = await fabric.joinRoom('room-id');
///
/// // Start media
/// await room.startLocalVideo();
///
/// // Disconnect when done
/// await fabric.disconnect();
/// ```
class CodexFabric {
  /// Server endpoint URL
  final String endpoint;

  /// SDK configuration
  final FabricConfig config;

  /// Unique client ID
  final String clientId;

  /// Connection state
  ConnectionState _state = ConnectionState.disconnected;

  /// Signaling client
  SignalingClient? _signalingClient;

  /// WebRTC peer connection manager
  PeerConnectionManager? _peerConnectionManager;

  /// Key manager for E2EE
  KeyManager? _keyManager;

  /// Event emitter
  final EventEmitter _events = EventEmitter();

  /// Logger
  final Logger _logger;

  /// Current room
  RoomInfo? _currentRoom;

  /// Create a new CODEX Fabric instance
  CodexFabric({
    required this.endpoint,
    required this.config,
    String? clientId,
  })  : clientId = clientId ?? const Uuid().v4(),
        _logger = Logger(
          printer: PrettyPrinter(),
          level: config.enableLogging
              ? _toLogLevel(config.logLevel)
              : Level.off,
        ) {
    _logger.d('CODEX Fabric SDK initialized');
    _logger.d('Client ID: $clientId');
    _logger.d('Endpoint: $endpoint');
    _logger.d('E2EE Enabled: ${config.enableE2EE}');
  }

  /// Get current connection state
  ConnectionState get state => _state;

  /// Get event emitter for subscribing to events
  EventEmitter get events => _events;

  /// Check if connected
  bool get isConnected => _state == ConnectionState.connected;

  /// Check if E2EE is enabled
  bool get isE2EEEnabled => config.enableE2EE;

  /// Get current room info
  RoomInfo? get currentRoom => _currentRoom;

  /// Get signaling client
  SignalingClient? get signalingClient => _signalingClient;

  /// Get peer connection manager
  PeerConnectionManager? get peerConnectionManager => _peerConnectionManager;

  /// Connect to the signaling server
  ///
  /// Throws [ConnectionException] if connection fails.
  Future<void> connect() async {
    if (_state == ConnectionState.connected) {
      _logger.w('Already connected');
      return;
    }

    _updateState(ConnectionState.connecting);

    try {
      // Initialize key manager if E2EE is enabled
      if (config.enableE2EE) {
        _keyManager = KeyManager();
        await _keyManager!.initialize();
        _logger.i('Key manager initialized');
      }

      // Create signaling client
      _signalingClient = SignalingClient(
        endpoint: endpoint,
        clientId: clientId,
        config: config,
        logger: _logger,
      );

      // Set up event handlers
      _signalingClient!.onMessage = _handleSignalingMessage;
      _signalingClient!.onStateChange = _handleConnectionStateChange;

      // Connect to server
      await _signalingClient!.connect();

      // Initialize peer connection manager
      _peerConnectionManager = PeerConnectionManager(
        config: config,
        signalingClient: _signalingClient!,
        keyManager: _keyManager,
        logger: _logger,
      );

      _updateState(ConnectionState.connected);
      _logger.i('Connected to signaling server');
    } catch (e) {
      _updateState(ConnectionState.error);
      throw ConnectionException(
        message: 'Failed to connect: $e',
        code: 'CONNECTION_FAILED',
        cause: e is Exception ? e : null,
      );
    }
  }

  /// Disconnect from the signaling server
  Future<void> disconnect() async {
    if (_state == ConnectionState.disconnected) {
      return;
    }

    _logger.i('Disconnecting...');

    // Leave current room if in one
    if (_currentRoom != null) {
      await leaveRoom();
    }

    // Clean up resources
    await _peerConnectionManager?.close();
    await _signalingClient?.disconnect();

    _peerConnectionManager = null;
    _signalingClient = null;
    _keyManager = null;
    _currentRoom = null;

    _updateState(ConnectionState.disconnected);
    _logger.i('Disconnected from signaling server');
  }

  /// Join a room
  ///
  /// [roomId] - Unique room identifier
  /// [peerId] - Optional peer identifier within the room
  Future<RoomInfo> joinRoom(String roomId, {String? peerId}) async {
    if (!isConnected) {
      throw InvalidStateException(
        message: 'Must be connected before joining a room',
        code: 'NOT_CONNECTED',
      );
    }

    _logger.i('Joining room: $roomId');

    try {
      final room = await _signalingClient!.joinRoom(roomId, peerId: peerId);
      _currentRoom = room;

      _events.emit(RoomJoinedEvent(room: room));
      _logger.i('Joined room: $roomId');

      return room;
    } catch (e) {
      throw RoomException(
        message: 'Failed to join room: $e',
        code: 'JOIN_FAILED',
        cause: e is Exception ? e : null,
      );
    }
  }

  /// Leave the current room
  Future<void> leaveRoom() async {
    if (_currentRoom == null) {
      return;
    }

    _logger.i('Leaving room: ${_currentRoom!.id}');

    try {
      await _signalingClient?.leaveRoom(_currentRoom!.id);
      await _peerConnectionManager?.closeAll();

      _events.emit(RoomLeftEvent(roomId: _currentRoom!.id));
      _currentRoom = null;

      _logger.i('Left room');
    } catch (e) {
      throw RoomException(
        message: 'Failed to leave room: $e',
        code: 'LEAVE_FAILED',
        cause: e is Exception ? e : null,
      );
    }
  }

  /// Start local video stream
  Future<void> startLocalVideo({bool audio = true, bool video = true}) async {
    if (_currentRoom == null) {
      throw InvalidStateException(
        message: 'Must be in a room to start video',
        code: 'NOT_IN_ROOM',
      );
    }

    _logger.i('Starting local video');

    try {
      await _peerConnectionManager?.startLocalMedia(
        audio: audio,
        video: video,
      );

      _events.emit(MediaStartedEvent(mediaType: MediaType.audioVideo));
      _logger.i('Local video started');
    } catch (e) {
      throw MediaException(
        message: 'Failed to start video: $e',
        code: 'MEDIA_START_FAILED',
        cause: e is Exception ? e : null,
      );
    }
  }

  /// Stop local video stream
  Future<void> stopLocalVideo() async {
    _logger.i('Stopping local video');

    try {
      await _peerConnectionManager?.stopLocalMedia();
      _events.emit(MediaStoppedEvent(mediaType: MediaType.audioVideo));
      _logger.i('Local video stopped');
    } catch (e) {
      throw MediaException(
        message: 'Failed to stop video: $e',
        code: 'MEDIA_STOP_FAILED',
        cause: e is Exception ? e : null,
      );
    }
  }

  /// Subscribe to a peer's media
  Future<void> subscribeToPeer(String peerId) async {
    if (_currentRoom == null) {
      throw InvalidStateException(
        message: 'Must be in a room to subscribe',
        code: 'NOT_IN_ROOM',
      );
    }

    _logger.i('Subscribing to peer: $peerId');

    try {
      await _peerConnectionManager?.subscribe(peerId);
      _logger.i('Subscribed to peer: $peerId');
    } catch (e) {
      throw WebRTCException(
        message: 'Failed to subscribe: $e',
        code: 'SUBSCRIBE_FAILED',
        cause: e is Exception ? e : null,
      );
    }
  }

  /// Unsubscribe from a peer's media
  Future<void> unsubscribeFromPeer(String peerId) async {
    try {
      await _peerConnectionManager?.unsubscribe(peerId);
      _logger.i('Unsubscribed from peer: $peerId');
    } catch (e) {
      throw WebRTCException(
        message: 'Failed to unsubscribe: $e',
        code: 'UNSUBSCRIBE_FAILED',
        cause: e is Exception ? e : null,
      );
    }
  }

  /// Send a data message to a peer
  Future<void> sendToPeer(String peerId, dynamic message) async {
    if (_currentRoom == null) {
      throw InvalidStateException(
        message: 'Must be in a room to send messages',
        code: 'NOT_IN_ROOM',
      );
    }

    _logger.d('Sending message to peer: $peerId');

    try {
      await _peerConnectionManager?.sendData(peerId, message);
    } catch (e) {
      throw WebRTCException(
        message: 'Failed to send message: $e',
        code: 'SEND_FAILED',
        cause: e is Exception ? e : null,
      );
    }
  }

  /// Subscribe to events
  void on(String eventType, EventListener listener) {
    _events.on(eventType, listener);
  }

  /// Unsubscribe from events
  void off(String eventType, EventListener listener) {
    _events.off(eventType, listener);
  }

  /// Update connection state
  void _updateState(ConnectionState newState) {
    final previousState = _state;
    _state = newState;

    _events.emit(ConnectionStateEvent(
      previousState: previousState,
      currentState: newState,
    ));
  }

  /// Handle signaling messages
  void _handleSignalingMessage(Map<String, dynamic> message) {
    _logger.d('Received signaling message: ${message['type']}');

    // Forward to peer connection manager
    _peerConnectionManager?.handleSignalingMessage(message);
  }

  /// Handle connection state changes
  void _handleConnectionStateChange(ConnectionState state) {
    _updateState(state);
  }

  /// Convert log level enum to logger level
  static Level _toLogLevel(LogLevel level) {
    switch (level) {
      case LogLevel.none:
        return Level.off;
      case LogLevel.error:
        return Level.error;
      case LogLevel.warning:
        return Level.warning;
      case LogLevel.info:
        return Level.info;
      case LogLevel.debug:
        return Level.debug;
      case LogLevel.verbose:
        return Level.all;
    }
  }
}