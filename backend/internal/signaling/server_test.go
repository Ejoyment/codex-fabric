package signaling

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/Ejoyment/codex-fabric/backend/internal/auth"
	"github.com/Ejoyment/codex-fabric/backend/internal/config"
	"github.com/Ejoyment/codex-fabric/backend/internal/webrtc"
	"github.com/gorilla/websocket"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/zap"
)

// createTestServer creates a signaling server for testing
func createTestServer(t *testing.T) (*Server, *httptest.Server, *webrtc.Manager) {
	return createTestServerWithAuth(t, nil)
}

// createTestServerWithAuth creates a signaling server with an optional auth
// validator. When authValidator is nil, the /ws endpoint is left unprotected.
func createTestServerWithAuth(t *testing.T, authValidator *auth.Validator) (*Server, *httptest.Server, *webrtc.Manager) {
	logger, _ := zap.NewDevelopment()

	cfg := config.WebRTCConfig{
		STUNServers: []string{
			"stun:stun.l.google.com:19302",
		},
		ConnectionTimeout: 30 * time.Second,
		EnableDataChannel: false,
	}

	webrtcMgr, err := webrtc.NewManager(cfg, logger)
	require.NoError(t, err)

	sigCfg := config.SignalingConfig{
		AllowedOrigins:    []string{"*"},
		MaxMessageSize:    1024 * 1024,
		HandshakeTimeout:  10 * time.Second,
		PingInterval:      30 * time.Second,
		PongWait:          60 * time.Second,
		WriteWait:         10 * time.Second,
		MaxConnections:    100,
		EnableCompression: false,
	}

	server, err := NewServer(sigCfg, webrtcMgr, authValidator, logger)
	require.NoError(t, err)

	// Create HTTP test server
	mux := http.NewServeMux()
	if authValidator != nil {
		mux.Handle("/ws", authValidator.HTTPMiddleware(http.HandlerFunc(server.HandleWebSocket)))
	} else {
		mux.HandleFunc("/ws", server.HandleWebSocket)
	}
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	httpServer := httptest.NewServer(mux)

	return server, httpServer, webrtcMgr
}

// connectWebSocket connects a WebSocket client to the test server
func connectWebSocket(t *testing.T, httpServer *httptest.Server) (*websocket.Conn, chan []byte) {
	conn, messages, _, err := connectWebSocketWithHeaders(t, httpServer, nil)
	require.NoError(t, err)
	return conn, messages
}

// connectWebSocketWithHeaders connects a WebSocket client with custom headers.
// The HTTP response is always returned so callers can inspect the status code
// when the handshake is rejected (e.g. by auth middleware).
func connectWebSocketWithHeaders(t *testing.T, httpServer *httptest.Server, headers http.Header) (*websocket.Conn, chan []byte, *http.Response, error) {
	url := "ws" + httpServer.URL[4:] + "/ws"

	// Set up headers to pass CORS check
	header := http.Header{}
	header.Set("Origin", httpServer.URL)
	for k, v := range headers {
		header[k] = v
	}

	conn, resp, err := websocket.DefaultDialer.Dial(url, header)
	if err != nil {
		return nil, nil, resp, err
	}

	// Create a channel to receive messages
	messages := make(chan []byte, 10)

	// Start reading messages in a goroutine
	go func() {
		for {
			_, msg, err := conn.ReadMessage()
			if err != nil {
				close(messages)
				return
			}
			messages <- msg
		}
	}()

	return conn, messages, resp, nil
}

// readMessage reads a message from the channel with timeout
func readMessage(t *testing.T, messages chan []byte, timeout time.Duration) []byte {
	select {
	case msg, ok := <-messages:
		if !ok {
			t.Fatal("message channel closed unexpectedly")
		}
		return msg
	case <-time.After(timeout):
		t.Fatal("timeout waiting for message")
	}
	return nil
}

func TestServer_NewServer(t *testing.T) {
	logger, _ := zap.NewDevelopment()

	cfg := config.WebRTCConfig{
		ConnectionTimeout: 30 * time.Second,
	}

	webrtcMgr, err := webrtc.NewManager(cfg, logger)
	require.NoError(t, err)

	sigCfg := config.SignalingConfig{
		MaxConnections: 100,
	}

	server, err := NewServer(sigCfg, webrtcMgr, nil, logger)
	require.NoError(t, err)
	assert.NotNil(t, server)
}

