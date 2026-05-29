import 'types.dart';

/// Base event class for CODEX Fabric SDK
abstract class FabricEvent {
  /// Event type
  final String type;

  /// Event timestamp
  final DateTime timestamp;

  /// Create a new event
  FabricEvent({
    required this.type,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Connection state changed event
class ConnectionStateEvent extends FabricEvent {
  /// Previous state
  final ConnectionState previousState;

  /// Current state
  final ConnectionState currentState;

  /// Error message if state is error
  final String? error;

  ConnectionStateEvent({
    required this.previousState,
    required this.currentState,
    this.error,
  }) : super(type: 'connection_state');
}

/// Peer connected event
class PeerConnectedEvent extends FabricEvent {
  /// Peer information
  final Participant peer;

  PeerConnectedEvent({
    required this.peer,
  }) : super(type: 'peer_connected');
}

/// Peer disconnected event
class PeerDisconnectedEvent extends FabricEvent {
  /// Peer ID
  final String peerId;

  PeerDisconnectedEvent({
    required this.peerId,
  }) : super(type: 'peer_disconnected');
}

/// Track added event
class TrackAddedEvent extends FabricEvent {
  /// Track information
  final TrackInfo track;

  /// Peer ID who added the track
  final String peerId;

  TrackAddedEvent({
    required this.track,
    required this.peerId,
  }) : super(type: 'track_added');
}

/// Track removed event
class TrackRemovedEvent extends FabricEvent {
  /// Track ID
  final String trackId;

  /// Peer ID
  final String peerId;

  TrackRemovedEvent({
    required this.trackId,
    required this.peerId,
  }) : super(type: 'track_removed');
}

/// Room joined event
class RoomJoinedEvent extends FabricEvent {
  /// Room information
  final RoomInfo room;

  RoomJoinedEvent({
    required this.room,
  }) : super(type: 'room_joined');
}

/// Room left event
class RoomLeftEvent extends FabricEvent {
  /// Room ID
  final String roomId;

  RoomLeftEvent({
    required this.roomId,
  }) : super(type: 'room_left');
}

/// Message received event
class MessageReceivedEvent extends FabricEvent {
  /// Sender peer ID
  final String senderId;

  /// Message content
  final dynamic message;

  MessageReceivedEvent({
    required this.senderId,
    required this.message,
  }) : super(type: 'message_received');
}

/// Error event
class ErrorEvent extends FabricEvent {
  /// Error code
  final String code;

  /// Error message
  final String message;

  /// Stack trace if available
  final String? stackTrace;

  ErrorEvent({
    required this.code,
    required this.message,
    this.stackTrace,
  }) : super(type: 'error');
}

/// Encryption established event
class EncryptionEstablishedEvent extends FabricEvent {
  /// Session ID
  final String sessionId;

  /// Peer ID
  final String peerId;

  EncryptionEstablishedEvent({
    required this.sessionId,
    required this.peerId,
  }) : super(type: 'encryption_established');
}

/// Media started event
class MediaStartedEvent extends FabricEvent {
  /// Media type
  final MediaType mediaType;

  MediaStartedEvent({
    required this.mediaType,
  }) : super(type: 'media_started');
}

/// Media stopped event
class MediaStoppedEvent extends FabricEvent {
  /// Media type
  final MediaType mediaType;

  MediaStoppedEvent({
    required this.mediaType,
  }) : super(type: 'media_stopped');
}

/// Statistics event
class StatsEvent extends FabricEvent {
  /// Connection statistics
  final ConnectionStats stats;

  StatsEvent({
    required this.stats,
  }) : super(type: 'stats');
}

/// Event listener callback
typedef EventListener = void Function(FabricEvent event);

/// Event handler for managing event listeners
class EventEmitter {
  final Map<String, List<EventListener>> _listeners = {};

  /// Subscribe to an event
  void on(String eventType, EventListener listener) {
    _listeners.putIfAbsent(eventType, () => []);
    _listeners[eventType]!.add(listener);
  }

  /// Unsubscribe from an event
  void off(String eventType, EventListener listener) {
    if (_listeners.containsKey(eventType)) {
      _listeners[eventType]!.remove(listener);
    }
  }

  /// Emit an event
  void emit(FabricEvent event) {
    if (_listeners.containsKey(event.type)) {
      for (final listener in _listeners[event.type]!) {
        listener(event);
      }
    }
  }

  /// Clear all listeners for an event type
  void clear([String? eventType]) {
    if (eventType == null) {
      _listeners.clear();
    } else {
      _listeners.remove(eventType);
    }
  }

  /// Get listener count for an event type
  int listenerCount(String eventType) {
    return _listeners[eventType]?.length ?? 0;
  }
}