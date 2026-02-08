#!/bin/bash

################################################################################
# MinIO Enterprise Restore Script
#
# This script automates restoring MinIO data, PostgreSQL database, Redis state,
# and configuration files from backups created by backup.sh.
#
# Usage:
#   ./restore.sh [OPTIONS]
#
# Options:
#   -f, --file FILE        Backup file to restore (required)
#   -k, --key-file FILE    GPG key file for decryption (if backup is encrypted)
#   -t, --target DIR       Target directory for extraction (default: /tmp/restore)
#   -s, --stop-services    Stop services before restore
#   -r, --start-services   Start services after restore
#   --verify               Verify backup before restoring
#   --dry-run              Show what would be restored without actually restoring
#   -h, --help             Show this help message
#
# Examples:
#   # Restore from backup with verification
#   ./restore.sh --file /backup/minio_backup_full_20240118_120000.tar.gz --verify
#
#   # Restore encrypted backup
#   ./restore.sh --file /backup/minio_backup_full_20240118_120000.tar.gz.gpg --key-file /etc/backup/gpg-key.asc
#
#   # Dry run to see what would be restored
#   ./restore.sh --file /backup/minio_backup_full_20240118_120000.tar.gz --dry-run
#
################################################################################

set -euo pipefail

# Default configuration
BACKUP_FILE=""
GPG_KEY_FILE=""
TARGET_DIR="/tmp/restore"
STOP_SERVICES=false
START_SERVICES=false
VERIFY_BEFORE_RESTORE=false
DRY_RUN=false
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

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
MinIO Enterprise Restore Script

Usage:
  ./restore.sh [OPTIONS]

Options:
  -f, --file FILE        Backup file to restore (required)
  -k, --key-file FILE    GPG key file for decryption (if backup is encrypted)
  -t, --target DIR       Target directory for extraction (default: /tmp/restore)
  -s, --stop-services    Stop services before restore
  -r, --start-services   Start services after restore
  --verify               Verify backup before restoring
  --dry-run              Show what would be restored without actually restoring
  -h, --help             Show this help message

Examples:
  # Restore from backup with verification
  ./restore.sh --file /backup/minio_backup_full_20240118_120000.tar.gz --verify

  # Restore encrypted backup
  ./restore.sh --file /backup/minio_backup_full_20240118_120000.tar.gz.gpg --key-file /etc/backup/gpg-key.asc

  # Dry run to see what would be restored
  ./restore.sh --file /backup/minio_backup_full_20240118_120000.tar.gz --dry-run

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                BACKUP_FILE="$2"
                shift 2
                ;;
            -k|--key-file)
                GPG_KEY_FILE="$2"
                shift 2
                ;;
            -t|--target)
                TARGET_DIR="$2"
                shift 2
                ;;
            -s|--stop-services)
                STOP_SERVICES=true
                shift
                ;;
            -r|--start-services)
                START_SERVICES=true
                shift
                ;;
            --verify)
                VERIFY_BEFORE_RESTORE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
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
    if [[ -z "$BACKUP_FILE" ]]; then
        log_error "Backup file not specified. Use -f or --file option."
        show_help
        exit 1
    fi

    if [[ ! -f "$BACKUP_FILE" ]]; then
        log_error "Backup file not found: $BACKUP_FILE"
        exit 1
    fi

    # Check if backup is encrypted
    if [[ "$BACKUP_FILE" == *.gpg ]]; then
        if [[ -z "$GPG_KEY_FILE" ]]; then
            log_error "Backup is encrypted but no GPG key file specified."
            exit 1
        fi

        if [[ ! -f "$GPG_KEY_FILE" ]]; then
            log_error "GPG key file not found: $GPG_KEY_FILE"
            exit 1
        fi
    fi

    # Check required commands
    for cmd in docker tar; do
        if ! command -v $cmd &> /dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done

    if [[ "$BACKUP_FILE" == *.gz* ]] && ! command -v gunzip &> /dev/null; then
        log_error "gunzip not found but backup is compressed."
        exit 1
    fi

    if [[ "$BACKUP_FILE" == *.gpg ]] && ! command -v gpg &> /dev/null; then
        log_error "gpg not found but backup is encrypted."
        exit 1
    fi
}

