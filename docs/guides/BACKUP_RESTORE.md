# MinIO Enterprise - Backup & Restore Guide

**Version**: 1.0.0
**Last Updated**: 2026-02-08
**Status**: Production Ready

## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Prerequisites](#prerequisites)
4. [Quick Start](#quick-start)
5. [Backup Operations](#backup-operations)
6. [Restore Operations](#restore-operations)
7. [Configuration](#configuration)
8. [Scheduling Automated Backups](#scheduling-automated-backups)
9. [Disaster Recovery Procedures](#disaster-recovery-procedures)
10. [Best Practices](#best-practices)
11. [Troubleshooting](#troubleshooting)
12. [Performance Considerations](#performance-considerations)

---

## Overview

The MinIO Enterprise Backup & Restore system provides comprehensive, automated backup and recovery capabilities for all critical components:

- **PostgreSQL Database**: Complete database dumps with schema and data
- **Redis State**: Snapshot-based backups of cached data
- **MinIO Objects**: Full and incremental object storage backups

### Key Features

✅ **Comprehensive Coverage**: Backup all system components
✅ **Flexible Backup Types**: Full, incremental, and component-specific backups
✅ **Encryption Support**: GPG-based encryption for sensitive data
✅ **Compression**: Automatic gzip compression to reduce storage
✅ **Verification**: Built-in integrity checking for backups
✅ **Automated Retention**: Configurable retention policies with automatic cleanup
✅ **Disaster Recovery**: Complete system restore with verification
✅ **Docker-Aware**: Support for containerized deployments
✅ **Cron-Compatible**: Easy integration with cron for scheduled backups

---

## Features

### Backup Features

1. **Multiple Backup Types**
   - **Full**: Complete backup of PostgreSQL, Redis, and MinIO objects
   - **Incremental**: Only objects modified since last backup
   - **Component-Specific**: Individual backups for postgres, redis, or objects

2. **Security & Reliability**
   - GPG encryption with key-based security
   - Automatic compression to save storage
   - SHA256 checksums for integrity verification
   - Detailed manifests with backup metadata

3. **Automation & Scheduling**
   - Cron-compatible for scheduled backups
   - Configurable retention policies
   - Automatic cleanup of old backups
   - Email notifications (optional)

4. **Enterprise Features**
   - Docker/Kubernetes aware
   - Remote S3 backup support (optional)
   - Comprehensive logging
   - Dry-run mode for testing

### Restore Features

1. **Flexible Restore Options**
   - Full system restore
   - Component-specific restore
   - Point-in-time recovery
   - Dry-run mode for validation

2. **Safety & Verification**
   - Pre-restore confirmation prompts
   - Automatic decryption and decompression
   - Post-restore integrity verification
   - Detailed restore logging

3. **Recovery Capabilities**
   - Complete disaster recovery
   - Selective component restoration
   - Cross-environment restore support
   - Rollback capability

---

## Prerequisites

### Required Tools

Install the following tools based on your backup/restore needs:

```bash
# PostgreSQL tools
sudo apt-get install postgresql-client  # Ubuntu/Debian
brew install postgresql                  # macOS

# Redis tools
sudo apt-get install redis-tools         # Ubuntu/Debian
brew install redis                       # macOS

# MinIO Client
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# Compression & Encryption (usually pre-installed)
sudo apt-get install gzip gpg tar       # Ubuntu/Debian
```

### Optional: GPG Key Setup

For encrypted backups, generate a GPG key:

```bash
# Generate GPG key
gpg --full-generate-key

# List keys and note the key ID
gpg --list-keys

# Export your key ID
export GPG_KEY_ID="YOUR_KEY_ID_HERE"
```

### System Requirements

- **Disk Space**: At least 2x the size of your data for backups
- **Network**: Sufficient bandwidth for object transfers
- **Permissions**: Read access to PostgreSQL, Redis, and MinIO

---

## Quick Start

### 1. Setup

```bash
# Navigate to backup scripts directory
cd scripts/backup

# Make scripts executable
chmod +x backup.sh
chmod +x ../restore/restore.sh

# Copy and edit configuration
cp backup.conf backup.local.conf
nano backup.local.conf  # Edit with your settings
```

### 2. Basic Backup

```bash
# Full backup with defaults
./backup.sh --type full

# Full backup with encryption and verification
./backup.sh --type full --encrypt --verify --config backup.local.conf

# PostgreSQL only
./backup.sh --type postgres

# Incremental objects backup
./backup.sh --type incremental
```

### 3. Basic Restore

```bash
# List available backups
ls -lh ../../backups/

# Dry-run restore (preview only)
cd ../restore
./restore.sh --backup-dir ../../backups/backup_full_20260208_120000 --dry-run

# Full restore with verification
./restore.sh --backup-dir ../../backups/backup_full_20260208_120000 --verify

# Restore specific component
./restore.sh --backup-dir ../../backups/backup_full_20260208_120000 --type postgres
```

---

## Backup Operations

### Backup Types

#### 1. Full Backup

Backs up all components (PostgreSQL + Redis + Objects):

```bash
./backup.sh --type full --output /backups --compress --verify
```

**Use Cases**:
- Daily/weekly scheduled backups
- Before major system updates
- Disaster recovery preparation

**Duration**: ~10-60 minutes (depends on data size)
**Storage**: Largest backup size

#### 2. Incremental Backup

Backs up only objects modified since last backup:

```bash
./backup.sh --type incremental --output /backups
```

**Use Cases**:
- Hourly backups for active systems
- Continuous backup strategy
- Minimizing backup windows

**Duration**: ~1-10 minutes
**Storage**: Smallest backup size

#### 3. Component-Specific Backups

**PostgreSQL Only**:
```bash
./backup.sh --type postgres --output /backups
```

**Redis Only**:
```bash
./backup.sh --type redis --output /backups
```

**Objects Only**:
```bash
./backup.sh --type objects --output /backups
```

**Use Cases**:
- Database-only updates
- Component-specific recovery
- Selective backup strategies

### Backup Options

| Option | Description | Example |
|--------|-------------|---------|
| `--config <file>` | Configuration file path | `--config ./backup.local.conf` |
| `--type <type>` | Backup type (full/incremental/postgres/redis/objects) | `--type full` |
| `--output <dir>` | Output directory | `--output /mnt/backups` |
| `--encrypt` | Enable GPG encryption | `--encrypt` |
| `--compress` | Enable gzip compression (default) | `--compress` |
| `--no-compress` | Disable compression | `--no-compress` |
| `--verify` | Verify backup integrity | `--verify` |
| `--help` | Show help message | `--help` |

### Backup Workflow

```
1. Initialize
   ├── Load configuration
   ├── Check prerequisites
   └── Create backup directory

2. Backup Components
   ├── PostgreSQL → pg_dump → compress → encrypt
   ├── Redis → SAVE + RDB copy → compress → encrypt
   └── Objects → mc mirror → tar → compress → encrypt

3. Post-Backup
   ├── Verify integrity (if enabled)
   ├── Generate manifest with checksums
   ├── Cleanup old backups (retention policy)
   └── Log results
```

### Backup Output Structure

```
backups/
└── backup_full_20260208_120000/
    ├── postgresql_20260208_120000.sql.gz.gpg
    ├── redis_20260208_120000.rdb.gz.gpg
    ├── objects_20260208_120000.tar.gz.gpg
    ├── MANIFEST.txt
    └── backup.log
```

### Backup Manifest Example

```
MinIO Enterprise Backup Manifest
==================================

Backup Type: full
Timestamp: 20260208_120000
Date: 2026-02-08 12:00:00
Script Version: 1.0.0

Configuration:
  Compression: true
  Encryption: true
  Verification: true

Files:
  - postgresql_20260208_120000.sql.gz.gpg
    Size: 245M
    SHA256: a3f5d2c8e9b7...

  - redis_20260208_120000.rdb.gz.gpg
    Size: 89M
    SHA256: 7d2e1f4b6c9a...

  - objects_20260208_120000.tar.gz.gpg
    Size: 1.2G
    SHA256: 2b8c7e3a5f1d...

Backup Location: /backups/backup_full_20260208_120000
```

---

## Restore Operations

### Restore Types

#### 1. Full Restore

Restores all components (PostgreSQL + Redis + Objects):

```bash
./restore.sh --backup-dir /backups/backup_full_20260208_120000 --type full --verify
```

**RTO (Recovery Time Objective)**: ~15-90 minutes
**Use Cases**: Complete disaster recovery

#### 2. Component-Specific Restore

**PostgreSQL Only**:
```bash
./restore.sh --backup-dir /backups/backup_full_20260208_120000 --type postgres
```

**Redis Only**:
```bash
./restore.sh --backup-dir /backups/backup_full_20260208_120000 --type redis
```

**Objects Only**:
```bash
./restore.sh --backup-dir /backups/backup_full_20260208_120000 --type objects
```

### Restore Options

| Option | Description | Example |
|--------|-------------|---------|
| `--backup-dir <dir>` | Backup directory to restore from (required) | `--backup-dir /backups/backup_full_20260208_120000` |
| `--type <type>` | Restore type (full/postgres/redis/objects) | `--type full` |
| `--verify` | Verify restore integrity | `--verify` |
| `--dry-run` | Preview restore without making changes | `--dry-run` |
| `--force` | Skip confirmation prompts | `--force` |
| `--help` | Show help message | `--help` |

### Restore Workflow

```
1. Initialize
   ├── Load configuration
   ├── Check prerequisites
   ├── Read backup manifest
   └── Validate backup directory

2. Prepare Files
   ├── Decrypt (if encrypted)
   ├── Decompress (if compressed)
   └── Extract (if archived)

3. Restore Components
   ├── PostgreSQL → DROP + CREATE + pg_restore
   ├── Redis → SHUTDOWN + RDB replace + START
   └── Objects → mc mirror to MinIO

4. Post-Restore
   ├── Verify integrity (if enabled)
   ├── Check connectivity
   ├── Validate data counts
   └── Log results
```

### Pre-Restore Checklist

Before performing a restore:

1. ✅ **Backup Current State**: Create a backup before restoring
2. ✅ **Stop Applications**: Stop services accessing the data
3. ✅ **Verify Backup**: Check manifest and file integrity
4. ✅ **Test Dry-Run**: Run restore with `--dry-run` first
5. ✅ **Check Disk Space**: Ensure sufficient storage
6. ✅ **Review Logs**: Check backup logs for issues
7. ✅ **Notify Team**: Inform stakeholders of maintenance window

### Restore Safety Features

1. **Confirmation Prompts**
   - User confirmation before destructive operations
   - `--force` flag to skip prompts for automation

2. **Dry-Run Mode**
   - Preview restore operations without changes
   - Validates backup files and prerequisites

3. **Automatic Verification**
   - Post-restore connectivity checks
   - Data integrity validation
   - Log analysis

4. **Detailed Logging**
   - All operations logged to `restore_TIMESTAMP.log`
   - Error messages with troubleshooting hints
   - Success confirmations with metrics

---

## Configuration

### Configuration File: `backup.conf`

Located at `scripts/backup/backup.conf`, this file contains default settings:

```bash
# PostgreSQL Configuration
POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"
POSTGRES_USER="postgres"
POSTGRES_PASSWORD="changeme"
POSTGRES_DB="minio"

# Redis Configuration
REDIS_HOST="localhost"
REDIS_PORT="6379"
REDIS_PASSWORD=""
REDIS_CONTAINER_NAME="redis"

# MinIO Configuration
MINIO_ENDPOINT="http://localhost:9000"
MINIO_ACCESS_KEY="minioadmin"
MINIO_SECRET_KEY="minioadmin"

# Backup Settings
RETENTION_DAYS="30"
GPG_KEY_ID=""  # Set for encryption
```

### Environment Variables

Override configuration with environment variables:

```bash
# Export environment variables
export POSTGRES_HOST="db.production.com"
export POSTGRES_PASSWORD="secure_password"
export GPG_KEY_ID="ABCD1234"

# Run backup
./backup.sh --type full --encrypt
```

### Docker/Kubernetes Configuration

For containerized deployments, configure container access:

```bash
# Docker container names
POSTGRES_CONTAINER_NAME="postgres"
REDIS_CONTAINER_NAME="redis"
MINIO_CONTAINER_PREFIX="minio"

# Backup will use: docker exec <container> or docker cp
```

---

## Scheduling Automated Backups

### Cron Setup

Create scheduled backups using cron:

```bash
# Edit crontab
crontab -e

# Add backup schedules:

# Daily full backup at 2 AM
0 2 * * * /path/to/scripts/backup/backup.sh --type full --config /path/to/backup.local.conf --compress --verify >> /var/log/minio-backup.log 2>&1

# Hourly incremental backup
0 * * * * /path/to/scripts/backup/backup.sh --type incremental --config /path/to/backup.local.conf >> /var/log/minio-backup-incremental.log 2>&1

# Weekly full backup with encryption (Sunday 3 AM)
0 3 * * 0 /path/to/scripts/backup/backup.sh --type full --config /path/to/backup.local.conf --encrypt --verify >> /var/log/minio-backup-weekly.log 2>&1

# PostgreSQL only backup (every 6 hours)
0 */6 * * * /path/to/scripts/backup/backup.sh --type postgres --config /path/to/backup.local.conf >> /var/log/minio-backup-postgres.log 2>&1
```

### Systemd Timer (Alternative to Cron)

Create a systemd service and timer:

**Service File**: `/etc/systemd/system/minio-backup.service`

```ini
[Unit]
Description=MinIO Enterprise Backup
After=network.target postgresql.service redis.service

[Service]
Type=oneshot
User=backup
Group=backup
ExecStart=/opt/minio/scripts/backup/backup.sh --type full --config /etc/minio/backup.conf --compress --verify
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**Timer File**: `/etc/systemd/system/minio-backup.timer`

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

**Enable Timer**:

```bash
sudo systemctl daemon-reload
sudo systemctl enable minio-backup.timer
sudo systemctl start minio-backup.timer

# Check timer status
sudo systemctl list-timers minio-backup.timer
```

### Kubernetes CronJob

Deploy scheduled backups in Kubernetes:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: minio-backup
  namespace: minio-enterprise
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: minio-enterprise-backup:latest
            command:
            - /scripts/backup/backup.sh
            args:
            - --type
            - full
            - --config
            - /config/backup.conf
            - --compress
            - --verify
            volumeMounts:
            - name: backup-config
              mountPath: /config
            - name: backup-storage
              mountPath: /backups
            env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-credentials
                  key: password
            - name: MINIO_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: minio-credentials
                  key: secretKey
          volumes:
          - name: backup-config
            configMap:
              name: backup-config
          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-pvc
          restartPolicy: OnFailure
```

---

## Disaster Recovery Procedures

### Scenario 1: Complete System Failure

**Objective**: Restore entire MinIO Enterprise system from backup

**RTO**: 60-90 minutes
**RPO**: Last backup interval (e.g., 24 hours for daily backups)

**Procedure**:

1. **Prepare New Infrastructure**
   ```bash
   # Provision new servers/containers
   # Install PostgreSQL, Redis, MinIO
   # Install restore tools (pg_restore, redis-cli, mc)
   ```

2. **Identify Latest Backup**
   ```bash
   ls -lht /backups/ | head -10
   # Select most recent full backup
   ```

3. **Perform Dry-Run**
   ```bash
   cd scripts/restore
   ./restore.sh --backup-dir /backups/backup_full_20260208_020000 --dry-run
   ```

4. **Execute Full Restore**
   ```bash
   ./restore.sh \
     --backup-dir /backups/backup_full_20260208_020000 \
     --type full \
     --verify \
     --force
   ```

5. **Verify Services**
   ```bash
   # Check PostgreSQL
   psql -h localhost -U postgres -d minio -c "SELECT COUNT(*) FROM tenants;"

   # Check Redis
   redis-cli PING
   redis-cli DBSIZE

   # Check MinIO
   mc ls local/
   ```

6. **Restart Applications**
   ```bash
   # Restart MinIO servers
   systemctl start minio-server

   # Verify API health
   curl http://localhost:9000/health
   ```

7. **Validate Operations**
   - Test uploads and downloads
   - Verify user authentication
   - Check replication status

### Scenario 2: Database Corruption

**Objective**: Restore PostgreSQL database only

**RTO**: 15-30 minutes

**Procedure**:

1. **Stop MinIO Services**
   ```bash
   systemctl stop minio-server
   ```

2. **Restore PostgreSQL**
   ```bash
   cd scripts/restore
   ./restore.sh \
     --backup-dir /backups/backup_full_20260208_020000 \
     --type postgres \
     --verify
   ```

3. **Restart Services**
   ```bash
   systemctl start minio-server
   ```

### Scenario 3: Accidental Object Deletion

**Objective**: Restore MinIO objects only

**RTO**: 30-60 minutes

**Procedure**:

1. **Identify Affected Objects**
   - Review application logs
   - Check MinIO audit logs

2. **Selective Restore**
   ```bash
   # Restore all objects
   cd scripts/restore
   ./restore.sh \
     --backup-dir /backups/backup_full_20260208_020000 \
     --type objects \
     --force

   # Alternative: Manual selective restore
   mc mirror /backups/.../objects/bucket-name/ local/bucket-name/
   ```

### Scenario 4: Cross-Environment Migration

**Objective**: Migrate from staging to production

**Procedure**:

1. **Create Backup in Source Environment**
   ```bash
   # On staging
   ./backup.sh --type full --output /shared-storage/migration --compress
   ```

2. **Transfer Backup**
   ```bash
   # Copy to production environment
   rsync -avz /shared-storage/migration/ prod-server:/backups/
   ```

3. **Restore in Target Environment**
   ```bash
   # On production
   ./restore.sh \
     --backup-dir /backups/migration/backup_full_20260208_120000 \
     --type full \
     --verify
   ```

---

## Best Practices

### Backup Strategy

1. **3-2-1 Backup Rule**
   - Keep **3** copies of data
   - On **2** different storage types
   - With **1** copy offsite

2. **Backup Schedule Recommendations**
   - **Production**: Daily full + hourly incremental
   - **Staging**: Daily full
   - **Development**: Weekly full

3. **Retention Policies**
   - Daily backups: 30 days
   - Weekly backups: 90 days
   - Monthly backups: 1 year

4. **Backup Testing**
   - Test restores monthly
   - Automate restore verification
   - Document recovery procedures

### Security Best Practices

1. **Encryption**
   - Always encrypt production backups
   - Use strong GPG keys (4096-bit RSA)
   - Rotate encryption keys annually

2. **Access Control**
   - Restrict backup directory permissions: `chmod 700`
   - Use dedicated backup user account
   - Implement audit logging

3. **Credential Management**
   - Store passwords in secure vaults (Vault, AWS Secrets Manager)
   - Use environment variables, not config files
   - Rotate credentials regularly

### Performance Best Practices

1. **Backup Windows**
   - Schedule during low-traffic periods
   - Use incremental backups for active hours
   - Monitor backup duration trends

2. **Storage Optimization**
   - Enable compression (default)
   - Implement retention policies
   - Use efficient storage backends (NVMe, S3)

3. **Network Optimization**
   - Use local storage for backups when possible
   - Compress before remote transfer
   - Consider bandwidth limitations

### Monitoring & Alerting

1. **Backup Monitoring**
   ```bash
   # Check last backup age
   find /backups -type d -name "backup_*" -mtime -1 | wc -l

   # Alert if no backup in 24 hours
   ```

2. **Log Analysis**
   - Monitor backup logs for errors
   - Track backup sizes and durations
   - Alert on failed backups

3. **Storage Monitoring**
   ```bash
   # Check backup storage usage
   df -h /backups

   # Alert at 80% capacity
   ```

---

## Troubleshooting

### Common Issues

#### 1. Backup Fails: "Permission Denied"

**Symptom**: Backup script cannot access PostgreSQL/Redis/MinIO

**Solution**:
```bash
# Check PostgreSQL access
psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1;"

# Check Redis access
redis-cli -h $REDIS_HOST -p $REDIS_PORT PING

# Check MinIO access
mc alias set test $MINIO_ENDPOINT $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
mc ls test
```

#### 2. Backup Fails: "Insufficient Disk Space"

**Symptom**: Not enough space to create backup

**Solution**:
```bash
# Check available space
df -h /backups

# Cleanup old backups manually
rm -rf /backups/backup_*_older_than_30_days

# Adjust retention policy
export RETENTION_DAYS=15
```

#### 3. Restore Fails: "Database Already Exists"

**Symptom**: PostgreSQL restore fails due to existing database

**Solution**:
```bash
# Manually drop database
psql -h $POSTGRES_HOST -U $POSTGRES_USER -c "DROP DATABASE $POSTGRES_DB;"

# Or use --force flag
./restore.sh --backup-dir /backups/... --type postgres --force
```

#### 4. Decryption Fails: "GPG Key Not Found"

**Symptom**: Cannot decrypt encrypted backup

**Solution**:
```bash
# List available GPG keys
gpg --list-keys

# Import missing key
gpg --import /path/to/private-key.asc

# Verify key
gpg --list-secret-keys
```

#### 5. Redis Restore: "Cannot Access RDB File"

**Symptom**: Redis RDB file not accessible in container

**Solution**:
```bash
# Check Redis container name
docker ps | grep redis

# Update configuration
export REDIS_CONTAINER_NAME="actual_container_name"

# Alternative: Manual restore
docker cp redis_backup.rdb redis_container:/data/dump.rdb
docker restart redis_container
```

### Debug Mode

Enable detailed logging:

```bash
# Run backup with verbose output
bash -x ./backup.sh --type full 2>&1 | tee backup-debug.log

# Check log file
cat /backups/backup_*/backup.log
```

### Verification Failures

If backup verification fails:

```bash
# Manual verification
cd /backups/backup_full_20260208_120000

# Check PostgreSQL dump
pg_restore --list postgresql_*.sql

# Check Redis RDB
file redis_*.rdb

# Check object tarball
tar -tzf objects_*.tar.gz | head -20

# Verify checksums
sha256sum -c MANIFEST.txt
```

---

## Performance Considerations

### Backup Performance

| Component | Typical Duration | Optimization |
|-----------|------------------|--------------|
| PostgreSQL (100GB) | 10-20 minutes | Use parallel dump with `-j` flag |
| Redis (10GB) | 2-5 minutes | Ensure sufficient disk I/O |
| Objects (1TB) | 30-60 minutes | Use high-bandwidth network, parallel transfers |

### Optimization Tips

1. **PostgreSQL Optimization**
   ```bash
   # Use custom format for faster restore
   pg_dump -Fc -f backup.dump

   # Parallel dump (4 jobs)
   pg_dump -Fd -j 4 -f backup_dir
   ```

2. **MinIO Optimization**
   ```bash
   # Parallel object transfers
   mc mirror --parallel 10 source/ destination/

   # Exclude unnecessary objects
   mc mirror --exclude "*.tmp" source/ destination/
   ```

3. **Compression Optimization**
   ```bash
   # Use pigz for parallel compression
   tar -cf - directory/ | pigz -p 4 > backup.tar.gz

   # Adjust compression level (1=fast, 9=best)
   gzip -5 backup.sql
   ```

### Storage Requirements

**Example: Medium Deployment (100 users, 1TB data)**

```
Component          Uncompressed    Compressed    Encrypted
PostgreSQL         50 GB           15 GB         15.5 GB
Redis             5 GB            1.5 GB        1.6 GB
Objects           1000 GB         750 GB        760 GB
Total             1055 GB         766.5 GB      777.1 GB

Retention (30 days): ~23 TB storage needed
```

---

## Additional Resources

### Related Documentation

- [Deployment Guide](DEPLOYMENT.md) - System deployment procedures
- [Performance Guide](PERFORMANCE.md) - Performance optimization
- [Security Guide](../HARDWARE_REQUIREMENTS.md) - Security best practices

### External Resources

- [PostgreSQL Backup & Restore](https://www.postgresql.org/docs/current/backup.html)
- [Redis Persistence](https://redis.io/docs/management/persistence/)
- [MinIO Client Documentation](https://min.io/docs/minio/linux/reference/minio-mc.html)

### Support

- **GitHub Issues**: [Repository Issues](https://github.com/abiolaogu/MinIO/issues)
- **Documentation**: [docs/](../)

---

## Summary

### Key Takeaways

✅ **Regular Backups**: Schedule daily full backups and hourly incremental backups
✅ **Test Restores**: Verify restore procedures monthly
✅ **Secure Storage**: Encrypt sensitive production backups
✅ **Monitor Health**: Track backup success rates and storage usage
✅ **Document Procedures**: Maintain disaster recovery runbooks
✅ **3-2-1 Rule**: Keep 3 copies on 2 media types with 1 offsite

### Quick Commands Reference

```bash
# Backup
./backup.sh --type full --encrypt --verify
./backup.sh --type incremental
./backup.sh --type postgres

# Restore
./restore.sh --backup-dir /backups/backup_full_20260208_120000 --dry-run
./restore.sh --backup-dir /backups/backup_full_20260208_120000 --type full --verify

# Schedule (crontab)
0 2 * * * /path/to/backup.sh --type full --compress --verify
0 * * * * /path/to/backup.sh --type incremental

# Verify
tar -tzf objects_*.tar.gz
pg_restore --list postgresql_*.sql
```

---

**Document Version**: 1.0.0
**Last Updated**: 2026-02-08
**Maintained By**: MinIO Enterprise Team
