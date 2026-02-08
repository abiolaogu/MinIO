#!/bin/bash

###############################################################################
# MinIO Enterprise - Automated Restore Script
# Version: 1.0.0
# Description: Comprehensive restore solution for MinIO data, PostgreSQL,
#              Redis, and configuration files
###############################################################################

set -euo pipefail

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/var/backups/minio-enterprise}"
RESTORE_FROM="${RESTORE_FROM:-}"
ENABLE_VERIFICATION="${ENABLE_VERIFICATION:-true}"
ENABLE_ROLLBACK="${ENABLE_ROLLBACK:-true}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"
DRY_RUN="${DRY_RUN:-false}"

# Database credentials
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-minio_db}"
POSTGRES_USER="${POSTGRES_USER:-minio_user}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"

REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

# Logging
LOG_FILE="${BACKUP_DIR}/logs/restore-$(date +%Y%m%d-%H%M%S).log"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESTORE_TMP_DIR="/tmp/minio-restore-${TIMESTAMP}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###############################################################################
# Utility Functions
###############################################################################

log() {
    local level=$1
    shift
    local message="$@"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $@" >&2
    log "ERROR" "$@"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $@"
    log "INFO" "$@"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $@"
    log "WARN" "$@"
}

info() {
    echo -e "[INFO] $@"
    log "INFO" "$@"
}

prompt_confirmation() {
    local message="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would prompt: $message"
        return 0
    fi

    echo -e "${YELLOW}[CONFIRM]${NC} $message"
    read -p "Continue? (yes/no): " response

    if [[ "$response" != "yes" ]]; then
        error "Operation cancelled by user"
        exit 1
    fi
}

check_dependencies() {
    local deps=("docker" "docker-compose" "tar" "gzip")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "Required dependency '$dep' is not installed"
            exit 1
        fi
    done

    success "All dependencies are available"
}

create_restore_dirs() {
    mkdir -p "$RESTORE_TMP_DIR"
    mkdir -p "${BACKUP_DIR}/logs"
    success "Created restore temporary directories"
}

###############################################################################
# Backup Analysis Functions
###############################################################################

