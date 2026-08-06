package signaling

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"sync/atomic"
	"time"

	"github.com/Ejoyment/codex-fabric/backend/internal/auth"
	"github.com/Ejoyment/codex-fabric/backend/internal/config"
	"github.com/Ejoyment/codex-fabric/backend/internal/webrtc"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

// MessageType defines the type of signaling message
type MessageType string

const (
	// Client -> Server messages
	MessageTypeOffer        MessageType = "offer"
	MessageTypeAnswer       MessageType = "answer"
	MessageTypeICECandidate MessageType = "ice-candidate"
	MessageTypeJoin         MessageType = "join"
	MessageTypeLeave        MessageType = "leave"
	MessageTypePing         MessageType = "ping"

	// E2EE Handshake messages (Client <-> Server <-> Client)
	MessageTypeKeyExchange    MessageType = "key-exchange"
	MessageTypeKeyExchangeAck MessageType = "key-exchange-ack"

	// Server -> Client messages
	MessageTypeWelcome    MessageType = "welcome"
	MessageTypeJoined     MessageType = "joined"
	MessageTypeReady      MessageType = "ready"
	MessageTypePong       MessageType = "pong"
	MessageTypeError      MessageType = "error"
	MessageTypeDisconnect MessageType = "disconnect"
)

// Message represents a signaling message
type Message struct {
	Type      MessageType     `json:"type"`
	ID        string          `json:"id,omitempty"`
	RoomID    string          `json:"room_id,omitempty"`
	PeerID    string          `json:"peer_id,omitempty"`
	SDP       json.RawMessage `json:"sdp,omitempty"`
	Candidate json.RawMessage `json:"candidate,omitempty"`
	Error     string          `json:"error,omitempty"`
	Message   string          `json:"message,omitempty"`
	Timestamp int64           `json:"timestamp"`

	// E2EE Key Exchange fields
	SigningPublicKey  string `json:"signing_public_key,omitempty"`
	ExchangePublicKey string `json:"exchange_public_key,omitempty"`
	Signature         string `json:"signature,omitempty"`
	Status            string `json:"status,omitempty"`
}

// Client represents a connected WebSocket client
type Client struct {
	ID            string
	conn          *websocket.Conn
	server        *Server
	roomID        string
	peerID        string
	send          chan []byte
	authenticated bool
	userID        string
	orgID         string
	roles         []string
	lastActivity  time.Time
	mu            sync.RWMutex
}

// Server manages WebSocket connections and signaling
type Server struct {
	config    config.SignalingConfig
	webrtcMgr *webrtc.Manager
	auth      *auth.Validator
	logger    *zap.Logger
	upgrader  websocket.Upgrader
	clients   map[string]*Client
	rooms     map[string]map[string]*Client
	clientsMu sync.RWMutex
	roomsMu   sync.RWMutex
	connCount int64
	hub       *Hub
}

// Hub manages message broadcasting within rooms
type Hub struct {
	rooms map[string]chan *Message
	mu    sync.RWMutex
}

// NewServer creates a new signaling server
func NewServer(cfg config.SignalingConfig, webrtcMgr *webrtc.Manager, authValidator *auth.Validator, logger *zap.Logger) (*Server, error) {
	allowedOrigins := make(map[string]bool)
	for _, origin := range cfg.AllowedOrigins {
		allowedOrigins[origin] = true
	}

	s := &Server{
		config:    cfg,
		webrtcMgr: webrtcMgr,
		auth:      authValidator,
		logger:    logger,
		clients:   make(map[string]*Client),
		rooms:     make(map[string]map[string]*Client),
		hub: &Hub{
			rooms: make(map[string]chan *Message),
		},
		upgrader: websocket.Upgrader{
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
			CheckOrigin: func(r *http.Request) bool {
				if len(allowedOrigins) == 0 {
					return true // Allow all origins if not configured
				}
				// Allow wildcard
				if allowedOrigins["*"] {
					return true
				}
				return allowedOrigins[r.Header.Get("Origin")]
			},
			EnableCompression: cfg.EnableCompression,
		},
	}

	return s, nil
}

