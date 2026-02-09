#!/bin/bash
# MinIO Enterprise Restore Script
# Supports restoration from full and incremental backups with verification and rollback

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
CONFIG_FILE="${SCRIPT_DIR}/../backup/backup.conf"
LOG_DIR="/var/log/minio/restore"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
else
    echo -e "${YELLOW}Warning: Configuration file not found at $CONFIG_FILE${NC}"
    echo -e "${YELLOW}Using default configuration...${NC}"
fi

# Default configuration
BACKUP_ROOT="${BACKUP_DIR:-/var/backups/minio}"
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
VERIFY_RESTORE="${VERIFY_RESTORE:-true}"
CREATE_ROLLBACK="${CREATE_ROLLBACK:-true}"
ENCRYPTION="${ENCRYPTION:-false}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"

# Create necessary directories
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/restore_${TIMESTAMP}.log"

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

    local deps=(rsync pg_restore redis-cli tar gzip)
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

list_backups() {
    log_info "Available backups:"
    echo ""

    local backup_types=("full" "incremental")

    for backup_type in "${backup_types[@]}"; do
        local backup_dir="$BACKUP_ROOT/$backup_type"
        if [ -d "$backup_dir" ]; then
            echo -e "${BLUE}=== $backup_type backups ===${NC}"
            local backups=$(find "$backup_dir" -maxdepth 1 -type d -name "backup_*" | sort -r)

            if [ -z "$backups" ]; then
                echo "  No backups found"
            else
                while IFS= read -r backup; do
                    local backup_name=$(basename "$backup")
                    local backup_date=$(echo "$backup_name" | sed 's/backup_//')
                    local backup_size=$(du -sh "$backup" 2>/dev/null | cut -f1)

                    if [ -f "$backup/metadata.json" ]; then
                        echo "  $backup_date ($backup_size) ✓"
                    else
                        echo "  $backup_date ($backup_size)"
                    fi
                done <<< "$backups"
            fi
            echo ""
        fi
    done
}

