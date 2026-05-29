/// CODEX Fabric SDK - Self-Hosted Zero-Trust Video & Data Streaming
///
/// A secure, end-to-end encrypted streaming SDK designed for high-security
/// enterprise environments including Healthcare, FinTech, and Defense sectors.
///
/// ## Features
///
/// - **End-to-End Encryption**: All media and data streams are encrypted
///   with keys that never leave the client device.
/// - **Zero-Trust Architecture**: Never trust, always verify.
/// - **Cross-Platform**: Works on iOS, Android, Web, Windows, macOS, and Linux.
/// - **Ultra-Low Latency**: Optimized for real-time communication.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:codex_fabric/codex_fabric.dart';
///
/// // Initialize the SDK
/// final fabric = CodexFabric(
///   endpoint: 'wss://your-server.com',
///   config: FabricConfig(
///     enableE2EE: true,
///   ),
/// );
///
/// // Connect to the signaling server
/// await fabric.connect();
///
/// // Join a secure room
/// final room = await fabric.joinRoom('room-id');
///
/// // Start video stream
/// await room.startLocalVideo();
///
/// // Clean up
/// await fabric.disconnect();
/// ```
///
/// ## Security Model
///
/// The SDK implements a zero-trust security model where:
///
/// 1. **Key Generation**: Cryptographic keys are generated on the client device
///    using secure random number generators.
/// 2. **Key Exchange**: Keys are exchanged using Elliptic Curve Diffie-Hellman
///    (ECDH) key agreement.
/// 3. **Encryption**: All media is encrypted using AES-256-GCM before
///    transmission.
/// 4. **Authentication**: Messages are signed using Ed25519 for integrity.
///
/// For more information, see the [Security Documentation](https://docs.codex.inc/security).
library codex_fabric;

// Core SDK classes
export 'src/codex_fabric.dart';
export 'src/config.dart';
export 'src/types.dart';

// Signaling
export 'src/signaling/signaling_client.dart';
export 'src/signaling/messages.dart';

// WebRTC
export 'src/webrtc/peer_connection.dart';
export 'src/webrtc/media_stream.dart';

// Security
export 'src/crypto/crypto.dart';
export 'src/crypto/key_manager.dart';

// Events
export 'src/events.dart';

// Exceptions
export 'src/exceptions.dart';

/// SDK version
const String version = '0.1.0';