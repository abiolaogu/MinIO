#!/bin/bash
#
# MinIO Enterprise Backup Script
# Automated backup solution for MinIO cluster, PostgreSQL, Redis, and configurations
#
# Usage:
#   ./backup.sh [full|incremental] [destination]
#
# Examples:
#   ./backup.sh full /backup/storage
#   ./backup.sh incremental s3://backup-bucket/minio-backups
#

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_TYPE="${1:-full}"
BACKUP_DEST="${2:-/backup}"
BACKUP_NAME="minio-backup-${BACKUP_TYPE}-${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DEST}/${BACKUP_NAME}"
LOG_FILE="${BACKUP_PATH}/backup.log"

# Compression settings
COMPRESSION="gzip"  # Options: gzip, bzip2, xz, none
COMPRESSION_LEVEL="6"  # 1-9 (higher = better compression, slower)

# Encryption settings
ENABLE_ENCRYPTION="false"
ENCRYPTION_KEY_FILE="/etc/minio/backup-encryption.key"

# Retention settings (days)
RETENTION_FULL=30
RETENTION_INCREMENTAL=7

# Docker Compose file
COMPOSE_FILE="${PROJECT_ROOT}/deployments/docker/docker-compose.production.yml"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================
# Helper Functions
# ============================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
    log "INFO" "$*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
    log "SUCCESS" "$*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
    log "WARNING" "$*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
    log "ERROR" "$*"
}

check_dependencies() {
    local missing_deps=()

    for cmd in docker docker-compose tar gzip md5sum; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please install missing dependencies and try again"
        exit 1
    fi
}

verify_services_running() {
    log_info "Verifying services are running..."

    local services=("postgres" "redis" "minio1")
    local all_running=true

    for service in "${services[@]}"; do
        if ! docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            log_error "Service ${service} is not running"
            all_running=false
        fi
    done

    if [ "$all_running" = false ]; then
        log_error "Not all required services are running. Please start services and try again."
        exit 1
    fi

    log_success "All required services are running"
}

create_backup_directory() {
    log_info "Creating backup directory: ${BACKUP_PATH}"

    mkdir -p "${BACKUP_PATH}"/{metadata,postgres,redis,minio,configs}

    if [ ! -d "$BACKUP_PATH" ]; then
        log_error "Failed to create backup directory"
        exit 1
    fi

    log_success "Backup directory created"
}

# ============================================================
# Backup Functions
# ============================================================

backup_metadata() {
    log_info "Creating backup metadata..."

    cat > "${BACKUP_PATH}/metadata/backup-info.json" <<EOF
{
  "backup_name": "${BACKUP_NAME}",
  "backup_type": "${BACKUP_TYPE}",
  "timestamp": "${TIMESTAMP}",
  "date": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "user": "$(whoami)",
  "compression": "${COMPRESSION}",
  "encryption": "${ENABLE_ENCRYPTION}",
  "services": {
    "postgres": "$(docker inspect postgres --format '{{.Config.Image}}' 2>/dev/null || echo 'unknown')",
    "redis": "$(docker inspect redis --format '{{.Config.Image}}' 2>/dev/null || echo 'unknown')",
    "minio": "$(docker inspect minio1 --format '{{.Config.Image}}' 2>/dev/null || echo 'unknown')"
  },
  "retention_days": {
    "full": ${RETENTION_FULL},
    "incremental": ${RETENTION_INCREMENTAL}
  }
}
EOF

    log_success "Backup metadata created"
}

backup_postgresql() {
    log_info "Backing up PostgreSQL database..."

    local pg_backup_file="${BACKUP_PATH}/postgres/postgres-${TIMESTAMP}.sql"

    # Backup using pg_dump
    docker exec postgres pg_dumpall -U postgres > "$pg_backup_file" 2>/dev/null

    if [ ! -s "$pg_backup_file" ]; then
        log_error "PostgreSQL backup failed - backup file is empty"
        return 1
    fi

    # Compress if enabled
    if [ "$COMPRESSION" != "none" ]; then
        log_info "Compressing PostgreSQL backup..."
        $COMPRESSION -${COMPRESSION_LEVEL} "$pg_backup_file"
        pg_backup_file="${pg_backup_file}.gz"
    fi

    # Calculate checksum
    md5sum "$pg_backup_file" > "${pg_backup_file}.md5"

    local backup_size=$(du -h "$pg_backup_file" | cut -f1)
    log_success "PostgreSQL backup completed (size: ${backup_size})"
}

