# Repository Structure

This document explains the organization of the MinIO Enterprise repository following Go and Docker best practices.

## Directory Layout

```
MinIO/
├── cmd/                    # Main applications
│   └── server/            # Server entry point (main.go)
├── internal/              # Private application code (not importable by external projects)
│   ├── cache/            # Cache engine implementations (V1 & V2)
│   ├── replication/      # Replication engine
│   ├── tenant/           # Multi-tenancy management
│   └── monitoring/       # Observability and metrics
├── api/                   # API definitions (OpenAPI/Swagger specs)
├── configs/              # Configuration file templates
│   └── .env.example      # Environment variable template
├── deployments/          # Deployment configurations
│   ├── docker/          # Docker & docker-compose files
│   │   ├── Dockerfile
│   │   ├── docker-compose.yml
│   │   ├── haproxy.cfg
│   │   └── prometheus.yml
│   └── kubernetes/      # Kubernetes manifests
├── docs/                 # Documentation
│   ├── guides/          # User guides (PERFORMANCE.md, DEPLOYMENT.md)
│   ├── api/             # API documentation
│   ├── TEST_REPORT.md
│   └── TASK_COMPLETE.md
├── scripts/             # Build, install, and analysis scripts
│   ├── security-check.sh
│   └── validate-configs.sh
├── test/                # Test files
│   ├── test_suite.go
│   └── performance_test.go
├── build/               # CI/CD and build configurations
│   ├── ci/
│   │   └── ci.yml       # GitHub Actions workflow
│   └── .golangci.yml    # Linter configuration
├── bin/                 # Build output directory (gitignored)
├── .gitignore           # Git ignore rules
├── go.mod               # Go module definition
├── LICENSE              # Apache 2.0 license
├── Makefile             # Build automation
├── README.md            # Project overview
└── STRUCTURE.md         # This file
```

## Design Principles

### 1. `/cmd` - Main Applications
Contains the main applications for this project. The directory name for each application should match the name of the executable you want to have.

**Example**: `cmd/server/main.go` → builds to `bin/minio-enterprise`

### 2. `/internal` - Private Code
Application and library code that should not be imported by other applications. This layout pattern is enforced by the Go compiler itself.

**Why**: Prevents external dependencies on internal implementations, allowing for breaking changes without affecting external users.

### 3. `/api` - API Definitions
OpenAPI/Swagger specs, JSON schema files, protocol definition files.

**Why**: Centralizes API contracts, making them easy to version and share.

### 4. `/configs` - Configuration Templates
Configuration file templates or default configs. Do not commit actual configuration files with secrets.

**Example**: `.env.example` (template), `.env` (actual, gitignored)

### 5. `/deployments` - Deployment Configurations
System and container orchestration deployment configurations and templates.

**Subdirectories**:
- `docker/` - Dockerfiles and docker-compose files
- `kubernetes/` - K8s manifests, Helm charts

### 6. `/docs` - Documentation
Design and user documents (in addition to godoc generated documentation).

**Structure**:
- `guides/` - User guides and tutorials
- `api/` - API documentation
- Root-level reports and summaries

### 7. `/scripts` - Build and Utility Scripts
Scripts to perform various build, install, analysis, etc operations.

**Examples**: `security-check.sh`, `validate-configs.sh`

### 8. `/test` - Test Applications and Data
Additional external test apps and test data. Feel free to structure the `/test` directory anyway you want.

**Why**: Separates test code from production code while keeping it accessible.

### 9. `/build` - CI/CD and Build Configs
Build configuration files (CI/CD, linters, etc.).

**Examples**:
- `ci/` - GitHub Actions, GitLab CI configs
- `.golangci.yml` - Linter configuration

## File Naming Conventions

### Go Files
- `*_v1.go` - Version 1 implementations
- `*_v2.go` - Version 2 implementations
- `*_test.go` - Test files (automatically excluded from builds)

### Configuration Files
- `*.example` - Templates (committed to git)
- Actual configs without `.example` - Gitignored

### Docker Files
- `Dockerfile` - Production Dockerfile
- `Dockerfile.dev` - Development Dockerfile
- `docker-compose.yml` - Production compose
- `docker-compose.override.yml` - Local overrides (gitignored)

## Package Organization

### Internal Package Structure
```
internal/
├── cache/
│   ├── cache_engine_v1.go    # Original implementation
│   └── cache_engine_v2.go    # Optimized implementation
├── replication/
│   ├── replication_engine_v1.go
│   └── replication_engine_v2.go
├── tenant/
│   ├── tenantmanager_v1.go
│   └── tenantmanager_v2.go
└── monitoring/
    └── monitoring.go
```

Each package is self-contained with minimal external dependencies.

## Build Artifacts

Generated files go in `bin/` or root (gitignored):
- `bin/` - Compiled binaries
- `coverage.out` - Test coverage data
- `coverage.html` - Coverage reports
- `*.prof` - Profiling data

## Best Practices Followed

1. **Separation of Concerns**: Clear boundaries between packages
2. **Private by Default**: Use `/internal` for implementation details
3. **Explicit Public API**: Only expose what's necessary
4. **Testability**: Test files alongside source
5. **Documentation**: Comprehensive docs in `/docs`
6. **Build Automation**: Makefile for common tasks
7. **CI/CD Ready**: GitHub Actions workflow configured
8. **Security**: No secrets in git, templates only

## References

- [Standard Go Project Layout](https://github.com/golang-standards/project-layout)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [12-Factor App](https://12factor.net/)

