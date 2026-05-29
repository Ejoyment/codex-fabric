package config

import (
	"fmt"
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

// Config represents the complete server configuration
type Config struct {
	Server   ServerConfig   `yaml:"server"`
	Signaling SignalingConfig `yaml:"signaling"`
	WebRTC   WebRTCConfig   `yaml:"webrtc"`
	Auth     AuthConfig     `yaml:"auth"`
	Redis    RedisConfig    `yaml:"redis"`
	Metrics  MetricsConfig  `yaml:"metrics"`
}

// ServerConfig holds HTTP server configuration
type ServerConfig struct {
	Port         int    `yaml:"port"`
	TLSEnabled   bool   `yaml:"tls_enabled"`
	TLSCertFile  string `yaml:"tls_cert_file"`
	TLSKeyFile   string `yaml:"tls_key_file"`
	ReadTimeout  string `yaml:"read_timeout"`
	WriteTimeout string `yaml:"write_timeout"`
	IdleTimeout  string `yaml:"idle_timeout"`
}

// SignalingConfig holds WebSocket signaling configuration
type SignalingConfig struct {
	AllowedOrigins    []string      `yaml:"allowed_origins"`
	MaxMessageSize    int64         `yaml:"max_message_size"`
	HandshakeTimeout  time.Duration `yaml:"handshake_timeout"`
	PingInterval      time.Duration `yaml:"ping_interval"`
	PongWait          time.Duration `yaml:"pong_wait"`
	WriteWait         time.Duration `yaml:"write_wait"`
	MaxConnections    int           `yaml:"max_connections"`
	EnableCompression bool          `yaml:"enable_compression"`
}

// WebRTCConfig holds WebRTC configuration
type WebRTCConfig struct {
	ICEServers        []ICEServerConfig `yaml:"ice_servers"`
	STUNServers       []string          `yaml:"stun_servers"`
	TURNServers       []TURNServerConfig `yaml:"turn_servers"`
	EnableTURN        bool              `yaml:"enable_turn"`
	TURNUsername      string            `yaml:"turn_username"`
	TURNPassword      string            `yaml:"turn_password"`
	TURNRealm         string            `yaml:"turn_realm"`
	ICEGatherTimeout  time.Duration     `yaml:"ice_gather_timeout"`
	ConnectionTimeout time.Duration     `yaml:"connection_timeout"`
	EnableDataChannel bool              `yaml:"enable_data_channel"`
}

// ICEServerConfig represents a single ICE server
type ICEServerConfig struct {
	URLs       []string `yaml:"urls"`
	Username   string   `yaml:"username,omitempty"`
	Credential string   `yaml:"credential,omitempty"`
}

// TURNServerConfig represents a TURN server configuration
type TURNServerConfig struct {
	URL        string `yaml:"url"`
	Username   string `yaml:"username"`
	Password   string `yaml:"password"`
	Realm      string `yaml:"realm"`
	StaticAuthSecret string `yaml:"static_auth_secret,omitempty"`
}

// AuthConfig holds authentication configuration
type AuthConfig struct {
	Enabled           bool          `yaml:"enabled"`
	JWTSecret         string        `yaml:"jwt_secret"`
	JWTExpiration     time.Duration `yaml:"jwt_expiration"`
	APIKeyHeader      string        `yaml:"api_key_header"`
	AllowInsecure     bool          `yaml:"allow_insecure"`
	RequiredRoles     []string      `yaml:"required_roles"`
	MaxTokenAge       time.Duration `yaml:"max_token_age"`
}

// RedisConfig holds Redis configuration for session management
type RedisConfig struct {
	Enabled       bool          `yaml:"enabled"`
	Addr          string        `yaml:"addr"`
	Password      string        `yaml:"password"`
	DB            int           `yaml:"db"`
	PoolSize      int           `yaml:"pool_size"`
	MinIdleConns  int           `yaml:"min_idle_conns"`
	IdleTimeout   time.Duration `yaml:"idle_timeout"`
	DialTimeout   time.Duration `yaml:"dial_timeout"`
	ReadTimeout   time.Duration `yaml:"read_timeout"`
	WriteTimeout  time.Duration `yaml:"write_timeout"`
}

// MetricsConfig holds Prometheus metrics configuration
type MetricsConfig struct {
	Enabled     bool   `yaml:"enabled"`
	Path        string `yaml:"path"`
	EnableGoMetrics bool `yaml:"enable_go_metrics"`
	EnableProcessMetrics bool `yaml:"enable_process_metrics"`
}

// Load reads and parses the configuration from a YAML file
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %w", err)
	}

	// Apply defaults
	cfg.setDefaults()

	// Override with environment variables
	cfg.overrideFromEnv()

	return &cfg, nil
}

