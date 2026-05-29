package auth

import (
	"crypto/subtle"
	"errors"
	"fmt"
	"time"

	"github.com/Ejoyment/codex-fabric/backend/internal/config"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

var (
	// ErrInvalidToken is returned when the token is invalid
	ErrInvalidToken = errors.New("invalid token")
	// ErrExpiredToken is returned when the token has expired
	ErrExpiredToken = errors.New("token expired")
	// ErrInvalidAPIKey is returned when the API key is invalid
	ErrInvalidAPIKey = errors.New("invalid API key")
	// ErrMissingCredentials is returned when no credentials are provided
	ErrMissingCredentials = errors.New("missing credentials")
)

// TokenClaims represents the claims in a JWT token
type TokenClaims struct {
	jwt.RegisteredClaims
	UserID    string   `json:"user_id"`
	Roles     []string `json:"roles"`
	OrgID     string   `json:"org_id"`
	Permissions []string `json:"permissions"`
}

// Validator handles authentication and authorization
type Validator struct {
	config      config.AuthConfig
	apiKeys     map[string]*APIKeyInfo
	secret      []byte
}

// APIKeyInfo contains metadata about an API key
type APIKeyInfo struct {
	Key       string
	OrgID     string
	UserID    string
	Roles     []string
	ExpiresAt time.Time
	CreatedAt time.Time
}

// NewValidator creates a new authentication validator
func NewValidator(cfg config.AuthConfig) *Validator {
	v := &Validator{
		config:  cfg,
		apiKeys: make(map[string]*APIKeyInfo),
	}

	// If JWT is enabled, prepare the secret
	if cfg.Enabled && cfg.JWTSecret != "" {
		v.secret = []byte(cfg.JWTSecret)
	}

	return v
}

// GenerateToken creates a new JWT token for a user
func (v *Validator) GenerateToken(userID, orgID string, roles []string, permissions []string) (string, time.Time, error) {
	if !v.config.Enabled {
		return "", time.Time{}, fmt.Errorf("authentication is disabled")
	}

	if v.secret == nil {
		return "", time.Time{}, fmt.Errorf("JWT secret not configured")
	}

	now := time.Now()
	expiresAt := now.Add(v.config.JWTExpiration)

	claims := TokenClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    "codex-fabric",
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(expiresAt),
			NotBefore: jwt.NewNumericDate(now),
			ID:        uuid.New().String(),
		},
		UserID:      userID,
		OrgID:       orgID,
		Roles:       roles,
		Permissions: permissions,
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString(v.secret)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("failed to sign token: %w", err)
	}

	return tokenString, expiresAt, nil
}

// ValidateToken validates a JWT token and returns the claims
func (v *Validator) ValidateToken(tokenString string) (*TokenClaims, error) {
	if !v.config.Enabled {
		return &TokenClaims{}, nil
	}

	if v.secret == nil {
		return nil, fmt.Errorf("JWT secret not configured")
	}

	token, err := jwt.ParseWithClaims(tokenString, &TokenClaims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return v.secret, nil
	})

	if err != nil {
		if errors.Is(err, jwt.ErrTokenExpired) {
			return nil, ErrExpiredToken
		}
		return nil, fmt.Errorf("%w: %v", ErrInvalidToken, err)
	}

	if claims, ok := token.Claims.(*TokenClaims); ok && token.Valid {
		// Check if token is too old (max token age)
		if v.config.MaxTokenAge > 0 {
			issuedAt := claims.IssuedAt.Time
			if time.Since(issuedAt) > v.config.MaxTokenAge {
				return nil, ErrExpiredToken
			}
		}

		return claims, nil
	}

	return nil, ErrInvalidToken
}

// ValidateAPIKey validates an API key
func (v *Validator) ValidateAPIKey(apiKey string) (*APIKeyInfo, error) {
	if !v.config.Enabled {
		return &APIKeyInfo{}, nil
	}

	// Use constant-time comparison to prevent timing attacks
	for storedKey, info := range v.apiKeys {
		if subtle.ConstantTimeCompare([]byte(apiKey), []byte(storedKey)) == 1 {
			// Check if key has expired
			if !info.ExpiresAt.IsZero() && time.Now().After(info.ExpiresAt) {
				return nil, ErrExpiredToken
			}
			return info, nil
		}
	}

	return nil, ErrInvalidAPIKey
}

// AddAPIKey adds an API key to the validator
func (v *Validator) AddAPIKey(key, orgID, userID string, roles []string, expiresAt time.Time) {
	v.apiKeys[key] = &APIKeyInfo{
		Key:       key,
		OrgID:     orgID,
		UserID:    userID,
		Roles:     roles,
		ExpiresAt: expiresAt,
		CreatedAt: time.Now(),
	}
}

// RemoveAPIKey removes an API key from the validator
func (v *Validator) RemoveAPIKey(key string) {
	delete(v.apiKeys, key)
}

// HasRole checks if the claims contain the required role
func (v *Validator) HasRole(claims *TokenClaims, role string) bool {
	for _, r := range claims.Roles {
		if r == role {
			return true
		}
	}
	return false
}

// HasPermission checks if the claims contain the required permission
func (v *Validator) HasPermission(claims *TokenClaims, permission string) bool {
	for _, p := range claims.Permissions {
		if p == permission {
			return true
		}
	}
	return false
}

// HasAnyRole checks if the claims contain any of the required roles
func (v *Validator) HasAnyRole(claims *TokenClaims, roles []string) bool {
	for _, role := range roles {
		if v.HasRole(claims, role) {
			return true
		}
	}
	return false
}

// RefreshToken generates a new token with extended expiration
func (v *Validator) RefreshToken(oldTokenString string) (string, time.Time, error) {
	claims, err := v.ValidateToken(oldTokenString)
	if err != nil {
		return "", time.Time{}, err
	}

	// Generate new token with same claims but new expiration
	return v.GenerateToken(claims.UserID, claims.OrgID, claims.Roles, claims.Permissions)
}

// ValidateOrgAccess checks if a user has access to a specific organization
func (v *Validator) ValidateOrgAccess(claims *TokenClaims, orgID string) bool {
	return claims.OrgID == orgID
}

// ExtractFromBearer extracts token from Authorization header
func ExtractFromBearer(authHeader string) (string, error) {
	if authHeader == "" {
		return "", ErrMissingCredentials
	}

	const bearerPrefix = "Bearer "
	if len(authHeader) < len(bearerPrefix) || authHeader[:len(bearerPrefix)] != bearerPrefix {
		return "", ErrMissingCredentials
	}

	return authHeader[len(bearerPrefix):], nil
}

// Middleware creates an authentication middleware function
func (v *Validator) Middleware(requiredRoles []string) func(token string) (*TokenClaims, error) {
	return func(token string) (*TokenClaims, error) {
		claims, err := v.ValidateToken(token)
		if err != nil {
			return nil, err
		}

		if len(requiredRoles) > 0 && !v.HasAnyRole(claims, requiredRoles) {
			return nil, fmt.Errorf("insufficient permissions")
		}

		return claims, nil
	}
}

// GenerateAPIKey generates a new random API key
func GenerateAPIKey() (string, error) {
	// Generate a cryptographically secure random key
	key := uuid.New().String() + "-" + uuid.New().String()
	return key, nil
}

// HashAPIKey creates a hash of an API key for storage
func HashAPIKey(key string) string {
	// In production, use a proper hashing algorithm like bcrypt
	// This is a simplified version
	return key // Placeholder - implement proper hashing
}