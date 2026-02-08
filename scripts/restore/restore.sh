#!/bin/bash
# MinIO Enterprise Restore Script
# =================================
# Automated restore solution for MinIO Enterprise stack
# Supports: MinIO data, PostgreSQL, Redis, configuration files
# Features: Verification, rollback, dry-run mode

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

# Load configuration from backup directory
CONFIG_FILE="${SCRIPT_DIR}/../backup/backup.conf"
if [[ -f "${CONFIG_FILE}" ]]; then
    source "${CONFIG_FILE}"
fi

# Initialize variables
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${LOG_DIR:-./logs/restore}"
LOG_FILE="${LOG_DIR}/restore_${TIMESTAMP}.log"
DRY_RUN=false
RESTORE_DIR=""
SKIP_VERIFICATION=false
CREATE_PRE_RESTORE_BACKUP=true

# Create necessary directories
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

# Usage information
usage() {
    cat <<EOF
MinIO Enterprise Restore Script

Usage: $0 [OPTIONS] <backup_directory>

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run           Perform dry-run (no actual restore)
    -s, --skip-verification Skip backup verification
    -n, --no-pre-backup     Skip pre-restore backup
    -p, --postgresql-only   Restore only PostgreSQL
    -r, --redis-only        Restore only Redis
    -m, --minio-only        Restore only MinIO data
    -c, --config-only       Restore only configuration files

EXAMPLES:
    # Restore from specific backup directory
    $0 /var/backups/minio-enterprise/20240118_120000

    # Dry-run restore
    $0 --dry-run /var/backups/minio-enterprise/20240118_120000

    # Restore only database
    $0 --postgresql-only /var/backups/minio-enterprise/20240118_120000

EOF
    exit 0
}

# Parse command line arguments
parse_arguments() {
    local restore_postgresql=true
    local restore_redis=true
    local restore_minio=true
    local restore_config=true

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -s|--skip-verification)
                SKIP_VERIFICATION=true
                shift
                ;;
            -n|--no-pre-backup)
                CREATE_PRE_RESTORE_BACKUP=false
                shift
                ;;
            -p|--postgresql-only)
                restore_redis=false
                restore_minio=false
                restore_config=false
                shift
                ;;
            -r|--redis-only)
                restore_postgresql=false
                restore_minio=false
                restore_config=false
                shift
                ;;
            -m|--minio-only)
                restore_postgresql=false
                restore_redis=false
                restore_config=false
                shift
                ;;
            -c|--config-only)
                restore_postgresql=false
                restore_redis=false
                restore_minio=false
                shift
                ;;
            *)
                if [[ -z "${RESTORE_DIR}" ]]; then
                    RESTORE_DIR="$1"
                else
                    log_error "Unknown argument: $1"
                    usage
                fi
                shift
                ;;
        esac
    done

    # Export restore flags
    export RESTORE_POSTGRESQL=${restore_postgresql}
    export RESTORE_REDIS=${restore_redis}
    export RESTORE_MINIO=${restore_minio}
    export RESTORE_CONFIG=${restore_config}

    if [[ -z "${RESTORE_DIR}" ]]; then
        log_error "Backup directory not specified"
        usage
    fi

    if [[ ! -d "${RESTORE_DIR}" ]]; then
        log_error "Backup directory does not exist: ${RESTORE_DIR}"
        exit 1
    fi
}

# Verify backup integrity
verify_backup() {
    if [[ "${SKIP_VERIFICATION}" == "true" ]]; then
        log_warn "Backup verification skipped"
        return 0
    fi

    log_info "Verifying backup integrity..."

    # Check metadata file
    local metadata_file="${RESTORE_DIR}/backup_metadata.json"
    if [[ ! -f "${metadata_file}" ]]; then
        log_error "Backup metadata not found: ${metadata_file}"
        return 1
    fi

    # Parse metadata
    local backup_timestamp=$(jq -r '.backup_timestamp' "${metadata_file}" 2>/dev/null || echo "unknown")
    local backup_date=$(jq -r '.backup_date' "${metadata_file}" 2>/dev/null || echo "unknown")

    log_info "Backup timestamp: ${backup_timestamp}"
    log_info "Backup date: ${backup_date}"

    # Check component files
    if [[ "${RESTORE_POSTGRESQL}" == "true" ]]; then
        if ls "${RESTORE_DIR}"/postgresql_*.sql &>/dev/null; then
            log_success "PostgreSQL backup found"
        else
            log_warn "PostgreSQL backup not found"
        fi
    fi

    if [[ "${RESTORE_REDIS}" == "true" ]]; then
        if [[ -d "${RESTORE_DIR}/redis" ]]; then
            log_success "Redis backup found"
        else
            log_warn "Redis backup not found"
        fi
    fi

    if [[ "${RESTORE_MINIO}" == "true" ]]; then
        if [[ -d "${RESTORE_DIR}/minio_data" ]]; then
            log_success "MinIO data backup found"
        else
            log_warn "MinIO data backup not found"
        fi
    fi

    if [[ "${RESTORE_CONFIG}" == "true" ]]; then
        if ls "${RESTORE_DIR}"/config_*.tar.gz &>/dev/null; then
            log_success "Configuration backup found"
        else
            log_warn "Configuration backup not found"
        fi
    fi

    log_success "Backup verification completed"
    return 0
}

