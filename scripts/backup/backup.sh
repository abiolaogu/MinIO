#!/bin/bash
# MinIO Enterprise Backup Script
# Version: 1.0.0
# Description: Automated backup solution for MinIO, PostgreSQL, Redis, and configuration files
# Usage: ./backup.sh [full|incremental] [--config=/path/to/config]

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration
DEFAULT_CONFIG="${SCRIPT_DIR}/backup.conf"
CONFIG_FILE="${DEFAULT_CONFIG}"

# Parse command line arguments
BACKUP_TYPE="${1:-full}"
for arg in "$@"; do
    case $arg in
        --config=*)
            CONFIG_FILE="${arg#*=}"
            shift
            ;;
    esac
done

# Load configuration
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
else
    echo "Error: Configuration file not found: ${CONFIG_FILE}"
    echo "Please create a configuration file or use --config=/path/to/config"
    exit 1
fi

# Required configuration variables (with defaults)
BACKUP_DIR="${BACKUP_DIR:-/var/backups/minio}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
BACKUP_COMPRESSION="${BACKUP_COMPRESSION:-gzip}"
BACKUP_ENCRYPTION_ENABLED="${BACKUP_ENCRYPTION_ENABLED:-false}"
BACKUP_ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-minio}"
POSTGRES_DB="${POSTGRES_DB:-minio}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
MINIO_DATA_DIR="${MINIO_DATA_DIR:-/var/lib/minio}"
MINIO_CONFIG_DIR="${MINIO_CONFIG_DIR:-/etc/minio}"
S3_BACKUP_ENABLED="${S3_BACKUP_ENABLED:-false}"
S3_BUCKET="${S3_BUCKET:-}"
S3_ENDPOINT="${S3_ENDPOINT:-}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-}"
S3_SECRET_KEY="${S3_SECRET_KEY:-}"
NOTIFICATION_ENABLED="${NOTIFICATION_ENABLED:-false}"
NOTIFICATION_WEBHOOK="${NOTIFICATION_WEBHOOK:-}"
LOG_FILE="${LOG_FILE:-${BACKUP_DIR}/backup.log}"

# Timestamp for backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="minio_backup_${BACKUP_TYPE}_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Error handler
error_exit() {
    log "ERROR" "$1"
    send_notification "FAILURE" "Backup failed: $1"
    exit 1
}

# Success handler
success_exit() {
    log "INFO" "$1"
    send_notification "SUCCESS" "$1"
    exit 0
}

# Send notification
send_notification() {
    local status="$1"
    local message="$2"

    if [[ "${NOTIFICATION_ENABLED}" == "true" ]] && [[ -n "${NOTIFICATION_WEBHOOK}" ]]; then
        local payload=$(cat <<EOF
{
  "status": "${status}",
  "backup_type": "${BACKUP_TYPE}",
  "timestamp": "${TIMESTAMP}",
  "backup_name": "${BACKUP_NAME}",
  "message": "${message}"
}
EOF
)
        curl -X POST "${NOTIFICATION_WEBHOOK}" \
            -H "Content-Type: application/json" \
            -d "${payload}" \
            --silent --show-error || log "WARN" "Failed to send notification"
    fi
}

# Initialize backup directory
initialize_backup() {
    log "INFO" "Initializing backup: ${BACKUP_NAME}"
    log "INFO" "Backup type: ${BACKUP_TYPE}"
    log "INFO" "Backup path: ${BACKUP_PATH}"

    mkdir -p "${BACKUP_PATH}"
    mkdir -p "${BACKUP_PATH}/postgresql"
    mkdir -p "${BACKUP_PATH}/redis"
    mkdir -p "${BACKUP_PATH}/minio-data"
    mkdir -p "${BACKUP_PATH}/config"
    mkdir -p "${BACKUP_PATH}/metadata"

    # Create metadata file
    cat > "${BACKUP_PATH}/metadata/backup.info" <<EOF
backup_name=${BACKUP_NAME}
backup_type=${BACKUP_TYPE}
timestamp=${TIMESTAMP}
date=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
hostname=$(hostname)
script_version=1.0.0
EOF
}

# Backup PostgreSQL database
backup_postgresql() {
    log "INFO" "Starting PostgreSQL backup..."

    local pg_dump_file="${BACKUP_PATH}/postgresql/dump.sql"

    # Set password environment variable if provided
    if [[ -n "${POSTGRES_PASSWORD}" ]]; then
        export PGPASSWORD="${POSTGRES_PASSWORD}"
    fi

    # Dump database
    if pg_dump -h "${POSTGRES_HOST}" \
                -p "${POSTGRES_PORT}" \
                -U "${POSTGRES_USER}" \
                -d "${POSTGRES_DB}" \
                -F plain \
                --no-owner \
                --no-privileges \
                -f "${pg_dump_file}"; then
        log "INFO" "PostgreSQL backup completed: ${pg_dump_file}"

        # Compress if enabled
        if [[ "${BACKUP_COMPRESSION}" == "gzip" ]]; then
            gzip "${pg_dump_file}"
            log "INFO" "PostgreSQL dump compressed"
        fi
    else
        error_exit "PostgreSQL backup failed"
    fi

    # Unset password
    unset PGPASSWORD
}

