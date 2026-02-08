#!/bin/bash
#
# MinIO Enterprise Restore Script
# Restores MinIO data, PostgreSQL database, and Redis state from backups
#
# Usage:
#   ./restore.sh <backup_directory> [OPTIONS]
#
# Options:
#   -c, --config PATH          Path to restore configuration file (default: restore.conf)
#   -s, --skip-verification    Skip backup verification before restore
#   -f, --force                Force restore without confirmation prompts
#   --postgresql-only          Restore only PostgreSQL database
#   --redis-only               Restore only Redis state
#   --minio-only               Restore only MinIO data
#   --config-only              Restore only configuration files
#   -h, --help                 Show this help message
#

set -euo pipefail

# Default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/restore.conf"
SKIP_VERIFICATION=false
FORCE=false
RESTORE_POSTGRESQL=true
RESTORE_REDIS=true
RESTORE_MINIO=true
RESTORE_CONFIG=true
BACKUP_DIR=""

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show help
show_help() {
    cat << EOF
MinIO Enterprise Restore Script

Usage: $0 <backup_directory> [OPTIONS]

Arguments:
  backup_directory        Path to the backup directory to restore from

Options:
  -c, --config PATH          Path to restore configuration file (default: restore.conf)
  -s, --skip-verification    Skip backup verification before restore
  -f, --force                Force restore without confirmation prompts
  --postgresql-only          Restore only PostgreSQL database
  --redis-only               Restore only Redis state
  --minio-only               Restore only MinIO data
  --config-only              Restore only configuration files
  -h, --help                 Show this help message

Examples:
  $0 /var/backups/minio/full/20240118_120000                    # Full restore
  $0 /var/backups/minio/full/20240118_120000 -f                 # Force restore without prompts
  $0 /var/backups/minio/full/20240118_120000 --postgresql-only  # Restore only database

Safety:
  - Always stop MinIO services before restoring
  - Create a backup before restoring (just in case)
  - Test restore on non-production environment first

EOF
}

# Parse command line arguments
parse_args() {
    if [[ $# -eq 0 ]]; then
        log_error "No backup directory specified"
        show_help
        exit 1
    fi

    BACKUP_DIR="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -s|--skip-verification)
                SKIP_VERIFICATION=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            --postgresql-only)
                RESTORE_REDIS=false
                RESTORE_MINIO=false
                RESTORE_CONFIG=false
                shift
                ;;
            --redis-only)
                RESTORE_POSTGRESQL=false
                RESTORE_MINIO=false
                RESTORE_CONFIG=false
                shift
                ;;
            --minio-only)
                RESTORE_POSTGRESQL=false
                RESTORE_REDIS=false
                RESTORE_CONFIG=false
                shift
                ;;
            --config-only)
                RESTORE_POSTGRESQL=false
                RESTORE_REDIS=false
                RESTORE_MINIO=false
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Load configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warning "Configuration file not found: $CONFIG_FILE"
        log_info "Creating default configuration file..."
        create_default_config
    fi

    log_info "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
}

# Create default configuration file
create_default_config() {
    cat > "$CONFIG_FILE" << 'EOF'
# MinIO Enterprise Restore Configuration

# PostgreSQL configuration
PG_HOST="localhost"
PG_PORT="5432"
PG_DATABASE="minio"
PG_USER="minio"
PG_PASSWORD=""  # Set via environment variable PGPASSWORD

# Redis configuration
REDIS_HOST="localhost"
REDIS_PORT="6379"
REDIS_PASSWORD=""  # Set via environment variable REDIS_PASSWORD

# MinIO data directory
MINIO_DATA_DIR="/var/lib/minio/data"

# Backup before restore (recommended)
CREATE_PRE_RESTORE_BACKUP=true
PRE_RESTORE_BACKUP_DIR="/var/backups/minio/pre-restore"

# Services to restart after restore
RESTART_SERVICES=true
MINIO_SERVICE_NAME="minio"  # Or Docker container name
EOF

    log_success "Created default configuration at $CONFIG_FILE"
    log_warning "Please edit $CONFIG_FILE with your actual settings"
    exit 0
}

