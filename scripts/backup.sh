#!/bin/bash

###############################################################################
# MinIO Enterprise - Backup Script
#
# Purpose: Automated backup of MinIO data, PostgreSQL, Redis, and configurations
# Usage: ./backup.sh [OPTIONS]
#
# Options:
#   -t, --type <full|incremental>  Backup type (default: full)
#   -d, --destination <path>       Backup destination directory
#   -c, --compress                 Enable compression (gzip)
#   -e, --encrypt                  Enable encryption (GPG)
#   -k, --key <path>              GPG key for encryption
#   -r, --retention <days>        Retention period in days (default: 30)
#   -v, --verify                  Verify backup after creation
#   -h, --help                    Show this help message
#
# Environment Variables:
#   BACKUP_DESTINATION           Default backup location
#   BACKUP_RETENTION_DAYS        Default retention period
#   BACKUP_COMPRESSION_ENABLED   Enable/disable compression (true/false)
#   BACKUP_ENCRYPTION_ENABLED    Enable/disable encryption (true/false)
#   BACKUP_GPG_KEY_PATH          Path to GPG public key
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
BACKUP_TYPE="${BACKUP_TYPE:-full}"
BACKUP_DESTINATION="${BACKUP_DESTINATION:-/var/backups/minio}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_COMPRESSION_ENABLED="${BACKUP_COMPRESSION_ENABLED:-true}"
BACKUP_ENCRYPTION_ENABLED="${BACKUP_ENCRYPTION_ENABLED:-false}"
BACKUP_GPG_KEY_PATH="${BACKUP_GPG_KEY_PATH:-}"
VERIFY_BACKUP="${VERIFY_BACKUP:-false}"

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

# Timestamp for backup
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="${BACKUP_DESTINATION}/${TIMESTAMP}"
LOG_FILE="${BACKUP_DIR}/backup.log"

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
MinIO Enterprise - Backup Script

Usage: $0 [OPTIONS]

Options:
  -t, --type <full|incremental>  Backup type (default: full)
  -d, --destination <path>       Backup destination directory
  -c, --compress                 Enable compression (gzip)
  -e, --encrypt                  Enable encryption (GPG)
  -k, --key <path>              GPG key for encryption
  -r, --retention <days>        Retention period in days (default: 30)
  -v, --verify                  Verify backup after creation
  -h, --help                    Show this help message

Environment Variables:
  BACKUP_DESTINATION           Default backup location
  BACKUP_RETENTION_DAYS        Default retention period
  BACKUP_COMPRESSION_ENABLED   Enable/disable compression (true/false)
  BACKUP_ENCRYPTION_ENABLED    Enable/disable encryption (true/false)
  BACKUP_GPG_KEY_PATH          Path to GPG public key

Examples:
  # Full backup with compression
  $0 --type full --compress

  # Incremental backup with encryption
  $0 --type incremental --encrypt --key /path/to/key.gpg

  # Full backup with verification
  $0 --type full --compress --verify
EOF
}

# Function: Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                BACKUP_TYPE="$2"
                shift 2
                ;;
            -d|--destination)
                BACKUP_DESTINATION="$2"
                shift 2
                ;;
            -c|--compress)
                BACKUP_COMPRESSION_ENABLED="true"
                shift
                ;;
            -e|--encrypt)
                BACKUP_ENCRYPTION_ENABLED="true"
                shift
                ;;
            -k|--key)
                BACKUP_GPG_KEY_PATH="$2"
                shift 2
                ;;
            -r|--retention)
                BACKUP_RETENTION_DAYS="$2"
                shift 2
                ;;
            -v|--verify)
                VERIFY_BACKUP="true"
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
}

# Function: Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check required commands
    local required_commands=("pg_dump" "redis-cli" "tar")

    if [[ "${BACKUP_COMPRESSION_ENABLED}" == "true" ]]; then
        required_commands+=("gzip")
    fi

    if [[ "${BACKUP_ENCRYPTION_ENABLED}" == "true" ]]; then
        required_commands+=("gpg")
    fi

    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" &> /dev/null; then
            log_error "Required command not found: ${cmd}"
            exit 1
        fi
    done

    # Check encryption key if encryption is enabled
    if [[ "${BACKUP_ENCRYPTION_ENABLED}" == "true" ]] && [[ -z "${BACKUP_GPG_KEY_PATH}" ]]; then
        log_error "Encryption enabled but no GPG key path provided"
        exit 1
    fi

    if [[ "${BACKUP_ENCRYPTION_ENABLED}" == "true" ]] && [[ ! -f "${BACKUP_GPG_KEY_PATH}" ]]; then
        log_error "GPG key file not found: ${BACKUP_GPG_KEY_PATH}"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Function: Create backup directory
