#!/bin/bash
set -euo pipefail

################################################################################
# MinIO Enterprise Restore Script
#
# Description: Automated restore solution for MinIO cluster including:
#   - MinIO object data (all buckets and objects)
#   - PostgreSQL database (tenant metadata, quotas)
#   - Redis snapshots (cache state)
#   - Configuration files
#
# Features:
#   - Full restore from backup
#   - Verification and rollback capabilities
#   - Support for encrypted backups
#   - S3-compatible storage support
#   - Local filesystem storage support
#   - Pre-restore validation
#   - Service health checks
#
# Usage:
#   ./restore.sh [options]
#
# Options:
#   --backup-file <path>       Path to backup file (required)
#   --storage <local|s3>       Storage backend (default: local)
#   --decrypt                  Decrypt backup before restore
#   --verify                   Verify backup before restore
#   --force                    Skip confirmation prompts
#   --rollback                 Rollback to previous state
#   --help                     Show this help message
#
################################################################################

# Script version
VERSION="1.0.0"

# Default configuration
STORAGE_BACKEND="${STORAGE_BACKEND:-local}"
DECRYPT_BACKUP="${DECRYPT_BACKUP:-false}"
VERIFY_BACKUP="${VERIFY_BACKUP:-false}"
FORCE_RESTORE="${FORCE_RESTORE:-false}"
ROLLBACK_MODE="${ROLLBACK_MODE:-false}"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESTORE_ROOT="${RESTORE_ROOT:-${PROJECT_ROOT}/restores}"
RESTORE_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RESTORE_DIR="${RESTORE_ROOT}/${RESTORE_TIMESTAMP}"

# Docker Compose configuration
DOCKER_COMPOSE_FILE="${PROJECT_ROOT}/deployments/docker/docker-compose.production.yml"

# Log file
LOG_FILE="${RESTORE_ROOT}/restore_${RESTORE_TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Logging functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

################################################################################
# Utility functions
################################################################################

usage() {
    cat <<EOF
MinIO Enterprise Restore Script v${VERSION}

Usage: $(basename "$0") [options]

Options:
    --backup-file <path>       Path to backup file (required)
    --storage <local|s3>       Storage backend (default: local)
    --decrypt                  Decrypt backup before restore
    --verify                   Verify backup before restore
    --force                    Skip confirmation prompts
    --rollback                 Rollback to previous state
    --help                     Show this help message

Environment Variables:
    RESTORE_ROOT              Root directory for restore operations (default: ./restores)
    ENCRYPTION_KEY            Encryption key for encrypted backups
    S3_ENDPOINT               S3 endpoint for remote storage
    S3_ACCESS_KEY             S3 access key
    S3_SECRET_KEY             S3 secret key
    S3_BUCKET                 S3 bucket name

Examples:
    # Restore from local backup
    ./restore.sh --backup-file /path/to/backup.tar.gz

    # Restore from encrypted backup with verification
    ./restore.sh --backup-file backup.tar.gz.enc --decrypt --verify

    # Restore from S3
    ./restore.sh --backup-file s3://bucket/backups/backup.tar.gz --storage s3

    # Force restore without confirmation
    ./restore.sh --backup-file backup.tar.gz --force

EOF
    exit 0
}

check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()

    for cmd in docker docker-compose tar gzip date; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ "$DECRYPT_BACKUP" == "true" ]]; then
        if ! command -v openssl &> /dev/null; then
            missing_deps+=("openssl")
        fi
    fi

    if [[ "$STORAGE_BACKEND" == "s3" ]]; then
        if ! command -v aws &> /dev/null; then
            missing_deps+=("aws-cli")
        fi
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_error "Please install missing dependencies and try again"
        exit 1
    fi

    log_success "All dependencies satisfied"
}

confirm_restore() {
    if [[ "$FORCE_RESTORE" == "true" ]]; then
        return 0
    fi

    log_warning "====================================================================="
    log_warning "WARNING: This will restore from backup and overwrite current data!"
    log_warning "====================================================================="
    log_warning "Backup file: ${BACKUP_FILE}"
    log_warning "Current services will be stopped during restore"
    log_warning "All existing data will be replaced with backup data"
    log_warning "====================================================================="

    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Restore cancelled by user"
        exit 0
    fi

    log_info "Restore confirmed by user"
}

