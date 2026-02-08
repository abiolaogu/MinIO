#!/bin/bash
#
# MinIO Enterprise Restore Script
# Restores MinIO data, PostgreSQL database, Redis state, and configuration from backup
#
# Usage: ./restore.sh [OPTIONS] BACKUP_PATH
# Options:
#   --verify        Verify backup integrity before restore
#   --rollback      Create rollback point before restore
#   --force         Skip confirmation prompts
#   --decrypt       Decrypt backup before restore
#   --data-only     Restore only MinIO data
#   --db-only       Restore only PostgreSQL database
#   --config-only   Restore only configuration files
#   --help          Show this help message

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY_BACKUP=false
CREATE_ROLLBACK=false
FORCE_RESTORE=false
DECRYPT=false
RESTORE_DATA=true
RESTORE_DB=true
RESTORE_REDIS=true
RESTORE_CONFIG=true

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# Show usage
show_usage() {
    cat << EOF
MinIO Enterprise Restore Script

Usage: $0 [OPTIONS] BACKUP_PATH

Arguments:
  BACKUP_PATH     Path to backup directory or archive file

Options:
  --verify        Verify backup integrity before restore
  --rollback      Create rollback point before restore
  --force         Skip confirmation prompts
  --decrypt       Decrypt backup before restore (requires gpg)
  --data-only     Restore only MinIO data
  --db-only       Restore only PostgreSQL database
  --config-only   Restore only configuration files
  --help          Show this help message

Examples:
  $0 --verify --rollback /var/backups/minio/minio-backup-full-20260208_142000
  $0 --force --decrypt /var/backups/minio/minio-backup-full-20260208_142000.tar.gz.gpg
  $0 --db-only /var/backups/minio/minio-backup-full-20260208_142000

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verify)
                VERIFY_BACKUP=true
                shift
                ;;
            --rollback)
                CREATE_ROLLBACK=true
                shift
                ;;
            --force)
                FORCE_RESTORE=true
                shift
                ;;
            --decrypt)
                DECRYPT=true
                shift
                ;;
            --data-only)
                RESTORE_DB=false
                RESTORE_REDIS=false
                RESTORE_CONFIG=false
                shift
                ;;
            --db-only)
                RESTORE_DATA=false
                RESTORE_REDIS=false
                RESTORE_CONFIG=false
                shift
                ;;
            --config-only)
                RESTORE_DATA=false
                RESTORE_DB=false
                RESTORE_REDIS=false
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                BACKUP_PATH="$1"
                shift
                ;;
        esac
    done

    if [[ -z "${BACKUP_PATH:-}" ]]; then
        log_error "Backup path not specified"
        show_usage
        exit 1
    fi
}

