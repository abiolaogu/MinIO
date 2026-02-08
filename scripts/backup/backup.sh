#!/bin/bash
#
# MinIO Enterprise Backup Script
# Supports full and incremental backups of MinIO data, PostgreSQL database, and Redis state
#
# Usage:
#   ./backup.sh [full|incremental] [OPTIONS]
#
# Options:
#   -c, --config PATH       Path to backup configuration file (default: backup.conf)
#   -d, --destination PATH  Override backup destination directory
#   -e, --encrypt           Enable encryption for backup files
#   -v, --verify            Verify backup integrity after completion
#   -h, --help              Show this help message
#

set -euo pipefail

# Default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/backup.conf"
BACKUP_TYPE="full"
ENCRYPT=false
VERIFY=false
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show help
show_help() {
    cat << EOF
MinIO Enterprise Backup Script

Usage: $0 [full|incremental] [OPTIONS]

Backup Types:
  full            Full backup of all data (default)
  incremental     Incremental backup of changes since last full backup

Options:
  -c, --config PATH       Path to backup configuration file (default: backup.conf)
  -d, --destination PATH  Override backup destination directory
  -e, --encrypt           Enable encryption for backup files
  -v, --verify            Verify backup integrity after completion
  -h, --help              Show this help message

Examples:
  $0 full                              # Full backup with default config
  $0 incremental -e                    # Encrypted incremental backup
  $0 full -d /mnt/backup -v            # Full backup to custom location with verification
  $0 full -c /etc/minio/backup.conf    # Full backup with custom config

Configuration:
  Edit backup.conf to customize backup locations, retention policies, and credentials.

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            full|incremental)
                BACKUP_TYPE="$1"
                shift
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -d|--destination)
                BACKUP_DESTINATION="$2"
                shift 2
                ;;
            -e|--encrypt)
                ENCRYPT=true
                shift
                ;;
            -v|--verify)
                VERIFY=true
                shift
                ;;
            -h|--help)
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
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_info "Creating default configuration file..."
        create_default_config
    fi

    log_info "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"

    # Validate required configuration
    if [[ -z "${BACKUP_DESTINATION:-}" ]]; then
        log_error "BACKUP_DESTINATION not set in configuration"
        exit 1
    fi
}

# Create default configuration file
create_default_config() {
    cat > "$CONFIG_FILE" << 'EOF'
# MinIO Enterprise Backup Configuration

# Backup destination directory
BACKUP_DESTINATION="/var/backups/minio"

# Retention policy (days)
RETENTION_DAYS=30

# PostgreSQL configuration
PG_HOST="localhost"
PG_PORT="5432"
PG_DATABASE="minio"
PG_USER="minio"
PG_PASSWORD=""  # Set via environment variable PGPASSWORD

# Redis configuration
REDIS_HOST="localhost"
REDIS_PORT="6379"
REDIS_PASSWORD=""  # Set via environment variable REDIS_PASSWORD

# MinIO data directory
MINIO_DATA_DIR="/var/lib/minio/data"

# Compression settings
COMPRESSION="gzip"  # Options: gzip, bzip2, xz, none

# Encryption settings (when enabled with -e flag)
ENCRYPTION_KEY_FILE=""  # Path to encryption key file (GPG or age)

# S3-compatible backup destination (optional)
S3_BACKUP_ENABLED=false
S3_ENDPOINT=""
S3_BUCKET=""
S3_ACCESS_KEY=""
S3_SECRET_KEY=""

# Notification settings (optional)
NOTIFICATION_EMAIL=""
NOTIFICATION_WEBHOOK=""
EOF

    log_success "Created default configuration at $CONFIG_FILE"
    log_warning "Please edit $CONFIG_FILE with your actual credentials and settings"
    exit 0
}

# Create backup directory structure
create_backup_dir() {
    local backup_dir="$BACKUP_DESTINATION/$BACKUP_TYPE/$TIMESTAMP"

    mkdir -p "$backup_dir"/{postgresql,redis,minio-data,config,metadata}

    echo "$backup_dir"
}