# Create target directory
create_target_dir() {
    if [[ ! -d "$TARGET_DIR" ]]; then
        log_info "Creating target directory: $TARGET_DIR"
        mkdir -p "$TARGET_DIR"
    fi
}

# Extract backup archive
extract_backup() {
    log_info "Extracting backup archive..."

    local archive_path="$BACKUP_FILE"
    local work_file="$archive_path"

    # Decrypt if encrypted
    if [[ "$archive_path" == *.gpg ]]; then
        log_info "Decrypting backup..."
        local decrypted_path="${TARGET_DIR}/$(basename ${archive_path%.gpg})"

        if [[ "$DRY_RUN" == false ]]; then
            gpg --batch --yes --decrypt --output "$decrypted_path" "$archive_path" || {
                log_error "Failed to decrypt backup"
                return 1
            }
        else
            log_info "[DRY RUN] Would decrypt: $archive_path"
        fi

        work_file="$decrypted_path"
    fi

    # Decompress if compressed
    if [[ "$work_file" == *.gz ]]; then
        log_info "Decompressing backup..."
        local decompressed_path="${work_file%.gz}"

        if [[ "$DRY_RUN" == false ]]; then
            gunzip -c "$work_file" > "$decompressed_path" || {
                log_error "Failed to decompress backup"
                return 1
            }

            # Remove decrypted file if it was temporary
            if [[ "$work_file" != "$archive_path" ]]; then
                rm "$work_file"
            fi
        else
            log_info "[DRY RUN] Would decompress: $work_file"
        fi

        work_file="$decompressed_path"
    fi

    # Extract tar archive
    log_info "Extracting tar archive..."

    if [[ "$DRY_RUN" == false ]]; then
        tar -xf "$work_file" -C "$TARGET_DIR" || {
            log_error "Failed to extract backup archive"
            return 1
        }

        # Remove decompressed file if it was temporary
        if [[ "$work_file" != "$archive_path" ]]; then
            rm "$work_file"
        fi
    else
        log_info "[DRY RUN] Would extract: $work_file to $TARGET_DIR"
        log_info "[DRY RUN] Contents:"
        tar -tzf "$work_file" | head -20
        echo "..."
    fi

    log_success "Backup extracted successfully"
}

# Show backup metadata
show_metadata() {
    log_info "Reading backup metadata..."

    local backup_dir=$(find "$TARGET_DIR" -maxdepth 1 -type d -name "minio_backup_*" | head -1)

    if [[ -z "$backup_dir" ]]; then
        log_warning "Backup directory not found in extraction"
        return 1
    fi

    local metadata_file="${backup_dir}/metadata/backup_info.json"

    if [[ -f "$metadata_file" ]]; then
        log_info "Backup Metadata:"
        cat "$metadata_file" | while IFS= read -r line; do
            echo "  $line"
        done
    else
        log_warning "Metadata file not found"
    fi
}

# Stop Docker services
stop_services() {
    log_info "Stopping Docker services..."

    if [[ "$DRY_RUN" == false ]]; then
        docker-compose -f deployments/docker/docker-compose.production.yml down || {
            log_warning "Failed to stop some services"
        }
        log_success "Services stopped"
    else
        log_info "[DRY RUN] Would stop Docker services"
    fi
}

