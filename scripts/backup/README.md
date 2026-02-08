# MinIO Enterprise Backup Scripts

Automated backup and restore tools for MinIO Enterprise deployments.

## Quick Start

```bash
# 1. Configure backup settings
cp backup.conf backup.local.conf
nano backup.local.conf

# 2. Set required environment variables
export POSTGRES_PASSWORD="your-secure-password"

# 3. Run your first backup
./backup.sh --full --verify

# 4. Verify backup was created
ls -lh /var/backups/minio/
```

## Scripts

### backup.sh

Performs automated backups of MinIO data, PostgreSQL database, Redis state, and configuration files.

**Features**:
- Full and incremental backups
- Compression (gzip)
- Encryption (GPG)
- S3 offsite storage
- Integrity verification
- Automatic retention management

**Usage**:
```bash
./backup.sh [OPTIONS]

Options:
  --full          Full backup (default)
  --incremental   Incremental since last full
  --compress      Enable compression
  --encrypt       Enable encryption
  --verify        Verify after creation
  --s3            Upload to S3
  --help          Show help
```

**Examples**:
```bash
# Simple full backup
./backup.sh --full

# Production backup (compressed, verified, offsite)
./backup.sh --full --compress --verify --s3

# Daily incremental backup
./backup.sh --incremental --compress --s3
```

### Configuration

Edit `backup.conf` or create `backup.local.conf`:

```bash
# Paths
BACKUP_DIR="/var/backups/minio"
MINIO_DATA_DIR="/data/minio"

# Retention
RETENTION_DAYS=30
RETENTION_FULL_BACKUPS=4

# Database
POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"
POSTGRES_DB="minio"
POSTGRES_USER="minio"

# Redis
REDIS_HOST="localhost"
REDIS_PORT="6379"

# S3 (offsite)
S3_ENDPOINT="https://s3.amazonaws.com"
S3_BUCKET="minio-backups"

# Security
GPG_RECIPIENT="backup@example.com"
```

## Automation

### Cron Setup

```bash
# Edit crontab
crontab -e

# Add backup jobs
# Full backup: Sunday 2 AM
0 2 * * 0 /opt/minio/scripts/backup/backup.sh --full --compress --verify --s3

# Incremental: Mon-Sat 2 AM
0 2 * * 1-6 /opt/minio/scripts/backup/backup.sh --incremental --compress --s3
```

### Systemd Timer

See [BACKUP_RESTORE.md](../../docs/guides/BACKUP_RESTORE.md#systemd-timer-alternative) for systemd timer setup.

## Security

### Encryption Setup

```bash
# Generate GPG key
gpg --full-generate-key

# List keys
gpg --list-keys

# Update configuration
GPG_RECIPIENT="your-email@example.com"

# Run encrypted backup
./backup.sh --full --encrypt
```

### Password Management

**Never store passwords in configuration files!**

Use environment variables:
```bash
export POSTGRES_PASSWORD="secure-password"
export S3_ACCESS_KEY="access-key"
export S3_SECRET_KEY="secret-key"
```

Or use secrets management:
```bash
# AWS Secrets Manager
export POSTGRES_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id minio/postgres --query SecretString --output text)

# HashiCorp Vault
export POSTGRES_PASSWORD=$(vault kv get -field=password secret/minio/postgres)
```

## Monitoring

### Check Last Backup

```bash
# Find latest backup
ls -lt /var/backups/minio/ | head -5

# Check backup size
du -sh /var/backups/minio/minio-backup-full-*

# View backup metadata
cat /var/backups/minio/minio-backup-full-20260208_020000/metadata/backup.info
```

### Prometheus Metrics

Backups export metrics for Prometheus monitoring:

- `minio_backup_age_seconds`: Age of last successful backup
- `minio_backup_size_bytes`: Size of last backup
- `minio_backup_last_success_timestamp`: Unix timestamp of last backup

### Alerts

Configure alerts for backup monitoring:

- Backup too old (>48 hours)
- Backup size anomalous (>50% deviation)
- Backup metrics missing

See [BACKUP_RESTORE.md](../../docs/guides/BACKUP_RESTORE.md#monitoring-backup-success) for alert configuration.

## Troubleshooting

### Common Issues

**Permission Denied**:
```bash
# Check PostgreSQL password
echo $POSTGRES_PASSWORD

# Or use .pgpass
cat > ~/.pgpass << EOF
localhost:5432:minio:minio:password
EOF
chmod 600 ~/.pgpass
```

**Disk Full**:
```bash
# Check space
df -h /var/backups/minio

# Clean old backups
find /var/backups/minio -name "minio-backup-*" -mtime +30 -delete
```

**S3 Upload Fails**:
```bash
# Check credentials
aws s3 ls s3://$S3_BUCKET/

# Test upload
echo "test" > /tmp/test.txt
aws s3 cp /tmp/test.txt s3://$S3_BUCKET/test.txt --endpoint-url $S3_ENDPOINT
```

### Debug Mode

```bash
# Enable bash debugging
bash -x backup.sh --full 2>&1 | tee backup-debug.log
```

## Testing

### Verify Backup Script

```bash
# Dry run (check prerequisites only)
./backup.sh --help

# Test backup to /tmp
./backup.sh --full --output /tmp/test-backup --verify

# Verify archive
tar -tzf /tmp/test-backup/minio-backup-full-*.tar.gz
```

### Test Restore

**WARNING**: Test restore in a safe environment first!

```bash
# Restore to test environment
cd ../restore
./restore.sh --verify /var/backups/minio/minio-backup-full-20260208_020000
```

## Documentation

Full documentation available at:
- [Backup & Restore Guide](../../docs/guides/BACKUP_RESTORE.md)
- [Disaster Recovery](../../docs/guides/BACKUP_RESTORE.md#disaster-recovery)
- [Best Practices](../../docs/guides/BACKUP_RESTORE.md#best-practices)

## Support

- **Issues**: [GitHub Issues](https://github.com/abiolaogu/MinIO/issues)
- **Discussions**: [GitHub Discussions](https://github.com/abiolaogu/MinIO/discussions)

---

**Version**: 1.0.0
**Last Updated**: 2026-02-08
