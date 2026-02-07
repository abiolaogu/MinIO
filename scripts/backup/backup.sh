#!/bin/bash
#
# MinIO Enterprise Backup Script
# Automates backup of MinIO data, PostgreSQL, Redis, and configuration files
#
# Version: 1.0.0
# Date: 2026-02-07
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

# Load configuration from file if exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/backup.config"

# Default configuration
BACKUP_TYPE="${BACKUP_TYPE:-full}"           # full or incremental
BACKUP_DIR="${BACKUP_DIR:-/var/backups/minio}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
ENABLE_ENCRYPTION="${ENABLE_ENCRYPTION:-false}"
ENABLE_COMPRESSION="${ENABLE_COMPRESSION:-true}"
LOG_FILE="${LOG_FILE:-/var/log/minio-backup.log}"

# Service configuration
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-minio}"
POSTGRES_DB="${POSTGRES_DB:-minio}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
MINIO_DATA_DIR="${MINIO_DATA_DIR:-/data/minio}"
CONFIG_DIR="${CONFIG_DIR:-/etc/minio}"

# S3 remote backup (optional)
S3_ENABLED="${S3_ENABLED:-false}"
S3_BUCKET="${S3_BUCKET:-}"
S3_ENDPOINT="${S3_ENDPOINT:-}"

# Encryption configuration
ENCRYPTION_KEY_FILE="${ENCRYPTION_KEY_FILE:-${SCRIPT_DIR}/.backup.key}"

# Load external config if exists
[[ -f "${CONFIG_FILE}" ]] && source "${CONFIG_FILE}"

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

check_dependencies() {
    local deps=("pg_dump" "redis-cli" "tar" "gzip")

    if [[ "${ENABLE_ENCRYPTION}" == "true" ]]; then
        deps+=("openssl")
    fi

    for cmd in "${deps[@]}"; do
        if ! command -v "${cmd}" &> /dev/null; then
            error_exit "Required command '${cmd}' not found. Please install it."
        fi
    done

    log "INFO" "All dependencies checked successfully"
}

create_backup_dir() {
    local backup_timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_subdir="${BACKUP_DIR}/${backup_timestamp}"

    mkdir -p "${backup_subdir}"
    echo "${backup_subdir}"
}

generate_encryption_key() {
    if [[ ! -f "${ENCRYPTION_KEY_FILE}" ]]; then
        log "INFO" "Generating new encryption key"
        openssl rand -base64 32 > "${ENCRYPTION_KEY_FILE}"
        chmod 600 "${ENCRYPTION_KEY_FILE}"
    fi
}

encrypt_file() {
    local input_file="$1"
    local output_file="${input_file}.enc"

    log "INFO" "Encrypting ${input_file}"
    openssl enc -aes-256-cbc -salt -pbkdf2 -in "${input_file}" \
        -out "${output_file}" -pass file:"${ENCRYPTION_KEY_FILE}"

    rm -f "${input_file}"
    echo "${output_file}"
}

compress_file() {
    local input_file="$1"
    local output_file="${input_file}.gz"

    log "INFO" "Compressing ${input_file}"
    gzip -c "${input_file}" > "${output_file}"
    rm -f "${input_file}"

    echo "${output_file}"
}

# ============================================================================
# Backup Functions
# ============================================================================

backup_postgresql() {
    local backup_dir="$1"
    local backup_file="${backup_dir}/postgresql_backup.sql"

    log "INFO" "Starting PostgreSQL backup"

    PGPASSWORD="${POSTGRES_PASSWORD:-}" pg_dump \
        -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT}" \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        --format=custom \
        --file="${backup_file}" \
        --verbose 2>&1 | tee -a "${LOG_FILE}"

    if [[ $? -eq 0 ]]; then
        log "INFO" "PostgreSQL backup completed: ${backup_file}"

        # Get backup size
        local size=$(du -h "${backup_file}" | cut -f1)
        log "INFO" "PostgreSQL backup size: ${size}"

        # Apply compression
        if [[ "${ENABLE_COMPRESSION}" == "true" ]]; then
            backup_file=$(compress_file "${backup_file}")
        fi

        # Apply encryption
        if [[ "${ENABLE_ENCRYPTION}" == "true" ]]; then
            backup_file=$(encrypt_file "${backup_file}")
        fi

        echo "${backup_file}"
    else
        error_exit "PostgreSQL backup failed"
    fi
}

