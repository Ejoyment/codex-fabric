# Getting Started with CODEX Fabric

This guide will help you integrate CODEX Fabric SDK into your application in under 30 minutes.

## Prerequisites

- Flutter 3.10.0 or higher
- Dart 3.0.0 or higher
- A CODEX Fabric signaling server (self-hosted or cloud)

## Installation

### 1. Add Dependency

Add CODEX Fabric to your `pubspec.yaml`:

```yaml
dependencies:
  codex_fabric: ^0.1.0
```

Then run:

```bash
flutter pub get
```

### 2. Initialize the SDK

```dart
import 'package:codex_fabric/codex_fabric.dart';

// Create a configuration
final config = FabricConfig(
  enableE2EE: true,  // Enable end-to-end encryption
  enableVideo: true,
  enableAudio: true,
);

// Initialize the SDK
final fabric = CodexFabric(
  endpoint: 'wss://your-signaling-server.com',
  config: config,
);
```

### 3. Connect to the Server

```dart
// Connect to the signaling server
await fabric.connect();

// Listen for connection state changes
fabric.on('connection_state', (event) {
  print('Connection state: ${event.currentState}');
});
```

### 4. Join a Room

```dart
// Join a secure room
final room = await fabric.joinRoom('room-123');

print('Joined room: ${room.id}');
```

### 5. Start Video/Audio

```dart
// Start local video and audio
await fabric.startLocalVideo(audio: true, video: true);

// Listen for when other participants join
fabric.on('peer_connected', (event) {
  print('Peer connected: ${event.peer.id}');
});
```

### 6. Clean Up

```dart
// When done, leave the room and disconnect
await fabric.leaveRoom();
await fabric.disconnect();
```

## Complete Example

Here's a complete example of a simple video call app:

```dart
import 'package:flutter/material.dart';
import 'package:codex_fabric/codex_fabric.dart';

class VideoCallPage extends StatefulWidget {
  final String roomId;
  
  const VideoCallPage({required this.roomId});

  @override
  _VideoCallPageState createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> {
  late CodexFabric _fabric;
  bool _isConnected = false;
  bool _isInRoom = false;
  List<Participant> _participants = [];

  @override
  void initState() {
    super.initState();
    _initializeFabric();
  }

  Future<void> _initializeFabric() async {
    _fabric = CodexFabric(
      endpoint: 'wss://your-signaling-server.com',
      config: const FabricConfig(enableE2EE: true),
    );

    // Set up event listeners
    _fabric.on('connection_state', _onConnectionState);
    _fabric.on('peer_connected', _onPeerConnected);
    _fabric.on('peer_disconnected', _onPeerDisconnected);

    // Connect
    await _fabric.connect();
    
    // Join room
    await _fabric.joinRoom(widget.roomId);
    
    // Start video
    await _fabric.startLocalVideo();
  }

  void _onConnectionState(FabricEvent event) {
    final stateEvent = event as ConnectionStateEvent;
    setState(() {
      _isConnected = stateEvent.currentState == ConnectionState.connected;
    });
  }

  void _onPeerConnected(FabricEvent event) {
    final peerEvent = event as PeerConnectedEvent;
    setState(() {
      _participants.add(peerEvent.peer);
    });
  }

  void _onPeerDisconnected(FabricEvent event) {
    final peerEvent = event as PeerDisconnectedEvent;
    setState(() {
      _participants.removeWhere((p) => p.id == peerEvent.peerId);
    });
  }

  @override
  void dispose() {
    _fabric.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Room: ${widget.roomId}'),
      ),
      body: Column(
        children: [
          // Local video preview
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.black,
              child: Center(
                child: Text('Local Video Preview'),
              ),
            ),
          ),
          // Remote participants
          Expanded(
            flex: 1,
            child: ListView.builder(
              itemCount: _participants.length,
              itemBuilder: (context, index) {
                final participant = _participants[index];
                return ListTile(
                  title: Text(participant.name ?? 'Participant ${participant.id}'),
                  subtitle: Text('ID: ${participant.id}'),
                );
              },
            ),
          ),
          // Controls
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.videocam),
                  onPressed: () {
                    // Toggle video
                  },
                ),
                IconButton(
                  icon: Icon(Icons.mic),
                  onPressed: () {
                    // Toggle audio
                  },
                ),
                IconButton(
                  icon: Icon(Icons.call_end, color: Colors.red),
                  onPressed: () {
                    _fabric.disconnect();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

## Configuration Options

### FabricConfig

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enableE2EE` | bool | true | Enable end-to-end encryption |
| `enableVideo` | bool | true | Enable video streaming |
| `enableAudio` | bool | true | Enable audio streaming |
| `enableDataChannel` | bool | true | Enable data channels |
| `videoCodec` | VideoCodec | VideoCodec.vp9 | Video codec preference |
| `audioCodec` | AudioCodec | AudioCodec.opus | Audio codec preference |
| `maxBandwidth` | int | 0 (unlimited) | Maximum bandwidth in kbps |
| `connectionTimeout` | int | 30 | Connection timeout in seconds |

### ICE Servers

You can configure custom ICE servers:

```dart
final config = FabricConfig(
  iceServers: [
    ICEServer.stun('stun:stun.l.google.com:19302'),
    ICEServer.turn(
      url: 'turn:your-turn-server.com:5349',
      username: 'user',
      credential: 'password',
    ),
  ],
);
```

## Troubleshooting

### Connection Issues

1. **Check WebSocket URL**: Ensure your endpoint uses `wss://` for production
2. **Firewall Rules**: Make sure port 8080 (or your configured port) is open
3. **Certificate**: For self-signed certificates, you may need to configure certificate pinning

### Media Issues

1. **Permissions**: Ensure your app has camera and microphone permissions
2. **Device Support**: Check that the device supports WebRTC
3. **Network**: Verify network connectivity and NAT traversal

## Next Steps

- [API Reference](api-reference.md) - Complete API documentation
- [Security Guide](security.md) - Security best practices
- [Deployment Guide](deployment.md) - Deploying your own signaling server
- [Examples](examples.md) - More code examples

## Support

Need help? Contact us at [support@codex.inc](mailto:support@codex.inc) or join our [Discord community](https://discord.gg/codex-fabric).