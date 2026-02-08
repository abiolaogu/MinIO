#!/bin/bash
################################################################################
# MinIO Enterprise - Backup & Restore Test Script
################################################################################
# Description: Automated test suite for backup and restore functionality
# Tests: Backup creation, compression, encryption, restore, verification
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Test configuration
TEST_BACKUP_DIR="/tmp/minio-backup-test-$(date +%s)"
TEST_ENCRYPTION_KEY="test-encryption-key-12345"
RESULTS_FILE="${SCRIPT_DIR}/test-results.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

################################################################################
# Test framework functions
################################################################################

log_test() {
    echo -e "${BLUE}[TEST]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    ((TESTS_FAILED++))
}

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $*"
}

start_test() {
    ((TESTS_TOTAL++))
    log_test "Test $TESTS_TOTAL: $*"
}

################################################################################
# Setup and teardown
################################################################################

setup_test_environment() {
    log_info "Setting up test environment..."

    # Create test backup directory
    mkdir -p "$TEST_BACKUP_DIR"

    # Ensure Docker services are running
    if ! docker ps > /dev/null 2>&1; then
        log_fail "Docker is not running"
        exit 1
    fi

    log_info "Test environment ready"
}

teardown_test_environment() {
    log_info "Cleaning up test environment..."

    # Remove test backup directory
    if [[ -d "$TEST_BACKUP_DIR" ]]; then
        rm -rf "$TEST_BACKUP_DIR"
    fi

    log_info "Cleanup complete"
}

################################################################################
# Test cases
################################################################################

test_backup_script_exists() {
    start_test "Backup script exists and is executable"

    if [[ -f "${SCRIPT_DIR}/backup.sh" ]]; then
        log_pass "Backup script found"
    else
        log_fail "Backup script not found"
        return 1
    fi

    if [[ -x "${SCRIPT_DIR}/backup.sh" ]]; then
        log_pass "Backup script is executable"
    else
        log_fail "Backup script is not executable"
        chmod +x "${SCRIPT_DIR}/backup.sh"
    fi
}

test_restore_script_exists() {
    start_test "Restore script exists and is executable"

    if [[ -f "${SCRIPT_DIR}/../restore/restore.sh" ]]; then
        log_pass "Restore script found"
    else
        log_fail "Restore script not found"
        return 1
    fi

    if [[ -x "${SCRIPT_DIR}/../restore/restore.sh" ]]; then
        log_pass "Restore script is executable"
    else
        log_fail "Restore script is not executable"
        chmod +x "${SCRIPT_DIR}/../restore/restore.sh"
    fi
}

test_backup_dependencies() {
    start_test "Required dependencies are installed"

    local deps=("docker" "tar" "gzip" "jq")
    local missing=()

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_pass "All dependencies installed"
    else
        log_fail "Missing dependencies: ${missing[*]}"
        return 1
    fi
}

test_docker_services_running() {
    start_test "Docker services are running"

    local required_services=("minio" "postgres" "redis")
    local missing=()

    for service in "${required_services[@]}"; do
        if ! docker ps --format '{{.Names}}' | grep -q "$service"; then
            missing+=("$service")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_pass "All required services running"
    else
        log_fail "Services not running: ${missing[*]}"
        log_info "Start services with: docker-compose -f deployments/docker/docker-compose.yml up -d"
        return 1
    fi
}

test_full_backup() {
    start_test "Full backup creation"

    export BACKUP_DIR="$TEST_BACKUP_DIR"
    export BACKUP_TYPE="full"
    export COMPRESS=false
    export ENCRYPT=false
    export S3_BACKUP=false
    export RETENTION_DAYS=1

    if "${SCRIPT_DIR}/backup.sh" > "${TEST_BACKUP_DIR}/backup-test.log" 2>&1; then
        log_pass "Full backup completed successfully"

        # Check if backup was created
        local backup_count=$(find "$TEST_BACKUP_DIR" -type d -name "minio-backup-full-*" | wc -l)
        if [[ $backup_count -gt 0 ]]; then
            log_pass "Backup directory created"
        else
            log_fail "Backup directory not found"
            return 1
        fi
    else
        log_fail "Full backup failed"
        cat "${TEST_BACKUP_DIR}/backup-test.log"
        return 1
    fi
}

test_compressed_backup() {
    start_test "Compressed backup creation"

    export BACKUP_DIR="$TEST_BACKUP_DIR"
    export BACKUP_TYPE="full"
    export COMPRESS=true
    export ENCRYPT=false
    export S3_BACKUP=false

    if "${SCRIPT_DIR}/backup.sh" > "${TEST_BACKUP_DIR}/compressed-test.log" 2>&1; then
        log_pass "Compressed backup completed"

        # Check if compressed file was created
        local compressed_count=$(find "$TEST_BACKUP_DIR" -type f -name "*.tar.gz" | wc -l)
        if [[ $compressed_count -gt 0 ]]; then
            log_pass "Compressed backup file created"

            # Verify it's a valid tar.gz
            local backup_file=$(find "$TEST_BACKUP_DIR" -type f -name "*.tar.gz" | head -n1)
            if tar -tzf "$backup_file" > /dev/null 2>&1; then
                log_pass "Compressed backup is valid"
            else
                log_fail "Compressed backup is corrupted"
                return 1
            fi
        else
            log_fail "Compressed backup file not found"
            return 1
        fi
    else
        log_fail "Compressed backup failed"
        return 1
    fi
}

