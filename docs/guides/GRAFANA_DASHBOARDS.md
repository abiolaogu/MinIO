# MinIO Enterprise - Grafana Dashboards Guide

## Overview

This guide provides comprehensive documentation for the custom Grafana dashboards designed for MinIO Enterprise monitoring. These dashboards provide real-time visibility into performance, security, and operational metrics.

## Dashboard Architecture

### Dashboard Collection
MinIO Enterprise includes three specialized dashboards:

1. **Performance Dashboard** - Cache, replication, and throughput metrics
2. **Security Dashboard** - Authentication, access control, and audit metrics
3. **Operations Dashboard** - System health, API latency, and resource utilization

### Data Source Configuration
All dashboards use Prometheus as the data source, configured at:
- **URL**: `http://prometheus:9090`
- **Scrape Interval**: 15 seconds
- **Method**: POST (for better query performance)

---

## Dashboard Provisioning

### Automatic Provisioning
The dashboards are automatically provisioned when the Docker stack is deployed. Configuration files are located at:

```
deployments/docker/grafana/
├── datasources/
│   └── prometheus.yml          # Prometheus data source configuration
└── dashboards/
    ├── dashboard-provider.yml  # Dashboard provisioning config
    ├── performance-dashboard.json
    ├── security-dashboard.json
    └── operations-dashboard.json
```

### Manual Import
To manually import dashboards:

1. Access Grafana UI: `http://localhost:3000`
2. Navigate to **Dashboards → Import**
3. Upload JSON file or paste JSON content
4. Select Prometheus data source
5. Click **Import**

---

## 1. Performance Dashboard

### Purpose
Monitor ultra-high-performance components and achieve performance targets (10-100x improvements).

### Key Metrics

#### Cache Throughput
- **Metric**: `rate(minio_cache_writes_total[5m])`, `rate(minio_cache_reads_total[5m])`
- **Target**: 500K writes/sec, 2M reads/sec (current), 1M/5M (target)
- **Alert Thresholds**:
  - Warning: <250K writes/sec or <1M reads/sec
  - Critical: <100K writes/sec or <500K reads/sec

#### Cache P99 Latency
- **Metric**: `histogram_quantile(0.99, rate(minio_cache_latency_bucket[5m]))`
- **Target**: <10ms
- **Alert Thresholds**:
  - Warning: >50ms
  - Critical: >100ms

#### Cache Hit Rate
- **Metric**: `rate(minio_cache_hits_total[5m]) / (rate(minio_cache_hits_total[5m]) + rate(minio_cache_misses_total[5m])) * 100`
- **Target**: >90%
- **Alert Thresholds**:
  - Warning: <80%
  - Critical: <70%

#### Replication Throughput
- **Metric**: `rate(minio_replication_operations_total[5m])`
- **Target**: 10K ops/sec (current), 50K ops/sec (target)
- **Alert Thresholds**:
  - Warning: <5K ops/sec
  - Critical: <1K ops/sec

#### Replication Latency
- **Metric**: `histogram_quantile(0.99, rate(minio_replication_latency_bucket[5m]))`
- **Target**: <50ms (current), <10ms (target)
- **Alert Thresholds**:
  - Warning: >100ms
  - Critical: >200ms

#### Cache Memory Usage
- **Metric**: `minio_cache_memory_usage_bytes`
- **Target**: Stable within configured limits (50GB L1 cache)
- **Alert Thresholds**:
  - Warning: >40GB (80% of capacity)
  - Critical: >45GB (90% of capacity)

#### Cache Eviction Rate
- **Metric**: `rate(minio_cache_evictions_total[5m])`
- **Target**: Low and stable
- **Alert Thresholds**:
  - Warning: >10K evictions/sec
  - Critical: >50K evictions/sec

#### Tenant Quota Updates
- **Metric**: `rate(minio_tenant_quota_updates_total[5m])`
- **Target**: 500K updates/sec
- **Alert Thresholds**:
  - Warning: <250K updates/sec
  - Critical: <100K updates/sec

### Usage Tips
1. **Compare against targets**: Use the performance table in README.md as reference
2. **Correlate metrics**: High eviction rate + low hit rate indicates cache sizing issues
3. **Trend analysis**: Use 24h/7d views to identify performance degradation
4. **Peak load identification**: Identify traffic patterns for capacity planning

