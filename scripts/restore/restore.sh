#!/usr/bin/env bash

# MinIO Enterprise - Restore Automation Script
# This script performs automated restoration of MinIO objects, PostgreSQL database,
# Redis snapshots, and configuration files with verification and rollback capabilities.

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/restore.conf}"

# Default configuration (can be overridden by restore.conf)
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/minio}"
BACKUP_TO_RESTORE="${BACKUP_TO_RESTORE:-latest}"  # latest, specific date (YYYYMMDD_HHMMSS), or full path
RESTORE_DATE="$(date +%Y%m%d_%H%M%S)"
VERIFY_RESTORE="${VERIFY_RESTORE:-true}"
CREATE_ROLLBACK="${CREATE_ROLLBACK:-true}"
ROLLBACK_DIR="${ROLLBACK_DIR:-/var/backups/minio/rollback_${RESTORE_DATE}}"
LOG_FILE="${LOG_FILE:-${BACKUP_ROOT}/restore.log}"

# Component flags
RESTORE_MINIO="${RESTORE_MINIO:-true}"
RESTORE_POSTGRES="${RESTORE_POSTGRES:-true}"
RESTORE_REDIS="${RESTORE_REDIS:-true}"
RESTORE_CONFIG="${RESTORE_CONFIG:-true}"

# Decryption
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"

# MinIO configuration
MINIO_DATA_DIR="${MINIO_DATA_DIR:-${PROJECT_ROOT}/data/minio}"

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
REDIS_DATA_DIR="${REDIS_DATA_DIR:-/var/lib/redis}"

# Service control
STOP_SERVICES="${STOP_SERVICES:-true}"
START_SERVICES="${START_SERVICES:-true}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
    log "INFO" "$*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
    log "SUCCESS" "$*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
    log "WARNING" "$*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
    log "ERROR" "$*"
}

# Load configuration file if exists
load_config() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        log_info "Loading configuration from ${CONFIG_FILE}"
        # shellcheck source=/dev/null
        source "${CONFIG_FILE}"
    else
        log_warning "Configuration file not found: ${CONFIG_FILE}"
        log_warning "Using default configuration"
    fi
}

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()

    [[ "${RESTORE_POSTGRES}" == "true" ]] && ! command -v psql >/dev/null 2>&1 && missing_deps+=("psql (postgresql-client)")
    [[ "${RESTORE_POSTGRES}" == "true" ]] && ! command -v pg_restore >/dev/null 2>&1 && missing_deps+=("pg_restore (postgresql-client)")
    [[ "${RESTORE_REDIS}" == "true" ]] && ! command -v redis-cli >/dev/null 2>&1 && missing_deps+=("redis-cli (redis-tools)")
    ! command -v tar >/dev/null 2>&1 && missing_deps+=("tar")
    ! command -v gzip >/dev/null 2>&1 && missing_deps+=("gzip")
    [[ -n "${ENCRYPTION_KEY}" ]] && ! command -v openssl >/dev/null 2>&1 && missing_deps+=("openssl")

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_error "Install with: apt-get install postgresql-client redis-tools tar gzip openssl"
        return 1
    fi

    log_success "All dependencies satisfied"
    return 0
}

# Find backup directory to restore
find_backup_dir() {
    log_info "Finding backup to restore: ${BACKUP_TO_RESTORE}"

    local backup_dir=""

    if [[ "${BACKUP_TO_RESTORE}" == "latest" ]]; then
        # Find the most recent backup
        backup_dir=$(find "${BACKUP_ROOT}" -maxdepth 1 -type d -name "[0-9]*_[0-9]*" 2>/dev/null | sort -r | head -n 1)

        if [[ -z "${backup_dir}" ]]; then
            log_error "No backups found in ${BACKUP_ROOT}"
            return 1
        fi

        log_info "Latest backup found: $(basename "${backup_dir}")"
    elif [[ -d "${BACKUP_TO_RESTORE}" ]]; then
        # Full path provided
        backup_dir="${BACKUP_TO_RESTORE}"
        log_info "Using specified backup directory: ${backup_dir}"
    elif [[ -d "${BACKUP_ROOT}/${BACKUP_TO_RESTORE}" ]]; then
        # Backup date provided
        backup_dir="${BACKUP_ROOT}/${BACKUP_TO_RESTORE}"
        log_info "Using backup: ${BACKUP_TO_RESTORE}"
    else
        log_error "Backup not found: ${BACKUP_TO_RESTORE}"
        return 1
    fi

    # Verify backup directory structure
    if [[ ! -d "${backup_dir}/metadata" ]]; then
        log_error "Invalid backup directory: missing metadata"
        return 1
    fi

    # Export backup directory for use by other functions
    export BACKUP_DIR="${backup_dir}"
    log_success "Backup directory verified: ${BACKUP_DIR}"
    return 0
}

