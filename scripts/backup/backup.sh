#!/bin/bash
#
# MinIO Enterprise - Backup Automation Script
# Version: 1.0.0
# Description: Automated backup script supporting full and incremental backups
#              with encryption, compression, and retention policies
#
# Usage:
#   ./backup.sh [OPTIONS]
#
# Options:
#   -t, --type <full|incremental>  Backup type (default: full)
#   -d, --destination <path>       Backup destination directory
#   -e, --encrypt                  Enable encryption
#   -c, --compress                 Enable compression
#   -r, --retention <days>         Retention period in days (default: 30)
#   -v, --verbose                  Verbose output
#   -h, --help                     Show this help message
#
# Environment Variables:
#   BACKUP_DESTINATION     Backup destination directory (default: /var/backups/minio)
#   BACKUP_TYPE           Backup type: full or incremental (default: full)
#   BACKUP_ENCRYPT        Enable encryption: true or false (default: false)
#   BACKUP_COMPRESS       Enable compression: true or false (default: true)
#   BACKUP_RETENTION_DAYS Retention period in days (default: 30)
#   ENCRYPTION_KEY        Encryption key (required if BACKUP_ENCRYPT=true)
#   POSTGRES_HOST         PostgreSQL host (default: localhost)
#   POSTGRES_PORT         PostgreSQL port (default: 5432)
#   POSTGRES_USER         PostgreSQL user (default: postgres)
#   POSTGRES_PASSWORD     PostgreSQL password
#   POSTGRES_DB           PostgreSQL database (default: minio)
#   REDIS_HOST            Redis host (default: localhost)
#   REDIS_PORT            Redis port (default: 6379)
#   MINIO_DATA_PATH       MinIO data directory (default: /data)
#

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

# Default configuration
BACKUP_DESTINATION="${BACKUP_DESTINATION:-/var/backups/minio}"
BACKUP_TYPE="${BACKUP_TYPE:-full}"
BACKUP_ENCRYPT="${BACKUP_ENCRYPT:-false}"
BACKUP_COMPRESS="${BACKUP_COMPRESS:-true}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-minio}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
MINIO_DATA_PATH="${MINIO_DATA_PATH:-/data}"
VERBOSE=false

# Backup metadata
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_ID="backup_${BACKUP_TYPE}_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DESTINATION}/${BACKUP_ID}"
MANIFEST_FILE="${BACKUP_PATH}/manifest.json"
LOG_FILE="${BACKUP_PATH}/backup.log"

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
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}" 2>/dev/null || true

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
    exit 1
}

show_help() {
    cat << EOF
MinIO Enterprise - Backup Automation Script

Usage: $0 [OPTIONS]

Options:
  -t, --type <full|incremental>  Backup type (default: full)
  -d, --destination <path>       Backup destination directory
  -e, --encrypt                  Enable encryption
  -c, --compress                 Enable compression
  -r, --retention <days>         Retention period in days (default: 30)
  -v, --verbose                  Verbose output
  -h, --help                     Show this help message

Environment Variables:
  BACKUP_DESTINATION     Backup destination directory
  BACKUP_TYPE           Backup type: full or incremental
  BACKUP_ENCRYPT        Enable encryption: true or false
  BACKUP_COMPRESS       Enable compression: true or false
  BACKUP_RETENTION_DAYS Retention period in days
  ENCRYPTION_KEY        Encryption key (required if encryption enabled)
  POSTGRES_HOST         PostgreSQL host
  POSTGRES_USER         PostgreSQL user
  POSTGRES_PASSWORD     PostgreSQL password
  REDIS_HOST            Redis host
  MINIO_DATA_PATH       MinIO data directory

Examples:
  # Full backup with compression
  $0 --type full --compress --destination /backups

  # Incremental backup with encryption
  ENCRYPTION_KEY=mysecret $0 --type incremental --encrypt

  # Full backup with 60-day retention
  $0 --retention 60

EOF
}

check_dependencies() {
    log INFO "Checking dependencies..."

    local missing_deps=()

    command -v pg_dump >/dev/null 2>&1 || missing_deps+=("postgresql-client")
    command -v redis-cli >/dev/null 2>&1 || missing_deps+=("redis-tools")
    command -v tar >/dev/null 2>&1 || missing_deps+=("tar")

    if [ "${BACKUP_ENCRYPT}" = true ]; then
        command -v openssl >/dev/null 2>&1 || missing_deps+=("openssl")
    fi

    if [ "${#missing_deps[@]}" -gt 0 ]; then
        error_exit "Missing dependencies: ${missing_deps[*]}"
    fi

    log INFO "All dependencies satisfied"
}