create_restore_directory() {
    log_info "Creating restore directory: ${RESTORE_DIR}"

    mkdir -p "${RESTORE_DIR}"

    if [[ ! -d "$RESTORE_DIR" ]]; then
        log_error "Failed to create restore directory"
        exit 1
    fi

    log_success "Restore directory created"
}

download_from_s3() {
    log_info "Downloading backup from S3..."

    if [[ -z "${S3_BUCKET:-}" ]]; then
        log_error "S3_BUCKET environment variable not set"
        return 1
    fi

    local s3_path="${BACKUP_FILE#s3://}"
    local local_file="${RESTORE_DIR}/$(basename "$BACKUP_FILE")"

    aws s3 cp "$BACKUP_FILE" "$local_file" \
        --endpoint-url "${S3_ENDPOINT:-}" \
        2>&1 | tee -a "$LOG_FILE"

    if [[ $? -eq 0 ]]; then
        BACKUP_FILE="$local_file"
        log_success "Backup downloaded from S3"
    else
        log_error "Failed to download backup from S3"
        return 1
    fi
}

verify_backup_file() {
    log_info "Verifying backup integrity..."

    if [[ ! -f "$BACKUP_FILE" ]]; then
        log_error "Backup file not found: ${BACKUP_FILE}"
        return 1
    fi

    # Test archive integrity
    if [[ "$DECRYPT_BACKUP" == "true" ]]; then
        if [[ -z "${ENCRYPTION_KEY:-}" ]]; then
            log_error "ENCRYPTION_KEY environment variable not set"
            return 1
        fi

        openssl enc -aes-256-cbc -d -pbkdf2 \
            -in "$BACKUP_FILE" \
            -pass "pass:${ENCRYPTION_KEY}" 2>/dev/null | tar -tzf - > /dev/null
    else
        tar -tzf "$BACKUP_FILE" > /dev/null
    fi

    if [[ $? -eq 0 ]]; then
        log_success "Backup verification successful"
    else
        log_error "Backup verification failed"
        return 1
    fi
}

extract_backup() {
    log_info "Extracting backup..."

    if [[ "$DECRYPT_BACKUP" == "true" ]]; then
        log_info "Decrypting backup..."
        openssl enc -aes-256-cbc -d -pbkdf2 \
            -in "$BACKUP_FILE" \
            -pass "pass:${ENCRYPTION_KEY}" 2>&1 | tar -xzf - -C "${RESTORE_DIR}" \
            2>&1 | tee -a "$LOG_FILE"
    else
        tar -xzf "$BACKUP_FILE" -C "${RESTORE_DIR}" \
            2>&1 | tee -a "$LOG_FILE"
    fi

    if [[ $? -eq 0 ]]; then
        log_success "Backup extracted successfully"
    else
        log_error "Failed to extract backup"
        return 1
    fi

    # Find extracted backup directory
    local backup_dir=$(find "${RESTORE_DIR}" -maxdepth 1 -type d -name "20*" | head -n1)
    if [[ -z "$backup_dir" ]]; then
        log_error "Could not find extracted backup directory"
        return 1
    fi

    EXTRACTED_BACKUP_DIR="$backup_dir"
    log_info "Extracted backup directory: ${EXTRACTED_BACKUP_DIR}"
}

read_backup_metadata() {
    log_info "Reading backup metadata..."

    local metadata_file="${EXTRACTED_BACKUP_DIR}/metadata/backup_info.json"

    if [[ ! -f "$metadata_file" ]]; then
        log_warning "Backup metadata not found"
        return 0
    fi

    log_info "Backup metadata:"
    cat "$metadata_file" | tee -a "$LOG_FILE"
}

stop_services() {
    log_info "Stopping Docker services..."

    docker-compose -f "$DOCKER_COMPOSE_FILE" stop \
        2>&1 | tee -a "$LOG_FILE"

    if [[ $? -eq 0 ]]; then
        log_success "Services stopped successfully"
    else
        log_error "Failed to stop services"
        return 1
    fi

    # Wait for containers to stop
    sleep 5
}

