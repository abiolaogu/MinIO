#!/bin/bash
# MinIO Enterprise Restore Script
# Version: 1.0.0
# Description: Automated restore solution for MinIO backups
# Usage: ./restore.sh <backup_name_or_path> [--verify-only] [--config=/path/to/config]

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration
DEFAULT_CONFIG="${SCRIPT_DIR}/../backup/backup.conf"
CONFIG_FILE="${DEFAULT_CONFIG}"

# Parse command line arguments
BACKUP_TO_RESTORE="${1:-}"
VERIFY_ONLY=false

if [[ -z "${BACKUP_TO_RESTORE}" ]]; then
    echo "Usage: $0 <backup_name_or_path> [--verify-only] [--config=/path/to/config]"
    echo ""
    echo "Examples:"
    echo "  $0 minio_backup_full_20260209_143000"
    echo "  $0 /var/backups/minio/minio_backup_full_20260209_143000"
    echo "  $0 minio_backup_full_20260209_143000 --verify-only"
    exit 1
fi

shift

for arg in "$@"; do
    case $arg in
        --verify-only)
            VERIFY_ONLY=true
            shift
            ;;
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
NOTIFICATION_ENABLED="${NOTIFICATION_ENABLED:-false}"
NOTIFICATION_WEBHOOK="${NOTIFICATION_WEBHOOK:-}"
LOG_FILE="${LOG_FILE:-${BACKUP_DIR}/restore.log}"
RESTORE_TEMP_DIR="${RESTORE_TEMP_DIR:-/tmp/minio_restore}"

# Resolve backup path
if [[ -d "${BACKUP_TO_RESTORE}" ]]; then
    BACKUP_PATH="${BACKUP_TO_RESTORE}"
elif [[ -d "${BACKUP_DIR}/${BACKUP_TO_RESTORE}" ]]; then
    BACKUP_PATH="${BACKUP_DIR}/${BACKUP_TO_RESTORE}"
elif [[ -f "${BACKUP_TO_RESTORE}" ]]; then
    BACKUP_PATH="${BACKUP_TO_RESTORE}"
elif [[ -f "${BACKUP_DIR}/${BACKUP_TO_RESTORE}.tar.gz.enc" ]]; then
    BACKUP_PATH="${BACKUP_DIR}/${BACKUP_TO_RESTORE}.tar.gz.enc"
else
    echo "Error: Backup not found: ${BACKUP_TO_RESTORE}"
    exit 1
fi

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
    send_notification "FAILURE" "Restore failed: $1"
    cleanup_temp
    exit 1
}

