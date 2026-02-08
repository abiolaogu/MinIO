#!/bin/bash

################################################################################
# MinIO Enterprise Backup Scheduler Setup
#
# This script sets up automated backup scheduling using either cron or systemd
# timers based on your system configuration.
#
# Usage:
#   sudo ./setup-schedule.sh [OPTIONS]
#
# Options:
#   -m, --method METHOD    Scheduling method: cron or systemd (default: auto-detect)
#   -u, --user USER        User to run backups as (default: root)
#   --uninstall            Remove scheduled backups
#   -h, --help             Show this help message
#
################################################################################

set -euo pipefail

# Default configuration
SCHEDULE_METHOD="auto"
BACKUP_USER="root"
UNINSTALL=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup.sh"
CONFIG_FILE="${SCRIPT_DIR}/backup.conf"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
MinIO Enterprise Backup Scheduler Setup

Usage:
  sudo ./setup-schedule.sh [OPTIONS]

Options:
  -m, --method METHOD    Scheduling method: cron or systemd (default: auto-detect)
  -u, --user USER        User to run backups as (default: root)
  --uninstall            Remove scheduled backups
  -h, --help             Show this help message

Examples:
  # Auto-detect and setup scheduling
  sudo ./setup-schedule.sh

  # Use cron for scheduling
  sudo ./setup-schedule.sh --method cron

  # Use systemd timers
  sudo ./setup-schedule.sh --method systemd

  # Uninstall scheduled backups
  sudo ./setup-schedule.sh --uninstall

EOF
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--method)
                SCHEDULE_METHOD="$2"
                shift 2
                ;;
            -u|--user)
                BACKUP_USER="$2"
                shift 2
                ;;
            --uninstall)
                UNINSTALL=true
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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Validate inputs
validate_inputs() {
    if [[ ! -f "$BACKUP_SCRIPT" ]]; then
        log_error "Backup script not found: $BACKUP_SCRIPT"
        exit 1
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warning "Config file not found: $CONFIG_FILE"
    fi

    if [[ "$SCHEDULE_METHOD" != "auto" && "$SCHEDULE_METHOD" != "cron" && "$SCHEDULE_METHOD" != "systemd" ]]; then
        log_error "Invalid scheduling method: $SCHEDULE_METHOD"
        exit 1
    fi

    # Check if user exists
    if ! id "$BACKUP_USER" &>/dev/null; then
        log_error "User does not exist: $BACKUP_USER"
        exit 1
    fi
}

# Auto-detect scheduling method
auto_detect_method() {
    if [[ "$SCHEDULE_METHOD" == "auto" ]]; then
        if command -v systemctl &> /dev/null && systemctl is-system-running &> /dev/null; then
            SCHEDULE_METHOD="systemd"
            log_info "Auto-detected: systemd"
        elif command -v crontab &> /dev/null; then
            SCHEDULE_METHOD="cron"
            log_info "Auto-detected: cron"
        else
            log_error "Cannot auto-detect scheduling method. No cron or systemd found."
            exit 1
        fi
    fi
}

# Setup cron scheduling
setup_cron() {
    log_info "Setting up cron scheduling..."

    # Load configuration
    source "$CONFIG_FILE"

    # Create cron entries
    local cron_entries=""

    # Full backup schedule
    cron_entries+="${FULL_BACKUP_SCHEDULE} ${BACKUP_USER} ${BACKUP_SCRIPT} --type full --compress"
    if [[ "$VERIFY" == true ]]; then
        cron_entries+=" --verify"
    fi
    cron_entries+=" >> /var/log/minio_backup.log 2>&1\n"

    # Incremental backup schedule (if different from full)
    if [[ "$FULL_BACKUP_SCHEDULE" != "$INCREMENTAL_BACKUP_SCHEDULE" ]]; then
        cron_entries+="${INCREMENTAL_BACKUP_SCHEDULE} ${BACKUP_USER} ${BACKUP_SCRIPT} --type incremental --compress"
        if [[ "$VERIFY" == true ]]; then
            cron_entries+=" --verify"
        fi
        cron_entries+=" >> /var/log/minio_backup.log 2>&1\n"
    fi

    # Add to crontab
    local cron_file="/etc/cron.d/minio-backup"

    echo -e "# MinIO Enterprise Backup Schedule" > "$cron_file"
    echo -e "# Managed by setup-schedule.sh\n" >> "$cron_file"
    echo -e "$cron_entries" >> "$cron_file"

    chmod 644 "$cron_file"

    log_success "Cron scheduling configured"
    log_info "Cron entries added to: $cron_file"
}