func TestServer_WebSocketConnection(t *testing.T) {
	_, httpServer, webrtcMgr := createTestServer(t)
	defer webrtcMgr.Close()
	defer httpServer.Close()

	conn, messages := connectWebSocket(t, httpServer)
	defer conn.Close()

	// Should receive welcome message
	msg := readMessage(t, messages, 5*time.Second)

	var welcomeMsg Message
	err := json.Unmarshal(msg, &welcomeMsg)
	require.NoError(t, err)

	assert.Equal(t, MessageTypeWelcome, welcomeMsg.Type)
	assert.NotEmpty(t, welcomeMsg.ID)
}

func TestServer_JoinRoom(t *testing.T) {
	_, httpServer, webrtcMgr := createTestServer(t)
	defer webrtcMgr.Close()
	defer httpServer.Close()

	conn, messages := connectWebSocket(t, httpServer)
	defer conn.Close()

	// Read welcome message
	readMessage(t, messages, 5*time.Second)

	// Send join message
	joinMsg := Message{
		Type:   MessageTypeJoin,
		RoomID: "test-room",
		PeerID: "test-peer-1",
	}
	err := conn.WriteJSON(joinMsg)
	require.NoError(t, err)

	// Should receive joined message
	msg := readMessage(t, messages, 5*time.Second)

	var responseMsg Message
	err = json.Unmarshal(msg, &responseMsg)
	require.NoError(t, err)

	assert.Equal(t, MessageTypeJoined, responseMsg.Type)
	assert.Equal(t, "test-room", responseMsg.RoomID)
}

func TestServer_MultipleClients(t *testing.T) {
	server, httpServer, webrtcMgr := createTestServer(t)
	_ = server // Use server for assertions
	defer webrtcMgr.Close()
	defer httpServer.Close()

	// Connect first client
	conn1, messages1 := connectWebSocket(t, httpServer)
	defer conn1.Close()

	// Read welcome message
	readMessage(t, messages1, 5*time.Second)

	// Join room with first client
	joinMsg := Message{
		Type:   MessageTypeJoin,
		RoomID: "test-room",
		PeerID: "peer-1",
	}
	err := conn1.WriteJSON(joinMsg)
	require.NoError(t, err)

	// Read joined message
	readMessage(t, messages1, 5*time.Second)

	// Connect second client
	conn2, messages2 := connectWebSocket(t, httpServer)
	defer conn2.Close()

	// Read welcome message
	readMessage(t, messages2, 5*time.Second)

	// Join same room with second client
	joinMsg2 := Message{
		Type:   MessageTypeJoin,
		RoomID: "test-room",
		PeerID: "peer-2",
	}
	err = conn2.WriteJSON(joinMsg2)
	require.NoError(t, err)

	// Second client should receive joined message
	readMessage(t, messages2, 5*time.Second)

	// First client should receive ready notification
	msg := readMessage(t, messages1, 5*time.Second)

	var responseMsg Message
	err = json.Unmarshal(msg, &responseMsg)
	require.NoError(t, err)

	assert.Equal(t, MessageTypeReady, responseMsg.Type)
}

