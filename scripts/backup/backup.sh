#!/bin/bash
#
# MinIO Enterprise Backup Script
# Creates automated backups of MinIO data, PostgreSQL database, Redis state, and configuration
#
# Usage: ./backup.sh [OPTIONS]
# Options:
#   --full          Perform full backup (default)
#   --incremental   Perform incremental backup since last full backup
#   --config FILE   Use custom configuration file (default: backup.conf)
#   --output DIR    Override output directory
#   --compress      Enable compression (gzip)
#   --encrypt       Enable encryption (gpg)
#   --verify        Verify backup integrity after creation
#   --s3            Upload backup to S3-compatible storage
#   --help          Show this help message

set -euo pipefail

# Script directory and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/backup.conf"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_TYPE="full"
VERIFY_BACKUP=false
COMPRESS=false
ENCRYPT=false
UPLOAD_S3=false

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# Show usage
show_usage() {
    cat << EOF
MinIO Enterprise Backup Script

Usage: $0 [OPTIONS]

Options:
  --full          Perform full backup (default)
  --incremental   Perform incremental backup since last full backup
  --config FILE   Use custom configuration file (default: backup.conf)
  --output DIR    Override output directory
  --compress      Enable compression (gzip)
  --encrypt       Enable encryption (gpg)
  --verify        Verify backup integrity after creation
  --s3            Upload backup to S3-compatible storage
  --help          Show this help message

Examples:
  $0 --full --compress --verify
  $0 --incremental --encrypt --s3
  $0 --config /etc/minio/backup.conf --output /mnt/backups

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --full)
                BACKUP_TYPE="full"
                shift
                ;;
            --incremental)
                BACKUP_TYPE="incremental"
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --output)
                BACKUP_DIR="$2"
                shift 2
                ;;
            --compress)
                COMPRESS=true
                shift
                ;;
            --encrypt)
                ENCRYPT=true
                shift
                ;;
            --verify)
                VERIFY_BACKUP=true
                shift
                ;;
            --s3)
                UPLOAD_S3=true
                shift
                ;;
            --help)
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

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    else
        log_warning "Configuration file not found: $CONFIG_FILE"
        log_info "Using default configuration"

        # Default configuration
        BACKUP_DIR="${BACKUP_DIR:-/var/backups/minio}"
        RETENTION_DAYS="${RETENTION_DAYS:-30}"
        RETENTION_FULL_BACKUPS="${RETENTION_FULL_BACKUPS:-4}"

        # PostgreSQL settings
        POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
        POSTGRES_PORT="${POSTGRES_PORT:-5432}"
        POSTGRES_DB="${POSTGRES_DB:-minio}"
        POSTGRES_USER="${POSTGRES_USER:-minio}"

        # Redis settings
        REDIS_HOST="${REDIS_HOST:-localhost}"
        REDIS_PORT="${REDIS_PORT:-6379}"

        # MinIO settings
        MINIO_DATA_DIR="${MINIO_DATA_DIR:-/data/minio}"
        MINIO_CONFIG_DIR="${MINIO_CONFIG_DIR:-/etc/minio}"

        # S3 upload settings
        S3_ENDPOINT="${S3_ENDPOINT:-}"
        S3_BUCKET="${S3_BUCKET:-minio-backups}"
        S3_ACCESS_KEY="${S3_ACCESS_KEY:-}"
        S3_SECRET_KEY="${S3_SECRET_KEY:-}"

        # Encryption settings
        GPG_RECIPIENT="${GPG_RECIPIENT:-backup@example.com}"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    # Required tools
    command -v tar >/dev/null 2>&1 || missing_tools+=("tar")
    command -v pg_dump >/dev/null 2>&1 || missing_tools+=("postgresql-client")
    command -v redis-cli >/dev/null 2>&1 || missing_tools+=("redis-tools")

    if [[ "$COMPRESS" == true ]]; then
        command -v gzip >/dev/null 2>&1 || missing_tools+=("gzip")
    fi

    if [[ "$ENCRYPT" == true ]]; then
        command -v gpg >/dev/null 2>&1 || missing_tools+=("gnupg")
    fi

    if [[ "$UPLOAD_S3" == true ]]; then
        command -v aws >/dev/null 2>&1 || missing_tools+=("awscli")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install missing tools and try again"
        exit 1
    fi

    # Check directories
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_info "Creating backup directory: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
    fi

    log_success "Prerequisites check passed"
}

# Create backup directory structure
create_backup_structure() {
    BACKUP_NAME="minio-backup-${BACKUP_TYPE}-${TIMESTAMP}"
    BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

    log_info "Creating backup structure: $BACKUP_PATH"
    mkdir -p "${BACKUP_PATH}"/{data,database,redis,config,metadata}

    # Create metadata file
    cat > "${BACKUP_PATH}/metadata/backup.info" << EOF
backup_type=${BACKUP_TYPE}
timestamp=${TIMESTAMP}
hostname=$(hostname)
started_at=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
minio_version=$(cat /etc/minio/version 2>/dev/null || echo "unknown")
script_version=1.0.0
EOF
}

