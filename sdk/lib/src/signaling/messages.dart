/// Signaling message types for CODEX Fabric protocol
library;

/// Message types for signaling protocol
class MessageType {
  /// Client -> Server messages
  static const String join = 'join';
  static const String leave = 'leave';
  static const String offer = 'offer';
  static const String answer = 'answer';
  static const String iceCandidate = 'ice-candidate';
  static const String ping = 'ping';
  
  /// E2EE Handshake messages (Client <-> Server)
  static const String keyExchange = 'key-exchange';
  static const String keyExchangeAck = 'key-exchange-ack';

  /// Server -> Client messages
  static const String welcome = 'welcome';
  static const String joined = 'joined';
  static const String ready = 'ready';
  static const String pong = 'pong';
  static const String error = 'error';
  static const String disconnect = 'disconnect';
}

/// Base signaling message
abstract class SignalingMessage {
  /// Message type
  final String type;

  /// Message timestamp
  final int timestamp;

  /// Create a new signaling message
  SignalingMessage({
    required this.type,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'timestamp': timestamp,
    };
  }

  /// Create from JSON
  factory SignalingMessage.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case MessageType.welcome:
        return WelcomeMessage.fromJson(json);
      case MessageType.joined:
        return JoinedMessage.fromJson(json);
      case MessageType.ready:
        return ReadyMessage.fromJson(json);
      case MessageType.offer:
        return OfferMessage.fromJson(json);
      case MessageType.answer:
        return AnswerMessage.fromJson(json);
      case MessageType.iceCandidate:
        return ICECandidateMessage.fromJson(json);
      case MessageType.disconnect:
        return DisconnectMessage.fromJson(json);
      case MessageType.error:
        return ErrorMessage.fromJson(json);
      case MessageType.pong:
        return PongMessage.fromJson(json);
      case MessageType.keyExchange:
        return KeyExchangeMessage.fromJson(json);
      case MessageType.keyExchangeAck:
        return KeyExchangeAckMessage.fromJson(json);
      default:
        return _UnknownMessage(type: type, json: json);
    }
  }
}

/// Welcome message from server
class WelcomeMessage extends SignalingMessage {
  /// Client ID assigned by server
  final String id;

  WelcomeMessage({
    required this.id,
  }) : super(type: MessageType.welcome);

  factory WelcomeMessage.fromJson(Map<String, dynamic> json) {
    return WelcomeMessage(
      id: json['id'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'id': id,
    };
  }
}

/// Joined room confirmation
class JoinedMessage extends SignalingMessage {
  /// Room ID
  final String roomId;

  /// Peer ID
  final String peerId;

  JoinedMessage({
    required this.roomId,
    required this.peerId,
  }) : super(type: MessageType.joined);

  factory JoinedMessage.fromJson(Map<String, dynamic> json) {
    return JoinedMessage(
      roomId: json['room_id'] as String,
      peerId: json['peer_id'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'room_id': roomId,
      'peer_id': peerId,
    };
  }
}

/// Peer ready notification
class ReadyMessage extends SignalingMessage {
  /// Peer ID that is ready
  final String peerId;

  ReadyMessage({
    required this.peerId,
  }) : super(type: MessageType.ready);

  factory ReadyMessage.fromJson(Map<String, dynamic> json) {
    return ReadyMessage(
      peerId: json['peer_id'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'peer_id': peerId,
    };
  }
}

/// WebRTC offer message
class OfferMessage extends SignalingMessage {
  /// Sender peer ID
  final String peerId;

  /// SDP offer
  final Map<String, dynamic> sdp;

  OfferMessage({
    required this.peerId,
    required this.sdp,
  }) : super(type: MessageType.offer);

  factory OfferMessage.fromJson(Map<String, dynamic> json) {
    return OfferMessage(
      peerId: json['peer_id'] as String,
      sdp: json['sdp'] as Map<String, dynamic>,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'peer_id': peerId,
      'sdp': sdp,
    };
  }
}

/// WebRTC answer message
class AnswerMessage extends SignalingMessage {
  /// Sender peer ID
  final String peerId;

  /// SDP answer
  final Map<String, dynamic> sdp;

  AnswerMessage({
    required this.peerId,
    required this.sdp,
  }) : super(type: MessageType.answer);

  factory AnswerMessage.fromJson(Map<String, dynamic> json) {
    return AnswerMessage(
      peerId: json['peer_id'] as String,
      sdp: json['sdp'] as Map<String, dynamic>,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'peer_id': peerId,
      'sdp': sdp,
    };
  }
}

/// ICE candidate message
class ICECandidateMessage extends SignalingMessage {
  /// Sender peer ID
  final String peerId;

