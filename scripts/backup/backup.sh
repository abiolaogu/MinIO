#!/bin/bash
# MinIO Enterprise Backup Script
# ================================
# Automated backup solution for MinIO Enterprise stack
# Supports: MinIO data, PostgreSQL, Redis, configuration files
# Features: Compression, encryption, verification, remote storage

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Load configuration
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/backup.conf}"
if [[ -f "${CONFIG_FILE}" ]]; then
    source "${CONFIG_FILE}"
else
    echo -e "${RED}Error: Configuration file not found: ${CONFIG_FILE}${NC}"
    exit 1
fi

# Initialize variables
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_ROOT_DIR}/${TIMESTAMP}"
LOG_FILE="${LOG_DIR}/backup_${TIMESTAMP}.log"
BACKUP_METADATA="${BACKUP_DIR}/backup_metadata.json"

# Create necessary directories
mkdir -p "${BACKUP_DIR}"
mkdir -p "${LOG_DIR}"

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warn() {
    log "WARN" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Error handler
error_handler() {
    log_error "Backup failed at line $1"
    send_notification "FAILED" "Backup failed at line $1"
    exit 1
}

trap 'error_handler ${LINENO}' ERR

# Send notification
send_notification() {
    local status=$1
    local message=$2

    if [[ "${ENABLE_EMAIL_NOTIFICATION}" == "true" ]]; then
        echo "${message}" | mail -s "${EMAIL_SUBJECT_PREFIX} ${status}" "${EMAIL_RECIPIENT}" 2>/dev/null || true
    fi

    if [[ -n "${BACKUP_HEALTH_CHECK_URL}" ]]; then
        if [[ "${status}" == "SUCCESS" ]]; then
            curl -fsS --retry 3 "${BACKUP_HEALTH_CHECK_URL}" >/dev/null 2>&1 || true
        fi
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    # Check required tools
    for tool in docker docker-compose tar gzip; do
        if ! command -v ${tool} &> /dev/null; then
            missing_tools+=("${tool}")
        fi
    done

    # Check optional tools
    if [[ "${BACKUP_COMPRESSION}" == "true" ]] && [[ "${COMPRESSION_TOOL}" != "gzip" ]]; then
        if ! command -v ${COMPRESSION_TOOL} &> /dev/null; then
            log_warn "Compression tool ${COMPRESSION_TOOL} not found, falling back to gzip"
            COMPRESSION_TOOL="gzip"
        fi
    fi

    if [[ "${BACKUP_ENCRYPTION}" == "true" ]]; then
        if ! command -v openssl &> /dev/null; then
            missing_tools+=("openssl")
        fi
    fi

    if [[ "${S3_BACKUP_ENABLED}" == "true" ]]; then
        if ! command -v aws &> /dev/null; then
            log_warn "AWS CLI not found, S3 backup will be skipped"
            S3_BACKUP_ENABLED="false"
        fi
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    # Check Docker containers
    cd "${PROJECT_ROOT}"
    if ! docker-compose -f "${DOCKER_COMPOSE_FILE}" ps &> /dev/null; then
        log_error "Docker Compose services not running"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Create backup metadata
create_metadata() {
    log_info "Creating backup metadata..."

    cat > "${BACKUP_METADATA}" <<EOF
{
    "backup_timestamp": "${TIMESTAMP}",
    "backup_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "backup_type": "$([ "${ENABLE_INCREMENTAL_BACKUP}" == "true" ] && echo "incremental" || echo "full")",
    "components": {
        "minio_data": ${BACKUP_MINIO_DATA},
        "postgresql": ${BACKUP_POSTGRESQL},
        "redis": ${BACKUP_REDIS},
        "config_files": ${BACKUP_CONFIG_FILES}
    },
    "settings": {
        "compression": "${BACKUP_COMPRESSION}",
        "compression_tool": "${COMPRESSION_TOOL}",
        "encryption": "${BACKUP_ENCRYPTION}",
        "verification": "${BACKUP_VERIFICATION}"
    },
    "hostname": "$(hostname)",
    "script_version": "1.0.0"
}
EOF

    log_success "Metadata created"
}

# Backup PostgreSQL
backup_postgresql() {
    if [[ "${BACKUP_POSTGRESQL}" != "true" ]]; then
        log_info "PostgreSQL backup disabled, skipping"
        return 0
    fi

    log_info "Backing up PostgreSQL database..."

    local pg_backup_file="${BACKUP_DIR}/postgresql_${TIMESTAMP}.sql"

    cd "${PROJECT_ROOT}"
    docker exec "${POSTGRES_CONTAINER}" pg_dump \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        --format=custom \
        --compress=9 \
        --verbose \
        > "${pg_backup_file}" 2>>"${LOG_FILE}"

    # Verify backup
    if [[ "${BACKUP_VERIFICATION}" == "true" ]]; then
        log_info "Verifying PostgreSQL backup..."
        if docker exec "${POSTGRES_CONTAINER}" pg_restore --list "${pg_backup_file}" &>/dev/null; then
            log_success "PostgreSQL backup verified"
        else
            log_error "PostgreSQL backup verification failed"
            return 1
        fi
    fi

    local backup_size=$(du -h "${pg_backup_file}" | cut -f1)
    log_success "PostgreSQL backup completed (${backup_size})"

    return 0
}

# Backup Redis
backup_redis() {
    if [[ "${BACKUP_REDIS}" != "true" ]]; then
        log_info "Redis backup disabled, skipping"
        return 0
    fi

    log_info "Backing up Redis data..."

    local redis_backup_dir="${BACKUP_DIR}/redis"
    mkdir -p "${redis_backup_dir}"

    cd "${PROJECT_ROOT}"

    # Trigger Redis save
    docker exec "${REDIS_CONTAINER}" redis-cli BGSAVE >/dev/null

    # Wait for save to complete
    log_info "Waiting for Redis BGSAVE to complete..."
    local max_wait=60
    local waited=0
    while [[ ${waited} -lt ${max_wait} ]]; do
        if docker exec "${REDIS_CONTAINER}" redis-cli LASTSAVE | grep -q "$(docker exec "${REDIS_CONTAINER}" redis-cli LASTSAVE)"; then
            sleep 1
            if ! docker exec "${REDIS_CONTAINER}" redis-cli INFO persistence | grep -q "rdb_bgsave_in_progress:1"; then
                break
            fi
        fi
        sleep 1
        waited=$((waited + 1))
    done

    # Copy RDB file
    docker cp "${REDIS_CONTAINER}:/data/${REDIS_RDB_FILE}" "${redis_backup_dir}/" 2>>"${LOG_FILE}" || true

    # Copy AOF file if exists
    docker cp "${REDIS_CONTAINER}:/data/${REDIS_AOF_FILE}" "${redis_backup_dir}/" 2>>"${LOG_FILE}" || true

    local backup_size=$(du -sh "${redis_backup_dir}" | cut -f1)
    log_success "Redis backup completed (${backup_size})"

    return 0
}

# Backup MinIO data
backup_minio_data() {
    if [[ "${BACKUP_MINIO_DATA}" != "true" ]]; then
        log_info "MinIO data backup disabled, skipping"
        return 0
    fi

    log_info "Backing up MinIO data volumes..."

    local minio_backup_dir="${BACKUP_DIR}/minio_data"
    mkdir -p "${minio_backup_dir}"

    cd "${PROJECT_ROOT}"

    # Backup each MinIO data volume
    for volume in ${MINIO_DATA_VOLUMES}; do
        log_info "Backing up volume: ${volume}..."

        local volume_backup="${minio_backup_dir}/${volume}.tar"

        # Create temporary container to access volume
        docker run --rm \
            -v "${volume}:/data:ro" \
            -v "${minio_backup_dir}:/backup" \
            alpine \
            tar -cf "/backup/${volume}.tar" -C /data . 2>>"${LOG_FILE}"

        # Compress if enabled
        if [[ "${BACKUP_COMPRESSION}" == "true" ]]; then
            log_info "Compressing ${volume}..."
            case "${COMPRESSION_TOOL}" in
                gzip)
                    gzip -${COMPRESSION_LEVEL} "${volume_backup}"
                    ;;
                bzip2)
                    bzip2 -${COMPRESSION_LEVEL} "${volume_backup}"
                    ;;
                xz)
                    xz -${COMPRESSION_LEVEL} "${volume_backup}"
                    ;;
            esac
        fi

        log_success "Volume ${volume} backed up"
    done

    local backup_size=$(du -sh "${minio_backup_dir}" | cut -f1)
    log_success "MinIO data backup completed (${backup_size})"

    return 0
}

