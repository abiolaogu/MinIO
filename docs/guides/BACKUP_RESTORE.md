# MinIO Enterprise Backup & Restore Guide

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Quick Start](#quick-start)
4. [Backup Operations](#backup-operations)
5. [Restore Operations](#restore-operations)
6. [Automated Scheduling](#automated-scheduling)
7. [Configuration Reference](#configuration-reference)
8. [Recovery Procedures](#recovery-procedures)
9. [Best Practices](#best-practices)
10. [Troubleshooting](#troubleshooting)

---

## Overview

The MinIO Enterprise Backup & Restore system provides automated, reliable, and secure backup and recovery capabilities for production deployments.

### Key Features

- **Full and Incremental Backups**: Support for both complete and differential backups
- **Multi-Component Backup**: Backs up MinIO data, PostgreSQL, Redis, and configurations
- **Encryption & Compression**: AES-256 encryption and gzip compression
- **Remote Storage**: S3-compatible storage integration for off-site backups
- **Automated Retention**: Configurable retention policies with automatic cleanup
- **Verification**: Built-in integrity checking with checksums
- **Rollback Support**: Automatic snapshot creation before restore operations
- **Recovery Time Objective (RTO)**: < 30 minutes for complete system restore

### Components Backed Up

| Component | Description | Backup Method |
|-----------|-------------|---------------|
| **MinIO Data** | Object storage volumes (4 nodes) | Docker volume snapshots |
| **PostgreSQL** | Metadata database | pg_dump SQL dumps |
| **Redis** | Cache state and session data | RDB snapshots |
| **Configuration** | Config files and deployment manifests | File copy |

---

## Architecture

### Backup Flow

```
┌─────────────────┐
│  Backup Script  │
└────────┬────────┘
         │
         ├──────> 1. Pre-flight Checks
         │        ├─ Verify dependencies
         │        ├─ Check disk space
         │        └─ Validate configuration
         │
         ├──────> 2. Data Collection
         │        ├─ MinIO volumes (tar.gz)
         │        ├─ PostgreSQL dump (SQL)
         │        ├─ Redis snapshot (RDB)
         │        └─ Config files
         │
         ├──────> 3. Post-processing
         │        ├─ Create metadata
         │        ├─ Generate checksums
         │        ├─ Compress backup
         │        └─ Encrypt backup
         │
         ├──────> 4. Remote Backup (optional)
         │        └─ Upload to S3
         │
         └──────> 5. Cleanup
                  └─ Remove old backups
```

### Restore Flow

```
┌─────────────────┐
│ Restore Script  │
└────────┬────────┘
         │
         ├──────> 1. Pre-restore Checks
         │        ├─ Validate backup file
         │        ├─ Verify checksums
         │        ├─ Check services
         │        └─ Create snapshot
         │
         ├──────> 2. Service Shutdown
         │        └─ Stop all services
         │
         ├──────> 3. Data Restoration
         │        ├─ Restore MinIO volumes
         │        ├─ Restore PostgreSQL
         │        ├─ Restore Redis
         │        └─ Restore configs
         │
         ├──────> 4. Service Startup
         │        └─ Start all services
         │
         └──────> 5. Verification
                  ├─ Health checks
                  └─ Connectivity tests
```

---

## Quick Start

### Prerequisites

```bash
# Install required tools
sudo apt-get update
sudo apt-get install -y docker docker-compose postgresql-client redis-tools openssl

# Verify installation
docker --version
docker-compose --version
pg_dump --version
redis-cli --version
```

### Basic Backup

```bash
# 1. Navigate to backup directory
cd /path/to/MinIO/scripts/backup

# 2. Configure backup settings (first time only)
cp backup.conf.example backup.conf
nano backup.conf

# 3. Run backup
chmod +x backup.sh
sudo ./backup.sh

# Output:
# ✓ Checking dependencies...
# ✓ Backing up MinIO object data...
# ✓ Backing up PostgreSQL database...
# ✓ Backing up Redis data...
# ✓ Configuration backup completed
# ✓ Backup completed successfully!
# Backup location: /var/backups/minio-enterprise/minio-backup-full-20240118_120000.tar.gz.enc
```

### Basic Restore

```bash
# 1. Navigate to restore directory
cd /path/to/MinIO/scripts/restore

# 2. Run restore (with confirmation prompt)
chmod +x restore.sh
sudo ./restore.sh /var/backups/minio-enterprise/minio-backup-full-20240118_120000.tar.gz.enc

# 3. Confirm when prompted
# WARNING: This will restore the system from backup and overwrite current data
# Are you sure you want to continue? (yes/NO): yes

# Output:
# ✓ Creating pre-restore snapshot...
# ➜ Stopping MinIO services...
# ➜ Restoring MinIO object data...
# ➜ Restoring PostgreSQL database...
# ➜ Restoring Redis data...
# ➜ Starting MinIO services...
# ✓ Restore completed successfully!
```

---

## Backup Operations

### Full Backup

Creates a complete backup of all components.

```bash
# Using default configuration
sudo ./backup.sh

# Or with environment variables
BACKUP_TYPE=full \
BACKUP_DIR=/custom/path \
COMPRESSION=true \
ENCRYPTION=true \
ENCRYPTION_KEY="your-secure-key" \
sudo -E ./backup.sh
```

**When to use**:
- Initial backup
- Weekly/monthly comprehensive backups
- Before major system upgrades
- Disaster recovery planning

**Size**: Typically 10-100 GB depending on data volume

**Duration**: 5-30 minutes depending on data size

### Incremental Backup

Backs up only changes since the last backup.

```bash
# Set backup type to incremental
BACKUP_TYPE=incremental sudo -E ./backup.sh
```

**When to use**:
- Daily backups
- Frequent backup schedules
- Limited storage space

**Size**: Typically 1-10 GB (10-20% of full backup)

**Duration**: 1-5 minutes

### Encrypted Backup

Protects backup data with AES-256 encryption.

```bash
# Generate encryption key
ENCRYPTION_KEY=$(openssl rand -base64 32)
echo "Store this key securely: $ENCRYPTION_KEY"

# Create encrypted backup
ENCRYPTION=true \
ENCRYPTION_KEY="$ENCRYPTION_KEY" \
sudo -E ./backup.sh
```

**Important**: Store the encryption key securely! Without it, backups cannot be restored.

### Remote Backup to S3

Automatically uploads backups to S3-compatible storage.

```bash
# Configure S3 settings
cat >> backup.conf <<EOF
S3_BACKUP=true
S3_BUCKET="my-minio-backups"
S3_ENDPOINT="https://s3.amazonaws.com"
EOF

# Set AWS credentials
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"

# Run backup (will automatically upload)
sudo -E ./backup.sh
```

### Component-Specific Backup

Backup individual components instead of full system.

```bash
# Backup only PostgreSQL
docker-compose -f deployments/docker/docker-compose.production.yml exec -T postgres \
  pg_dump -U minio -d minio_enterprise > postgres_backup_$(date +%Y%m%d).sql

# Backup only Redis
docker-compose -f deployments/docker/docker-compose.production.yml exec -T redis \
  redis-cli BGSAVE

# Backup only MinIO volumes
docker run --rm -v minio1-data:/data -v $(pwd):/backup alpine \
  tar czf /backup/minio1-data.tar.gz -C /data .
```

---

## Restore Operations

### Full System Restore

Restore complete system from backup.

```bash
# Interactive restore (with confirmation)
sudo ./restore.sh /path/to/backup.tar.gz.enc

# Non-interactive restore (for automation)
FORCE_RESTORE=true \
ENCRYPTION_KEY="your-encryption-key" \
sudo -E ./restore.sh /path/to/backup.tar.gz.enc --force
```

### Partial Restore

Restore specific components only.

```bash
# Restore only PostgreSQL
sudo ./restore.sh /path/to/backup.tar.gz --components postgresql

# Restore PostgreSQL and Redis
sudo ./restore.sh /path/to/backup.tar.gz --components postgresql,redis

# Restore MinIO data only
sudo ./restore.sh /path/to/backup.tar.gz --components minio
```

### Restore from S3

Download and restore from remote backup.

```bash
# Download from S3
aws s3 cp s3://my-minio-backups/minio-backup-full-20240118_120000.tar.gz.enc ./

# Restore downloaded backup
sudo ./restore.sh ./minio-backup-full-20240118_120000.tar.gz.enc
```

### Point-in-Time Recovery

Restore system to specific point in time.

```bash
# List available backups
ls -lh /var/backups/minio-enterprise/

# Choose backup from desired time
sudo ./restore.sh /var/backups/minio-enterprise/minio-backup-full-20240115_030000.tar.gz.enc
```

### Restore with Verification

Extra validation steps before and after restore.

```bash
# Enable verification (default)
VERIFY_BEFORE_RESTORE=true sudo -E ./restore.sh /path/to/backup.tar.gz

# Skip verification (faster, but risky)
sudo ./restore.sh /path/to/backup.tar.gz --no-verify
```

### Rollback Failed Restore

Automatic rollback if restore fails.

```bash
# Restore with automatic snapshot
sudo ./restore.sh /path/to/backup.tar.gz

# If restore fails, system automatically rolls back to snapshot
# Manual rollback (if needed)
sudo ./restore.sh /var/backups/minio-snapshots/snapshot-20240118_120000.tar.gz --no-snapshot
```

---

## Automated Scheduling

### Cron Setup

Schedule automated backups using cron.

```bash
# Edit crontab
sudo crontab -e

# Add backup schedules

# Full backup: Daily at 2 AM
0 2 * * * cd /path/to/MinIO/scripts/backup && BACKUP_TYPE=full ./backup.sh >> /var/log/minio-backup-cron.log 2>&1

# Incremental backup: Every 6 hours
0 */6 * * * cd /path/to/MinIO/scripts/backup && BACKUP_TYPE=incremental ./backup.sh >> /var/log/minio-backup-cron.log 2>&1

# Weekly full backup: Sunday at 1 AM
0 1 * * 0 cd /path/to/MinIO/scripts/backup && BACKUP_TYPE=full ENCRYPTION=true ./backup.sh >> /var/log/minio-backup-cron.log 2>&1

# Cleanup old backups: Daily at 3 AM
0 3 * * * find /var/backups/minio-enterprise -type f -mtime +30 -delete
```

### Systemd Timer

Alternative to cron using systemd timers.

```bash
# Create service file
sudo tee /etc/systemd/system/minio-backup.service > /dev/null <<EOF
[Unit]
Description=MinIO Enterprise Backup
After=docker.service

[Service]
Type=oneshot
User=root
WorkingDirectory=/path/to/MinIO/scripts/backup
Environment="BACKUP_TYPE=full"
Environment="ENCRYPTION=true"
ExecStart=/path/to/MinIO/scripts/backup/backup.sh
StandardOutput=append:/var/log/minio-backup.log
StandardError=append:/var/log/minio-backup.log
EOF

# Create timer file
sudo tee /etc/systemd/system/minio-backup.timer > /dev/null <<EOF
[Unit]
Description=MinIO Enterprise Backup Timer
Requires=minio-backup.service

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start timer
sudo systemctl daemon-reload
sudo systemctl enable minio-backup.timer
sudo systemctl start minio-backup.timer

# Check status
sudo systemctl status minio-backup.timer
sudo systemctl list-timers --all
```

### Monitoring Backups

Set up monitoring for backup success/failure.

```bash
# Add email notification to backup.conf
NOTIFICATION_EMAIL="admin@example.com"

# Configure mail server (using msmtp)
sudo apt-get install msmtp msmtp-mta mailutils

# Configure msmtp
sudo tee /etc/msmtprc > /dev/null <<EOF
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           smtp.gmail.com
port           587
from           backup@example.com
user           backup@example.com
password       your-app-password
EOF

# Test notification
echo "Test backup notification" | mail -s "MinIO Backup Test" admin@example.com
```

---

## Configuration Reference

### backup.conf

```bash
# Backup directory (local storage location)
BACKUP_DIR="/var/backups/minio-enterprise"

# Backup type: "full" or "incremental"
BACKUP_TYPE="full"

# Retention policy (days)
RETENTION_DAYS=30

# Compression (true/false)
COMPRESSION=true

# Encryption (true/false)
ENCRYPTION=true
ENCRYPTION_KEY=""  # Generate with: openssl rand -base64 32

# S3 backup (optional)
S3_BACKUP=false
S3_BUCKET=""
S3_ENDPOINT=""  # For non-AWS S3

# Notification email (optional)
NOTIFICATION_EMAIL=""

# Log file location
LOG_FILE="/var/log/minio-backup.log"

# Database credentials
POSTGRES_USER="minio"
POSTGRES_DB="minio_enterprise"
POSTGRES_PASSWORD="minio_secure_password"
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `BACKUP_DIR` | Backup storage directory | `/var/backups/minio-enterprise` |
| `BACKUP_TYPE` | Backup type (full/incremental) | `full` |
| `RETENTION_DAYS` | Days to keep backups | `30` |
| `COMPRESSION` | Enable compression | `true` |
| `ENCRYPTION` | Enable encryption | `true` |
| `ENCRYPTION_KEY` | Encryption password | (none) |
| `S3_BACKUP` | Enable S3 upload | `false` |
| `RESTORE_MODE` | Restore mode (full/partial) | `full` |
| `VERIFY_BEFORE_RESTORE` | Verify backup integrity | `true` |
| `CREATE_SNAPSHOT` | Create pre-restore snapshot | `true` |
| `FORCE_RESTORE` | Skip confirmation prompts | `false` |

---

## Recovery Procedures

### Disaster Recovery Scenario

**Scenario**: Complete server failure, need to restore on new hardware.

```bash
# 1. Install fresh MinIO Enterprise system
git clone <repo-url>
cd MinIO

# 2. Install dependencies
sudo apt-get update
sudo apt-get install -y docker docker-compose postgresql-client redis-tools

# 3. Download backup from S3
aws s3 cp s3://my-minio-backups/minio-backup-full-20240118_120000.tar.gz.enc ./

# 4. Restore system
cd scripts/restore
ENCRYPTION_KEY="your-encryption-key" \
sudo -E ./restore.sh ../../minio-backup-full-20240118_120000.tar.gz.enc --force

# 5. Verify services
docker-compose -f deployments/docker/docker-compose.production.yml ps

# 6. Test functionality
curl http://localhost:9000/minio/health/live
```

### Data Corruption Recovery

**Scenario**: PostgreSQL database corrupted, need to restore only database.

```bash
# 1. Stop services
docker-compose -f deployments/docker/docker-compose.production.yml stop

# 2. Restore only PostgreSQL
cd scripts/restore
sudo ./restore.sh /var/backups/latest-backup.tar.gz --components postgresql

# 3. Start services
docker-compose -f deployments/docker/docker-compose.production.yml start

# 4. Verify database
docker-compose -f deployments/docker/docker-compose.production.yml exec postgres \
  psql -U minio -d minio_enterprise -c "SELECT COUNT(*) FROM tenants;"
```

### Accidental Deletion Recovery

**Scenario**: User accidentally deleted objects, need to restore specific data.

```bash
# 1. Find backup before deletion
ls -lh /var/backups/minio-enterprise/ | grep "$(date -d '2 days ago' +%Y%m%d)"

# 2. Extract specific volume from backup
mkdir /tmp/recovery
tar xzf /var/backups/minio-enterprise/minio-backup-full-20240116_020000.tar.gz -C /tmp/recovery

# 3. Extract specific files from volume backup
cd /tmp/recovery/minio-backup-full-20240116_020000/minio
tar xzf minio1-data.tar.gz -C /tmp/recovery/extracted

# 4. Manually copy needed files back
# Use MinIO client (mc) to upload recovered objects
mc cp /tmp/recovery/extracted/path/to/object myminio/bucket/object
```

### Multi-Region Failover

**Scenario**: Primary region failed, failover to backup region.

```bash
# 1. Download latest backup from S3 in secondary region
aws s3 cp s3://my-minio-backups/minio-backup-full-20240118_020000.tar.gz.enc ./ \
  --region us-west-2

# 2. Deploy MinIO in secondary region
cd /path/to/MinIO
docker-compose -f deployments/docker/docker-compose.production.yml up -d

# 3. Restore from backup
cd scripts/restore
ENCRYPTION_KEY="your-key" sudo -E ./restore.sh ../minio-backup-full-20240118_020000.tar.gz.enc --force

# 4. Update DNS to point to secondary region
# Update Route53 or your DNS provider

# 5. Verify services
curl http://secondary-region-endpoint:9000/minio/health/live
```

---

## Best Practices

### Backup Strategy

1. **3-2-1 Rule**: Keep 3 copies of data, on 2 different media types, with 1 offsite
   ```bash
   # Local backup
   BACKUP_DIR=/var/backups/minio ./backup.sh

   # NAS backup
   BACKUP_DIR=/mnt/nas/backups ./backup.sh

   # S3 backup
   S3_BACKUP=true ./backup.sh
   ```

2. **Backup Schedule**:
   - **Full backup**: Daily during off-peak hours (e.g., 2 AM)
   - **Incremental backup**: Every 4-6 hours
   - **Long-term backup**: Weekly full backup kept for 90+ days

3. **Retention Policy**:
   ```bash
   # Daily backups: 30 days
   # Weekly backups: 90 days
   # Monthly backups: 1 year
   # Yearly backups: 7 years (compliance)
   ```

### Security

1. **Always encrypt backups**:
   ```bash
   ENCRYPTION=true
   ENCRYPTION_KEY=$(openssl rand -base64 32)
   ```

2. **Store encryption keys securely**:
   - Use a password manager (1Password, LastPass)
   - Use HashiCorp Vault
   - Use AWS Secrets Manager
   - Never commit to version control

3. **Restrict backup file permissions**:
   ```bash
   chmod 600 /var/backups/minio-enterprise/*.tar.gz.enc
   chown root:root /var/backups/minio-enterprise/
   ```

4. **Use separate credentials for backups**:
   ```bash
   # Create read-only backup user for PostgreSQL
   docker-compose exec postgres psql -U postgres -c \
     "CREATE USER backup_user WITH PASSWORD 'secure_password';"
   docker-compose exec postgres psql -U postgres -c \
     "GRANT SELECT ON ALL TABLES IN SCHEMA public TO backup_user;"
   ```

### Testing

1. **Test restores regularly** (monthly):
   ```bash
   # Restore to test environment
   COMPOSE_FILE=deployments/docker/docker-compose.test.yml \
     ./restore.sh /var/backups/latest-backup.tar.gz --force
   ```

2. **Verify backup integrity**:
   ```bash
   # Check checksums
   cd /var/backups/minio-enterprise/minio-backup-full-20240118_020000/
   sha256sum -c metadata/checksums.txt
   ```

3. **Document restore procedures**:
   - Create runbooks for different scenarios
   - Train team members on restore process
   - Conduct disaster recovery drills

### Monitoring

1. **Set up backup monitoring**:
   ```bash
   # Create Prometheus alert
   - alert: BackupFailed
     expr: time() - minio_last_backup_timestamp > 86400
     annotations:
       summary: "MinIO backup has not run in 24 hours"
   ```

2. **Monitor backup size trends**:
   ```bash
   # Check backup growth
   du -sh /var/backups/minio-enterprise/* | tail -n 10
   ```

3. **Log backup operations**:
   ```bash
   # Centralize logs
   tail -f /var/log/minio-backup.log | grep -E "ERROR|WARN|SUCCESS"
   ```

### Storage Management

1. **Calculate storage requirements**:
   ```
   Daily backup size: 50 GB
   Retention: 30 days
   Total required: 50 GB × 30 = 1.5 TB

   With 20% growth buffer: 1.8 TB
   ```

2. **Monitor disk space**:
   ```bash
   # Alert if backup partition < 20% free
   df -h /var/backups/minio-enterprise | awk 'NR==2 {if ($5+0 > 80) print "WARNING: Disk space low"}'
   ```

3. **Use tiered storage**:
   ```bash
   # Recent backups on fast SSD
   # Older backups on slower HDD
   # Archive to S3 Glacier for long-term retention
   ```

---

## Troubleshooting

### Common Issues

#### 1. Backup Script Fails - "Permission Denied"

**Problem**: Script cannot access Docker volumes or write to backup directory.

**Solution**:
```bash
# Run with sudo
sudo ./backup.sh

# Or add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Ensure backup directory is writable
sudo mkdir -p /var/backups/minio-enterprise
sudo chown -R $USER:$USER /var/backups/minio-enterprise
```

#### 2. PostgreSQL Backup Fails - "Connection Refused"

**Problem**: PostgreSQL service is not running or not accessible.

**Solution**:
```bash
# Check if PostgreSQL is running
docker-compose -f deployments/docker/docker-compose.production.yml ps postgres

# Start PostgreSQL if stopped
docker-compose -f deployments/docker/docker-compose.production.yml start postgres

# Check PostgreSQL logs
docker-compose -f deployments/docker/docker-compose.production.yml logs postgres

# Test connection
docker-compose -f deployments/docker/docker-compose.production.yml exec postgres \
  psql -U minio -d minio_enterprise -c "SELECT 1;"
```

#### 3. Restore Fails - "Checksum Mismatch"

**Problem**: Backup file is corrupted.

**Solution**:
```bash
# Try restoring from a different backup
ls -lh /var/backups/minio-enterprise/ | grep "$(date -d '1 day ago' +%Y%m%d)"

# Verify backup integrity manually
cd /tmp
tar xzf /var/backups/minio-enterprise/backup.tar.gz
cd minio-backup-*/metadata
sha256sum -c checksums.txt

# If checksums fail, backup is corrupted
# Restore from S3 or older backup
```

#### 4. Insufficient Disk Space

**Problem**: Not enough space for backup operation.

**Solution**:
```bash
# Check available space
df -h /var/backups/minio-enterprise

# Free up space by removing old backups
find /var/backups/minio-enterprise -type f -mtime +30 -delete

# Or compress existing backups
cd /var/backups/minio-enterprise
for dir in minio-backup-*/; do
  tar czf "${dir%/}.tar.gz" "$dir" && rm -rf "$dir"
done

# Move backups to different partition
mkdir -p /mnt/large-disk/backups
mv /var/backups/minio-enterprise/* /mnt/large-disk/backups/
ln -s /mnt/large-disk/backups /var/backups/minio-enterprise
```

#### 5. Encryption/Decryption Fails

**Problem**: Wrong encryption key or OpenSSL errors.

**Solution**:
```bash
# Verify encryption key
echo "Test" | openssl enc -aes-256-cbc -salt -pbkdf2 -k "$ENCRYPTION_KEY" | \
  openssl enc -aes-256-cbc -d -pbkdf2 -k "$ENCRYPTION_KEY"

# Check OpenSSL version
openssl version

# Try manual decryption
openssl enc -aes-256-cbc -d -pbkdf2 \
  -in backup.tar.gz.enc \
  -out backup.tar.gz \
  -k "$ENCRYPTION_KEY"
```

#### 6. Slow Backup Performance

**Problem**: Backup takes too long to complete.

**Solution**:
```bash
# Use incremental backups
BACKUP_TYPE=incremental ./backup.sh

# Disable compression for large datasets
COMPRESSION=false ./backup.sh

# Backup during off-peak hours
# (Add to cron for 2 AM)

# Optimize PostgreSQL dump
docker-compose exec postgres pg_dump \
  -U minio -d minio_enterprise \
  --format=custom --compress=0 > backup.dump

# Use faster compression
pigz backup.tar  # parallel gzip
```

#### 7. Restore Hangs

**Problem**: Restore process appears stuck.

**Solution**:
```bash
# Check if services are stopping
docker-compose -f deployments/docker/docker-compose.production.yml ps

# Force stop if needed
docker-compose -f deployments/docker/docker-compose.production.yml down

# Check restore logs
tail -f /var/log/minio-restore.log

# Run restore with verbose output
bash -x ./restore.sh /path/to/backup.tar.gz

# Monitor system resources
htop
iostat -x 1
```

### Logging and Debugging

```bash
# Enable debug mode
set -x  # Add to script for detailed output

# Check all log files
tail -f /var/log/minio-backup.log
tail -f /var/log/minio-restore.log
docker-compose -f deployments/docker/docker-compose.production.yml logs --tail=100

# Verify backup metadata
cat /var/backups/minio-enterprise/latest/metadata/backup_info.json | jq .

# Test individual components
docker-compose exec postgres pg_dump -U minio -d minio_enterprise > test.sql
docker-compose exec redis redis-cli BGSAVE
docker run --rm -v minio1-data:/data -v $(pwd):/backup alpine ls -lh /data
```

---

## Support & Resources

### Documentation

- [MinIO Official Docs](https://min.io/docs)
- [PostgreSQL Backup Documentation](https://www.postgresql.org/docs/current/backup.html)
- [Redis Persistence Documentation](https://redis.io/topics/persistence)

### Tools

- **MinIO Client (mc)**: [https://min.io/docs/minio/linux/reference/minio-mc.html](https://min.io/docs/minio/linux/reference/minio-mc.html)
- **AWS CLI**: [https://aws.amazon.com/cli/](https://aws.amazon.com/cli/)
- **Restic**: [https://restic.net/](https://restic.net/) (Alternative backup tool)

### Getting Help

- **GitHub Issues**: [Repository Issues](https://github.com/abiolaogu/MinIO/issues)
- **GitHub Discussions**: [Repository Discussions](https://github.com/abiolaogu/MinIO/discussions)

---

**Last Updated**: 2026-02-07
**Version**: 1.0.0
**Maintainer**: MinIO Enterprise Team