---

## 2. Security Dashboard

### Purpose
Monitor authentication, authorization, access patterns, and security events for compliance and threat detection.

### Key Metrics

#### Authentication Events
- **Metrics**:
  - `rate(minio_auth_success_total[5m])` - Successful authentications
  - `rate(minio_auth_failure_total[5m])` - Failed authentications
- **Alert Thresholds**:
  - Warning: >10 failures/sec (potential brute force)
  - Critical: >100 failures/sec (active attack)

#### Failed Authentication Rate
- **Metric**: `rate(minio_auth_failure_total[5m])`
- **Target**: Near zero in normal operations
- **Alert Thresholds**:
  - Warning: >10/sec
  - Critical: >100/sec

#### Active Sessions
- **Metric**: `minio_active_sessions`
- **Target**: Stable within expected range
- **Alert Thresholds**:
  - Warning: >10,000 sessions (capacity planning)
  - Critical: >50,000 sessions (DOS risk)

#### API Access by Tenant
- **Metric**: `sum by (tenant) (rate(minio_api_requests_total[5m]))`
- **Use Case**: Multi-tenancy monitoring, quota enforcement validation
- **Alert Thresholds**: Per-tenant quotas (configured individually)

#### Access Denied Events
- **Metric**: `rate(minio_access_denied_total[5m])`
- **Target**: Low and stable
- **Alert Thresholds**:
  - Warning: >10/sec (potential misconfiguration)
  - Critical: >100/sec (attack or major misconfiguration)

#### API Requests by Method
- **Metric**: `sum by (method) (rate(minio_api_requests_total[5m]))`
- **Use Case**: API usage patterns, identify unusual activity
- **Alert Thresholds**: Baseline-dependent (establish patterns first)

#### Bandwidth by Tenant
- **Metric**: `sum by (tenant) (minio_tenant_bandwidth_bytes)`
- **Use Case**: Cost allocation, quota enforcement
- **Alert Thresholds**: Per-tenant bandwidth quotas

#### Total Audit Events
- **Metric**: `sum(minio_audit_events_total)`
- **Target**: Comprehensive audit trail
- **Alert Thresholds**:
  - Critical: Audit logging failure (counter stops incrementing)

#### Security Violations
- **Metric**: `sum(minio_security_violations_total)`
- **Target**: Zero
- **Alert Thresholds**:
  - Warning: >0 violations
  - Critical: >10 violations

#### Token Refresh Rate
- **Metric**: `rate(minio_token_refresh_total[5m])`
- **Target**: Stable pattern
- **Alert Thresholds**:
  - Warning: Unusual spike (>2x baseline)

### Security Monitoring Best Practices
1. **Baseline establishment**: Monitor for 1-2 weeks to establish normal patterns
2. **Alert tuning**: Adjust thresholds based on business patterns (e.g., high morning logins)
3. **Correlation**: Failed auth + access denied from same IP = potential attack
4. **Compliance**: Use audit events dashboard for SOC2/ISO27001 evidence
5. **Incident response**: Set up Prometheus AlertManager for real-time notifications

---

## 3. Operations Dashboard

### Purpose
Monitor system health, availability, resource utilization, and API performance for operational excellence.

### Key Metrics

#### Service Status
- **Metric**: `up{job="minio"}`
- **Target**: 1 (UP)
- **Alert Thresholds**:
  - Critical: 0 (DOWN) - immediate incident

#### System Uptime
- **Metric**: `time() - process_start_time_seconds`
- **Target**: High availability (>99.99%)
- **Alert Thresholds**:
  - Warning: Frequent restarts (<24h uptime)

#### CPU Usage
- **Metric**: `100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)`
- **Target**: <70% (sustained)
- **Alert Thresholds**:
  - Warning: >70%
  - Critical: >90%

#### Memory Usage
- **Metric**: `100 * (1 - ((node_memory_MemAvailable_bytes or node_memory_Buffers_bytes + node_memory_Cached_bytes + node_memory_MemFree_bytes) / node_memory_MemTotal_bytes))`
- **Target**: <70%
- **Alert Thresholds**:
  - Warning: >70%
  - Critical: >90%