create_backup_directory() {
    log_info "Creating backup directory: ${BACKUP_DIR}"

    mkdir -p "${BACKUP_DIR}"

    # Create subdirectories
    mkdir -p "${BACKUP_DIR}/postgresql"
    mkdir -p "${BACKUP_DIR}/redis"
    mkdir -p "${BACKUP_DIR}/minio-data"
    mkdir -p "${BACKUP_DIR}/minio-config"
    mkdir -p "${BACKUP_DIR}/metadata"

    log_success "Backup directory created"
}

# Function: Backup PostgreSQL
backup_postgresql() {
    log_info "Backing up PostgreSQL database: ${POSTGRES_DB}"

    local output_file="${BACKUP_DIR}/postgresql/${POSTGRES_DB}_${TIMESTAMP}.sql"

    # Set password if provided
    if [[ -n "${POSTGRES_PASSWORD}" ]]; then
        export PGPASSWORD="${POSTGRES_PASSWORD}"
    fi

    # Perform backup
    if pg_dump -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" -F p -f "${output_file}" 2>> "${LOG_FILE}"; then

        # Compress if enabled
        if [[ "${BACKUP_COMPRESSION_ENABLED}" == "true" ]]; then
            log_info "Compressing PostgreSQL backup..."
            gzip "${output_file}"
            output_file="${output_file}.gz"
        fi

        local size=$(du -h "${output_file}" | cut -f1)
        log_success "PostgreSQL backup completed: ${output_file} (${size})"
    else
        log_error "PostgreSQL backup failed"
        return 1
    fi

    # Unset password
    unset PGPASSWORD
}

# Function: Backup Redis
backup_redis() {
    log_info "Backing up Redis data..."

    local output_file="${BACKUP_DIR}/redis/redis_${TIMESTAMP}.rdb"

    # Trigger Redis save
    if [[ -n "${REDIS_PASSWORD}" ]]; then
        redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" -a "${REDIS_PASSWORD}" \
            --no-auth-warning BGSAVE 2>> "${LOG_FILE}"
    else
        redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" BGSAVE 2>> "${LOG_FILE}"
    fi

    # Wait for save to complete
    sleep 5

    # Copy RDB file
    local redis_rdb_path="/var/lib/redis/dump.rdb"
    if [[ -f "${redis_rdb_path}" ]]; then
        cp "${redis_rdb_path}" "${output_file}"

        # Compress if enabled
        if [[ "${BACKUP_COMPRESSION_ENABLED}" == "true" ]]; then
            log_info "Compressing Redis backup..."
            gzip "${output_file}"
            output_file="${output_file}.gz"
        fi

        local size=$(du -h "${output_file}" | cut -f1)
        log_success "Redis backup completed: ${output_file} (${size})"
    else
        log_warning "Redis RDB file not found, skipping Redis backup"
    fi
}

# Function: Backup MinIO data
backup_minio_data() {
    log_info "Backing up MinIO data directory..."

    if [[ ! -d "${MINIO_DATA_DIR}" ]]; then
        log_warning "MinIO data directory not found: ${MINIO_DATA_DIR}, skipping"
        return 0
    fi

    local output_file="${BACKUP_DIR}/minio-data/minio_data_${TIMESTAMP}.tar"

    # Create tar archive
    if tar -czf "${output_file}.gz" -C "$(dirname "${MINIO_DATA_DIR}")" \
        "$(basename "${MINIO_DATA_DIR}")" 2>> "${LOG_FILE}"; then

        local size=$(du -h "${output_file}.gz" | cut -f1)
        log_success "MinIO data backup completed: ${output_file}.gz (${size})"
    else
        log_error "MinIO data backup failed"
        return 1
    fi
}

