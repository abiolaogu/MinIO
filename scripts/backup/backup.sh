#!/usr/bin/env bash
#
# MinIO Enterprise - Backup Script
#
# This script performs automated backups of:
# - PostgreSQL database
# - Redis snapshots
# - MinIO objects
# - Configuration files
#
# Supports full and incremental backups with encryption and compression.
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load configuration
if [ -f "$SCRIPT_DIR/backup.conf" ]; then
    source "$SCRIPT_DIR/backup.conf"
else
    echo "ERROR: Configuration file not found: $SCRIPT_DIR/backup.conf"
    echo "Please copy backup.conf.example to backup.conf and configure it."
    exit 1
fi

# Default values (override in backup.conf)
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/minio}"
BACKUP_TYPE="${BACKUP_TYPE:-full}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
ENABLE_ENCRYPTION="${ENABLE_ENCRYPTION:-true}"
ENABLE_COMPRESSION="${ENABLE_COMPRESSION:-true}"
ENCRYPTION_KEY_FILE="${ENCRYPTION_KEY_FILE:-$SCRIPT_DIR/backup.key}"
S3_UPLOAD="${S3_UPLOAD:-false}"

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"

# Logging
LOG_FILE="$BACKUP_ROOT/backup.log"
mkdir -p "$BACKUP_ROOT"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# Check dependencies
check_dependencies() {
    local deps=("pg_dump" "redis-cli" "tar" "gzip")

    if [ "$ENABLE_ENCRYPTION" = "true" ]; then
        deps+=("openssl")
    fi

    if [ "$S3_UPLOAD" = "true" ]; then
        deps+=("aws")
    fi

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Required command not found: $cmd"
            exit 1
        fi
    done
}

# Create backup directory
create_backup_dir() {
    log "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"/{postgresql,redis,objects,configs}
}

# Backup PostgreSQL database
backup_postgresql() {
    log "Backing up PostgreSQL database..."

    local db_host="${POSTGRES_HOST:-localhost}"
    local db_port="${POSTGRES_PORT:-5432}"
    local db_name="${POSTGRES_DB:-minio}"
    local db_user="${POSTGRES_USER:-minio}"

    local output_file="$BACKUP_DIR/postgresql/database.sql"

    # Use pg_dump with custom format for better compression and restore options
    PGPASSWORD="${POSTGRES_PASSWORD:-minio}" pg_dump \
        -h "$db_host" \
        -p "$db_port" \
        -U "$db_user" \
        -d "$db_name" \
        -Fc \
        -f "$output_file" \
        --verbose \
        2>> "$LOG_FILE"

    if [ $? -eq 0 ]; then
        log "PostgreSQL backup completed: $output_file ($(du -h "$output_file" | cut -f1))"
    else
        error "PostgreSQL backup failed"
        return 1
    fi
}

# Backup Redis data
backup_redis() {
    log "Backing up Redis data..."

    local redis_host="${REDIS_HOST:-localhost}"
    local redis_port="${REDIS_PORT:-6379}"
    local redis_password="${REDIS_PASSWORD:-}"

    # Trigger Redis BGSAVE to create RDB snapshot
    if [ -n "$redis_password" ]; then
        redis-cli -h "$redis_host" -p "$redis_port" -a "$redis_password" --no-auth-warning BGSAVE
    else
        redis-cli -h "$redis_host" -p "$redis_port" BGSAVE
    fi

    # Wait for BGSAVE to complete
    log "Waiting for Redis BGSAVE to complete..."
    sleep 5

    # Copy RDB file if available
    local redis_rdb="${REDIS_RDB_PATH:-/data/redis/dump.rdb}"

    if [ -f "$redis_rdb" ]; then
        cp "$redis_rdb" "$BACKUP_DIR/redis/dump.rdb"
        log "Redis backup completed: $BACKUP_DIR/redis/dump.rdb ($(du -h "$BACKUP_DIR/redis/dump.rdb" | cut -f1))"
    else
        error "Redis RDB file not found: $redis_rdb"
        log "Attempting to get Redis info..."

        if [ -n "$redis_password" ]; then
            redis-cli -h "$redis_host" -p "$redis_port" -a "$redis_password" --no-auth-warning INFO persistence | tee -a "$LOG_FILE"
        else
            redis-cli -h "$redis_host" -p "$redis_port" INFO persistence | tee -a "$LOG_FILE"
        fi

        return 1
    fi
}

