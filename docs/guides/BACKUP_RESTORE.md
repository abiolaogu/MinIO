# MinIO Enterprise Backup & Restore Guide

**Version**: 1.0.0
**Last Updated**: 2026-02-08
**Status**: Production Ready

---

## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Architecture](#architecture)
4. [Quick Start](#quick-start)
5. [Backup Configuration](#backup-configuration)
6. [Scheduling Backups](#scheduling-backups)
7. [Restore Procedures](#restore-procedures)
8. [Advanced Usage](#advanced-usage)
9. [Best Practices](#best-practices)
10. [Troubleshooting](#troubleshooting)
11. [FAQ](#faq)

---

## Overview

The MinIO Enterprise Backup & Restore system provides automated, reliable disaster recovery capabilities for your MinIO deployment. It supports backing up all critical components including MinIO data, PostgreSQL databases, Redis state, and configuration files.

### Key Components

- **Backup Script** (`scripts/backup/backup.sh`) - Main backup automation script
- **Restore Script** (`scripts/restore/restore.sh`) - Main restore automation script
- **Configuration File** (`scripts/backup/backup.conf`) - Centralized configuration
- **Scheduler Setup** (`scripts/backup/setup-schedule.sh`) - Automated scheduling setup

### What Gets Backed Up

- ✅ MinIO object data (all 4 nodes)
- ✅ PostgreSQL database (complete dump)
- ✅ Redis data (RDB snapshots)
- ✅ Configuration files (Docker Compose, Grafana, Prometheus, etc.)
- ✅ Backup metadata (version, timestamp, components)

---

## Features

### Backup Features

- **Full & Incremental Backups** - Choose between complete or differential backups
- **Compression** - Gzip compression to reduce storage requirements
- **Encryption** - GPG encryption for secure offsite storage
- **Verification** - Automatic integrity checking after backup creation
- **Retention Policies** - Automatic cleanup of old backups
- **Parallel Operations** - Backup multiple components simultaneously
- **Metadata Tracking** - Detailed information about each backup

### Restore Features

- **Selective Restoration** - Restore specific components or everything
- **Verification** - Verify backup integrity before restoring
- **Dry Run Mode** - Preview what would be restored without making changes
- **Service Management** - Automatic stop/start of Docker services
- **Rollback Support** - Backup current state before restoring
- **Health Checks** - Verify system health after restoration

### Scheduling Features

- **Automated Scheduling** - Set up recurring backups with cron or systemd
- **Flexible Schedules** - Different schedules for full and incremental backups
- **Email Notifications** - Get notified of backup success/failure
- **Slack Integration** - Send backup status to Slack channels
- **Offsite Replication** - Automatically replicate backups to remote locations

---

## Architecture

### Backup Process Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Backup Process                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Parse Configuration                                     │
│     ├─ Load backup.conf                                     │
│     ├─ Validate parameters                                  │
│     └─ Check prerequisites                                  │
│                                                             │
│  2. Create Temporary Directory                              │
│     └─ /tmp/minio_backup_<timestamp>                        │
│                                                             │
│  3. Backup Components (Parallel)                            │
│     ├─ MinIO Data (4 nodes)                                 │
│     │  └─ docker exec tar → .tar.gz                         │
│     ├─ PostgreSQL                                           │
│     │  └─ pg_dumpall → .sql                                 │
│     ├─ Redis                                                │
│     │  └─ SAVE + copy dump.rdb                              │
│     └─ Configurations                                       │
│        └─ Copy configs, deployments, .env                   │
│                                                             │
│  4. Create Metadata                                         │
│     └─ backup_info.json                                     │
│                                                             │
│  5. Create Archive                                          │
│     ├─ tar cvf backup.tar                                   │
│     ├─ [Optional] gzip → backup.tar.gz                      │
│     └─ [Optional] gpg encrypt → backup.tar.gz.gpg          │
│                                                             │
│  6. Verify (if enabled)                                     │
│     └─ Test archive integrity                               │
│                                                             │
│  7. Cleanup                                                 │
│     ├─ Remove temporary files                               │
│     └─ Delete old backups per retention policy              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Restore Process Flow

```
┌─────────────────────────────────────────────────────────────┐
│                   Restore Process                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Validate Backup File                                    │
│     ├─ Check file exists                                    │
│     ├─ Verify encryption/compression format                 │
│     └─ Check required tools available                       │
│                                                             │
│  2. Extract Archive                                         │
│     ├─ [If encrypted] gpg decrypt                           │
│     ├─ [If compressed] gunzip                               │
│     └─ tar extract → /tmp/restore                           │
│                                                             │
│  3. Read Metadata                                           │
│     └─ Display backup information                           │
│                                                             │
│  4. Stop Services (if requested)                            │
│     └─ docker-compose down                                  │
│                                                             │
│  5. Restore Components                                      │
│     ├─ MinIO Data                                           │
│     │  └─ docker exec tar restore to /data                  │
│     ├─ PostgreSQL                                           │
│     │  └─ psql < postgres_dump.sql                          │
│     ├─ Redis                                                │
│     │  └─ docker cp dump.rdb → /data                        │
│     └─ Configurations                                       │
│        └─ Copy files to configs/                            │
│                                                             │
│  6. Start Services (if requested)                           │
│     └─ docker-compose up -d                                 │
│                                                             │
│  7. Verify Restoration                                      │
│     ├─ Check container health                               │
│     ├─ Test PostgreSQL connection                           │
│     └─ Test Redis connection                                │
│                                                             │
│  8. Cleanup                                                 │
│     └─ Remove temporary extraction directory                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- Root or sudo access
- Sufficient disk space (3x data size recommended)
- `tar`, `gzip` commands available
- `gpg` (optional, for encryption)

### 1. First Backup (Manual)

```bash
# Navigate to the scripts directory
cd scripts/backup

# Run a full backup with compression
./backup.sh --type full --compress --verify

# Check the backup
ls -lh /backup/
```

### 2. First Restore (Test)

```bash
# Navigate to the restore scripts directory
cd scripts/restore

# Dry run to see what would be restored
./restore.sh --file /backup/minio_backup_full_20260208_120000.tar.gz --dry-run

# Actual restore (stops services, restores, starts services)
./restore.sh --file /backup/minio_backup_full_20260208_120000.tar.gz \
  --stop-services --start-services --verify
```

### 3. Setup Automated Backups

```bash
# Navigate to backup scripts
cd scripts/backup

# Setup automated scheduling (uses systemd or cron)
sudo ./setup-schedule.sh

# Check status
systemctl status minio-backup-full.timer
systemctl status minio-backup-incremental.timer
```

---

## Backup Configuration

### Configuration File Location

`scripts/backup/backup.conf`

### Key Configuration Options

```bash
# Backup type
BACKUP_TYPE="full"              # or "incremental"

# Destination
BACKUP_DEST="/backup"           # Change to your backup location

# Compression & Encryption
COMPRESS=true                   # Enable gzip compression
ENCRYPT=false                   # Enable GPG encryption
GPG_KEY_FILE=""                 # Path to GPG key if encrypted

# Retention
RETENTION_DAYS=30               # Delete backups older than 30 days
KEEP_LAST_FULL_BACKUPS=7        # Always keep last 7 full backups

# Verification
VERIFY=true                     # Verify backup after creation

# Schedules (cron format)
FULL_BACKUP_SCHEDULE="0 2 * * *"              # Daily at 2 AM
INCREMENTAL_BACKUP_SCHEDULE="0 */6 * * *"     # Every 6 hours
```

### Component Selection

```bash
# Enable/disable specific components
BACKUP_MINIO=true
BACKUP_POSTGRESQL=true
BACKUP_REDIS=true
BACKUP_CONFIGS=true
```

### Notification Configuration

```bash
# Email notifications
EMAIL_NOTIFICATIONS=false
EMAIL_RECIPIENTS="admin@example.com"
SMTP_SERVER="smtp.example.com"
SMTP_PORT="587"

# Slack notifications
SLACK_NOTIFICATIONS=false
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

### Advanced Configuration

```bash
# Performance
PARALLEL_JOBS=2                 # Backup jobs in parallel
IO_NICE=5                       # I/O priority (0-7)
CPU_NICE=10                     # CPU priority (0-19)

# Storage backend
STORAGE_BACKEND="local"         # or "s3" or "both"
S3_ENDPOINT="https://s3.amazonaws.com"
S3_BUCKET="minio-backups"
S3_ACCESS_KEY=""
S3_SECRET_KEY=""

# Offsite replication
OFFSITE_REPLICATION=false
OFFSITE_DESTINATION="user@backup-server:/mnt/backups/"
OFFSITE_SSH_KEY="/root/.ssh/backup_id_rsa"
```

---

## Scheduling Backups

### Using the Setup Script (Recommended)

```bash
# Auto-detect and setup (systemd or cron)
sudo ./setup-schedule.sh

# Force cron
sudo ./setup-schedule.sh --method cron

# Force systemd
sudo ./setup-schedule.sh --method systemd

# Run as specific user
sudo ./setup-schedule.sh --user minio

# Uninstall
sudo ./setup-schedule.sh --uninstall
```

### Manual Systemd Setup

If you prefer manual setup:

```bash
# Copy service files
sudo cp systemd/minio-backup-*.service /etc/systemd/system/
sudo cp systemd/minio-backup-*.timer /etc/systemd/system/

# Enable and start timers
sudo systemctl daemon-reload
sudo systemctl enable minio-backup-full.timer
sudo systemctl enable minio-backup-incremental.timer
sudo systemctl start minio-backup-full.timer
sudo systemctl start minio-backup-incremental.timer

# Check status
sudo systemctl list-timers | grep minio-backup
```

### Manual Cron Setup

```bash
# Edit crontab as root
sudo crontab -e

# Add entries
# Full backup daily at 2 AM
0 2 * * * /path/to/scripts/backup/backup.sh --type full --compress --verify >> /var/log/minio_backup.log 2>&1

# Incremental backup every 6 hours
0 */6 * * * /path/to/scripts/backup/backup.sh --type incremental --compress >> /var/log/minio_backup.log 2>&1
```

### Viewing Scheduled Backups

**Systemd:**
```bash
# List timers
systemctl list-timers | grep minio-backup

# Check timer status
systemctl status minio-backup-full.timer

# View logs
journalctl -u minio-backup-full.service -f
```

**Cron:**
```bash
# View crontab
sudo crontab -l

# View cron entries
cat /etc/cron.d/minio-backup

# View logs
tail -f /var/log/minio_backup.log
```

---

## Restore Procedures

### Basic Restore

```bash
# Restore everything from a backup
./restore.sh --file /backup/minio_backup_full_20260208_120000.tar.gz \
  --stop-services --start-services --verify
```

### Restore Options

```bash
# Dry run (preview only)
./restore.sh --file /backup/backup.tar.gz --dry-run

# Restore with verification
./restore.sh --file /backup/backup.tar.gz --verify

# Restore encrypted backup
./restore.sh --file /backup/backup.tar.gz.gpg \
  --key-file /etc/backup/gpg-key.asc

# Custom extraction directory
./restore.sh --file /backup/backup.tar.gz \
  --target /mnt/restore

# Stop services, restore, but don't start (manual start)
./restore.sh --file /backup/backup.tar.gz --stop-services
```

### Disaster Recovery Procedure

**Complete System Failure Recovery:**

```bash
# 1. Ensure Docker and Docker Compose are installed
docker --version
docker-compose --version

# 2. Clone or restore the MinIO repository
git clone <repo-url> MinIO
cd MinIO

# 3. Stop any running services
docker-compose -f deployments/docker/docker-compose.production.yml down

# 4. Restore from latest backup
cd scripts/restore
./restore.sh \
  --file /backup/minio_backup_full_LATEST.tar.gz \
  --stop-services \
  --start-services \
  --verify

# 5. Verify all services are healthy
docker-compose -f deployments/docker/docker-compose.production.yml ps

# 6. Check MinIO health
curl http://localhost:9000/minio/health/live

# 7. Verify data integrity
# Run your application-specific health checks
```

### Partial Restore (Manual)

If you only need to restore specific components:

```bash
# Extract backup to temporary location
./restore.sh --file /backup/backup.tar.gz --target /tmp/restore

# Manually restore only PostgreSQL
cd /tmp/restore/minio_backup_*
docker exec -i postgres psql -U postgres < postgresql/postgres_dump.sql

# Manually restore only Redis
docker cp redis/dump.rdb redis:/data/dump.rdb
docker restart redis

# Manually restore only configs
cp -r configs/* /path/to/MinIO/configs/
```

### Recovery Time Objective (RTO)

Expected recovery times based on data size:

| Data Size | Extraction | Restore | Total RTO |
|-----------|-----------|---------|-----------|
| < 10 GB   | 2-5 min   | 5-10 min | **< 15 min** |
| 10-50 GB  | 5-15 min  | 10-20 min | **< 30 min** |
| 50-200 GB | 15-30 min | 20-40 min | **< 60 min** |
| > 200 GB  | 30-60 min | 40-90 min | **< 2 hours** |

*Times are estimates and depend on hardware, network, and I/O performance.*

---

## Advanced Usage

### Encrypted Backups

**Generate GPG Key:**

```bash
# Generate a new GPG key pair
gpg --gen-key

# Export public key
gpg --export --armor you@example.com > /etc/backup/public-key.asc

# Export private key (keep secure!)
gpg --export-secret-keys --armor you@example.com > /etc/backup/private-key.asc
```

**Backup with Encryption:**

```bash
./backup.sh --type full --encrypt --key-file /etc/backup/public-key.asc
```

**Restore Encrypted Backup:**

```bash
# Import private key first (if on different machine)
gpg --import /etc/backup/private-key.asc

# Restore
./restore.sh --file /backup/backup.tar.gz.gpg --key-file /etc/backup/private-key.asc
```

### Offsite Replication

**Setup SSH Key Authentication:**

```bash
# Generate SSH key
ssh-keygen -t rsa -b 4096 -f /root/.ssh/backup_id_rsa

# Copy to remote server
ssh-copy-id -i /root/.ssh/backup_id_rsa.pub user@backup-server
```

**Configure in backup.conf:**

```bash
OFFSITE_REPLICATION=true
OFFSITE_DESTINATION="user@backup-server:/mnt/backups/minio/"
OFFSITE_SSH_KEY="/root/.ssh/backup_id_rsa"
```

**Manual Offsite Sync:**

```bash
# Sync backups to remote server
rsync -avz --delete \
  -e "ssh -i /root/.ssh/backup_id_rsa" \
  /backup/ \
  user@backup-server:/mnt/backups/minio/
```

### S3-Compatible Storage Backend

**Configure in backup.conf:**

```bash
STORAGE_BACKEND="s3"
S3_ENDPOINT="https://s3.amazonaws.com"
S3_BUCKET="minio-backups"
S3_ACCESS_KEY="YOUR_ACCESS_KEY"
S3_SECRET_KEY="YOUR_SECRET_KEY"
S3_REGION="us-east-1"
```

**Manual S3 Upload:**

```bash
# Install AWS CLI
apt-get install awscli

# Configure credentials
aws configure

# Upload backup to S3
aws s3 cp /backup/minio_backup_full_20260208_120000.tar.gz \
  s3://minio-backups/backups/
```

### Backup Verification

**Verify Backup Integrity:**

```bash
# Verify during backup creation
./backup.sh --type full --verify

# Verify existing backup
tar -tzf /backup/backup.tar.gz > /dev/null && echo "OK" || echo "CORRUPTED"

# Verify encrypted backup
gpg --decrypt /backup/backup.tar.gz.gpg | tar -tz > /dev/null && echo "OK"
```

**Weekly Integrity Check (Automated):**

Configure in `backup.conf`:

```bash
WEEKLY_INTEGRITY_CHECK=true
INTEGRITY_CHECK_DAY=0        # Sunday
INTEGRITY_CHECK_TIME="03:00"
```

---

## Best Practices

### 1. Backup Strategy

**3-2-1 Rule:**
- Keep **3** copies of your data
- Store on **2** different media types
- Keep **1** copy offsite

**Recommended Schedule:**
- **Full backups**: Daily or weekly (depending on data change rate)
- **Incremental backups**: Every 6 hours or hourly
- **Offsite replication**: Daily or after each full backup
- **Verification**: Weekly or after each full backup

### 2. Storage Management

**Retention Policy:**
```bash
# Keep:
# - Last 7 full backups (always)
# - Last 28 incremental backups (always)
# - All backups from last 30 days
# - Monthly backups for 1 year

RETENTION_DAYS=30
KEEP_LAST_FULL_BACKUPS=7
KEEP_LAST_INCREMENTAL_BACKUPS=28
```

**Disk Space Monitoring:**
```bash
# Check backup destination space
df -h /backup

# Calculate required space
# Minimum: 3x uncompressed data size
# Recommended: 5x uncompressed data size
```

### 3. Security

**Encryption:**
- Always encrypt backups stored offsite
- Use GPG with strong key (RSA 4096-bit)
- Store encryption keys securely (separate from backups)
- Rotate encryption keys annually

**Access Control:**
```bash
# Backup directory permissions
chmod 700 /backup
chown root:root /backup

# Script permissions
chmod 750 scripts/backup/backup.sh
chmod 750 scripts/restore/restore.sh
chmod 640 scripts/backup/backup.conf
```

**Secrets Management:**
```bash
# Never store passwords in backup.conf
# Use environment variables or secrets manager
export SMTP_PASSWORD="secret"
export GPG_PASSPHRASE="secret"
```

### 4. Testing

**Monthly Restore Tests:**
```bash
# Test restore to alternate location
./restore.sh \
  --file /backup/minio_backup_full_LATEST.tar.gz \
  --target /tmp/restore-test \
  --dry-run

# Verify metadata
cat /tmp/restore-test/minio_backup_*/metadata/backup_info.json
```

**Disaster Recovery Drill (Quarterly):**
1. Spin up fresh VM/container
2. Install prerequisites
3. Perform complete restore
4. Verify all services and data
5. Document time taken (RTO)
6. Identify improvements

### 5. Monitoring

**Backup Monitoring Checklist:**
- [ ] Backup completion notifications
- [ ] Backup size trending (detect anomalies)
- [ ] Backup age (detect missed backups)
- [ ] Storage capacity monitoring
- [ ] Backup verification status
- [ ] Restoration test results

**Setup Alerts:**
```bash
# Example: Alert if backup older than 48 hours
find /backup -name "minio_backup_full_*" -mtime +2 | grep . && \
  echo "WARNING: No recent full backup!" | mail -s "Backup Alert" admin@example.com
```

### 6. Documentation

**Maintain a Runbook:**
- Backup schedule and retention policy
- Recovery procedures for common scenarios
- Contact information for on-call personnel
- Locations of encryption keys and credentials
- Testing schedule and results log

---

## Troubleshooting

### Common Issues

#### 1. Backup Script Fails with "Permission Denied"

**Symptoms:**
```
[ERROR] Failed to backup minio1 data. Permission denied.
```

**Solution:**
```bash
# Ensure script is run as root or with sudo
sudo ./backup.sh --type full

# Check Docker socket permissions
ls -l /var/run/docker.sock

# Add user to docker group
sudo usermod -aG docker $USER
```

#### 2. Not Enough Disk Space

**Symptoms:**
```
[ERROR] No space left on device
tar: Error writing to archive
```

**Solution:**
```bash
# Check available space
df -h /backup

# Clean old backups manually
find /backup -name "minio_backup_*" -mtime +30 -delete

# Increase retention policy cleanup frequency
# Edit backup.conf: RETENTION_DAYS=15
```

#### 3. PostgreSQL Backup Fails

**Symptoms:**
```
[WARNING] Failed to backup PostgreSQL database
pg_dumpall: connection failed
```

**Solution:**
```bash
# Check if PostgreSQL container is running
docker ps | grep postgres

# Start PostgreSQL
docker-compose -f deployments/docker/docker-compose.production.yml up -d postgres

# Test connection manually
docker exec postgres pg_isready -U postgres

# Check logs
docker logs postgres
```

#### 4. Restore Fails with "Corrupt Archive"

**Symptoms:**
```
[ERROR] Backup verification failed: corrupt archive
tar: Unexpected EOF in archive
```

**Solution:**
```bash
# Try different extraction location
./restore.sh --file /backup/backup.tar.gz --target /mnt/restore

# Check backup file integrity
tar -tzf /backup/backup.tar.gz > /dev/null

# If corrupted, restore from previous backup
ls -lt /backup/ | grep minio_backup_full

# Consider enabling verification during backup
# Edit backup.conf: VERIFY=true
```

#### 5. GPG Decryption Fails

**Symptoms:**
```
[ERROR] Failed to decrypt backup
gpg: decryption failed: No secret key
```

**Solution:**
```bash
# List available keys
gpg --list-secret-keys

# Import private key
gpg --import /path/to/private-key.asc

# Verify key matches backup
gpg --list-keys

# If passphrase protected, provide it
export GPG_PASSPHRASE="your_passphrase"
./restore.sh --file /backup/backup.tar.gz.gpg
```

### Debug Mode

Enable verbose logging:

```bash
# Edit scripts and add at the top
set -x  # Enable debug output

# Or run with bash -x
bash -x ./backup.sh --type full
```

### Log Files

Check log files for details:

```bash
# Backup logs
tail -f /var/log/minio_backup.log

# Systemd service logs
journalctl -u minio-backup-full.service -f

# Docker logs
docker-compose -f deployments/docker/docker-compose.production.yml logs -f
```

---

## FAQ

### Q: How much disk space do I need for backups?

**A:** As a general rule:
- **Minimum**: 3x uncompressed data size
- **Recommended**: 5x uncompressed data size
- With compression (gzip): ~40-60% size reduction
- With retention policy (30 days): Plan for 30 backups

Example: If you have 100GB of data:
- Compressed backup size: ~40-60GB
- With 30-day retention: ~1.8TB (30 full backups)
- Recommended storage: 2-3TB

### Q: Should I use full or incremental backups?

**A:** Use both:
- **Full backups**: Daily or weekly (simpler restore, larger size)
- **Incremental backups**: Hourly or every 6 hours (faster, smaller size)

Incremental backups only save changed data since the last backup, making them faster and smaller but requiring the base full backup to restore.

### Q: How long does a backup take?

**A:** Depends on data size and hardware:
- **< 10GB**: 2-5 minutes
- **10-50GB**: 5-15 minutes
- **50-200GB**: 15-45 minutes
- **> 200GB**: 45+ minutes

Factors that affect speed:
- Disk I/O speed (SSD vs HDD)
- Network speed (for offsite replication)
- Compression enabled
- CPU resources available

### Q: Can I restore to a different server?

**A:** Yes! The restore process is portable:

1. Install Docker and Docker Compose on the new server
2. Copy the backup file to the new server
3. Clone or copy the MinIO repository structure
4. Run the restore script

```bash
# On new server
git clone <repo-url> MinIO
cd MinIO/scripts/restore
./restore.sh --file /path/to/backup.tar.gz --start-services
```

### Q: What happens if a backup fails?

**A:** The backup script:
1. Logs the error to `/var/log/minio_backup.log`
2. Sends notification (if configured)
3. Cleans up temporary files
4. Exits with error code (1)

Scheduled backups will retry on the next schedule. Check logs to diagnose the issue.

### Q: Can I backup while MinIO is running?

**A:** Yes! The backup script is designed to work with running services:
- Uses `docker exec` to backup data without stopping containers
- PostgreSQL uses `pg_dumpall` which supports hot backups
- Redis uses `SAVE` command for consistent snapshots
- Minimal impact on production workload

### Q: How do I test if my backups are good?

**A:** Several methods:

1. **Verification during backup** (recommended):
   ```bash
   ./backup.sh --type full --verify
   ```

2. **Manual verification**:
   ```bash
   tar -tzf /backup/backup.tar.gz > /dev/null && echo "OK"
   ```

3. **Dry run restore**:
   ```bash
   ./restore.sh --file /backup/backup.tar.gz --dry-run
   ```

4. **Full restore test** (monthly recommended):
   - Restore to test environment
   - Verify all services start
   - Check data integrity

### Q: What's the recommended backup retention policy?

**A:** Standard 3-2-1 rule with these retention periods:

```
Daily full backups:     Keep 7 days
Weekly full backups:    Keep 4 weeks
Monthly full backups:   Keep 12 months
Incremental backups:    Keep 7 days
Offsite backups:        Keep 30 days
```

Configure in `backup.conf`:
```bash
RETENTION_DAYS=30
KEEP_LAST_FULL_BACKUPS=7
KEEP_LAST_INCREMENTAL_BACKUPS=28
```

### Q: Can I exclude specific MinIO nodes from backup?

**A:** Yes, edit `backup.sh`:

```bash
# Find the backup_minio_data() function
# Comment out nodes you want to skip:
for node in minio1 minio2 minio3 minio4; do
    # Skip minio4
    [[ "$node" == "minio4" ]] && continue

    # ... backup code ...
done
```

### Q: How do I backup to cloud storage (S3, GCS, Azure)?

**A:** Configure S3-compatible storage in `backup.conf`:

```bash
STORAGE_BACKEND="both"  # Local + S3
S3_ENDPOINT="https://s3.amazonaws.com"
S3_BUCKET="minio-backups"
S3_ACCESS_KEY="YOUR_KEY"
S3_SECRET_KEY="YOUR_SECRET"
```

Or use rclone for more options:
```bash
# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Configure cloud backend
rclone config

# Add to backup script
rclone sync /backup/ remote:minio-backups/
```

---

## Support & Resources

### Documentation
- [README.md](../../README.md) - Project overview
- [DEPLOYMENT.md](DEPLOYMENT.md) - Deployment guide
- [PERFORMANCE.md](PERFORMANCE.md) - Performance optimization

### Getting Help
- **GitHub Issues**: [Report issues](https://github.com/abiolaogu/MinIO/issues)
- **GitHub Discussions**: [Ask questions](https://github.com/abiolaogu/MinIO/discussions)

### Related Scripts
- `scripts/backup/backup.sh` - Main backup script
- `scripts/restore/restore.sh` - Main restore script
- `scripts/backup/setup-schedule.sh` - Scheduling setup
- `scripts/backup/backup.conf` - Configuration file

---

**Document Version**: 1.0.0
**Last Updated**: 2026-02-08
**Maintainer**: Development Team
**Review Cycle**: Monthly
