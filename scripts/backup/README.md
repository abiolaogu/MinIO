# MinIO Enterprise Backup & Restore System

Comprehensive automated backup and restore solution for MinIO Enterprise cluster, including PostgreSQL, Redis, and all configurations.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Scheduling](#scheduling)
- [Restore Procedures](#restore-procedures)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Overview

The MinIO Enterprise Backup & Restore System provides:

- **Full and incremental backups** of entire MinIO cluster
- **PostgreSQL database** backup with pg_dumpall
- **Redis data** backup with RDB snapshots
- **Configuration files** backup
- **Automated scheduling** with systemd timers or cron
- **Encryption** support for sensitive data
- **Compression** to reduce storage usage
- **Integrity verification** with MD5 checksums
- **Rollback capability** for disaster recovery
- **Retention policies** for automatic cleanup

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Backup Components                       │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │   MinIO      │  │  PostgreSQL  │  │    Redis     │  │
│  │  (4 nodes)   │  │   Database   │  │    Cache     │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
│         │                  │                  │          │
│         └──────────────────┼──────────────────┘          │
│                            │                             │
│                   ┌────────▼────────┐                    │
│                   │  Backup Script  │                    │
│                   └────────┬────────┘                    │
│                            │                             │
│              ┌─────────────┼─────────────┐               │
│              │             │             │               │
│         ┌────▼────┐   ┌───▼────┐   ┌───▼────┐          │
│         │Compress │   │Encrypt │   │Verify  │          │
│         └────┬────┘   └───┬────┘   └───┬────┘          │
│              │            │            │                │
│              └────────────┼────────────┘                │
│                           │                             │
│                  ┌────────▼────────┐                    │
│                  │ Backup Storage  │                    │
│                  │ /backup/minio/  │                    │
│                  └─────────────────┘                    │
└─────────────────────────────────────────────────────────┘
```

---

## Features

### Backup Capabilities

✅ **Full Backups**
- Complete snapshot of all data
- MinIO cluster (4 nodes)
- PostgreSQL database (all databases)
- Redis data store
- Configuration files

✅ **Incremental Backups**
- Changes since last backup
- Faster execution
- Reduced storage usage

✅ **Compression**
- gzip, bzip2, xz support
- Configurable compression levels
- Typical 60-70% size reduction

✅ **Encryption**
- AES-256-CBC encryption
- Secure key management
- Optional per-backup encryption

✅ **Integrity Verification**
- MD5 checksum validation
- Automatic verification after backup
- Pre-restore verification

### Restore Capabilities

✅ **Complete Restore**
- Full system restoration
- Point-in-time recovery
- Rollback support

✅ **Selective Restore**
- Individual component restoration
- PostgreSQL only
- Redis only
- MinIO data only

✅ **Verification Mode**
- Validate backup before restore
- No system changes

✅ **Rollback Protection**
- Automatic snapshot before restore
- One-command rollback
- Minimizes data loss risk

---

## Quick Start

### Create Your First Backup

```bash
# Navigate to scripts directory
cd /opt/minio-enterprise/scripts/backup

# Make scripts executable
chmod +x backup.sh ../restore/restore.sh

# Run full backup
./backup.sh full /backup/minio

# Backup completes in 2-5 minutes (typical)
```

### Restore from Backup

```bash
# Navigate to restore directory
cd /opt/minio-enterprise/scripts/restore

# Verify backup first (recommended)
./restore.sh /backup/minio/minio-backup-full-20260208_102600 --verify-only

# Perform restore (interactive confirmation)
./restore.sh /backup/minio/minio-backup-full-20260208_102600
```

---

## Installation

### Prerequisites

- Docker and Docker Compose installed
- MinIO Enterprise running
- Sufficient disk space (3-5x data size recommended)
- Root or sudo access

### Setup Steps

1. **Create backup directory**

```bash
sudo mkdir -p /backup/minio
sudo chown $USER:$USER /backup/minio
```

2. **Make scripts executable**

```bash
cd /opt/minio-enterprise/scripts/backup
chmod +x backup.sh
chmod +x ../restore/restore.sh
```

3. **Configure backup settings** (optional)

```bash
cp backup-config.env backup-config.local.env
nano backup-config.local.env
# Edit settings as needed
```

4. **Test backup**

```bash
./backup.sh full /backup/minio
```

5. **Set up automated scheduling** (see [Scheduling](#scheduling))

---

## Configuration

### Backup Configuration File

Edit `backup-config.env` to customize backup behavior:

```bash
# Backup destination
BACKUP_DESTINATION=/backup/minio

# Retention (days)
RETENTION_FULL=30
RETENTION_INCREMENTAL=7

# Compression
COMPRESSION=gzip
COMPRESSION_LEVEL=6

# Encryption
ENABLE_ENCRYPTION=false
ENCRYPTION_KEY_FILE=/etc/minio/backup-encryption.key

# Components to backup
BACKUP_POSTGRESQL=true
BACKUP_REDIS=true
BACKUP_MINIO_DATA=true
BACKUP_CONFIGURATIONS=true
```

### Encryption Setup

If enabling encryption:

```bash
# Generate encryption key
sudo mkdir -p /etc/minio
sudo openssl rand -base64 32 > /etc/minio/backup-encryption.key
sudo chmod 600 /etc/minio/backup-encryption.key

# Enable in config
sed -i 's/ENABLE_ENCRYPTION=false/ENABLE_ENCRYPTION=true/' backup-config.env
```

**⚠️ WARNING**: Keep encryption key secure! Loss of key means permanent data loss.

---

## Usage

### Backup Command Syntax

```bash
./backup.sh [BACKUP_TYPE] [DESTINATION]
```

**Parameters:**
- `BACKUP_TYPE`: `full` or `incremental`
- `DESTINATION`: Path to backup storage (default: `/backup`)

### Backup Examples

#### Full Backup

```bash
# Basic full backup
./backup.sh full /backup/minio

# Full backup to S3-compatible storage (requires mc or aws cli)
# Note: Backup to local first, then sync to S3
./backup.sh full /tmp/backup
mc mirror /tmp/backup/minio-backup-* s3/backup-bucket/
```

#### Incremental Backup

```bash
# Incremental backup (faster, smaller)
./backup.sh incremental /backup/minio
```

### Restore Command Syntax

```bash
./restore.sh <BACKUP_PATH> [OPTIONS]
```

**Options:**
- `--verify-only`: Only verify backup integrity, don't restore
- `--rollback`: Rollback to snapshot created before last restore

### Restore Examples

#### Verify Backup

```bash
# Check backup integrity without restoring
./restore.sh /backup/minio/minio-backup-full-20260208_102600 --verify-only
```

#### Full Restore

```bash
# Interactive restore with confirmation
./restore.sh /backup/minio/minio-backup-full-20260208_102600

# Script will:
# 1. Verify backup integrity
# 2. Create rollback snapshot
# 3. Prompt for confirmation
# 4. Restore all components
# 5. Verify services
```

#### Rollback After Restore

```bash
# If restore didn't work, rollback to previous state
./restore.sh /backup/minio/minio-backup-full-20260208_102600 --rollback
```

---

## Scheduling

### Option 1: Systemd Timers (Recommended for Linux)

```bash
# Copy service and timer files
sudo cp systemd/*.service /etc/systemd/system/
sudo cp systemd/*.timer /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable and start timers
sudo systemctl enable minio-backup-full.timer
sudo systemctl enable minio-backup-incremental.timer
sudo systemctl start minio-backup-full.timer
sudo systemctl start minio-backup-incremental.timer

# Check status
sudo systemctl status minio-backup-full.timer
sudo systemctl list-timers minio-backup*
```

**Default Schedule:**
- Full backup: Daily at 2:00 AM
- Incremental backup: Every 6 hours

### Option 2: Cron Jobs

```bash
# Copy cron file
sudo cp cron/minio-backup.cron /etc/cron.d/minio-backup
sudo chmod 0644 /etc/cron.d/minio-backup

# Verify cron is working
sudo service cron status
sudo tail -f /var/log/minio-backup-full.log
```

### Option 3: Docker Compose Integration

Add backup container to `docker-compose.yml`:

```yaml
services:
  backup:
    image: alpine:latest
    container_name: minio-backup
    volumes:
      - ./scripts:/scripts
      - /backup:/backup
      - /var/run/docker.sock:/var/run/docker.sock
    command: >
      sh -c "apk add --no-cache docker-cli &&
             while true; do
               /scripts/backup/backup.sh full /backup;
               sleep 86400;
             done"
    restart: unless-stopped
```

---

## Restore Procedures

### Standard Restore Procedure

1. **Verify backup integrity**

```bash
./restore.sh /backup/minio/minio-backup-full-TIMESTAMP --verify-only
```

2. **Review backup metadata**

```bash
cat /backup/minio/minio-backup-full-TIMESTAMP/metadata/backup-info.json
```

3. **Stop application traffic** (optional but recommended)

```bash
# Put load balancer in maintenance mode
# Or stop HAProxy
docker-compose -f deployments/docker/docker-compose.production.yml stop haproxy
```

4. **Perform restore**

```bash
./restore.sh /backup/minio/minio-backup-full-TIMESTAMP
# Type 'yes' when prompted
```

5. **Verify services**

```bash
# Check all containers are healthy
docker ps

# Test MinIO API
curl http://localhost:9000/minio/health/live

# Test PostgreSQL
docker exec postgres psql -U postgres -c "SELECT 1"

# Test Redis
docker exec redis redis-cli ping
```

6. **Resume application traffic**

```bash
docker-compose -f deployments/docker/docker-compose.production.yml start haproxy
```

### Emergency Recovery

If primary system fails:

1. **Set up new MinIO cluster**
2. **Copy backup files to new system**
3. **Install backup scripts**
4. **Run restore**

```bash
# On new system
scp -r old-server:/backup/minio/minio-backup-full-TIMESTAMP /backup/
cd /opt/minio-enterprise/scripts/restore
./restore.sh /backup/minio-backup-full-TIMESTAMP
```

### Partial Restore

To restore only specific components, edit the restore script or manually extract:

```bash
# PostgreSQL only
./restore.sh /backup/minio/minio-backup-full-TIMESTAMP
# Then manually skip other components when prompted

# Or extract manually:
gunzip < /backup/minio/minio-backup-full-TIMESTAMP/postgres/postgres-*.sql.gz | \
  docker exec -i postgres psql -U postgres
```

---

## Testing

### Test Backup Creation

```bash
# Create test backup
./backup.sh full /tmp/test-backup

# Expected output:
# - Backup directory created
# - PostgreSQL backup (~10-100 MB)
# - Redis backup (~1-10 MB)
# - MinIO data backup (varies)
# - Configuration backup (~1 MB)
# - All checksums verified
```

### Test Restore (Non-Destructive)

```bash
# Verify only (doesn't change anything)
./restore.sh /tmp/test-backup/minio-backup-full-* --verify-only

# Expected output:
# - Backup integrity verified
# - All checksums passed
# - Metadata readable
```

### Test Complete Backup/Restore Cycle

**⚠️ WARNING**: This will overwrite data! Only test in non-production environment.

```bash
# 1. Create test data
docker exec minio1 mc mb /data/test-bucket
docker exec minio1 mc cp /etc/os-release /data/test-bucket/

# 2. Backup
./backup.sh full /tmp/test-restore

# 3. Delete test data
docker exec minio1 mc rm --recursive --force /data/test-bucket/

# 4. Restore
./restore.sh /tmp/test-restore/minio-backup-full-* <<< "yes"

# 5. Verify data restored
docker exec minio1 mc ls /data/test-bucket/
```

### Automated Testing Script

```bash
#!/bin/bash
# test-backup-restore.sh

set -e

echo "Testing backup/restore cycle..."

# Create backup
./backup.sh full /tmp/test-backup-$(date +%s)

# Verify backup
BACKUP_DIR=$(ls -td /tmp/test-backup-* | head -1)
./restore.sh "$BACKUP_DIR" --verify-only

echo "✅ Backup/restore test passed!"
```

---

## Troubleshooting

### Common Issues

#### Issue: "Service not running" error

**Symptom**: Backup fails with "Service postgres/redis/minio1 is not running"

**Solution**:
```bash
# Check service status
docker ps

# Start all services
cd /opt/minio-enterprise/deployments/docker
docker-compose -f docker-compose.production.yml up -d

# Retry backup
cd /opt/minio-enterprise/scripts/backup
./backup.sh full /backup/minio
```

#### Issue: "Disk space full" error

**Symptom**: Backup fails with "No space left on device"

**Solution**:
```bash
# Check disk usage
df -h /backup

# Cleanup old backups manually
find /backup/minio -type d -name "minio-backup-*" -mtime +30 -exec rm -rf {} \;

# Or adjust retention in config
nano backup-config.env
# Set RETENTION_FULL=7 for shorter retention
```

#### Issue: Checksum verification failed

**Symptom**: "Checksum failed" during backup or restore

**Solution**:
```bash
# For backup: This indicates disk corruption or hardware issue
# - Check disk health: sudo smartctl -a /dev/sda
# - Try backup to different location
# - Contact hardware support if repeated failures

# For restore: Backup file may be corrupted
# - Try older backup
# - Check backup storage integrity
# - Re-download backup if stored remotely
```

#### Issue: Restore hangs or takes very long

**Symptom**: Restore script appears stuck

**Solution**:
```bash
# Check logs
tail -f /tmp/minio-restore-*.log

# Check Docker container status
docker ps
docker logs postgres
docker logs redis

# For very large databases, restore can take 30+ minutes
# Be patient, check logs for progress
```

#### Issue: Permission denied errors

**Symptom**: "Permission denied" when running scripts

**Solution**:
```bash
# Make scripts executable
chmod +x /opt/minio-enterprise/scripts/backup/backup.sh
chmod +x /opt/minio-enterprise/scripts/restore/restore.sh

# Check directory permissions
sudo chown -R $USER:$USER /backup/minio

# For systemd timers, ensure service runs as root
sudo systemctl edit minio-backup-full.service
# Add: User=root
```

### Debug Mode

Enable verbose logging:

```bash
# Add to top of backup.sh or restore.sh
set -x  # Print each command
set -v  # Print script lines

# Or run with bash -x
bash -x ./backup.sh full /backup/minio
```

### Log Files

Check log files for detailed error messages:

```bash
# Backup logs
ls -lh /backup/minio/minio-backup-*/backup.log

# Recent backup log
tail -100 /backup/minio/$(ls -t /backup/minio | head -1)/backup.log

# Restore logs
ls -lh /tmp/minio-restore-*.log

# Systemd logs
sudo journalctl -u minio-backup-full.service -n 100
```

---

## Best Practices

### 1. Backup Strategy

- **3-2-1 Rule**:
  - 3 copies of data
  - 2 different storage media
  - 1 off-site copy

```bash
# Example: Local + S3 backup
./backup.sh full /backup/minio
mc mirror /backup/minio s3/backup-bucket/minio/
```

- **Regular Testing**: Test restores monthly
- **Verify Backups**: Always verify after creation
- **Monitor Backups**: Set up alerts for backup failures

### 2. Retention Policies

Recommended retention periods:

| Backup Type | Frequency | Retention |
|-------------|-----------|-----------|
| Full | Daily | 30 days |
| Incremental | 6 hours | 7 days |
| Monthly | Monthly | 12 months |
| Yearly | Yearly | 7 years |

### 3. Security

- **Encrypt Backups**: Always enable encryption for production
- **Secure Keys**: Store encryption keys in secure vault (Vault, AWS KMS)
- **Access Control**: Limit backup access to authorized personnel
- **Network Security**: Use secure channels for remote backup transfer

### 4. Performance Optimization

- **Compression**: Use gzip level 6 for balance
- **Parallel Jobs**: Set PARALLEL_JOBS=2-4 for faster backups
- **Off-Peak Hours**: Schedule during low-traffic periods (2-4 AM)
- **Network Bandwidth**: Limit if affecting production (BANDWIDTH_LIMIT)

### 5. Monitoring and Alerting

Set up monitoring for:

- ✅ Backup completion status
- ✅ Backup duration (alert if >2x normal time)
- ✅ Backup size (alert if deviation >20%)
- ✅ Storage space (alert if <20% free)
- ✅ Restore test results (monthly)

Example with Prometheus:

```yaml
# Alert rule
- alert: BackupFailed
  expr: minio_backup_last_success_timestamp < (time() - 86400)
  annotations:
    summary: "MinIO backup has not completed in 24 hours"
```

### 6. Documentation

Maintain documentation for:

- Backup schedule and retention
- Restore procedures (runbook)
- Contact information for emergencies
- Encryption key locations and access procedures
- Change log for backup configuration

### 7. Disaster Recovery

Create and test disaster recovery plan:

1. **Document Recovery Time Objective (RTO)**: Target <30 minutes
2. **Document Recovery Point Objective (RPO)**: Target <6 hours
3. **Test DR Procedures**: Quarterly full restore tests
4. **Document Dependencies**: External services, DNS, certificates
5. **Contact List**: Personnel, vendors, stakeholders

---

## Recovery Time Estimates

Typical restore times (depends on data size and hardware):

| Data Size | Estimated Time |
|-----------|---------------|
| Small (<10 GB) | 5-10 minutes |
| Medium (10-100 GB) | 15-30 minutes |
| Large (100-500 GB) | 30-90 minutes |
| Very Large (500+ GB) | 2-6 hours |

Factors affecting restore time:

- Disk I/O speed
- Network bandwidth (if restoring from remote storage)
- Compression level used
- Encryption (adds 5-10% overhead)
- PostgreSQL database size (larger = longer restore)

---

## Support and Resources

### Documentation

- [MinIO Official Docs](https://min.io/docs)
- [PostgreSQL Backup Docs](https://www.postgresql.org/docs/current/backup.html)
- [Redis Persistence](https://redis.io/topics/persistence)

### Getting Help

- **GitHub Issues**: [Repository Issues](https://github.com/your-org/MinIO/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/MinIO/discussions)
- **Email**: backup-support@minio-enterprise.local

### Emergency Contacts

In case of critical backup/restore issues:

- On-call DevOps: [Configure in your organization]
- Database Administrator: [Configure in your organization]
- Security Team: [Configure in your organization]

---

## Appendix

### Backup Directory Structure

```
/backup/minio/
└── minio-backup-full-20260208_102600/
    ├── metadata/
    │   └── backup-info.json
    ├── postgres/
    │   ├── postgres-20260208_102600.sql.gz
    │   └── postgres-20260208_102600.sql.gz.md5
    ├── redis/
    │   ├── dump-20260208_102600.rdb.gz
    │   └── dump-20260208_102600.rdb.gz.md5
    ├── minio/
    │   ├── minio1-20260208_102600.tar.gz
    │   ├── minio1-20260208_102600.tar.gz.md5
    │   ├── minio2-20260208_102600.tar.gz
    │   ├── minio2-20260208_102600.tar.gz.md5
    │   ├── minio3-20260208_102600.tar.gz
    │   ├── minio3-20260208_102600.tar.gz.md5
    │   ├── minio4-20260208_102600.tar.gz
    │   └── minio4-20260208_102600.tar.gz.md5
    ├── configs/
    │   ├── configs-20260208_102600.tar.gz
    │   └── configs-20260208_102600.tar.gz.md5
    ├── backup.log
    └── MANIFEST.txt
```

### Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| BACKUP_DESTINATION | /backup | Backup storage location |
| COMPRESSION | gzip | Compression algorithm |
| COMPRESSION_LEVEL | 6 | Compression level (1-9) |
| ENABLE_ENCRYPTION | false | Enable AES-256 encryption |
| RETENTION_FULL | 30 | Full backup retention (days) |
| RETENTION_INCREMENTAL | 7 | Incremental retention (days) |
| VERIFY_AFTER_BACKUP | true | Verify after backup |

### Script Exit Codes

| Exit Code | Meaning |
|-----------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Missing dependencies |
| 3 | Service not running |
| 4 | Backup verification failed |
| 5 | Disk space insufficient |

---

**Last Updated**: 2026-02-08
**Version**: 1.0.0
**Maintainers**: DevOps Team