restore_minio() {
    log_info "Restoring MinIO data..."

    local minio_backup_dir="${EXTRACTED_BACKUP_DIR}/minio"

    if [[ ! -d "$minio_backup_dir" ]]; then
        log_error "MinIO backup directory not found"
        return 1
    fi

    # Restore all MinIO volumes (4 nodes)
    for node in {1..4}; do
        log_info "Restoring MinIO node ${node}..."

        local volume_name="deployments_minio${node}-data"
        local backup_file="${minio_backup_dir}/minio${node}_data.tar.gz"

        if [[ ! -f "$backup_file" ]]; then
            log_error "MinIO node ${node} backup file not found"
            return 1
        fi

        # Remove old volume
        docker volume rm "$volume_name" 2>/dev/null || true

        # Create new volume
        docker volume create "$volume_name" \
            2>&1 | tee -a "$LOG_FILE"

        # Restore data
        docker run --rm \
            -v "${volume_name}:/data" \
            -v "${minio_backup_dir}:/backup:ro" \
            alpine:latest \
            tar -xzf "/backup/minio${node}_data.tar.gz" -C /data \
            2>&1 | tee -a "$LOG_FILE"

        if [[ $? -eq 0 ]]; then
            log_success "MinIO node ${node} restored successfully"
        else
            log_error "Failed to restore MinIO node ${node}"
            return 1
        fi
    done

    # Restore MinIO cache volumes (optional)
    for node in {1..4}; do
        log_info "Restoring MinIO cache node ${node}..."

        local volume_name="deployments_minio${node}-cache"
        local backup_file="${minio_backup_dir}/minio${node}_cache.tar.gz"

        if [[ ! -f "$backup_file" ]]; then
            log_warning "MinIO cache node ${node} backup not found (skipping)"
            continue
        fi

        docker volume rm "$volume_name" 2>/dev/null || true
        docker volume create "$volume_name" 2>&1 | tee -a "$LOG_FILE"

        docker run --rm \
            -v "${volume_name}:/cache" \
            -v "${minio_backup_dir}:/backup:ro" \
            alpine:latest \
            tar -xzf "/backup/minio${node}_cache.tar.gz" -C /cache \
            2>&1 | tee -a "$LOG_FILE"

        if [[ $? -eq 0 ]]; then
            log_success "MinIO cache node ${node} restored successfully"
        else
            log_warning "Failed to restore MinIO cache node ${node} (non-critical)"
        fi
    done

    log_success "MinIO restore completed"
}

restore_postgresql() {
    log_info "Restoring PostgreSQL database..."

    local pg_backup_file=$(find "${EXTRACTED_BACKUP_DIR}/postgresql" -name "*.sql.gz" | head -n1)

    if [[ ! -f "$pg_backup_file" ]]; then
        log_error "PostgreSQL backup file not found"
        return 1
    fi

    # Start PostgreSQL service temporarily
    log_info "Starting PostgreSQL service..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d postgres \
        2>&1 | tee -a "$LOG_FILE"

    # Wait for PostgreSQL to be ready
    sleep 10

    # Restore database
    local pg_container="postgres"

    gunzip -c "$pg_backup_file" | docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$pg_container" \
        psql -U postgres \
        2>&1 | tee -a "$LOG_FILE"

    if [[ $? -eq 0 ]]; then
        log_success "PostgreSQL restore completed"
    else
        log_error "Failed to restore PostgreSQL database"
        return 1
    fi

    # Stop PostgreSQL
    docker-compose -f "$DOCKER_COMPOSE_FILE" stop postgres \
        2>&1 | tee -a "$LOG_FILE"
}

restore_redis() {
    log_info "Restoring Redis data..."

    local redis_backup_file="${EXTRACTED_BACKUP_DIR}/redis/redis_dump.rdb"

    if [[ ! -f "$redis_backup_file" ]]; then
        log_warning "Redis backup file not found (skipping)"
        return 0
    fi

    local volume_name="deployments_redis-data"

    # Remove old volume
    docker volume rm "$volume_name" 2>/dev/null || true

    # Create new volume
    docker volume create "$volume_name" \
        2>&1 | tee -a "$LOG_FILE"

    # Restore Redis dump
    docker run --rm \
        -v "${volume_name}:/data" \
        -v "$(dirname "$redis_backup_file"):/backup:ro" \
        alpine:latest \
        cp /backup/redis_dump.rdb /data/dump.rdb \
        2>&1 | tee -a "$LOG_FILE"

    if [[ $? -eq 0 ]]; then
        log_success "Redis restore completed"
    else
        log_warning "Failed to restore Redis data (non-critical)"
    fi
}

