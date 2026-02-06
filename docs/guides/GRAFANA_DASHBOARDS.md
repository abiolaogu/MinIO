# MinIO Enterprise - Grafana Dashboards Guide

## Overview

This guide provides comprehensive documentation for the custom Grafana dashboards included with MinIO Enterprise. These dashboards provide real-time visibility into performance, security, and operational metrics.

## Dashboard Suite

### 1. Performance Dashboard
**UID**: `minio-performance`
**Refresh Rate**: 5 seconds
**Focus**: System performance metrics, throughput, and latency

#### Key Metrics

##### Cache Throughput
- **Metric**: Cache write/read operations per second
- **Queries**:
  - `rate(minio_cache_writes_total[5m])` - Cache write throughput
  - `rate(minio_cache_reads_total[5m])` - Cache read throughput
- **Target**: 500K writes/sec, 2M reads/sec
- **Alert Threshold**: < 100K writes/sec or < 500K reads/sec

##### Cache Hit Rate
- **Metric**: Percentage of requests served from cache
- **Query**: `minio_cache_hit_rate * 100`
- **Target**: > 90%
- **Thresholds**:
  - 🔴 Red: < 70%
  - 🟡 Yellow: 70-90%
  - 🟢 Green: > 90%

##### API Latency Percentiles
- **Metrics**: P50, P95, P99 latency
- **Queries**:
  - `histogram_quantile(0.50, rate(minio_api_latency_bucket[5m]))` - P50
  - `histogram_quantile(0.95, rate(minio_api_latency_bucket[5m]))` - P95
  - `histogram_quantile(0.99, rate(minio_api_latency_bucket[5m]))` - P99
- **Targets**:
  - P50: < 10ms
  - P95: < 30ms
  - P99: < 50ms
- **Alert Threshold**: P99 > 100ms

##### Replication Performance
- **Metrics**: Replication throughput and lag
- **Queries**:
  - `rate(minio_replication_operations_total[5m])` - Throughput
  - `minio_replication_lag_ms` - Replication lag
- **Target**: 10K ops/sec, < 50ms lag
- **Alert Threshold**: Lag > 100ms

##### Memory Usage
- **Metrics**: Memory allocation and heap usage
- **Queries**:
  - `go_memstats_alloc_bytes` - Total allocated
  - `go_memstats_heap_inuse_bytes` - Heap in use
- **Target**: < 8GB per node
- **Alert Threshold**: > 14GB (approaching limit)

##### Concurrency Metrics
- **Metrics**: Active goroutines and worker pool size
- **Queries**:
  - `go_goroutines` - Active goroutines
  - `minio_worker_pool_size` - Dynamic worker pool size
- **Normal Range**: 4-128 workers based on load

---

### 2. Security Dashboard
**UID**: `minio-security`
**Refresh Rate**: 30 seconds
**Focus**: Authentication, authorization, and security events

#### Key Metrics

##### Authentication Attempts
- **Metrics**: Successful vs failed authentication attempts
- **Queries**:
  - `rate(minio_auth_attempts_total{status="success"}[5m])` - Successful
  - `rate(minio_auth_attempts_total{status="failed"}[5m])` - Failed
- **Alert Threshold**: Failed auth rate > 10/sec (potential attack)

##### Failed Auth (Last Hour)
- **Metric**: Total failed authentication attempts in last hour
- **Query**: `increase(minio_auth_attempts_total{status="failed"}[1h])`
- **Thresholds**:
  - 🟢 Green: < 10
  - 🟡 Yellow: 10-50
  - 🔴 Red: > 50
- **Action Required**: Investigate if > 50

##### Access Denied Events
- **Metric**: Authorization failures in last hour
- **Query**: `increase(minio_access_denied_total[1h])`
- **Thresholds**:
  - 🟢 Green: < 100
  - 🟡 Yellow: 100-500
  - 🔴 Red: > 500
- **Action Required**: Review RBAC policies if consistently high

##### Security Events by Type
- **Metric**: Rate of security events categorized by type
- **Query**: `rate(minio_security_events_total[5m])`
- **Event Types**:
  - Authentication failures
  - Authorization denials
  - Rate limit violations
  - Suspicious activity patterns
  - Invalid token usage

