#!/bin/bash
###############################################################################
# MinIO Enterprise - Automated Backup Script
#
# Description: Comprehensive backup solution for MinIO Enterprise cluster
# Components: PostgreSQL, Redis, MinIO objects, configuration files
# Features: Full/incremental backups, encryption, compression, retention
###############################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source configuration
CONFIG_FILE="${BACKUP_CONFIG_FILE:-$SCRIPT_DIR/backup.conf}"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Default configuration (can be overridden by backup.conf or environment variables)
BACKUP_TYPE="${BACKUP_TYPE:-full}"                # full or incremental
BACKUP_DIR="${BACKUP_DIR:-/var/backups/minio}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
ENABLE_COMPRESSION="${ENABLE_COMPRESSION:-true}"
ENABLE_ENCRYPTION="${ENABLE_ENCRYPTION:-true}"
ENCRYPTION_KEY_FILE="${ENCRYPTION_KEY_FILE:-$SCRIPT_DIR/.backup.key}"
S3_BACKUP_ENABLED="${S3_BACKUP_ENABLED:-false}"
S3_BUCKET="${S3_BUCKET:-}"
S3_ENDPOINT="${S3_ENDPOINT:-}"

# Docker/Kubernetes configuration
DEPLOYMENT_TYPE="${DEPLOYMENT_TYPE:-docker}"  # docker or kubernetes
DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-$PROJECT_ROOT/deployments/docker/docker-compose.production.yml}"
KUBE_NAMESPACE="${KUBE_NAMESPACE:-minio-enterprise}"

# Component configuration
BACKUP_POSTGRES="${BACKUP_POSTGRES:-true}"
BACKUP_REDIS="${BACKUP_REDIS:-true}"
BACKUP_MINIO="${BACKUP_MINIO:-true}"
BACKUP_CONFIGS="${BACKUP_CONFIGS:-true}"

# Notification configuration
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
EMAIL_RECIPIENT="${EMAIL_RECIPIENT:-}"

# Timestamp for this backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="minio_backup_${TIMESTAMP}"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

# Logging configuration
LOG_FILE="$BACKUP_DIR/logs/backup_${TIMESTAMP}.log"
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

###############################################################################
# Notification Functions
###############################################################################

send_notification() {
    local status="$1"
    local message="$2"

    # Slack notification
    if [[ -n "$SLACK_WEBHOOK" ]]; then
        curl -X POST "$SLACK_WEBHOOK" \
            -H 'Content-Type: application/json' \
            -d "{\"text\":\"MinIO Backup [$status]: $message\"}" \
            &>/dev/null || true
    fi

    # Email notification (requires mailx or sendmail)
    if [[ -n "$EMAIL_RECIPIENT" ]] && command -v mail &>/dev/null; then
        echo "$message" | mail -s "MinIO Backup [$status]" "$EMAIL_RECIPIENT" || true
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

    if [[ "$ENABLE_COMPRESSION" == "true" ]] && ! command -v gzip &>/dev/null; then
        missing_tools+=("gzip")
    fi

    if [[ "$ENABLE_ENCRYPTION" == "true" ]] && ! command -v openssl &>/dev/null; then
        missing_tools+=("openssl")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi

    # Create backup directory
    mkdir -p "$BACKUP_PATH"

    # Generate encryption key if needed
    if [[ "$ENABLE_ENCRYPTION" == "true" ]] && [[ ! -f "$ENCRYPTION_KEY_FILE" ]]; then
        log_info "Generating encryption key..."
        openssl rand -base64 32 > "$ENCRYPTION_KEY_FILE"
        chmod 600 "$ENCRYPTION_KEY_FILE"
    fi

    log_success "Prerequisites check passed"
    return 0
}

###############################################################################
# PostgreSQL Backup
###############################################################################

