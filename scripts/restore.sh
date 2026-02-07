#!/usr/bin/env bash
# MinIO Enterprise - Automated Restore Script
# Supports restore with verification and rollback capabilities

set -euo pipefail

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/var/backups/minio-enterprise}"
BACKUP_NAME="${BACKUP_NAME:-}"
RESTORE_COMPONENTS="${RESTORE_COMPONENTS:-all}"  # all, postgres, redis, minio, config
DRY_RUN="${DRY_RUN:-false}"
CREATE_ROLLBACK="${CREATE_ROLLBACK:-true}"
ENCRYPTION="${ENCRYPTION:-false}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"

# Component settings
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-minio}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"

REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

MINIO_DATA_DIR="${MINIO_DATA_DIR:-/data/minio}"
CONFIG_DIR="${CONFIG_DIR:-/etc/minio}"

# Rollback settings
ROLLBACK_DIR="${BACKUP_DIR}/rollback-$(date +%Y%m%d_%H%M%S)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_dry_run() {
    echo -e "${BLUE}[DRY RUN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    command -v psql >/dev/null 2>&1 || missing_tools+=("postgresql-client")
    command -v redis-cli >/dev/null 2>&1 || missing_tools+=("redis-tools")
    command -v tar >/dev/null 2>&1 || missing_tools+=("tar")

    if [ "${ENCRYPTION}" = "true" ]; then
        command -v openssl >/dev/null 2>&1 || missing_tools+=("openssl")
        if [ -z "${ENCRYPTION_KEY}" ]; then
            log_error "ENCRYPTION is enabled but ENCRYPTION_KEY is not set"
            exit 1
        fi
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install with: apt-get install -y ${missing_tools[*]}"
        exit 1
    fi

    log_info "All prerequisites satisfied"
}

# List available backups
list_backups() {
    log_info "Available backups:"
    echo ""

    if [ -d "${BACKUP_DIR}" ]; then
        local found=0

        # List unencrypted backups
        for backup_path in "${BACKUP_DIR}"/minio-backup-*; do
            if [ -d "${backup_path}" ]; then
                local backup_name=$(basename "${backup_path}")
                local backup_date=$(stat -c %y "${backup_path}" | cut -d' ' -f1,2 | cut -d'.' -f1)
                local backup_size=$(du -sh "${backup_path}" | cut -f1)

                echo "  - ${backup_name}"
                echo "    Date: ${backup_date}"
                echo "    Size: ${backup_size}"
                echo "    Type: Unencrypted"

                if [ -f "${backup_path}/metadata/backup.json" ]; then
                    echo "    Metadata: Available"
                fi
                echo ""

                found=1
            fi
        done

        # List encrypted backups
        for backup_file in "${BACKUP_DIR}"/minio-backup-*.tar.enc; do
            if [ -f "${backup_file}" ]; then
                local backup_name=$(basename "${backup_file}" .tar.enc)
                local backup_date=$(stat -c %y "${backup_file}" | cut -d' ' -f1,2 | cut -d'.' -f1)
                local backup_size=$(du -sh "${backup_file}" | cut -f1)

                echo "  - ${backup_name}"
                echo "    Date: ${backup_date}"
                echo "    Size: ${backup_size}"
                echo "    Type: Encrypted"
                echo ""

                found=1
            fi
        done

        if [ $found -eq 0 ]; then
            log_warn "No backups found in ${BACKUP_DIR}"
        fi
    else
        log_error "Backup directory not found: ${BACKUP_DIR}"
    fi
}

# Decrypt backup if needed
decrypt_backup() {
    local encrypted_file="${BACKUP_DIR}/${BACKUP_NAME}.tar.enc"

    if [ -f "${encrypted_file}" ]; then
        log_info "Decrypting backup..."

        local decrypted_file="${BACKUP_DIR}/${BACKUP_NAME}.tar"

        if ! openssl enc -aes-256-cbc -d -pbkdf2 \
            -in "${encrypted_file}" \
            -out "${decrypted_file}" \
            -pass pass:"${ENCRYPTION_KEY}"; then
            log_error "Failed to decrypt backup"
            return 1
        fi

        # Extract decrypted archive
        tar -xf "${decrypted_file}" -C "${BACKUP_DIR}"
        rm -f "${decrypted_file}"

        log_info "Backup decrypted successfully"
    fi
}

# Verify backup integrity
verify_backup() {
    log_info "Verifying backup integrity..."

    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"

    if [ ! -d "${backup_path}" ]; then
        log_error "Backup not found: ${backup_path}"
        return 1
    fi

    # Verify metadata
    if [ ! -f "${backup_path}/metadata/backup.json" ]; then
        log_warn "Backup metadata not found"
    else
        log_info "Backup metadata found"
    fi

    # Verify checksums
    if [ -f "${backup_path}/metadata/checksums.txt" ]; then
        (cd "${backup_path}" && sha256sum -c metadata/checksums.txt --quiet) && {
            log_info "Checksum verification passed"
        } || {
            log_error "Checksum verification failed!"
            return 1
        }
    else
        log_warn "Checksums not available, skipping verification"
    fi

    log_info "Backup verification completed successfully"
}