# Load environment configuration
load_config() {
    # Default configuration
    POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
    POSTGRES_PORT="${POSTGRES_PORT:-5432}"
    POSTGRES_DB="${POSTGRES_DB:-minio}"
    POSTGRES_USER="${POSTGRES_USER:-minio}"

    REDIS_HOST="${REDIS_HOST:-localhost}"
    REDIS_PORT="${REDIS_PORT:-6379}"

    MINIO_DATA_DIR="${MINIO_DATA_DIR:-/data/minio}"
    MINIO_CONFIG_DIR="${MINIO_CONFIG_DIR:-/etc/minio}"

    RESTORE_TEMP_DIR="/tmp/minio-restore-$$"

    log_info "Configuration loaded"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    command -v tar >/dev/null 2>&1 || missing_tools+=("tar")

    if [[ "$RESTORE_DB" == true ]]; then
        command -v pg_restore >/dev/null 2>&1 || missing_tools+=("postgresql-client")
    fi

    if [[ "$RESTORE_REDIS" == true ]]; then
        command -v redis-cli >/dev/null 2>&1 || missing_tools+=("redis-tools")
    fi

    if [[ "$DECRYPT" == true ]]; then
        command -v gpg >/dev/null 2>&1 || missing_tools+=("gnupg")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    # Check backup exists
    if [[ ! -e "$BACKUP_PATH" ]]; then
        log_error "Backup not found: $BACKUP_PATH"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Verify backup integrity
verify_backup_integrity() {
    if [[ "$VERIFY_BACKUP" != true ]]; then
        return 0
    fi

    log_info "Verifying backup integrity..."

    # Check checksum file
    local checksum_file="$(dirname "$BACKUP_PATH")/backup.checksum"
    if [[ -f "$checksum_file" ]]; then
        local expected_checksum=$(grep "checksum_sha256=" "$checksum_file" | cut -d= -f2)
        local actual_checksum=$(sha256sum "$BACKUP_PATH" | cut -d' ' -f1)

        if [[ "$expected_checksum" == "$actual_checksum" ]]; then
            log_success "Checksum verification passed"
        else
            log_error "Checksum verification failed"
            log_error "Expected: $expected_checksum"
            log_error "Actual: $actual_checksum"
            return 1
        fi
    else
        log_warning "Checksum file not found, skipping verification"
    fi

    # Test archive if compressed
    if [[ "$BACKUP_PATH" == *.tar.gz ]]; then
        if gzip -t "$BACKUP_PATH" 2>/dev/null; then
            log_success "Archive integrity verified"
        else
            log_error "Archive integrity check failed"
            return 1
        fi
    fi

    log_success "Backup integrity verification passed"
}

# Decrypt backup
decrypt_backup() {
    if [[ "$DECRYPT" != true ]]; then
        return 0
    fi

    log_info "Decrypting backup..."

    if [[ "$BACKUP_PATH" != *.gpg ]]; then
        log_warning "Backup does not appear to be encrypted (no .gpg extension)"
        return 0
    fi

    local decrypted_file="${BACKUP_PATH%.gpg}"

    if gpg --decrypt --output "$decrypted_file" "$BACKUP_PATH" 2>/dev/null; then
        log_success "Backup decrypted"
        BACKUP_PATH="$decrypted_file"
    else
        log_error "Decryption failed"
        return 1
    fi
}

# Extract backup
extract_backup() {
    log_info "Extracting backup..."

    mkdir -p "$RESTORE_TEMP_DIR"

    if [[ -d "$BACKUP_PATH" ]]; then
        # Backup is a directory
        log_info "Backup is a directory, copying contents..."
        cp -r "$BACKUP_PATH"/* "$RESTORE_TEMP_DIR/"
    elif [[ -f "$BACKUP_PATH" ]]; then
        # Backup is an archive
        if [[ "$BACKUP_PATH" == *.tar.gz ]]; then
            log_info "Extracting compressed archive..."
            tar -xzf "$BACKUP_PATH" -C "$RESTORE_TEMP_DIR" --strip-components=1 2>/dev/null
        elif [[ "$BACKUP_PATH" == *.tar ]]; then
            log_info "Extracting archive..."
            tar -xf "$BACKUP_PATH" -C "$RESTORE_TEMP_DIR" --strip-components=1 2>/dev/null
        else
            log_error "Unsupported backup format: $BACKUP_PATH"
            return 1
        fi
    else
        log_error "Invalid backup path: $BACKUP_PATH"
        return 1
    fi

    log_success "Backup extracted to $RESTORE_TEMP_DIR"
}

# Read backup metadata
read_backup_metadata() {
    log_info "Reading backup metadata..."

    local metadata_file="${RESTORE_TEMP_DIR}/metadata/backup.info"

    if [[ ! -f "$metadata_file" ]]; then
        log_warning "Backup metadata not found"
        return 0
    fi

    # shellcheck source=/dev/null
    source "$metadata_file"

    log_info "Backup information:"
    log_info "  Type: ${backup_type:-unknown}"
    log_info "  Timestamp: ${timestamp:-unknown}"
    log_info "  Hostname: ${hostname:-unknown}"
    log_info "  Started: ${started_at:-unknown}"
    log_info "  Status: ${status:-unknown}"
}

# Create rollback point
create_rollback_point() {
    if [[ "$CREATE_ROLLBACK" != true ]]; then
        return 0
    fi

    log_info "Creating rollback point..."

    local rollback_dir="/var/backups/minio/rollback-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$rollback_dir"

    # Backup current state
    if [[ -d "$MINIO_DATA_DIR" ]]; then
        tar -czf "${rollback_dir}/data.tar.gz" -C "$(dirname "$MINIO_DATA_DIR")" "$(basename "$MINIO_DATA_DIR")" 2>/dev/null || true
    fi

    if [[ "$RESTORE_DB" == true ]]; then
        PGPASSWORD="${POSTGRES_PASSWORD:-}" pg_dump \
            -h "$POSTGRES_HOST" \
            -p "$POSTGRES_PORT" \
            -U "$POSTGRES_USER" \
            -d "$POSTGRES_DB" \
            --format=custom \
            --file="${rollback_dir}/database.dump" 2>/dev/null || true
    fi

    log_success "Rollback point created: $rollback_dir"
    echo "$rollback_dir" > /tmp/minio-last-rollback
}

# Confirm restore
confirm_restore() {
    if [[ "$FORCE_RESTORE" == true ]]; then
        return 0
    fi

    log_warning "============================================"
    log_warning "WARNING: This will replace current data!"
    log_warning "============================================"
    log_warning "Restore components:"
    [[ "$RESTORE_DATA" == true ]] && log_warning "  - MinIO data"
    [[ "$RESTORE_DB" == true ]] && log_warning "  - PostgreSQL database"
    [[ "$RESTORE_REDIS" == true ]] && log_warning "  - Redis state"
    [[ "$RESTORE_CONFIG" == true ]] && log_warning "  - Configuration files"
    log_warning "============================================"

    read -p "Continue with restore? (yes/no): " -r
    echo

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Restore cancelled by user"
        exit 0
    fi
}

# Stop services
stop_services() {
    log_info "Stopping MinIO services..."

    # Try to stop via docker-compose
    if command -v docker-compose >/dev/null 2>&1; then
        local compose_file="deployments/docker/docker-compose.production.yml"
        if [[ -f "$compose_file" ]]; then
            docker-compose -f "$compose_file" stop minio-node1 minio-node2 minio-node3 minio-node4 2>/dev/null || true
        fi
    fi

    # Try to stop via systemd
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop minio 2>/dev/null || true
    fi

    log_success "Services stopped"
}

# Start services
start_services() {
    log_info "Starting MinIO services..."

    # Try to start via docker-compose
    if command -v docker-compose >/dev/null 2>&1; then
        local compose_file="deployments/docker/docker-compose.production.yml"
        if [[ -f "$compose_file" ]]; then
            docker-compose -f "$compose_file" start minio-node1 minio-node2 minio-node3 minio-node4 2>/dev/null || true
        fi
    fi

    # Try to start via systemd
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start minio 2>/dev/null || true
    fi

    log_success "Services started"
}

# Restore PostgreSQL database
restore_postgresql() {
    if [[ "$RESTORE_DB" != true ]]; then
        log_info "Skipping PostgreSQL restore (not requested)"
        return 0
    fi

    log_info "Restoring PostgreSQL database..."

    local dump_file="${RESTORE_TEMP_DIR}/database/minio.sql"

    if [[ ! -f "$dump_file" ]]; then
        log_warning "Database backup not found in restore archive"
        return 0
    fi

    # Drop and recreate database
    PGPASSWORD="${POSTGRES_PASSWORD:-}" psql \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -c "DROP DATABASE IF EXISTS ${POSTGRES_DB}_old;" 2>/dev/null || true

    PGPASSWORD="${POSTGRES_PASSWORD:-}" psql \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -c "ALTER DATABASE ${POSTGRES_DB} RENAME TO ${POSTGRES_DB}_old;" 2>/dev/null || true

    PGPASSWORD="${POSTGRES_PASSWORD:-}" psql \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -c "CREATE DATABASE ${POSTGRES_DB};" 2>/dev/null

    # Restore from dump
    PGPASSWORD="${POSTGRES_PASSWORD:-}" pg_restore \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        --no-owner \
        --no-privileges \
        "$dump_file" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        log_success "PostgreSQL database restored"
        # Drop old database
        PGPASSWORD="${POSTGRES_PASSWORD:-}" psql \
            -h "$POSTGRES_HOST" \
            -p "$POSTGRES_PORT" \
            -U "$POSTGRES_USER" \
            -c "DROP DATABASE IF EXISTS ${POSTGRES_DB}_old;" 2>/dev/null || true
    else
        log_error "PostgreSQL restore failed, attempting rollback..."
        PGPASSWORD="${POSTGRES_PASSWORD:-}" psql \
            -h "$POSTGRES_HOST" \
            -p "$POSTGRES_PORT" \
            -U "$POSTGRES_USER" \
            -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};" 2>/dev/null || true
        PGPASSWORD="${POSTGRES_PASSWORD:-}" psql \
            -h "$POSTGRES_HOST" \
            -p "$POSTGRES_PORT" \
            -U "$POSTGRES_USER" \
            -c "ALTER DATABASE ${POSTGRES_DB}_old RENAME TO ${POSTGRES_DB};" 2>/dev/null || true
        return 1
    fi
}

# Restore Redis state
restore_redis() {
    if [[ "$RESTORE_REDIS" != true ]]; then
        log_info "Skipping Redis restore (not requested)"
        return 0
    fi

    log_info "Restoring Redis state..."

    local redis_dump="${RESTORE_TEMP_DIR}/redis/dump.rdb"

    if [[ ! -f "$redis_dump" ]]; then
        log_warning "Redis backup not found in restore archive"
        return 0
    fi

    # Stop Redis, replace dump, restart
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop redis 2>/dev/null || true
        cp "$redis_dump" /var/lib/redis/dump.rdb
        chown redis:redis /var/lib/redis/dump.rdb 2>/dev/null || true
        systemctl start redis 2>/dev/null || true
        log_success "Redis state restored"
    else
        log_warning "Cannot control Redis service, manual restore required"
    fi
}

# Restore MinIO data
restore_minio_data() {
    if [[ "$RESTORE_DATA" != true ]]; then
        log_info "Skipping MinIO data restore (not requested)"
        return 0
    fi

    log_info "Restoring MinIO data..."

    local data_backup="${RESTORE_TEMP_DIR}/data/objects.tar"

    if [[ ! -f "$data_backup" ]]; then
        log_warning "MinIO data backup not found in restore archive"
        return 0
    fi

    # Backup current data
    if [[ -d "$MINIO_DATA_DIR" ]]; then
        mv "$MINIO_DATA_DIR" "${MINIO_DATA_DIR}.old"
    fi

    # Extract data
    mkdir -p "$(dirname "$MINIO_DATA_DIR")"
    tar -xf "$data_backup" -C "$(dirname "$MINIO_DATA_DIR")" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        log_success "MinIO data restored"
        # Remove old data
        rm -rf "${MINIO_DATA_DIR}.old" 2>/dev/null || true
    else
        log_error "MinIO data restore failed, attempting rollback..."
        rm -rf "$MINIO_DATA_DIR" 2>/dev/null || true
        [[ -d "${MINIO_DATA_DIR}.old" ]] && mv "${MINIO_DATA_DIR}.old" "$MINIO_DATA_DIR"
        return 1
    fi
}

# Restore configuration
restore_configuration() {
    if [[ "$RESTORE_CONFIG" != true ]]; then
        log_info "Skipping configuration restore (not requested)"
        return 0
    fi

    log_info "Restoring configuration files..."

    local config_backup="${RESTORE_TEMP_DIR}/config/config.tar"

    if [[ ! -f "$config_backup" ]]; then
        log_warning "Configuration backup not found in restore archive"
        return 0
    fi

    # Extract configuration
    tar -xf "$config_backup" -C / 2>/dev/null

    if [[ $? -eq 0 ]]; then
        log_success "Configuration restored"
    else
        log_error "Configuration restore failed"
        return 1
    fi
}

# Cleanup temporary files
cleanup() {
    if [[ -d "$RESTORE_TEMP_DIR" ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf "$RESTORE_TEMP_DIR"
    fi
}

# Main restore function
main() {
    log_info "=========================================="
    log_info "MinIO Enterprise Restore"
    log_info "=========================================="

    # Parse arguments
    parse_args "$@"

    # Load configuration
    load_config

    # Check prerequisites
    check_prerequisites

    # Verify backup
    verify_backup_integrity

    # Decrypt if needed
    decrypt_backup

    # Extract backup
    extract_backup

    # Read metadata
    read_backup_metadata

    # Create rollback point
    create_rollback_point

    # Confirm restore
    confirm_restore

    # Stop services
    stop_services

    # Perform restore
    restore_postgresql || log_warning "PostgreSQL restore had errors"
    restore_redis || log_warning "Redis restore had errors"
    restore_minio_data || log_warning "MinIO data restore had errors"
    restore_configuration || log_warning "Configuration restore had errors"

    # Start services
    start_services

    # Cleanup
    cleanup

    log_info "=========================================="
    log_success "Restore completed"
    log_info "=========================================="
}

# Trap cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
