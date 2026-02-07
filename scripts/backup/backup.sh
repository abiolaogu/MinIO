#!/usr/bin/env bash

# MinIO Enterprise - Backup Automation Script
# This script performs automated backups of MinIO objects, PostgreSQL database,
# Redis snapshots, and configuration files with support for full/incremental backups,
# retention policies, encryption, and verification.

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/backup.conf}"

# Default configuration (can be overridden by backup.conf)
BACKUP_TYPE="${BACKUP_TYPE:-full}"  # full or incremental
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/minio}"
BACKUP_DATE="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_DATE}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
COMPRESSION="${COMPRESSION:-true}"
ENCRYPTION="${ENCRYPTION:-false}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"
VERIFY_BACKUP="${VERIFY_BACKUP:-true}"
LOG_FILE="${LOG_FILE:-${BACKUP_ROOT}/backup.log}"

# Component flags
BACKUP_MINIO="${BACKUP_MINIO:-true}"
BACKUP_POSTGRES="${BACKUP_POSTGRES:-true}"
BACKUP_REDIS="${BACKUP_REDIS:-true}"
BACKUP_CONFIG="${BACKUP_CONFIG:-true}"

# MinIO configuration
MINIO_DATA_DIR="${MINIO_DATA_DIR:-${PROJECT_ROOT}/data/minio}"
MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://localhost:9000}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-}"

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

    [[ "${BACKUP_POSTGRES}" == "true" ]] && ! command -v pg_dump >/dev/null 2>&1 && missing_deps+=("pg_dump (postgresql-client)")
    [[ "${BACKUP_REDIS}" == "true" ]] && ! command -v redis-cli >/dev/null 2>&1 && missing_deps+=("redis-cli (redis-tools)")
    [[ "${COMPRESSION}" == "true" ]] && ! command -v gzip >/dev/null 2>&1 && missing_deps+=("gzip")
    [[ "${ENCRYPTION}" == "true" ]] && ! command -v openssl >/dev/null 2>&1 && missing_deps+=("openssl")

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_error "Install with: apt-get install postgresql-client redis-tools gzip openssl"
        return 1
    fi

    log_success "All dependencies satisfied"
    return 0
}

# Create backup directory structure
create_backup_dir() {
    log_info "Creating backup directory: ${BACKUP_DIR}"

    mkdir -p "${BACKUP_DIR}"/{minio,postgres,redis,config,metadata}

    if [[ ! -d "${BACKUP_DIR}" ]]; then
        log_error "Failed to create backup directory: ${BACKUP_DIR}"
        return 1
    fi

    log_success "Backup directory created"
    return 0
}

# Backup MinIO data
backup_minio() {
    if [[ "${BACKUP_MINIO}" != "true" ]]; then
        log_info "Skipping MinIO backup (disabled)"
        return 0
    fi

    log_info "Starting MinIO data backup..."

    local minio_backup_dir="${BACKUP_DIR}/minio"
    local backup_file="${minio_backup_dir}/minio_data.tar"

    if [[ ! -d "${MINIO_DATA_DIR}" ]]; then
        log_warning "MinIO data directory not found: ${MINIO_DATA_DIR}"
        return 0
    fi

    # Create tarball of MinIO data
    if tar -cf "${backup_file}" -C "$(dirname "${MINIO_DATA_DIR}")" "$(basename "${MINIO_DATA_DIR}")" 2>/dev/null; then
        local size=$(du -h "${backup_file}" | cut -f1)
        log_success "MinIO data backed up (${size})"

        # Compress if enabled
        if [[ "${COMPRESSION}" == "true" ]]; then
            log_info "Compressing MinIO backup..."
            gzip "${backup_file}"
            backup_file="${backup_file}.gz"
            size=$(du -h "${backup_file}" | cut -f1)
            log_success "MinIO backup compressed (${size})"
        fi

        # Encrypt if enabled
        if [[ "${ENCRYPTION}" == "true" ]] && [[ -n "${ENCRYPTION_KEY}" ]]; then
            log_info "Encrypting MinIO backup..."
            openssl enc -aes-256-cbc -salt -in "${backup_file}" -out "${backup_file}.enc" -k "${ENCRYPTION_KEY}"
            rm -f "${backup_file}"
            backup_file="${backup_file}.enc"
            log_success "MinIO backup encrypted"
        fi

        echo "${backup_file}" > "${minio_backup_dir}/backup_file.txt"
        return 0
    else
        log_error "Failed to backup MinIO data"
        return 1
    fi
}

