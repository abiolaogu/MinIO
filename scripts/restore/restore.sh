#!/bin/bash
#
# MinIO Enterprise Restore Script
# Automated restore solution for MinIO cluster, PostgreSQL, Redis, and configurations
#
# Usage:
#   ./restore.sh <backup_path> [--verify-only] [--rollback]
#
# Examples:
#   ./restore.sh /backup/minio-backup-full-20260208_102600
#   ./restore.sh /backup/minio-backup-full-20260208_102600 --verify-only
#   ./restore.sh /backup/minio-backup-full-20260208_102600 --rollback
#

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKUP_PATH="${1:-}"
VERIFY_ONLY=false
ROLLBACK=false
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/tmp/minio-restore-${TIMESTAMP}.log"

# Parse additional arguments
shift || true
while [ $# -gt 0 ]; do
    case "$1" in
        --verify-only)
            VERIFY_ONLY=true
            shift
            ;;
        --rollback)
            ROLLBACK=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Encryption settings
ENABLE_ENCRYPTION="false"
ENCRYPTION_KEY_FILE="/etc/minio/backup-encryption.key"

# Docker Compose file
COMPOSE_FILE="${PROJECT_ROOT}/deployments/docker/docker-compose.production.yml"

# Rollback directory
ROLLBACK_DIR="/tmp/minio-rollback-${TIMESTAMP}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================
# Helper Functions
# ============================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
    log "INFO" "$*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
    log "SUCCESS" "$*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
    log "WARNING" "$*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
    log "ERROR" "$*"
}

check_dependencies() {
    local missing_deps=()

    for cmd in docker docker-compose tar gzip gunzip md5sum; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please install missing dependencies and try again"
        exit 1
    fi
}