  /// ICE candidate
  final Map<String, dynamic> candidate;

  ICECandidateMessage({
    required this.peerId,
    required this.candidate,
  }) : super(type: MessageType.iceCandidate);

  factory ICECandidateMessage.fromJson(Map<String, dynamic> json) {
    return ICECandidateMessage(
      peerId: json['peer_id'] as String,
      candidate: json['candidate'] as Map<String, dynamic>,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'peer_id': peerId,
      'candidate': candidate,
    };
  }
}

/// Disconnect notification
class DisconnectMessage extends SignalingMessage {
  /// Peer ID that disconnected
  final String peerId;

  /// Room ID
  final String roomId;

  DisconnectMessage({
    required this.peerId,
    required this.roomId,
  }) : super(type: MessageType.disconnect);

  factory DisconnectMessage.fromJson(Map<String, dynamic> json) {
    return DisconnectMessage(
      peerId: json['peer_id'] as String,
      roomId: json['room_id'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'peer_id': peerId,
      'room_id': roomId,
    };
  }
}

/// Error message
class ErrorMessage extends SignalingMessage {
  /// Error message
  final String error;

  ErrorMessage({
    required this.error,
  }) : super(type: MessageType.error);

  factory ErrorMessage.fromJson(Map<String, dynamic> json) {
    return ErrorMessage(
      error: json['error'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'error': error,
    };
  }
}

/// Pong response
class PongMessage extends SignalingMessage {
  PongMessage() : super(type: MessageType.pong);

  factory PongMessage.fromJson(Map<String, dynamic> json) {
    return PongMessage();
  }
}

/// Join room request
class JoinRequest extends SignalingMessage {
  /// Room ID to join
  final String roomId;

  /// Peer ID
  final String peerId;

  JoinRequest({
    required this.roomId,
    required this.peerId,
  }) : super(type: MessageType.join);

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'room_id': roomId,
      'peer_id': peerId,
    };
  }
}

/// Leave room request
class LeaveRequest extends SignalingMessage {
  /// Room ID to leave
  final String roomId;

  LeaveRequest({
    required this.roomId,
  }) : super(type: MessageType.leave);

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'room_id': roomId,
    };
  }
}

/// Ping request
class PingRequest extends SignalingMessage {
  PingRequest() : super(type: MessageType.ping);
}

// ==================== E2EE Handshake Messages ====================

/// Key exchange initiation message (Client -> Server -> Peer)
/// 
/// This message contains the client's public keys for establishing
/// end-to-end encryption. Only public keys are transmitted; private
/// keys NEVER leave the client device.
class KeyExchangeMessage extends SignalingMessage {
  /// Target peer ID
  final String peerId;

  /// Sender's Ed25519 signing public key (hex encoded)
  final String signingPublicKey;

  /// Sender's X25519 exchange public key (hex encoded)
  final String exchangePublicKey;

  /// Optional: Signed challenge for authentication
  final String? signature;

  KeyExchangeMessage({
    required this.peerId,
    required this.signingPublicKey,
    required this.exchangePublicKey,
    this.signature,
  }) : super(type: MessageType.keyExchange);

  factory KeyExchangeMessage.fromJson(Map<String, dynamic> json) {
    return KeyExchangeMessage(
      peerId: json['peer_id'] as String,
      signingPublicKey: json['signing_public_key'] as String,
      exchangePublicKey: json['exchange_public_key'] as String,
      signature: json['signature'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'peer_id': peerId,
      'signing_public_key': signingPublicKey,
      'exchange_public_key': exchangePublicKey,
      if (signature != null) 'signature': signature,
    };
  }
}

/// Key exchange acknowledgment (Server -> Client)
/// 
/// Confirms that the key exchange message was forwarded to the target peer.
class KeyExchangeAckMessage extends SignalingMessage {
  /// The peer ID that received the key exchange
  final String peerId;

  /// Status of the key exchange
  final String status;

  KeyExchangeAckMessage({
    required this.peerId,
    required this.status,
  }) : super(type: MessageType.keyExchangeAck);

  factory KeyExchangeAckMessage.fromJson(Map<String, dynamic> json) {
    return KeyExchangeAckMessage(
      peerId: json['peer_id'] as String,
      status: json['status'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'peer_id': peerId,
      'status': status,
    };
  }
}

/// Catch-all for unknown or unrecognized message types
class _UnknownMessage extends SignalingMessage {
  /// The raw JSON data
  final Map<String, dynamic> _json;

  _UnknownMessage({
    required String type,
    required Map<String, dynamic> json,
  })  : _json = json,
        super(type: type, timestamp: json['timestamp'] as int?);

  @override
  Map<String, dynamic> toJson() => _json;
}
