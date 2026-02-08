# MinIO Enterprise - Systemd Timer Configuration

This directory contains systemd service and timer units for automated MinIO backups.

## Files

- `minio-backup.service` - Systemd service unit for backup execution
- `minio-backup.timer` - Systemd timer unit for scheduling backups
- `backup.env.example` - Example environment file for configuration

## Installation

### Step 1: Create Environment File

```bash
# Create configuration directory
sudo mkdir -p /etc/minio-enterprise

# Create environment file
sudo nano /etc/minio-enterprise/backup.env
```

Add the following (adjust as needed):
```bash
# Backup configuration
BACKUP_DIR=/var/backups/minio-enterprise
BACKUP_TYPE=full
RETENTION_DAYS=30
ENABLE_COMPRESSION=true
ENABLE_ENCRYPTION=true

# Encryption key (IMPORTANT: Keep secure!)
ENCRYPTION_KEY=YourSecureP@ssw0rd123!

# S3 backup (optional)
S3_BACKUP=false
S3_ENDPOINT=https://s3.amazonaws.com
S3_BUCKET=minio-backups
S3_ACCESS_KEY=your-access-key
S3_SECRET_KEY=your-secret-key

# Database credentials (usually auto-detected)
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=minio_db
POSTGRES_USER=minio_user

REDIS_HOST=redis
REDIS_PORT=6379
```

**Secure the environment file:**
```bash
sudo chmod 600 /etc/minio-enterprise/backup.env
sudo chown root:root /etc/minio-enterprise/backup.env
```

### Step 2: Install Systemd Units

```bash
# Copy service and timer files
sudo cp configs/systemd/minio-backup.service /etc/systemd/system/
sudo cp configs/systemd/minio-backup.timer /etc/systemd/system/

# Set correct permissions
sudo chmod 644 /etc/systemd/system/minio-backup.service
sudo chmod 644 /etc/systemd/system/minio-backup.timer

# Reload systemd
sudo systemctl daemon-reload
```

### Step 3: Enable and Start Timer

```bash
# Enable timer (start on boot)
sudo systemctl enable minio-backup.timer

# Start timer
sudo systemctl start minio-backup.timer

# Check timer status
sudo systemctl status minio-backup.timer

# List all timers
sudo systemctl list-timers
```

## Usage

### Check Timer Status

```bash
# View timer status
sudo systemctl status minio-backup.timer

# View next scheduled run
sudo systemctl list-timers minio-backup.timer
```

Output:
```
NEXT                          LEFT          LAST                          PASSED  UNIT                  ACTIVATES
Fri 2026-02-09 02:00:00 UTC   9h left       Thu 2026-02-08 02:00:00 UTC   14h ago minio-backup.timer    minio-backup.service
```

### Manual Backup Execution

```bash
# Run backup manually (doesn't affect timer schedule)
sudo systemctl start minio-backup.service

# Check backup status
sudo systemctl status minio-backup.service
```

### View Backup Logs

```bash
# View recent logs
sudo journalctl -u minio-backup.service -n 50

# Follow logs in real-time
sudo journalctl -u minio-backup.service -f

# View logs for specific date
sudo journalctl -u minio-backup.service --since "2026-02-08" --until "2026-02-09"

# View logs with timestamp
sudo journalctl -u minio-backup.service --since today -o short-iso
```

### Stop/Disable Timer

```bash
# Stop timer
sudo systemctl stop minio-backup.timer

# Disable timer (won't start on boot)
sudo systemctl disable minio-backup.timer

# Stop and disable
sudo systemctl disable --now minio-backup.timer
```

## Customization

### Change Backup Schedule

Edit the timer file:
```bash
sudo nano /etc/systemd/system/minio-backup.timer
```

Modify `OnCalendar` directive:

**Examples:**

```ini
# Daily at 2:00 AM
OnCalendar=*-*-* 02:00:00

# Daily at 2:00 AM and 2:00 PM
OnCalendar=*-*-* 02:00:00
OnCalendar=*-*-* 14:00:00

# Every 6 hours
OnCalendar=*-*-* 00,06,12,18:00:00

# Weekly on Sunday at 3:00 AM
OnCalendar=Sun *-*-* 03:00:00

# Monthly on 1st at 4:00 AM
OnCalendar=*-*-01 04:00:00

# Hourly
OnCalendar=hourly

# Every 30 minutes
OnCalendar=*:0/30
```

After editing, reload systemd:
```bash
sudo systemctl daemon-reload
sudo systemctl restart minio-backup.timer
```

### Add Email Notifications

Install mail utilities:
```bash
sudo apt-get install mailutils
```

Create notification script `/usr/local/bin/backup-notify.sh`:
```bash
#!/bin/bash
RESULT=$1
LOG_FILE="/var/backups/minio-enterprise/logs/backup-$(date +%Y%m%d)-*.log"

if [ "$RESULT" = "success" ]; then
    SUBJECT="MinIO Backup Successful"
    tail -20 $LOG_FILE | mail -s "$SUBJECT" admin@example.com
else
    SUBJECT="MinIO Backup FAILED"
    tail -50 $LOG_FILE | mail -s "$SUBJECT" admin@example.com
fi
```

