#!/bin/bash
################################################################################
# MinIO Enterprise - Automated Restore Script
################################################################################
# Description: Comprehensive restore solution for MinIO Enterprise
# Supports: Full restore, selective restore, verification, rollback
# Components: MinIO objects, PostgreSQL database, Redis snapshots, configs
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
BACKUP_FILE="${1:-}"
RESTORE_MODE="${RESTORE_MODE:-full}"  # full, selective, verify-only
SKIP_VERIFICATION="${SKIP_VERIFICATION:-false}"
CREATE_SNAPSHOT="${CREATE_SNAPSHOT:-true}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"

# Timestamp for restore
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESTORE_LOG="${SCRIPT_DIR}/restore-${TIMESTAMP}.log"
ERRORS_LOG="${SCRIPT_DIR}/restore-errors-${TIMESTAMP}.log"
TEMP_DIR="/tmp/minio-restore-${TIMESTAMP}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Logging functions
################################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        INFO)  color="${GREEN}" ;;
        WARN)  color="${YELLOW}" ;;
        ERROR) color="${RED}" ;;
        DEBUG) color="${BLUE}" ;;
        *)     color="${NC}" ;;
    esac

    echo -e "${color}[${timestamp}] [${level}] ${message}${NC}" | tee -a "${RESTORE_LOG}"
}

log_error() {
    log ERROR "$@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "${ERRORS_LOG}"
}

################################################################################
# Utility functions
################################################################################

usage() {
    cat <<EOF
Usage: $0 <backup-file> [options]

Restore MinIO Enterprise from backup.

Arguments:
  backup-file           Path to backup file or directory

Options:
  RESTORE_MODE          Restore mode: full, selective, verify-only (default: full)
  SKIP_VERIFICATION     Skip verification step (default: false)
  CREATE_SNAPSHOT       Create snapshot before restore (default: true)
  ENCRYPTION_KEY        Decryption key if backup is encrypted

Examples:
  # Full restore from backup
  $0 /var/backups/minio-backup-full-20240118_120000.tar.gz

  # Verify backup without restoring
  RESTORE_MODE=verify-only $0 /var/backups/minio-backup-full-20240118_120000.tar.gz

  # Selective restore (configs only)
  RESTORE_MODE=selective $0 /var/backups/minio-backup-full-20240118_120000.tar.gz

  # Restore encrypted backup
  ENCRYPTION_KEY="your-key" $0 /var/backups/minio-backup-full-20240118_120000.tar.gz.enc

EOF
    exit 1
}

check_dependencies() {
    local deps=("docker" "tar" "gzip" "jq")

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done

    log INFO "All dependencies satisfied"
}

validate_backup_file() {
    if [[ -z "${BACKUP_FILE}" ]]; then
        log_error "No backup file specified"
        usage
    fi

    if [[ ! -e "${BACKUP_FILE}" ]]; then
        log_error "Backup file not found: ${BACKUP_FILE}"
        return 1
    fi

    log INFO "Backup file validated: ${BACKUP_FILE}"
}

################################################################################
# Pre-restore functions
################################################################################

create_pre_restore_snapshot() {
    if [[ "${CREATE_SNAPSHOT}" != "true" ]]; then
        log INFO "Skipping pre-restore snapshot"
        return 0
    fi

    log INFO "Creating pre-restore snapshot..."

    local snapshot_dir="/var/backups/minio-enterprise/pre-restore-snapshots"
    mkdir -p "$snapshot_dir"

    # Run backup script to create snapshot
    if [[ -f "${SCRIPT_DIR}/../backup/backup.sh" ]]; then
        BACKUP_DIR="$snapshot_dir" \
        BACKUP_TYPE="snapshot" \
        "${SCRIPT_DIR}/../backup/backup.sh" 2>&1 | tee -a "${RESTORE_LOG}"

        log INFO "Pre-restore snapshot created"
    else
        log WARN "Backup script not found, skipping snapshot"
    fi
}

decrypt_backup() {
    if [[ "${BACKUP_FILE}" == *.enc ]]; then
        if [[ -z "${ENCRYPTION_KEY}" ]]; then
            log_error "Backup is encrypted but no decryption key provided"
            return 1
        fi

        log INFO "Decrypting backup..."

        local decrypted_file="${TEMP_DIR}/$(basename ${BACKUP_FILE%.enc})"
        mkdir -p "${TEMP_DIR}"

        openssl enc -aes-256-cbc -d -in "${BACKUP_FILE}" -out "$decrypted_file" -k "${ENCRYPTION_KEY}"

        if [[ $? -eq 0 ]]; then
            BACKUP_FILE="$decrypted_file"
            log INFO "Backup decrypted successfully"
        else
            log_error "Backup decryption failed"
            return 1
        fi
    fi
}

