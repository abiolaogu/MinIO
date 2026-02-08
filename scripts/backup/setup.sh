#!/usr/bin/env bash
#
# MinIO Enterprise - Backup Setup Script
#
# This script sets up the backup system including:
# - Creating necessary directories
# - Generating encryption key
# - Setting up cron jobs
# - Validating configuration
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "MinIO Enterprise - Backup Setup"
echo "========================================"

# Create backup directory
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/minio}"

echo "Creating backup directory: $BACKUP_ROOT"
sudo mkdir -p "$BACKUP_ROOT"
sudo chown $USER:$USER "$BACKUP_ROOT"

# Create configuration file if it doesn't exist
if [ ! -f "$SCRIPT_DIR/backup.conf" ]; then
    echo "Creating backup configuration..."
    cp "$SCRIPT_DIR/backup.conf.example" "$SCRIPT_DIR/backup.conf"
    echo "✓ Configuration file created: $SCRIPT_DIR/backup.conf"
    echo "  Please edit this file to customize your backup settings"
else
    echo "✓ Configuration file already exists"
fi

# Generate encryption key if it doesn't exist
ENCRYPTION_KEY_FILE="$SCRIPT_DIR/backup.key"

if [ ! -f "$ENCRYPTION_KEY_FILE" ]; then
    echo "Generating encryption key..."
    openssl rand -base64 32 > "$ENCRYPTION_KEY_FILE"
    chmod 600 "$ENCRYPTION_KEY_FILE"
    echo "✓ Encryption key generated: $ENCRYPTION_KEY_FILE"
    echo "  IMPORTANT: Keep this key secure! You'll need it to restore backups."
else
    echo "✓ Encryption key already exists"
fi

# Make scripts executable
echo "Setting script permissions..."
chmod +x "$SCRIPT_DIR/backup.sh"
chmod +x "$SCRIPT_DIR/../restore/restore.sh"
echo "✓ Scripts are now executable"

# Check dependencies
echo ""
echo "Checking dependencies..."

MISSING_DEPS=()

for cmd in pg_dump pg_restore redis-cli tar gzip openssl; do
    if command -v "$cmd" &> /dev/null; then
        echo "  ✓ $cmd"
    else
        echo "  ✗ $cmd (missing)"
        MISSING_DEPS+=("$cmd")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo ""
    echo "WARNING: Missing dependencies: ${MISSING_DEPS[*]}"
    echo "Install them before running backups:"
    echo "  Ubuntu/Debian: sudo apt-get install postgresql-client redis-tools openssl"
    echo "  RHEL/CentOS: sudo yum install postgresql redis openssl"
fi

# Offer to set up cron job
echo ""
echo "========================================"
echo "Cron Job Setup"
echo "========================================"
echo ""
echo "Would you like to set up a daily backup cron job?"
echo "This will run a full backup every day at 2:00 AM"
read -p "Set up cron job? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    CRON_JOB="0 2 * * * $SCRIPT_DIR/backup.sh >> $BACKUP_ROOT/backup.log 2>&1"

    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "$SCRIPT_DIR/backup.sh"; then
        echo "✓ Cron job already exists"
    else
        # Add cron job
        (crontab -l 2>/dev/null || true; echo "$CRON_JOB") | crontab -
        echo "✓ Cron job added successfully"
        echo "  Backup will run daily at 2:00 AM"
    fi

    echo ""
    echo "Current cron jobs:"
    crontab -l | grep backup || echo "  (no backup jobs found)"
fi

# Test backup (dry run)
echo ""
echo "========================================"
echo "Test Backup (Dry Run)"
echo "========================================"
echo ""
echo "Would you like to run a test backup (dry run)?"
echo "This will verify your configuration without making changes"
read -p "Run test? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Running test backup..."
    DRY_RUN=true "$SCRIPT_DIR/backup.sh" || true
fi

# Summary
echo ""
echo "========================================"
echo "Setup Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Edit configuration: $SCRIPT_DIR/backup.conf"
echo "2. Secure your encryption key: $ENCRYPTION_KEY_FILE"
echo "3. Test backup manually: $SCRIPT_DIR/backup.sh"
echo "4. Verify backup: ls -lh $BACKUP_ROOT"
echo "5. Test restore: $SCRIPT_DIR/../restore/restore.sh <backup_file>"
echo ""
echo "Documentation: $SCRIPT_DIR/README.md"
echo ""
