#!/bin/bash

###############################################################################
# MinIO Enterprise - Restore Script
#
# Purpose: Automated restore of MinIO data, PostgreSQL, Redis, and configurations
# Usage: ./restore.sh [OPTIONS]
#
# Options:
#   -b, --backup <backup_id>      Backup ID to restore (timestamp format)
#   -s, --source <path>           Backup source directory
#   -c, --components <list>       Components to restore (comma-separated)
#                                 Options: postgresql,redis,minio-data,minio-config,all
#   -d, --decrypt                 Decrypt encrypted backup
#   -k, --key <path>             GPG private key for decryption
#   --dry-run                    Show what would be restored without executing
#   --force                      Force restore without confirmation
#   -h, --help                   Show this help message
#
# Environment Variables:
#   BACKUP_SOURCE                Default backup location
#   POSTGRES_HOST                PostgreSQL host (default: localhost)
#   POSTGRES_PORT                PostgreSQL port (default: 5432)
#   POSTGRES_USER                PostgreSQL user (default: minio)
#   POSTGRES_DB                  PostgreSQL database (default: minio)
#   REDIS_HOST                   Redis host (default: localhost)
#   REDIS_PORT                   Redis port (default: 6379)
#   MINIO_DATA_DIR               MinIO data directory (default: /data)
#   MINIO_CONFIG_DIR             MinIO config directory (default: /etc/minio)
###############################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
BACKUP_SOURCE="${BACKUP_SOURCE:-/var/backups/minio}"
BACKUP_ID=""
COMPONENTS_TO_RESTORE="all"
DECRYPT_BACKUP="false"
GPG_KEY_PATH=""
DRY_RUN="false"
FORCE_RESTORE="false"

# Database configuration
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-minio}"
POSTGRES_DB="${POSTGRES_DB:-minio}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"

REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

# MinIO configuration
MINIO_DATA_DIR="${MINIO_DATA_DIR:-/data}"
MINIO_CONFIG_DIR="${MINIO_CONFIG_DIR:-/etc/minio}"

# Timestamp for restore log
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="/tmp/restore_${TIMESTAMP}.log"

# Function: Print colored output
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Function: Show usage
show_usage() {
    cat << EOF
MinIO Enterprise - Restore Script

Usage: $0 [OPTIONS]

Options:
  -b, --backup <backup_id>      Backup ID to restore (timestamp format)
  -s, --source <path>           Backup source directory
  -c, --components <list>       Components to restore (comma-separated)
                                Options: postgresql,redis,minio-data,minio-config,all
  -d, --decrypt                 Decrypt encrypted backup
  -k, --key <path>             GPG private key for decryption
  --dry-run                    Show what would be restored without executing
  --force                      Force restore without confirmation
  -h, --help                   Show this help message

Examples:
  # Restore all components from backup
  $0 --backup 20240118_120000

  # Restore only PostgreSQL database
  $0 --backup 20240118_120000 --components postgresql

  # Restore with decryption
  $0 --backup 20240118_120000 --decrypt --key /path/to/key.gpg

  # Dry run to preview restore
  $0 --backup 20240118_120000 --dry-run
EOF
}

# Function: Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--backup)
                BACKUP_ID="$2"
                shift 2
                ;;
            -s|--source)
                BACKUP_SOURCE="$2"
                shift 2
                ;;
            -c|--components)
                COMPONENTS_TO_RESTORE="$2"
                shift 2
                ;;
            -d|--decrypt)
                DECRYPT_BACKUP="true"
                shift
                ;;
            -k|--key)
                GPG_KEY_PATH="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --force)
                FORCE_RESTORE="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "${BACKUP_ID}" ]]; then
        log_error "Backup ID is required. Use --backup <backup_id>"
        show_usage
        exit 1
    fi
}

# Function: Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check required commands
    local required_commands=("psql" "redis-cli" "tar" "gunzip")

    if [[ "${DECRYPT_BACKUP}" == "true" ]]; then
        required_commands+=("gpg")
    fi

    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" &> /dev/null; then
            log_error "Required command not found: ${cmd}"
            exit 1
        fi
    done

    # Check decryption key if decryption is enabled
    if [[ "${DECRYPT_BACKUP}" == "true" ]] && [[ -z "${GPG_KEY_PATH}" ]]; then
        log_error "Decryption enabled but no GPG key path provided"
        exit 1
    fi

    if [[ "${DECRYPT_BACKUP}" == "true" ]] && [[ ! -f "${GPG_KEY_PATH}" ]]; then
        log_error "GPG key file not found: ${GPG_KEY_PATH}"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Function: Validate backup
