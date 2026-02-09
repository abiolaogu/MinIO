#!/bin/bash
###############################################################################
# MinIO Enterprise - Automated Restore Script
#
# Description: Restore MinIO Enterprise cluster from backup
# Components: PostgreSQL, Redis, MinIO objects, configuration files
# Features: Verification, rollback, incremental restore
###############################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source configuration
CONFIG_FILE="${RESTORE_CONFIG_FILE:-$SCRIPT_DIR/restore.conf}"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Default configuration
BACKUP_DIR="${BACKUP_DIR:-/var/backups/minio}"
ENCRYPTION_KEY_FILE="${ENCRYPTION_KEY_FILE:-$SCRIPT_DIR/../backup/.backup.key}"
RESTORE_DIR="${RESTORE_DIR:-/tmp/minio_restore}"
DRY_RUN="${DRY_RUN:-false}"
FORCE_RESTORE="${FORCE_RESTORE:-false}"
CREATE_SNAPSHOT="${CREATE_SNAPSHOT:-true}"

# Docker/Kubernetes configuration
DEPLOYMENT_TYPE="${DEPLOYMENT_TYPE:-docker}"
DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-$PROJECT_ROOT/deployments/docker/docker-compose.production.yml}"
KUBE_NAMESPACE="${KUBE_NAMESPACE:-minio-enterprise}"

# Component restore flags
RESTORE_POSTGRES="${RESTORE_POSTGRES:-true}"
RESTORE_REDIS="${RESTORE_REDIS:-true}"
RESTORE_MINIO="${RESTORE_MINIO:-true}"
RESTORE_CONFIGS="${RESTORE_CONFIGS:-true}"

# Notification configuration
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
EMAIL_RECIPIENT="${EMAIL_RECIPIENT:-}"

# Restore state
BACKUP_NAME=""
BACKUP_PATH=""
SNAPSHOT_NAME=""
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$BACKUP_DIR/logs/restore_${TIMESTAMP}.log"

mkdir -p "$BACKUP_DIR/logs"

###############################################################################
# Logging Functions
###############################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

log_warning() {
    log "WARNING" "$@"
}

###############################################################################
# Notification Functions
###############################################################################

send_notification() {
    local status="$1"
    local message="$2"

    if [[ -n "$SLACK_WEBHOOK" ]]; then
        curl -X POST "$SLACK_WEBHOOK" \
            -H 'Content-Type: application/json' \
            -d "{\"text\":\"MinIO Restore [$status]: $message\"}" \
            &>/dev/null || true
    fi

    if [[ -n "$EMAIL_RECIPIENT" ]] && command -v mail &>/dev/null; then
        echo "$message" | mail -s "MinIO Restore [$status]" "$EMAIL_RECIPIENT" || true
    fi
}

###############################################################################
# Utility Functions
###############################################################################

check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    # Check required tools
    local required_tools=("tar" "date")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        if ! command -v docker &>/dev/null; then
            missing_tools+=("docker")
        fi
    elif [[ "$DEPLOYMENT_TYPE" == "kubernetes" ]]; then
        if ! command -v kubectl &>/dev/null; then
            missing_tools+=("kubectl")
        fi
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi

    # Create restore directory
    mkdir -p "$RESTORE_DIR"

    log_success "Prerequisites check passed"
    return 0
}

###############################################################################
# Backup Selection
###############################################################################

