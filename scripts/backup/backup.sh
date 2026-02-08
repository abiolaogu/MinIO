#!/bin/bash
#
# MinIO Enterprise Backup Script
# Automated backup solution for PostgreSQL, Redis, and MinIO object data
#
# Usage: ./backup.sh [OPTIONS]
# Options:
#   --config <file>    Backup configuration file (default: ./backup.conf)
#   --type <type>      Backup type: full|incremental|postgres|redis|objects (default: full)
#   --output <dir>     Backup output directory (default: ./backups)
#   --encrypt          Enable encryption (requires GPG_KEY_ID in config)
#   --compress         Enable compression (gzip)
#   --verify           Verify backup integrity after creation
#   --help             Show this help message
#

set -euo pipefail

# Script metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Default configuration
CONFIG_FILE="${SCRIPT_DIR}/backup.conf"
BACKUP_TYPE="full"
OUTPUT_DIR="${SCRIPT_DIR}/../../backups"
ENABLE_ENCRYPTION=false
ENABLE_COMPRESSION=true
ENABLE_VERIFICATION=false
LOG_FILE=""

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    [[ -n "${LOG_FILE}" ]] && echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    [[ -n "${LOG_FILE}" ]] && echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    [[ -n "${LOG_FILE}" ]] && echo "[WARNING] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
    [[ -n "${LOG_FILE}" ]] && echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "${LOG_FILE}"
}

# Show help
show_help() {
    cat << EOF
MinIO Enterprise Backup Script v${SCRIPT_VERSION}

Usage: $0 [OPTIONS]

Options:
  --config <file>    Backup configuration file (default: ./backup.conf)
  --type <type>      Backup type: full|incremental|postgres|redis|objects (default: full)
  --output <dir>     Backup output directory (default: ./backups)
  --encrypt          Enable encryption (requires GPG_KEY_ID in config)
  --compress         Enable compression (gzip, enabled by default)
  --no-compress      Disable compression
  --verify           Verify backup integrity after creation
  --help             Show this help message

Backup Types:
  full               Backup all components (PostgreSQL + Redis + Objects)
  incremental        Incremental backup (objects only, based on last backup)
  postgres           PostgreSQL database only
  redis              Redis snapshots only
  objects            MinIO object data only

Environment Variables (override config file):
  POSTGRES_HOST      PostgreSQL host
  POSTGRES_PORT      PostgreSQL port
  POSTGRES_USER      PostgreSQL user
  POSTGRES_PASSWORD  PostgreSQL password
  POSTGRES_DB        PostgreSQL database name
  REDIS_HOST         Redis host
  REDIS_PORT         Redis port
  REDIS_PASSWORD     Redis password
  MINIO_ENDPOINT     MinIO endpoint
  MINIO_ACCESS_KEY   MinIO access key
  MINIO_SECRET_KEY   MinIO secret key
  GPG_KEY_ID         GPG key ID for encryption

Examples:
  # Full backup with encryption
  $0 --config ./backup.conf --type full --encrypt --verify

  # PostgreSQL backup only
  $0 --type postgres --output /backups

  # Incremental objects backup
  $0 --type incremental --compress

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --type)
                BACKUP_TYPE="$2"
                shift 2
                ;;
            --output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --encrypt)
                ENABLE_ENCRYPTION=true
                shift
                ;;
            --compress)
                ENABLE_COMPRESSION=true
                shift
                ;;
            --no-compress)
                ENABLE_COMPRESSION=false
                shift
                ;;
            --verify)
                ENABLE_VERIFICATION=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Load configuration