validate_backup() {
    log_info "Validating backup..."

    local backup_dir="${BACKUP_SOURCE}/${BACKUP_ID}"

    if [[ ! -d "${backup_dir}" ]]; then
        log_error "Backup directory not found: ${backup_dir}"
        exit 1
    fi

    # Check metadata file
    local metadata_file="${backup_dir}/metadata/backup_metadata.json"
    if [[ ! -f "${metadata_file}" ]]; then
        log_error "Backup metadata not found: ${metadata_file}"
        exit 1
    fi

    # Read and display backup metadata
    log_info "Backup metadata:"
    cat "${metadata_file}" | tee -a "${LOG_FILE}"

    log_success "Backup validation passed"
}

# Function: Confirm restore
confirm_restore() {
    if [[ "${FORCE_RESTORE}" == "true" ]] || [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi

    echo ""
    echo -e "${YELLOW}WARNING: This will restore the following components:${NC}"
    echo "  ${COMPONENTS_TO_RESTORE}"
    echo ""
    echo -e "${RED}CAUTION: This may overwrite existing data!${NC}"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Restore cancelled by user"
        exit 0
    fi
}

# Function: Decrypt backup files
decrypt_backup_files() {
    if [[ "${DECRYPT_BACKUP}" != "true" ]]; then
        return 0
    fi

    log_info "Decrypting backup files..."

    local backup_dir="${BACKUP_SOURCE}/${BACKUP_ID}"

    # Find and decrypt all .gpg files
    find "${backup_dir}" -type f -name "*.gpg" | while read -r encrypted_file; do
        local decrypted_file="${encrypted_file%.gpg}"
        log_info "Decrypting: $(basename "${encrypted_file}")"

        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would decrypt: ${encrypted_file}"
        else
            gpg --output "${decrypted_file}" --decrypt --recipient-file "${GPG_KEY_PATH}" "${encrypted_file}" 2>> "${LOG_FILE}"

            if [[ $? -eq 0 ]]; then
                log_success "Decrypted: $(basename "${decrypted_file}")"
            else
                log_error "Failed to decrypt: $(basename "${encrypted_file}")"
                return 1
            fi
        fi
    done
}

# Function: Check if component should be restored
should_restore_component() {
    local component="$1"

    if [[ "${COMPONENTS_TO_RESTORE}" == "all" ]]; then
        return 0
    fi

    if [[ ",${COMPONENTS_TO_RESTORE}," == *",${component},"* ]]; then
        return 0
    fi

    return 1
}

# Function: Restore PostgreSQL
restore_postgresql() {
    if ! should_restore_component "postgresql"; then
        log_info "Skipping PostgreSQL restore"
        return 0
    fi

    log_info "Restoring PostgreSQL database: ${POSTGRES_DB}"

    local backup_dir="${BACKUP_SOURCE}/${BACKUP_ID}"
    local sql_file=$(find "${backup_dir}/postgresql" -name "*.sql" -o -name "*.sql.gz" | head -1)

    if [[ -z "${sql_file}" ]]; then
        log_warning "PostgreSQL backup file not found"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would restore PostgreSQL from: ${sql_file}"
        return 0
    fi

    # Decompress if needed
    if [[ "${sql_file}" == *.gz ]]; then
        log_info "Decompressing PostgreSQL backup..."
        gunzip -k "${sql_file}"
        sql_file="${sql_file%.gz}"
    fi

    # Set password if provided
    if [[ -n "${POSTGRES_PASSWORD}" ]]; then
        export PGPASSWORD="${POSTGRES_PASSWORD}"
    fi

    # Drop existing database and recreate
    log_warning "Dropping existing database: ${POSTGRES_DB}"
    psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};" postgres 2>> "${LOG_FILE}"
    psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -c "CREATE DATABASE ${POSTGRES_DB};" postgres 2>> "${LOG_FILE}"

    # Restore database
    log_info "Restoring database from backup..."
    if psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -f "${sql_file}" 2>> "${LOG_FILE}"; then
        log_success "PostgreSQL restore completed"
    else
        log_error "PostgreSQL restore failed"
        return 1
    fi

    # Unset password
    unset PGPASSWORD

    # Clean up decompressed file
    if [[ -f "${sql_file}" ]] && [[ "${sql_file}" != *.gz ]]; then
        rm -f "${sql_file}"
    fi
}

