/// Connection state of the SDK
enum ConnectionState {
  /// Not connected
  disconnected,

  /// Connecting to server
  connecting,

  /// Connected to server
  connected,

  /// Reconnecting
  reconnecting,

  /// Error state
  error,
}

/// Peer connection state
enum PeerState {
  /// New peer
  newPeer,

  /// Connecting
  connecting,

  /// Connected
  connected,

  /// Disconnected
  disconnected,

  /// Failed
  failed,

  /// Closed
  closed,
}

/// Media type
enum MediaType {
  /// Audio only
  audio,

  /// Video only
  video,

  /// Both audio and video
  audioVideo,

  /// Data only
  data,
}

/// Room participant information
class Participant {
  /// Unique participant ID
  final String id;

  /// Display name
  final String? name;

  /// User metadata
  final Map<String, dynamic>? metadata;

  /// Whether participant is publishing
  final bool isPublishing;

  /// Whether participant is subscribed
  final bool isSubscribed;

  /// Connection state
  final PeerState state;

  /// Joined timestamp
  final DateTime joinedAt;

  /// Create a new participant
  const Participant({
    required this.id,
    this.name,
    this.metadata,
    this.isPublishing = false,
    this.isSubscribed = false,
    this.state = PeerState.newPeer,
    DateTime? joinedAt,
  }) : joinedAt = joinedAt ?? DateTime.now();

  /// Create a copy with updates
  Participant copyWith({
    String? id,
    String? name,
    Map<String, dynamic>? metadata,
    bool? isPublishing,
    bool? isSubscribed,
    PeerState? state,
    DateTime? joinedAt,
  }) {
    return Participant(
      id: id ?? this.id,
      name: name ?? this.name,
      metadata: metadata ?? this.metadata,
      isPublishing: isPublishing ?? this.isPublishing,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      state: state ?? this.state,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'metadata': metadata,
      'is_publishing': isPublishing,
      'is_subscribed': isSubscribed,
      'state': state.index,
      'joined_at': joinedAt.toIso8601String(),
    };
  }

  /// Create from JSON
  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      id: json['id'] as String,
      name: json['name'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      isPublishing: json['is_publishing'] as bool? ?? false,
      isSubscribed: json['is_subscribed'] as bool? ?? false,
      state: PeerState.values[json['state'] as int? ?? 0],
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : DateTime.now(),
    );
  }
}

/// Room information
class RoomInfo {
  /// Room ID
  final String id;

  /// Room name
  final String? name;

  /// Room metadata
  final Map<String, dynamic>? metadata;

  /// Current participants
  final List<Participant> participants;

  /// Maximum participants
  final int? maxParticipants;

  /// Whether room is locked
  final bool isLocked;

  /// Create a new room info
  const RoomInfo({
    required this.id,
    this.name,
    this.metadata,
    const List<Participant> participants = const [],
    this.maxParticipants,
    this.isLocked = false,
  });

  /// Get participant count
  int get participantCount => participants.length;

  /// Check if room is full
  bool get isFull {
    if (maxParticipants == null) return false;
    return participantCount >= maxParticipants!;
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'metadata': metadata,
      'participants': participants.map((p) => p.toJson()).toList(),
      'max_participants': maxParticipants,
      'is_locked': isLocked,
    };
  }

  /// Create from JSON
  factory RoomInfo.fromJson(Map<String, dynamic> json) {
    return RoomInfo(
      id: json['id'] as String,
      name: json['name'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      participants: (json['participants'] as List<dynamic>?)
              ?.map((p) => Participant.fromJson(p as Map<String, dynamic>))
              .toList() ??
          const [],
      maxParticipants: json['max_participants'] as int?,
      isLocked: json['is_locked'] as bool? ?? false,
    );
  }
}

/// Track information
class TrackInfo {
  /// Track ID
  final String id;

  /// Track kind (audio/video)
  final String kind;

  /// Track label
  final String label;

  /// Whether track is enabled
  final bool enabled;

  /// Whether track is muted
  final bool muted;

  /// Create a new track info
  const TrackInfo({
    required this.id,
    required this.kind,
    required this.label,
    this.enabled = true,
    this.muted = false,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind,
      'label': label,
      'enabled': enabled,
      'muted': muted,
    };
  }

  /// Create from JSON
  factory TrackInfo.fromJson(Map<String, dynamic> json) {
    return TrackInfo(
      id: json['id'] as String,
      kind: json['kind'] as String,
      label: json['label'] as String,
      enabled: json['enabled'] as bool? ?? true,
      muted: json['muted'] as bool? ?? false,
    );
  }
}

/// Connection statistics
class ConnectionStats {
  /// Bytes sent
  final int bytesSent;

  /// Bytes received
  final int bytesReceived;

  /// Packets sent
  final int packetsSent;

  /// Packets received
  final int packetsReceived;

  /// Packets lost
  final int packetsLost;

  /// Round trip time in milliseconds
  final int? roundTripTime;

  /// Jitter in milliseconds
  final double? jitter;

  /// Create connection stats
  const ConnectionStats({
    this.bytesSent = 0,
    this.bytesReceived = 0,
    this.packetsSent = 0,
    this.packetsReceived = 0,
    this.packetsLost = 0,
    this.roundTripTime,
    this.jitter,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'bytes_sent': bytesSent,
      'bytes_received': bytesReceived,
      'packets_sent': packetsSent,
      'packets_received': packetsReceived,
      'packets_lost': packetsLost,
      'round_trip_time': roundTripTime,
      'jitter': jitter,
    };
  }
}