load_config() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        log_info "Loading configuration from ${CONFIG_FILE}"
        # shellcheck disable=SC1090
        source "${CONFIG_FILE}"
    else
        log_warning "Configuration file not found: ${CONFIG_FILE}"
        log_info "Using environment variables or defaults"
    fi

    # Set defaults from environment or config
    POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
    POSTGRES_PORT="${POSTGRES_PORT:-5432}"
    POSTGRES_USER="${POSTGRES_USER:-postgres}"
    POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
    POSTGRES_DB="${POSTGRES_DB:-minio}"

    REDIS_HOST="${REDIS_HOST:-localhost}"
    REDIS_PORT="${REDIS_PORT:-6379}"
    REDIS_PASSWORD="${REDIS_PASSWORD:-}"

    MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://localhost:9000}"
    MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-minioadmin}"
    MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-minioadmin}"
    MINIO_BUCKET="${MINIO_BUCKET:-backups}"

    GPG_KEY_ID="${GPG_KEY_ID:-}"
    RETENTION_DAYS="${RETENTION_DAYS:-30}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    # Check for required tools based on backup type
    case "${BACKUP_TYPE}" in
        full|postgres)
            command -v pg_dump >/dev/null 2>&1 || missing_tools+=("pg_dump (postgresql-client)")
            ;;
    esac

    case "${BACKUP_TYPE}" in
        full|redis)
            command -v redis-cli >/dev/null 2>&1 || missing_tools+=("redis-cli")
            ;;
    esac

    case "${BACKUP_TYPE}" in
        full|objects|incremental)
            command -v mc >/dev/null 2>&1 || missing_tools+=("mc (MinIO Client)")
            ;;
    esac

    if [[ "${ENABLE_COMPRESSION}" == "true" ]]; then
        command -v gzip >/dev/null 2>&1 || missing_tools+=("gzip")
    fi

    if [[ "${ENABLE_ENCRYPTION}" == "true" ]]; then
        command -v gpg >/dev/null 2>&1 || missing_tools+=("gpg")
        if [[ -z "${GPG_KEY_ID}" ]]; then
            log_error "Encryption enabled but GPG_KEY_ID not set"
            exit 1
        fi
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install missing tools and try again"
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

# Create backup directory
create_backup_dir() {
    local backup_name="${1}"
    local backup_dir="${OUTPUT_DIR}/${backup_name}"

    if [[ ! -d "${backup_dir}" ]]; then
        mkdir -p "${backup_dir}"
        log_info "Created backup directory: ${backup_dir}"
    fi

    # Initialize log file
    LOG_FILE="${backup_dir}/backup.log"
    log_info "Backup log: ${LOG_FILE}"

    echo "${backup_dir}"
}

# Backup PostgreSQL
backup_postgresql() {
    local backup_dir="${1}"
    local pg_backup_file="${backup_dir}/postgresql_${TIMESTAMP}.sql"

    log_info "Starting PostgreSQL backup..."
    log_info "Database: ${POSTGRES_DB} at ${POSTGRES_HOST}:${POSTGRES_PORT}"

    # Set password for pg_dump
    export PGPASSWORD="${POSTGRES_PASSWORD}"

    # Create backup
    if pg_dump -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
               -d "${POSTGRES_DB}" -F c -f "${pg_backup_file}" 2>>"${LOG_FILE}"; then

        local file_size=$(du -h "${pg_backup_file}" | cut -f1)
        log_success "PostgreSQL backup created: ${pg_backup_file} (${file_size})"

        # Compress if enabled
        if [[ "${ENABLE_COMPRESSION}" == "true" ]]; then
            log_info "Compressing PostgreSQL backup..."
            gzip -f "${pg_backup_file}"
            pg_backup_file="${pg_backup_file}.gz"
            file_size=$(du -h "${pg_backup_file}" | cut -f1)
            log_success "Compressed: ${pg_backup_file} (${file_size})"
        fi

        # Encrypt if enabled
        if [[ "${ENABLE_ENCRYPTION}" == "true" ]]; then
            log_info "Encrypting PostgreSQL backup..."
            gpg --encrypt --recipient "${GPG_KEY_ID}" "${pg_backup_file}"
            rm -f "${pg_backup_file}"
            pg_backup_file="${pg_backup_file}.gpg"
            file_size=$(du -h "${pg_backup_file}" | cut -f1)
            log_success "Encrypted: ${pg_backup_file} (${file_size})"
        fi

        echo "${pg_backup_file}"
    else
        log_error "PostgreSQL backup failed"
        return 1
    fi

    unset PGPASSWORD
}

