# MinIO Enterprise - Restore Scripts

## Quick Start

```bash
# Make script executable
chmod +x restore.sh

# List available backups
./restore.sh --list

# Interactive restore
./restore.sh

# Dry run (preview only)
./restore.sh --dry-run minio_backup_20260209_120000

# Force restore without prompts
./restore.sh --force minio_backup_20260209_120000
```

## Files

- **restore.sh** - Main restore script
- **restore.conf** - Configuration file

## Common Operations

```bash
# Restore specific backup
./restore.sh minio_backup_20260209_120000

# Restore only PostgreSQL
./restore.sh --postgres-only minio_backup_20260209_120000

# Restore only MinIO objects
./restore.sh --minio-only minio_backup_20260209_120000

# Restore without snapshot (not recommended)
./restore.sh --no-snapshot minio_backup_20260209_120000
```

## Configuration

Edit `restore.conf` or use environment variables:

```bash
# Dry run mode
DRY_RUN=true ./restore.sh

# Force restore
FORCE_RESTORE=true ./restore.sh minio_backup_20260209_120000

# Skip snapshot
CREATE_SNAPSHOT=false ./restore.sh minio_backup_20260209_120000
```

## Safety Features

- **Pre-restore Snapshot**: Automatic snapshot before restore (enables rollback)
- **Verification**: Post-restore health checks
- **Confirmation Prompts**: User confirmation before overwriting data
- **Rollback**: Automatic rollback offer on failure

## Documentation

See [BACKUP_RESTORE.md](../../docs/guides/BACKUP_RESTORE.md) for complete documentation.