backup_redis() {
    local backup_dir="$1"
    local backup_file="${backup_dir}/redis_backup.rdb"

    log "INFO" "Starting Redis backup"

    # Trigger Redis SAVE
    redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" SAVE

    # Wait for save to complete
    sleep 2

    # Copy Redis dump file
    local redis_dump="/var/lib/redis/dump.rdb"
    if [[ -f "${redis_dump}" ]]; then
        cp "${redis_dump}" "${backup_file}"
        log "INFO" "Redis backup completed: ${backup_file}"

        local size=$(du -h "${backup_file}" | cut -f1)
        log "INFO" "Redis backup size: ${size}"

        # Apply compression
        if [[ "${ENABLE_COMPRESSION}" == "true" ]]; then
            backup_file=$(compress_file "${backup_file}")
        fi

        # Apply encryption
        if [[ "${ENABLE_ENCRYPTION}" == "true" ]]; then
            backup_file=$(encrypt_file "${backup_file}")
        fi

        echo "${backup_file}"
    else
        log "WARN" "Redis dump file not found at ${redis_dump}"
        return 1
    fi
}

backup_minio_data() {
    local backup_dir="$1"
    local backup_file="${backup_dir}/minio_data.tar"

    log "INFO" "Starting MinIO data backup"

    if [[ ! -d "${MINIO_DATA_DIR}" ]]; then
        log "WARN" "MinIO data directory not found: ${MINIO_DATA_DIR}"
        return 1
    fi

    # Create tar archive
    if [[ "${BACKUP_TYPE}" == "incremental" ]]; then
        local last_backup=$(find "${BACKUP_DIR}" -maxdepth 1 -type d -name "[0-9]*" | sort | tail -n 2 | head -n 1)
        if [[ -n "${last_backup}" ]]; then
            log "INFO" "Creating incremental backup (since ${last_backup})"
            tar --create --file="${backup_file}" \
                --listed-incremental="${backup_dir}/minio_data.snar" \
                --newer-mtime="$(stat -c %Y ${last_backup})" \
                -C "${MINIO_DATA_DIR}" . 2>&1 | tee -a "${LOG_FILE}"
        else
            log "WARN" "No previous backup found, performing full backup"
            tar -czf "${backup_file}" -C "${MINIO_DATA_DIR}" . 2>&1 | tee -a "${LOG_FILE}"
        fi
    else
        # Full backup
        tar -cf "${backup_file}" -C "${MINIO_DATA_DIR}" . 2>&1 | tee -a "${LOG_FILE}"
    fi

    if [[ $? -eq 0 ]]; then
        log "INFO" "MinIO data backup completed: ${backup_file}"

        local size=$(du -h "${backup_file}" | cut -f1)
        log "INFO" "MinIO data backup size: ${size}"

        # Apply compression
        if [[ "${ENABLE_COMPRESSION}" == "true" ]]; then
            backup_file=$(compress_file "${backup_file}")
        fi

        # Apply encryption
        if [[ "${ENABLE_ENCRYPTION}" == "true" ]]; then
            backup_file=$(encrypt_file "${backup_file}")
        fi

        echo "${backup_file}"
    else
        error_exit "MinIO data backup failed"
    fi
}