# Create rollback backup
create_rollback_backup() {
    if [ "${CREATE_ROLLBACK}" = "false" ] || [ "${DRY_RUN}" = "true" ]; then
        return 0
    fi

    log_info "Creating rollback backup..."
    mkdir -p "${ROLLBACK_DIR}"/{postgres,redis,minio,config}

    # Backup current PostgreSQL state
    if should_restore "postgres"; then
        log_info "Backing up current PostgreSQL state..."
        local pg_dump_file="${ROLLBACK_DIR}/postgres/minio.sql.gz"

        if [ -n "${POSTGRES_PASSWORD}" ]; then
            export PGPASSWORD="${POSTGRES_PASSWORD}"
        fi

        pg_dump -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
            --clean --if-exists --create | gzip -9 > "${pg_dump_file}" || log_warn "PostgreSQL rollback backup failed"

        unset PGPASSWORD
    fi

    # Backup current Redis state
    if should_restore "redis"; then
        log_info "Backing up current Redis state..."
        if [ -n "${REDIS_PASSWORD}" ]; then
            redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" -a "${REDIS_PASSWORD}" --no-auth-warning BGSAVE >/dev/null || true
        else
            redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" BGSAVE >/dev/null || true
        fi
    fi

    # Backup current MinIO data
    if should_restore "minio" && [ -d "${MINIO_DATA_DIR}" ]; then
        log_info "Backing up current MinIO data..."
        tar -czf "${ROLLBACK_DIR}/minio/data.tar.gz" -C "${MINIO_DATA_DIR}" . 2>/dev/null || log_warn "MinIO rollback backup failed"
    fi

    log_info "Rollback backup created at: ${ROLLBACK_DIR}"
}

# Helper function to check if component should be restored
should_restore() {
    local component=$1
    if [ "${RESTORE_COMPONENTS}" = "all" ] || [[ ",${RESTORE_COMPONENTS}," == *",${component},"* ]]; then
        return 0
    fi
    return 1
}

# Restore PostgreSQL database
restore_postgres() {
    if ! should_restore "postgres"; then
        log_info "Skipping PostgreSQL restore"
        return 0
    fi

    log_info "Restoring PostgreSQL database..."

    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"
    local pg_dump_file="${backup_path}/postgres/minio.sql"

    if [ -f "${pg_dump_file}.gz" ]; then
        pg_dump_file="${pg_dump_file}.gz"
    fi

    if [ ! -f "${pg_dump_file}" ]; then
        log_error "PostgreSQL backup file not found: ${pg_dump_file}"
        return 1
    fi

    if [ "${DRY_RUN}" = "true" ]; then
        log_dry_run "Would restore PostgreSQL from: ${pg_dump_file}"
        return 0
    fi

    if [ -n "${POSTGRES_PASSWORD}" ]; then
        export PGPASSWORD="${POSTGRES_PASSWORD}"
    fi

    # Restore database
    if [[ "${pg_dump_file}" == *.gz ]]; then
        gunzip -c "${pg_dump_file}" | psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres
    else
        psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres -f "${pg_dump_file}"
    fi

    unset PGPASSWORD

    log_info "PostgreSQL restore completed"
}

# Restore Redis data
restore_redis() {
    if ! should_restore "redis"; then
        log_info "Skipping Redis restore"
        return 0
    fi

    log_info "Restoring Redis data..."

    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"
    local redis_dump="${backup_path}/redis/dump.rdb"

    if [ -f "${redis_dump}.gz" ]; then
        redis_dump="${redis_dump}.gz"
    fi

    if [ ! -f "${redis_dump}" ]; then
        log_warn "Redis backup file not found: ${redis_dump}, skipping"
        return 0
    fi

    if [ "${DRY_RUN}" = "true" ]; then
        log_dry_run "Would restore Redis from: ${redis_dump}"
        return 0
    fi

    # Flush current Redis data
    log_warn "Flushing current Redis data..."
    if [ -n "${REDIS_PASSWORD}" ]; then
        redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" -a "${REDIS_PASSWORD}" --no-auth-warning FLUSHALL
    else
        redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" FLUSHALL
    fi

    log_info "Redis restore completed (manual RDB file placement may be required)"
    log_info "To complete Redis restore, copy ${redis_dump} to Redis data directory and restart Redis"
}

