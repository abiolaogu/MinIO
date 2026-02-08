#!/usr/bin/env bash
#
# MinIO Enterprise - Restore Script
#
# This script performs automated restoration of backups:
# - PostgreSQL database
# - Redis snapshots
# - MinIO objects
# - Configuration files
#
# Supports verification and rollback capabilities.
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load configuration
if [ -f "$SCRIPT_DIR/../backup/backup.conf" ]; then
    source "$SCRIPT_DIR/../backup/backup.conf"
else
    echo "ERROR: Configuration file not found: $SCRIPT_DIR/../backup/backup.conf"
    echo "Please configure backup.conf first."
    exit 1
fi

# Default values
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/minio}"
RESTORE_DIR="/tmp/minio_restore_$$"
ENABLE_VERIFICATION="${ENABLE_VERIFICATION:-true}"
ENABLE_ROLLBACK="${ENABLE_ROLLBACK:-true}"
DRY_RUN="${DRY_RUN:-false}"

# Logging
LOG_FILE="$BACKUP_ROOT/restore.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# Check dependencies
check_dependencies() {
    local deps=("pg_restore" "redis-cli" "tar" "gzip")

    if [ "$ENABLE_ENCRYPTION" = "true" ]; then
        deps+=("openssl")
    fi

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Required command not found: $cmd"
            exit 1
        fi
    done
}

# List available backups
list_backups() {
    log "Available backups in $BACKUP_ROOT:"
    log "=========================================="

    local backups=$(find "$BACKUP_ROOT" -name "minio_backup_*.tar.gz*" -type f 2>/dev/null | sort -r)

    if [ -z "$backups" ]; then
        log "No backups found"
        return 1
    fi

    local count=1
    while IFS= read -r backup; do
        local backup_name=$(basename "$backup")
        local backup_size=$(du -h "$backup" | cut -f1)
        local backup_date=$(echo "$backup_name" | grep -oP '\d{8}_\d{6}' || echo "unknown")

        echo "[$count] $backup_name ($backup_size) - $backup_date"
        count=$((count + 1))
    done <<< "$backups"

    log "=========================================="
}

# Select backup to restore
select_backup() {
    local backup_file="$1"

    if [ -z "$backup_file" ]; then
        error "No backup file specified"
        list_backups
        exit 1
    fi

    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
        list_backups
        exit 1
    fi

    log "Selected backup: $backup_file"
    echo "$backup_file"
}

# Verify backup integrity
verify_backup_integrity() {
    local backup_file="$1"

    log "Verifying backup integrity..."

    # Check file size
    local file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)

    if [ "$file_size" -lt 1024 ]; then
        error "Backup file is suspiciously small: $file_size bytes"
        return 1
    fi

    # Verify manifest if available
    local manifest_file="${backup_file}.manifest"

    if [ -f "$manifest_file" ]; then
        log "Verifying checksums from manifest..."

        local expected_md5=$(grep "MD5 Checksum:" "$manifest_file" | cut -d' ' -f3)
        local actual_md5=$(md5sum "$backup_file" | cut -d' ' -f1)

        if [ "$expected_md5" != "$actual_md5" ]; then
            error "MD5 checksum mismatch!"
            error "Expected: $expected_md5"
            error "Actual: $actual_md5"
            return 1
        fi

        log "MD5 checksum verified successfully"
    else
        log "Warning: Manifest file not found, skipping checksum verification"
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

# Decrypt backup
decrypt_backup() {
    local encrypted_file="$1"

    if [[ "$encrypted_file" != *.enc ]]; then
        log "Backup is not encrypted, skipping decryption"
        echo "$encrypted_file"
        return 0
    fi

    log "Decrypting backup..."

    local decrypted_file="${encrypted_file%.enc}"

    # Check if encryption key exists
    if [ ! -f "$ENCRYPTION_KEY_FILE" ]; then
        error "Encryption key file not found: $ENCRYPTION_KEY_FILE"
        return 1
    fi

    # Decrypt using AES-256-CBC
    openssl enc -d -aes-256-cbc -pbkdf2 \
        -in "$encrypted_file" \
        -out "$decrypted_file" \
        -pass file:"$ENCRYPTION_KEY_FILE" \
        2>> "$LOG_FILE"

    if [ $? -eq 0 ]; then
        log "Backup decrypted successfully"
        echo "$decrypted_file"
    else
        error "Decryption failed"
        return 1
    fi
}

