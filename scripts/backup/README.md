# MinIO Enterprise Backup & Restore Scripts

## Quick Start

### Running Your First Backup

```bash
# 1. Make scripts executable
chmod +x backup.sh restore.sh test_backup_restore.sh

# 2. Configure backup settings
cp backup.conf.example backup.conf
nano backup.conf

# 3. Run backup
sudo ./backup.sh
```

### Restoring from Backup

```bash
# 1. Navigate to restore directory
cd ../restore

# 2. Run restore (interactive)
sudo ./restore.sh /var/backups/minio-enterprise/minio-backup-full-20240118_120000.tar.gz.enc
```

## Directory Structure

```
scripts/
├── backup/
│   ├── backup.sh              # Main backup script
│   ├── backup.conf            # Configuration file
│   ├── test_backup_restore.sh # Test suite
│   └── README.md              # This file
└── restore/
    └── restore.sh             # Main restore script
```

## Documentation

For comprehensive documentation, see:

- **Full Guide**: [docs/guides/BACKUP_RESTORE.md](../../docs/guides/BACKUP_RESTORE.md)
- **Main README**: [README.md](../../README.md)
- **PRD**: [docs/PRD.md](../../docs/PRD.md)

## Testing

Run the test suite to verify backup and restore functionality:

```bash
chmod +x test_backup_restore.sh
./test_backup_restore.sh
```

## Common Commands

### Backup Commands

```bash
# Full backup
sudo ./backup.sh

# Incremental backup
BACKUP_TYPE=incremental sudo -E ./backup.sh

# Encrypted backup
ENCRYPTION=true ENCRYPTION_KEY="your-key" sudo -E ./backup.sh

# Backup to S3
S3_BACKUP=true S3_BUCKET="my-bucket" sudo -E ./backup.sh
```

### Restore Commands

```bash
# Full restore
sudo ./restore.sh /path/to/backup.tar.gz.enc

# Partial restore
sudo ./restore.sh /path/to/backup.tar.gz --components postgresql,redis

# Force restore (no confirmation)
sudo ./restore.sh /path/to/backup.tar.gz --force
```

## Support

For issues or questions:

- **GitHub Issues**: [Create an issue](https://github.com/abiolaogu/MinIO/issues)
- **Documentation**: [Full Backup & Restore Guide](../../docs/guides/BACKUP_RESTORE.md)