func TestServer_OfferAnswerExchange(t *testing.T) {
	_, httpServer, webrtcMgr := createTestServer(t)
	defer webrtcMgr.Close()
	defer httpServer.Close()

	// Connect offerer
	offererConn, offererMessages := connectWebSocket(t, httpServer)
	defer offererConn.Close()

	// Read welcome
	readMessage(t, offererMessages, 5*time.Second)

	// Join room
	joinMsg := Message{
		Type:   MessageTypeJoin,
		RoomID: "test-room",
		PeerID: "offerer",
	}
	err := offererConn.WriteJSON(joinMsg)
	require.NoError(t, err)
	readMessage(t, offererMessages, 5*time.Second)

	// Connect answerer
	answererConn, answererMessages := connectWebSocket(t, httpServer)
	defer answererConn.Close()

	// Read welcome
	readMessage(t, answererMessages, 5*time.Second)

	// Join room
	joinMsg2 := Message{
		Type:   MessageTypeJoin,
		RoomID: "test-room",
		PeerID: "answerer",
	}
	err = answererConn.WriteJSON(joinMsg2)
	require.NoError(t, err)
	readMessage(t, answererMessages, 5*time.Second)

	// Offerer should receive ready notification
	readMessage(t, offererMessages, 5*time.Second)

	// Send offer from offerer to answerer
	sdp := json.RawMessage(`{"type":"offer","sdp":"mock-sdp"}`)
	offerMsg := Message{
		Type:   MessageTypeOffer,
		RoomID: "test-room",
		PeerID: "answerer",
		SDP:    sdp,
	}
	err = offererConn.WriteJSON(offerMsg)
	require.NoError(t, err)

	// Answerer should receive offer
	msg := readMessage(t, answererMessages, 5*time.Second)

	var responseMsg Message
	err = json.Unmarshal(msg, &responseMsg)
	require.NoError(t, err)

	assert.Equal(t, MessageTypeOffer, responseMsg.Type)
	assert.Equal(t, "offerer", responseMsg.PeerID)

	// Send answer from answerer to offerer
	answerSDP := json.RawMessage(`{"type":"answer","sdp":"mock-sdp-answer"}`)
	answerMsg := Message{
		Type:   MessageTypeAnswer,
		RoomID: "test-room",
		PeerID: "offerer",
		SDP:    answerSDP,
	}
	err = answererConn.WriteJSON(answerMsg)
	require.NoError(t, err)

	// Offerer should receive answer
	msg = readMessage(t, offererMessages, 5*time.Second)

	err = json.Unmarshal(msg, &responseMsg)
	require.NoError(t, err)

	assert.Equal(t, MessageTypeAnswer, responseMsg.Type)
	assert.Equal(t, "answerer", responseMsg.PeerID)
}

func TestServer_ICECandidateExchange(t *testing.T) {
	_, httpServer, webrtcMgr := createTestServer(t)
	defer webrtcMgr.Close()
	defer httpServer.Close()

	// Connect two clients
	conn1, messages1 := connectWebSocket(t, httpServer)
	defer conn1.Close()

	conn2, messages2 := connectWebSocket(t, httpServer)
	defer conn2.Close()

	// Read welcome messages
	readMessage(t, messages1, 5*time.Second)
	readMessage(t, messages2, 5*time.Second)

	// Join room (sequenced to avoid race conditions with ready notifications)
	joinMsg1 := Message{Type: MessageTypeJoin, RoomID: "test-room", PeerID: "peer-1"}
	conn1.WriteJSON(joinMsg1)
	readMessage(t, messages1, 5*time.Second) // joined

	joinMsg2 := Message{Type: MessageTypeJoin, RoomID: "test-room", PeerID: "peer-2"}
	conn2.WriteJSON(joinMsg2)
	readMessage(t, messages2, 5*time.Second) // joined

	// Peer 1 receives ready notification for peer 2
	readMessage(t, messages1, 5*time.Second)

	// Send ICE candidate from peer 1 to peer 2
	candidate := json.RawMessage(`{"candidate":"mock-candidate","sdpMid":"0","sdpMLineIndex":0}`)
	iceMsg := Message{
		Type:      MessageTypeICECandidate,
		RoomID:    "test-room",
		PeerID:    "peer-2",
		Candidate: candidate,
	}
	err := conn1.WriteJSON(iceMsg)
	require.NoError(t, err)

	// Peer 2 should receive ICE candidate
	msg := readMessage(t, messages2, 5*time.Second)

	var responseMsg Message
	err = json.Unmarshal(msg, &responseMsg)
	require.NoError(t, err)

	assert.Equal(t, MessageTypeICECandidate, responseMsg.Type)
	assert.Equal(t, "peer-1", responseMsg.PeerID)
}

func TestServer_PingPong(t *testing.T) {
	_, httpServer, webrtcMgr := createTestServer(t)
	defer webrtcMgr.Close()
	defer httpServer.Close()

	conn, messages := connectWebSocket(t, httpServer)
	defer conn.Close()

	// Read welcome
	readMessage(t, messages, 5*time.Second)

	// Send ping
	pingMsg := Message{Type: MessageTypePing}
	err := conn.WriteJSON(pingMsg)
	require.NoError(t, err)

	// Should receive pong
	msg := readMessage(t, messages, 5*time.Second)

	var responseMsg Message
	err = json.Unmarshal(msg, &responseMsg)
	require.NoError(t, err)

	assert.Equal(t, MessageTypePong, responseMsg.Type)
}

