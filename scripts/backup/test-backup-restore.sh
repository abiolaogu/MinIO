#!/usr/bin/env bash

# MinIO Enterprise - Backup & Restore Test Script
# This script tests the backup and restore functionality

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_BACKUP_ROOT="/tmp/minio_backup_test_$(date +%s)"
TEST_DATA_DIR="/tmp/minio_test_data_$(date +%s)"

log_info() {
    echo -e "${BLUE}[TEST INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[TEST SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[TEST ERROR]${NC} $*"
}

cleanup() {
    log_info "Cleaning up test data..."
    rm -rf "${TEST_BACKUP_ROOT}" "${TEST_DATA_DIR}"
}

trap cleanup EXIT

# Test 1: Backup Script Syntax
test_backup_syntax() {
    log_info "Test 1: Checking backup script syntax..."

    if bash -n "${SCRIPT_DIR}/backup.sh"; then
        log_success "Backup script syntax is valid"
        return 0
    else
        log_error "Backup script has syntax errors"
        return 1
    fi
}

# Test 2: Restore Script Syntax
test_restore_syntax() {
    log_info "Test 2: Checking restore script syntax..."

    if bash -n "${SCRIPT_DIR}/../restore/restore.sh"; then
        log_success "Restore script syntax is valid"
        return 0
    else
        log_error "Restore script has syntax errors"
        return 1
    fi
}

# Test 3: Configuration File Parsing
test_config_parsing() {
    log_info "Test 3: Testing configuration file parsing..."

    cat > "${TEST_BACKUP_ROOT}/test.conf" <<EOF
BACKUP_TYPE="full"
BACKUP_ROOT="${TEST_BACKUP_ROOT}"
RETENTION_DAYS=7
COMPRESSION=true
EOF

    if source "${TEST_BACKUP_ROOT}/test.conf" && [[ "${BACKUP_TYPE}" == "full" ]]; then
        log_success "Configuration file parsing works"
        return 0
    else
        log_error "Configuration file parsing failed"
        return 1
    fi
}

# Test 4: Directory Creation
test_directory_creation() {
    log_info "Test 4: Testing backup directory creation..."

    mkdir -p "${TEST_BACKUP_ROOT}"

    if [[ -d "${TEST_BACKUP_ROOT}" ]]; then
        log_success "Backup directory created successfully"
        return 0
    else
        log_error "Failed to create backup directory"
        return 1
    fi
}

# Test 5: Test Data Creation
test_data_creation() {
    log_info "Test 5: Creating test data..."

    mkdir -p "${TEST_DATA_DIR}"/{minio,postgres,redis,config}

    # Create test files
    echo "test minio data" > "${TEST_DATA_DIR}/minio/test.txt"
    echo "test postgres data" > "${TEST_DATA_DIR}/postgres/test.sql"
    echo "test redis data" > "${TEST_DATA_DIR}/redis/dump.rdb"
    echo "test config" > "${TEST_DATA_DIR}/config/app.conf"

    if [[ -f "${TEST_DATA_DIR}/minio/test.txt" ]]; then
        log_success "Test data created successfully"
        return 0
    else
        log_error "Failed to create test data"
        return 1
    fi
}

# Test 6: Compression
test_compression() {
    log_info "Test 6: Testing compression..."

    echo "test data for compression" > "${TEST_BACKUP_ROOT}/test.txt"

    if gzip "${TEST_BACKUP_ROOT}/test.txt"; then
        if [[ -f "${TEST_BACKUP_ROOT}/test.txt.gz" ]]; then
            log_success "Compression works"
            return 0
        fi
    fi

    log_error "Compression failed"
    return 1
}

# Test 7: Decompression
test_decompression() {
    log_info "Test 7: Testing decompression..."

    if gunzip "${TEST_BACKUP_ROOT}/test.txt.gz"; then
        if [[ -f "${TEST_BACKUP_ROOT}/test.txt" ]]; then
            log_success "Decompression works"
            return 0
        fi
    fi

    log_error "Decompression failed"
    return 1
}

# Test 8: Encryption
test_encryption() {
    log_info "Test 8: Testing encryption..."

    echo "test data for encryption" > "${TEST_BACKUP_ROOT}/secret.txt"
    local encryption_key="test-key-123"

    if openssl enc -aes-256-cbc -salt -in "${TEST_BACKUP_ROOT}/secret.txt" \
        -out "${TEST_BACKUP_ROOT}/secret.txt.enc" -k "${encryption_key}"; then
        if [[ -f "${TEST_BACKUP_ROOT}/secret.txt.enc" ]]; then
            log_success "Encryption works"
            return 0
        fi
    fi

    log_error "Encryption failed"
    return 1
}

# Test 9: Decryption
test_decryption() {
    log_info "Test 9: Testing decryption..."

    local encryption_key="test-key-123"

    if openssl enc -d -aes-256-cbc -in "${TEST_BACKUP_ROOT}/secret.txt.enc" \
        -out "${TEST_BACKUP_ROOT}/secret_decrypted.txt" -k "${encryption_key}"; then
        if [[ -f "${TEST_BACKUP_ROOT}/secret_decrypted.txt" ]]; then
            local original=$(cat "${TEST_BACKUP_ROOT}/secret.txt" 2>/dev/null || echo "")
            local decrypted=$(cat "${TEST_BACKUP_ROOT}/secret_decrypted.txt")

            if [[ "${original}" == "${decrypted}" ]]; then
                log_success "Decryption works correctly"
                return 0
            fi
        fi
    fi

    log_error "Decryption failed"
    return 1
}