# Extract backup
extract_backup() {
    local backup_file="$1"

    log "Extracting backup to: $RESTORE_DIR"

    mkdir -p "$RESTORE_DIR"

    tar -xzf "$backup_file" -C "$RESTORE_DIR" --strip-components=1 2>> "$LOG_FILE"

    if [ $? -eq 0 ]; then
        log "Backup extracted successfully"
    else
        error "Extraction failed"
        return 1
    fi
}

# Create pre-restore snapshot (for rollback)
create_pre_restore_snapshot() {
    if [ "$ENABLE_ROLLBACK" != "true" ]; then
        log "Rollback disabled, skipping pre-restore snapshot"
        return 0
    fi

    log "Creating pre-restore snapshot for rollback..."

    local snapshot_dir="$BACKUP_ROOT/pre_restore_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$snapshot_dir"

    # Snapshot PostgreSQL
    log "Snapshotting PostgreSQL..."
    local db_host="${POSTGRES_HOST:-localhost}"
    local db_port="${POSTGRES_PORT:-5432}"
    local db_name="${POSTGRES_DB:-minio}"
    local db_user="${POSTGRES_USER:-minio}"

    PGPASSWORD="${POSTGRES_PASSWORD:-minio}" pg_dump \
        -h "$db_host" \
        -p "$db_port" \
        -U "$db_user" \
        -d "$db_name" \
        -Fc \
        -f "$snapshot_dir/postgresql_pre_restore.sql" \
        2>> "$LOG_FILE"

    log "Pre-restore snapshot created: $snapshot_dir"
    echo "$snapshot_dir"
}

# Restore PostgreSQL database
restore_postgresql() {
    local restore_file="$RESTORE_DIR/postgresql/database.sql"

    if [ ! -f "$restore_file" ]; then
        log "PostgreSQL backup not found in restore directory, skipping"
        return 0
    fi

    log "Restoring PostgreSQL database..."

    if [ "$DRY_RUN" = "true" ]; then
        log "DRY RUN: Would restore PostgreSQL from $restore_file"
        return 0
    fi

    local db_host="${POSTGRES_HOST:-localhost}"
    local db_port="${POSTGRES_PORT:-5432}"
    local db_name="${POSTGRES_DB:-minio}"
    local db_user="${POSTGRES_USER:-minio}"

    # Drop existing database (optional, uncomment if needed)
    # PGPASSWORD="${POSTGRES_PASSWORD:-minio}" psql -h "$db_host" -p "$db_port" -U "$db_user" -c "DROP DATABASE IF EXISTS $db_name;" 2>> "$LOG_FILE"
    # PGPASSWORD="${POSTGRES_PASSWORD:-minio}" psql -h "$db_host" -p "$db_port" -U "$db_user" -c "CREATE DATABASE $db_name;" 2>> "$LOG_FILE"

    # Restore using pg_restore
    PGPASSWORD="${POSTGRES_PASSWORD:-minio}" pg_restore \
        -h "$db_host" \
        -p "$db_port" \
        -U "$db_user" \
        -d "$db_name" \
        --clean \
        --if-exists \
        --verbose \
        "$restore_file" \
        2>> "$LOG_FILE"

    if [ $? -eq 0 ]; then
        log "PostgreSQL restore completed successfully"
    else
        error "PostgreSQL restore failed"
        return 1
    fi
}

