# Prometheus AlertManager Configuration for MinIO Enterprise

This directory contains the complete alerting configuration for MinIO Enterprise, including AlertManager setup, alert rules, and notification templates.

## 📁 Contents

- **`alertmanager.yml`** - AlertManager configuration (routing, receivers, inhibition)
- **`alert_rules.yml`** - Prometheus alert rules definitions (37 alerts across 6 categories)
- **`email_template.tmpl`** - HTML email template for alert notifications
- **`README.md`** - This documentation file

---

## 🚀 Quick Start

### 1. Configure Environment Variables

Set the following environment variables for notification channels:

```bash
# Email notifications
export SMTP_PASSWORD="your-smtp-password"

# Slack notifications
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# PagerDuty notifications
export PAGERDUTY_SERVICE_KEY="your-pagerduty-service-key"
```

Or create a `.env` file in `deployments/docker/`:

```bash
# deployments/docker/.env
SMTP_PASSWORD=your-smtp-password
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
PAGERDUTY_SERVICE_KEY=your-pagerduty-service-key
```

### 2. Update Email Addresses

Edit `alertmanager.yml` and replace example email addresses with your team's addresses:

```yaml
# Search and replace these addresses:
ops-team@example.com           → your-ops-team@company.com
performance-team@example.com   → your-performance-team@company.com
security-team@example.com      → your-security-team@company.com
```

### 3. Update Slack Channels

Edit `alertmanager.yml` and update Slack channel names:

```yaml
# Update these channels to match your Slack workspace:
#minio-critical-alerts    → your channel
#minio-alerts            → your channel
#minio-performance       → your channel
#minio-security          → your channel
#minio-operations        → your channel
```

### 4. Deploy the Stack

```bash
cd deployments/docker
docker-compose -f docker-compose.production.yml up -d
```

### 5. Verify AlertManager is Running

```bash
# Check AlertManager status
docker-compose -f docker-compose.production.yml ps alertmanager

# View AlertManager logs
docker-compose -f docker-compose.production.yml logs -f alertmanager

# Access AlertManager UI
open http://localhost:9093
```

---

## 📊 Alert Categories

### 1. Performance Alerts (6 alerts)
Monitor system performance and identify bottlenecks.

| Alert | Threshold | Severity | Description |
|-------|-----------|----------|-------------|
| `HighP99Latency` | >50ms for 5min | HIGH | API P99 latency exceeds threshold |
| `HighReplicationLag` | >100ms for 5min | HIGH | Replication lag exceeds threshold |
| `LowCacheHitRate` | <70% for 10min | WARNING | Cache efficiency degraded |
| `HighCacheEvictionRate` | >1000/sec for 5min | WARNING | High cache eviction rate |
| `LowThroughput` | <100 req/sec for 10min | WARNING | API throughput below threshold |
| `SlowReplicationSpeed` | <10MB/s for 10min | WARNING | Replication speed degraded |

### 2. Security Alerts (6 alerts)
Detect security threats and unauthorized access attempts.

| Alert | Threshold | Severity | Description |
|-------|-----------|----------|-------------|
| `HighAuthFailureRate` | >20% for 5min | HIGH | Authentication failures spike |
| `HighSecurityEvents` | >10/sec for 2min | HIGH | Security event rate elevated |
| `UnauthorizedAccessAttempts` | >5/sec for 5min | CRITICAL | Multiple unauthorized attempts |
| `SuspiciousAPIUsage` | >50 4xx/sec for 5min | WARNING | High 4xx error rate |
| `TokenValidationFailures` | >10/sec for 5min | HIGH | Token validation issues |
| `HighRateLimitingEvents` | >100/sec for 5min | WARNING | Rate limiting triggered |

### 3. Operations Alerts (10 alerts)
Monitor system resources and operational health.

| Alert | Threshold | Severity | Description |
|-------|-----------|----------|-------------|
| `HighCPUUsage` | >80% for 5min | HIGH | CPU utilization critical |
| `HighMemoryUsage` | >85% for 5min | HIGH | Memory usage critical |
| `HighDiskIO` | >80% for 5min | WARNING | Disk I/O saturated |
| `LowDiskSpace` | <15% free for 5min | CRITICAL | Disk space critically low |
| `HighErrorRate` | >10/sec for 5min | HIGH | API error rate elevated |
| `NodeDown` | Node down for 2min | CRITICAL | MinIO node unavailable |
| `ServiceUnavailable` | <2 nodes for 5min | CRITICAL | Insufficient nodes for HA |
| `HighGoroutineCount` | >10000 for 10min | WARNING | Goroutine leak suspected |
| `LongGCPauseTimes` | >100ms for 5min | WARNING | GC pause times elevated |
| `ConnectionPoolExhaustion` | >90% for 5min | HIGH | Connection pool near limit |

