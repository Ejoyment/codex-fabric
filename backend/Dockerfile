# Build stage
FROM golang:1.21-alpine AS builder

# Install necessary build dependencies
RUN apk add --no-cache git ca-certificates

# Set working directory
WORKDIR /build

# Copy go mod files first for better caching
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the binary with optimizations
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -ldflags="-w -s -X main.version=${VERSION:-dev} -X main.buildTime=$(date -u +%Y-%m-%dT%H:%M:%SZ) -X main.gitCommit=$(git rev-parse --short HEAD)" -o /build/codex-fabric ./cmd/server

# Runtime stage
FROM alpine:3.19

# Install ca-certificates for HTTPS
RUN apk --no-cache add ca-certificates tzdata

# Create non-root user for security
RUN addgroup -g 1000 codex && adduser -D -u 1000 -G codex codex

# Set working directory
WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/codex-fabric .
COPY --from=builder /build/config.yaml .

# Create directories for TLS certificates and data
RUN mkdir -p /app/certs /app/data && chown -R codex:codex /app

# Switch to non-root user
USER codex

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run the server
ENTRYPOINT ["./codex-fabric"]
CMD ["--config", "config.yaml"]