# Function: Backup MinIO configuration
backup_minio_config() {
    log_info "Backing up MinIO configuration files..."

    # Backup .env file if exists
    if [[ -f "$(dirname "$0")/../.env" ]]; then
        cp "$(dirname "$0")/../.env" "${BACKUP_DIR}/minio-config/.env_${TIMESTAMP}"
        log_success "Backed up .env file"
    fi

    # Backup configuration directory if exists
    if [[ -d "${MINIO_CONFIG_DIR}" ]]; then
        tar -czf "${BACKUP_DIR}/minio-config/config_${TIMESTAMP}.tar.gz" \
            -C "$(dirname "${MINIO_CONFIG_DIR}")" "$(basename "${MINIO_CONFIG_DIR}")" 2>> "${LOG_FILE}"
        log_success "Backed up configuration directory"
    fi

    # Backup Docker Compose files
    local compose_dir="$(dirname "$0")/../deployments/docker"
    if [[ -d "${compose_dir}" ]]; then
        tar -czf "${BACKUP_DIR}/minio-config/docker_compose_${TIMESTAMP}.tar.gz" \
            -C "$(dirname "${compose_dir}")" "$(basename "${compose_dir}")" 2>> "${LOG_FILE}"
        log_success "Backed up Docker Compose configurations"
    fi
}

# Function: Create backup metadata
create_backup_metadata() {
    log_info "Creating backup metadata..."

    local metadata_file="${BACKUP_DIR}/metadata/backup_metadata.json"

    cat > "${metadata_file}" << EOF
{
  "backup_id": "${TIMESTAMP}",
  "backup_type": "${BACKUP_TYPE}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "compression_enabled": ${BACKUP_COMPRESSION_ENABLED},
  "encryption_enabled": ${BACKUP_ENCRYPTION_ENABLED},
  "components": {
    "postgresql": {
      "host": "${POSTGRES_HOST}",
      "port": "${POSTGRES_PORT}",
      "database": "${POSTGRES_DB}"
    },
    "redis": {
      "host": "${REDIS_HOST}",
      "port": "${REDIS_PORT}"
    },
    "minio": {
      "data_dir": "${MINIO_DATA_DIR}",
      "config_dir": "${MINIO_CONFIG_DIR}"
    }
  },
  "retention_days": ${BACKUP_RETENTION_DAYS}
}
EOF

    log_success "Backup metadata created"
}

# Function: Encrypt backup
encrypt_backup() {
    if [[ "${BACKUP_ENCRYPTION_ENABLED}" != "true" ]]; then
        return 0
    fi

    log_info "Encrypting backup files..."

    # Find all backup files (excluding metadata and logs)
    find "${BACKUP_DIR}" -type f \( -name "*.sql*" -o -name "*.rdb*" -o -name "*.tar*" \) | while read -r file; do
        log_info "Encrypting: $(basename "${file}")"
        gpg --output "${file}.gpg" --encrypt --recipient-file "${BACKUP_GPG_KEY_PATH}" "${file}" 2>> "${LOG_FILE}"

        if [[ $? -eq 0 ]]; then
            # Remove unencrypted file
            rm -f "${file}"
            log_success "Encrypted: $(basename "${file}.gpg")"
        else
            log_error "Failed to encrypt: $(basename "${file}")"
        fi
    done
}

# Function: Verify backup
verify_backup() {
    if [[ "${VERIFY_BACKUP}" != "true" ]]; then
        return 0
    fi

    log_info "Verifying backup integrity..."

    local verification_passed=true

    # Check if backup directory exists
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        log_error "Backup directory not found"
        return 1
    fi

    # Verify PostgreSQL backup
    if [[ -f "${BACKUP_DIR}/postgresql/"*.sql* ]] || [[ -f "${BACKUP_DIR}/postgresql/"*.gpg ]]; then
        log_info "PostgreSQL backup found"
    else
        log_warning "PostgreSQL backup not found"
        verification_passed=false
    fi

    # Verify Redis backup
    if [[ -f "${BACKUP_DIR}/redis/"*.rdb* ]] || [[ -f "${BACKUP_DIR}/redis/"*.gpg ]]; then
        log_info "Redis backup found"
    else
        log_warning "Redis backup not found"
    fi

    # Verify MinIO data backup
    if [[ -f "${BACKUP_DIR}/minio-data/"*.tar* ]] || [[ -f "${BACKUP_DIR}/minio-data/"*.gpg ]]; then
        log_info "MinIO data backup found"
    else
        log_warning "MinIO data backup not found"
        verification_passed=false
    fi

    # Verify metadata
    if [[ -f "${BACKUP_DIR}/metadata/backup_metadata.json" ]]; then
        log_info "Backup metadata found"
    else
        log_error "Backup metadata not found"
        verification_passed=false
    fi

    if [[ "${verification_passed}" == "true" ]]; then
        log_success "Backup verification passed"
    else
        log_error "Backup verification failed"
        return 1
    fi
}

