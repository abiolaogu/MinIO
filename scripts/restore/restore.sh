#!/bin/bash
#
# MinIO Enterprise Restore Script
# Restores MinIO data, PostgreSQL, Redis, and configuration files from backup
#
# Version: 1.0.0
# Date: 2026-02-07
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/minio}"
LOG_FILE="${LOG_FILE:-/var/log/minio-restore.log}"

# Service configuration
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-minio}"
POSTGRES_DB="${POSTGRES_DB:-minio}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
MINIO_DATA_DIR="${MINIO_DATA_DIR:-/data/minio}"
CONFIG_DIR="${CONFIG_DIR:-/etc/minio}"

# Restore options
DRY_RUN="${DRY_RUN:-false}"
VERIFY_ONLY="${VERIFY_ONLY:-false}"
RESTORE_POSTGRES="${RESTORE_POSTGRES:-true}"
RESTORE_REDIS="${RESTORE_REDIS:-true}"
RESTORE_MINIO_DATA="${RESTORE_MINIO_DATA:-true}"
RESTORE_CONFIG="${RESTORE_CONFIG:-true}"

# Encryption configuration
ENCRYPTION_KEY_FILE="${ENCRYPTION_KEY_FILE:-${SCRIPT_DIR}/../backup/.backup.key}"

# ============================================================================
# Helper Functions
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

error_exit() {
    log "ERROR" "$1"
    exit 1
}

prompt_confirmation() {
    local message="$1"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY RUN] Would prompt: ${message}"
        return 0
    fi

    read -p "${message} (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "INFO" "Operation cancelled by user"
        exit 0
    fi
}

check_dependencies() {
    local deps=("pg_restore" "redis-cli" "tar" "gzip")

    for cmd in "${deps[@]}"; do
        if ! command -v "${cmd}" &> /dev/null; then
            error_exit "Required command '${cmd}' not found. Please install it."
        fi
    done

    log "INFO" "All dependencies checked successfully"
}

list_available_backups() {
    log "INFO" "Available backups:"
    echo

    local backups=$(find "${BACKUP_DIR}" -maxdepth 1 -type d -name "[0-9]*" | sort -r)

    if [[ -z "${backups}" ]]; then
        error_exit "No backups found in ${BACKUP_DIR}"
    fi

    local count=1
    while IFS= read -r backup; do
        local backup_name=$(basename "${backup}")
        local backup_size=$(du -sh "${backup}" 2>/dev/null | cut -f1)
        local manifest="${backup}/manifest.txt"

        echo "${count}. ${backup_name} (${backup_size})"

        if [[ -f "${manifest}" ]]; then
            local backup_date=$(grep "Backup Date:" "${manifest}" | cut -d: -f2- | xargs)
            local backup_type=$(grep "Backup Type:" "${manifest}" | cut -d: -f2 | xargs)
            echo "   Date: ${backup_date}"
            echo "   Type: ${backup_type}"
        fi

        echo

        count=$((count + 1))
    done <<< "${backups}"

    echo "${backups}"
}

