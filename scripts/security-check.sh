#!/bin/bash
# security-check.sh - Comprehensive security validation script

set -e

echo "========================================="
echo "MinIO Enterprise Security Check"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

FAILED=0

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
        FAILED=1
    fi
}

# 1. Check for hardcoded secrets
echo "1. Checking for hardcoded secrets..."
if grep -r "password.*=.*\"" . --include="*.go" --exclude-dir={vendor,.git,pkg} 2>/dev/null | grep -v "example\|test\|TODO"; then
    print_status 1 "Found potential hardcoded passwords"
else
    print_status 0 "No hardcoded secrets detected"
fi

# 2. Check file permissions
echo ""
echo "2. Checking file permissions..."
if find . -type f -name "*.sh" ! -perm 0755 2>/dev/null | grep -q .; then
    print_status 1 "Found shell scripts with incorrect permissions"
else
    print_status 0 "All shell scripts have correct permissions"
fi

# 3. Check for .env files in git
echo ""
echo "3. Checking for sensitive files in git..."
if git ls-files | grep -E "\.env$|id_rsa|\.pem$|\.key$" 2>/dev/null | grep -v "example\|\.pub"; then
    print_status 1 "Found sensitive files tracked in git"
else
    print_status 0 "No sensitive files in git"
fi

# 4. Check Docker security
echo ""
echo "4. Validating Docker configurations..."

if [ -f "deployments/docker/Dockerfile" ]; then
    # Check for non-root user
    if grep -q "USER minio" deployments/docker/Dockerfile; then
        print_status 0 "Dockerfile uses non-root user"
    else
        print_status 1 "Dockerfile may be running as root"
    fi

    # Check for security flags
    if grep -q "no-new-privileges" docker-compose.production.yml 2>/dev/null; then
        print_status 0 "Docker containers use security flags"
    else
        print_status 1 "Missing security flags in docker-compose"
    fi
else
    print_status 1 "deployments/docker/Dockerfile not found"
fi

# 5. Check for exposed ports
echo ""
echo "5. Checking for unnecessary exposed ports..."
if grep -r "0.0.0.0:" . --include="*.go" --include="*.yml" 2>/dev/null | grep -v "test\|example\|#"; then
    print_status 1 "Found services binding to 0.0.0.0"
else
    print_status 0 "No services binding to all interfaces"
fi

# 6. Validate configurations
echo ""
echo "6. Validating configuration files..."

if [ -f "prometheus.yml" ]; then
    if grep -q "static_configs" prometheus.yml; then
        print_status 0 "Prometheus configuration valid"
    else
        print_status 1 "Prometheus configuration incomplete"
    fi
fi

if [ -f "haproxy.cfg" ]; then
    if grep -q "http-server-close" haproxy.cfg; then
        print_status 0 "HAProxy configuration valid"
    else
        print_status 1 "HAProxy configuration incomplete"
    fi
fi

# 7. Check for TLS/SSL configuration
echo ""
echo "7. Checking TLS/SSL configuration..."
if grep -r "tls\|ssl\|https" . --include="*.go" --include="*.yml" 2>/dev/null | grep -v "test\|comment\|#" | head -1 > /dev/null; then
    print_status 0 "TLS/SSL configuration found"
else
    print_status 1 "No TLS/SSL configuration detected"
fi

# 8. Check dependency security
echo ""
echo "8. Checking Go module security..."
if [ -f "go.mod" ]; then
    print_status 0 "go.mod file exists"

    # Check for known vulnerable versions (examples)
    if grep -E "v0\.|v1\.0\.|v1\.1\." go.mod | grep -v "//"; then
        echo -e "${YELLOW}⚠${NC}  Warning: Some dependencies may be outdated"
    fi
else
    print_status 1 "go.mod file not found"
fi

# 9. Check for input validation
echo ""
echo "9. Checking for input validation..."
if grep -r "Sanitize\|Validate\|Clean" . --include="*.go" 2>/dev/null | head -1 > /dev/null; then
    print_status 0 "Input validation code found"
else
    print_status 1 "No explicit input validation found"
fi

# 10. Check resource limits
echo ""
echo "10. Checking resource limits..."
if grep -E "resources:|limits:|requests:" docker-compose.production.yml 2>/dev/null | head -1 > /dev/null; then
    print_status 0 "Resource limits configured in docker-compose"
else
    print_status 1 "No resource limits in docker-compose"
fi

# Summary
echo ""
echo "========================================="
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All security checks passed${NC}"
    exit 0
else
    echo -e "${RED}❌ Some security checks failed${NC}"
    echo "Please review the issues above"
    exit 1
fi