create_backup_directory() {
    log INFO "Creating backup directory: ${BACKUP_PATH}"
    mkdir -p "${BACKUP_PATH}" || error_exit "Failed to create backup directory"

    # Create subdirectories
    mkdir -p "${BACKUP_PATH}/postgres"
    mkdir -p "${BACKUP_PATH}/redis"
    mkdir -p "${BACKUP_PATH}/minio-data"
    mkdir -p "${BACKUP_PATH}/configs"
}

backup_postgresql() {
    log INFO "Backing up PostgreSQL database..."

    local dump_file="${BACKUP_PATH}/postgres/database.sql"

    export PGPASSWORD="${POSTGRES_PASSWORD}"

    if pg_dump -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
               -d "${POSTGRES_DB}" -f "${dump_file}" --verbose 2>> "${LOG_FILE}"; then

        local size=$(du -h "${dump_file}" | cut -f1)
        log SUCCESS "PostgreSQL backup completed (${size})"

        # Compress if enabled
        if [ "${BACKUP_COMPRESS}" = true ]; then
            log INFO "Compressing PostgreSQL backup..."
            gzip "${dump_file}" || log WARNING "Failed to compress PostgreSQL backup"
            dump_file="${dump_file}.gz"
        fi

        # Encrypt if enabled
        if [ "${BACKUP_ENCRYPT}" = true ]; then
            log INFO "Encrypting PostgreSQL backup..."
            encrypt_file "${dump_file}"
        fi

        return 0
    else
        log ERROR "PostgreSQL backup failed"
        return 1
    fi

    unset PGPASSWORD
}

backup_redis() {
    log INFO "Backing up Redis data..."

    # Trigger Redis snapshot
    if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" BGSAVE > /dev/null 2>&1; then
        log INFO "Redis BGSAVE triggered, waiting for completion..."

        # Wait for BGSAVE to complete (max 60 seconds)
        local count=0
        while [ $count -lt 60 ]; do
            if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" LASTSAVE > /tmp/redis_lastsave_new 2>/dev/null; then
                sleep 1
                if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" LASTSAVE > /tmp/redis_lastsave_check 2>/dev/null; then
                    if ! diff /tmp/redis_lastsave_new /tmp/redis_lastsave_check > /dev/null 2>&1; then
                        break
                    fi
                fi
            fi
            count=$((count + 1))
            sleep 1
        done

        # Export Redis data using redis-cli
        local redis_dump="${BACKUP_PATH}/redis/redis.rdb"
        if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" --rdb "${redis_dump}" > /dev/null 2>&1; then
            local size=$(du -h "${redis_dump}" | cut -f1)
            log SUCCESS "Redis backup completed (${size})"

            # Compress if enabled
            if [ "${BACKUP_COMPRESS}" = true ]; then
                log INFO "Compressing Redis backup..."
                gzip "${redis_dump}" || log WARNING "Failed to compress Redis backup"
                redis_dump="${redis_dump}.gz"
            fi

            # Encrypt if enabled
            if [ "${BACKUP_ENCRYPT}" = true ]; then
                log INFO "Encrypting Redis backup..."
                encrypt_file "${redis_dump}"
            fi

            return 0
        else
            log WARNING "Failed to export Redis data"
            return 1
        fi
    else
        log WARNING "Failed to trigger Redis BGSAVE"
        return 1
    fi
}