# Function: Restore Redis
restore_redis() {
    if ! should_restore_component "redis"; then
        log_info "Skipping Redis restore"
        return 0
    fi

    log_info "Restoring Redis data..."

    local backup_dir="${BACKUP_SOURCE}/${BACKUP_ID}"
    local rdb_file=$(find "${backup_dir}/redis" -name "*.rdb" -o -name "*.rdb.gz" | head -1)

    if [[ -z "${rdb_file}" ]]; then
        log_warning "Redis backup file not found"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would restore Redis from: ${rdb_file}"
        return 0
    fi

    # Decompress if needed
    if [[ "${rdb_file}" == *.gz ]]; then
        log_info "Decompressing Redis backup..."
        gunzip -k "${rdb_file}"
        rdb_file="${rdb_file%.gz}"
    fi

    # Stop Redis temporarily
    log_warning "Stopping Redis service..."
    if command -v systemctl &> /dev/null; then
        sudo systemctl stop redis 2>> "${LOG_FILE}" || log_warning "Could not stop Redis via systemctl"
    fi

    # Copy RDB file
    local redis_rdb_path="/var/lib/redis/dump.rdb"
    log_info "Copying Redis backup to: ${redis_rdb_path}"
    sudo cp "${rdb_file}" "${redis_rdb_path}" 2>> "${LOG_FILE}"
    sudo chown redis:redis "${redis_rdb_path}" 2>> "${LOG_FILE}" || true

    # Start Redis
    log_info "Starting Redis service..."
    if command -v systemctl &> /dev/null; then
        sudo systemctl start redis 2>> "${LOG_FILE}" || log_warning "Could not start Redis via systemctl"
    fi

    # Wait for Redis to start
    sleep 3

    # Verify Redis is running
    if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" PING &> /dev/null; then
        log_success "Redis restore completed"
    else
        log_error "Redis restore failed - service not responding"
        return 1
    fi

    # Clean up decompressed file
    if [[ -f "${rdb_file}" ]] && [[ "${rdb_file}" != *.gz ]]; then
        rm -f "${rdb_file}"
    fi
}

# Function: Restore MinIO data
restore_minio_data() {
    if ! should_restore_component "minio-data"; then
        log_info "Skipping MinIO data restore"
        return 0
    fi

    log_info "Restoring MinIO data directory..."

    local backup_dir="${BACKUP_SOURCE}/${BACKUP_ID}"
    local tar_file=$(find "${backup_dir}/minio-data" -name "*.tar.gz" | head -1)

    if [[ -z "${tar_file}" ]]; then
        log_warning "MinIO data backup file not found"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would restore MinIO data from: ${tar_file}"
        return 0
    fi

    # Backup existing data
    if [[ -d "${MINIO_DATA_DIR}" ]]; then
        local backup_suffix=$(date +"%Y%m%d_%H%M%S")
        log_warning "Backing up existing MinIO data to: ${MINIO_DATA_DIR}.backup_${backup_suffix}"
        sudo mv "${MINIO_DATA_DIR}" "${MINIO_DATA_DIR}.backup_${backup_suffix}" 2>> "${LOG_FILE}"
    fi

    # Extract tar archive
    log_info "Extracting MinIO data..."
    sudo mkdir -p "$(dirname "${MINIO_DATA_DIR}")"
    if sudo tar -xzf "${tar_file}" -C "$(dirname "${MINIO_DATA_DIR}")" 2>> "${LOG_FILE}"; then
        log_success "MinIO data restore completed"
    else
        log_error "MinIO data restore failed"
        return 1
    fi
}

# Function: Restore MinIO configuration
restore_minio_config() {
    if ! should_restore_component "minio-config"; then
        log_info "Skipping MinIO configuration restore"
        return 0
    fi

    log_info "Restoring MinIO configuration files..."

    local backup_dir="${BACKUP_SOURCE}/${BACKUP_ID}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would restore MinIO configuration"
        return 0
    fi

    # Restore .env file
    local env_file=$(find "${backup_dir}/minio-config" -name ".env_*" | head -1)
    if [[ -n "${env_file}" ]]; then
        log_info "Restoring .env file..."
        cp "${env_file}" "$(dirname "$0")/../.env"
        log_success "Restored .env file"
    fi

    # Restore configuration directory
    local config_tar=$(find "${backup_dir}/minio-config" -name "config_*.tar.gz" | head -1)
    if [[ -n "${config_tar}" ]]; then
        log_info "Restoring configuration directory..."
        sudo mkdir -p "$(dirname "${MINIO_CONFIG_DIR}")"
        sudo tar -xzf "${config_tar}" -C "$(dirname "${MINIO_CONFIG_DIR}")" 2>> "${LOG_FILE}"
        log_success "Restored configuration directory"
    fi

    # Restore Docker Compose files
    local compose_tar=$(find "${backup_dir}/minio-config" -name "docker_compose_*.tar.gz" | head -1)
    if [[ -n "${compose_tar}" ]]; then
        log_info "Restoring Docker Compose configurations..."
        local compose_dir="$(dirname "$0")/../deployments/docker"
        mkdir -p "$(dirname "${compose_dir}")"
        tar -xzf "${compose_tar}" -C "$(dirname "${compose_dir}")" 2>> "${LOG_FILE}"
        log_success "Restored Docker Compose configurations"
    fi
}

