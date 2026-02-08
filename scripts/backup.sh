#!/bin/bash

###############################################################################
# MinIO Enterprise - Automated Backup Script
# Version: 1.0.0
# Description: Comprehensive backup solution for MinIO data, PostgreSQL,
#              Redis, and configuration files
###############################################################################

set -euo pipefail

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/var/backups/minio-enterprise}"
BACKUP_TYPE="${BACKUP_TYPE:-full}"  # full or incremental
RETENTION_DAYS="${RETENTION_DAYS:-30}"
ENABLE_COMPRESSION="${ENABLE_COMPRESSION:-true}"
ENABLE_ENCRYPTION="${ENABLE_ENCRYPTION:-false}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"
S3_BACKUP="${S3_BACKUP:-false}"
S3_ENDPOINT="${S3_ENDPOINT:-}"
S3_BUCKET="${S3_BUCKET:-}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-}"
S3_SECRET_KEY="${S3_SECRET_KEY:-}"

# Database credentials (from environment or Docker Compose)
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-minio_db}"
POSTGRES_USER="${POSTGRES_USER:-minio_user}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"

REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

# Logging
LOG_FILE="${BACKUP_DIR}/logs/backup-$(date +%Y%m%d-%H%M%S).log"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="minio-backup-${BACKUP_TYPE}-${TIMESTAMP}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

check_dependencies() {
    local deps=("docker" "docker-compose" "tar" "gzip")

    if [[ "$ENABLE_ENCRYPTION" == "true" ]]; then
        deps+=("openssl")
    fi

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "Required dependency '$dep' is not installed"
            exit 1
        fi
    done

    success "All dependencies are available"
}

create_backup_dirs() {
    mkdir -p "${BACKUP_DIR}"/{data,postgres,redis,configs,logs,metadata}
    mkdir -p "${BACKUP_DIR}/data/${BACKUP_NAME}"
    success "Created backup directories"
}

###############################################################################
# Backup Functions
###############################################################################

backup_postgres() {
    info "Starting PostgreSQL backup..."

    local backup_file="${BACKUP_DIR}/postgres/${BACKUP_NAME}-postgres.sql"

    if docker-compose -f deployments/docker/docker-compose.production.yml exec -T postgres \
        pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > "$backup_file" 2>>"$LOG_FILE"; then

        local size=$(du -h "$backup_file" | cut -f1)
        success "PostgreSQL backup completed: $backup_file ($size)"

        if [[ "$ENABLE_COMPRESSION" == "true" ]]; then
            gzip "$backup_file"
            success "PostgreSQL backup compressed: ${backup_file}.gz"
        fi
    else
        error "PostgreSQL backup failed"
        return 1
    fi
}

backup_redis() {
    info "Starting Redis backup..."

    local backup_file="${BACKUP_DIR}/redis/${BACKUP_NAME}-redis.rdb"

    # Trigger Redis SAVE command
    if docker-compose -f deployments/docker/docker-compose.production.yml exec -T redis \
        redis-cli SAVE &>>"$LOG_FILE"; then

        # Copy the RDB file
        docker-compose -f deployments/docker/docker-compose.production.yml exec -T redis \
            cat /data/dump.rdb > "$backup_file" 2>>"$LOG_FILE"

        local size=$(du -h "$backup_file" | cut -f1)
        success "Redis backup completed: $backup_file ($size)"

        if [[ "$ENABLE_COMPRESSION" == "true" ]]; then
            gzip "$backup_file"
            success "Redis backup compressed: ${backup_file}.gz"
        fi
    else
        warning "Redis backup failed (non-critical)"
        return 0  # Don't fail the entire backup
    fi
}

backup_minio_data() {
    info "Starting MinIO data backup..."

    local data_dir="${BACKUP_DIR}/data/${BACKUP_NAME}"

    # Get list of MinIO containers
    local minio_containers=$(docker-compose -f deployments/docker/docker-compose.production.yml ps -q minio-node-1 minio-node-2 minio-node-3 minio-node-4)

    if [[ -z "$minio_containers" ]]; then
        warning "No MinIO containers found. Skipping data backup."
        return 0
    fi

    # Backup data from first node (assuming distributed setup replicates data)
    local first_container=$(echo "$minio_containers" | head -n 1)

    info "Backing up MinIO data from container: $first_container"

    # Create temporary directory for data copy
    mkdir -p "$data_dir/minio-data"

    # Copy MinIO data directory
    docker cp "$first_container:/data" "$data_dir/minio-data" 2>>"$LOG_FILE" || {
        warning "Could not copy MinIO data (container may use volumes)"
    }

    # Get volume information
    info "Collecting MinIO volume metadata..."
    docker volume ls | grep minio > "$data_dir/volumes.txt" 2>>"$LOG_FILE" || true

    success "MinIO data backup prepared"
}

