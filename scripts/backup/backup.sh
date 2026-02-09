#!/bin/bash
# MinIO Enterprise Backup Script
# Supports full and incremental backups of MinIO data, PostgreSQL, Redis, and configuration files

set -e  # Exit on error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/backup.conf"
LOG_DIR="${BACKUP_DIR:-/var/backups/minio}/logs"
BACKUP_ROOT="${BACKUP_DIR:-/var/backups/minio}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_TYPE="${1:-full}"  # full or incremental

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
else
    echo -e "${YELLOW}Warning: Configuration file not found at $CONFIG_FILE${NC}"
    echo -e "${YELLOW}Using default configuration...${NC}"
fi

# Default configuration (can be overridden by backup.conf)
MINIO_DATA_DIR="${MINIO_DATA_DIR:-/var/lib/minio}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-minio}"
POSTGRES_USER="${POSTGRES_USER:-minio}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
CONFIG_DIR="${CONFIG_DIR:-/etc/minio}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
COMPRESSION="${COMPRESSION:-true}"
ENCRYPTION="${ENCRYPTION:-false}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"
S3_STORAGE="${S3_STORAGE:-false}"
S3_BUCKET="${S3_BUCKET:-}"
S3_ENDPOINT="${S3_ENDPOINT:-}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-}"
S3_SECRET_KEY="${S3_SECRET_KEY:-}"
PARALLEL_JOBS="${PARALLEL_JOBS:-4}"
VERIFY_BACKUP="${VERIFY_BACKUP:-true}"

# Create necessary directories
mkdir -p "$BACKUP_ROOT"/{full,incremental,metadata,logs}
mkdir -p "$LOG_DIR"

# Log file
LOG_FILE="${LOG_DIR}/backup_${TIMESTAMP}.log"

# Functions
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

check_dependencies() {
    log_info "Checking dependencies..."

    local deps=(rsync pg_dump redis-cli tar gzip)
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Install missing dependencies:"
        log_info "  Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}"
        log_info "  CentOS/RHEL: sudo yum install ${missing_deps[*]}"
        exit 1
    fi

    if [ "$ENCRYPTION" = "true" ] && ! command -v openssl &> /dev/null; then
        log_error "Encryption enabled but openssl not found"
        exit 1
    fi

    log_success "All dependencies satisfied"
}

check_services() {
    log_info "Checking service availability..."

    # Check PostgreSQL
    if ! PGPASSWORD="$POSTGRES_PASSWORD" pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" &> /dev/null; then
        log_error "PostgreSQL is not accessible at $POSTGRES_HOST:$POSTGRES_PORT"
        exit 1
    fi
    log_success "PostgreSQL is accessible"

    # Check Redis
    if [ -n "$REDIS_PASSWORD" ]; then
        if ! redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" PING &> /dev/null; then
            log_error "Redis is not accessible at $REDIS_HOST:$REDIS_PORT"
            exit 1
        fi
    else
        if ! redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" PING &> /dev/null; then
            log_error "Redis is not accessible at $REDIS_HOST:$REDIS_PORT"
            exit 1
        fi
    fi
    log_success "Redis is accessible"

    # Check MinIO data directory
    if [ ! -d "$MINIO_DATA_DIR" ]; then
        log_error "MinIO data directory not found: $MINIO_DATA_DIR"
        exit 1
    fi
    log_success "MinIO data directory exists"
}

get_last_backup_timestamp() {
    local backup_dir="$BACKUP_ROOT/$1"
    if [ -d "$backup_dir" ]; then
        # Find the most recent backup directory
        find "$backup_dir" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | sort -r | head -n 1 | xargs basename 2>/dev/null || echo ""
    else
        echo ""
    fi
}

backup_postgresql() {
    local backup_dir="$1"
    log_info "Backing up PostgreSQL database..."

    local pg_backup_file="${backup_dir}/postgresql_${POSTGRES_DB}.sql"

    PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        --format=custom \
        --verbose \
        --file="$pg_backup_file" 2>> "$LOG_FILE"

    if [ $? -eq 0 ]; then
        log_success "PostgreSQL backup completed: $pg_backup_file"

        # Compress if enabled
        if [ "$COMPRESSION" = "true" ]; then
            gzip -f "$pg_backup_file"
            log_success "PostgreSQL backup compressed: ${pg_backup_file}.gz"
        fi
    else
        log_error "PostgreSQL backup failed"
        return 1
    fi
}

