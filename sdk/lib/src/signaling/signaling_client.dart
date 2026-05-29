import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:logger/logger.dart';
import '../config.dart';
import '../types.dart';
import '../events.dart';

/// Signaling message types
class SignalingMessageType {
  static const String welcome = 'welcome';
  static const String joined = 'joined';
  static const String ready = 'ready';
  static const String offer = 'offer';
  static const String answer = 'answer';
  static const String iceCandidate = 'ice-candidate';
  static const String disconnect = 'disconnect';
  static const String error = 'error';
  static const String pong = 'pong';
}

/// Callback for signaling messages
typedef MessageCallback = void Function(Map<String, dynamic> message);

/// Callback for connection state changes
typedef StateChangeCallback = void Function(ConnectionState state);

/// Signaling client for WebSocket communication with the server
class SignalingClient {
  /// Server endpoint
  final String endpoint;

  /// Client ID
  final String clientId;

  /// Configuration
  final FabricConfig config;

  /// Logger
  final Logger logger;

  /// WebSocket channel
  WebSocketChannel? _channel;

  /// Connection state
  ConnectionState _state = ConnectionState.disconnected;

  /// Message callback
  MessageCallback? onMessage;

  /// State change callback
  StateChangeCallback? onStateChange;

  /// Event emitter
  final EventEmitter _events = EventEmitter();

  /// Reconnect timer
  Timer? _reconnectTimer;

  /// Ping timer
  Timer? _pingTimer;

  /// Current room
  String? _currentRoom;

  /// Peer ID in current room
  String? _peerId;

  /// Connection attempt count
  int _reconnectAttempts = 0;

  /// Maximum reconnect attempts
  static const int maxReconnectAttempts = 5;

  /// Create a new signaling client
  SignalingClient({
    required this.endpoint,
    required this.clientId,
    required this.config,
    required this.logger,
  });

  /// Get current connection state
  ConnectionState get state => _state;

  /// Check if connected
  bool get isConnected => _state == ConnectionState.connected;

  /// Connect to the signaling server
  Future<void> connect() async {
    if (_state == ConnectionState.connected) {
      logger.w('Already connected');
      return;
    }

    _updateState(ConnectionState.connecting);
    logger.d('Connecting to $endpoint');

    try {
      // Create WebSocket with custom settings
      _channel = IOWebSocketChannel.connect(
        endpoint,
        pingInterval: const Duration(seconds: 30),
        connectTimeout: Duration(seconds: config.connectionTimeout),
      );

      // Listen for messages
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      // Wait for welcome message
      await _waitForWelcome();

      // Start ping timer
      _startPingTimer();

      _reconnectAttempts = 0;
      _updateState(ConnectionState.connected);
      logger.i('Connected to signaling server');
    } catch (e) {
      _updateState(ConnectionState.error);
      throw e;
    }
  }

  /// Disconnect from the signaling server
  Future<void> disconnect() async {
    logger.d('Disconnecting...');

    _stopPingTimer();
    _stopReconnectTimer();

    await _channel?.sink.close();
    _channel = null;
    _currentRoom = null;
    _peerId = null;

    _updateState(ConnectionState.disconnected);
    logger.i('Disconnected from signaling server');
  }

  /// Join a room
  Future<RoomInfo> joinRoom(String roomId, {String? peerId}) async {
    if (!isConnected) {
      throw StateError('Not connected');
    }

    _currentRoom = roomId;
    _peerId = peerId;

    final completer = Completer<RoomInfo>();

    void handleJoined(FabricEvent event) {
      if (event is RoomJoinedEvent) {
        _events.off('room_joined', handleJoined);
        completer.complete(event.room);
      }
    }

    _events.on('room_joined', handleJoined);

    // Send join message
    _send({
      'type': 'join',
      'room_id': roomId,
      'peer_id': peerId ?? clientId,
    });

    // Wait for joined response
    return completer.future.timeout(
      Duration(seconds: config.connectionTimeout),
      onTimeout: () {
        _events.off('room_joined', handleJoined);
        throw TimeoutException(
          message: 'Room join timeout',
          code: 'JOIN_TIMEOUT',
        );
      },
    );
  }

  /// Leave a room
  Future<void> leaveRoom(String roomId) async {
    if (!isConnected || _currentRoom != roomId) {
      return;
    }

    _send({
      'type': 'leave',
      'room_id': roomId,
    });

    _currentRoom = null;
    _peerId = null;
  }

  /// Send an offer
  Future<void> sendOffer(String roomId, String peerId, Map<String, dynamic> sdp) async {
    _send({
      'type': 'offer',
      'room_id': roomId,
      'peer_id': peerId,
      'sdp': sdp,
    });
  }

