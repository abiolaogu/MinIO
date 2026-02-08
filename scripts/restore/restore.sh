#!/bin/bash
#
# MinIO Enterprise Restore Script
# Automated restore solution for PostgreSQL, Redis, and MinIO object data
#
# Usage: ./restore.sh [OPTIONS]
# Options:
#   --backup-dir <dir>   Backup directory to restore from (required)
#   --type <type>        Restore type: full|postgres|redis|objects (default: full)
#   --verify             Verify restore integrity
#   --dry-run            Show what would be restored without actually restoring
#   --force              Skip confirmation prompts
#   --help               Show this help message
#

set -euo pipefail

# Script metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Default configuration
BACKUP_DIR=""
RESTORE_TYPE="full"
ENABLE_VERIFICATION=false
DRY_RUN=false
FORCE_RESTORE=false
LOG_FILE=""
TEMP_DIR=""

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

# Cleanup on exit
cleanup() {
    if [[ -n "${TEMP_DIR}" ]] && [[ -d "${TEMP_DIR}" ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf "${TEMP_DIR}"
    fi
}

trap cleanup EXIT

# Show help
show_help() {
    cat << EOF
MinIO Enterprise Restore Script v${SCRIPT_VERSION}

Usage: $0 [OPTIONS]

Options:
  --backup-dir <dir>   Backup directory to restore from (required)
  --type <type>        Restore type: full|postgres|redis|objects (default: full)
  --verify             Verify restore integrity after restoration
  --dry-run            Show what would be restored without actually restoring
  --force              Skip confirmation prompts (use with caution)
  --help               Show this help message

Restore Types:
  full                 Restore all components (PostgreSQL + Redis + Objects)
  postgres             PostgreSQL database only
  redis                Redis snapshots only
  objects              MinIO object data only

Environment Variables:
  POSTGRES_HOST        PostgreSQL host (default: localhost)
  POSTGRES_PORT        PostgreSQL port (default: 5432)
  POSTGRES_USER        PostgreSQL user (default: postgres)
  POSTGRES_PASSWORD    PostgreSQL password
  POSTGRES_DB          PostgreSQL database name (default: minio)
  REDIS_HOST           Redis host (default: localhost)
  REDIS_PORT           Redis port (default: 6379)
  REDIS_PASSWORD       Redis password
  MINIO_ENDPOINT       MinIO endpoint (default: http://localhost:9000)
  MINIO_ACCESS_KEY     MinIO access key (default: minioadmin)
  MINIO_SECRET_KEY     MinIO secret key (default: minioadmin)

Examples:
  # Full restore with verification
  $0 --backup-dir ./backups/backup_full_20260208_120000 --type full --verify

  # PostgreSQL restore only (dry-run)
  $0 --backup-dir ./backups/backup_full_20260208_120000 --type postgres --dry-run

  # Objects restore without confirmation
  $0 --backup-dir ./backups/backup_objects_20260208_120000 --type objects --force

WARNING:
  Restore operations will overwrite existing data. Always backup current state
  before performing a restore. Use --dry-run to preview restore operations.

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            --type)
                RESTORE_TYPE="$2"
                shift 2
                ;;
            --verify)
                ENABLE_VERIFICATION=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_RESTORE=true
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

    # Validate required arguments
    if [[ -z "${BACKUP_DIR}" ]]; then
        log_error "Backup directory is required (--backup-dir)"
        show_help
        exit 1
    fi

    if [[ ! -d "${BACKUP_DIR}" ]]; then
        log_error "Backup directory not found: ${BACKUP_DIR}"
        exit 1
    fi
}

# Load configuration
load_config() {
    # Set defaults from environment
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

    # Initialize log file
    LOG_FILE="${BACKUP_DIR}/restore_${TIMESTAMP}.log"
    log_info "Restore log: ${LOG_FILE}"

    # Create temp directory
    TEMP_DIR=$(mktemp -d)
    log_info "Temporary directory: ${TEMP_DIR}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    # Check for required tools based on restore type
    case "${RESTORE_TYPE}" in
        full|postgres)
            command -v pg_restore >/dev/null 2>&1 || missing_tools+=("pg_restore (postgresql-client)")
            command -v psql >/dev/null 2>&1 || missing_tools+=("psql (postgresql-client)")
            ;;
    esac

    case "${RESTORE_TYPE}" in
        full|redis)
            command -v redis-cli >/dev/null 2>&1 || missing_tools+=("redis-cli")
            ;;
    esac

    case "${RESTORE_TYPE}" in
        full|objects)
            command -v mc >/dev/null 2>&1 || missing_tools+=("mc (MinIO Client)")
            ;;
    esac

    command -v gpg >/dev/null 2>&1 || missing_tools+=("gpg (for encrypted backups)")
    command -v gzip >/dev/null 2>&1 || missing_tools+=("gzip")
    command -v tar >/dev/null 2>&1 || missing_tools+=("tar")

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install missing tools and try again"
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