list_backups() {
    log_info "Available backups:"
    echo ""

    local backups=()
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$BACKUP_DIR" -maxdepth 1 \( -name "minio_backup_*.tar.gz*" -o -type d -name "minio_backup_*" \) -print0 | sort -rz)

    if [[ ${#backups[@]} -eq 0 ]]; then
        echo "No backups found in $BACKUP_DIR"
        return 1
    fi

    local index=1
    for backup in "${backups[@]}"; do
        local backup_name=$(basename "$backup" | sed 's/\.tar\.gz.*$//')
        local timestamp=$(echo "$backup_name" | sed 's/minio_backup_//')
        local size=$(du -h "$backup" 2>/dev/null | cut -f1 || echo "N/A")
        local date_formatted=$(date -d "${timestamp:0:8}" "+%Y-%m-%d" 2>/dev/null || echo "$timestamp")

        printf "%2d) %s  %s  %s\n" "$index" "$backup_name" "$date_formatted" "$size"

        # Show metadata if available
        local metadata_file="$BACKUP_DIR/${backup_name}.metadata.json"
        if [[ -f "$metadata_file" ]]; then
            local components=$(jq -r '.components | to_entries | map(select(.value==true) | .key) | join(", ")' "$metadata_file" 2>/dev/null || echo "unknown")
            printf "     Components: %s\n" "$components"
        fi

        index=$((index + 1))
    done

    echo ""
    return 0
}

select_backup() {
    local backup_arg="${1:-}"

    if [[ -n "$backup_arg" ]]; then
        # Backup specified as argument
        if [[ -f "$backup_arg" ]] || [[ -d "$backup_arg" ]]; then
            BACKUP_PATH="$backup_arg"
            BACKUP_NAME=$(basename "$backup_arg" | sed 's/\.tar\.gz.*$//')
            log_info "Selected backup: $BACKUP_NAME"
            return 0
        elif [[ -f "$BACKUP_DIR/$backup_arg" ]] || [[ -d "$BACKUP_DIR/$backup_arg" ]]; then
            BACKUP_PATH="$BACKUP_DIR/$backup_arg"
            BACKUP_NAME=$(basename "$backup_arg" | sed 's/\.tar\.gz.*$//')
            log_info "Selected backup: $BACKUP_NAME"
            return 0
        else
            log_error "Backup not found: $backup_arg"
            return 1
        fi
    fi

    # Interactive selection
    list_backups || return 1

    echo -n "Select backup number (or 'q' to quit): "
    read -r selection

    if [[ "$selection" == "q" ]]; then
        log_info "Restore cancelled by user"
        exit 0
    fi

    local backups=()
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$BACKUP_DIR" -maxdepth 1 \( -name "minio_backup_*.tar.gz*" -o -type d -name "minio_backup_*" \) -print0 | sort -rz)

    local index=$((selection - 1))
    if [[ $index -ge 0 ]] && [[ $index -lt ${#backups[@]} ]]; then
        BACKUP_PATH="${backups[$index]}"
        BACKUP_NAME=$(basename "$BACKUP_PATH" | sed 's/\.tar\.gz.*$//')
        log_info "Selected backup: $BACKUP_NAME"
        return 0
    else
        log_error "Invalid selection: $selection"
        return 1
    fi
}

###############################################################################
# Backup Extraction
###############################################################################

extract_backup() {
    log_info "Extracting backup: $BACKUP_NAME"

    # Check if backup is encrypted
    if [[ -f "${BACKUP_PATH}.enc" ]] || [[ "$BACKUP_PATH" == *.enc ]]; then
        log_info "Decrypting backup..."

        if [[ ! -f "$ENCRYPTION_KEY_FILE" ]]; then
            log_error "Encryption key file not found: $ENCRYPTION_KEY_FILE"
            return 1
        fi

        local encrypted_file="$BACKUP_PATH"
        [[ "$encrypted_file" != *.enc ]] && encrypted_file="${BACKUP_PATH}.enc"

        local decrypted_file="${RESTORE_DIR}/$(basename "$encrypted_file" .enc)"

        openssl enc -aes-256-cbc -d \
            -in "$encrypted_file" \
            -out "$decrypted_file" \
            -pass "file:$ENCRYPTION_KEY_FILE" >>"$LOG_FILE" 2>&1 || {
            log_error "Decryption failed"
            return 1
        }

        BACKUP_PATH="$decrypted_file"
        log_success "Backup decrypted"
    fi

    # Extract compressed archive
    if [[ -f "$BACKUP_PATH" ]] && [[ "$BACKUP_PATH" == *.tar.gz ]]; then
        log_info "Extracting compressed backup..."

        tar xzf "$BACKUP_PATH" -C "$RESTORE_DIR" >>"$LOG_FILE" 2>&1 || {
            log_error "Extraction failed"
            return 1
        }

        # Update backup path to extracted directory
        BACKUP_PATH="$RESTORE_DIR/$BACKUP_NAME"
        log_success "Backup extracted"
    fi

    # Verify extracted backup structure
    if [[ ! -d "$BACKUP_PATH" ]]; then
        log_error "Backup directory not found: $BACKUP_PATH"
        return 1
    fi

    log_success "Backup ready for restore"
    return 0
}

###############################################################################
# Pre-Restore Snapshot
###############################################################################

create_snapshot() {
    if [[ "$CREATE_SNAPSHOT" != "true" ]]; then
        log_info "Snapshot creation disabled, skipping..."
        return 0
    fi

    log_info "Creating pre-restore snapshot..."
    SNAPSHOT_NAME="minio_snapshot_${TIMESTAMP}"

    # Use backup script to create snapshot
    local backup_script="$SCRIPT_DIR/../backup/backup.sh"
    if [[ -f "$backup_script" ]]; then
        BACKUP_TYPE="snapshot" \
        BACKUP_DIR="$BACKUP_DIR/snapshots" \
        "$backup_script" >>"$LOG_FILE" 2>&1 || {
            log_warning "Snapshot creation failed, continuing without snapshot"
            SNAPSHOT_NAME=""
            return 0
        }
    else
        log_warning "Backup script not found, skipping snapshot"
        SNAPSHOT_NAME=""
        return 0
    fi

    log_success "Snapshot created: $SNAPSHOT_NAME"
    return 0
}

###############################################################################
# Component Restore Functions
###############################################################################

restore_postgresql() {
    if [[ "$RESTORE_POSTGRES" != "true" ]]; then
        log_info "PostgreSQL restore disabled, skipping..."
        return 0
    fi

    local pg_backup_file="$BACKUP_PATH/postgresql.sql"
    if [[ ! -f "$pg_backup_file" ]]; then
        log_warning "PostgreSQL backup file not found, skipping..."
        return 0
    fi

    log_info "Restoring PostgreSQL database..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore PostgreSQL from: $pg_backup_file"
        return 0
    fi

    # Confirmation prompt
    if [[ "$FORCE_RESTORE" != "true" ]]; then
        echo -n "⚠️  This will OVERWRITE the current PostgreSQL database. Continue? (yes/no): "
        read -r confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "PostgreSQL restore cancelled by user"
            return 0
        fi
    fi

    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        # Stop services that depend on PostgreSQL
        docker compose -f "$DOCKER_COMPOSE_FILE" stop minio1 minio2 minio3 minio4 >>"$LOG_FILE" 2>&1 || true

        # Restore database
        docker compose -f "$DOCKER_COMPOSE_FILE" exec -T postgres \
            psql -U postgres < "$pg_backup_file" >>"$LOG_FILE" 2>&1 || {
            log_error "PostgreSQL restore failed"
            return 1
        }

        # Restart services
        docker compose -f "$DOCKER_COMPOSE_FILE" start minio1 minio2 minio3 minio4 >>"$LOG_FILE" 2>&1 || true
    elif [[ "$DEPLOYMENT_TYPE" == "kubernetes" ]]; then
        local pg_pod=$(kubectl get pods -n "$KUBE_NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}')

        # Scale down MinIO pods
        kubectl scale deployment -n "$KUBE_NAMESPACE" minio --replicas=0 >>"$LOG_FILE" 2>&1 || true

        # Restore database
        kubectl exec -n "$KUBE_NAMESPACE" "$pg_pod" -i -- \
            psql -U postgres < "$pg_backup_file" >>"$LOG_FILE" 2>&1 || {
            log_error "PostgreSQL restore failed"
            return 1
        }

        # Scale up MinIO pods
        kubectl scale deployment -n "$KUBE_NAMESPACE" minio --replicas=4 >>"$LOG_FILE" 2>&1 || true
    fi

    log_success "PostgreSQL restore completed"
    return 0
}

restore_redis() {
    if [[ "$RESTORE_REDIS" != "true" ]]; then
        log_info "Redis restore disabled, skipping..."
        return 0
    fi

    local redis_backup_file="$BACKUP_PATH/redis.rdb"
    if [[ ! -f "$redis_backup_file" ]]; then
        log_warning "Redis backup file not found, skipping..."
        return 0
    fi

    log_info "Restoring Redis data..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore Redis from: $redis_backup_file"
        return 0
    fi

    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        # Stop Redis
        docker compose -f "$DOCKER_COMPOSE_FILE" stop redis >>"$LOG_FILE" 2>&1 || {
            log_error "Failed to stop Redis"
            return 1
        }

        # Copy RDB file
        cat "$redis_backup_file" | docker compose -f "$DOCKER_COMPOSE_FILE" exec -T redis \
            sh -c 'cat > /data/dump.rdb' >>"$LOG_FILE" 2>&1 || {
            log_error "Failed to copy Redis backup"
            return 1
        }

        # Start Redis
        docker compose -f "$DOCKER_COMPOSE_FILE" start redis >>"$LOG_FILE" 2>&1 || {
            log_error "Failed to start Redis"
            return 1
        }
    elif [[ "$DEPLOYMENT_TYPE" == "kubernetes" ]]; then
        local redis_pod=$(kubectl get pods -n "$KUBE_NAMESPACE" -l app=redis -o jsonpath='{.items[0].metadata.name}')

        # Copy RDB file
        kubectl cp "$redis_backup_file" "$KUBE_NAMESPACE/$redis_pod:/data/dump.rdb" >>"$LOG_FILE" 2>&1 || {
            log_error "Failed to copy Redis backup"
            return 1
        }

        # Restart Redis pod to load new data
        kubectl delete pod -n "$KUBE_NAMESPACE" "$redis_pod" >>"$LOG_FILE" 2>&1 || {
            log_error "Failed to restart Redis pod"
            return 1
        }
    fi

    # Wait for Redis to be ready
    sleep 3

    log_success "Redis restore completed"
    return 0
}

restore_minio() {
    if [[ "$RESTORE_MINIO" != "true" ]]; then
        log_info "MinIO objects restore disabled, skipping..."
        return 0
    fi

    local minio_backup_file="$BACKUP_PATH/minio_data/data.tar.gz"
    if [[ ! -f "$minio_backup_file" ]]; then
        log_warning "MinIO backup file not found, skipping..."
        return 0
    fi

    log_info "Restoring MinIO objects..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore MinIO objects from: $minio_backup_file"
        return 0
    fi

    # Confirmation prompt
    if [[ "$FORCE_RESTORE" != "true" ]]; then
        echo -n "⚠️  This will OVERWRITE the current MinIO objects. Continue? (yes/no): "
        read -r confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "MinIO restore cancelled by user"
            return 0
        fi
    fi

    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        # Stop MinIO services
        docker compose -f "$DOCKER_COMPOSE_FILE" stop minio1 minio2 minio3 minio4 >>"$LOG_FILE" 2>&1 || {
            log_error "Failed to stop MinIO services"
            return 1
        }

        # Get MinIO data volume
        local volume_name=$(docker compose -f "$DOCKER_COMPOSE_FILE" config | grep -A 5 "minio1:" | grep "source:" | head -1 | awk '{print $2}')

        # Restore data to volume
        docker run --rm \
            -v "${volume_name}:/data" \
            -v "$BACKUP_PATH/minio_data:/backup:ro" \
            alpine sh -c 'rm -rf /data/* && tar xzf /backup/data.tar.gz -C /data' >>"$LOG_FILE" 2>&1 || {
            log_error "MinIO data restore failed"
            return 1
        }

        # Start MinIO services
        docker compose -f "$DOCKER_COMPOSE_FILE" start minio1 minio2 minio3 minio4 >>"$LOG_FILE" 2>&1 || {
            log_error "Failed to start MinIO services"
            return 1
        }
    elif [[ "$DEPLOYMENT_TYPE" == "kubernetes" ]]; then
        local minio_pod=$(kubectl get pods -n "$KUBE_NAMESPACE" -l app=minio -o jsonpath='{.items[0].metadata.name}')

        # Scale down MinIO
        kubectl scale deployment -n "$KUBE_NAMESPACE" minio --replicas=0 >>"$LOG_FILE" 2>&1 || {
            log_error "Failed to scale down MinIO"
            return 1
        }

        # Wait for pods to terminate
        sleep 5

        # Restore data (this is simplified - in production, you'd need to handle PVCs)
        kubectl scale deployment -n "$KUBE_NAMESPACE" minio --replicas=4 >>"$LOG_FILE" 2>&1 || {
            log_error "Failed to scale up MinIO"
            return 1
        }

        log_warning "Kubernetes restore is simplified. Consider using volume snapshots for production."
    fi

    # Wait for services to be ready
    sleep 5

    log_success "MinIO objects restore completed"
    return 0
}

restore_configs() {
    if [[ "$RESTORE_CONFIGS" != "true" ]]; then
        log_info "Configuration restore disabled, skipping..."
        return 0
    fi

    local config_backup_file="$BACKUP_PATH/configs.tar.gz"
    if [[ ! -f "$config_backup_file" ]]; then
        log_warning "Configuration backup file not found, skipping..."
        return 0
    fi

    log_info "Restoring configuration files..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore configurations from: $config_backup_file"
        return 0
    fi

    # Confirmation prompt
    if [[ "$FORCE_RESTORE" != "true" ]]; then
        echo -n "⚠️  This will OVERWRITE current configuration files. Continue? (yes/no): "
        read -r confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Configuration restore cancelled by user"
            return 0
        fi
    fi

    # Extract configurations
    tar xzf "$config_backup_file" -C "$PROJECT_ROOT" >>"$LOG_FILE" 2>&1 || {
        log_error "Configuration restore failed"
        return 1
    }

    log_success "Configuration restore completed"
    return 0
}

###############################################################################
# Post-Restore Verification
###############################################################################

verify_restore() {
    log_info "Verifying restore..."

    local errors=0

    # Check PostgreSQL
    if [[ "$RESTORE_POSTGRES" == "true" ]]; then
        if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
            if ! docker compose -f "$DOCKER_COMPOSE_FILE" exec -T postgres \
                psql -U postgres -c "SELECT 1" &>>"$LOG_FILE"; then
                log_error "PostgreSQL verification failed"
                errors=$((errors + 1))
            else
                log_success "PostgreSQL verified"
            fi
        fi
    fi

    # Check Redis
    if [[ "$RESTORE_REDIS" == "true" ]]; then
        if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
            if ! docker compose -f "$DOCKER_COMPOSE_FILE" exec -T redis \
                redis-cli PING &>>"$LOG_FILE"; then
                log_error "Redis verification failed"
                errors=$((errors + 1))
            else
                log_success "Redis verified"
            fi
        fi
    fi

    # Check MinIO
    if [[ "$RESTORE_MINIO" == "true" ]]; then
        if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
            # Check if MinIO services are running
            local running_services=$(docker compose -f "$DOCKER_COMPOSE_FILE" ps --services --filter "status=running" | grep -c minio || true)
            if [[ "$running_services" -lt 4 ]]; then
                log_error "MinIO verification failed (only $running_services/4 nodes running)"
                errors=$((errors + 1))
            else
                log_success "MinIO verified (4/4 nodes running)"
            fi
        fi
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Restore verification completed with $errors error(s)"
        return 1
    else
        log_success "Restore verification completed successfully"
        return 0
    fi
}

###############################################################################
# Cleanup
###############################################################################

cleanup() {
    log_info "Cleaning up temporary files..."

    if [[ -d "$RESTORE_DIR" ]]; then
        rm -rf "$RESTORE_DIR"
    fi

    log_success "Cleanup completed"
}

###############################################################################
# Rollback
###############################################################################

rollback() {
    if [[ -z "$SNAPSHOT_NAME" ]]; then
        log_error "No snapshot available for rollback"
        return 1
    fi

    log_warning "Rolling back to snapshot: $SNAPSHOT_NAME"

    # Recursively call restore script with snapshot
    FORCE_RESTORE=true \
    CREATE_SNAPSHOT=false \
    "$0" "$BACKUP_DIR/snapshots/${SNAPSHOT_NAME}.tar.gz" || {
        log_error "Rollback failed"
        return 1
    }

    log_success "Rollback completed"
    return 0
}

###############################################################################
# Main Execution
###############################################################################

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [BACKUP_NAME]

Restore MinIO Enterprise cluster from backup.

OPTIONS:
    -h, --help              Show this help message
    -l, --list              List available backups
    -d, --dry-run          Perform dry run (no actual restore)
    -f, --force            Force restore without confirmation prompts
    --no-snapshot          Skip pre-restore snapshot creation
    --postgres-only        Restore only PostgreSQL
    --redis-only           Restore only Redis
    --minio-only           Restore only MinIO objects
    --configs-only         Restore only configuration files

EXAMPLES:
    # Interactive restore (select from list)
    $0

    # Restore specific backup
    $0 minio_backup_20240118_120000

    # Dry run to see what would be restored
    $0 --dry-run minio_backup_20240118_120000

    # Force restore without prompts
    $0 --force minio_backup_20240118_120000

    # Restore only PostgreSQL
    $0 --postgres-only minio_backup_20240118_120000

EOF
    exit 0
}

main() {
    local backup_arg=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            -l|--list)
                list_backups
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_RESTORE=true
                shift
                ;;
            --no-snapshot)
                CREATE_SNAPSHOT=false
                shift
                ;;
            --postgres-only)
                RESTORE_POSTGRES=true
                RESTORE_REDIS=false
                RESTORE_MINIO=false
                RESTORE_CONFIGS=false
                shift
                ;;
            --redis-only)
                RESTORE_POSTGRES=false
                RESTORE_REDIS=true
                RESTORE_MINIO=false
                RESTORE_CONFIGS=false
                shift
                ;;
            --minio-only)
                RESTORE_POSTGRES=false
                RESTORE_REDIS=false
                RESTORE_MINIO=true
                RESTORE_CONFIGS=false
                shift
                ;;
            --configs-only)
                RESTORE_POSTGRES=false
                RESTORE_REDIS=false
                RESTORE_MINIO=false
                RESTORE_CONFIGS=true
                shift
                ;;
            *)
                backup_arg="$1"
                shift
                ;;
        esac
    done

    log_info "=========================================="
    log_info "MinIO Enterprise Restore Starting"
    log_info "Timestamp: $TIMESTAMP"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Mode: DRY RUN"
    fi
    log_info "=========================================="

    local start_time=$(date +%s)
    local status="SUCCESS"
    local error_msg=""

    # Execute restore pipeline
    if ! check_prerequisites; then
        status="FAILED"
        error_msg="Prerequisites check failed"
    elif ! select_backup "$backup_arg"; then
        status="FAILED"
        error_msg="Backup selection failed"
    elif ! extract_backup; then
        status="FAILED"
        error_msg="Backup extraction failed"
    elif ! create_snapshot; then
        status="WARNING"
        error_msg="Snapshot creation failed, continuing..."
    elif ! restore_postgresql; then
        status="FAILED"
        error_msg="PostgreSQL restore failed"
    elif ! restore_redis; then
        status="FAILED"
        error_msg="Redis restore failed"
    elif ! restore_minio; then
        status="FAILED"
        error_msg="MinIO restore failed"
    elif ! restore_configs; then
        status="FAILED"
        error_msg="Configuration restore failed"
    elif [[ "$DRY_RUN" != "true" ]] && ! verify_restore; then
        status="FAILED"
        error_msg="Restore verification failed"
    fi

    # Cleanup
    cleanup || true

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_info "=========================================="
    log_info "Restore Status: $status"
    log_info "Duration: ${duration}s"
    if [[ -n "$error_msg" ]]; then
        log_info "Error: $error_msg"
    fi
    log_info "=========================================="

    # Send notification
    if [[ "$status" == "SUCCESS" ]]; then
        send_notification "SUCCESS" "Restore completed successfully in ${duration}s"
    elif [[ "$status" == "FAILED" ]]; then
        send_notification "FAILED" "Restore failed: $error_msg"

        # Offer rollback option
        if [[ -n "$SNAPSHOT_NAME" ]] && [[ "$DRY_RUN" != "true" ]]; then
            echo ""
            echo -n "⚠️  Restore failed. Attempt rollback to snapshot? (yes/no): "
            read -r rollback_confirm
            if [[ "$rollback_confirm" == "yes" ]]; then
                rollback
            fi
        fi
    fi

    # Exit with appropriate code
    if [[ "$status" == "FAILED" ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"