// setDefaults applies default values to configuration
func (c *Config) setDefaults() {
	// Server defaults
	if c.Server.Port == 0 {
		c.Server.Port = 8080
	}
	if c.Server.ReadTimeout == "" {
		c.Server.ReadTimeout = "15s"
	}
	if c.Server.WriteTimeout == "" {
		c.Server.WriteTimeout = "15s"
	}
	if c.Server.IdleTimeout == "" {
		c.Server.IdleTimeout = "60s"
	}

	// Signaling defaults
	if c.Signaling.MaxMessageSize == 0 {
		c.Signaling.MaxMessageSize = 1024 * 1024 // 1MB
	}
	if c.Signaling.HandshakeTimeout == 0 {
		c.Signaling.HandshakeTimeout = 10 * time.Second
	}
	if c.Signaling.PingInterval == 0 {
		c.Signaling.PingInterval = 30 * time.Second
	}
	if c.Signaling.PongWait == 0 {
		c.Signaling.PongWait = 60 * time.Second
	}
	if c.Signaling.WriteWait == 0 {
		c.Signaling.WriteWait = 10 * time.Second
	}
	if c.Signaling.MaxConnections == 0 {
		c.Signaling.MaxConnections = 10000
	}

	// WebRTC defaults
	if len(c.WebRTC.STUNServers) == 0 {
		c.WebRTC.STUNServers = []string{
			"stun:stun.l.google.com:19302",
			"stun:stun1.l.google.com:19302",
			"stun:stun2.l.google.com:19302",
			"stun:stun3.l.google.com:19302",
			"stun:stun4.l.google.com:19302",
		}
	}
	if c.WebRTC.ICEGatherTimeout == 0 {
		c.WebRTC.ICEGatherTimeout = 10 * time.Second
	}
	if c.WebRTC.ConnectionTimeout == 0 {
		c.WebRTC.ConnectionTimeout = 30 * time.Second
	}
	if c.WebRTC.TURNRealm == "" {
		c.WebRTC.TURNRealm = "codex.fabric"
	}

	// Auth defaults
	if c.Auth.APIKeyHeader == "" {
		c.Auth.APIKeyHeader = "X-API-Key"
	}
	if c.Auth.JWTExpiration == 0 {
		c.Auth.JWTExpiration = 24 * time.Hour
	}
	if c.Auth.MaxTokenAge == 0 {
		c.Auth.MaxTokenAge = 1 * time.Hour
	}

	// Redis defaults
	if c.Redis.Addr == "" {
		c.Redis.Addr = "localhost:6379"
	}
	if c.Redis.PoolSize == 0 {
		c.Redis.PoolSize = 10
	}
	if c.Redis.MinIdleConns == 0 {
		c.Redis.MinIdleConns = 5
	}
	if c.Redis.IdleTimeout == 0 {
		c.Redis.IdleTimeout = 5 * time.Minute
	}
	if c.Redis.DialTimeout == 0 {
		c.Redis.DialTimeout = 5 * time.Second
	}
	if c.Redis.ReadTimeout == 0 {
		c.Redis.ReadTimeout = 3 * time.Second
	}
	if c.Redis.WriteTimeout == 0 {
		c.Redis.WriteTimeout = 3 * time.Second
	}

	// Metrics defaults
	if c.Metrics.Path == "" {
		c.Metrics.Path = "/metrics"
	}
}

// overrideFromEnv overrides configuration with environment variables
func (c *Config) overrideFromEnv() {
	if port := os.Getenv("SERVER_PORT"); port != "" {
		c.Server.Port = 8080 // Parse int in real implementation
	}
	if secret := os.Getenv("AUTH_JWT_SECRET"); secret != "" {
		c.Auth.JWTSecret = secret
	}
	if redisAddr := os.Getenv("REDIS_ADDR"); redisAddr != "" {
		c.Redis.Addr = redisAddr
	}
	if redisPassword := os.Getenv("REDIS_PASSWORD"); redisPassword != "" {
		c.Redis.Password = redisPassword
	}
}

// Validate checks if the configuration is valid
func (c *Config) Validate() error {
	if c.Server.Port < 1 || c.Server.Port > 65535 {
		return fmt.Errorf("invalid server port: %d", c.Server.Port)
	}

	if c.Server.TLSEnabled {
		if c.Server.TLSCertFile == "" {
			return fmt.Errorf("TLS enabled but no certificate file specified")
		}
		if c.Server.TLSKeyFile == "" {
			return fmt.Errorf("TLS enabled but no key file specified")
		}
	}

	if c.Signaling.MaxConnections < 1 {
		return fmt.Errorf("invalid max connections: %d", c.Signaling.MaxConnections)
	}

	if c.Signaling.MaxMessageSize < 1024 {
		return fmt.Errorf("max message size too small: %d", c.Signaling.MaxMessageSize)
	}

	if c.Auth.Enabled && c.Auth.JWTSecret == "" && !c.Auth.AllowInsecure {
		return fmt.Errorf("auth enabled but no JWT secret provided")
	}

	return nil
}

// GetICEServers returns combined ICE servers from configuration
func (c *WebRTCConfig) GetICEServers() []ICEServerConfig {
	var servers []ICEServerConfig

	// Add STUN servers
	for _, stun := range c.STUNServers {
		servers = append(servers, ICEServerConfig{
			URLs: []string{stun},
		})
	}

	// Add configured ICE servers
	servers = append(servers, c.ICEServers...)

	// Add TURN servers if enabled
	if c.EnableTURN {
		for _, turn := range c.TURNServers {
			servers = append(servers, ICEServerConfig{
				URLs:       []string{turn.URL},
				Username:   turn.Username,
				Credential: turn.Password,
			})
		}
	}

	return servers
}