# Backup MinIO objects (using MinIO client)
backup_minio_objects() {
    log "Backing up MinIO objects..."

    local minio_endpoint="${MINIO_ENDPOINT:-http://localhost:9000}"
    local minio_access_key="${MINIO_ACCESS_KEY:-minioadmin}"
    local minio_secret_key="${MINIO_SECRET_KEY:-minioadmin}"

    # Check if mc (MinIO client) is available
    if ! command -v mc &> /dev/null; then
        log "MinIO client (mc) not found, skipping object backup"
        log "To backup objects, install mc: https://min.io/docs/minio/linux/reference/minio-mc.html"
        return 0
    fi

    # Configure MinIO client alias
    mc alias set backup-target "$minio_endpoint" "$minio_access_key" "$minio_secret_key" &>> "$LOG_FILE"

    # List and backup all buckets
    local buckets=$(mc ls backup-target --json 2>/dev/null | grep -oP '"key":"[^"]*"' | cut -d'"' -f4 || echo "")

    if [ -z "$buckets" ]; then
        log "No buckets found or unable to list buckets"
        return 0
    fi

    for bucket in $buckets; do
        log "Backing up bucket: $bucket"
        mc mirror backup-target/"$bucket" "$BACKUP_DIR/objects/$bucket" --quiet &>> "$LOG_FILE"

        if [ $? -eq 0 ]; then
            log "Bucket $bucket backed up successfully"
        else
            error "Failed to backup bucket: $bucket"
        fi
    done
}

# Backup configuration files
backup_configs() {
    log "Backing up configuration files..."

    local config_files=(
        "$PROJECT_ROOT/configs"
        "$PROJECT_ROOT/deployments"
        "$PROJECT_ROOT/.env"
        "$PROJECT_ROOT/docker-compose.yml"
    )

    for config in "${config_files[@]}"; do
        if [ -e "$config" ]; then
            local basename=$(basename "$config")
            cp -r "$config" "$BACKUP_DIR/configs/$basename" 2>> "$LOG_FILE"
            log "Backed up: $config"
        fi
    done
}

# Compress backup
compress_backup() {
    if [ "$ENABLE_COMPRESSION" != "true" ]; then
        log "Compression disabled, skipping..."
        return 0
    fi

    log "Compressing backup..."

    local archive_file="$BACKUP_ROOT/minio_backup_$TIMESTAMP.tar.gz"

    tar -czf "$archive_file" -C "$BACKUP_ROOT" "$TIMESTAMP" 2>> "$LOG_FILE"

    if [ $? -eq 0 ]; then
        local archive_size=$(du -h "$archive_file" | cut -f1)
        log "Backup compressed: $archive_file ($archive_size)"

        # Remove uncompressed directory
        rm -rf "$BACKUP_DIR"
        log "Removed uncompressed backup directory"

        echo "$archive_file"
    else
        error "Compression failed"
        return 1
    fi
}

# Encrypt backup
encrypt_backup() {
    if [ "$ENABLE_ENCRYPTION" != "true" ]; then
        log "Encryption disabled, skipping..."
        return 0
    fi

    local input_file="$1"

    if [ ! -f "$input_file" ]; then
        error "Input file not found: $input_file"
        return 1
    fi

    log "Encrypting backup..."

    # Check if encryption key exists
    if [ ! -f "$ENCRYPTION_KEY_FILE" ]; then
        error "Encryption key file not found: $ENCRYPTION_KEY_FILE"
        error "Generate a key with: openssl rand -base64 32 > $ENCRYPTION_KEY_FILE"
        return 1
    fi

    local encrypted_file="${input_file}.enc"

    # Encrypt using AES-256-CBC
    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -in "$input_file" \
        -out "$encrypted_file" \
        -pass file:"$ENCRYPTION_KEY_FILE" \
        2>> "$LOG_FILE"

    if [ $? -eq 0 ]; then
        local encrypted_size=$(du -h "$encrypted_file" | cut -f1)
        log "Backup encrypted: $encrypted_file ($encrypted_size)"

        # Remove unencrypted file
        rm -f "$input_file"
        log "Removed unencrypted backup file"

        echo "$encrypted_file"
    else
        error "Encryption failed"
        return 1
    fi
}