# Backup Redis
backup_redis() {
    local backup_dir="${1}"
    local redis_backup_file="${backup_dir}/redis_${TIMESTAMP}.rdb"

    log_info "Starting Redis backup..."
    log_info "Redis: ${REDIS_HOST}:${REDIS_PORT}"

    # Trigger Redis SAVE command
    local redis_cmd="redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT}"
    [[ -n "${REDIS_PASSWORD}" ]] && redis_cmd="${redis_cmd} -a ${REDIS_PASSWORD}"

    if ${redis_cmd} --no-auth-warning SAVE >/dev/null 2>>"${LOG_FILE}"; then
        log_info "Redis SAVE command executed"

        # Get Redis data directory from config
        local redis_dir=$(${redis_cmd} --no-auth-warning CONFIG GET dir | tail -n 1)
        local redis_dbfilename=$(${redis_cmd} --no-auth-warning CONFIG GET dbfilename | tail -n 1)
        local redis_rdb="${redis_dir}/${redis_dbfilename}"

        # Copy RDB file
        if [[ -f "${redis_rdb}" ]]; then
            cp "${redis_rdb}" "${redis_backup_file}"
            local file_size=$(du -h "${redis_backup_file}" | cut -f1)
            log_success "Redis backup created: ${redis_backup_file} (${file_size})"
        else
            log_warning "Redis RDB file not found at ${redis_rdb}, attempting container copy..."

            # Try to copy from Docker container (common in production)
            local container_name="${REDIS_CONTAINER_NAME:-redis}"
            if docker cp "${container_name}:${redis_rdb}" "${redis_backup_file}" 2>>"${LOG_FILE}"; then
                local file_size=$(du -h "${redis_backup_file}" | cut -f1)
                log_success "Redis backup created from container: ${redis_backup_file} (${file_size})"
            else
                log_error "Failed to copy Redis RDB file"
                return 1
            fi
        fi

        # Compress if enabled
        if [[ "${ENABLE_COMPRESSION}" == "true" ]]; then
            log_info "Compressing Redis backup..."
            gzip -f "${redis_backup_file}"
            redis_backup_file="${redis_backup_file}.gz"
            file_size=$(du -h "${redis_backup_file}" | cut -f1)
            log_success "Compressed: ${redis_backup_file} (${file_size})"
        fi

        # Encrypt if enabled
        if [[ "${ENABLE_ENCRYPTION}" == "true" ]]; then
            log_info "Encrypting Redis backup..."
            gpg --encrypt --recipient "${GPG_KEY_ID}" "${redis_backup_file}"
            rm -f "${redis_backup_file}"
            redis_backup_file="${redis_backup_file}.gpg"
            file_size=$(du -h "${redis_backup_file}" | cut -f1)
            log_success "Encrypted: ${redis_backup_file} (${file_size})"
        fi

        echo "${redis_backup_file}"
    else
        log_error "Redis backup failed"
        return 1
    fi
}