Update service file:
```ini
[Service]
ExecStart=/home/runner/work/MinIO/MinIO/scripts/backup.sh --full
ExecStartPost=/usr/local/bin/backup-notify.sh success
ExecStopPost=/usr/local/bin/backup-notify.sh failure
```

### Multiple Backup Schedules

Create separate service/timer pairs:

**Daily Backup:**
```bash
sudo cp /etc/systemd/system/minio-backup.service /etc/systemd/system/minio-backup-daily.service
sudo cp /etc/systemd/system/minio-backup.timer /etc/systemd/system/minio-backup-daily.timer
```

Edit `minio-backup-daily.timer`:
```ini
OnCalendar=*-*-* 02:00:00
```

**Weekly Backup:**
```bash
sudo cp /etc/systemd/system/minio-backup.service /etc/systemd/system/minio-backup-weekly.service
sudo cp /etc/systemd/system/minio-backup.timer /etc/systemd/system/minio-backup-weekly.timer
```

Edit `minio-backup-weekly.timer`:
```ini
OnCalendar=Sun *-*-* 03:00:00
```

Edit `minio-backup-weekly.service` environment:
```ini
Environment="RETENTION_DAYS=90"
Environment="S3_BACKUP=true"
```

Enable both:
```bash
sudo systemctl enable --now minio-backup-daily.timer
sudo systemctl enable --now minio-backup-weekly.timer
```

## Monitoring

### Systemd Service Monitoring

Check if service is enabled:
```bash
systemctl is-enabled minio-backup.timer
```

Check if service is active:
```bash
systemctl is-active minio-backup.timer
```

### Integration with Prometheus

Export systemd metrics using `node_exporter`:

```bash
# Install node_exporter with systemd collector
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xzf node_exporter-1.7.0.linux-amd64.tar.gz
sudo cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
sudo chmod +x /usr/local/bin/node_exporter

# Create systemd service for node_exporter
sudo nano /etc/systemd/system/node_exporter.service
```

Add Prometheus scrape config:
```yaml
scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
```

Query metrics:
```promql
# Check if backup timer is active
node_systemd_unit_state{name="minio-backup.timer", state="active"}

# Check last backup time
node_systemd_timer_last_trigger_seconds{name="minio-backup.timer"}
```

### Alert on Backup Failures

Add to Prometheus alert rules:
```yaml
groups:
  - name: backup_alerts
    rules:
      - alert: MinIOBackupFailed
        expr: |
          time() - node_systemd_timer_last_trigger_seconds{name="minio-backup.timer"} > 86400 * 2
        for: 1h
        labels:
          severity: critical
        annotations:
          summary: "MinIO backup has not run in 2 days"
          description: "Last successful backup: {{ $value | humanizeDuration }} ago"
```

## Troubleshooting

### Timer Not Running

Check timer status:
```bash
sudo systemctl status minio-backup.timer
```

Check if timer is enabled:
```bash
sudo systemctl is-enabled minio-backup.timer
```

View timer next run:
```bash
sudo systemctl list-timers --all | grep minio
```

### Service Fails

View service logs:
```bash
sudo journalctl -u minio-backup.service -n 100 --no-pager
```

Test service manually:
```bash
sudo systemctl start minio-backup.service
sudo systemctl status minio-backup.service
```

Check script permissions:
```bash
ls -l /home/runner/work/MinIO/MinIO/scripts/backup.sh
# Should be: -rwxr-xr-x
```

### Environment Variables Not Loaded

Check environment file exists:
```bash
ls -l /etc/minio-enterprise/backup.env
```

Test environment loading:
```bash
sudo systemd-run --unit=test-backup --property=EnvironmentFile=/etc/minio-enterprise/backup.env /usr/bin/env
sudo journalctl -u test-backup
```

### Backup Directory Permission Issues

Ensure backup directory is writable:
```bash
sudo mkdir -p /var/backups/minio-enterprise
sudo chown root:root /var/backups/minio-enterprise
sudo chmod 755 /var/backups/minio-enterprise
```

## Best Practices

1. **Test First**: Always test timer and service before production use
2. **Monitor Logs**: Regularly check backup logs for errors
3. **Secure Credentials**: Keep encryption keys and environment files secure (chmod 600)
4. **Verify Backups**: Schedule verification jobs to test backup integrity
5. **Offsite Backups**: Enable S3 backup for disaster recovery
6. **Alert on Failures**: Configure monitoring and alerting
7. **Document**: Keep recovery procedures documented
8. **Test Restores**: Quarterly disaster recovery drills

## References

- [systemd.timer](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)
- [systemd.service](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [systemd.time](https://www.freedesktop.org/software/systemd/man/systemd.time.html)
- [MinIO Backup & Restore Guide](../docs/guides/BACKUP_RESTORE.md)

---

**Last Updated**: 2026-02-08
**Status**: Production Ready
