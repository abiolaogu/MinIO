#!/bin/bash
# MinIO Enterprise - Restore Script
# Description: Automated restore script for MinIO cluster, PostgreSQL, Redis, and configurations
# Version: 1.0.0
# Date: 2026-02-07

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

#==============================================================================
# CONFIGURATION
#==============================================================================

# Default configuration
BACKUP_FILE="${BACKUP_FILE:-}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/minio}"
RESTORE_COMPONENTS="${RESTORE_COMPONENTS:-all}"  # all, postgres, redis, minio, config
DRY_RUN="${DRY_RUN:-false}"
VERIFY_BEFORE_RESTORE="${VERIFY_BEFORE_RESTORE:-true}"
CREATE_ROLLBACK="${CREATE_ROLLBACK:-true}"
FORCE_RESTORE="${FORCE_RESTORE:-false}"

# PostgreSQL configuration
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-minio}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"

# Redis configuration
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

# MinIO configuration
MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://localhost:9000}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-minioadmin}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-minioadmin}"

# Encryption
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"

# Timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESTORE_LOG="${BACKUP_DIR}/restore_${TIMESTAMP}.log"
ROLLBACK_DIR="${BACKUP_DIR}/rollback_${TIMESTAMP}"

#==============================================================================
# LOGGING FUNCTIONS
#==============================================================================

log() {
    local level=$1
    shift
    local message="$@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$RESTORE_LOG"
}

