package webrtc

import (
	"context"
	"fmt"
	"net"
	"strings"
	"sync"
	"time"

	"github.com/Ejoyment/codex-fabric/backend/internal/config"
	"github.com/pion/stun"
	"go.uber.org/zap"
)

// NATType represents the type of NAT traversal required
type NATType int

const (
	// NATUnknown indicates NAT type hasn't been determined
	NATUnknown NATType = iota
	// NATNone indicates no NAT (direct connection possible)
	NATNone
	// NATFullCone indicates full cone NAT (easiest to traverse)
	NATFullCone
	// NATRestrictedCone indicates restricted cone NAT
	NATRestrictedCone
	// NATPortRestricted indicates port restricted NAT
	NATPortRestricted
	// NATSymmetric indicates symmetric NAT (hardest to traverse)
	NATSymmetric
)

// NATTraversalManager handles NAT traversal strategies and STUN/TURN fallback
type NATTraversalManager struct {
	config      config.WebRTCConfig
	logger      *zap.Logger
	natType     NATType
	stunServers []string
	turnServers []config.TURNServerConfig

	// Connection pool for STUN/TURN servers
	stunConnPool *sync.Pool
	mu           sync.RWMutex

	// Health check status
	stunHealth map[string]bool
	turnHealth map[string]bool
	healthMu   sync.RWMutex
}

// NewNATTraversalManager creates a new NAT traversal manager
func NewNATTraversalManager(cfg config.WebRTCConfig, logger *zap.Logger) *NATTraversalManager {
	return &NATTraversalManager{
		config:      cfg,
		logger:      logger,
		natType:     NATUnknown,
		stunServers: cfg.STUNServers,
		turnServers: cfg.TURNServers,
		stunConnPool: &sync.Pool{
			New: func() interface{} {
				return &stunConnection{}
			},
		},
		stunHealth: make(map[string]bool),
		turnHealth: make(map[string]bool),
	}
}

type stunConnection struct {
	conn     net.PacketConn
	lastUsed time.Time
}

// DetectNATType determines the type of NAT the client is behind
func (m *NATTraversalManager) DetectNATType(ctx context.Context) (NATType, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.natType != NATUnknown {
		return m.natType, nil
	}

	// Test connectivity to STUN servers
	healthySTUN := m.getHealthySTUNServers()
	if len(healthySTUN) == 0 {
		return NATUnknown, fmt.Errorf("no healthy STUN servers available")
	}

	// Perform STUN tests to determine NAT type
	natType, err := m.performNATDiscovery(ctx, healthySTUN)
	if err != nil {
		return NATUnknown, err
	}

	m.natType = natType
	m.logger.Info("NAT type detected",
		zap.String("nat_type", natType.String()),
		zap.Int("healthy_stun_servers", len(healthySTUN)))

	return natType, nil
}

// performNATDiscovery performs STUN tests to determine NAT type
func (m *NATTraversalManager) performNATDiscovery(ctx context.Context, servers []string) (NATType, error) {
	// Simplified NAT detection - in production this would implement full RFC 3489 tests
	// For now, we'll use a heuristic approach based on connection success rates

	successCount := 0
	for _, server := range servers[:min(3, len(servers))] {
		if m.testSTUNServer(ctx, server) {
			successCount++
		}
	}

	// Heuristic: if we can reach multiple STUN servers consistently, likely cone NAT
	// If success rate is low, likely symmetric NAT
	successRate := float64(successCount) / float64(min(3, len(servers)))

	switch {
	case successRate >= 0.9:
		return NATFullCone, nil
	case successRate >= 0.7:
		return NATRestrictedCone, nil
	case successRate >= 0.5:
		return NATPortRestricted, nil
	default:
		return NATSymmetric, nil
	}
}

// testSTUNServer tests connectivity to a STUN server using simple UDP
func (m *NATTraversalManager) testSTUNServer(ctx context.Context, server string) bool {
	// Parse STUN server address
	host, port, err := net.SplitHostPort(strings.TrimPrefix(server, "stun:"))
	if err != nil {
		m.logger.Warn("Failed to parse STUN server address",
			zap.String("server", server),
			zap.Error(err))
		return false
	}

	// Create UDP connection
	conn, err := net.DialTimeout("udp", net.JoinHostPort(host, port), 5*time.Second)
	if err != nil {
		return false
	}
	defer conn.Close()

	// Set a timeout for the operation
	conn.SetDeadline(time.Now().Add(3 * time.Second))

	// Create STUN binding request
	msg, err := stun.Build(stun.BindingRequest, stun.TransactionID)
	if err != nil {
		return false
	}

	// Send the request
	if _, err := conn.Write(msg.Raw); err != nil {
		return false
	}

	// Read response
	response := make([]byte, 1024)
	n, err := conn.Read(response)
	if err != nil {
		return false
	}

	// Parse response
	var res stun.Message
	res.Raw = response[:n]
	if err := res.Decode(); err != nil {
		return false
	}

	return res.Type == stun.BindingSuccess
}