select_backup() {
    if [ $# -eq 0 ]; then
        log_info "No backup specified. Listing available backups..."
        list_backups

        echo -n "Enter backup timestamp (e.g., 20260209_070000) or 'latest' for most recent: "
        read -r backup_timestamp

        if [ "$backup_timestamp" = "latest" ]; then
            # Find the most recent backup
            local latest_full=$(find "$BACKUP_ROOT/full" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | sort -r | head -n 1)
            if [ -n "$latest_full" ]; then
                SELECTED_BACKUP="$latest_full"
                log_info "Selected latest backup: $(basename "$SELECTED_BACKUP")"
            else
                log_error "No backups found"
                exit 1
            fi
        else
            # Look for specific backup
            local backup_path=""
            if [ -d "$BACKUP_ROOT/full/backup_$backup_timestamp" ]; then
                backup_path="$BACKUP_ROOT/full/backup_$backup_timestamp"
            elif [ -d "$BACKUP_ROOT/incremental/backup_$backup_timestamp" ]; then
                backup_path="$BACKUP_ROOT/incremental/backup_$backup_timestamp"
            fi

            if [ -n "$backup_path" ]; then
                SELECTED_BACKUP="$backup_path"
                log_info "Selected backup: $(basename "$SELECTED_BACKUP")"
            else
                log_error "Backup not found: $backup_timestamp"
                exit 1
            fi
        fi
    else
        SELECTED_BACKUP="$1"
        if [ ! -d "$SELECTED_BACKUP" ]; then
            log_error "Backup directory not found: $SELECTED_BACKUP"
            exit 1
        fi
    fi
}

verify_backup_integrity() {
    local backup_dir="$1"
    log_info "Verifying backup integrity..."

    # Check metadata
    if [ ! -f "$backup_dir/metadata.json" ]; then
        log_warning "Metadata file not found, backup may be incomplete"
    else
        log_success "Metadata file found"
    fi

    # Check PostgreSQL backup
    local pg_backup=$(find "$backup_dir" -name "postgresql_*.sql*" | head -n 1)
    if [ -n "$pg_backup" ] && [ -f "$pg_backup" ]; then
        if [ "${pg_backup##*.}" = "gz" ]; then
            if gzip -t "$pg_backup" 2>> "$LOG_FILE"; then
                log_success "PostgreSQL backup integrity verified"
            else
                log_error "PostgreSQL backup is corrupted"
                return 1
            fi
        else
            log_success "PostgreSQL backup found"
        fi
    else
        log_warning "PostgreSQL backup not found"
    fi

    # Check MinIO data
    if [ -d "$backup_dir/minio_data" ]; then
        local file_count=$(find "$backup_dir/minio_data" -type f | wc -l)
        log_success "MinIO data backup found ($file_count files)"
    else
        log_warning "MinIO data backup not found"
    fi

    log_success "Backup integrity verification completed"
}

decrypt_backup() {
    local encrypted_file="$1"
    log_info "Decrypting backup..."

    if [ -z "$ENCRYPTION_KEY" ]; then
        log_error "Encryption key not provided"
        return 1
    fi

    local decrypted_dir="${encrypted_file%.tar.gz.enc}"
    openssl enc -aes-256-cbc -d -k "$ENCRYPTION_KEY" -in "$encrypted_file" | tar -xzf - -C "$(dirname "$decrypted_dir")"

    if [ $? -eq 0 ]; then
        log_success "Backup decrypted successfully"
        echo "$decrypted_dir"
    else
        log_error "Backup decryption failed"
        return 1
    fi
}

create_rollback_point() {
    log_info "Creating rollback point..."

    local rollback_dir="$BACKUP_ROOT/rollback/restore_$TIMESTAMP"
    mkdir -p "$rollback_dir"

    # Backup current PostgreSQL database
    log_info "Backing up current PostgreSQL database..."
    PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        --format=custom \
        --file="${rollback_dir}/postgresql_${POSTGRES_DB}.sql" 2>> "$LOG_FILE"

    # Backup current MinIO data
    if [ -d "$MINIO_DATA_DIR" ]; then
        log_info "Backing up current MinIO data..."
        rsync -a "$MINIO_DATA_DIR/" "$rollback_dir/minio_data/" 2>> "$LOG_FILE"
    fi

    # Backup current Redis data
    log_info "Triggering Redis save..."
    if [ -n "$REDIS_PASSWORD" ]; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" SAVE &>> "$LOG_FILE"
    else
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SAVE &>> "$LOG_FILE"
    fi

    # Create rollback metadata
    cat > "$rollback_dir/metadata.json" << EOF
{
  "timestamp": "$TIMESTAMP",
  "type": "rollback_point",
  "created_before_restore": true,
  "system_info": {
    "hostname": "$(hostname)",
    "timestamp": "$TIMESTAMP"
  }
}
EOF

    log_success "Rollback point created: $rollback_dir"
    echo "$rollback_dir"
}

stop_services() {
    log_info "Stopping services..."

    # Stop MinIO service (example using systemd)
    if systemctl is-active --quiet minio 2>/dev/null; then
        sudo systemctl stop minio
        log_success "MinIO service stopped"
    elif command -v docker-compose &> /dev/null; then
        # Try stopping via docker-compose
        if [ -f "deployments/docker/docker-compose.production.yml" ]; then
            docker-compose -f deployments/docker/docker-compose.production.yml stop minio 2>> "$LOG_FILE"
            log_success "MinIO containers stopped"
        fi
    else
        log_warning "Could not automatically stop MinIO service"
        echo -n "Have you manually stopped MinIO? (y/n): "
        read -r response
        if [ "$response" != "y" ]; then
            log_error "Please stop MinIO service before continuing"
            exit 1
        fi
    fi
}

start_services() {
    log_info "Starting services..."

    # Start MinIO service
    if command -v systemctl &> /dev/null && systemctl list-unit-files | grep -q "^minio.service"; then
        sudo systemctl start minio
        log_success "MinIO service started"
    elif command -v docker-compose &> /dev/null; then
        if [ -f "deployments/docker/docker-compose.production.yml" ]; then
            docker-compose -f deployments/docker/docker-compose.production.yml start minio 2>> "$LOG_FILE"
            log_success "MinIO containers started"
        fi
    else
        log_warning "Could not automatically start MinIO service"
        log_info "Please start MinIO service manually"
    fi
}

restore_postgresql() {
    local backup_dir="$1"
    log_info "Restoring PostgreSQL database..."

    # Find PostgreSQL backup file
    local pg_backup=$(find "$backup_dir" -name "postgresql_*.sql*" | head -n 1)

    if [ -z "$pg_backup" ]; then
        log_error "PostgreSQL backup not found in $backup_dir"
        return 1
    fi

    # Decompress if needed
    if [ "${pg_backup##*.}" = "gz" ]; then
        log_info "Decompressing PostgreSQL backup..."
        gunzip -k "$pg_backup"
        pg_backup="${pg_backup%.gz}"
    fi

    # Drop existing database and recreate
    log_info "Dropping and recreating database..."
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};" postgres 2>> "$LOG_FILE"
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -c "CREATE DATABASE ${POSTGRES_DB};" postgres 2>> "$LOG_FILE"

    # Restore database
    log_info "Restoring database from backup..."
    PGPASSWORD="$POSTGRES_PASSWORD" pg_restore \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        --verbose \
        "$pg_backup" 2>> "$LOG_FILE"

    if [ $? -eq 0 ]; then
        log_success "PostgreSQL database restored successfully"
    else
        log_error "PostgreSQL restore failed"
        return 1
    fi
}

