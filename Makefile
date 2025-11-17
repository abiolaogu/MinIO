# Makefile for Enterprise MinIO
.PHONY: help build test deploy clean lint fmt docker push local-dev

VERSION ?= $(shell git describe --tags --always)
DOCKER_REGISTRY ?= docker.io
DOCKER_NAMESPACE ?= enterprise-minio
DOCKER_IMAGE ?= $(DOCKER_REGISTRY)/$(DOCKER_NAMESPACE)/minio
DOCKER_TAG ?= $(VERSION)

# Directories
ENTERPRISE_DIR := enterprise
CMD_DIR := cmd
DIST_DIR := dist

# Build flags
BUILD_FLAGS := -ldflags="-s -w -X main.version=$(VERSION) -X main.buildTime=$(shell date -u '+%Y-%m-%d_%H:%M:%S_UTC')"

## help: Display this help message
help:
	@echo "Enterprise MinIO - Build and Deployment"
	@echo ""
	@grep -E '^## ' Makefile | sed 's/## //'

## setup: Install development dependencies
setup:
	go mod download
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	go install github.com/cosmtrek/air@latest
	npm install -g prettier

## lint: Run linters on Go code
lint:
	@echo "Running linters..."
	golangci-lint run ./... --deadline=5m
	go vet ./...

## fmt: Format code
fmt:
	@echo "Formatting code..."
	go fmt ./...
	goimports -w .
	cd $(ENTERPRISE_DIR)/dashboard && npm run format

## test: Run unit tests
test:
	@echo "Running tests..."
	go test -v -race -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report: coverage.html"

## test-integration: Run integration tests
test-integration:
	@echo "Running integration tests..."
	docker-compose -f docker-compose.test.yml up -d
	sleep 10
	go test -v -tags=integration ./...
	docker-compose -f docker-compose.test.yml down

## test-performance: Run performance benchmarks
test-performance:
	@echo "Running performance benchmarks..."
	go test -v -bench=. -benchmem -benchtime=10s ./enterprise/performance/...
	go test -v -bench=. -benchmem -benchtime=10s ./enterprise/replication/...

## build: Build binaries
build: lint test
	@echo "Building Enterprise MinIO (v$(VERSION))..."
	mkdir -p $(DIST_DIR)
	
	# Build main service
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
		$(BUILD_FLAGS) \
		-o $(DIST_DIR)/enterprise-minio-service-linux-amd64 \
		./cmd/enterprise-service
	
	# Build for macOS
	CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build \
		$(BUILD_FLAGS) \
		-o $(DIST_DIR)/enterprise-minio-service-darwin-amd64 \
		./cmd/enterprise-service
	
	# Build for Windows
	CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build \
		$(BUILD_FLAGS) \
		-o $(DIST_DIR)/enterprise-minio-service-windows-amd64.exe \
		./cmd/enterprise-service
	
	@echo "Build complete: $(DIST_DIR)/"

## docker-build: Build Docker image
docker-build:
	@echo "Building Docker image: $(DOCKER_IMAGE):$(DOCKER_TAG)"
	docker build \
		--build-arg VERSION=$(VERSION) \
		-t $(DOCKER_IMAGE):$(DOCKER_TAG) \
		-t $(DOCKER_IMAGE):latest \
		-f $(ENTERPRISE_DIR)/Dockerfile \
		.

## docker-push: Push Docker image to registry
docker-push: docker-build
	@echo "Pushing Docker image to registry..."
	docker push $(DOCKER_IMAGE):$(DOCKER_TAG)
	docker push $(DOCKER_IMAGE):latest

## docker-run: Run Docker container locally
docker-run:
	@echo "Starting Enterprise MinIO in Docker..."
	docker run -d \
		--name enterprise-minio \
		-p 8080:8080 \
		-p 9000:9000 \
		-p 9001:9001 \
		-p 9090:9090 \
		-e MINIO_ENDPOINT=http://minio:9000 \
		-e LOG_LEVEL=info \
		$(DOCKER_IMAGE):latest
	@echo "Service started. API: http://localhost:8080, Dashboard: http://localhost:9001"

## local-dev: Start local development environment
local-dev:
	@echo "Starting local development environment..."
	docker-compose -f docker-compose.enterprise.yml up -d
	@echo ""
	@echo "Services available at:"
	@echo "  MinIO API: http://localhost:9000"
	@echo "  MinIO Console: http://localhost:9001"
	@echo "  Enterprise API: http://localhost:8080"
	@echo "  Prometheus: http://localhost:9090"
	@echo "  Grafana: http://localhost:3000"
	@echo "  Dashboard: http://localhost:3001"
	@echo ""
	@echo "Default credentials: minioadmin / minioadmin123"

## local-stop: Stop local development environment
local-stop:
	@echo "Stopping local development environment..."
	docker-compose -f docker-compose.enterprise.yml down