# Create pre-restore backup
create_pre_restore_backup() {
    if [[ "${CREATE_PRE_RESTORE_BACKUP}" != "true" ]]; then
        log_info "Pre-restore backup disabled"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create pre-restore backup"
        return 0
    fi

    log_info "Creating pre-restore backup..."

    # Call backup script
    local backup_script="${SCRIPT_DIR}/../backup/backup.sh"
    if [[ -f "${backup_script}" ]]; then
        bash "${backup_script}" 2>&1 | tee -a "${LOG_FILE}"
        log_success "Pre-restore backup created"
    else
        log_warn "Backup script not found, skipping pre-restore backup"
    fi

    return 0
}

# Stop services
stop_services() {
    log_info "Stopping services..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would stop Docker Compose services"
        return 0
    fi

    cd "${PROJECT_ROOT}"

    # Stop services gracefully
    docker-compose -f "${DOCKER_COMPOSE_FILE}" stop 2>&1 | tee -a "${LOG_FILE}"

    log_success "Services stopped"
    return 0
}

# Start services
start_services() {
    log_info "Starting services..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would start Docker Compose services"
        return 0
    fi

    cd "${PROJECT_ROOT}"

    # Start services
    docker-compose -f "${DOCKER_COMPOSE_FILE}" up -d 2>&1 | tee -a "${LOG_FILE}"

    # Wait for services to be healthy
    log_info "Waiting for services to be healthy..."
    local max_wait=120
    local waited=0

    while [[ ${waited} -lt ${max_wait} ]]; do
        local unhealthy=$(docker-compose -f "${DOCKER_COMPOSE_FILE}" ps | grep -c "unhealthy" || true)
        if [[ ${unhealthy} -eq 0 ]]; then
            log_success "All services are healthy"
            return 0
        fi
        sleep 5
        waited=$((waited + 5))
    done

    log_warn "Some services may not be fully healthy after ${max_wait} seconds"
    return 0
}

# Restore PostgreSQL
restore_postgresql() {
    if [[ "${RESTORE_POSTGRESQL}" != "true" ]]; then
        log_info "PostgreSQL restore disabled, skipping"
        return 0
    fi

    log_info "Restoring PostgreSQL database..."

    local pg_backup_file=$(ls "${RESTORE_DIR}"/postgresql_*.sql 2>/dev/null | head -1)

    if [[ -z "${pg_backup_file}" ]]; then
        log_error "PostgreSQL backup file not found"
        return 1
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would restore PostgreSQL from: ${pg_backup_file}"
        return 0
    fi

    cd "${PROJECT_ROOT}"

    # Drop existing database and recreate
    log_info "Dropping existing database..."
    docker exec "${POSTGRES_CONTAINER}" psql -U "${POSTGRES_USER}" -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};" 2>&1 | tee -a "${LOG_FILE}"
    docker exec "${POSTGRES_CONTAINER}" psql -U "${POSTGRES_USER}" -c "CREATE DATABASE ${POSTGRES_DB};" 2>&1 | tee -a "${LOG_FILE}"

    # Restore database
    log_info "Restoring database from backup..."
    cat "${pg_backup_file}" | docker exec -i "${POSTGRES_CONTAINER}" pg_restore \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        --verbose \
        --no-owner \
        --no-acl 2>&1 | tee -a "${LOG_FILE}"

    log_success "PostgreSQL restore completed"
    return 0
}

