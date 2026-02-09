# MinIO Enterprise Backup & Restore System

Comprehensive backup and restore solution for MinIO Enterprise with support for full/incremental backups, encryption, compression, S3 storage, and automated scheduling.

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Backup Strategies](#backup-strategies)
- [Restore Procedures](#restore-procedures)
- [Scheduling](#scheduling)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Features

### Backup Features
- ✅ **Full & Incremental Backups**: Optimize storage with incremental backups
- ✅ **Multi-Component Support**: PostgreSQL, Redis, MinIO data, and configuration files
- ✅ **Compression**: Reduce backup size with gzip compression
- ✅ **Encryption**: AES-256-CBC encryption for sensitive data
- ✅ **S3 Storage**: Remote backup to S3-compatible storage
- ✅ **Verification**: Automatic integrity checks after backup
- ✅ **Retention Policies**: Automatic cleanup of old backups
- ✅ **Metadata Tracking**: Complete backup metadata in JSON format
- ✅ **Parallel Processing**: Multi-threaded backup operations
- ✅ **Detailed Logging**: Comprehensive logs for audit and troubleshooting

### Restore Features
- ✅ **Selective Restore**: Restore individual components or complete system
- ✅ **Rollback Support**: Automatic rollback point creation before restore
- ✅ **Verification**: Post-restore integrity checks
- ✅ **Interactive Selection**: Browse and select backups interactively
- ✅ **Service Management**: Automatic service stop/start during restore
- ✅ **Decryption**: Automatic decryption of encrypted backups

---

## Architecture

### Backup Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Backup Process                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Pre-flight Checks                                       │
│     ├─ Check dependencies                                   │
│     ├─ Verify service availability                          │
│     └─ Validate configuration                               │
│                                                              │
│  2. Create Backup Directory                                 │
│     └─ /var/backups/minio/{full|incremental}/backup_DATE   │
│                                                              │
│  3. Component Backups (Parallel)                            │
│     ├─ PostgreSQL → pg_dump (custom format)                 │
│     ├─ Redis → BGSAVE + RDB copy                            │
│     ├─ MinIO Data → rsync with hardlinks                    │
│     └─ Config Files → rsync                                 │
│                                                              │
│  4. Post-Processing                                         │
│     ├─ Compression (gzip)                                   │
│     ├─ Encryption (AES-256)                                 │
│     ├─ Verification                                         │
│     └─ Metadata creation                                    │
│                                                              │
│  5. Remote Storage (Optional)                               │
│     └─ Upload to S3                                         │
│                                                              │
│  6. Cleanup                                                 │
│     └─ Delete backups older than retention period           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
/var/backups/minio/
├── full/                          # Full backups
│   ├── backup_20260209_020000/
│   │   ├── postgresql_minio.sql.gz
│   │   ├── redis_dump.rdb.gz
│   │   ├── minio_data/
│   │   ├── config/
│   │   └── metadata.json
│   └── backup_20260210_020000/
│       └── ...
├── incremental/                   # Incremental backups
│   ├── backup_20260209_080000/
│   └── ...
├── rollback/                      # Rollback points
│   └── restore_20260209_100000/
├── logs/                          # Backup logs
│   ├── backup_20260209_020000.log
│   └── ...
└── metadata/                      # Backup indexes
```

---

## Quick Start

### 1. Install Dependencies

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y rsync postgresql-client redis-tools gzip tar openssl

# CentOS/RHEL
sudo yum install -y rsync postgresql redis gzip tar openssl
```

### 2. Configure Backup Settings

```bash
# Copy and edit configuration
cp scripts/backup/backup.conf scripts/backup/backup.local.conf
nano scripts/backup/backup.local.conf
```

### 3. Run Your First Backup

```bash
# Full backup
sudo ./scripts/backup/backup.sh full

# Incremental backup
sudo ./scripts/backup/backup.sh incremental
```

### 4. Restore from Backup

```bash
# Interactive restore (lists available backups)
sudo ./scripts/restore/restore.sh

# Restore specific backup
sudo ./scripts/restore/restore.sh /var/backups/minio/full/backup_20260209_020000

# Restore latest backup
sudo ./scripts/restore/restore.sh latest
```

---

## Installation

### Step 1: Set Up Backup User

```bash
# Create dedicated backup user
sudo useradd -r -s /bin/bash -d /var/backups/minio -m minio-backup

# Grant necessary permissions
sudo usermod -aG postgres,redis minio-backup  # Add to required groups
```

### Step 2: Configure Permissions

```bash
# Set up backup directory
sudo mkdir -p /var/backups/minio
sudo chown minio-backup:minio-backup /var/backups/minio
sudo chmod 750 /var/backups/minio

# Set up log directory
sudo mkdir -p /var/log/minio
sudo chown minio-backup:minio-backup /var/log/minio
```

### Step 3: Make Scripts Executable

```bash
sudo chmod +x scripts/backup/backup.sh
sudo chmod +x scripts/restore/restore.sh
```

### Step 4: Configure Database Access

For PostgreSQL:
```bash
# Create .pgpass file for passwordless access
echo "localhost:5432:minio:minio:YOUR_PASSWORD" > ~/.pgpass
chmod 600 ~/.pgpass
```

For Redis:
```bash
# Set Redis password in environment or config file
export REDIS_PASSWORD="your_redis_password"
```

---

## Configuration

### Configuration File (`backup.conf`)

```bash
# Backup Storage Location
BACKUP_DIR="/var/backups/minio"

# MinIO Configuration
MINIO_DATA_DIR="/var/lib/minio"

# PostgreSQL Configuration
POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"
POSTGRES_DB="minio"
POSTGRES_USER="minio"
POSTGRES_PASSWORD=""  # Use environment variable

# Redis Configuration
REDIS_HOST="localhost"
REDIS_PORT="6379"
REDIS_PASSWORD=""  # Use environment variable

# Backup Settings
RETENTION_DAYS=30
COMPRESSION=true
ENCRYPTION=false
ENCRYPTION_KEY=""

# S3 Storage
S3_STORAGE=false
S3_BUCKET=""
S3_ENDPOINT=""
S3_ACCESS_KEY=""
S3_SECRET_KEY=""

# Performance
PARALLEL_JOBS=4
VERIFY_BACKUP=true
```

### Environment Variables

For security, sensitive values should be set via environment variables:

```bash
export PGPASSWORD="your_postgres_password"
export REDIS_PASSWORD="your_redis_password"
export ENCRYPTION_KEY="your_encryption_key"
export S3_ACCESS_KEY="your_s3_access_key"
export S3_SECRET_KEY="your_s3_secret_key"
```

### Docker Environment

If using Docker, you can pass environment variables to the backup container:

```bash
docker run --rm \
  -v /var/backups/minio:/var/backups/minio \
  -e PGPASSWORD="$PGPASSWORD" \
  -e REDIS_PASSWORD="$REDIS_PASSWORD" \
  minio-enterprise:latest \
  /scripts/backup/backup.sh full
```

---

## Usage

### Backup Commands

#### Full Backup
```bash
# Run full backup
./scripts/backup/backup.sh full

# With custom configuration
CONFIG_FILE=/path/to/custom.conf ./scripts/backup/backup.sh full

# With environment variables
BACKUP_DIR=/custom/backup/dir ./scripts/backup/backup.sh full
```

#### Incremental Backup
```bash
# Run incremental backup (uses hardlinks to previous full backup)
./scripts/backup/backup.sh incremental
```

#### Backup with Encryption
```bash
# Enable encryption in config or via environment
ENCRYPTION=true ENCRYPTION_KEY="your_secret_key" ./scripts/backup/backup.sh full
```

#### Backup to S3
```bash
# Configure S3 settings in backup.conf, then run:
S3_STORAGE=true ./scripts/backup/backup.sh full
```

### Restore Commands

#### Interactive Restore
```bash
# List backups and select interactively
./scripts/restore/restore.sh
```

#### Restore Specific Backup
```bash
# Restore from specific backup directory
./scripts/restore/restore.sh /var/backups/minio/full/backup_20260209_020000
```

#### Restore Latest Backup
```bash
# Automatically select and restore the most recent backup
./scripts/restore/restore.sh latest
```

#### Restore Without Rollback
```bash
# Skip creating rollback point (not recommended)
CREATE_ROLLBACK=false ./scripts/restore/restore.sh latest
```

### List Available Backups

```bash
# View all available backups
ls -lh /var/backups/minio/full/
ls -lh /var/backups/minio/incremental/

# View backup metadata
cat /var/backups/minio/full/backup_20260209_020000/metadata.json
```

---

## Backup Strategies

### Strategy 1: Daily Full + Hourly Incremental

Best for: Production systems with moderate data changes

```bash
# Cron schedule
0 2 * * * /scripts/backup/backup.sh full       # Daily at 2 AM
0 * * * * /scripts/backup/backup.sh incremental # Every hour
```

**Pros:**
- Fast recovery (latest incremental + daily full)
- Minimal storage (incremental uses hardlinks)
- Hourly recovery points

**Cons:**
- Higher backup frequency
- More backup jobs to manage

### Strategy 2: Weekly Full + Daily Incremental

Best for: Cost-conscious deployments with weekly backup windows

```bash
# Cron schedule
0 3 * * 0 /scripts/backup/backup.sh full       # Sunday at 3 AM
0 2 * * 1-6 /scripts/backup/backup.sh incremental # Mon-Sat at 2 AM
```

**Pros:**
- Lower storage requirements
- Fewer full backups
- Daily recovery points

**Cons:**
- Longer recovery time (1 full + 6 incrementals max)

### Strategy 3: Continuous Incremental

Best for: High-change systems requiring frequent backups

```bash
# Cron schedule
0 2 * * 0 /scripts/backup/backup.sh full       # Weekly full
0 */4 * * * /scripts/backup/backup.sh incremental # Every 4 hours
```

**Pros:**
- Maximum data protection
- Minimal data loss window
- Fine-grained recovery points

**Cons:**
- Highest storage usage
- More backups to manage

### Strategy 4: 3-2-1 Backup Rule

Best for: Critical production systems

**3 copies of data:**
- Original data
- Local backup
- Remote backup (S3)

**2 different media:**
- Local disk
- S3 storage

**1 offsite copy:**
- S3 in different region

```bash
# Configuration
S3_STORAGE=true
S3_BUCKET="minio-backups"
S3_ENDPOINT="https://s3.us-west-1.amazonaws.com"
RETENTION_DAYS=30

# Full backup with S3 upload
./scripts/backup/backup.sh full
```

---

## Restore Procedures

### Standard Restore Procedure

1. **Identify Backup**
   ```bash
   ./scripts/restore/restore.sh
   # Select backup from list
   ```

2. **Review Backup Metadata**
   ```bash
   cat /var/backups/minio/full/backup_TIMESTAMP/metadata.json
   ```

3. **Stop Services** (automatic)
   - Script stops MinIO services
   - PostgreSQL and Redis remain running

4. **Create Rollback Point** (automatic)
   - Current state backed up before restore
   - Allows rollback if restore fails

5. **Restore Components**
   - PostgreSQL database
   - Redis data
   - MinIO objects
   - Configuration files

6. **Start Services** (automatic)
   - MinIO services restarted

7. **Verification** (automatic)
   - Database connectivity
   - Redis connectivity
   - Data integrity

### Emergency Restore Procedure

For critical failures requiring immediate restore:

```bash
# 1. Identify latest backup
LATEST=$(ls -t /var/backups/minio/full/ | head -n 1)

# 2. Stop services manually
sudo systemctl stop minio
# OR
docker-compose -f deployments/docker/docker-compose.production.yml stop

# 3. Restore with verification disabled for speed
VERIFY_RESTORE=false ./scripts/restore/restore.sh /var/backups/minio/full/$LATEST

# 4. Verify manually after restore
curl http://localhost:9000/health
```

### Partial Restore

To restore only specific components:

#### PostgreSQL Only
```bash
# Extract and restore PostgreSQL backup manually
cd /var/backups/minio/full/backup_TIMESTAMP
gunzip -c postgresql_minio.sql.gz | pg_restore -d minio
```

#### MinIO Data Only
```bash
# Stop MinIO
sudo systemctl stop minio

# Restore data
rsync -avz /var/backups/minio/full/backup_TIMESTAMP/minio_data/ /var/lib/minio/

# Start MinIO
sudo systemctl start minio
```

#### Configuration Only
```bash
rsync -avz /var/backups/minio/full/backup_TIMESTAMP/config/ /etc/minio/
```

### Rollback After Failed Restore

If a restore fails or causes issues:

```bash
# Find rollback point created before restore
ls -lh /var/backups/minio/rollback/

# Restore from rollback point
./scripts/restore/restore.sh /var/backups/minio/rollback/restore_TIMESTAMP
```

---

## Scheduling

### Using Cron

#### Install Cron Jobs

```bash
# Option 1: Install for root user
sudo crontab scripts/backup/backup.cron

# Option 2: Install for backup user
sudo crontab -u minio-backup scripts/backup/backup.cron

# Option 3: Edit crontab directly
sudo crontab -e
# Then paste the contents of backup.cron
```

#### Verify Cron Jobs

```bash
# List installed cron jobs
sudo crontab -l

# Check cron logs
sudo tail -f /var/log/syslog | grep CRON
# OR
sudo tail -f /var/log/cron
```

#### Monitor Backup Jobs

```bash
# View backup logs
tail -f /var/log/minio/backup-cron.log

# View specific backup log
tail -f /var/backups/minio/logs/backup_20260209_020000.log
```

### Using Systemd Timers

Alternatively, use systemd timers for more control:

#### Create Systemd Service

```bash
# /etc/systemd/system/minio-backup.service
[Unit]
Description=MinIO Enterprise Backup
After=postgresql.service redis.service

[Service]
Type=oneshot
User=minio-backup
ExecStart=/home/runner/work/MinIO/MinIO/scripts/backup/backup.sh full
StandardOutput=journal
StandardError=journal
```

#### Create Systemd Timer

```bash
# /etc/systemd/system/minio-backup.timer
[Unit]
Description=MinIO Enterprise Backup Timer

[Timer]
OnCalendar=daily
OnCalendar=02:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

#### Enable and Start Timer

```bash
sudo systemctl daemon-reload
sudo systemctl enable minio-backup.timer
sudo systemctl start minio-backup.timer

# Check timer status
sudo systemctl status minio-backup.timer
sudo systemctl list-timers
```

---

## Verification

### Manual Backup Verification

```bash
# Check backup directory exists
ls -lh /var/backups/minio/full/backup_TIMESTAMP/

# Verify PostgreSQL backup
gunzip -c /var/backups/minio/full/backup_TIMESTAMP/postgresql_minio.sql.gz | head -n 20

# Verify MinIO data
du -sh /var/backups/minio/full/backup_TIMESTAMP/minio_data/

# Verify metadata
jq . /var/backups/minio/full/backup_TIMESTAMP/metadata.json

# Test gzip integrity
find /var/backups/minio/full/backup_TIMESTAMP/ -name "*.gz" -exec gzip -t {} \;
```

### Automated Verification Script

Create a verification script:

```bash
#!/bin/bash
# scripts/backup/verify-backup.sh

BACKUP_DIR=$1
ERRORS=0

echo "Verifying backup: $BACKUP_DIR"

# Check PostgreSQL backup
if [ -f "$BACKUP_DIR/postgresql_minio.sql.gz" ]; then
    gzip -t "$BACKUP_DIR/postgresql_minio.sql.gz" || ERRORS=$((ERRORS+1))
fi

# Check MinIO data
if [ -d "$BACKUP_DIR/minio_data" ]; then
    FILE_COUNT=$(find "$BACKUP_DIR/minio_data" -type f | wc -l)
    echo "MinIO files: $FILE_COUNT"
else
    ERRORS=$((ERRORS+1))
fi

# Check metadata
if [ ! -f "$BACKUP_DIR/metadata.json" ]; then
    ERRORS=$((ERRORS+1))
fi

if [ $ERRORS -eq 0 ]; then
    echo "Verification PASSED"
    exit 0
else
    echo "Verification FAILED ($ERRORS errors)"
    exit 1
fi
```

### Restore Test

Periodically test restore procedure:

```bash
# Create test environment
docker-compose -f deployments/docker/docker-compose.test.yml up -d

# Restore to test environment
POSTGRES_HOST=test-postgres \
REDIS_HOST=test-redis \
MINIO_DATA_DIR=/tmp/minio-test \
./scripts/restore/restore.sh latest

# Verify test environment
curl http://test-minio:9000/health

# Cleanup
docker-compose -f deployments/docker/docker-compose.test.yml down -v
```

---

## Troubleshooting

### Common Issues

#### Issue: "Permission Denied"

**Symptoms:**
```
Error: Cannot write to /var/backups/minio: Permission denied
```

**Solution:**
```bash
# Fix permissions
sudo chown -R minio-backup:minio-backup /var/backups/minio
sudo chmod -R 750 /var/backups/minio

# OR run backup as root
sudo ./scripts/backup/backup.sh full
```

#### Issue: "PostgreSQL Connection Failed"

**Symptoms:**
```
Error: PostgreSQL is not accessible at localhost:5432
```

**Solutions:**
```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Test connection manually
psql -h localhost -U minio -d minio

# Verify pg_hba.conf allows connections
sudo nano /etc/postgresql/*/main/pg_hba.conf

# Add line:
# host    minio    minio    127.0.0.1/32    md5

# Reload PostgreSQL
sudo systemctl reload postgresql
```

#### Issue: "Disk Space Full"

**Symptoms:**
```
Error: No space left on device
```

**Solutions:**
```bash
# Check disk space
df -h /var/backups/minio

# Clean old backups manually
rm -rf /var/backups/minio/full/backup_OLDEST

# Reduce retention period
# Edit backup.conf: RETENTION_DAYS=7

# Enable compression
# Edit backup.conf: COMPRESSION=true

# Move backups to larger disk
sudo mv /var/backups/minio /mnt/large-disk/backups
sudo ln -s /mnt/large-disk/backups /var/backups/minio
```

#### Issue: "Backup Too Slow"

**Symptoms:**
```
Backup taking hours to complete
```

**Solutions:**
```bash
# Increase parallel jobs
# Edit backup.conf: PARALLEL_JOBS=8

# Use incremental backups instead of full
./scripts/backup/backup.sh incremental

# Exclude temporary files
# The script already excludes *.tmp and *.lock

# Use faster storage for backup directory
# Move to SSD: /var/backups/minio -> /mnt/ssd/backups
```

#### Issue: "Restore Failed - Services Won't Start"

**Symptoms:**
```
Error: MinIO service failed to start after restore
```

**Solutions:**
```bash
# Check logs
sudo journalctl -u minio -n 50

# Verify data permissions
sudo chown -R minio:minio /var/lib/minio
sudo chmod -R 755 /var/lib/minio

# Check configuration
sudo cat /etc/minio/config.json

# Restore from rollback point
./scripts/restore/restore.sh /var/backups/minio/rollback/restore_TIMESTAMP
```

### Debugging

Enable verbose logging:

```bash
# Run backup with verbose output
bash -x ./scripts/backup/backup.sh full 2>&1 | tee /tmp/backup-debug.log

# Check logs
tail -f /var/backups/minio/logs/backup_TIMESTAMP.log

# Check system logs
sudo tail -f /var/log/syslog
```

---

## Best Practices

### 1. Security

- **Never store passwords in backup.conf** - use environment variables or .pgpass
- **Enable encryption for sensitive data** - set `ENCRYPTION=true`
- **Restrict backup directory permissions** - `chmod 750 /var/backups/minio`
- **Use dedicated backup user** - don't run backups as root
- **Rotate encryption keys regularly** - implement key rotation policy
- **Test restore in isolated environment** - don't restore to production for testing

### 2. Storage Management

- **Use incremental backups** - reduce storage with hardlinks
- **Enable compression** - set `COMPRESSION=true`
- **Configure retention policies** - set appropriate `RETENTION_DAYS`
- **Monitor disk space** - set up alerts for low disk space
- **Use S3 for long-term storage** - offload old backups to S3
- **Implement 3-2-1 backup rule** - 3 copies, 2 media types, 1 offsite

### 3. Reliability

- **Test backups regularly** - schedule monthly restore tests
- **Verify backup integrity** - keep `VERIFY_BACKUP=true`
- **Monitor backup jobs** - set up alerting for failed backups
- **Keep backup metadata** - don't delete metadata.json files
- **Document custom configurations** - maintain runbook for your setup
- **Create rollback points** - keep `CREATE_ROLLBACK=true`

### 4. Performance

- **Adjust parallel jobs** - tune `PARALLEL_JOBS` based on CPU cores
- **Schedule during low-traffic periods** - run backups during off-peak hours
- **Use local storage for speed** - avoid NFS/CIFS for backup destination
- **Optimize PostgreSQL dumps** - use custom format for faster restore
- **Monitor backup duration** - track and optimize slow backups
- **Use incremental for frequent backups** - full backups only when needed

### 5. Compliance

- **Retain backups per regulations** - configure `RETENTION_DAYS` appropriately
- **Encrypt backups for compliance** - enable encryption for GDPR/HIPAA
- **Maintain audit logs** - keep backup logs for compliance audits
- **Test disaster recovery** - document and test DR procedures
- **Document backup procedures** - maintain up-to-date documentation
- **Review backup access** - audit who can access backups

### 6. Monitoring

Set up monitoring for:
- Backup success/failure rates
- Backup duration trends
- Backup size trends
- Disk space utilization
- Restore test results
- Service availability during backups

Example Prometheus alerts:

```yaml
groups:
  - name: backup_alerts
    rules:
      - alert: BackupFailed
        expr: minio_backup_last_success_timestamp < (time() - 86400)
        annotations:
          summary: "MinIO backup has not completed successfully in 24 hours"

      - alert: BackupDiskSpaceLow
        expr: node_filesystem_avail_bytes{mountpoint="/var/backups/minio"} < 10737418240
        annotations:
          summary: "Backup disk space below 10GB"
```

---

## Recovery Time Objective (RTO) and Recovery Point Objective (RPO)

### RTO (Recovery Time Objective)

Expected restore times:

| Backup Size | Restore Time | Components |
|-------------|--------------|------------|
| < 10 GB | 5-10 minutes | All |
| 10-100 GB | 15-30 minutes | All |
| 100-500 GB | 30-90 minutes | All |
| > 500 GB | 2+ hours | All |

### RPO (Recovery Point Objective)

Maximum acceptable data loss:

| Backup Strategy | RPO | Use Case |
|-----------------|-----|----------|
| Hourly incremental | 1 hour | Production systems |
| Every 4 hours | 4 hours | Standard workloads |
| Daily backups | 24 hours | Development systems |
| Weekly backups | 7 days | Archive systems |

---

## Support & Resources

- **Documentation**: [MinIO Docs](https://min.io/docs)
- **GitHub Issues**: [Report Issues](https://github.com/abiolaogu/MinIO/issues)
- **Backup Logs**: `/var/backups/minio/logs/`
- **System Logs**: `/var/log/syslog` or `journalctl`

---

## Appendix

### Backup Script Exit Codes

| Exit Code | Meaning |
|-----------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Missing dependencies |
| 3 | Service unavailable |
| 4 | Backup verification failed |
| 5 | Insufficient disk space |

### Backup File Formats

- **PostgreSQL**: Custom format (`.sql`), compressed with gzip
- **Redis**: RDB binary format (`.rdb`), compressed with gzip
- **MinIO Data**: Raw files, rsync with hardlinks
- **Metadata**: JSON format

### Required Permissions

Backup user needs:
- Read access to `/var/lib/minio`
- Write access to `/var/backups/minio`
- PostgreSQL connection permissions
- Redis connection permissions
- Ability to stop/start MinIO service (optional)

---

**Version**: 1.0.0
**Last Updated**: 2026-02-09
**Maintainer**: MinIO Enterprise Team