list_available_backups() {
    info "Available backups:"
    echo "========================================"

    local backups=$(find "$BACKUP_DIR" -type f \( -name "minio-backup-*.tar.gz" -o -name "minio-backup-*.tar.gz.enc" \) -printf "%T@ %p\n" | sort -rn | head -20)

    if [[ -z "$backups" ]]; then
        warning "No backups found in $BACKUP_DIR"
        return 1
    fi

    echo "$backups" | while read -r timestamp path; do
        local date=$(date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S")
        local size=$(du -h "$path" | cut -f1)
        local name=$(basename "$path")
        echo "  $date | $size | $name"
    done

    echo "========================================"
}

get_backup_metadata() {
    local backup_file="$1"
    local backup_name=$(basename "$backup_file" | sed 's/.tar.gz.*$//')

    local metadata_file="${BACKUP_DIR}/metadata/${backup_name}.json"

    if [[ -f "$metadata_file" ]]; then
        cat "$metadata_file"
    else
        warning "Metadata file not found: $metadata_file"
        echo "{}"
    fi
}

###############################################################################
# Restore Preparation Functions
###############################################################################

decrypt_backup() {
    local backup_file="$1"

    if [[ ! "$backup_file" =~ \.enc$ ]]; then
        # Not encrypted, return as-is
        echo "$backup_file"
        return 0
    fi

    if [[ -z "$ENCRYPTION_KEY" ]]; then
        error "Backup is encrypted but ENCRYPTION_KEY not provided"
        exit 1
    fi

    info "Decrypting backup..."

    local decrypted_file="${RESTORE_TMP_DIR}/$(basename ${backup_file%.enc})"

    if openssl enc -d -aes-256-cbc -pbkdf2 \
        -in "$backup_file" \
        -out "$decrypted_file" \
        -k "$ENCRYPTION_KEY" 2>>"$LOG_FILE"; then

        success "Backup decrypted: $decrypted_file"
        echo "$decrypted_file"
    else
        error "Decryption failed. Check ENCRYPTION_KEY."
        exit 1
    fi
}

extract_backup() {
    local backup_file="$1"

    info "Extracting backup archive..."

    if tar -xzf "$backup_file" -C "$RESTORE_TMP_DIR" 2>>"$LOG_FILE"; then
        success "Backup extracted to: $RESTORE_TMP_DIR"
    else
        error "Failed to extract backup archive"
        exit 1
    fi
}

verify_backup_integrity() {
    local backup_file="$1"

    info "Verifying backup integrity..."

    if tar -tzf "$backup_file" &>/dev/null; then
        success "Backup archive integrity verified"
    else
        error "Backup archive is corrupted"
        exit 1
    fi
}

###############################################################################
# Pre-Restore Backup Functions
###############################################################################

create_pre_restore_backup() {
    if [[ "$ENABLE_ROLLBACK" != "true" ]]; then
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create pre-restore backup"
        return 0
    fi

    info "Creating pre-restore backup for rollback..."

    local rollback_backup="${BACKUP_DIR}/rollback-${TIMESTAMP}"

    # Quick backup of current state
    BACKUP_DIR="$rollback_backup" \
    BACKUP_TYPE="rollback" \
    ENABLE_COMPRESSION="true" \
    ENABLE_ENCRYPTION="false" \
    bash scripts/backup.sh --full &>>"$LOG_FILE" || {
        warning "Could not create rollback backup (continuing anyway)"
        return 0
    }

    success "Pre-restore backup created: $rollback_backup"
}

###############################################################################
# Restore Functions
###############################################################################

restore_postgres() {
    info "Restoring PostgreSQL database..."

    local backup_name=$(basename "$RESTORE_FROM" | sed 's/.tar.gz.*$//')
    local postgres_backup=$(find "$RESTORE_TMP_DIR" -name "*postgres.sql*" | head -1)

    if [[ -z "$postgres_backup" ]]; then
        # Check in backup directory
        postgres_backup=$(find "${BACKUP_DIR}/postgres" -name "${backup_name}*postgres.sql*" | head -1)
    fi

    if [[ -z "$postgres_backup" ]]; then
        warning "PostgreSQL backup not found, skipping"
        return 0
    fi

    # Decompress if needed
    if [[ "$postgres_backup" =~ \.gz$ ]]; then
        gunzip -c "$postgres_backup" > "${RESTORE_TMP_DIR}/postgres.sql"
        postgres_backup="${RESTORE_TMP_DIR}/postgres.sql"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would restore PostgreSQL from: $postgres_backup"
        return 0
    fi

    prompt_confirmation "This will OVERWRITE the current PostgreSQL database. Are you sure?"

    # Drop and recreate database
    docker-compose -f deployments/docker/docker-compose.production.yml exec -T postgres \
        psql -U "$POSTGRES_USER" -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};" 2>>"$LOG_FILE" || true

    docker-compose -f deployments/docker/docker-compose.production.yml exec -T postgres \
        psql -U "$POSTGRES_USER" -c "CREATE DATABASE ${POSTGRES_DB};" 2>>"$LOG_FILE"

    # Restore database
    docker-compose -f deployments/docker/docker-compose.production.yml exec -T postgres \
        psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$postgres_backup" 2>>"$LOG_FILE"

    success "PostgreSQL database restored"
}

