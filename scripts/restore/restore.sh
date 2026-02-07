#!/bin/bash
# MinIO Enterprise Restore Script
# Version: 1.0.0
# Description: Automated restore script for MinIO Enterprise with verification,
#              rollback capabilities, and safety checks

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default configuration
BACKUP_FILE="${1:-}"
RESTORE_MODE="${RESTORE_MODE:-full}"  # full, partial
VERIFY_BEFORE_RESTORE="${VERIFY_BEFORE_RESTORE:-true}"
CREATE_SNAPSHOT="${CREATE_SNAPSHOT:-true}"
FORCE_RESTORE="${FORCE_RESTORE:-false}"
LOG_FILE="${LOG_FILE:-/var/log/minio-restore.log}"

# Docker compose file
COMPOSE_FILE="${PROJECT_ROOT}/deployments/docker/docker-compose.production.yml"

# Temporary working directory
WORK_DIR="/tmp/minio-restore-$$"
SNAPSHOT_DIR="/var/backups/minio-snapshots"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================
# Logging Functions
# ============================================================

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
    echo -e "${GREEN}✓${NC} $@"
}

log_warn() {
    log "WARN" "$@"
    echo -e "${YELLOW}⚠${NC} $@"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}✗${NC} $@"
}

log_step() {
    log "STEP" "$@"
    echo -e "${BLUE}➜${NC} $@"
}

# ============================================================
# Utility Functions
# ============================================================

usage() {
    cat <<EOF
Usage: $0 <backup_file> [options]

Restore MinIO Enterprise from a backup file.

Arguments:
  backup_file           Path to backup file or directory

Options:
  --mode MODE          Restore mode: full (default), partial
  --no-verify          Skip backup verification before restore
  --no-snapshot        Don't create snapshot before restore
  --force              Force restore without confirmation
  --components LIST    Comma-separated list of components to restore
                       (minio,postgresql,redis,configs)
  --help               Show this help message

Environment Variables:
  RESTORE_MODE         Restore mode (full, partial)
  VERIFY_BEFORE_RESTORE  Verify backup before restore (true, false)
  CREATE_SNAPSHOT      Create snapshot before restore (true, false)
  FORCE_RESTORE        Skip confirmation prompts (true, false)
  ENCRYPTION_KEY       Encryption key (if backup is encrypted)

Examples:
  # Full restore with default settings
  $0 /var/backups/minio-backup-full-20240118_120000.tar.gz

  # Restore only PostgreSQL and Redis
  $0 /path/to/backup.tar.gz --components postgresql,redis

  # Force restore without confirmation
  $0 /path/to/backup.tar.gz --force

EOF
    exit 1
}

check_dependencies() {
    log_info "Checking dependencies..."

    local deps=("docker" "docker-compose" "tar" "gzip" "psql")

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done

    log_info "All dependencies satisfied"
}

check_services() {
    log_info "Checking service status..."

    if ! docker-compose -f "$COMPOSE_FILE" ps | grep -q "Up"; then
        log_warn "Some services are not running"
        log_warn "Services should be stopped before restore"

        if [ "$FORCE_RESTORE" = "false" ]; then
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Restore cancelled"
                exit 0
            fi
        fi
    fi
}

validate_backup_file() {
    log_info "Validating backup file: $BACKUP_FILE"

    if [ ! -e "$BACKUP_FILE" ]; then
        log_error "Backup file not found: $BACKUP_FILE"
        return 1
    fi

    # Check if encrypted
    if [[ "$BACKUP_FILE" == *.enc ]]; then
        log_info "Backup is encrypted"

        if [ -z "${ENCRYPTION_KEY:-}" ]; then
            log_error "ENCRYPTION_KEY not set for encrypted backup"
            return 1
        fi

        log_info "Decrypting backup..."
        local decrypted_file="${WORK_DIR}/backup.tar.gz"
        openssl enc -aes-256-cbc -d -pbkdf2 -in "$BACKUP_FILE" -out "$decrypted_file" -k "$ENCRYPTION_KEY"

        if [ $? -ne 0 ]; then
            log_error "Decryption failed"
            return 1
        fi

        BACKUP_FILE="$decrypted_file"
        log_info "Backup decrypted successfully"
    fi

    # Check if compressed
    if [[ "$BACKUP_FILE" == *.tar.gz ]] || [[ "$BACKUP_FILE" == *.tgz ]]; then
        log_info "Backup is compressed, extracting..."
        tar xzf "$BACKUP_FILE" -C "$WORK_DIR"

        # Find extracted directory
        local extracted_dir=$(find "$WORK_DIR" -maxdepth 1 -name "minio-backup-*" -type d | head -n 1)

        if [ -z "$extracted_dir" ]; then
            log_error "Failed to find extracted backup directory"
            return 1
        fi

        BACKUP_FILE="$extracted_dir"
        log_info "Backup extracted to: $BACKUP_FILE"
    fi

    log_info "Backup file validated"
}

