/**
 * @codex-fabric/sdk
 * 
 * Self-hosted, zero-trust E2EE video and data streaming SDK.
 * All keys are generated and stored on the client device.
 * Private keys NEVER leave the client.
 * 
 * Usage:
 * ```ts
 * import { CodexFabric } from '@codex-fabric/sdk';
 * 
 * const fabric = new CodexFabric({ url: 'wss://your-server:8080/ws', roomId: 'room-123' });
 * await fabric.connect();
 * await fabric.startSecureSession('peer-id');
 * fabric.encryptForPeer(Buffer.from('secret'), 'peer-id');
 * ```
 */

export { KeyManager } from './crypto/key_manager';
export { SecurityHandshake } from './crypto/security_handshake';
export type { KeyPair, SessionKeys } from './crypto/key_manager';
export type { SessionInfo, PeerKeys, HandshakeState } from './crypto/security_handshake';
export { SignalingClient } from './signaling/signaling_client';
export type { SignalingConfig, SignalingMessage } from './signaling/signaling_client';