restore_redis() {
    local backup_dir="$1"
    log_info "Restoring Redis data..."

    # Find Redis backup file
    local redis_backup=$(find "$backup_dir" -name "redis_dump.rdb*" | head -n 1)

    if [ -z "$redis_backup" ]; then
        log_warning "Redis backup not found, skipping Redis restore"
        return 0
    fi

    # Decompress if needed
    if [ "${redis_backup##*.}" = "gz" ]; then
        log_info "Decompressing Redis backup..."
        gunzip -k "$redis_backup"
        redis_backup="${redis_backup%.gz}"
    fi

    # Flush current Redis data
    log_info "Flushing current Redis data..."
    if [ -n "$REDIS_PASSWORD" ]; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" FLUSHALL 2>> "$LOG_FILE"
    else
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" FLUSHALL 2>> "$LOG_FILE"
    fi

    # Copy RDB file (only works for local Redis)
    if [ "$REDIS_HOST" = "localhost" ] || [ "$REDIS_HOST" = "127.0.0.1" ]; then
        # Stop Redis
        if systemctl is-active --quiet redis 2>/dev/null; then
            sudo systemctl stop redis
        fi

        # Copy backup file
        sudo cp "$redis_backup" /var/lib/redis/dump.rdb
        sudo chown redis:redis /var/lib/redis/dump.rdb 2>/dev/null || true

        # Start Redis
        if command -v systemctl &> /dev/null; then
            sudo systemctl start redis
        fi

        log_success "Redis data restored successfully"
    else
        log_warning "Redis is remote, cannot restore RDB file directly"
        log_info "Please restore Redis manually from: $redis_backup"
    fi
}

restore_minio_data() {
    local backup_dir="$1"
    log_info "Restoring MinIO data..."

    local minio_backup_dir="${backup_dir}/minio_data"

    if [ ! -d "$minio_backup_dir" ]; then
        log_error "MinIO data backup not found in $backup_dir"
        return 1
    fi

    # Clear existing data
    log_info "Clearing existing MinIO data..."
    if [ -d "$MINIO_DATA_DIR" ]; then
        rm -rf "${MINIO_DATA_DIR:?}/"*
    else
        mkdir -p "$MINIO_DATA_DIR"
    fi

    # Restore data
    log_info "Copying backup data to MinIO directory..."
    rsync -avz --progress "$minio_backup_dir/" "$MINIO_DATA_DIR/" 2>> "$LOG_FILE" | tee -a "$LOG_FILE"

    if [ $? -eq 0 ]; then
        log_success "MinIO data restored successfully"
    else
        log_error "MinIO data restore failed"
        return 1
    fi
}

