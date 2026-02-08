# MinIO Enterprise Backup and Restore Guide

Complete guide for backing up and restoring MinIO Enterprise deployments.

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Backup System](#backup-system)
4. [Restore System](#restore-system)
5. [Automation](#automation)
6. [Best Practices](#best-practices)
7. [Disaster Recovery](#disaster-recovery)
8. [Troubleshooting](#troubleshooting)

---

## Overview

The MinIO Enterprise backup and restore system provides comprehensive data protection capabilities with support for:

- **Full and Incremental Backups**: Efficient backup strategies for different scenarios
- **Multi-Component Coverage**: Backs up MinIO data, PostgreSQL database, Redis state, and configuration
- **Encryption and Compression**: Secure and space-efficient backups
- **Offsite Storage**: S3-compatible storage integration for geographic redundancy
- **Automated Scheduling**: Cron-compatible for automated backup operations
- **Verification**: Built-in integrity checking and verification
- **Rollback Protection**: Create restore points before restore operations

### Components Backed Up

| Component | Description | Size (Typical) | Frequency |
|-----------|-------------|----------------|-----------|
| MinIO Data | Object storage data | 10GB - 10TB+ | Daily (incremental) |
| PostgreSQL | Metadata, tenant info, audit logs | 100MB - 10GB | Daily (full) |
| Redis | Cache state, session data | 10MB - 1GB | Daily (snapshot) |
| Configuration | Config files, deployment settings | 10MB | Weekly |

### Backup Types

- **Full Backup**: Complete backup of all components (recommended weekly)
- **Incremental Backup**: Only changed files since last full backup (recommended daily)

---

## Quick Start

### Prerequisites

```bash
# Install required tools
sudo apt-get update
sudo apt-get install -y postgresql-client redis-tools tar gzip gnupg awscli

# Set execute permissions
chmod +x scripts/backup/backup.sh
chmod +x scripts/restore/restore.sh
```

### Perform Your First Backup

```bash
# 1. Configure backup settings
cp scripts/backup/backup.conf scripts/backup/backup.local.conf
nano scripts/backup/backup.local.conf

# 2. Run a test backup
./scripts/backup/backup.sh --full --verify

# 3. Check backup was created
ls -lh /var/backups/minio/
```

### Test Restore Process

```bash
# Test restore in a safe environment first!
./scripts/restore/restore.sh --verify /var/backups/minio/minio-backup-full-20260208_142000
```

---

## Backup System

### Basic Usage

```bash
# Full backup
./scripts/backup/backup.sh --full

# Incremental backup
./scripts/backup/backup.sh --incremental

# Full backup with compression and verification
./scripts/backup/backup.sh --full --compress --verify

# Encrypted backup uploaded to S3
./scripts/backup/backup.sh --full --compress --encrypt --s3
```

### Command Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `--full` | Perform full backup (default) | `--full` |
| `--incremental` | Incremental backup since last full | `--incremental` |
| `--config FILE` | Use custom config file | `--config /etc/minio/backup.conf` |
| `--output DIR` | Override output directory | `--output /mnt/backups` |
| `--compress` | Enable gzip compression | `--compress` |
| `--encrypt` | Enable GPG encryption | `--encrypt` |
| `--verify` | Verify backup after creation | `--verify` |
| `--s3` | Upload to S3 storage | `--s3` |
| `--help` | Show help message | `--help` |

### Configuration File

Edit `scripts/backup/backup.conf`:

```bash
# Backup directory
BACKUP_DIR="/var/backups/minio"

# Retention policy
RETENTION_DAYS=30          # Keep daily backups for 30 days
RETENTION_FULL_BACKUPS=4   # Keep 4 most recent full backups

# PostgreSQL connection
POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"
POSTGRES_DB="minio"
POSTGRES_USER="minio"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"  # From environment

# Redis connection
REDIS_HOST="localhost"
REDIS_PORT="6379"

# MinIO paths
MINIO_DATA_DIR="/data/minio"
MINIO_CONFIG_DIR="/etc/minio"

# S3 offsite storage
S3_ENDPOINT="https://s3.amazonaws.com"
S3_BUCKET="minio-backups"
S3_ACCESS_KEY="${S3_ACCESS_KEY}"
S3_SECRET_KEY="${S3_SECRET_KEY}"

# Encryption
GPG_RECIPIENT="backup@example.com"
```

### Backup Structure

A complete backup contains:

```
minio-backup-full-20260208_142000/
├── metadata/
│   └── backup.info              # Backup metadata (timestamp, type, etc.)
├── database/
│   └── minio.sql                # PostgreSQL dump (custom format)
├── redis/
│   └── dump.rdb                 # Redis snapshot
├── data/
│   └── objects.tar              # MinIO object data
└── config/
    └── config.tar               # Configuration files
```

### Backup Workflow

1. **Validation**: Check prerequisites and configuration
2. **Preparation**: Create backup directory structure
3. **Component Backups**:
   - PostgreSQL: `pg_dump` with custom format and compression
   - Redis: Trigger `BGSAVE` and copy RDB file
   - MinIO Data: `tar` archive (full or incremental)
   - Configuration: Archive config directories
4. **Post-Processing**:
   - Compression (optional): Create `.tar.gz` archive
   - Encryption (optional): GPG encrypt entire backup
   - Verification (optional): Checksum and integrity tests
   - Upload (optional): Copy to S3-compatible storage
5. **Cleanup**: Remove old backups per retention policy

### Security Considerations

#### Encryption

```bash
# Generate GPG key for backups
gpg --full-generate-key

# List keys
gpg --list-keys

# Update config with recipient
GPG_RECIPIENT="your-email@example.com"

# Run encrypted backup
./scripts/backup/backup.sh --full --encrypt
```

#### Password Management

Never store passwords in configuration files. Use environment variables:

```bash
# Set password via environment
export POSTGRES_PASSWORD="your-secure-password"
export S3_ACCESS_KEY="your-access-key"
export S3_SECRET_KEY="your-secret-key"

# Run backup (will use environment variables)
./scripts/backup/backup.sh --full
```

Or use a secrets management system:

```bash
# Using AWS Secrets Manager
POSTGRES_PASSWORD=$(aws secretsmanager get-secret-value --secret-id minio/postgres --query SecretString --output text)
export POSTGRES_PASSWORD

# Using HashiCorp Vault
POSTGRES_PASSWORD=$(vault kv get -field=password secret/minio/postgres)
export POSTGRES_PASSWORD
```

---

## Restore System

### Basic Usage

```bash
# Restore from directory
./scripts/restore/restore.sh /var/backups/minio/minio-backup-full-20260208_142000

# Restore from compressed archive
./scripts/restore/restore.sh /var/backups/minio/minio-backup-full-20260208_142000.tar.gz

# Restore with verification and rollback point
./scripts/restore/restore.sh --verify --rollback /var/backups/minio/minio-backup-full-20260208_142000

# Decrypt and restore
./scripts/restore/restore.sh --decrypt /var/backups/minio/minio-backup-full-20260208_142000.tar.gz.gpg

# Force restore without confirmation
./scripts/restore/restore.sh --force /var/backups/minio/minio-backup-full-20260208_142000
```

### Command Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `--verify` | Verify backup integrity before restore | `--verify` |
| `--rollback` | Create rollback point before restore | `--rollback` |
| `--force` | Skip confirmation prompts | `--force` |
| `--decrypt` | Decrypt backup before restore | `--decrypt` |
| `--data-only` | Restore only MinIO data | `--data-only` |
| `--db-only` | Restore only PostgreSQL | `--db-only` |
| `--config-only` | Restore only configuration | `--config-only` |
| `--help` | Show help message | `--help` |

### Selective Restore

Restore specific components:

```bash
# Restore only database (e.g., to recover from data corruption)
./scripts/restore/restore.sh --db-only /var/backups/minio/minio-backup-full-20260208_142000

# Restore only MinIO data (e.g., to recover deleted objects)
./scripts/restore/restore.sh --data-only /var/backups/minio/minio-backup-full-20260208_142000

# Restore only configuration (e.g., to revert config changes)
./scripts/restore/restore.sh --config-only /var/backups/minio/minio-backup-full-20260208_142000
```

### Restore Workflow

1. **Validation**: Verify backup exists and prerequisites met
2. **Integrity Check** (optional): Verify checksums and archive integrity
3. **Decryption** (optional): Decrypt GPG-encrypted backup
4. **Extraction**: Extract backup to temporary directory
5. **Metadata Reading**: Read backup information and display to user
6. **Rollback Point** (optional): Create backup of current state
7. **Confirmation**: Request user confirmation (unless `--force`)
8. **Service Stop**: Stop MinIO and related services
9. **Component Restore**:
   - PostgreSQL: Drop/recreate database, `pg_restore`
   - Redis: Stop service, replace RDB file, restart
   - MinIO Data: Replace data directory with backup
   - Configuration: Extract config files to system paths
10. **Service Start**: Restart MinIO and related services
11. **Cleanup**: Remove temporary files

### Rollback Procedure

If restore fails or you need to revert:

```bash
# Find last rollback point
cat /tmp/minio-last-rollback
# Output: /var/backups/minio/rollback-20260208_143000

# Restore from rollback point
./scripts/restore/restore.sh --force /var/backups/minio/rollback-20260208_143000
```

---

## Automation

### Cron Setup

#### Daily Automated Backups

```bash
# Edit crontab
crontab -e

# Add backup schedule
# Full backup: Every Sunday at 2:00 AM
0 2 * * 0 /opt/minio/scripts/backup/backup.sh --full --compress --verify --s3 >> /var/log/minio-backup.log 2>&1

# Incremental backup: Monday-Saturday at 2:00 AM
0 2 * * 1-6 /opt/minio/scripts/backup/backup.sh --incremental --compress --s3 >> /var/log/minio-backup.log 2>&1

# Cleanup old logs
0 3 * * 0 find /var/log -name "minio-backup*.log" -mtime +30 -delete
```

#### Systemd Timer (Alternative)

Create systemd service:

```ini
# /etc/systemd/system/minio-backup.service
[Unit]
Description=MinIO Enterprise Backup
After=network.target

[Service]
Type=oneshot
User=minio
Group=minio
Environment="POSTGRES_PASSWORD=secret"
ExecStart=/opt/minio/scripts/backup/backup.sh --full --compress --verify
StandardOutput=journal
StandardError=journal
```

Create systemd timer:

```ini
# /etc/systemd/system/minio-backup.timer
[Unit]
Description=MinIO Enterprise Backup Timer
Requires=minio-backup.service

[Timer]
OnCalendar=Sun *-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable minio-backup.timer
sudo systemctl start minio-backup.timer

# Check status
sudo systemctl status minio-backup.timer
```

### Monitoring Backup Success

#### Log Monitoring

```bash
# Watch backup logs in real-time
tail -f /var/log/minio-backup.log

# Check for errors
grep ERROR /var/log/minio-backup.log

# Check last backup status
grep "Backup completed" /var/log/minio-backup.log | tail -1
```

#### Prometheus Metrics

Export backup metrics for monitoring:

```bash
# Create metrics exporter script
cat > /opt/minio/scripts/backup/export-metrics.sh << 'EOF'
#!/bin/bash
METRICS_FILE="/var/lib/node_exporter/textfile_collector/minio_backup.prom"

# Get last backup info
LAST_BACKUP=$(find /var/backups/minio -name "minio-backup-full-*" -type d | sort -r | head -1)
BACKUP_AGE=$(($(date +%s) - $(stat -c %Y "$LAST_BACKUP")))
BACKUP_SIZE=$(du -sb "$LAST_BACKUP" | cut -f1)

# Write metrics
cat > "$METRICS_FILE" << METRICS
# HELP minio_backup_age_seconds Age of last successful backup in seconds
# TYPE minio_backup_age_seconds gauge
minio_backup_age_seconds $BACKUP_AGE

# HELP minio_backup_size_bytes Size of last backup in bytes
# TYPE minio_backup_size_bytes gauge
minio_backup_size_bytes $BACKUP_SIZE

# HELP minio_backup_last_success_timestamp Unix timestamp of last successful backup
# TYPE minio_backup_last_success_timestamp gauge
minio_backup_last_success_timestamp $(stat -c %Y "$LAST_BACKUP")
METRICS
EOF

chmod +x /opt/minio/scripts/backup/export-metrics.sh

# Add to crontab to run after backups
*/5 * * * * /opt/minio/scripts/backup/export-metrics.sh
```

#### Alerts

Configure Prometheus alerts:

```yaml
# /configs/prometheus/rules/backup_alerts.yml
groups:
  - name: backup_alerts
    interval: 5m
    rules:
      - alert: BackupTooOld
        expr: minio_backup_age_seconds > 86400 * 2
        for: 1h
        labels:
          severity: warning
          component: backup
        annotations:
          summary: "MinIO backup is too old"
          description: "Last backup is {{ $value | humanizeDuration }} old (>48h)"

      - alert: BackupMissing
        expr: absent(minio_backup_age_seconds)
        for: 30m
        labels:
          severity: critical
          component: backup
        annotations:
          summary: "MinIO backup metrics missing"
          description: "No backup metrics found - backup system may be down"

      - alert: BackupSizeAnomalous
        expr: |
          abs(minio_backup_size_bytes - avg_over_time(minio_backup_size_bytes[7d]))
          / avg_over_time(minio_backup_size_bytes[7d]) > 0.5
        for: 1h
        labels:
          severity: warning
          component: backup
        annotations:
          summary: "MinIO backup size anomalous"
          description: "Backup size differs >50% from 7-day average"
```

---

## Best Practices

### 1. Backup Strategy

#### 3-2-1 Rule

Follow the industry-standard 3-2-1 backup rule:

- **3 Copies**: Production data + 2 backups
- **2 Different Media**: Local storage + cloud/offsite
- **1 Offsite Copy**: Geographic separation

```bash
# Implementation example
# Local backup (1st copy)
./scripts/backup/backup.sh --full --compress

# Offsite backup (2nd copy)
./scripts/backup/backup.sh --full --compress --encrypt --s3

# Archive copy (optional 3rd copy - tape/glacier)
aws s3 cp /var/backups/minio/latest.tar.gz.gpg \
  s3://minio-archive/monthly/ --storage-class GLACIER
```

#### Backup Schedule

Recommended schedule for production:

| Frequency | Type | Time | Retention |
|-----------|------|------|-----------|
| Daily | Incremental | 2:00 AM | 7 days |
| Weekly | Full | Sunday 2:00 AM | 4 weeks |
| Monthly | Full | 1st Sunday | 12 months |
| Yearly | Full | Jan 1st | 7 years |

### 2. Testing Backups

**Critical**: Regularly test restore procedures!

```bash
# Monthly restore test procedure
# 1. Restore to test environment
./scripts/restore/restore.sh --verify /var/backups/minio/latest-full

# 2. Verify data integrity
# - Check database connectivity
# - Verify object counts match
# - Test random object retrieval

# 3. Document results
echo "Restore test $(date): SUCCESS" >> /var/log/restore-tests.log
```

### 3. Security

#### Encrypt Sensitive Backups

```bash
# Always encrypt backups containing:
# - Personally Identifiable Information (PII)
# - Financial data
# - Healthcare records
# - Proprietary business data

./scripts/backup/backup.sh --full --encrypt
```

#### Secure Backup Storage

```bash
# Set restrictive permissions
chmod 700 /var/backups/minio
chown minio:minio /var/backups/minio

# Use dedicated backup user
useradd -r -s /bin/false minio-backup
```

#### Audit Backup Access

```bash
# Enable audit logging
auditctl -w /var/backups/minio -p rwxa -k minio_backup_access

# Review audit logs
ausearch -k minio_backup_access
```

### 4. Performance Optimization

#### Minimize Backup Windows

```bash
# Use parallel compression
tar -cf - /data/minio | pigz -p 4 > backup.tar.gz

# Use fast compression for large datasets
tar -cf - /data/minio | lz4 > backup.tar.lz4
```

#### Incremental Backups

```bash
# Daily incremental backups reduce:
# - Backup time: 90% reduction
# - Storage usage: 80% reduction
# - Network bandwidth: 85% reduction

# Weekly schedule:
# Sun: Full (100GB, 2h)
# Mon-Sat: Incremental (10GB each, 15min)
```

### 5. Documentation

Maintain backup documentation:

```markdown
# Required Documentation
1. Backup schedule and retention policy
2. Restore procedures with step-by-step instructions
3. Contact information for backup administrators
4. Encryption key management procedures
5. Disaster recovery runbook
6. Test restore results and dates
```

---

## Disaster Recovery

### Recovery Time Objective (RTO)

Target restore times:

| Scenario | RTO | Procedure |
|----------|-----|-----------|
| Single object recovery | <5 minutes | Extract from backup, copy to production |
| Database corruption | <30 minutes | Database-only restore |
| Complete system failure | <2 hours | Full restore from backup |
| Datacenter disaster | <4 hours | Restore from offsite backup |

### Recovery Point Objective (RPO)

Maximum acceptable data loss:

| Service Level | RPO | Backup Frequency |
|---------------|-----|------------------|
| Standard | 24 hours | Daily backups |
| High Availability | 12 hours | Twice-daily backups |
| Mission Critical | 1 hour | Hourly backups + replication |

### Disaster Recovery Procedures

#### Scenario 1: Database Corruption

```bash
# 1. Detect issue
# Alert: High database error rate

# 2. Stop affected services
docker-compose -f deployments/docker/docker-compose.production.yml stop

# 3. Restore database only
./scripts/restore/restore.sh --verify --rollback --db-only \
  /var/backups/minio/minio-backup-full-20260208_020000

# 4. Restart services
docker-compose -f deployments/docker/docker-compose.production.yml start

# 5. Verify functionality
curl http://localhost:9000/health
```

#### Scenario 2: Ransomware Attack

```bash
# 1. Isolate affected systems
# - Disconnect from network
# - Stop all services

# 2. Assess damage
# - Identify encrypted files
# - Check backup integrity

# 3. Restore from clean backup (before infection)
./scripts/restore/restore.sh --verify --force \
  /var/backups/minio/minio-backup-full-20260201_020000

# 4. Update security
# - Change all passwords
# - Update firewall rules
# - Install security patches

# 5. Resume operations
```

#### Scenario 3: Complete Datacenter Loss

```bash
# 1. Provision new infrastructure
# - Deploy new servers
# - Install MinIO Enterprise
# - Configure networking

# 2. Retrieve offsite backup
aws s3 cp s3://minio-backups/minio-backup-full-20260208_020000.tar.gz.gpg /tmp/

# 3. Decrypt backup
gpg --decrypt /tmp/minio-backup-full-20260208_020000.tar.gz.gpg > /tmp/backup.tar.gz

# 4. Restore
./scripts/restore/restore.sh --force /tmp/backup.tar.gz

# 5. Update DNS and networking
# - Point DNS to new servers
# - Update firewall rules
# - Test connectivity

# 6. Verify and resume operations
```

### Disaster Recovery Testing

Conduct DR tests quarterly:

```bash
# DR Test Checklist
# 1. Schedule maintenance window
# 2. Notify stakeholders
# 3. Document current state
# 4. Simulate disaster scenario
# 5. Execute restore procedure
# 6. Measure RTO/RPO achievement
# 7. Document lessons learned
# 8. Update procedures
```

---

## Troubleshooting

### Common Issues

#### Issue 1: Backup Fails with "Permission Denied"

**Symptoms**:
```
[ERROR] PostgreSQL backup failed
psql: error: connection to server failed: FATAL: password authentication failed
```

**Solution**:
```bash
# Check PostgreSQL password
echo $POSTGRES_PASSWORD

# Set password if missing
export POSTGRES_PASSWORD="your-password"

# Or use .pgpass file
cat > ~/.pgpass << EOF
localhost:5432:minio:minio:your-password
EOF
chmod 600 ~/.pgpass
```

#### Issue 2: Backup Directory Full

**Symptoms**:
```
[ERROR] No space left on device
tar: Error writing to archive
```

**Solution**:
```bash
# Check disk space
df -h /var/backups/minio

# Clean up old backups manually
find /var/backups/minio -name "minio-backup-*" -mtime +30 -delete

# Or adjust retention policy
RETENTION_DAYS=7  # Reduce retention period
```

#### Issue 3: Restore Fails - Checksum Mismatch

**Symptoms**:
```
[ERROR] Checksum verification failed
Expected: abc123...
Actual: def456...
```

**Solution**:
```bash
# Backup may be corrupted
# Try alternate backup
ls -lt /var/backups/minio/

# Or restore from offsite
aws s3 ls s3://minio-backups/
aws s3 cp s3://minio-backups/minio-backup-full-20260207_020000.tar.gz /tmp/

# Restore from downloaded backup
./scripts/restore/restore.sh --verify /tmp/minio-backup-full-20260207_020000.tar.gz
```

#### Issue 4: Redis Restore Fails

**Symptoms**:
```
[WARNING] Cannot control Redis service, manual restore required
```

**Solution**:
```bash
# Manual Redis restore
sudo systemctl stop redis
sudo cp /tmp/restore/redis/dump.rdb /var/lib/redis/dump.rdb
sudo chown redis:redis /var/lib/redis/dump.rdb
sudo systemctl start redis

# Verify Redis is working
redis-cli ping
# Expected: PONG
```

#### Issue 5: S3 Upload Timeout

**Symptoms**:
```
[ERROR] S3 upload failed
ReadTimeout: Read timeout on endpoint URL
```

**Solution**:
```bash
# Increase timeout
export AWS_CLI_READ_TIMEOUT=300

# Or use multipart upload for large files
aws configure set default.s3.max_concurrent_requests 10
aws configure set default.s3.multipart_threshold 100MB

# Retry upload
./scripts/backup/backup.sh --s3
```

### Verification Commands

```bash
# Verify backup integrity
tar -tzf /var/backups/minio/minio-backup-full-20260208_020000.tar.gz > /dev/null
echo "Archive OK: $?"

# Verify PostgreSQL dump
pg_restore --list /var/backups/minio/backup/database/minio.sql

# Verify Redis dump
redis-check-rdb /var/backups/minio/backup/redis/dump.rdb

# Verify encryption
gpg --verify /var/backups/minio/backup.tar.gz.gpg
```

### Logging and Debugging

```bash
# Enable debug mode
set -x

# Run backup with detailed output
./scripts/backup/backup.sh --full --compress 2>&1 | tee /tmp/backup-debug.log

# Check system logs
journalctl -u minio-backup.service -n 100

# Check PostgreSQL logs
tail -f /var/log/postgresql/postgresql-16-main.log

# Check Redis logs
tail -f /var/log/redis/redis-server.log
```

---

## Summary

The MinIO Enterprise backup and restore system provides:

✅ **Comprehensive Coverage**: All critical components backed up
✅ **Flexible Options**: Full and incremental backups
✅ **Security**: Encryption and secure storage
✅ **Automation**: Cron-compatible scheduling
✅ **Verification**: Built-in integrity checks
✅ **Disaster Recovery**: Complete restore procedures
✅ **Monitoring**: Prometheus metrics and alerts

### Quick Reference

```bash
# Daily full backup
./scripts/backup/backup.sh --full --compress --verify

# Daily incremental
./scripts/backup/backup.sh --incremental --compress

# Offsite encrypted backup
./scripts/backup/backup.sh --full --compress --encrypt --s3

# Restore from backup
./scripts/restore/restore.sh --verify --rollback /var/backups/minio/latest

# Test restore (database only)
./scripts/restore/restore.sh --db-only --verify /var/backups/minio/latest
```

### Support

- **Documentation**: This guide and inline script help
- **Issues**: [GitHub Issues](https://github.com/abiolaogu/MinIO/issues)
- **Discussions**: [GitHub Discussions](https://github.com/abiolaogu/MinIO/discussions)

---

**Last Updated**: 2026-02-08
**Version**: 1.0.0
**Maintainer**: Development Team