  /// Send an answer
  Future<void> sendAnswer(String roomId, String peerId, Map<String, dynamic> sdp) async {
    _send({
      'type': 'answer',
      'room_id': roomId,
      'peer_id': peerId,
      'sdp': sdp,
    });
  }

  /// Send an ICE candidate
  Future<void> sendICECandidate(String roomId, String peerId, Map<String, dynamic> candidate) async {
    _send({
      'type': 'ice-candidate',
      'room_id': roomId,
      'peer_id': peerId,
      'candidate': candidate,
    });
  }

  /// Send a message
  void _send(Map<String, dynamic> message) {
    if (_channel == null || !isConnected) {
      throw StateError('Not connected');
    }

    message['timestamp'] = DateTime.now().millisecondsSinceEpoch;
    final json = jsonEncode(message);
    logger.d('Sending: $json');
    _channel!.sink.add(json);
  }

  /// Handle incoming messages
  void _onMessage(dynamic data) {
    try {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      logger.d('Received: ${message['type']}');

      _handleMessage(message);
    } catch (e) {
      logger.e('Failed to parse message: $e');
    }
  }

  /// Handle a signaling message
  void _handleMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;

    switch (type) {
      case SignalingMessageType.welcome:
        // Welcome message handled during connection
        break;

      case SignalingMessageType.joined:
        _events.emit(RoomJoinedEvent(
          room: RoomInfo(
            id: message['room_id'] as String,
            participants: const [],
          ),
        ));
        break;

      case SignalingMessageType.ready:
        // Peer is ready
        _events.emit(PeerConnectedEvent(
          peer: Participant(id: message['peer_id'] as String),
        ));
        break;

      case SignalingMessageType.offer:
      case SignalingMessageType.answer:
      case SignalingMessageType.iceCandidate:
        // Forward to message callback
        onMessage?.call(message);
        break;

      case SignalingMessageType.disconnect:
        // Peer disconnected
        _events.emit(PeerDisconnectedEvent(peerId: message['peer_id'] as String));
        break;

      case SignalingMessageType.error:
        _events.emit(ErrorEvent(
          code: 'SERVER_ERROR',
          message: message['error'] as String,
        ));
        break;

      case SignalingMessageType.pong:
        // Pong response to our ping
        break;

      default:
        logger.w('Unknown message type: $type');
    }
  }

  /// Handle WebSocket errors
  void _onError(dynamic error) {
    logger.e('WebSocket error: $error');
    _events.emit(ErrorEvent(
      code: 'WEBSOCKET_ERROR',
      message: error.toString(),
    ));
    _attemptReconnect();
  }

  /// Handle WebSocket close
  void _onDone() {
    logger.d('WebSocket closed');

    if (_state == ConnectionState.connected) {
      _attemptReconnect();
    }
  }

  /// Wait for welcome message
  Future<void> _waitForWelcome() async {
    final completer = Completer<void>();
    final timeout = Duration(seconds: config.connectionTimeout);

    void checkMessage(FabricEvent event) {
      if (event is ConnectionStateEvent &&
          event.currentState == ConnectionState.connected) {
        _events.off('connection_state', checkMessage);
        completer.complete();
      }
    }

    _events.on('connection_state', checkMessage);

    return completer.future.timeout(timeout, onTimeout: () {
      _events.off('connection_state', checkMessage);
      throw TimeoutException(
        message: 'Welcome message timeout',
        code: 'WELCOME_TIMEOUT',
      );
    });
  }

  /// Update connection state
  void _updateState(ConnectionState newState) {
    final previousState = _state;
    _state = newState;

    _events.emit(ConnectionStateEvent(
      previousState: previousState,
      currentState: newState,
    ));

    onStateChange?.call(newState);
  }

  /// Start ping timer
  void _startPingTimer() {
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isConnected) {
        _send({'type': 'ping'});
      }
    });
  }

  /// Stop ping timer
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Attempt to reconnect
  void _attemptReconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      logger.e('Max reconnect attempts reached');
      _updateState(ConnectionState.error);
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts);

    logger.d('Attempting reconnect in ${delay.inSeconds}s (attempt $_reconnectAttempts/$maxReconnectAttempts)');

    _updateState(ConnectionState.reconnecting);

    _reconnectTimer = Timer(delay, () {
      connect().catchError((e) {
        logger.e('Reconnect failed: $e');
        _attemptReconnect();
      });
    });
  }

  /// Stop reconnect timer
  void _stopReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// Subscribe to events
  void on(String event, EventListener listener) {
    _events.on(event, listener);
  }

  /// Unsubscribe from events
  void off(String event, EventListener listener) {
    _events.off(event, listener);
  }
}