### 4. Cluster Health Alerts (3 alerts)
Monitor cluster-wide health and consistency.

| Alert | Threshold | Severity | Description |
|-------|-----------|----------|-------------|
| `ClusterDegraded` | <4 nodes for 5min | HIGH | Cluster operating degraded |
| `SplitBrain` | Multiple cluster IDs | CRITICAL | Split-brain detected |
| `DataInconsistency` | >0 errors for 1min | CRITICAL | Data consistency violated |

### 5. Tenant Management Alerts (2 alerts)
Monitor multi-tenant operations and quotas.

| Alert | Threshold | Severity | Description |
|-------|-----------|----------|-------------|
| `TenantQuotaExceeded` | >95% quota for 5min | HIGH | Tenant near quota limit |
| `TenantIsolationViolation` | >0 violations | CRITICAL | Tenant isolation breach |

### 6. Replication Alerts (2 alerts)
Monitor replication health and performance.

| Alert | Threshold | Severity | Description |
|-------|-----------|----------|-------------|
| `ReplicationFailed` | >1 failure/sec for 5min | HIGH | Replication failures detected |
| `ReplicationQueueBacklog` | >10000 items for 10min | WARNING | Large replication backlog |

**Total: 37 alerts across 6 categories**

---

## 🔔 Notification Routing

### Routing Strategy

```
Alert → Severity/Category Match → Receiver(s) → Notification Channel(s)
```

### Routing Rules (in order of evaluation)

1. **Critical Alerts** → PagerDuty + Slack
   - Immediate notification
   - Group wait: 10s
   - Repeat: 1h

2. **High Severity** → Slack + Email
   - Group wait: 30s
   - Repeat: 2h

3. **Performance Alerts** → Performance Team (Email + Slack)
   - Group wait: 1m
   - Repeat: 3h

4. **Security Alerts** → Security Team (Email + Slack)
   - Group wait: 30s
   - Repeat: 1h

5. **Operations Alerts** → Operations Team (Email + Slack)
   - Group wait: 1m
   - Repeat: 3h

6. **Warning Alerts** → Email Only
   - Group wait: 5m
   - Repeat: 12h

7. **Info Alerts** → Daily Summary Email
   - Group wait: 12h
   - Repeat: 24h

### Alert Grouping

Alerts are grouped by:
- `alertname` - Same alert type
- `cluster` - Same cluster
- `service` - Same service
- `severity` - Same severity level

Additional grouping per category:
- Performance: `instance`
- Security: `tenant`
- Operations: `node`

---

## 🎯 Notification Channels

### Email Notifications

**Configuration** (in `alertmanager.yml`):
```yaml
smtp_smarthost: 'smtp.example.com:587'
smtp_from: 'alertmanager@minio-enterprise.com'
smtp_auth_username: 'alertmanager@minio-enterprise.com'
smtp_auth_password: '${SMTP_PASSWORD}'
smtp_require_tls: true
```

**Features**:
- HTML formatted emails with styling
- Alert statistics (firing/resolved counts)
- Detailed alert information
- Direct links to dashboards
- Responsive design

**Receivers**:
- `ops-team@example.com` - Default, warnings, daily summary
- `performance-team@example.com` - Performance alerts
- `security-team@example.com` - Security alerts

### Slack Notifications

**Configuration**:
```yaml
slack_api_url: '${SLACK_WEBHOOK_URL}'
```

**Channels**:
- `#minio-critical-alerts` - Critical severity (🔥 fire emoji)
- `#minio-alerts` - High severity (⚠️ warning emoji)
- `#minio-performance` - Performance alerts (📈 chart emoji)
- `#minio-security` - Security alerts (🛡️ shield emoji)
- `#minio-operations` - Operations alerts (⚙️ gear emoji)

**Features**:
- Color-coded messages (red/orange/blue)
- Emoji indicators
- Alert summary and details
- Resolved notifications

### PagerDuty Integration

**Configuration**:
```yaml
pagerduty_url: 'https://events.pagerduty.com/v2/enqueue'
service_key: '${PAGERDUTY_SERVICE_KEY}'
```

**Features**:
- Critical alerts only
- Auto-incident creation
- On-call escalation
- Mobile notifications

---

## 🚫 Alert Inhibition Rules

Inhibition rules prevent alert noise by suppressing lower-priority alerts when higher-priority ones are firing.

### Rule 1: Critical Suppresses Warning/Info
```yaml
source: severity=critical
target: severity=warning|info
equal: [alertname, cluster, instance]
```
**Example**: If `NodeDown` (critical) is firing, suppress `HighCPUUsage` (warning) for the same node.

### Rule 2: Cluster Down Suppresses Node Alerts
```yaml
source: alertname=ClusterDown
target: alertname matching Node.*
equal: [cluster]
```
**Example**: If entire cluster is down, don't alert on individual node issues.

