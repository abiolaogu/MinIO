#!/bin/bash
# validate-configs.sh - Validate all configuration files

set -e

echo "========================================="
echo "Configuration Validation"
echo "========================================="
echo ""

FAILED=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
        FAILED=1
    fi
}

# 1. Validate Dockerfile
echo "1. Validating Dockerfile..."

if [ -f "deployments/docker/Dockerfile" ]; then
    if grep -q "FROM" deployments/docker/Dockerfile && grep -q "WORKDIR" deployments/docker/Dockerfile; then
        print_status 0 "deployments/docker/Dockerfile structure valid"
    else
        print_status 1 "deployments/docker/Dockerfile missing required instructions"
    fi

    if [ $(grep -c "^FROM" deployments/docker/Dockerfile) -gt 1 ]; then
        print_status 0 "Multi-stage build detected"
    fi

    if grep -q "HEALTHCHECK" deployments/docker/Dockerfile; then
        print_status 0 "Health check configured"
    fi
else
    print_status 1 "deployments/docker/Dockerfile not found"
fi

# 2. Validate environment file
echo ""
echo "2. Validating environment configuration..."

if [ -f "configs/.env.example" ]; then
    print_status 0 "configs/.env.example exists"
else
    print_status 1 "configs/.env.example not found"
fi

# 3. Validate HAProxy config
echo ""
echo "3. Validating HAProxy configuration..."

if [ -f "deployments/docker/haproxy.cfg" ]; then
    if grep -q "^global" deployments/docker/haproxy.cfg && grep -q "^defaults" deployments/docker/haproxy.cfg; then
        print_status 0 "HAProxy configuration valid"
    else
        print_status 1 "HAProxy configuration invalid"
    fi
else
    print_status 1 "deployments/docker/haproxy.cfg not found"
fi

# 4. Validate Prometheus config
echo ""
echo "4. Validating Prometheus configuration..."

if [ -f "deployments/docker/prometheus.yml" ]; then
    if grep -q "scrape_configs:" deployments/docker/prometheus.yml; then
        print_status 0 "Prometheus configuration valid"
    else
        print_status 1 "Prometheus configuration invalid"
    fi
else
    print_status 1 "deployments/docker/prometheus.yml not found"
fi

# 5. Validate Go module
echo ""
echo "5. Validating Go module..."

if [ -f "go.mod" ]; then
    if grep -q "^module" go.mod; then
        print_status 0 "go.mod valid"
    else
        print_status 1 "go.mod invalid"
    fi
else
    print_status 1 "go.mod not found"
fi

# 6. Validate documentation
echo ""
echo "6. Validating documentation..."

for doc in README.md PERFORMANCE.md DEPLOYMENT.md; do
    if [ -f "$doc" ] && [ -s "$doc" ]; then
        print_status 0 "$doc exists"
    else
        print_status 1 "$doc missing or empty"
    fi
done

# 7. Validate test files
echo ""
echo "7. Validating test coverage..."

if [ -f "main_test.go" ]; then
    print_status 0 "Test files found"
else
    print_status 1 "No test files"
fi

# 8. Validate directory structure
echo ""
echo "8. Validating directory structure..."

for dir in cmd pkg scripts; do
    if [ -d "$dir" ]; then
        print_status 0 "$dir/ exists"
    else
        print_status 1 "$dir/ missing"
    fi
done

# Summary
echo ""
echo "========================================="
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All configurations valid${NC}"
    exit 0
else
    echo -e "${RED}❌ Some validations failed${NC}"
    exit 1
fi
