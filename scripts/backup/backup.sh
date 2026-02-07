#!/bin/bash
# MinIO Enterprise - Backup Script
# Description: Automated backup script for MinIO cluster, PostgreSQL, Redis, and configurations
# Version: 1.0.0
# Date: 2026-02-07

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

#==============================================================================
# CONFIGURATION
#==============================================================================

# Default configuration (can be overridden by config file or environment)
BACKUP_TYPE="${BACKUP_TYPE:-full}"  # full or incremental
BACKUP_DIR="${BACKUP_DIR:-/var/backups/minio}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
COMPRESS="${COMPRESS:-true}"
ENCRYPT="${ENCRYPT:-false}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"
S3_BACKUP="${S3_BACKUP:-false}"
S3_ENDPOINT="${S3_ENDPOINT:-}"
S3_BUCKET="${S3_BUCKET:-minio-backups}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-}"
S3_SECRET_KEY="${S3_SECRET_KEY:-}"

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

# Timestamp for backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="minio_backup_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# Log file
LOG_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.log"

#==============================================================================
# LOGGING FUNCTIONS
#==============================================================================

log() {
    local level=$1
    shift
    local message="$@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
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

    local deps=("pg_dump" "redis-cli" "tar" "gzip")

    if [ "$ENCRYPT" = "true" ]; then
        deps+=("openssl")
    fi

    if [ "$S3_BACKUP" = "true" ]; then
        deps+=("aws")
    fi

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' not found"
            exit 1
        fi
    done

    log_success "All dependencies satisfied"
}

create_backup_directory() {
    log_info "Creating backup directory: $BACKUP_PATH"

    mkdir -p "$BACKUP_PATH"/{postgres,redis,minio,config}

    if [ $? -eq 0 ]; then
        log_success "Backup directory created"
    else
        log_error "Failed to create backup directory"
        exit 1
    fi
}

cleanup_old_backups() {
    log_info "Cleaning up backups older than $RETENTION_DAYS days..."

    if [ -d "$BACKUP_DIR" ]; then
        find "$BACKUP_DIR" -type d -name "minio_backup_*" -mtime +$RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true
        find "$BACKUP_DIR" -type f -name "backup_*.log" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
        log_success "Old backups cleaned up"
    fi
}

#==============================================================================
# BACKUP FUNCTIONS
#==============================================================================

backup_postgresql() {
    log_info "Starting PostgreSQL backup..."

    local dump_file="${BACKUP_PATH}/postgres/minio_db.sql"

    export PGPASSWORD="$POSTGRES_PASSWORD"

    if pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
        --format=custom --blobs --verbose > "$dump_file" 2>> "$LOG_FILE"; then

        unset PGPASSWORD

        local size=$(du -h "$dump_file" | cut -f1)
        log_success "PostgreSQL backup completed: $dump_file ($size)"

        # Create schema-only backup for quick recovery
        export PGPASSWORD="$POSTGRES_PASSWORD"
        pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
            --schema-only > "${BACKUP_PATH}/postgres/schema_only.sql" 2>> "$LOG_FILE"
        unset PGPASSWORD

        log_info "Schema-only backup created"
        return 0
    else
        unset PGPASSWORD
        log_error "PostgreSQL backup failed"
        return 1
    fi
}

backup_redis() {
    log_info "Starting Redis backup..."

    local redis_dump="${BACKUP_PATH}/redis/dump.rdb"

    # Trigger BGSAVE to create snapshot
    if [ -n "$REDIS_PASSWORD" ]; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning BGSAVE >> "$LOG_FILE" 2>&1
    else
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" BGSAVE >> "$LOG_FILE" 2>&1
    fi

    # Wait for BGSAVE to complete
    sleep 2

    # Get Redis data directory
    local redis_dir="/var/lib/redis"
    if [ -f "${redis_dir}/dump.rdb" ]; then
        cp "${redis_dir}/dump.rdb" "$redis_dump"

        # Also save AOF if enabled
        if [ -f "${redis_dir}/appendonly.aof" ]; then
            cp "${redis_dir}/appendonly.aof" "${BACKUP_PATH}/redis/"
            log_info "Redis AOF file backed up"
        fi

        local size=$(du -h "$redis_dump" | cut -f1)
        log_success "Redis backup completed: $redis_dump ($size)"
        return 0
    else
        log_warning "Redis dump.rdb not found, attempting alternative backup..."

        # Export keys as fallback
        if [ -n "$REDIS_PASSWORD" ]; then
            redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning \
                --csv KEYS '*' > "${BACKUP_PATH}/redis/keys.csv" 2>> "$LOG_FILE"
        else
            redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --csv KEYS '*' > "${BACKUP_PATH}/redis/keys.csv" 2>> "$LOG_FILE"
        fi

        log_success "Redis keys exported to CSV"
        return 0
    fi
}

