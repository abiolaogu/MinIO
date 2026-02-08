# MinIO Enterprise Backup & Restore Scripts

Automated backup and restore scripts for MinIO Enterprise with support for full/incremental backups, compression, encryption, and automated scheduling.

## Quick Start

### First Backup

```bash
# Simple full backup with compression
./backup.sh --type full --compress

# With verification
./backup.sh --type full --compress --verify

# With encryption
./backup.sh --type full --compress --encrypt --key-file /path/to/gpg-key.asc
```

### First Restore

```bash
# Restore from backup (dry run first)
cd ../restore
./restore.sh --file /backup/minio_backup_full_20260208_120000.tar.gz --dry-run

# Actual restore
./restore.sh --file /backup/minio_backup_full_20260208_120000.tar.gz \
  --stop-services --start-services --verify
```

### Setup Automated Backups

```bash
# Setup scheduled backups (auto-detects systemd or cron)
sudo ./setup-schedule.sh

# Check status
systemctl list-timers | grep minio-backup
```

## Files

- **backup.sh** - Main backup script
- **backup.conf** - Configuration file (edit this!)
- **setup-schedule.sh** - Automated scheduling setup
- **README.md** - This file

## Configuration

Edit `backup.conf` to customize:

```bash
# Basic settings
BACKUP_TYPE="full"              # or "incremental"
BACKUP_DEST="/backup"           # Backup destination
COMPRESS=true                   # Enable compression
ENCRYPT=false                   # Enable encryption
RETENTION_DAYS=30               # Keep backups for 30 days

# Schedules (cron format)
FULL_BACKUP_SCHEDULE="0 2 * * *"              # Daily at 2 AM
INCREMENTAL_BACKUP_SCHEDULE="0 */6 * * *"     # Every 6 hours
```

## Backup Script Usage

```bash
./backup.sh [OPTIONS]

Options:
  -t, --type TYPE        Backup type: full or incremental (default: full)
  -d, --dest DIR         Destination directory (default: /backup)
  -c, --compress         Enable compression (gzip)
  -e, --encrypt          Enable encryption (GPG)
  -k, --key-file FILE    GPG key file for encryption
  -r, --retention DAYS   Retention period in days (default: 30)
  -v, --verify           Verify backup after creation
  -h, --help             Show help message

Examples:
  # Full backup with compression and verification
  ./backup.sh --type full --compress --verify

  # Incremental backup
  ./backup.sh --type incremental --compress

  # Encrypted backup
  ./backup.sh --type full --encrypt --key-file /etc/backup/gpg-key.asc
```

## Restore Script Usage

```bash
../restore/restore.sh [OPTIONS]

Options:
  -f, --file FILE        Backup file to restore (required)
  -k, --key-file FILE    GPG key file for decryption (if encrypted)
  -t, --target DIR       Target directory (default: /tmp/restore)
  -s, --stop-services    Stop services before restore
  -r, --start-services   Start services after restore
  --verify               Verify backup before restoring
  --dry-run              Preview without restoring
  -h, --help             Show help message

Examples:
  # Dry run
  ../restore/restore.sh --file /backup/backup.tar.gz --dry-run

  # Full restore with verification
  ../restore/restore.sh --file /backup/backup.tar.gz \
    --stop-services --start-services --verify

  # Restore encrypted backup
  ../restore/restore.sh --file /backup/backup.tar.gz.gpg \
    --key-file /etc/backup/private-key.asc
```

## What Gets Backed Up

✅ MinIO object data (all 4 nodes)
✅ PostgreSQL database (complete dump)
✅ Redis data (RDB snapshots)
✅ Configuration files (Docker Compose, Grafana, Prometheus, etc.)
✅ Backup metadata (version, timestamp, components)

## Automated Scheduling

### Setup (Recommended)

```bash
# Auto-detect and setup
sudo ./setup-schedule.sh

# Force specific method
sudo ./setup-schedule.sh --method systemd
sudo ./setup-schedule.sh --method cron

# Uninstall
sudo ./setup-schedule.sh --uninstall
```

### Default Schedule

- **Full backups**: Daily at 2:00 AM
- **Incremental backups**: Every 6 hours (00:00, 06:00, 12:00, 18:00)

### Check Status

**Systemd:**
```bash
systemctl list-timers | grep minio-backup
systemctl status minio-backup-full.timer
journalctl -u minio-backup-full.service -f
```

**Cron:**
```bash
cat /etc/cron.d/minio-backup
tail -f /var/log/minio_backup.log
```

## Backup Retention

Old backups are automatically deleted based on:
- Age: Delete backups older than `RETENTION_DAYS` (default: 30)
- Count: Always keep last `KEEP_LAST_FULL_BACKUPS` (default: 7)

## Encryption

### Generate GPG Key

```bash
# Generate key
gpg --gen-key

# Export public key (for encryption)
gpg --export --armor you@example.com > /etc/backup/public-key.asc

# Export private key (for decryption - keep secure!)
gpg --export-secret-keys --armor you@example.com > /etc/backup/private-key.asc
```

### Use Encryption

```bash
# Backup with encryption
./backup.sh --type full --encrypt --key-file /etc/backup/public-key.asc

# Restore encrypted backup
../restore/restore.sh --file /backup/backup.tar.gz.gpg \
  --key-file /etc/backup/private-key.asc
```

## Troubleshooting

### Check Logs

```bash
# Backup logs
tail -f /var/log/minio_backup.log

# Systemd logs
journalctl -u minio-backup-full.service -f

# Docker logs
docker-compose -f ../../deployments/docker/docker-compose.production.yml logs -f
```

### Common Issues

1. **Permission denied**: Run with `sudo` or as root
2. **No space left**: Clean old backups or increase disk space
3. **Container not running**: Start services with docker-compose
4. **Corrupt archive**: Enable verification with `--verify`

### Test Backup

```bash
# Verify backup integrity
tar -tzf /backup/backup.tar.gz > /dev/null && echo "OK" || echo "CORRUPTED"

# Dry run restore
../restore/restore.sh --file /backup/backup.tar.gz --dry-run
```

## Best Practices

1. **Test restores regularly** (monthly recommended)
2. **Enable verification** (`VERIFY=true` in config)
3. **Use encryption** for offsite backups
4. **Monitor disk space** (5x data size recommended)
5. **Keep offsite copies** (3-2-1 backup rule)
6. **Document recovery procedures** in runbook

## Performance

### Expected Times

| Data Size | Backup Time | Restore Time |
|-----------|-------------|--------------|
| < 10 GB   | 2-5 min     | 5-10 min     |
| 10-50 GB  | 5-15 min    | 10-20 min    |
| 50-200 GB | 15-45 min   | 20-40 min    |
| > 200 GB  | 45+ min     | 40-90 min    |

### Optimization

```bash
# In backup.conf
PARALLEL_JOBS=2          # Backup components in parallel
IO_NICE=5                # Lower I/O priority (less impact)
CPU_NICE=10              # Lower CPU priority
```

## Documentation

For detailed documentation, see:
- [BACKUP_RESTORE.md](../../docs/guides/BACKUP_RESTORE.md) - Complete guide (500+ lines)

## Support

- **Issues**: [GitHub Issues](https://github.com/abiolaogu/MinIO/issues)
- **Discussions**: [GitHub Discussions](https://github.com/abiolaogu/MinIO/discussions)

---

**Quick Links:**
- [Configuration File](backup.conf)
- [Full Documentation](../../docs/guides/BACKUP_RESTORE.md)
- [Main README](../../README.md)