backup_redis() {
    local backup_dir="$1"
    log_info "Backing up Redis data..."

    local redis_backup_file="${backup_dir}/redis_dump.rdb"

    # Trigger Redis BGSAVE
    if [ -n "$REDIS_PASSWORD" ]; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" BGSAVE &>> "$LOG_FILE"
    else
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" BGSAVE &>> "$LOG_FILE"
    fi

    # Wait for BGSAVE to complete
    sleep 2
    local save_status=""
    for i in {1..30}; do
        if [ -n "$REDIS_PASSWORD" ]; then
            save_status=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" LASTSAVE 2>/dev/null)
        else
            save_status=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" LASTSAVE 2>/dev/null)
        fi

        if [ -n "$save_status" ]; then
            break
        fi
        sleep 1
    done

    # Copy Redis dump file
    if [ "$REDIS_HOST" = "localhost" ] || [ "$REDIS_HOST" = "127.0.0.1" ]; then
        cp /var/lib/redis/dump.rdb "$redis_backup_file" 2>> "$LOG_FILE" || true
    else
        log_warning "Redis is remote, skipping RDB file copy. Consider using Redis persistence."
    fi

    if [ -f "$redis_backup_file" ]; then
        log_success "Redis backup completed: $redis_backup_file"

        # Compress if enabled
        if [ "$COMPRESSION" = "true" ]; then
            gzip -f "$redis_backup_file"
            log_success "Redis backup compressed: ${redis_backup_file}.gz"
        fi
    else
        log_warning "Redis RDB file not found, backup may be incomplete"
    fi
}

backup_minio_data() {
    local backup_dir="$1"
    local backup_type="$2"
    log_info "Backing up MinIO data ($backup_type)..."

    local minio_backup_dir="${backup_dir}/minio_data"
    mkdir -p "$minio_backup_dir"

    if [ "$backup_type" = "full" ]; then
        # Full backup
        rsync -avz --progress \
            --exclude='*.tmp' \
            --exclude='*.lock' \
            "$MINIO_DATA_DIR/" \
            "$minio_backup_dir/" \
            2>> "$LOG_FILE" | tee -a "$LOG_FILE"
    else
        # Incremental backup
        local last_backup=$(get_last_backup_timestamp "full")
        if [ -z "$last_backup" ]; then
            log_warning "No previous full backup found, performing full backup instead"
            rsync -avz --progress \
                --exclude='*.tmp' \
                --exclude='*.lock' \
                "$MINIO_DATA_DIR/" \
                "$minio_backup_dir/" \
                2>> "$LOG_FILE" | tee -a "$LOG_FILE"
        else
            local last_backup_dir="$BACKUP_ROOT/full/$last_backup/minio_data"
            rsync -avz --progress \
                --link-dest="$last_backup_dir" \
                --exclude='*.tmp' \
                --exclude='*.lock' \
                "$MINIO_DATA_DIR/" \
                "$minio_backup_dir/" \
                2>> "$LOG_FILE" | tee -a "$LOG_FILE"
        fi
    fi

    if [ $? -eq 0 ]; then
        log_success "MinIO data backup completed: $minio_backup_dir"
    else
        log_error "MinIO data backup failed"
        return 1
    fi
}

backup_config() {
    local backup_dir="$1"
    log_info "Backing up configuration files..."

    local config_backup_dir="${backup_dir}/config"
    mkdir -p "$config_backup_dir"

    # Backup configuration directory if it exists
    if [ -d "$CONFIG_DIR" ]; then
        rsync -avz --progress "$CONFIG_DIR/" "$config_backup_dir/" 2>> "$LOG_FILE"
    fi

    # Backup docker-compose files
    if [ -f "$(pwd)/deployments/docker/docker-compose.yml" ]; then
        cp "$(pwd)/deployments/docker/docker-compose.yml" "$config_backup_dir/" 2>> "$LOG_FILE"
    fi

    if [ -f "$(pwd)/deployments/docker/docker-compose.production.yml" ]; then
        cp "$(pwd)/deployments/docker/docker-compose.production.yml" "$config_backup_dir/" 2>> "$LOG_FILE"
    fi

    # Backup environment files (excluding sensitive data)
    if [ -f "$(pwd)/configs/.env.example" ]; then
        cp "$(pwd)/configs/.env.example" "$config_backup_dir/" 2>> "$LOG_FILE"
    fi

    log_success "Configuration backup completed: $config_backup_dir"
}

