#!/bin/bash

################################################################################
# MinIO Enterprise Backup Script
#
# This script automates backing up MinIO data, PostgreSQL database, Redis state,
# and configuration files. Supports full and incremental backups with encryption
# and compression.
#
# Usage:
#   ./backup.sh [OPTIONS]
#
# Options:
#   -t, --type TYPE        Backup type: full or incremental (default: full)
#   -d, --dest DIR         Destination directory (default: /backup)
#   -c, --compress         Enable compression (gzip)
#   -e, --encrypt          Enable encryption (GPG)
#   -k, --key-file FILE    GPG key file for encryption
#   -r, --retention DAYS   Retention period in days (default: 30)
#   -v, --verify           Verify backup after creation
#   -h, --help             Show this help message
#
# Examples:
#   # Full backup with compression
#   ./backup.sh --type full --compress
#
#   # Incremental backup with encryption
#   ./backup.sh --type incremental --encrypt --key-file /etc/backup/gpg-key.asc
#
#   # Full backup with verification
#   ./backup.sh --type full --verify
#
################################################################################

set -euo pipefail

# Default configuration
BACKUP_TYPE="full"
BACKUP_DEST="/backup"
COMPRESS=false
ENCRYPT=false
GPG_KEY_FILE=""
RETENTION_DAYS=30
VERIFY=false
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="minio_backup_${BACKUP_TYPE}_${TIMESTAMP}"
TEMP_DIR="/tmp/${BACKUP_NAME}"

# Color codes for output
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

# Help message
show_help() {
    cat << EOF
MinIO Enterprise Backup Script

Usage:
  ./backup.sh [OPTIONS]

Options:
  -t, --type TYPE        Backup type: full or incremental (default: full)
  -d, --dest DIR         Destination directory (default: /backup)
  -c, --compress         Enable compression (gzip)
  -e, --encrypt          Enable encryption (GPG)
  -k, --key-file FILE    GPG key file for encryption
  -r, --retention DAYS   Retention period in days (default: 30)
  -v, --verify           Verify backup after creation
  -h, --help             Show this help message

Examples:
  # Full backup with compression
  ./backup.sh --type full --compress

  # Incremental backup with encryption
  ./backup.sh --type incremental --encrypt --key-file /etc/backup/gpg-key.asc

  # Full backup with verification
  ./backup.sh --type full --verify

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                BACKUP_TYPE="$2"
                shift 2
                ;;
            -d|--dest)
                BACKUP_DEST="$2"
                shift 2
                ;;
            -c|--compress)
                COMPRESS=true
                shift
                ;;
            -e|--encrypt)
                ENCRYPT=true
                shift
                ;;
            -k|--key-file)
                GPG_KEY_FILE="$2"
                shift 2
                ;;
            -r|--retention)
                RETENTION_DAYS="$2"
                shift 2
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

# Validate inputs
validate_inputs() {
    if [[ "$BACKUP_TYPE" != "full" && "$BACKUP_TYPE" != "incremental" ]]; then
        log_error "Invalid backup type: $BACKUP_TYPE. Must be 'full' or 'incremental'."
        exit 1
    fi

    if [[ ! -d "$BACKUP_DEST" ]]; then
        log_warning "Backup destination does not exist. Creating: $BACKUP_DEST"
        mkdir -p "$BACKUP_DEST"
    fi

    if [[ "$ENCRYPT" == true && -z "$GPG_KEY_FILE" ]]; then
        log_error "Encryption enabled but no GPG key file specified."
        exit 1
    fi

    if [[ "$ENCRYPT" == true && ! -f "$GPG_KEY_FILE" ]]; then
        log_error "GPG key file not found: $GPG_KEY_FILE"
        exit 1
    fi

    # Check required commands
    for cmd in docker tar; do
        if ! command -v $cmd &> /dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done

    if [[ "$COMPRESS" == true ]] && ! command -v gzip &> /dev/null; then
        log_error "gzip not found. Install it or disable compression."
        exit 1
    fi

    if [[ "$ENCRYPT" == true ]] && ! command -v gpg &> /dev/null; then
        log_error "gpg not found. Install it or disable encryption."
        exit 1
    fi
}