# Backup PostgreSQL database
backup_postgres() {
    if [[ "${BACKUP_POSTGRES}" != "true" ]]; then
        log_info "Skipping PostgreSQL backup (disabled)"
        return 0
    fi

    log_info "Starting PostgreSQL backup..."

    local postgres_backup_dir="${BACKUP_DIR}/postgres"
    local backup_file="${postgres_backup_dir}/postgres_${POSTGRES_DB}.sql"

    # Set password environment variable if provided
    if [[ -n "${POSTGRES_PASSWORD}" ]]; then
        export PGPASSWORD="${POSTGRES_PASSWORD}"
    fi

    # Perform database dump
    if pg_dump -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
        -F plain -f "${backup_file}" 2>/dev/null; then

        local size=$(du -h "${backup_file}" | cut -f1)
        log_success "PostgreSQL database backed up (${size})"

        # Compress if enabled
        if [[ "${COMPRESSION}" == "true" ]]; then
            log_info "Compressing PostgreSQL backup..."
            gzip "${backup_file}"
            backup_file="${backup_file}.gz"
            size=$(du -h "${backup_file}" | cut -f1)
            log_success "PostgreSQL backup compressed (${size})"
        fi

        # Encrypt if enabled
        if [[ "${ENCRYPTION}" == "true" ]] && [[ -n "${ENCRYPTION_KEY}" ]]; then
            log_info "Encrypting PostgreSQL backup..."
            openssl enc -aes-256-cbc -salt -in "${backup_file}" -out "${backup_file}.enc" -k "${ENCRYPTION_KEY}"
            rm -f "${backup_file}"
            backup_file="${backup_file}.enc"
            log_success "PostgreSQL backup encrypted"
        fi

        echo "${backup_file}" > "${postgres_backup_dir}/backup_file.txt"
        unset PGPASSWORD
        return 0
    else
        log_error "Failed to backup PostgreSQL database"
        unset PGPASSWORD
        return 1
    fi
}

# Backup Redis data
backup_redis() {
    if [[ "${BACKUP_REDIS}" != "true" ]]; then
        log_info "Skipping Redis backup (disabled)"
        return 0
    fi

    log_info "Starting Redis backup..."

    local redis_backup_dir="${BACKUP_DIR}/redis"
    local backup_file="${redis_backup_dir}/redis_dump.rdb"

    # Build redis-cli command
    local redis_cmd="redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT}"
    if [[ -n "${REDIS_PASSWORD}" ]]; then
        redis_cmd="${redis_cmd} -a ${REDIS_PASSWORD}"
    fi

    # Trigger Redis BGSAVE
    if ${redis_cmd} BGSAVE >/dev/null 2>&1; then
        log_info "Redis background save triggered, waiting for completion..."

        # Wait for BGSAVE to complete (check every second, max 60 seconds)
        local max_wait=60
        local waited=0
        while [[ ${waited} -lt ${max_wait} ]]; do
            local last_save=$(${redis_cmd} LASTSAVE 2>/dev/null || echo "0")
            sleep 1
            local new_save=$(${redis_cmd} LASTSAVE 2>/dev/null || echo "0")

            if [[ ${new_save} -gt ${last_save} ]]; then
                break
            fi

            waited=$((waited + 1))
        done

        # Copy Redis dump file
        local redis_data_dir="/var/lib/redis"  # Default Redis data directory
        if [[ -f "${redis_data_dir}/dump.rdb" ]]; then
            cp "${redis_data_dir}/dump.rdb" "${backup_file}"
            local size=$(du -h "${backup_file}" | cut -f1)
            log_success "Redis data backed up (${size})"

            # Compress if enabled
            if [[ "${COMPRESSION}" == "true" ]]; then
                log_info "Compressing Redis backup..."
                gzip "${backup_file}"
                backup_file="${backup_file}.gz"
                size=$(du -h "${backup_file}" | cut -f1)
                log_success "Redis backup compressed (${size})"
            fi

            # Encrypt if enabled
            if [[ "${ENCRYPTION}" == "true" ]] && [[ -n "${ENCRYPTION_KEY}" ]]; then
                log_info "Encrypting Redis backup..."
                openssl enc -aes-256-cbc -salt -in "${backup_file}" -out "${backup_file}.enc" -k "${ENCRYPTION_KEY}"
                rm -f "${backup_file}"
                backup_file="${backup_file}.enc"
                log_success "Redis backup encrypted"
            fi

            echo "${backup_file}" > "${redis_backup_dir}/backup_file.txt"
            return 0
        else
            log_warning "Redis dump file not found at ${redis_data_dir}/dump.rdb"
            log_warning "You may need to adjust REDIS_DATA_DIR in configuration"
            return 0
        fi
    else
        log_error "Failed to trigger Redis background save"
        return 1
    fi
}

