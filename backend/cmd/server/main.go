package main

import (
	"context"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/Ejoyment/codex-fabric/backend/internal/auth"
	"github.com/Ejoyment/codex-fabric/backend/internal/config"
	"github.com/Ejoyment/codex-fabric/backend/internal/signaling"
	"github.com/Ejoyment/codex-fabric/backend/internal/webrtc"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.uber.org/zap"
)

var (
	version   = "dev"
	buildTime = "unknown"
	gitCommit = "unknown"
)

func main() {
	// Parse command line flags
	configPath := flag.String("config", "config.yaml", "path to configuration file")
	showVersion := flag.Bool("version", false, "show version information")
	flag.Parse()

	if *showVersion {
		fmt.Printf("CODEX Fabric Signaling Server\n")
		fmt.Printf("Version: %s\n", version)
		fmt.Printf("Build Time: %s\n", buildTime)
		fmt.Printf("Git Commit: %s\n", gitCommit)
		os.Exit(0)
	}

	// Initialize logger
	logger, err := zap.NewProduction()
	if err != nil {
		fmt.Printf("Failed to initialize logger: %v\n", err)
		os.Exit(1)
	}
	defer logger.Sync()

	logger.Info("Starting CODEX Fabric Signaling Server",
		zap.String("version", version),
		zap.String("build_time", buildTime),
		zap.String("git_commit", gitCommit))

	// Load configuration
	cfg, err := config.Load(*configPath)
	if err != nil {
		logger.Fatal("Failed to load configuration", zap.Error(err))
	}

	// Validate configuration
	if err := cfg.Validate(); err != nil {
		logger.Fatal("Invalid configuration", zap.Error(err))
	}

	// Initialize WebRTC manager
	webrtcManager, err := webrtc.NewManager(cfg.WebRTC, logger)
	if err != nil {
		logger.Fatal("Failed to initialize WebRTC manager", zap.Error(err))
	}
	defer webrtcManager.Close()

	// Initialize auth validator
	authValidator := auth.NewValidator(cfg.Auth)

	// Initialize signaling server
	sigServer, err := signaling.NewServer(cfg.Signaling, webrtcManager, authValidator, logger)
	if err != nil {
		logger.Fatal("Failed to initialize signaling server", zap.Error(err))
	}

	// Setup HTTP routes
	mux := http.NewServeMux()
	// WebSocket endpoint is protected by the auth middleware. When
	// auth.enabled is false the middleware passes requests through
	// unchanged, preserving the unauthenticated development behavior.
	mux.Handle("/ws", authValidator.HTTPMiddleware(http.HandlerFunc(sigServer.HandleWebSocket)))
	mux.HandleFunc("/health", handleHealth)
	mux.HandleFunc("/ready", handleReady)
	mux.Handle("/metrics", promhttp.Handler())

	// Create HTTP server
	server := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.Server.Port),
		Handler:      setupMiddleware(mux, logger),
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Start server in goroutine
	go func() {
		logger.Info("Starting HTTP server",
			zap.Int("port", cfg.Server.Port),
			zap.String("tls", map[bool]string{true: "enabled", false: "disabled"}[cfg.Server.TLSEnabled]))

		var err error
		if cfg.Server.TLSEnabled {
			err = server.ListenAndServeTLS(cfg.Server.TLSCertFile, cfg.Server.TLSKeyFile)
		} else {
			err = server.ListenAndServe()
		}

		if err != nil && err != http.ErrServerClosed {
			logger.Fatal("HTTP server failed", zap.Error(err))
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("Shutting down server...")

	// Graceful shutdown
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		logger.Error("Server forced to shutdown", zap.Error(err))
	}

	logger.Info("Server stopped gracefully")
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func handleReady(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("Ready"))
}

func setupMiddleware(next http.Handler, logger *zap.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Security headers
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("X-XSS-Protection", "1; mode=block")
		w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		w.Header().Set("Content-Security-Policy", "default-src 'none'")
		w.Header().Set("Referrer-Policy", "no-referrer")

		// Log request
		logger.Debug("Request started",
			zap.String("method", r.Method),
			zap.String("path", r.URL.Path),
			zap.String("remote_addr", r.RemoteAddr),
			zap.String("user_agent", r.UserAgent()))

		// Wrap response writer to capture status code
		wrapped := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		next.ServeHTTP(wrapped, r)

		// Log completion
		logger.Debug("Request completed",
			zap.Int("status", wrapped.statusCode),
			zap.Duration("duration", time.Since(start)),
			zap.String("method", r.Method),
			zap.String("path", r.URL.Path))
	})
}

type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}