### Rule 3: Node Down Suppresses Component Alerts
```yaml
source: alertname=NodeDown
target: alertname matching Cache.*|Replication.*
equal: [cluster, node]
```
**Example**: If node is down, don't alert on cache/replication issues for that node.

### Rule 4: Maintenance Mode Suppresses Performance Alerts
```yaml
source: alertname=MaintenanceMode
target: category=performance
equal: [cluster]
```
**Example**: During maintenance, suppress performance alerts.

---

## 🔧 Configuration Guide

### Customizing Alert Thresholds

Edit `alert_rules.yml` to adjust thresholds:

```yaml
# Example: Change High CPU threshold from 80% to 90%
- alert: HighCPUUsage
  expr: (100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)) > 90  # Changed
  for: 5m
```

### Adding New Alert Routes

Add to `alertmanager.yml` under `route.routes`:

```yaml
- match:
    team: 'database'
  receiver: 'database-team'
  group_wait: 30s
  repeat_interval: 2h
```

### Creating New Receivers

Add to `alertmanager.yml` under `receivers`:

```yaml
- name: 'database-team'
  email_configs:
    - to: 'database-team@example.com'
  slack_configs:
    - channel: '#database-alerts'
```

### Silencing Alerts

#### Via CLI:
```bash
# Silence all alerts for maintenance (2 hours)
amtool silence add alertname=~".+" --duration=2h --comment="Maintenance window"

# Silence specific alert
amtool silence add alertname="HighCPUUsage" instance="minio1:9000" --duration=1h
```

#### Via UI:
1. Go to http://localhost:9093
2. Click on "Silences"
3. Click "New Silence"
4. Configure matchers and duration

#### Via API:
```bash
curl -X POST http://localhost:9093/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [
      {"name": "alertname", "value": "HighCPUUsage", "isRegex": false}
    ],
    "startsAt": "2024-01-01T00:00:00Z",
    "endsAt": "2024-01-01T02:00:00Z",
    "comment": "Maintenance window",
    "createdBy": "admin"
  }'
```

---

## 📖 Testing Alerts

### 1. Test AlertManager Configuration

```bash
# Validate config syntax
docker exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml

# Test routing
docker exec alertmanager amtool config routes test \
  --config.file=/etc/alertmanager/alertmanager.yml \
  severity=critical alertname=TestAlert
```

### 2. Send Test Alert

```bash
# Send test alert to AlertManager
curl -X POST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[
    {
      "labels": {
        "alertname": "TestAlert",
        "severity": "critical",
        "category": "test",
        "cluster": "minio-enterprise",
        "instance": "test:9000"
      },
      "annotations": {
        "summary": "This is a test alert",
        "description": "Testing AlertManager configuration"
      }
    }
  ]'
```

### 3. Trigger Real Alert

```bash
# Trigger HighCPUUsage by simulating load
docker exec minio1 sh -c 'yes > /dev/null &'

# Wait 5 minutes for alert to fire
# Check Prometheus: http://localhost:9090/alerts
# Check AlertManager: http://localhost:9093
```

---

## 🔍 Monitoring & Troubleshooting

### Check AlertManager Status

```bash
# View AlertManager logs
docker-compose -f docker-compose.production.yml logs -f alertmanager

# Check AlertManager health
curl http://localhost:9093/-/healthy

# View current alerts
curl http://localhost:9093/api/v2/alerts | jq

# View active silences
curl http://localhost:9093/api/v2/silences | jq
```

### Check Prometheus Alert Status

```bash
# View all configured alerts
curl http://localhost:9090/api/v1/rules | jq

# View firing alerts
curl http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.state=="firing")'

# Reload Prometheus config
curl -X POST http://localhost:9090/-/reload
```

### Common Issues

#### Issue: Alerts not firing
**Diagnosis**:
```bash
# Check if Prometheus is evaluating rules
curl http://localhost:9090/api/v1/rules

# Check if metrics exist
curl 'http://localhost:9090/api/v1/query?query=up{job="minio"}'
```

**Solutions**:
- Verify alert rules syntax in `alert_rules.yml`
- Ensure metrics are being scraped
- Check `evaluation_interval` in Prometheus config
- Reload Prometheus config: `curl -X POST http://localhost:9090/-/reload`

#### Issue: Notifications not sent
**Diagnosis**:
```bash
# Check AlertManager logs for errors
docker logs alertmanager 2>&1 | grep -i error

# Test routing
docker exec alertmanager amtool config routes test severity=critical
```

**Solutions**:
- Verify environment variables are set (SMTP_PASSWORD, SLACK_WEBHOOK_URL)
- Check receiver configuration in `alertmanager.yml`
- Test notification channels manually
- Check inhibition rules aren't blocking alerts

