# Dockerfile for Enterprise MinIO Services
FROM golang:1.21-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git gcc musl-dev

WORKDIR /build

# Copy source code
COPY . .

# Build the enterprise service with optimizations
RUN CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-s -w -X main.version=$(git describe --tags --always)" \
    -o enterprise-minio-service \
    ./cmd/enterprise-service

# Final runtime image
FROM alpine:3.18

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    curl \
    tzdata \
    postgresql-client \
    bash

# Create non-root user
RUN addgroup -g 1000 minio && \
    adduser -D -u 1000 -G minio minio

# Create necessary directories
RUN mkdir -p /var/lib/minio /var/log/minio /etc/minio && \
    chown -R minio:minio /var/lib/minio /var/log/minio /etc/minio

WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/enterprise-minio-service .

# Copy configuration templates
COPY --chown=minio:minio config/ /etc/minio/

# Health check
HEALTHCHECK --interval=30s --timeout=20s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Metrics export port
EXPOSE 9090

# API port
EXPOSE 8080

# Console port (MinIO)
EXPOSE 9001

# Run as non-root
USER minio

# Start service
ENTRYPOINT ["./enterprise-minio-service"]
CMD ["--config", "/etc/minio/config.yaml"]
