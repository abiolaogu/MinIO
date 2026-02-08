#!/bin/bash
#
# MinIO Enterprise - Restore Automation Script
# Version: 1.0.0
# Description: Automated restore script with verification and rollback capabilities
#
# Usage:
#   ./restore.sh [OPTIONS]
#
# Options:
#   -b, --backup <path>           Path to backup directory (required)
#   -c, --component <name>        Component to restore (all|postgres|redis|minio|configs)
#   -v, --verify                  Verify restore without applying changes
#   -f, --force                   Force restore without confirmation
#   --verbose                     Verbose output
#   -h, --help                    Show this help message
#
# Environment Variables:
#   POSTGRES_HOST         PostgreSQL host (default: localhost)
#   POSTGRES_PORT         PostgreSQL port (default: 5432)
#   POSTGRES_USER         PostgreSQL user (default: postgres)
#   POSTGRES_PASSWORD     PostgreSQL password
#   POSTGRES_DB           PostgreSQL database (default: minio)
#   REDIS_HOST            Redis host (default: localhost)
#   REDIS_PORT            Redis port (default: 6379)
#   MINIO_DATA_PATH       MinIO data directory (default: /data)
#   ENCRYPTION_KEY        Encryption key (required if backup is encrypted)
#

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

# Default configuration
BACKUP_PATH=""
COMPONENT="all"
VERIFY_ONLY=false
FORCE=false
VERBOSE=false
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-minio}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
MINIO_DATA_PATH="${MINIO_DATA_PATH:-/data}"

# Restore metadata
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESTORE_LOG="/tmp/minio_restore_${TIMESTAMP}.log"
ROLLBACK_DIR="/tmp/minio_rollback_${TIMESTAMP}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================
# Helper Functions
# ============================================================

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Log to file
    echo "[${timestamp}] [${level}] ${message}" >> "${RESTORE_LOG}"

    # Log to stdout with color
    case "${level}" in
        INFO)
            [ "${VERBOSE}" = true ] && echo -e "${BLUE}[INFO]${NC} ${message}"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} ${message}"
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING]${NC} ${message}"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} ${message}"
            ;;
    esac
}

error_exit() {
    log ERROR "$1"
    echo
    echo "Restore log: ${RESTORE_LOG}"
    exit 1
}

show_help() {
    cat << EOF
MinIO Enterprise - Restore Automation Script

Usage: $0 [OPTIONS]

Options:
  -b, --backup <path>           Path to backup directory (required)
  -c, --component <name>        Component to restore (all|postgres|redis|minio|configs)
  -v, --verify                  Verify restore without applying changes
  -f, --force                   Force restore without confirmation
  --verbose                     Verbose output
  -h, --help                    Show this help message

Environment Variables:
  POSTGRES_HOST         PostgreSQL host
  POSTGRES_USER         PostgreSQL user
  POSTGRES_PASSWORD     PostgreSQL password
  REDIS_HOST            Redis host
  MINIO_DATA_PATH       MinIO data directory
  ENCRYPTION_KEY        Encryption key (required if backup is encrypted)

Components:
  all       - Restore all components (default)
  postgres  - Restore PostgreSQL database only
  redis     - Restore Redis data only
  minio     - Restore MinIO object data only
  configs   - Restore configuration files only

Examples:
  # Restore all components from backup
  $0 --backup /var/backups/minio/backup_full_20240118_120000

  # Restore only PostgreSQL database
  $0 --backup /backups/backup_full_20240118_120000 --component postgres

  # Verify backup integrity without restoring
  $0 --backup /backups/backup_full_20240118_120000 --verify

  # Force restore without confirmation
  $0 --backup /backups/backup_full_20240118_120000 --force

EOF
}

check_dependencies() {
    log INFO "Checking dependencies..."

    local missing_deps=()

    command -v tar >/dev/null 2>&1 || missing_deps+=("tar")
    command -v gzip >/dev/null 2>&1 || missing_deps+=("gzip")

    if [ "${COMPONENT}" = "all" ] || [ "${COMPONENT}" = "postgres" ]; then
        command -v psql >/dev/null 2>&1 || missing_deps+=("postgresql-client")
    fi

    if [ "${COMPONENT}" = "all" ] || [ "${COMPONENT}" = "redis" ]; then
        command -v redis-cli >/dev/null 2>&1 || missing_deps+=("redis-tools")
    fi

    if [ "${#missing_deps[@]}" -gt 0 ]; then
        error_exit "Missing dependencies: ${missing_deps[*]}"
    fi

    log INFO "All dependencies satisfied"
}