create_metadata() {
    local backup_dir="$1"
    local backup_type="$2"
    log_info "Creating backup metadata..."

    local metadata_file="${backup_dir}/metadata.json"

    cat > "$metadata_file" << EOF
{
  "timestamp": "$TIMESTAMP",
  "backup_type": "$backup_type",
  "backup_dir": "$backup_dir",
  "components": {
    "postgresql": {
      "host": "$POSTGRES_HOST",
      "database": "$POSTGRES_DB",
      "user": "$POSTGRES_USER"
    },
    "redis": {
      "host": "$REDIS_HOST",
      "port": "$REDIS_PORT"
    },
    "minio": {
      "data_dir": "$MINIO_DATA_DIR"
    }
  },
  "settings": {
    "compression": $COMPRESSION,
    "encryption": $ENCRYPTION,
    "retention_days": $RETENTION_DAYS
  },
  "system_info": {
    "hostname": "$(hostname)",
    "os": "$(uname -s)",
    "kernel": "$(uname -r)"
  }
}
EOF

    log_success "Metadata created: $metadata_file"
}

encrypt_backup() {
    local backup_dir="$1"
    log_info "Encrypting backup..."

    if [ -z "$ENCRYPTION_KEY" ]; then
        log_error "Encryption key not provided"
        return 1
    fi

    local encrypted_file="${backup_dir}.tar.gz.enc"
    tar -czf - -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")" | \
        openssl enc -aes-256-cbc -salt -k "$ENCRYPTION_KEY" -out "$encrypted_file"

    if [ $? -eq 0 ]; then
        log_success "Backup encrypted: $encrypted_file"
        # Remove unencrypted backup
        rm -rf "$backup_dir"
    else
        log_error "Backup encryption failed"
        return 1
    fi
}

verify_backup() {
    local backup_dir="$1"
    log_info "Verifying backup integrity..."

    local verification_failed=0

    # Check if backup directory exists
    if [ ! -d "$backup_dir" ]; then
        log_error "Backup directory not found: $backup_dir"
        return 1
    fi

    # Verify PostgreSQL backup
    local pg_backup=$(find "$backup_dir" -name "postgresql_*.sql*" | head -n 1)
    if [ -n "$pg_backup" ] && [ -f "$pg_backup" ]; then
        if [ "${pg_backup##*.}" = "gz" ]; then
            if gzip -t "$pg_backup" 2>> "$LOG_FILE"; then
                log_success "PostgreSQL backup verified"
            else
                log_error "PostgreSQL backup verification failed"
                verification_failed=1
            fi
        else
            log_success "PostgreSQL backup exists"
        fi
    else
        log_warning "PostgreSQL backup not found"
    fi

    # Verify MinIO data
    if [ -d "$backup_dir/minio_data" ]; then
        local file_count=$(find "$backup_dir/minio_data" -type f | wc -l)
        log_success "MinIO data backup verified ($file_count files)"
    else
        log_error "MinIO data backup not found"
        verification_failed=1
    fi

    # Verify metadata
    if [ -f "$backup_dir/metadata.json" ]; then
        log_success "Metadata file verified"
    else
        log_warning "Metadata file not found"
    fi

    if [ $verification_failed -eq 0 ]; then
        log_success "Backup verification completed successfully"
        return 0
    else
        log_error "Backup verification failed"
        return 1
    fi
}

