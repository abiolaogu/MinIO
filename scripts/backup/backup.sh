#!/bin/bash
# MinIO Enterprise Backup Script
# Version: 1.0.0
# Description: Automated backup script for MinIO Enterprise with support for
#              full and incremental backups, encryption, compression, and retention policies

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load configuration
if [ -f "$SCRIPT_DIR/backup.conf" ]; then
    source "$SCRIPT_DIR/backup.conf"
else
    echo "Warning: backup.conf not found, using defaults"
fi

# Default configuration (can be overridden in backup.conf)
BACKUP_DIR="${BACKUP_DIR:-/var/backups/minio-enterprise}"
BACKUP_TYPE="${BACKUP_TYPE:-full}"  # full or incremental
RETENTION_DAYS="${RETENTION_DAYS:-30}"
COMPRESSION="${COMPRESSION:-true}"
ENCRYPTION="${ENCRYPTION:-true}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"
S3_BACKUP="${S3_BACKUP:-false}"
S3_BUCKET="${S3_BUCKET:-}"
S3_ENDPOINT="${S3_ENDPOINT:-}"
NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-}"
LOG_FILE="${LOG_FILE:-/var/log/minio-backup.log}"

# Docker compose file
COMPOSE_FILE="${PROJECT_ROOT}/deployments/docker/docker-compose.production.yml"

# Timestamp for backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="minio-backup-${BACKUP_TYPE}-${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# ============================================================
# Utility Functions
# ============================================================

check_dependencies() {
    log_info "Checking dependencies..."

    local deps=("docker" "docker-compose" "pg_dump" "tar" "gzip")

    if [ "$ENCRYPTION" = "true" ]; then
        deps+=("openssl")
    fi

    if [ "$S3_BACKUP" = "true" ]; then
        deps+=("aws")
    fi

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done

    log_info "All dependencies satisfied"
}

create_backup_directory() {
    log_info "Creating backup directory: $BACKUP_PATH"
    mkdir -p "$BACKUP_PATH"/{minio,postgres,redis,configs,metadata}
}

get_last_backup() {
    local last_backup=$(find "$BACKUP_DIR" -maxdepth 1 -name "minio-backup-*" -type d | sort -r | head -n 1)
    echo "$last_backup"
}

# ============================================================
# Backup Functions
# ============================================================

backup_minio_data() {
    log_info "Backing up MinIO object data..."

    # Get list of volumes from docker-compose
    local volumes=$(docker-compose -f "$COMPOSE_FILE" config --volumes | grep minio.*-data)

    for volume in $volumes; do
        log_info "Backing up volume: $volume"

        # Create volume backup using docker
        docker run --rm \
            -v "${volume}:/data:ro" \
            -v "${BACKUP_PATH}/minio:/backup" \
            alpine:latest \
            tar czf "/backup/${volume}.tar.gz" -C /data .

        if [ $? -eq 0 ]; then
            log_info "Successfully backed up volume: $volume"
        else
            log_error "Failed to backup volume: $volume"
            return 1
        fi
    done
}

backup_minio_incremental() {
    log_info "Performing incremental MinIO backup..."

    local last_backup=$(get_last_backup)
    if [ -z "$last_backup" ]; then
        log_warn "No previous backup found, performing full backup instead"
        backup_minio_data
        return $?
    fi

    log_info "Last backup: $last_backup"

    # Get list of volumes
    local volumes=$(docker-compose -f "$COMPOSE_FILE" config --volumes | grep minio.*-data)

    for volume in $volumes; do
        log_info "Performing incremental backup for volume: $volume"

        # Use rsync for incremental backup
        docker run --rm \
            -v "${volume}:/data:ro" \
            -v "${BACKUP_PATH}/minio:/backup" \
            -v "${last_backup}/minio:/last-backup:ro" \
            instrumentisto/rsync-ssh:latest \
            rsync -av --delete --link-dest=/last-backup/"${volume}.tar.gz" \
            /data/ "/backup/${volume}/"

        # Create compressed archive
        docker run --rm \
            -v "${BACKUP_PATH}/minio:/backup" \
            alpine:latest \
            tar czf "/backup/${volume}.tar.gz" -C "/backup/${volume}" .

        # Remove uncompressed directory
        docker run --rm \
            -v "${BACKUP_PATH}/minio:/backup" \
            alpine:latest \
            rm -rf "/backup/${volume}"
    done
}

