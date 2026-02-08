#!/bin/bash
#
# MinIO Enterprise - Backup Scheduler Setup Script
# Version: 1.0.0
# Description: Sets up automated backup scheduling using cron or systemd timers
#
# Usage:
#   ./schedule-backup.sh [OPTIONS]
#
# Options:
#   --method <cron|systemd>       Scheduling method (default: cron)
#   --full-schedule <schedule>    Cron schedule for full backups (default: "0 2 * * *")
#   --incr-schedule <schedule>    Cron schedule for incremental backups (default: "0 */6 * * *")
#   --uninstall                   Remove scheduled backups
#   -h, --help                    Show this help message
#

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup.sh"
METHOD="cron"
FULL_SCHEDULE="0 2 * * *"      # Daily at 2 AM
INCR_SCHEDULE="0 */6 * * *"    # Every 6 hours
UNINSTALL=false

# ============================================================
# Helper Functions
# ============================================================

show_help() {
    cat << EOF
MinIO Enterprise - Backup Scheduler Setup Script

Usage: $0 [OPTIONS]

Options:
  --method <cron|systemd>       Scheduling method (default: cron)
  --full-schedule <schedule>    Cron schedule for full backups (default: "0 2 * * *")
  --incr-schedule <schedule>    Cron schedule for incremental backups (default: "0 */6 * * *")
  --uninstall                   Remove scheduled backups
  -h, --help                    Show this help message

Examples:
  # Setup cron-based scheduling (default)
  $0

  # Setup systemd-based scheduling
  $0 --method systemd

  # Custom schedules
  $0 --full-schedule "0 3 * * 0" --incr-schedule "0 */4 * * *"

  # Remove scheduled backups
  $0 --uninstall

Cron Schedule Format:
  ┌───────────── minute (0 - 59)
  │ ┌───────────── hour (0 - 23)
  │ │ ┌───────────── day of month (1 - 31)
  │ │ │ ┌───────────── month (1 - 12)
  │ │ │ │ ┌───────────── day of week (0 - 6) (Sunday to Saturday)
  │ │ │ │ │
  * * * * *

Common Cron Schedules:
  "0 2 * * *"       - Daily at 2 AM
  "0 */6 * * *"     - Every 6 hours
  "0 3 * * 0"       - Weekly on Sunday at 3 AM
  "0 1 1 * *"       - Monthly on 1st at 1 AM

EOF
}

setup_cron() {
    echo "Setting up cron-based backup scheduling..."

    # Check if cron is installed
    if ! command -v crontab >/dev/null 2>&1; then
        echo "ERROR: cron is not installed"
        exit 1
    fi

    # Create temporary crontab file
    local temp_crontab=$(mktemp)

    # Get existing crontab (ignore errors if no crontab exists)
    crontab -l > "${temp_crontab}" 2>/dev/null || true

    # Remove existing MinIO backup entries
    sed -i '/# MinIO Backup - Full/d' "${temp_crontab}"
    sed -i '/# MinIO Backup - Incremental/d' "${temp_crontab}"
    sed -i "s|.*${BACKUP_SCRIPT}.*||g" "${temp_crontab}"
    sed -i '/^$/d' "${temp_crontab}"

    if [ "${UNINSTALL}" = false ]; then
        # Add new entries
        cat >> "${temp_crontab}" << EOF

# MinIO Backup - Full
${FULL_SCHEDULE} ${BACKUP_SCRIPT} --type full --compress --retention 30 >> /var/log/minio-backup-full.log 2>&1

# MinIO Backup - Incremental
${INCR_SCHEDULE} ${BACKUP_SCRIPT} --type incremental --compress --retention 7 >> /var/log/minio-backup-incr.log 2>&1
EOF

        # Install new crontab
        crontab "${temp_crontab}"

        echo "✓ Cron jobs installed successfully"
        echo
        echo "Scheduled backups:"
        echo "  Full backup:        ${FULL_SCHEDULE}"
        echo "  Incremental backup: ${INCR_SCHEDULE}"
        echo
        echo "Logs:"
        echo "  Full backup:        /var/log/minio-backup-full.log"
        echo "  Incremental backup: /var/log/minio-backup-incr.log"
        echo
        echo "To view scheduled jobs: crontab -l"
        echo "To remove jobs: $0 --uninstall"
    else
        crontab "${temp_crontab}"
        echo "✓ Cron jobs removed successfully"
    fi

    rm -f "${temp_crontab}"
}