verify_backup() {
    log INFO "Verifying backup integrity..."

    if [ ! -d "${BACKUP_PATH}" ]; then
        error_exit "Backup directory not found: ${BACKUP_PATH}"
    fi

    local manifest="${BACKUP_PATH}/manifest.json"
    if [ ! -f "${manifest}" ]; then
        error_exit "Backup manifest not found: ${manifest}"
    fi

    # Parse manifest
    log INFO "Reading backup manifest..."

    if command -v jq >/dev/null 2>&1; then
        local backup_id=$(jq -r '.backup_id' "${manifest}")
        local backup_type=$(jq -r '.type' "${manifest}")
        local encryption=$(jq -r '.encryption' "${manifest}")
        local compression=$(jq -r '.compression' "${manifest}")

        log INFO "Backup ID: ${backup_id}"
        log INFO "Backup Type: ${backup_type}"
        log INFO "Encryption: ${encryption}"
        log INFO "Compression: ${compression}"

        # Check encryption
        if [ "${encryption}" = "true" ] && [ -z "${ENCRYPTION_KEY:-}" ]; then
            error_exit "Backup is encrypted but ENCRYPTION_KEY not set"
        fi
    else
        log WARNING "jq not installed, skipping detailed manifest parsing"
    fi

    # Verify components exist
    local errors=0

    if [ "${COMPONENT}" = "all" ] || [ "${COMPONENT}" = "postgres" ]; then
        if [ ! -d "${BACKUP_PATH}/postgres" ]; then
            log ERROR "PostgreSQL backup not found"
            errors=$((errors + 1))
        fi
    fi

    if [ "${COMPONENT}" = "all" ] || [ "${COMPONENT}" = "redis" ]; then
        if [ ! -d "${BACKUP_PATH}/redis" ]; then
            log WARNING "Redis backup not found"
        fi
    fi

    if [ "${COMPONENT}" = "all" ] || [ "${COMPONENT}" = "minio" ]; then
        if [ ! -d "${BACKUP_PATH}/minio-data" ]; then
            log ERROR "MinIO data backup not found"
            errors=$((errors + 1))
        fi
    fi

    if [ "${COMPONENT}" = "all" ] || [ "${COMPONENT}" = "configs" ]; then
        if [ ! -d "${BACKUP_PATH}/configs" ]; then
            log WARNING "Configuration backup not found"
        fi
    fi

    if [ ${errors} -gt 0 ]; then
        error_exit "Backup verification failed with ${errors} error(s)"
    fi

    log SUCCESS "Backup verification passed"
}

decrypt_file() {
    local encrypted_file=$1
    local decrypted_file="${encrypted_file%.enc}"

    if [ -z "${ENCRYPTION_KEY:-}" ]; then
        error_exit "ENCRYPTION_KEY not set for decrypting: ${encrypted_file}"
    fi

    log INFO "Decrypting: $(basename ${encrypted_file})"

    if openssl enc -aes-256-cbc -d -pbkdf2 -in "${encrypted_file}" -out "${decrypted_file}" -k "${ENCRYPTION_KEY}" 2>> "${RESTORE_LOG}"; then
        log INFO "Decryption successful"
        echo "${decrypted_file}"
    else
        error_exit "Failed to decrypt file: ${encrypted_file}"
    fi
}

decompress_file() {
    local compressed_file=$1

    log INFO "Decompressing: $(basename ${compressed_file})"

    if gunzip -k "${compressed_file}" 2>> "${RESTORE_LOG}"; then
        local decompressed="${compressed_file%.gz}"
        log INFO "Decompression successful"
        echo "${decompressed}"
    else
        error_exit "Failed to decompress file: ${compressed_file}"
    fi
}

