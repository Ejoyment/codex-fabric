import 'package:flutter/foundation.dart';

/// Configuration for CODEX Fabric SDK
class FabricConfig {
  /// Enable end-to-end encryption
  final bool enableE2EE;

  /// ICE servers for WebRTC connection
  final List<ICEServer> iceServers;

  /// Enable TURN servers for NAT traversal
  final bool enableTURN;

  /// TURN server credentials
  final String? turnUsername;

  /// TURN server password
  final String? turnPassword;

  /// Connection timeout in seconds
  final int connectionTimeout;

  /// Enable data channels
  final bool enableDataChannel;

  /// Enable video
  final bool enableVideo;

  /// Enable audio
  final bool enableAudio;

  /// Video codec preferences
  final VideoCodec videoCodec;

  /// Audio codec preferences
  final AudioCodec audioCodec;

  /// Maximum bandwidth in kbps (0 = unlimited)
  final int maxBandwidth;

  /// Enable logging
  final bool enableLogging;

  /// Log level
  final LogLevel logLevel;

  /// Create a new FabricConfig
  const FabricConfig({
    this.enableE2EE = true,
    this.iceServers = const [],
    this.enableTURN = false,
    this.turnUsername,
    this.turnPassword,
    this.connectionTimeout = 30,
    this.enableDataChannel = true,
    this.enableVideo = true,
    this.enableAudio = true,
    this.videoCodec = VideoCodec.vp9,
    this.audioCodec = AudioCodec.opus,
    this.maxBandwidth = 0,
    this.enableLogging = kDebugMode,
    this.logLevel = LogLevel.info,
  });

  /// Create a copy of this config with optional overrides
  FabricConfig copyWith({
    bool? enableE2EE,
    List<ICEServer>? iceServers,
    bool? enableTURN,
    String? turnUsername,
    String? turnPassword,
    int? connectionTimeout,
    bool? enableDataChannel,
    bool? enableVideo,
    bool? enableAudio,
    VideoCodec? videoCodec,
    AudioCodec? audioCodec,
    int? maxBandwidth,
    bool? enableLogging,
    LogLevel? logLevel,
  }) {
    return FabricConfig(
      enableE2EE: enableE2EE ?? this.enableE2EE,
      iceServers: iceServers ?? this.iceServers,
      enableTURN: enableTURN ?? this.enableTURN,
      turnUsername: turnUsername ?? this.turnUsername,
      turnPassword: turnPassword ?? this.turnPassword,
      connectionTimeout: connectionTimeout ?? this.connectionTimeout,
      enableDataChannel: enableDataChannel ?? this.enableDataChannel,
      enableVideo: enableVideo ?? this.enableVideo,
      enableAudio: enableAudio ?? this.enableAudio,
      videoCodec: videoCodec ?? this.videoCodec,
      audioCodec: audioCodec ?? this.audioCodec,
      maxBandwidth: maxBandwidth ?? this.maxBandwidth,
      enableLogging: enableLogging ?? this.enableLogging,
      logLevel: logLevel ?? this.logLevel,
    );
  }

  /// Get default ICE servers
  static List<ICEServer> getDefaultICEServers() {
    return [
      const ICEServer(urls: ['stun:stun.l.google.com:19302']),
      const ICEServer(urls: ['stun:stun1.l.google.com:19302']),
      const ICEServer(urls: ['stun:stun2.l.google.com:19302']),
      const ICEServer(urls: ['stun:stun3.l.google.com:19302']),
      const ICEServer(urls: ['stun:stun4.l.google.com:19302']),
    ];
  }
}

/// ICE server configuration
class ICEServer {
  /// ICE server URLs
  final List<String> urls;

  /// Username for authentication (TURN)
  final String? username;

  /// Credential for authentication (TURN)
  final String? credential;

  const ICEServer({
    required this.urls,
    this.username,
    this.credential,
  });

  /// Create a STUN server
  const ICEServer.stun(String url) : this(urls: [url]);

  /// Create a TURN server
  const ICEServer.turn({
    required String url,
    required String username,
    required String credential,
  }) : this(
          urls: [url],
          username: username,
          credential: credential,
        );

  /// Check if this is a TURN server
  bool get isTURN => urls.any((url) => url.startsWith('turn:'));

  /// Check if this is a STUN server
  bool get isSTUN => urls.any((url) => url.startsWith('stun:'));
}

/// Video codec options
enum VideoCodec {
  /// VP8 codec
  vp8,

  /// VP9 codec
  vp9,

  /// H264 codec
  h264,

  /// AV1 codec
  av1,
}

/// Audio codec options
enum AudioCodec {
  /// Opus codec
  opus,

  /// PCMU codec
  pcmu,

  /// PCMA codec
  pcma,
}

/// Log level options
enum LogLevel {
  /// No logging
  none,

  /// Error level
  error,

  /// Warning level
  warning,

  /// Info level
  info,

  /// Debug level
  debug,

  /// Verbose level
  verbose,
}