// HandleWebSocket handles incoming WebSocket connections
func (s *Server) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	// Check connection limit
	if int(atomic.LoadInt64(&s.connCount)) >= s.config.MaxConnections {
		s.logger.Warn("Max connections reached", zap.Int64("count", atomic.LoadInt64(&s.connCount)))
		http.Error(w, "Server at capacity", http.StatusServiceUnavailable)
		return
	}

	// Read the authenticated identity attached to the request by the auth
	// middleware. When auth is disabled no claims are present and the client
	// remains unauthenticated.
	claims := auth.ClaimsFromContext(r.Context())

	// Defensive check: if the server is configured to require authentication
	// but the request was not authorized, reject it before upgrading. This
	// protects against the middleware wrapper being accidentally bypassed.
	if s.auth != nil && s.auth.Enabled() && claims == nil {
		s.logger.Warn("Rejecting unauthenticated WebSocket connection")
		http.Error(w, "authentication required", http.StatusUnauthorized)
		return
	}

	// Upgrade HTTP connection to WebSocket
	conn, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		s.logger.Warn("WebSocket upgrade failed", zap.Error(err))
		return
	}

	// Create new client
	client := &Client{
		ID:           uuid.New().String(),
		conn:         conn,
		server:       s,
		send:         make(chan []byte, 256),
		lastActivity: time.Now(),
	}

	if claims != nil {
		client.authenticated = true
		client.userID = claims.UserID
		client.orgID = claims.OrgID
		client.roles = claims.Roles
	}

	// Register client
	s.clientsMu.Lock()
	s.clients[client.ID] = client
	s.clientsMu.Unlock()
	atomic.AddInt64(&s.connCount, 1)

	s.logger.Info("Client connected",
		zap.String("client_id", client.ID),
		zap.String("remote_addr", r.RemoteAddr),
		zap.Bool("authenticated", client.authenticated),
		zap.String("user_id", client.userID),
		zap.Int64("total_connections", atomic.LoadInt64(&s.connCount)))

	// Send welcome message
	welcomeMsg := Message{
		Type:      MessageTypeWelcome,
		ID:        client.ID,
		Timestamp: time.Now().UnixNano(),
	}
	if err := client.Send(welcomeMsg); err != nil {
		s.logger.Error("Failed to send welcome message", zap.Error(err))
	}

	// Start client handlers
	go client.writePump()
	go client.readPump()
}

// Send sends a message to a client
func (c *Client) Send(msg Message) error {
	data, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("failed to marshal message: %w", err)
	}

	select {
	case c.send <- data:
		return nil
	default:
		return fmt.Errorf("send buffer full")
	}
}

// readPump pumps messages from the WebSocket connection to the hub
func (c *Client) readPump() {
	defer func() {
		c.server.unregisterClient(c)
		c.conn.Close()
	}()

	c.conn.SetReadLimit(c.server.config.MaxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(c.server.config.PongWait))
	c.conn.SetPongHandler(func(string) error {
		c.lastActivity = time.Now()
		c.conn.SetReadDeadline(time.Now().Add(c.server.config.PongWait))
		return nil
	})

	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				c.server.logger.Error("WebSocket read error", zap.Error(err))
			}
			break
		}

		c.lastActivity = time.Now()

		var msg Message
		if err := json.Unmarshal(message, &msg); err != nil {
			c.server.logger.Warn("Failed to unmarshal message", zap.Error(err))
			continue
		}

		if err := c.server.handleMessage(c, &msg); err != nil {
			c.server.logger.Error("Failed to handle message",
				zap.String("client_id", c.ID),
				zap.String("type", string(msg.Type)),
				zap.Error(err))

			errMsg := Message{
				Type:      MessageTypeError,
				Error:     err.Error(),
				Timestamp: time.Now().UnixNano(),
			}
			c.Send(errMsg)
		}
	}
}