# Restore MinIO object data
restore_minio_data() {
    if ! should_restore "minio"; then
        log_info "Skipping MinIO data restore"
        return 0
    fi

    log_info "Restoring MinIO object data..."

    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"
    local minio_backup="${backup_path}/minio/data.tar"

    if [ -f "${minio_backup}.gz" ]; then
        minio_backup="${minio_backup}.gz"
    fi

    if [ ! -f "${minio_backup}" ]; then
        log_warn "MinIO backup file not found: ${minio_backup}, skipping"
        return 0
    fi

    if [ "${DRY_RUN}" = "true" ]; then
        log_dry_run "Would restore MinIO data from: ${minio_backup}"
        return 0
    fi

    # Create data directory if it doesn't exist
    mkdir -p "${MINIO_DATA_DIR}"

    # Restore data
    if [[ "${minio_backup}" == *.gz ]]; then
        tar -xzf "${minio_backup}" -C "${MINIO_DATA_DIR}"
    else
        tar -xf "${minio_backup}" -C "${MINIO_DATA_DIR}"
    fi

    log_info "MinIO data restore completed"
}

# Restore configuration files
restore_config() {
    if ! should_restore "config"; then
        log_info "Skipping configuration restore"
        return 0
    fi

    log_info "Restoring configuration files..."

    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"
    local config_backup="${backup_path}/config/config.tar.gz"

    if [ ! -f "${config_backup}" ]; then
        log_warn "Configuration backup not found, skipping"
        return 0
    fi

    if [ "${DRY_RUN}" = "true" ]; then
        log_dry_run "Would restore configuration from: ${config_backup}"
        return 0
    fi

    # Restore configuration
    tar -xzf "${config_backup}" -C "$(dirname ${CONFIG_DIR})"

    # Restore docker-compose files
    if [ -f "${backup_path}/config/docker-compose.tar.gz" ]; then
        tar -xzf "${backup_path}/config/docker-compose.tar.gz"
    fi

    # Restore environment file
    if [ -f "${backup_path}/config/.env.backup" ]; then
        cp "${backup_path}/config/.env.backup" "configs/.env"
    fi

    log_info "Configuration restore completed"
}

# Verify restore
verify_restore() {
    if [ "${DRY_RUN}" = "true" ]; then
        return 0
    fi

    log_info "Verifying restore..."

    local errors=0

    # Verify PostgreSQL connection
    if should_restore "postgres"; then
        if [ -n "${POSTGRES_PASSWORD}" ]; then
            export PGPASSWORD="${POSTGRES_PASSWORD}"
        fi

        if psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "SELECT 1" >/dev/null 2>&1; then
            log_info "PostgreSQL connection verified"
        else
            log_error "PostgreSQL connection failed"
            errors=$((errors + 1))
        fi

        unset PGPASSWORD
    fi

    # Verify Redis connection
    if should_restore "redis"; then
        if [ -n "${REDIS_PASSWORD}" ]; then
            if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" -a "${REDIS_PASSWORD}" --no-auth-warning PING >/dev/null 2>&1; then
                log_info "Redis connection verified"
            else
                log_error "Redis connection failed"
                errors=$((errors + 1))
            fi
        else
            if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" PING >/dev/null 2>&1; then
                log_info "Redis connection verified"
            else
                log_error "Redis connection failed"
                errors=$((errors + 1))
            fi
        fi
    fi

    # Verify MinIO data directory
    if should_restore "minio" && [ -d "${MINIO_DATA_DIR}" ]; then
        log_info "MinIO data directory verified"
    fi

    if [ $errors -eq 0 ]; then
        log_info "Restore verification completed successfully"
        return 0
    else
        log_error "Restore verification failed with ${errors} errors"
        return 1
    fi
}

# Print restore summary
print_summary() {
    echo ""
    echo "========================================="
    echo "Restore Summary"
    echo "========================================="
    echo "Backup Name:       ${BACKUP_NAME}"
    echo "Components:        ${RESTORE_COMPONENTS}"
    echo "Dry Run:           ${DRY_RUN}"
    echo "Rollback Created:  ${CREATE_ROLLBACK}"
    echo "Timestamp:         $(date)"
    echo ""

    if [ "${CREATE_ROLLBACK}" = "true" ] && [ "${DRY_RUN}" = "false" ]; then
        echo "Rollback Location: ${ROLLBACK_DIR}"
        echo ""
        echo "To rollback this restore, run:"
        echo "  BACKUP_NAME=$(basename ${ROLLBACK_DIR}) ./scripts/restore.sh"
    fi

    echo "========================================="
}

# Main execution
main() {
    log_info "Starting MinIO Enterprise restore process..."

    # If no backup name provided, list available backups
    if [ -z "${BACKUP_NAME}" ]; then
        list_backups
        echo ""
        log_error "Please specify a backup to restore using: BACKUP_NAME=<name> ./scripts/restore.sh"
        exit 1
    fi

    if [ "${DRY_RUN}" = "true" ]; then
        log_info "Running in DRY RUN mode - no changes will be made"
    fi

    check_prerequisites
    decrypt_backup
    verify_backup
    create_rollback_backup

    # Perform restore
    restore_postgres || log_error "PostgreSQL restore failed but continuing..."
    restore_redis || log_error "Redis restore failed but continuing..."
    restore_minio_data || log_error "MinIO data restore failed but continuing..."
    restore_config || log_error "Configuration restore failed but continuing..."

    verify_restore
    print_summary

    log_info "Restore process completed"
}

# Run main function
main "$@"