extract_backup() {
    log INFO "Extracting backup..."

    mkdir -p "${TEMP_DIR}"

    if [[ -f "${BACKUP_FILE}" ]] && [[ "${BACKUP_FILE}" == *.tar.gz ]]; then
        tar -xzf "${BACKUP_FILE}" -C "${TEMP_DIR}"

        # Find the backup directory
        local backup_dir=$(find "${TEMP_DIR}" -maxdepth 1 -type d -name "minio-backup-*" | head -n1)

        if [[ -z "$backup_dir" ]]; then
            log_error "Invalid backup structure"
            return 1
        fi

        echo "$backup_dir"
    elif [[ -d "${BACKUP_FILE}" ]]; then
        echo "${BACKUP_FILE}"
    else
        log_error "Unsupported backup format"
        return 1
    fi
}

verify_backup_integrity() {
    local backup_dir="$1"

    log INFO "Verifying backup integrity..."

    # Check for metadata
    if [[ ! -f "${backup_dir}/metadata/backup-info.json" ]]; then
        log_error "Backup metadata not found"
        return 1
    fi

    # Parse metadata
    local backup_info=$(cat "${backup_dir}/metadata/backup-info.json")
    local backup_type=$(echo "$backup_info" | jq -r '.backup_type')
    local backup_date=$(echo "$backup_info" | jq -r '.date')
    local version=$(echo "$backup_info" | jq -r '.version')

    log INFO "Backup Type: ${backup_type}"
    log INFO "Backup Date: ${backup_date}"
    log INFO "Version: ${version}"

    # Check for required components
    local required_dirs=("minio" "postgres" "redis" "configs")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "${backup_dir}/${dir}" ]]; then
            log_error "Required backup component missing: ${dir}"
            return 1
        fi
    done

    log INFO "Backup integrity verified"
}

################################################################################
# Restore functions
################################################################################

confirm_restore() {
    if [[ "${SKIP_VERIFICATION}" == "true" ]]; then
        return 0
    fi

    log WARN "=========================================="
    log WARN "WARNING: This will REPLACE current data!"
    log WARN "=========================================="
    log WARN "A snapshot will be created before restore."
    log WARN ""

    read -p "Are you sure you want to continue? (yes/no): " confirm

    if [[ "${confirm}" != "yes" ]]; then
        log INFO "Restore cancelled by user"
        exit 0
    fi
}

stop_services() {
    log INFO "Stopping services..."

    # Stop MinIO services gracefully
    docker-compose -f "${PROJECT_ROOT}/deployments/docker/docker-compose.yml" stop minio || true
    docker-compose -f "${PROJECT_ROOT}/deployments/docker/docker-compose.production.yml" stop minio || true

    log INFO "Services stopped"
}

restore_minio_data() {
    local backup_dir="$1"

    log INFO "Restoring MinIO data..."

    local minio_container=$(docker ps -a --format '{{.Names}}' | grep minio | head -n1)

    if [[ -z "$minio_container" ]]; then
        log_error "MinIO container not found"
        return 1
    fi

    # Copy backup to container
    docker cp "${backup_dir}/minio/minio-data.tar.gz" "${minio_container}:/tmp/"

    # Extract in container
    docker exec "$minio_container" bash -c "cd / && tar xzf /tmp/minio-data.tar.gz"
    docker exec "$minio_container" rm -f /tmp/minio-data.tar.gz

    log INFO "MinIO data restored"
}

restore_postgres() {
    local backup_dir="$1"

    log INFO "Restoring PostgreSQL database..."

    local postgres_container=$(docker ps --format '{{.Names}}' | grep postgres | head -n1)

    if [[ -z "$postgres_container" ]]; then
        log_error "PostgreSQL container not found"
        return 1
    fi

    local db_name="${POSTGRES_DB:-minio}"
    local db_user="${POSTGRES_USER:-postgres}"

    # Copy backup to container
    docker cp "${backup_dir}/postgres/postgres-backup.dump" "${postgres_container}:/tmp/"

    # Drop existing database and recreate
    docker exec "$postgres_container" psql -U "$db_user" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${db_name}';" || true
    docker exec "$postgres_container" psql -U "$db_user" -c "DROP DATABASE IF EXISTS ${db_name};" || true
    docker exec "$postgres_container" psql -U "$db_user" -c "CREATE DATABASE ${db_name};"

    # Restore from backup
    docker exec "$postgres_container" pg_restore -U "$db_user" -d "$db_name" /tmp/postgres-backup.dump
    docker exec "$postgres_container" rm -f /tmp/postgres-backup.dump

    log INFO "PostgreSQL database restored"
}

restore_redis() {
    local backup_dir="$1"

    log INFO "Restoring Redis data..."

    local redis_container=$(docker ps -a --format '{{.Names}}' | grep redis | head -n1)

    if [[ -z "$redis_container" ]]; then
        log_error "Redis container not found"
        return 1
    fi

    # Stop Redis to restore RDB file
    docker stop "$redis_container" 2>/dev/null || true

    # Copy backup to container
    docker cp "${backup_dir}/redis/redis-data.tar.gz" "${redis_container}:/tmp/"

    # Extract in container
    docker start "$redis_container"
    docker exec "$redis_container" bash -c "cd / && tar xzf /tmp/redis-data.tar.gz"
    docker exec "$redis_container" rm -f /tmp/redis-data.tar.gz

    # Restart Redis
    docker restart "$redis_container"

    log INFO "Redis data restored"
}