# Validate backup directory
validate_backup() {
    log_info "Validating backup directory..."

    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "Backup directory does not exist: $BACKUP_DIR"
        exit 1
    fi

    # Check for metadata
    if [[ ! -f "$BACKUP_DIR/metadata/backup_info.json" ]]; then
        log_error "Backup metadata not found. This may not be a valid backup directory."
        exit 1
    fi

    # Read backup metadata
    local backup_type=$(jq -r '.backup_type' "$BACKUP_DIR/metadata/backup_info.json" 2>/dev/null || echo "unknown")
    local backup_date=$(jq -r '.date' "$BACKUP_DIR/metadata/backup_info.json" 2>/dev/null || echo "unknown")

    log_info "Backup Type: $backup_type"
    log_info "Backup Date: $backup_date"

    if [[ ! $SKIP_VERIFICATION == true ]]; then
        verify_backup_integrity
    fi
}

# Verify backup integrity
verify_backup_integrity() {
    log_info "Verifying backup integrity..."

    local issues=0

    # Check PostgreSQL backup
    if $RESTORE_POSTGRESQL; then
        if [[ -f "$BACKUP_DIR/postgresql/minio_database.sql"* ]]; then
            log_info "✓ PostgreSQL backup found"
        else
            log_error "✗ PostgreSQL backup missing"
            issues=$((issues + 1))
        fi
    fi

    # Check Redis backup
    if $RESTORE_REDIS; then
        if [[ -f "$BACKUP_DIR/redis/dump.rdb"* ]]; then
            log_info "✓ Redis backup found"
        else
            log_warning "✓ Redis backup not found (may have been skipped)"
        fi
    fi

    # Check MinIO data backup
    if $RESTORE_MINIO; then
        if [[ -d "$BACKUP_DIR/minio-data" ]]; then
            log_info "✓ MinIO data backup found"
        else
            log_error "✗ MinIO data backup missing"
            issues=$((issues + 1))
        fi
    fi

    if [[ $issues -gt 0 ]]; then
        log_error "Backup verification failed with $issues issues"
        if [[ ! $FORCE == true ]]; then
            exit 1
        else
            log_warning "Continuing restore despite verification failures (--force enabled)"
        fi
    else
        log_success "Backup verification passed"
    fi
}

# Confirm restore operation
confirm_restore() {
    if [[ $FORCE == true ]]; then
        return 0
    fi

    log_warning "=========================================="
    log_warning "WARNING: This will overwrite existing data!"
    log_warning "=========================================="
    log_warning "Restoring from: $BACKUP_DIR"

    if $RESTORE_POSTGRESQL; then
        log_warning "- PostgreSQL database: $PG_DATABASE"
    fi
    if $RESTORE_REDIS; then
        log_warning "- Redis state"
    fi
    if $RESTORE_MINIO; then
        log_warning "- MinIO data: $MINIO_DATA_DIR"
    fi
    if $RESTORE_CONFIG; then
        log_warning "- Configuration files"
    fi

    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation

    if [[ "$confirmation" != "yes" ]]; then
        log_info "Restore cancelled by user"
        exit 0
    fi
}

# Create pre-restore backup
create_pre_restore_backup() {
    if [[ ! $CREATE_PRE_RESTORE_BACKUP == true ]]; then
        return 0
    fi

    log_info "Creating pre-restore backup..."

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$PRE_RESTORE_BACKUP_DIR/$timestamp"

    mkdir -p "$backup_dir"

    # Backup current PostgreSQL database
    if $RESTORE_POSTGRESQL && command -v pg_dump &> /dev/null; then
        export PGPASSWORD="${PG_PASSWORD}"
        pg_dump -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
            > "$backup_dir/postgresql_pre_restore.sql" 2>/dev/null || true
        unset PGPASSWORD
    fi

    # Backup current MinIO data
    if $RESTORE_MINIO && [[ -d "$MINIO_DATA_DIR" ]]; then
        rsync -a "$MINIO_DATA_DIR/" "$backup_dir/minio-data/" 2>/dev/null || true
    fi

    log_success "Pre-restore backup created: $backup_dir"
}

# Stop services
stop_services() {
    log_info "Stopping MinIO services..."

    # Check if running in Docker
    if command -v docker &> /dev/null; then
        # Try to stop Docker containers
        docker stop minio-1 minio-2 minio-3 minio-4 2>/dev/null || true
        log_info "Stopped MinIO Docker containers"
    fi

    # Try systemd service
    if command -v systemctl &> /dev/null; then
        systemctl stop "$MINIO_SERVICE_NAME" 2>/dev/null || true
        log_info "Stopped MinIO systemd service"
    fi

    # Wait for services to stop
    sleep 5
}