backup_configuration() {
    local backup_dir="$1"
    local backup_file="${backup_dir}/configuration.tar.gz"

    log "INFO" "Starting configuration backup"

    # Backup configuration files
    local config_items=(
        "/etc/minio"
        "/etc/prometheus"
        "/etc/grafana"
        "$(dirname ${SCRIPT_DIR})/configs"
        "$(dirname ${SCRIPT_DIR})/deployments"
    )

    local existing_items=()
    for item in "${config_items[@]}"; do
        if [[ -e "${item}" ]]; then
            existing_items+=("${item}")
        fi
    done

    if [[ ${#existing_items[@]} -eq 0 ]]; then
        log "WARN" "No configuration files found to backup"
        return 1
    fi

    tar -czf "${backup_file}" "${existing_items[@]}" 2>&1 | tee -a "${LOG_FILE}"

    if [[ $? -eq 0 ]]; then
        log "INFO" "Configuration backup completed: ${backup_file}"

        local size=$(du -h "${backup_file}" | cut -f1)
        log "INFO" "Configuration backup size: ${size}"

        # Apply encryption (already compressed)
        if [[ "${ENABLE_ENCRYPTION}" == "true" ]]; then
            backup_file=$(encrypt_file "${backup_file}")
        fi

        echo "${backup_file}"
    else
        error_exit "Configuration backup failed"
    fi
}

create_backup_manifest() {
    local backup_dir="$1"
    local manifest_file="${backup_dir}/manifest.txt"

    log "INFO" "Creating backup manifest"

    {
        echo "MinIO Enterprise Backup Manifest"
        echo "================================="
        echo "Backup Type: ${BACKUP_TYPE}"
        echo "Backup Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Backup Directory: ${backup_dir}"
        echo ""
        echo "Files:"
        find "${backup_dir}" -type f -exec ls -lh {} \; | awk '{print $9, $5}'
        echo ""
        echo "Total Size: $(du -sh ${backup_dir} | cut -f1)"
        echo ""
        echo "Checksums:"
        find "${backup_dir}" -type f ! -name "manifest.txt" -exec sha256sum {} \;
    } > "${manifest_file}"

    log "INFO" "Manifest created: ${manifest_file}"
}

verify_backup() {
    local backup_dir="$1"

    log "INFO" "Verifying backup integrity"

    local manifest_file="${backup_dir}/manifest.txt"
    if [[ ! -f "${manifest_file}" ]]; then
        log "WARN" "Manifest file not found, skipping verification"
        return 1
    fi

    # Verify checksums
    local checksum_section=$(sed -n '/^Checksums:/,/^$/p' "${manifest_file}" | tail -n +2)

    while IFS= read -r line; do
        if [[ -n "${line}" ]]; then
            local expected_sum=$(echo "${line}" | awk '{print $1}')
            local file_path=$(echo "${line}" | awk '{print $2}')

            if [[ -f "${file_path}" ]]; then
                local actual_sum=$(sha256sum "${file_path}" | awk '{print $1}')
                if [[ "${expected_sum}" == "${actual_sum}" ]]; then
                    log "INFO" "Checksum verified: $(basename ${file_path})"
                else
                    log "ERROR" "Checksum mismatch: $(basename ${file_path})"
                    return 1
                fi
            fi
        fi
    done <<< "${checksum_section}"

    log "INFO" "Backup verification completed successfully"
    return 0
}

sync_to_s3() {
    local backup_dir="$1"

    if [[ "${S3_ENABLED}" != "true" ]]; then
        return 0
    fi

    log "INFO" "Syncing backup to S3: ${S3_BUCKET}"

    if ! command -v aws &> /dev/null; then
        log "WARN" "AWS CLI not found, skipping S3 sync"
        return 1
    fi

    local s3_path="s3://${S3_BUCKET}/minio-backups/$(basename ${backup_dir})"

    if [[ -n "${S3_ENDPOINT}" ]]; then
        aws s3 sync "${backup_dir}" "${s3_path}" --endpoint-url "${S3_ENDPOINT}" 2>&1 | tee -a "${LOG_FILE}"
    else
        aws s3 sync "${backup_dir}" "${s3_path}" 2>&1 | tee -a "${LOG_FILE}"
    fi

    if [[ $? -eq 0 ]]; then
        log "INFO" "S3 sync completed: ${s3_path}"
    else
        log "ERROR" "S3 sync failed"
        return 1
    fi
}

cleanup_old_backups() {
    log "INFO" "Cleaning up backups older than ${RETENTION_DAYS} days"

    find "${BACKUP_DIR}" -maxdepth 1 -type d -name "[0-9]*" -mtime +${RETENTION_DAYS} -exec rm -rf {} \;

    log "INFO" "Cleanup completed"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log "INFO" "=========================================="
    log "INFO" "MinIO Enterprise Backup Started"
    log "INFO" "Backup Type: ${BACKUP_TYPE}"
    log "INFO" "=========================================="

    # Pre-flight checks
    check_dependencies

    # Generate encryption key if needed
    if [[ "${ENABLE_ENCRYPTION}" == "true" ]]; then
        generate_encryption_key
    fi

    # Create backup directory
    local backup_dir=$(create_backup_dir)
    log "INFO" "Backup directory: ${backup_dir}"

    # Perform backups
    local backup_files=()

    # PostgreSQL backup
    if backup_file=$(backup_postgresql "${backup_dir}"); then
        backup_files+=("${backup_file}")
    fi

    # Redis backup
    if backup_file=$(backup_redis "${backup_dir}"); then
        backup_files+=("${backup_file}")
    fi

    # MinIO data backup
    if backup_file=$(backup_minio_data "${backup_dir}"); then
        backup_files+=("${backup_file}")
    fi

    # Configuration backup
    if backup_file=$(backup_configuration "${backup_dir}"); then
        backup_files+=("${backup_file}")
    fi

    # Create manifest
    create_backup_manifest "${backup_dir}"

    # Verify backup
    verify_backup "${backup_dir}"

    # Sync to S3 if enabled
    sync_to_s3 "${backup_dir}"

    # Cleanup old backups
    cleanup_old_backups

    log "INFO" "=========================================="
    log "INFO" "Backup completed successfully"
    log "INFO" "Backup location: ${backup_dir}"
    log "INFO" "Total size: $(du -sh ${backup_dir} | cut -f1)"
    log "INFO" "=========================================="

    exit 0
}

# Run main function
main "$@"