##### Access Patterns by Tenant
- **Metric**: Distribution of access across tenants
- **Query**: `sum by(tenant_id) (minio_tenant_access_count)`
- **Purpose**: Identify unusual access patterns or anomalies

##### API Request Rate
- **Metric**: Total API request rate (for rate limiting monitoring)
- **Query**: `rate(minio_api_requests_total[5m])`
- **Alert Threshold**: > 1000 req/sec per tenant (rate limit)
- **Purpose**: Monitor for potential abuse or DDoS

##### Top Failed Auth Users
- **Metric**: Top 10 users with failed authentication attempts
- **Query**: `topk(10, sum by(user_id) (increase(minio_auth_attempts_total{status="failed"}[1h])))`
- **Purpose**: Identify compromised accounts or brute force targets
- **Action Required**: Lock accounts with > 10 failed attempts

##### Audit Log Events
- **Metric**: Audit log events by action and resource
- **Query**: `increase(minio_audit_log_events_total[1h])`
- **Purpose**: Track all administrative and data access actions
- **Compliance**: Required for SOC2, ISO 27001

---

### 3. Operations Dashboard
**UID**: `minio-operations`
**Refresh Rate**: 30 seconds
**Focus**: System health, resource utilization, and availability

#### Key Metrics

##### Service Status
- **Metric**: Up/down status of MinIO nodes
- **Query**: `up{job="minio"}`
- **Values**:
  - 1 = UP (green)
  - 0 = DOWN (red)
- **Alert**: Any node down for > 2 minutes

##### Memory Usage
- **Metric**: System memory utilization percentage
- **Query**: `100 * (1 - ((avg_over_time(node_memory_MemAvailable_bytes[5m]) * 100) / avg_over_time(node_memory_MemTotal_bytes[5m])))`
- **Thresholds**:
  - 🟢 Green: < 90%
  - 🟡 Yellow: 90-95%
  - 🔴 Red: > 95%
- **Alert**: > 95% for > 5 minutes

##### CPU Usage
- **Metric**: System CPU utilization percentage
- **Query**: `100 * (1 - (sum(rate(node_cpu_seconds_total{mode="idle"}[5m])) / sum(rate(node_cpu_seconds_total[5m]))))`
- **Thresholds**:
  - 🟢 Green: < 80%
  - 🟡 Yellow: 80-90%
  - 🔴 Red: > 90%
- **Alert**: > 90% for > 10 minutes

##### Disk Usage
- **Metric**: Root filesystem utilization percentage
- **Query**: `100 * (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}))`
- **Thresholds**:
  - 🟢 Green: < 75%
  - 🟡 Yellow: 75-90%
  - 🔴 Red: > 90%
- **Alert**: > 90%
- **Action Required**: Expand storage or implement cleanup

##### API Request Rate
- **Metric**: API requests per second by method and status
- **Query**: `rate(minio_api_requests_total[5m])`
- **Purpose**: Monitor overall system load

##### Error Rate by Type
- **Metric**: Error rate categorized by type
- **Query**: `rate(minio_errors_total[5m])`
- **Error Types**:
  - Network errors
  - Storage errors
  - Authentication errors
  - Replication errors
- **Alert**: Any error type > 1/sec sustained

##### Network Bandwidth
- **Metrics**: Inbound and outbound network traffic
- **Queries**:
  - `rate(node_network_receive_bytes_total[5m]) / 1024 / 1024` - Inbound (MB/s)
  - `rate(node_network_transmit_bytes_total[5m]) / 1024 / 1024` - Outbound (MB/s)
- **Purpose**: Monitor network saturation

##### Disk I/O Operations
- **Metrics**: Disk read and write IOPS
- **Queries**:
  - `rate(node_disk_reads_completed_total[5m])` - Read IOPS
  - `rate(node_disk_writes_completed_total[5m])` - Write IOPS
- **Purpose**: Identify I/O bottlenecks

##### Tenant Quota Usage
- **Metric**: Top 10 tenants by quota utilization
- **Query**: `topk(10, (minio_tenant_quota_used / minio_tenant_quota_limit) * 100)`
- **Thresholds**:
  - 🟢 Green: < 70%
  - 🟡 Yellow: 70-90%
  - 🔴 Red: > 90%
