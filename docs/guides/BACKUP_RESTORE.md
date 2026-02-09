# MinIO Enterprise Backup & Restore Guide

**Version**: 1.0.0
**Last Updated**: 2026-02-09
**Status**: Production Ready

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Quick Start](#quick-start)
4. [Backup Operations](#backup-operations)
5. [Restore Operations](#restore-operations)
6. [Verification](#verification)
7. [Scheduling](#scheduling)
8. [Best Practices](#best-practices)
9. [Disaster Recovery](#disaster-recovery)
10. [Troubleshooting](#troubleshooting)
11. [Advanced Topics](#advanced-topics)

---

## Overview

The MinIO Enterprise Backup & Restore system provides comprehensive automated backup and disaster recovery capabilities for:

- **PostgreSQL Database**: Complete database dumps with full schema and data
- **Redis Cache**: RDB snapshots for cache persistence
- **MinIO Object Storage**: All object data with incremental backup support
- **Configuration Files**: Application and deployment configurations

### Key Features

✅ **Full and Incremental Backups**: Optimize storage with incremental backups
✅ **Encryption Support**: AES-256-CBC encryption for secure backups
✅ **Compression**: Gzip compression to reduce backup size
✅ **S3 Integration**: Automatic offsite backup to S3-compatible storage
✅ **Verification Tools**: Comprehensive backup validation
✅ **Rollback Support**: Safe restore with automatic rollback on failure
✅ **Notifications**: Webhook notifications for backup/restore events
✅ **Retention Management**: Automatic cleanup of old backups

---

## Architecture

### Backup Components

```
┌─────────────────────────────────────────────────────────┐
│                  Backup System                          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │  PostgreSQL  │  │    Redis     │  │    MinIO     │ │
│  │   Database   │  │    Cache     │  │  Object Data │ │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘ │
│         │                 │                 │          │
│         └─────────────────┴─────────────────┘          │
│                           │                            │
│                    ┌──────▼──────┐                     │
│                    │   Backup    │                     │
│                    │   Script    │                     │
│                    └──────┬──────┘                     │
│                           │                            │
│         ┌─────────────────┴─────────────────┐          │
│         │                                   │          │
│  ┌──────▼────────┐                 ┌───────▼───────┐  │
│  │  Local Storage│                 │  S3 Storage   │  │
│  │  /var/backups │                 │   (Offsite)   │  │
│  └───────────────┘                 └───────────────┘  │
│                                                        │
└────────────────────────────────────────────────────────┘
```

### Backup Types

1. **Full Backup**: Complete snapshot of all data
   - All PostgreSQL tables and data
   - Complete Redis RDB snapshot
   - All MinIO objects
   - All configuration files

2. **Incremental Backup**: Only changes since last full backup
   - Uses rsync with hard links
   - Significantly faster and smaller
   - Requires recent full backup as base

### Backup Structure

```
/var/backups/minio/
├── minio_backup_full_20260209_143000/
│   ├── postgresql/
│   │   └── dump.sql.gz
│   ├── redis/
│   │   └── dump.rdb.gz
│   ├── minio-data/
│   │   └── [object files]
│   ├── config/
│   │   ├── minio/
│   │   ├── docker/
│   │   └── configs/
│   └── metadata/
│       └── backup.info
└── minio_backup_incremental_20260209_180000/
    └── [same structure as full]
```

---

## Quick Start

### Prerequisites

**Required Tools**:
- `pg_dump` / `psql` (PostgreSQL client tools)
- `redis-cli` (Redis CLI)
- `rsync` (for efficient data copying)
- `gzip` (for compression)
- `openssl` (for encryption, optional)
- `mc` (MinIO client, optional for S3 backups)

**Installation** (Ubuntu/Debian):
```bash
sudo apt-get update
sudo apt-get install postgresql-client redis-tools rsync gzip openssl
```

### Initial Configuration

1. **Create backup directory**:
```bash
sudo mkdir -p /var/backups/minio
sudo chown $USER:$USER /var/backups/minio
chmod 755 /var/backups/minio
```

2. **Configure backup settings**:
```bash
cd /path/to/MinIO/scripts/backup
cp backup.conf backup.conf.local
nano backup.conf.local
```

3. **Set sensitive credentials via environment variables**:
```bash
# Add to ~/.bashrc or /etc/environment
export POSTGRES_PASSWORD="your-secure-password"
export BACKUP_ENCRYPTION_KEY="your-encryption-key"
export S3_ACCESS_KEY="your-s3-access-key"
export S3_SECRET_KEY="your-s3-secret-key"
```

4. **Make scripts executable**:
```bash
chmod +x backup.sh restore.sh verify.sh
```

### First Backup

**Create a full backup**:
```bash
./backup.sh full
```

**Verify the backup**:
```bash
./verify.sh minio_backup_full_YYYYMMDD_HHMMSS
```

---

## Backup Operations

### Full Backup

Creates a complete snapshot of all data.

```bash
# Basic full backup
./backup.sh full

# Full backup with custom config
./backup.sh full --config=/path/to/custom.conf
```

**When to use**:
- Initial backup
- Weekly scheduled backups
- Before major upgrades
- After significant data changes

**Disk space required**: ~100-200% of total data size (includes compression)

### Incremental Backup

Backs up only changes since the last full backup.

```bash
# Incremental backup
./backup.sh incremental

# Incremental with custom config
./backup.sh incremental --config=/path/to/custom.conf
```

**When to use**:
- Daily scheduled backups
- Frequent backup intervals (every 6 hours)
- Large datasets (>100GB)

**Disk space required**: ~10-30% of full backup size (varies by change rate)

**Important**: Incremental backups require a recent full backup. If no full backup is found, the script automatically performs a full backup instead.

### Backup Output

Successful backup output:
```
[2026-02-09 14:30:00] [INFO] === MinIO Enterprise Backup Started ===
[2026-02-09 14:30:00] [INFO] Backup type: full
[2026-02-09 14:30:01] [INFO] Initializing backup: minio_backup_full_20260209_143000
[2026-02-09 14:30:02] [INFO] Starting PostgreSQL backup...
[2026-02-09 14:30:15] [INFO] PostgreSQL backup completed
[2026-02-09 14:30:15] [INFO] Starting Redis backup...
[2026-02-09 14:30:17] [INFO] Redis backup completed
[2026-02-09 14:30:17] [INFO] Starting MinIO data backup (full)...
[2026-02-09 14:32:45] [INFO] MinIO data backup completed
[2026-02-09 14:32:45] [INFO] Starting configuration backup...
[2026-02-09 14:32:47] [INFO] Configuration backup completed
[2026-02-09 14:32:47] [INFO] Verifying backup integrity...
[2026-02-09 14:32:50] [INFO] Total backup size: 24G
[2026-02-09 14:32:50] [INFO] === MinIO Enterprise Backup Completed Successfully ===
[2026-02-09 14:32:50] [INFO] Backup location: /var/backups/minio/minio_backup_full_20260209_143000
```

### Backup with Encryption

Enable encryption in `backup.conf`:
```bash
BACKUP_ENCRYPTION_ENABLED=true
```

Set encryption key:
```bash
export BACKUP_ENCRYPTION_KEY="your-very-secure-encryption-key-here"
```

Run backup:
```bash
./backup.sh full
```

**Result**: Creates encrypted archive `minio_backup_full_YYYYMMDD_HHMMSS.tar.gz.enc`

### Backup to S3

Configure S3 settings in `backup.conf`:
```bash
S3_BACKUP_ENABLED=true
S3_BUCKET="minio-backups"
S3_ENDPOINT="https://s3.amazonaws.com"
```

Set S3 credentials:
```bash
export S3_ACCESS_KEY="your-access-key"
export S3_SECRET_KEY="your-secret-key"
```

Install MinIO client (mc):
```bash
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/
```

Run backup:
```bash
./backup.sh full
```

**Result**: Backup is created locally AND uploaded to S3.

---

## Restore Operations

### Pre-Restore Checklist

⚠️ **CRITICAL**: Restore operations are destructive and will overwrite existing data.

Before restoring:
1. ✅ Stop MinIO application/services
2. ✅ Notify all users of maintenance window
3. ✅ Verify backup integrity with `verify.sh`
4. ✅ Ensure sufficient disk space
5. ✅ Have rollback plan ready
6. ✅ Take pre-restore snapshot if possible

### Verify-Only Mode

Test restore without making changes:

```bash
./restore.sh minio_backup_full_20260209_143000 --verify-only
```

This checks:
- Backup structure integrity
- File accessibility
- Metadata validity
- No actual restore performed

### Full Restore

Complete system restore from backup:

```bash
# Restore from backup name
./restore.sh minio_backup_full_20260209_143000

# Restore from full path
./restore.sh /var/backups/minio/minio_backup_full_20260209_143000

# Restore with custom config
./restore.sh minio_backup_full_20260209_143000 --config=/path/to/custom.conf
```

**Interactive prompts**:
```
WARNING: This will overwrite existing data!
Backup to restore: /var/backups/minio/minio_backup_full_20260209_143000
Target PostgreSQL: localhost:5432/minio
Target MinIO data: /var/lib/minio

Are you sure you want to continue? (yes/no): yes
```

### Restore from Encrypted Backup

```bash
# Set decryption key
export BACKUP_ENCRYPTION_KEY="your-encryption-key"

# Restore encrypted backup
./restore.sh minio_backup_full_20260209_143000.tar.gz.enc
```

### Partial Restore

To restore only specific components, modify the restore script or manually restore:

**PostgreSQL only**:
```bash
export PGPASSWORD="your-password"
gunzip -c /var/backups/minio/minio_backup_full_20260209_143000/postgresql/dump.sql.gz | \
  psql -h localhost -U minio -d minio
```

**Redis only**:
```bash
# Stop Redis
sudo systemctl stop redis

# Copy dump file
sudo cp /var/backups/minio/minio_backup_full_20260209_143000/redis/dump.rdb.gz /var/lib/redis/
cd /var/lib/redis
sudo gunzip dump.rdb.gz

# Start Redis
sudo systemctl start redis
```

**MinIO data only**:
```bash
rsync -av --delete \
  /var/backups/minio/minio_backup_full_20260209_143000/minio-data/ \
  /var/lib/minio/
```

### Rollback After Failed Restore

The restore script automatically creates a pre-restore backup. If restore fails:

```bash
# Check restore log for pre-restore backup path
grep "Pre-restore backup created" /var/backups/minio/restore.log

# Manual rollback (example)
./restore.sh /var/backups/minio/pre_restore_20260209_150000
```

---

## Verification

### Verify Backup Integrity

```bash
# Basic verification
./verify.sh minio_backup_full_20260209_143000

# Detailed verification with more info
./verify.sh minio_backup_full_20260209_143000 --detailed
```

### Verification Output

```
==========================================
MinIO Enterprise Backup Verification
==========================================

Backup path: /var/backups/minio/minio_backup_full_20260209_143000
Detailed mode: false

==========================================
1. Backup Structure Verification
==========================================
✓ Backup directory exists
✓ Directory exists: postgresql/
✓ Directory exists: redis/
✓ Directory exists: minio-data/
✓ Directory exists: config/
✓ Directory exists: metadata/
✓ Metadata file exists

==========================================
2. Metadata Verification
==========================================
✓ Metadata field: backup_name=minio_backup_full_20260209_143000
✓ Metadata field: backup_type=full
✓ Metadata field: timestamp=20260209_143000
✓ Metadata field: date=2026-02-09 14:30:00 UTC
✓ All required metadata fields present

==========================================
3. PostgreSQL Backup Verification
==========================================
✓ PostgreSQL dump found (compressed): dump.sql.gz
ℹ Compressed dump size: 2.4G
✓ Compressed dump integrity verified
ℹ Uncompressed size: 8.1GB

==========================================
4. Redis Backup Verification
==========================================
✓ Redis dump found (compressed): dump.rdb.gz
ℹ Compressed dump size: 245M
✓ Compressed dump integrity verified

==========================================
5. MinIO Data Backup Verification
==========================================
✓ MinIO data directory exists
ℹ Files backed up: 145,234
ℹ Directories backed up: 3,456
ℹ Total MinIO data size: 24G
✓ MinIO data contains files

==========================================
6. Configuration Backup Verification
==========================================
✓ Configuration directory exists
✓ Configuration found: minio/
ℹ   Files in minio: 12
✓ Configuration found: docker/
ℹ   Files in docker: 8
✓ Configuration found: configs/
ℹ   Files in configs: 45
✓ At least one configuration backup found

==========================================
7. Backup Age Verification
==========================================
ℹ Backup date: 2026-02-09 14:30:00 UTC
ℹ Backup age: 0 days, 2 hours
✓ Backup age is acceptable

==========================================
8. File Permissions Verification
==========================================
✓ Backup directory is readable
✓ Metadata file is readable
✓ PostgreSQL dump is readable

==========================================
Verification Summary
==========================================

  Total checks:   28
  Passed:         26
  Failed:         0
  Warnings:       2
  Success rate:   100%

✓ Backup verification PASSED with warnings
```

### List Available Backups

```bash
ls -lh /var/backups/minio/
```

```
drwxr-xr-x 7 minio minio 4.0K Feb  9 14:30 minio_backup_full_20260209_143000
drwxr-xr-x 7 minio minio 4.0K Feb  9 18:00 minio_backup_incremental_20260209_180000
drwxr-xr-x 7 minio minio 4.0K Feb 10 02:00 minio_backup_incremental_20260210_020000
```

---

## Scheduling

### Cron Scheduling

**Recommended schedule**:
- **Full backup**: Weekly (Sunday 2 AM)
- **Incremental backup**: Daily (2 AM, Monday-Saturday)

**Edit crontab**:
```bash
crontab -e
```

**Add backup jobs**:
```cron
# MinIO Full Backup - Every Sunday at 2 AM
0 2 * * 0 /path/to/MinIO/scripts/backup/backup.sh full --config=/path/to/backup.conf >> /var/log/minio-backup.log 2>&1

# MinIO Incremental Backup - Monday to Saturday at 2 AM
0 2 * * 1-6 /path/to/MinIO/scripts/backup/backup.sh incremental --config=/path/to/backup.conf >> /var/log/minio-backup.log 2>&1

# Backup Verification - Daily at 3 AM
0 3 * * * /path/to/MinIO/scripts/backup/verify.sh $(ls -t /var/backups/minio/ | head -1) >> /var/log/minio-verify.log 2>&1
```

**High-frequency schedule** (for critical systems):
```cron
# Full backup twice daily
0 2,14 * * * /path/to/MinIO/scripts/backup/backup.sh full --config=/path/to/backup.conf

# Incremental backup every 6 hours
0 */6 * * * /path/to/MinIO/scripts/backup/backup.sh incremental --config=/path/to/backup.conf
```

### Systemd Timer (Alternative to Cron)

**Create timer unit** (`/etc/systemd/system/minio-backup.timer`):
```ini
[Unit]
Description=MinIO Backup Timer
Requires=minio-backup.service

[Timer]
OnCalendar=daily
OnCalendar=Sun *-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

**Create service unit** (`/etc/systemd/system/minio-backup.service`):
```ini
[Unit]
Description=MinIO Backup Service
After=network.target postgresql.service redis.service

[Service]
Type=oneshot
User=minio
Environment="POSTGRES_PASSWORD=secure-password"
ExecStart=/path/to/MinIO/scripts/backup/backup.sh full
StandardOutput=journal
StandardError=journal
```

**Enable and start**:
```bash
sudo systemctl daemon-reload
sudo systemctl enable minio-backup.timer
sudo systemctl start minio-backup.timer
```

**Check status**:
```bash
sudo systemctl status minio-backup.timer
sudo systemctl list-timers
```

---

## Best Practices

### Backup Strategy

1. **3-2-1 Rule**:
   - **3** copies of data (production + 2 backups)
   - **2** different storage types (local + cloud)
   - **1** offsite copy (S3 or remote datacenter)

2. **Testing**:
   - Test restores monthly
   - Verify backups daily
   - Document restore procedures
   - Train team on recovery process

3. **Retention Policy**:
   - Daily backups: 7 days
   - Weekly backups: 4 weeks
   - Monthly backups: 12 months
   - Yearly backups: 7 years (compliance)

4. **Monitoring**:
   - Set up backup success/failure alerts
   - Monitor backup size trends
   - Track backup duration
   - Alert on verification failures

### Security Best Practices

1. **Encryption**:
   ```bash
   # Always encrypt production backups
   BACKUP_ENCRYPTION_ENABLED=true

   # Use strong encryption keys (32+ characters)
   export BACKUP_ENCRYPTION_KEY="$(openssl rand -base64 32)"
   ```

2. **Credentials Management**:
   ```bash
   # Never hardcode passwords in config files
   # Use environment variables
   export POSTGRES_PASSWORD="$(vault read -field=password secret/postgres)"

   # Or use secrets management systems
   # - HashiCorp Vault
   # - AWS Secrets Manager
   # - Kubernetes Secrets
   ```

3. **File Permissions**:
   ```bash
   # Protect configuration files
   chmod 600 backup.conf
   chown root:root backup.conf

   # Protect backup directory
   chmod 700 /var/backups/minio
   chown root:root /var/backups/minio
   ```

4. **Access Control**:
   - Limit backup script execution to authorized users
   - Use sudo for privileged operations
   - Audit backup access logs
   - Rotate encryption keys annually

### Performance Optimization

1. **Compression**:
   ```bash
   # Use pigz for parallel gzip (faster)
   sudo apt-get install pigz

   # Modify backup script to use pigz instead of gzip
   # Replace: gzip "${pg_dump_file}"
   # With: pigz "${pg_dump_file}"
   ```

2. **Network**:
   ```bash
   # For S3 uploads, use multipart uploads
   # Configure mc (MinIO client)
   mc config set mybackup s3.amazonaws.com \
     --api S3v4 \
     --path on
   ```

3. **Storage**:
   - Use fast local storage (SSD) for backups
   - Deduplicate backups where possible
   - Compress before encrypting (better compression)

### Disaster Recovery RTO/RPO

**RTO** (Recovery Time Objective): Time to restore service

| Backup Type | Expected RTO |
|-------------|--------------|
| PostgreSQL | 5-15 minutes |
| Redis | 2-5 minutes |
| MinIO Data (100GB) | 10-30 minutes |
| MinIO Data (1TB) | 1-3 hours |
| Full System | 30-60 minutes |

**RPO** (Recovery Point Objective): Maximum acceptable data loss

| Backup Schedule | RPO |
|-----------------|-----|
| Every 6 hours | 6 hours |
| Daily | 24 hours |
| Weekly | 7 days |

**Recommendations**:
- Critical systems: Incremental backups every 6 hours (RPO: 6h)
- Standard systems: Daily backups (RPO: 24h)
- Archival systems: Weekly backups (RPO: 7d)

---

## Disaster Recovery

### Recovery Scenarios

#### Scenario 1: Accidental Data Deletion

**Situation**: User accidentally deleted important objects

**Recovery**:
```bash
# 1. Identify most recent backup
ls -lt /var/backups/minio/ | head -2

# 2. Verify backup
./verify.sh minio_backup_incremental_20260209_180000

# 3. Restore MinIO data only (no database changes)
rsync -av /var/backups/minio/minio_backup_incremental_20260209_180000/minio-data/ /var/lib/minio/

# 4. Restart MinIO
docker-compose restart minio-node1
```

**RTO**: 5-10 minutes
**RPO**: Since last backup

#### Scenario 2: Database Corruption

**Situation**: PostgreSQL database corrupted

**Recovery**:
```bash
# 1. Stop applications
docker-compose stop

# 2. Restore database only
export PGPASSWORD="your-password"
psql -h localhost -U minio -d postgres -c "DROP DATABASE minio;"
psql -h localhost -U minio -d postgres -c "CREATE DATABASE minio;"
gunzip -c /var/backups/minio/minio_backup_full_20260209_143000/postgresql/dump.sql.gz | \
  psql -h localhost -U minio -d minio

# 3. Verify database
psql -h localhost -U minio -d minio -c "SELECT COUNT(*) FROM information_schema.tables;"

# 4. Restart applications
docker-compose up -d
```

**RTO**: 10-20 minutes
**RPO**: Since last backup

#### Scenario 3: Complete System Failure

**Situation**: Server crashed, need full restore on new hardware

**Recovery**:
```bash
# 1. Provision new server
# 2. Install dependencies and MinIO
# 3. Copy backup from offsite storage
mc cp -r s3/minio-backups/minio_backup_full_20260209_143000/ /var/backups/minio/

# 4. Run full restore
./restore.sh minio_backup_full_20260209_143000

# 5. Apply latest incremental backup
./restore.sh minio_backup_incremental_20260209_180000

# 6. Start services
docker-compose up -d

# 7. Verify all services
./verify.sh minio_backup_incremental_20260209_180000
```

**RTO**: 1-2 hours
**RPO**: Since last backup

#### Scenario 4: Ransomware Attack

**Situation**: System infected with ransomware

**Recovery**:
```bash
# 1. Isolate infected system (disconnect network)
# 2. Provision clean new server
# 3. Restore from offsite backup (before infection)

# Find last known good backup (before attack date)
ls -lt /var/backups/minio/ | grep "20260208"

# 4. Restore to new system
./restore.sh minio_backup_full_20260208_143000

# 5. Verify no malware in backup
clamscan -r /var/lib/minio

# 6. Update security and restart
apt-get update && apt-get upgrade -y
docker-compose up -d
```

**RTO**: 2-4 hours
**RPO**: To last clean backup

### Disaster Recovery Drills

**Quarterly DR Test** (recommended):

1. **Week 1**: Plan
   - Schedule maintenance window
   - Document expected outcomes
   - Prepare test environment

2. **Week 2**: Execute
   - Restore to test environment
   - Verify data integrity
   - Test application functionality
   - Measure RTO/RPO

3. **Week 3**: Review
   - Document results
   - Identify improvements
   - Update procedures
   - Train team

4. **Week 4**: Improve
   - Implement changes
   - Update documentation
   - Schedule next drill

---

## Troubleshooting

### Common Issues

#### Issue 1: Backup Fails with "Permission Denied"

**Symptoms**:
```
[ERROR] PostgreSQL backup failed
pg_dump: error: connection to database "minio" failed: FATAL: Ident authentication failed
```

**Solution**:
```bash
# 1. Check PostgreSQL password
echo $POSTGRES_PASSWORD

# 2. Test connection manually
psql -h localhost -U minio -d minio -c "SELECT 1;"

# 3. Update pg_hba.conf to allow password auth
sudo nano /etc/postgresql/*/main/pg_hba.conf
# Change: local all all peer
# To: local all all md5

# 4. Restart PostgreSQL
sudo systemctl restart postgresql
```

#### Issue 2: Restore Fails with "Disk Full"

**Symptoms**:
```
[ERROR] MinIO data restore failed
rsync: write failed on "/var/lib/minio/...": No space left on device (28)
```

**Solution**:
```bash
# 1. Check disk space
df -h

# 2. Clean up old backups
./backup.sh full  # This will trigger automatic cleanup

# 3. Or manually remove old backups
rm -rf /var/backups/minio/minio_backup_full_20260101_*

# 4. Consider expanding storage
# Resize volume or add new volume
```

#### Issue 3: Backup Takes Too Long

**Symptoms**:
- Backup runs for hours
- CPU usage high during backup
- System performance degraded

**Solution**:
```bash
# 1. Use incremental backups instead of full
./backup.sh incremental

# 2. Schedule backups during low-traffic periods
# Edit crontab to run at 2 AM instead of 2 PM

# 3. Use parallel compression
sudo apt-get install pigz
# Update backup script to use pigz instead of gzip

# 4. Exclude unnecessary data
# Modify backup script to skip temp files:
rsync -av --exclude='*.tmp' --exclude='cache/' ...
```

#### Issue 4: Encrypted Backup Cannot Be Decrypted

**Symptoms**:
```
[ERROR] Decryption failed
bad decrypt
```

**Solution**:
```bash
# 1. Verify encryption key
echo $BACKUP_ENCRYPTION_KEY

# 2. Check if key has changed
# Compare with key used during backup

# 3. Try manual decryption
openssl enc -aes-256-cbc -d -pbkdf2 \
  -pass pass:"$BACKUP_ENCRYPTION_KEY" \
  -in backup.tar.gz.enc \
  -out backup.tar.gz

# 4. If key is lost, backup is unrecoverable
# Prevention: Store encryption key in multiple secure locations
```

#### Issue 5: Verification Fails

**Symptoms**:
```
✗ PostgreSQL dump not found
✗ Backup verification FAILED
```

**Solution**:
```bash
# 1. Check if backup completed successfully
tail -100 /var/backups/minio/backup.log

# 2. Manually inspect backup structure
ls -lR /var/backups/minio/minio_backup_full_20260209_143000/

# 3. Re-run backup if incomplete
./backup.sh full

# 4. Check disk space during backup
df -h /var/backups/minio/
```

### Debugging

**Enable verbose logging**:
```bash
# Edit backup.sh
set -x  # Add at top of script

# Run backup with output
./backup.sh full 2>&1 | tee /tmp/backup-debug.log
```

**Check backup log**:
```bash
# View recent backup activity
tail -100 /var/backups/minio/backup.log

# Search for errors
grep ERROR /var/backups/minio/backup.log

# View full log
less /var/backups/minio/backup.log
```

**Test individual components**:
```bash
# Test PostgreSQL connection
PGPASSWORD="password" psql -h localhost -U minio -d minio -c "SELECT version();"

# Test Redis connection
redis-cli -h localhost -p 6379 PING

# Test rsync
rsync -av --dry-run /var/lib/minio/ /tmp/test-backup/
```

---

## Advanced Topics

### Multi-Region Backups

For multi-region disaster recovery:

```bash
# Primary region backup
./backup.sh full

# Replicate to secondary region
aws s3 sync /var/backups/minio/ s3://backup-us-west-2/ --region us-west-2
aws s3 sync /var/backups/minio/ s3://backup-eu-west-1/ --region eu-west-1

# Verify replication
aws s3 ls s3://backup-us-west-2/
aws s3 ls s3://backup-eu-west-1/
```

### Continuous Data Protection (CDP)

For near-zero RPO:

```bash
# Use PostgreSQL WAL archiving
# Edit postgresql.conf
archive_mode = on
archive_command = 'rsync %p /var/backups/minio/wal/%f'

# Use MinIO replication
mc admin replicate add minio-primary minio-secondary

# Combine with regular backups for point-in-time recovery
```

### Backup Validation Automation

**Automated restore testing**:

```bash
#!/bin/bash
# test-restore.sh - Automated restore testing

# 1. Create test environment
docker-compose -f docker-compose.test.yml up -d

# 2. Restore to test environment
export POSTGRES_HOST=test-postgres
export MINIO_DATA_DIR=/var/lib/minio-test
./restore.sh minio_backup_full_20260209_143000

# 3. Run validation tests
./scripts/test/integration-tests.sh

# 4. Teardown test environment
docker-compose -f docker-compose.test.yml down

# 5. Report results
echo "Restore test completed: $(date)" | mail -s "Backup Test Report" admin@example.com
```

**Schedule monthly**:
```cron
0 3 1 * * /path/to/test-restore.sh >> /var/log/restore-test.log 2>&1
```

### Custom Backup Hooks

Add custom logic before/after backup:

**Create hooks** (`/scripts/backup/hooks/`):

```bash
# pre-backup.sh
#!/bin/bash
# Runs before backup starts

# Notify monitoring system
curl -X POST https://monitoring.example.com/backup/start \
  -d '{"status":"started","timestamp":"'$(date -u +%s)'"}'

# Flush application caches
redis-cli FLUSHALL

# Checkpoint PostgreSQL
psql -c "CHECKPOINT;"
```

```bash
# post-backup.sh
#!/bin/bash
# Runs after backup completes

BACKUP_NAME="$1"
BACKUP_STATUS="$2"

# Upload metrics
curl -X POST https://monitoring.example.com/backup/complete \
  -d '{
    "backup_name":"'$BACKUP_NAME'",
    "status":"'$BACKUP_STATUS'",
    "timestamp":"'$(date -u +%s)'"
  }'

# Generate backup report
./generate-backup-report.sh "$BACKUP_NAME"
```

**Integrate hooks in backup.sh**:
```bash
# At start of main()
if [[ -f "${SCRIPT_DIR}/hooks/pre-backup.sh" ]]; then
    source "${SCRIPT_DIR}/hooks/pre-backup.sh"
fi

# At end of main()
if [[ -f "${SCRIPT_DIR}/hooks/post-backup.sh" ]]; then
    source "${SCRIPT_DIR}/hooks/post-backup.sh" "$BACKUP_NAME" "$STATUS"
fi
```

---

## Appendix

### Configuration Reference

See [`backup.conf`](../../scripts/backup/backup.conf) for complete configuration options.

### Script Reference

| Script | Purpose | Location |
|--------|---------|----------|
| `backup.sh` | Main backup script | `/scripts/backup/backup.sh` |
| `restore.sh` | Main restore script | `/scripts/restore/restore.sh` |
| `verify.sh` | Backup verification | `/scripts/backup/verify.sh` |
| `backup.conf` | Configuration file | `/scripts/backup/backup.conf` |

### External Resources

- [PostgreSQL Backup Documentation](https://www.postgresql.org/docs/current/backup.html)
- [Redis Persistence](https://redis.io/topics/persistence)
- [MinIO Backup Best Practices](https://docs.min.io/docs/minio-backup-and-restore-guide.html)
- [AWS S3 CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/s3/)

### Support

For issues or questions:
- **GitHub Issues**: [Repository Issues](https://github.com/abiolaogu/MinIO/issues)
- **Documentation**: [Project Docs](../../docs/)
- **Community**: [GitHub Discussions](https://github.com/abiolaogu/MinIO/discussions)

---

**Last Updated**: 2026-02-09
**Version**: 1.0.0
**Maintainer**: MinIO Enterprise Team