backup_minio_data() {
    log INFO "Backing up MinIO data..."

    if [ ! -d "${MINIO_DATA_PATH}" ]; then
        log WARNING "MinIO data path not found: ${MINIO_DATA_PATH}"
        return 1
    fi

    local tar_file="${BACKUP_PATH}/minio-data/data.tar"

    # Determine backup type
    local tar_options="-cf"
    local incremental_file=""

    if [ "${BACKUP_TYPE}" = "incremental" ]; then
        log INFO "Performing incremental backup..."

        # Find the most recent full backup
        local last_full_backup=$(find "${BACKUP_DESTINATION}" -name "backup_full_*" -type d | sort -r | head -n1)

        if [ -n "${last_full_backup}" ]; then
            incremental_file="${last_full_backup}/minio-data/.snapshot"
            tar_options="-cf --listed-incremental=${BACKUP_PATH}/minio-data/.snapshot"

            # Copy snapshot file if it exists
            if [ -f "${incremental_file}" ]; then
                cp "${incremental_file}" "${BACKUP_PATH}/minio-data/.snapshot"
            fi
        else
            log WARNING "No full backup found, performing full backup instead"
            BACKUP_TYPE="full"
        fi
    fi

    # Create tar archive
    if tar ${tar_options} "${tar_file}" -C "${MINIO_DATA_PATH}" . 2>> "${LOG_FILE}"; then
        local size=$(du -h "${tar_file}" | cut -f1)
        log SUCCESS "MinIO data backup completed (${size})"

        # Compress if enabled
        if [ "${BACKUP_COMPRESS}" = true ]; then
            log INFO "Compressing MinIO data backup..."
            gzip "${tar_file}" || log WARNING "Failed to compress MinIO data backup"
            tar_file="${tar_file}.gz"
        fi

        # Encrypt if enabled
        if [ "${BACKUP_ENCRYPT}" = true ]; then
            log INFO "Encrypting MinIO data backup..."
            encrypt_file "${tar_file}"
        fi

        return 0
    else
        log ERROR "MinIO data backup failed"
        return 1
    fi
}