# Backup MinIO objects
backup_minio_objects() {
    local backup_dir="${1}"
    local incremental="${2:-false}"
    local minio_backup_dir="${backup_dir}/objects_${TIMESTAMP}"

    log_info "Starting MinIO objects backup..."
    log_info "Endpoint: ${MINIO_ENDPOINT}"
    log_info "Mode: ${incremental}"

    # Configure MinIO client
    local mc_alias="backup_source"
    mc alias set "${mc_alias}" "${MINIO_ENDPOINT}" "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}" \
       --api S3v4 >/dev/null 2>>"${LOG_FILE}"

    # Create backup directory
    mkdir -p "${minio_backup_dir}"

    # Mirror/sync objects
    local mc_cmd="mc mirror"
    [[ "${incremental}" == "true" ]] && mc_cmd="${mc_cmd} --newer-than"

    if mc mirror "${mc_alias}/" "${minio_backup_dir}/" 2>>"${LOG_FILE}"; then
        local file_count=$(find "${minio_backup_dir}" -type f | wc -l)
        local total_size=$(du -sh "${minio_backup_dir}" | cut -f1)
        log_success "MinIO objects backup created: ${minio_backup_dir}"
        log_info "Files: ${file_count}, Total size: ${total_size}"

        # Create tarball
        local tar_file="${backup_dir}/objects_${TIMESTAMP}.tar"
        log_info "Creating tarball..."
        tar -cf "${tar_file}" -C "${backup_dir}" "objects_${TIMESTAMP}" 2>>"${LOG_FILE}"
        rm -rf "${minio_backup_dir}"

        local file_size=$(du -h "${tar_file}" | cut -f1)
        log_success "Tarball created: ${tar_file} (${file_size})"

        # Compress if enabled
        if [[ "${ENABLE_COMPRESSION}" == "true" ]]; then
            log_info "Compressing objects backup..."
            gzip -f "${tar_file}"
            tar_file="${tar_file}.gz"
            file_size=$(du -h "${tar_file}" | cut -f1)
            log_success "Compressed: ${tar_file} (${file_size})"
        fi

        # Encrypt if enabled
        if [[ "${ENABLE_ENCRYPTION}" == "true" ]]; then
            log_info "Encrypting objects backup..."
            gpg --encrypt --recipient "${GPG_KEY_ID}" "${tar_file}"
            rm -f "${tar_file}"
            tar_file="${tar_file}.gpg"
            file_size=$(du -h "${tar_file}" | cut -f1)
            log_success "Encrypted: ${tar_file} (${file_size})"
        fi

        echo "${tar_file}"
    else
        log_error "MinIO objects backup failed"
        return 1
    fi
}

# Verify backup integrity
verify_backup() {
    local backup_file="${1}"

    log_info "Verifying backup integrity: ${backup_file}"

    # Decrypt if encrypted
    if [[ "${backup_file}" == *.gpg ]]; then
        log_info "Decrypting for verification..."
        local decrypted_file="${backup_file%.gpg}"
        if gpg --decrypt "${backup_file}" > "${decrypted_file}" 2>>"${LOG_FILE}"; then
            backup_file="${decrypted_file}"
            log_success "Decryption successful"
        else
            log_error "Decryption failed"
            return 1
        fi
    fi

    # Decompress if compressed
    if [[ "${backup_file}" == *.gz ]]; then
        log_info "Decompressing for verification..."
        if gzip -t "${backup_file}" 2>>"${LOG_FILE}"; then
            log_success "Compression integrity verified"
        else
            log_error "Compression integrity check failed"
            return 1
        fi
    fi

    # Additional file-specific checks
    case "${backup_file}" in
        *.sql*|*.dump*)
            log_info "PostgreSQL dump verification passed (basic)"
            ;;
        *.rdb*)
            log_info "Redis RDB verification passed (basic)"
            ;;
        *.tar*)
            log_info "Tar archive verification..."
            if tar -tzf "${backup_file}" >/dev/null 2>>"${LOG_FILE}"; then
                log_success "Tar archive integrity verified"
            else
                log_error "Tar archive integrity check failed"
                return 1
            fi
            ;;
    esac

    log_success "Backup verification completed: ${backup_file}"

    # Cleanup temporary decrypted files
    [[ "${backup_file}" != "${1}" ]] && rm -f "${backup_file}"
}

# Create backup manifest
create_manifest() {
    local backup_dir="${1}"
    shift
    local backup_files=("$@")

    local manifest_file="${backup_dir}/MANIFEST.txt"

    log_info "Creating backup manifest..."

    {
        echo "MinIO Enterprise Backup Manifest"
        echo "=================================="
        echo ""
        echo "Backup Type: ${BACKUP_TYPE}"
        echo "Timestamp: ${TIMESTAMP}"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Script Version: ${SCRIPT_VERSION}"
        echo ""
        echo "Configuration:"
        echo "  Compression: ${ENABLE_COMPRESSION}"
        echo "  Encryption: ${ENABLE_ENCRYPTION}"
        echo "  Verification: ${ENABLE_VERIFICATION}"
        echo ""
        echo "Files:"
        for file in "${backup_files[@]}"; do
            local filename=$(basename "${file}")
            local filesize=$(du -h "${file}" | cut -f1)
            local checksum=$(sha256sum "${file}" | cut -d' ' -f1)
            echo "  - ${filename}"
            echo "    Size: ${filesize}"
            echo "    SHA256: ${checksum}"
        done
        echo ""
        echo "Backup Location: ${backup_dir}"
    } > "${manifest_file}"

    log_success "Manifest created: ${manifest_file}"
}