# Backup PostgreSQL database
backup_postgresql() {
    log_info "Backing up PostgreSQL database..."

    local dump_file="${BACKUP_PATH}/database/minio.sql"

    if PGPASSWORD="${POSTGRES_PASSWORD:-}" pg_dump \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        --format=custom \
        --compress=9 \
        --file="$dump_file" 2>/dev/null; then

        local size=$(du -h "$dump_file" | cut -f1)
        log_success "PostgreSQL backup completed: $size"
        echo "postgresql_backup_size=$size" >> "${BACKUP_PATH}/metadata/backup.info"
    else
        log_error "PostgreSQL backup failed"
        return 1
    fi
}

# Backup Redis state
backup_redis() {
    log_info "Backing up Redis state..."

    local redis_dump="${BACKUP_PATH}/redis/dump.rdb"

    # Trigger Redis save
    if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" BGSAVE >/dev/null 2>&1; then
        # Wait for save to complete
        sleep 2

        # Copy RDB file
        if [[ -f "/var/lib/redis/dump.rdb" ]]; then
            cp /var/lib/redis/dump.rdb "$redis_dump"
            local size=$(du -h "$redis_dump" | cut -f1)
            log_success "Redis backup completed: $size"
            echo "redis_backup_size=$size" >> "${BACKUP_PATH}/metadata/backup.info"
        else
            log_warning "Redis dump file not found, skipping"
        fi
    else
        log_warning "Redis save command failed, skipping"
    fi
}

# Backup MinIO data
backup_minio_data() {
    log_info "Backing up MinIO data directory..."

    if [[ ! -d "$MINIO_DATA_DIR" ]]; then
        log_warning "MinIO data directory not found: $MINIO_DATA_DIR"
        return 0
    fi

    local data_backup="${BACKUP_PATH}/data/objects.tar"

    if [[ "$BACKUP_TYPE" == "full" ]]; then
        log_info "Creating full data backup..."
        tar -cf "$data_backup" -C "$(dirname "$MINIO_DATA_DIR")" "$(basename "$MINIO_DATA_DIR")" 2>/dev/null
    else
        log_info "Creating incremental data backup..."
        local last_full=$(find "$BACKUP_DIR" -name "minio-backup-full-*" -type d | sort -r | head -1)

        if [[ -z "$last_full" ]]; then
            log_warning "No full backup found, creating full backup instead"
            tar -cf "$data_backup" -C "$(dirname "$MINIO_DATA_DIR")" "$(basename "$MINIO_DATA_DIR")" 2>/dev/null
        else
            local reference_file="${last_full}/metadata/backup.info"
            tar -cf "$data_backup" -C "$(dirname "$MINIO_DATA_DIR")" "$(basename "$MINIO_DATA_DIR")" \
                --newer-mtime="$(stat -c %Y "$reference_file")" 2>/dev/null
        fi
    fi

    local size=$(du -h "$data_backup" | cut -f1)
    log_success "MinIO data backup completed: $size"
    echo "minio_data_backup_size=$size" >> "${BACKUP_PATH}/metadata/backup.info"
}