# Backup Redis data
backup_redis() {
    log "INFO" "Starting Redis backup..."

    local redis_dump="${BACKUP_PATH}/redis/dump.rdb"

    # Trigger Redis save
    if [[ -n "${REDIS_PASSWORD}" ]]; then
        redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" -a "${REDIS_PASSWORD}" --no-auth-warning SAVE || error_exit "Redis SAVE command failed"
    else
        redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" SAVE || error_exit "Redis SAVE command failed"
    fi

    log "INFO" "Redis save triggered, waiting for completion..."
    sleep 2

    # Copy Redis dump file
    # Note: This assumes Redis is configured to save to /var/lib/redis/dump.rdb
    # Adjust path based on your Redis configuration
    local redis_data_dir="${REDIS_DATA_DIR:-/var/lib/redis}"
    if [[ -f "${redis_data_dir}/dump.rdb" ]]; then
        cp "${redis_data_dir}/dump.rdb" "${redis_dump}"
        log "INFO" "Redis backup completed: ${redis_dump}"

        # Compress if enabled
        if [[ "${BACKUP_COMPRESSION}" == "gzip" ]]; then
            gzip "${redis_dump}"
            log "INFO" "Redis dump compressed"
        fi
    else
        log "WARN" "Redis dump file not found at ${redis_data_dir}/dump.rdb, skipping Redis backup"
    fi
}

# Backup MinIO data
backup_minio_data() {
    log "INFO" "Starting MinIO data backup (${BACKUP_TYPE})..."

    if [[ ! -d "${MINIO_DATA_DIR}" ]]; then
        log "WARN" "MinIO data directory not found: ${MINIO_DATA_DIR}, skipping data backup"
        return
    fi

    local rsync_opts="-av --delete"

    if [[ "${BACKUP_TYPE}" == "incremental" ]]; then
        # Find the latest full backup
        local latest_full=$(find "${BACKUP_DIR}" -maxdepth 1 -type d -name "minio_backup_full_*" | sort -r | head -n 1)

        if [[ -n "${latest_full}" ]]; then
            log "INFO" "Incremental backup based on: ${latest_full}"
            rsync_opts="${rsync_opts} --link-dest=${latest_full}/minio-data"
        else
            log "WARN" "No full backup found for incremental, performing full backup instead"
            BACKUP_TYPE="full"
        fi
    fi

    # Perform rsync backup
    if rsync ${rsync_opts} "${MINIO_DATA_DIR}/" "${BACKUP_PATH}/minio-data/"; then
        log "INFO" "MinIO data backup completed"

        # Calculate backup size
        local backup_size=$(du -sh "${BACKUP_PATH}/minio-data" | cut -f1)
        log "INFO" "MinIO data backup size: ${backup_size}"
    else
        error_exit "MinIO data backup failed"
    fi
}

# Backup configuration files
backup_config() {
    log "INFO" "Starting configuration backup..."

    # Backup MinIO configuration
    if [[ -d "${MINIO_CONFIG_DIR}" ]]; then
        cp -r "${MINIO_CONFIG_DIR}" "${BACKUP_PATH}/config/minio"
        log "INFO" "MinIO configuration backed up"
    fi

    # Backup Docker Compose files
    local compose_dir="$(dirname "$(dirname "${SCRIPT_DIR}")")/deployments/docker"
    if [[ -d "${compose_dir}" ]]; then
        cp -r "${compose_dir}" "${BACKUP_PATH}/config/docker"
        log "INFO" "Docker configuration backed up"
    fi

    # Backup environment files (excluding sensitive data in plaintext)
    local config_base="$(dirname "$(dirname "${SCRIPT_DIR}")")/configs"
    if [[ -d "${config_base}" ]]; then
        cp -r "${config_base}" "${BACKUP_PATH}/config/configs"
        log "INFO" "Application configuration backed up"
    fi

    log "INFO" "Configuration backup completed"
}

# Encrypt backup
encrypt_backup() {
    if [[ "${BACKUP_ENCRYPTION_ENABLED}" == "true" ]]; then
        if [[ -z "${BACKUP_ENCRYPTION_KEY}" ]]; then
            error_exit "Encryption enabled but no encryption key provided"
        fi

        log "INFO" "Encrypting backup..."

        # Create encrypted tarball
        local archive="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz.enc"
        tar -czf - -C "${BACKUP_DIR}" "${BACKUP_NAME}" | \
            openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:"${BACKUP_ENCRYPTION_KEY}" -out "${archive}"

        if [[ $? -eq 0 ]]; then
            log "INFO" "Backup encrypted: ${archive}"
            # Remove unencrypted backup
            rm -rf "${BACKUP_PATH}"
            BACKUP_PATH="${archive}"
        else
            error_exit "Encryption failed"
        fi
    fi
}

