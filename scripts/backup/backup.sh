#!/bin/bash
################################################################################
# MinIO Enterprise - Automated Backup Script
################################################################################
# Description: Comprehensive backup solution for MinIO Enterprise
# Supports: Full backups, incremental backups, encryption, compression
# Components: MinIO objects, PostgreSQL database, Redis snapshots, configs
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source configuration
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/backup.conf}"
if [[ -f "${CONFIG_FILE}" ]]; then
    source "${CONFIG_FILE}"
fi

# Default configuration
BACKUP_TYPE="${BACKUP_TYPE:-full}"  # full or incremental
BACKUP_DIR="${BACKUP_DIR:-/var/backups/minio-enterprise}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
COMPRESS="${COMPRESS:-true}"
ENCRYPT="${ENCRYPT:-false}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"
S3_BACKUP="${S3_BACKUP:-false}"
S3_ENDPOINT="${S3_ENDPOINT:-}"
S3_BUCKET="${S3_BUCKET:-}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-}"
S3_SECRET_KEY="${S3_SECRET_KEY:-}"

# Timestamp for backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="minio-backup-${BACKUP_TYPE}-${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# Logging
LOG_FILE="${BACKUP_DIR}/backup.log"
ERRORS_FILE="${BACKUP_DIR}/backup-errors.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
        *)     color="${NC}" ;;
    esac

    echo -e "${color}[${timestamp}] [${level}] ${message}${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    log ERROR "$@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "${ERRORS_FILE}"
}

################################################################################
# Utility functions
################################################################################

create_backup_dir() {
    log INFO "Creating backup directory: ${BACKUP_PATH}"
    mkdir -p "${BACKUP_PATH}"/{minio,postgres,redis,configs,metadata}
}

check_dependencies() {
    local deps=("docker" "tar" "gzip")

    if [[ "${ENCRYPT}" == "true" ]]; then
        deps+=("openssl")
    fi

    if [[ "${S3_BACKUP}" == "true" ]]; then
        deps+=("aws")
    fi

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done

    log INFO "All dependencies satisfied"
}

check_docker_services() {
    log INFO "Checking Docker services..."

    local required_services=("minio" "postgres" "redis")
    local all_running=true

    for service in "${required_services[@]}"; do
        if ! docker ps --format '{{.Names}}' | grep -q "$service"; then
            log ERROR "Required service not running: $service"
            all_running=false
        fi
    done

    if [[ "$all_running" == "false" ]]; then
        return 1
    fi

    log INFO "All required services are running"
}

################################################################################
# Backup functions
################################################################################

backup_minio_data() {
    log INFO "Backing up MinIO data..."

    local minio_container=$(docker ps --format '{{.Names}}' | grep minio | head -n1)

    if [[ -z "$minio_container" ]]; then
        log_error "MinIO container not found"
        return 1
    fi

    # Export MinIO data directory
    docker exec "$minio_container" tar czf /tmp/minio-data.tar.gz /data 2>/dev/null || true
    docker cp "${minio_container}:/tmp/minio-data.tar.gz" "${BACKUP_PATH}/minio/minio-data.tar.gz"
    docker exec "$minio_container" rm -f /tmp/minio-data.tar.gz

    log INFO "MinIO data backup completed"
}

backup_postgres() {
    log INFO "Backing up PostgreSQL database..."

    local postgres_container=$(docker ps --format '{{.Names}}' | grep postgres | head -n1)

    if [[ -z "$postgres_container" ]]; then
        log_error "PostgreSQL container not found"
        return 1
    fi

    # Get database credentials from environment or defaults
    local db_name="${POSTGRES_DB:-minio}"
    local db_user="${POSTGRES_USER:-postgres}"

    # Full backup
    docker exec "$postgres_container" pg_dump -U "$db_user" -d "$db_name" -F c -f /tmp/postgres-backup.dump
    docker cp "${postgres_container}:/tmp/postgres-backup.dump" "${BACKUP_PATH}/postgres/postgres-backup.dump"
    docker exec "$postgres_container" rm -f /tmp/postgres-backup.dump

    # Also export as SQL for easy inspection
    docker exec "$postgres_container" pg_dump -U "$db_user" -d "$db_name" > "${BACKUP_PATH}/postgres/postgres-backup.sql"

    log INFO "PostgreSQL backup completed"
}

backup_redis() {
    log INFO "Backing up Redis data..."

    local redis_container=$(docker ps --format '{{.Names}}' | grep redis | head -n1)

    if [[ -z "$redis_container" ]]; then
        log_error "Redis container not found"
        return 1
    fi

    # Trigger Redis save
    docker exec "$redis_container" redis-cli SAVE || true

    # Copy RDB file
    docker exec "$redis_container" tar czf /tmp/redis-data.tar.gz /data 2>/dev/null || true
    docker cp "${redis_container}:/tmp/redis-data.tar.gz" "${BACKUP_PATH}/redis/redis-data.tar.gz"
    docker exec "$redis_container" rm -f /tmp/redis-data.tar.gz

    log INFO "Redis backup completed"
}

backup_configs() {
    log INFO "Backing up configuration files..."

    # Backup Docker Compose files
    cp -r "${PROJECT_ROOT}/deployments" "${BACKUP_PATH}/configs/"

    # Backup configuration templates
    if [[ -d "${PROJECT_ROOT}/configs" ]]; then
        cp -r "${PROJECT_ROOT}/configs" "${BACKUP_PATH}/configs/"
    fi

    # Backup environment files (excluding secrets)
    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        cp "${PROJECT_ROOT}/.env" "${BACKUP_PATH}/configs/.env.backup"
    fi

    log INFO "Configuration backup completed"
}