log_info() {
    log "INFO" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

log_warning() {
    log "WARNING" "$@"
}

#==============================================================================
# HELPER FUNCTIONS
#==============================================================================

check_dependencies() {
    log_info "Checking dependencies..."

    local deps=("pg_restore" "redis-cli" "tar" "gzip")

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' not found"
            exit 1
        fi
    done

    log_success "All dependencies satisfied"
}

validate_backup_file() {
    log_info "Validating backup file..."

    if [ -z "$BACKUP_FILE" ]; then
        log_error "BACKUP_FILE not specified"
        echo "Usage: $0 -f <backup_file>"
        echo ""
        echo "Available backups:"
        ls -lh "$BACKUP_DIR"/minio_backup_* 2>/dev/null || echo "No backups found"
        exit 1
    fi

    if [ ! -f "$BACKUP_FILE" ]; then
        log_error "Backup file not found: $BACKUP_FILE"
        exit 1
    fi

    local size=$(du -h "$BACKUP_FILE" | cut -f1)
    log_success "Backup file validated: $BACKUP_FILE ($size)"
}

verify_checksum() {
    if [ "$VERIFY_BEFORE_RESTORE" != "true" ]; then
        log_info "Checksum verification disabled"
        return 0
    fi

    log_info "Verifying backup checksum..."

    local checksum_file="${BACKUP_FILE}.sha256"

    if [ -f "$checksum_file" ]; then
        if sha256sum -c "$checksum_file" 2>> "$RESTORE_LOG"; then
            log_success "Checksum verification passed"
            return 0
        else
            log_error "Checksum verification failed"
            return 1
        fi
    else
        log_warning "Checksum file not found: $checksum_file"
        log_warning "Skipping checksum verification"
        return 0
    fi
}

decrypt_backup() {
    if [[ ! "$BACKUP_FILE" =~ \.enc$ ]]; then
        log_info "Backup is not encrypted"
        return 0
    fi

    if [ -z "$ENCRYPTION_KEY" ]; then
        log_error "Backup is encrypted but ENCRYPTION_KEY not set"
        exit 1
    fi

    log_info "Decrypting backup..."

    local decrypted="${BACKUP_FILE%.enc}"

    if openssl enc -aes-256-cbc -d -pbkdf2 -in "$BACKUP_FILE" -out "$decrypted" -k "$ENCRYPTION_KEY" 2>> "$RESTORE_LOG"; then
        log_success "Backup decrypted: $decrypted"
        BACKUP_FILE="$decrypted"
        return 0
    else
        log_error "Decryption failed"
        return 1
    fi
}

extract_backup() {
    log_info "Extracting backup archive..."

    local extract_dir="${BACKUP_DIR}/restore_temp_${TIMESTAMP}"
    mkdir -p "$extract_dir"

    if tar -xzf "$BACKUP_FILE" -C "$extract_dir" 2>> "$RESTORE_LOG"; then
        # Find the backup directory inside
        EXTRACTED_BACKUP=$(find "$extract_dir" -maxdepth 1 -type d -name "minio_backup_*" | head -n 1)

        if [ -z "$EXTRACTED_BACKUP" ]; then
            log_error "Could not find backup directory in archive"
            return 1
        fi

        log_success "Backup extracted to: $EXTRACTED_BACKUP"
        return 0
    else
        log_error "Extraction failed"
        return 1
    fi
}

confirm_restore() {
    if [ "$FORCE_RESTORE" = "true" ]; then
        log_warning "Force restore enabled, skipping confirmation"
        return 0
    fi

    echo ""
    echo "⚠️  WARNING: This will overwrite existing data!"
    echo ""
    echo "Backup file: $BACKUP_FILE"
    echo "Components to restore: $RESTORE_COMPONENTS"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        log_info "Restore cancelled by user"
        exit 0
    fi

    log_info "User confirmed restore operation"
}

create_rollback_backup() {
    if [ "$CREATE_ROLLBACK" != "true" ]; then
        log_info "Rollback backup disabled"
        return 0
    fi

    log_info "Creating rollback backup..."

    mkdir -p "$ROLLBACK_DIR"/{postgres,redis,config}

    # Backup current PostgreSQL
    export PGPASSWORD="$POSTGRES_PASSWORD"
    pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
        --format=custom > "${ROLLBACK_DIR}/postgres/pre_restore.sql" 2>> "$RESTORE_LOG" || true
    unset PGPASSWORD

    # Backup current Redis
    if [ -n "$REDIS_PASSWORD" ]; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning BGSAVE >> "$RESTORE_LOG" 2>&1 || true
    else
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" BGSAVE >> "$RESTORE_LOG" 2>&1 || true
    fi

    log_success "Rollback backup created: $ROLLBACK_DIR"
    echo "To rollback, run: $0 -f ${ROLLBACK_DIR}/postgres/pre_restore.sql"
}

#==============================================================================
# RESTORE FUNCTIONS
#==============================================================================

restore_postgresql() {
    if [[ "$RESTORE_COMPONENTS" != "all" && "$RESTORE_COMPONENTS" != "postgres" ]]; then
        log_info "Skipping PostgreSQL restore (not selected)"
        return 0
    fi

    log_info "Starting PostgreSQL restore..."

    local dump_file="${EXTRACTED_BACKUP}/postgres/minio_db.sql"

    if [ ! -f "$dump_file" ]; then
        log_error "PostgreSQL dump file not found: $dump_file"
        return 1
    fi

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would restore PostgreSQL from: $dump_file"
        return 0
    fi

    # Drop existing connections
    export PGPASSWORD="$POSTGRES_PASSWORD"
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres \
        -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$POSTGRES_DB' AND pid <> pg_backend_pid();" \
        >> "$RESTORE_LOG" 2>&1 || true

    # Drop and recreate database
    log_info "Dropping and recreating database..."
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres \
        -c "DROP DATABASE IF EXISTS $POSTGRES_DB;" >> "$RESTORE_LOG" 2>&1

    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres \
        -c "CREATE DATABASE $POSTGRES_DB;" >> "$RESTORE_LOG" 2>&1

    # Restore database
    if pg_restore -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
        --verbose "$dump_file" >> "$RESTORE_LOG" 2>&1; then

        unset PGPASSWORD
        log_success "PostgreSQL restore completed"
        return 0
    else
        unset PGPASSWORD
        log_error "PostgreSQL restore failed (check log for details)"
        return 1
    fi
}

restore_redis() {
    if [[ "$RESTORE_COMPONENTS" != "all" && "$RESTORE_COMPONENTS" != "redis" ]]; then
        log_info "Skipping Redis restore (not selected)"
        return 0
    fi

    log_info "Starting Redis restore..."

    local redis_dump="${EXTRACTED_BACKUP}/redis/dump.rdb"

    if [ ! -f "$redis_dump" ]; then
        log_warning "Redis dump file not found: $redis_dump"
        return 1
    fi

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would restore Redis from: $redis_dump"
        return 0
    fi

    # Flush existing data
    log_warning "Flushing existing Redis data..."
    if [ -n "$REDIS_PASSWORD" ]; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning FLUSHALL >> "$RESTORE_LOG" 2>&1
    else
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" FLUSHALL >> "$RESTORE_LOG" 2>&1
    fi

    # Stop Redis (requires root/sudo)
    log_info "Stopping Redis service..."
    systemctl stop redis 2>> "$RESTORE_LOG" || service redis stop 2>> "$RESTORE_LOG" || log_warning "Could not stop Redis service automatically"

    # Copy dump file
    local redis_dir="/var/lib/redis"
    log_info "Copying Redis dump file..."

    if cp "$redis_dump" "${redis_dir}/dump.rdb" 2>> "$RESTORE_LOG"; then
        chown redis:redis "${redis_dir}/dump.rdb" 2>> "$RESTORE_LOG" || true

        # Copy AOF if exists
        if [ -f "${EXTRACTED_BACKUP}/redis/appendonly.aof" ]; then
            cp "${EXTRACTED_BACKUP}/redis/appendonly.aof" "${redis_dir}/"
            chown redis:redis "${redis_dir}/appendonly.aof" 2>> "$RESTORE_LOG" || true
            log_info "Redis AOF file restored"
        fi

        # Start Redis
        log_info "Starting Redis service..."
        systemctl start redis 2>> "$RESTORE_LOG" || service redis start 2>> "$RESTORE_LOG" || log_warning "Could not start Redis service automatically"

        # Wait for Redis to be ready
        sleep 2

        # Verify
        if [ -n "$REDIS_PASSWORD" ]; then
            redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning PING >> "$RESTORE_LOG" 2>&1
        else
            redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" PING >> "$RESTORE_LOG" 2>&1
        fi

        if [ $? -eq 0 ]; then
            log_success "Redis restore completed"
            return 0
        else
            log_error "Redis restore verification failed"
            return 1
        fi
    else
        log_error "Failed to copy Redis dump file"
        return 1
    fi
}

restore_minio_data() {
    if [[ "$RESTORE_COMPONENTS" != "all" && "$RESTORE_COMPONENTS" != "minio" ]]; then
        log_info "Skipping MinIO data restore (not selected)"
        return 0
    fi

    log_info "Starting MinIO data restore..."

    local minio_backup="${EXTRACTED_BACKUP}/minio"

    if [ ! -d "$minio_backup" ]; then
        log_warning "MinIO backup directory not found: $minio_backup"
        return 1
    fi

    # Check if mc (MinIO client) is available
    if ! command -v mc &> /dev/null; then
        log_error "MinIO client (mc) not found"
        log_info "Install mc with: wget https://dl.min.io/client/mc/release/linux-amd64/mc"
        return 1
    fi

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would restore MinIO data from: $minio_backup"
        return 0
    fi

    # Configure mc alias
    mc alias set restore "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" >> "$RESTORE_LOG" 2>&1

    # Restore each bucket
    for bucket_dir in "$minio_backup"/*; do
        if [ -d "$bucket_dir" ] && [ "$(basename $bucket_dir)" != "cluster_info.json" ]; then
            local bucket=$(basename "$bucket_dir")
            log_info "Restoring bucket: $bucket"

            # Create bucket if it doesn't exist
            mc mb restore/"${bucket}" >> "$RESTORE_LOG" 2>&1 || log_info "Bucket already exists: $bucket"

            # Mirror data
            if mc mirror --overwrite "$bucket_dir" restore/"${bucket}" >> "$RESTORE_LOG" 2>&1; then
                local count=$(find "$bucket_dir" -type f | wc -l)
                log_success "Bucket '$bucket' restored: $count objects"
            else
                log_error "Failed to restore bucket: $bucket"
            fi
        fi
    done

    log_success "MinIO data restore completed"
    return 0
}

restore_configurations() {
    if [[ "$RESTORE_COMPONENTS" != "all" && "$RESTORE_COMPONENTS" != "config" ]]; then
        log_info "Skipping configuration restore (not selected)"
        return 0
    fi

    log_info "Starting configuration restore..."

    local config_backup="${EXTRACTED_BACKUP}/config"

    if [ ! -d "$config_backup" ]; then
        log_warning "Configuration backup directory not found: $config_backup"
        return 1
    fi

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would restore configurations from: $config_backup"
        return 0
    fi

    # Restore configuration files
    if [ -d "${config_backup}/configs" ]; then
        log_info "Restoring configuration files..."
        cp -r "${config_backup}/configs"/* configs/ 2>> "$RESTORE_LOG" || true
    fi

    if [ -d "${config_backup}/deployments" ]; then
        log_info "Restoring deployment files..."
        cp -r "${config_backup}/deployments"/* deployments/ 2>> "$RESTORE_LOG" || true
    fi

    log_success "Configuration restore completed"
    return 0
}

#==============================================================================
# VERIFICATION
#==============================================================================

verify_restore() {
    log_info "Verifying restore integrity..."

    local failures=0

    # Verify PostgreSQL
    if [[ "$RESTORE_COMPONENTS" == "all" || "$RESTORE_COMPONENTS" == "postgres" ]]; then
        export PGPASSWORD="$POSTGRES_PASSWORD"
        if psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
            -c "SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public';" >> "$RESTORE_LOG" 2>&1; then
            log_success "PostgreSQL verification passed"
        else
            log_error "PostgreSQL verification failed"
            ((failures++))
        fi
        unset PGPASSWORD
    fi

    # Verify Redis
    if [[ "$RESTORE_COMPONENTS" == "all" || "$RESTORE_COMPONENTS" == "redis" ]]; then
        if [ -n "$REDIS_PASSWORD" ]; then
            redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning PING >> "$RESTORE_LOG" 2>&1
        else
            redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" PING >> "$RESTORE_LOG" 2>&1
        fi

        if [ $? -eq 0 ]; then
            log_success "Redis verification passed"
        else
            log_error "Redis verification failed"
            ((failures++))
        fi
    fi

    # Verify MinIO
    if [[ "$RESTORE_COMPONENTS" == "all" || "$RESTORE_COMPONENTS" == "minio" ]]; then
        if command -v mc &> /dev/null; then
            if mc admin info restore >> "$RESTORE_LOG" 2>&1; then
                log_success "MinIO verification passed"
            else
                log_error "MinIO verification failed"
                ((failures++))
            fi
        fi
    fi

    return $failures
}

#==============================================================================
# CLEANUP
#==============================================================================

cleanup_temp_files() {
    log_info "Cleaning up temporary files..."

    if [ -n "$EXTRACTED_BACKUP" ] && [ -d "$EXTRACTED_BACKUP" ]; then
        rm -rf "$(dirname $EXTRACTED_BACKUP)"
        log_info "Temporary extraction directory removed"
    fi

    # Remove decrypted file if exists
    if [[ "$BACKUP_FILE" =~ _decrypted\.tar\.gz$ ]]; then
        rm -f "$BACKUP_FILE"
        log_info "Decrypted temporary file removed"
    fi
}

#==============================================================================
# MAIN FUNCTION
#==============================================================================

main() {
    echo "============================================================"
    echo "MinIO Enterprise - Restore Script"
    echo "============================================================"
    echo ""

    # Parse command line arguments
    while getopts "f:c:dyvh" opt; do
        case $opt in
            f) BACKUP_FILE="$OPTARG" ;;
            c) RESTORE_COMPONENTS="$OPTARG" ;;
            d) DRY_RUN="true" ;;
            y) FORCE_RESTORE="true" ;;
            v) VERIFY_BEFORE_RESTORE="true" ;;
            h)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  -f FILE    Backup file to restore"
                echo "  -c COMP    Components to restore (all,postgres,redis,minio,config)"
                echo "  -d         Dry run (don't actually restore)"
                echo "  -y         Force restore without confirmation"
                echo "  -v         Verify checksum before restore"
                echo "  -h         Show this help"
                exit 0
                ;;
            \?) log_error "Invalid option: -$OPTARG"; exit 1 ;;
        esac
    done

    # Load config file if exists
    if [ -f "/etc/minio/restore.conf" ]; then
        log_info "Loading configuration from /etc/minio/restore.conf"
        source /etc/minio/restore.conf
    elif [ -f "$(dirname $0)/restore.conf" ]; then
        log_info "Loading configuration from $(dirname $0)/restore.conf"
        source "$(dirname $0)/restore.conf"
    fi

    # Create log directory
    mkdir -p "$BACKUP_DIR"

    log_info "Starting restore process..."
    log_info "Restore components: $RESTORE_COMPONENTS"
    log_info "Dry run: $DRY_RUN"
    log_info "Timestamp: $TIMESTAMP"

    # Validation
    validate_backup_file
    check_dependencies
    verify_checksum || exit 1

    # Decrypt if needed
    decrypt_backup || exit 1

    # Extract backup
    extract_backup || exit 1

    # Confirm restore
    confirm_restore

    # Create rollback backup
    create_rollback_backup

    # Track failures
    local failures=0

    # Perform restore
    restore_postgresql || ((failures++))
    restore_redis || ((failures++))
    restore_minio_data || ((failures++))
    restore_configurations || ((failures++))

    # Verify restore
    verify_restore || ((failures++))

    # Cleanup
    cleanup_temp_files

    # Summary
    echo ""
    echo "============================================================"
    if [ $failures -eq 0 ]; then
        log_success "Restore completed successfully!"
        if [ "$DRY_RUN" = "true" ]; then
            log_info "This was a DRY RUN - no actual changes were made"
        fi
        log_success "Log file: $RESTORE_LOG"
        exit 0
    else
        log_warning "Restore completed with $failures failures"
        log_warning "Check log file for details: $RESTORE_LOG"
        if [ -d "$ROLLBACK_DIR" ]; then
            log_info "Rollback backup available at: $ROLLBACK_DIR"
        fi
        exit 1
    fi
}

# Run main function
main "$@"