backup_redis() {
    log_info "Backing up Redis data..."

    local redis_backup_dir="${BACKUP_PATH}/redis"

    # Trigger Redis BGSAVE for consistent snapshot
    docker exec redis redis-cli BGSAVE > /dev/null

    # Wait for BGSAVE to complete (check every second, max 60 seconds)
    local wait_count=0
    while [ $wait_count -lt 60 ]; do
        if docker exec redis redis-cli LASTSAVE | grep -q "$(date +%s)"; then
            break
        fi
        sleep 1
        ((wait_count++))
    done

    # Copy RDB file from container
    docker cp redis:/data/dump.rdb "${redis_backup_dir}/dump-${TIMESTAMP}.rdb"

    if [ ! -f "${redis_backup_dir}/dump-${TIMESTAMP}.rdb" ]; then
        log_error "Redis backup failed - dump file not found"
        return 1
    fi

    # Compress if enabled
    if [ "$COMPRESSION" != "none" ]; then
        log_info "Compressing Redis backup..."
        $COMPRESSION -${COMPRESSION_LEVEL} "${redis_backup_dir}/dump-${TIMESTAMP}.rdb"
    fi

    # Calculate checksum
    local rdb_file="${redis_backup_dir}/dump-${TIMESTAMP}.rdb"
    [ "$COMPRESSION" != "none" ] && rdb_file="${rdb_file}.gz"
    md5sum "$rdb_file" > "${rdb_file}.md5"

    local backup_size=$(du -h "$rdb_file" | cut -f1)
    log_success "Redis backup completed (size: ${backup_size})"
}

backup_minio_data() {
    log_info "Backing up MinIO data (4-node cluster)..."

    local minio_backup_dir="${BACKUP_PATH}/minio"

    # Backup data from each MinIO node
    for node in minio1 minio2 minio3 minio4; do
        log_info "Backing up ${node}..."

        local node_backup="${minio_backup_dir}/${node}-${TIMESTAMP}.tar"

        # Export volume data (this captures object data)
        docker run --rm \
            --volumes-from "$node" \
            -v "${minio_backup_dir}:/backup" \
            alpine:latest \
            tar -czf "/backup/${node}-${TIMESTAMP}.tar.gz" /data 2>/dev/null || {
                log_warning "Failed to backup ${node}, continuing..."
                continue
            }

        # Calculate checksum
        md5sum "${minio_backup_dir}/${node}-${TIMESTAMP}.tar.gz" > "${minio_backup_dir}/${node}-${TIMESTAMP}.tar.gz.md5"

        local backup_size=$(du -h "${minio_backup_dir}/${node}-${TIMESTAMP}.tar.gz" | cut -f1)
        log_success "${node} backup completed (size: ${backup_size})"
    done

    log_success "MinIO cluster backup completed"
}

backup_configurations() {
    log_info "Backing up configuration files..."

    local config_backup_dir="${BACKUP_PATH}/configs"

    # Backup configuration files
    local config_dirs=(
        "${PROJECT_ROOT}/configs"
        "${PROJECT_ROOT}/deployments"
        "${PROJECT_ROOT}/.env"
    )

    for config_path in "${config_dirs[@]}"; do
        if [ -e "$config_path" ]; then
            local basename=$(basename "$config_path")
            cp -r "$config_path" "${config_backup_dir}/${basename}" 2>/dev/null || true
        fi
    done

    # Backup Docker Compose files
    cp "$COMPOSE_FILE" "${config_backup_dir}/docker-compose.production.yml" 2>/dev/null || true

    # Create archive
    tar -czf "${config_backup_dir}/configs-${TIMESTAMP}.tar.gz" -C "$config_backup_dir" . 2>/dev/null

    # Cleanup individual files (keep only archive)
    find "$config_backup_dir" -type f -not -name "*.tar.gz" -delete 2>/dev/null || true
    find "$config_backup_dir" -type d -empty -delete 2>/dev/null || true

    md5sum "${config_backup_dir}/configs-${TIMESTAMP}.tar.gz" > "${config_backup_dir}/configs-${TIMESTAMP}.tar.gz.md5"

    log_success "Configuration backup completed"
}