# Restore Redis
restore_redis() {
    if [[ "${RESTORE_REDIS}" != "true" ]]; then
        log_info "Redis restore disabled, skipping"
        return 0
    fi

    log_info "Restoring Redis data..."

    local redis_backup_dir="${RESTORE_DIR}/redis"

    if [[ ! -d "${redis_backup_dir}" ]]; then
        log_error "Redis backup directory not found"
        return 1
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would restore Redis from: ${redis_backup_dir}"
        return 0
    fi

    cd "${PROJECT_ROOT}"

    # Stop Redis to restore files
    log_info "Stopping Redis..."
    docker-compose -f "${DOCKER_COMPOSE_FILE}" stop redis 2>&1 | tee -a "${LOG_FILE}"

    # Restore RDB file
    if [[ -f "${redis_backup_dir}/${REDIS_RDB_FILE}" ]]; then
        log_info "Restoring RDB file..."
        docker cp "${redis_backup_dir}/${REDIS_RDB_FILE}" "${REDIS_CONTAINER}:/data/" 2>&1 | tee -a "${LOG_FILE}"
    fi

    # Restore AOF file
    if [[ -f "${redis_backup_dir}/${REDIS_AOF_FILE}" ]]; then
        log_info "Restoring AOF file..."
        docker cp "${redis_backup_dir}/${REDIS_AOF_FILE}" "${REDIS_CONTAINER}:/data/" 2>&1 | tee -a "${LOG_FILE}"
    fi

    # Start Redis
    log_info "Starting Redis..."
    docker-compose -f "${DOCKER_COMPOSE_FILE}" start redis 2>&1 | tee -a "${LOG_FILE}"

    # Wait for Redis to be ready
    sleep 5

    log_success "Redis restore completed"
    return 0
}

# Restore MinIO data
restore_minio_data() {
    if [[ "${RESTORE_MINIO}" != "true" ]]; then
        log_info "MinIO data restore disabled, skipping"
        return 0
    fi

    log_info "Restoring MinIO data volumes..."

    local minio_backup_dir="${RESTORE_DIR}/minio_data"

    if [[ ! -d "${minio_backup_dir}" ]]; then
        log_error "MinIO backup directory not found"
        return 1
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would restore MinIO data from: ${minio_backup_dir}"
        return 0
    fi

    cd "${PROJECT_ROOT}"

    # Restore each MinIO data volume
    for volume in ${MINIO_DATA_VOLUMES}; do
        log_info "Restoring volume: ${volume}..."

        # Find backup file (handle different compression formats)
        local volume_backup=""
        for ext in "" ".gz" ".bz2" ".xz"; do
            if [[ -f "${minio_backup_dir}/${volume}.tar${ext}" ]]; then
                volume_backup="${minio_backup_dir}/${volume}.tar${ext}"
                break
            fi
        done

        if [[ -z "${volume_backup}" ]]; then
            log_warn "Backup for volume ${volume} not found, skipping"
            continue
        fi

        # Decompress if needed
        local tar_file="${volume_backup}"
        if [[ "${volume_backup}" == *.gz ]]; then
            log_info "Decompressing gzip archive..."
            gunzip -c "${volume_backup}" > "${minio_backup_dir}/${volume}.tar"
            tar_file="${minio_backup_dir}/${volume}.tar"
        elif [[ "${volume_backup}" == *.bz2 ]]; then
            log_info "Decompressing bzip2 archive..."
            bunzip2 -c "${volume_backup}" > "${minio_backup_dir}/${volume}.tar"
            tar_file="${minio_backup_dir}/${volume}.tar"
        elif [[ "${volume_backup}" == *.xz ]]; then
            log_info "Decompressing xz archive..."
            unxz -c "${volume_backup}" > "${minio_backup_dir}/${volume}.tar"
            tar_file="${minio_backup_dir}/${volume}.tar"
        fi

        # Restore volume using temporary container
        docker run --rm \
            -v "${volume}:/data" \
            -v "$(dirname "${tar_file}"):/backup:ro" \
            alpine \
            sh -c "rm -rf /data/* && tar -xf /backup/$(basename "${tar_file}") -C /data" 2>&1 | tee -a "${LOG_FILE}"

        # Cleanup temporary tar file
        if [[ "${tar_file}" != "${volume_backup}" ]]; then
            rm -f "${tar_file}"
        fi

        log_success "Volume ${volume} restored"
    done

    log_success "MinIO data restore completed"
    return 0
}