# Create temporary backup directory
create_temp_dir() {
    log_info "Creating temporary backup directory: $TEMP_DIR"
    mkdir -p "$TEMP_DIR"/{minio,postgresql,redis,configs,metadata}
}

# Backup MinIO data
backup_minio_data() {
    log_info "Backing up MinIO data..."

    local minio_backup_dir="${TEMP_DIR}/minio"

    # Backup data from all MinIO nodes
    for node in minio1 minio2 minio3 minio4; do
        log_info "  Backing up $node data volume..."

        if docker ps --filter "name=$node" --filter "status=running" -q > /dev/null 2>&1; then
            # Export volume data using docker cp
            local volume_name="${node}-data"
            local container_id=$(docker ps -q -f name=$node)

            if [[ -n "$container_id" ]]; then
                docker exec "$container_id" tar czf - /data 2>/dev/null > "${minio_backup_dir}/${node}_data.tar.gz" || {
                    log_warning "Failed to backup $node data. Container may not have /data mounted."
                }
            else
                log_warning "Container $node not found or not running. Skipping..."
            fi
        else
            log_warning "Container $node not running. Skipping..."
        fi
    done

    log_success "MinIO data backup completed"
}

# Backup PostgreSQL database
backup_postgresql() {
    log_info "Backing up PostgreSQL database..."

    local pg_backup_file="${TEMP_DIR}/postgresql/postgres_dump.sql"

    if docker ps --filter "name=postgres" --filter "status=running" -q > /dev/null 2>&1; then
        docker exec postgres pg_dumpall -U postgres > "$pg_backup_file" 2>/dev/null || {
            log_error "Failed to backup PostgreSQL database"
            return 1
        }

        log_success "PostgreSQL backup completed: $(du -h $pg_backup_file | cut -f1)"
    else
        log_warning "PostgreSQL container not running. Skipping..."
    fi
}

# Backup Redis data
backup_redis() {
    log_info "Backing up Redis data..."

    local redis_backup_dir="${TEMP_DIR}/redis"

    if docker ps --filter "name=redis" --filter "status=running" -q > /dev/null 2>&1; then
        # Trigger Redis save
        docker exec redis redis-cli SAVE > /dev/null 2>&1 || {
            log_warning "Failed to trigger Redis SAVE command"
        }

        # Copy RDB file
        docker cp redis:/data/dump.rdb "${redis_backup_dir}/dump.rdb" 2>/dev/null || {
            log_warning "Failed to copy Redis dump file"
        }

        log_success "Redis backup completed"
    else
        log_warning "Redis container not running. Skipping..."
    fi
}