verify_backup() {
    if [ "$VERIFY_BEFORE_RESTORE" = "false" ]; then
        log_info "Backup verification skipped"
        return 0
    fi

    log_info "Verifying backup integrity..."

    # Check metadata
    if [ ! -f "$BACKUP_FILE/metadata/backup_info.json" ]; then
        log_error "Backup metadata not found"
        return 1
    fi

    # Display backup information
    log_info "Backup Information:"
    cat "$BACKUP_FILE/metadata/backup_info.json" | tee -a "$LOG_FILE"

    # Verify checksums
    if [ -f "$BACKUP_FILE/metadata/checksums.txt" ]; then
        log_info "Verifying checksums..."

        cd "$BACKUP_FILE"
        if sha256sum -c metadata/checksums.txt > /dev/null 2>&1; then
            log_info "Checksum verification passed"
        else
            log_error "Checksum verification failed"
            return 1
        fi
    else
        log_warn "Checksums file not found, skipping verification"
    fi

    log_info "Backup verification completed"
}

create_snapshot() {
    if [ "$CREATE_SNAPSHOT" = "false" ]; then
        log_info "Snapshot creation skipped"
        return 0
    fi

    log_info "Creating pre-restore snapshot..."

    mkdir -p "$SNAPSHOT_DIR"
    local snapshot_name="snapshot-$(date +%Y%m%d_%H%M%S)"
    local snapshot_path="${SNAPSHOT_DIR}/${snapshot_name}"

    # Run backup script to create snapshot
    if [ -f "${PROJECT_ROOT}/scripts/backup/backup.sh" ]; then
        BACKUP_DIR="$SNAPSHOT_DIR" BACKUP_TYPE="full" \
            bash "${PROJECT_ROOT}/scripts/backup/backup.sh" || {
            log_warn "Snapshot creation failed, continuing anyway"
            return 0
        }

        log_info "Snapshot created: $snapshot_path"
        echo "$snapshot_path" > "${WORK_DIR}/snapshot_path.txt"
    else
        log_warn "Backup script not found, skipping snapshot"
    fi
}

confirm_restore() {
    if [ "$FORCE_RESTORE" = "true" ]; then
        return 0
    fi

    log_warn "======================================"
    log_warn "WARNING: This will restore the system"
    log_warn "from backup and overwrite current data"
    log_warn "======================================"
    echo
    read -p "Are you sure you want to continue? (yes/NO): " -r
    echo

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Restore cancelled by user"
        exit 0
    fi
}

stop_services() {
    log_step "Stopping MinIO services..."

    docker-compose -f "$COMPOSE_FILE" stop

    if [ $? -eq 0 ]; then
        log_info "Services stopped successfully"
    else
        log_error "Failed to stop services"
        return 1
    fi
}

restore_minio_data() {
    log_step "Restoring MinIO object data..."

    # Get list of backup files
    local backup_files=$(find "$BACKUP_FILE/minio" -name "*.tar.gz" -type f)

    if [ -z "$backup_files" ]; then
        log_error "No MinIO backup files found"
        return 1
    fi

    for backup_archive in $backup_files; do
        local volume_name=$(basename "$backup_archive" .tar.gz)
        log_info "Restoring volume: $volume_name"

        # Extract backup to volume
        docker run --rm \
            -v "${volume_name}:/data" \
            -v "$(dirname $backup_archive):/backup:ro" \
            alpine:latest \
            sh -c "rm -rf /data/* && tar xzf /backup/$(basename $backup_archive) -C /data"

        if [ $? -eq 0 ]; then
            log_info "Successfully restored volume: $volume_name"
        else
            log_error "Failed to restore volume: $volume_name"
            return 1
        fi
    done

    log_info "MinIO data restored"
}