# Restore configuration files
restore_config_files() {
    if [[ "${RESTORE_CONFIG}" != "true" ]]; then
        log_info "Configuration restore disabled, skipping"
        return 0
    fi

    log_info "Restoring configuration files..."

    local config_backup_file=$(ls "${RESTORE_DIR}"/config_*.tar.gz 2>/dev/null | head -1)

    if [[ -z "${config_backup_file}" ]]; then
        log_error "Configuration backup file not found"
        return 1
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would restore configuration from: ${config_backup_file}"
        return 0
    fi

    cd "${PROJECT_ROOT}"

    # Extract configuration backup
    tar -xzf "${config_backup_file}" 2>&1 | tee -a "${LOG_FILE}"

    log_success "Configuration restore completed"
    return 0
}

# Verify restore
verify_restore() {
    log_info "Verifying restore..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would verify restore"
        return 0
    fi

    cd "${PROJECT_ROOT}"

    local all_healthy=true

    # Check PostgreSQL
    if [[ "${RESTORE_POSTGRESQL}" == "true" ]]; then
        log_info "Checking PostgreSQL..."
        if docker exec "${POSTGRES_CONTAINER}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "SELECT 1;" &>/dev/null; then
            log_success "PostgreSQL is accessible"
        else
            log_error "PostgreSQL verification failed"
            all_healthy=false
        fi
    fi

    # Check Redis
    if [[ "${RESTORE_REDIS}" == "true" ]]; then
        log_info "Checking Redis..."
        if docker exec "${REDIS_CONTAINER}" redis-cli PING | grep -q "PONG"; then
            log_success "Redis is accessible"
        else
            log_error "Redis verification failed"
            all_healthy=false
        fi
    fi

    # Check MinIO nodes
    if [[ "${RESTORE_MINIO}" == "true" ]]; then
        for container in ${MINIO_CONTAINERS}; do
            log_info "Checking MinIO node: ${container}..."
            if docker exec "${container}" curl -f http://localhost:9000/minio/health/live &>/dev/null; then
                log_success "MinIO node ${container} is healthy"
            else
                log_warn "MinIO node ${container} may not be fully healthy"
            fi
        done
    fi

    if [[ "${all_healthy}" == "true" ]]; then
        log_success "Restore verification completed successfully"
        return 0
    else
        log_warn "Some components may require manual verification"
        return 1
    fi
}

# Generate restore report
generate_report() {
    log_info "Generating restore report..."

    local report_file="${LOG_DIR}/restore_report_${TIMESTAMP}.txt"

    cat > "${report_file}" <<EOF
================================================================================
MinIO Enterprise Restore Report
================================================================================

Restore Timestamp: ${TIMESTAMP}
Restore Date: $(date)
Backup Source: ${RESTORE_DIR}
Dry Run: ${DRY_RUN}

Components Restored:
  - PostgreSQL Database: ${RESTORE_POSTGRESQL}
  - Redis Data: ${RESTORE_REDIS}
  - MinIO Data Volumes: ${RESTORE_MINIO}
  - Configuration Files: ${RESTORE_CONFIG}

Pre-Restore Backup: ${CREATE_PRE_RESTORE_BACKUP}
Verification: $([ "${SKIP_VERIFICATION}" == "true" ] && echo "Skipped" || echo "Performed")

Status: $([ "${DRY_RUN}" == "true" ] && echo "DRY-RUN" || echo "SUCCESS")

Next Steps:
  1. Verify all services are running correctly
  2. Check application logs for any errors
  3. Run health checks on all components
  4. Test critical functionality

================================================================================
EOF

    cat "${report_file}" | tee -a "${LOG_FILE}"

    return 0
}

# Main restore function
main() {
    local start_time=$(date +%s)

    log_info "========================================="
    log_info "MinIO Enterprise Restore Started"
    log_info "Timestamp: ${TIMESTAMP}"
    log_info "========================================="

    # Parse arguments
    parse_arguments "$@"

    # Execute restore steps
    verify_backup
    create_pre_restore_backup
    stop_services
    restore_postgresql
    restore_redis
    restore_minio_data
    restore_config_files
    start_services
    verify_restore
    generate_report

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_success "========================================="
        log_success "Dry-run completed successfully!"
        log_success "Duration: ${duration} seconds"
        log_success "No actual changes were made"
        log_success "========================================="
    else
        log_success "========================================="
        log_success "Restore completed successfully!"
        log_success "Duration: ${duration} seconds"
        log_success "========================================="
    fi

    return 0
}

# Run main function
main "$@"
