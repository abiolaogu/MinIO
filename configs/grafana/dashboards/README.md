# MinIO Enterprise Grafana Dashboards

This directory contains comprehensive Grafana dashboards for monitoring MinIO Enterprise performance, security, and operations.

## Available Dashboards

### 1. Performance Dashboard (`performance-dashboard.json`)

**Purpose**: Monitor system performance metrics, cache efficiency, and throughput.

**Key Metrics**:
- **Operations Throughput**: PUT, GET, DELETE, LIST operations per second
- **Cache Performance**: Hit/miss rates, cache efficiency percentage
- **API Latency**: P50, P90, P95, P99 percentile latencies
- **Replication Performance**: Replication lag, throughput, and errors
- **Storage Metrics**: Total bytes stored, object count

**Alerts Configured**:
- High P99 Latency (threshold: 50ms)
- High Replication Lag (threshold: 100ms)

**Recommended For**: Performance optimization, capacity planning, troubleshooting slow requests

---

### 2. Security Dashboard (`security-dashboard.json`)

**Purpose**: Monitor authentication events, access patterns, and security incidents.

**Key Metrics**:
- **Authentication Events**: Success/failure rates, failure patterns
- **Access Pattern Analysis**: Request patterns by tenant
- **Security Events**: Unauthorized access, invalid tokens, quota exceeded, rate limiting
- **API Error Rates**: 4xx and 5xx errors by status code
- **Active Sessions**: Current session count
- **Audit Log Volume**: Audit trail activity

**Alerts Configured**:
- High Authentication Failure Rate (threshold: 20%)
- High Security Events (threshold: 10 events/sec)

**Recommended For**: Security monitoring, intrusion detection, compliance auditing

---

### 3. Operations Dashboard (`operations-dashboard.json`)

**Purpose**: Monitor system health, resource utilization, and operational metrics.

**Key Metrics**:
- **System Resources**: CPU usage, memory consumption
- **Disk I/O**: Read/write throughput and operations
- **Network Bandwidth**: Received/transmitted bytes
- **Error Rates**: Total errors and errors by type
- **Service Uptime**: Process uptime duration
- **Go Runtime**: Active goroutines, GC pause times
- **System Availability**: Overall availability percentage
- **Connection Pools**: Active/idle connections, wait times
- **Node Health**: Status of all MinIO nodes

**Alerts Configured**:
- High CPU Usage (threshold: 80%)
- High Error Rate (threshold: 10 errors/sec)
- Node Down (any node unavailable)

**Recommended For**: Operations monitoring, capacity planning, incident response

---

## Installation

### Option 1: Manual Import

1. Open Grafana at http://localhost:3000
2. Navigate to **Dashboards** → **Import**
3. Click **Upload JSON file**
4. Select one of the dashboard JSON files
5. Select your Prometheus data source
6. Click **Import**

### Option 2: Automatic Provisioning

Add to your Grafana provisioning configuration (`provisioning/dashboards/dashboard.yml`):

```yaml
apiVersion: 1

providers:
  - name: 'MinIO Enterprise'
    orgId: 1
    folder: 'MinIO'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/dashboards/minio
```

Then copy the dashboard files to the provisioning directory:

```bash
cp configs/grafana/dashboards/*.json /etc/grafana/dashboards/minio/
```

### Option 3: Docker Compose Integration

Update your `docker-compose.yml` to mount the dashboards:

```yaml
services:
  grafana:
    image: grafana/grafana:latest
    volumes:
      - ./configs/grafana/dashboards:/etc/grafana/provisioning/dashboards/minio:ro
      - ./configs/grafana/provisioning:/etc/grafana/provisioning:ro
```

---

## Configuration

### Data Source

All dashboards expect a Prometheus data source. Configure it in Grafana:

1. Navigate to **Configuration** → **Data Sources**
2. Add **Prometheus**
3. Set URL to `http://prometheus:9090` (or your Prometheus endpoint)
4. Click **Save & Test**

### Metric Requirements

The dashboards expect the following Prometheus metrics to be exported by MinIO:

#### Performance Metrics
- `minio_put_ops_total`
- `minio_get_ops_total`
- `minio_delete_ops_total`
- `minio_list_ops_total`
- `minio_cache_hits_total`
- `minio_cache_misses_total`
- `minio_request_duration_seconds_bucket`
- `minio_replication_lag_seconds`
- `minio_replication_throughput_total`
- `minio_replication_errors_total`
- `minio_bytes_stored_total`
- `minio_object_count_total`

#### Security Metrics
- `minio_auth_success_total`
- `minio_auth_failed_total`
- `minio_requests_total`
- `minio_security_events_total`
- `minio_http_requests_total`
- `minio_active_sessions_total`
- `minio_rate_limited_total`
- `minio_audit_log_entries_total`

#### Operations Metrics
- `process_cpu_seconds_total`
- `process_resident_memory_bytes`
- `process_start_time_seconds`
- `minio_disk_read_bytes_total`
- `minio_disk_write_bytes_total`
- `minio_disk_read_ops_total`
- `minio_disk_write_ops_total`
- `minio_network_received_bytes_total`
- `minio_network_transmitted_bytes_total`
- `minio_errors_total`
- `go_goroutines`
- `go_gc_duration_seconds_sum`
- `minio_request_queue_depth`
- `minio_worker_pool_active`
- `minio_connection_pool_active`
- `minio_connection_pool_idle`
- `up`