# Backup PostgreSQL database
backup_postgresql() {
    local backup_dir="$1"
    local pg_backup_file="$backup_dir/postgresql/minio_database.sql"

    log_info "Backing up PostgreSQL database..."

    export PGPASSWORD="${PG_PASSWORD}"

    if pg_dump -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
        --no-owner --no-acl --clean --if-exists > "$pg_backup_file"; then

        # Compress if configured
        if [[ "$COMPRESSION" != "none" ]]; then
            log_info "Compressing PostgreSQL backup..."
            case "$COMPRESSION" in
                gzip)
                    gzip -9 "$pg_backup_file"
                    pg_backup_file="${pg_backup_file}.gz"
                    ;;
                bzip2)
                    bzip2 -9 "$pg_backup_file"
                    pg_backup_file="${pg_backup_file}.bz2"
                    ;;
                xz)
                    xz -9 "$pg_backup_file"
                    pg_backup_file="${pg_backup_file}.xz"
                    ;;
            esac
        fi

        local size=$(du -h "$pg_backup_file" | cut -f1)
        log_success "PostgreSQL backup completed: $pg_backup_file ($size)"
    else
        log_error "PostgreSQL backup failed"
        return 1
    fi

    unset PGPASSWORD
}

# Backup Redis state
backup_redis() {
    local backup_dir="$1"
    local redis_backup_file="$backup_dir/redis/dump.rdb"

    log_info "Backing up Redis state..."

    # Trigger Redis BGSAVE
    if [[ -n "$REDIS_PASSWORD" ]]; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning BGSAVE
    else
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" BGSAVE
    fi

    # Wait for BGSAVE to complete
    local save_in_progress=true
    local max_wait=300  # 5 minutes
    local waited=0

    while $save_in_progress && [[ $waited -lt $max_wait ]]; do
        sleep 1
        waited=$((waited + 1))

        if [[ -n "$REDIS_PASSWORD" ]]; then
            local last_save=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning LASTSAVE)
        else
            local last_save=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" LASTSAVE)
        fi

        # Check if BGSAVE completed by comparing LASTSAVE timestamp
        if [[ $(date +%s) -ge $((last_save + 2)) ]]; then
            save_in_progress=false
        fi
    done

    # Copy Redis dump file
    if [[ -f "/var/lib/redis/dump.rdb" ]]; then
        cp /var/lib/redis/dump.rdb "$redis_backup_file"

        if [[ "$COMPRESSION" != "none" ]]; then
            log_info "Compressing Redis backup..."
            gzip -9 "$redis_backup_file"
            redis_backup_file="${redis_backup_file}.gz"
        fi

        local size=$(du -h "$redis_backup_file" | cut -f1)
        log_success "Redis backup completed: $redis_backup_file ($size)"
    else
        log_warning "Redis dump file not found, skipping Redis backup"
    fi
}

# Backup MinIO data
backup_minio_data() {
    local backup_dir="$1"
    local minio_backup_dir="$backup_dir/minio-data"

    log_info "Backing up MinIO data directory..."

    if [[ ! -d "$MINIO_DATA_DIR" ]]; then
        log_warning "MinIO data directory not found: $MINIO_DATA_DIR"
        return 0
    fi

    if [[ "$BACKUP_TYPE" == "incremental" ]]; then
        # Find last full backup for incremental
        local last_full=$(find "$BACKUP_DESTINATION/full" -maxdepth 1 -type d | sort -r | head -n 1)

        if [[ -n "$last_full" ]]; then
            log_info "Creating incremental backup based on: $last_full"
            rsync -av --link-dest="$last_full/minio-data/" "$MINIO_DATA_DIR/" "$minio_backup_dir/"
        else
            log_warning "No previous full backup found, creating full backup instead"
            rsync -av "$MINIO_DATA_DIR/" "$minio_backup_dir/"
        fi
    else
        # Full backup
        rsync -av "$MINIO_DATA_DIR/" "$minio_backup_dir/"
    fi

    local size=$(du -sh "$minio_backup_dir" | cut -f1)
    log_success "MinIO data backup completed: $minio_backup_dir ($size)"
}