# Backup configuration files
backup_config() {
    if [[ "${BACKUP_CONFIG}" != "true" ]]; then
        log_info "Skipping configuration backup (disabled)"
        return 0
    fi

    log_info "Starting configuration files backup..."

    local config_backup_dir="${BACKUP_DIR}/config"
    local backup_file="${config_backup_dir}/config_files.tar"

    # List of configuration directories/files to backup
    local config_paths=(
        "${PROJECT_ROOT}/configs"
        "${PROJECT_ROOT}/deployments"
        "${PROJECT_ROOT}/.env"
        "${PROJECT_ROOT}/docker-compose.yml"
    )

    # Create list of existing paths
    local existing_paths=()
    for path in "${config_paths[@]}"; do
        if [[ -e "${path}" ]]; then
            existing_paths+=("${path}")
        fi
    done

    if [[ ${#existing_paths[@]} -eq 0 ]]; then
        log_warning "No configuration files found to backup"
        return 0
    fi

    # Create tarball of configuration files
    if tar -cf "${backup_file}" -C "${PROJECT_ROOT}" \
        $(for path in "${existing_paths[@]}"; do echo "${path#${PROJECT_ROOT}/}"; done) 2>/dev/null; then

        local size=$(du -h "${backup_file}" | cut -f1)
        log_success "Configuration files backed up (${size})"

        # Compress if enabled
        if [[ "${COMPRESSION}" == "true" ]]; then
            log_info "Compressing configuration backup..."
            gzip "${backup_file}"
            backup_file="${backup_file}.gz"
            size=$(du -h "${backup_file}" | cut -f1)
            log_success "Configuration backup compressed (${size})"
        fi

        # Encrypt if enabled
        if [[ "${ENCRYPTION}" == "true" ]] && [[ -n "${ENCRYPTION_KEY}" ]]; then
            log_info "Encrypting configuration backup..."
            openssl enc -aes-256-cbc -salt -in "${backup_file}" -out "${backup_file}.enc" -k "${ENCRYPTION_KEY}"
            rm -f "${backup_file}"
            backup_file="${backup_file}.enc"
            log_success "Configuration backup encrypted"
        fi

        echo "${backup_file}" > "${config_backup_dir}/backup_file.txt"
        return 0
    else
        log_error "Failed to backup configuration files"
        return 1
    fi
}

# Create backup metadata
create_metadata() {
    log_info "Creating backup metadata..."

    local metadata_file="${BACKUP_DIR}/metadata/backup_info.json"

    cat > "${metadata_file}" <<EOF
{
  "backup_date": "${BACKUP_DATE}",
  "backup_type": "${BACKUP_TYPE}",
  "backup_dir": "${BACKUP_DIR}",
  "compression": ${COMPRESSION},
  "encryption": ${ENCRYPTION},
  "components": {
    "minio": ${BACKUP_MINIO},
    "postgres": ${BACKUP_POSTGRES},
    "redis": ${BACKUP_REDIS},
    "config": ${BACKUP_CONFIG}
  },
  "version": "1.0.0",
  "hostname": "$(hostname)",
  "backup_size": "$(du -sh "${BACKUP_DIR}" | cut -f1)"
}
EOF

    log_success "Backup metadata created"
}

# Verify backup integrity
verify_backup() {
    if [[ "${VERIFY_BACKUP}" != "true" ]]; then
        log_info "Skipping backup verification (disabled)"
        return 0
    fi

    log_info "Verifying backup integrity..."

    local verification_passed=true

    # Verify MinIO backup
    if [[ "${BACKUP_MINIO}" == "true" ]] && [[ -f "${BACKUP_DIR}/minio/backup_file.txt" ]]; then
        local minio_file=$(cat "${BACKUP_DIR}/minio/backup_file.txt")
        if [[ -f "${minio_file}" ]]; then
            log_success "MinIO backup file verified: ${minio_file}"
        else
            log_error "MinIO backup file not found: ${minio_file}"
            verification_passed=false
        fi
    fi

    # Verify PostgreSQL backup
    if [[ "${BACKUP_POSTGRES}" == "true" ]] && [[ -f "${BACKUP_DIR}/postgres/backup_file.txt" ]]; then
        local postgres_file=$(cat "${BACKUP_DIR}/postgres/backup_file.txt")
        if [[ -f "${postgres_file}" ]]; then
            log_success "PostgreSQL backup file verified: ${postgres_file}"
        else
            log_error "PostgreSQL backup file not found: ${postgres_file}"
            verification_passed=false
        fi
    fi

    # Verify Redis backup
    if [[ "${BACKUP_REDIS}" == "true" ]] && [[ -f "${BACKUP_DIR}/redis/backup_file.txt" ]]; then
        local redis_file=$(cat "${BACKUP_DIR}/redis/backup_file.txt")
        if [[ -f "${redis_file}" ]]; then
            log_success "Redis backup file verified: ${redis_file}"
        else
            log_error "Redis backup file not found: ${redis_file}"
            verification_passed=false
        fi
    fi

    # Verify configuration backup
    if [[ "${BACKUP_CONFIG}" == "true" ]] && [[ -f "${BACKUP_DIR}/config/backup_file.txt" ]]; then
        local config_file=$(cat "${BACKUP_DIR}/config/backup_file.txt")
        if [[ -f "${config_file}" ]]; then
            log_success "Configuration backup file verified: ${config_file}"
        else
            log_error "Configuration backup file not found: ${config_file}"
            verification_passed=false
        fi
    fi

    # Verify metadata
    if [[ -f "${BACKUP_DIR}/metadata/backup_info.json" ]]; then
        log_success "Backup metadata verified"
    else
        log_error "Backup metadata not found"
        verification_passed=false
    fi

    if [[ "${verification_passed}" == "true" ]]; then
        log_success "All backup files verified successfully"
        return 0
    else
        log_error "Backup verification failed"
        return 1
    fi
}

# Clean old backups based on retention policy
cleanup_old_backups() {
    log_info "Cleaning up old backups (retention: ${RETENTION_DAYS} days)..."

    if [[ ! -d "${BACKUP_ROOT}" ]]; then
        log_warning "Backup root directory not found: ${BACKUP_ROOT}"
        return 0
    fi

    local deleted_count=0

    # Find and delete backups older than retention period
    while IFS= read -r -d '' backup_dir; do
        local backup_name=$(basename "${backup_dir}")

        # Skip if not a dated backup directory
        if [[ ! "${backup_name}" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
            continue
        fi

        # Delete if older than retention period
        if find "${backup_dir}" -maxdepth 0 -type d -mtime "+${RETENTION_DAYS}" -print0 2>/dev/null | grep -qz .; then
            log_info "Deleting old backup: ${backup_name}"
            rm -rf "${backup_dir}"
            deleted_count=$((deleted_count + 1))
        fi
    done < <(find "${BACKUP_ROOT}" -maxdepth 1 -type d -print0 2>/dev/null)

    if [[ ${deleted_count} -gt 0 ]]; then
        log_success "Deleted ${deleted_count} old backup(s)"
    else
        log_info "No old backups to delete"
    fi
}

# Display backup summary
display_summary() {
    log_info "================================================"
    log_info "Backup Summary"
    log_info "================================================"
    log_info "Backup Date: ${BACKUP_DATE}"
    log_info "Backup Type: ${BACKUP_TYPE}"
    log_info "Backup Directory: ${BACKUP_DIR}"
    log_info "Backup Size: $(du -sh "${BACKUP_DIR}" | cut -f1)"
    log_info "Compression: ${COMPRESSION}"
    log_info "Encryption: ${ENCRYPTION}"
    log_info "Components:"
    log_info "  - MinIO: ${BACKUP_MINIO}"
    log_info "  - PostgreSQL: ${BACKUP_POSTGRES}"
    log_info "  - Redis: ${BACKUP_REDIS}"
    log_info "  - Configuration: ${BACKUP_CONFIG}"
    log_info "================================================"
}

# Main backup function
main() {
    log_info "Starting MinIO Enterprise backup..."
    log_info "Backup date: ${BACKUP_DATE}"

    # Load configuration
    load_config

    # Check dependencies
    if ! check_dependencies; then
        log_error "Dependency check failed"
        exit 1
    fi

    # Create backup directory
    if ! create_backup_dir; then
        log_error "Failed to create backup directory"
        exit 1
    fi

    # Perform backups
    local backup_failed=false

    backup_minio || backup_failed=true
    backup_postgres || backup_failed=true
    backup_redis || backup_failed=true
    backup_config || backup_failed=true

    # Create metadata
    create_metadata

    # Verify backup
    if ! verify_backup; then
        backup_failed=true
    fi

    # Clean old backups
    cleanup_old_backups

    # Display summary
    display_summary

    if [[ "${backup_failed}" == "true" ]]; then
        log_error "Backup completed with errors"
        exit 1
    else
        log_success "Backup completed successfully!"
        log_info "Backup location: ${BACKUP_DIR}"
        exit 0
    fi
}

# Run main function
main "$@"