func TestServer_Disconnect(t *testing.T) {
	_, httpServer, webrtcMgr := createTestServer(t)
	defer webrtcMgr.Close()
	defer httpServer.Close()

	// Connect two clients
	conn1, messages1 := connectWebSocket(t, httpServer)
	defer conn1.Close()

	conn2, messages2 := connectWebSocket(t, httpServer)
	defer conn2.Close()

	// Read welcome messages
	readMessage(t, messages1, 5*time.Second)
	readMessage(t, messages2, 5*time.Second)

	// Join room (sequenced)
	joinMsg1 := Message{Type: MessageTypeJoin, RoomID: "test-room", PeerID: "peer-1"}
	conn1.WriteJSON(joinMsg1)
	readMessage(t, messages1, 5*time.Second) // joined

	joinMsg2 := Message{Type: MessageTypeJoin, RoomID: "test-room", PeerID: "peer-2"}
	conn2.WriteJSON(joinMsg2)
	readMessage(t, messages2, 5*time.Second) // joined

	// Peer 1 receives ready notification for peer 2
	readMessage(t, messages1, 5*time.Second)

	// Close conn2
	conn2.Close()

	// Peer 1 should receive disconnect notification
	msg := readMessage(t, messages1, 5*time.Second)

	var responseMsg Message
	err := json.Unmarshal(msg, &responseMsg)
	require.NoError(t, err)

	assert.Equal(t, MessageTypeDisconnect, responseMsg.Type)
}

func TestServer_ConcurrentConnections(t *testing.T) {
	server, httpServer, webrtcMgr := createTestServer(t)
	defer webrtcMgr.Close()
	defer httpServer.Close()

	const numClients = 10
	var wg sync.WaitGroup
	clients := make([]chan []byte, numClients)
	conns := make([]*websocket.Conn, numClients)

	// Connect all clients
	for i := 0; i < numClients; i++ {
		wg.Add(1)
		go func(index int) {
			defer wg.Done()
			conn, messages := connectWebSocket(t, httpServer)
			conns[index] = conn
			clients[index] = messages

			// Read welcome
			readMessage(t, messages, 5*time.Second)

			// Join room
			joinMsg := Message{
				Type:   MessageTypeJoin,
				RoomID: "concurrent-room",
				PeerID: "peer-" + string(rune('0'+index)),
			}
			conn.WriteJSON(joinMsg)

			// Read joined
			readMessage(t, messages, 5*time.Second)
		}(i)
	}

	wg.Wait()

	// Verify all clients are connected
	assert.Equal(t, numClients, len(server.clients))

	// Cleanup
	for i := 0; i < numClients; i++ {
		conns[i].Close()
	}
}

func TestServer_GetStats(t *testing.T) {
	server, httpServer, webrtcMgr := createTestServer(t)
	_ = server // Use server for assertions
	defer webrtcMgr.Close()
	defer httpServer.Close()

	// Connect a client
	conn, messages := connectWebSocket(t, httpServer)
	defer conn.Close()

	// Read welcome
	readMessage(t, messages, 5*time.Second)

	// Get stats
	stats := server.GetStats()

	assert.Equal(t, int64(1), stats["total_connections"])
	assert.Equal(t, 1, stats["active_clients"])

	// Join a room
	joinMsg := Message{
		Type:   MessageTypeJoin,
		RoomID: "stats-room",
		PeerID: "stats-peer",
	}
	conn.WriteJSON(joinMsg)
	readMessage(t, messages, 5*time.Second)

	// Get stats again
	stats = server.GetStats()

	assert.Equal(t, 1, stats["active_rooms"])
}

func TestServer_WebSocketAuthDefensiveReject(t *testing.T) {
	// Server is configured with auth enabled, but /ws is registered WITHOUT
	// the auth middleware. The server must still reject unauthenticated
	// connections before the upgrade as a defensive measure.
	logger, _ := zap.NewDevelopment()

	webrtcMgr, err := webrtc.NewManager(config.WebRTCConfig{EnableDataChannel: false}, logger)
	require.NoError(t, err)
	defer webrtcMgr.Close()

	sigCfg := config.SignalingConfig{
		AllowedOrigins: []string{"*"},
		MaxMessageSize: 1024 * 1024,
		MaxConnections: 100,
	}

	server, err := NewServer(sigCfg, webrtcMgr, newTestAuthValidator(t), logger)
	require.NoError(t, err)

	mux := http.NewServeMux()
	mux.HandleFunc("/ws", server.HandleWebSocket)
	httpServer := httptest.NewServer(mux)
	defer httpServer.Close()

	_, _, resp, err := connectWebSocketWithHeaders(t, httpServer, nil)
	require.Error(t, err)
	require.NotNil(t, resp)
	assert.Equal(t, http.StatusUnauthorized, resp.StatusCode)
}

