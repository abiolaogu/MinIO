# MinIO Enterprise - Backup & Restore Documentation

Complete guide for automated backup and restore procedures for MinIO Enterprise system, including MinIO objects, PostgreSQL database, Redis snapshots, and configuration files.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
  - [Manual Backup](#manual-backup)
  - [Manual Restore](#manual-restore)
  - [Scheduled Backups](#scheduled-backups)
- [Backup Components](#backup-components)
- [Restore Procedures](#restore-procedures)
- [Verification](#verification)
- [Rollback Procedures](#rollback-procedures)
- [Retention Policies](#retention-policies)
- [Encryption](#encryption)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [Recovery Time Objectives](#recovery-time-objectives)

---

## Overview

The MinIO Enterprise backup and restore system provides automated, reliable, and verifiable backup and recovery capabilities for production deployments. The system supports:

- **Full and incremental backups**
- **Automated retention management**
- **Encryption and compression**
- **Verification and rollback**
- **Multi-component backup** (MinIO, PostgreSQL, Redis, configuration)

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Backup Process Flow                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────┐   ┌───────────┐   ┌─────────┐   ┌────────┐ │
│  │  MinIO   │──▶│PostgreSQL │──▶│  Redis  │──▶│ Config │ │
│  │   Data   │   │ Database  │   │ Snapshot│   │ Files  │ │
│  └──────────┘   └───────────┘   └─────────┘   └────────┘ │
│       │               │               │             │      │
│       └───────────────┴───────────────┴─────────────┘      │
│                         │                                   │
│                         ▼                                   │
│              ┌─────────────────────┐                       │
│              │  Backup Directory   │                       │
│              │  YYYYMMDD_HHMMSS    │                       │
│              ├─────────────────────┤                       │
│              │  - minio/           │                       │
│              │  - postgres/        │                       │
│              │  - redis/           │                       │
│              │  - config/          │                       │
│              │  - metadata/        │                       │
│              └─────────────────────┘                       │
│                         │                                   │
│                         ▼                                   │
│       ┌──────────────────────────────────────┐            │
│       │  Optional Processing                 │            │
│       │  - Compression (gzip)                │            │
│       │  - Encryption (AES-256-CBC)          │            │
│       │  - Verification                      │            │
│       └──────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────────┘
```

---

## Features

### Backup Features

- ✅ **Full Backups**: Complete system state backup
- ✅ **Incremental Backups**: Delta-based backups (planned)
- ✅ **Component Selection**: Choose which components to backup
- ✅ **Compression**: gzip compression to save storage space
- ✅ **Encryption**: AES-256-CBC encryption for security
- ✅ **Verification**: Automatic backup integrity verification
- ✅ **Retention Management**: Automatic cleanup of old backups
- ✅ **Metadata Tracking**: JSON metadata for each backup
- ✅ **Detailed Logging**: Comprehensive logs for audit and debugging

### Restore Features

- ✅ **Selective Restoration**: Restore specific components
- ✅ **Rollback Protection**: Automatic rollback point creation
- ✅ **Verification**: Post-restore integrity checks
- ✅ **Service Management**: Automatic service stop/start
- ✅ **Decryption**: Automatic handling of encrypted backups
- ✅ **Decompression**: Automatic handling of compressed backups
- ✅ **Interactive Confirmation**: Safety prompts before restore
- ✅ **Detailed Reporting**: Complete restore status reports

---

## Prerequisites

### System Requirements

- **OS**: Linux (Ubuntu 20.04+, Debian 10+, RHEL 8+)
- **Disk Space**: Minimum 2x current data size for backups
- **Memory**: 2GB+ available during backup/restore operations
- **Network**: Access to PostgreSQL and Redis services

### Software Dependencies

Install required tools:

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y \
    postgresql-client \
    redis-tools \
    tar \
    gzip \
    openssl

# RHEL/CentOS
sudo yum install -y \
    postgresql \
    redis \
    tar \
    gzip \
    openssl
```

### Permissions

- **Read/Write** access to backup directory (`/var/backups/minio`)
- **Read** access to MinIO data directory
- **Connect** permissions to PostgreSQL database
- **Connect** permissions to Redis instance
- **Execute** permissions on backup/restore scripts

---

## Installation

### 1. Script Setup

```bash
# Navigate to project directory
cd /path/to/MinIO

# Make scripts executable
chmod +x scripts/backup/backup.sh
chmod +x scripts/restore/restore.sh

# Create backup root directory
sudo mkdir -p /var/backups/minio
sudo chown $(whoami):$(whoami) /var/backups/minio
```

### 2. Configuration Setup

```bash
# Copy example configurations
cp scripts/backup/backup.conf.example scripts/backup/backup.conf
cp scripts/restore/restore.conf.example scripts/restore/restore.conf

# Edit backup configuration
nano scripts/backup/backup.conf

# Edit restore configuration
nano scripts/restore/restore.conf
```

### 3. Test Installation

```bash
# Test backup script
./scripts/backup/backup.sh

# Verify backup was created
ls -lh /var/backups/minio/
```

---

## Configuration

### Backup Configuration (`backup.conf`)

#### Basic Settings

```bash
# Backup type: full or incremental
BACKUP_TYPE="full"

# Backup root directory
BACKUP_ROOT="/var/backups/minio"

# Retention period (days)
RETENTION_DAYS=30

# Enable compression
COMPRESSION=true

# Enable encryption
ENCRYPTION=false
ENCRYPTION_KEY=""  # Set if encryption enabled

# Enable verification
VERIFY_BACKUP=true
```

#### Component Selection

```bash
# Choose which components to backup
BACKUP_MINIO=true
BACKUP_POSTGRES=true
BACKUP_REDIS=true
BACKUP_CONFIG=true
```

#### MinIO Settings

```bash
MINIO_DATA_DIR="/var/lib/minio/data"
MINIO_ENDPOINT="http://localhost:9000"
MINIO_ACCESS_KEY=""  # Optional
MINIO_SECRET_KEY=""  # Optional
```

#### PostgreSQL Settings

```bash
POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"
POSTGRES_DB="minio"
POSTGRES_USER="postgres"
POSTGRES_PASSWORD="your-password"
```

#### Redis Settings

```bash
REDIS_HOST="localhost"
REDIS_PORT="6379"
REDIS_PASSWORD=""  # If auth enabled
REDIS_DATA_DIR="/var/lib/redis"
```

### Restore Configuration (`restore.conf`)

```bash
# Backup to restore: "latest", date, or path
BACKUP_TO_RESTORE="latest"

# Create rollback before restore
CREATE_ROLLBACK=true

# Stop/start services automatically
STOP_SERVICES=true
START_SERVICES=true

# Component selection
RESTORE_MINIO=true
RESTORE_POSTGRES=true
RESTORE_REDIS=true
RESTORE_CONFIG=true

# Encryption key (if backup is encrypted)
ENCRYPTION_KEY=""
```

---

## Usage

### Manual Backup

#### Basic Backup

```bash
# Run with default configuration
./scripts/backup/backup.sh
```

#### Backup with Custom Configuration

```bash
# Use custom config file
CONFIG_FILE=/path/to/custom.conf ./scripts/backup/backup.sh
```

#### Backup Specific Components

```bash
# Backup only PostgreSQL and Redis
BACKUP_MINIO=false \
BACKUP_CONFIG=false \
./scripts/backup/backup.sh
```

#### Encrypted Backup

```bash
# Enable encryption with strong key
ENCRYPTION=true \
ENCRYPTION_KEY="your-strong-encryption-password" \
./scripts/backup/backup.sh
```

#### Environment Variable Override

```bash
# Override any configuration via environment
BACKUP_ROOT=/custom/backup/path \
RETENTION_DAYS=60 \
COMPRESSION=true \
./scripts/backup/backup.sh
```

### Manual Restore

#### Restore Latest Backup

```bash
# Restore most recent backup
./scripts/restore/restore.sh
```

#### Restore Specific Backup

```bash
# By date
BACKUP_TO_RESTORE="20260207_183000" \
./scripts/restore/restore.sh

# By full path
BACKUP_TO_RESTORE="/var/backups/minio/20260207_183000" \
./scripts/restore/restore.sh
```

#### Restore Specific Components

```bash
# Restore only PostgreSQL database
RESTORE_MINIO=false \
RESTORE_REDIS=false \
RESTORE_CONFIG=false \
./scripts/restore/restore.sh
```

#### Restore Encrypted Backup

```bash
# Provide decryption key
ENCRYPTION_KEY="your-encryption-password" \
./scripts/restore/restore.sh
```

### Scheduled Backups

#### Using Cron

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * cd /path/to/MinIO && ./scripts/backup/backup.sh >> /var/backups/minio/cron.log 2>&1

# Add hourly backup
0 * * * * cd /path/to/MinIO && ./scripts/backup/backup.sh >> /var/backups/minio/cron.log 2>&1

# Add weekly backup (Sunday at 3 AM)
0 3 * * 0 cd /path/to/MinIO && ./scripts/backup/backup.sh >> /var/backups/minio/cron.log 2>&1
```

#### Using Systemd Timers

Create service file (`/etc/systemd/system/minio-backup.service`):

```ini
[Unit]
Description=MinIO Enterprise Backup
After=network.target

[Service]
Type=oneshot
User=minio
Group=minio
WorkingDirectory=/path/to/MinIO
ExecStart=/path/to/MinIO/scripts/backup/backup.sh
StandardOutput=journal
StandardError=journal
```

Create timer file (`/etc/systemd/system/minio-backup.timer`):

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

# Check timer status
sudo systemctl status minio-backup.timer
sudo systemctl list-timers
```

---

## Backup Components

### MinIO Data

**What's backed up:**
- All object data in MinIO storage
- Bucket metadata
- Object metadata
- Access policies

**Backup method:**
- Tarball of MinIO data directory
- Preserves directory structure and permissions

**Size:** Typically largest component

### PostgreSQL Database

**What's backed up:**
- All tenant data
- Quota information
- User accounts
- System metadata

**Backup method:**
- SQL dump using `pg_dump`
- Plain text format for maximum compatibility

**Size:** Usually small (<100MB)

### Redis Cache

**What's backed up:**
- Cache entries
- Session data
- Temporary state

**Backup method:**
- RDB snapshot using `BGSAVE`
- Binary dump file

**Size:** Varies (typically <1GB)

### Configuration Files

**What's backed up:**
- `configs/` directory
- `deployments/` directory
- `.env` files
- Docker Compose files

**Backup method:**
- Tarball of configuration directories
- Preserves structure

**Size:** Small (<10MB)

---

## Restore Procedures

### Full System Restore

Complete restore of all components:

```bash
# 1. Stop all services
docker-compose -f deployments/docker/docker-compose.production.yml stop

# 2. Run restore script
./scripts/restore/restore.sh

# 3. Verify services are running
docker-compose -f deployments/docker/docker-compose.production.yml ps
```

### Partial Restore

Restore only specific components:

```bash
# Restore only database
RESTORE_MINIO=false \
RESTORE_REDIS=false \
RESTORE_CONFIG=false \
./scripts/restore/restore.sh
```

### Point-in-Time Recovery

Restore to specific backup:

```bash
# List available backups
ls -lh /var/backups/minio/

# Restore specific backup
BACKUP_TO_RESTORE="20260207_120000" \
./scripts/restore/restore.sh
```

---

## Verification

### Backup Verification

Automatic verification checks:

1. ✅ All expected files created
2. ✅ File sizes are reasonable
3. ✅ Metadata is valid JSON
4. ✅ Compressed files can be read
5. ✅ Encrypted files have correct format

Manual verification:

```bash
# Check backup directory
ls -lh /var/backups/minio/20260207_183000/

# View backup metadata
cat /var/backups/minio/20260207_183000/metadata/backup_info.json

# Test decompression (without extracting)
gunzip -t /var/backups/minio/20260207_183000/minio/minio_data.tar.gz

# Verify PostgreSQL dump
head -n 50 /var/backups/minio/20260207_183000/postgres/postgres_minio.sql.gz | gunzip
```

### Restore Verification

Automatic verification checks:

1. ✅ MinIO data directory exists and accessible
2. ✅ PostgreSQL database connection successful
3. ✅ Redis data file present
4. ✅ Configuration files restored

Manual verification:

```bash
# Check MinIO data
ls -lh /var/lib/minio/data/

# Test PostgreSQL connection
psql -h localhost -U postgres -d minio -c "SELECT COUNT(*) FROM tenants;"

# Check Redis
redis-cli -h localhost ping

# Verify services
docker-compose -f deployments/docker/docker-compose.production.yml ps
```

---

## Rollback Procedures

### Automatic Rollback

The restore script automatically creates a rollback point before restore:

```bash
# Rollback location
/var/backups/minio/rollback_YYYYMMDD_HHMMSS/
```

### Manual Rollback

If restore fails or produces unexpected results:

```bash
# 1. Stop services
docker-compose -f deployments/docker/docker-compose.production.yml stop

# 2. Restore from rollback point
BACKUP_TO_RESTORE="/var/backups/minio/rollback_20260207_140000" \
CREATE_ROLLBACK=false \
./scripts/restore/restore.sh

# 3. Verify and start services
docker-compose -f deployments/docker/docker-compose.production.yml start
```

### Rollback Components

Each rollback backup contains:
- Pre-restore MinIO data
- Pre-restore PostgreSQL database
- Pre-restore Redis data
- Pre-restore configuration files

---

## Retention Policies

### Automatic Cleanup

The backup script automatically removes old backups:

```bash
# Default: 30 days
RETENTION_DAYS=30

# Custom retention
RETENTION_DAYS=90  # Keep 90 days
```

### Manual Cleanup

```bash
# List all backups with sizes
du -sh /var/backups/minio/*/ | sort -h

# Remove specific backup
rm -rf /var/backups/minio/20260101_120000/

# Remove all backups older than 60 days
find /var/backups/minio/ -maxdepth 1 -type d -mtime +60 -exec rm -rf {} \;
```

### Recommended Policies

| Environment | Backup Frequency | Retention Period |
|-------------|------------------|------------------|
| Production  | Every 6 hours    | 30 days          |
| Staging     | Daily            | 14 days          |
| Development | Weekly           | 7 days           |

---

## Encryption

### Enabling Encryption

```bash
# Generate strong encryption key
ENCRYPTION_KEY=$(openssl rand -base64 32)

# Save key securely (do NOT commit to git)
echo "${ENCRYPTION_KEY}" > /secure/location/encryption.key
chmod 600 /secure/location/encryption.key

# Run backup with encryption
ENCRYPTION=true \
ENCRYPTION_KEY="${ENCRYPTION_KEY}" \
./scripts/backup/backup.sh
```

### Encrypted Backup Structure

```
backup_YYYYMMDD_HHMMSS/
├── minio/
│   └── minio_data.tar.gz.enc    # Encrypted
├── postgres/
│   └── postgres_minio.sql.gz.enc # Encrypted
├── redis/
│   └── redis_dump.rdb.gz.enc     # Encrypted
└── config/
    └── config_files.tar.gz.enc   # Encrypted
```

### Restoring Encrypted Backups

```bash
# Provide encryption key
ENCRYPTION_KEY="your-encryption-password" \
./scripts/restore/restore.sh
```

### Security Best Practices

1. **Never hardcode** encryption keys in scripts
2. **Store keys securely** using secret management (Vault, AWS Secrets Manager)
3. **Rotate keys** periodically (quarterly recommended)
4. **Test decryption** regularly
5. **Document key locations** in secure runbook

---

## Troubleshooting

### Common Issues

#### Issue: "Permission denied" error

**Cause**: Insufficient permissions on backup directory

**Solution**:
```bash
sudo chown -R $(whoami):$(whoami) /var/backups/minio
chmod 755 /var/backups/minio
```

#### Issue: "pg_dump: command not found"

**Cause**: PostgreSQL client not installed

**Solution**:
```bash
# Ubuntu/Debian
sudo apt-get install postgresql-client

# RHEL/CentOS
sudo yum install postgresql
```

#### Issue: "Failed to trigger Redis background save"

**Cause**: Redis not accessible or authentication required

**Solution**:
```bash
# Test Redis connection
redis-cli -h localhost ping

# Test with password
redis-cli -h localhost -a your-password ping

# Update config with password
echo 'REDIS_PASSWORD="your-password"' >> scripts/backup/backup.conf
```

#### Issue: "Backup verification failed"

**Cause**: Partial backup or corrupted files

**Solution**:
```bash
# Check backup log
tail -n 100 /var/backups/minio/backup.log

# Re-run backup without verification to see detailed errors
VERIFY_BACKUP=false ./scripts/backup/backup.sh

# Check disk space
df -h /var/backups/minio
```

#### Issue: "Restore hangs at PostgreSQL restore"

**Cause**: Large database or slow connection

**Solution**:
```bash
# Monitor PostgreSQL restore progress
# In another terminal:
watch -n 1 'psql -h localhost -U postgres -d minio -c "SELECT COUNT(*) FROM pg_stat_activity;"'

# Check PostgreSQL logs
tail -f /var/log/postgresql/postgresql-*.log
```

### Debug Mode

Enable verbose logging:

```bash
# Add debug output
set -x

# Run script with trace
bash -x ./scripts/backup/backup.sh
```

### Log Analysis

```bash
# View backup log
tail -n 100 /var/backups/minio/backup.log

# Search for errors
grep ERROR /var/backups/minio/backup.log

# View restore log
tail -n 100 /var/backups/minio/restore.log
```

---

## Best Practices

### Backup Best Practices

1. **Test Regularly**: Perform test restores monthly
2. **Monitor Backups**: Set up alerting for backup failures
3. **Verify Integrity**: Always enable backup verification
4. **Encrypt Sensitive Data**: Use encryption for production backups
5. **Off-site Storage**: Copy backups to remote location
6. **Document Procedures**: Keep runbooks updated
7. **Version Control**: Track configuration changes
8. **Capacity Planning**: Monitor backup storage usage

### Restore Best Practices

1. **Test in Staging**: Test restore procedures in non-production first
2. **Create Rollback**: Always create rollback point before restore
3. **Verify Post-Restore**: Run smoke tests after restoration
4. **Document Issues**: Record any restore issues encountered
5. **Update Runbooks**: Document lessons learned
6. **Communicate**: Notify team during restore operations
7. **Monitor Services**: Watch logs during post-restore startup

### Security Best Practices

1. **Encrypt Backups**: Use strong encryption for sensitive data
2. **Secure Credentials**: Never store passwords in plain text
3. **Limit Access**: Restrict backup directory permissions
4. **Audit Logs**: Review backup/restore logs regularly
5. **Rotate Keys**: Change encryption keys periodically
6. **Test Recovery**: Verify encrypted backups can be restored

### Operational Best Practices

1. **Automate Backups**: Use cron or systemd timers
2. **Monitor Disk Space**: Alert when backup storage is low
3. **Test Disaster Recovery**: Run full DR tests quarterly
4. **Document Changes**: Update docs when configuration changes
5. **Version Scripts**: Keep backup scripts in version control
6. **Review Retention**: Adjust retention based on compliance needs

---

## Recovery Time Objectives

### Estimated Recovery Times

| Component | Data Size | Restore Time | RTO Target |
|-----------|-----------|--------------|------------|
| Configuration | <10MB | <1 minute | 5 minutes |
| PostgreSQL | <100MB | <5 minutes | 15 minutes |
| Redis | <1GB | <2 minutes | 10 minutes |
| MinIO (small) | <10GB | <10 minutes | 30 minutes |
| MinIO (medium) | 10-100GB | 30-60 minutes | 2 hours |
| MinIO (large) | 100GB+ | 1-3 hours | 4 hours |
| **Full System** | Varies | **30min-3hrs** | **<4 hours** |

### RTO Optimization

1. **Use Compression**: Reduces restore time by 30-50%
2. **Local Storage**: Keep recent backups on fast local disks
3. **Parallel Restore**: Restore components simultaneously
4. **Pre-staging**: Keep critical backups readily accessible
5. **Hardware**: Use fast storage (NVMe) for backup/restore operations

### RPO (Recovery Point Objective)

Recommended backup frequencies:

- **Critical Production**: Every 4-6 hours (RPO: 6 hours)
- **Standard Production**: Daily (RPO: 24 hours)
- **Staging/Development**: Weekly (RPO: 7 days)

---

## Support & Resources

### Documentation

- [Deployment Guide](../../docs/guides/DEPLOYMENT.md)
- [Performance Guide](../../docs/guides/PERFORMANCE.md)
- [Product Requirements Document](../../docs/PRD.md)

### Getting Help

- **GitHub Issues**: [Repository Issues](https://github.com/abiolaogu/MinIO/issues)
- **Documentation**: [docs/](../../docs/)

### Version History

- **v1.0.0** (2026-02-07): Initial release with full/incremental backup support

---

**Last Updated**: 2026-02-07
**Maintained By**: MinIO Enterprise Team
**Version**: 1.0.0