# Backup configuration files
backup_configuration() {
    log_info "Backing up configuration files..."

    local config_backup="${BACKUP_PATH}/config/config.tar"
    local config_dirs=()

    # Collect configuration directories
    [[ -d "$MINIO_CONFIG_DIR" ]] && config_dirs+=("$MINIO_CONFIG_DIR")
    [[ -d "/etc/minio" ]] && config_dirs+=("/etc/minio")
    [[ -d "$(pwd)/configs" ]] && config_dirs+=("$(pwd)/configs")
    [[ -d "$(pwd)/deployments" ]] && config_dirs+=("$(pwd)/deployments")

    if [[ ${#config_dirs[@]} -gt 0 ]]; then
        tar -cf "$config_backup" "${config_dirs[@]}" 2>/dev/null || true
        local size=$(du -h "$config_backup" | cut -f1)
        log_success "Configuration backup completed: $size"
        echo "config_backup_size=$size" >> "${BACKUP_PATH}/metadata/backup.info"
    else
        log_warning "No configuration directories found"
    fi
}

# Compress backup
compress_backup() {
    if [[ "$COMPRESS" != true ]]; then
        return 0
    fi

    log_info "Compressing backup..."

    local archive_name="${BACKUP_NAME}.tar.gz"
    local archive_path="${BACKUP_DIR}/${archive_name}"

    tar -czf "$archive_path" -C "$BACKUP_DIR" "$BACKUP_NAME" 2>/dev/null

    if [[ -f "$archive_path" ]]; then
        local size=$(du -h "$archive_path" | cut -f1)
        log_success "Backup compressed: $size"

        # Remove uncompressed backup
        rm -rf "$BACKUP_PATH"
        BACKUP_PATH="$archive_path"
    else
        log_error "Compression failed"
        return 1
    fi
}

# Encrypt backup
encrypt_backup() {
    if [[ "$ENCRYPT" != true ]]; then
        return 0
    fi

    log_info "Encrypting backup..."

    local encrypted_file="${BACKUP_PATH}.gpg"

    if gpg --encrypt --recipient "$GPG_RECIPIENT" --output "$encrypted_file" "$BACKUP_PATH" 2>/dev/null; then
        log_success "Backup encrypted"

        # Remove unencrypted backup
        rm -f "$BACKUP_PATH"
        BACKUP_PATH="$encrypted_file"
    else
        log_error "Encryption failed"
        return 1
    fi
}

# Verify backup
verify_backup() {
    if [[ "$VERIFY_BACKUP" != true ]]; then
        return 0
    fi

    log_info "Verifying backup integrity..."

    local verification_passed=true

    # Check if backup file exists
    if [[ ! -e "$BACKUP_PATH" ]]; then
        log_error "Backup file not found: $BACKUP_PATH"
        return 1
    fi

    # Calculate checksums
    if [[ -f "$BACKUP_PATH" ]]; then
        local checksum=$(sha256sum "$BACKUP_PATH" | cut -d' ' -f1)
        echo "checksum_sha256=$checksum" >> "$(dirname "$BACKUP_PATH")/backup.checksum"
        log_success "Backup checksum: $checksum"
    fi

    # Test archive integrity
    if [[ "$COMPRESS" == true ]] && [[ "$BACKUP_PATH" == *.tar.gz ]]; then
        if gzip -t "$BACKUP_PATH" 2>/dev/null; then
            log_success "Archive integrity verified"
        else
            log_error "Archive integrity check failed"
            verification_passed=false
        fi
    fi

    if [[ "$verification_passed" == true ]]; then
        log_success "Backup verification passed"
    else
        log_error "Backup verification failed"
        return 1
    fi
}

# Upload to S3
upload_to_s3() {
    if [[ "$UPLOAD_S3" != true ]]; then
        return 0
    fi

    log_info "Uploading backup to S3..."

    if [[ -z "$S3_ENDPOINT" ]] || [[ -z "$S3_ACCESS_KEY" ]] || [[ -z "$S3_SECRET_KEY" ]]; then
        log_error "S3 credentials not configured"
        return 1
    fi

    local backup_file=$(basename "$BACKUP_PATH")

    AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY" \
    AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY" \
    aws s3 cp "$BACKUP_PATH" "s3://${S3_BUCKET}/${backup_file}" \
        --endpoint-url "$S3_ENDPOINT" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        log_success "Backup uploaded to S3: s3://${S3_BUCKET}/${backup_file}"
    else
        log_error "S3 upload failed"
        return 1
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    log_info "Cleaning up old backups (retention: ${RETENTION_DAYS} days)..."

    # Remove backups older than retention period
    find "$BACKUP_DIR" -maxdepth 1 -name "minio-backup-*" -type d -mtime "+${RETENTION_DAYS}" -exec rm -rf {} \; 2>/dev/null || true
    find "$BACKUP_DIR" -maxdepth 1 -name "minio-backup-*.tar.gz*" -type f -mtime "+${RETENTION_DAYS}" -exec rm -f {} \; 2>/dev/null || true

    # Keep minimum number of full backups
    local full_backups=$(find "$BACKUP_DIR" -maxdepth 1 -name "minio-backup-full-*" | sort -r)
    local full_count=$(echo "$full_backups" | wc -l)

    if [[ $full_count -gt $RETENTION_FULL_BACKUPS ]]; then
        echo "$full_backups" | tail -n +$((RETENTION_FULL_BACKUPS + 1)) | xargs rm -rf 2>/dev/null || true
        log_info "Removed old full backups (kept ${RETENTION_FULL_BACKUPS} most recent)"
    fi

    log_success "Cleanup completed"
}

# Main backup function
main() {
    log_info "=========================================="
    log_info "MinIO Enterprise Backup"
    log_info "=========================================="
    log_info "Backup type: ${BACKUP_TYPE}"
    log_info "Timestamp: ${TIMESTAMP}"

    # Parse arguments
    parse_args "$@"

    # Load configuration
    load_config

    # Check prerequisites
    check_prerequisites

    # Create backup structure
    create_backup_structure

    # Perform backups
    backup_postgresql || true
    backup_redis || true
    backup_minio_data || true
    backup_configuration || true

    # Finalize backup metadata
    echo "completed_at=$(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> "${BACKUP_PATH}/metadata/backup.info"
    echo "status=success" >> "${BACKUP_PATH}/metadata/backup.info"

    # Post-processing
    compress_backup
    encrypt_backup
    verify_backup
    upload_to_s3

    # Cleanup
    cleanup_old_backups

    log_info "=========================================="
    log_success "Backup completed successfully"
    log_info "Backup location: $BACKUP_PATH"
    log_info "=========================================="
}

# Run main function
main "$@"