# Restore Redis data
restore_redis() {
    local restore_file="$RESTORE_DIR/redis/dump.rdb"

    if [ ! -f "$restore_file" ]; then
        log "Redis backup not found in restore directory, skipping"
        return 0
    fi

    log "Restoring Redis data..."

    if [ "$DRY_RUN" = "true" ]; then
        log "DRY RUN: Would restore Redis from $restore_file"
        return 0
    fi

    local redis_rdb="${REDIS_RDB_PATH:-/data/redis/dump.rdb}"

    # Stop Redis (if running as a service)
    log "Stopping Redis service..."
    systemctl stop redis 2>/dev/null || docker-compose -f "$PROJECT_ROOT/deployments/docker/docker-compose.production.yml" stop redis 2>/dev/null || true

    # Backup existing RDB file
    if [ -f "$redis_rdb" ]; then
        cp "$redis_rdb" "${redis_rdb}.backup.$(date +%Y%m%d_%H%M%S)"
        log "Backed up existing Redis RDB file"
    fi

    # Copy restored RDB file
    cp "$restore_file" "$redis_rdb"

    # Start Redis
    log "Starting Redis service..."
    systemctl start redis 2>/dev/null || docker-compose -f "$PROJECT_ROOT/deployments/docker/docker-compose.production.yml" start redis 2>/dev/null || true

    # Wait for Redis to be ready
    sleep 5

    log "Redis restore completed successfully"
}