# Display backup information
display_backup_info() {
    log_info "================================================"
    log_info "Backup Information"
    log_info "================================================"

    local metadata_file="${BACKUP_DIR}/metadata/backup_info.json"

    if [[ -f "${metadata_file}" ]]; then
        log_info "Backup Date: $(grep -o '"backup_date": "[^"]*"' "${metadata_file}" | cut -d'"' -f4)"
        log_info "Backup Type: $(grep -o '"backup_type": "[^"]*"' "${metadata_file}" | cut -d'"' -f4)"
        log_info "Backup Size: $(grep -o '"backup_size": "[^"]*"' "${metadata_file}" | cut -d'"' -f4)"
        log_info "Compression: $(grep -o '"compression": [^,}]*' "${metadata_file}" | cut -d' ' -f2)"
        log_info "Encryption: $(grep -o '"encryption": [^,}]*' "${metadata_file}" | cut -d' ' -f2)"
    else
        log_warning "Backup metadata not found"
    fi

    log_info "================================================"
}

# Create rollback point
create_rollback_point() {
    if [[ "${CREATE_ROLLBACK}" != "true" ]]; then
        log_info "Skipping rollback point creation (disabled)"
        return 0
    fi

    log_info "Creating rollback point at ${ROLLBACK_DIR}..."

    mkdir -p "${ROLLBACK_DIR}"/{minio,postgres,redis,config,metadata}

    # Backup current MinIO data
    if [[ "${RESTORE_MINIO}" == "true" ]] && [[ -d "${MINIO_DATA_DIR}" ]]; then
        log_info "Backing up current MinIO data for rollback..."
        tar -czf "${ROLLBACK_DIR}/minio/minio_data.tar.gz" -C "$(dirname "${MINIO_DATA_DIR}")" "$(basename "${MINIO_DATA_DIR}")" 2>/dev/null || true
    fi

    # Backup current PostgreSQL database
    if [[ "${RESTORE_POSTGRES}" == "true" ]]; then
        log_info "Backing up current PostgreSQL database for rollback..."
        if [[ -n "${POSTGRES_PASSWORD}" ]]; then
            export PGPASSWORD="${POSTGRES_PASSWORD}"
        fi
        pg_dump -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
            -F plain -f "${ROLLBACK_DIR}/postgres/postgres_${POSTGRES_DB}.sql" 2>/dev/null || true
        unset PGPASSWORD
    fi

    # Backup current Redis data
    if [[ "${RESTORE_REDIS}" == "true" ]] && [[ -f "${REDIS_DATA_DIR}/dump.rdb" ]]; then
        log_info "Backing up current Redis data for rollback..."
        cp "${REDIS_DATA_DIR}/dump.rdb" "${ROLLBACK_DIR}/redis/redis_dump.rdb" 2>/dev/null || true
    fi

    # Backup current configuration files
    if [[ "${RESTORE_CONFIG}" == "true" ]]; then
        log_info "Backing up current configuration files for rollback..."
        tar -czf "${ROLLBACK_DIR}/config/config_files.tar.gz" \
            -C "${PROJECT_ROOT}" configs deployments .env docker-compose.yml 2>/dev/null || true
    fi

    log_success "Rollback point created at ${ROLLBACK_DIR}"
    return 0
}

# Stop services before restore
stop_services() {
    if [[ "${STOP_SERVICES}" != "true" ]]; then
        log_info "Skipping service stop (disabled)"
        return 0
    fi

    log_info "Stopping services..."

    # Attempt to stop via docker-compose
    if command -v docker-compose >/dev/null 2>&1 && [[ -f "${PROJECT_ROOT}/deployments/docker/docker-compose.production.yml" ]]; then
        log_info "Stopping services via docker-compose..."
        docker-compose -f "${PROJECT_ROOT}/deployments/docker/docker-compose.production.yml" stop 2>/dev/null || true
    fi

    # Wait for services to stop
    sleep 5

    log_success "Services stopped"
    return 0
}

# Start services after restore
start_services() {
    if [[ "${START_SERVICES}" != "true" ]]; then
        log_info "Skipping service start (disabled)"
        return 0
    fi

    log_info "Starting services..."

    # Attempt to start via docker-compose
    if command -v docker-compose >/dev/null 2>&1 && [[ -f "${PROJECT_ROOT}/deployments/docker/docker-compose.production.yml" ]]; then
        log_info "Starting services via docker-compose..."
        docker-compose -f "${PROJECT_ROOT}/deployments/docker/docker-compose.production.yml" start 2>/dev/null || true
    fi

    # Wait for services to start
    sleep 10

    log_success "Services started"
    return 0
}

# Decrypt and decompress file
decrypt_decompress_file() {
    local file="$1"
    local output="$2"

    # Check if file is encrypted
    if [[ "${file}" == *.enc ]]; then
        if [[ -z "${ENCRYPTION_KEY}" ]]; then
            log_error "Encrypted backup found but no encryption key provided"
            return 1
        fi

        log_info "Decrypting file: $(basename "${file}")"
        local decrypted_file="${file%.enc}"
        openssl enc -d -aes-256-cbc -in "${file}" -out "${decrypted_file}" -k "${ENCRYPTION_KEY}" || return 1
        file="${decrypted_file}"
    fi

    # Check if file is compressed
    if [[ "${file}" == *.gz ]]; then
        log_info "Decompressing file: $(basename "${file}")"
        gunzip -c "${file}" > "${output}" || return 1
    else
        cp "${file}" "${output}" || return 1
    fi

    return 0
}

# Restore MinIO data
restore_minio() {
    if [[ "${RESTORE_MINIO}" != "true" ]]; then
        log_info "Skipping MinIO restore (disabled)"
        return 0
    fi

    log_info "Starting MinIO data restore..."

    local minio_backup_dir="${BACKUP_DIR}/minio"

    if [[ ! -f "${minio_backup_dir}/backup_file.txt" ]]; then
        log_warning "MinIO backup file reference not found"
        return 0
    fi

    local backup_file=$(cat "${minio_backup_dir}/backup_file.txt")

    if [[ ! -f "${backup_file}" ]]; then
        log_error "MinIO backup file not found: ${backup_file}"
        return 1
    fi

    # Decrypt and decompress
    local temp_file="/tmp/minio_restore_${RESTORE_DATE}.tar"
    if ! decrypt_decompress_file "${backup_file}" "${temp_file}"; then
        log_error "Failed to decrypt/decompress MinIO backup"
        return 1
    fi

    # Remove existing MinIO data directory
    if [[ -d "${MINIO_DATA_DIR}" ]]; then
        log_info "Removing existing MinIO data directory..."
        rm -rf "${MINIO_DATA_DIR}"
    fi

    # Extract backup
    log_info "Extracting MinIO backup..."
    if tar -xf "${temp_file}" -C "$(dirname "${MINIO_DATA_DIR}")" 2>/dev/null; then
        rm -f "${temp_file}"
        log_success "MinIO data restored successfully"
        return 0
    else
        rm -f "${temp_file}"
        log_error "Failed to extract MinIO backup"
        return 1
    fi
}

# Restore PostgreSQL database
restore_postgres() {
    if [[ "${RESTORE_POSTGRES}" != "true" ]]; then
        log_info "Skipping PostgreSQL restore (disabled)"
        return 0
    fi

    log_info "Starting PostgreSQL restore..."

    local postgres_backup_dir="${BACKUP_DIR}/postgres"

    if [[ ! -f "${postgres_backup_dir}/backup_file.txt" ]]; then
        log_warning "PostgreSQL backup file reference not found"
        return 0
    fi

    local backup_file=$(cat "${postgres_backup_dir}/backup_file.txt")

    if [[ ! -f "${backup_file}" ]]; then
        log_error "PostgreSQL backup file not found: ${backup_file}"
        return 1
    fi

    # Decrypt and decompress
    local temp_file="/tmp/postgres_restore_${RESTORE_DATE}.sql"
    if ! decrypt_decompress_file "${backup_file}" "${temp_file}"; then
        log_error "Failed to decrypt/decompress PostgreSQL backup"
        return 1
    fi

    # Set password environment variable if provided
    if [[ -n "${POSTGRES_PASSWORD}" ]]; then
        export PGPASSWORD="${POSTGRES_PASSWORD}"
    fi

    # Drop and recreate database
    log_info "Dropping and recreating PostgreSQL database..."
    psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres \
        -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};" 2>/dev/null || true
    psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres \
        -c "CREATE DATABASE ${POSTGRES_DB};" 2>/dev/null || return 1

    # Restore database
    log_info "Restoring PostgreSQL database..."
    if psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
        -f "${temp_file}" 2>/dev/null; then
        rm -f "${temp_file}"
        unset PGPASSWORD
        log_success "PostgreSQL database restored successfully"
        return 0
    else
        rm -f "${temp_file}"
        unset PGPASSWORD
        log_error "Failed to restore PostgreSQL database"
        return 1
    fi
}

# Restore Redis data
restore_redis() {
    if [[ "${RESTORE_REDIS}" != "true" ]]; then
        log_info "Skipping Redis restore (disabled)"
        return 0
    fi

    log_info "Starting Redis restore..."

    local redis_backup_dir="${BACKUP_DIR}/redis"

    if [[ ! -f "${redis_backup_dir}/backup_file.txt" ]]; then
        log_warning "Redis backup file reference not found"
        return 0
    fi

    local backup_file=$(cat "${redis_backup_dir}/backup_file.txt")

    if [[ ! -f "${backup_file}" ]]; then
        log_error "Redis backup file not found: ${backup_file}"
        return 1
    fi

    # Decrypt and decompress
    local temp_file="/tmp/redis_restore_${RESTORE_DATE}.rdb"
    if ! decrypt_decompress_file "${backup_file}" "${temp_file}"; then
        log_error "Failed to decrypt/decompress Redis backup"
        return 1
    fi

    # Copy dump file to Redis data directory
    log_info "Copying Redis dump file..."
    if cp "${temp_file}" "${REDIS_DATA_DIR}/dump.rdb" 2>/dev/null; then
        rm -f "${temp_file}"
        log_success "Redis data restored successfully"
        return 0
    else
        rm -f "${temp_file}"
        log_error "Failed to restore Redis data"
        return 1
    fi
}

# Restore configuration files
restore_config() {
    if [[ "${RESTORE_CONFIG}" != "true" ]]; then
        log_info "Skipping configuration restore (disabled)"
        return 0
    fi

    log_info "Starting configuration files restore..."

    local config_backup_dir="${BACKUP_DIR}/config"

    if [[ ! -f "${config_backup_dir}/backup_file.txt" ]]; then
        log_warning "Configuration backup file reference not found"
        return 0
    fi

    local backup_file=$(cat "${config_backup_dir}/backup_file.txt")

    if [[ ! -f "${backup_file}" ]]; then
        log_error "Configuration backup file not found: ${backup_file}"
        return 1
    fi

    # Decrypt and decompress
    local temp_file="/tmp/config_restore_${RESTORE_DATE}.tar"
    if ! decrypt_decompress_file "${backup_file}" "${temp_file}"; then
        log_error "Failed to decrypt/decompress configuration backup"
        return 1
    fi

    # Extract configuration files
    log_info "Extracting configuration files..."
    if tar -xf "${temp_file}" -C "${PROJECT_ROOT}" 2>/dev/null; then
        rm -f "${temp_file}"
        log_success "Configuration files restored successfully"
        return 0
    else
        rm -f "${temp_file}"
        log_error "Failed to extract configuration files"
        return 1
    fi
}

# Verify restore
verify_restore() {
    if [[ "${VERIFY_RESTORE}" != "true" ]]; then
        log_info "Skipping restore verification (disabled)"
        return 0
    fi

    log_info "Verifying restore..."

    local verification_passed=true

    # Verify MinIO data directory
    if [[ "${RESTORE_MINIO}" == "true" ]]; then
        if [[ -d "${MINIO_DATA_DIR}" ]]; then
            log_success "MinIO data directory verified"
        else
            log_error "MinIO data directory not found after restore"
            verification_passed=false
        fi
    fi

    # Verify PostgreSQL database
    if [[ "${RESTORE_POSTGRES}" == "true" ]]; then
        if [[ -n "${POSTGRES_PASSWORD}" ]]; then
            export PGPASSWORD="${POSTGRES_PASSWORD}"
        fi

        if psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
            -c "SELECT 1;" >/dev/null 2>&1; then
            log_success "PostgreSQL database verified"
        else
            log_error "PostgreSQL database verification failed"
            verification_passed=false
        fi

        unset PGPASSWORD
    fi

    # Verify Redis data
    if [[ "${RESTORE_REDIS}" == "true" ]]; then
        if [[ -f "${REDIS_DATA_DIR}/dump.rdb" ]]; then
            log_success "Redis data file verified"
        else
            log_error "Redis data file not found after restore"
            verification_passed=false
        fi
    fi

    # Verify configuration files
    if [[ "${RESTORE_CONFIG}" == "true" ]]; then
        if [[ -d "${PROJECT_ROOT}/configs" ]]; then
            log_success "Configuration files verified"
        else
            log_error "Configuration files not found after restore"
            verification_passed=false
        fi
    fi

    if [[ "${verification_passed}" == "true" ]]; then
        log_success "All restore operations verified successfully"
        return 0
    else
        log_error "Restore verification failed"
        return 1
    fi
}

# Display restore summary
display_summary() {
    log_info "================================================"
    log_info "Restore Summary"
    log_info "================================================"
    log_info "Restore Date: ${RESTORE_DATE}"
    log_info "Backup Source: ${BACKUP_DIR}"
    log_info "Rollback Available: ${CREATE_ROLLBACK}"
    if [[ "${CREATE_ROLLBACK}" == "true" ]]; then
        log_info "Rollback Location: ${ROLLBACK_DIR}"
    fi
    log_info "Components Restored:"
    log_info "  - MinIO: ${RESTORE_MINIO}"
    log_info "  - PostgreSQL: ${RESTORE_POSTGRES}"
    log_info "  - Redis: ${RESTORE_REDIS}"
    log_info "  - Configuration: ${RESTORE_CONFIG}"
    log_info "================================================"
}

# Main restore function
main() {
    log_info "Starting MinIO Enterprise restore..."
    log_info "Restore date: ${RESTORE_DATE}"

    # Load configuration
    load_config

    # Check dependencies
    if ! check_dependencies; then
        log_error "Dependency check failed"
        exit 1
    fi

    # Find backup to restore
    if ! find_backup_dir; then
        log_error "Failed to find backup directory"
        exit 1
    fi

    # Display backup information
    display_backup_info

    # Confirm restore
    log_warning "WARNING: This will restore data from backup and may overwrite existing data"
    log_warning "A rollback point will be created at: ${ROLLBACK_DIR}"
    read -p "Do you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Restore cancelled by user"
        exit 0
    fi

    # Create rollback point
    create_rollback_point

    # Stop services
    stop_services

    # Perform restore
    local restore_failed=false

    restore_minio || restore_failed=true
    restore_postgres || restore_failed=true
    restore_redis || restore_failed=true
    restore_config || restore_failed=true

    # Verify restore
    if ! verify_restore; then
        restore_failed=true
    fi

    # Start services
    start_services

    # Display summary
    display_summary

    if [[ "${restore_failed}" == "true" ]]; then
        log_error "Restore completed with errors"
        log_error "You can rollback using the backup at: ${ROLLBACK_DIR}"
        exit 1
    else
        log_success "Restore completed successfully!"
        log_info "Rollback point available at: ${ROLLBACK_DIR}"
        exit 0
    fi
}

# Run main function
main "$@"