select_backup() {
    local backups=$(list_available_backups)
    local backup_array=()

    while IFS= read -r line; do
        backup_array+=("${line}")
    done <<< "${backups}"

    if [[ ${#backup_array[@]} -eq 0 ]]; then
        error_exit "No backups available"
    fi

    if [[ ${#backup_array[@]} -eq 1 ]]; then
        log "INFO" "Using only available backup: $(basename ${backup_array[0]})"
        echo "${backup_array[0]}"
        return
    fi

    echo "Select a backup to restore (1-${#backup_array[@]}):"
    read -r selection

    if [[ ! "${selection}" =~ ^[0-9]+$ ]] || [[ "${selection}" -lt 1 ]] || [[ "${selection}" -gt ${#backup_array[@]} ]]; then
        error_exit "Invalid selection"
    fi

    local selected_backup="${backup_array[$((selection - 1))]}"
    log "INFO" "Selected backup: $(basename ${selected_backup})"
    echo "${selected_backup}"
}

verify_backup() {
    local backup_dir="$1"

    log "INFO" "Verifying backup integrity"

    local manifest_file="${backup_dir}/manifest.txt"
    if [[ ! -f "${manifest_file}" ]]; then
        error_exit "Manifest file not found: ${manifest_file}"
    fi

    # Verify checksums
    local checksum_section=$(sed -n '/^Checksums:/,/^$/p' "${manifest_file}" | tail -n +2)
    local verification_failed=false

    while IFS= read -r line; do
        if [[ -n "${line}" ]]; then
            local expected_sum=$(echo "${line}" | awk '{print $1}')
            local file_path=$(echo "${line}" | awk '{print $2}')

            if [[ -f "${file_path}" ]]; then
                local actual_sum=$(sha256sum "${file_path}" | awk '{print $1}')
                if [[ "${expected_sum}" == "${actual_sum}" ]]; then
                    log "INFO" "✓ Checksum verified: $(basename ${file_path})"
                else
                    log "ERROR" "✗ Checksum mismatch: $(basename ${file_path})"
                    verification_failed=true
                fi
            else
                log "ERROR" "✗ File not found: ${file_path}"
                verification_failed=true
            fi
        fi
    done <<< "${checksum_section}"

    if [[ "${verification_failed}" == "true" ]]; then
        error_exit "Backup verification failed"
    fi

    log "INFO" "Backup verification completed successfully"
}

decrypt_file() {
    local encrypted_file="$1"
    local decrypted_file="${encrypted_file%.enc}"

    if [[ ! "${encrypted_file}" =~ \.enc$ ]]; then
        echo "${encrypted_file}"
        return
    fi

    if [[ ! -f "${ENCRYPTION_KEY_FILE}" ]]; then
        error_exit "Encryption key file not found: ${ENCRYPTION_KEY_FILE}"
    fi

    log "INFO" "Decrypting ${encrypted_file}"
    openssl enc -aes-256-cbc -d -pbkdf2 -in "${encrypted_file}" \
        -out "${decrypted_file}" -pass file:"${ENCRYPTION_KEY_FILE}"

    echo "${decrypted_file}"
}

decompress_file() {
    local compressed_file="$1"
    local decompressed_file="${compressed_file%.gz}"

    if [[ ! "${compressed_file}" =~ \.gz$ ]]; then
        echo "${compressed_file}"
        return
    fi

    log "INFO" "Decompressing ${compressed_file}"
    gunzip -c "${compressed_file}" > "${decompressed_file}"

    echo "${decompressed_file}"
}

prepare_backup_file() {
    local backup_file="$1"

    # Decrypt if encrypted
    if [[ "${backup_file}" =~ \.enc$ ]]; then
        backup_file=$(decrypt_file "${backup_file}")
    fi

    # Decompress if compressed
    if [[ "${backup_file}" =~ \.gz$ ]]; then
        backup_file=$(decompress_file "${backup_file}")
    fi

    echo "${backup_file}"
}

# ============================================================================
# Restore Functions
# ============================================================================

restore_postgresql() {
    local backup_dir="$1"

    log "INFO" "Starting PostgreSQL restore"

    # Find PostgreSQL backup file
    local pg_backup=$(find "${backup_dir}" -name "postgresql_backup.sql*" | head -n 1)

    if [[ -z "${pg_backup}" ]]; then
        log "WARN" "PostgreSQL backup not found in ${backup_dir}"
        return 1
    fi

    # Prepare backup file (decrypt/decompress)
    pg_backup=$(prepare_backup_file "${pg_backup}")

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY RUN] Would restore PostgreSQL from: ${pg_backup}"
        return 0
    fi

    # Create backup of current database
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local pre_restore_backup="/tmp/minio_pre_restore_${timestamp}.sql"
    log "INFO" "Creating pre-restore backup: ${pre_restore_backup}"

    PGPASSWORD="${POSTGRES_PASSWORD:-}" pg_dump \
        -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT}" \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        --format=custom \
        --file="${pre_restore_backup}" 2>&1 | tee -a "${LOG_FILE}"

    # Drop and recreate database
    prompt_confirmation "This will DROP and recreate the database '${POSTGRES_DB}'. Continue?"

    log "INFO" "Dropping database ${POSTGRES_DB}"
    PGPASSWORD="${POSTGRES_PASSWORD:-}" psql \
        -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT}" \
        -U "${POSTGRES_USER}" \
        -d postgres \
        -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};" 2>&1 | tee -a "${LOG_FILE}"

    log "INFO" "Creating database ${POSTGRES_DB}"
    PGPASSWORD="${POSTGRES_PASSWORD:-}" psql \
        -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT}" \
        -U "${POSTGRES_USER}" \
        -d postgres \
        -c "CREATE DATABASE ${POSTGRES_DB};" 2>&1 | tee -a "${LOG_FILE}"

    # Restore from backup
    log "INFO" "Restoring PostgreSQL from backup"
    PGPASSWORD="${POSTGRES_PASSWORD:-}" pg_restore \
        -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT}" \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        --verbose \
        "${pg_backup}" 2>&1 | tee -a "${LOG_FILE}"

    if [[ $? -eq 0 ]]; then
        log "INFO" "PostgreSQL restore completed successfully"
        log "INFO" "Pre-restore backup saved at: ${pre_restore_backup}"
        return 0
    else
        log "ERROR" "PostgreSQL restore failed"
        log "INFO" "Rolling back to pre-restore backup"

        PGPASSWORD="${POSTGRES_PASSWORD:-}" psql \
            -h "${POSTGRES_HOST}" \
            -p "${POSTGRES_PORT}" \
            -U "${POSTGRES_USER}" \
            -d postgres \
            -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};" 2>&1 | tee -a "${LOG_FILE}"

        PGPASSWORD="${POSTGRES_PASSWORD:-}" psql \
            -h "${POSTGRES_HOST}" \
            -p "${POSTGRES_PORT}" \
            -U "${POSTGRES_USER}" \
            -d postgres \
            -c "CREATE DATABASE ${POSTGRES_DB};" 2>&1 | tee -a "${LOG_FILE}"

        PGPASSWORD="${POSTGRES_PASSWORD:-}" pg_restore \
            -h "${POSTGRES_HOST}" \
            -p "${POSTGRES_PORT}" \
            -U "${POSTGRES_USER}" \
            -d "${POSTGRES_DB}" \
            "${pre_restore_backup}" 2>&1 | tee -a "${LOG_FILE}"

        error_exit "PostgreSQL restore failed and rolled back"
    fi
}

restore_redis() {
    local backup_dir="$1"

    log "INFO" "Starting Redis restore"

    # Find Redis backup file
    local redis_backup=$(find "${backup_dir}" -name "redis_backup.rdb*" | head -n 1)

    if [[ -z "${redis_backup}" ]]; then
        log "WARN" "Redis backup not found in ${backup_dir}"
        return 1
    fi

    # Prepare backup file (decrypt/decompress)
    redis_backup=$(prepare_backup_file "${redis_backup}")

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY RUN] Would restore Redis from: ${redis_backup}"
        return 0
    fi

    prompt_confirmation "This will FLUSH all Redis data and restore from backup. Continue?"

    # Stop Redis writes
    log "INFO" "Setting Redis to read-only mode"
    redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" CONFIG SET save "" 2>&1 | tee -a "${LOG_FILE}"

    # Flush current data
    log "INFO" "Flushing Redis data"
    redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" FLUSHALL 2>&1 | tee -a "${LOG_FILE}"

    # Copy backup file
    local redis_dump_dir="/var/lib/redis"
    local redis_dump="${redis_dump_dir}/dump.rdb"

    log "INFO" "Stopping Redis to replace dump file"
    systemctl stop redis 2>&1 | tee -a "${LOG_FILE}" || true

    # Backup current dump file
    if [[ -f "${redis_dump}" ]]; then
        mv "${redis_dump}" "${redis_dump}.backup.$(date +%s)"
    fi

    # Copy restore file
    cp "${redis_backup}" "${redis_dump}"
    chown redis:redis "${redis_dump}"
    chmod 644 "${redis_dump}"

    # Start Redis
    log "INFO" "Starting Redis"
    systemctl start redis 2>&1 | tee -a "${LOG_FILE}"

    # Wait for Redis to start
    sleep 3

    # Verify restore
    local keys_count=$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" DBSIZE | awk '{print $2}')
    log "INFO" "Redis restore completed. Keys restored: ${keys_count}"

    return 0
}

restore_minio_data() {
    local backup_dir="$1"

    log "INFO" "Starting MinIO data restore"

    # Find MinIO data backup file
    local minio_backup=$(find "${backup_dir}" -name "minio_data.tar*" | head -n 1)

    if [[ -z "${minio_backup}" ]]; then
        log "WARN" "MinIO data backup not found in ${backup_dir}"
        return 1
    fi

    # Prepare backup file (decrypt/decompress)
    minio_backup=$(prepare_backup_file "${minio_backup}")

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY RUN] Would restore MinIO data from: ${minio_backup}"
        return 0
    fi

    prompt_confirmation "This will REPLACE all MinIO data in ${MINIO_DATA_DIR}. Continue?"

    # Create backup of current data
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local pre_restore_backup="/tmp/minio_data_pre_restore_${timestamp}.tar.gz"

    if [[ -d "${MINIO_DATA_DIR}" ]]; then
        log "INFO" "Creating pre-restore backup: ${pre_restore_backup}"
        tar -czf "${pre_restore_backup}" -C "${MINIO_DATA_DIR}" . 2>&1 | tee -a "${LOG_FILE}"
    fi

    # Clear current data
    log "INFO" "Clearing current MinIO data"
    rm -rf "${MINIO_DATA_DIR}"/*

    # Restore from backup
    log "INFO" "Restoring MinIO data from backup"
    tar -xf "${minio_backup}" -C "${MINIO_DATA_DIR}" 2>&1 | tee -a "${LOG_FILE}"

    if [[ $? -eq 0 ]]; then
        log "INFO" "MinIO data restore completed successfully"
        log "INFO" "Pre-restore backup saved at: ${pre_restore_backup}"
        return 0
    else
        log "ERROR" "MinIO data restore failed"
        log "INFO" "Rolling back to pre-restore backup"

        rm -rf "${MINIO_DATA_DIR}"/*
        tar -xzf "${pre_restore_backup}" -C "${MINIO_DATA_DIR}" 2>&1 | tee -a "${LOG_FILE}"

        error_exit "MinIO data restore failed and rolled back"
    fi
}

restore_configuration() {
    local backup_dir="$1"

    log "INFO" "Starting configuration restore"

    # Find configuration backup file
    local config_backup=$(find "${backup_dir}" -name "configuration.tar.gz*" | head -n 1)

    if [[ -z "${config_backup}" ]]; then
        log "WARN" "Configuration backup not found in ${backup_dir}"
        return 1
    fi

    # Prepare backup file (decrypt if encrypted)
    if [[ "${config_backup}" =~ \.enc$ ]]; then
        config_backup=$(decrypt_file "${config_backup}")
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[DRY RUN] Would restore configuration from: ${config_backup}"
        return 0
    fi

    prompt_confirmation "This will restore configuration files. Continue?"

    # Extract to root (preserves paths)
    log "INFO" "Restoring configuration files"
    tar -xzf "${config_backup}" -C / 2>&1 | tee -a "${LOG_FILE}"

    if [[ $? -eq 0 ]]; then
        log "INFO" "Configuration restore completed successfully"
        return 0
    else
        error_exit "Configuration restore failed"
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Restore MinIO Enterprise from backup.

OPTIONS:
    --backup-dir DIR          Backup directory (default: ${BACKUP_DIR})
    --dry-run                 Show what would be restored without making changes
    --verify-only             Only verify backup integrity
    --skip-postgres           Skip PostgreSQL restore
    --skip-redis              Skip Redis restore
    --skip-minio-data         Skip MinIO data restore
    --skip-config             Skip configuration restore
    -h, --help                Show this help message

EXAMPLES:
    # List and select backup to restore
    $0

    # Restore specific backup
    $0 --backup-dir /var/backups/minio/20260207_020000

    # Dry run (no actual changes)
    $0 --dry-run

    # Verify backup integrity only
    $0 --verify-only --backup-dir /var/backups/minio/20260207_020000

    # Restore only PostgreSQL
    $0 --skip-redis --skip-minio-data --skip-config

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verify-only)
                VERIFY_ONLY=true
                shift
                ;;
            --skip-postgres)
                RESTORE_POSTGRES=false
                shift
                ;;
            --skip-redis)
                RESTORE_REDIS=false
                shift
                ;;
            --skip-minio-data)
                RESTORE_MINIO_DATA=false
                shift
                ;;
            --skip-config)
                RESTORE_CONFIG=false
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

main() {
    parse_arguments "$@"

    log "INFO" "=========================================="
    log "INFO" "MinIO Enterprise Restore Started"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "MODE: DRY RUN (no changes will be made)"
    fi
    log "INFO" "=========================================="

    # Pre-flight checks
    check_dependencies

    # Select or verify backup
    local backup_dir
    if [[ -d "${BACKUP_DIR}" ]] && [[ -f "${BACKUP_DIR}/manifest.txt" ]]; then
        backup_dir="${BACKUP_DIR}"
        log "INFO" "Using specified backup: ${backup_dir}"
    else
        backup_dir=$(select_backup)
    fi

    # Verify backup integrity
    verify_backup "${backup_dir}"

    if [[ "${VERIFY_ONLY}" == "true" ]]; then
        log "INFO" "Verification complete. Exiting (verify-only mode)."
        exit 0
    fi

    # Perform restores
    if [[ "${RESTORE_POSTGRES}" == "true" ]]; then
        restore_postgresql "${backup_dir}" || log "WARN" "PostgreSQL restore skipped or failed"
    fi

    if [[ "${RESTORE_REDIS}" == "true" ]]; then
        restore_redis "${backup_dir}" || log "WARN" "Redis restore skipped or failed"
    fi

    if [[ "${RESTORE_MINIO_DATA}" == "true" ]]; then
        restore_minio_data "${backup_dir}" || log "WARN" "MinIO data restore skipped or failed"
    fi

    if [[ "${RESTORE_CONFIG}" == "true" ]]; then
        restore_configuration "${backup_dir}" || log "WARN" "Configuration restore skipped or failed"
    fi

    log "INFO" "=========================================="
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "Dry run completed (no changes made)"
    else
        log "INFO" "Restore completed successfully"
        log "INFO" "Please restart MinIO services to apply changes"
    fi
    log "INFO" "=========================================="

    exit 0
}

# Run main function
main "$@"