# Read backup manifest
read_manifest() {
    local manifest_file="${BACKUP_DIR}/MANIFEST.txt"

    if [[ ! -f "${manifest_file}" ]]; then
        log_warning "Manifest file not found: ${manifest_file}"
        return 1
    fi

    log_info "Reading backup manifest..."
    cat "${manifest_file}" | grep -E "^(Backup Type|Timestamp|Date|Compression|Encryption):" | while read -r line; do
        log_info "  ${line}"
    done

    log_success "Manifest read successfully"
}

# Prepare backup file (decrypt/decompress)
prepare_backup_file() {
    local backup_file="${1}"
    local output_file="${backup_file}"

    log_info "Preparing backup file: $(basename "${backup_file}")"

    # Check if file is encrypted
    if [[ "${backup_file}" == *.gpg ]]; then
        log_info "Decrypting backup file..."
        local decrypted_file="${TEMP_DIR}/$(basename "${backup_file%.gpg}")"

        if gpg --decrypt "${backup_file}" > "${decrypted_file}" 2>>"${LOG_FILE}"; then
            log_success "Decryption successful"
            output_file="${decrypted_file}"
        else
            log_error "Decryption failed"
            return 1
        fi
    fi

    # Check if file is compressed
    if [[ "${output_file}" == *.gz ]]; then
        log_info "Decompressing backup file..."
        local decompressed_file="${TEMP_DIR}/$(basename "${output_file%.gz}")"

        if gzip -dc "${output_file}" > "${decompressed_file}" 2>>"${LOG_FILE}"; then
            log_success "Decompression successful"
            output_file="${decompressed_file}"
        else
            log_error "Decompression failed"
            return 1
        fi
    fi

    echo "${output_file}"
}