// newTestAuthValidator returns a Validator with auth enabled for testing
func newTestAuthValidator(t *testing.T) *auth.Validator {
	t.Helper()
	v := auth.NewValidator(config.AuthConfig{
		Enabled:       true,
		JWTSecret:     "test-secret-that-is-long-enough-for-hs256-1234",
		JWTExpiration: time.Hour,
		MaxTokenAge:   time.Hour,
	})
	return v
}

func TestServer_WebSocketAuthRejectedWithoutToken(t *testing.T) {
	_, httpServer, webrtcMgr := createTestServerWithAuth(t, newTestAuthValidator(t))
	defer webrtcMgr.Close()
	defer httpServer.Close()

	// Dialing without credentials must be rejected before the upgrade
	_, _, resp, err := connectWebSocketWithHeaders(t, httpServer, nil)
	require.Error(t, err)
	require.NotNil(t, resp)
	assert.Equal(t, http.StatusUnauthorized, resp.StatusCode)
}

func TestServer_WebSocketAuthRejectedInvalidToken(t *testing.T) {
	_, httpServer, webrtcMgr := createTestServerWithAuth(t, newTestAuthValidator(t))
	defer webrtcMgr.Close()
	defer httpServer.Close()

	headers := http.Header{}
	headers.Set("Authorization", "Bearer not-a-valid-token")

	_, _, resp, err := connectWebSocketWithHeaders(t, httpServer, headers)
	require.Error(t, err)
	require.NotNil(t, resp)
	assert.Equal(t, http.StatusUnauthorized, resp.StatusCode)
}

func TestServer_WebSocketAuthAcceptedBearerToken(t *testing.T) {
	validator := newTestAuthValidator(t)
	token, _, err := validator.GenerateToken("user-1", "org-1", []string{"user"}, nil)
	require.NoError(t, err)

	server, httpServer, webrtcMgr := createTestServerWithAuth(t, validator)
	defer webrtcMgr.Close()
	defer httpServer.Close()

	headers := http.Header{}
	headers.Set("Authorization", "Bearer "+token)

	conn, messages, _, err := connectWebSocketWithHeaders(t, httpServer, headers)
	require.NoError(t, err)
	defer conn.Close()

	// Should receive welcome message
	msg := readMessage(t, messages, 5*time.Second)

	var welcomeMsg Message
	err = json.Unmarshal(msg, &welcomeMsg)
	require.NoError(t, err)

	assert.Equal(t, MessageTypeWelcome, welcomeMsg.Type)
	assert.NotEmpty(t, welcomeMsg.ID)

	// The client should be marked as authenticated server-side
	server.clientsMu.RLock()
	var client *Client
	for _, c := range server.clients {
		client = c
		break
	}
	server.clientsMu.RUnlock()

	require.NotNil(t, client)
	assert.True(t, client.authenticated)
	assert.Equal(t, "user-1", client.userID)
	assert.Equal(t, "org-1", client.orgID)
	assert.Equal(t, []string{"user"}, client.roles)
}

func TestServer_WebSocketAuthAcceptedQueryToken(t *testing.T) {
	validator := newTestAuthValidator(t)
	token, _, err := validator.GenerateToken("user-1", "org-1", []string{"user"}, nil)
	require.NoError(t, err)

	_, httpServer, webrtcMgr := createTestServerWithAuth(t, validator)
	defer webrtcMgr.Close()
	defer httpServer.Close()

	// Query param fallback for clients that cannot set custom headers
	url := "ws" + httpServer.URL[4:] + "/ws?token=" + token
	header := http.Header{}
	header.Set("Origin", httpServer.URL)

	conn, _, err := websocket.DefaultDialer.Dial(url, header)
	require.NoError(t, err)
	defer conn.Close()

	// Should receive welcome message
	var welcomeMsg Message
	require.NoError(t, conn.ReadJSON(&welcomeMsg))
	assert.Equal(t, MessageTypeWelcome, welcomeMsg.Type)
}
