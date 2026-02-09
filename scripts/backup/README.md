# MinIO Enterprise - Backup Scripts

## Quick Start

```bash
# Make scripts executable
chmod +x backup.sh
chmod +x ../restore/restore.sh

# Run first backup
./backup.sh

# Check logs
tail -f /var/backups/minio/logs/backup_*.log
```

## Files

- **backup.sh** - Main backup script
- **backup.conf** - Configuration file
- **.backup.key** - Encryption key (generated automatically)

## Configuration

Edit `backup.conf` or use environment variables:

```bash
# Custom backup directory
BACKUP_DIR=/custom/path ./backup.sh

# Disable encryption
ENABLE_ENCRYPTION=false ./backup.sh

# Enable S3 upload
S3_BACKUP_ENABLED=true S3_BUCKET=my-backups ./backup.sh
```

## Scheduling

Add to crontab for automated backups:

```bash
# Daily backup at 2 AM
0 2 * * * /path/to/backup.sh >> /var/log/minio-backup.log 2>&1
```

## Documentation

See [BACKUP_RESTORE.md](../../docs/guides/BACKUP_RESTORE.md) for complete documentation.
