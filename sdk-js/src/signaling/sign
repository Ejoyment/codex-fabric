/**
 * CODEX Fabric - WebSocket Signaling Client
 * 
 * Handles WebSocket connection to the signaling server and E2EE key exchange.
 */

export interface SignalingMessage {
  type: string;
  timestamp?: number;
  [key: string]: unknown;
}

export interface SignalingConfig {
  url: string;
  roomId: string;
  peerId?: string;
  reconnectAttempts?: number;
  reconnectDelay?: number;
}

type MessageHandler = (msg: SignalingMessage) => void;
type StateHandler = (state: string) => void;

export class SignalingClient {
  private _ws: WebSocket | null = null;
  private _config: SignalingConfig;
  private _clientId: string = '';
  private _handlers: Map<string, MessageHandler[]> = new Map();
  private _stateHandlers: StateHandler[] = [];
  private _connected = false;

  get clientId(): string { return this._clientId; }
  get connected(): boolean { return this._connected; }

  constructor(config: SignalingConfig) {
    this._config = {
      reconnectAttempts: 5,
      reconnectDelay: 1000,
      ...config,
    };
  }

  /**
   * Connect to the signaling server.
   */
  async connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      this._ws = new WebSocket(this._config.url);

      this._ws.onopen = () => {
        this._connected = true;
        this._emitState('connected');
      };

      this._ws.onmessage = (event) => {
        try {
          const msg: SignalingMessage = JSON.parse(event.data);
          this._handleMessage(msg);

          if (msg.type === 'welcome') {
            this._clientId = msg.id as string;
            resolve();
          }
        } catch (e) {
          reject(e);
        }
      };

      this._ws.onerror = (error) => {
        this._emitState('error');
        reject(error);
      };

      this._ws.onclose = () => {
        this._connected = false;
        this._emitState('disconnected');
      };
    });
  }

  /**
   * Join a signaling room.
   */
  async joinRoom(roomId: string): Promise<void> {
    this.send({
      type: 'join',
      room_id: roomId,
      peer_id: this._clientId,
    });
  }

  /**
   * Send a key exchange message to a peer.
   */
  sendKeyExchange(targetPeerId: string, signingPublicKey: string, exchangePublicKey: string): void {
    this.send({
      type: 'key-exchange',
      peer_id: targetPeerId,
      signing_public_key: signingPublicKey,
      exchange_public_key: exchangePublicKey,
    });
  }

  /**
   * Send a key exchange acknowledgment to a peer.
   */
  sendKeyExchangeAck(targetPeerId: string, status: string): void {
    this.send({
      type: 'key-exchange-ack',
      peer_id: targetPeerId,
      status: status,
    });
  }

  /**
   * Send a message to the signaling server.
   */
  send(msg: SignalingMessage): void {
    if (!this._ws || !this._connected) {
      throw new Error('Not connected to signaling server');
    }
    this._ws.send(JSON.stringify({ ...msg, timestamp: Date.now() }));
  }

  /**
   * Register a handler for a specific message type.
   */
  on(type: string, handler: MessageHandler): void {
    if (!this._handlers.has(type)) {
      this._handlers.set(type, []);
    }
    this._handlers.get(type)!.push(handler);
  }

  /**
   * Register a handler for connection state changes.
   */
  onState(handler: StateHandler): void {
    this._stateHandlers.push(handler);
  }

  /**
   * Disconnect from the signaling server.
   */
  disconnect(): void {
    this._ws?.close();
    this._connected = false;
  }

  private _handleMessage(msg: SignalingMessage): void {
    const handlers = this._handlers.get(msg.type) || [];
    handlers.forEach((h) => h(msg));
  }

  private _emitState(state: string): void {
    this._stateHandlers.forEach((h) => h(state));
  }
}