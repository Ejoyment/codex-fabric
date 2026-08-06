package auth

import (
	"context"
	"encoding/json"
	"net/http"
)

type contextKey string

const (
	// claimsContextKey holds the authenticated TokenClaims in the request context
	claimsContextKey contextKey = "auth_claims"
)

// HTTPMiddleware authenticates incoming HTTP requests against the Validator.
//
// Credentials are extracted from the Authorization header ("Bearer <jwt>")
// with a fallback to the "token" query parameter for clients (e.g. browsers)
// that cannot set custom headers on WebSocket handshakes.
//
// When authentication is disabled in configuration the middleware passes
// every request through untouched, preserving the current development
// behavior. When enabled, requests without valid credentials are rejected
// with HTTP 401 before reaching the downstream handler.
func (v *Validator) HTTPMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Authentication is optional: pass through when disabled
		if !v.config.Enabled {
			next.ServeHTTP(w, r)
			return
		}

		token, err := ExtractFromBearer(r.Header.Get("Authorization"))
		if err != nil {
			// Fall back to the "token" query parameter for clients that
			// cannot set custom headers (e.g. browser WebSockets)
			token = r.URL.Query().Get("token")
			if token == "" {
				writeAuthError(w, http.StatusUnauthorized, ErrMissingCredentials)
				return
			}
		}

		claims, err := v.ValidateToken(token)
		if err != nil {
			writeAuthError(w, http.StatusUnauthorized, err)
			return
		}

		// Enforce required roles when configured
		if len(v.config.RequiredRoles) > 0 && !v.HasAnyRole(claims, v.config.RequiredRoles) {
			writeAuthError(w, http.StatusForbidden, &forbiddenError{})
			return
		}

		ctx := context.WithValue(r.Context(), claimsContextKey, claims)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// ClaimsFromContext returns the authenticated claims stored by HTTPMiddleware,
// or nil when no claims are present in the context.
func ClaimsFromContext(ctx context.Context) *TokenClaims {
	claims, _ := ctx.Value(claimsContextKey).(*TokenClaims)
	return claims
}

type forbiddenError struct{}

func (e *forbiddenError) Error() string { return "insufficient permissions" }

func writeAuthError(w http.ResponseWriter, status int, err error) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
}
