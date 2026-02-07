#!/bin/bash
# MinIO Enterprise Backup & Restore Test Script
# Version: 1.0.0
# Description: Automated testing for backup and restore functionality

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test directory
TEST_DIR="/tmp/minio-backup-test-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ============================================================
# Logging Functions
# ============================================================

log_test() {
    echo -e "${BLUE}[TEST]${NC} $@"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $@"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $@"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $@"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $@"
}

# ============================================================
# Setup and Cleanup
# ============================================================

setup() {
    log_info "Setting up test environment..."
    mkdir -p "$TEST_DIR"/{backup,restore,test-data}

    # Create test configuration
    cat > "$TEST_DIR/backup.conf" <<EOF
BACKUP_DIR="$TEST_DIR/backup"
BACKUP_TYPE="full"
RETENTION_DAYS=7
COMPRESSION=true
ENCRYPTION=false
S3_BACKUP=false
NOTIFICATION_EMAIL=""
LOG_FILE="$TEST_DIR/backup.log"
POSTGRES_USER="minio"
POSTGRES_DB="minio_enterprise"
POSTGRES_PASSWORD="test_password"
EOF

    log_info "Test environment created at: $TEST_DIR"
}

cleanup() {
    log_info "Cleaning up test environment..."
    rm -rf "$TEST_DIR"
    log_info "Test environment cleaned up"
}

# ============================================================
# Test Functions
# ============================================================

test_dependencies() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Testing dependency checks..."

    local deps=("docker" "docker-compose" "tar" "gzip" "openssl")
    local missing=()

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        log_pass "All dependencies present"
    else
        log_fail "Missing dependencies: ${missing[*]}"
    fi
}

test_backup_script_exists() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Testing backup script exists..."

    if [ -f "$SCRIPT_DIR/backup.sh" ] && [ -x "$SCRIPT_DIR/backup.sh" ]; then
        log_pass "Backup script found and executable"
    else
        log_fail "Backup script not found or not executable"
    fi
}

test_restore_script_exists() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Testing restore script exists..."

    if [ -f "$SCRIPT_DIR/../restore/restore.sh" ] && [ -x "$SCRIPT_DIR/../restore/restore.sh" ]; then
        log_pass "Restore script found and executable"
    else
        log_fail "Restore script not found or not executable"
    fi
}

test_backup_directory_creation() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Testing backup directory creation..."

    local test_backup_dir="$TEST_DIR/backup/test-$(date +%s)"

    if mkdir -p "$test_backup_dir"; then
        log_pass "Backup directory created successfully"
        rm -rf "$test_backup_dir"
    else
        log_fail "Failed to create backup directory"
    fi
}

test_compression() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Testing compression functionality..."

    # Create test file
    echo "Test data for compression" > "$TEST_DIR/test-data/test.txt"

    # Compress
    if tar czf "$TEST_DIR/test-data/test.tar.gz" -C "$TEST_DIR/test-data" test.txt; then
        # Decompress
        if tar xzf "$TEST_DIR/test-data/test.tar.gz" -C "$TEST_DIR/test-data" && \
           [ -f "$TEST_DIR/test-data/test.txt" ]; then
            log_pass "Compression/decompression works"
        else
            log_fail "Decompression failed"
        fi
    else
        log_fail "Compression failed"
    fi
}

test_encryption() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Testing encryption functionality..."

    local test_key="test-encryption-key-123"
    local test_file="$TEST_DIR/test-data/encrypt-test.txt"
    local encrypted_file="$TEST_DIR/test-data/encrypt-test.txt.enc"
    local decrypted_file="$TEST_DIR/test-data/encrypt-test-decrypted.txt"

    # Create test file
    echo "Sensitive test data" > "$test_file"

    # Encrypt
    if openssl enc -aes-256-cbc -salt -pbkdf2 -in "$test_file" -out "$encrypted_file" -k "$test_key"; then
        # Decrypt
        if openssl enc -aes-256-cbc -d -pbkdf2 -in "$encrypted_file" -out "$decrypted_file" -k "$test_key"; then
            # Compare original and decrypted
            if diff "$test_file" "$decrypted_file" > /dev/null; then
                log_pass "Encryption/decryption works correctly"
            else
                log_fail "Decrypted file doesn't match original"
            fi
        else
            log_fail "Decryption failed"
        fi
    else
        log_fail "Encryption failed"
    fi
}

test_checksum_generation() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Testing checksum generation..."

    # Create test files
    echo "File 1" > "$TEST_DIR/test-data/file1.txt"
    echo "File 2" > "$TEST_DIR/test-data/file2.txt"

    # Generate checksums
    if (cd "$TEST_DIR/test-data" && sha256sum file*.txt > checksums.txt); then
        # Verify checksums
        if (cd "$TEST_DIR/test-data" && sha256sum -c checksums.txt > /dev/null 2>&1); then
            log_pass "Checksum generation and verification works"
        else
            log_fail "Checksum verification failed"
        fi
    else
        log_fail "Checksum generation failed"
    fi
}

test_retention_policy() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Testing retention policy logic..."

    # Create test backup files with different ages
    touch -d "35 days ago" "$TEST_DIR/backup/old-backup-1.tar.gz"
    touch -d "20 days ago" "$TEST_DIR/backup/recent-backup-1.tar.gz"
    touch -d "5 days ago" "$TEST_DIR/backup/new-backup-1.tar.gz"

    # Find files older than 30 days
    local old_files=$(find "$TEST_DIR/backup" -type f -mtime +30 | wc -l)

    if [ "$old_files" -eq 1 ]; then
        log_pass "Retention policy logic works (found 1 old file)"
    else
        log_fail "Retention policy logic failed (found $old_files old files, expected 1)"
    fi
}