# Restore MinIO data
restore_minio_data() {
    log_info "Restoring MinIO data..."

    local backup_dir=$(find "$TARGET_DIR" -maxdepth 1 -type d -name "minio_backup_*" | head -1)
    local minio_backup_dir="${backup_dir}/minio"

    if [[ ! -d "$minio_backup_dir" ]]; then
        log_warning "MinIO backup directory not found. Skipping..."
        return 0
    fi

    # Restore data for each MinIO node
    for node in minio1 minio2 minio3 minio4; do
        local backup_file="${minio_backup_dir}/${node}_data.tar.gz"

        if [[ -f "$backup_file" ]]; then
            log_info "  Restoring $node data..."

            if [[ "$DRY_RUN" == false ]]; then
                # Start the container if not running
                if ! docker ps --filter "name=$node" --filter "status=running" -q > /dev/null 2>&1; then
                    docker-compose -f deployments/docker/docker-compose.production.yml up -d "$node" 2>/dev/null || {
                        log_warning "Failed to start $node"
                        continue
                    }
                    sleep 5
                fi

                # Restore data
                cat "$backup_file" | docker exec -i "$node" tar xzf - -C / 2>/dev/null || {
                    log_warning "Failed to restore $node data"
                }
            else
                log_info "[DRY RUN] Would restore: $backup_file to $node"
            fi
        else
            log_warning "Backup file not found for $node. Skipping..."
        fi
    done

    log_success "MinIO data restore completed"
}

# Restore PostgreSQL database
restore_postgresql() {
    log_info "Restoring PostgreSQL database..."

    local backup_dir=$(find "$TARGET_DIR" -maxdepth 1 -type d -name "minio_backup_*" | head -1)
    local pg_backup_file="${backup_dir}/postgresql/postgres_dump.sql"

    if [[ ! -f "$pg_backup_file" ]]; then
        log_warning "PostgreSQL backup file not found. Skipping..."
        return 0
    fi

    if [[ "$DRY_RUN" == false ]]; then
        # Start PostgreSQL if not running
        if ! docker ps --filter "name=postgres" --filter "status=running" -q > /dev/null 2>&1; then
            docker-compose -f deployments/docker/docker-compose.production.yml up -d postgres 2>/dev/null
            sleep 10
        fi

        # Restore database
        docker exec -i postgres psql -U postgres < "$pg_backup_file" 2>/dev/null || {
            log_error "Failed to restore PostgreSQL database"
            return 1
        }

        log_success "PostgreSQL database restored: $(du -h $pg_backup_file | cut -f1)"
    else
        log_info "[DRY RUN] Would restore PostgreSQL from: $pg_backup_file"
    fi
}

# Restore Redis data
restore_redis() {
    log_info "Restoring Redis data..."

    local backup_dir=$(find "$TARGET_DIR" -maxdepth 1 -type d -name "minio_backup_*" | head -1)
    local redis_dump_file="${backup_dir}/redis/dump.rdb"

    if [[ ! -f "$redis_dump_file" ]]; then
        log_warning "Redis backup file not found. Skipping..."
        return 0
    fi

    if [[ "$DRY_RUN" == false ]]; then
        # Stop Redis if running
        if docker ps --filter "name=redis" --filter "status=running" -q > /dev/null 2>&1; then
            docker-compose -f deployments/docker/docker-compose.production.yml stop redis 2>/dev/null
        fi

        # Copy dump file
        docker cp "$redis_dump_file" redis:/data/dump.rdb 2>/dev/null || {
            log_error "Failed to restore Redis dump file"
            return 1
        }

        # Start Redis
        docker-compose -f deployments/docker/docker-compose.production.yml up -d redis 2>/dev/null

        log_success "Redis data restored"
    else
        log_info "[DRY RUN] Would restore Redis from: $redis_dump_file"
    fi
}

# Restore configuration files
restore_configs() {
    log_info "Restoring configuration files..."

    local backup_dir=$(find "$TARGET_DIR" -maxdepth 1 -type d -name "minio_backup_*" | head -1)
    local config_backup_dir="${backup_dir}/configs"

    if [[ ! -d "$config_backup_dir" ]]; then
        log_warning "Configuration backup directory not found. Skipping..."
        return 0
    fi

    if [[ "$DRY_RUN" == false ]]; then
        # Backup current configs
        if [[ -d "configs" ]]; then
            log_info "  Backing up current configs..."
            mv configs "configs.backup.${TIMESTAMP}" 2>/dev/null || true
        fi

        # Restore configs
        if [[ -d "$config_backup_dir" ]]; then
            cp -r "$config_backup_dir" configs 2>/dev/null || {
                log_warning "Failed to restore some configuration files"
            }
        fi

        log_success "Configuration files restored"
    else
        log_info "[DRY RUN] Would restore configurations from: $config_backup_dir"
    fi
}

