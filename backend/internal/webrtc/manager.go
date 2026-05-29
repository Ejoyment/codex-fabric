package webrtc

import (
	"fmt"
	"sync"
	"time"

	"github.com/Ejoyment/codex-fabric/backend/internal/config"
	"github.com/pion/ice/v2"
	"github.com/pion/webrtc/v3"
	"go.uber.org/zap"
)

// Manager handles WebRTC peer connections and media routing
type Manager struct {
	config      config.WebRTCConfig
	logger      *zap.Logger
	api         *webrtc.API
	mediaEngine *webrtc.MediaEngine
	settings    *webrtc.SettingEngine
	connections map[string]*webrtc.PeerConnection
	connsMu     sync.RWMutex
	closed      bool
}

// PeerConnection wraps a WebRTC peer connection with metadata
type PeerConnection struct {
	Connection *webrtc.PeerConnection
	PeerID     string
	RoomID     string
	OfferSDP   *webrtc.SessionDescription
	AnswerSDP  *webrtc.SessionDescription
	CreatedAt  time.Time
	LastActivity time.Time
	DataChannel *webrtc.DataChannel
	mu          sync.RWMutex
}

// NewManager creates a new WebRTC manager
func NewManager(cfg config.WebRTCConfig, logger *zap.Logger) (*Manager, error) {
	// Create a setting engine for advanced configuration
	settingEngine := &webrtc.SettingEngine{}
	
	// Configure NAT traversal
	settingEngine.SetICETimeout(cfg.ConnectionTimeout)
	settingEngine.SetIncludeLoopbackCandidate(false)
	settingEngine.SetNet(nil) // Use default network

	// Configure ICE servers
	iceServers := make([]webrtc.ICEServer, 0)
	for _, server := range cfg.GetICEServers() {
		iceServers = append(iceServers, webrtc.ICEServer{
			URLs:       server.URLs,
			Username:   server.Username,
			Credential: server.Credential,
		})
	}
	settingEngine.SetICEServers(iceServers)

	// Create media engine
	mediaEngine := &webrtc.MediaEngine{}
	
	// Register video codecs
	if err := mediaEngine.RegisterDefaultCodecs(); err != nil {
		return nil, fmt.Errorf("failed to register codecs: %w", err)
	}

	// Create API with custom settings
	api := webrtc.NewAPI(
		webrtc.WithMediaEngine(mediaEngine),
		webrtc.WithSettingEngine(*settingEngine),
	)

	m := &Manager{
		config:      cfg,
		logger:      logger,
		api:         api,
		mediaEngine: mediaEngine,
		settings:    settingEngine,
		connections: make(map[string]*webrtc.PeerConnection),
	}

	return m, nil
}

// CreatePeerConnection creates a new WebRTC peer connection
func (m *Manager) CreatePeerConnection(peerID, roomID string) (*PeerConnection, error) {
	if m.closed {
		return nil, fmt.Errorf("manager is closed")
	}

	// Configure ICE candidate gathering
	settingEngine := &webrtc.SettingEngine{}
	settingEngine.SetICETimeout(m.config.ConnectionTimeout)
	
	// Set up ICE servers
	iceServers := make([]webrtc.ICEServer, 0)
	for _, server := range m.config.GetICEServers() {
		iceServers = append(iceServers, webrtc.ICEServer{
			URLs:       server.URLs,
			Username:   server.Username,
			Credential: server.Credential,
		})
	}
	settingEngine.SetICEServers(iceServers)

	// Create new API instance for this connection
	api := webrtc.NewAPI(
		webrtc.WithMediaEngine(m.mediaEngine),
		webrtc.WithSettingEngine(*settingEngine),
	)

	// Create peer connection
	pc, err := api.NewPeerConnection(webrtc.Configuration{
		ICEServers: iceServers,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create peer connection: %w", err)
	}

	// Wrap connection
	wrappedConn := &PeerConnection{
		Connection:   pc,
		PeerID:       peerID,
		RoomID:       roomID,
		CreatedAt:    time.Now(),
		LastActivity: time.Now(),
	}

	// Set up connection event handlers
	pc.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		m.logger.Info("Peer connection state changed",
			zap.String("peer_id", peerID),
			zap.String("room_id", roomID),
			zap.String("state", state.String()))

		wrappedConn.LastActivity = time.Now()

		switch state {
		case webrtc.PeerConnectionStateFailed:
			// Connection failed, clean up
			m.RemovePeerConnection(peerID)
		case webrtc.PeerConnectionStateClosed:
			// Connection closed, clean up
			m.RemovePeerConnection(peerID)
		case webrtc.PeerConnectionStateConnected:
			// Connection established successfully
			m.logger.Info("Peer connection established",
				zap.String("peer_id", peerID),
				zap.String("room_id", roomID))
		}
	})

	pc.OnICECandidate(func(candidate *ice.Candidate) {
		if candidate != nil {
			m.logger.Debug("ICE candidate gathered",
				zap.String("peer_id", peerID),
				zap.String("candidate", candidate.String()))
		}
	})

	pc.OnICEConnectionStateChange(func(state ice.ConnectionState) {
		m.logger.Debug("ICE connection state changed",
			zap.String("peer_id", peerID),
			zap.String("state", state.String()))
	})

	// Set up data channel if enabled
	if m.config.EnableDataChannel {
		dataChannel, err := pc.CreateDataChannel("codex-data", nil)
		if err != nil {
			m.logger.Warn("Failed to create data channel", zap.Error(err))
		} else {
			wrappedConn.DataChannel = dataChannel
			
			dataChannel.OnOpen(func() {
				m.logger.Info("Data channel opened",
					zap.String("peer_id", peerID),
					zap.String("room_id", roomID))
			})

			dataChannel.OnClose(func() {
				m.logger.Info("Data channel closed",
					zap.String("peer_id", peerID),
					zap.String("room_id", roomID))
			})
		}
	}

	// Store connection
	m.connsMu.Lock()
	m.connections[peerID] = pc
	m.connsMu.Unlock()

	return wrappedConn, nil
}