// GetOptimalICEServers returns the optimal ICE server configuration based on NAT type
func (m *NATTraversalManager) GetOptimalICEServers() []config.ICEServerConfig {
	m.mu.RLock()
	natType := m.natType
	m.mu.RUnlock()

	var servers []config.ICEServerConfig

	// Always include healthy STUN servers
	healthySTUN := m.getHealthySTUNServers()
	for _, server := range healthySTUN {
		servers = append(servers, config.ICEServerConfig{
			URLs: []string{server},
		})
	}

	// Add TURN servers based on NAT type
	// For symmetric NAT or worse, we need TURN
	if natType == NATSymmetric || natType == NATPortRestricted {
		healthyTURN := m.getHealthyTURNServers()
		for _, turnServer := range healthyTURN {
			servers = append(servers, config.ICEServerConfig{
				URLs:       []string{turnServer.URL},
				Username:   turnServer.Username,
				Credential: turnServer.Password,
			})
		}
	}

	return servers
}

// StartHealthChecks starts periodic health checks for STUN/TURN servers
func (m *NATTraversalManager) StartHealthChecks(ctx context.Context) {
	go m.runSTUNHealthChecks(ctx)
	go m.runTURNHealthChecks(ctx)
}

// runSTUNHealthChecks periodically checks STUN server health
func (m *NATTraversalManager) runSTUNHealthChecks(ctx context.Context) {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()

	// Initial health check
	m.checkAllSTUNServers(ctx)

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			m.checkAllSTUNServers(ctx)
		}
	}
}

// checkAllSTUNServers checks health of all STUN servers
func (m *NATTraversalManager) checkAllSTUNServers(ctx context.Context) {
	m.healthMu.Lock()
	defer m.healthMu.Unlock()

	for _, server := range m.stunServers {
		m.stunHealth[server] = m.testSTUNServer(ctx, server)
	}
}

// getHealthySTUNServers returns list of healthy STUN servers
func (m *NATTraversalManager) getHealthySTUNServers() []string {
	m.healthMu.RLock()
	defer m.healthMu.RUnlock()

	var healthy []string
	for server, isHealthy := range m.stunHealth {
		if isHealthy {
			healthy = append(healthy, server)
		}
	}
	return healthy
}

// runTURNHealthChecks periodically checks TURN server health
func (m *NATTraversalManager) runTURNHealthChecks(ctx context.Context) {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()

	// Initial health check
	m.checkAllTURNServers(ctx)

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			m.checkAllTURNServers(ctx)
		}
	}
}

// checkAllTURNServers checks health of all TURN servers
func (m *NATTraversalManager) checkAllTURNServers(ctx context.Context) {
	m.healthMu.Lock()
	defer m.healthMu.Unlock()

	for _, server := range m.turnServers {
		// Simplified TURN health check - in production would test TURN allocation
		host, port, err := net.SplitHostPort(strings.TrimPrefix(server.URL, "turn:"))
		if err != nil {
			m.turnHealth[server.URL] = false
			continue
		}

		conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, port), 3*time.Second)
		if err != nil {
			m.turnHealth[server.URL] = false
			continue
		}
		conn.Close()
		m.turnHealth[server.URL] = true
	}
}

// getHealthyTURNServers returns list of healthy TURN servers
func (m *NATTraversalManager) getHealthyTURNServers() []config.TURNServerConfig {
	m.healthMu.RLock()
	defer m.healthMu.RUnlock()

	var healthy []config.TURNServerConfig
	for _, server := range m.turnServers {
		if m.turnHealth[server.URL] {
			healthy = append(healthy, server)
		}
	}
	return healthy
}

// String returns string representation of NAT type
func (n NATType) String() string {
	switch n {
	case NATNone:
		return "none"
	case NATFullCone:
		return "full_cone"
	case NATRestrictedCone:
		return "restricted_cone"
	case NATPortRestricted:
		return "port_restricted"
	case NATSymmetric:
		return "symmetric"
	default:
		return "unknown"
	}
}

// RequiresTURN indicates if this NAT type typically requires TURN servers
func (n NATType) RequiresTURN() bool {
	return n == NATSymmetric || n == NATPortRestricted
}

// Helper function
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