## local-logs: View local development logs
local-logs:
	docker-compose -f docker-compose.enterprise.yml logs -f

## deploy-k8s: Deploy to Kubernetes
deploy-k8s:
	@echo "Deploying to Kubernetes..."
	kubectl create namespace enterprise-minio || true
	kubectl create secret generic minio-credentials \
		--from-literal=username=minioadmin \
		--from-literal=password=minioadmin123 \
		-n enterprise-minio \
		--dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f k8s/
	@echo "Deployment complete"

## deploy-k8s-check: Check Kubernetes deployment status
deploy-k8s-check:
	@echo "Checking deployment status..."
	kubectl -n enterprise-minio get all
	kubectl -n enterprise-minio get events --sort-by='.lastTimestamp'

## deploy-k8s-logs: View Kubernetes pod logs
deploy-k8s-logs:
	@echo "Fetching pod logs..."
	kubectl -n enterprise-minio logs -f deployment/enterprise-minio-api

## docs: Generate documentation
docs:
	@echo "Generating documentation..."
	go doc -all ./... > docs/API.md
	@echo "Documentation generated: docs/API.md"

## security-scan: Run security scanning
security-scan:
	@echo "Running security scans..."
	go list -json -m all | nancy sleuth
	trivy image $(DOCKER_IMAGE):latest

## benchmark-s3: Run S3 compatibility benchmarks
benchmark-s3:
	@echo "Running S3 compatibility benchmarks..."
	docker-compose -f docker-compose.enterprise.yml up -d
	sleep 10
	go run ./cmd/benchmark-s3/main.go \
		--endpoint http://localhost:9000 \
		--access-key minioadmin \
		--secret-key minioadmin123 \
		--bucket test-bucket \
		--duration 60s
	docker-compose -f docker-compose.enterprise.yml down

## coverage-report: Generate coverage report
coverage-report: test
	@echo "Generating coverage report..."
	go tool cover -html=coverage.out -o coverage.html
	open coverage.html

## migrate-db: Run database migrations
migrate-db:
	@echo "Running database migrations..."
	migrate -path ./migrations -database "postgresql://$$DB_USER:$$DB_PASSWORD@$$DB_HOST:$$DB_PORT/$$DB_NAME" up

## clean: Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(DIST_DIR)
	rm -f coverage.out coverage.html
	docker-compose -f docker-compose.enterprise.yml down || true

## version: Display version information
version:
	@echo "Enterprise MinIO Version: $(VERSION)"
	@go version

## deps: Display dependencies
deps:
	@echo "External dependencies:"
	go list -m all | head -20

## vendor: Vendor dependencies
vendor:
	@echo "Vendoring dependencies..."
	go mod vendor
	go mod tidy

## pre-commit: Run pre-commit checks
pre-commit: fmt lint test
	@echo "Pre-commit checks passed!"

## release: Create a release
release: clean build
	@echo "Creating release $(VERSION)..."
	git tag -a v$(VERSION) -m "Release $(VERSION)"
	git push origin v$(VERSION)
	@echo "Release created: v$(VERSION)"

## watch: Watch for file changes and rebuild
watch:
	@echo "Watching for changes..."
	air -c .air.toml

## profile-cpu: Generate CPU profile
profile-cpu:
	@echo "Running CPU profile..."
	go test -cpuprofile=cpu.prof -bench=. ./enterprise/replication/...
	go tool pprof -http=:8081 cpu.prof

## profile-memory: Generate memory profile
profile-memory:
	@echo "Running memory profile..."
	go test -memprofile=mem.prof -bench=. ./enterprise/replication/...
	go tool pprof -http=:8081 mem.prof

## quality-gates: Check code quality gates
quality-gates:
	@echo "Checking code quality gates..."
	@test $$(go fmt ./... | wc -l) -eq 0 || (echo "Code is not formatted"; exit 1)
	@golangci-lint run ./... || exit 1
	@go test -race ./... || exit 1
	@echo "All quality gates passed!"

## dashboard-dev: Start dashboard development server
dashboard-dev:
	@echo "Starting dashboard development server..."
	cd $(ENTERPRISE_DIR)/dashboard && npm install && npm start

## dashboard-build: Build dashboard for production
dashboard-build:
	@echo "Building dashboard..."
	cd $(ENTERPRISE_DIR)/dashboard && npm install && npm run build

# Default target
.DEFAULT_GOAL := help

# Phony targets
.PHONY: help setup lint fmt test test-integration test-performance build docker-build docker-push docker-run local-dev local-stop local-logs deploy-k8s deploy-k8s-check deploy-k8s-logs docs security-scan benchmark-s3 coverage-report migrate-db clean version deps vendor pre-commit release watch profile-cpu profile-memory quality-gates dashboard-dev dashboard-build