- **Action Required**: Notify tenant when > 80%

##### HTTP Status Distribution
- **Metric**: Distribution of HTTP response status codes
- **Query**: `sum by(status) (minio_api_requests_total)`
- **Purpose**: Identify trends in error rates (4xx, 5xx)

##### Service Uptime
- **Metric**: Time since service started
- **Query**: `time() - process_start_time_seconds`
- **Purpose**: Track availability and restart frequency

---

## Setup Instructions

### 1. Prerequisites
- Docker Compose deployment running
- Prometheus collecting metrics from MinIO
- Grafana accessible (default: http://localhost:3000)

### 2. Automatic Provisioning
The dashboards are automatically provisioned when you deploy the stack:

```bash
# Deploy full stack with monitoring
docker-compose -f deployments/docker/docker-compose.production.yml up -d

# Verify Grafana is running
docker-compose -f deployments/docker/docker-compose.production.yml ps grafana

# Check Grafana logs
docker-compose -f deployments/docker/docker-compose.production.yml logs -f grafana
```

### 3. Access Dashboards
1. Open Grafana: http://localhost:3000
2. Login (default credentials):
   - Username: `admin`
   - Password: `admin` (change on first login)
3. Navigate to **Dashboards** → **MinIO Enterprise** folder
4. Select dashboard:
   - MinIO Enterprise - Performance Dashboard
   - MinIO Enterprise - Security Dashboard
   - MinIO Enterprise - Operations Dashboard

### 4. Manual Import (if needed)
If dashboards don't auto-provision:

1. Go to **Dashboards** → **Import**
2. Upload JSON file from `configs/grafana/dashboards/`
3. Select **Prometheus** as data source
4. Click **Import**

---

## Alert Configuration

### Recommended Alert Rules

Create these alert rules in Prometheus AlertManager:

#### High Priority Alerts

```yaml
# Performance Alerts
- alert: HighAPILatency
  expr: histogram_quantile(0.99, rate(minio_api_latency_bucket[5m])) > 100
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "High API latency (P99 > 100ms)"

- alert: LowCacheHitRate
  expr: minio_cache_hit_rate * 100 < 70
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Cache hit rate below 70%"

- alert: HighReplicationLag
  expr: minio_replication_lag_ms > 100
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Replication lag exceeds 100ms"

# Security Alerts
- alert: HighFailedAuthRate
  expr: rate(minio_auth_attempts_total{status="failed"}[5m]) > 10
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "High rate of failed authentication attempts (potential attack)"

- alert: ManyFailedAuthsPerUser
  expr: increase(minio_auth_attempts_total{status="failed"}[1h]) > 10
  for: 1m
  labels:
    severity: warning
  annotations:
    summary: "User account experiencing many failed auth attempts"

# Operations Alerts
- alert: ServiceDown
  expr: up{job="minio"} == 0
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "MinIO service is down"

- alert: HighMemoryUsage
  expr: 100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 95
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Memory usage exceeds 95%"

- alert: HighDiskUsage
  expr: 100 * (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) > 90
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Disk usage exceeds 90%"

- alert: HighErrorRate
  expr: rate(minio_errors_total[5m]) > 1
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Error rate exceeds 1/sec"
```

---

## Customization

### Adding Custom Panels

1. Open dashboard in Grafana
2. Click **Add** → **Visualization**
3. Configure query:
   - Data source: Prometheus
   - Metric: Select from available MinIO metrics
   - Legend: Use `{{label}}` for dynamic labels
4. Configure visualization type (timeseries, gauge, stat, etc.)
5. Set thresholds and units
6. Click **Save**

### Exporting Dashboards

To save customizations:

1. Click **Dashboard settings** (gear icon)
2. Select **JSON Model**
3. Copy JSON
4. Save to `configs/grafana/dashboards/`
5. Commit to repository

### Variables and Templating

Add dashboard variables for filtering:

1. **Dashboard settings** → **Variables**
2. Click **Add variable**
3. Configure:
   - Name: `instance`
   - Type: Query
   - Query: `label_values(up{job="minio"}, instance)`
4. Use in queries: `{instance="$instance"}`

---

## Metrics Reference

### MinIO Custom Metrics

These metrics must be exposed by MinIO application:

```go
// Performance Metrics
minio_cache_writes_total          // Counter: Total cache write operations
minio_cache_reads_total           // Counter: Total cache read operations
minio_cache_hit_rate              // Gauge: Cache hit rate (0.0-1.0)
minio_api_latency_bucket          // Histogram: API request latency
minio_replication_operations_total // Counter: Replication operations
minio_replication_lag_ms          // Gauge: Replication lag in milliseconds
minio_worker_pool_size            // Gauge: Current worker pool size

// Security Metrics
minio_auth_attempts_total{status} // Counter: Auth attempts (success/failed)
minio_access_denied_total         // Counter: Authorization failures
minio_security_events_total{type} // Counter: Security events by type
minio_tenant_access_count{tenant_id} // Counter: Access per tenant
minio_audit_log_events_total{action,resource} // Counter: Audit events

// Operations Metrics
minio_api_requests_total{method,status,endpoint} // Counter: API requests
minio_errors_total{error_type}    // Counter: Errors by type
minio_tenant_quota_used{tenant_id} // Gauge: Quota used
minio_tenant_quota_limit{tenant_id} // Gauge: Quota limit
```

### Standard Go/Prometheus Metrics

```
// Memory
go_memstats_alloc_bytes
go_memstats_heap_inuse_bytes

// Goroutines
go_goroutines

// Process
process_start_time_seconds
up

// Node Exporter (if available)
node_memory_MemAvailable_bytes
node_memory_MemTotal_bytes
node_cpu_seconds_total
node_filesystem_avail_bytes
node_filesystem_size_bytes
node_network_receive_bytes_total
node_network_transmit_bytes_total
node_disk_reads_completed_total
node_disk_writes_completed_total
```

---

## Troubleshooting

### Dashboards Not Appearing

1. Check Grafana logs:
   ```bash
   docker-compose -f deployments/docker/docker-compose.production.yml logs grafana
   ```

2. Verify provisioning directory is mounted:
   ```bash
   docker exec -it grafana ls -la /etc/grafana/provisioning/dashboards/
   ```

3. Check datasource configuration:
   - Navigate to **Configuration** → **Data Sources**
   - Verify Prometheus is configured and reachable

### No Data in Panels

1. Verify Prometheus is scraping MinIO:
   - Open Prometheus: http://localhost:9090
   - Go to **Status** → **Targets**
   - Check MinIO target status

2. Check metric names:
   - In Prometheus, go to **Graph**
   - Type metric name to verify it exists
   - Verify labels match query

3. Verify MinIO is exposing metrics:
   ```bash
   curl http://localhost:9000/metrics
   ```

### High Memory Usage in Grafana

1. Reduce query frequency:
   - Edit dashboard settings
   - Increase refresh interval to 1m or 5m

2. Limit time range:
   - Use shorter time ranges (15m instead of 24h)
   - Reduce data retention in Prometheus

---

## Best Practices

### Monitoring Strategy

1. **Start with Operations Dashboard**: Ensure system health first
2. **Check Performance Dashboard**: Validate throughput and latency targets
3. **Review Security Dashboard**: Daily review of security events

### Alert Fatigue Prevention

1. Set appropriate thresholds (avoid too sensitive)
2. Use `for:` clause to require sustained conditions
3. Group related alerts
4. Implement alert routing and escalation

### Dashboard Maintenance

1. Review dashboards monthly
2. Archive unused panels
3. Update thresholds based on actual baselines
4. Document custom modifications

### Performance Optimization

1. Use recording rules for complex queries
2. Pre-aggregate high-cardinality metrics
3. Set reasonable retention periods
4. Use downsampling for historical data

---

## Additional Resources

- [Grafana Documentation](https://grafana.com/docs/)
- [PromQL Query Language](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [MinIO Monitoring Guide](../PERFORMANCE.md)
- [Alert Configuration](https://prometheus.io/docs/alerting/latest/configuration/)

---

**Last Updated**: 2026-02-06
**Version**: 1.0
**Maintainer**: Development Team