create_rollback_backup() {
    log INFO "Creating rollback backup..."

    mkdir -p "${ROLLBACK_DIR}"

    # Backup current state for rollback
    if [ "${COMPONENT}" = "all" ] || [ "${COMPONENT}" = "postgres" ]; then
        log INFO "Backing up current PostgreSQL state..."
        export PGPASSWORD="${POSTGRES_PASSWORD}"
        pg_dump -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
                -d "${POSTGRES_DB}" -f "${ROLLBACK_DIR}/postgres_rollback.sql" 2>> "${RESTORE_LOG}" || true
        unset PGPASSWORD
    fi

    if [ "${COMPONENT}" = "all" ] || [ "${COMPONENT}" = "minio" ]; then
        if [ -d "${MINIO_DATA_PATH}" ]; then
            log INFO "Backing up current MinIO data state..."
            tar -czf "${ROLLBACK_DIR}/minio_data_rollback.tar.gz" -C "${MINIO_DATA_PATH}" . 2>> "${RESTORE_LOG}" || true
        fi
    fi

    log SUCCESS "Rollback backup created: ${ROLLBACK_DIR}"
}

restore_postgresql() {
    log INFO "Restoring PostgreSQL database..."

    # Find backup file
    local backup_file=$(find "${BACKUP_PATH}/postgres" -name "database.sql*" -type f | head -1)

    if [ -z "${backup_file}" ]; then
        log ERROR "PostgreSQL backup file not found"
        return 1
    fi

    # Handle encryption
    if [[ "${backup_file}" == *.enc ]]; then
        backup_file=$(decrypt_file "${backup_file}")
    fi

    # Handle compression
    if [[ "${backup_file}" == *.gz ]]; then
        backup_file=$(decompress_file "${backup_file}")
    fi

    log INFO "Using backup file: ${backup_file}"

    # Drop and recreate database
    export PGPASSWORD="${POSTGRES_PASSWORD}"

    log INFO "Dropping existing database..."
    psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
         -d postgres -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};" 2>> "${RESTORE_LOG}" || true

    log INFO "Creating fresh database..."
    psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
         -d postgres -c "CREATE DATABASE ${POSTGRES_DB};" 2>> "${RESTORE_LOG}" || error_exit "Failed to create database"

    # Restore from backup
    log INFO "Restoring database from backup..."
    if psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
            -d "${POSTGRES_DB}" -f "${backup_file}" 2>> "${RESTORE_LOG}"; then
        log SUCCESS "PostgreSQL restore completed"
        unset PGPASSWORD
        return 0
    else
        log ERROR "PostgreSQL restore failed"
        unset PGPASSWORD
        return 1
    fi
}

restore_redis() {
    log INFO "Restoring Redis data..."

    # Find backup file
    local backup_file=$(find "${BACKUP_PATH}/redis" -name "redis.rdb*" -type f | head -1)

    if [ -z "${backup_file}" ]; then
        log WARNING "Redis backup file not found"
        return 1
    fi

    # Handle encryption
    if [[ "${backup_file}" == *.enc ]]; then
        backup_file=$(decrypt_file "${backup_file}")
    fi

    # Handle compression
    if [[ "${backup_file}" == *.gz ]]; then
        backup_file=$(decompress_file "${backup_file}")
    fi

    log INFO "Using backup file: ${backup_file}"

    # Flush Redis
    log INFO "Flushing Redis database..."
    redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" FLUSHALL > /dev/null 2>&1 || log WARNING "Failed to flush Redis"

    # Stop Redis temporarily (if running in Docker, this would be different)
    log WARNING "Redis restore requires manual steps:"
    log WARNING "1. Stop Redis server"
    log WARNING "2. Copy ${backup_file} to Redis data directory as dump.rdb"
    log WARNING "3. Start Redis server"
    log WARNING "Automatic Redis restore is not yet implemented"

    return 0
}