# Upload to S3
upload_to_s3() {
    if [[ "${S3_BACKUP_ENABLED}" == "true" ]]; then
        if [[ -z "${S3_BUCKET}" ]] || [[ -z "${S3_ENDPOINT}" ]]; then
            log "WARN" "S3 backup enabled but bucket or endpoint not configured"
            return
        fi

        log "INFO" "Uploading backup to S3..."

        # Use AWS CLI or mc (MinIO client)
        if command -v mc &> /dev/null; then
            # Configure mc alias
            mc alias set backup "${S3_ENDPOINT}" "${S3_ACCESS_KEY}" "${S3_SECRET_KEY}" --api S3v4

            # Upload backup
            if [[ -d "${BACKUP_PATH}" ]]; then
                mc cp -r "${BACKUP_PATH}" "backup/${S3_BUCKET}/${BACKUP_NAME}/"
            else
                mc cp "${BACKUP_PATH}" "backup/${S3_BUCKET}/"
            fi

            log "INFO" "Backup uploaded to S3: s3://${S3_BUCKET}/${BACKUP_NAME}"
        else
            log "WARN" "MinIO client (mc) not found, skipping S3 upload"
        fi
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    log "INFO" "Cleaning up old backups (retention: ${BACKUP_RETENTION_DAYS} days)..."

    # Find and delete backups older than retention period
    find "${BACKUP_DIR}" -maxdepth 1 -type d -name "minio_backup_*" -mtime +${BACKUP_RETENTION_DAYS} -exec rm -rf {} \;
    find "${BACKUP_DIR}" -maxdepth 1 -type f -name "minio_backup_*.tar.gz*" -mtime +${BACKUP_RETENTION_DAYS} -exec rm -f {} \;

    log "INFO" "Old backups cleaned up"
}

# Verify backup integrity
verify_backup() {
    log "INFO" "Verifying backup integrity..."

    # Check if backup path exists
    if [[ ! -e "${BACKUP_PATH}" ]]; then
        error_exit "Backup path does not exist: ${BACKUP_PATH}"
    fi

    # Verify PostgreSQL dump
    if [[ -f "${BACKUP_PATH}/postgresql/dump.sql" ]] || [[ -f "${BACKUP_PATH}/postgresql/dump.sql.gz" ]]; then
        log "INFO" "PostgreSQL backup verified"
    else
        log "WARN" "PostgreSQL backup file not found"
    fi

    # Verify MinIO data
    if [[ -d "${BACKUP_PATH}/minio-data" ]]; then
        local file_count=$(find "${BACKUP_PATH}/minio-data" -type f | wc -l)
        log "INFO" "MinIO data backup verified (${file_count} files)"
    else
        log "WARN" "MinIO data backup not found"
    fi

    # Calculate total backup size
    local total_size=$(du -sh "${BACKUP_PATH}" | cut -f1)
    log "INFO" "Total backup size: ${total_size}"

    # Update metadata
    cat >> "${BACKUP_PATH}/metadata/backup.info" <<EOF
total_size=${total_size}
verification_status=success
verification_date=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
EOF

    log "INFO" "Backup verification completed"
}

# Main backup workflow
main() {
    log "INFO" "=== MinIO Enterprise Backup Started ==="
    log "INFO" "Backup type: ${BACKUP_TYPE}"

    # Validate backup type
    if [[ "${BACKUP_TYPE}" != "full" ]] && [[ "${BACKUP_TYPE}" != "incremental" ]]; then
        error_exit "Invalid backup type: ${BACKUP_TYPE}. Must be 'full' or 'incremental'"
    fi

    # Check dependencies
    if ! command -v pg_dump &> /dev/null; then
        error_exit "pg_dump not found. Please install PostgreSQL client tools."
    fi

    if ! command -v redis-cli &> /dev/null; then
        log "WARN" "redis-cli not found. Redis backup will be skipped."
    fi

    if ! command -v rsync &> /dev/null; then
        error_exit "rsync not found. Please install rsync."
    fi

    # Create backup directory if it doesn't exist
    mkdir -p "${BACKUP_DIR}"

    # Start backup process
    initialize_backup
    backup_postgresql
    backup_redis
    backup_minio_data
    backup_config
    verify_backup
    encrypt_backup
    upload_to_s3
    cleanup_old_backups

    log "INFO" "=== MinIO Enterprise Backup Completed Successfully ==="
    log "INFO" "Backup location: ${BACKUP_PATH}"
    success_exit "Backup completed successfully: ${BACKUP_NAME}"
}

# Run main function
main
