# Multi-stage build for API documentation server
FROM golang:1.22-alpine AS builder

WORKDIR /build

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY cmd/api-docs-server ./cmd/api-docs-server

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o api-docs-server ./cmd/api-docs-server

# Final stage - minimal image
FROM nginx:alpine

# Copy custom nginx config
COPY deployments/docker/nginx-api-docs.conf /etc/nginx/conf.d/default.conf

# Copy API documentation files
COPY docs/api /usr/share/nginx/html

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost/index.html || exit 1

# Run nginx
CMD ["nginx", "-g", "daemon off;"]