#### HTTP Request Rate
- **Metric**: `rate(minio_http_requests_total[5m])`
- **Target**: Stable, matches business patterns
- **Alert Thresholds**:
  - Warning: >2x baseline (capacity planning)
  - Critical: Sudden drop to <10% baseline (outage indicator)

#### HTTP Error Rate
- **Metric**: `rate(minio_http_errors_total[5m])`
- **Target**: <1% of total requests
- **Alert Thresholds**:
  - Warning: >1% error rate
  - Critical: >5% error rate

#### API Latency (P50/P95/P99)
- **Metrics**:
  - P50: `histogram_quantile(0.50, rate(minio_http_request_duration_seconds_bucket[5m])) * 1000`
  - P95: `histogram_quantile(0.95, rate(minio_http_request_duration_seconds_bucket[5m])) * 1000`
  - P99: `histogram_quantile(0.99, rate(minio_http_request_duration_seconds_bucket[5m])) * 1000`
- **Targets**:
  - P50: <10ms
  - P95: <50ms
  - P99: <100ms
- **Alert Thresholds**:
  - Warning: P99 >200ms
  - Critical: P99 >500ms

#### Disk Usage
- **Metric**: `100 - ((node_filesystem_avail_bytes{mountpoint="/data"} * 100) / node_filesystem_size_bytes{mountpoint="/data"})`
- **Target**: <70%
- **Alert Thresholds**:
  - Warning: >70%
  - Critical: >90%

#### Network Throughput
- **Metrics**:
  - In: `rate(node_network_receive_bytes_total[5m])`
  - Out: `rate(node_network_transmit_bytes_total[5m])`
- **Target**: Within network capacity
- **Alert Thresholds**:
  - Warning: >80% of network capacity
  - Critical: >95% of network capacity

#### Disk I/O Operations
- **Metrics**:
  - Reads: `rate(node_disk_reads_completed_total[5m])`
  - Writes: `rate(node_disk_writes_completed_total[5m])`
- **Target**: Stable, within disk IOPS limits
- **Alert Thresholds**:
  - Warning: Approaching disk IOPS limits

#### Active Goroutines
- **Metric**: `go_goroutines`
- **Target**: Stable (typically 100-10,000 depending on load)
- **Alert Thresholds**:
  - Warning: Rapid growth (>2x baseline)
  - Critical: Goroutine leak (continuous growth)

#### Go Memory Statistics
- **Metrics**:
  - Allocated: `go_memstats_alloc_bytes`
  - Heap In Use: `go_memstats_heap_inuse_bytes`
- **Target**: Stable, no memory leaks
- **Alert Thresholds**:
  - Warning: Continuous growth over 24h (memory leak)

### Operational Best Practices
1. **SLO/SLI tracking**: Use P99 latency and error rate as primary SLIs
2. **Capacity planning**: Monitor trends (30d/90d) for resource utilization
3. **Performance correlation**: Compare operations metrics with performance dashboard
4. **Incident detection**: Set up alerts for service status, error rate, and P99 latency
5. **Health checks**: Verify uptime and restart frequency

---

## Alert Configuration

### Prometheus AlertManager Integration

Create alert rules in `/deployments/docker/prometheus-alerts.yml`:

```yaml
groups:
  - name: minio_performance
    interval: 30s
    rules:
      - alert: HighCacheLatency
        expr: histogram_quantile(0.99, rate(minio_cache_latency_bucket[5m])) > 100
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High cache P99 latency (>100ms)"
          description: "Cache latency is {{ $value }}ms"

      - alert: LowCacheHitRate
        expr: rate(minio_cache_hits_total[5m]) / (rate(minio_cache_hits_total[5m]) + rate(minio_cache_misses_total[5m])) * 100 < 70
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Low cache hit rate (<70%)"
          description: "Cache hit rate is {{ $value }}%"

  - name: minio_security
    interval: 30s
    rules:
      - alert: HighAuthFailureRate
        expr: rate(minio_auth_failure_total[5m]) > 100
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High authentication failure rate (>100/sec)"
          description: "Potential brute force attack: {{ $value }} failures/sec"

      - alert: SecurityViolations
        expr: sum(minio_security_violations_total) > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Security violations detected"
          description: "{{ $value }} security violations"

  - name: minio_operations
    interval: 30s
    rules:
      - alert: ServiceDown
        expr: up{job="minio"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "MinIO service is down"
          description: "Service has been down for 1 minute"

      - alert: HighAPILatency
        expr: histogram_quantile(0.99, rate(minio_http_request_duration_seconds_bucket[5m])) * 1000 > 500
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High API P99 latency (>500ms)"
          description: "API latency is {{ $value }}ms"

      - alert: HighErrorRate
        expr: rate(minio_http_errors_total[5m]) / rate(minio_http_requests_total[5m]) * 100 > 5
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High HTTP error rate (>5%)"
          description: "Error rate is {{ $value }}%"

      - alert: HighCPUUsage
        expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage (>90%)"
          description: "CPU usage is {{ $value }}%"

      - alert: HighMemoryUsage
        expr: 100 * (1 - ((node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes)) > 90
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage (>90%)"
          description: "Memory usage is {{ $value }}%"

      - alert: HighDiskUsage
        expr: 100 - ((node_filesystem_avail_bytes{mountpoint="/data"} * 100) / node_filesystem_size_bytes{mountpoint="/data"}) > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High disk usage (>90%)"
          description: "Disk usage is {{ $value }}%"
```

---

## Accessing Dashboards

### URLs
- **Grafana UI**: http://localhost:3000
- **Prometheus UI**: http://localhost:9090
- **Default Credentials**: admin/admin (change on first login)

### Dashboard Links
Once logged into Grafana:
1. **Performance Dashboard**: Dashboards → MinIO → Performance Dashboard
2. **Security Dashboard**: Dashboards → MinIO → Security Dashboard
3. **Operations Dashboard**: Dashboards → MinIO → Operations Dashboard

---

## Troubleshooting

### Dashboards Not Appearing
1. Check dashboard provisioning:
   ```bash
   docker-compose logs grafana | grep -i "provision"
   ```
2. Verify files exist:
   ```bash
   ls -la deployments/docker/grafana/dashboards/
   ```
3. Restart Grafana container:
   ```bash
   docker-compose restart grafana
   ```

### No Data in Panels
1. Check Prometheus data source:
   - Grafana → Configuration → Data Sources → Prometheus
   - Test connection (should return "Data source is working")
2. Verify Prometheus is scraping MinIO:
   ```bash
   curl http://localhost:9090/api/v1/targets
   ```
3. Check MinIO metrics endpoint:
   ```bash
   curl http://localhost:9000/metrics
   ```

### Incorrect Metrics
1. **Metric names**: Verify that your application exports metrics with the expected names
2. **Labels**: Check if metrics have the expected labels (tenant, method, status, etc.)
3. **Custom metrics**: If using custom metric names, update dashboard queries accordingly

### Performance Issues
1. **Long query times**: Reduce time range or increase step interval
2. **Too many series**: Add label filters to queries
3. **Memory usage**: Increase Grafana container memory limits

---

## Customization

### Adding Custom Panels
1. Open dashboard in Grafana UI
2. Click "Add Panel" → "Add new panel"
3. Configure query, visualization, and thresholds
4. Save dashboard
5. Export JSON and commit to repository

### Modifying Thresholds
Edit dashboard JSON files and update threshold values in `fieldConfig.defaults.thresholds`:

```json
"thresholds": {
  "mode": "absolute",
  "steps": [
    { "color": "green", "value": null },
    { "color": "yellow", "value": 70 },
    { "color": "red", "value": 90 }
  ]
}
```

### Adding Variables
Use Grafana variables for dynamic filtering:
1. Dashboard Settings → Variables → Add variable
2. Configure variable (e.g., `$tenant`, `$node`)
3. Use in queries: `rate(minio_api_requests_total{tenant="$tenant"}[5m])`

---

## Best Practices

### Dashboard Management
1. **Version control**: Commit all dashboard JSON files to git
2. **Documentation**: Update this guide when adding/modifying dashboards
3. **Testing**: Test dashboards after changes before committing
4. **Naming conventions**: Use descriptive, consistent panel titles

### Monitoring Strategy
1. **Layered approach**: Start with operations dashboard, drill down to performance/security
2. **Real-time + historical**: Monitor live data, analyze historical trends
3. **Correlate metrics**: Use multiple dashboards to understand root causes
4. **Regular reviews**: Weekly performance reviews, monthly capacity planning

