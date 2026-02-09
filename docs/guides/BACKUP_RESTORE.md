# MinIO Enterprise - Backup & Restore Guide

**Version**: 1.0.0
**Last Updated**: 2026-02-09
**Status**: Production Ready

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Architecture](#architecture)
4. [Backup Operations](#backup-operations)
5. [Restore Operations](#restore-operations)
6. [Configuration](#configuration)
7. [Scheduling & Automation](#scheduling--automation)
8. [Disaster Recovery](#disaster-recovery)
9. [Security](#security)
10. [Troubleshooting](#troubleshooting)
11. [Best Practices](#best-practices)

---

## Overview

The MinIO Enterprise Backup & Restore system provides comprehensive disaster recovery capabilities with automated backup and restore procedures for all critical components.

### Features

- **✅ Comprehensive Coverage**: PostgreSQL, Redis, MinIO objects, and configuration files
- **✅ Encryption**: AES-256-CBC encryption for sensitive data
- **✅ Compression**: Gzip compression to minimize storage
- **✅ Retention Management**: Automatic cleanup of old backups
- **✅ Remote Storage**: S3-compatible storage support
- **✅ Verification**: Backup integrity checks and restore verification
- **✅ Rollback**: Automatic snapshot and rollback capability
- **✅ Notifications**: Slack and email alerts
- **✅ Flexible Scheduling**: Cron-compatible for automated backups

### Components Backed Up

| Component | Description | Critical |
|-----------|-------------|----------|
| **PostgreSQL** | All databases (pg_dumpall) | ✅ High |
| **Redis** | RDB snapshot | ✅ High |
| **MinIO Objects** | All stored objects | ✅ High |
| **Configuration Files** | Configs, deployments, .env | ⚠️ Medium |

### Recovery Time Objective (RTO)

- **Target RTO**: < 30 minutes
- **Verified RTO**: ~15-20 minutes (depending on data volume)

### Recovery Point Objective (RPO)

- **Daily Backups**: RPO = 24 hours
- **Hourly Backups**: RPO = 1 hour
- **Continuous Replication**: RPO < 5 minutes (for critical data)

---

## Quick Start

### Prerequisites

**Required Tools**:
- `bash` (v4.0+)
- `docker` or `kubectl` (depending on deployment)
- `tar`, `gzip`
- `openssl` (for encryption)

**Optional Tools**:
- `aws` CLI (for S3 uploads)
- `jq` (for JSON metadata parsing)
- `mail` (for email notifications)

### Installation

1. **Clone Repository** (if not already done):
   ```bash
   git clone <repo-url>
   cd MinIO
   ```

2. **Make Scripts Executable**:
   ```bash
   chmod +x scripts/backup/backup.sh
   chmod +x scripts/restore/restore.sh
   ```

3. **Create Backup Directory**:
   ```bash
   sudo mkdir -p /var/backups/minio/logs
   sudo chown -R $USER:$USER /var/backups/minio
   ```

4. **Generate Encryption Key** (automatic on first backup):
   ```bash
   # Or manually:
   openssl rand -base64 32 > scripts/backup/.backup.key
   chmod 600 scripts/backup/.backup.key
   ```

### First Backup

```bash
# Run a full backup
./scripts/backup/backup.sh

# Check backup logs
tail -f /var/backups/minio/logs/backup_*.log
```

### First Restore (Dry Run)

```bash
# List available backups
./scripts/restore/restore.sh --list

# Dry run restore (no actual changes)
./scripts/restore/restore.sh --dry-run minio_backup_20260209_120000
```

---

## Architecture

### Backup Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                     Backup Pipeline                          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
    ┌───────────────────────────────────────────────┐
    │  1. Prerequisites Check                       │
    │     - Verify tools (docker, tar, gzip, etc.)  │
    │     - Create backup directory                 │
    │     - Generate encryption key (if needed)     │
    └───────────────┬───────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────────────────┐
    │  2. Component Backups (Parallel)              │
    │     ┌─────────────────────────────────────┐   │
    │     │  PostgreSQL: pg_dumpall             │   │
    │     │  Redis: BGSAVE + dump.rdb           │   │
    │     │  MinIO: tar.gz of data volumes      │   │
    │     │  Configs: tar.gz of config dirs     │   │
    │     └─────────────────────────────────────┘   │
    └───────────────┬───────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────────────────┐
    │  3. Compression                               │
    │     - Create tar archive                      │
    │     - Gzip compression                        │
    │     - ~60-80% size reduction                  │
    └───────────────┬───────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────────────────┐
    │  4. Encryption                                │
    │     - AES-256-CBC encryption                  │
    │     - Using secure key file                   │
    │     - Remove unencrypted archive              │
    └───────────────┬───────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────────────────┐
    │  5. Verification                              │
    │     - Check file exists and has content       │
    │     - Generate SHA-256 checksum               │
    │     - Create metadata JSON file               │
    └───────────────┬───────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────────────────┐
    │  6. Upload (Optional)                         │
    │     - Upload to S3-compatible storage         │
    │     - Include metadata file                   │
    └───────────────┬───────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────────────────┐
    │  7. Cleanup                                   │
    │     - Remove old backups (retention policy)   │
    │     - Remove temporary files                  │
    │     - Send notifications                      │
    └───────────────────────────────────────────────┘
```

### Restore Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                     Restore Pipeline                         │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
    ┌───────────────────────────────────────────────┐
    │  1. Backup Selection                          │
    │     - Interactive selection OR                │
    │     - Specified backup name                   │
    └───────────────┬───────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────────────────┐
    │  2. Pre-Restore Snapshot                      │
    │     - Create snapshot of current state        │
    │     - Enables rollback if restore fails       │
    └───────────────┬───────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────────────────┐
    │  3. Backup Extraction                         │
    │     - Decrypt backup (if encrypted)           │
    │     - Decompress archive                      │
    │     - Extract to temporary directory          │
    └───────────────┬───────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────────────────┐
    │  4. Component Restore (Sequential)            │
    │     ┌─────────────────────────────────────┐   │
    │     │  PostgreSQL: psql < backup.sql      │   │
    │     │  Redis: Copy dump.rdb + restart     │   │
    │     │  MinIO: Extract to data volumes     │   │
    │     │  Configs: Extract to project dirs   │   │
    │     └─────────────────────────────────────┘   │
    │                                               │
    │  ⚠️  Services stopped during restore          │
    │  ⚠️  User confirmation required               │
    └───────────────┬───────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────────────────┐
    │  5. Verification                              │
    │     - Check PostgreSQL connectivity           │
    │     - Check Redis PING response               │
    │     - Check MinIO nodes status                │
    │     - Verify data integrity                   │
    └───────────────┬───────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────────────────┐
    │  6. Cleanup & Notification                    │
    │     - Remove temporary files                  │
    │     - Send success/failure notification       │
    │     - Offer rollback if failed                │
    └───────────────────────────────────────────────┘
```

### File Structure

```
/var/backups/minio/
├── minio_backup_20260209_120000.tar.gz.enc    # Encrypted backup
├── minio_backup_20260209_120000.metadata.json # Backup metadata
├── minio_backup_20260208_120000.tar.gz.enc
├── minio_backup_20260208_120000.metadata.json
├── logs/
│   ├── backup_20260209_120000.log
│   └── restore_20260209_130000.log
└── snapshots/
    └── minio_snapshot_20260209_130000.tar.gz.enc
```

---

## Backup Operations

### Manual Backup

#### Full Backup

```bash
# Standard full backup
./scripts/backup/backup.sh

# Full backup with custom directory
BACKUP_DIR=/mnt/backups ./scripts/backup/backup.sh

# Full backup without encryption
ENABLE_ENCRYPTION=false ./scripts/backup/backup.sh

# Full backup with S3 upload
S3_BACKUP_ENABLED=true \
S3_BUCKET=my-backups \
./scripts/backup/backup.sh
```

#### Component-Specific Backup

```bash
# Backup only PostgreSQL
BACKUP_POSTGRES=true \
BACKUP_REDIS=false \
BACKUP_MINIO=false \
BACKUP_CONFIGS=false \
./scripts/backup/backup.sh

# Backup only MinIO objects
BACKUP_POSTGRES=false \
BACKUP_REDIS=false \
BACKUP_MINIO=true \
BACKUP_CONFIGS=false \
./scripts/backup/backup.sh
```

### Backup Verification

```bash
# Check backup metadata
BACKUP_NAME="minio_backup_20260209_120000"
jq '.' /var/backups/minio/${BACKUP_NAME}.metadata.json

# Verify checksum
BACKUP_FILE="/var/backups/minio/${BACKUP_NAME}.tar.gz.enc"
EXPECTED_CHECKSUM=$(jq -r '.checksum' /var/backups/minio/${BACKUP_NAME}.metadata.json)
ACTUAL_CHECKSUM=$(sha256sum "$BACKUP_FILE" | cut -d' ' -f1)

if [[ "$EXPECTED_CHECKSUM" == "$ACTUAL_CHECKSUM" ]]; then
    echo "✅ Checksum verified"
else
    echo "❌ Checksum mismatch!"
fi
```

### Monitoring Backup Status

```bash
# View latest backup log
tail -f /var/backups/minio/logs/backup_$(date +%Y%m%d)*.log

# Check backup success
if grep -q "Backup Status: SUCCESS" /var/backups/minio/logs/backup_*.log; then
    echo "✅ Last backup succeeded"
else
    echo "❌ Last backup failed"
fi

# List all backups with sizes
ls -lh /var/backups/minio/minio_backup_*.tar.gz.enc
```

---

## Restore Operations

### Interactive Restore

```bash
# Interactive restore (select from list)
./scripts/restore/restore.sh

# This will:
# 1. Display list of available backups
# 2. Prompt for selection
# 3. Create pre-restore snapshot
# 4. Confirm before overwriting data
# 5. Restore selected backup
# 6. Verify restoration
```

### Direct Restore

```bash
# Restore specific backup
./scripts/restore/restore.sh minio_backup_20260209_120000

# Force restore without prompts
./scripts/restore/restore.sh --force minio_backup_20260209_120000

# Dry run (preview only)
./scripts/restore/restore.sh --dry-run minio_backup_20260209_120000
```

### Component-Specific Restore

```bash
# Restore only PostgreSQL
./scripts/restore/restore.sh --postgres-only minio_backup_20260209_120000

# Restore only Redis
./scripts/restore/restore.sh --redis-only minio_backup_20260209_120000

# Restore only MinIO objects
./scripts/restore/restore.sh --minio-only minio_backup_20260209_120000

# Restore only configurations
./scripts/restore/restore.sh --configs-only minio_backup_20260209_120000
```

### Restore with Options

```bash
# Restore without creating snapshot (not recommended)
./scripts/restore/restore.sh --no-snapshot minio_backup_20260209_120000

# Restore with custom restore directory
RESTORE_DIR=/tmp/my_restore ./scripts/restore/restore.sh minio_backup_20260209_120000
```

### Rollback After Failed Restore

```bash
# Automatic rollback prompt on failure
# The restore script will offer rollback if restore fails and snapshot exists

# Manual rollback
./scripts/restore/restore.sh /var/backups/minio/snapshots/minio_snapshot_20260209_130000.tar.gz
```

---

## Configuration

### Backup Configuration

Edit `scripts/backup/backup.conf`:

```bash
# Essential settings
BACKUP_TYPE="full"                  # full or incremental
BACKUP_DIR="/var/backups/minio"
BACKUP_RETENTION_DAYS=30

# Compression & Encryption
ENABLE_COMPRESSION=true
ENABLE_ENCRYPTION=true
ENCRYPTION_KEY_FILE="/path/to/.backup.key"

# Component selection
BACKUP_POSTGRES=true
BACKUP_REDIS=true
BACKUP_MINIO=true
BACKUP_CONFIGS=true

# S3 remote backup
S3_BACKUP_ENABLED=false
S3_BUCKET="my-minio-backups"
S3_ENDPOINT="https://s3.amazonaws.com"

# Notifications
SLACK_WEBHOOK="https://hooks.slack.com/services/..."
EMAIL_RECIPIENT="admin@example.com"
```

### Restore Configuration

Edit `scripts/restore/restore.conf`:

```bash
# Essential settings
BACKUP_DIR="/var/backups/minio"
RESTORE_DIR="/tmp/minio_restore"
CREATE_SNAPSHOT=true
FORCE_RESTORE=false

# Encryption
ENCRYPTION_KEY_FILE="/path/to/.backup.key"

# Component selection
RESTORE_POSTGRES=true
RESTORE_REDIS=true
RESTORE_MINIO=true
RESTORE_CONFIGS=true

# Notifications
SLACK_WEBHOOK="https://hooks.slack.com/services/..."
EMAIL_RECIPIENT="admin@example.com"
```

### Environment Variables

Override configuration via environment variables:

```bash
# Backup
export BACKUP_DIR="/custom/backup/path"
export ENABLE_ENCRYPTION=false
export S3_BACKUP_ENABLED=true

# Restore
export DRY_RUN=true
export FORCE_RESTORE=true
export CREATE_SNAPSHOT=false
```

---

## Scheduling & Automation

### Cron Setup

#### Daily Full Backup

```bash
# Add to crontab
crontab -e

# Daily full backup at 2 AM
0 2 * * * /path/to/MinIO/scripts/backup/backup.sh >> /var/log/minio-backup.log 2>&1
```

#### Hourly Incremental Backup

```bash
# Hourly incremental backups
0 * * * * BACKUP_TYPE=incremental /path/to/MinIO/scripts/backup/backup.sh >> /var/log/minio-backup.log 2>&1
```

#### Weekly S3 Backup

```bash
# Weekly full backup with S3 upload (Sunday 3 AM)
0 3 * * 0 S3_BACKUP_ENABLED=true S3_BUCKET=my-backups /path/to/MinIO/scripts/backup/backup.sh >> /var/log/minio-backup.log 2>&1
```

#### Complete Backup Schedule

```bash
# /etc/cron.d/minio-backup
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Daily full backup at 2 AM
0 2 * * * root /opt/MinIO/scripts/backup/backup.sh >> /var/log/minio-backup.log 2>&1

# Hourly incremental backup (business hours)
0 9-17 * * 1-5 root BACKUP_TYPE=incremental /opt/MinIO/scripts/backup/backup.sh >> /var/log/minio-backup.log 2>&1

# Weekly S3 backup (Sunday 3 AM)
0 3 * * 0 root S3_BACKUP_ENABLED=true S3_BUCKET=minio-backups /opt/MinIO/scripts/backup/backup.sh >> /var/log/minio-backup-s3.log 2>&1

# Monthly cleanup (first day of month)
0 4 1 * * root find /var/backups/minio -name "minio_backup_*" -mtime +90 -delete
```

### Systemd Timer (Alternative to Cron)

#### Create Backup Service

`/etc/systemd/system/minio-backup.service`:

```ini
[Unit]
Description=MinIO Enterprise Backup
After=docker.service

[Service]
Type=oneshot
User=root
ExecStart=/opt/MinIO/scripts/backup/backup.sh
StandardOutput=append:/var/log/minio-backup.log
StandardError=append:/var/log/minio-backup.log

[Install]
WantedBy=multi-user.target
```

#### Create Backup Timer

`/etc/systemd/system/minio-backup.timer`:

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

#### Enable Timer

```bash
sudo systemctl daemon-reload
sudo systemctl enable minio-backup.timer
sudo systemctl start minio-backup.timer

# Check timer status
sudo systemctl status minio-backup.timer
sudo systemctl list-timers minio-backup.timer
```

---

## Disaster Recovery

### Complete System Recovery

#### Scenario: Total System Loss

**Prerequisites**:
- Clean system with Docker/Kubernetes installed
- MinIO repository cloned
- Backup files and encryption key available

**Recovery Steps**:

1. **Prepare Environment**:
   ```bash
   # Clone repository
   git clone <repo-url> /opt/MinIO
   cd /opt/MinIO

   # Copy encryption key
   cp /secure/location/.backup.key scripts/backup/.backup.key
   chmod 600 scripts/backup/.backup.key
   ```

2. **Deploy Infrastructure**:
   ```bash
   # Start services (without data)
   docker compose -f deployments/docker/docker-compose.production.yml up -d

   # Wait for services to initialize
   sleep 30
   ```

3. **Restore from Backup**:
   ```bash
   # Copy backup files to backup directory
   mkdir -p /var/backups/minio
   cp /external/storage/minio_backup_*.tar.gz.enc /var/backups/minio/

   # Run restore
   ./scripts/restore/restore.sh --force minio_backup_20260209_120000
   ```

4. **Verify Recovery**:
   ```bash
   # Check all services
   docker compose -f deployments/docker/docker-compose.production.yml ps

   # Test MinIO API
   curl -f http://localhost:9000/health || echo "MinIO not ready"

   # Check PostgreSQL
   docker compose exec postgres psql -U postgres -c "SELECT version();"

   # Check Redis
   docker compose exec redis redis-cli PING
   ```

5. **Resume Operations**:
   ```bash
   # Monitor logs
   docker compose logs -f minio1

   # Run health checks
   make health-check
   ```

**Expected Recovery Time**: 15-30 minutes (depending on backup size)

### Partial Recovery Scenarios

#### Scenario 1: PostgreSQL Database Corruption

```bash
# Restore only PostgreSQL
./scripts/restore/restore.sh --postgres-only --force minio_backup_20260209_120000

# Verify
docker compose exec postgres psql -U postgres -c "\l"
```

#### Scenario 2: Lost MinIO Objects

```bash
# Restore only MinIO objects
./scripts/restore/restore.sh --minio-only --force minio_backup_20260209_120000

# Verify
curl -X GET http://localhost:9000/api/list
```

#### Scenario 3: Configuration Loss

```bash
# Restore only configurations
./scripts/restore/restore.sh --configs-only --force minio_backup_20260209_120000

# Verify
ls -la configs/ deployments/
```

### Point-in-Time Recovery (PITR)

For more granular recovery, you can combine backups with transaction logs (future enhancement):

```bash
# Restore base backup
./scripts/restore/restore.sh minio_backup_20260209_020000

# Apply transaction logs up to specific time (planned feature)
# ./scripts/restore/replay_logs.sh --until "2026-02-09 14:30:00"
```

---

## Security

### Encryption

#### Key Management

**Generate New Key**:
```bash
openssl rand -base64 32 > scripts/backup/.backup.key
chmod 600 scripts/backup/.backup.key
```

**Secure Key Storage**:
- Store key separately from backups
- Use hardware security module (HSM) for production
- Consider key rotation policy

**Key Rotation**:
```bash
# Generate new key
openssl rand -base64 32 > scripts/backup/.backup.key.new

# Re-encrypt existing backups (manual process)
for backup in /var/backups/minio/*.enc; do
    # Decrypt with old key
    openssl enc -aes-256-cbc -d \
        -in "$backup" \
        -out "${backup%.enc}" \
        -pass file:scripts/backup/.backup.key.old

    # Encrypt with new key
    openssl enc -aes-256-cbc \
        -in "${backup%.enc}" \
        -out "${backup}.new" \
        -pass file:scripts/backup/.backup.key.new

    # Replace old backup
    mv "${backup}.new" "$backup"
    rm "${backup%.enc}"
done

# Replace key
mv scripts/backup/.backup.key.new scripts/backup/.backup.key
```

### Access Control

#### File Permissions

```bash
# Secure backup directory
sudo chown -R backup-user:backup-group /var/backups/minio
sudo chmod 700 /var/backups/minio
sudo chmod 600 /var/backups/minio/*.enc

# Secure scripts
chmod 700 scripts/backup/backup.sh scripts/restore/restore.sh
chmod 600 scripts/backup/.backup.key
```

#### S3 Bucket Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "MinIOBackupAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT:user/minio-backup"
      },
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-minio-backups/*",
        "arn:aws:s3:::my-minio-backups"
      ]
    }
  ]
}
```

### Audit Trail

All backup and restore operations are logged:

```bash
# View backup audit trail
grep "Backup Status:" /var/backups/minio/logs/backup_*.log

# View restore audit trail
grep "Restore Status:" /var/backups/minio/logs/restore_*.log

# Export to centralized logging
tail -f /var/backups/minio/logs/*.log | logger -t minio-backup
```

---

## Troubleshooting

### Common Issues

#### Issue 1: Backup Script Fails with Permission Error

**Symptoms**:
```
[ERROR] Failed to create backup directory
mkdir: cannot create directory '/var/backups/minio': Permission denied
```

**Solution**:
```bash
# Create directory with proper permissions
sudo mkdir -p /var/backups/minio/logs
sudo chown -R $USER:$USER /var/backups/minio

# Or run with sudo
sudo ./scripts/backup/backup.sh
```

#### Issue 2: PostgreSQL Backup Hangs

**Symptoms**:
- Backup process appears to hang on PostgreSQL step
- No progress for > 5 minutes

**Solution**:
```bash
# Check PostgreSQL container status
docker compose ps postgres

# Check PostgreSQL logs
docker compose logs postgres

# Try manual backup to identify issue
docker compose exec postgres pg_dumpall -U postgres

# If database is very large, increase timeout
BACKUP_TIMEOUT=3600 ./scripts/backup/backup.sh
```

#### Issue 3: Encryption Key Not Found

**Symptoms**:
```
[ERROR] Encryption key file not found: scripts/backup/.backup.key
```

**Solution**:
```bash
# Generate encryption key
openssl rand -base64 32 > scripts/backup/.backup.key
chmod 600 scripts/backup/.backup.key

# Or specify existing key location
ENCRYPTION_KEY_FILE=/path/to/key ./scripts/backup/backup.sh
```

#### Issue 4: Restore Fails - Services Won't Start

**Symptoms**:
- Restore completes but services don't start
- Verification checks fail

**Solution**:
```bash
# Check Docker logs
docker compose logs

# Check specific service
docker compose logs minio1

# Try restarting services
docker compose restart

# If still failing, check restored data integrity
docker compose exec postgres psql -U postgres -c "SELECT 1"

# Rollback if necessary
./scripts/restore/restore.sh /var/backups/minio/snapshots/minio_snapshot_*.tar.gz.enc
```

#### Issue 5: S3 Upload Fails

**Symptoms**:
```
[ERROR] S3 upload failed
```

**Solution**:
```bash
# Verify AWS credentials
aws sts get-caller-identity

# Test S3 access
aws s3 ls s3://my-minio-backups/

# Check endpoint configuration
aws s3 ls --endpoint-url https://custom-endpoint.com

# Manual upload for debugging
aws s3 cp /var/backups/minio/minio_backup_*.tar.gz.enc \
    s3://my-minio-backups/test/ --debug
```

### Diagnostic Commands

```bash
# Check backup script syntax
bash -n scripts/backup/backup.sh

# Run backup in verbose mode
bash -x scripts/backup/backup.sh 2>&1 | tee backup-debug.log

# Check disk space
df -h /var/backups/minio

# Check Docker volumes
docker volume ls
docker volume inspect minio-data

# Verify backup file integrity
file /var/backups/minio/minio_backup_*.tar.gz.enc
openssl enc -aes-256-cbc -d \
    -in /var/backups/minio/minio_backup_*.tar.gz.enc \
    -pass file:scripts/backup/.backup.key | tar tzf - | head

# Check cron logs
grep CRON /var/log/syslog
```

---

## Best Practices

### Backup Strategy

1. **3-2-1 Rule**:
   - **3** copies of data
   - **2** different storage types
   - **1** off-site copy

2. **Backup Frequency**:
   - **Critical data**: Hourly incremental + daily full
   - **Standard data**: Daily full
   - **Configuration**: On change + weekly

3. **Retention Policy**:
   - **Daily backups**: 30 days
   - **Weekly backups**: 90 days
   - **Monthly backups**: 1 year
   - **Yearly backups**: 7 years (compliance)

4. **Testing**:
   - Test restores monthly
   - Full DR drill quarterly
   - Document recovery times

### Security Best Practices

1. **Encryption**:
   - Always enable encryption for production
   - Store keys separately from backups
   - Rotate keys annually

2. **Access Control**:
   - Limit backup access to authorized personnel
   - Use separate AWS accounts for backup storage
   - Enable MFA for S3 bucket access

3. **Monitoring**:
   - Alert on backup failures
   - Monitor backup sizes for anomalies
   - Track restore test results

### Performance Optimization

1. **Backup**:
   - Schedule during low-usage periods
   - Use compression (60-80% size reduction)
   - Parallelize component backups where possible

2. **Storage**:
   - Use fast storage for backup destination (SSD preferred)
   - Separate backup storage from operational storage
   - Monitor storage capacity (keep 20% free)

3. **Network**:
   - Use dedicated network for backup traffic
   - Consider bandwidth limits for S3 uploads
   - Use S3 Transfer Acceleration for large backups

### Operational Guidelines

1. **Documentation**:
   - Maintain runbook for DR procedures
   - Document all configuration changes
   - Keep inventory of backup locations

2. **Communication**:
   - Notify team before scheduled maintenance
   - Document restore procedures clearly
   - Maintain on-call contacts for DR

3. **Automation**:
   - Automate backup verification
   - Alert on retention policy violations
   - Automate off-site rotation

---

## Appendix

### Backup Metadata Schema

```json
{
  "backup_name": "minio_backup_20260209_120000",
  "timestamp": "20260209_120000",
  "type": "full",
  "components": {
    "postgresql": true,
    "redis": true,
    "minio": true,
    "configs": true
  },
  "compression": true,
  "encryption": true,
  "size_bytes": 1073741824,
  "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General failure |
| 2 | Prerequisites check failed |
| 3 | Component backup/restore failed |
| 4 | Verification failed |
| 5 | User cancelled operation |

### Support & Resources

- **GitHub Issues**: [Repository Issues](https://github.com/abiolaogu/MinIO/issues)
- **Documentation**: [docs/](../../docs/)
- **Slack Channel**: #minio-enterprise (internal)

---

**Document Version**: 1.0.0
**Last Updated**: 2026-02-09
**Maintainer**: MinIO Enterprise Team