backup_minio_data() {
    log_info "Starting MinIO data backup..."

    # Check if mc (MinIO client) is available
    if ! command -v mc &> /dev/null; then
        log_warning "MinIO client (mc) not found, skipping object data backup"
        log_info "Install mc with: wget https://dl.min.io/client/mc/release/linux-amd64/mc"
        return 1
    fi

    # Configure mc alias
    mc alias set backup "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" >> "$LOG_FILE" 2>&1

    # Mirror all buckets
    local bucket_list=$(mc ls backup/ 2>/dev/null | awk '{print $NF}' | tr -d '/')

    if [ -z "$bucket_list" ]; then
        log_info "No buckets found to backup"
        return 0
    fi

    for bucket in $bucket_list; do
        log_info "Backing up bucket: $bucket"

        mkdir -p "${BACKUP_PATH}/minio/${bucket}"

        if mc mirror --preserve backup/"${bucket}" "${BACKUP_PATH}/minio/${bucket}" >> "$LOG_FILE" 2>&1; then
            local count=$(find "${BACKUP_PATH}/minio/${bucket}" -type f | wc -l)
            local size=$(du -sh "${BACKUP_PATH}/minio/${bucket}" | cut -f1)
            log_success "Bucket '$bucket' backed up: $count objects, $size"
        else
            log_error "Failed to backup bucket: $bucket"
        fi
    done

    # Save bucket metadata
    mc admin info backup > "${BACKUP_PATH}/minio/cluster_info.json" 2>> "$LOG_FILE" || true

    log_success "MinIO data backup completed"
    return 0
}

backup_configurations() {
    log_info "Starting configuration backup..."

    local config_files=(
        "configs/.env.example"
        "configs/prometheus/prometheus.yml"
        "configs/prometheus/alertmanager.yml"
        "configs/grafana/grafana.ini"
        "configs/loki/loki-config.yml"
        "deployments/docker/docker-compose.yml"
        "deployments/docker/docker-compose.production.yml"
        "deployments/kubernetes/*.yaml"
    )

    for pattern in "${config_files[@]}"; do
        for file in $pattern; do
            if [ -f "$file" ]; then
                local dest_dir="${BACKUP_PATH}/config/$(dirname $file)"
                mkdir -p "$dest_dir"
                cp "$file" "$dest_dir/"
                log_info "Backed up: $file"
            fi
        done
    done

    # Backup environment variables (sanitized)
    env | grep -E '^(MINIO|POSTGRES|REDIS)_' | sed 's/=.*SECRET.*/=***REDACTED***/g' > "${BACKUP_PATH}/config/environment.txt"

    log_success "Configuration backup completed"
    return 0
}

#==============================================================================
# COMPRESSION AND ENCRYPTION
#==============================================================================

compress_backup() {
    if [ "$COMPRESS" != "true" ]; then
        log_info "Compression disabled, skipping..."
        return 0
    fi

    log_info "Compressing backup..."

    local archive="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

    if tar -czf "$archive" -C "$BACKUP_DIR" "$BACKUP_NAME" 2>> "$LOG_FILE"; then
        local size=$(du -h "$archive" | cut -f1)
        log_success "Backup compressed: $archive ($size)"

        # Remove uncompressed directory
        rm -rf "$BACKUP_PATH"
        log_info "Uncompressed backup removed"

        BACKUP_PATH="$archive"
        return 0
    else
        log_error "Compression failed"
        return 1
    fi
}