# Success handler
success_exit() {
    log "INFO" "$1"
    send_notification "SUCCESS" "$1"
    cleanup_temp
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
  "operation": "restore",
  "backup_path": "${BACKUP_PATH}",
  "timestamp": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')",
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

# Cleanup temporary files
cleanup_temp() {
    if [[ -d "${RESTORE_TEMP_DIR}" ]]; then
        log "INFO" "Cleaning up temporary files..."
        rm -rf "${RESTORE_TEMP_DIR}"
    fi
}

# Decrypt backup if encrypted
decrypt_backup() {
    if [[ -f "${BACKUP_PATH}" ]] && [[ "${BACKUP_PATH}" == *.enc ]]; then
        if [[ "${BACKUP_ENCRYPTION_ENABLED}" != "true" ]] || [[ -z "${BACKUP_ENCRYPTION_KEY}" ]]; then
            error_exit "Backup is encrypted but no decryption key provided"
        fi

        log "INFO" "Decrypting backup..."

        mkdir -p "${RESTORE_TEMP_DIR}"
        local decrypted="${RESTORE_TEMP_DIR}/backup.tar.gz"

        openssl enc -aes-256-cbc -d -pbkdf2 -pass pass:"${BACKUP_ENCRYPTION_KEY}" \
            -in "${BACKUP_PATH}" -out "${decrypted}"

        if [[ $? -eq 0 ]]; then
            log "INFO" "Backup decrypted successfully"

            # Extract archive
            tar -xzf "${decrypted}" -C "${RESTORE_TEMP_DIR}"

            # Find extracted backup directory
            local backup_name=$(basename "${BACKUP_PATH}" .tar.gz.enc)
            BACKUP_PATH="${RESTORE_TEMP_DIR}/${backup_name}"

            if [[ ! -d "${BACKUP_PATH}" ]]; then
                error_exit "Extracted backup directory not found: ${BACKUP_PATH}"
            fi
        else
            error_exit "Decryption failed"
        fi
    fi
}

# Verify backup integrity
verify_backup() {
    log "INFO" "Verifying backup integrity..."

    # Check backup metadata
    local metadata_file="${BACKUP_PATH}/metadata/backup.info"
    if [[ ! -f "${metadata_file}" ]]; then
        error_exit "Backup metadata not found: ${metadata_file}"
    fi

    # Read and display backup info
    log "INFO" "Backup Information:"
    while IFS='=' read -r key value; do
        log "INFO" "  ${key}: ${value}"
    done < "${metadata_file}"

    # Verify PostgreSQL dump
    local pg_dump_sql="${BACKUP_PATH}/postgresql/dump.sql"
    local pg_dump_gz="${BACKUP_PATH}/postgresql/dump.sql.gz"

    if [[ -f "${pg_dump_sql}" ]]; then
        log "INFO" "PostgreSQL dump found: ${pg_dump_sql}"
    elif [[ -f "${pg_dump_gz}" ]]; then
        log "INFO" "PostgreSQL dump found (compressed): ${pg_dump_gz}"
    else
        log "WARN" "PostgreSQL dump not found"
    fi

    # Verify Redis dump
    local redis_dump="${BACKUP_PATH}/redis/dump.rdb"
    local redis_dump_gz="${BACKUP_PATH}/redis/dump.rdb.gz"

    if [[ -f "${redis_dump}" ]]; then
        log "INFO" "Redis dump found: ${redis_dump}"
    elif [[ -f "${redis_dump_gz}" ]]; then
        log "INFO" "Redis dump found (compressed): ${redis_dump_gz}"
    else
        log "WARN" "Redis dump not found"
    fi

    # Verify MinIO data
    if [[ -d "${BACKUP_PATH}/minio-data" ]]; then
        local file_count=$(find "${BACKUP_PATH}/minio-data" -type f 2>/dev/null | wc -l)
        log "INFO" "MinIO data found: ${file_count} files"
    else
        log "WARN" "MinIO data directory not found"
    fi

    # Verify configuration
    if [[ -d "${BACKUP_PATH}/config" ]]; then
        log "INFO" "Configuration files found"
    else
        log "WARN" "Configuration directory not found"
    fi

    log "INFO" "Backup verification completed"
}

# Create pre-restore backup
create_pre_restore_backup() {
    log "INFO" "Creating pre-restore backup for safety..."

    local pre_restore_dir="${BACKUP_DIR}/pre_restore_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${pre_restore_dir}"

    # Backup current PostgreSQL database
    if command -v pg_dump &> /dev/null; then
        if [[ -n "${POSTGRES_PASSWORD}" ]]; then
            export PGPASSWORD="${POSTGRES_PASSWORD}"
        fi

        pg_dump -h "${POSTGRES_HOST}" \
                -p "${POSTGRES_PORT}" \
                -U "${POSTGRES_USER}" \
                -d "${POSTGRES_DB}" \
                -F plain \
                -f "${pre_restore_dir}/postgresql_pre_restore.sql" 2>/dev/null || log "WARN" "Could not backup current PostgreSQL database"

        unset PGPASSWORD
    fi

    # Backup current MinIO data
    if [[ -d "${MINIO_DATA_DIR}" ]]; then
        rsync -a "${MINIO_DATA_DIR}/" "${pre_restore_dir}/minio-data/" 2>/dev/null || log "WARN" "Could not backup current MinIO data"
    fi

    log "INFO" "Pre-restore backup created: ${pre_restore_dir}"
    echo "${pre_restore_dir}" > "${RESTORE_TEMP_DIR}/pre_restore_path"
}

# Restore PostgreSQL database
restore_postgresql() {
    log "INFO" "Starting PostgreSQL restore..."

    local pg_dump_sql="${BACKUP_PATH}/postgresql/dump.sql"
    local pg_dump_gz="${BACKUP_PATH}/postgresql/dump.sql.gz"

    # Decompress if needed
    if [[ ! -f "${pg_dump_sql}" ]] && [[ -f "${pg_dump_gz}" ]]; then
        log "INFO" "Decompressing PostgreSQL dump..."
        gunzip -c "${pg_dump_gz}" > "${RESTORE_TEMP_DIR}/dump.sql"
        pg_dump_sql="${RESTORE_TEMP_DIR}/dump.sql"
    fi

    if [[ ! -f "${pg_dump_sql}" ]]; then
        log "WARN" "PostgreSQL dump not found, skipping database restore"
        return
    fi

    # Set password environment variable if provided
    if [[ -n "${POSTGRES_PASSWORD}" ]]; then
        export PGPASSWORD="${POSTGRES_PASSWORD}"
    fi

    # Drop existing database and recreate (WARNING: This will delete all data!)
    log "WARN" "Dropping existing database: ${POSTGRES_DB}"
    psql -h "${POSTGRES_HOST}" \
         -p "${POSTGRES_PORT}" \
         -U "${POSTGRES_USER}" \
         -d postgres \
         -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};" || error_exit "Failed to drop database"

    psql -h "${POSTGRES_HOST}" \
         -p "${POSTGRES_PORT}" \
         -U "${POSTGRES_USER}" \
         -d postgres \
         -c "CREATE DATABASE ${POSTGRES_DB};" || error_exit "Failed to create database"

    # Restore database
    log "INFO" "Restoring PostgreSQL database..."
    if psql -h "${POSTGRES_HOST}" \
            -p "${POSTGRES_PORT}" \
            -U "${POSTGRES_USER}" \
            -d "${POSTGRES_DB}" \
            -f "${pg_dump_sql}"; then
        log "INFO" "PostgreSQL restore completed successfully"
    else
        error_exit "PostgreSQL restore failed"
    fi

    # Unset password
    unset PGPASSWORD
}