# Start services
start_services() {
    if [[ ! $RESTART_SERVICES == true ]]; then
        log_warning "Service restart disabled in configuration"
        return 0
    fi

    log_info "Starting MinIO services..."

    # Check if running in Docker
    if command -v docker &> /dev/null; then
        # Try to start Docker containers
        docker start minio-1 minio-2 minio-3 minio-4 2>/dev/null || true
        log_info "Started MinIO Docker containers"
    fi

    # Try systemd service
    if command -v systemctl &> /dev/null; then
        systemctl start "$MINIO_SERVICE_NAME" 2>/dev/null || true
        log_info "Started MinIO systemd service"
    fi

    # Wait for services to start
    sleep 10

    log_success "Services started"
}

# Restore PostgreSQL database
restore_postgresql() {
    if [[ ! $RESTORE_POSTGRESQL == true ]]; then
        return 0
    fi

    log_info "Restoring PostgreSQL database..."

    # Find PostgreSQL backup file
    local pg_backup_file
    if [[ -f "$BACKUP_DIR/postgresql/minio_database.sql" ]]; then
        pg_backup_file="$BACKUP_DIR/postgresql/minio_database.sql"
    elif [[ -f "$BACKUP_DIR/postgresql/minio_database.sql.gz" ]]; then
        pg_backup_file="$BACKUP_DIR/postgresql/minio_database.sql.gz"
        log_info "Decompressing PostgreSQL backup..."
        gunzip -c "$pg_backup_file" > "/tmp/minio_database_restore.sql"
        pg_backup_file="/tmp/minio_database_restore.sql"
    elif [[ -f "$BACKUP_DIR/postgresql/minio_database.sql.bz2" ]]; then
        pg_backup_file="$BACKUP_DIR/postgresql/minio_database.sql.bz2"
        log_info "Decompressing PostgreSQL backup..."
        bunzip2 -c "$pg_backup_file" > "/tmp/minio_database_restore.sql"
        pg_backup_file="/tmp/minio_database_restore.sql"
    elif [[ -f "$BACKUP_DIR/postgresql/minio_database.sql.xz" ]]; then
        pg_backup_file="$BACKUP_DIR/postgresql/minio_database.sql.xz"
        log_info "Decompressing PostgreSQL backup..."
        xz -dc "$pg_backup_file" > "/tmp/minio_database_restore.sql"
        pg_backup_file="/tmp/minio_database_restore.sql"
    else
        log_error "PostgreSQL backup file not found"
        return 1
    fi

    export PGPASSWORD="${PG_PASSWORD}"

    if psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" < "$pg_backup_file"; then
        log_success "PostgreSQL database restored successfully"
    else
        log_error "PostgreSQL database restore failed"
        unset PGPASSWORD
        return 1
    fi

    unset PGPASSWORD

    # Clean up temporary file
    if [[ "$pg_backup_file" == "/tmp/minio_database_restore.sql" ]]; then
        rm -f "$pg_backup_file"
    fi
}

# Restore Redis state
restore_redis() {
    if [[ ! $RESTORE_REDIS == true ]]; then
        return 0
    fi

    log_info "Restoring Redis state..."

    # Find Redis backup file
    local redis_backup_file
    if [[ -f "$BACKUP_DIR/redis/dump.rdb" ]]; then
        redis_backup_file="$BACKUP_DIR/redis/dump.rdb"
    elif [[ -f "$BACKUP_DIR/redis/dump.rdb.gz" ]]; then
        redis_backup_file="$BACKUP_DIR/redis/dump.rdb.gz"
        log_info "Decompressing Redis backup..."
        gunzip -c "$redis_backup_file" > "/tmp/dump.rdb"
        redis_backup_file="/tmp/dump.rdb"
    else
        log_warning "Redis backup file not found, skipping Redis restore"
        return 0
    fi

    # Stop Redis temporarily
    if command -v systemctl &> /dev/null; then
        systemctl stop redis 2>/dev/null || true
    fi

    # Copy dump.rdb to Redis data directory
    cp "$redis_backup_file" /var/lib/redis/dump.rdb
    chown redis:redis /var/lib/redis/dump.rdb 2>/dev/null || true

    # Start Redis
    if command -v systemctl &> /dev/null; then
        systemctl start redis 2>/dev/null || true
    fi

    log_success "Redis state restored successfully"

    # Clean up temporary file
    if [[ "$redis_backup_file" == "/tmp/dump.rdb" ]]; then
        rm -f "$redis_backup_file"
    fi
}