restore_config() {
    local backup_dir="$1"
    log_info "Restoring configuration files..."

    local config_backup_dir="${backup_dir}/config"

    if [ ! -d "$config_backup_dir" ]; then
        log_warning "Configuration backup not found, skipping config restore"
        return 0
    fi

    # Restore configuration directory
    if [ -n "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        rsync -avz "$config_backup_dir/" "$CONFIG_DIR/" 2>> "$LOG_FILE"
    fi

    log_success "Configuration files restored successfully"
}

verify_restore() {
    log_info "Verifying restore..."

    # Check PostgreSQL
    log_info "Checking PostgreSQL connection..."
    if PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;" &> /dev/null; then
        log_success "PostgreSQL is accessible and database exists"
    else
        log_error "PostgreSQL verification failed"
        return 1
    fi

    # Check Redis
    log_info "Checking Redis connection..."
    if [ -n "$REDIS_PASSWORD" ]; then
        if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" PING &> /dev/null; then
            log_success "Redis is accessible"
        else
            log_error "Redis verification failed"
            return 1
        fi
    else
        if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" PING &> /dev/null; then
            log_success "Redis is accessible"
        else
            log_error "Redis verification failed"
            return 1
        fi
    fi

    # Check MinIO data
    if [ -d "$MINIO_DATA_DIR" ]; then
        local file_count=$(find "$MINIO_DATA_DIR" -type f | wc -l)
        log_success "MinIO data directory verified ($file_count files)"
    else
        log_error "MinIO data directory not found"
        return 1
    fi

    log_success "Restore verification completed successfully"
}

print_summary() {
    local backup_dir="$1"
    local duration="$2"
    local rollback_dir="${3:-}"

    echo ""
    log_info "======================================"
    log_info "Restore Summary"
    log_info "======================================"
    log_info "Restored From: $backup_dir"
    log_info "Timestamp: $TIMESTAMP"
    log_info "Duration: ${duration}s"

    if [ -n "$rollback_dir" ]; then
        log_info "Rollback Point: $rollback_dir"
        log_info "To rollback, run: $0 $rollback_dir"
    fi

    log_info "Log File: $LOG_FILE"
    log_info "======================================"
    echo ""
}

# Main execution
main() {
    local start_time=$(date +%s)

    log_info "======================================"
    log_info "MinIO Enterprise Restore Script"
    log_info "======================================"
    log_info "Timestamp: $TIMESTAMP"
    log_info "======================================"
    echo ""

    # Pre-flight checks
    check_dependencies

    # Select backup to restore
    select_backup "$@"

    # Verify backup integrity
    verify_backup_integrity "$SELECTED_BACKUP"

    # Confirm restore
    echo ""
    log_warning "WARNING: This will overwrite current data!"
    log_info "Backup to restore: $SELECTED_BACKUP"
    echo -n "Are you sure you want to continue? (yes/no): "
    read -r confirmation

    if [ "$confirmation" != "yes" ]; then
        log_info "Restore cancelled by user"
        exit 0
    fi
    echo ""

    # Create rollback point
    local rollback_dir=""
    if [ "$CREATE_ROLLBACK" = "true" ]; then
        rollback_dir=$(create_rollback_point)
    fi

    # Stop services
    stop_services

    # Perform restore
    restore_postgresql "$SELECTED_BACKUP" || {
        log_error "PostgreSQL restore failed"
        start_services
        exit 1
    }

    restore_redis "$SELECTED_BACKUP" || {
        log_warning "Redis restore failed, continuing..."
    }

    restore_minio_data "$SELECTED_BACKUP" || {
        log_error "MinIO data restore failed"
        start_services
        exit 1
    }

    restore_config "$SELECTED_BACKUP" || {
        log_warning "Config restore failed, continuing..."
    }

    # Start services
    start_services

    # Wait for services to start
    log_info "Waiting for services to start..."
    sleep 5

    # Verify restore
    if [ "$VERIFY_RESTORE" = "true" ]; then
        verify_restore || {
            log_error "Restore verification failed"
            if [ -n "$rollback_dir" ]; then
                log_info "Consider rolling back using: $0 $rollback_dir"
            fi
            exit 1
        }
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    print_summary "$SELECTED_BACKUP" "$duration" "$rollback_dir"

    log_success "Restore completed successfully!"
}

# Run main function
main "$@"