# Function: Clean old backups
clean_old_backups() {
    log_info "Cleaning backups older than ${BACKUP_RETENTION_DAYS} days..."

    local deleted_count=0

    # Find and delete old backups
    find "${BACKUP_DESTINATION}" -maxdepth 1 -type d -name "[0-9]*_[0-9]*" -mtime +${BACKUP_RETENTION_DAYS} | while read -r old_backup; do
        log_info "Deleting old backup: $(basename "${old_backup}")"
        rm -rf "${old_backup}"
        deleted_count=$((deleted_count + 1))
    done

    if [[ ${deleted_count} -gt 0 ]]; then
        log_success "Deleted ${deleted_count} old backup(s)"
    else
        log_info "No old backups to delete"
    fi
}

# Function: Generate backup summary
generate_backup_summary() {
    log_info "Generating backup summary..."

    local summary_file="${BACKUP_DIR}/BACKUP_SUMMARY.txt"
    local total_size=$(du -sh "${BACKUP_DIR}" | cut -f1)

    cat > "${summary_file}" << EOF
MinIO Enterprise - Backup Summary
==================================

Backup ID: ${TIMESTAMP}
Backup Type: ${BACKUP_TYPE}
Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Total Size: ${total_size}

Components Backed Up:
---------------------
$(find "${BACKUP_DIR}" -type f -not -path "*/metadata/*" -not -name "*.log" -not -name "BACKUP_SUMMARY.txt" | while read -r file; do
    echo "  - $(basename "${file}") ($(du -h "${file}" | cut -f1))"
done)

Configuration:
--------------
Compression: ${BACKUP_COMPRESSION_ENABLED}
Encryption: ${BACKUP_ENCRYPTION_ENABLED}
Retention Period: ${BACKUP_RETENTION_DAYS} days

Backup Location:
----------------
${BACKUP_DIR}

Restore Command:
----------------
./scripts/restore.sh --backup ${TIMESTAMP}

EOF

    log_success "Backup summary generated: ${summary_file}"

    # Display summary
    cat "${summary_file}"
}

# Main execution
main() {
    echo "========================================="
    echo "MinIO Enterprise - Backup Script"
    echo "========================================="
    echo ""

    # Parse arguments
    parse_arguments "$@"

    # Create log directory early
    mkdir -p "$(dirname "${BACKUP_DIR}")"
    mkdir -p "${BACKUP_DIR}"
    touch "${LOG_FILE}"

    log_info "Starting backup process..."
    log_info "Backup type: ${BACKUP_TYPE}"
    log_info "Destination: ${BACKUP_DIR}"

    # Execute backup steps
    check_prerequisites
    create_backup_directory

    # Backup components
    backup_postgresql || log_warning "PostgreSQL backup had issues"
    backup_redis || log_warning "Redis backup had issues"
    backup_minio_data || log_warning "MinIO data backup had issues"
    backup_minio_config

    # Create metadata
    create_backup_metadata

    # Encrypt if enabled
    encrypt_backup

    # Verify backup
    verify_backup || log_warning "Backup verification had issues"

    # Clean old backups
    clean_old_backups

    # Generate summary
    generate_backup_summary

    log_success "Backup process completed successfully!"
    log_info "Backup location: ${BACKUP_DIR}"
    log_info "Log file: ${LOG_FILE}"

    echo ""
    echo "========================================="
    echo "Backup completed successfully!"
    echo "========================================="
}

# Run main function
main "$@"