# Backup configuration files
backup_config_files() {
    if [[ "${BACKUP_CONFIG_FILES}" != "true" ]]; then
        log_info "Configuration backup disabled, skipping"
        return 0
    fi

    log_info "Backing up configuration files..."

    local config_backup_file="${BACKUP_DIR}/config_${TIMESTAMP}.tar.gz"

    cd "${PROJECT_ROOT}"

    # List of config directories/files to backup
    local config_paths=(
        "configs"
        "deployments"
        ".env"
        "docker-compose*.yml"
    )

    # Create tar archive
    tar -czf "${config_backup_file}" \
        --exclude='*.log' \
        --exclude='*.tmp' \
        --exclude='.git' \
        ${config_paths[@]} 2>>"${LOG_FILE}" || true

    local backup_size=$(du -h "${config_backup_file}" | cut -f1)
    log_success "Configuration backup completed (${backup_size})"

    return 0
}

# Encrypt backup
encrypt_backup() {
    if [[ "${BACKUP_ENCRYPTION}" != "true" ]]; then
        return 0
    fi

    if [[ -z "${ENCRYPTION_KEY_FILE}" ]] || [[ ! -f "${ENCRYPTION_KEY_FILE}" ]]; then
        log_warn "Encryption key file not found, skipping encryption"
        return 0
    fi

    log_info "Encrypting backup..."

    # Create encrypted archive
    local encrypted_file="${BACKUP_DIR}.tar.gz.enc"

    tar -czf - -C "$(dirname "${BACKUP_DIR}")" "$(basename "${BACKUP_DIR}")" | \
        openssl enc -${ENCRYPTION_ALGORITHM} \
        -salt \
        -pass file:"${ENCRYPTION_KEY_FILE}" \
        -out "${encrypted_file}"

    if [[ $? -eq 0 ]]; then
        # Remove unencrypted backup
        rm -rf "${BACKUP_DIR}"
        log_success "Backup encrypted successfully"
    else
        log_error "Encryption failed"
        return 1
    fi

    return 0
}

