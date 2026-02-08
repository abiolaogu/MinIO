# MinIO Enterprise - Backup & Restore System

## 📋 Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Backup Operations](#backup-operations)
- [Restore Operations](#restore-operations)
- [Scheduling](#scheduling)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Overview

The MinIO Enterprise Backup & Restore System provides comprehensive disaster recovery capabilities for production deployments. It supports automated backups of all critical data including PostgreSQL databases, Redis state, MinIO objects, and configuration files.

### Key Capabilities

- **Full Backups**: Complete system state snapshots
- **Incremental Backups**: Efficient differential backups (planned)
- **Encryption**: AES-256-CBC encryption for data at rest
- **Compression**: Gzip compression to reduce storage costs
- **Verification**: Integrity checks with MD5/SHA256 checksums
- **Rollback**: Pre-restore snapshots for safe recovery
- **S3 Upload**: Optional offsite backup to S3-compatible storage
- **Retention**: Automated cleanup of old backups

### What Gets Backed Up

| Component | Description | Backup Method |
|-----------|-------------|---------------|
| **PostgreSQL** | Tenant metadata, quotas, audit logs | `pg_dump` with custom format |
| **Redis** | Cache state, session data | RDB snapshot |
| **MinIO Objects** | User data, files, objects | MinIO client (mc) mirror |
| **Configuration** | Configs, deployment files, .env | File copy |

---

## Quick Start

### 1. Installation

```bash
# Navigate to backup scripts directory
cd /home/runner/work/MinIO/MinIO/scripts/backup

# Run setup script (creates directories, generates encryption key)
./setup.sh
```

### 2. Configuration

```bash
# Edit configuration file
nano backup.conf

# Minimum required settings:
# - BACKUP_ROOT: Where to store backups
# - POSTGRES_PASSWORD: PostgreSQL password
# - MINIO_ACCESS_KEY: MinIO admin access key
# - MINIO_SECRET_KEY: MinIO admin secret key
```

### 3. First Backup

```bash
# Run manual backup
./backup.sh

# Check backup status
ls -lh /var/backups/minio/

# View backup log
tail -f /var/backups/minio/backup.log
```

### 4. Test Restore

```bash
# List available backups
cd ../restore
./restore.sh

# Restore from specific backup (dry run first)
DRY_RUN=true ./restore.sh /var/backups/minio/minio_backup_20260208_120000.tar.gz.enc

# Perform actual restore
./restore.sh /var/backups/minio/minio_backup_20260208_120000.tar.gz.enc
```

---

## Features

### Backup Features

#### 1. Full System Backup

Captures complete system state:
- All PostgreSQL databases and schemas
- Redis RDB snapshot with all keys
- All MinIO buckets and objects
- Configuration files and environment variables

#### 2. Encryption

```bash
# AES-256-CBC encryption with PBKDF2 key derivation
# Encryption key stored in: scripts/backup/backup.key

# Generate new key:
openssl rand -base64 32 > backup.key
chmod 600 backup.key
```

**Security Notes**:
- Encryption key is required for restore operations
- Store key securely (password manager, key vault)
- Never commit encryption key to version control
- Rotate keys periodically (every 90 days recommended)

#### 3. Compression

```bash
# Gzip compression (typically 70-90% size reduction)
# Compression level: 6 (balance of speed and ratio)

# Example sizes:
# Uncompressed: 10 GB
# Compressed: 1-3 GB
# Encrypted: 1-3 GB (minimal size change)
```

#### 4. Integrity Verification

Each backup includes:
- **MD5 checksum**: Fast integrity check
- **SHA256 checksum**: Cryptographic verification
- **Manifest file**: Backup metadata and checksums
- **Gzip test**: Compression integrity check

#### 5. Retention Management

```bash
# Automatic cleanup of old backups
RETENTION_DAYS=30  # Keep backups for 30 days

# Manual cleanup:
find /var/backups/minio -name "minio_backup_*.tar.gz*" -mtime +30 -delete
```

### Restore Features

#### 1. Verification Before Restore

- Checksum validation (MD5, SHA256)
- File integrity checks (gzip test)
- Manifest verification
- Size sanity checks

#### 2. Pre-Restore Snapshots

```bash
# Automatic snapshot before restore (for rollback)
ENABLE_ROLLBACK=true

# Snapshot saved to:
# /var/backups/minio/pre_restore_TIMESTAMP/
```

#### 3. Dry Run Mode

```bash
# Test restore without making changes
DRY_RUN=true ./restore.sh /path/to/backup.tar.gz.enc

# Output shows what would be restored:
# - PostgreSQL database
# - Redis data
# - MinIO objects
# - Configuration files
```

#### 4. Post-Restore Verification

- PostgreSQL: Table count query
- Redis: PING command
- MinIO: Bucket listing
- Configuration: File existence checks

---

## Installation

### Prerequisites

#### Required Software

```bash
# PostgreSQL client tools
sudo apt-get install postgresql-client  # Ubuntu/Debian
sudo yum install postgresql             # RHEL/CentOS

# Redis client tools
sudo apt-get install redis-tools        # Ubuntu/Debian
sudo yum install redis                  # RHEL/CentOS

# MinIO client (mc)
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# OpenSSL (usually pre-installed)
openssl version

# AWS CLI (optional, for S3 upload)
pip install awscli
```

#### System Requirements

- **Disk Space**: 2-3x size of data being backed up
- **Memory**: 2 GB minimum (4 GB recommended)
- **CPU**: 2 cores minimum (4+ for compression)
- **Network**: 100 Mbps for large object backups

### Setup Steps

#### 1. Clone or Copy Scripts

```bash
# Scripts are already in the repository at:
# /home/runner/work/MinIO/MinIO/scripts/backup/
# /home/runner/work/MinIO/MinIO/scripts/restore/
```

#### 2. Run Setup Script

```bash
cd /home/runner/work/MinIO/MinIO/scripts/backup
./setup.sh
```

This script will:
- Create backup directory structure
- Generate encryption key
- Copy configuration template
- Set file permissions
- Check dependencies
- Optionally set up cron job

#### 3. Configure Backup Settings

```bash
nano backup.conf

# Edit these critical settings:
POSTGRES_PASSWORD="your_secure_password"
MINIO_ACCESS_KEY="your_access_key"
MINIO_SECRET_KEY="your_secret_key"
```

#### 4. Test Backup

```bash
# Run test backup
./backup.sh

# Verify backup was created
ls -lh /var/backups/minio/

# Check backup manifest
cat /var/backups/minio/minio_backup_*.manifest
```

---

## Configuration

### Configuration File: `backup.conf`

```bash
# Copy example configuration
cp backup.conf.example backup.conf

# Edit configuration
nano backup.conf
```

### Essential Settings

#### Backup Location

```bash
# Where backups are stored (requires ~2-3x data size)
BACKUP_ROOT="/var/backups/minio"

# Ensure directory exists and is writable
sudo mkdir -p /var/backups/minio
sudo chown $USER:$USER /var/backups/minio
```

#### PostgreSQL Configuration

```bash
POSTGRES_HOST="localhost"           # PostgreSQL server address
POSTGRES_PORT="5432"                # PostgreSQL port
POSTGRES_DB="minio"                 # Database name
POSTGRES_USER="minio"               # Database user
POSTGRES_PASSWORD="your_password"   # Database password
```

#### Redis Configuration

```bash
REDIS_HOST="localhost"              # Redis server address
REDIS_PORT="6379"                   # Redis port
REDIS_PASSWORD=""                   # Redis password (if auth enabled)
REDIS_RDB_PATH="/data/redis/dump.rdb"  # Path to Redis RDB file
```

#### MinIO Configuration

```bash
MINIO_ENDPOINT="http://localhost:9000"  # MinIO API endpoint
MINIO_ACCESS_KEY="minioadmin"           # MinIO access key
MINIO_SECRET_KEY="minioadmin"           # MinIO secret key
```

### Optional Settings

#### Encryption

```bash
ENABLE_ENCRYPTION=true                  # Enable AES-256 encryption
ENCRYPTION_KEY_FILE="./backup.key"      # Path to encryption key
```

#### Compression

```bash
ENABLE_COMPRESSION=true                 # Enable gzip compression
```

#### Retention

```bash
RETENTION_DAYS=30                       # Keep backups for 30 days
```

#### S3 Upload

```bash
S3_UPLOAD=false                         # Upload to S3 after backup
S3_BACKUP_BUCKET="my-backup-bucket"     # S3 bucket name
S3_BACKUP_PREFIX="minio-backups"        # S3 prefix (folder)

# AWS credentials (set in environment or ~/.aws/credentials)
export AWS_ACCESS_KEY_ID="your_key"
export AWS_SECRET_ACCESS_KEY="your_secret"
export AWS_DEFAULT_REGION="us-east-1"
```

---

## Backup Operations

### Manual Backup

```bash
# Full backup with default settings
./backup.sh

# Output:
# [2026-02-08 12:00:00] ==========================================
# [2026-02-08 12:00:00] MinIO Enterprise Backup Started
# [2026-02-08 12:00:00] Backup Type: full
# [2026-02-08 12:00:00] ==========================================
# [2026-02-08 12:00:01] Creating backup directory: /var/backups/minio/20260208_120000
# [2026-02-08 12:00:02] Backing up PostgreSQL database...
# [2026-02-08 12:00:15] PostgreSQL backup completed: database.sql (45M)
# [2026-02-08 12:00:16] Backing up Redis data...
# [2026-02-08 12:00:21] Redis backup completed: dump.rdb (125M)
# [2026-02-08 12:00:22] Backing up MinIO objects...
# [2026-02-08 12:01:30] Bucket my-bucket backed up successfully
# [2026-02-08 12:01:31] Backing up configuration files...
# [2026-02-08 12:01:32] Compressing backup...
# [2026-02-08 12:02:15] Backup compressed: minio_backup_20260208_120000.tar.gz (250M)
# [2026-02-08 12:02:16] Encrypting backup...
# [2026-02-08 12:02:45] Backup encrypted: minio_backup_20260208_120000.tar.gz.enc (250M)
# [2026-02-08 12:02:46] Verifying backup integrity...
# [2026-02-08 12:02:50] Backup integrity verified successfully
# [2026-02-08 12:02:51] Creating backup manifest...
# [2026-02-08 12:02:52] Manifest created: minio_backup_20260208_120000.tar.gz.enc.manifest
# [2026-02-08 12:02:53] Cleaning up backups older than 30 days...
# [2026-02-08 12:02:54] Deleted 5 old backup(s)
# [2026-02-08 12:02:55] ==========================================
# [2026-02-08 12:02:55] Backup completed successfully!
# [2026-02-08 12:02:55] Backup file: /var/backups/minio/minio_backup_20260208_120000.tar.gz.enc
# [2026-02-08 12:02:55] Backup size: 250M
# [2026-02-08 12:02:55] ==========================================
```

### Backup with Custom Settings

```bash
# Backup without encryption
ENABLE_ENCRYPTION=false ./backup.sh

# Backup without compression
ENABLE_COMPRESSION=false ./backup.sh

# Backup with S3 upload
S3_UPLOAD=true ./backup.sh

# Backup to custom location
BACKUP_ROOT=/mnt/external/backups ./backup.sh
```

### List Backups

```bash
# List all backups
ls -lh /var/backups/minio/

# Output:
# -rw-r--r-- 1 user user 250M Feb  8 12:02 minio_backup_20260208_120000.tar.gz.enc
# -rw-r--r-- 1 user user  512 Feb  8 12:02 minio_backup_20260208_120000.tar.gz.enc.manifest
# -rw-r--r-- 1 user user 245M Feb  7 12:02 minio_backup_20260207_120000.tar.gz.enc
# -rw-r--r-- 1 user user  512 Feb  7 12:02 minio_backup_20260207_120000.tar.gz.enc.manifest

# View backup manifest
cat /var/backups/minio/minio_backup_20260208_120000.tar.gz.enc.manifest

# Output:
# Backup Manifest
# ===============
# Timestamp: 20260208_120000
# Backup Type: full
# Backup File: minio_backup_20260208_120000.tar.gz.enc
# File Size: 250M
# MD5 Checksum: d41d8cd98f00b204e9800998ecf8427e
# SHA256 Checksum: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
# Encrypted: true
# Compressed: true
# PostgreSQL: Yes
# Redis: Yes
# MinIO Objects: Yes
# Configuration: Yes
```

### Monitor Backup Progress

```bash
# Watch backup log in real-time
tail -f /var/backups/minio/backup.log

# Check backup disk usage
du -sh /var/backups/minio/

# Count number of backups
ls -1 /var/backups/minio/minio_backup_*.tar.gz* | wc -l
```

---

## Restore Operations

### List Available Backups

```bash
cd /home/runner/work/MinIO/MinIO/scripts/restore

# List all available backups
./restore.sh

# Output:
# Available backups in /var/backups/minio:
# ==========================================
# [1] minio_backup_20260208_120000.tar.gz.enc (250M) - 20260208_120000
# [2] minio_backup_20260207_120000.tar.gz.enc (245M) - 20260207_120000
# [3] minio_backup_20260206_120000.tar.gz.enc (240M) - 20260206_120000
# ==========================================
```

### Dry Run Restore

```bash
# Test restore without making changes
DRY_RUN=true ./restore.sh /var/backups/minio/minio_backup_20260208_120000.tar.gz.enc

# Output shows what would be restored:
# [2026-02-08 14:00:00] ==========================================
# [2026-02-08 14:00:00] MinIO Enterprise Restore Started
# [2026-02-08 14:00:00] MODE: DRY RUN (no actual changes will be made)
# [2026-02-08 14:00:00] ==========================================
# [2026-02-08 14:00:01] Selected backup: /var/backups/minio/minio_backup_20260208_120000.tar.gz.enc
# [2026-02-08 14:00:02] Verifying backup integrity...
# [2026-02-08 14:00:05] MD5 checksum verified successfully
# [2026-02-08 14:00:06] Backup integrity verified successfully
# [2026-02-08 14:00:07] Decrypting backup...
# [2026-02-08 14:00:35] Backup decrypted successfully
# [2026-02-08 14:00:36] Extracting backup to: /tmp/minio_restore_12345
# [2026-02-08 14:00:50] Backup extracted successfully
# [2026-02-08 14:00:51] DRY RUN: Would restore PostgreSQL from /tmp/minio_restore_12345/postgresql/database.sql
# [2026-02-08 14:00:52] DRY RUN: Would restore Redis from /tmp/minio_restore_12345/redis/dump.rdb
# [2026-02-08 14:00:53] DRY RUN: Would restore MinIO objects from /tmp/minio_restore_12345/objects
# [2026-02-08 14:00:54] DRY RUN: Would restore configurations from /tmp/minio_restore_12345/configs
# [2026-02-08 14:00:55] ==========================================
# [2026-02-08 14:00:55] Restore completed successfully!
# [2026-02-08 14:00:55] ==========================================
```

### Full Restore

```bash
# Restore from backup
./restore.sh /var/backups/minio/minio_backup_20260208_120000.tar.gz.enc

# Output:
# [2026-02-08 14:00:00] ==========================================
# [2026-02-08 14:00:00] MinIO Enterprise Restore Started
# [2026-02-08 14:00:00] ==========================================
# [2026-02-08 14:00:01] Selected backup: /var/backups/minio/minio_backup_20260208_120000.tar.gz.enc
# [2026-02-08 14:00:02] Verifying backup integrity...
# [2026-02-08 14:00:05] Backup integrity verified successfully
# [2026-02-08 14:00:06] Decrypting backup...
# [2026-02-08 14:00:35] Backup decrypted successfully
# [2026-02-08 14:00:36] Extracting backup...
# [2026-02-08 14:00:50] Backup extracted successfully
# [2026-02-08 14:00:51] Creating pre-restore snapshot for rollback...
# [2026-02-08 14:01:15] Pre-restore snapshot created: /var/backups/minio/pre_restore_20260208_140051
# [2026-02-08 14:01:16] Starting restoration process...
# [2026-02-08 14:01:17] Restoring PostgreSQL database...
# [2026-02-08 14:02:00] PostgreSQL restore completed successfully
# [2026-02-08 14:02:01] Restoring Redis data...
# [2026-02-08 14:02:10] Redis restore completed successfully
# [2026-02-08 14:02:11] Restoring MinIO objects...
# [2026-02-08 14:03:30] Bucket my-bucket restored successfully
# [2026-02-08 14:03:31] MinIO objects restore completed
# [2026-02-08 14:03:32] Restoring configuration files...
# [2026-02-08 14:03:35] Configuration restore completed
# [2026-02-08 14:03:36] Verifying restoration...
# [2026-02-08 14:03:40] PostgreSQL verification: OK
# [2026-02-08 14:03:41] Redis verification: OK
# [2026-02-08 14:03:42] Verification completed successfully
# [2026-02-08 14:03:43] ==========================================
# [2026-02-08 14:03:43] Restore completed successfully!
# [2026-02-08 14:03:44] Pre-restore snapshot saved to: /var/backups/minio/pre_restore_20260208_140051
# [2026-02-08 14:03:45] ==========================================
```

### Selective Restore

To restore only specific components, modify the restore script or manually extract:

```bash
# Extract backup manually
mkdir /tmp/backup_extract
cd /tmp/backup_extract

# Decrypt
openssl enc -d -aes-256-cbc -pbkdf2 \
  -in /var/backups/minio/minio_backup_20260208_120000.tar.gz.enc \
  -out backup.tar.gz \
  -pass file:/home/runner/work/MinIO/MinIO/scripts/backup/backup.key

# Extract
tar -xzf backup.tar.gz

# Now restore only what you need:
# - PostgreSQL: postgresql/database.sql
# - Redis: redis/dump.rdb
# - Objects: objects/
# - Configs: configs/
```

---

## Scheduling

### Cron Job Setup

#### Daily Full Backup

```bash
# Edit crontab
crontab -e

# Add daily backup at 2:00 AM
0 2 * * * /home/runner/work/MinIO/MinIO/scripts/backup/backup.sh >> /var/backups/minio/backup.log 2>&1
```

#### Multiple Backup Schedules

```bash
# Daily full backup at 2:00 AM
0 2 * * * /home/runner/work/MinIO/MinIO/scripts/backup/backup.sh >> /var/backups/minio/backup.log 2>&1

# Weekly S3 upload on Sundays at 3:00 AM
0 3 * * 0 S3_UPLOAD=true /home/runner/work/MinIO/MinIO/scripts/backup/backup.sh >> /var/backups/minio/backup.log 2>&1

# Monthly long-term backup (90-day retention)
0 4 1 * * RETENTION_DAYS=90 /home/runner/work/MinIO/MinIO/scripts/backup/backup.sh >> /var/backups/minio/backup.log 2>&1
```

### Systemd Timer (Alternative to Cron)

#### 1. Create Service Unit

```bash
# Create service file
sudo nano /etc/systemd/system/minio-backup.service
```

```ini
[Unit]
Description=MinIO Enterprise Backup
After=network.target postgresql.service redis.service

[Service]
Type=oneshot
User=minio
Group=minio
ExecStart=/home/runner/work/MinIO/MinIO/scripts/backup/backup.sh
StandardOutput=append:/var/backups/minio/backup.log
StandardError=append:/var/backups/minio/backup.log
```

#### 2. Create Timer Unit

```bash
# Create timer file
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

#### 3. Enable Timer

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable timer
sudo systemctl enable minio-backup.timer

# Start timer
sudo systemctl start minio-backup.timer

# Check timer status
sudo systemctl status minio-backup.timer

# List all timers
systemctl list-timers
```

---

## Security

### Encryption Key Management

#### Generate Strong Key

```bash
# Generate 256-bit key (32 bytes)
openssl rand -base64 32 > backup.key

# Secure permissions (read-only for owner)
chmod 600 backup.key

# Verify key
cat backup.key
```

#### Store Key Securely

**Recommended Options**:

1. **Password Manager** (1Password, LastPass, Bitwarden)
2. **Key Vault** (AWS KMS, Azure Key Vault, HashiCorp Vault)
3. **Hardware Security Module (HSM)**
4. **Offline Storage** (USB drive in safe)

**Never**:
- ❌ Commit to version control
- ❌ Store in backup directory
- ❌ Email or share unencrypted
- ❌ Leave in default location on production

#### Key Rotation

```bash
# Generate new key
openssl rand -base64 32 > backup.key.new

# Re-encrypt existing backups with new key (example)
for backup in /var/backups/minio/*.tar.gz.enc; do
    # Decrypt with old key
    openssl enc -d -aes-256-cbc -pbkdf2 \
        -in "$backup" \
        -out "${backup%.enc}" \
        -pass file:backup.key

    # Re-encrypt with new key
    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -in "${backup%.enc}" \
        -out "${backup}.new" \
        -pass file:backup.key.new

    # Verify and replace
    mv "${backup}.new" "$backup"
    rm "${backup%.enc}"
done

# Replace key
mv backup.key.new backup.key
```

### Access Control

#### File Permissions

```bash
# Backup directory (owner read/write/execute)
chmod 700 /var/backups/minio

# Backup files (owner read/write)
chmod 600 /var/backups/minio/*.tar.gz*

# Encryption key (owner read-only)
chmod 400 /home/runner/work/MinIO/MinIO/scripts/backup/backup.key

# Scripts (owner execute)
chmod 700 /home/runner/work/MinIO/MinIO/scripts/backup/*.sh
chmod 700 /home/runner/work/MinIO/MinIO/scripts/restore/*.sh
```

#### User and Group

```bash
# Create dedicated backup user
sudo useradd -r -s /bin/bash -m minio-backup

# Set ownership
sudo chown -R minio-backup:minio-backup /var/backups/minio
sudo chown -R minio-backup:minio-backup /home/runner/work/MinIO/MinIO/scripts/backup
sudo chown -R minio-backup:minio-backup /home/runner/work/MinIO/MinIO/scripts/restore

# Run backups as dedicated user
sudo -u minio-backup /home/runner/work/MinIO/MinIO/scripts/backup/backup.sh
```

### Secure Credentials

#### Environment Variables

```bash
# Store credentials in secure location
echo "export POSTGRES_PASSWORD='secure_password'" >> ~/.backup_secrets
echo "export MINIO_SECRET_KEY='secure_key'" >> ~/.backup_secrets
chmod 600 ~/.backup_secrets

# Source in backup script
source ~/.backup_secrets
```

#### AWS Secrets Manager (for S3 backups)

```bash
# Store credentials in AWS Secrets Manager
aws secretsmanager create-secret \
    --name minio-backup-credentials \
    --secret-string '{"postgres_password":"xxx","minio_secret":"yyy"}'

# Retrieve in script
SECRET=$(aws secretsmanager get-secret-value --secret-id minio-backup-credentials --query SecretString --output text)
POSTGRES_PASSWORD=$(echo $SECRET | jq -r .postgres_password)
MINIO_SECRET_KEY=$(echo $SECRET | jq -r .minio_secret)
```

---

## Troubleshooting

### Common Issues

#### 1. Backup Fails: "pg_dump: command not found"

**Problem**: PostgreSQL client tools not installed

**Solution**:
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install postgresql-client

# RHEL/CentOS
sudo yum install postgresql
```

#### 2. Backup Fails: "Permission denied"

**Problem**: Insufficient permissions on backup directory

**Solution**:
```bash
# Check current permissions
ls -ld /var/backups/minio

# Fix permissions
sudo chown $USER:$USER /var/backups/minio
chmod 700 /var/backups/minio
```

#### 3. Restore Fails: "Decryption failed"

**Problem**: Wrong encryption key or corrupted key file

**Solution**:
```bash
# Verify key file exists and is readable
cat /home/runner/work/MinIO/MinIO/scripts/backup/backup.key

# Check backup manifest for encryption info
cat /var/backups/minio/*.manifest | grep Encrypted

# Verify backup file integrity
md5sum /var/backups/minio/minio_backup_*.tar.gz.enc
```

#### 4. Redis Backup Fails: "RDB file not found"

**Problem**: Incorrect Redis RDB path in configuration

**Solution**:
```bash
# Find actual RDB path
redis-cli CONFIG GET dir
redis-cli CONFIG GET dbfilename

# Update backup.conf with correct path
REDIS_RDB_PATH="/actual/path/to/dump.rdb"
```

#### 5. MinIO Backup Fails: "mc: command not found"

**Problem**: MinIO client not installed

**Solution**:
```bash
# Install MinIO client
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# Verify installation
mc --version
```

#### 6. S3 Upload Fails: "Unable to locate credentials"

**Problem**: AWS credentials not configured

**Solution**:
```bash
# Configure AWS CLI
aws configure

# Or set environment variables
export AWS_ACCESS_KEY_ID="your_key"
export AWS_SECRET_ACCESS_KEY="your_secret"
export AWS_DEFAULT_REGION="us-east-1"

# Or use instance profile (EC2)
# (no configuration needed)
```

### Debugging Tips

#### Enable Verbose Logging

```bash
# Add set -x to enable bash debugging
# Edit backup.sh, add after 'set -euo pipefail':
set -x

# Run backup to see detailed execution
./backup.sh
```

#### Check Disk Space

```bash
# Check available space
df -h /var/backups/minio

# Check backup size vs available space
du -sh /var/lib/postgresql /var/lib/redis /var/lib/minio
df -h /var/backups
```

#### Test Individual Components

```bash
# Test PostgreSQL connection
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U minio -d minio -c "SELECT 1;"

# Test Redis connection
redis-cli -h localhost PING

# Test MinIO connection
mc alias set test http://localhost:9000 minioadmin minioadmin
mc ls test
```

#### Review Logs

```bash
# View full backup log
cat /var/backups/minio/backup.log

# View recent errors
grep ERROR /var/backups/minio/backup.log

# Monitor live backup
tail -f /var/backups/minio/backup.log
```

---

## Best Practices

### 1. Regular Testing

```bash
# Test restore quarterly
# - Use dry run mode first
# - Restore to separate test environment
# - Verify data integrity
# - Document restore time (RTO)

# Example test procedure:
DRY_RUN=true ./restore.sh /var/backups/minio/minio_backup_latest.tar.gz.enc
```

### 2. Offsite Backups

```bash
# Enable S3 upload for offsite storage
S3_UPLOAD=true
S3_BACKUP_BUCKET="minio-backups-offsite"

# Consider multiple regions
# - Primary: us-east-1
# - Disaster recovery: us-west-2
```

### 3. Backup Verification

```bash
# Verify backups after creation
# - Check file size (should be > 0)
# - Verify checksums (MD5, SHA256)
# - Test extraction (gzip -t)
# - Periodic restore tests
```

### 4. Monitoring and Alerting

```bash
# Monitor backup success/failure
# - Check backup log for errors
# - Alert on backup failures
# - Track backup size trends
# - Monitor disk space

# Example: Send email on failure
if ! ./backup.sh; then
    echo "Backup failed at $(date)" | mail -s "MinIO Backup Failed" admin@example.com
fi
```

### 5. Documentation

```bash
# Document your backup strategy:
# - Backup frequency and retention
# - Restore procedures (runbooks)
# - Encryption key locations
# - Contact information
# - Recovery Time Objective (RTO)
# - Recovery Point Objective (RPO)
```

### 6. Retention Strategy

```bash
# 3-2-1 Backup Rule:
# - 3 copies of data
# - 2 different storage types
# - 1 offsite copy

# Example retention:
# - Daily: 7 days local
# - Weekly: 4 weeks local + S3
# - Monthly: 12 months S3 only
```

### 7. Security Hardening

```bash
# Security checklist:
# ✓ Enable encryption
# ✓ Secure encryption key
# ✓ Use dedicated backup user
# ✓ Restrict file permissions (600/700)
# ✓ Rotate encryption keys
# ✓ Audit backup access logs
# ✓ Use MFA for S3 access
# ✓ Enable versioning on S3 bucket
```

### 8. Performance Optimization

```bash
# Optimize backup performance:
# - Use SSD for backup storage
# - Run backups during low-traffic hours
# - Enable parallel compression
# - Use PostgreSQL custom format (-Fc)
# - Monitor backup duration trends
```

---

## Support & Resources

### Documentation

- [MinIO Documentation](https://min.io/docs)
- [PostgreSQL Backup Documentation](https://www.postgresql.org/docs/current/backup.html)
- [Redis Persistence](https://redis.io/docs/management/persistence/)

### Getting Help

- **GitHub Issues**: [MinIO Enterprise Issues](https://github.com/abiolaogu/MinIO/issues)
- **Email**: admin@example.com
- **Slack**: #minio-support

### Version Information

- **Script Version**: 1.0.0
- **Last Updated**: 2026-02-08
- **Compatibility**: MinIO Enterprise 2.0.0+

---

## License

Apache License 2.0 - See [LICENSE](../../LICENSE) file for details.

---

## Appendix

### Sample Backup Manifest

```
Backup Manifest
===============
Timestamp: 20260208_120000
Backup Type: full
Backup File: minio_backup_20260208_120000.tar.gz.enc
File Size: 250M
MD5 Checksum: d41d8cd98f00b204e9800998ecf8427e
SHA256 Checksum: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
Encrypted: true
Compressed: true
PostgreSQL: Yes
Redis: Yes
MinIO Objects: Yes
Configuration: Yes
```

### Backup Directory Structure

```
/var/backups/minio/
├── 20260208_120000/                          # Temporary extraction directory
│   ├── postgresql/
│   │   └── database.sql                       # PostgreSQL dump
│   ├── redis/
│   │   └── dump.rdb                           # Redis RDB snapshot
│   ├── objects/
│   │   ├── bucket1/                           # MinIO bucket 1
│   │   │   ├── file1.txt
│   │   │   └── file2.jpg
│   │   └── bucket2/                           # MinIO bucket 2
│   │       └── data.csv
│   └── configs/
│       ├── configs/                           # Configuration directory
│       ├── deployments/                       # Deployment configs
│       ├── .env                               # Environment variables
│       └── docker-compose.yml                 # Docker Compose file
├── minio_backup_20260208_120000.tar.gz.enc   # Encrypted backup
├── minio_backup_20260208_120000.tar.gz.enc.manifest  # Backup manifest
├── minio_backup_20260207_120000.tar.gz.enc   # Previous backup
├── minio_backup_20260207_120000.tar.gz.enc.manifest
├── backup.log                                 # Backup log file
└── restore.log                                # Restore log file
```

### Recovery Time Estimates

| Environment | Data Size | Restore Time | RTO Target |
|-------------|-----------|--------------|------------|
| Development | 1 GB | 5 minutes | 15 minutes |
| Staging | 10 GB | 15 minutes | 30 minutes |
| Production | 100 GB | 45 minutes | 60 minutes |
| Enterprise | 1 TB | 4 hours | 6 hours |

### Backup Size Estimates

| Component | Raw Size | Compressed | Encrypted | Final Size |
|-----------|----------|------------|-----------|------------|
| PostgreSQL | 500 MB | 100 MB | 100 MB | ~20% |
| Redis | 2 GB | 400 MB | 400 MB | ~20% |
| Objects | 10 GB | 8 GB | 8 GB | ~80% |
| Configs | 10 MB | 2 MB | 2 MB | ~20% |
| **Total** | **12.5 GB** | **8.5 GB** | **8.5 GB** | **~68%** |

---

**End of Documentation**