---

## Alert Configuration

### Enabling Prometheus AlertManager

The dashboards include alert definitions, but you need to configure AlertManager to receive notifications:

1. **Configure AlertManager** in `prometheus.yml`:

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
```

2. **Create AlertManager configuration** (`alertmanager.yml`):

```yaml
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.example.com:587'
  smtp_from: 'alerts@example.com'
  smtp_auth_username: 'alerts@example.com'
  smtp_auth_password: 'password'

route:
  group_by: ['alertname', 'cluster']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'email-notifications'

receivers:
  - name: 'email-notifications'
    email_configs:
      - to: 'ops-team@example.com'
        headers:
          Subject: 'MinIO Alert: {{ .GroupLabels.alertname }}'
```

### Notification Channels

Configure additional notification channels in Grafana:

- **Email**: Settings → Alerting → Contact Points
- **Slack**: Add webhook URL
- **PagerDuty**: Add integration key
- **Webhook**: Custom HTTP endpoint

---

## Customization

### Modifying Thresholds

To adjust alert thresholds, edit the dashboard JSON files:

```json
"alert": {
  "conditions": [
    {
      "evaluator": {
        "params": [50],  // <-- Change this value
        "type": "gt"
      }
    }
  ]
}
```

### Adding Custom Panels

1. Import the dashboard
2. Click **Add Panel** → **Add new panel**
3. Configure your metrics query
4. Save the dashboard
5. Export JSON for version control

### Dashboard Variables

Add template variables for dynamic filtering:

```json
"templating": {
  "list": [
    {
      "name": "tenant",
      "type": "query",
      "datasource": "Prometheus",
      "query": "label_values(minio_requests_total, tenant_id)"
    }
  ]
}
```

---

## Usage Examples

### Scenario 1: Performance Troubleshooting

**Symptom**: Users reporting slow requests

**Steps**:
1. Open **Performance Dashboard**
2. Check **API Latency Percentiles** panel - identify which percentile is elevated
3. Review **Cache Performance** panel - low hit rate may indicate cache issues
4. Check **Operations Throughput** - identify which operation type is slow
5. Correlate with **Replication Performance** - high lag can impact writes

### Scenario 2: Security Incident Investigation

**Symptom**: Suspected unauthorized access

**Steps**:
1. Open **Security Dashboard**
2. Check **Authentication Events** - spike in failures indicates brute force
3. Review **Access Pattern Analysis** - identify anomalous tenant activity
4. Check **Recent Security Events** table - review specific event details
5. Examine **API Error Rate by Code** - 403 errors indicate unauthorized attempts

### Scenario 3: Capacity Planning

**Symptom**: Planning for increased load

**Steps**:
1. Open **Operations Dashboard**
2. Check **System Resources** - current CPU/memory baseline
3. Review **Disk I/O** - current throughput and headroom
4. Check **Network Bandwidth** - network constraints
5. Review **Performance Dashboard** → **Storage Metrics** - growth rate

---

## Best Practices

### 1. Dashboard Organization

- Create a **MinIO** folder in Grafana
- Star frequently used dashboards
- Use consistent color schemes across dashboards
- Add dashboard links for easy navigation

### 2. Alert Management

- Start with conservative thresholds, adjust based on baselines
- Use alert grouping to reduce noise
- Configure escalation policies for critical alerts
- Document alert runbooks

### 3. Performance Optimization

- Use appropriate time ranges (avoid excessive ranges)
- Leverage dashboard variables for filtering
- Use query caching where possible
- Set reasonable refresh intervals (default: 30s)

### 4. Regular Maintenance

- Review and update dashboards quarterly
- Archive unused dashboards
- Document customizations
- Version control dashboard JSON files

---

## Troubleshooting

### No Data Displayed

**Cause**: Metrics not being exported or data source misconfigured

**Solution**:
1. Verify MinIO metrics endpoint: `curl http://localhost:9000/metrics`
2. Check Prometheus targets: http://localhost:9090/targets
3. Verify Grafana data source connection
4. Review Prometheus scrape configuration

### Alerts Not Firing

**Cause**: AlertManager not configured or rules not loaded

**Solution**:
1. Check AlertManager status: http://localhost:9093
2. Verify alert rules in Prometheus: http://localhost:9090/alerts
3. Check Grafana notification channels
4. Review alert evaluation logs

### Dashboard Performance Issues

**Cause**: Complex queries or long time ranges

**Solution**:
1. Reduce time range
2. Increase refresh interval
3. Simplify queries (use recording rules)
4. Use dashboard caching

---

## Support

For issues or questions:

- **GitHub Issues**: [Repository Issues](https://github.com/abiolaogu/MinIO/issues)
- **Documentation**: [MinIO Enterprise Docs](../../../docs/)
- **Grafana Docs**: https://grafana.com/docs/

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-06 | Initial dashboard creation (Performance, Security, Operations) |

---

**Author**: Claude Code Agent
**Last Updated**: 2026-02-06
**Status**: Production Ready