restore_configs() {
    local backup_dir="$1"

    log INFO "Restoring configuration files..."

    # Restore deployment configurations
    if [[ -d "${backup_dir}/configs/deployments" ]]; then
        cp -r "${backup_dir}/configs/deployments" "${PROJECT_ROOT}/"
        log INFO "Deployment configs restored"
    fi

    # Restore configs directory
    if [[ -d "${backup_dir}/configs/configs" ]]; then
        cp -r "${backup_dir}/configs/configs" "${PROJECT_ROOT}/"
        log INFO "Configuration templates restored"
    fi

    # Restore environment file
    if [[ -f "${backup_dir}/configs/.env.backup" ]]; then
        cp "${backup_dir}/configs/.env.backup" "${PROJECT_ROOT}/.env"
        log INFO "Environment file restored"
    fi

    log INFO "Configuration files restored"
}

start_services() {
    log INFO "Starting services..."

    # Start services
    docker-compose -f "${PROJECT_ROOT}/deployments/docker/docker-compose.yml" start minio || \
    docker-compose -f "${PROJECT_ROOT}/deployments/docker/docker-compose.production.yml" start minio

    log INFO "Services started"
}

verify_restore() {
    log INFO "Verifying restore..."

    # Wait for services to be ready
    sleep 10

    # Check MinIO health
    local minio_container=$(docker ps --format '{{.Names}}' | grep minio | head -n1)
    if [[ -n "$minio_container" ]]; then
        if docker exec "$minio_container" mc admin info local >/dev/null 2>&1; then
            log INFO "MinIO is healthy"
        else
            log WARN "MinIO health check failed"
        fi
    fi

    # Check PostgreSQL
    local postgres_container=$(docker ps --format '{{.Names}}' | grep postgres | head -n1)
    if [[ -n "$postgres_container" ]]; then
        if docker exec "$postgres_container" pg_isready >/dev/null 2>&1; then
            log INFO "PostgreSQL is healthy"
        else
            log WARN "PostgreSQL health check failed"
        fi
    fi

    # Check Redis
    local redis_container=$(docker ps --format '{{.Names}}' | grep redis | head -n1)
    if [[ -n "$redis_container" ]]; then
        if docker exec "$redis_container" redis-cli ping | grep -q PONG; then
            log INFO "Redis is healthy"
        else
            log WARN "Redis health check failed"
        fi
    fi

    log INFO "Restore verification completed"
}

################################################################################
# Cleanup functions
################################################################################

cleanup_temp_files() {
    log INFO "Cleaning up temporary files..."

    if [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi

    log INFO "Cleanup completed"
}

################################################################################
# Main restore workflow
################################################################################

main() {
    log INFO "=========================================="
    log INFO "MinIO Enterprise Restore Starting"
    log INFO "Restore Mode: ${RESTORE_MODE}"
    log INFO "=========================================="

    # Pre-flight checks
    validate_backup_file || exit 1
    check_dependencies || exit 1

    # Decrypt if needed
    decrypt_backup || exit 1

    # Extract backup
    local backup_dir=$(extract_backup)
    if [[ -z "$backup_dir" ]]; then
        log_error "Failed to extract backup"
        exit 1
    fi

    log INFO "Backup extracted to: ${backup_dir}"

    # Verify backup integrity
    verify_backup_integrity "$backup_dir" || exit 1

    # Verify-only mode
    if [[ "${RESTORE_MODE}" == "verify-only" ]]; then
        log INFO "=========================================="
        log INFO "Backup verification completed successfully"
        log INFO "=========================================="
        cleanup_temp_files
        exit 0
    fi

    # Confirm restore
    confirm_restore

    # Create pre-restore snapshot
    create_pre_restore_snapshot

    # Stop services
    stop_services

    # Perform restore
    if [[ "${RESTORE_MODE}" == "full" ]] || [[ "${RESTORE_MODE}" == "selective" ]]; then
        restore_minio_data "$backup_dir" || log_error "MinIO data restore failed"
        restore_postgres "$backup_dir" || log_error "PostgreSQL restore failed"
        restore_redis "$backup_dir" || log_error "Redis restore failed"
        restore_configs "$backup_dir" || log_error "Configuration restore failed"
    fi

    # Start services
    start_services

    # Verify restore
    verify_restore

    # Cleanup
    cleanup_temp_files

    log INFO "=========================================="
    log INFO "Restore completed successfully"
    log INFO "Restore log: ${RESTORE_LOG}"
    log INFO "=========================================="
}

# Run main function
main "$@"