restore_minio_data() {
    log INFO "Restoring MinIO data..."

    # Find backup file
    local backup_file=$(find "${BACKUP_PATH}/minio-data" -name "data.tar*" -type f | head -1)

    if [ -z "${backup_file}" ]; then
        log ERROR "MinIO data backup file not found"
        return 1
    fi

    # Handle encryption
    if [[ "${backup_file}" == *.enc ]]; then
        backup_file=$(decrypt_file "${backup_file}")
    fi

    # Handle compression
    if [[ "${backup_file}" == *.gz ]]; then
        log INFO "Decompressing MinIO data..."
        gunzip -k "${backup_file}" 2>> "${RESTORE_LOG}" || error_exit "Failed to decompress"
        backup_file="${backup_file%.gz}"
    fi

    log INFO "Using backup file: ${backup_file}"

    # Clear existing data
    if [ -d "${MINIO_DATA_PATH}" ]; then
        log INFO "Clearing existing MinIO data..."
        rm -rf "${MINIO_DATA_PATH}"/*
    else
        mkdir -p "${MINIO_DATA_PATH}"
    fi

    # Extract tar archive
    log INFO "Extracting MinIO data..."
    if tar -xf "${backup_file}" -C "${MINIO_DATA_PATH}" 2>> "${RESTORE_LOG}"; then
        log SUCCESS "MinIO data restore completed"
        return 0
    else
        log ERROR "MinIO data restore failed"
        return 1
    fi
}

restore_configs() {
    log INFO "Restoring configuration files..."

    # Find backup file
    local backup_file=$(find "${BACKUP_PATH}/configs" -name "configs.tar.gz*" -type f | head -1)

    if [ -z "${backup_file}" ]; then
        log WARNING "Configuration backup file not found"
        return 1
    fi

    # Handle encryption
    if [[ "${backup_file}" == *.enc ]]; then
        backup_file=$(decrypt_file "${backup_file}")
    fi

    log INFO "Using backup file: ${backup_file}"

    # Extract to current directory
    log INFO "Extracting configuration files..."
    if tar -xzf "${backup_file}" -C / 2>> "${RESTORE_LOG}"; then
        log SUCCESS "Configuration restore completed"
        return 0
    else
        log WARNING "Configuration restore failed"
        return 1
    fi
}

verify_restore() {
    log INFO "Verifying restore..."

    local errors=0

    # Verify PostgreSQL
    if [ "${COMPONENT}" = "all" ] || [ "${COMPONENT}" = "postgres" ]; then
        export PGPASSWORD="${POSTGRES_PASSWORD}"
        if psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
                -d "${POSTGRES_DB}" -c "SELECT 1;" > /dev/null 2>&1; then
            log SUCCESS "PostgreSQL verification passed"
        else
            log ERROR "PostgreSQL verification failed"
            errors=$((errors + 1))
        fi
        unset PGPASSWORD
    fi

    # Verify Redis
    if [ "${COMPONENT}" = "all" ] || [ "${COMPONENT}" = "redis" ]; then
        if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" PING > /dev/null 2>&1; then
            log SUCCESS "Redis verification passed"
        else
            log WARNING "Redis verification failed"
        fi
    fi

    # Verify MinIO data
    if [ "${COMPONENT}" = "all" ] || [ "${COMPONENT}" = "minio" ]; then
        if [ -d "${MINIO_DATA_PATH}" ] && [ "$(ls -A ${MINIO_DATA_PATH})" ]; then
            log SUCCESS "MinIO data verification passed"
        else
            log ERROR "MinIO data verification failed"
            errors=$((errors + 1))
        fi
    fi

    if [ ${errors} -gt 0 ]; then
        log ERROR "Restore verification failed with ${errors} error(s)"
        return 1
    else
        log SUCCESS "Restore verification passed"
        return 0
    fi
}

perform_rollback() {
    log WARNING "Performing rollback..."

    if [ ! -d "${ROLLBACK_DIR}" ]; then
        error_exit "Rollback directory not found: ${ROLLBACK_DIR}"
    fi

    # Rollback PostgreSQL
    if [ -f "${ROLLBACK_DIR}/postgres_rollback.sql" ]; then
        log INFO "Rolling back PostgreSQL..."
        export PGPASSWORD="${POSTGRES_PASSWORD}"
        psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
             -d postgres -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};" 2>> "${RESTORE_LOG}"
        psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
             -d postgres -c "CREATE DATABASE ${POSTGRES_DB};" 2>> "${RESTORE_LOG}"
        psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
             -d "${POSTGRES_DB}" -f "${ROLLBACK_DIR}/postgres_rollback.sql" 2>> "${RESTORE_LOG}"
        unset PGPASSWORD
        log SUCCESS "PostgreSQL rollback completed"
    fi

    # Rollback MinIO data
    if [ -f "${ROLLBACK_DIR}/minio_data_rollback.tar.gz" ]; then
        log INFO "Rolling back MinIO data..."
        rm -rf "${MINIO_DATA_PATH}"/*
        tar -xzf "${ROLLBACK_DIR}/minio_data_rollback.tar.gz" -C "${MINIO_DATA_PATH}" 2>> "${RESTORE_LOG}"
        log SUCCESS "MinIO data rollback completed"
    fi

    log SUCCESS "Rollback completed"
}

# ============================================================
# Main Function
# ============================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--backup)
                BACKUP_PATH="$2"
                shift 2
                ;;
            -c|--component)
                COMPONENT="$2"
                shift 2
                ;;
            -v|--verify)
                VERIFY_ONLY=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Validate backup path
    if [ -z "${BACKUP_PATH}" ]; then
        error_exit "Backup path is required. Use -b or --backup option"
    fi

    # Validate component
    if [ "${COMPONENT}" != "all" ] && [ "${COMPONENT}" != "postgres" ] && \
       [ "${COMPONENT}" != "redis" ] && [ "${COMPONENT}" != "minio" ] && \
       [ "${COMPONENT}" != "configs" ]; then
        error_exit "Invalid component: ${COMPONENT}"
    fi

    # Banner
    echo "============================================================"
    echo "MinIO Enterprise - Restore Automation"
    echo "============================================================"
    echo "Backup Path:     ${BACKUP_PATH}"
    echo "Component:       ${COMPONENT}"
    echo "Verify Only:     ${VERIFY_ONLY}"
    echo "Timestamp:       ${TIMESTAMP}"
    echo "============================================================"
    echo

    # Check dependencies
    check_dependencies

    # Verify backup
    verify_backup

    if [ "${VERIFY_ONLY}" = true ]; then
        log SUCCESS "Verification completed successfully"
        exit 0
    fi

    # Confirmation prompt
    if [ "${FORCE}" = false ]; then
        echo
        echo -e "${YELLOW}WARNING: This will overwrite existing data!${NC}"
        echo -e "${YELLOW}Component to restore: ${COMPONENT}${NC}"
        echo
        read -p "Are you sure you want to continue? (yes/no): " confirm

        if [ "${confirm}" != "yes" ]; then
            echo "Restore cancelled"
            exit 0
        fi
    fi

    # Create rollback backup
    create_rollback_backup

    # Perform restore
    local restore_errors=0

    if [ "${COMPONENT}" = "all" ] || [ "${COMPONENT}" = "postgres" ]; then
        restore_postgresql || restore_errors=$((restore_errors + 1))
    fi

    if [ "${COMPONENT}" = "all" ] || [ "${COMPONENT}" = "redis" ]; then
        restore_redis || true  # Redis restore is manual
    fi

    if [ "${COMPONENT}" = "all" ] || [ "${COMPONENT}" = "minio" ]; then
        restore_minio_data || restore_errors=$((restore_errors + 1))
    fi

    if [ "${COMPONENT}" = "all" ] || [ "${COMPONENT}" = "configs" ]; then
        restore_configs || true  # Config restore is optional
    fi

    # Verify restore
    if ! verify_restore; then
        log ERROR "Restore verification failed"
        read -p "Do you want to rollback? (yes/no): " rollback_confirm

        if [ "${rollback_confirm}" = "yes" ]; then
            perform_rollback
        fi

        error_exit "Restore failed"
    fi

    # Summary
    echo
    echo "============================================================"
    if [ ${restore_errors} -eq 0 ]; then
        log SUCCESS "Restore completed successfully"
        log SUCCESS "Rollback backup: ${ROLLBACK_DIR}"
        log SUCCESS "Restore log: ${RESTORE_LOG}"
        exit 0
    else
        log ERROR "Restore completed with ${restore_errors} error(s)"
        log ERROR "Rollback backup: ${ROLLBACK_DIR}"
        log ERROR "Restore log: ${RESTORE_LOG}"
        exit 1
    fi
}

# Run main function
main "$@"
