# MinIO Enterprise - Backup & Restore Documentation

Comprehensive documentation for the MinIO Enterprise automated backup and restore system.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Backup System](#backup-system)
- [Restore System](#restore-system)
- [Configuration](#configuration)
- [Scheduling](#scheduling)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Recovery Procedures](#recovery-procedures)

---

## Overview

The MinIO Enterprise backup and restore system provides automated, production-ready disaster recovery capabilities for all critical components:

- **MinIO Object Storage**: All stored objects and metadata
- **PostgreSQL Database**: Tenant data, quota information, metadata
- **Redis Cache**: Session data, cached state
- **Configuration Files**: Docker Compose, environment files, service configs

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Backup System                           │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌───────┐  ┌─────────┐   │
│  │  MinIO   │  │PostgreSQL│  │ Redis │  │ Configs │   │
│  │   Data   │  │ Database │  │ State │  │  Files  │   │
│  └────┬─────┘  └────┬─────┘  └───┬───┘  └────┬────┘   │
│       │             │             │           │         │
│       └─────────────┴─────────────┴───────────┘         │
│                     │                                    │
│              ┌──────▼──────┐                            │
│              │  Compress   │                            │
│              │  (gzip)     │                            │
│              └──────┬──────┘                            │
│                     │                                    │
│              ┌──────▼──────┐                            │
│              │  Encrypt    │                            │
│              │  (AES-256)  │                            │
│              └──────┬──────┘                            │
│                     │                                    │
│         ┌───────────┴───────────┐                       │
│         │                       │                       │
│    ┌────▼────┐           ┌──────▼──────┐               │
│    │  Local  │           │  S3 Upload  │               │
│    │ Storage │           │  (Optional) │               │
│    └─────────┘           └─────────────┘               │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

## Features

### Backup Features

- ✅ **Full Backups**: Complete system state backup
- ✅ **Incremental Backups**: Space-efficient differential backups
- ✅ **Compression**: gzip compression to reduce storage requirements
- ✅ **Encryption**: AES-256-CBC encryption for data security
- ✅ **S3 Upload**: Automatic upload to S3-compatible storage
- ✅ **Retention Policy**: Configurable retention with automatic cleanup
- ✅ **Verification**: Automatic backup integrity verification
- ✅ **Metadata**: Complete backup metadata for tracking
- ✅ **Logging**: Comprehensive logging for audit and debugging

### Restore Features

- ✅ **Full Restore**: Complete system restoration
- ✅ **Selective Restore**: Restore specific components
- ✅ **Verification Mode**: Verify backup without restoring
- ✅ **Pre-Restore Snapshot**: Automatic snapshot before restore
- ✅ **Rollback Support**: Easy rollback if restore fails
- ✅ **Service Management**: Automatic service stop/start
- ✅ **Health Checks**: Post-restore verification
- ✅ **Decryption**: Automatic decryption of encrypted backups

---

## Prerequisites

### Required Software

```bash
# Docker and Docker Compose
docker --version  # >= 20.10
docker-compose --version  # >= 1.29

# System utilities
tar --version     # For archiving
gzip --version    # For compression
jq --version      # For JSON parsing

# Optional (for encryption)
openssl version   # For backup encryption

# Optional (for S3 upload)
aws --version     # AWS CLI for S3 uploads
```

### Required Permissions

- Docker access (execute Docker commands)
- Write access to backup directory (`/var/backups/minio-enterprise`)
- Read access to project directory

### System Requirements

- **Disk Space**: At least 2x the size of all data being backed up
- **Memory**: 2GB+ available during backup/restore operations
- **CPU**: Multi-core recommended for compression

---

## Quick Start

### 1. Basic Backup

```bash
# Run a full backup with default settings
cd /path/to/MinIO
./scripts/backup/backup.sh

# Backup will be saved to: /var/backups/minio-enterprise/
```

### 2. Basic Restore

```bash
# Restore from a backup
./scripts/restore/restore.sh /var/backups/minio-enterprise/minio-backup-full-20240118_120000.tar.gz
```

### 3. Verify Backup

```bash
# Verify backup integrity without restoring
RESTORE_MODE=verify-only ./scripts/restore/restore.sh /var/backups/minio-enterprise/minio-backup-full-20240118_120000.tar.gz
```

---

## Backup System

### Manual Backup

```bash
# Full backup
./scripts/backup/backup.sh

# Incremental backup
BACKUP_TYPE=incremental ./scripts/backup/backup.sh

# Custom backup directory
BACKUP_DIR=/mnt/backups ./scripts/backup/backup.sh

# Compressed backup
COMPRESS=true ./scripts/backup/backup.sh

# Encrypted backup
ENCRYPT=true ENCRYPTION_KEY="your-secure-key" ./scripts/backup/backup.sh
```

### Configuration File

Edit `/scripts/backup/backup.conf`:

```bash
# Backup type: full or incremental
BACKUP_TYPE="full"

# Backup directory
BACKUP_DIR="/var/backups/minio-enterprise"

# Retention policy (days)
RETENTION_DAYS=30

# Enable compression
COMPRESS=true

# Enable encryption
ENCRYPT=false
ENCRYPTION_KEY="your-secure-encryption-key"

# S3 upload settings
S3_BACKUP=false
S3_ENDPOINT="https://s3.amazonaws.com"
S3_BUCKET="minio-enterprise-backups"
S3_ACCESS_KEY="your-access-key"
S3_SECRET_KEY="your-secret-key"

# Database credentials
POSTGRES_DB="minio"
POSTGRES_USER="postgres"
```

### Backup Contents

Each backup includes:

1. **MinIO Data** (`minio/`)
   - Object storage data
   - Metadata files
   - Bucket configurations

2. **PostgreSQL Database** (`postgres/`)
   - Full database dump (custom format)
   - SQL export (for inspection)

3. **Redis State** (`redis/`)
   - RDB snapshot
   - All cached data

4. **Configuration Files** (`configs/`)
   - Docker Compose files
   - Configuration templates
   - Environment files (secrets excluded)

5. **Metadata** (`metadata/`)
   - Backup information (JSON)
   - Docker versions
   - Timestamp and checksums

### Backup Workflow

```
1. Pre-flight checks
   ├── Verify dependencies
   ├── Check Docker services
   └── Create backup directory

2. Component backups
   ├── Backup MinIO data
   ├── Backup PostgreSQL
   ├── Backup Redis
   └── Backup configs

3. Create metadata
   └── Generate backup-info.json

4. Post-processing
   ├── Compress (optional)
   ├── Encrypt (optional)
   └── Verify integrity

5. Storage
   ├── Save to local directory
   └── Upload to S3 (optional)

6. Cleanup
   └── Remove old backups (retention policy)
```

---

## Restore System

### Manual Restore

```bash
# Full restore
./scripts/restore/restore.sh /path/to/backup.tar.gz

# Verify only (no restore)
RESTORE_MODE=verify-only ./scripts/restore/restore.sh /path/to/backup.tar.gz

# Selective restore
RESTORE_MODE=selective ./scripts/restore/restore.sh /path/to/backup.tar.gz

# Restore encrypted backup
ENCRYPTION_KEY="your-key" ./scripts/restore/restore.sh /path/to/backup.tar.gz.enc

# Skip verification prompt
SKIP_VERIFICATION=true ./scripts/restore/restore.sh /path/to/backup.tar.gz

# Skip pre-restore snapshot
CREATE_SNAPSHOT=false ./scripts/restore/restore.sh /path/to/backup.tar.gz
```

### Restore Workflow

```
1. Validation
   ├── Validate backup file
   ├── Check dependencies
   └── Decrypt if encrypted

2. Extract and verify
   ├── Extract archive
   ├── Verify integrity
   └── Parse metadata

3. Pre-restore safety
   ├── User confirmation
   ├── Create snapshot
   └── Stop services

4. Component restore
   ├── Restore MinIO data
   ├── Restore PostgreSQL
   ├── Restore Redis
   └── Restore configs

5. Post-restore
   ├── Start services
   ├── Verify health
   └── Cleanup temp files
```

### Restore Modes

#### 1. Full Restore
Restores all components to the backup state.

```bash
./scripts/restore/restore.sh /path/to/backup.tar.gz
```

#### 2. Verify Only
Verifies backup integrity without making changes.

```bash
RESTORE_MODE=verify-only ./scripts/restore/restore.sh /path/to/backup.tar.gz
```

#### 3. Selective Restore
Allows restoring specific components (interactive).

```bash
RESTORE_MODE=selective ./scripts/restore/restore.sh /path/to/backup.tar.gz
```

---

## Configuration

### Environment Variables

#### Backup Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_TYPE` | `full` | Backup type: `full` or `incremental` |
| `BACKUP_DIR` | `/var/backups/minio-enterprise` | Backup storage directory |
| `RETENTION_DAYS` | `30` | Number of days to keep backups |
| `COMPRESS` | `true` | Enable gzip compression |
| `ENCRYPT` | `false` | Enable AES-256 encryption |
| `ENCRYPTION_KEY` | - | Encryption key (required if `ENCRYPT=true`) |
| `S3_BACKUP` | `false` | Upload to S3-compatible storage |
| `S3_ENDPOINT` | - | S3 endpoint URL |
| `S3_BUCKET` | - | S3 bucket name |
| `S3_ACCESS_KEY` | - | S3 access key |
| `S3_SECRET_KEY` | - | S3 secret key |

#### Restore Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `RESTORE_MODE` | `full` | Restore mode: `full`, `selective`, `verify-only` |
| `SKIP_VERIFICATION` | `false` | Skip user confirmation |
| `CREATE_SNAPSHOT` | `true` | Create pre-restore snapshot |
| `ENCRYPTION_KEY` | - | Decryption key for encrypted backups |

---

## Scheduling

### Using Cron

Create automated daily backups:

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * /path/to/MinIO/scripts/backup/backup.sh >> /var/log/minio-backup.log 2>&1

# Add weekly full backup on Sunday at 3 AM
0 3 * * 0 BACKUP_TYPE=full /path/to/MinIO/scripts/backup/backup.sh >> /var/log/minio-backup.log 2>&1

# Add daily incremental backup at 2 AM (Monday-Saturday)
0 2 * * 1-6 BACKUP_TYPE=incremental /path/to/MinIO/scripts/backup/backup.sh >> /var/log/minio-backup.log 2>&1
```

### Using Systemd Timers

1. Create service file: `/etc/systemd/system/minio-backup.service`

```ini
[Unit]
Description=MinIO Enterprise Backup
After=docker.service

[Service]
Type=oneshot
User=root
ExecStart=/path/to/MinIO/scripts/backup/backup.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

2. Create timer file: `/etc/systemd/system/minio-backup.timer`

```ini
[Unit]
Description=MinIO Enterprise Backup Timer
Requires=minio-backup.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

3. Enable and start timer:

```bash
systemctl daemon-reload
systemctl enable minio-backup.timer
systemctl start minio-backup.timer
systemctl status minio-backup.timer
```

---

## Best Practices

### Backup Strategy

1. **3-2-1 Rule**
   - Keep 3 copies of data
   - Store on 2 different media
   - Keep 1 copy offsite (S3)

2. **Backup Schedule**
   - **Daily**: Incremental backups
   - **Weekly**: Full backups
   - **Monthly**: Full backups (long-term retention)

3. **Retention Policy**
   - **Daily backups**: 7 days
   - **Weekly backups**: 4 weeks
   - **Monthly backups**: 12 months

4. **Testing**
   - Test restore procedures monthly
   - Verify backup integrity weekly
   - Document restore times (RTO)

### Security

1. **Encryption**
   - Always encrypt backups containing sensitive data
   - Store encryption keys securely (separate from backups)
   - Rotate encryption keys regularly

2. **Access Control**
   - Restrict backup directory permissions
   - Use dedicated service accounts
   - Audit backup access logs

3. **S3 Storage**
   - Use encryption at rest
   - Enable versioning
   - Implement lifecycle policies

### Performance

1. **Compression**
   - Enable compression for space savings
   - Use parallel compression for large backups
   - Monitor compression ratios

2. **Network**
   - Schedule S3 uploads during off-peak hours
   - Use bandwidth throttling if needed
   - Monitor upload success rates

3. **Storage**
   - Monitor disk space usage
   - Use fast storage for backup directory
   - Implement automatic cleanup

---

## Troubleshooting

### Common Issues

#### 1. Backup Fails: "Docker container not found"

**Cause**: Docker services not running

**Solution**:
```bash
# Check Docker services
docker ps -a

# Start services
docker-compose -f deployments/docker/docker-compose.yml up -d
```

#### 2. Backup Fails: "Permission denied"

**Cause**: Insufficient permissions for backup directory

**Solution**:
```bash
# Create backup directory with correct permissions
sudo mkdir -p /var/backups/minio-enterprise
sudo chown $(whoami):$(whoami) /var/backups/minio-enterprise
```

#### 3. Restore Fails: "Backup verification failed"

**Cause**: Corrupted or incomplete backup

**Solution**:
```bash
# Verify backup integrity
RESTORE_MODE=verify-only ./scripts/restore/restore.sh /path/to/backup.tar.gz

# Try a different backup
ls -lh /var/backups/minio-enterprise/
```

#### 4. Decryption Fails: "Bad decrypt"

**Cause**: Incorrect encryption key

**Solution**:
- Verify encryption key is correct
- Check for typos or whitespace
- Ensure key matches the one used for encryption

#### 5. S3 Upload Fails: "Connection timeout"

**Cause**: Network connectivity or incorrect S3 credentials

**Solution**:
```bash
# Test S3 connectivity
aws s3 ls --endpoint-url "$S3_ENDPOINT"

# Verify credentials
aws configure list
```

### Debug Mode

Enable verbose logging:

```bash
# Backup with debug output
set -x
./scripts/backup/backup.sh
set +x

# Restore with debug output
set -x
./scripts/restore/restore.sh /path/to/backup.tar.gz
set +x
```

### Log Files

Check log files for detailed information:

```bash
# Backup logs
tail -f /var/backups/minio-enterprise/backup.log

# Restore logs
tail -f /path/to/restore-YYYYMMDD_HHMMSS.log

# Error logs
cat /var/backups/minio-enterprise/backup-errors.log
```

---

## Recovery Procedures

### Disaster Recovery Scenarios

#### Scenario 1: Complete System Failure

**Recovery Steps**:

1. **Prepare New Environment**
   ```bash
   # Clone repository
   git clone <repo-url>
   cd MinIO

   # Deploy infrastructure
   docker-compose -f deployments/docker/docker-compose.production.yml up -d
   ```

2. **Restore from Backup**
   ```bash
   # Restore latest backup
   ./scripts/restore/restore.sh /path/to/latest-backup.tar.gz
   ```

3. **Verify System**
   ```bash
   # Check services
   docker ps

   # Test MinIO
   curl http://localhost:9000/health
   ```

**Expected RTO**: < 30 minutes

#### Scenario 2: Data Corruption

**Recovery Steps**:

1. **Stop Affected Services**
   ```bash
   docker-compose -f deployments/docker/docker-compose.yml stop
   ```

2. **Restore from Last Known Good Backup**
   ```bash
   # Find last good backup
   ls -lht /var/backups/minio-enterprise/ | head

   # Restore
   ./scripts/restore/restore.sh /path/to/good-backup.tar.gz
   ```

3. **Verify Data Integrity**
   ```bash
   # Run verification tests
   make test
   ```

**Expected RTO**: < 15 minutes

#### Scenario 3: Accidental Deletion

**Recovery Steps**:

1. **Identify Affected Component**
   - MinIO objects: Restore MinIO data only
   - Database records: Restore PostgreSQL only
   - Cache data: Restore Redis only

2. **Selective Restore**
   ```bash
   RESTORE_MODE=selective ./scripts/restore/restore.sh /path/to/backup.tar.gz
   ```

3. **Verify Restored Data**
   - Check affected objects/records
   - Run application tests

**Expected RTO**: < 10 minutes

### Recovery Time Objectives (RTO)

| Scenario | Target RTO | Backup Size | Network |
|----------|-----------|-------------|---------|
| Full System | 30 min | Any | Local |
| Full System (S3) | 60 min | < 100GB | Cloud |
| Selective Restore | 10 min | Any | Local |
| Verification Only | 5 min | Any | Local |

### Recovery Point Objectives (RPO)

| Backup Schedule | RPO | Data Loss |
|----------------|-----|-----------|
| Hourly | 1 hour | Minimal |
| Daily | 24 hours | Low |
| Weekly | 7 days | Moderate |

---

## Examples

### Example 1: Daily Automated Backup

```bash
#!/bin/bash
# /etc/cron.daily/minio-backup

# Set variables
export BACKUP_DIR="/mnt/backups/minio"
export RETENTION_DAYS=7
export COMPRESS=true
export ENCRYPT=true
export ENCRYPTION_KEY="$(cat /etc/minio-backup-key)"
export S3_BACKUP=true
export S3_ENDPOINT="https://s3.amazonaws.com"
export S3_BUCKET="minio-backups"
export S3_ACCESS_KEY="$(cat /etc/aws-access-key)"
export S3_SECRET_KEY="$(cat /etc/aws-secret-key)"

# Run backup
/opt/MinIO/scripts/backup/backup.sh

# Send notification
if [ $? -eq 0 ]; then
    echo "Backup successful" | mail -s "MinIO Backup Success" admin@example.com
else
    echo "Backup failed" | mail -s "MinIO Backup FAILED" admin@example.com
fi
```

### Example 2: Point-in-Time Recovery

```bash
#!/bin/bash
# Restore to specific point in time

# List available backups
ls -lht /var/backups/minio-enterprise/

# Select backup before incident
BACKUP_FILE="/var/backups/minio-enterprise/minio-backup-full-20240118_120000.tar.gz"

# Create safety snapshot
CREATE_SNAPSHOT=true

# Restore
./scripts/restore/restore.sh "$BACKUP_FILE"

# Verify
docker ps
curl http://localhost:9000/health
```

### Example 3: Encrypted Backup to S3

```bash
#!/bin/bash
# Secure backup with encryption and S3 upload

export BACKUP_TYPE="full"
export COMPRESS=true
export ENCRYPT=true
export ENCRYPTION_KEY="MySecureEncryptionKey123!"
export S3_BACKUP=true
export S3_ENDPOINT="https://s3.us-west-2.amazonaws.com"
export S3_BUCKET="minio-enterprise-backups"
export S3_ACCESS_KEY="AKIAIOSFODNN7EXAMPLE"
export S3_SECRET_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

./scripts/backup/backup.sh
```

---

## Support & Resources

### Getting Help

- **GitHub Issues**: [Report issues](https://github.com/your-org/MinIO/issues)
- **Documentation**: [Full documentation](../docs/)
- **Discussions**: [Community discussions](https://github.com/your-org/MinIO/discussions)

### Related Documentation

- [Deployment Guide](../../docs/guides/DEPLOYMENT.md)
- [Performance Guide](../../docs/guides/PERFORMANCE.md)
- [PRD (Product Requirements Document)](../../docs/PRD.md)

### Monitoring Backups

Use Grafana dashboards to monitor backup health:

- Backup success/failure rates
- Backup size trends
- Storage capacity
- S3 upload status

---

**Last Updated**: 2026-02-08
**Version**: 1.0.0
**Status**: Production Ready