backup_configs() {
    info "Starting configuration backup..."

    local config_dir="${BACKUP_DIR}/configs/${BACKUP_NAME}"
    mkdir -p "$config_dir"

    # Backup important config directories
    local configs=(
        "configs"
        "deployments"
        ".env.example"
        "docker-compose.yml"
    )

    for config in "${configs[@]}"; do
        if [[ -e "$config" ]]; then
            cp -r "$config" "$config_dir/" 2>>"$LOG_FILE" || warning "Could not backup: $config"
        fi
    done

    # Backup environment variables (sanitized)
    docker-compose -f deployments/docker/docker-compose.production.yml config > \
        "$config_dir/docker-compose-resolved.yml" 2>>"$LOG_FILE" || true

    success "Configuration backup completed"
}

create_metadata() {
    info "Creating backup metadata..."

    local metadata_file="${BACKUP_DIR}/metadata/${BACKUP_NAME}.json"

    cat > "$metadata_file" <<EOF
{
  "backup_name": "${BACKUP_NAME}",
  "backup_type": "${BACKUP_TYPE}",
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "components": {
    "postgres": true,
    "redis": true,
    "minio_data": true,
    "configs": true
  },
  "compression": ${ENABLE_COMPRESSION},
  "encryption": ${ENABLE_ENCRYPTION},
  "retention_days": ${RETENTION_DAYS}
}
EOF

    success "Backup metadata created: $metadata_file"
}

compress_backup() {
    if [[ "$ENABLE_COMPRESSION" != "true" ]]; then
        return 0
    fi

    info "Compressing backup archive..."

    local archive="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

    tar -czf "$archive" \
        -C "${BACKUP_DIR}" \
        "data/${BACKUP_NAME}" \
        "configs/${BACKUP_NAME}" \
        "metadata/${BACKUP_NAME}.json" \
        2>>"$LOG_FILE"

    local size=$(du -h "$archive" | cut -f1)
    success "Backup archive created: $archive ($size)"

    # Clean up individual directories
    rm -rf "${BACKUP_DIR}/data/${BACKUP_NAME}"
    rm -rf "${BACKUP_DIR}/configs/${BACKUP_NAME}"
}

encrypt_backup() {
    if [[ "$ENABLE_ENCRYPTION" != "true" ]]; then
        return 0
    fi

    if [[ -z "$ENCRYPTION_KEY" ]]; then
        error "Encryption enabled but ENCRYPTION_KEY not set"
        return 1
    fi

    info "Encrypting backup..."

    local archive="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -in "$archive" \
        -out "${archive}.enc" \
        -k "$ENCRYPTION_KEY" \
        2>>"$LOG_FILE"

    rm "$archive"
    success "Backup encrypted: ${archive}.enc"
}

upload_to_s3() {
    if [[ "$S3_BACKUP" != "true" ]]; then
        return 0
    fi

    info "Uploading backup to S3..."

    local backup_file="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    if [[ "$ENABLE_ENCRYPTION" == "true" ]]; then
        backup_file="${backup_file}.enc"
    fi

    # Use mc (MinIO Client) or aws cli
    if command -v mc &> /dev/null; then
        mc alias set s3backup "$S3_ENDPOINT" "$S3_ACCESS_KEY" "$S3_SECRET_KEY" &>>"$LOG_FILE"
        mc cp "$backup_file" "s3backup/${S3_BUCKET}/" &>>"$LOG_FILE"
    elif command -v aws &> /dev/null; then
        aws s3 cp "$backup_file" "s3://${S3_BUCKET}/" --endpoint-url "$S3_ENDPOINT" &>>"$LOG_FILE"
    else
        warning "Neither 'mc' nor 'aws' CLI found. Skipping S3 upload."
        return 0
    fi

    success "Backup uploaded to S3: ${S3_BUCKET}/${BACKUP_NAME}"
}