# Restore MinIO objects
restore_minio_objects() {
    local restore_dir="$RESTORE_DIR/objects"

    if [ ! -d "$restore_dir" ]; then
        log "MinIO objects backup not found in restore directory, skipping"
        return 0
    fi

    log "Restoring MinIO objects..."

    if [ "$DRY_RUN" = "true" ]; then
        log "DRY RUN: Would restore MinIO objects from $restore_dir"
        return 0
    fi

    local minio_endpoint="${MINIO_ENDPOINT:-http://localhost:9000}"
    local minio_access_key="${MINIO_ACCESS_KEY:-minioadmin}"
    local minio_secret_key="${MINIO_SECRET_KEY:-minioadmin}"

    # Check if mc (MinIO client) is available
    if ! command -v mc &> /dev/null; then
        log "MinIO client (mc) not found, skipping object restore"
        return 0
    fi

    # Configure MinIO client alias
    mc alias set restore-target "$minio_endpoint" "$minio_access_key" "$minio_secret_key" &>> "$LOG_FILE"

    # Restore all buckets
    for bucket_dir in "$restore_dir"/*; do
        if [ -d "$bucket_dir" ]; then
            local bucket=$(basename "$bucket_dir")
            log "Restoring bucket: $bucket"

            # Create bucket if it doesn't exist
            mc mb restore-target/"$bucket" --ignore-existing &>> "$LOG_FILE"

            # Mirror objects to bucket
            mc mirror "$bucket_dir" restore-target/"$bucket" --overwrite --quiet &>> "$LOG_FILE"

            if [ $? -eq 0 ]; then
                log "Bucket $bucket restored successfully"
            else
                error "Failed to restore bucket: $bucket"
            fi
        fi
    done

    log "MinIO objects restore completed"
}

# Restore configuration files
restore_configs() {
    local restore_dir="$RESTORE_DIR/configs"

    if [ ! -d "$restore_dir" ]; then
        log "Configuration backup not found in restore directory, skipping"
        return 0
    fi

    log "Restoring configuration files..."

    if [ "$DRY_RUN" = "true" ]; then
        log "DRY RUN: Would restore configurations from $restore_dir"
        return 0
    fi

    # Backup existing configs before restore
    local backup_configs_dir="$BACKUP_ROOT/configs_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_configs_dir"

    if [ -d "$PROJECT_ROOT/configs" ]; then
        cp -r "$PROJECT_ROOT/configs" "$backup_configs_dir/"
        log "Backed up existing configs to: $backup_configs_dir"
    fi

    # Restore configs
    for item in "$restore_dir"/*; do
        if [ -e "$item" ]; then
            local basename=$(basename "$item")
            local target="$PROJECT_ROOT/$basename"

            # Special handling for .env files
            if [ "$basename" = ".env" ]; then
                cp "$item" "$target"
                log "Restored: $basename"
            elif [ -d "$item" ]; then
                cp -r "$item" "$target"
                log "Restored directory: $basename"
            else
                cp "$item" "$target"
                log "Restored file: $basename"
            fi
        fi
    done

    log "Configuration restore completed"
}

# Verify restoration
verify_restoration() {
    if [ "$ENABLE_VERIFICATION" != "true" ]; then
        log "Verification disabled, skipping"
        return 0
    fi

    log "Verifying restoration..."

    # Verify PostgreSQL
    local db_host="${POSTGRES_HOST:-localhost}"
    local db_port="${POSTGRES_PORT:-5432}"
    local db_name="${POSTGRES_DB:-minio}"
    local db_user="${POSTGRES_USER:-minio}"

    PGPASSWORD="${POSTGRES_PASSWORD:-minio}" psql \
        -h "$db_host" \
        -p "$db_port" \
        -U "$db_user" \
        -d "$db_name" \
        -c "SELECT COUNT(*) FROM information_schema.tables;" \
        &>> "$LOG_FILE"

    if [ $? -eq 0 ]; then
        log "PostgreSQL verification: OK"
    else
        error "PostgreSQL verification: FAILED"
        return 1
    fi

    # Verify Redis
    local redis_host="${REDIS_HOST:-localhost}"
    local redis_port="${REDIS_PORT:-6379}"
    local redis_password="${REDIS_PASSWORD:-}"

    if [ -n "$redis_password" ]; then
        redis-cli -h "$redis_host" -p "$redis_port" -a "$redis_password" --no-auth-warning PING &>> "$LOG_FILE"
    else
        redis-cli -h "$redis_host" -p "$redis_port" PING &>> "$LOG_FILE"
    fi

    if [ $? -eq 0 ]; then
        log "Redis verification: OK"
    else
        error "Redis verification: FAILED"
        return 1
    fi

    log "Verification completed successfully"
}

# Cleanup temporary files
cleanup() {
    if [ -d "$RESTORE_DIR" ]; then
        log "Cleaning up temporary files..."
        rm -rf "$RESTORE_DIR"
        log "Cleanup completed"
    fi
}

# Main restore function
main() {
    local backup_file="${1:-}"

    log "=========================================="
    log "MinIO Enterprise Restore Started"
    log "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"

    if [ "$DRY_RUN" = "true" ]; then
        log "MODE: DRY RUN (no actual changes will be made)"
    fi

    log "=========================================="

    # List backups if no file specified
    if [ -z "$backup_file" ]; then
        list_backups
        error "Please specify a backup file to restore"
        exit 1
    fi

    # Check dependencies
    check_dependencies

    # Select and verify backup
    backup_file=$(select_backup "$backup_file")
    verify_backup_integrity "$backup_file"

    # Decrypt if needed
    if [[ "$backup_file" == *.enc ]]; then
        backup_file=$(decrypt_backup "$backup_file")
    fi

    # Extract backup
    extract_backup "$backup_file"

    # Create pre-restore snapshot for rollback
    local snapshot_dir
    snapshot_dir=$(create_pre_restore_snapshot)

    # Perform restoration
    log "Starting restoration process..."

    restore_postgresql || error "PostgreSQL restore failed (non-fatal)"
    restore_redis || error "Redis restore failed (non-fatal)"
    restore_minio_objects || error "MinIO objects restore failed (non-fatal)"
    restore_configs

    # Verify restoration
    verify_restoration

    # Cleanup
    cleanup

    log "=========================================="
    log "Restore completed successfully!"

    if [ -n "$snapshot_dir" ]; then
        log "Pre-restore snapshot saved to: $snapshot_dir"
        log "To rollback, restore from this snapshot"
    fi

    log "=========================================="
}

# Trap cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