# Setup systemd scheduling
setup_systemd() {
    log_info "Setting up systemd timers..."

    # Load configuration
    source "$CONFIG_FILE"

    # Create systemd service for full backup
    cat > /etc/systemd/system/minio-backup-full.service << EOF
[Unit]
Description=MinIO Enterprise Full Backup
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=${BACKUP_USER}
ExecStart=${BACKUP_SCRIPT} --type full --compress $([ "$VERIFY" == true ] && echo "--verify")
StandardOutput=append:/var/log/minio_backup.log
StandardError=append:/var/log/minio_backup.log

[Install]
WantedBy=multi-user.target
EOF

    # Create systemd timer for full backup
    cat > /etc/systemd/system/minio-backup-full.timer << EOF
[Unit]
Description=MinIO Enterprise Full Backup Timer
Requires=minio-backup-full.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Create systemd service for incremental backup
    cat > /etc/systemd/system/minio-backup-incremental.service << EOF
[Unit]
Description=MinIO Enterprise Incremental Backup
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=${BACKUP_USER}
ExecStart=${BACKUP_SCRIPT} --type incremental --compress $([ "$VERIFY" == true ] && echo "--verify")
StandardOutput=append:/var/log/minio_backup.log
StandardError=append:/var/log/minio_backup.log

[Install]
WantedBy=multi-user.target
EOF

    # Create systemd timer for incremental backup
    cat > /etc/systemd/system/minio-backup-incremental.timer << EOF
[Unit]
Description=MinIO Enterprise Incremental Backup Timer
Requires=minio-backup-incremental.service

[Timer]
OnCalendar=*-*-* 00,06,12,18:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Reload systemd and enable timers
    systemctl daemon-reload
    systemctl enable minio-backup-full.timer
    systemctl enable minio-backup-incremental.timer
    systemctl start minio-backup-full.timer
    systemctl start minio-backup-incremental.timer

    log_success "Systemd timers configured and enabled"
    log_info "Service files created in /etc/systemd/system/"
}

# Uninstall cron scheduling
uninstall_cron() {
    log_info "Removing cron scheduling..."

    local cron_file="/etc/cron.d/minio-backup"

    if [[ -f "$cron_file" ]]; then
        rm "$cron_file"
        log_success "Cron entries removed"
    else
        log_warning "No cron entries found"
    fi
}

# Uninstall systemd scheduling
uninstall_systemd() {
    log_info "Removing systemd timers..."

    # Stop and disable timers
    systemctl stop minio-backup-full.timer 2>/dev/null || true
    systemctl stop minio-backup-incremental.timer 2>/dev/null || true
    systemctl disable minio-backup-full.timer 2>/dev/null || true
    systemctl disable minio-backup-incremental.timer 2>/dev/null || true

    # Remove service and timer files
    rm -f /etc/systemd/system/minio-backup-full.service
    rm -f /etc/systemd/system/minio-backup-full.timer
    rm -f /etc/systemd/system/minio-backup-incremental.service
    rm -f /etc/systemd/system/minio-backup-incremental.timer

    # Reload systemd
    systemctl daemon-reload

    log_success "Systemd timers removed"
}

# Show scheduling status
show_status() {
    log_info "Checking backup schedule status..."

    if [[ "$SCHEDULE_METHOD" == "cron" ]]; then
        if [[ -f "/etc/cron.d/minio-backup" ]]; then
            log_success "Cron scheduling is active"
            cat /etc/cron.d/minio-backup
        else
            log_warning "Cron scheduling is not configured"
        fi
    elif [[ "$SCHEDULE_METHOD" == "systemd" ]]; then
        if systemctl is-active --quiet minio-backup-full.timer; then
            log_success "Systemd timers are active"
            systemctl status minio-backup-full.timer --no-pager
            systemctl status minio-backup-incremental.timer --no-pager
        else
            log_warning "Systemd timers are not active"
        fi
    fi
}

# Main function
main() {
    log_info "=========================================="
    log_info "MinIO Backup Scheduler Setup"
    log_info "=========================================="

    parse_args "$@"
    check_root
    validate_inputs
    auto_detect_method

    if [[ "$UNINSTALL" == true ]]; then
        log_info "Uninstalling backup schedules..."

        if [[ "$SCHEDULE_METHOD" == "cron" ]]; then
            uninstall_cron
        elif [[ "$SCHEDULE_METHOD" == "systemd" ]]; then
            uninstall_systemd
        fi

        log_success "Backup schedules uninstalled"
    else
        log_info "Installing backup schedules using $SCHEDULE_METHOD..."

        if [[ "$SCHEDULE_METHOD" == "cron" ]]; then
            setup_cron
        elif [[ "$SCHEDULE_METHOD" == "systemd" ]]; then
            setup_systemd
        fi

        show_status

        log_success "=========================================="
        log_success "Backup scheduling setup completed!"
        log_success "=========================================="
        log_info "Full backups: Daily at 2:00 AM"
        log_info "Incremental backups: Every 6 hours"
        log_info "Logs: /var/log/minio_backup.log"
    fi
}

# Run main
main "$@"