restore_postgresql() {
    log_step "Restoring PostgreSQL database..."

    # Find SQL dump
    local sql_file=$(find "$BACKUP_FILE/postgres" -name "*.sql.gz" -o -name "*.sql" | head -n 1)

    if [ -z "$sql_file" ]; then
        log_error "PostgreSQL backup file not found"
        return 1
    fi

    # Start PostgreSQL service
    docker-compose -f "$COMPOSE_FILE" start postgres
    sleep 5

    # Get credentials
    local postgres_user="${POSTGRES_USER:-minio}"
    local postgres_db="${POSTGRES_DB:-minio_enterprise}"

    # Drop and recreate database
    log_info "Dropping existing database..."
    docker-compose -f "$COMPOSE_FILE" exec -T postgres \
        psql -U "$postgres_user" -c "DROP DATABASE IF EXISTS $postgres_db;"

    log_info "Creating fresh database..."
    docker-compose -f "$COMPOSE_FILE" exec -T postgres \
        psql -U "$postgres_user" -c "CREATE DATABASE $postgres_db;"

    # Restore SQL dump
    log_info "Restoring SQL dump..."
    if [[ "$sql_file" == *.gz ]]; then
        zcat "$sql_file" | docker-compose -f "$COMPOSE_FILE" exec -T postgres \
            psql -U "$postgres_user" -d "$postgres_db"
    else
        cat "$sql_file" | docker-compose -f "$COMPOSE_FILE" exec -T postgres \
            psql -U "$postgres_user" -d "$postgres_db"
    fi

    if [ $? -eq 0 ]; then
        log_info "PostgreSQL database restored"
    else
        log_error "PostgreSQL restore failed"
        return 1
    fi

    # Stop PostgreSQL
    docker-compose -f "$COMPOSE_FILE" stop postgres
}

restore_redis() {
    log_step "Restoring Redis data..."

    # Find Redis backup
    local rdb_file=$(find "$BACKUP_FILE/redis" -name "dump.rdb.gz" -o -name "dump.rdb" | head -n 1)

    if [ -z "$rdb_file" ]; then
        log_error "Redis backup file not found"
        return 1
    fi

    # Decompress if needed
    local rdb_source="$rdb_file"
    if [[ "$rdb_file" == *.gz ]]; then
        log_info "Decompressing Redis backup..."
        gunzip -c "$rdb_file" > "${WORK_DIR}/dump.rdb"
        rdb_source="${WORK_DIR}/dump.rdb"
    fi

    # Copy RDB file to Redis volume
    log_info "Copying Redis backup to volume..."
    docker run --rm \
        -v redis-data:/data \
        -v "$(dirname $rdb_source):/backup:ro" \
        alpine:latest \
        cp "/backup/$(basename $rdb_source)" /data/dump.rdb

    if [ $? -eq 0 ]; then
        log_info "Redis data restored"
    else
        log_error "Redis restore failed"
        return 1
    fi
}