#### Issue: Too many notifications
**Diagnosis**:
```bash
# Check alert frequency
curl http://localhost:9093/api/v2/alerts | jq '.[] | .labels.alertname' | sort | uniq -c
```

**Solutions**:
- Adjust `repeat_interval` in routing rules
- Add inhibition rules to reduce noise
- Increase alert thresholds if too sensitive
- Use alert grouping more effectively

#### Issue: AlertManager not receiving alerts from Prometheus
**Diagnosis**:
```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="alertmanager")'

# Check AlertManager in Prometheus config
docker exec prometheus cat /etc/prometheus/prometheus.yml | grep -A5 alerting
```

**Solutions**:
- Verify AlertManager target in `prometheus.yml`
- Check network connectivity: `docker exec prometheus ping alertmanager`
- Restart Prometheus: `docker-compose restart prometheus`

---

## 🎨 Customizing Email Templates

The email template is located at `email_template.tmpl` and uses Go's text/template syntax.

### Available Variables

```go
.GroupLabels     // Alert group labels
.CommonLabels    // Common labels across alerts
.Alerts          // All alerts
.Alerts.Firing   // Currently firing alerts
.Alerts.Resolved // Recently resolved alerts
.ExternalURL     // AlertManager URL
```

### Example Customization

```html
<!-- Add company logo -->
<div class="header">
    <img src="https://your-company.com/logo.png" alt="Logo" style="height: 50px;">
    <h1>🚨 MinIO Enterprise Alert</h1>
</div>

<!-- Add custom footer -->
<div class="footer">
    <p>Your Company Name | IT Operations</p>
    <p>On-Call: +1-555-123-4567</p>
</div>
```

---

## 📚 Best Practices

### 1. Alert Design
- ✅ **Alert on symptoms, not causes** - Alert on high latency, not high CPU
- ✅ **Set appropriate thresholds** - Balance between noise and missed issues
- ✅ **Include runbook links** - Help on-call engineers respond quickly
- ✅ **Use meaningful descriptions** - Include actual values and thresholds

### 2. Notification Management
- ✅ **Route by severity** - Critical → PagerDuty, Warning → Email
- ✅ **Use inhibition rules** - Reduce alert noise during incidents
- ✅ **Group related alerts** - Prevent notification storms
- ✅ **Set reasonable repeat intervals** - Don't spam on-call engineers

### 3. Maintenance
- ✅ **Use silences during maintenance** - Prevent false alerts
- ✅ **Review alert fatigue** - Tune overly sensitive alerts
- ✅ **Test notification channels** - Ensure they work before incidents
- ✅ **Document runbooks** - Make alerts actionable

### 4. Monitoring the Monitors
- ✅ **Monitor AlertManager health** - Alert if AlertManager is down
- ✅ **Track alert resolution time** - Measure MTTR
- ✅ **Review alert trends** - Identify recurring issues
- ✅ **Audit notification delivery** - Ensure alerts reach the right people

---

## 🔗 Related Documentation

- [Grafana Dashboards](../grafana/dashboards/README.md) - Custom dashboards with integrated alerts
- [Prometheus Configuration](../../deployments/docker/prometheus.yml) - Prometheus scrape config
- [Docker Compose Setup](../../deployments/docker/docker-compose.production.yml) - Full stack deployment
- [Performance Guide](../../docs/guides/PERFORMANCE.md) - Performance optimization tips
- [Operations Guide](../../docs/guides/DEPLOYMENT.md) - Deployment and operations

---

## 🆘 Support

For issues or questions:
- **GitHub Issues**: https://github.com/abiolaogu/MinIO/issues
- **Documentation**: https://docs.minio-enterprise.com
- **On-Call Escalation**: See your team's on-call schedule

---

## 📝 Configuration Summary

| Component | Port | URL |
|-----------|------|-----|
| AlertManager UI | 9093 | http://localhost:9093 |
| Prometheus | 9090 | http://localhost:9090 |
| Grafana | 3000 | http://localhost:3000 |
| MinIO | 9000 | http://localhost:9000 |

| Configuration File | Purpose |
|-------------------|---------|
| `alertmanager.yml` | AlertManager routing and receivers |
| `alert_rules.yml` | Prometheus alert definitions (37 alerts) |
| `email_template.tmpl` | HTML email notification template |

| Environment Variable | Required | Purpose |
|---------------------|----------|---------|
| `SMTP_PASSWORD` | No | Email notifications password |
| `SLACK_WEBHOOK_URL` | No | Slack webhook for notifications |
| `PAGERDUTY_SERVICE_KEY` | No | PagerDuty integration key |

---

**Last Updated**: 2026-02-06
**Version**: 1.0
**Status**: Production Ready