setup_systemd() {
    echo "Setting up systemd-based backup scheduling..."

    # Check if systemd is available
    if ! command -v systemctl >/dev/null 2>&1; then
        echo "ERROR: systemd is not available"
        exit 1
    fi

    # Define systemd unit files
    local service_dir="/etc/systemd/system"
    local full_service="${service_dir}/minio-backup-full.service"
    local full_timer="${service_dir}/minio-backup-full.timer"
    local incr_service="${service_dir}/minio-backup-incr.service"
    local incr_timer="${service_dir}/minio-backup-incr.timer"

    if [ "${UNINSTALL}" = false ]; then
        # Create full backup service
        cat > "${full_service}" << EOF
[Unit]
Description=MinIO Full Backup
After=network.target

[Service]
Type=oneshot
ExecStart=${BACKUP_SCRIPT} --type full --compress --retention 30
StandardOutput=journal
StandardError=journal
EOF

        # Create full backup timer
        cat > "${full_timer}" << EOF
[Unit]
Description=MinIO Full Backup Timer
Requires=minio-backup-full.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

        # Create incremental backup service
        cat > "${incr_service}" << EOF
[Unit]
Description=MinIO Incremental Backup
After=network.target

[Service]
Type=oneshot
ExecStart=${BACKUP_SCRIPT} --type incremental --compress --retention 7
StandardOutput=journal
StandardError=journal
EOF

        # Create incremental backup timer
        cat > "${incr_timer}" << EOF
[Unit]
Description=MinIO Incremental Backup Timer
Requires=minio-backup-incr.service

[Timer]
OnCalendar=*-*-* */6:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

        # Reload systemd and enable timers
        systemctl daemon-reload
        systemctl enable minio-backup-full.timer
        systemctl enable minio-backup-incr.timer
        systemctl start minio-backup-full.timer
        systemctl start minio-backup-incr.timer

        echo "✓ Systemd timers installed and started successfully"
        echo
        echo "Scheduled backups:"
        echo "  Full backup:        Daily"
        echo "  Incremental backup: Every 6 hours"
        echo
        echo "To check timer status:"
        echo "  systemctl status minio-backup-full.timer"
        echo "  systemctl status minio-backup-incr.timer"
        echo
        echo "To view logs:"
        echo "  journalctl -u minio-backup-full.service"
        echo "  journalctl -u minio-backup-incr.service"
        echo
        echo "To remove timers: $0 --method systemd --uninstall"
    else
        # Stop and disable timers
        systemctl stop minio-backup-full.timer 2>/dev/null || true
        systemctl stop minio-backup-incr.timer 2>/dev/null || true
        systemctl disable minio-backup-full.timer 2>/dev/null || true
        systemctl disable minio-backup-incr.timer 2>/dev/null || true

        # Remove unit files
        rm -f "${full_service}" "${full_timer}" "${incr_service}" "${incr_timer}"

        # Reload systemd
        systemctl daemon-reload

        echo "✓ Systemd timers removed successfully"
    fi
}

# ============================================================
# Main Function
# ============================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --method)
                METHOD="$2"
                shift 2
                ;;
            --full-schedule)
                FULL_SCHEDULE="$2"
                shift 2
                ;;
            --incr-schedule)
                INCR_SCHEDULE="$2"
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
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Validate method
    if [ "${METHOD}" != "cron" ] && [ "${METHOD}" != "systemd" ]; then
        echo "ERROR: Invalid method: ${METHOD}. Must be 'cron' or 'systemd'"
        exit 1
    fi

    # Check if backup script exists
    if [ ! -f "${BACKUP_SCRIPT}" ]; then
        echo "ERROR: Backup script not found: ${BACKUP_SCRIPT}"
        exit 1
    fi

    # Make backup script executable
    chmod +x "${BACKUP_SCRIPT}"

    # Banner
    echo "============================================================"
    echo "MinIO Enterprise - Backup Scheduler Setup"
    echo "============================================================"
    echo "Method:          ${METHOD}"
    echo "Action:          $( [ "${UNINSTALL}" = true ] && echo "Uninstall" || echo "Install" )"
    echo "============================================================"
    echo

    # Execute based on method
    case "${METHOD}" in
        cron)
            setup_cron
            ;;
        systemd)
            setup_systemd
            ;;
    esac

    echo
    echo "✓ Setup complete"
}

# Run main function
main "$@"