backup_configs() {
    log INFO "Backing up configuration files..."

    local config_sources=(
        "configs"
        "deployments"
        ".env"
    )

    local config_tar="${BACKUP_PATH}/configs/configs.tar.gz"
    local config_files=()

    # Collect existing config files
    for source in "${config_sources[@]}"; do
        if [ -e "${source}" ]; then
            config_files+=("${source}")
        fi
    done

    if [ ${#config_files[@]} -eq 0 ]; then
        log WARNING "No configuration files found"
        return 1
    fi

    # Create tar archive
    if tar -czf "${config_tar}" "${config_files[@]}" 2>> "${LOG_FILE}"; then
        local size=$(du -h "${config_tar}" | cut -f1)
        log SUCCESS "Configuration backup completed (${size})"

        # Encrypt if enabled
        if [ "${BACKUP_ENCRYPT}" = true ]; then
            log INFO "Encrypting configuration backup..."
            encrypt_file "${config_tar}"
        fi

        return 0
    else
        log WARNING "Configuration backup failed"
        return 1
    fi
}

encrypt_file() {
    local file=$1

    if [ -z "${ENCRYPTION_KEY:-}" ]; then
        log WARNING "ENCRYPTION_KEY not set, skipping encryption"
        return 1
    fi

    if openssl enc -aes-256-cbc -salt -pbkdf2 -in "${file}" -out "${file}.enc" -k "${ENCRYPTION_KEY}" 2>> "${LOG_FILE}"; then
        rm -f "${file}"
        log INFO "File encrypted: ${file}.enc"
        return 0
    else
        log ERROR "Failed to encrypt file: ${file}"
        return 1
    fi
}

create_manifest() {
    log INFO "Creating backup manifest..."

    cat > "${MANIFEST_FILE}" << EOF
{
  "backup_id": "${BACKUP_ID}",
  "timestamp": "${TIMESTAMP}",
  "type": "${BACKUP_TYPE}",
  "encryption": ${BACKUP_ENCRYPT},
  "compression": ${BACKUP_COMPRESS},
  "components": {
    "postgresql": $([ -f "${BACKUP_PATH}/postgres/database.sql"* ] && echo "true" || echo "false"),
    "redis": $([ -f "${BACKUP_PATH}/redis/redis.rdb"* ] && echo "true" || echo "false"),
    "minio_data": $([ -f "${BACKUP_PATH}/minio-data/data.tar"* ] && echo "true" || echo "false"),
    "configs": $([ -f "${BACKUP_PATH}/configs/configs.tar.gz"* ] && echo "true" || echo "false")
  },
  "size": "$(du -sh ${BACKUP_PATH} | cut -f1)",
  "retention_days": ${BACKUP_RETENTION_DAYS}
}
EOF

    log SUCCESS "Manifest created: ${MANIFEST_FILE}"
}

verify_backup() {
    log INFO "Verifying backup integrity..."

    local errors=0

    # Check if critical files exist
    [ ! -f "${MANIFEST_FILE}" ] && log ERROR "Manifest file missing" && errors=$((errors + 1))

    # Verify each component
    local postgres_files=$(find "${BACKUP_PATH}/postgres" -type f 2>/dev/null | wc -l)
    local redis_files=$(find "${BACKUP_PATH}/redis" -type f 2>/dev/null | wc -l)
    local minio_files=$(find "${BACKUP_PATH}/minio-data" -type f 2>/dev/null | wc -l)

    [ "${postgres_files}" -eq 0 ] && log WARNING "PostgreSQL backup not found" && errors=$((errors + 1))
    [ "${redis_files}" -eq 0 ] && log WARNING "Redis backup not found"
    [ "${minio_files}" -eq 0 ] && log WARNING "MinIO data backup not found" && errors=$((errors + 1))

    if [ ${errors} -gt 0 ]; then
        log WARNING "Backup verification completed with ${errors} error(s)"
        return 1
    else
        log SUCCESS "Backup verification passed"
        return 0
    fi
}

apply_retention_policy() {
    log INFO "Applying retention policy (${BACKUP_RETENTION_DAYS} days)..."

    local deleted_count=0
    local cutoff_date=$(date -d "${BACKUP_RETENTION_DAYS} days ago" +%Y%m%d 2>/dev/null || date -v-${BACKUP_RETENTION_DAYS}d +%Y%m%d)

    # Find and delete old backups
    while IFS= read -r backup_dir; do
        local backup_date=$(basename "${backup_dir}" | grep -oP '\d{8}' | head -1)

        if [ -n "${backup_date}" ] && [ "${backup_date}" -lt "${cutoff_date}" ]; then
            log INFO "Deleting old backup: ${backup_dir}"
            rm -rf "${backup_dir}"
            deleted_count=$((deleted_count + 1))
        fi
    done < <(find "${BACKUP_DESTINATION}" -maxdepth 1 -type d -name "backup_*" 2>/dev/null || true)

    if [ ${deleted_count} -gt 0 ]; then
        log SUCCESS "Deleted ${deleted_count} old backup(s)"
    else
        log INFO "No old backups to delete"
    fi
}

# ============================================================
# Main Function
# ============================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                BACKUP_TYPE="$2"
                shift 2
                ;;
            -d|--destination)
                BACKUP_DESTINATION="$2"
                shift 2
                ;;
            -e|--encrypt)
                BACKUP_ENCRYPT=true
                shift
                ;;
            -c|--compress)
                BACKUP_COMPRESS=true
                shift
                ;;
            -r|--retention)
                BACKUP_RETENTION_DAYS="$2"
                shift 2
                ;;
            -v|--verbose)
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

    # Validate backup type
    if [ "${BACKUP_TYPE}" != "full" ] && [ "${BACKUP_TYPE}" != "incremental" ]; then
        error_exit "Invalid backup type: ${BACKUP_TYPE}. Must be 'full' or 'incremental'"
    fi

    # Banner
    echo "============================================================"
    echo "MinIO Enterprise - Backup Automation"
    echo "============================================================"
    echo "Backup Type:        ${BACKUP_TYPE}"
    echo "Destination:        ${BACKUP_DESTINATION}"
    echo "Encryption:         ${BACKUP_ENCRYPT}"
    echo "Compression:        ${BACKUP_COMPRESS}"
    echo "Retention (days):   ${BACKUP_RETENTION_DAYS}"
    echo "Timestamp:          ${TIMESTAMP}"
    echo "============================================================"
    echo

    # Check dependencies
    check_dependencies

    # Create backup directory
    create_backup_directory

    # Initialize log file
    log INFO "Backup started: ${BACKUP_ID}"

    # Perform backups
    local backup_errors=0

    backup_postgresql || backup_errors=$((backup_errors + 1))
    backup_redis || true  # Redis backup is optional
    backup_minio_data || backup_errors=$((backup_errors + 1))
    backup_configs || true  # Config backup is optional

    # Create manifest
    create_manifest

    # Verify backup
    verify_backup || backup_errors=$((backup_errors + 1))

    # Apply retention policy
    apply_retention_policy

    # Summary
    echo
    echo "============================================================"
    if [ ${backup_errors} -eq 0 ]; then
        log SUCCESS "Backup completed successfully"
        log SUCCESS "Backup location: ${BACKUP_PATH}"
        log SUCCESS "Backup size: $(du -sh ${BACKUP_PATH} | cut -f1)"
        exit 0
    else
        log ERROR "Backup completed with ${backup_errors} error(s)"
        log ERROR "Check log file: ${LOG_FILE}"
        exit 1
    fi
}

# Run main function
main "$@"
