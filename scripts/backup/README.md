# MinIO Enterprise Backup & Restore System

Comprehensive backup and restore automation for MinIO Enterprise stack including PostgreSQL, Redis, MinIO data volumes, and configuration files.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Backup Operations](#backup-operations)
- [Restore Operations](#restore-operations)
- [Scheduling](#scheduling)
- [Monitoring & Alerts](#monitoring--alerts)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Overview

The MinIO Enterprise Backup & Restore system provides automated, reliable backup and disaster recovery capabilities for production deployments.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Backup Architecture                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │ MinIO    │  │PostgreSQL│  │  Redis   │  │  Config  │  │
│  │ Data     │  │ Database │  │  State   │  │  Files   │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  │
│       │             │             │             │         │
│       └─────────────┴─────────────┴─────────────┘         │
│                         │                                  │
│                    ┌────▼────┐                            │
│                    │ Backup  │                            │
│                    │ Script  │                            │
│                    └────┬────┘                            │
│                         │                                  │
│       ┌─────────────────┼─────────────────┐              │
│       │                 │                 │              │
│   ┌───▼───┐        ┌───▼───┐        ┌───▼───┐          │
│   │ Local │        │  S3   │        │ Email │          │
│   │ Disk  │        │Remote │        │ Alert │          │
│   └───────┘        └───────┘        └───────┘          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Features

### Backup Features
- ✅ **Full & Incremental Backups**: Support for both backup types
- ✅ **Multi-Component**: PostgreSQL, Redis, MinIO volumes, configuration files
- ✅ **Compression**: Configurable compression (gzip, bzip2, xz)
- ✅ **Encryption**: AES-256 encryption support
- ✅ **Verification**: Automatic backup integrity checks
- ✅ **Remote Storage**: S3-compatible remote backup storage
- ✅ **Retention Policy**: Automatic cleanup of old backups
- ✅ **Notifications**: Email and webhook notifications
- ✅ **Metadata Tracking**: JSON metadata for each backup
- ✅ **Parallel Processing**: Multi-threaded backup operations

### Restore Features
- ✅ **Selective Restore**: Restore individual components
- ✅ **Dry-Run Mode**: Test restore without making changes
- ✅ **Pre-Restore Backup**: Automatic backup before restore
- ✅ **Verification**: Post-restore health checks
- ✅ **Rollback Support**: Revert to previous state if restore fails
- ✅ **Detailed Reporting**: Comprehensive restore reports

---

## Prerequisites

### Required Tools
- Docker & Docker Compose
- Bash 4.0+
- tar, gzip
- jq (for JSON parsing)

### Optional Tools
- openssl (for encryption)
- aws-cli (for S3 remote backups)
- bzip2, xz (for alternative compression)
- mail command (for email notifications)

### Permissions
- Docker access (ability to execute docker commands)
- Read/write access to backup directory
- Access to Docker volumes

---

## Quick Start

### 1. Configure Backup Settings

Edit `backup.conf`:

```bash
# Basic configuration
BACKUP_ROOT_DIR="/var/backups/minio-enterprise"
BACKUP_RETENTION_DAYS="30"
BACKUP_COMPRESSION="true"

# Enable components
BACKUP_MINIO_DATA="true"
BACKUP_POSTGRESQL="true"
BACKUP_REDIS="true"
BACKUP_CONFIG_FILES="true"
```

### 2. Run First Backup

```bash
# Make scripts executable
chmod +x scripts/backup/backup.sh
chmod +x scripts/restore/restore.sh

# Run backup
./scripts/backup/backup.sh
```

### 3. Verify Backup

```bash
# Check backup directory
ls -lh /var/backups/minio-enterprise/

# View backup report
cat /var/backups/minio-enterprise/<timestamp>/backup_report.txt
```

### 4. Test Restore (Dry-Run)

```bash
# Dry-run restore
./scripts/restore/restore.sh --dry-run /var/backups/minio-enterprise/<timestamp>
```

---

## Configuration

### Configuration File: `backup.conf`

#### Backup Settings

```bash
# Root directory for all backups
BACKUP_ROOT_DIR="/var/backups/minio-enterprise"

# Number of days to retain backups
BACKUP_RETENTION_DAYS="30"

# Enable compression
BACKUP_COMPRESSION="true"
COMPRESSION_TOOL="gzip"        # Options: gzip, bzip2, xz
COMPRESSION_LEVEL="6"          # 1-9 (higher = better compression, slower)

# Enable encryption
BACKUP_ENCRYPTION="false"
ENCRYPTION_KEY_FILE=""
ENCRYPTION_ALGORITHM="aes-256-cbc"

# Verification
BACKUP_VERIFICATION="true"
BACKUP_INTEGRITY_CHECK="true"
```

#### Component Selection

```bash
# Select components to backup
BACKUP_MINIO_DATA="true"
BACKUP_POSTGRESQL="true"
BACKUP_REDIS="true"
BACKUP_CONFIG_FILES="true"
BACKUP_MONITORING_DATA="false"
```

#### Docker Settings

```bash
DOCKER_COMPOSE_FILE="./deployments/docker/docker-compose.production.yml"
POSTGRES_CONTAINER="postgres"
REDIS_CONTAINER="redis"
MINIO_CONTAINERS="minio1 minio2 minio3 minio4"
```

#### PostgreSQL Settings

```bash
POSTGRES_DB="minio_enterprise"
POSTGRES_USER="minio"
POSTGRES_PASSWORD="minio_secure_password"
```

#### S3 Remote Backup

```bash
S3_BACKUP_ENABLED="false"
S3_BUCKET="my-backup-bucket"
S3_ENDPOINT="https://s3.amazonaws.com"  # Optional for non-AWS S3
S3_ACCESS_KEY="YOUR_ACCESS_KEY"
S3_SECRET_KEY="YOUR_SECRET_KEY"
```

#### Notifications

```bash
# Email notifications
ENABLE_EMAIL_NOTIFICATION="false"
EMAIL_RECIPIENT="admin@example.com"
EMAIL_SUBJECT_PREFIX="[MinIO Backup]"

# Health check ping
BACKUP_HEALTH_CHECK_URL="https://hc-ping.com/your-check-id"
```

#### Performance Tuning

```bash
# Parallel processing
PARALLEL_JOBS="4"

# Logging
LOG_DIR="./logs/backup"
LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR
```

---

## Backup Operations

### Manual Backup

```bash
# Full backup
./scripts/backup/backup.sh

# Custom configuration
CONFIG_FILE=/path/to/custom.conf ./scripts/backup/backup.sh

# Custom backup location
BACKUP_ROOT_DIR=/mnt/external/backups ./scripts/backup/backup.sh
```

### Backup Components

#### PostgreSQL Backup
- Uses `pg_dump` with custom format
- Compressed with level 9
- Includes all database objects
- Verifies backup with `pg_restore --list`

#### Redis Backup
- Triggers `BGSAVE` command
- Backs up RDB snapshot
- Backs up AOF file (if enabled)
- Waits for save completion

#### MinIO Data Backup
- Backs up all data volumes
- Creates tar archives
- Supports compression
- Parallel volume processing

#### Configuration Backup
- Backs up `configs/` directory
- Backs up `deployments/` directory
- Includes environment files
- Excludes logs and temporary files

### Backup Output

Each backup creates:

```
/var/backups/minio-enterprise/20240118_120000/
├── backup_metadata.json          # Backup metadata
├── backup_report.txt             # Human-readable report
├── postgresql_20240118_120000.sql # PostgreSQL dump
├── redis/                        # Redis data
│   ├── dump.rdb
│   └── appendonly.aof
├── minio_data/                   # MinIO volumes
│   ├── minio1-data.tar.gz
│   ├── minio2-data.tar.gz
│   ├── minio3-data.tar.gz
│   └── minio4-data.tar.gz
└── config_20240118_120000.tar.gz # Configuration files
```

### Backup Metadata

`backup_metadata.json` contains:

```json
{
    "backup_timestamp": "20240118_120000",
    "backup_date": "2024-01-18T12:00:00Z",
    "backup_type": "full",
    "components": {
        "minio_data": true,
        "postgresql": true,
        "redis": true,
        "config_files": true
    },
    "settings": {
        "compression": "true",
        "compression_tool": "gzip",
        "encryption": "false",
        "verification": "true"
    },
    "hostname": "minio-prod-01",
    "script_version": "1.0.0"
}
```

---

## Restore Operations

### Restore Command

```bash
# Full restore
./scripts/restore/restore.sh /var/backups/minio-enterprise/20240118_120000

# Dry-run (test without making changes)
./scripts/restore/restore.sh --dry-run /var/backups/minio-enterprise/20240118_120000

# Selective restore
./scripts/restore/restore.sh --postgresql-only /var/backups/minio-enterprise/20240118_120000
./scripts/restore/restore.sh --redis-only /var/backups/minio-enterprise/20240118_120000
./scripts/restore/restore.sh --minio-only /var/backups/minio-enterprise/20240118_120000
./scripts/restore/restore.sh --config-only /var/backups/minio-enterprise/20240118_120000

# Skip pre-restore backup
./scripts/restore/restore.sh --no-pre-backup /var/backups/minio-enterprise/20240118_120000

# Skip verification
./scripts/restore/restore.sh --skip-verification /var/backups/minio-enterprise/20240118_120000
```

### Restore Options

| Option | Description |
|--------|-------------|
| `-d, --dry-run` | Perform dry-run (no actual changes) |
| `-s, --skip-verification` | Skip backup verification step |
| `-n, --no-pre-backup` | Skip pre-restore backup creation |
| `-p, --postgresql-only` | Restore only PostgreSQL database |
| `-r, --redis-only` | Restore only Redis data |
| `-m, --minio-only` | Restore only MinIO data volumes |
| `-c, --config-only` | Restore only configuration files |
| `-h, --help` | Show help message |

### Restore Process

1. **Verification**: Validates backup integrity
2. **Pre-Restore Backup**: Creates safety backup (optional)
3. **Stop Services**: Gracefully stops Docker services
4. **Restore Components**: Restores selected components
5. **Start Services**: Restarts all services
6. **Verification**: Checks service health
7. **Report**: Generates restore report

### Restore Verification

The restore script automatically verifies:
- PostgreSQL database accessibility
- Redis connectivity
- MinIO node health
- Service startup status

### Recovery Time Objective (RTO)

Expected restore times:
- **PostgreSQL**: 2-5 minutes (100GB database)
- **Redis**: 1-2 minutes (4GB data)
- **MinIO Data**: 10-30 minutes (1TB data)
- **Configuration**: <1 minute
- **Total**: ~15-40 minutes for complete system

---

## Scheduling

### Cron Setup

Add to crontab (`crontab -e`):

```bash
# Daily backup at 2 AM
0 2 * * * /path/to/MinIO/scripts/backup/backup.sh >> /var/log/minio-backup.log 2>&1

# Weekly full backup on Sunday at 1 AM
0 1 * * 0 ENABLE_FULL_BACKUP=true /path/to/MinIO/scripts/backup/backup.sh

# Incremental backup every 6 hours
0 */6 * * * ENABLE_INCREMENTAL_BACKUP=true /path/to/MinIO/scripts/backup/backup.sh
```

### Systemd Timer

Create `/etc/systemd/system/minio-backup.service`:

```ini
[Unit]
Description=MinIO Enterprise Backup
After=docker.service

[Service]
Type=oneshot
ExecStart=/path/to/MinIO/scripts/backup/backup.sh
User=root
StandardOutput=journal
StandardError=journal
```

Create `/etc/systemd/system/minio-backup.timer`:

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

Enable timer:

```bash
systemctl daemon-reload
systemctl enable minio-backup.timer
systemctl start minio-backup.timer
systemctl list-timers
```

---

## Monitoring & Alerts

### Backup Monitoring

#### Log Files

```bash
# View backup logs
tail -f logs/backup/backup_*.log

# View restore logs
tail -f logs/restore/restore_*.log
```

#### Health Check Integration

Configure healthchecks.io or similar:

```bash
BACKUP_HEALTH_CHECK_URL="https://hc-ping.com/your-check-id"
```

On successful backup, the script will ping this URL.

#### Email Notifications

```bash
ENABLE_EMAIL_NOTIFICATION="true"
EMAIL_RECIPIENT="admin@example.com"
```

Notifications sent on:
- Backup completion (success/failure)
- Backup errors
- Cleanup operations

### Monitoring Backup Health

#### Check Backup Age

```bash
# Find most recent backup
ls -lt /var/backups/minio-enterprise/ | head -5

# Alert if no backup in 24 hours
find /var/backups/minio-enterprise/ -maxdepth 1 -type d -mtime -1 | wc -l
```

#### Check Backup Size

```bash
# Monitor backup size growth
du -sh /var/backups/minio-enterprise/*/
```

#### Verify Backup Integrity

```bash
# Test backup can be read
tar -tzf /var/backups/minio-enterprise/20240118_120000/config_*.tar.gz > /dev/null
```

---

## Troubleshooting

### Common Issues

#### Issue: Backup Script Fails with "Permission Denied"

**Solution**:
```bash
# Make script executable
chmod +x scripts/backup/backup.sh
chmod +x scripts/restore/restore.sh

# Check Docker permissions
sudo usermod -aG docker $USER
```

#### Issue: "No space left on device"

**Solution**:
```bash
# Check disk space
df -h /var/backups

# Enable automatic cleanup
AUTO_CLEANUP_OLD_BACKUPS="true"
BACKUP_RETENTION_DAYS="7"

# Manual cleanup
find /var/backups/minio-enterprise -type d -mtime +7 -exec rm -rf {} \;
```

#### Issue: PostgreSQL backup fails

**Solution**:
```bash
# Check PostgreSQL container status
docker exec postgres psql -U minio -d minio_enterprise -c "SELECT 1;"

# Check credentials
echo $POSTGRES_PASSWORD

# View PostgreSQL logs
docker logs postgres
```

#### Issue: Redis BGSAVE timeout

**Solution**:
```bash
# Check Redis is responding
docker exec redis redis-cli PING

# Check Redis save status
docker exec redis redis-cli INFO persistence

# Increase timeout in backup script (line ~250)
max_wait=120  # Increase from 60
```

#### Issue: S3 upload fails

**Solution**:
```bash
# Test AWS CLI configuration
aws s3 ls s3://${S3_BUCKET}/ --endpoint-url ${S3_ENDPOINT}

# Check credentials
echo $S3_ACCESS_KEY

# Test connectivity
curl -I ${S3_ENDPOINT}
```

### Debug Mode

Enable debug logging:

```bash
LOG_LEVEL="DEBUG" ./scripts/backup/backup.sh
```

### Backup Verification

Manually verify backup:

```bash
# Check metadata
cat /var/backups/minio-enterprise/20240118_120000/backup_metadata.json | jq '.'

# Test PostgreSQL backup
docker exec postgres pg_restore --list /var/backups/minio-enterprise/20240118_120000/postgresql_*.sql

# List MinIO volumes
tar -tzf /var/backups/minio-enterprise/20240118_120000/minio_data/minio1-data.tar.gz | head -20
```

---

## Best Practices

### Backup Strategy

1. **3-2-1 Rule**: 3 copies, 2 different media, 1 offsite
   ```bash
   # Local backup
   BACKUP_ROOT_DIR="/var/backups/minio-enterprise"

   # Remote S3 backup
   S3_BACKUP_ENABLED="true"
   ```

2. **Regular Testing**: Test restores monthly
   ```bash
   # Monthly restore test (dry-run)
   ./scripts/restore/restore.sh --dry-run /var/backups/minio-enterprise/latest
   ```

3. **Retention Policy**: Balance storage costs and recovery needs
   ```bash
   # Keep daily backups for 7 days
   BACKUP_RETENTION_DAYS="7"

   # Keep weekly backups for 4 weeks
   # Keep monthly backups for 12 months
   ```

4. **Encryption**: Encrypt sensitive backups
   ```bash
   BACKUP_ENCRYPTION="true"
   ENCRYPTION_KEY_FILE="/secure/location/backup.key"
   ```

### Performance Optimization

1. **Parallel Processing**: Utilize multiple CPUs
   ```bash
   PARALLEL_JOBS="4"  # Match CPU core count
   ```

2. **Compression**: Balance speed vs size
   ```bash
   COMPRESSION_TOOL="gzip"    # Fast, moderate compression
   COMPRESSION_LEVEL="6"       # Default level
   ```

3. **Incremental Backups**: Reduce backup time
   ```bash
   # Full backup weekly
   ENABLE_FULL_BACKUP="true"

   # Incremental daily
   ENABLE_INCREMENTAL_BACKUP="true"
   ```

### Security

1. **Protect Credentials**: Use environment variables
   ```bash
   # Don't hardcode credentials in backup.conf
   POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
   ```

2. **Secure Backup Location**: Restrict access
   ```bash
   chmod 700 /var/backups/minio-enterprise
   chown root:root /var/backups/minio-enterprise
   ```

3. **Encryption Keys**: Secure key storage
   ```bash
   # Generate encryption key
   openssl rand -base64 32 > /secure/location/backup.key
   chmod 400 /secure/location/backup.key
   ```

### Monitoring

1. **Alert on Failures**: Set up monitoring
   ```bash
   ENABLE_EMAIL_NOTIFICATION="true"
   BACKUP_HEALTH_CHECK_URL="https://hc-ping.com/your-check-id"
   ```

2. **Track Metrics**:
   - Backup duration
   - Backup size
   - Success rate
   - Age of last successful backup

3. **Log Retention**: Keep logs for auditing
   ```bash
   # Rotate logs weekly
   find logs/backup -name "*.log" -mtime +7 -delete
   ```

---

## Advanced Configuration

### Custom Backup Script

Create custom backup wrapper:

```bash
#!/bin/bash
# custom-backup.sh

# Pre-backup tasks
echo "Starting custom backup..."

# Run backup
/path/to/scripts/backup/backup.sh

# Post-backup tasks
if [ $? -eq 0 ]; then
    echo "Backup successful, running post-backup tasks..."
    # Upload to additional locations
    # Update monitoring dashboard
    # Send Slack notification
fi
```

### Backup Hooks

Add hooks in `backup.sh`:

```bash
# After successful backup (add to main function)
if [ -f "/path/to/post-backup-hook.sh" ]; then
    /path/to/post-backup-hook.sh "${BACKUP_DIR}"
fi
```

### Multi-Region Backups

Configure multiple S3 regions:

```bash
# Primary region backup
S3_BACKUP_ENABLED="true"
S3_BUCKET="backups-us-east-1"
S3_ENDPOINT="https://s3.us-east-1.amazonaws.com"

# Secondary region (add to script)
aws s3 sync /var/backups/minio-enterprise/ s3://backups-eu-west-1/
```

---

## Support & Contributing

### Getting Help

- **Documentation**: This README and inline script comments
- **Issues**: [GitHub Issues](https://github.com/abiolaogu/MinIO/issues)
- **Discussions**: [GitHub Discussions](https://github.com/abiolaogu/MinIO/discussions)

### Contributing

Contributions welcome! Areas for improvement:
- Additional compression formats
- Cloud provider integrations
- Backup verification tools
- Performance optimizations

---

## Appendix

### Script Files

| File | Description |
|------|-------------|
| `scripts/backup/backup.sh` | Main backup script |
| `scripts/backup/backup.conf` | Configuration file |
| `scripts/restore/restore.sh` | Main restore script |
| `scripts/backup/README.md` | This documentation |

### Dependencies

```bash
# Check all dependencies
command -v docker >/dev/null || echo "docker not found"
command -v docker-compose >/dev/null || echo "docker-compose not found"
command -v tar >/dev/null || echo "tar not found"
command -v gzip >/dev/null || echo "gzip not found"
command -v jq >/dev/null || echo "jq not found"
```

### Backup Size Estimates

| Component | Typical Size | Compressed Size |
|-----------|-------------|-----------------|
| PostgreSQL (100GB) | 100GB | 20-30GB |
| Redis (4GB) | 4GB | 2-3GB |
| MinIO Data (1TB) | 1TB | 600-800GB |
| Configuration | 10MB | 2-3MB |

### RTO/RPO Targets

| Metric | Target | Achieved |
|--------|--------|----------|
| **RPO** (Recovery Point Objective) | 24 hours | 1-6 hours |
| **RTO** (Recovery Time Objective) | 1 hour | 15-40 minutes |

---

**Last Updated**: 2026-02-08
**Version**: 1.0.0
**Maintained By**: MinIO Enterprise DevOps Team