encrypt_backup() {
    if [ "$ENABLE_ENCRYPTION" = "true" ]; then
        log_info "Encrypting backup..."

        if [ ! -f "$ENCRYPTION_KEY_FILE" ]; then
            log_error "Encryption key file not found: ${ENCRYPTION_KEY_FILE}"
            log_info "Generate a key with: openssl rand -base64 32 > ${ENCRYPTION_KEY_FILE}"
            return 1
        fi

        # Encrypt all backup files
        find "$BACKUP_PATH" -type f \( -name "*.sql.gz" -o -name "*.rdb.gz" -o -name "*.tar.gz" \) | while read -r file; do
            openssl enc -aes-256-cbc -salt -in "$file" -out "${file}.enc" -pass file:"$ENCRYPTION_KEY_FILE"
            rm "$file"  # Remove unencrypted file
            log_info "Encrypted: $(basename "$file")"
        done

        log_success "Backup encryption completed"
    fi
}

verify_backup() {
    log_info "Verifying backup integrity..."

    local failed_checks=0

    # Verify checksums
    find "$BACKUP_PATH" -name "*.md5" | while read -r md5_file; do
        local dir=$(dirname "$md5_file")
        pushd "$dir" > /dev/null

        if md5sum -c "$(basename "$md5_file")" > /dev/null 2>&1; then
            log_info "✓ Checksum verified: $(basename "$md5_file")"
        else
            log_error "✗ Checksum failed: $(basename "$md5_file")"
            ((failed_checks++))
        fi

        popd > /dev/null
    done

    if [ $failed_checks -gt 0 ]; then
        log_error "Backup verification failed with ${failed_checks} errors"
        return 1
    fi

    log_success "Backup verification completed successfully"
}

create_backup_manifest() {
    log_info "Creating backup manifest..."

    cat > "${BACKUP_PATH}/MANIFEST.txt" <<EOF
MinIO Enterprise Backup Manifest
================================

Backup Name: ${BACKUP_NAME}
Backup Type: ${BACKUP_TYPE}
Timestamp: ${TIMESTAMP}
Date: $(date)

Contents:
---------
EOF

    find "$BACKUP_PATH" -type f -exec ls -lh {} \; | awk '{print $9, "(" $5 ")"}' >> "${BACKUP_PATH}/MANIFEST.txt"

    log_success "Backup manifest created"
}

cleanup_old_backups() {
    log_info "Cleaning up old backups (retention: ${RETENTION_FULL} days for full, ${RETENTION_INCREMENTAL} days for incremental)..."

    if [ "$BACKUP_TYPE" = "full" ]; then
        find "$BACKUP_DEST" -maxdepth 1 -type d -name "minio-backup-full-*" -mtime +${RETENTION_FULL} -exec rm -rf {} \; 2>/dev/null || true
    else
        find "$BACKUP_DEST" -maxdepth 1 -type d -name "minio-backup-incremental-*" -mtime +${RETENTION_INCREMENTAL} -exec rm -rf {} \; 2>/dev/null || true
    fi

    log_success "Old backups cleaned up"
}

# ============================================================
# Main Backup Process
# ============================================================

main() {
    echo "======================================================"
    echo "MinIO Enterprise Backup Script"
    echo "======================================================"
    echo ""

    log_info "Starting ${BACKUP_TYPE} backup..."
    log_info "Backup destination: ${BACKUP_PATH}"

    # Pre-flight checks
    check_dependencies
    verify_services_running

    # Create backup directory
    create_backup_directory

    # Backup metadata
    backup_metadata

    # Perform backups
    backup_postgresql
    backup_redis
    backup_minio_data
    backup_configurations

    # Post-backup operations
    encrypt_backup
    verify_backup
    create_backup_manifest

    # Cleanup
    cleanup_old_backups

    # Summary
    local total_size=$(du -sh "$BACKUP_PATH" | cut -f1)
    echo ""
    echo "======================================================"
    log_success "Backup completed successfully!"
    echo "======================================================"
    log_info "Backup location: ${BACKUP_PATH}"
    log_info "Backup size: ${total_size}"
    log_info "Log file: ${LOG_FILE}"
    echo ""
    log_info "To restore this backup, run:"
    echo "  ./restore.sh ${BACKUP_PATH}"
    echo ""
}

# ============================================================
# Script Entry Point
# ============================================================

# Validate arguments
if [ "$BACKUP_TYPE" != "full" ] && [ "$BACKUP_TYPE" != "incremental" ]; then
    echo "Error: Invalid backup type. Must be 'full' or 'incremental'"
    echo "Usage: $0 [full|incremental] [destination]"
    exit 1
fi

# Run main function
main "$@"