// CreateOffer creates an SDP offer for a peer connection
func (m *Manager) CreateOffer(peerID, roomID string) (*webrtc.SessionDescription, error) {
	// Create or get existing peer connection
	conn, exists := m.GetPeerConnection(peerID)
	if !exists {
		// Create new connection
		wrappedConn, err := m.CreatePeerConnection(peerID, roomID)
		if err != nil {
			return nil, err
		}
		conn = wrappedConn.Connection
	}

	// Create offer
	offer, err := conn.CreateOffer(nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create offer: %w", err)
	}

	// Set local description
	if err := conn.SetLocalDescription(offer); err != nil {
		return nil, fmt.Errorf("failed to set local description: %w", err)
	}

	return &offer, nil
}

// CreateAnswer creates an SDP answer for a peer connection
func (m *Manager) CreateAnswer(peerID string, offer webrtc.SessionDescription) (*webrtc.SessionDescription, error) {
	conn, exists := m.GetPeerConnection(peerID)
	if !exists {
		return nil, fmt.Errorf("peer connection not found")
	}

	// Set remote description
	if err := conn.SetRemoteDescription(offer); err != nil {
		return nil, fmt.Errorf("failed to set remote description: %w", err)
	}

	// Create answer
	answer, err := conn.CreateAnswer(nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create answer: %w", err)
	}

	// Set local description
	if err := conn.SetLocalDescription(answer); err != nil {
		return nil, fmt.Errorf("failed to set local description: %w", err)
	}

	return &answer, nil
}

// SetRemoteDescription sets the remote session description
func (m *Manager) SetRemoteDescription(peerID string, desc webrtc.SessionDescription) error {
	conn, exists := m.GetPeerConnection(peerID)
	if !exists {
		return fmt.Errorf("peer connection not found")
	}

	return conn.SetRemoteDescription(desc)
}

// AddICECandidate adds an ICE candidate to a peer connection
func (m *Manager) AddICECandidate(peerID string, candidateInit webrtc.ICECandidateInit) error {
	conn, exists := m.GetPeerConnection(peerID)
	if !exists {
		return fmt.Errorf("peer connection not found")
	}

	return conn.AddICECandidate(candidateInit)
}

// GetPeerConnection retrieves a peer connection by peer ID
func (m *Manager) GetPeerConnection(peerID string) (*webrtc.PeerConnection, bool) {
	m.connsMu.RLock()
	defer m.connsMu.RUnlock()

	conn, exists := m.connections[peerID]
	return conn, exists
}

// RemovePeerConnection removes and closes a peer connection
func (m *Manager) RemovePeerConnection(peerID string) {
	m.connsMu.Lock()
	defer m.connsMu.Unlock()

	if conn, exists := m.connections[peerID]; exists {
		if err := conn.Close(); err != nil {
			m.logger.Error("Failed to close peer connection",
				zap.String("peer_id", peerID),
				zap.Error(err))
		}
		delete(m.connections, peerID)
		m.logger.Info("Peer connection removed", zap.String("peer_id", peerID))
	}
}

// GetConnectionStats returns statistics for all connections
func (m *Manager) GetConnectionStats() map[string]interface{} {
	m.connsMu.RLock()
	defer m.connsMu.RUnlock()

	stats := map[string]interface{}{
		"total_connections": len(m.connections),
		"connections":       make([]map[string]interface{}, 0),
	}

	for peerID, conn := range m.connections {
		connStats := map[string]interface{}{
			"peer_id":        peerID,
			"connection_state": conn.ConnectionState().String(),
			"ice_state":      conn.ICEConnectionState().String(),
			"signaling_state": conn.SignalingState().String(),
		}
		stats["connections"] = append(stats["connections"].([]map[string]interface{}), connStats)
	}

	return stats
}

// Close closes the manager and all peer connections
func (m *Manager) Close() error {
	m.connsMu.Lock()
	defer m.connsMu.Unlock()

	m.closed = true

	var errs []error
	for peerID, conn := range m.connections {
		if err := conn.Close(); err != nil {
			errs = append(errs, fmt.Errorf("failed to close connection %s: %w", peerID, err))
		}
	}

	m.connections = make(map[string]*webrtc.PeerConnection)

	if len(errs) > 0 {
		return fmt.Errorf("errors during close: %v", errs)
	}

	return nil
}

// GetActiveConnectionCount returns the number of active connections
func (m *Manager) GetActiveConnectionCount() int {
	m.connsMu.RLock()
	defer m.connsMu.RUnlock()
	return len(m.connections)
}

// CleanupStaleConnections removes connections that haven't been active recently
func (m *Manager) CleanupStaleConnections(timeout time.Duration) int {
	m.connsMu.Lock()
	defer m.connsMu.Unlock()

	cleaned := 0
	now := time.Now()

	for peerID, conn := range m.connections {
		// This is a simplified check - in reality we'd need to track last activity
		// in the PeerConnection wrapper
		if now.Sub(conn.ConnectionState().String() /* placeholder */ ) > timeout {
			if err := conn.Close(); err == nil {
				delete(m.connections, peerID)
				cleaned++
			}
		}
	}

	return cleaned
}