// writePump pumps messages from the hub to the WebSocket connection
func (c *Client) writePump() {
	ticker := time.NewTicker(c.server.config.PingInterval)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(c.server.config.WriteWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := c.conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)

			if err := w.Close(); err != nil {
				return
			}
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(c.server.config.WriteWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// handleMessage processes incoming messages from clients
func (s *Server) handleMessage(client *Client, msg *Message) error {
	switch msg.Type {
	case MessageTypeJoin:
		return s.handleJoin(client, msg)
	case MessageTypeLeave:
		return s.handleLeave(client, msg)
	case MessageTypeOffer:
		return s.handleOffer(client, msg)
	case MessageTypeAnswer:
		return s.handleAnswer(client, msg)
	case MessageTypeICECandidate:
		return s.handleICECandidate(client, msg)
	case MessageTypePing:
		return s.handlePing(client, msg)
	case MessageTypeKeyExchange:
		return s.handleKeyExchange(client, msg)
	case MessageTypeKeyExchangeAck:
		return s.handleKeyExchangeAck(client, msg)
	default:
		return fmt.Errorf("unknown message type: %s", msg.Type)
	}
}

// handleJoin handles a client joining a room
func (s *Server) handleJoin(client *Client, msg *Message) error {
	if msg.RoomID == "" {
		return fmt.Errorf("room_id is required")
	}

	client.roomID = msg.RoomID
	client.peerID = msg.PeerID

	s.roomsMu.Lock()
	if _, exists := s.rooms[msg.RoomID]; !exists {
		s.rooms[msg.RoomID] = make(map[string]*Client)
	}
	// Store by both client.ID (UUID) and peer_id for flexible lookup
	s.rooms[msg.RoomID][client.ID] = client
	if msg.PeerID != "" {
		s.rooms[msg.RoomID][msg.PeerID] = client
	}
	s.roomsMu.Unlock()

	s.logger.Info("Client joined room",
		zap.String("client_id", client.ID),
		zap.String("room_id", msg.RoomID),
		zap.String("peer_id", msg.PeerID))

	// Send joined confirmation
	joinedMsg := Message{
		Type:      MessageTypeJoined,
		RoomID:    msg.RoomID,
		PeerID:    client.ID,
		Timestamp: time.Now().UnixNano(),
	}
	client.Send(joinedMsg)

	// Notify other clients in the room
	s.broadcastToRoom(msg.RoomID, Message{
		Type:      MessageTypeReady,
		PeerID:    client.ID,
		Timestamp: time.Now().UnixNano(),
	}, client.ID)

	return nil
}

// handleLeave handles a client leaving a room
func (s *Server) handleLeave(client *Client, msg *Message) error {
	if client.roomID != "" {
		s.removeFromRoom(client.roomID, client.ID)
		client.roomID = ""
	}
	return nil
}

// handleOffer handles a WebRTC offer from a client
func (s *Server) handleOffer(client *Client, msg *Message) error {
	if msg.RoomID == "" || msg.PeerID == "" {
		return fmt.Errorf("room_id and peer_id are required")
	}

	s.roomsMu.RLock()
	room, exists := s.rooms[msg.RoomID]
	s.roomsMu.RUnlock()

	if !exists {
		return fmt.Errorf("room not found")
	}

	// Forward offer to target peer
	if peer, ok := room[msg.PeerID]; ok {
		offerMsg := Message{
			Type:      MessageTypeOffer,
			PeerID:    client.peerID,
			SDP:       msg.SDP,
			Timestamp: time.Now().UnixNano(),
		}
		return peer.Send(offerMsg)
	}

	return fmt.Errorf("peer not found in room")
}

// handleAnswer handles a WebRTC answer from a client
func (s *Server) handleAnswer(client *Client, msg *Message) error {
	if msg.RoomID == "" || msg.PeerID == "" {
		return fmt.Errorf("room_id and peer_id are required")
	}

	s.roomsMu.RLock()
	room, exists := s.rooms[msg.RoomID]
	s.roomsMu.RUnlock()

	if !exists {
		return fmt.Errorf("room not found")
	}

	// Forward answer to target peer
	if peer, ok := room[msg.PeerID]; ok {
		answerMsg := Message{
			Type:      MessageTypeAnswer,
			PeerID:    client.peerID,
			SDP:       msg.SDP,
			Timestamp: time.Now().UnixNano(),
		}
		return peer.Send(answerMsg)
	}

	return fmt.Errorf("peer not found in room")
}

// handleICECandidate handles ICE candidate from a client
func (s *Server) handleICECandidate(client *Client, msg *Message) error {
	if msg.RoomID == "" || msg.PeerID == "" {
		return fmt.Errorf("room_id and peer_id are required")
	}

	s.roomsMu.RLock()
	room, exists := s.rooms[msg.RoomID]
	s.roomsMu.RUnlock()

	if !exists {
		return fmt.Errorf("room not found")
	}

	// Forward ICE candidate to target peer
	if peer, ok := room[msg.PeerID]; ok {
		iceMsg := Message{
			Type:      MessageTypeICECandidate,
			PeerID:    client.peerID,
			Candidate: msg.Candidate,
			Timestamp: time.Now().UnixNano(),
		}
		return peer.Send(iceMsg)
	}

	return fmt.Errorf("peer not found in room")
}

// handlePing handles ping messages
func (s *Server) handlePing(client *Client, msg *Message) error {
	pongMsg := Message{
		Type:      MessageTypePong,
		Timestamp: time.Now().UnixNano(),
	}
	return client.Send(pongMsg)
}

// handleKeyExchange handles E2EE key exchange messages.
// The server acts purely as a relay - it forwards the public keys to the
// target peer WITHOUT ever seeing private keys or deriving session keys.
// This is critical for maintaining zero-trust architecture.
func (s *Server) handleKeyExchange(client *Client, msg *Message) error {
	if msg.PeerID == "" {
		return fmt.Errorf("peer_id is required for key exchange")
	}

	if msg.SigningPublicKey == "" || msg.ExchangePublicKey == "" {
		return fmt.Errorf("signing_public_key and exchange_public_key are required")
	}

	s.logger.Info("Key exchange initiated",
		zap.String("from_client", client.ID),
		zap.String("to_peer", msg.PeerID))

	// Find the target peer in the same room
	if client.roomID == "" {
		return fmt.Errorf("must join a room before key exchange")
	}

	s.roomsMu.RLock()
	room, exists := s.rooms[client.roomID]
	s.roomsMu.RUnlock()

	if !exists {
		return fmt.Errorf("room not found")
	}

	// Forward the key exchange message to the target peer
	// CRITICAL: The server only relays public keys. It never accesses
	// private keys, cannot compute the ECDH shared secret, and therefore
	// cannot derive session encryption keys.
	if peer, ok := room[msg.PeerID]; ok {
		keyExchangeMsg := Message{
			Type:              MessageTypeKeyExchange,
			PeerID:            client.peerID,
			SigningPublicKey:  msg.SigningPublicKey,
			ExchangePublicKey: msg.ExchangePublicKey,
			Signature:         msg.Signature,
			Timestamp:         time.Now().UnixNano(),
		}
		return peer.Send(keyExchangeMsg)
	}

	return fmt.Errorf("peer not found in room")
}

// handleKeyExchangeAck handles E2EE key exchange acknowledgment messages.
// The server relays the acknowledgment back to the initiating peer to
// confirm the key exchange was processed.
func (s *Server) handleKeyExchangeAck(client *Client, msg *Message) error {
	if msg.PeerID == "" {
		return fmt.Errorf("peer_id is required for key exchange ack")
	}

	s.logger.Info("Key exchange acknowledgment",
		zap.String("from_client", client.ID),
		zap.String("to_peer", msg.PeerID),
		zap.String("status", msg.Status))

	// Find the target peer in the same room
	if client.roomID == "" {
		return fmt.Errorf("must join a room before key exchange ack")
	}

	s.roomsMu.RLock()
	room, exists := s.rooms[client.roomID]
	s.roomsMu.RUnlock()

	if !exists {
		return fmt.Errorf("room not found")
	}

	// Forward the acknowledgment to the initiating peer
	if peer, ok := room[msg.PeerID]; ok {
		ackMsg := Message{
			Type:      MessageTypeKeyExchangeAck,
			PeerID:    client.peerID,
			Status:    msg.Status,
			Timestamp: time.Now().UnixNano(),
		}
		return peer.Send(ackMsg)
	}

	return fmt.Errorf("peer not found in room")
}

// broadcastToRoom sends a message to all clients in a room except the sender.
// Uses pointer comparison to avoid duplicate sends when clients are stored
// under multiple keys (both UUID and peer_id).
func (s *Server) broadcastToRoom(roomID string, msg Message, excludeClientID string) {
	s.roomsMu.RLock()
	room, exists := s.rooms[roomID]
	if !exists {
		s.roomsMu.RUnlock()
		return
	}

	// Find the excluded client pointer
	var excludeClient *Client
	if c, ok := room[excludeClientID]; ok {
		excludeClient = c
	}

	// Collect unique clients to send to (avoid duplicate sends)
	var targets []*Client
	sent := make(map[*Client]bool)
	for _, client := range room {
		if client == excludeClient || sent[client] {
			continue
		}
		sent[client] = true
		targets = append(targets, client)
	}
	s.roomsMu.RUnlock()

	// Send outside the lock to avoid holding it during I/O
	for _, client := range targets {
		client.Send(msg)
	}
}

// removeFromRoom removes a client from a room (by both UUID and peer_id keys)
func (s *Server) removeFromRoom(roomID, clientID string) {
	s.roomsMu.Lock()
	if room, exists := s.rooms[roomID]; exists {
		// Also remove by peer_id if found
		if client, ok := room[clientID]; ok && client.peerID != "" {
			delete(room, client.peerID)
		}
		delete(room, clientID)
		if len(room) == 0 {
			delete(s.rooms, roomID)
		}
	}
	s.roomsMu.Unlock()
}

// unregisterClient removes a client from the server
func (s *Server) unregisterClient(client *Client) {
	s.clientsMu.Lock()
	delete(s.clients, client.ID)
	s.clientsMu.Unlock()
	atomic.AddInt64(&s.connCount, -1)

	if client.roomID != "" {
		s.removeFromRoom(client.roomID, client.ID)

		// Notify other clients
		s.broadcastToRoom(client.roomID, Message{
			Type:      MessageTypeDisconnect,
			PeerID:    client.ID,
			RoomID:    client.roomID,
			Timestamp: time.Now().UnixNano(),
		}, "")
	}

	s.logger.Info("Client disconnected",
		zap.String("client_id", client.ID),
		zap.Int64("total_connections", atomic.LoadInt64(&s.connCount)))
}

// GetStats returns server statistics
func (s *Server) GetStats() map[string]interface{} {
	s.clientsMu.RLock()
	clientCount := len(s.clients)
	s.clientsMu.RUnlock()

	s.roomsMu.RLock()
	roomCount := len(s.rooms)
	s.roomsMu.RUnlock()

	return map[string]interface{}{
		"total_connections": atomic.LoadInt64(&s.connCount),
		"active_clients":    clientCount,
		"active_rooms":      roomCount,
		"uptime":            time.Now().Unix(),
	}
}
