/// Base exception for CODEX Fabric SDK
class CodexException implements Exception {
  /// Error message
  final String message;

  /// Error code
  final String? code;

  /// Underlying cause
  final Exception? cause;

  /// Create a new CodexException
  const CodexException({
    required this.message,
    this.code,
    this.cause,
  });

  @override
  String toString() {
    if (cause != null) {
      return 'CodexException($code): $message - Cause: $cause';
    }
    return 'CodexException($code): $message';
  }
}

/// Connection exception
class ConnectionException extends CodexException {
  const ConnectionException({
    required super.message,
    super.code,
    super.cause,
  });
}

/// Authentication exception
class AuthenticationException extends CodexException {
  const AuthenticationException({
    required super.message,
    super.code,
    super.cause,
  });
}

/// WebRTC exception
class WebRTCException extends CodexException {
  const WebRTCException({
    required super.message,
    super.code,
    super.cause,
  });
}

/// Signaling exception
class SignalingException extends CodexException {
  const SignalingException({
    required super.message,
    super.code,
    super.cause,
  });
}

/// Encryption exception
class EncryptionException extends CodexException {
  const EncryptionException({
    required super.message,
    super.code,
    super.cause,
  });
}

/// Room exception
class RoomException extends CodexException {
  const RoomException({
    required super.message,
    super.code,
    super.cause,
  });
}

/// Media exception
class MediaException extends CodexException {
  const MediaException({
    required super.message,
    super.code,
    super.cause,
  });
}

/// Configuration exception
class ConfigException extends CodexException {
  const ConfigException({
    required super.message,
    super.code,
    super.cause,
  });
}

/// Timeout exception
class TimeoutException extends CodexException {
  const TimeoutException({
    required super.message,
    super.code,
    super.cause,
  });
}

/// Invalid state exception
class InvalidStateException extends CodexException {
  const InvalidStateException({
    required super.message,
    super.code,
    super.cause,
  });
}

/// Permission denied exception
class PermissionDeniedException extends CodexException {
  const PermissionDeniedException({
    required super.message,
    super.code,
    super.cause,
  });
}

/// Network exception
class NetworkException extends CodexException {
  const NetworkException({
    required super.message,
    super.code,
    super.cause,
  });
}