# Makefile for MinIO Enterprise
# Best practices compliant build system

.PHONY: help build test test-race bench security-scan validate clean deploy docker-build fmt lint coverage install run all api-docs api-docs-build api-docs-stop

# Variables
BINARY_NAME=minio-enterprise
GO=go
DOCKER=docker
DOCKER_COMPOSE=docker-compose
BUILD_DIR=bin
COVERAGE_FILE=coverage.out

# Build flags
VERSION?=2.0.0
BUILD_DATE=$(shell date -u +%Y-%m-%dT%H:%M:%SZ)
GIT_COMMIT=$(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
LDFLAGS=-ldflags "-s -w -X main.Version=$(VERSION) -X main.BuildDate=$(BUILD_DATE) -X main.GitCommit=$(GIT_COMMIT)"

# Colors for output
CYAN=\033[0;36m
GREEN=\033[0;32m
RED=\033[0;31m
NC=\033[0m

## help: Display this help message
help:
	@echo "$(CYAN)MinIO Enterprise - Build System$(NC)"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
	@echo ""

## build: Build the server binary
build:
	@echo "$(CYAN)Building $(BINARY_NAME)...$(NC)"
	@mkdir -p $(BUILD_DIR)
	$(GO) build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) ./cmd/server
	@echo "$(GREEN)✓ Build complete: $(BUILD_DIR)/$(BINARY_NAME)$(NC)"

## test: Run all tests
test:
	@echo "$(CYAN)Running tests...$(NC)"
	$(GO) test -v -timeout 60s ./...
	@echo "$(GREEN)✓ All tests passed$(NC)"

## test-race: Run tests with race detector
test-race:
	@echo "$(CYAN)Running tests with race detector...$(NC)"
	$(GO) test -v -race -timeout 60s ./...
	@echo "$(GREEN)✓ Race detector tests passed$(NC)"

## bench: Run performance benchmarks
bench:
	@echo "$(CYAN)Running benchmarks...$(NC)"
	$(GO) test -bench=. -benchmem -run=^$$ ./...
	@echo "$(GREEN)✓ Benchmarks complete$(NC)"

## security-scan: Run security scans
security-scan:
	@echo "$(CYAN)Running security scans...$(NC)"
	@bash scripts/security-check.sh
	@echo "$(GREEN)✓ Security scans passed$(NC)"

## validate: Validate all configurations
validate:
	@echo "$(CYAN)Validating configurations...$(NC)"
	@bash scripts/validate-configs.sh
	@echo "$(GREEN)✓ Configurations valid$(NC)"

## docker-build: Build Docker image
docker-build:
	@echo "$(CYAN)Building Docker image...$(NC)"
	$(DOCKER) build -f deployments/docker/Dockerfile -t $(BINARY_NAME):$(VERSION) -t $(BINARY_NAME):latest .
	@echo "$(GREEN)✓ Docker image built: $(BINARY_NAME):$(VERSION)$(NC)"

## deploy: Deploy with Docker Compose
deploy:
	@echo "$(CYAN)Deploying with Docker Compose...$(NC)"
	cd deployments/docker && $(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)✓ Deployment complete$(NC)"
	@echo "$(CYAN)Services available at:$(NC)"
	@echo "  - MinIO API:     http://localhost:9000"
	@echo "  - MinIO Console: http://localhost:9001"
	@echo "  - Grafana:       http://localhost:3000"
	@echo "  - Prometheus:    http://localhost:9090"

## deploy-down: Stop Docker Compose deployment
deploy-down:
	@echo "$(CYAN)Stopping deployment...$(NC)"
	cd deployments/docker && $(DOCKER_COMPOSE) down
	@echo "$(GREEN)✓ Deployment stopped$(NC)"

## api-docs: Start API documentation server
api-docs:
	@echo "$(CYAN)Starting API documentation server...$(NC)"
	@if command -v $(GO) >/dev/null 2>&1; then \
		$(GO) run cmd/api-docs-server/main.go & \
		echo "$(GREEN)✓ API documentation server started$(NC)"; \
		echo "$(CYAN)Open in browser: http://localhost:8080/index.html$(NC)"; \
	else \
		echo "$(RED)Go not installed. Using Python HTTP server...$(NC)"; \
		cd docs/api && python3 -m http.server 8080 & \
		echo "$(GREEN)✓ API documentation server started$(NC)"; \
		echo "$(CYAN)Open in browser: http://localhost:8080$(NC)"; \
	fi

## api-docs-build: Build API documentation Docker image
api-docs-build:
	@echo "$(CYAN)Building API documentation Docker image...$(NC)"
	$(DOCKER) build -f deployments/docker/api-docs.Dockerfile -t minio-api-docs:latest .
	@echo "$(GREEN)✓ API documentation image built$(NC)"

## api-docs-deploy: Deploy API documentation with Docker
api-docs-deploy: api-docs-build
	@echo "$(CYAN)Deploying API documentation...$(NC)"
	cd deployments/docker && $(DOCKER_COMPOSE) -f docker-compose.api-docs.yml up -d
	@echo "$(GREEN)✓ API documentation deployed$(NC)"
	@echo "$(CYAN)Access at: http://localhost:8080$(NC)"

## api-docs-stop: Stop API documentation server
api-docs-stop:
	@echo "$(CYAN)Stopping API documentation server...$(NC)"
	cd deployments/docker && $(DOCKER_COMPOSE) -f docker-compose.api-docs.yml down 2>/dev/null || true
	@echo "$(GREEN)✓ API documentation stopped$(NC)"

## clean: Clean build artifacts
clean:
	@echo "$(CYAN)Cleaning build artifacts...$(NC)"
	rm -rf $(BUILD_DIR)/
	rm -f $(COVERAGE_FILE) coverage.html
	$(GO) clean
	@echo "$(GREEN)✓ Clean complete$(NC)"

## fmt: Format Go code
fmt:
	@echo "$(CYAN)Formatting code...$(NC)"
	$(GO) fmt ./...
	@echo "$(GREEN)✓ Code formatted$(NC)"

## lint: Run linter
lint:
	@echo "$(CYAN)Running linter...$(NC)"
	@if command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run --config build/.golangci.yml; \
		echo "$(GREEN)✓ Linting complete$(NC)"; \
	else \
		echo "$(RED)golangci-lint not installed. Skipping...$(NC)"; \
	fi

## coverage: Generate test coverage report
coverage:
	@echo "$(CYAN)Generating coverage report...$(NC)"
	$(GO) test -coverprofile=$(COVERAGE_FILE) ./...
	$(GO) tool cover -html=$(COVERAGE_FILE) -o coverage.html
	@echo "$(GREEN)✓ Coverage report: coverage.html$(NC)"

## install: Install the binary to GOPATH/bin
install: build
	@echo "$(CYAN)Installing $(BINARY_NAME)...$(NC)"
	cp $(BUILD_DIR)/$(BINARY_NAME) $(shell go env GOPATH)/bin/
	@echo "$(GREEN)✓ Installed to $(shell go env GOPATH)/bin/$(BINARY_NAME)$(NC)"

## run: Run the server locally
run: build
	@echo "$(CYAN)Starting server...$(NC)"
	./$(BUILD_DIR)/$(BINARY_NAME)

## all: Run all checks and build
all: fmt lint test-race security-scan validate build
	@echo "$(GREEN)✓ All checks passed and build complete$(NC)"

.DEFAULT_GOAL := help
