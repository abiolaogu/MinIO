# MinIO Enterprise - Backup & Restore Guide

## Table of Contents
1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Backup Operations](#backup-operations)
4. [Restore Operations](#restore-operations)
5. [Scheduling Automated Backups](#scheduling-automated-backups)
6. [Configuration](#configuration)
7. [Best Practices](#best-practices)
8. [Disaster Recovery](#disaster-recovery)
9. [Troubleshooting](#troubleshooting)
10. [Reference](#reference)

---

## Overview

The MinIO Enterprise backup and restore system provides comprehensive data protection for:

- **PostgreSQL Database**: Tenant metadata, quotas, and system state
- **Redis Cache**: Session data and temporary state
- **MinIO Object Data**: All stored objects and metadata
- **Configuration Files**: Docker Compose, Prometheus, Grafana configs

### Key Features

- ✅ **Full & Incremental Backups**: Efficient incremental backups based on rsync
- ✅ **Compression**: Multiple algorithms (gzip, bzip2, xz)
- ✅ **Encryption**: GPG encryption for secure backups
- ✅ **Automated Scheduling**: Cron-based automated backups
- ✅ **Retention Policies**: Automatic cleanup of old backups
- ✅ **Verification**: Built-in backup and restore verification
- ✅ **S3 Upload**: Optional upload to S3-compatible storage
- ✅ **Notifications**: Email and webhook notifications
- ✅ **Safe Restore**: Pre-restore backup and rollback capability

### Backup Types

| Type | When to Use | Storage Efficiency | Speed |
|------|-------------|-------------------|-------|
| **Full** | Weekly/monthly, first backup | Low (100% of data) | Slower |
| **Incremental** | Daily backups | High (only changes) | Faster |

---

## Quick Start

### Prerequisites

```bash
# Install required tools
sudo apt-get update
sudo apt-get install -y postgresql-client redis-tools rsync gzip

# Optional: For S3 uploads
sudo apt-get install -y awscli

# Optional: For encryption
sudo apt-get install -y gnupg
```

### Initial Setup

```bash
# 1. Navigate to backup scripts directory
cd /home/runner/work/MinIO/MinIO/scripts/backup

# 2. Create configuration from example
cp backup.conf.example backup.conf

# 3. Edit configuration with your settings
nano backup.conf

# 4. Make scripts executable
chmod +x backup.sh
chmod +x schedule-backups.sh

# 5. Create backup destination directory
sudo mkdir -p /var/backups/minio
sudo chown $USER:$USER /var/backups/minio

# 6. Run your first backup
./backup.sh full -v
```

### First Backup

```bash
# Full backup with verification
./backup.sh full -v

# Full encrypted backup
./backup.sh full -e -v

# Incremental backup (after first full backup)
./backup.sh incremental
```

---

## Backup Operations

### Basic Backup Commands

```bash
# Full backup
./backup.sh full

# Incremental backup
./backup.sh incremental

# Full backup with encryption and verification
./backup.sh full -e -v

# Backup to custom location
./backup.sh full -d /mnt/external/backups

# Use custom configuration
./backup.sh full -c /etc/minio/custom-backup.conf
```

### Backup Script Options

| Option | Description | Example |
|--------|-------------|---------|
| `full` | Full backup of all data | `./backup.sh full` |
| `incremental` | Changes since last full backup | `./backup.sh incremental` |
| `-c, --config PATH` | Custom configuration file | `-c /etc/backup.conf` |
| `-d, --destination PATH` | Override backup destination | `-d /mnt/backups` |
| `-e, --encrypt` | Enable GPG encryption | `-e` |
| `-v, --verify` | Verify backup after creation | `-v` |
| `-h, --help` | Show help message | `-h` |

### Backup Process Flow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Load Configuration & Validate                            │
├─────────────────────────────────────────────────────────────┤
│ 2. Create Backup Directory Structure                        │
│    ├── postgresql/                                          │
│    ├── redis/                                               │
│    ├── minio-data/                                          │
│    ├── config/                                              │
│    └── metadata/                                            │
├─────────────────────────────────────────────────────────────┤
│ 3. Backup Components                                        │
│    ├── PostgreSQL (pg_dump)                                 │
│    ├── Redis (BGSAVE + copy dump.rdb)                      │
│    ├── MinIO Data (rsync)                                   │
│    └── Configuration Files (cp)                             │
├─────────────────────────────────────────────────────────────┤
│ 4. Compress Backups (if configured)                         │
├─────────────────────────────────────────────────────────────┤
│ 5. Create Backup Metadata                                   │
├─────────────────────────────────────────────────────────────┤
│ 6. Encrypt Backup (if -e flag used)                         │
├─────────────────────────────────────────────────────────────┤
│ 7. Verify Backup (if -v flag used)                          │
├─────────────────────────────────────────────────────────────┤
│ 8. Upload to S3 (if S3_BACKUP_ENABLED=true)                │
├─────────────────────────────────────────────────────────────┤
│ 9. Apply Retention Policy (delete old backups)              │
├─────────────────────────────────────────────────────────────┤
│ 10. Send Notification (if configured)                       │
└─────────────────────────────────────────────────────────────┘
```

### Backup Directory Structure

```
/var/backups/minio/
├── full/
│   ├── 20260208_020000/
│   │   ├── postgresql/
│   │   │   └── minio_database.sql.gz
│   │   ├── redis/
│   │   │   └── dump.rdb.gz
│   │   ├── minio-data/
│   │   │   └── [object files]
│   │   ├── config/
│   │   │   ├── docker-compose.production.yml
│   │   │   ├── prometheus/
│   │   │   └── grafana/
│   │   └── metadata/
│   │       └── backup_info.json
│   └── 20260215_020000/
│       └── [same structure]
└── incremental/
    ├── 20260209_020000/
    │   └── [same structure, but minio-data uses hard links]
    └── 20260210_020000/
        └── [same structure]
```

### Backup Metadata Example

```json
{
  "backup_type": "full",
  "timestamp": "20260208_020000",
  "date": "2026-02-08T02:00:00+00:00",
  "hostname": "minio-server-01",
  "backup_directory": "/var/backups/minio/full/20260208_020000",
  "components": {
    "postgresql": {
      "host": "localhost",
      "port": "5432",
      "database": "minio"
    },
    "redis": {
      "host": "localhost",
      "port": "6379"
    },
    "minio": {
      "data_directory": "/var/lib/minio/data"
    }
  },
  "settings": {
    "compression": "gzip",
    "encrypted": true
  }
}
```

---

## Restore Operations

### Basic Restore Commands

```bash
# Navigate to restore scripts directory
cd /home/runner/work/MinIO/MinIO/scripts/restore

# Full restore (with confirmation prompt)
./restore.sh /var/backups/minio/full/20260208_020000

# Force restore without prompts
./restore.sh /var/backups/minio/full/20260208_020000 -f

# Restore only PostgreSQL database
./restore.sh /var/backups/minio/full/20260208_020000 --postgresql-only

# Restore without verification (faster)
./restore.sh /var/backups/minio/full/20260208_020000 -s

# Use custom configuration
./restore.sh /var/backups/minio/full/20260208_020000 -c /etc/restore.conf
```

### Restore Script Options

| Option | Description | Example |
|--------|-------------|---------|
| `<backup_dir>` | Path to backup directory (required) | `/var/backups/minio/full/20260208_020000` |
| `-c, --config PATH` | Custom configuration file | `-c /etc/restore.conf` |
| `-s, --skip-verification` | Skip backup verification | `-s` |
| `-f, --force` | No confirmation prompts | `-f` |
| `--postgresql-only` | Restore only PostgreSQL | `--postgresql-only` |
| `--redis-only` | Restore only Redis | `--redis-only` |
| `--minio-only` | Restore only MinIO data | `--minio-only` |
| `--config-only` | Restore only config files | `--config-only` |
| `-h, --help` | Show help message | `-h` |

### Restore Process Flow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Load Configuration & Validate                            │
├─────────────────────────────────────────────────────────────┤
│ 2. Validate Backup Directory & Metadata                     │
├─────────────────────────────────────────────────────────────┤
│ 3. Verify Backup Integrity (unless -s flag)                 │
├─────────────────────────────────────────────────────────────┤
│ 4. Confirm Restore Operation (unless -f flag)               │
├─────────────────────────────────────────────────────────────┤
│ 5. Create Pre-Restore Backup (safety net)                   │
├─────────────────────────────────────────────────────────────┤
│ 6. Stop MinIO Services                                      │
│    ├── Stop Docker containers (if applicable)               │
│    └── Stop systemd service (if applicable)                 │
├─────────────────────────────────────────────────────────────┤
│ 7. Restore Components                                       │
│    ├── PostgreSQL (psql < dump.sql)                         │
│    ├── Redis (copy dump.rdb)                                │
│    ├── MinIO Data (rsync)                                   │
│    └── Configuration Files (cp)                             │
├─────────────────────────────────────────────────────────────┤
│ 8. Start MinIO Services (if RESTART_SERVICES=true)          │
├─────────────────────────────────────────────────────────────┤
│ 9. Verify Restore (check services responding)               │
├─────────────────────────────────────────────────────────────┤
│ 10. Complete (or rollback if verification fails)            │
└─────────────────────────────────────────────────────────────┘
```

### Safety Features

#### Pre-Restore Backup

Before any restore operation, the system automatically creates a backup of the current state:

```bash
# Automatic pre-restore backup location
/var/backups/minio/pre-restore/20260208_143022/
├── postgresql_pre_restore.sql
└── minio-data/
```

This allows you to rollback if the restore doesn't work as expected.

#### Rollback Procedure

If restore fails or you need to rollback:

```bash
# The pre-restore backup is saved at:
ls /var/backups/minio/pre-restore/

# Restore from pre-restore backup
./restore.sh /var/backups/minio/pre-restore/20260208_143022 -f
```

---

## Scheduling Automated Backups

### Install Backup Schedule

```bash
cd /home/runner/work/MinIO/MinIO/scripts/backup

# Install with default schedule (full backup Sunday 2 AM, incremental Mon-Sat 2 AM)
sudo ./schedule-backups.sh install

# Install for specific user
sudo CRON_USER=minio ./schedule-backups.sh install

# Custom schedule
FULL_BACKUP_SCHEDULE="0 3 * * 0" \
INCREMENTAL_BACKUP_SCHEDULE="0 3 * * 1-6" \
sudo ./schedule-backups.sh install
```

### Check Backup Schedule

```bash
# Check schedule status
sudo ./schedule-backups.sh status

# View crontab directly
crontab -l | grep backup
```

### Uninstall Backup Schedule

```bash
# Remove scheduled backups
sudo ./schedule-backups.sh uninstall
```

### Default Schedule

| Backup Type | Schedule | Time | Frequency |
|-------------|----------|------|-----------|
| Full | `0 2 * * 0` | 2:00 AM | Every Sunday |
| Incremental | `0 2 * * 1-6` | 2:00 AM | Monday-Saturday |

### Custom Schedules

#### Cron Schedule Format

```
* * * * *
│ │ │ │ │
│ │ │ │ └─── Day of week (0-7, Sun=0 or 7)
│ │ │ └───── Month (1-12)
│ │ └─────── Day of month (1-31)
│ └───────── Hour (0-23)
└─────────── Minute (0-59)
```

#### Schedule Examples

```bash
# Every day at 2 AM
FULL_BACKUP_SCHEDULE="0 2 * * *"

# Every 6 hours
FULL_BACKUP_SCHEDULE="0 */6 * * *"

# First day of month at midnight
FULL_BACKUP_SCHEDULE="0 0 1 * *"

# Every weekday at 11 PM
INCREMENTAL_BACKUP_SCHEDULE="0 23 * * 1-5"

# Every 4 hours during business hours (9 AM - 5 PM)
INCREMENTAL_BACKUP_SCHEDULE="0 9-17/4 * * *"
```

### Monitoring Scheduled Backups

```bash
# View backup logs
tail -f /var/log/minio/backup-full.log
tail -f /var/log/minio/backup-incremental.log

# Check last backup status
tail -n 50 /var/log/minio/backup-full.log | grep -E "(SUCCESS|ERROR|completed)"

# Check backup sizes
du -sh /var/backups/minio/full/*
du -sh /var/backups/minio/incremental/*

# List recent backups
find /var/backups/minio -type d -name "202*" -mtime -7 | sort
```

---

## Configuration

### Backup Configuration (`backup.conf`)

```bash
# Create configuration from example
cp backup.conf.example backup.conf

# Edit configuration
nano backup.conf
```

#### Essential Settings

```bash
# Backup destination
BACKUP_DESTINATION="/var/backups/minio"

# Retention (days)
RETENTION_DAYS=30

# Database credentials
PG_HOST="localhost"
PG_PORT="5432"
PG_DATABASE="minio"
PG_USER="minio"
export PGPASSWORD="your_password"  # Set via environment

# Redis credentials
REDIS_HOST="localhost"
REDIS_PORT="6379"
export REDIS_PASSWORD="your_password"  # Set via environment

# MinIO data path
MINIO_DATA_DIR="/var/lib/minio/data"

# Compression: gzip, bzip2, xz, none
COMPRESSION="gzip"
```

#### Advanced Settings

```bash
# Encryption (requires GPG key)
ENCRYPTION_KEY_FILE="/etc/minio/backup-key.asc"

# S3 backup
S3_BACKUP_ENABLED=true
S3_ENDPOINT="https://s3.amazonaws.com"
S3_BUCKET="minio-backups"
S3_ACCESS_KEY="your_access_key"
S3_SECRET_KEY="your_secret_key"

# Notifications
NOTIFICATION_EMAIL="admin@example.com"
NOTIFICATION_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

### Restore Configuration (`restore.conf`)

```bash
# Create configuration from example
cp restore.conf.example restore.conf

# Edit configuration
nano restore.conf
```

#### Essential Settings

```bash
# Database credentials
PG_HOST="localhost"
PG_PORT="5432"
PG_DATABASE="minio"
PG_USER="minio"
export PGPASSWORD="your_password"

# Redis credentials
REDIS_HOST="localhost"
REDIS_PORT="6379"

# MinIO data path
MINIO_DATA_DIR="/var/lib/minio/data"

# Pre-restore backup (recommended)
CREATE_PRE_RESTORE_BACKUP=true
PRE_RESTORE_BACKUP_DIR="/var/backups/minio/pre-restore"

# Service management
RESTART_SERVICES=true
MINIO_SERVICE_NAME="minio"
```

### Encryption Setup

#### Generate GPG Key

```bash
# Generate a new GPG key pair
gpg --full-generate-key

# Follow prompts:
# - Kind of key: (1) RSA and RSA (default)
# - Key size: 4096
# - Expiration: 0 (does not expire) or set expiration
# - Real name: MinIO Backup
# - Email: backup@example.com

# Export public key for encryption
gpg --export --armor backup@example.com > /etc/minio/backup-key.asc

# Set in backup.conf
ENCRYPTION_KEY_FILE="/etc/minio/backup-key.asc"
```

#### Decrypt Encrypted Backup

```bash
# If backup was encrypted, decrypt first
gpg --decrypt backup.tar.gz.gpg > backup.tar.gz

# Extract
tar xzf backup.tar.gz

# Then restore
./restore.sh /path/to/extracted/backup
```

---

## Best Practices

### Backup Strategy

#### 3-2-1 Backup Rule

- **3** copies of your data (production + 2 backups)
- **2** different storage media (local disk + cloud/tape)
- **1** copy offsite (cloud storage, remote datacenter)

#### Recommended Schedule

| Environment | Full Backup | Incremental | Retention |
|-------------|-------------|-------------|-----------|
| **Development** | Weekly | Daily | 7 days |
| **Staging** | Weekly | Daily | 14 days |
| **Production** | Weekly | Daily | 30-90 days |
| **High-Compliance** | Daily | Hourly | 365 days |

### Testing Backups

```bash
# Test backup monthly
# 1. Run full backup
./backup.sh full -v

# 2. Find latest backup
latest_backup=$(find /var/backups/minio/full -type d -name "202*" | sort -r | head -n 1)

# 3. Test restore to staging environment
# (on staging server)
./restore.sh $latest_backup --postgresql-only
./restore.sh $latest_backup --minio-only

# 4. Verify data integrity
# - Check database records
# - Verify object count matches
# - Test API operations
```

### Monitoring & Alerts

#### Set Up Slack Notifications

```bash
# 1. Create Slack webhook
# Go to: https://api.slack.com/messaging/webhooks
# Create webhook for #alerts channel

# 2. Add to backup.conf
NOTIFICATION_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# 3. Test notification
curl -X POST $NOTIFICATION_WEBHOOK \
  -H "Content-Type: application/json" \
  -d '{"text":"MinIO Backup Test Notification"}'
```

#### Monitor Backup Health

```bash
#!/bin/bash
# check-backup-health.sh

BACKUP_DIR="/var/backups/minio"
MAX_AGE_HOURS=48  # Alert if no backup in 48 hours

# Find most recent backup
latest_backup=$(find $BACKUP_DIR -type d -name "202*" -mtime -2 | sort -r | head -n 1)

if [[ -z "$latest_backup" ]]; then
    echo "ERROR: No recent backup found (older than $MAX_AGE_HOURS hours)"
    # Send alert
    exit 1
else
    echo "OK: Recent backup found: $latest_backup"
    exit 0
fi
```

### Security Considerations

1. **Encrypt Backups**: Always use `-e` flag for production backups
2. **Secure Credentials**: Use environment variables, not config files
3. **Restrict Access**: Set proper file permissions
   ```bash
   chmod 600 backup.conf restore.conf
   chmod 700 backup.sh restore.sh
   ```
4. **Offsite Storage**: Upload to S3 or remote location
5. **Audit Logs**: Review backup logs regularly

### Storage Management

#### Monitor Disk Usage

```bash
# Check backup storage usage
du -sh /var/backups/minio/*

# Check by backup type
du -sh /var/backups/minio/full
du -sh /var/backups/minio/incremental

# Check oldest backups
find /var/backups/minio -type d -name "202*" | sort | head -n 10
```

#### Optimize Storage

```bash
# Use higher compression for older backups
cd /var/backups/minio/full

# Recompress with xz (best compression)
for backup in $(find . -type d -name "202*" -mtime +30); do
    tar cf - $backup | xz -9 > ${backup}.tar.xz
    rm -rf $backup
done
```

---

## Disaster Recovery

### Complete System Recovery

#### Scenario: Complete server failure

**Recovery Time Objective (RTO)**: < 2 hours
**Recovery Point Objective (RPO)**: < 24 hours (with daily backups)

#### Recovery Steps

```bash
# 1. Provision new server with same OS
# 2. Install MinIO Enterprise and dependencies
git clone <repo-url>
cd MinIO
make install-deps

# 3. Copy latest backup to new server
scp -r backup-server:/var/backups/minio/full/20260208_020000 /tmp/

# 4. Configure restore
cd scripts/restore
cp restore.conf.example restore.conf
nano restore.conf  # Update with new server details

# 5. Perform full restore
./restore.sh /tmp/20260208_020000 -f

# 6. Verify services
docker ps
curl http://localhost:9000/health

# 7. Verify data integrity
# - Check object count
# - Test API operations
# - Run smoke tests

# 8. Resume production traffic
# - Update DNS/load balancer
# - Monitor for issues
```

### Partial Recovery Scenarios

#### Scenario 1: Corrupted PostgreSQL Database

```bash
# Restore only database
./restore.sh /var/backups/minio/full/20260208_020000 --postgresql-only

# Verify database
psql -h localhost -U minio -d minio -c "SELECT COUNT(*) FROM tenants;"
```

#### Scenario 2: Accidentally Deleted Objects

```bash
# Restore only MinIO data
./restore.sh /var/backups/minio/full/20260208_020000 --minio-only

# Verify object count
find /var/lib/minio/data -type f | wc -l
```

#### Scenario 3: Lost Configuration

```bash
# Restore only configuration files
./restore.sh /var/backups/minio/full/20260208_020000 --config-only

# Restart services to apply new config
docker-compose restart
```

### Recovery Testing

#### Quarterly DR Drill

```bash
# 1. Document current state
date > dr-drill-start.txt
docker ps >> dr-drill-start.txt
psql -h localhost -U minio -d minio -c "\dt" >> dr-drill-start.txt

# 2. Simulate disaster (on test environment!)
docker-compose down -v
sudo rm -rf /var/lib/minio/data/*

# 3. Perform recovery
cd scripts/restore
./restore.sh /var/backups/minio/full/latest -f

# 4. Verify recovery
docker ps
psql -h localhost -U minio -d minio -c "\dt"

# 5. Document recovery time and issues
date > dr-drill-complete.txt

# 6. Update recovery procedures based on findings
```

---

## Troubleshooting

### Common Issues

#### Issue 1: Backup Script Fails - Permission Denied

**Symptom**: Error message: "Permission denied" when running backup

**Solution**:
```bash
# Check script permissions
ls -l backup.sh

# Make executable
chmod +x backup.sh

# Check backup destination permissions
ls -ld /var/backups/minio

# Fix ownership
sudo chown -R $USER:$USER /var/backups/minio
```

#### Issue 2: PostgreSQL Backup Fails - Authentication Error

**Symptom**: `pg_dump: error: connection to server failed: FATAL: password authentication failed`

**Solution**:
```bash
# Set password via environment variable (don't put in config file)
export PGPASSWORD="your_password"

# Or use .pgpass file
echo "localhost:5432:minio:minio:your_password" > ~/.pgpass
chmod 600 ~/.pgpass

# Test connection
psql -h localhost -p 5432 -U minio -d minio -c "SELECT 1"
```

#### Issue 3: Backup Takes Too Long

**Symptom**: Backup runs for hours and doesn't complete

**Solution**:
```bash
# Check what's taking time
time ./backup.sh full 2>&1 | tee backup-timing.log

# If PostgreSQL is slow:
# - Increase checkpoint_timeout in postgresql.conf
# - Use pg_dump with --jobs option for parallel dump

# If MinIO data is large:
# - Use incremental backups instead of full
# - Exclude temporary/cache directories
# - Run backups during off-peak hours

# If compression is slow:
# - Use gzip instead of xz/bzip2
# - Or disable compression: COMPRESSION="none"
```

#### Issue 4: Restore Fails - Services Won't Start

**Symptom**: After restore, MinIO services fail to start

**Solution**:
```bash
# Check service status
docker ps -a
systemctl status minio

# Check logs
docker logs minio-1
journalctl -u minio -n 100

# Common fixes:
# 1. Check data directory permissions
sudo chown -R minio:minio /var/lib/minio/data

# 2. Verify database is accessible
psql -h localhost -U minio -d minio -c "SELECT 1"

# 3. Check Redis is running
redis-cli ping

# 4. Verify configuration files
docker-compose config

# 5. Try starting services manually
docker-compose up -d
```

#### Issue 5: Incremental Backup Uses Full Space

**Symptom**: Incremental backups are the same size as full backups

**Solution**:
```bash
# Check if hard links are working
ls -li /var/backups/minio/incremental/*/minio-data/

# If inode numbers are different, hard links aren't working
# This happens when backups cross filesystem boundaries

# Solution: Keep backups on same filesystem as source
# Or: Use different incremental backup strategy

# Alternative: Use btrfs or ZFS snapshots instead
```

### Debug Mode

```bash
# Run backup with verbose output
bash -x ./backup.sh full 2>&1 | tee backup-debug.log

# Check each step
set -x  # Enable debug mode
./backup.sh full
set +x  # Disable debug mode
```

### Log Analysis

```bash
# Search for errors in backup logs
grep -i error /var/log/minio/backup-*.log

# Find failed backups
grep -i "backup.*failed" /var/log/minio/backup-*.log

# Check backup completion times
grep "completed successfully" /var/log/minio/backup-*.log | awk '{print $1, $2, $NF}'

# Monitor real-time backup progress
tail -f /var/log/minio/backup-full.log
```

---

## Reference

### Backup Script Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | Backup completed successfully |
| 1 | Error | Backup failed, check logs |

### Restore Script Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | Restore completed successfully |
| 1 | Error | Restore failed, check logs and consider rollback |

### File Locations

| Type | Path |
|------|------|
| Backup Script | `/home/runner/work/MinIO/MinIO/scripts/backup/backup.sh` |
| Restore Script | `/home/runner/work/MinIO/MinIO/scripts/restore/restore.sh` |
| Scheduler Script | `/home/runner/work/MinIO/MinIO/scripts/backup/schedule-backups.sh` |
| Backup Config | `/home/runner/work/MinIO/MinIO/scripts/backup/backup.conf` |
| Restore Config | `/home/runner/work/MinIO/MinIO/scripts/restore/restore.conf` |
| Backups | `/var/backups/minio/` |
| Logs | `/var/log/minio/backup-*.log` |

### Supported Compression Algorithms

| Algorithm | Compression Ratio | Speed | CPU Usage | Recommendation |
|-----------|-------------------|-------|-----------|----------------|
| **gzip** | Medium (60-70%) | Fast | Low | ✅ Recommended for most cases |
| **bzip2** | High (70-80%) | Medium | Medium | Good for archival |
| **xz** | Very High (75-85%) | Slow | High | Best for long-term storage |
| **none** | None (100%) | Very Fast | None | For fast local backups |

### Estimated Backup Times

(Based on 4-node cluster with 1TB data, SSD storage)

| Backup Type | Data Size | Time | Throughput |
|-------------|-----------|------|------------|
| Full (gzip) | 1TB → 700GB | ~45 min | ~250 MB/s |
| Full (no compression) | 1TB → 1TB | ~20 min | ~850 MB/s |
| Incremental (10% change) | 100GB → 70GB | ~5 min | ~230 MB/s |

### Support & Resources

- **Documentation**: [docs/guides/](../guides/)
- **Issues**: [GitHub Issues](https://github.com/abiolaogu/MinIO/issues)
- **Discussions**: [GitHub Discussions](https://github.com/abiolaogu/MinIO/discussions)

---

**Last Updated**: 2026-02-08
**Version**: 1.0
**Maintainer**: MinIO Enterprise Team