test_encrypted_backup() {
    start_test "Encrypted backup creation"

    export BACKUP_DIR="$TEST_BACKUP_DIR"
    export BACKUP_TYPE="full"
    export COMPRESS=true
    export ENCRYPT=true
    export ENCRYPTION_KEY="$TEST_ENCRYPTION_KEY"
    export S3_BACKUP=false

    if "${SCRIPT_DIR}/backup.sh" > "${TEST_BACKUP_DIR}/encrypted-test.log" 2>&1; then
        log_pass "Encrypted backup completed"

        # Check if encrypted file was created
        local encrypted_count=$(find "$TEST_BACKUP_DIR" -type f -name "*.enc" | wc -l)
        if [[ $encrypted_count -gt 0 ]]; then
            log_pass "Encrypted backup file created"
        else
            log_fail "Encrypted backup file not found"
            return 1
        fi
    else
        log_fail "Encrypted backup failed"
        return 1
    fi
}

test_backup_metadata() {
    start_test "Backup metadata creation"

    # Find the most recent uncompressed backup
    local backup_dir=$(find "$TEST_BACKUP_DIR" -type d -name "minio-backup-*" | head -n1)

    if [[ -z "$backup_dir" ]]; then
        # Extract a compressed backup for testing
        local compressed_backup=$(find "$TEST_BACKUP_DIR" -type f -name "minio-backup-*.tar.gz" ! -name "*.enc" | head -n1)
        if [[ -n "$compressed_backup" ]]; then
            mkdir -p "${TEST_BACKUP_DIR}/extracted"
            tar -xzf "$compressed_backup" -C "${TEST_BACKUP_DIR}/extracted"
            backup_dir=$(find "${TEST_BACKUP_DIR}/extracted" -type d -name "minio-backup-*" | head -n1)
        fi
    fi

    if [[ -z "$backup_dir" ]]; then
        log_fail "No backup directory found for metadata test"
        return 1
    fi

    # Check for metadata file
    if [[ -f "${backup_dir}/metadata/backup-info.json" ]]; then
        log_pass "Metadata file exists"

        # Validate JSON
        if jq empty "${backup_dir}/metadata/backup-info.json" 2>/dev/null; then
            log_pass "Metadata is valid JSON"

            # Check required fields
            local required_fields=("backup_name" "backup_type" "timestamp" "components")
            local missing_fields=()

            for field in "${required_fields[@]}"; do
                if ! jq -e ".$field" "${backup_dir}/metadata/backup-info.json" > /dev/null 2>&1; then
                    missing_fields+=("$field")
                fi
            done

            if [[ ${#missing_fields[@]} -eq 0 ]]; then
                log_pass "All required metadata fields present"
            else
                log_fail "Missing metadata fields: ${missing_fields[*]}"
                return 1
            fi
        else
            log_fail "Metadata is not valid JSON"
            return 1
        fi
    else
        log_fail "Metadata file not found"
        return 1
    fi
}

test_backup_components() {
    start_test "Backup includes all components"

    # Find backup directory
    local backup_dir=$(find "${TEST_BACKUP_DIR}/extracted" -type d -name "minio-backup-*" | head -n1)

    if [[ -z "$backup_dir" ]]; then
        log_fail "No backup directory found"
        return 1
    fi

    local required_dirs=("minio" "postgres" "redis" "configs" "metadata")
    local missing_dirs=()

    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "${backup_dir}/${dir}" ]]; then
            missing_dirs+=("$dir")
        fi
    done

    if [[ ${#missing_dirs[@]} -eq 0 ]]; then
        log_pass "All backup components present"
    else
        log_fail "Missing backup components: ${missing_dirs[*]}"
        return 1
    fi
}

test_backup_verification() {
    start_test "Backup verification"

    # Find latest compressed backup
    local backup_file=$(find "$TEST_BACKUP_DIR" -type f -name "minio-backup-*.tar.gz" ! -name "*.enc" | head -n1)

    if [[ -z "$backup_file" ]]; then
        log_fail "No backup file found for verification"
        return 1
    fi

    # Use restore script in verify-only mode
    if RESTORE_MODE=verify-only SKIP_VERIFICATION=true \
       "${SCRIPT_DIR}/../restore/restore.sh" "$backup_file" > "${TEST_BACKUP_DIR}/verify-test.log" 2>&1; then
        log_pass "Backup verification succeeded"
    else
        log_fail "Backup verification failed"
        cat "${TEST_BACKUP_DIR}/verify-test.log"
        return 1
    fi
}

test_encrypted_backup_decryption() {
    start_test "Encrypted backup decryption"

    # Find encrypted backup
    local encrypted_backup=$(find "$TEST_BACKUP_DIR" -type f -name "*.enc" | head -n1)

    if [[ -z "$encrypted_backup" ]]; then
        log_fail "No encrypted backup found"
        return 1
    fi

    # Test decryption with correct key
    local decrypted_file="${TEST_BACKUP_DIR}/decrypted-test.tar.gz"
    if openssl enc -aes-256-cbc -d -in "$encrypted_backup" -out "$decrypted_file" -k "$TEST_ENCRYPTION_KEY" 2>/dev/null; then
        log_pass "Decryption with correct key succeeded"

        # Verify decrypted file is valid
        if tar -tzf "$decrypted_file" > /dev/null 2>&1; then
            log_pass "Decrypted file is valid"
        else
            log_fail "Decrypted file is corrupted"
            return 1
        fi
    else
        log_fail "Decryption failed"
        return 1
    fi

    # Test decryption with wrong key
    local wrong_key_file="${TEST_BACKUP_DIR}/wrong-key-test.tar.gz"
    if openssl enc -aes-256-cbc -d -in "$encrypted_backup" -out "$wrong_key_file" -k "wrong-key" 2>/dev/null; then
        log_fail "Decryption with wrong key should have failed"
        return 1
    else
        log_pass "Decryption with wrong key correctly failed"
    fi
}

test_backup_retention() {
    start_test "Backup retention policy"

    # Create old backup file for testing
    local old_backup="${TEST_BACKUP_DIR}/minio-backup-full-old.tar.gz"
    touch "$old_backup"
    touch -t 202301010000 "$old_backup"  # Set to 2023-01-01

    # Run backup with short retention
    export BACKUP_DIR="$TEST_BACKUP_DIR"
    export RETENTION_DAYS=1
    export COMPRESS=true
    export ENCRYPT=false

    "${SCRIPT_DIR}/backup.sh" > "${TEST_BACKUP_DIR}/retention-test.log" 2>&1 || true

    # Check if old backup was removed
    if [[ ! -f "$old_backup" ]]; then
        log_pass "Old backup cleaned up by retention policy"
    else
        log_fail "Old backup not removed"
        return 1
    fi
}

################################################################################
# Performance tests
################################################################################

test_backup_performance() {
    start_test "Backup performance benchmarking"

    export BACKUP_DIR="$TEST_BACKUP_DIR"
    export BACKUP_TYPE="full"
    export COMPRESS=true
    export ENCRYPT=false

    local start_time=$(date +%s)

    if "${SCRIPT_DIR}/backup.sh" > "${TEST_BACKUP_DIR}/perf-test.log" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log_pass "Backup completed in ${duration} seconds"

        # Calculate backup size
        local backup_file=$(find "$TEST_BACKUP_DIR" -type f -name "*.tar.gz" ! -name "*.enc" -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2)
        local backup_size=$(du -h "$backup_file" | cut -f1)

        log_info "Backup size: ${backup_size}"
        log_info "Performance: ${backup_size} in ${duration}s"

        # Warning if backup takes too long
        if [[ $duration -gt 300 ]]; then
            log_fail "Backup took longer than 5 minutes"
            return 1
        fi
    else
        log_fail "Performance test failed"
        return 1
    fi
}

################################################################################
# Main test suite
################################################################################

run_test_suite() {
    echo "========================================"
    echo "MinIO Enterprise Backup & Restore Tests"
    echo "========================================"
    echo ""

    setup_test_environment

    # Run all tests
    test_backup_script_exists || true
    test_restore_script_exists || true
    test_backup_dependencies || true
    test_docker_services_running || true

    # Only run backup tests if services are running
    if docker ps --format '{{.Names}}' | grep -q "minio"; then
        test_full_backup || true
        test_compressed_backup || true
        test_encrypted_backup || true
        test_backup_metadata || true
        test_backup_components || true
        test_backup_verification || true
        test_encrypted_backup_decryption || true
        test_backup_retention || true
        test_backup_performance || true
    else
        log_info "Skipping backup tests (services not running)"
    fi

    teardown_test_environment

    # Print results
    echo ""
    echo "========================================"
    echo "Test Results"
    echo "========================================"
    echo "Total Tests:  $TESTS_TOTAL"
    echo "Passed:       $TESTS_PASSED"
    echo "Failed:       $TESTS_FAILED"
    echo "========================================"

    # Save results to file
    cat > "$RESULTS_FILE" <<EOF
MinIO Enterprise Backup & Restore Test Results
Date: $(date)
Total Tests: $TESTS_TOTAL
Passed: $TESTS_PASSED
Failed: $TESTS_FAILED
Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%
EOF

    # Exit with failure if any tests failed
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    else
        echo ""
        log_pass "All tests passed!"
        exit 0
    fi
}

# Make scripts executable
chmod +x "${SCRIPT_DIR}/backup.sh" 2>/dev/null || true
chmod +x "${SCRIPT_DIR}/../restore/restore.sh" 2>/dev/null || true

# Run test suite
run_test_suite
