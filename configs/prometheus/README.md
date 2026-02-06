# AlertManager Configuration Guide

Complete guide for managing alerts in MinIO Enterprise using Prometheus AlertManager.

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Alert Rules](#alert-rules)
4. [AlertManager Configuration](#alertmanager-configuration)
5. [Notification Channels](#notification-channels)
6. [Alert Management](#alert-management)
7. [Testing Alerts](#testing-alerts)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)

---

## Overview

MinIO Enterprise includes comprehensive alerting through Prometheus AlertManager. The system monitors:

- **Performance**: Latency, replication lag, cache efficiency
- **Security**: Authentication failures, unauthorized access, security events
- **Operations**: CPU/memory usage, error rates, node health
- **Data Integrity**: Replication errors, cache corruption

### Architecture

```
┌─────────────┐      ┌──────────────┐      ┌───────────────┐
│   MinIO     │────▶ │  Prometheus  │────▶ │ AlertManager  │
│   Cluster   │      │  (Metrics)   │      │  (Routing)    │
└─────────────┘      └──────────────┘      └───────────────┘
                            │                       │
                            ▼                       ▼
                     ┌──────────────┐      ┌───────────────┐
                     │   Grafana    │      │ Notifications │
                     │ (Dashboards) │      │ Email/Slack   │
                     └──────────────┘      └───────────────┘
```

---

## Quick Start

### 1. Deploy the Monitoring Stack

```bash
# Navigate to Docker deployment directory
cd deployments/docker

# Start the full stack (includes AlertManager)
docker-compose -f docker-compose.production.yml up -d

# Verify AlertManager is running
docker-compose -f docker-compose.production.yml ps alertmanager

# Check AlertManager logs
docker-compose -f docker-compose.production.yml logs -f alertmanager
```

### 2. Access AlertManager UI

Open in your browser: **http://localhost:9093**

The AlertManager UI shows:
- Active alerts
- Silenced alerts
- Alert history
- Configuration status

### 3. Verify Alert Rules

```bash
# Check Prometheus has loaded alert rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].name'

# Expected output:
# "performance_alerts"
# "security_alerts"
# "operations_alerts"
# "cluster_health_alerts"
# "data_integrity_alerts"
```

### 4. View Alerts in Grafana

1. Open Grafana: **http://localhost:3000**
2. Navigate to: **Alerting → Alert rules**
3. View alert status on dashboards:
   - Performance Dashboard
   - Security Dashboard
   - Operations Dashboard

---

## Alert Rules

### Alert Categories

#### 1. Performance Alerts (`performance_alerts`)

| Alert Name | Threshold | Duration | Severity | Description |
|------------|-----------|----------|----------|-------------|
| **HighP99Latency** | >50ms | 5m | Warning | P99 latency exceeds threshold |
| **HighReplicationLag** | >100ms | 5m | Warning | Replication lag too high |
| **LowCacheHitRate** | <70% | 10m | Warning | Cache efficiency degraded |
| **DegradedClusterPerformance** | <1000 req/s | 10m | Warning | Cluster throughput below baseline |

#### 2. Security Alerts (`security_alerts`)

| Alert Name | Threshold | Duration | Severity | Description |
|------------|-----------|----------|----------|-------------|
| **HighAuthFailureRate** | >20% | 5m | Critical | High authentication failure rate |
| **HighSecurityEvents** | >10/sec | 5m | Critical | Security event spike detected |
| **UnauthorizedAccessAttempts** | >5/sec | 3m | Warning | Unauthorized access attempts |
| **HighAPIErrorRate** | >10% | 5m | Warning | High API error rate |

#### 3. Operations Alerts (`operations_alerts`)

| Alert Name | Threshold | Duration | Severity | Description |
|------------|-----------|----------|----------|-------------|
| **HighCPUUsage** | >80% | 10m | Warning | CPU usage high |
| **HighErrorRate** | >10/sec | 5m | Critical | System error rate high |
| **NodeDown** | N/A | 2m | Critical | MinIO node unreachable |
| **HighMemoryUsage** | >14GB | 10m | Warning | Memory usage high |
| **DiskSpaceLow** | >85% | 5m | Warning | Disk space running low |

#### 4. Cluster Health Alerts (`cluster_health_alerts`)

| Alert Name | Threshold | Duration | Severity | Description |
|------------|-----------|----------|----------|-------------|
| **ClusterQuorumLost** | <3 nodes | 2m | Critical | Cluster quorum lost |

#### 5. Data Integrity Alerts (`data_integrity_alerts`)

| Alert Name | Threshold | Duration | Severity | Description |
|------------|-----------|----------|----------|-------------|
| **ReplicationErrors** | >1/sec | 5m | Critical | Replication errors detected |
| **CacheCorruption** | >0 | 1m | Critical | Cache corruption detected |

### Alert Rule Location

**File**: `/configs/prometheus/rules/minio_alerts.yml`

### Modifying Alert Rules

1. Edit the alert rules file:
```bash
vim configs/prometheus/rules/minio_alerts.yml
```

2. Reload Prometheus configuration:
```bash
# Hot reload without restart
curl -X POST http://localhost:9090/-/reload

# Or restart Prometheus
docker-compose -f deployments/docker/docker-compose.production.yml restart prometheus
```

3. Verify changes:
```bash
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[].name'
```

---

## AlertManager Configuration

### Configuration File

**Location**: `/configs/prometheus/alertmanager.yml`

### Key Configuration Sections

#### 1. Global Settings

```yaml
global:
  resolve_timeout: 5m  # Time before resolved alerts are removed
  # SMTP settings for email notifications (configure if needed)
```

#### 2. Routing Tree

```yaml
route:
  receiver: 'default-receiver'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 30s       # Wait before first notification
  group_interval: 5m    # Wait before notification about new alerts
  repeat_interval: 4h   # Wait before re-sending notification
```

**Child Routes**:
- **Critical Alerts**: 10s group_wait, 1h repeat
- **Performance Alerts**: 10m group_interval, 12h repeat
- **Security Alerts**: 10s group_wait, 2h repeat
- **Operations Alerts**: 10m group_interval, 6h repeat

#### 3. Inhibition Rules

Suppress redundant notifications:

```yaml
inhibit_rules:
  # Suppress all alerts if cluster is down
  - source_match:
      alertname: 'ClusterDown'
    target_match_re:
      alertname: '.*'

  # Suppress warnings if critical alert is firing
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
```

#### 4. Receivers

Notification endpoints by team:
- `critical-alerts`: Critical issues → Multiple channels
- `performance-team`: Performance issues
- `security-team`: Security incidents
- `operations-team`: Operational issues

---

## Notification Channels

### Available Integrations

AlertManager supports multiple notification channels. Configure in `/configs/prometheus/alertmanager.yml`.

### 1. Email Notifications

```yaml
global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'alerts@minio-enterprise.com'
  smtp_auth_username: 'alerts@minio-enterprise.com'
  smtp_auth_password: 'your-smtp-password'
  smtp_require_tls: true

receivers:
  - name: 'critical-alerts'
    email_configs:
      - to: 'oncall@minio-enterprise.com'
        subject: '[CRITICAL] MinIO Alert: {{ .GroupLabels.alertname }}'
        html: |
          <h2>Critical Alert Fired</h2>
          <p><strong>Alert:</strong> {{ .GroupLabels.alertname }}</p>
          <p><strong>Summary:</strong> {{ .CommonAnnotations.summary }}</p>
```

### 2. Slack Notifications

```yaml
receivers:
  - name: 'critical-alerts'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
        channel: '#critical-alerts'
        title: '[CRITICAL] {{ .GroupLabels.alertname }}'
        text: |
          *Alert:* {{ .GroupLabels.alertname }}
          *Severity:* {{ .CommonLabels.severity }}
          *Summary:* {{ .CommonAnnotations.summary }}
```

**Setup Steps**:
1. Create Slack Incoming Webhook: https://api.slack.com/messaging/webhooks
2. Copy webhook URL to `api_url` field
3. Configure channel name
4. Reload AlertManager config

### 3. PagerDuty Integration

```yaml
receivers:
  - name: 'critical-alerts'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_SERVICE_KEY'
        description: '{{ .GroupLabels.alertname }}: {{ .CommonAnnotations.summary }}'
```

**Setup Steps**:
1. Create PagerDuty service integration
2. Copy integration key to `service_key` field
3. Reload AlertManager config

### 4. Webhook Integration

```yaml
receivers:
  - name: 'critical-alerts'
    webhook_configs:
      - url: 'http://localhost:5001/webhook/critical'
        send_resolved: true
```

**Use Cases**:
- Custom integrations
- Ticketing systems (Jira, ServiceNow)
- Chat platforms (Microsoft Teams, Discord)
- Custom automation workflows

---

## Alert Management

### Viewing Active Alerts

#### Via AlertManager UI

1. Open: **http://localhost:9093**
2. View active alerts with details
3. Filter by severity, category, or service

#### Via Prometheus UI

1. Open: **http://localhost:9090/alerts**
2. View alert rules and their current state
3. Check evaluation time and firing status

#### Via Grafana

1. Open: **http://localhost:3000**
2. Navigate to: **Alerting → Alert rules**
3. View alerts on specific dashboards

### Silencing Alerts

Temporarily suppress alert notifications during maintenance.

#### Via AlertManager UI

1. Go to: **http://localhost:9093/#/silences**
2. Click **New Silence**
3. Configure:
   - **Matchers**: `alertname=NodeDown` or `severity=warning`
   - **Duration**: e.g., 2h
   - **Creator**: Your name
   - **Comment**: "Scheduled maintenance"
4. Click **Create**

#### Via CLI

```bash
# Create silence for 2 hours
amtool silence add alertname=NodeDown \
  --duration=2h \
  --comment="Scheduled maintenance" \
  --alertmanager.url=http://localhost:9093

# List active silences
amtool silence query --alertmanager.url=http://localhost:9093

# Expire silence by ID
amtool silence expire <SILENCE_ID> --alertmanager.url=http://localhost:9093
```

### Alert History

View past alerts and resolutions:

```bash
# Query alert history via Prometheus
curl -s 'http://localhost:9090/api/v1/query?query=ALERTS' | jq
```

---

## Testing Alerts

### 1. Manual Alert Testing

#### Simulate High CPU Usage

```bash
# Generate CPU load on a MinIO node
docker exec minio1 sh -c "dd if=/dev/zero of=/dev/null &"
# Wait for HighCPUUsage alert to fire (10 minutes)

# Stop CPU load
docker exec minio1 sh -c "killall dd"
```

#### Simulate Node Down

```bash
# Stop a MinIO node
docker-compose -f deployments/docker/docker-compose.production.yml stop minio1

# Wait for NodeDown alert to fire (2 minutes)
# Check AlertManager UI: http://localhost:9093

# Restart node
docker-compose -f deployments/docker/docker-compose.production.yml start minio1
```

#### Simulate Authentication Failures

```bash
# Send invalid authentication requests
for i in {1..100}; do
  curl -X GET http://localhost:9000/bucket-name \
    -H "Authorization: Bearer invalid-token"
  sleep 0.1
done

# Wait for HighAuthFailureRate alert to fire (5 minutes)
```

### 2. Alert Rule Validation

```bash
# Validate alert rules syntax
docker exec prometheus promtool check rules /etc/prometheus/rules/minio_alerts.yml

# Check alert evaluation
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | {name: .name, state: .state}'
```

### 3. End-to-End Testing

1. **Trigger Alert**: Use manual testing methods above
2. **Verify Alert Fires**: Check Prometheus UI (http://localhost:9090/alerts)
3. **Verify AlertManager**: Check AlertManager UI (http://localhost:9093)
4. **Verify Notification**: Check configured notification channel
5. **Resolve Alert**: Stop the triggering condition
6. **Verify Resolution**: Check alert resolves in AlertManager

---

## Troubleshooting

### Common Issues

#### 1. Alerts Not Firing

**Symptoms**: No alerts appear despite conditions being met

**Diagnosis**:
```bash
# Check Prometheus is scraping metrics
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .scrapePool, health: .health}'

# Check alert rules are loaded
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].name'

# Check for PromQL errors
docker-compose -f deployments/docker/docker-compose.production.yml logs prometheus | grep -i error
```

**Solutions**:
- Verify metrics are being collected
- Check alert rule syntax with `promtool`
- Ensure evaluation interval is appropriate
- Verify threshold values are correct

#### 2. AlertManager Not Receiving Alerts

**Symptoms**: Alerts fire in Prometheus but don't reach AlertManager

**Diagnosis**:
```bash
# Check Prometheus AlertManager config
curl -s http://localhost:9090/api/v1/alertmanagers | jq

# Check AlertManager is reachable
curl http://localhost:9093/-/healthy

# Check Prometheus logs
docker-compose -f deployments/docker/docker-compose.production.yml logs prometheus | grep alertmanager
```

**Solutions**:
- Verify AlertManager service is running
- Check `alerting.alertmanagers` in prometheus.yml
- Verify network connectivity between containers
- Check AlertManager logs for errors

#### 3. Notifications Not Sent

**Symptoms**: Alerts appear in AlertManager but notifications don't arrive

**Diagnosis**:
```bash
# Check AlertManager logs for notification errors
docker-compose -f deployments/docker/docker-compose.production.yml logs alertmanager | grep -i error

# Verify receiver configuration
curl -s http://localhost:9093/api/v1/status | jq '.data.config.receivers'

# Check for inhibited alerts
curl -s http://localhost:9093/api/v1/alerts | jq '.data[] | {labels: .labels, status: .status}'
```

**Solutions**:
- Verify notification channel configuration (SMTP, Slack, etc.)
- Check credentials and API keys
- Verify receiver names match in routes
- Check inhibition rules aren't suppressing alerts
- Test notification channel manually

#### 4. Too Many Notifications (Alert Fatigue)

**Symptoms**: Excessive notifications, alert spam

**Solutions**:
- Adjust alert thresholds (increase values or duration)
- Configure proper grouping (`group_by`)
- Increase `repeat_interval`
- Use inhibition rules to suppress redundant alerts
- Implement proper silencing during maintenance

#### 5. Alerts Resolve Too Slowly

**Symptoms**: Alerts stay firing after condition resolves

**Solutions**:
- Reduce `resolve_timeout` in AlertManager config
- Ensure metrics are updated frequently
- Check scrape interval in Prometheus config
- Verify `for` duration in alert rules

### Debugging Commands

```bash
# View AlertManager status
curl http://localhost:9093/api/v1/status | jq

# View all active alerts
curl http://localhost:9093/api/v1/alerts | jq

# View all silences
curl http://localhost:9093/api/v1/silences | jq

# Test AlertManager config
docker exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml

# Reload AlertManager config
curl -X POST http://localhost:9093/-/reload

# Reload Prometheus config
curl -X POST http://localhost:9090/-/reload
```

---

## Best Practices

### 1. Alert Design

✅ **DO**:
- Set appropriate thresholds based on actual baseline metrics
- Use `for` duration to avoid flapping alerts
- Include runbook links in annotations
- Add clear, actionable descriptions
- Group related alerts by labels
- Test alerts before deploying to production

❌ **DON'T**:
- Create alerts for every possible condition
- Set thresholds too aggressively (causes fatigue)
- Ignore alert annotations (they're critical for responders)
- Create overlapping alerts that fire simultaneously

### 2. Notification Strategy

✅ **DO**:
- Route critical alerts to on-call teams immediately
- Use escalation for unacknowledged critical alerts
- Group related alerts to reduce noise
- Configure different channels for different severity levels
- Send resolved notifications to confirm issues are fixed

❌ **DON'T**:
- Send all alerts to everyone
- Use same notification channel for all severity levels
- Ignore alert grouping (leads to spam)
- Skip testing notification integrations

### 3. Alert Maintenance

✅ **DO**:
- Review and tune alert thresholds regularly
- Document runbooks for each alert type
- Test alert rules after changes
- Monitor alert frequency (weekly/monthly reviews)
- Archive or remove obsolete alerts
- Version control alert configurations

❌ **DON'T**:
- Set and forget alerts
- Ignore frequently firing alerts
- Keep outdated alerts
- Make alert changes without testing

### 4. Team Coordination

✅ **DO**:
- Define clear ownership for alert categories
- Establish escalation procedures
- Document response procedures
- Use silences during planned maintenance
- Share alert insights in postmortems

❌ **DON'T**:
- Leave alert ownership undefined
- Ignore alerts during business hours
- Skip postmortem analysis
- Forget to communicate maintenance windows

### 5. Monitoring the Monitors

✅ **DO**:
- Monitor AlertManager availability
- Track alert notification delivery success rate
- Set up meta-alerts for monitoring infrastructure
- Monitor alert evaluation times
- Track silence usage

❌ **DON'T**:
- Assume monitoring is always working
- Ignore failed notifications
- Skip health checks on monitoring components

---

## Alert Severity Guidelines

| Severity | Response Time | Escalation | Examples |
|----------|--------------|------------|----------|
| **Critical** | Immediate | Page on-call | Node down, cluster quorum lost, high security events |
| **Warning** | 1 hour | Normal business hours | High CPU, low cache hit rate, disk space low |
| **Info** | Next business day | None | Informational metrics, trend alerts |

---

## Appendix

### A. Useful Resources

- [Prometheus Alerting Best Practices](https://prometheus.io/docs/practices/alerting/)
- [AlertManager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [PromQL Query Examples](https://prometheus.io/docs/prometheus/latest/querying/examples/)

### B. Alert Rule Template

```yaml
- alert: AlertName
  expr: prometheus_query > threshold
  for: 5m
  labels:
    severity: warning|critical
    category: performance|security|operations
    service: minio
    component: specific_component
  annotations:
    summary: "Brief description"
    description: "Detailed description with value: {{ $value }}"
    dashboard: "dashboard-name"
    runbook: "https://docs.minio-enterprise.com/runbooks/alert-name"
    action: "Recommended action"
```

### C. Contact & Support

- **GitHub Issues**: [MinIO Enterprise Issues](https://github.com/abiolaogu/MinIO/issues)
- **Documentation**: `/docs/` directory

---

**Document Version**: 1.0
**Last Updated**: 2026-02-06
**Maintainer**: DevOps Team