backup_postgresql() {
    log_info "Backing up PostgreSQL database..."

    # Get PostgreSQL credentials from environment or .env file
    local postgres_user="${POSTGRES_USER:-minio}"
    local postgres_db="${POSTGRES_DB:-minio_enterprise}"
    local postgres_password="${POSTGRES_PASSWORD:-minio_secure_password}"

    # Backup PostgreSQL using pg_dump through docker exec
    docker-compose -f "$COMPOSE_FILE" exec -T postgres \
        pg_dump -U "$postgres_user" -d "$postgres_db" \
        > "${BACKUP_PATH}/postgres/minio_enterprise.sql"

    if [ $? -eq 0 ]; then
        log_info "PostgreSQL backup completed"

        # Compress the SQL dump
        gzip "${BACKUP_PATH}/postgres/minio_enterprise.sql"
        log_info "PostgreSQL backup compressed"
    else
        log_error "PostgreSQL backup failed"
        return 1
    fi
}

backup_redis() {
    log_info "Backing up Redis data..."

    # Trigger Redis BGSAVE
    docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli BGSAVE

    # Wait for BGSAVE to complete
    sleep 2

    # Copy RDB file from Redis container
    docker cp $(docker-compose -f "$COMPOSE_FILE" ps -q redis):/data/dump.rdb \
        "${BACKUP_PATH}/redis/dump.rdb"

    if [ $? -eq 0 ]; then
        log_info "Redis backup completed"

        # Compress the RDB file
        gzip "${BACKUP_PATH}/redis/dump.rdb"
        log_info "Redis backup compressed"
    else
        log_error "Redis backup failed"
        return 1
    fi
}

backup_configs() {
    log_info "Backing up configuration files..."

    # Copy configuration files
    cp -r "${PROJECT_ROOT}/configs" "${BACKUP_PATH}/configs/"
    cp -r "${PROJECT_ROOT}/deployments" "${BACKUP_PATH}/configs/"

    # Remove sensitive .env file if exists (shouldn't be in configs, but check anyway)
    find "${BACKUP_PATH}/configs" -name ".env" -delete

    log_info "Configuration backup completed"
}

create_metadata() {
    log_info "Creating backup metadata..."

    cat > "${BACKUP_PATH}/metadata/backup_info.json" <<EOF
{
  "backup_name": "${BACKUP_NAME}",
  "backup_type": "${BACKUP_TYPE}",
  "timestamp": "${TIMESTAMP}",
  "date": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "version": "1.0.0",
  "components": {
    "minio": true,
    "postgresql": true,
    "redis": true,
    "configs": true
  },
  "compression": ${COMPRESSION},
  "encryption": ${ENCRYPTION}
}
EOF

    # Create checksums
    find "$BACKUP_PATH" -type f ! -path "*/metadata/*" -exec sha256sum {} \; \
        > "${BACKUP_PATH}/metadata/checksums.txt"

    log_info "Metadata created"
}

compress_backup() {
    if [ "$COMPRESSION" = "false" ]; then
        log_info "Compression disabled, skipping"
        return 0
    fi

    log_info "Compressing backup archive..."

    cd "$BACKUP_DIR"
    tar czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"

    if [ $? -eq 0 ]; then
        log_info "Backup compressed successfully"

        # Remove uncompressed directory
        rm -rf "$BACKUP_NAME"

        # Update backup path
        BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    else
        log_error "Backup compression failed"
        return 1
    fi
}

encrypt_backup() {
    if [ "$ENCRYPTION" = "false" ]; then
        log_info "Encryption disabled, skipping"
        return 0
    fi

    if [ -z "$ENCRYPTION_KEY" ]; then
        log_error "Encryption enabled but ENCRYPTION_KEY not set"
        return 1
    fi

    log_info "Encrypting backup..."

    local encrypted_file="${BACKUP_PATH}.enc"

    openssl enc -aes-256-cbc -salt -pbkdf2 -in "$BACKUP_PATH" -out "$encrypted_file" -k "$ENCRYPTION_KEY"

    if [ $? -eq 0 ]; then
        log_info "Backup encrypted successfully"

        # Remove unencrypted file
        rm -f "$BACKUP_PATH"

        # Update backup path
        BACKUP_PATH="$encrypted_file"
    else
        log_error "Backup encryption failed"
        return 1
    fi
}