# Function: Verify restore
verify_restore() {
    log_info "Verifying restore..."

    local verification_passed=true

    # Verify PostgreSQL
    if should_restore_component "postgresql"; then
        if [[ -n "${POSTGRES_PASSWORD}" ]]; then
            export PGPASSWORD="${POSTGRES_PASSWORD}"
        fi

        if psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "\dt" &> /dev/null; then
            log_success "PostgreSQL database is accessible"
        else
            log_error "PostgreSQL database verification failed"
            verification_passed=false
        fi

        unset PGPASSWORD
    fi

    # Verify Redis
    if should_restore_component "redis"; then
        if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" PING &> /dev/null; then
            log_success "Redis is responding"
        else
            log_error "Redis verification failed"
            verification_passed=false
        fi
    fi

    # Verify MinIO data
    if should_restore_component "minio-data"; then
        if [[ -d "${MINIO_DATA_DIR}" ]]; then
            log_success "MinIO data directory exists"
        else
            log_error "MinIO data directory verification failed"
            verification_passed=false
        fi
    fi

    if [[ "${verification_passed}" == "true" ]]; then
        log_success "Restore verification passed"
    else
        log_error "Restore verification failed"
        return 1
    fi
}

# Function: Generate restore summary
generate_restore_summary() {
    log_info "Generating restore summary..."

    local summary_file="/tmp/restore_summary_${TIMESTAMP}.txt"

    cat > "${summary_file}" << EOF
MinIO Enterprise - Restore Summary
===================================

Backup ID: ${BACKUP_ID}
Restore Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Components Restored: ${COMPONENTS_TO_RESTORE}
Dry Run: ${DRY_RUN}

Backup Source:
--------------
${BACKUP_SOURCE}/${BACKUP_ID}

Components:
-----------
PostgreSQL: $(should_restore_component "postgresql" && echo "Restored" || echo "Skipped")
Redis: $(should_restore_component "redis" && echo "Restored" || echo "Skipped")
MinIO Data: $(should_restore_component "minio-data" && echo "Restored" || echo "Skipped")
MinIO Config: $(should_restore_component "minio-config" && echo "Restored" || echo "Skipped")

Log File:
---------
${LOG_FILE}

Next Steps:
-----------
1. Verify services are running: docker-compose ps
2. Check MinIO health: curl http://localhost:9000/health
3. Test MinIO operations
4. Monitor logs for any errors

EOF

    log_success "Restore summary generated: ${summary_file}"

    # Display summary
    cat "${summary_file}"
}

# Main execution
main() {
    echo "========================================="
    echo "MinIO Enterprise - Restore Script"
    echo "========================================="
    echo ""

    # Parse arguments
    parse_arguments "$@"

    log_info "Starting restore process..."
    log_info "Backup ID: ${BACKUP_ID}"
    log_info "Components: ${COMPONENTS_TO_RESTORE}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi

    # Execute restore steps
    check_prerequisites
    validate_backup
    confirm_restore

    # Decrypt if needed
    decrypt_backup_files

    # Restore components
    restore_postgresql || log_warning "PostgreSQL restore had issues"
    restore_redis || log_warning "Redis restore had issues"
    restore_minio_data || log_warning "MinIO data restore had issues"
    restore_minio_config || log_warning "MinIO config restore had issues"

    # Verify restore
    if [[ "${DRY_RUN}" != "true" ]]; then
        verify_restore || log_warning "Restore verification had issues"
    fi

    # Generate summary
    generate_restore_summary

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Dry run completed - no changes were made"
    else
        log_success "Restore process completed successfully!"
    fi

    log_info "Log file: ${LOG_FILE}"

    echo ""
    echo "========================================="
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "Dry run completed!"
    else
        echo "Restore completed successfully!"
    fi
    echo "========================================="
}

# Run main function
main "$@"
