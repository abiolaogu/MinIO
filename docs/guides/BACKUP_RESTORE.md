# MinIO Enterprise - Backup & Restore Guide

Complete guide for backing up and restoring MinIO Enterprise system including PostgreSQL, Redis, data, and configurations.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Backup](#backup)
  - [Manual Backup](#manual-backup)
  - [Automated Backup](#automated-backup)
  - [Backup Types](#backup-types)
  - [Backup Components](#backup-components)
- [Restore](#restore)
  - [Full Restore](#full-restore)
  - [Partial Restore](#partial-restore)
  - [Disaster Recovery](#disaster-recovery)
- [Configuration](#configuration)
- [Scheduling](#scheduling)
- [Encryption](#encryption)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Overview

The MinIO Enterprise backup and restore system provides comprehensive data protection for:

- **PostgreSQL Database**: Tenant metadata, quota information, audit logs
- **Redis Cache**: Session data, temporary state
- **MinIO Data**: Object storage data files
- **Configuration Files**: System configuration, environment variables, deployment files

### Features

✅ **Full and incremental backups**
✅ **Compression support** (gzip)
✅ **Encryption support** (GPG)
✅ **Automated scheduling** (cron, systemd)
✅ **Retention policies**
✅ **Backup verification**
✅ **Dry-run mode**
✅ **Component-based restore**
✅ **Detailed logging**
✅ **Rollback capabilities**

---

## Quick Start

### Prerequisites

```bash
# Install required tools
sudo apt-get update
sudo apt-get install -y postgresql-client redis-tools gnupg tar gzip

# Verify installations
pg_dump --version
redis-cli --version
gpg --version
```

### Basic Backup

```bash
# Make scripts executable
chmod +x scripts/backup.sh scripts/restore.sh

# Run a basic backup
./scripts/backup.sh --type full --compress

# Verify backup was created
ls -lh /var/backups/minio/
```

### Basic Restore

```bash
# List available backups
ls -1 /var/backups/minio/

# Restore from specific backup
./scripts/restore.sh --backup 20240118_120000

# Verify restore
docker-compose ps
curl http://localhost:9000/health
```

---

## Backup

### Manual Backup

#### Full Backup with Compression

```bash
./scripts/backup.sh \
  --type full \
  --compress \
  --verify
```

**Output:**
```
=========================================
MinIO Enterprise - Backup Script
=========================================

[INFO] Starting backup process...
[INFO] Backup type: full
[SUCCESS] Prerequisites check passed
[SUCCESS] Backup directory created
[SUCCESS] PostgreSQL backup completed: minio_20240118_120000.sql.gz (145M)
[SUCCESS] Redis backup completed: redis_20240118_120000.rdb.gz (23M)
[SUCCESS] MinIO data backup completed: minio_data_20240118_120000.tar.gz (2.3G)
[SUCCESS] Backup verification passed
[SUCCESS] Backup process completed successfully!

Backup location: /var/backups/minio/20240118_120000
```

#### Backup with Encryption

```bash
# Generate GPG key (first time only)
gpg --gen-key
gpg --export your-email@example.com > /etc/minio/backup-keys/public.gpg

# Run encrypted backup
./scripts/backup.sh \
  --type full \
  --compress \
  --encrypt \
  --key /etc/minio/backup-keys/public.gpg
```

#### Backup to Custom Location

```bash
./scripts/backup.sh \
  --type full \
  --destination /mnt/external/backups \
  --compress
```

### Automated Backup

#### Using Cron

Create a cron job for daily backups at 2 AM:

```bash
# Edit crontab
crontab -e

# Add this line for daily backups at 2:00 AM
0 2 * * * /path/to/MinIO/scripts/backup.sh --type full --compress --verify >> /var/log/minio-backup.log 2>&1
```

**Example schedules:**

```bash
# Daily at 2 AM
0 2 * * * /path/to/backup.sh --type full --compress

# Every 6 hours
0 */6 * * * /path/to/backup.sh --type incremental --compress

# Weekly on Sunday at 3 AM
0 3 * * 0 /path/to/backup.sh --type full --compress --verify

# Hourly incremental backups
0 * * * * /path/to/backup.sh --type incremental --compress
```

#### Using Systemd Timer

Create systemd service and timer:

**1. Create service file: `/etc/systemd/system/minio-backup.service`**

```ini
[Unit]
Description=MinIO Enterprise Backup
After=network.target postgresql.service redis.service

[Service]
Type=oneshot
User=root
WorkingDirectory=/path/to/MinIO
EnvironmentFile=/path/to/MinIO/configs/backup-config.env
ExecStart=/path/to/MinIO/scripts/backup.sh --type full --compress --verify
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**2. Create timer file: `/etc/systemd/system/minio-backup.timer`**

```ini
[Unit]
Description=MinIO Enterprise Backup Timer
Requires=minio-backup.service

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
```

**3. Enable and start timer:**

```bash
sudo systemctl daemon-reload
sudo systemctl enable minio-backup.timer
sudo systemctl start minio-backup.timer

# Check timer status
sudo systemctl status minio-backup.timer

# View timer schedule
sudo systemctl list-timers minio-backup.timer
```

### Backup Types

#### Full Backup

Complete backup of all components.

```bash
./scripts/backup.sh --type full --compress
```

**Use cases:**
- Initial backup
- Weekly/monthly complete snapshots
- Before major upgrades
- Disaster recovery preparation

**Size:** Full size of all data
**Duration:** Longest
**Storage:** Highest

#### Incremental Backup

Backup only changes since last backup (future feature).

```bash
./scripts/backup.sh --type incremental --compress
```

**Use cases:**
- Daily/hourly backups
- Continuous protection
- Minimizing backup time

**Size:** Only changes
**Duration:** Fastest
**Storage:** Minimal

### Backup Components

The backup includes these components:

#### 1. PostgreSQL Database

**Contents:**
- Tenant metadata
- User accounts
- Quota information
- Audit logs
- Access policies

**Backup format:** SQL dump (plain text)
**Typical size:** 100-500 MB

#### 2. Redis Cache

**Contents:**
- Session data
- Temporary cache state
- Rate limiting counters

**Backup format:** RDB snapshot
**Typical size:** 10-100 MB

#### 3. MinIO Data

**Contents:**
- Object storage files
- Bucket data
- Metadata

**Backup format:** Tar archive
**Typical size:** Varies (GB to TB)

#### 4. Configuration Files

**Contents:**
- `.env` environment variables
- MinIO configuration files
- Docker Compose files
- Deployment manifests

**Backup format:** Tar archive
**Typical size:** <10 MB

---

## Restore

### Full Restore

Restore all components from a backup:

```bash
# List available backups
ls -1 /var/backups/minio/

# Restore everything
./scripts/restore.sh --backup 20240118_120000

# You will be prompted for confirmation:
# WARNING: This will restore the following components: all
# CAUTION: This may overwrite existing data!
# Are you sure you want to continue? (yes/no): yes
```

**Output:**
```
=========================================
MinIO Enterprise - Restore Script
=========================================

[INFO] Starting restore process...
[SUCCESS] Prerequisites check passed
[SUCCESS] Backup validation passed
[WARNING] Dropping existing database: minio
[SUCCESS] PostgreSQL restore completed
[SUCCESS] Redis restore completed
[SUCCESS] MinIO data restore completed
[SUCCESS] MinIO config restore completed
[SUCCESS] Restore verification passed
[SUCCESS] Restore process completed successfully!
```

### Partial Restore

Restore specific components:

#### Restore Only Database

```bash
./scripts/restore.sh \
  --backup 20240118_120000 \
  --components postgresql
```

#### Restore Only MinIO Data

```bash
./scripts/restore.sh \
  --backup 20240118_120000 \
  --components minio-data
```

#### Restore Multiple Components

```bash
./scripts/restore.sh \
  --backup 20240118_120000 \
  --components postgresql,redis
```

### Disaster Recovery

Complete disaster recovery procedure:

#### Scenario 1: Database Corruption

```bash
# 1. Stop services
docker-compose down

# 2. Restore database only
./scripts/restore.sh --backup LATEST_BACKUP_ID --components postgresql

# 3. Verify database
psql -h localhost -U minio -d minio -c "\dt"

# 4. Start services
docker-compose up -d

# 5. Verify system health
curl http://localhost:9000/health
```

#### Scenario 2: Complete System Failure

```bash
# 1. Stop all services
docker-compose down

# 2. Restore everything
./scripts/restore.sh --backup LATEST_BACKUP_ID --force

# 3. Start services
docker-compose up -d

# 4. Comprehensive health check
docker-compose ps
curl http://localhost:9000/health
curl http://localhost:9090/-/healthy  # Prometheus
redis-cli -h localhost PING
psql -h localhost -U minio -d minio -c "SELECT 1"

# 5. Verify data integrity
# - Check object counts
# - Test upload/download
# - Verify tenant quotas
```

#### Scenario 3: Data Center Failover

```bash
# On new data center:

# 1. Install MinIO Enterprise
git clone <repo-url>
cd MinIO

# 2. Copy backup from remote storage
rsync -avz backup-server:/var/backups/minio/LATEST_BACKUP_ID /var/backups/minio/

# 3. Restore system
./scripts/restore.sh --backup LATEST_BACKUP_ID --force

# 4. Update DNS/load balancer
# Point to new data center

# 5. Start services
docker-compose up -d

# 6. Monitor and verify
tail -f /var/log/minio/*.log
```

### Dry Run

Preview restore without making changes:

```bash
./scripts/restore.sh \
  --backup 20240118_120000 \
  --dry-run
```

**Output shows what would be restored:**
```
[INFO] [DRY RUN] Would restore PostgreSQL from: /var/backups/minio/20240118_120000/postgresql/minio.sql.gz
[INFO] [DRY RUN] Would restore Redis from: /var/backups/minio/20240118_120000/redis/redis.rdb.gz
[INFO] [DRY RUN] Would restore MinIO data from: /var/backups/minio/20240118_120000/minio-data/minio_data.tar.gz
[INFO] Dry run completed - no changes were made
```

---

## Configuration

### Configuration File

Edit `/configs/backup-config.env`:

```bash
# Basic configuration
BACKUP_DESTINATION=/var/backups/minio
BACKUP_TYPE=full
BACKUP_RETENTION_DAYS=30
BACKUP_COMPRESSION_ENABLED=true
BACKUP_ENCRYPTION_ENABLED=false

# Database configuration
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_USER=minio
POSTGRES_DB=minio

REDIS_HOST=localhost
REDIS_PORT=6379

# MinIO configuration
MINIO_DATA_DIR=/data
MINIO_CONFIG_DIR=/etc/minio
```

### Environment Variables

You can override configuration using environment variables:

```bash
# Export variables
export BACKUP_DESTINATION=/mnt/external/backups
export BACKUP_RETENTION_DAYS=60
export BACKUP_COMPRESSION_ENABLED=true

# Run backup with custom configuration
./scripts/backup.sh --type full
```

### Docker Configuration

For Docker deployments, mount backup directory:

```yaml
# docker-compose.yml
services:
  minio:
    volumes:
      - /var/backups/minio:/backups
      - ./scripts:/scripts
```

Run backup from container:

```bash
docker exec minio-node1 /scripts/backup.sh --type full --compress
```

---

## Scheduling

### Backup Schedule Recommendations

#### Production Environment

```
Daily Full Backup:      02:00 (off-peak)
Hourly Incremental:     Every hour
Retention:              30 days
Verification:           Daily
Remote Copy:            After each backup
```

**Cron configuration:**
```bash
# Full backup daily at 2 AM
0 2 * * * /path/to/backup.sh --type full --compress --verify

# Incremental every hour
0 * * * * /path/to/backup.sh --type incremental --compress

# Cleanup old backups daily at 4 AM
0 4 * * * find /var/backups/minio -type d -mtime +30 -exec rm -rf {} \;
```

#### Development Environment

```
Daily Full Backup:      03:00
Retention:              7 days
Verification:           Weekly
```

**Cron configuration:**
```bash
# Full backup daily at 3 AM
0 3 * * * /path/to/backup.sh --type full --compress

# Cleanup weekly
0 4 * * 0 find /var/backups/minio -type d -mtime +7 -exec rm -rf {} \;
```

### Backup Window Calculation

Calculate expected backup duration:

| Component | Size | Duration | Compression | Total Time |
|-----------|------|----------|-------------|------------|
| PostgreSQL | 500 MB | ~2 min | ~1 min | 3 min |
| Redis | 50 MB | ~30 sec | ~15 sec | 45 sec |
| MinIO Data | 1 TB | ~45 min | ~30 min | 75 min |
| **Total** | **~1 TB** | | | **~80 min** |

*Times are estimates and vary based on hardware and load*

---

## Encryption

### Setting Up Encryption

#### 1. Generate GPG Key Pair

```bash
# Generate key (interactive)
gpg --gen-key

# Follow prompts:
# - Name: MinIO Backup
# - Email: backup@yourdomain.com
# - Passphrase: <strong-passphrase>
```

#### 2. Export Public Key

```bash
# Create key directory
sudo mkdir -p /etc/minio/backup-keys

# Export public key for encryption
gpg --export backup@yourdomain.com > /etc/minio/backup-keys/public.gpg

# Export private key for decryption (KEEP SECURE!)
gpg --export-secret-key backup@yourdomain.com > /etc/minio/backup-keys/private.gpg

# Set permissions
sudo chmod 600 /etc/minio/backup-keys/private.gpg
sudo chmod 644 /etc/minio/backup-keys/public.gpg
```

#### 3. Configure Backup with Encryption

```bash
# Edit config file
vi configs/backup-config.env

# Set encryption options
BACKUP_ENCRYPTION_ENABLED=true
BACKUP_GPG_KEY_PATH=/etc/minio/backup-keys/public.gpg
```

#### 4. Run Encrypted Backup

```bash
./scripts/backup.sh \
  --type full \
  --compress \
  --encrypt \
  --key /etc/minio/backup-keys/public.gpg
```

### Restoring Encrypted Backups

```bash
./scripts/restore.sh \
  --backup 20240118_120000 \
  --decrypt \
  --key /etc/minio/backup-keys/private.gpg
```

**You will be prompted for GPG passphrase:**
```
gpg: encrypted with 4096-bit RSA key, ID ABCD1234
Enter passphrase: ************
```

### Encryption Best Practices

1. **Store private key securely**
   - Use hardware security module (HSM)
   - Or secure key management system (KMS)
   - Never commit to version control

2. **Use strong passphrases**
   - Minimum 20 characters
   - Mix of letters, numbers, symbols
   - Use password manager

3. **Backup encryption keys**
   - Store in multiple secure locations
   - Use key escrow for disaster recovery
   - Document key recovery procedures

4. **Rotate keys periodically**
   - Generate new keys annually
   - Re-encrypt old backups with new keys
   - Revoke old keys after rotation

---

## Verification

### Automatic Verification

Enable verification in backups:

```bash
./scripts/backup.sh --type full --compress --verify
```

**Verification checks:**
- ✅ Backup directory exists
- ✅ PostgreSQL backup file present
- ✅ Redis backup file present
- ✅ MinIO data backup present
- ✅ Metadata file valid
- ✅ File integrity (checksums)

### Manual Verification

#### Verify Backup Exists

```bash
ls -lh /var/backups/minio/20240118_120000/
```

#### Verify PostgreSQL Backup

```bash
# Extract SQL file
gunzip -c /var/backups/minio/20240118_120000/postgresql/minio.sql.gz | head -20

# Check for expected tables
gunzip -c /var/backups/minio/20240118_120000/postgresql/minio.sql.gz | grep "CREATE TABLE"
```

#### Verify Redis Backup

```bash
# Check RDB file
file /var/backups/minio/20240118_120000/redis/redis.rdb.gz

# Decompress and verify
gunzip -c /var/backups/minio/20240118_120000/redis/redis.rdb.gz | head -c 20
# Should show "REDIS" magic number
```

#### Verify MinIO Data

```bash
# List contents of data archive
tar -tzf /var/backups/minio/20240118_120000/minio-data/minio_data.tar.gz | head -20
```

#### Test Restore (Dry Run)

```bash
# Preview restore without making changes
./scripts/restore.sh --backup 20240118_120000 --dry-run
```

### Backup Testing Schedule

**Recommended testing schedule:**

| Frequency | Test Type | Action |
|-----------|-----------|--------|
| Daily | Verification | Automated checks after backup |
| Weekly | Dry Run | Test restore procedure |
| Monthly | Partial Restore | Restore to test environment |
| Quarterly | Full DR Test | Complete disaster recovery drill |

---

## Troubleshooting

### Common Issues

#### Issue 1: Backup Fails - "Permission Denied"

**Symptoms:**
```
[ERROR] Failed to create backup directory: Permission denied
```

**Solution:**
```bash
# Check permissions
ls -ld /var/backups/minio

# Fix permissions
sudo mkdir -p /var/backups/minio
sudo chown $(whoami):$(whoami) /var/backups/minio
sudo chmod 755 /var/backups/minio
```

#### Issue 2: PostgreSQL Connection Fails

**Symptoms:**
```
[ERROR] PostgreSQL backup failed: could not connect to server
```

**Solution:**
```bash
# Test connection
psql -h localhost -U minio -d minio -c "SELECT 1"

# Check PostgreSQL is running
docker-compose ps postgresql

# Verify credentials
grep POSTGRES_ configs/backup-config.env

# Set password
export PGPASSWORD="your-password"
./scripts/backup.sh --type full
```

#### Issue 3: Disk Space Issues

**Symptoms:**
```
[ERROR] No space left on device
```

**Solution:**
```bash
# Check disk space
df -h /var/backups

# Clean old backups manually
find /var/backups/minio -type d -mtime +30 -exec rm -rf {} \;

# Reduce retention period
# Edit configs/backup-config.env
BACKUP_RETENTION_DAYS=14
```

#### Issue 4: Restore Fails - "Backup Not Found"

**Symptoms:**
```
[ERROR] Backup directory not found: /var/backups/minio/20240118_120000
```

**Solution:**
```bash
# List available backups
ls -1 /var/backups/minio/

# Check backup source path
echo $BACKUP_SOURCE

# Use correct backup ID
./scripts/restore.sh --backup $(ls -1 /var/backups/minio/ | tail -1)
```

#### Issue 5: GPG Decryption Fails

**Symptoms:**
```
[ERROR] Failed to decrypt: gpg: decryption failed: No secret key
```

**Solution:**
```bash
# List GPG keys
gpg --list-secret-keys

# Import private key if missing
gpg --import /etc/minio/backup-keys/private.gpg

# Verify key
gpg --list-keys backup@yourdomain.com
```

### Debugging

#### Enable Debug Logging

```bash
# Set log level
export BACKUP_LOG_LEVEL=DEBUG

# Run backup with verbose output
./scripts/backup.sh --type full 2>&1 | tee -a backup-debug.log
```

#### Check Backup Logs

```bash
# View latest backup log
cat /var/backups/minio/20240118_120000/backup.log

# Search for errors
grep ERROR /var/backups/minio/*/backup.log

# View last 50 lines
tail -50 /var/backups/minio/20240118_120000/backup.log
```

#### Test Individual Components

```bash
# Test PostgreSQL backup only
pg_dump -h localhost -U minio -d minio -F p -f /tmp/test-backup.sql

# Test Redis backup only
redis-cli -h localhost BGSAVE
redis-cli -h localhost LASTSAVE

# Test tar creation
tar -czf /tmp/test-data.tar.gz /data
```

---

## Best Practices

### 1. Regular Testing

- **Weekly**: Dry-run restore tests
- **Monthly**: Restore to staging environment
- **Quarterly**: Full disaster recovery drills

### 2. Multiple Backup Locations

```bash
# Primary backup
BACKUP_DESTINATION=/var/backups/minio

# Secondary backup to NAS
rsync -avz /var/backups/minio/ nas.local:/backups/minio/

# Tertiary backup to cloud
aws s3 sync /var/backups/minio/ s3://my-backup-bucket/minio/
```

### 3. Monitoring

Monitor backup health:

```bash
# Check last backup age
find /var/backups/minio -maxdepth 1 -type d -name "[0-9]*" -mtime -1

# Alert if no recent backup
if [ $(find /var/backups/minio -maxdepth 1 -type d -mtime -1 | wc -l) -eq 0 ]; then
    echo "ALERT: No backup in last 24 hours!" | mail -s "Backup Alert" admin@example.com
fi
```

### 4. Documentation

Maintain runbooks:

- Backup procedures
- Restore procedures
- Disaster recovery plan
- Contact information
- Escalation procedures

### 5. Retention Strategy

**3-2-1 Rule:**
- **3** copies of data
- **2** different media types
- **1** offsite copy

```bash
# Local backup (1)
/var/backups/minio/

# NAS backup (2)
nas.local:/backups/minio/

# Cloud backup (3, offsite)
s3://my-backup-bucket/minio/
```

### 6. Encryption

Always encrypt backups containing sensitive data:

```bash
# Generate strong GPG key
gpg --full-generate-key --expert

# Use encryption for all backups
BACKUP_ENCRYPTION_ENABLED=true
```

### 7. Automation

Fully automate backup process:

```bash
# Systemd timer for reliability
sudo systemctl enable minio-backup.timer

# Monitor timer execution
sudo systemctl status minio-backup.timer

# Check recent runs
journalctl -u minio-backup.service --since "1 week ago"
```

### 8. Backup Validation

Always verify backups:

```bash
# Enable verification
VERIFY_BACKUP=true

# Or manually verify
./scripts/backup.sh --type full --verify
```

### 9. Performance Optimization

```bash
# Use compression for network transfer
BACKUP_COMPRESSION_ENABLED=true

# Parallel compression
BACKUP_COMPRESSION_THREADS=4

# Schedule during off-peak hours
0 2 * * * /path/to/backup.sh  # 2 AM
```

### 10. Security

```bash
# Restrict backup file permissions
chmod 600 /var/backups/minio/*

# Use dedicated backup user
sudo useradd -r -s /bin/bash minio-backup
sudo chown -R minio-backup:minio-backup /var/backups/minio

# Run backups as backup user
sudo -u minio-backup /path/to/backup.sh
```

---

## RTO and RPO

### Recovery Time Objective (RTO)

Expected time to restore services:

| Component | Restore Time | Notes |
|-----------|--------------|-------|
| PostgreSQL | 5-10 min | For 500 MB database |
| Redis | 1-2 min | For 50 MB snapshot |
| MinIO Data | 30-120 min | Depends on data size |
| Configuration | 1-2 min | Small files |
| **Total RTO** | **30-60 min** | For typical deployment |

### Recovery Point Objective (RPO)

Maximum acceptable data loss:

| Backup Frequency | RPO | Use Case |
|------------------|-----|----------|
| Hourly | 1 hour | Critical production |
| Every 6 hours | 6 hours | Standard production |
| Daily | 24 hours | Development |
| Weekly | 7 days | Archive |

**Recommendation for production**:
- **RPO: 1 hour** (hourly incremental backups)
- **RTO: 30 minutes** (tested and documented procedures)

---

## Compliance

### Regulatory Requirements

#### SOC 2 Type II

- ✅ Regular automated backups
- ✅ Encrypted backups
- ✅ Offsite storage
- ✅ Tested restore procedures
- ✅ Audit logs of backup operations

#### GDPR

- ✅ Data retention policies
- ✅ Secure backup storage
- ✅ Right to deletion (can remove from backups)
- ✅ Data transfer controls (encrypted)

#### HIPAA

- ✅ Encrypted backups (at rest and in transit)
- ✅ Access controls to backups
- ✅ Audit trail of access
- ✅ Disaster recovery plan

---

## Support

For backup and restore issues:

1. Check this documentation
2. Review troubleshooting section
3. Check logs: `/var/backups/minio/*/backup.log`
4. GitHub Issues: [Repository Issues](https://github.com/abiolaogu/MinIO/issues)
5. Emergency: Follow disaster recovery procedures

---

**Last Updated**: 2026-02-08
**Version**: 1.0
**Status**: Production Ready