# Restore Redis data
restore_redis() {
    log "INFO" "Starting Redis restore..."

    local redis_dump="${BACKUP_PATH}/redis/dump.rdb"
    local redis_dump_gz="${BACKUP_PATH}/redis/dump.rdb.gz"

    # Decompress if needed
    if [[ ! -f "${redis_dump}" ]] && [[ -f "${redis_dump_gz}" ]]; then
        log "INFO" "Decompressing Redis dump..."
        gunzip -c "${redis_dump_gz}" > "${RESTORE_TEMP_DIR}/dump.rdb"
        redis_dump="${RESTORE_TEMP_DIR}/dump.rdb"
    fi

    if [[ ! -f "${redis_dump}" ]]; then
        log "WARN" "Redis dump not found, skipping Redis restore"
        return
    fi

    # Stop Redis (requires appropriate permissions)
    log "WARN" "Redis restore requires stopping Redis service"
    log "INFO" "Please stop Redis manually and press Enter to continue..."
    read -r

    # Copy dump file to Redis data directory
    local redis_data_dir="${REDIS_DATA_DIR:-/var/lib/redis}"
    cp "${redis_dump}" "${redis_data_dir}/dump.rdb" || error_exit "Failed to copy Redis dump"

    log "INFO" "Redis dump file copied. Please start Redis service and press Enter to continue..."
    read -r

    log "INFO" "Redis restore completed"
}

# Restore MinIO data
restore_minio_data() {
    log "INFO" "Starting MinIO data restore..."

    if [[ ! -d "${BACKUP_PATH}/minio-data" ]]; then
        log "WARN" "MinIO data not found in backup, skipping data restore"
        return
    fi

    # Create MinIO data directory if it doesn't exist
    mkdir -p "${MINIO_DATA_DIR}"

    # Restore data using rsync
    log "WARN" "Restoring MinIO data (this will overwrite existing data)..."
    if rsync -av --delete "${BACKUP_PATH}/minio-data/" "${MINIO_DATA_DIR}/"; then
        log "INFO" "MinIO data restore completed"

        # Set appropriate permissions
        chown -R 1000:1000 "${MINIO_DATA_DIR}" 2>/dev/null || log "WARN" "Could not set ownership (may require root)"
    else
        error_exit "MinIO data restore failed"
    fi
}

# Restore configuration files
restore_config() {
    log "INFO" "Starting configuration restore..."

    if [[ ! -d "${BACKUP_PATH}/config" ]]; then
        log "WARN" "Configuration not found in backup, skipping config restore"
        return
    fi

    # Restore MinIO configuration
    if [[ -d "${BACKUP_PATH}/config/minio" ]]; then
        mkdir -p "${MINIO_CONFIG_DIR}"
        cp -r "${BACKUP_PATH}/config/minio/"* "${MINIO_CONFIG_DIR}/" || log "WARN" "Could not restore MinIO config"
        log "INFO" "MinIO configuration restored"
    fi

    # Restore Docker configuration (to a restore directory, not overwriting production)
    if [[ -d "${BACKUP_PATH}/config/docker" ]]; then
        local restore_config_dir="${RESTORE_TEMP_DIR}/restored_configs"
        mkdir -p "${restore_config_dir}"
        cp -r "${BACKUP_PATH}/config/docker" "${restore_config_dir}/"
        log "INFO" "Docker configuration extracted to: ${restore_config_dir}/docker"
    fi

    # Restore application configuration
    if [[ -d "${BACKUP_PATH}/config/configs" ]]; then
        local restore_config_dir="${RESTORE_TEMP_DIR}/restored_configs"
        mkdir -p "${restore_config_dir}"
        cp -r "${BACKUP_PATH}/config/configs" "${restore_config_dir}/"
        log "INFO" "Application configuration extracted to: ${restore_config_dir}/configs"
    fi

    log "INFO" "Configuration restore completed"
}

