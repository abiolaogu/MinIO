# MinIO Enterprise - Backup & Restore Guide

Comprehensive guide for backing up and restoring MinIO Enterprise deployments with automated disaster recovery capabilities.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Backup Operations](#backup-operations)
- [Restore Operations](#restore-operations)
- [Automation & Scheduling](#automation--scheduling)
- [Disaster Recovery Procedures](#disaster-recovery-procedures)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [FAQ](#faq)

## Overview

The MinIO Enterprise Backup & Restore system provides automated, reliable, and secure backup capabilities for production deployments. It supports:

- **Full and incremental backups** of all system components
- **Automated retention policies** to manage storage
- **Encryption and compression** for secure, efficient storage
- **Rollback capabilities** for safe restore operations
- **Verification and validation** to ensure data integrity

### Architecture

```
┌─────────────────────────────────────────┐
│         Backup Components               │
├─────────────────────────────────────────┤
│  ┌───────────┐  ┌──────────┐           │
│  │ PostgreSQL│  │  Redis   │           │
│  │  Database │  │  Cache   │           │
│  └─────┬─────┘  └────┬─────┘           │
│        │             │                  │
│  ┌─────▼─────┐  ┌───▼──────┐           │
│  │   MinIO   │  │  Config  │           │
│  │  Objects  │  │  Files   │           │
│  └───────────┘  └──────────┘           │
└─────────────────────────────────────────┘
           │
           ▼
    ┌─────────────┐
    │   Backup    │
    │  Archive    │
    └─────────────┘
           │
    ┌──────┴──────┐
    │             │
    ▼             ▼
┌────────┐   ┌────────┐
│ Local  │   │ Remote │
│ Storage│   │ Storage│
└────────┘   └────────┘
```

## Features

### Backup Features

✅ **Full System Backup**
- PostgreSQL database (complete schema and data)
- Redis cache state (RDB snapshots)
- MinIO object data (all buckets and objects)
- Configuration files and environment settings

✅ **Incremental Backups**
- Only backs up files modified in last 24 hours
- Significantly faster for large datasets
- Reduces storage requirements

✅ **Compression & Encryption**
- Gzip compression (9x compression level)
- AES-256-CBC encryption with PBKDF2
- Optional - can be enabled/disabled per backup

✅ **Automated Retention**
- Configurable retention period (default: 30 days)
- Automatic cleanup of old backups
- Prevents disk space exhaustion

✅ **Verification & Integrity**
- SHA-256 checksums for all files
- Automatic verification after backup
- Metadata tracking for audit trail

### Restore Features

✅ **Selective Restore**
- Restore specific components (postgres, redis, minio, config)
- Or restore all components together
- Flexible recovery options

✅ **Rollback Protection**
- Automatic rollback backup before restore
- Can revert to previous state if issues occur
- Ensures safe recovery operations

✅ **Dry Run Mode**
- Test restore without making changes
- Preview what will be restored
- Validate backup integrity

✅ **Verification**
- Post-restore connectivity checks
- Database integrity validation
- Ensures successful recovery

## Prerequisites

### System Requirements

- **Operating System**: Linux (Ubuntu 20.04+, Debian 10+, CentOS 8+)
- **Disk Space**: At least 2x the size of your data for backups
- **Memory**: 2GB+ available during backup operations
- **CPU**: 2+ cores recommended for compression

### Required Tools

Install the following tools on your system:

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y postgresql-client redis-tools gzip tar openssl

# CentOS/RHEL
sudo yum install -y postgresql redis gzip tar openssl

# Verify installation
pg_dump --version
redis-cli --version
```

### Permissions

The backup/restore scripts need:

- **Read access** to MinIO data directory (`/data/minio`)
- **Write access** to backup directory (`/var/backups/minio-enterprise`)
- **Network access** to PostgreSQL and Redis
- **Sudo access** (optional, for system-level operations)

## Quick Start

### 1. Configure Settings

Edit the configuration file:

```bash
cp configs/backup.conf.example configs/backup.conf
nano configs/backup.conf
```

Set your environment-specific values:

```bash
BACKUP_DIR=/var/backups/minio-enterprise
POSTGRES_HOST=your-postgres-host
REDIS_HOST=your-redis-host
MINIO_DATA_DIR=/data/minio
```

### 2. Set Credentials (Securely)

**IMPORTANT**: Never store passwords in configuration files!

Set credentials via environment variables:

```bash
export POSTGRES_PASSWORD='your-postgres-password'
export REDIS_PASSWORD='your-redis-password'

# For encryption (optional)
export ENCRYPTION_KEY='your-secure-encryption-key'
```

### 3. Run Your First Backup

```bash
# Make scripts executable
chmod +x scripts/backup.sh scripts/restore.sh

# Run full backup
./scripts/backup.sh
```

Expected output:
```
[INFO] 2026-02-07 12:00:00 - Starting MinIO Enterprise backup process...
[INFO] 2026-02-07 12:00:01 - Backup type: full
[INFO] 2026-02-07 12:00:02 - Backing up PostgreSQL database...
[INFO] 2026-02-07 12:00:15 - PostgreSQL backup completed: 250MB
[INFO] 2026-02-07 12:00:16 - Backing up Redis data...
[INFO] 2026-02-07 12:00:20 - Redis backup completed: 50MB
[INFO] 2026-02-07 12:00:21 - Backing up MinIO object data...
[INFO] 2026-02-07 12:05:30 - MinIO data backup completed: 10GB
[INFO] 2026-02-07 12:05:31 - Backup completed successfully!
```

### 4. List Available Backups

```bash
# List all backups
BACKUP_NAME="" ./scripts/restore.sh
```

### 5. Restore from Backup (Dry Run First!)

```bash
# Dry run (no changes)
DRY_RUN=true BACKUP_NAME=minio-backup-full-20260207_120000 ./scripts/restore.sh

# Actual restore
BACKUP_NAME=minio-backup-full-20260207_120000 ./scripts/restore.sh
```

## Configuration

### Configuration File

The backup system uses `/configs/backup.conf` for settings:

```bash
# Core Settings
BACKUP_DIR=/var/backups/minio-enterprise    # Where backups are stored
BACKUP_TYPE=full                             # full or incremental
RETENTION_DAYS=30                            # Auto-delete after X days
COMPRESSION=true                             # Enable gzip compression
ENCRYPTION=false                             # Enable AES-256 encryption

# Database Settings
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=minio
POSTGRES_USER=postgres

REDIS_HOST=redis
REDIS_PORT=6379

# Data Paths
MINIO_DATA_DIR=/data/minio
CONFIG_DIR=/etc/minio

# Restore Settings
RESTORE_COMPONENTS=all                       # all, postgres, redis, minio, config
CREATE_ROLLBACK=true                         # Create rollback before restore
DRY_RUN=false                                # Test mode
```

### Environment Variables

Override configuration with environment variables:

```bash
# Backup settings
export BACKUP_TYPE=incremental
export COMPRESSION=true
export ENCRYPTION=true
export ENCRYPTION_KEY='your-secure-key-here'

# Database credentials (SECURE!)
export POSTGRES_PASSWORD='db-password'
export REDIS_PASSWORD='redis-password'

# Custom paths
export BACKUP_DIR=/custom/backup/path
export MINIO_DATA_DIR=/custom/minio/data
```

### Security Best Practices

**NEVER commit passwords to version control!**

Use environment variables or secrets management:

```bash
# Option 1: Environment file (not in git)
echo "export POSTGRES_PASSWORD='secret'" > .backup-env
chmod 600 .backup-env
source .backup-env

# Option 2: Docker secrets
docker secret create postgres_password /path/to/password/file

# Option 3: Kubernetes secrets
kubectl create secret generic backup-secrets \
  --from-literal=postgres-password='secret' \
  --from-literal=redis-password='secret'
```

## Backup Operations

### Full Backup

Backs up all data:

```bash
BACKUP_TYPE=full ./scripts/backup.sh
```

**Use cases:**
- Initial backup
- Weekly/monthly comprehensive backups
- Before major system upgrades
- Compliance and archival requirements

**Pros:**
- Complete system state
- Independent restore (no dependencies)
- Simple disaster recovery

**Cons:**
- Larger storage requirements
- Longer backup time
- Higher network/IO usage

### Incremental Backup

Backs up only files modified in last 24 hours:

```bash
BACKUP_TYPE=incremental ./scripts/backup.sh
```

**Use cases:**
- Daily backups between full backups
- High-frequency backup schedules
- Large datasets with low change rate

**Pros:**
- Faster backup time
- Reduced storage usage
- Lower system impact

**Cons:**
- Requires base full backup
- More complex restore process
- Dependency chain

### Compressed Backup

Reduces backup size (enabled by default):

```bash
COMPRESSION=true ./scripts/backup.sh
```

**Compression ratios:**
- Database dumps: 8-10x compression
- Log files: 10-20x compression
- Binary data: 2-3x compression

**Trade-offs:**
- +CPU usage during backup
- -Disk space usage
- +Backup speed (less I/O)

### Encrypted Backup

Secures backups with AES-256 encryption:

```bash
ENCRYPTION=true ENCRYPTION_KEY='your-secure-key' ./scripts/backup.sh
```

**Important:**
- Store encryption key securely (password manager, secrets vault)
- Loss of key = permanent data loss
- No key recovery mechanism
- Use strong keys (32+ characters, alphanumeric + symbols)

**Generate strong encryption key:**

```bash
# Linux/macOS
openssl rand -base64 32

# Example output:
# 3Hf8jK2mP9xQ7vR4tY6nU1wE5sA0zL8c
```

### Remote Backup

Copy backups to remote storage (optional):

```bash
# S3-compatible storage
REMOTE_BACKUP=true \
REMOTE_BACKUP_TYPE=s3 \
S3_BUCKET=minio-backups \
S3_REGION=us-east-1 \
./scripts/backup.sh

# Rsync to remote server
REMOTE_BACKUP=true \
REMOTE_BACKUP_TYPE=rsync \
RSYNC_DEST=backup-server:/backups/minio \
./scripts/backup.sh
```

## Restore Operations

### List Available Backups

```bash
BACKUP_NAME="" ./scripts/restore.sh
```

Output:
```
Available backups:

  - minio-backup-full-20260207_120000
    Date: 2026-02-07 12:00:00
    Size: 10GB
    Type: Unencrypted
    Metadata: Available

  - minio-backup-incremental-20260207_140000
    Date: 2026-02-07 14:00:00
    Size: 500MB
    Type: Unencrypted
    Metadata: Available
```

### Full System Restore

Restore all components:

```bash
BACKUP_NAME=minio-backup-full-20260207_120000 ./scripts/restore.sh
```

**Process:**
1. Verifies backup integrity
2. Creates rollback backup of current state
3. Restores PostgreSQL database
4. Restores Redis cache
5. Restores MinIO object data
6. Restores configuration files
7. Verifies connectivity and integrity

### Selective Component Restore

Restore specific components only:

```bash
# Restore only database
RESTORE_COMPONENTS=postgres \
BACKUP_NAME=minio-backup-full-20260207_120000 \
./scripts/restore.sh

# Restore only MinIO data
RESTORE_COMPONENTS=minio \
BACKUP_NAME=minio-backup-full-20260207_120000 \
./scripts/restore.sh

# Restore multiple components
RESTORE_COMPONENTS=postgres,redis \
BACKUP_NAME=minio-backup-full-20260207_120000 \
./scripts/restore.sh
```

**Available components:**
- `postgres` - PostgreSQL database
- `redis` - Redis cache
- `minio` - MinIO object data
- `config` - Configuration files
- `all` - All components (default)

### Dry Run (Test Mode)

Preview restore without making changes:

```bash
DRY_RUN=true \
BACKUP_NAME=minio-backup-full-20260207_120000 \
./scripts/restore.sh
```

Output:
```
[DRY RUN] Would restore PostgreSQL from: /var/backups/.../postgres/minio.sql.gz
[DRY RUN] Would restore Redis from: /var/backups/.../redis/dump.rdb
[DRY RUN] Would restore MinIO data from: /var/backups/.../minio/data.tar.gz
```

### Encrypted Backup Restore

Decrypt and restore:

```bash
ENCRYPTION=true \
ENCRYPTION_KEY='your-encryption-key' \
BACKUP_NAME=minio-backup-full-20260207_120000 \
./scripts/restore.sh
```

### Rollback After Failed Restore

If restore fails or causes issues:

```bash
# Check rollback backup location (shown in restore output)
# Example: /var/backups/minio-enterprise/rollback-20260207_150000

# Restore from rollback
BACKUP_NAME=rollback-20260207_150000 ./scripts/restore.sh
```

## Automation & Scheduling

### Cron Job Setup

Automate backups with cron:

```bash
# Edit crontab
crontab -e

# Add backup schedules
# Daily full backup at 2 AM
0 2 * * * /path/to/scripts/backup.sh >> /var/log/minio-backup.log 2>&1

# Incremental backup every 6 hours
0 */6 * * * BACKUP_TYPE=incremental /path/to/scripts/backup.sh >> /var/log/minio-backup.log 2>&1

# Weekly full backup on Sunday at 1 AM
0 1 * * 0 BACKUP_TYPE=full /path/to/scripts/backup.sh >> /var/log/minio-backup.log 2>&1
```

### Systemd Timer (Alternative to Cron)

Create systemd service:

```bash
# Create service file
sudo nano /etc/systemd/system/minio-backup.service
```

```ini
[Unit]
Description=MinIO Enterprise Backup Service
After=network.target postgresql.service redis.service

[Service]
Type=oneshot
User=backup
Group=backup
Environment="BACKUP_TYPE=full"
Environment="COMPRESSION=true"
ExecStart=/opt/minio/scripts/backup.sh
StandardOutput=append:/var/log/minio-backup.log
StandardError=append:/var/log/minio-backup.log

[Install]
WantedBy=multi-user.target
```

Create timer:

```bash
sudo nano /etc/systemd/system/minio-backup.timer
```

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

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable minio-backup.timer
sudo systemctl start minio-backup.timer

# Check status
sudo systemctl status minio-backup.timer
```

### Docker Compose Integration

Add backup service to docker-compose:

```yaml
services:
  backup:
    image: minio-backup:latest
    volumes:
      - ./scripts:/scripts
      - backup-data:/var/backups
      - minio-data:/data/minio:ro
    environment:
      - BACKUP_TYPE=full
      - COMPRESSION=true
      - POSTGRES_HOST=postgres
      - REDIS_HOST=redis
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    command: /scripts/backup.sh
    depends_on:
      - postgres
      - redis
      - minio-node1
```

### Kubernetes CronJob

Deploy backup as Kubernetes CronJob:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: minio-backup
  namespace: minio-enterprise
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: minio-backup:latest
            command: ["/scripts/backup.sh"]
            env:
            - name: BACKUP_TYPE
              value: "full"
            - name: COMPRESSION
              value: "true"
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: backup-secrets
                  key: postgres-password
            volumeMounts:
            - name: backup-storage
              mountPath: /var/backups
            - name: minio-data
              mountPath: /data/minio
              readOnly: true
          restartPolicy: OnFailure
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-pvc
          - name: minio-data
            persistentVolumeClaim:
              claimName: minio-data-pvc
```

## Disaster Recovery Procedures

### Complete System Failure

**Scenario**: Total system loss, need to rebuild from scratch.

**Recovery Steps:**

1. **Provision new infrastructure**
   ```bash
   # Deploy fresh MinIO cluster
   docker-compose -f deployments/docker/docker-compose.production.yml up -d
   ```

2. **Verify services are running**
   ```bash
   docker-compose ps
   # Ensure postgres, redis, minio nodes are healthy
   ```

3. **Identify latest backup**
   ```bash
   BACKUP_NAME="" ./scripts/restore.sh
   # Note the most recent full backup
   ```

4. **Perform restore**
   ```bash
   BACKUP_NAME=minio-backup-full-YYYYMMDD_HHMMSS ./scripts/restore.sh
   ```

5. **Verify restoration**
   ```bash
   # Check database
   docker exec -it postgres psql -U postgres -d minio -c "SELECT COUNT(*) FROM objects;"

   # Check Redis
   docker exec -it redis redis-cli PING

   # Check MinIO API
   curl http://localhost:9000/health
   ```

6. **Resume operations**
   ```bash
   # Monitor logs
   docker-compose logs -f

   # Run smoke tests
   make test-integration
   ```

**Expected RTO**: <30 minutes (10GB dataset)

### Database Corruption

**Scenario**: PostgreSQL database corruption.

**Recovery Steps:**

1. **Stop MinIO services**
   ```bash
   docker-compose stop minio-node1 minio-node2 minio-node3 minio-node4
   ```

2. **Restore database only**
   ```bash
   RESTORE_COMPONENTS=postgres \
   BACKUP_NAME=minio-backup-full-20260207_120000 \
   ./scripts/restore.sh
   ```

3. **Verify database**
   ```bash
   docker exec -it postgres psql -U postgres -d minio -c "\dt"
   ```

4. **Restart MinIO**
   ```bash
   docker-compose start minio-node1 minio-node2 minio-node3 minio-node4
   ```

**Expected RTO**: <10 minutes

### Accidental Data Deletion

**Scenario**: User accidentally deleted objects.

**Recovery Steps:**

1. **Identify backup before deletion**
   ```bash
   BACKUP_NAME="" ./scripts/restore.sh
   # Find backup from before deletion occurred
   ```

2. **Dry run first**
   ```bash
   DRY_RUN=true \
   RESTORE_COMPONENTS=minio \
   BACKUP_NAME=minio-backup-full-20260207_120000 \
   ./scripts/restore.sh
   ```

3. **Perform selective restore**
   ```bash
   RESTORE_COMPONENTS=minio \
   BACKUP_NAME=minio-backup-full-20260207_120000 \
   ./scripts/restore.sh
   ```

**Expected RTO**: <20 minutes

### Configuration Error

**Scenario**: Bad configuration deployed, system unstable.

**Recovery Steps:**

1. **Restore configuration only**
   ```bash
   RESTORE_COMPONENTS=config \
   BACKUP_NAME=minio-backup-full-20260207_120000 \
   ./scripts/restore.sh
   ```

2. **Restart services**
   ```bash
   docker-compose restart
   ```

**Expected RTO**: <5 minutes

## Troubleshooting

### Backup Failures

#### Issue: PostgreSQL backup fails

```
[ERROR] PostgreSQL backup failed
```

**Diagnosis:**
```bash
# Check PostgreSQL connectivity
psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1"

# Check credentials
echo $POSTGRES_PASSWORD

# Check disk space
df -h /var/backups
```

**Solutions:**
- Verify `POSTGRES_PASSWORD` is set correctly
- Ensure PostgreSQL is running and accessible
- Check network connectivity: `ping $POSTGRES_HOST`
- Verify user permissions: `GRANT ALL ON DATABASE minio TO postgres;`
- Ensure sufficient disk space for backup

#### Issue: Redis backup incomplete

```
[WARN] Redis RDB dump may have failed
```

**Diagnosis:**
```bash
# Check Redis connectivity
redis-cli -h $REDIS_HOST -p $REDIS_PORT PING

# Check Redis save configuration
redis-cli -h $REDIS_HOST CONFIG GET save

# Check Redis write permissions
redis-cli -h $REDIS_HOST CONFIG GET dir
```

**Solutions:**
- Verify `REDIS_PASSWORD` if authentication is enabled
- Ensure Redis persistence is configured: `redis-cli CONFIG SET save "900 1 300 10 60 10000"`
- Check Redis data directory permissions
- Increase Redis memory if needed

#### Issue: Disk space exhausted

```
[ERROR] No space left on device
```

**Solutions:**
```bash
# Check current usage
df -h

# Clean old backups manually
find /var/backups/minio-enterprise -type d -mtime +30 -exec rm -rf {} \;

# Reduce retention period
RETENTION_DAYS=7 ./scripts/backup.sh

# Enable compression if not already
COMPRESSION=true ./scripts/backup.sh

# Move backups to larger volume
BACKUP_DIR=/mnt/large-volume/backups ./scripts/backup.sh
```

### Restore Failures

#### Issue: Backup not found

```
[ERROR] Backup not found: /var/backups/minio-enterprise/minio-backup-full-20260207_120000
```

**Solutions:**
```bash
# List available backups
ls -lah /var/backups/minio-enterprise/

# Check exact backup name
BACKUP_NAME="" ./scripts/restore.sh

# Verify backup directory
echo $BACKUP_DIR

# Check for encrypted backups
ls -lah /var/backups/minio-enterprise/*.tar.enc
```

#### Issue: Checksum verification failed

```
[ERROR] Checksum verification failed!
```

**Diagnosis:**
```bash
# Check backup integrity
cd /var/backups/minio-enterprise/minio-backup-full-20260207_120000
sha256sum -c metadata/checksums.txt
```

**Solutions:**
- Backup may be corrupted - use a different backup
- Disk corruption - check disk health: `sudo smartctl -a /dev/sda`
- Network transfer corruption - re-download backup
- DO NOT use corrupted backups for production restore

#### Issue: Decryption failed

```
[ERROR] Failed to decrypt backup
```

**Solutions:**
```bash
# Verify encryption key
echo $ENCRYPTION_KEY

# Test decryption manually
openssl enc -aes-256-cbc -d -pbkdf2 \
  -in backup.tar.enc \
  -out backup.tar \
  -pass pass:"$ENCRYPTION_KEY"

# Check backup was actually encrypted
file backup.tar.enc
```

### Performance Issues

#### Issue: Backup is too slow

**Optimizations:**

1. **Enable compression** (paradoxically faster due to less I/O)
   ```bash
   COMPRESSION=true ./scripts/backup.sh
   ```

2. **Use incremental backups** for frequent schedules
   ```bash
   BACKUP_TYPE=incremental ./scripts/backup.sh
   ```

3. **Exclude large temporary files**
   ```bash
   # Edit backup.sh to add exclusions
   tar --exclude='*.tmp' --exclude='cache/*' -cf ...
   ```

4. **Schedule during low-traffic periods**
   ```bash
   # Run at 2 AM when usage is low
   0 2 * * * /path/to/scripts/backup.sh
   ```

5. **Use faster storage** for backup destination
   ```bash
   BACKUP_DIR=/mnt/nvme-ssd/backups ./scripts/backup.sh
   ```

## Best Practices

### Backup Strategy

**3-2-1 Rule:**
- **3** copies of data (original + 2 backups)
- **2** different media types (local disk + cloud)
- **1** off-site copy (different location)

**Recommended Schedule:**
```bash
# Daily incremental (keeps RPO low)
0 2 * * 1-6 BACKUP_TYPE=incremental /scripts/backup.sh

# Weekly full (complete state)
0 1 * * 0 BACKUP_TYPE=full /scripts/backup.sh

# Monthly archive (long-term retention)
0 0 1 * * BACKUP_TYPE=full RETENTION_DAYS=365 /scripts/backup.sh
```

### Security

1. **Never store credentials in scripts or config files**
   ```bash
   # BAD
   POSTGRES_PASSWORD="mypassword"  # In config file

   # GOOD
   export POSTGRES_PASSWORD=$(cat /run/secrets/postgres_password)
   ```

2. **Use encryption for sensitive data**
   ```bash
   ENCRYPTION=true ENCRYPTION_KEY='strong-key' ./scripts/backup.sh
   ```

3. **Secure backup directory permissions**
   ```bash
   chmod 700 /var/backups/minio-enterprise
   chown backup:backup /var/backups/minio-enterprise
   ```

4. **Rotate encryption keys periodically**
   ```bash
   # Every 90 days, re-encrypt with new key
   ```

### Testing

**Regular restore testing** is critical:

```bash
# Monthly restore test
# 1. Spin up test environment
# 2. Restore latest backup
# 3. Run smoke tests
# 4. Document results
# 5. Destroy test environment
```

**Automate restore testing:**
```bash
#!/bin/bash
# restore-test.sh
DRY_RUN=false \
BACKUP_NAME=latest \
POSTGRES_HOST=test-postgres \
REDIS_HOST=test-redis \
./scripts/restore.sh && echo "✅ Restore test PASSED" || echo "❌ Restore test FAILED"
```

### Monitoring

Monitor backup jobs:

```bash
# Log backup results
./scripts/backup.sh 2>&1 | tee -a /var/log/minio-backup.log

# Alert on failures
./scripts/backup.sh || mail -s "Backup FAILED" admin@example.com

# Track backup sizes
du -sh /var/backups/minio-enterprise/* | tee backup-sizes.log

# Monitor disk space
df -h /var/backups | tee -a disk-usage.log
```

Integrate with monitoring systems:

```bash
# Prometheus metrics
echo "minio_backup_success 1" > /var/lib/node_exporter/textfile_collector/backup.prom
echo "minio_backup_size_bytes $(du -sb /var/backups/latest | cut -f1)" >> /var/lib/node_exporter/textfile_collector/backup.prom
```

### Documentation

Maintain a runbook:

```markdown
# Disaster Recovery Runbook

## Contact Information
- On-call engineer: +1-555-0100
- Backup admin: backup-team@example.com

## Recovery Procedures
- RTO Target: 30 minutes
- RPO Target: 24 hours

## Latest Backup Location
- Path: /var/backups/minio-enterprise/minio-backup-full-20260207_120000
- Size: 10GB
- Date: 2026-02-07
- Checksum: abc123...

## Recovery Steps
1. ...
2. ...
```

## FAQ

### Q: How long do backups take?

**A:** Depends on data size and backup type:
- **Full backup**: ~1-2 minutes per GB (with compression)
- **Incremental**: ~30 seconds per GB of changed data
- **Example**: 10GB dataset = ~15 minutes full, ~5 minutes incremental

### Q: How much disk space do I need?

**A:** General formula:
```
Required space = (Data size × Compression ratio × Retention days) / Backup frequency

Example:
- 10GB data
- 30% compression (0.3 of original)
- 30 day retention
- Daily backups
= 10GB × 0.3 × 30 = 90GB
```

Add 20% buffer: **~110GB**

### Q: Can I restore to a different server?

**A:** Yes! The restore process is server-agnostic:

1. Copy backup to new server
2. Update host settings:
   ```bash
   POSTGRES_HOST=new-postgres \
   REDIS_HOST=new-redis \
   ./scripts/restore.sh
   ```

### Q: What if I lose my encryption key?

**A:** **There is no recovery.** Encrypted backups without the key are permanently inaccessible.

**Prevention:**
- Store keys in password manager (1Password, LastPass)
- Use key management service (AWS KMS, HashiCorp Vault)
- Maintain key backup in secure, separate location
- Document key rotation procedures

### Q: Can I backup to cloud storage?

**A:** Yes! Use remote backup feature:

```bash
# S3
REMOTE_BACKUP=true \
REMOTE_BACKUP_TYPE=s3 \
S3_BUCKET=my-backups \
./scripts/backup.sh

# Or use rclone for any cloud provider
rclone sync /var/backups/minio-enterprise remote:backups/
```

### Q: How do I verify a backup without restoring?

**A:** Use verification tools:

```bash
# Check checksums
cd /var/backups/minio-enterprise/minio-backup-full-20260207_120000
sha256sum -c metadata/checksums.txt

# List backup contents
tar -tzf minio/data.tar.gz | head -20

# Check PostgreSQL dump
zcat postgres/minio.sql.gz | grep "CREATE TABLE" | wc -l
```

### Q: Can I run backups while system is live?

**A:** Yes! The backup script uses:
- PostgreSQL: `pg_dump` (non-blocking, consistent snapshot)
- Redis: `BGSAVE` (background save, non-blocking)
- MinIO: File-level copy (may capture mid-write, but MinIO handles consistency)

For absolute consistency, use:
```bash
# Put system in maintenance mode
docker-compose stop minio-node*

# Backup
./scripts/backup.sh

# Resume
docker-compose start minio-node*
```

### Q: What's the difference between backup types?

| Feature | Full Backup | Incremental Backup |
|---------|------------|-------------------|
| Speed | Slow (all data) | Fast (changed data only) |
| Size | Large | Small |
| Restore | Simple | Complex (needs base + increments) |
| RPO | Best | Good |
| Recommended | Weekly/Monthly | Daily/Hourly |

### Q: How do I backup to multiple locations?

**A:** Run backup script multiple times with different destinations:

```bash
#!/bin/bash
# multi-backup.sh

# Local backup
BACKUP_DIR=/var/backups/local ./scripts/backup.sh

# Network backup
BACKUP_DIR=/mnt/nfs/backups ./scripts/backup.sh

# Cloud backup
BACKUP_DIR=/tmp/backups ./scripts/backup.sh
rclone sync /tmp/backups remote:backups/
rm -rf /tmp/backups
```

---

## Summary

The MinIO Enterprise Backup & Restore system provides:

✅ **Reliability**: Comprehensive backups with verification
✅ **Flexibility**: Full, incremental, selective restore options
✅ **Security**: Encryption, checksums, secure credential handling
✅ **Automation**: Cron, systemd, Docker, Kubernetes integration
✅ **Recovery**: Fast RTO (<30 min), documented procedures

**Next Steps:**
1. Configure backup settings: `configs/backup.conf`
2. Test backup: `./scripts/backup.sh`
3. Test restore: `DRY_RUN=true ./scripts/restore.sh`
4. Schedule automation: `crontab -e`
5. Document runbook for your team

For additional help:
- GitHub Issues: [Repository Issues](https://github.com/abiolaogu/MinIO/issues)
- Documentation: [docs/](../)

---

**Last Updated**: 2026-02-07
**Version**: 1.0.0
**Maintained By**: MinIO Enterprise Team