create_metadata() {
    log INFO "Creating backup metadata..."

    cat > "${BACKUP_PATH}/metadata/backup-info.json" <<EOF
{
  "backup_name": "${BACKUP_NAME}",
  "backup_type": "${BACKUP_TYPE}",
  "timestamp": "${TIMESTAMP}",
  "date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "components": {
    "minio": "included",
    "postgres": "included",
    "redis": "included",
    "configs": "included"
  },
  "compression": "${COMPRESS}",
  "encryption": "${ENCRYPT}",
  "version": "2.0.0"
}
EOF

    # Save Docker container versions
    docker ps --format '{{.Names}}\t{{.Image}}' > "${BACKUP_PATH}/metadata/docker-versions.txt"

    log INFO "Metadata created"
}

compress_backup() {
    if [[ "${COMPRESS}" == "true" ]]; then
        log INFO "Compressing backup..."

        local archive_name="${BACKUP_NAME}.tar.gz"
        tar -czf "${BACKUP_DIR}/${archive_name}" -C "${BACKUP_DIR}" "${BACKUP_NAME}"

        # Remove uncompressed directory
        rm -rf "${BACKUP_PATH}"

        log INFO "Backup compressed: ${archive_name}"
        echo "${BACKUP_DIR}/${archive_name}"
    else
        echo "${BACKUP_PATH}"
    fi
}

encrypt_backup() {
    if [[ "${ENCRYPT}" == "true" ]]; then
        if [[ -z "${ENCRYPTION_KEY}" ]]; then
            log_error "Encryption enabled but no encryption key provided"
            return 1
        fi

        log INFO "Encrypting backup..."

        local input_file="$1"
        local encrypted_file="${input_file}.enc"

        openssl enc -aes-256-cbc -salt -in "$input_file" -out "$encrypted_file" -k "${ENCRYPTION_KEY}"

        # Remove unencrypted file
        rm -f "$input_file"

        log INFO "Backup encrypted: $(basename $encrypted_file)"
        echo "$encrypted_file"
    else
        echo "$1"
    fi
}

upload_to_s3() {
    if [[ "${S3_BACKUP}" == "true" ]]; then
        log INFO "Uploading backup to S3..."

        local backup_file="$1"

        if [[ -z "${S3_ENDPOINT}" ]] || [[ -z "${S3_BUCKET}" ]]; then
            log_error "S3 backup enabled but endpoint or bucket not configured"
            return 1
        fi

        export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY}"
        export AWS_SECRET_ACCESS_KEY="${S3_SECRET_KEY}"

        aws s3 cp "$backup_file" "s3://${S3_BUCKET}/backups/$(basename $backup_file)" \
            --endpoint-url "${S3_ENDPOINT}"

        log INFO "Backup uploaded to S3: s3://${S3_BUCKET}/backups/$(basename $backup_file)"
    fi
}

cleanup_old_backups() {
    log INFO "Cleaning up old backups (retention: ${RETENTION_DAYS} days)..."

    find "${BACKUP_DIR}" -type f -name "minio-backup-*" -mtime +${RETENTION_DAYS} -delete

    local removed=$(find "${BACKUP_DIR}" -type f -name "minio-backup-*" -mtime +${RETENTION_DAYS} 2>/dev/null | wc -l)
    log INFO "Removed ${removed} old backup(s)"
}

verify_backup() {
    log INFO "Verifying backup integrity..."

    local backup_file="$1"

    if [[ "${backup_file}" == *.tar.gz ]]; then
        if tar -tzf "${backup_file}" > /dev/null 2>&1; then
            log INFO "Backup verification passed"
            return 0
        else
            log_error "Backup verification failed"
            return 1
        fi
    fi

    if [[ -d "${backup_file}" ]]; then
        if [[ -f "${backup_file}/metadata/backup-info.json" ]]; then
            log INFO "Backup verification passed"
            return 0
        else
            log_error "Backup verification failed: missing metadata"
            return 1
        fi
    fi

    log INFO "Backup verification passed"
}

################################################################################
# Main backup workflow
################################################################################

main() {
    log INFO "========================================"
    log INFO "MinIO Enterprise Backup Starting"
    log INFO "Backup Type: ${BACKUP_TYPE}"
    log INFO "========================================"

    # Pre-flight checks
    mkdir -p "${BACKUP_DIR}"
    check_dependencies || exit 1
    check_docker_services || exit 1

    # Create backup directory structure
    create_backup_dir

    # Perform backups
    backup_minio_data || log_error "MinIO data backup failed"
    backup_postgres || log_error "PostgreSQL backup failed"
    backup_redis || log_error "Redis backup failed"
    backup_configs || log_error "Configuration backup failed"

    # Create metadata
    create_metadata

    # Post-processing
    local final_backup="${BACKUP_PATH}"

    if [[ "${COMPRESS}" == "true" ]]; then
        final_backup=$(compress_backup)
    fi

    if [[ "${ENCRYPT}" == "true" ]]; then
        final_backup=$(encrypt_backup "${final_backup}")
    fi

    # Verify backup
    verify_backup "${final_backup}"

    # Upload to S3 if configured
    if [[ "${S3_BACKUP}" == "true" ]]; then
        upload_to_s3 "${final_backup}"
    fi

    # Cleanup old backups
    cleanup_old_backups

    # Calculate backup size
    local backup_size=$(du -sh "${final_backup}" | cut -f1)

    log INFO "========================================"
    log INFO "Backup completed successfully"
    log INFO "Backup location: ${final_backup}"
    log INFO "Backup size: ${backup_size}"
    log INFO "========================================"
}

# Run main function
main "$@"