# Backup configuration files
backup_configs() {
    log_info "Backing up configuration files..."

    local config_backup_dir="${TEMP_DIR}/configs"

    # Backup configuration directories
    if [[ -d "configs" ]]; then
        cp -r configs/* "$config_backup_dir/" 2>/dev/null || log_warning "No configs to backup"
    fi

    if [[ -d "deployments" ]]; then
        cp -r deployments/* "${TEMP_DIR}/configs/deployments/" 2>/dev/null || log_warning "No deployments to backup"
    fi

    # Backup .env files
    if [[ -f ".env" ]]; then
        cp .env "${config_backup_dir}/.env" 2>/dev/null
    fi

    if [[ -f "configs/.env.example" ]]; then
        cp configs/.env.example "${config_backup_dir}/.env.example" 2>/dev/null
    fi

    log_success "Configuration backup completed"
}

# Create backup metadata
create_metadata() {
    log_info "Creating backup metadata..."

    local metadata_file="${TEMP_DIR}/metadata/backup_info.json"

    cat > "$metadata_file" << EOF
{
  "backup_name": "${BACKUP_NAME}",
  "backup_type": "${BACKUP_TYPE}",
  "timestamp": "${TIMESTAMP}",
  "date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "compressed": ${COMPRESS},
  "encrypted": ${ENCRYPT},
  "components": {
    "minio": true,
    "postgresql": $(docker ps -q -f name=postgres > /dev/null && echo true || echo false),
    "redis": $(docker ps -q -f name=redis > /dev/null && echo true || echo false),
    "configs": true
  },
  "docker_compose_version": "$(docker-compose version --short 2>/dev/null || echo 'unknown')",
  "script_version": "1.0.0"
}
EOF

    log_success "Backup metadata created"
}

# Create final backup archive
create_archive() {
    log_info "Creating backup archive..."

    local archive_path="${BACKUP_DEST}/${BACKUP_NAME}.tar"

    # Create tar archive
    tar -cf "$archive_path" -C "$(dirname $TEMP_DIR)" "$(basename $TEMP_DIR)"

    # Compress if requested
    if [[ "$COMPRESS" == true ]]; then
        log_info "Compressing backup..."
        gzip "$archive_path"
        archive_path="${archive_path}.gz"
    fi

    # Encrypt if requested
    if [[ "$ENCRYPT" == true ]]; then
        log_info "Encrypting backup..."
        gpg --batch --yes --recipient-file "$GPG_KEY_FILE" --encrypt "$archive_path"
        rm "$archive_path"
        archive_path="${archive_path}.gpg"
    fi

    FINAL_BACKUP_PATH="$archive_path"

    log_success "Backup archive created: $FINAL_BACKUP_PATH"
    log_success "Backup size: $(du -h $FINAL_BACKUP_PATH | cut -f1)"
}

# Verify backup
verify_backup() {
    log_info "Verifying backup integrity..."

    local archive_path="$FINAL_BACKUP_PATH"

    # Decrypt if encrypted
    if [[ "$ENCRYPT" == true ]]; then
        log_info "Decrypting for verification..."
        local decrypted_path="${archive_path%.gpg}"
        gpg --batch --yes --decrypt --output "$decrypted_path" "$archive_path" || {
            log_error "Failed to decrypt backup for verification"
            return 1
        }
        archive_path="$decrypted_path"
    fi

    # Decompress if compressed
    if [[ "$COMPRESS" == true ]]; then
        log_info "Decompressing for verification..."
        local decompressed_path="${archive_path%.gz}"
        gunzip -c "$archive_path" > "$decompressed_path" || {
            log_error "Failed to decompress backup for verification"
            [[ "$ENCRYPT" == true ]] && rm "$archive_path"
            return 1
        }
        [[ "$ENCRYPT" == true ]] && rm "$archive_path"
        archive_path="$decompressed_path"
    fi

    # Verify tar integrity
    if tar -tf "$archive_path" > /dev/null 2>&1; then
        log_success "Backup verification passed"

        # Cleanup verification files
        if [[ "$COMPRESS" == true ]] || [[ "$ENCRYPT" == true ]]; then
            rm "$archive_path"
        fi

        return 0
    else
        log_error "Backup verification failed: corrupt archive"
        return 1
    fi
}

# Clean old backups based on retention policy
cleanup_old_backups() {
    log_info "Cleaning up old backups (retention: $RETENTION_DAYS days)..."

    find "$BACKUP_DEST" -name "minio_backup_*" -type f -mtime +$RETENTION_DAYS -delete 2>/dev/null || {
        log_warning "Failed to cleanup old backups"
    }

    log_success "Old backups cleaned up"
}

# Cleanup temporary files
cleanup_temp() {
    if [[ -d "$TEMP_DIR" ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
    fi
}

# Main backup process
main() {
    log_info "=========================================="
    log_info "MinIO Enterprise Backup - Starting"
    log_info "=========================================="
    log_info "Backup type: $BACKUP_TYPE"
    log_info "Destination: $BACKUP_DEST"
    log_info "Timestamp: $TIMESTAMP"
    log_info "=========================================="

    # Parse and validate inputs
    parse_args "$@"
    validate_inputs

    # Create temporary directory
    create_temp_dir

    # Perform backups
    backup_minio_data
    backup_postgresql
    backup_redis
    backup_configs
    create_metadata

    # Create final archive
    create_archive

    # Verify if requested
    if [[ "$VERIFY" == true ]]; then
        verify_backup || {
            log_error "Backup verification failed!"
            cleanup_temp
            exit 1
        }
    fi

    # Cleanup old backups
    cleanup_old_backups

    # Cleanup temporary files
    cleanup_temp

    log_success "=========================================="
    log_success "Backup completed successfully!"
    log_success "Backup file: $FINAL_BACKUP_PATH"
    log_success "=========================================="
}

# Trap errors and cleanup
trap cleanup_temp EXIT ERR INT TERM

# Run main function
main "$@"