upload_to_s3() {
    local backup_dir="$1"
    log_info "Uploading backup to S3..."

    if [ -z "$S3_BUCKET" ] || [ -z "$S3_ENDPOINT" ]; then
        log_error "S3 configuration incomplete"
        return 1
    fi

    # Create tarball
    local tarball="${backup_dir}.tar.gz"
    tar -czf "$tarball" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"

    # Upload using mc (MinIO Client)
    if command -v mc &> /dev/null; then
        mc alias set s3backup "$S3_ENDPOINT" "$S3_ACCESS_KEY" "$S3_SECRET_KEY"
        mc cp "$tarball" "s3backup/$S3_BUCKET/$(basename "$tarball")"

        if [ $? -eq 0 ]; then
            log_success "Backup uploaded to S3: $S3_BUCKET/$(basename "$tarball")"
            rm -f "$tarball"
        else
            log_error "S3 upload failed"
            return 1
        fi
    else
        log_warning "mc (MinIO Client) not found, skipping S3 upload"
    fi
}

cleanup_old_backups() {
    log_info "Cleaning up old backups (retention: $RETENTION_DAYS days)..."

    # Clean full backups
    find "$BACKUP_ROOT/full" -maxdepth 1 -type d -name "backup_*" -mtime +"$RETENTION_DAYS" -exec rm -rf {} \; 2>> "$LOG_FILE"

    # Clean incremental backups
    find "$BACKUP_ROOT/incremental" -maxdepth 1 -type d -name "backup_*" -mtime +"$RETENTION_DAYS" -exec rm -rf {} \; 2>> "$LOG_FILE"

    # Clean old logs
    find "$LOG_DIR" -type f -name "backup_*.log" -mtime +"$RETENTION_DAYS" -delete 2>> "$LOG_FILE"

    log_success "Old backups cleaned up"
}

print_summary() {
    local backup_dir="$1"
    local duration="$2"

    echo ""
    log_info "======================================"
    log_info "Backup Summary"
    log_info "======================================"
    log_info "Backup Type: $BACKUP_TYPE"
    log_info "Timestamp: $TIMESTAMP"
    log_info "Backup Directory: $backup_dir"
    log_info "Duration: ${duration}s"

    if [ -d "$backup_dir" ]; then
        local backup_size=$(du -sh "$backup_dir" | cut -f1)
        log_info "Backup Size: $backup_size"
    fi

    log_info "Log File: $LOG_FILE"
    log_info "======================================"
    echo ""
}

# Main execution
main() {
    local start_time=$(date +%s)

    log_info "======================================"
    log_info "MinIO Enterprise Backup Script"
    log_info "======================================"
    log_info "Backup Type: $BACKUP_TYPE"
    log_info "Timestamp: $TIMESTAMP"
    log_info "======================================"
    echo ""

    # Validate backup type
    if [ "$BACKUP_TYPE" != "full" ] && [ "$BACKUP_TYPE" != "incremental" ]; then
        log_error "Invalid backup type: $BACKUP_TYPE (must be 'full' or 'incremental')"
        exit 1
    fi

    # Pre-flight checks
    check_dependencies
    check_services

    # Create backup directory
    local backup_dir="$BACKUP_ROOT/$BACKUP_TYPE/backup_$TIMESTAMP"
    mkdir -p "$backup_dir"
    log_info "Backup directory: $backup_dir"
    echo ""

    # Perform backups
    backup_postgresql "$backup_dir" || exit 1
    backup_redis "$backup_dir" || exit 1
    backup_minio_data "$backup_dir" "$BACKUP_TYPE" || exit 1
    backup_config "$backup_dir" || exit 1
    create_metadata "$backup_dir" "$BACKUP_TYPE"

    # Verify backup
    if [ "$VERIFY_BACKUP" = "true" ]; then
        verify_backup "$backup_dir" || exit 1
    fi

    # Encrypt if enabled
    if [ "$ENCRYPTION" = "true" ]; then
        encrypt_backup "$backup_dir" || exit 1
    fi

    # Upload to S3 if enabled
    if [ "$S3_STORAGE" = "true" ]; then
        upload_to_s3 "$backup_dir"
    fi

    # Cleanup old backups
    cleanup_old_backups

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    print_summary "$backup_dir" "$duration"

    log_success "Backup completed successfully!"
}

# Run main function
main