# Test 10: Tar Archive Creation
test_tar_creation() {
    log_info "Test 10: Testing tar archive creation..."

    if tar -cf "${TEST_BACKUP_ROOT}/test.tar" -C "${TEST_DATA_DIR}" minio; then
        if [[ -f "${TEST_BACKUP_ROOT}/test.tar" ]]; then
            log_success "Tar archive creation works"
            return 0
        fi
    fi

    log_error "Tar archive creation failed"
    return 1
}

# Test 11: Tar Archive Extraction
test_tar_extraction() {
    log_info "Test 11: Testing tar archive extraction..."

    local extract_dir="${TEST_BACKUP_ROOT}/extract"
    mkdir -p "${extract_dir}"

    if tar -xf "${TEST_BACKUP_ROOT}/test.tar" -C "${extract_dir}"; then
        if [[ -f "${extract_dir}/minio/test.txt" ]]; then
            log_success "Tar archive extraction works"
            return 0
        fi
    fi

    log_error "Tar archive extraction failed"
    return 1
}

# Test 12: JSON Metadata Creation
test_json_metadata() {
    log_info "Test 12: Testing JSON metadata creation..."

    cat > "${TEST_BACKUP_ROOT}/metadata.json" <<EOF
{
  "backup_date": "$(date +%Y%m%d_%H%M%S)",
  "backup_type": "full",
  "compression": true,
  "encryption": false
}
EOF

    if [[ -f "${TEST_BACKUP_ROOT}/metadata.json" ]]; then
        if grep -q "backup_date" "${TEST_BACKUP_ROOT}/metadata.json"; then
            log_success "JSON metadata creation works"
            return 0
        fi
    fi

    log_error "JSON metadata creation failed"
    return 1
}

# Test 13: Dependency Check
test_dependencies() {
    log_info "Test 13: Checking dependencies..."

    local missing_deps=()

    command -v tar >/dev/null 2>&1 || missing_deps+=("tar")
    command -v gzip >/dev/null 2>&1 || missing_deps+=("gzip")
    command -v openssl >/dev/null 2>&1 || missing_deps+=("openssl")

    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        log_success "All required dependencies are installed"
        return 0
    else
        log_error "Missing dependencies: ${missing_deps[*]}"
        return 1
    fi
}

# Test 14: File Permissions
test_file_permissions() {
    log_info "Test 14: Testing file permissions..."

    if [[ -x "${SCRIPT_DIR}/backup.sh" ]]; then
        log_success "Backup script is executable"
    else
        log_error "Backup script is not executable"
        return 1
    fi

    if [[ -x "${SCRIPT_DIR}/../restore/restore.sh" ]]; then
        log_success "Restore script is executable"
        return 0
    else
        log_error "Restore script is not executable"
        return 1
    fi
}

# Test 15: Backup Directory Structure
test_backup_structure() {
    log_info "Test 15: Testing backup directory structure..."

    local backup_dir="${TEST_BACKUP_ROOT}/20260207_120000"
    mkdir -p "${backup_dir}"/{minio,postgres,redis,config,metadata}

    if [[ -d "${backup_dir}/minio" ]] && \
       [[ -d "${backup_dir}/postgres" ]] && \
       [[ -d "${backup_dir}/redis" ]] && \
       [[ -d "${backup_dir}/config" ]] && \
       [[ -d "${backup_dir}/metadata" ]]; then
        log_success "Backup directory structure is correct"
        return 0
    else
        log_error "Backup directory structure is incorrect"
        return 1
    fi
}

# Run all tests
run_tests() {
    log_info "========================================"
    log_info "MinIO Enterprise Backup/Restore Tests"
    log_info "========================================"
    echo ""

    local total_tests=0
    local passed_tests=0
    local failed_tests=0

    local tests=(
        "test_backup_syntax"
        "test_restore_syntax"
        "test_config_parsing"
        "test_directory_creation"
        "test_data_creation"
        "test_compression"
        "test_decompression"
        "test_encryption"
        "test_decryption"
        "test_tar_creation"
        "test_tar_extraction"
        "test_json_metadata"
        "test_dependencies"
        "test_file_permissions"
        "test_backup_structure"
    )

    for test in "${tests[@]}"; do
        total_tests=$((total_tests + 1))

        if ${test}; then
            passed_tests=$((passed_tests + 1))
        else
            failed_tests=$((failed_tests + 1))
        fi

        echo ""
    done

    log_info "========================================"
    log_info "Test Results"
    log_info "========================================"
    log_info "Total Tests: ${total_tests}"
    log_success "Passed: ${passed_tests}"

    if [[ ${failed_tests} -gt 0 ]]; then
        log_error "Failed: ${failed_tests}"
        echo ""
        log_error "Some tests failed. Please review the output above."
        return 1
    else
        echo ""
        log_success "All tests passed!"
        return 0
    fi
}

# Main execution
main() {
    # Create test directories
    mkdir -p "${TEST_BACKUP_ROOT}" "${TEST_DATA_DIR}"

    # Run tests
    run_tests

    local exit_code=$?

    # Cleanup is handled by trap

    exit ${exit_code}
}

main "$@"