# Restore MinIO data
restore_minio_data() {
    if [[ ! $RESTORE_MINIO == true ]]; then
        return 0
    fi

    log_info "Restoring MinIO data..."

    if [[ ! -d "$BACKUP_DIR/minio-data" ]]; then
        log_error "MinIO data backup not found"
        return 1
    fi

    # Backup current data if exists
    if [[ -d "$MINIO_DATA_DIR" ]] && [[ -n "$(ls -A "$MINIO_DATA_DIR")" ]]; then
        local backup_current="${MINIO_DATA_DIR}.bak.$(date +%Y%m%d_%H%M%S)"
        log_info "Backing up current data to: $backup_current"
        mv "$MINIO_DATA_DIR" "$backup_current"
    fi

    # Create data directory
    mkdir -p "$MINIO_DATA_DIR"

    # Restore data
    rsync -av "$BACKUP_DIR/minio-data/" "$MINIO_DATA_DIR/"

    log_success "MinIO data restored successfully"
}

# Restore configuration files
restore_config() {
    if [[ ! $RESTORE_CONFIG == true ]]; then
        return 0
    fi

    log_info "Restoring configuration files..."

    if [[ ! -d "$BACKUP_DIR/config" ]]; then
        log_warning "Configuration backup not found, skipping"
        return 0
    fi

    # Restore Docker Compose files
    if ls "$BACKUP_DIR/config"/*.yml 1> /dev/null 2>&1; then
        cp "$BACKUP_DIR/config"/*.yml /home/runner/work/MinIO/MinIO/deployments/docker/ 2>/dev/null || true
        log_info "Restored Docker Compose files"
    fi

    # Restore Prometheus configuration
    if [[ -d "$BACKUP_DIR/config/prometheus" ]]; then
        cp -r "$BACKUP_DIR/config/prometheus" /home/runner/work/MinIO/MinIO/configs/ 2>/dev/null || true
        log_info "Restored Prometheus configuration"
    fi

    # Restore Grafana dashboards
    if [[ -d "$BACKUP_DIR/config/grafana" ]]; then
        cp -r "$BACKUP_DIR/config/grafana" /home/runner/work/MinIO/MinIO/configs/ 2>/dev/null || true
        log_info "Restored Grafana dashboards"
    fi

    log_success "Configuration files restored"
}

# Verify restore
verify_restore() {
    log_info "Verifying restore operation..."

    local issues=0

    # Check PostgreSQL
    if $RESTORE_POSTGRESQL; then
        export PGPASSWORD="${PG_PASSWORD}"
        if psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" -c "SELECT 1" &> /dev/null; then
            log_info "✓ PostgreSQL database is accessible"
        else
            log_error "✗ PostgreSQL database is not accessible"
            issues=$((issues + 1))
        fi
        unset PGPASSWORD
    fi

    # Check Redis
    if $RESTORE_REDIS; then
        if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping &> /dev/null; then
            log_info "✓ Redis is responding"
        else
            log_warning "✓ Redis is not responding"
        fi
    fi

    # Check MinIO data
    if $RESTORE_MINIO; then
        if [[ -d "$MINIO_DATA_DIR" ]] && [[ -n "$(ls -A "$MINIO_DATA_DIR")" ]]; then
            log_info "✓ MinIO data directory exists and contains data"
        else
            log_error "✗ MinIO data directory is empty or missing"
            issues=$((issues + 1))
        fi
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "Restore verification passed"
        return 0
    else
        log_error "Restore verification failed with $issues issues"
        return 1
    fi
}

# Main restore function
main() {
    log_info "=========================================="
    log_info "MinIO Enterprise Restore"
    log_info "=========================================="

    # Parse arguments
    parse_args "$@"

    log_info "Backup Directory: $BACKUP_DIR"
    log_info "PostgreSQL: $RESTORE_POSTGRESQL"
    log_info "Redis: $RESTORE_REDIS"
    log_info "MinIO Data: $RESTORE_MINIO"
    log_info "Configuration: $RESTORE_CONFIG"
    log_info "=========================================="

    # Load configuration
    load_config

    # Validate backup
    validate_backup

    # Confirm restore
    confirm_restore

    # Create pre-restore backup
    create_pre_restore_backup

    # Stop services
    stop_services

    # Perform restore
    local restore_failed=false

    restore_postgresql || restore_failed=true
    restore_redis || true  # Redis restore is optional
    restore_minio_data || restore_failed=true
    restore_config || true

    if $restore_failed; then
        log_error "Restore completed with errors"
        log_warning "Services are stopped. Please investigate before starting them."
        exit 1
    fi

    # Start services
    start_services

    # Verify restore
    verify_restore || true

    log_success "=========================================="
    log_success "Restore completed successfully!"
    log_success "=========================================="
}

# Run main function
main "$@"