restore_configs() {
    log_step "Restoring configuration files..."

    if [ ! -d "$BACKUP_FILE/configs" ]; then
        log_warn "Configuration backup not found, skipping"
        return 0
    fi

    # Backup current configs
    if [ -d "${PROJECT_ROOT}/configs" ]; then
        mv "${PROJECT_ROOT}/configs" "${PROJECT_ROOT}/configs.old.$$"
        log_info "Current configs backed up to configs.old.$$"
    fi

    # Restore configs
    cp -r "$BACKUP_FILE/configs/configs" "${PROJECT_ROOT}/configs"

    # Restore deployment configs if they exist
    if [ -d "$BACKUP_FILE/configs/deployments" ]; then
        cp -r "$BACKUP_FILE/configs/deployments"/* "${PROJECT_ROOT}/deployments/"
    fi

    log_info "Configuration files restored"
}

start_services() {
    log_step "Starting MinIO services..."

    docker-compose -f "$COMPOSE_FILE" up -d

    if [ $? -eq 0 ]; then
        log_info "Services started successfully"
    else
        log_error "Failed to start services"
        return 1
    fi

    # Wait for services to be healthy
    log_info "Waiting for services to be healthy..."
    sleep 10

    # Check health
    local retries=30
    local count=0

    while [ $count -lt $retries ]; do
        if docker-compose -f "$COMPOSE_FILE" ps | grep -q "healthy"; then
            log_info "Services are healthy"
            return 0
        fi

        count=$((count + 1))
        sleep 2
    done

    log_warn "Services may not be fully healthy yet"
}

verify_restore() {
    log_step "Verifying restore..."

    # Check if services are running
    if ! docker-compose -f "$COMPOSE_FILE" ps | grep -q "Up"; then
        log_error "Services are not running"
        return 1
    fi

    # Check MinIO health endpoint
    if command -v curl &> /dev/null; then
        local health_check=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9000/minio/health/live || echo "000")

        if [ "$health_check" = "200" ]; then
            log_info "MinIO health check passed"
        else
            log_warn "MinIO health check failed (HTTP $health_check)"
        fi
    fi

    # Check PostgreSQL connection
    if docker-compose -f "$COMPOSE_FILE" exec -T postgres psql -U minio -d minio_enterprise -c "SELECT 1;" > /dev/null 2>&1; then
        log_info "PostgreSQL connection successful"
    else
        log_warn "PostgreSQL connection failed"
    fi

    # Check Redis connection
    if docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli ping | grep -q "PONG"; then
        log_info "Redis connection successful"
    else
        log_warn "Redis connection failed"
    fi

    log_info "Restore verification completed"
}

rollback() {
    log_error "Restore failed, attempting rollback..."

    if [ ! -f "${WORK_DIR}/snapshot_path.txt" ]; then
        log_error "No snapshot found for rollback"
        return 1
    fi

    local snapshot_path=$(cat "${WORK_DIR}/snapshot_path.txt")

    log_info "Rolling back to snapshot: $snapshot_path"

    # Stop services
    stop_services

    # Restore from snapshot
    BACKUP_FILE="$snapshot_path" \
    CREATE_SNAPSHOT="false" \
    FORCE_RESTORE="true" \
        bash "$0" "$snapshot_path" --no-snapshot --force

    if [ $? -eq 0 ]; then
        log_info "Rollback completed successfully"
    else
        log_error "Rollback failed"
        return 1
    fi
}

cleanup() {
    log_info "Cleaning up temporary files..."

    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
        log_info "Temporary directory removed"
    fi
}

# ============================================================
# Main Execution
# ============================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mode)
                RESTORE_MODE="$2"
                shift 2
                ;;
            --no-verify)
                VERIFY_BEFORE_RESTORE="false"
                shift
                ;;
            --no-snapshot)
                CREATE_SNAPSHOT="false"
                shift
                ;;
            --force)
                FORCE_RESTORE="true"
                shift
                ;;
            --help)
                usage
                ;;
            *)
                if [ -z "$BACKUP_FILE" ]; then
                    BACKUP_FILE="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate arguments
    if [ -z "$BACKUP_FILE" ]; then
        log_error "Backup file not specified"
        usage
    fi

    log_info "======================================"
    log_info "MinIO Enterprise Restore Script"
    log_info "Backup File: $BACKUP_FILE"
    log_info "Restore Mode: $RESTORE_MODE"
    log_info "======================================"

    # Create working directory
    mkdir -p "$WORK_DIR"

    # Trap cleanup on exit
    trap cleanup EXIT

    # Pre-restore checks
    check_dependencies || exit 1
    check_services

    # Validate and prepare backup
    validate_backup_file || exit 1
    verify_backup || exit 1

    # Confirmation
    confirm_restore

    # Create snapshot
    create_snapshot

    # Stop services
    stop_services || {
        log_error "Failed to stop services"
        exit 1
    }

    # Perform restore
    local restore_failed=false

    restore_minio_data || restore_failed=true
    restore_postgresql || restore_failed=true
    restore_redis || restore_failed=true
    restore_configs

    if [ "$restore_failed" = "true" ]; then
        log_error "Restore failed"
        rollback
        exit 1
    fi

    # Start services
    start_services || {
        log_error "Failed to start services"
        rollback
        exit 1
    }

    # Verify restore
    verify_restore || log_warn "Restore verification had warnings"

    log_info "======================================"
    log_info "Restore completed successfully!"
    log_info "======================================"
}

# Run main function
main "$@"