# Upload to S3
upload_to_s3() {
    if [[ "${S3_BACKUP_ENABLED}" != "true" ]]; then
        return 0
    fi

    log_info "Uploading backup to S3..."

    local backup_archive
    if [[ "${BACKUP_ENCRYPTION}" == "true" ]]; then
        backup_archive="${BACKUP_DIR}.tar.gz.enc"
    else
        # Create archive for upload
        backup_archive="${BACKUP_DIR}.tar.gz"
        tar -czf "${backup_archive}" -C "$(dirname "${BACKUP_DIR}")" "$(basename "${BACKUP_DIR}")"
    fi

    # Configure AWS CLI
    export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY}"
    export AWS_SECRET_ACCESS_KEY="${S3_SECRET_KEY}"

    local s3_path="s3://${S3_BUCKET}/backups/$(basename "${backup_archive}")"

    if [[ -n "${S3_ENDPOINT}" ]]; then
        aws s3 cp "${backup_archive}" "${s3_path}" --endpoint-url "${S3_ENDPOINT}" 2>>"${LOG_FILE}"
    else
        aws s3 cp "${backup_archive}" "${s3_path}" 2>>"${LOG_FILE}"
    fi

    if [[ $? -eq 0 ]]; then
        log_success "Backup uploaded to S3: ${s3_path}"
    else
        log_error "S3 upload failed"
        return 1
    fi

    return 0
}

# Cleanup old backups
cleanup_old_backups() {
    if [[ "${AUTO_CLEANUP_OLD_BACKUPS}" != "true" ]]; then
        return 0
    fi

    log_info "Cleaning up backups older than ${BACKUP_RETENTION_DAYS} days..."

    local deleted_count=0

    # Find and delete old backups
    find "${BACKUP_ROOT_DIR}" -maxdepth 1 -type d -mtime +${BACKUP_RETENTION_DAYS} | while read -r old_backup; do
        if [[ -d "${old_backup}" ]] && [[ "${old_backup}" != "${BACKUP_ROOT_DIR}" ]]; then
            log_info "Deleting old backup: $(basename "${old_backup}")"
            rm -rf "${old_backup}"
            deleted_count=$((deleted_count + 1))
        fi
    done

    # Cleanup old encrypted backups
    find "${BACKUP_ROOT_DIR}" -maxdepth 1 -type f -name "*.tar.gz.enc" -mtime +${BACKUP_RETENTION_DAYS} -delete

    log_success "Cleaned up ${deleted_count} old backup(s)"

    return 0
}

# Generate backup report
generate_report() {
    log_info "Generating backup report..."

    local report_file="${BACKUP_DIR}/backup_report.txt"

    cat > "${report_file}" <<EOF
================================================================================
MinIO Enterprise Backup Report
================================================================================

Backup Timestamp: ${TIMESTAMP}
Backup Date: $(date)
Backup Location: ${BACKUP_DIR}

Components Backed Up:
  - PostgreSQL Database: ${BACKUP_POSTGRESQL}
  - Redis Data: ${BACKUP_REDIS}
  - MinIO Data Volumes: ${BACKUP_MINIO_DATA}
  - Configuration Files: ${BACKUP_CONFIG_FILES}

Backup Settings:
  - Compression: ${BACKUP_COMPRESSION} (${COMPRESSION_TOOL})
  - Encryption: ${BACKUP_ENCRYPTION}
  - Verification: ${BACKUP_VERIFICATION}
  - Retention: ${BACKUP_RETENTION_DAYS} days

Backup Size:
$(du -sh "${BACKUP_DIR}" | cut -f1) total

Files:
$(ls -lh "${BACKUP_DIR}" 2>/dev/null || echo "No files")

Status: SUCCESS

================================================================================
EOF

    cat "${report_file}" | tee -a "${LOG_FILE}"

    return 0
}

# Main backup function
main() {
    local start_time=$(date +%s)

    log_info "========================================="
    log_info "MinIO Enterprise Backup Started"
    log_info "Timestamp: ${TIMESTAMP}"
    log_info "========================================="

    # Execute backup steps
    check_prerequisites
    create_metadata
    backup_postgresql
    backup_redis
    backup_minio_data
    backup_config_files
    generate_report
    encrypt_backup
    upload_to_s3
    cleanup_old_backups

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_success "========================================="
    log_success "Backup completed successfully!"
    log_success "Duration: ${duration} seconds"
    log_success "Location: ${BACKUP_DIR}"
    log_success "========================================="

    send_notification "SUCCESS" "Backup completed successfully in ${duration} seconds"

    return 0
}

# Run main function
main "$@"
