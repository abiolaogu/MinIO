#!/bin/bash
#
# MinIO Backup Scheduler
# Sets up automated backup schedule using cron
#
# Usage:
#   ./schedule-backups.sh [install|uninstall|status]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup.sh"
CRON_USER="${CRON_USER:-root}"

# Default schedules
FULL_BACKUP_SCHEDULE="0 2 * * 0"      # Every Sunday at 2 AM
INCREMENTAL_BACKUP_SCHEDULE="0 2 * * 1-6"  # Monday-Saturday at 2 AM

show_help() {
    cat << EOF
MinIO Backup Scheduler

Usage: $0 [install|uninstall|status]

Commands:
  install       Install automated backup schedule
  uninstall     Remove automated backup schedule
  status        Show current backup schedule status

Default Schedules:
  Full Backup:         Every Sunday at 2:00 AM
  Incremental Backup:  Monday-Saturday at 2:00 AM

Environment Variables:
  CRON_USER                    User to run cron jobs (default: root)
  FULL_BACKUP_SCHEDULE         Cron schedule for full backups
  INCREMENTAL_BACKUP_SCHEDULE  Cron schedule for incremental backups

Examples:
  $0 install                    # Install with default schedule
  CRON_USER=minio $0 install    # Install for specific user
  $0 status                     # Check current schedule
  $0 uninstall                  # Remove scheduled backups

EOF
}

install_schedule() {
    echo "Installing MinIO backup schedule..."

    # Check if backup script exists
    if [[ ! -f "$BACKUP_SCRIPT" ]]; then
        echo "Error: Backup script not found: $BACKUP_SCRIPT"
        exit 1
    fi

    # Make backup script executable
    chmod +x "$BACKUP_SCRIPT"

    # Create cron job entries
    local cron_file="/tmp/minio_backup_cron"

    # Export current crontab
    crontab -u "$CRON_USER" -l > "$cron_file" 2>/dev/null || echo "# MinIO Backup Schedule" > "$cron_file"

    # Remove existing MinIO backup entries
    sed -i '/# MinIO Backup/d' "$cron_file"
    sed -i '/backup.sh/d' "$cron_file"

    # Add new entries
    cat >> "$cron_file" << EOF

# MinIO Backup Schedule - Full Backup (Sunday 2 AM)
$FULL_BACKUP_SCHEDULE $BACKUP_SCRIPT full -e -v >> /var/log/minio/backup-full.log 2>&1

# MinIO Backup Schedule - Incremental Backup (Monday-Saturday 2 AM)
$INCREMENTAL_BACKUP_SCHEDULE $BACKUP_SCRIPT incremental -e >> /var/log/minio/backup-incremental.log 2>&1
EOF

    # Install new crontab
    crontab -u "$CRON_USER" "$cron_file"

    # Clean up
    rm -f "$cron_file"

    # Create log directory
    mkdir -p /var/log/minio
    chown "$CRON_USER:$CRON_USER" /var/log/minio 2>/dev/null || true

    echo "✓ Backup schedule installed successfully"
    echo ""
    echo "Schedule:"
    echo "  Full Backup:        $FULL_BACKUP_SCHEDULE (Every Sunday at 2:00 AM)"
    echo "  Incremental Backup: $INCREMENTAL_BACKUP_SCHEDULE (Monday-Saturday at 2:00 AM)"
    echo ""
    echo "Logs:"
    echo "  Full backups:        /var/log/minio/backup-full.log"
    echo "  Incremental backups: /var/log/minio/backup-incremental.log"
    echo ""
    echo "To verify: crontab -u $CRON_USER -l | grep backup.sh"
}

uninstall_schedule() {
    echo "Uninstalling MinIO backup schedule..."

    local cron_file="/tmp/minio_backup_cron"

    # Export current crontab
    if ! crontab -u "$CRON_USER" -l > "$cron_file" 2>/dev/null; then
        echo "No crontab found for user: $CRON_USER"
        return 0
    fi

    # Remove MinIO backup entries
    sed -i '/# MinIO Backup/d' "$cron_file"
    sed -i '/backup.sh/d' "$cron_file"

    # Install updated crontab
    crontab -u "$CRON_USER" "$cron_file"

    # Clean up
    rm -f "$cron_file"

    echo "✓ Backup schedule uninstalled successfully"
}

show_status() {
    echo "MinIO Backup Schedule Status"
    echo "================================"
    echo ""

    # Check if cron is running
    if systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null; then
        echo "✓ Cron service is running"
    else
        echo "✗ Cron service is not running"
    fi

    echo ""
    echo "Scheduled Jobs for user '$CRON_USER':"
    echo "================================"

    if crontab -u "$CRON_USER" -l 2>/dev/null | grep -q "backup.sh"; then
        crontab -u "$CRON_USER" -l | grep -A1 "# MinIO Backup" | grep -v "^--$"
        echo ""
        echo "✓ Backup schedule is installed"
    else
        echo "✗ No backup schedule found"
        echo ""
        echo "Run '$0 install' to set up automated backups"
    fi

    echo ""
    echo "Recent Backup Logs:"
    echo "================================"

    if [[ -f /var/log/minio/backup-full.log ]]; then
        echo ""
        echo "Last Full Backup:"
        tail -n 10 /var/log/minio/backup-full.log 2>/dev/null || echo "No logs found"
    fi

    if [[ -f /var/log/minio/backup-incremental.log ]]; then
        echo ""
        echo "Last Incremental Backup:"
        tail -n 10 /var/log/minio/backup-incremental.log 2>/dev/null || echo "No logs found"
    fi
}

# Main
case "${1:-}" in
    install)
        install_schedule
        ;;
    uninstall)
        uninstall_schedule
        ;;
    status)
        show_status
        ;;
    -h|--help|help)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