upload_to_s3() {
    if [ "$S3_BACKUP" = "false" ]; then
        log_info "S3 backup disabled, skipping"
        return 0
    fi

    if [ -z "$S3_BUCKET" ]; then
        log_error "S3 backup enabled but S3_BUCKET not set"
        return 1
    fi

    log_info "Uploading backup to S3..."

    local s3_path="s3://${S3_BUCKET}/minio-backups/$(basename $BACKUP_PATH)"

    if [ -n "$S3_ENDPOINT" ]; then
        aws s3 cp "$BACKUP_PATH" "$s3_path" --endpoint-url "$S3_ENDPOINT"
    else
        aws s3 cp "$BACKUP_PATH" "$s3_path"
    fi

    if [ $? -eq 0 ]; then
        log_info "Backup uploaded to S3: $s3_path"
    else
        log_error "S3 upload failed"
        return 1
    fi
}

cleanup_old_backups() {
    log_info "Cleaning up old backups (retention: ${RETENTION_DAYS} days)..."

    local count=0
    while IFS= read -r backup; do
        rm -rf "$backup"
        count=$((count + 1))
        log_info "Removed old backup: $(basename $backup)"
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name "minio-backup-*" -type d -o -name "minio-backup-*.tar.gz*" -mtime +"$RETENTION_DAYS")

    log_info "Removed $count old backup(s)"
}

verify_backup() {
    log_info "Verifying backup integrity..."

    # Check if backup file exists and is not empty
    if [ ! -f "$BACKUP_PATH" ] || [ ! -s "$BACKUP_PATH" ]; then
        log_error "Backup file is missing or empty"
        return 1
    fi

    local size=$(du -h "$BACKUP_PATH" | cut -f1)
    log_info "Backup size: $size"

    # Verify checksums if available
    if [ -f "${BACKUP_PATH}/metadata/checksums.txt" ]; then
        cd "${BACKUP_PATH}"
        sha256sum -c "metadata/checksums.txt"
        if [ $? -eq 0 ]; then
            log_info "Checksum verification passed"
        else
            log_error "Checksum verification failed"
            return 1
        fi
    fi

    log_info "Backup verification completed"
}

send_notification() {
    local status=$1
    local message=$2

    if [ -z "$NOTIFICATION_EMAIL" ]; then
        return 0
    fi

    local subject="MinIO Backup ${status}: ${BACKUP_NAME}"

    echo "$message" | mail -s "$subject" "$NOTIFICATION_EMAIL" || true

    log_info "Notification sent to $NOTIFICATION_EMAIL"
}

# ============================================================
# Main Execution
# ============================================================

main() {
    log_info "======================================"
    log_info "MinIO Enterprise Backup Script"
    log_info "Backup Type: $BACKUP_TYPE"
    log_info "Timestamp: $TIMESTAMP"
    log_info "======================================"

    # Check dependencies
    if ! check_dependencies; then
        log_error "Dependency check failed"
        exit 1
    fi

    # Create backup directory
    create_backup_directory

    # Perform backups
    local backup_failed=false

    # MinIO data backup
    if [ "$BACKUP_TYPE" = "incremental" ]; then
        backup_minio_incremental || backup_failed=true
    else
        backup_minio_data || backup_failed=true
    fi

    # PostgreSQL backup
    backup_postgresql || backup_failed=true

    # Redis backup
    backup_redis || backup_failed=true

    # Configuration backup
    backup_configs || backup_failed=true

    # Create metadata
    create_metadata

    if [ "$backup_failed" = "true" ]; then
        log_error "One or more backup operations failed"
        send_notification "FAILED" "Backup completed with errors. Check logs for details."
        exit 1
    fi

    # Compress backup
    compress_backup || {
        log_error "Backup compression failed"
        send_notification "FAILED" "Backup compression failed"
        exit 1
    }

    # Encrypt backup
    encrypt_backup || {
        log_error "Backup encryption failed"
        send_notification "FAILED" "Backup encryption failed"
        exit 1
    }

    # Upload to S3
    upload_to_s3 || log_warn "S3 upload failed (backup still available locally)"

    # Verify backup
    # verify_backup || log_warn "Backup verification failed"

    # Cleanup old backups
    cleanup_old_backups

    log_info "======================================"
    log_info "Backup completed successfully!"
    log_info "Backup location: $BACKUP_PATH"
    log_info "======================================"

    send_notification "SUCCESS" "Backup completed successfully. Location: $BACKUP_PATH"
}

# Run main function
main "$@"
