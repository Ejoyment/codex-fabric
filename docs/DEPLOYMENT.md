# CODEX Fabric — Deployment Guide

## Docker Compose (Recommended)

### Production Configuration

```yaml
version: '3.8'

services:
  codex-signaling:
    build:
      context: ./backend
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      - CODex_PORT=8080
      - CODEX_MAX_CONNECTIONS=10000
      - CODEX_ALLOWED_ORIGINS=https://your-domain.com
      - CODEX_ENABLE_AUTH=true
      - CODEX_JWT_SECRET=${JWT_SECRET}
      - CODEX_STUN_SERVERS=stun:stun.l.google.com:19302
      - CODEX_TURN_SERVERS=turn:your-turn-server:5349
      - CODEX_TURN_USERNAME=${TURN_USERNAME}
      - CODEX_TURN_PASSWORD=${TURN_PASSWORD}
    volumes:
      - ./config.yaml:/app/config.yaml:ro
      - ./certs:/app/certs:ro
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: '2.0'
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  codex-prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    depends_on:
      - codex-signaling

  codex-grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
    volumes:
      - grafana-data:/var/lib/grafana

volumes:
  grafana-data:
```

### Staging Environment (Air-Gapped)

```yaml
version: '3.8'

services:
  codex-signaling:
    build:
      context: ./backend
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      - CODEX_MAX_CONNECTIONS=1000
      - CODEX_ALLOWED_ORIGINS=*
      - CODEX_ENABLE_AUTH=false
    volumes:
      - ./config-staging.yaml:/app/config.yaml:ro
    restart: always
    networks:
      - codex-internal

  # Internal STUN/TURN for air-gapped environment
  coturn:
    image: coturn/coturn:latest
    ports:
      - "3478:3478"
      - "5349:5349"
    volumes:
      - ./coturn.conf:/etc/coturn/coturn.conf:ro
    networks:
      - codex-internal

networks:
  codex-internal:
    driver: bridge
    internal: true  # No external access
```

## Manual Deployment

### Build the Server

```bash
cd backend
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o codex-server ./cmd/server
```

### Systemd Service

```ini
[Unit]
Description=Codex Fabric Signaling Server
After=network.target

[Service]
Type=simple
User=codex
Group=codex
WorkingDirectory=/opt/codex-fabric
ExecStart=/opt/codex-fabric/codex-server -config /etc/codex/config.yaml
Restart=always
RestartSec=5
LimitNOFILE=65536

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/codex

[Install]
WantedBy=multi-user.target
```

### Nginx Reverse Proxy (TLS Termination)

```nginx
upstream codex_backend {
    server 127.0.0.1:8080;
}

server {
    listen 443 ssl http2;
    server_name signaling.your-domain.com;

    ssl_certificate /etc/letsencrypt/live/signaling.your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/signaling.your-domain.com/privkey.pem;
    ssl_protocols TLSv1.3;

    location /ws {
        proxy_pass http://codex_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }

    location /health {
        proxy_pass http://codex_backend;
    }
}
```

## TURN Server Configuration (coturn)

For production, deploy a TURN server for NAT traversal in restrictive environments:

```ini
# /etc/coturn/coturn.conf
listening-port=3478
tls-listening-port=5349
fingerprint
lt-cred-mech
user=codex:${TURN_PASSWORD}
realm=your-domain.com
total-quota=100
stale-nonce=600
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CODEX_PORT` | 8080 | Server listen port |
| `CODEX_MAX_CONNECTIONS` | 10000 | Maximum concurrent connections |
| `CODEX_ALLOWED_ORIGINS` | `*` | CORS allowed origins |
| `CODEX_ENABLE_AUTH` | false | Enable JWT authentication |
| `CODEX_JWT_SECRET` | — | JWT signing secret |
| `CODEX_STUN_SERVERS` | — | Comma-separated STUN servers |
| `CODEX_TURN_SERVERS` | — | Comma-separated TURN servers |

## Monitoring

### Prometheus Metrics

The server exposes metrics at `http://localhost:8080/metrics`:

- `codex_connections_total` — Total connections
- `codex_connections_active` — Active connections
- `codex_messages_total` — Total messages processed
- `codex_key_exchanges_total` — Total E2EE key exchanges

### Health Check

```bash
curl http://localhost:8080/health
# Returns: {"status":"ok","connections":42,"rooms":5}
```

## Security Checklist

- [ ] TLS 1.3 enabled (WSS only, no plain WS)
- [ ] CORS configured for specific domains (not `*`)
- [ ] JWT authentication enabled
- [ ] TURN server credentials rotated monthly
- [ ] Firewall rules restrict port access
- [ ] Log monitoring configured
- [ ] Rate limiting enabled
- [ ] Max connections configured appropriately