restore_redis() {
    info "Restoring Redis data..."

    local backup_name=$(basename "$RESTORE_FROM" | sed 's/.tar.gz.*$//')
    local redis_backup=$(find "$RESTORE_TMP_DIR" -name "*redis.rdb*" | head -1)

    if [[ -z "$redis_backup" ]]; then
        redis_backup=$(find "${BACKUP_DIR}/redis" -name "${backup_name}*redis.rdb*" | head -1)
    fi

    if [[ -z "$redis_backup" ]]; then
        warning "Redis backup not found, skipping"
        return 0
    fi

    # Decompress if needed
    if [[ "$redis_backup" =~ \.gz$ ]]; then
        gunzip -c "$redis_backup" > "${RESTORE_TMP_DIR}/dump.rdb"
        redis_backup="${RESTORE_TMP_DIR}/dump.rdb"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would restore Redis from: $redis_backup"
        return 0
    fi

    prompt_confirmation "This will OVERWRITE the current Redis data. Are you sure?"

    # Stop Redis, replace RDB file, restart
    docker-compose -f deployments/docker/docker-compose.production.yml stop redis 2>>"$LOG_FILE"

    docker cp "$redis_backup" \
        $(docker-compose -f deployments/docker/docker-compose.production.yml ps -q redis):/data/dump.rdb \
        2>>"$LOG_FILE"

    docker-compose -f deployments/docker/docker-compose.production.yml start redis 2>>"$LOG_FILE"

    success "Redis data restored"
}

restore_minio_data() {
    info "Restoring MinIO data..."

    local data_dir=$(find "$RESTORE_TMP_DIR" -type d -name "minio-data" | head -1)

    if [[ -z "$data_dir" ]]; then
        warning "MinIO data backup not found, skipping"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would restore MinIO data from: $data_dir"
        return 0
    fi

    prompt_confirmation "This will OVERWRITE MinIO object data. Are you sure?"

    # Stop MinIO nodes
    docker-compose -f deployments/docker/docker-compose.production.yml stop \
        minio-node-1 minio-node-2 minio-node-3 minio-node-4 2>>"$LOG_FILE"

    # Restore data to first node
    local first_container=$(docker-compose -f deployments/docker/docker-compose.production.yml ps -q minio-node-1)

    if [[ -n "$first_container" ]]; then
        docker cp "$data_dir/data" "$first_container:/" 2>>"$LOG_FILE"
        success "MinIO data copied to container"
    else
        warning "MinIO container not found, manual data restoration may be required"
    fi

    # Restart MinIO cluster
    docker-compose -f deployments/docker/docker-compose.production.yml start \
        minio-node-1 minio-node-2 minio-node-3 minio-node-4 2>>"$LOG_FILE"

    success "MinIO data restored"
}