# Restore PostgreSQL
restore_postgresql() {
    local backup_file=$(find "${BACKUP_DIR}" -name "postgresql_*.sql*" | head -n 1)

    if [[ -z "${backup_file}" ]]; then
        log_error "PostgreSQL backup file not found in ${BACKUP_DIR}"
        return 1
    fi

    log_info "Starting PostgreSQL restore..."
    log_info "Backup file: $(basename "${backup_file}")"
    log_info "Target: ${POSTGRES_DB} at ${POSTGRES_HOST}:${POSTGRES_PORT}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would restore PostgreSQL from ${backup_file}"
        return 0
    fi

    # Prepare backup file
    local prepared_file=$(prepare_backup_file "${backup_file}")
    if [[ -z "${prepared_file}" ]]; then
        return 1
    fi

    # Set password for pg_restore
    export PGPASSWORD="${POSTGRES_PASSWORD}"

    # Check if database exists
    if psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -lqt 2>>"${LOG_FILE}" | \
       cut -d \| -f 1 | grep -qw "${POSTGRES_DB}"; then
        log_warning "Database ${POSTGRES_DB} exists. It will be dropped and recreated."

        if [[ "${FORCE_RESTORE}" == "false" ]]; then
            read -p "Continue? (yes/no): " -r confirm
            if [[ ! "${confirm}" =~ ^[Yy][Ee][Ss]$ ]]; then
                log_info "Restore cancelled by user"
                unset PGPASSWORD
                return 1
            fi
        fi

        # Drop existing database
        log_info "Dropping existing database..."
        if psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
                -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};" 2>>"${LOG_FILE}"; then
            log_success "Database dropped"
        else
            log_error "Failed to drop database"
            unset PGPASSWORD
            return 1
        fi
    fi

    # Create database
    log_info "Creating database..."
    if psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
            -c "CREATE DATABASE ${POSTGRES_DB};" 2>>"${LOG_FILE}"; then
        log_success "Database created"
    else
        log_error "Failed to create database"
        unset PGPASSWORD
        return 1
    fi

    # Restore database
    log_info "Restoring database..."
    if pg_restore -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
                  -d "${POSTGRES_DB}" -v "${prepared_file}" 2>>"${LOG_FILE}"; then
        log_success "PostgreSQL restore completed"
    else
        log_error "PostgreSQL restore failed"
        unset PGPASSWORD
        return 1
    fi

    unset PGPASSWORD

    # Verify restore
    if [[ "${ENABLE_VERIFICATION}" == "true" ]]; then
        verify_postgresql_restore
    fi
}