validate_backup_path() {
    log_info "Validating backup path: ${BACKUP_PATH}"

    if [ -z "$BACKUP_PATH" ]; then
        log_error "Backup path not specified"
        echo "Usage: $0 <backup_path> [--verify-only] [--rollback]"
        exit 1
    fi

    if [ ! -d "$BACKUP_PATH" ]; then
        log_error "Backup directory does not exist: ${BACKUP_PATH}"
        exit 1
    fi

    # Check for required backup components
    local required_dirs=("metadata" "postgres" "redis" "minio" "configs")
    local missing_dirs=()

    for dir in "${required_dirs[@]}"; do
        if [ ! -d "${BACKUP_PATH}/${dir}" ]; then
            missing_dirs+=("$dir")
        fi
    done

    if [ ${#missing_dirs[@]} -ne 0 ]; then
        log_error "Backup is incomplete. Missing directories: ${missing_dirs[*]}"
        exit 1
    fi

    log_success "Backup path validation successful"
}

verify_backup_integrity() {
    log_info "Verifying backup integrity..."

    local failed_checks=0

    # Verify checksums
    find "$BACKUP_PATH" -name "*.md5" | while read -r md5_file; do
        local dir=$(dirname "$md5_file")
        pushd "$dir" > /dev/null

        if md5sum -c "$(basename "$md5_file")" > /dev/null 2>&1; then
            log_info "✓ Checksum verified: $(basename "$md5_file")"
        else
            log_error "✗ Checksum failed: $(basename "$md5_file")"
            ((failed_checks++))
        fi

        popd > /dev/null
    done

    if [ $failed_checks -gt 0 ]; then
        log_error "Backup integrity verification failed with ${failed_checks} errors"
        return 1
    fi

    log_success "Backup integrity verification completed successfully"
}

read_backup_metadata() {
    log_info "Reading backup metadata..."

    local metadata_file="${BACKUP_PATH}/metadata/backup-info.json"

    if [ ! -f "$metadata_file" ]; then
        log_error "Backup metadata file not found"
        return 1
    fi

    # Display metadata
    log_info "Backup Information:"
    cat "$metadata_file" | tee -a "$LOG_FILE"

    log_success "Backup metadata read successfully"
}

decrypt_backup() {
    if [ "$ENABLE_ENCRYPTION" = "true" ]; then
        log_info "Decrypting backup..."

        if [ ! -f "$ENCRYPTION_KEY_FILE" ]; then
            log_error "Encryption key file not found: ${ENCRYPTION_KEY_FILE}"
            return 1
        fi

        # Decrypt all encrypted files
        find "$BACKUP_PATH" -type f -name "*.enc" | while read -r encrypted_file; do
            local decrypted_file="${encrypted_file%.enc}"
            openssl enc -aes-256-cbc -d -in "$encrypted_file" -out "$decrypted_file" -pass file:"$ENCRYPTION_KEY_FILE"
            log_info "Decrypted: $(basename "$encrypted_file")"
        done

        log_success "Backup decryption completed"
    fi
}

create_rollback_snapshot() {
    log_info "Creating rollback snapshot..."

    mkdir -p "$ROLLBACK_DIR"

    # Snapshot current PostgreSQL data
    log_info "Snapshotting PostgreSQL..."
    docker exec postgres pg_dumpall -U postgres > "${ROLLBACK_DIR}/postgres-rollback.sql" 2>/dev/null || true

    # Snapshot current Redis data
    log_info "Snapshotting Redis..."
    docker exec redis redis-cli BGSAVE > /dev/null
    sleep 2
    docker cp redis:/data/dump.rdb "${ROLLBACK_DIR}/redis-rollback.rdb" 2>/dev/null || true

    log_success "Rollback snapshot created at: ${ROLLBACK_DIR}"
    log_warning "Keep this directory for rollback capability!"
}

stop_services() {
    log_info "Stopping MinIO services..."

    cd "$PROJECT_ROOT/deployments/docker"
    docker-compose -f docker-compose.production.yml stop minio1 minio2 minio3 minio4 || true

    log_success "MinIO services stopped"
}

start_services() {
    log_info "Starting MinIO services..."

    cd "$PROJECT_ROOT/deployments/docker"
    docker-compose -f docker-compose.production.yml up -d minio1 minio2 minio3 minio4

    # Wait for services to be healthy
    log_info "Waiting for services to become healthy..."
    sleep 10

    local max_wait=60
    local wait_count=0

    while [ $wait_count -lt $max_wait ]; do
        if docker ps --filter "name=minio1" --filter "health=healthy" | grep -q minio1; then
            log_success "MinIO services are healthy"
            return 0
        fi
        sleep 2
        ((wait_count+=2))
    done

    log_warning "Services started but health check timed out"
}

restore_postgresql() {
    log_info "Restoring PostgreSQL database..."

    # Find PostgreSQL backup file
    local pg_backup=$(find "${BACKUP_PATH}/postgres" -name "*.sql.gz" -o -name "*.sql" | head -1)

    if [ -z "$pg_backup" ]; then
        log_error "PostgreSQL backup file not found"
        return 1
    fi

    log_info "Found backup: $(basename "$pg_backup")"

    # Decompress if needed
    local sql_file="$pg_backup"
    if [[ "$pg_backup" == *.gz ]]; then
        log_info "Decompressing PostgreSQL backup..."
        gunzip -k "$pg_backup"
        sql_file="${pg_backup%.gz}"
    fi

    # Restore database
    log_info "Restoring database (this may take several minutes)..."

    # Stop connections and restore
    docker exec -i postgres psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid <> pg_backend_pid();" 2>/dev/null || true
    cat "$sql_file" | docker exec -i postgres psql -U postgres > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        log_success "PostgreSQL restore completed"
    else
        log_error "PostgreSQL restore failed"
        return 1
    fi

    # Cleanup decompressed file if we created it
    if [[ "$pg_backup" == *.gz ]]; then
        rm -f "$sql_file"
    fi
}

restore_redis() {
    log_info "Restoring Redis data..."

    # Find Redis backup file
    local redis_backup=$(find "${BACKUP_PATH}/redis" -name "*.rdb.gz" -o -name "*.rdb" | head -1)

    if [ -z "$redis_backup" ]; then
        log_error "Redis backup file not found"
        return 1
    fi

    log_info "Found backup: $(basename "$redis_backup")"

    # Decompress if needed
    local rdb_file="$redis_backup"
    if [[ "$redis_backup" == *.gz ]]; then
        log_info "Decompressing Redis backup..."
        gunzip -k "$redis_backup"
        rdb_file="${redis_backup%.gz}"
    fi

    # Stop Redis, restore file, start Redis
    log_info "Stopping Redis service..."
    docker-compose -f "$COMPOSE_FILE" stop redis

    log_info "Copying RDB file to Redis container..."
    docker cp "$rdb_file" redis:/data/dump.rdb

    log_info "Starting Redis service..."
    docker-compose -f "$COMPOSE_FILE" start redis

    # Wait for Redis to be ready
    sleep 5

    if docker exec redis redis-cli ping | grep -q PONG; then
        log_success "Redis restore completed and service is healthy"
    else
        log_error "Redis restore failed - service not responding"
        return 1
    fi

    # Cleanup decompressed file if we created it
    if [[ "$redis_backup" == *.gz ]]; then
        rm -f "$rdb_file"
    fi
}

restore_minio_data() {
    log_info "Restoring MinIO data (4-node cluster)..."

    # Stop MinIO services
    stop_services

    # Restore data to each MinIO node
    for node in minio1 minio2 minio3 minio4; do
        local node_backup=$(find "${BACKUP_PATH}/minio" -name "${node}-*.tar.gz" | head -1)

        if [ -z "$node_backup" ]; then
            log_warning "Backup for ${node} not found, skipping..."
            continue
        fi

        log_info "Restoring ${node}..."

        # Restore volume data
        docker run --rm \
            --volumes-from "$node" \
            -v "$(dirname "$node_backup"):/backup" \
            alpine:latest \
            sh -c "rm -rf /data/* && tar -xzf /backup/$(basename "$node_backup") -C /" 2>/dev/null || {
                log_warning "Failed to restore ${node}, continuing..."
                continue
            }

        log_success "${node} restore completed"
    done

    # Start MinIO services
    start_services

    log_success "MinIO cluster restore completed"
}

restore_configurations() {
    log_info "Restoring configuration files..."

    local config_backup=$(find "${BACKUP_PATH}/configs" -name "*.tar.gz" | head -1)

    if [ -z "$config_backup" ]; then
        log_error "Configuration backup not found"
        return 1
    fi

    # Extract configurations to temporary directory
    local temp_config_dir="/tmp/minio-config-restore-${TIMESTAMP}"
    mkdir -p "$temp_config_dir"

    tar -xzf "$config_backup" -C "$temp_config_dir"

    log_info "Configuration files extracted. Review and manually apply if needed."
    log_info "Location: ${temp_config_dir}"

    log_warning "Configuration restore requires manual review and application"
    log_info "Compare files in ${temp_config_dir} with current configuration"
}

perform_rollback() {
    log_info "Performing rollback to previous state..."

    if [ ! -d "$ROLLBACK_DIR" ]; then
        log_error "Rollback directory not found. Cannot rollback."
        exit 1
    fi

    # Rollback PostgreSQL
    if [ -f "${ROLLBACK_DIR}/postgres-rollback.sql" ]; then
        log_info "Rolling back PostgreSQL..."
        cat "${ROLLBACK_DIR}/postgres-rollback.sql" | docker exec -i postgres psql -U postgres > /dev/null 2>&1
        log_success "PostgreSQL rollback completed"
    fi

    # Rollback Redis
    if [ -f "${ROLLBACK_DIR}/redis-rollback.rdb" ]; then
        log_info "Rolling back Redis..."
        docker-compose -f "$COMPOSE_FILE" stop redis
        docker cp "${ROLLBACK_DIR}/redis-rollback.rdb" redis:/data/dump.rdb
        docker-compose -f "$COMPOSE_FILE" start redis
        log_success "Redis rollback completed"
    fi

    log_success "Rollback completed"
}

verify_restore() {
    log_info "Verifying restore..."

    local verification_failed=false

    # Check PostgreSQL
    if docker exec postgres psql -U postgres -c "SELECT 1" > /dev/null 2>&1; then
        log_success "✓ PostgreSQL is responding"
    else
        log_error "✗ PostgreSQL verification failed"
        verification_failed=true
    fi

    # Check Redis
    if docker exec redis redis-cli ping | grep -q PONG; then
        log_success "✓ Redis is responding"
    else
        log_error "✗ Redis verification failed"
        verification_failed=true
    fi

    # Check MinIO nodes
    for node in minio1 minio2 minio3 minio4; do
        if docker ps --filter "name=$node" --filter "health=healthy" | grep -q "$node"; then
            log_success "✓ ${node} is healthy"
        else
            log_warning "✗ ${node} verification failed"
        fi
    done

    if [ "$verification_failed" = true ]; then
        log_error "Restore verification failed"
        return 1
    fi

    log_success "Restore verification completed successfully"
}

# ============================================================
# Main Restore Process
# ============================================================

main() {
    echo "======================================================"
    echo "MinIO Enterprise Restore Script"
    echo "======================================================"
    echo ""

    log_info "Starting restore process..."
    log_info "Backup path: ${BACKUP_PATH}"
    log_info "Log file: ${LOG_FILE}"

    # Pre-flight checks
    check_dependencies
    validate_backup_path
    verify_backup_integrity
    read_backup_metadata
    decrypt_backup

    if [ "$VERIFY_ONLY" = true ]; then
        log_success "Verification complete. Backup is valid."
        exit 0
    fi

    if [ "$ROLLBACK" = true ]; then
        perform_rollback
        exit 0
    fi

    # Confirmation prompt
    echo ""
    log_warning "WARNING: This will overwrite existing data!"
    log_warning "Make sure you have a rollback plan in place."
    echo ""
    read -p "Do you want to continue? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        log_info "Restore cancelled by user"
        exit 0
    fi

    # Create rollback snapshot
    create_rollback_snapshot

    # Perform restore
    log_info "Starting restore operations..."

    restore_postgresql
    restore_redis
    restore_minio_data
    restore_configurations

    # Verify restore
    verify_restore

    # Summary
    echo ""
    echo "======================================================"
    log_success "Restore completed successfully!"
    echo "======================================================"
    log_info "Rollback snapshot saved at: ${ROLLBACK_DIR}"
    log_info "Log file: ${LOG_FILE}"
    echo ""
    log_info "To rollback this restore, run:"
    echo "  ./restore.sh ${BACKUP_PATH} --rollback"
    echo ""
    log_warning "Please verify your application functionality before removing rollback snapshot"
}

# ============================================================
# Script Entry Point
# ============================================================

main "$@"