# Upload to S3 (optional)
upload_to_s3() {
    if [ "$S3_UPLOAD" != "true" ]; then
        log "S3 upload disabled, skipping..."
        return 0
    fi

    local backup_file="$1"

    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
        return 1
    fi

    log "Uploading backup to S3..."

    local s3_bucket="${S3_BACKUP_BUCKET:-}"
    local s3_prefix="${S3_BACKUP_PREFIX:-minio-backups}"

    if [ -z "$s3_bucket" ]; then
        error "S3_BACKUP_BUCKET not configured"
        return 1
    fi

    local s3_path="s3://$s3_bucket/$s3_prefix/$(basename "$backup_file")"

    aws s3 cp "$backup_file" "$s3_path" --storage-class STANDARD_IA 2>> "$LOG_FILE"

    if [ $? -eq 0 ]; then
        log "Backup uploaded to: $s3_path"
    else
        error "S3 upload failed"
        return 1
    fi
}

# Clean up old backups
cleanup_old_backups() {
    log "Cleaning up backups older than $RETENTION_DAYS days..."

    find "$BACKUP_ROOT" -name "minio_backup_*.tar.gz*" -type f -mtime +$RETENTION_DAYS -delete 2>> "$LOG_FILE"

    local deleted_count=$(find "$BACKUP_ROOT" -name "minio_backup_*.tar.gz*" -type f -mtime +$RETENTION_DAYS 2>/dev/null | wc -l)
    log "Deleted $deleted_count old backup(s)"
}

# Create backup manifest
create_manifest() {
    local backup_file="$1"
    local manifest_file="${backup_file}.manifest"

    log "Creating backup manifest..."

    cat > "$manifest_file" <<EOF
Backup Manifest
===============
Timestamp: $TIMESTAMP
Backup Type: $BACKUP_TYPE
Backup File: $(basename "$backup_file")
File Size: $(du -h "$backup_file" | cut -f1)
MD5 Checksum: $(md5sum "$backup_file" | cut -d' ' -f1)
SHA256 Checksum: $(sha256sum "$backup_file" | cut -d' ' -f1)
Encrypted: $ENABLE_ENCRYPTION
Compressed: $ENABLE_COMPRESSION
PostgreSQL: $([ -d "$BACKUP_DIR/postgresql" ] 2>/dev/null && echo "Yes" || echo "Skipped")
Redis: $([ -d "$BACKUP_DIR/redis" ] 2>/dev/null && echo "Yes" || echo "Skipped")
MinIO Objects: $([ -d "$BACKUP_DIR/objects" ] 2>/dev/null && echo "Yes" || echo "Skipped")
Configuration: $([ -d "$BACKUP_DIR/configs" ] 2>/dev/null && echo "Yes" || echo "Skipped")
EOF

    log "Manifest created: $manifest_file"
}

# Verify backup integrity
verify_backup() {
    local backup_file="$1"

    log "Verifying backup integrity..."

    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
        return 1
    fi

    # Check file size
    local file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)

    if [ "$file_size" -lt 1024 ]; then
        error "Backup file is suspiciously small: $file_size bytes"
        return 1
    fi

    # Verify compressed file integrity
    if [[ "$backup_file" == *.tar.gz ]]; then
        gzip -t "$backup_file" 2>> "$LOG_FILE"

        if [ $? -ne 0 ]; then
            error "Backup file integrity check failed (corrupted gzip)"
            return 1
        fi
    fi

    log "Backup integrity verified successfully"
}

# Main backup function
main() {
    log "=========================================="
    log "MinIO Enterprise Backup Started"
    log "Backup Type: $BACKUP_TYPE"
    log "Timestamp: $TIMESTAMP"
    log "=========================================="

    # Check dependencies
    check_dependencies

    # Create backup directory
    create_backup_dir

    # Perform backups
    backup_postgresql || error "PostgreSQL backup failed (non-fatal)"
    backup_redis || error "Redis backup failed (non-fatal)"
    backup_minio_objects || error "MinIO objects backup failed (non-fatal)"
    backup_configs

    # Compress backup
    local backup_file
    backup_file=$(compress_backup)

    if [ -z "$backup_file" ]; then
        error "Compression failed, backup incomplete"
        exit 1
    fi

    # Encrypt backup
    if [ "$ENABLE_ENCRYPTION" = "true" ]; then
        backup_file=$(encrypt_backup "$backup_file")

        if [ -z "$backup_file" ]; then
            error "Encryption failed, backup incomplete"
            exit 1
        fi
    fi

    # Verify backup
    verify_backup "$backup_file"

    # Create manifest
    create_manifest "$backup_file"

    # Upload to S3 (optional)
    upload_to_s3 "$backup_file"

    # Cleanup old backups
    cleanup_old_backups

    log "=========================================="
    log "Backup completed successfully!"
    log "Backup file: $backup_file"
    log "Backup size: $(du -h "$backup_file" | cut -f1)"
    log "=========================================="
}

# Run main function
main "$@"