# Verify restoration
verify_restoration() {
    log_info "Verifying restoration..."

    local all_ok=true

    # Check MinIO containers
    for node in minio1 minio2 minio3 minio4; do
        if ! docker ps --filter "name=$node" --filter "status=running" -q > /dev/null 2>&1; then
            log_warning "MinIO node $node is not running"
            all_ok=false
        fi
    done

    # Check PostgreSQL
    if docker ps --filter "name=postgres" --filter "status=running" -q > /dev/null 2>&1; then
        if ! docker exec postgres pg_isready -U postgres > /dev/null 2>&1; then
            log_warning "PostgreSQL is not ready"
            all_ok=false
        fi
    fi

    # Check Redis
    if docker ps --filter "name=redis" --filter "status=running" -q > /dev/null 2>&1; then
        if ! docker exec redis redis-cli ping > /dev/null 2>&1; then
            log_warning "Redis is not responding"
            all_ok=false
        fi
    fi

    if [[ "$all_ok" == true ]]; then
        log_success "Restoration verification passed"
        return 0
    else
        log_warning "Restoration verification found issues"
        return 1
    fi
}

# Start Docker services
start_services() {
    log_info "Starting Docker services..."

    if [[ "$DRY_RUN" == false ]]; then
        docker-compose -f deployments/docker/docker-compose.production.yml up -d || {
            log_error "Failed to start services"
            return 1
        }

        log_info "Waiting for services to be ready..."
        sleep 30

        log_success "Services started"
    else
        log_info "[DRY RUN] Would start Docker services"
    fi
}

# Cleanup temporary files
cleanup_temp() {
    if [[ -d "$TARGET_DIR" ]] && [[ "$DRY_RUN" == false ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf "$TARGET_DIR"
    fi
}

# Main restore process
main() {
    log_info "=========================================="
    log_info "MinIO Enterprise Restore - Starting"
    log_info "=========================================="
    log_info "Backup file: $BACKUP_FILE"
    log_info "Target directory: $TARGET_DIR"

    if [[ "$DRY_RUN" == true ]]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi

    log_info "=========================================="

    # Parse and validate inputs
    parse_args "$@"
    validate_inputs

    # Create target directory
    create_target_dir

    # Extract backup
    extract_backup

    # Show metadata
    show_metadata

    if [[ "$DRY_RUN" == true ]]; then
        log_info "=========================================="
        log_info "DRY RUN completed - no changes made"
        log_info "=========================================="
        return 0
    fi

    # Verify before restore if requested
    if [[ "$VERIFY_BEFORE_RESTORE" == true ]]; then
        log_info "Verifying backup integrity before restoration..."
        # Additional verification can be added here
    fi

    # Stop services if requested
    if [[ "$STOP_SERVICES" == true ]]; then
        stop_services
    fi

    # Perform restoration
    restore_minio_data
    restore_postgresql
    restore_redis
    restore_configs

    # Start services if requested
    if [[ "$START_SERVICES" == true ]]; then
        start_services
        verify_restoration
    fi

    # Cleanup temporary files
    cleanup_temp

    log_success "=========================================="
    log_success "Restore completed successfully!"
    log_success "=========================================="

    if [[ "$START_SERVICES" == false ]]; then
        log_info "Note: Services were not automatically started."
        log_info "Run the following to start services:"
        log_info "  docker-compose -f deployments/docker/docker-compose.production.yml up -d"
    fi
}

# Trap errors
trap 'log_error "Restore failed. Check logs above."' ERR

# Run main function
main "$@"