# Restore Redis
restore_redis() {
    local backup_file=$(find "${BACKUP_DIR}" -name "redis_*.rdb*" | head -n 1)

    if [[ -z "${backup_file}" ]]; then
        log_error "Redis backup file not found in ${BACKUP_DIR}"
        return 1
    fi

    log_info "Starting Redis restore..."
    log_info "Backup file: $(basename "${backup_file}")"
    log_info "Target: ${REDIS_HOST}:${REDIS_PORT}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would restore Redis from ${backup_file}"
        return 0
    fi

    # Prepare backup file
    local prepared_file=$(prepare_backup_file "${backup_file}")
    if [[ -z "${prepared_file}" ]]; then
        return 1
    fi

    # Warning about data loss
    log_warning "Redis restore will overwrite all existing data."

    if [[ "${FORCE_RESTORE}" == "false" ]]; then
        read -p "Continue? (yes/no): " -r confirm
        if [[ ! "${confirm}" =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Restore cancelled by user"
            return 1
        fi
    fi

    # Get Redis configuration
    local redis_cmd="redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT}"
    [[ -n "${REDIS_PASSWORD}" ]] && redis_cmd="${redis_cmd} -a ${REDIS_PASSWORD}"

    local redis_dir=$(${redis_cmd} --no-auth-warning CONFIG GET dir 2>>"${LOG_FILE}" | tail -n 1)
    local redis_dbfilename=$(${redis_cmd} --no-auth-warning CONFIG GET dbfilename 2>>"${LOG_FILE}" | tail -n 1)
    local redis_rdb="${redis_dir}/${redis_dbfilename}"

    log_info "Redis data directory: ${redis_dir}"
    log_info "Redis RDB file: ${redis_dbfilename}"

    # Stop Redis to safely replace RDB file
    log_info "Stopping Redis..."
    ${redis_cmd} --no-auth-warning SHUTDOWN NOSAVE 2>>"${LOG_FILE}" || true
    sleep 2

    # Copy RDB file
    log_info "Copying RDB file..."
    if [[ -f "${redis_dir}" ]]; then
        # Direct filesystem access
        cp "${prepared_file}" "${redis_rdb}"
        log_success "RDB file copied"
    else
        # Docker container approach
        local container_name="${REDIS_CONTAINER_NAME:-redis}"
        log_info "Attempting to copy to container ${container_name}..."

        if docker cp "${prepared_file}" "${container_name}:${redis_rdb}" 2>>"${LOG_FILE}"; then
            log_success "RDB file copied to container"
        else
            log_error "Failed to copy RDB file"
            return 1
        fi
    fi

    # Start Redis
    log_info "Starting Redis..."
    log_warning "You may need to manually start Redis using 'redis-server' or container restart"

    # Try to verify Redis is running
    sleep 2
    if ${redis_cmd} --no-auth-warning PING >/dev/null 2>&1; then
        log_success "Redis is running"

        # Verify restore
        if [[ "${ENABLE_VERIFICATION}" == "true" ]]; then
            verify_redis_restore
        fi
    else
        log_warning "Redis may need manual restart"
    fi
}

# Restore MinIO objects
restore_minio_objects() {
    local backup_file=$(find "${BACKUP_DIR}" -name "objects_*.tar*" | head -n 1)

    if [[ -z "${backup_file}" ]]; then
        log_error "MinIO objects backup file not found in ${BACKUP_DIR}"
        return 1
    fi

    log_info "Starting MinIO objects restore..."
    log_info "Backup file: $(basename "${backup_file}")"
    log_info "Target: ${MINIO_ENDPOINT}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would restore MinIO objects from ${backup_file}"
        return 0
    fi

    # Prepare backup file
    local prepared_file=$(prepare_backup_file "${backup_file}")
    if [[ -z "${prepared_file}" ]]; then
        return 1
    fi

    # Extract tarball
    log_info "Extracting objects backup..."
    local extract_dir="${TEMP_DIR}/objects"
    mkdir -p "${extract_dir}"

    if tar -xf "${prepared_file}" -C "${TEMP_DIR}" 2>>"${LOG_FILE}"; then
        log_success "Objects backup extracted"
    else
        log_error "Failed to extract objects backup"
        return 1
    fi

    # Find extracted directory
    local objects_dir=$(find "${TEMP_DIR}" -maxdepth 1 -type d -name "objects_*" | head -n 1)
    if [[ -z "${objects_dir}" ]]; then
        log_error "Objects directory not found after extraction"
        return 1
    fi

    # Warning about data overwrite
    log_warning "MinIO objects restore will overwrite existing objects."

    if [[ "${FORCE_RESTORE}" == "false" ]]; then
        read -p "Continue? (yes/no): " -r confirm
        if [[ ! "${confirm}" =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Restore cancelled by user"
            return 1
        fi
    fi

    # Configure MinIO client
    local mc_alias="restore_target"
    mc alias set "${mc_alias}" "${MINIO_ENDPOINT}" "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}" \
       --api S3v4 >/dev/null 2>>"${LOG_FILE}"

    # Restore objects
    log_info "Restoring objects to MinIO..."
    if mc mirror "${objects_dir}/" "${mc_alias}/" --overwrite 2>>"${LOG_FILE}"; then
        local file_count=$(find "${objects_dir}" -type f | wc -l)
        log_success "MinIO objects restore completed"
        log_info "Restored files: ${file_count}"

        # Verify restore
        if [[ "${ENABLE_VERIFICATION}" == "true" ]]; then
            verify_minio_restore
        fi
    else
        log_error "MinIO objects restore failed"
        return 1
    fi
}

# Verify PostgreSQL restore
verify_postgresql_restore() {
    log_info "Verifying PostgreSQL restore..."

    export PGPASSWORD="${POSTGRES_PASSWORD}"

    # Check database connectivity
    if psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
            -d "${POSTGRES_DB}" -c "SELECT 1;" >/dev/null 2>>"${LOG_FILE}"; then
        log_success "PostgreSQL connection successful"
    else
        log_error "PostgreSQL connection failed"
        unset PGPASSWORD
        return 1
    fi

    # Get table count
    local table_count=$(psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" \
                             -d "${POSTGRES_DB}" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';" 2>>"${LOG_FILE}" | xargs)

    log_info "Tables restored: ${table_count}"

    unset PGPASSWORD

    if [[ ${table_count} -gt 0 ]]; then
        log_success "PostgreSQL restore verification passed"
    else
        log_warning "PostgreSQL restore verification: No tables found"
    fi
}

# Verify Redis restore
verify_redis_restore() {
    log_info "Verifying Redis restore..."

    local redis_cmd="redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT}"
    [[ -n "${REDIS_PASSWORD}" ]] && redis_cmd="${redis_cmd} -a ${REDIS_PASSWORD}"

    # Check Redis connectivity
    if ${redis_cmd} --no-auth-warning PING >/dev/null 2>&1; then
        log_success "Redis connection successful"
    else
        log_error "Redis connection failed"
        return 1
    fi

    # Get key count
    local key_count=$(${redis_cmd} --no-auth-warning DBSIZE 2>>"${LOG_FILE}" | grep -oP '\d+' || echo "0")
    log_info "Keys restored: ${key_count}"

    if [[ ${key_count} -gt 0 ]]; then
        log_success "Redis restore verification passed"
    else
        log_warning "Redis restore verification: No keys found"
    fi
}

# Verify MinIO restore
verify_minio_restore() {
    log_info "Verifying MinIO restore..."

    local mc_alias="restore_verify"
    mc alias set "${mc_alias}" "${MINIO_ENDPOINT}" "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}" \
       --api S3v4 >/dev/null 2>>"${LOG_FILE}"

    # List buckets
    local bucket_count=$(mc ls "${mc_alias}" 2>>"${LOG_FILE}" | wc -l)
    log_info "Buckets restored: ${bucket_count}"

    # Count objects
    local object_count=$(mc find "${mc_alias}" --name "*" 2>>"${LOG_FILE}" | wc -l)
    log_info "Objects restored: ${object_count}"

    if [[ ${object_count} -gt 0 ]]; then
        log_success "MinIO restore verification passed"
    else
        log_warning "MinIO restore verification: No objects found"
    fi
}

# Main restore function
main() {
    log_info "=========================================="
    log_info "MinIO Enterprise Restore v${SCRIPT_VERSION}"
    log_info "=========================================="

    # Parse arguments
    parse_args "$@"

    # Load configuration
    load_config

    # Check prerequisites
    check_prerequisites

    # Read manifest
    read_manifest

    log_info "Restore type: ${RESTORE_TYPE}"
    log_info "Backup directory: ${BACKUP_DIR}"
    [[ "${DRY_RUN}" == "true" ]] && log_warning "DRY-RUN MODE: No actual changes will be made"

    # Track restore status
    local restore_failed=false

    # Perform restore based on type
    case "${RESTORE_TYPE}" in
        full)
            log_info "Starting full restore (PostgreSQL + Redis + Objects)..."

            if ! restore_postgresql; then
                restore_failed=true
            fi

            if ! restore_redis; then
                restore_failed=true
            fi

            if ! restore_minio_objects; then
                restore_failed=true
            fi
            ;;

        postgres)
            if ! restore_postgresql; then
                restore_failed=true
            fi
            ;;

        redis)
            if ! restore_redis; then
                restore_failed=true
            fi
            ;;

        objects)
            if ! restore_minio_objects; then
                restore_failed=true
            fi
            ;;

        *)
            log_error "Unknown restore type: ${RESTORE_TYPE}"
            exit 1
            ;;
    esac

    # Summary
    log_info "=========================================="
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY-RUN completed"
        log_info "No actual changes were made"
    elif [[ "${restore_failed}" == "true" ]]; then
        log_error "Restore completed with errors"
        log_error "Check log file: ${LOG_FILE}"
        exit 1
    else
        log_success "Restore completed successfully!"
        log_info "Log file: ${LOG_FILE}"
    fi
    log_info "=========================================="
}

# Execute main function
main "$@"