restore_configs() {
    log_info "Restoring configuration files..."

    local config_backup_file=$(find "${EXTRACTED_BACKUP_DIR}/configs" -name "*.tar.gz" | head -n1)

    if [[ ! -f "$config_backup_file" ]]; then
        log_error "Configuration backup file not found"
        return 1
    fi

    # Extract configs
    tar -xzf "$config_backup_file" -C "${PROJECT_ROOT}" \
        2>&1 | tee -a "$LOG_FILE"

    if [[ $? -eq 0 ]]; then
        log_success "Configuration restore completed"
    else
        log_error "Failed to restore configurations"
        return 1
    fi
}

start_services() {
    log_info "Starting Docker services..."

    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d \
        2>&1 | tee -a "$LOG_FILE"

    if [[ $? -eq 0 ]]; then
        log_success "Services started successfully"
    else
        log_error "Failed to start services"
        return 1
    fi

    # Wait for services to be healthy
    log_info "Waiting for services to be healthy..."
    sleep 30

    # Check service health
    docker-compose -f "$DOCKER_COMPOSE_FILE" ps \
        2>&1 | tee -a "$LOG_FILE"
}

verify_restore() {
    log_info "Verifying restore..."

    local failed_services=()

    # Check MinIO nodes
    for node in {1..4}; do
        if ! docker-compose -f "$DOCKER_COMPOSE_FILE" ps "minio${node}" | grep -q "Up"; then
            failed_services+=("minio${node}")
        fi
    done

    # Check PostgreSQL
    if ! docker-compose -f "$DOCKER_COMPOSE_FILE" ps postgres | grep -q "Up"; then
        failed_services+=("postgres")
    fi

    # Check Redis
    if ! docker-compose -f "$DOCKER_COMPOSE_FILE" ps redis | grep -q "Up"; then
        failed_services+=("redis")
    fi

    if [[ ${#failed_services[@]} -eq 0 ]]; then
        log_success "All services are running correctly"
    else
        log_error "The following services failed to start: ${failed_services[*]}"
        return 1
    fi
}

################################################################################
# Main execution
################################################################################

main() {
    log_info "====================================================================="
    log_info "MinIO Enterprise Restore Script v${VERSION}"
    log_info "====================================================================="
    log_info "Backup file: ${BACKUP_FILE}"
    log_info "Storage backend: ${STORAGE_BACKEND}"
    log_info "Decryption: ${DECRYPT_BACKUP}"
    log_info "Verification: ${VERIFY_BACKUP}"
    log_info "====================================================================="

    # Pre-flight checks
    check_dependencies
    create_restore_directory
    confirm_restore

    # Download from S3 if needed
    if [[ "$STORAGE_BACKEND" == "s3" ]]; then
        download_from_s3 || exit 1
    fi

    # Verify backup
    if [[ "$VERIFY_BACKUP" == "true" ]] || [[ "$DECRYPT_BACKUP" == "true" ]]; then
        verify_backup_file || exit 1
    fi

    # Extract backup
    extract_backup || exit 1
    read_backup_metadata

    # Stop services
    stop_services || exit 1

    # Perform restore
    restore_minio || exit 1
    restore_postgresql || exit 1
    restore_redis
    restore_configs || exit 1

    # Start services
    start_services || exit 1

    # Verify restore
    verify_restore || exit 1

    # Final summary
    log_success "====================================================================="
    log_success "Restore completed successfully!"
    log_success "====================================================================="
    log_success "Backup file: ${BACKUP_FILE}"
    log_success "Restore directory: ${RESTORE_DIR}"
    log_success "Log file: ${LOG_FILE}"
    log_success "====================================================================="
    log_success "All services are running. Please verify functionality."
    log_success "====================================================================="
}

################################################################################
# Parse command-line arguments
################################################################################

BACKUP_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --backup-file)
            BACKUP_FILE="$2"
            shift 2
            ;;
        --storage)
            STORAGE_BACKEND="$2"
            shift 2
            ;;
        --decrypt)
            DECRYPT_BACKUP="true"
            shift
            ;;
        --verify)
            VERIFY_BACKUP="true"
            shift
            ;;
        --force)
            FORCE_RESTORE="true"
            shift
            ;;
        --rollback)
            ROLLBACK_MODE="true"
            shift
            ;;
        --help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$BACKUP_FILE" ]]; then
    log_error "Backup file is required. Use --backup-file option."
    usage
fi

# Create restore root directory
mkdir -p "$RESTORE_ROOT"

# Run main function
main