### Alert Strategy
1. **Start conservative**: Set high thresholds, tune down based on false positives
2. **Actionable alerts**: Every alert should require action
3. **Alert fatigue**: Too many alerts = ignored alerts
4. **Escalation**: Critical alerts → immediate notification, warnings → daily digest

---

## Metrics Reference

### Performance Metrics
| Metric Name | Type | Description |
|-------------|------|-------------|
| `minio_cache_writes_total` | Counter | Total cache write operations |
| `minio_cache_reads_total` | Counter | Total cache read operations |
| `minio_cache_hits_total` | Counter | Total cache hits |
| `minio_cache_misses_total` | Counter | Total cache misses |
| `minio_cache_latency_bucket` | Histogram | Cache operation latency distribution |
| `minio_cache_memory_usage_bytes` | Gauge | Cache memory usage in bytes |
| `minio_cache_evictions_total` | Counter | Total cache evictions |
| `minio_replication_operations_total` | Counter | Total replication operations |
| `minio_replication_latency_bucket` | Histogram | Replication latency distribution |
| `minio_tenant_quota_updates_total` | Counter | Total tenant quota updates |

### Security Metrics
| Metric Name | Type | Description |
|-------------|------|-------------|
| `minio_auth_success_total` | Counter | Successful authentication attempts |
| `minio_auth_failure_total` | Counter | Failed authentication attempts |
| `minio_active_sessions` | Gauge | Current active sessions |
| `minio_api_requests_total` | Counter | Total API requests (labeled by tenant, method) |
| `minio_access_denied_total` | Counter | Access denied events |
| `minio_tenant_bandwidth_bytes` | Gauge | Bandwidth usage per tenant |
| `minio_audit_events_total` | Counter | Total audit events |
| `minio_security_violations_total` | Counter | Security violations detected |
| `minio_token_refresh_total` | Counter | Token refresh operations |

### Operations Metrics
| Metric Name | Type | Description |
|-------------|------|-------------|
| `up` | Gauge | Service availability (1=up, 0=down) |
| `process_start_time_seconds` | Gauge | Process start time (Unix timestamp) |
| `minio_http_requests_total` | Counter | Total HTTP requests |
| `minio_http_errors_total` | Counter | Total HTTP errors (labeled by status) |
| `minio_http_request_duration_seconds_bucket` | Histogram | HTTP request duration distribution |
| `node_cpu_seconds_total` | Counter | CPU time in various modes |
| `node_memory_MemTotal_bytes` | Gauge | Total memory |
| `node_memory_MemAvailable_bytes` | Gauge | Available memory |
| `node_filesystem_size_bytes` | Gauge | Filesystem size |
| `node_filesystem_avail_bytes` | Gauge | Available filesystem space |
| `node_network_receive_bytes_total` | Counter | Network bytes received |
| `node_network_transmit_bytes_total` | Counter | Network bytes transmitted |
| `node_disk_reads_completed_total` | Counter | Disk read operations |
| `node_disk_writes_completed_total` | Counter | Disk write operations |
| `go_goroutines` | Gauge | Number of goroutines |
| `go_memstats_alloc_bytes` | Gauge | Allocated memory |
| `go_memstats_heap_inuse_bytes` | Gauge | Heap memory in use |

---

## Next Steps

1. **Deploy the stack**:
   ```bash
   docker-compose -f deployments/docker/docker-compose.production.yml up -d
   ```

2. **Access Grafana**: http://localhost:3000 (admin/admin)

3. **Explore dashboards**: Navigate to Dashboards → MinIO folder

4. **Configure alerts**: Add Prometheus AlertManager configuration

5. **Customize**: Modify dashboards based on specific monitoring needs

6. **Document changes**: Update this guide when making modifications

---

## Support

For issues or questions:
- **GitHub Issues**: [Repository Issues](https://github.com/abiolaogu/MinIO/issues)
- **Documentation**: [docs/guides/](.)
- **Performance Guide**: [PERFORMANCE.md](PERFORMANCE.md)
- **Deployment Guide**: [DEPLOYMENT.md](DEPLOYMENT.md)

---

**Last Updated**: 2026-02-05
**Version**: 1.0
**Author**: Claude Code Agent