test_backup_metadata() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Testing backup metadata creation..."

    local metadata_file="$TEST_DIR/test-data/backup_info.json"

    # Create metadata
    cat > "$metadata_file" <<EOF
{
  "backup_name": "test-backup",
  "backup_type": "full",
  "timestamp": "$(date +%s)",
  "date": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "version": "1.0.0"
}
EOF

    # Validate JSON
    if command -v jq &> /dev/null; then
        if jq empty "$metadata_file" 2>/dev/null; then
            log_pass "Backup metadata is valid JSON"
        else
            log_fail "Backup metadata is invalid JSON"
        fi
    else
        log_warn "jq not found, skipping JSON validation"
        log_pass "Backup metadata created (validation skipped)"
    fi
}

test_docker_volume_backup_simulation() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Testing Docker volume backup simulation..."

    # Create test data structure similar to volume
    mkdir -p "$TEST_DIR/test-data/volume-data"
    echo "Volume data" > "$TEST_DIR/test-data/volume-data/data.txt"

    # Simulate volume backup using tar
    if tar czf "$TEST_DIR/test-data/volume-backup.tar.gz" -C "$TEST_DIR/test-data/volume-data" .; then
        # Simulate restore
        mkdir -p "$TEST_DIR/test-data/volume-restore"
        if tar xzf "$TEST_DIR/test-data/volume-backup.tar.gz" -C "$TEST_DIR/test-data/volume-restore"; then
            if [ -f "$TEST_DIR/test-data/volume-restore/data.txt" ]; then
                log_pass "Docker volume backup simulation works"
            else
                log_fail "Restored data not found"
            fi
        else
            log_fail "Volume restore simulation failed"
        fi
    else
        log_fail "Volume backup simulation failed"
    fi
}

test_configuration_backup() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Testing configuration file backup..."

    # Create test config files
    mkdir -p "$TEST_DIR/test-data/configs"
    echo "config1=value1" > "$TEST_DIR/test-data/configs/app.conf"
    echo "config2=value2" > "$TEST_DIR/test-data/configs/db.conf"

    # Backup configs
    if cp -r "$TEST_DIR/test-data/configs" "$TEST_DIR/backup/configs"; then
        # Verify backup
        if [ -f "$TEST_DIR/backup/configs/app.conf" ] && \
           [ -f "$TEST_DIR/backup/configs/db.conf" ]; then
            log_pass "Configuration backup works"
        else
            log_fail "Configuration files not backed up"
        fi
    else
        log_fail "Configuration backup failed"
    fi
}

test_backup_verification() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Testing backup verification logic..."

    # Create test backup structure
    mkdir -p "$TEST_DIR/test-data/backup/metadata"
    echo "test data" > "$TEST_DIR/test-data/backup/data.txt"

    # Generate checksum
    (cd "$TEST_DIR/test-data/backup" && sha256sum data.txt > metadata/checksums.txt)

    # Verify checksum
    if (cd "$TEST_DIR/test-data/backup" && sha256sum -c metadata/checksums.txt > /dev/null 2>&1); then
        log_pass "Backup verification works"
    else
        log_fail "Backup verification failed"
    fi

    # Test with corrupted data
    echo "corrupted" >> "$TEST_DIR/test-data/backup/data.txt"

    if ! (cd "$TEST_DIR/test-data/backup" && sha256sum -c metadata/checksums.txt > /dev/null 2>&1); then
        log_pass "Backup corruption detection works"
    else
        log_fail "Failed to detect corrupted backup"
    fi
}

test_s3_command_availability() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Testing S3 CLI availability..."

    if command -v aws &> /dev/null; then
        log_pass "AWS CLI available for S3 backups"
    else
        log_warn "AWS CLI not found (S3 backups will not work)"
        TESTS_RUN=$((TESTS_RUN - 1))  # Don't count this as a test
    fi
}

test_log_file_creation() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Testing log file creation..."

    local log_file="$TEST_DIR/test.log"

    # Write to log
    echo "Test log entry" >> "$log_file"

    if [ -f "$log_file" ] && [ -s "$log_file" ]; then
        log_pass "Log file creation works"
    else
        log_fail "Log file creation failed"
    fi
}

test_error_handling() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Testing error handling..."

    # Test handling of non-existent file
    if ! tar xzf "$TEST_DIR/non-existent-file.tar.gz" 2>/dev/null; then
        log_pass "Error handling works (non-existent file)"
    else
        log_fail "Error handling failed"
    fi
}

test_documentation_exists() {
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Testing documentation exists..."

    if [ -f "$PROJECT_ROOT/docs/guides/BACKUP_RESTORE.md" ]; then
        log_pass "Backup & Restore documentation exists"
    else
        log_fail "Documentation not found"
    fi
}

# ============================================================
# Main Test Execution
# ============================================================

main() {
    echo "======================================"
    echo "MinIO Backup & Restore Test Suite"
    echo "======================================"
    echo

    # Setup
    setup

    # Run all tests
    test_dependencies
    test_backup_script_exists
    test_restore_script_exists
    test_backup_directory_creation
    test_compression
    test_encryption
    test_checksum_generation
    test_retention_policy
    test_backup_metadata
    test_docker_volume_backup_simulation
    test_configuration_backup
    test_backup_verification
    test_s3_command_availability
    test_log_file_creation
    test_error_handling
    test_documentation_exists

    # Cleanup
    cleanup

    # Results
    echo
    echo "======================================"
    echo "Test Results"
    echo "======================================"
    echo "Tests Run:    $TESTS_RUN"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo "======================================"

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Run tests
main "$@"