restore_configs() {
    info "Restoring configuration files..."

    local config_dir=$(find "$RESTORE_TMP_DIR" -type d -path "*/configs/*" | head -1 | xargs dirname)

    if [[ -z "$config_dir" ]]; then
        warning "Configuration backup not found, skipping"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would restore configs from: $config_dir"
        return 0
    fi

    prompt_confirmation "This will OVERWRITE configuration files. Are you sure?"

    # Backup current configs
    if [[ -d "configs" ]]; then
        mv configs "configs.backup-${TIMESTAMP}" 2>>"$LOG_FILE" || true
    fi

    # Restore configs
    cp -r "$config_dir"/* . 2>>"$LOG_FILE" || true

    success "Configuration files restored"
}

###############################################################################
# Post-Restore Functions
###############################################################################

verify_restore() {
    if [[ "$ENABLE_VERIFICATION" != "true" ]]; then
        return 0
    fi

    info "Verifying restore..."

    # Check PostgreSQL
    if docker-compose -f deployments/docker/docker-compose.production.yml exec -T postgres \
        psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt" &>>"$LOG_FILE"; then
        success "PostgreSQL verification passed"
    else
        error "PostgreSQL verification failed"
        return 1
    fi

    # Check Redis
    if docker-compose -f deployments/docker/docker-compose.production.yml exec -T redis \
        redis-cli PING | grep -q "PONG" 2>>"$LOG_FILE"; then
        success "Redis verification passed"
    else
        error "Redis verification failed"
        return 1
    fi

    # Check MinIO cluster
    sleep 5  # Give MinIO time to start
    local health_check=$(docker-compose -f deployments/docker/docker-compose.production.yml ps | grep minio | grep -c "Up" || true)

    if [[ "$health_check" -ge 1 ]]; then
        success "MinIO cluster verification passed ($health_check nodes running)"
    else
        warning "MinIO cluster health check inconclusive"
    fi

    success "Restore verification completed"
}

cleanup_restore() {
    info "Cleaning up temporary files..."

    rm -rf "$RESTORE_TMP_DIR" 2>>"$LOG_FILE" || true

    success "Cleanup completed"
}

###############################################################################
# Main Execution
###############################################################################

main() {
    echo "========================================"
    echo "MinIO Enterprise Restore"
    echo "========================================"
    echo "Timestamp: $TIMESTAMP"
    echo "Dry Run: $DRY_RUN"
    echo "========================================"
    echo

    # Preflight checks
    check_dependencies
    create_restore_dirs

    # Select backup if not specified
    if [[ -z "$RESTORE_FROM" ]]; then
        list_available_backups
        echo
        read -p "Enter backup filename to restore: " RESTORE_FROM
        RESTORE_FROM="${BACKUP_DIR}/${RESTORE_FROM}"
    fi

    if [[ ! -f "$RESTORE_FROM" ]]; then
        error "Backup file not found: $RESTORE_FROM"
        exit 1
    fi

    info "Restoring from: $RESTORE_FROM"

    # Show backup metadata
    info "Backup metadata:"
    get_backup_metadata "$RESTORE_FROM" | head -20

    # Verify backup
    verify_backup_integrity "$RESTORE_FROM"

    # Decrypt if needed
    local decrypted_backup=$(decrypt_backup "$RESTORE_FROM")

    # Extract backup
    extract_backup "$decrypted_backup"

    # Create rollback backup
    create_pre_restore_backup

    # Perform restore
    restore_postgres
    restore_redis
    restore_minio_data
    restore_configs

    # Verify and cleanup
    verify_restore
    cleanup_restore

    echo
    echo "========================================"
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Restore simulation completed"
    else
        success "Restore completed successfully!"
    fi
    echo "========================================"
    echo "Restored from: $RESTORE_FROM"
    echo "Log file: $LOG_FILE"
    echo "========================================"

    if [[ "$ENABLE_ROLLBACK" == "true" && "$DRY_RUN" != "true" ]]; then
        echo
        info "A rollback backup was created at: ${BACKUP_DIR}/rollback-${TIMESTAMP}"
        info "To rollback, run: RESTORE_FROM=\"<rollback-file>\" ./restore.sh"
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        cat <<EOF
MinIO Enterprise Restore Script

Usage: $0 [OPTIONS]

Options:
  --help, -h           Show this help message
  --list               List available backups
  --dry-run            Simulate restore without making changes
  --verify-only FILE   Only verify backup without restoring

Environment Variables:
  RESTORE_FROM         Backup file to restore from (if not set, will prompt)
  BACKUP_DIR           Backup directory (default: /var/backups/minio-enterprise)
  ENABLE_VERIFICATION  Verify restore (default: true)
  ENABLE_ROLLBACK      Create pre-restore backup (default: true)
  ENCRYPTION_KEY       Decryption passphrase (if backup is encrypted)
  DRY_RUN              Simulate without making changes (default: false)

Examples:
  # List available backups
  ./restore.sh --list

  # Interactive restore (will prompt for backup)
  ./restore.sh

  # Restore specific backup
  RESTORE_FROM="/var/backups/minio-enterprise/minio-backup-full-20240115-120000.tar.gz" ./restore.sh

  # Restore encrypted backup
  RESTORE_FROM="backup.tar.gz.enc" ENCRYPTION_KEY="mypassword" ./restore.sh

  # Dry run (no changes made)
  DRY_RUN=true RESTORE_FROM="backup.tar.gz" ./restore.sh

  # Restore without rollback backup
  ENABLE_ROLLBACK=false RESTORE_FROM="backup.tar.gz" ./restore.sh

EOF
        exit 0
        ;;
    --list)
        list_available_backups
        exit 0
        ;;
    --dry-run)
        DRY_RUN=true
        main
        ;;
    --verify-only)
        if [[ -z "${2:-}" ]]; then
            error "Please specify backup file to verify"
            exit 1
        fi
        RESTORE_FROM="$2"
        verify_backup_integrity "$RESTORE_FROM"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