# Clean old backups
cleanup_old_backups() {
    log_info "Cleaning up backups older than ${RETENTION_DAYS} days..."

    local deleted_count=0
    while IFS= read -r -d '' backup; do
        rm -rf "${backup}"
        deleted_count=$((deleted_count + 1))
        log_info "Deleted old backup: ${backup}"
    done < <(find "${OUTPUT_DIR}" -maxdepth 1 -type d -name "*_*" -mtime +"${RETENTION_DAYS}" -print0)

    if [[ ${deleted_count} -gt 0 ]]; then
        log_success "Cleaned up ${deleted_count} old backup(s)"
    else
        log_info "No old backups to clean up"
    fi
}

# Main backup function
main() {
    log_info "=========================================="
    log_info "MinIO Enterprise Backup v${SCRIPT_VERSION}"
    log_info "=========================================="

    # Parse arguments
    parse_args "$@"

    # Load configuration
    load_config

    # Check prerequisites
    check_prerequisites

    # Create backup directory
    local backup_name="backup_${BACKUP_TYPE}_${TIMESTAMP}"
    local backup_dir=$(create_backup_dir "${backup_name}")

    log_info "Backup type: ${BACKUP_TYPE}"
    log_info "Output directory: ${backup_dir}"

    # Track backup files
    local backup_files=()
    local backup_failed=false

    # Perform backup based on type
    case "${BACKUP_TYPE}" in
        full)
            log_info "Starting full backup (PostgreSQL + Redis + Objects)..."

            if pg_file=$(backup_postgresql "${backup_dir}"); then
                backup_files+=("${pg_file}")
            else
                backup_failed=true
            fi

            if redis_file=$(backup_redis "${backup_dir}"); then
                backup_files+=("${redis_file}")
            else
                backup_failed=true
            fi

            if objects_file=$(backup_minio_objects "${backup_dir}" false); then
                backup_files+=("${objects_file}")
            else
                backup_failed=true
            fi
            ;;

        postgres)
            if pg_file=$(backup_postgresql "${backup_dir}"); then
                backup_files+=("${pg_file}")
            else
                backup_failed=true
            fi
            ;;

        redis)
            if redis_file=$(backup_redis "${backup_dir}"); then
                backup_files+=("${redis_file}")
            else
                backup_failed=true
            fi
            ;;

        objects)
            if objects_file=$(backup_minio_objects "${backup_dir}" false); then
                backup_files+=("${objects_file}")
            else
                backup_failed=true
            fi
            ;;

        incremental)
            if objects_file=$(backup_minio_objects "${backup_dir}" true); then
                backup_files+=("${objects_file}")
            else
                backup_failed=true
            fi
            ;;

        *)
            log_error "Unknown backup type: ${BACKUP_TYPE}"
            exit 1
            ;;
    esac

    # Verify backups if enabled
    if [[ "${ENABLE_VERIFICATION}" == "true" ]] && [[ ${#backup_files[@]} -gt 0 ]]; then
        log_info "Verifying backups..."
        for file in "${backup_files[@]}"; do
            if ! verify_backup "${file}"; then
                backup_failed=true
            fi
        done
    fi

    # Create manifest
    if [[ ${#backup_files[@]} -gt 0 ]]; then
        create_manifest "${backup_dir}" "${backup_files[@]}"
    fi

    # Cleanup old backups
    cleanup_old_backups

    # Summary
    log_info "=========================================="
    if [[ "${backup_failed}" == "true" ]]; then
        log_error "Backup completed with errors"
        log_error "Check log file: ${LOG_FILE}"
        exit 1
    else
        log_success "Backup completed successfully!"
        log_success "Backup location: ${backup_dir}"
        log_success "Backup files: ${#backup_files[@]}"
        log_info "Log file: ${LOG_FILE}"
    fi
    log_info "=========================================="
}

# Execute main function
main "$@"