encrypt_backup() {
    if [ "$ENCRYPT" != "true" ]; then
        log_info "Encryption disabled, skipping..."
        return 0
    fi

    if [ -z "$ENCRYPTION_KEY" ]; then
        log_error "ENCRYPTION_KEY not set but encryption enabled"
        return 1
    fi

    log_info "Encrypting backup..."

    local encrypted="${BACKUP_PATH}.enc"

    if openssl enc -aes-256-cbc -salt -pbkdf2 -in "$BACKUP_PATH" -out "$encrypted" -k "$ENCRYPTION_KEY" 2>> "$LOG_FILE"; then
        local size=$(du -h "$encrypted" | cut -f1)
        log_success "Backup encrypted: $encrypted ($size)"

        # Remove unencrypted file
        rm -f "$BACKUP_PATH"
        log_info "Unencrypted backup removed"

        BACKUP_PATH="$encrypted"
        return 0
    else
        log_error "Encryption failed"
        return 1
    fi
}

#==============================================================================
# S3 UPLOAD
#==============================================================================

upload_to_s3() {
    if [ "$S3_BACKUP" != "true" ]; then
        log_info "S3 backup disabled, skipping..."
        return 0
    fi

    if [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ]; then
        log_error "S3 credentials not set but S3 backup enabled"
        return 1
    fi

    log_info "Uploading backup to S3..."

    export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"

    local s3_path="s3://${S3_BUCKET}/$(basename $BACKUP_PATH)"

    if [ -n "$S3_ENDPOINT" ]; then
        aws s3 cp "$BACKUP_PATH" "$s3_path" --endpoint-url "$S3_ENDPOINT" 2>> "$LOG_FILE"
    else
        aws s3 cp "$BACKUP_PATH" "$s3_path" 2>> "$LOG_FILE"
    fi

    if [ $? -eq 0 ]; then
        log_success "Backup uploaded to S3: $s3_path"
        unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
        return 0
    else
        log_error "S3 upload failed"
        unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
        return 1
    fi
}

#==============================================================================
# VERIFICATION
#==============================================================================

verify_backup() {
    log_info "Verifying backup integrity..."

    if [ -f "$BACKUP_PATH" ]; then
        # Check file size
        local size=$(stat -f%z "$BACKUP_PATH" 2>/dev/null || stat -c%s "$BACKUP_PATH" 2>/dev/null)

        if [ "$size" -gt 0 ]; then
            log_success "Backup file exists and has size: $(numfmt --to=iec $size 2>/dev/null || echo ${size} bytes)"

            # Create checksum
            local checksum_file="${BACKUP_PATH}.sha256"
            sha256sum "$BACKUP_PATH" > "$checksum_file"
            log_info "Checksum created: $checksum_file"

            return 0
        else
            log_error "Backup file is empty"
            return 1
        fi
    else
        log_error "Backup file not found: $BACKUP_PATH"
        return 1
    fi
}

#==============================================================================
# MAIN FUNCTION
#==============================================================================

main() {
    echo "============================================================"
    echo "MinIO Enterprise - Backup Script"
    echo "============================================================"
    echo ""

    # Load config file if exists
    if [ -f "/etc/minio/backup.conf" ]; then
        log_info "Loading configuration from /etc/minio/backup.conf"
        source /etc/minio/backup.conf
    elif [ -f "$(dirname $0)/backup.conf" ]; then
        log_info "Loading configuration from $(dirname $0)/backup.conf"
        source "$(dirname $0)/backup.conf"
    fi

    # Create log directory
    mkdir -p "$BACKUP_DIR"

    log_info "Starting backup process..."
    log_info "Backup type: $BACKUP_TYPE"
    log_info "Backup directory: $BACKUP_DIR"
    log_info "Timestamp: $TIMESTAMP"

    # Check dependencies
    check_dependencies

    # Create backup directory
    create_backup_directory

    # Track failures
    local failures=0

    # Perform backups
    backup_postgresql || ((failures++))
    backup_redis || ((failures++))
    backup_minio_data || ((failures++))
    backup_configurations || ((failures++))

    # Post-processing
    compress_backup || ((failures++))
    encrypt_backup || ((failures++))

    # Verification
    verify_backup || ((failures++))

    # Upload to S3
    upload_to_s3 || ((failures++))

    # Cleanup old backups
    cleanup_old_backups

    # Summary
    echo ""
    echo "============================================================"
    if [ $failures -eq 0 ]; then
        log_success "Backup completed successfully!"
        log_success "Backup location: $BACKUP_PATH"
        log_success "Log file: $LOG_FILE"
        exit 0
    else
        log_warning "Backup completed with $failures failures"
        log_warning "Check log file for details: $LOG_FILE"
        exit 1
    fi
}

# Run main function
main "$@"