backup_postgresql() {
    if [[ "$BACKUP_POSTGRES" != "true" ]]; then
        log_info "PostgreSQL backup disabled, skipping..."
        return 0
    fi

    log_info "Backing up PostgreSQL database..."
    local pg_backup_file="$BACKUP_PATH/postgresql.sql"

    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        # Docker deployment
        docker compose -f "$DOCKER_COMPOSE_FILE" exec -T postgres \
            pg_dumpall -U postgres > "$pg_backup_file" 2>>"$LOG_FILE" || {
            log_error "PostgreSQL backup failed"
            return 1
        }
    elif [[ "$DEPLOYMENT_TYPE" == "kubernetes" ]]; then
        # Kubernetes deployment
        local pg_pod=$(kubectl get pods -n "$KUBE_NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}')
        kubectl exec -n "$KUBE_NAMESPACE" "$pg_pod" -- \
            pg_dumpall -U postgres > "$pg_backup_file" 2>>"$LOG_FILE" || {
            log_error "PostgreSQL backup failed"
            return 1
        }
    fi

    local size=$(du -h "$pg_backup_file" | cut -f1)
    log_success "PostgreSQL backup completed ($size)"
    return 0
}

###############################################################################
# Redis Backup
###############################################################################

backup_redis() {
    if [[ "$BACKUP_REDIS" != "true" ]]; then
        log_info "Redis backup disabled, skipping..."
        return 0
    fi

    log_info "Backing up Redis data..."
    local redis_backup_file="$BACKUP_PATH/redis.rdb"

    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        # Trigger Redis save
        docker compose -f "$DOCKER_COMPOSE_FILE" exec -T redis \
            redis-cli BGSAVE >>"$LOG_FILE" 2>&1 || {
            log_error "Redis BGSAVE failed"
            return 1
        }

        # Wait for save to complete
        sleep 2
        while docker compose -f "$DOCKER_COMPOSE_FILE" exec -T redis \
            redis-cli LASTSAVE | grep -q "$(date +%s)"; do
            sleep 1
        done

        # Copy RDB file
        docker compose -f "$DOCKER_COMPOSE_FILE" exec -T redis \
            cat /data/dump.rdb > "$redis_backup_file" 2>>"$LOG_FILE" || {
            log_error "Redis backup copy failed"
            return 1
        }
    elif [[ "$DEPLOYMENT_TYPE" == "kubernetes" ]]; then
        local redis_pod=$(kubectl get pods -n "$KUBE_NAMESPACE" -l app=redis -o jsonpath='{.items[0].metadata.name}')

        # Trigger save
        kubectl exec -n "$KUBE_NAMESPACE" "$redis_pod" -- \
            redis-cli BGSAVE >>"$LOG_FILE" 2>&1 || {
            log_error "Redis BGSAVE failed"
            return 1
        }

        sleep 2

        # Copy RDB file
        kubectl exec -n "$KUBE_NAMESPACE" "$redis_pod" -- \
            cat /data/dump.rdb > "$redis_backup_file" 2>>"$LOG_FILE" || {
            log_error "Redis backup copy failed"
            return 1
        }
    fi

    local size=$(du -h "$redis_backup_file" | cut -f1)
    log_success "Redis backup completed ($size)"
    return 0
}

###############################################################################
# MinIO Objects Backup
###############################################################################

backup_minio() {
    if [[ "$BACKUP_MINIO" != "true" ]]; then
        log_info "MinIO objects backup disabled, skipping..."
        return 0
    fi

    log_info "Backing up MinIO objects..."
    local minio_backup_dir="$BACKUP_PATH/minio_data"
    mkdir -p "$minio_backup_dir"

    if [[ "$DEPLOYMENT_TYPE" == "docker" ]]; then
        # Get MinIO data volume path
        local volume_name=$(docker compose -f "$DOCKER_COMPOSE_FILE" config | grep -A 5 "minio1:" | grep "source:" | head -1 | awk '{print $2}')
        if [[ -z "$volume_name" ]]; then
            log_error "Could not find MinIO data volume"
            return 1
        fi

        # Copy data from volume using a temporary container
        docker run --rm \
            -v "${volume_name}:/data:ro" \
            -v "$minio_backup_dir:/backup" \
            alpine tar czf /backup/data.tar.gz -C /data . >>"$LOG_FILE" 2>&1 || {
            log_error "MinIO data backup failed"
            return 1
        }
    elif [[ "$DEPLOYMENT_TYPE" == "kubernetes" ]]; then
        # Backup from first MinIO pod
        local minio_pod=$(kubectl get pods -n "$KUBE_NAMESPACE" -l app=minio -o jsonpath='{.items[0].metadata.name}')

        kubectl exec -n "$KUBE_NAMESPACE" "$minio_pod" -- \
            tar czf - /data > "$minio_backup_dir/data.tar.gz" 2>>"$LOG_FILE" || {
            log_error "MinIO data backup failed"
            return 1
        }
    fi

    local size=$(du -h "$minio_backup_dir/data.tar.gz" | cut -f1)
    log_success "MinIO objects backup completed ($size)"
    return 0
}

###############################################################################
# Configuration Files Backup
###############################################################################

backup_configs() {
    if [[ "$BACKUP_CONFIGS" != "true" ]]; then
        log_info "Configuration backup disabled, skipping..."
        return 0
    fi

    log_info "Backing up configuration files..."
    local config_backup_file="$BACKUP_PATH/configs.tar.gz"

    # Backup configuration directories
    tar czf "$config_backup_file" \
        -C "$PROJECT_ROOT" \
        configs/ \
        deployments/ \
        .env.* \
        2>>"$LOG_FILE" || {
        log_error "Configuration backup failed"
        return 1
    }

    local size=$(du -h "$config_backup_file" | cut -f1)
    log_success "Configuration backup completed ($size)"
    return 0
}

###############################################################################
# Compression and Encryption
###############################################################################

compress_backup() {
    if [[ "$ENABLE_COMPRESSION" != "true" ]]; then
        log_info "Compression disabled, skipping..."
        return 0
    fi

    log_info "Compressing backup archive..."
    local archive_file="$BACKUP_DIR/${BACKUP_NAME}.tar"

    tar cf "$archive_file" -C "$BACKUP_DIR" "$BACKUP_NAME" >>"$LOG_FILE" 2>&1 || {
        log_error "Compression failed"
        return 1
    }

    gzip "$archive_file" || {
        log_error "Gzip compression failed"
        return 1
    }

    local size=$(du -h "${archive_file}.gz" | cut -f1)
    log_success "Backup compressed ($size)"
    return 0
}

encrypt_backup() {
    if [[ "$ENABLE_ENCRYPTION" != "true" ]]; then
        log_info "Encryption disabled, skipping..."
        return 0
    fi

    log_info "Encrypting backup archive..."
    local archive_file="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"

    if [[ ! -f "$archive_file" ]]; then
        log_error "Archive file not found: $archive_file"
        return 1
    fi

    openssl enc -aes-256-cbc -salt \
        -in "$archive_file" \
        -out "${archive_file}.enc" \
        -pass "file:$ENCRYPTION_KEY_FILE" >>"$LOG_FILE" 2>&1 || {
        log_error "Encryption failed"
        return 1
    }

    # Remove unencrypted archive
    rm -f "$archive_file"

    local size=$(du -h "${archive_file}.enc" | cut -f1)
    log_success "Backup encrypted ($size)"
    return 0
}

###############################################################################
# Backup Verification
###############################################################################

verify_backup() {
    log_info "Verifying backup integrity..."

    local backup_file=""
    if [[ "$ENABLE_ENCRYPTION" == "true" ]]; then
        backup_file="$BACKUP_DIR/${BACKUP_NAME}.tar.gz.enc"
    elif [[ "$ENABLE_COMPRESSION" == "true" ]]; then
        backup_file="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
    else
        backup_file="$BACKUP_PATH"
    fi

    if [[ ! -e "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    # Verify file is readable and has content
    if [[ -f "$backup_file" ]]; then
        local size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)
        if [[ "$size" -eq 0 ]]; then
            log_error "Backup file is empty"
            return 1
        fi
    fi

    # Create verification metadata
    local metadata_file="$BACKUP_DIR/${BACKUP_NAME}.metadata.json"
    cat > "$metadata_file" <<EOF
{
    "backup_name": "$BACKUP_NAME",
    "timestamp": "$TIMESTAMP",
    "type": "$BACKUP_TYPE",
    "components": {
        "postgresql": $([[ "$BACKUP_POSTGRES" == "true" ]] && echo "true" || echo "false"),
        "redis": $([[ "$BACKUP_REDIS" == "true" ]] && echo "true" || echo "false"),
        "minio": $([[ "$BACKUP_MINIO" == "true" ]] && echo "true" || echo "false"),
        "configs": $([[ "$BACKUP_CONFIGS" == "true" ]] && echo "true" || echo "false")
    },
    "compression": $([[ "$ENABLE_COMPRESSION" == "true" ]] && echo "true" || echo "false"),
    "encryption": $([[ "$ENABLE_ENCRYPTION" == "true" ]] && echo "true" || echo "false"),
    "size_bytes": $size,
    "checksum": "$(sha256sum "$backup_file" | cut -d' ' -f1)"
}
EOF

    log_success "Backup verification completed"
    return 0
}

###############################################################################
# S3 Upload
###############################################################################

upload_to_s3() {
    if [[ "$S3_BACKUP_ENABLED" != "true" ]] || [[ -z "$S3_BUCKET" ]]; then
        log_info "S3 upload disabled, skipping..."
        return 0
    fi

    log_info "Uploading backup to S3..."

    local backup_file=""
    if [[ "$ENABLE_ENCRYPTION" == "true" ]]; then
        backup_file="$BACKUP_DIR/${BACKUP_NAME}.tar.gz.enc"
    elif [[ "$ENABLE_COMPRESSION" == "true" ]]; then
        backup_file="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
    fi

    if ! command -v aws &>/dev/null; then
        log_error "AWS CLI not found, cannot upload to S3"
        return 1
    fi

    local s3_path="s3://${S3_BUCKET}/minio-backups/$(date +%Y/%m)/${BACKUP_NAME}"

    if [[ -n "$S3_ENDPOINT" ]]; then
        aws s3 cp "$backup_file" "$s3_path" --endpoint-url "$S3_ENDPOINT" >>"$LOG_FILE" 2>&1 || {
            log_error "S3 upload failed"
            return 1
        }

        # Upload metadata
        aws s3 cp "$BACKUP_DIR/${BACKUP_NAME}.metadata.json" "${s3_path}.metadata.json" \
            --endpoint-url "$S3_ENDPOINT" >>"$LOG_FILE" 2>&1 || true
    else
        aws s3 cp "$backup_file" "$s3_path" >>"$LOG_FILE" 2>&1 || {
            log_error "S3 upload failed"
            return 1
        }

        aws s3 cp "$BACKUP_DIR/${BACKUP_NAME}.metadata.json" "${s3_path}.metadata.json" >>"$LOG_FILE" 2>&1 || true
    fi

    log_success "Backup uploaded to S3: $s3_path"
    return 0
}

###############################################################################
# Cleanup Old Backups
###############################################################################

cleanup_old_backups() {
    log_info "Cleaning up old backups (retention: $BACKUP_RETENTION_DAYS days)..."

    # Find and delete old backups
    find "$BACKUP_DIR" -maxdepth 1 -name "minio_backup_*" -type f -mtime +"$BACKUP_RETENTION_DAYS" -delete 2>>"$LOG_FILE" || true
    find "$BACKUP_DIR" -maxdepth 1 -name "minio_backup_*" -type d -mtime +"$BACKUP_RETENTION_DAYS" -exec rm -rf {} + 2>>"$LOG_FILE" || true

    # Cleanup old logs
    find "$BACKUP_DIR/logs" -name "backup_*.log" -type f -mtime +90 -delete 2>>"$LOG_FILE" || true

    log_success "Old backups cleaned up"
    return 0
}

###############################################################################
# Main Execution
###############################################################################

main() {
    log_info "=========================================="
    log_info "MinIO Enterprise Backup Starting"
    log_info "Backup Type: $BACKUP_TYPE"
    log_info "Timestamp: $TIMESTAMP"
    log_info "=========================================="

    local start_time=$(date +%s)
    local status="SUCCESS"
    local error_msg=""

    # Execute backup pipeline
    if ! check_prerequisites; then
        status="FAILED"
        error_msg="Prerequisites check failed"
    elif ! backup_postgresql; then
        status="FAILED"
        error_msg="PostgreSQL backup failed"
    elif ! backup_redis; then
        status="FAILED"
        error_msg="Redis backup failed"
    elif ! backup_minio; then
        status="FAILED"
        error_msg="MinIO objects backup failed"
    elif ! backup_configs; then
        status="FAILED"
        error_msg="Configuration backup failed"
    elif ! compress_backup; then
        status="FAILED"
        error_msg="Compression failed"
    elif ! encrypt_backup; then
        status="FAILED"
        error_msg="Encryption failed"
    elif ! verify_backup; then
        status="FAILED"
        error_msg="Backup verification failed"
    elif ! upload_to_s3; then
        status="WARNING"
        error_msg="S3 upload failed, but local backup is complete"
    fi

    # Cleanup
    cleanup_old_backups || true

    # Remove temporary backup directory if compression was enabled
    if [[ "$ENABLE_COMPRESSION" == "true" ]] && [[ -d "$BACKUP_PATH" ]]; then
        rm -rf "$BACKUP_PATH"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_info "=========================================="
    log_info "Backup Status: $status"
    log_info "Duration: ${duration}s"
    if [[ -n "$error_msg" ]]; then
        log_info "Error: $error_msg"
    fi
    log_info "=========================================="

    # Send notification
    if [[ "$status" == "SUCCESS" ]]; then
        send_notification "SUCCESS" "Backup completed successfully in ${duration}s"
    else
        send_notification "$status" "Backup $status: $error_msg"
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