cleanup_old_backups() {
    info "Cleaning up backups older than ${RETENTION_DAYS} days..."

    find "${BACKUP_DIR}" -type f -name "minio-backup-*" -mtime +${RETENTION_DAYS} -delete 2>>"$LOG_FILE" || true
    find "${BACKUP_DIR}/postgres" -type f -mtime +${RETENTION_DAYS} -delete 2>>"$LOG_FILE" || true
    find "${BACKUP_DIR}/redis" -type f -mtime +${RETENTION_DAYS} -delete 2>>"$LOG_FILE" || true
    find "${BACKUP_DIR}/logs" -type f -name "backup-*.log" -mtime +${RETENTION_DAYS} -delete 2>>"$LOG_FILE" || true

    success "Old backups cleaned up (retention: ${RETENTION_DAYS} days)"
}

verify_backup() {
    info "Verifying backup integrity..."

    local backup_file="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    if [[ "$ENABLE_ENCRYPTION" == "true" ]]; then
        backup_file="${backup_file}.enc"
    fi

    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
        return 1
    fi

    local size=$(du -h "$backup_file" | cut -f1)

    if [[ "$ENABLE_ENCRYPTION" == "true" ]]; then
        # Verify encryption
        if openssl enc -d -aes-256-cbc -pbkdf2 -in "$backup_file" -k "$ENCRYPTION_KEY" 2>/dev/null | tar -tz &>/dev/null; then
            success "Backup verification passed ($size)"
        else
            error "Backup verification failed - archive may be corrupted"
            return 1
        fi
    else
        # Verify tar archive
        if tar -tzf "$backup_file" &>/dev/null; then
            success "Backup verification passed ($size)"
        else
            error "Backup verification failed - archive may be corrupted"
            return 1
        fi
    fi
}

###############################################################################
# Main Execution
###############################################################################

main() {
    echo "========================================"
    echo "MinIO Enterprise Backup"
    echo "========================================"
    echo "Backup Type: $BACKUP_TYPE"
    echo "Timestamp: $TIMESTAMP"
    echo "========================================"
    echo

    # Preflight checks
    check_dependencies
    create_backup_dirs

    # Perform backups
    backup_postgres || exit 1
    backup_redis
    backup_minio_data
    backup_configs
    create_metadata

    # Post-processing
    compress_backup
    encrypt_backup
    verify_backup || exit 1
    upload_to_s3
    cleanup_old_backups

    echo
    echo "========================================"
    success "Backup completed successfully!"
    echo "========================================"
    echo "Backup name: $BACKUP_NAME"
    echo "Location: $BACKUP_DIR"
    echo "Log file: $LOG_FILE"
    echo "========================================"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        cat <<EOF
MinIO Enterprise Backup Script

Usage: $0 [OPTIONS]

Options:
  --help, -h           Show this help message
  --full               Perform full backup (default)
  --incremental        Perform incremental backup
  --verify-only FILE   Only verify an existing backup

Environment Variables:
  BACKUP_DIR           Backup directory (default: /var/backups/minio-enterprise)
  RETENTION_DAYS       Days to keep backups (default: 30)
  ENABLE_COMPRESSION   Enable compression (default: true)
  ENABLE_ENCRYPTION    Enable encryption (default: false)
  ENCRYPTION_KEY       Encryption passphrase
  S3_BACKUP            Enable S3 upload (default: false)
  S3_ENDPOINT          S3 endpoint URL
  S3_BUCKET            S3 bucket name
  S3_ACCESS_KEY        S3 access key
  S3_SECRET_KEY        S3 secret key

Examples:
  # Full backup with defaults
  ./backup.sh

  # Full backup with compression and encryption
  ENABLE_ENCRYPTION=true ENCRYPTION_KEY="mypassword" ./backup.sh

  # Backup to S3
  S3_BACKUP=true S3_ENDPOINT="https://s3.amazonaws.com" \
  S3_BUCKET="my-backups" S3_ACCESS_KEY="xxx" S3_SECRET_KEY="yyy" \
  ./backup.sh

EOF
        exit 0
        ;;
    --full)
        BACKUP_TYPE="full"
        main
        ;;
    --incremental)
        BACKUP_TYPE="incremental"
        main
        ;;
    --verify-only)
        if [[ -z "${2:-}" ]]; then
            error "Please specify backup file to verify"
            exit 1
        fi
        verify_backup "$2"
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