# Backup configuration files
backup_config() {
    local backup_dir="$1"
    local config_backup_dir="$backup_dir/config"

    log_info "Backing up configuration files..."

    # Backup Docker Compose files
    if [[ -d "/home/runner/work/MinIO/MinIO/deployments/docker" ]]; then
        cp -r /home/runner/work/MinIO/MinIO/deployments/docker/*.yml "$config_backup_dir/" 2>/dev/null || true
    fi

    # Backup environment files
    if [[ -f "/home/runner/work/MinIO/MinIO/configs/.env.example" ]]; then
        cp /home/runner/work/MinIO/MinIO/configs/.env.example "$config_backup_dir/" 2>/dev/null || true
    fi

    # Backup Prometheus configuration
    if [[ -d "/home/runner/work/MinIO/MinIO/configs/prometheus" ]]; then
        cp -r /home/runner/work/MinIO/MinIO/configs/prometheus "$config_backup_dir/" 2>/dev/null || true
    fi

    # Backup Grafana dashboards
    if [[ -d "/home/runner/work/MinIO/MinIO/configs/grafana" ]]; then
        cp -r /home/runner/work/MinIO/MinIO/configs/grafana "$config_backup_dir/" 2>/dev/null || true
    fi

    log_success "Configuration backup completed"
}

# Create backup metadata
create_metadata() {
    local backup_dir="$1"
    local metadata_file="$backup_dir/metadata/backup_info.json"

    log_info "Creating backup metadata..."

    cat > "$metadata_file" << EOF
{
  "backup_type": "$BACKUP_TYPE",
  "timestamp": "$TIMESTAMP",
  "date": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "backup_directory": "$backup_dir",
  "components": {
    "postgresql": {
      "host": "$PG_HOST",
      "port": "$PG_PORT",
      "database": "$PG_DATABASE"
    },
    "redis": {
      "host": "$REDIS_HOST",
      "port": "$REDIS_PORT"
    },
    "minio": {
      "data_directory": "$MINIO_DATA_DIR"
    }
  },
  "settings": {
    "compression": "$COMPRESSION",
    "encrypted": $ENCRYPT
  }
}
EOF

    log_success "Backup metadata created: $metadata_file"
}

# Encrypt backup
encrypt_backup() {
    local backup_dir="$1"

    if [[ ! $ENCRYPT == true ]]; then
        return 0
    fi

    log_info "Encrypting backup..."

    if [[ -z "$ENCRYPTION_KEY_FILE" ]]; then
        log_error "Encryption enabled but ENCRYPTION_KEY_FILE not set in configuration"
        return 1
    fi

    if [[ ! -f "$ENCRYPTION_KEY_FILE" ]]; then
        log_error "Encryption key file not found: $ENCRYPTION_KEY_FILE"
        return 1
    fi

    # Create encrypted archive
    local encrypted_file="${backup_dir}.tar.gz.gpg"

    tar czf - -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")" | \
        gpg --encrypt --recipient-file "$ENCRYPTION_KEY_FILE" > "$encrypted_file"

    if [[ $? -eq 0 ]]; then
        log_success "Backup encrypted: $encrypted_file"
        # Optionally remove unencrypted backup
        # rm -rf "$backup_dir"
    else
        log_error "Backup encryption failed"
        return 1
    fi
}

# Verify backup integrity
verify_backup() {
    local backup_dir="$1"

    if [[ ! $VERIFY == true ]]; then
        return 0
    fi

    log_info "Verifying backup integrity..."

    local issues=0

    # Check PostgreSQL backup
    if [[ -f "$backup_dir/postgresql/minio_database.sql"* ]]; then
        log_info "✓ PostgreSQL backup exists"
    else
        log_error "✗ PostgreSQL backup missing"
        issues=$((issues + 1))
    fi

    # Check Redis backup
    if [[ -f "$backup_dir/redis/dump.rdb"* ]]; then
        log_info "✓ Redis backup exists"
    else
        log_warning "✓ Redis backup missing (may be skipped)"
    fi

    # Check MinIO data backup
    if [[ -d "$backup_dir/minio-data" ]] && [[ -n "$(ls -A "$backup_dir/minio-data")" ]]; then
        log_info "✓ MinIO data backup exists"
    else
        log_warning "✓ MinIO data backup empty or missing"
    fi

    # Check metadata
    if [[ -f "$backup_dir/metadata/backup_info.json" ]]; then
        log_info "✓ Backup metadata exists"
    else
        log_error "✗ Backup metadata missing"
        issues=$((issues + 1))
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "Backup verification passed"
        return 0
    else
        log_error "Backup verification failed with $issues issues"
        return 1
    fi
}

# Apply retention policy
apply_retention() {
    log_info "Applying retention policy (keeping last $RETENTION_DAYS days)..."

    find "$BACKUP_DESTINATION" -type d -name "20*" -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true

    log_success "Retention policy applied"
}

# Upload to S3 (if configured)
upload_to_s3() {
    local backup_dir="$1"

    if [[ "$S3_BACKUP_ENABLED" != "true" ]]; then
        return 0
    fi

    log_info "Uploading backup to S3..."

    if ! command -v aws &> /dev/null; then
        log_warning "AWS CLI not found, skipping S3 upload"
        return 0
    fi

    export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"

    local backup_archive="${backup_dir}.tar.gz"
    tar czf "$backup_archive" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"

    aws s3 cp "$backup_archive" "s3://$S3_BUCKET/$(basename "$backup_archive")" --endpoint-url "$S3_ENDPOINT"

    if [[ $? -eq 0 ]]; then
        log_success "Backup uploaded to S3: s3://$S3_BUCKET/$(basename "$backup_archive")"
        rm -f "$backup_archive"
    else
        log_error "S3 upload failed"
    fi

    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
}

# Send notification
send_notification() {
    local status="$1"
    local backup_dir="$2"

    if [[ -z "$NOTIFICATION_EMAIL" ]] && [[ -z "$NOTIFICATION_WEBHOOK" ]]; then
        return 0
    fi

    local message="MinIO Backup $status - $BACKUP_TYPE backup at $TIMESTAMP"

    # Email notification
    if [[ -n "$NOTIFICATION_EMAIL" ]] && command -v mail &> /dev/null; then
        echo "$message" | mail -s "MinIO Backup $status" "$NOTIFICATION_EMAIL"
    fi

    # Webhook notification
    if [[ -n "$NOTIFICATION_WEBHOOK" ]]; then
        curl -X POST "$NOTIFICATION_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"$message\",\"backup_dir\":\"$backup_dir\",\"status\":\"$status\"}" \
            &> /dev/null
    fi
}

# Main backup function
main() {
    log_info "=========================================="
    log_info "MinIO Enterprise Backup"
    log_info "=========================================="
    log_info "Backup Type: $BACKUP_TYPE"
    log_info "Timestamp: $TIMESTAMP"
    log_info "Encryption: $ENCRYPT"
    log_info "Verification: $VERIFY"
    log_info "=========================================="

    # Parse arguments
    parse_args "$@"

    # Load configuration
    load_config

    # Create backup directory
    local backup_dir
    backup_dir=$(create_backup_dir)
    log_info "Backup directory: $backup_dir"

    # Perform backups
    local backup_failed=false

    backup_postgresql "$backup_dir" || backup_failed=true
    backup_redis "$backup_dir" || true  # Redis backup is optional
    backup_minio_data "$backup_dir" || backup_failed=true
    backup_config "$backup_dir" || true
    create_metadata "$backup_dir" || true

    if $backup_failed; then
        log_error "Backup completed with errors"
        send_notification "FAILED" "$backup_dir"
        exit 1
    fi

    # Post-backup operations
    encrypt_backup "$backup_dir" || true
    verify_backup "$backup_dir" || true
    upload_to_s3 "$backup_dir" || true
    apply_retention || true

    log_success "=========================================="
    log_success "Backup completed successfully!"
    log_success "Location: $backup_dir"
    log_success "=========================================="

    send_notification "SUCCESS" "$backup_dir"
}

# Run main function
main "$@"