# Verify restored data
verify_restored_data() {
    log "INFO" "Verifying restored data..."

    # Verify PostgreSQL
    if [[ -n "${POSTGRES_PASSWORD}" ]]; then
        export PGPASSWORD="${POSTGRES_PASSWORD}"
    fi

    local table_count=$(psql -h "${POSTGRES_HOST}" \
                             -p "${POSTGRES_PORT}" \
                             -U "${POSTGRES_USER}" \
                             -d "${POSTGRES_DB}" \
                             -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | xargs)

    if [[ -n "${table_count}" ]] && [[ "${table_count}" -gt 0 ]]; then
        log "INFO" "PostgreSQL verified: ${table_count} tables found"
    else
        log "WARN" "PostgreSQL verification: No tables found or verification failed"
    fi

    unset PGPASSWORD

    # Verify MinIO data
    if [[ -d "${MINIO_DATA_DIR}" ]]; then
        local file_count=$(find "${MINIO_DATA_DIR}" -type f 2>/dev/null | wc -l)
        log "INFO" "MinIO data verified: ${file_count} files found"
    fi

    log "INFO" "Data verification completed"
}

# Rollback restore
rollback_restore() {
    log "WARN" "Rolling back restore..."

    if [[ ! -f "${RESTORE_TEMP_DIR}/pre_restore_path" ]]; then
        log "ERROR" "Cannot rollback: Pre-restore backup path not found"
        return
    fi

    local pre_restore_dir=$(cat "${RESTORE_TEMP_DIR}/pre_restore_path")

    if [[ ! -d "${pre_restore_dir}" ]]; then
        log "ERROR" "Cannot rollback: Pre-restore backup not found at ${pre_restore_dir}"
        return
    fi

    # Rollback PostgreSQL
    if [[ -f "${pre_restore_dir}/postgresql_pre_restore.sql" ]]; then
        log "INFO" "Rolling back PostgreSQL..."

        if [[ -n "${POSTGRES_PASSWORD}" ]]; then
            export PGPASSWORD="${POSTGRES_PASSWORD}"
        fi

        psql -h "${POSTGRES_HOST}" \
             -p "${POSTGRES_PORT}" \
             -U "${POSTGRES_USER}" \
             -d postgres \
             -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};" 2>/dev/null

        psql -h "${POSTGRES_HOST}" \
             -p "${POSTGRES_PORT}" \
             -U "${POSTGRES_USER}" \
             -d postgres \
             -c "CREATE DATABASE ${POSTGRES_DB};" 2>/dev/null

        psql -h "${POSTGRES_HOST}" \
             -p "${POSTGRES_PORT}" \
             -U "${POSTGRES_USER}" \
             -d "${POSTGRES_DB}" \
             -f "${pre_restore_dir}/postgresql_pre_restore.sql" 2>/dev/null

        unset PGPASSWORD
        log "INFO" "PostgreSQL rolled back"
    fi

    # Rollback MinIO data
    if [[ -d "${pre_restore_dir}/minio-data" ]]; then
        log "INFO" "Rolling back MinIO data..."
        rsync -av --delete "${pre_restore_dir}/minio-data/" "${MINIO_DATA_DIR}/" 2>/dev/null
        log "INFO" "MinIO data rolled back"
    fi

    log "INFO" "Rollback completed"
}

# Main restore workflow
main() {
    log "INFO" "=== MinIO Enterprise Restore Started ==="
    log "INFO" "Backup path: ${BACKUP_PATH}"
    log "INFO" "Verify only: ${VERIFY_ONLY}"

    # Check dependencies
    if ! command -v psql &> /dev/null; then
        error_exit "psql not found. Please install PostgreSQL client tools."
    fi

    if ! command -v rsync &> /dev/null; then
        error_exit "rsync not found. Please install rsync."
    fi

    # Create temporary directory
    mkdir -p "${RESTORE_TEMP_DIR}"

    # Decrypt if needed
    decrypt_backup

    # Verify backup
    verify_backup

    if [[ "${VERIFY_ONLY}" == "true" ]]; then
        log "INFO" "Verify-only mode: Skipping actual restore"
        success_exit "Backup verification completed"
    fi

    # Confirmation prompt
    echo ""
    echo "WARNING: This will overwrite existing data!"
    echo "Backup to restore: ${BACKUP_PATH}"
    echo "Target PostgreSQL: ${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
    echo "Target MinIO data: ${MINIO_DATA_DIR}"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "INFO" "Restore cancelled by user"
        cleanup_temp
        exit 0
    fi

    # Create pre-restore backup
    create_pre_restore_backup

    # Perform restore
    log "INFO" "Starting restore process..."

    # Trap errors for rollback
    trap 'log "ERROR" "Restore failed, starting rollback..."; rollback_restore; exit 1' ERR

    restore_postgresql
    restore_redis
    restore_minio_data
    restore_config
    verify_restored_data

    # Remove error trap
    trap - ERR

    log "INFO" "=== MinIO Enterprise Restore Completed Successfully ==="
    success_exit "Restore completed successfully from: ${BACKUP_PATH}"
}

# Run main function
main
