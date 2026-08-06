package auth

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/Ejoyment/codex-fabric/backend/internal/config"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const testSecret = "test-secret-that-is-long-enough-for-hs256-1234"

func newTestValidator(t *testing.T, cfg config.AuthConfig) *Validator {
	t.Helper()
	if cfg.JWTSecret == "" {
		cfg.JWTSecret = testSecret
	}
	if cfg.JWTExpiration == 0 {
		cfg.JWTExpiration = time.Hour
	}
	if cfg.MaxTokenAge == 0 {
		cfg.MaxTokenAge = time.Hour
	}
	cfg.Enabled = true
	return NewValidator(cfg)
}

func generateTestToken(t *testing.T, v *Validator) string {
	t.Helper()
	token, _, err := v.GenerateToken("user-1", "org-1", []string{"user"}, []string{"signaling:join"})
	require.NoError(t, err)
	return token
}

// captureClaims records the authenticated claims (or nil) seen by the handler
func captureClaims(t *testing.T, handler http.Handler) (claims *TokenClaims, status int) {
	t.Helper()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/ws", nil)
	handler.ServeHTTP(rec, req)
	return ClaimsFromContext(req.Context()), rec.Code
}

func TestHTTPMiddleware_DisabledPassesThrough(t *testing.T) {
	v := NewValidator(config.AuthConfig{Enabled: false, JWTSecret: testSecret})

	handler := v.HTTPMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	claims, status := captureClaims(t, handler)
	assert.Equal(t, http.StatusOK, status)
	assert.Nil(t, claims)
}

func TestHTTPMiddleware_ValidBearerToken(t *testing.T) {
	v := newTestValidator(t, config.AuthConfig{})
	token := generateTestToken(t, v)

	var gotClaims *TokenClaims
	handler := v.HTTPMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotClaims = ClaimsFromContext(r.Context())
		w.WriteHeader(http.StatusOK)
	}))

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/ws", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	handler.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusOK, rec.Code)
	require.NotNil(t, gotClaims)
	assert.Equal(t, "user-1", gotClaims.UserID)
	assert.Equal(t, "org-1", gotClaims.OrgID)
}

func TestHTTPMiddleware_ValidQueryToken(t *testing.T) {
	v := newTestValidator(t, config.AuthConfig{})
	token := generateTestToken(t, v)

	var gotClaims *TokenClaims
	handler := v.HTTPMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotClaims = ClaimsFromContext(r.Context())
		w.WriteHeader(http.StatusOK)
	}))

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/ws?token="+token, nil)
	handler.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusOK, rec.Code)
	require.NotNil(t, gotClaims)
	assert.Equal(t, "user-1", gotClaims.UserID)
}

func TestHTTPMiddleware_BearerTakesPrecedenceOverQuery(t *testing.T) {
	v := newTestValidator(t, config.AuthConfig{})
	validToken := generateTestToken(t, v)

	handler := v.HTTPMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/ws?token=invalid-query-token", nil)
	req.Header.Set("Authorization", "Bearer "+validToken)
	handler.ServeHTTP(rec, req)

	// Valid bearer token wins even though the query param is invalid
	assert.Equal(t, http.StatusOK, rec.Code)
}

func TestHTTPMiddleware_MissingCredentials(t *testing.T) {
	v := newTestValidator(t, config.AuthConfig{})

	handler := v.HTTPMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	claims, status := captureClaims(t, handler)
	assert.Equal(t, http.StatusUnauthorized, status)
	assert.Nil(t, claims)

	// Also test a malformed header (no "Bearer " prefix)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/ws", nil)
	req.Header.Set("Authorization", "Token not-a-bearer")
	handler.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusUnauthorized, rec.Code)
}

func TestHTTPMiddleware_InvalidToken(t *testing.T) {
	v := newTestValidator(t, config.AuthConfig{})

	handler := v.HTTPMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/ws", nil)
	req.Header.Set("Authorization", "Bearer garbage-token-value")
	handler.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusUnauthorized, rec.Code)

	var body map[string]string
	require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &body))
	assert.Contains(t, body["error"], ErrInvalidToken.Error())
}

func TestHTTPMiddleware_ExpiredToken(t *testing.T) {
	v := newTestValidator(t, config.AuthConfig{JWTExpiration: -time.Hour})
	token, _, err := v.GenerateToken("user-1", "org-1", []string{"user"}, nil)
	require.NoError(t, err)

	handler := v.HTTPMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/ws", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	handler.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusUnauthorized, rec.Code)

	var body map[string]string
	require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &body))
	assert.Equal(t, ErrExpiredToken.Error(), body["error"])
}

func TestHTTPMiddleware_SignedWithDifferentSecret(t *testing.T) {
	v := newTestValidator(t, config.AuthConfig{})
	other := NewValidator(config.AuthConfig{
		Enabled:       true,
		JWTSecret:     "a-different-secret-that-is-long-enough-99999",
		JWTExpiration: time.Hour,
		MaxTokenAge:   time.Hour,
	})
	token := generateTestToken(t, other)

	handler := v.HTTPMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/ws", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	handler.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusUnauthorized, rec.Code)
}

func TestHTTPMiddleware_RequiredRoles(t *testing.T) {
	v := newTestValidator(t, config.AuthConfig{RequiredRoles: []string{"admin"}})
	userToken, _, err := v.GenerateToken("user-1", "org-1", []string{"user"}, nil)
	require.NoError(t, err)
	adminToken, _, err := v.GenerateToken("admin-1", "org-1", []string{"admin"}, nil)
	require.NoError(t, err)

	handler := v.HTTPMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	// Non-admin role is rejected with 403
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/ws", nil)
	req.Header.Set("Authorization", "Bearer "+userToken)
	handler.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusForbidden, rec.Code)

	// Admin role passes through
	rec = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodGet, "/ws", nil)
	req.Header.Set("Authorization", "Bearer "+adminToken)
	handler.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusOK, rec.Code)
}
