# MinIO Enterprise - Backup & Restore Documentation

Version: 1.0.0
Last Updated: 2026-02-08

## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Prerequisites](#prerequisites)
4. [Quick Start](#quick-start)
5. [Backup Operations](#backup-operations)
6. [Restore Operations](#restore-operations)
7. [Scheduling](#scheduling)
8. [Configuration](#configuration)
9. [Security Best Practices](#security-best-practices)
10. [Troubleshooting](#troubleshooting)
11. [Recovery Procedures](#recovery-procedures)

---

## Overview

The MinIO Enterprise Backup & Restore system provides automated, reliable, and secure backup solutions for MinIO deployments. The system supports full and incremental backups with encryption, compression, and flexible retention policies.

### What Gets Backed Up

- **PostgreSQL Database**: Complete database dumps with all schemas and data
- **Redis Data**: Redis snapshots for caching layer
- **MinIO Object Data**: All object storage data
- **Configuration Files**: System configuration and deployment files

---

## Features

### Backup Features

- ✅ **Full & Incremental Backups**: Reduce storage with incremental backups
- ✅ **Encryption**: AES-256-CBC encryption for data at rest
- ✅ **Compression**: Gzip compression to reduce backup size
- ✅ **Retention Policies**: Automatic deletion of old backups
- ✅ **Verification**: Integrity checks after backup completion
- ✅ **Manifest Files**: JSON metadata for each backup
- ✅ **Parallel Operations**: Fast backup execution
- ✅ **Logging**: Comprehensive logging for audit and debugging

### Restore Features

- ✅ **Component Selection**: Restore specific components or all
- ✅ **Verification Mode**: Test restore without applying changes
- ✅ **Rollback Support**: Automatic rollback on failure
- ✅ **Decryption**: Automatic decryption of encrypted backups
- ✅ **Decompression**: Automatic decompression handling
- ✅ **Safety Checks**: Confirmation prompts and pre-restore backups

---

## Prerequisites

### System Requirements

- **Operating System**: Linux (Ubuntu 20.04+, CentOS 8+, Debian 10+)
- **Disk Space**: At least 2x the size of your data for backups
- **Memory**: 2GB+ available RAM during backup operations

### Required Tools

```bash
# Ubuntu/Debian
sudo apt-get install -y postgresql-client redis-tools tar gzip openssl

# CentOS/RHEL
sudo yum install -y postgresql redis tar gzip openssl

# Check installation
pg_dump --version
redis-cli --version
tar --version
gzip --version
openssl version
```

### Permissions

- Read access to MinIO data directory
- Database credentials for PostgreSQL
- Write access to backup destination directory

---

## Quick Start

### 1. Basic Full Backup

```bash
# Navigate to backup directory
cd /path/to/MinIO/scripts/backup

# Make scripts executable
chmod +x backup.sh

# Set database password
export POSTGRES_PASSWORD="your-password"

# Run full backup
./backup.sh --type full --compress --retention 30
```

### 2. Verify Backup

```bash
# List backups
ls -lh /var/backups/minio/

# Check backup manifest
cat /var/backups/minio/backup_full_20240118_120000/manifest.json
```

### 3. Basic Restore

```bash
# Navigate to restore directory
cd /path/to/MinIO/scripts/restore

# Make script executable
chmod +x restore.sh

# Set database password
export POSTGRES_PASSWORD="your-password"

# Verify backup first
./restore.sh --backup /var/backups/minio/backup_full_20240118_120000 --verify

# Perform restore
./restore.sh --backup /var/backups/minio/backup_full_20240118_120000
```

---

## Backup Operations

### Full Backup

A full backup creates a complete copy of all data.

```bash
./backup.sh \
  --type full \
  --destination /var/backups/minio \
  --compress \
  --retention 30 \
  --verbose
```

**When to use**:
- Initial backup
- Weekly or monthly comprehensive backups
- Before major system changes
- After significant data modifications

### Incremental Backup

An incremental backup only backs up changes since the last full backup.

```bash
./backup.sh \
  --type incremental \
  --destination /var/backups/minio \
  --compress \
  --retention 7 \
  --verbose
```

**When to use**:
- Frequent backups (hourly, daily)
- Reducing backup time and storage
- Continuous data protection

**Note**: Incremental backups require a full backup as a base.

### Encrypted Backup

For sensitive data, enable encryption:

```bash
# Set encryption key (strong password)
export ENCRYPTION_KEY="your-strong-encryption-key-min-32-chars"

# Run encrypted backup
./backup.sh \
  --type full \
  --encrypt \
  --compress \
  --destination /var/backups/minio
```

**Important**: Store the encryption key securely! Loss of the key means loss of data.

### Configuration File

Create a configuration file for consistent backups:

```bash
# Copy example configuration
cp backup.conf /etc/minio/backup.conf

# Edit configuration
nano /etc/minio/backup.conf

# Use configuration
source /etc/minio/backup.conf
./backup.sh --type full
```

### Environment Variables

All settings can be configured via environment variables:

```bash
export BACKUP_DESTINATION=/backups/minio
export BACKUP_TYPE=full
export BACKUP_ENCRYPT=true
export BACKUP_COMPRESS=true
export BACKUP_RETENTION_DAYS=30
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=secret
export POSTGRES_DB=minio
export REDIS_HOST=localhost
export REDIS_PORT=6379
export MINIO_DATA_PATH=/data
export ENCRYPTION_KEY=your-secret-key

./backup.sh
```

---

## Restore Operations

### Full Restore

Restore all components from a backup:

```bash
./restore.sh \
  --backup /var/backups/minio/backup_full_20240118_120000 \
  --verbose
```

**Warning**: This will overwrite all existing data!

### Partial Restore

Restore specific components:

```bash
# Restore only PostgreSQL
./restore.sh \
  --backup /var/backups/minio/backup_full_20240118_120000 \
  --component postgres

# Restore only MinIO data
./restore.sh \
  --backup /var/backups/minio/backup_full_20240118_120000 \
  --component minio

# Restore only configurations
./restore.sh \
  --backup /var/backups/minio/backup_full_20240118_120000 \
  --component configs
```

### Verify Before Restore

Always verify backup integrity before restoring:

```bash
./restore.sh \
  --backup /var/backups/minio/backup_full_20240118_120000 \
  --verify
```

### Force Restore

Skip confirmation prompts (use with caution):

```bash
./restore.sh \
  --backup /var/backups/minio/backup_full_20240118_120000 \
  --force
```

### Restore from Encrypted Backup

```bash
# Set encryption key (must match backup encryption key)
export ENCRYPTION_KEY="your-encryption-key"

# Perform restore
./restore.sh \
  --backup /var/backups/minio/backup_full_20240118_120000
```

### Rollback After Failed Restore

If restore fails, use the automatic rollback:

```bash
# During restore, you'll be prompted to rollback on failure
# Rollback files are stored in: /tmp/minio_rollback_<timestamp>

# To manually rollback, use the restore script with the rollback directory
ls -la /tmp/minio_rollback_*
```

---

## Scheduling

### Using Cron

Setup automated backups with cron:

```bash
# Make scheduler executable
chmod +x schedule-backup.sh

# Setup default schedule (daily full, 6-hourly incremental)
./schedule-backup.sh

# Custom schedule
./schedule-backup.sh \
  --full-schedule "0 3 * * 0" \    # Weekly on Sunday at 3 AM
  --incr-schedule "0 */4 * * *"   # Every 4 hours

# View scheduled jobs
crontab -l

# Remove scheduled backups
./schedule-backup.sh --uninstall
```

### Using Systemd

Setup automated backups with systemd timers:

```bash
# Setup systemd timers (requires root)
sudo ./schedule-backup.sh --method systemd

# Check timer status
systemctl status minio-backup-full.timer
systemctl status minio-backup-incr.timer

# View next run times
systemctl list-timers | grep minio

# View backup logs
journalctl -u minio-backup-full.service
journalctl -u minio-backup-incr.service

# Remove timers
sudo ./schedule-backup.sh --method systemd --uninstall
```

### Recommended Schedules

**Small Deployments** (< 100GB data):
- Full backup: Daily at 2 AM
- Incremental: Every 6 hours
- Retention: 30 days full, 7 days incremental

**Medium Deployments** (100GB - 1TB):
- Full backup: Weekly on Sunday at 3 AM
- Incremental: Every 4 hours
- Retention: 90 days full, 14 days incremental

**Large Deployments** (> 1TB):
- Full backup: Monthly on 1st at 2 AM
- Weekly differential: Every Sunday at 3 AM
- Incremental: Every 2 hours
- Retention: 180 days full, 30 days weekly, 7 days incremental

---

## Configuration

### Backup Configuration File

Location: `backup.conf`

```bash
# Backup Settings
BACKUP_DESTINATION=/var/backups/minio
BACKUP_TYPE=full
BACKUP_ENCRYPT=false
BACKUP_COMPRESS=true
BACKUP_RETENTION_DAYS=30

# Database Settings
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_USER=postgres
POSTGRES_DB=minio

# Redis Settings
REDIS_HOST=localhost
REDIS_PORT=6379

# MinIO Settings
MINIO_DATA_PATH=/data

# Security (use environment variable)
# ENCRYPTION_KEY=set-via-environment
```

### Docker Compose Integration

Add backup service to your docker-compose.yml:

```yaml
services:
  backup:
    image: ubuntu:22.04
    container_name: minio-backup
    volumes:
      - ./scripts:/scripts:ro
      - backup-data:/backups
      - minio-data:/data:ro
    environment:
      - BACKUP_DESTINATION=/backups
      - POSTGRES_HOST=postgres
      - POSTGRES_USER=postgres
      - POSTGRES_DB=minio
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - REDIS_HOST=redis
      - MINIO_DATA_PATH=/data
    command: /scripts/backup/backup.sh --type full --compress

volumes:
  backup-data:
  minio-data:
```

---

## Security Best Practices

### Encryption Keys

```bash
# Generate strong encryption key
openssl rand -base64 32

# Store in environment variable (not in scripts!)
export ENCRYPTION_KEY="$(openssl rand -base64 32)"

# Or use secrets management
# AWS Secrets Manager, HashiCorp Vault, etc.
```

### Database Passwords

```bash
# Never hardcode passwords
# Use environment variables
export POSTGRES_PASSWORD="$(cat /run/secrets/postgres_password)"

# Or use .pgpass file
echo "localhost:5432:minio:postgres:password" > ~/.pgpass
chmod 600 ~/.pgpass
```

### Backup Storage

- Store backups on separate physical storage
- Use off-site backup storage for disaster recovery
- Implement access controls on backup directories
- Enable encryption at rest for backup storage
- Regular security audits of backup systems

### File Permissions

```bash
# Secure backup scripts
chmod 750 backup.sh restore.sh
chown root:backup backup.sh restore.sh

# Secure backup directory
chmod 700 /var/backups/minio
chown root:root /var/backups/minio

# Secure configuration files
chmod 600 backup.conf
chown root:root backup.conf
```

---

## Troubleshooting

### Common Issues

#### Issue: "Missing dependencies"

```bash
# Solution: Install required tools
sudo apt-get install -y postgresql-client redis-tools tar gzip openssl
```

#### Issue: "Permission denied"

```bash
# Solution: Check permissions
ls -la /var/backups/minio
ls -la /data

# Fix permissions
sudo chown -R $USER:$USER /var/backups/minio
```

#### Issue: "Backup directory creation failed"

```bash
# Solution: Create directory manually
sudo mkdir -p /var/backups/minio
sudo chown $USER:$USER /var/backups/minio
```

#### Issue: "PostgreSQL connection failed"

```bash
# Solution: Check connection
psql -h localhost -U postgres -d minio -c "SELECT 1;"

# Check environment variables
echo $POSTGRES_HOST
echo $POSTGRES_USER
echo $POSTGRES_DB
```

#### Issue: "Redis connection failed"

```bash
# Solution: Check Redis
redis-cli -h localhost ping

# Check if authentication is required
redis-cli -h localhost -a password ping
```

#### Issue: "Encryption failed"

```bash
# Solution: Check encryption key
echo $ENCRYPTION_KEY | wc -c  # Should be >= 32 characters

# Test encryption
echo "test" | openssl enc -aes-256-cbc -salt -pbkdf2 -k "$ENCRYPTION_KEY" | openssl enc -aes-256-cbc -d -pbkdf2 -k "$ENCRYPTION_KEY"
```

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
# Backup with verbose output
./backup.sh --type full --verbose

# Check log files
tail -f /var/backups/minio/backup_full_*/backup.log

# Restore with verbose output
./restore.sh --backup /path/to/backup --verbose

# Check restore log
cat /tmp/minio_restore_*/restore.log
```

### Verify Backup Integrity

```bash
# Check backup structure
ls -la /var/backups/minio/backup_full_20240118_120000/

# Verify manifest
cat /var/backups/minio/backup_full_20240118_120000/manifest.json | jq .

# Check backup size
du -sh /var/backups/minio/backup_full_20240118_120000/

# Test decompression
gunzip -t /var/backups/minio/backup_full_20240118_120000/postgres/database.sql.gz

# Test decryption (if encrypted)
openssl enc -aes-256-cbc -d -pbkdf2 -in file.enc -k "$ENCRYPTION_KEY" > /dev/null
```

---

## Recovery Procedures

### Complete System Recovery

**Recovery Time Objective (RTO)**: < 30 minutes
**Recovery Point Objective (RPO)**: Based on backup frequency

#### Step 1: Prepare System

```bash
# Install fresh MinIO system
# Follow installation guide

# Install backup tools
sudo apt-get install -y postgresql-client redis-tools tar gzip openssl

# Create restore directory
mkdir -p /tmp/minio-restore
cd /tmp/minio-restore
```

#### Step 2: Identify Backup

```bash
# List available backups
ls -la /var/backups/minio/

# Choose most recent successful backup
BACKUP_PATH=/var/backups/minio/backup_full_20240118_120000

# Verify backup
./restore.sh --backup $BACKUP_PATH --verify
```

#### Step 3: Perform Restore

```bash
# Set environment variables
export POSTGRES_PASSWORD="your-password"
export ENCRYPTION_KEY="your-encryption-key"  # If encrypted

# Stop services
docker-compose down

# Restore all components
./restore.sh --backup $BACKUP_PATH --force

# Verify restore
./restore.sh --backup $BACKUP_PATH --verify
```

#### Step 4: Start Services

```bash
# Start services
docker-compose up -d

# Check health
curl http://localhost:9000/minio/health/live

# Verify data
# Test uploads and downloads
```

#### Step 5: Verify Recovery

```bash
# Check PostgreSQL
psql -h localhost -U postgres -d minio -c "\dt"

# Check Redis
redis-cli -h localhost ping
redis-cli -h localhost dbsize

# Check MinIO data
ls -la /data/
```

### Partial Recovery

#### Recover Only Database

```bash
# Restore PostgreSQL only
./restore.sh \
  --backup /var/backups/minio/backup_full_20240118_120000 \
  --component postgres \
  --force

# Restart services
docker-compose restart minio
```

#### Recover Only Object Data

```bash
# Stop MinIO
docker-compose stop minio

# Restore object data
./restore.sh \
  --backup /var/backups/minio/backup_full_20240118_120000 \
  --component minio \
  --force

# Start MinIO
docker-compose start minio
```

### Point-in-Time Recovery

For precise recovery to a specific time:

```bash
# List all backups sorted by time
ls -lt /var/backups/minio/ | grep backup_

# Identify backup closest to desired time
# Example: Restore to 2024-01-18 14:30

# Full backup from 2024-01-18 02:00
FULL_BACKUP=/var/backups/minio/backup_full_20240118_020000

# Incremental backup from 2024-01-18 14:00
INCR_BACKUP=/var/backups/minio/backup_incremental_20240118_140000

# Restore full backup first
./restore.sh --backup $FULL_BACKUP --force

# Then restore incremental
./restore.sh --backup $INCR_BACKUP --force
```

### Disaster Recovery

For complete infrastructure failure:

1. **Deploy new infrastructure**
2. **Install MinIO Enterprise from scratch**
3. **Copy backups from off-site storage**
4. **Restore using procedures above**
5. **Verify all services**
6. **Update DNS/load balancers**

---

## Best Practices

### Backup Strategy

1. **3-2-1 Rule**:
   - 3 copies of data
   - 2 different storage media
   - 1 copy off-site

2. **Regular Testing**:
   - Test restores monthly
   - Verify backup integrity weekly
   - Document recovery procedures

3. **Monitoring**:
   - Alert on backup failures
   - Track backup sizes and durations
   - Monitor backup storage usage

4. **Documentation**:
   - Keep recovery procedures updated
   - Document all configuration changes
   - Maintain backup inventory

### Performance Optimization

```bash
# Run backups during low-traffic periods
# Use compression to reduce size
# Consider parallel backups for large datasets
# Use incremental backups to reduce time
# Store backups on fast storage (SSD/NVMe)
```

---

## Support & Resources

### Getting Help

- **Documentation**: `/path/to/MinIO/docs/`
- **GitHub Issues**: https://github.com/your-org/MinIO/issues
- **Backup Logs**: `/var/backups/minio/*/backup.log`
- **Restore Logs**: `/tmp/minio_restore_*/restore.log`

### Related Documentation

- [MinIO Performance Guide](../../docs/guides/PERFORMANCE.md)
- [MinIO Deployment Guide](../../docs/guides/DEPLOYMENT.md)
- [MinIO Security Guide](../../docs/)

---

**Document Version**: 1.0.0
**Last Updated**: 2026-02-08
**Maintainer**: MinIO Enterprise Team
