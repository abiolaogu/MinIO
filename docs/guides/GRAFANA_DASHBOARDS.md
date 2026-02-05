# MinIO Enterprise - Grafana Dashboards Guide

## Overview

MinIO Enterprise includes three comprehensive Grafana dashboards for monitoring performance, security, and operational metrics. These dashboards provide real-time visibility into system health and include pre-configured alerts for critical thresholds.

**Version**: 1.0
**Created**: 2026-02-05
**Grafana Version**: 10.x+
**Data Source**: Prometheus

---

## Table of Contents

1. [Dashboard Overview](#dashboard-overview)
2. [Installation & Setup](#installation--setup)
3. [Performance Dashboard](#performance-dashboard)
4. [Security Dashboard](#security-dashboard)
5. [Operations Dashboard](#operations-dashboard)
6. [Alert Configuration](#alert-configuration)
7. [Metrics Reference](#metrics-reference)
8. [Troubleshooting](#troubleshooting)
9. [Customization Guide](#customization-guide)

---

## Dashboard Overview

### Performance Dashboard (`minio-performance`)
**Purpose**: Monitor cache performance, replication throughput, API latency, and tenant metrics

**Key Metrics**:
- Cache write/read throughput (target: 500K/2M ops/sec)
- Cache hit rate (target: >75%)
- Replication throughput and lag
- API request rate, latency (P50/P95/P99), and error rate
- Tenant quota usage and request patterns

**Alerts**: 7 configured alerts for performance degradation

### Security Dashboard (`minio-security`)
**Purpose**: Monitor authentication, authorization, access patterns, and security events

**Key Metrics**:
- Authentication success/failure rates
- Access patterns by user and IP address
- Authorization failures
- Suspicious activity detection
- TLS/SSL connection health
- Certificate expiry status
- Security scan results
- Audit log events
- Rate limit violations

**Alerts**: 6 configured alerts for security incidents

### Operations Dashboard (`minio-operations`)
**Purpose**: Monitor system resources, cluster health, infrastructure components, and availability

**Key Metrics**:
- Cluster health status
- CPU, memory, disk, and network usage
- Disk I/O performance
- Goroutine count and garbage collection
- PostgreSQL, Redis, and NATS health
- Service availability (SLA tracking)
- Error logs

**Alerts**: 8 configured alerts for operational issues

---

## Installation & Setup

### Prerequisites

1. **Docker Compose Stack**: Ensure the full MinIO Enterprise stack is deployed
2. **Prometheus**: Must be running and scraping MinIO metrics
3. **Grafana**: Must be accessible at http://localhost:3000

### Quick Start

1. **Deploy the Stack**:
   ```bash
   cd deployments/docker
   docker-compose -f docker-compose.production.yml up -d
   ```

2. **Access Grafana**:
   - URL: http://localhost:3000
   - Default credentials: admin/admin (change on first login)

3. **Verify Dashboard Installation**:
   - Navigate to **Dashboards** → **Browse**
   - Look for "MinIO Enterprise" folder
   - You should see three dashboards:
     - MinIO Enterprise - Performance Dashboard
     - MinIO Enterprise - Security Dashboard
     - MinIO Enterprise - Operations Dashboard

### Manual Import (if needed)

If dashboards are not automatically provisioned:

1. Navigate to **Dashboards** → **Import**
2. Upload JSON files from: `deployments/docker/grafana/dashboards/`
   - `performance-dashboard.json`
   - `security-dashboard.json`
   - `operations-dashboard.json`
3. Select "Prometheus" as the data source
4. Click **Import**

---

## Performance Dashboard

### Panels Overview

#### Cache Metrics (Row 1-2)
1. **Cache Write Throughput**: Operations per second for cache writes
   - **Target**: 500K+ ops/sec
   - **Alert**: <400K ops/sec for 5 minutes
   - **Color**: Green >500K, Yellow 400K-500K, Red <400K

2. **Cache Read Throughput**: Operations per second for cache reads
   - **Target**: 2M+ ops/sec
   - **Alert**: <1.5M ops/sec for 5 minutes

3. **Cache Hit Rate**: Percentage of cache hits vs total cache requests
   - **Target**: >75%
   - **Alert**: <75% for 5 minutes
   - **Formula**: `100 * hits / (hits + misses)`

4. **Cache Eviction Rate**: Operations per second for cache evictions
   - **Normal Range**: Variable based on workload
   - **High Values**: May indicate insufficient cache size

#### Replication Metrics (Row 3)
5. **Replication Throughput**: Operations per second for replication
   - **Target**: 10K+ ops/sec
   - **Alert**: <8K ops/sec for 5 minutes

6. **Replication Lag**: Milliseconds of replication delay
   - **Target**: <50ms (P99)
   - **Alert**: >100ms for 5 minutes

#### API Metrics (Row 4)
7. **API Request Rate**: Requests per second by method and endpoint
   - **Monitor for**: Traffic patterns and spikes

8. **API Latency (P50/P95/P99)**: Percentile latencies for API requests
   - **Target P99**: <50ms
   - **Alert**: P99 >50ms for 5 minutes

9. **API Error Rate**: Percentage of failed API requests
   - **Target**: <1%
   - **Alert**: >5% for 5 minutes

#### Tenant Metrics (Row 5)
10. **Tenant Quota Usage**: Percentage of quota consumed per tenant
    - **Alert**: >85% for any tenant

11. **Tenant Request Rate**: Requests per second per tenant
    - **Monitor for**: Usage patterns and anomalies

### Variables

- **datasource**: Select Prometheus data source
- **instance**: Filter by MinIO instance (supports multi-select)

### Time Range Recommendations

- **Real-time monitoring**: Last 15 minutes (default)
- **Trend analysis**: Last 1-6 hours
- **Incident investigation**: Custom time range

---

## Security Dashboard

### Panels Overview

#### Authentication Metrics (Row 1)
1. **Authentication Attempts**: Success vs failure rate
   - **Alert**: >10 failures/sec for 5 minutes
   - **Investigate**: Brute force attacks, misconfigured clients

2. **Authentication Success Rate**: Percentage of successful authentications
   - **Target**: >95%
   - **Color coding**: Green >95%, Yellow 90-95%, Red <90%

#### Access Pattern Metrics (Row 2)
3. **Access Patterns by User**: Request rate per user and HTTP method
   - **Monitor for**: Unusual user activity

4. **Access Patterns by IP**: Request rate per source IP address
   - **Monitor for**: Distributed attacks, suspicious IPs

#### Authorization & Security Events (Row 3)
5. **Authorization Failures**: Failed authorization attempts by resource
   - **Alert**: >5 failures/sec for 5 minutes
   - **Investigate**: Permission issues, malicious access attempts

6. **Suspicious Activity Detection**: Rate of detected suspicious events
   - **Alert**: >1 event/sec immediately
   - **Types**: Anomalous access patterns, privilege escalation attempts

#### Recent Events (Row 4)
7. **Recent Authentication Failures**: Table of last 100 failed auth attempts
   - **Columns**: Timestamp, User, Source IP, Failure Reason
   - **Use for**: Forensic analysis

8. **TLS/SSL Connection Success Rate**: Percentage of successful TLS connections
   - **Target**: >99%

9. **Certificate Expiry Status**: Days until certificate expiration
   - **Alert**: <30 days until expiry
   - **Action required**: Renew certificates

#### Vulnerability & Audit (Row 5-6)
10. **Security Scan Results**: Vulnerability counts by severity
    - **Alert**: >1 critical vulnerability
    - **Integration**: Trivy, Gosec scan results

11. **Audit Log Events**: Event rate by severity and type
    - **Monitor for**: Compliance and forensics

12. **Rate Limit Violations**: Rate limit exceeded events
    - **Alert**: >10 violations/sec
    - **Action**: Review rate limit configuration

13. **Active Security Incidents**: Count of ongoing security incidents
    - **Color coding**: Green 0, Yellow 1-4, Red 5+

### Variables

- **datasource**: Select Prometheus data source
- **instance**: Filter by MinIO instance
- **user**: Filter by username

### Time Range Recommendations

- **Real-time monitoring**: Last 1 hour (default)
- **Incident response**: Last 24 hours
- **Compliance reporting**: Last 30 days

---

## Operations Dashboard

### Panels Overview

#### Cluster Status (Row 1)
1. **Cluster Health Status**: Overall cluster health
   - **Values**: Healthy (2), Degraded (1), Down (0)
   - **Color coding**: Green/Yellow/Red

2. **Uptime**: Time since process start
   - **Format**: Seconds (converts to days/hours in display)

3. **Active Nodes**: Count of healthy MinIO nodes
   - **Target**: 4 nodes
   - **Color**: Green 4, Yellow 2-3, Red <2

4. **Total Error Count**: Errors in last 5 minutes
   - **Target**: <10
   - **Color**: Green <10, Yellow 10-50, Red >50

#### System Resources (Row 2-3)
5. **CPU Usage**: Percentage of CPU utilization per instance
   - **Alert**: >85% for 5 minutes
   - **Target**: <70% sustained

6. **Memory Usage**: Percentage of memory utilization
   - **Alert**: >90% for 5 minutes
   - **Target**: <80% sustained

7. **Disk I/O**: Read/write throughput in MB/s
   - **Monitor for**: I/O bottlenecks

8. **Disk Space Usage**: Percentage of disk space used
   - **Alert**: >85% for 5 minutes
   - **Action required**: Add capacity or clean up

#### Network Metrics (Row 4)
9. **Network Traffic**: Receive/transmit rates in MB/s
   - **Monitor for**: Bandwidth saturation

10. **Network Errors & Drops**: Network error and drop rates
    - **Alert**: >10 errors/sec
    - **Action**: Investigate network issues

#### Application Metrics (Row 5)
11. **Goroutine Count**: Number of active goroutines
    - **Alert**: >10,000 sustained
    - **High values**: May indicate goroutine leaks

12. **Garbage Collection Duration**: Time spent in GC (ms)
    - **Target**: <10ms average
    - **High values**: Memory pressure, tune GC settings

#### Infrastructure Services (Row 6)
13. **PostgreSQL Connections**: Active database connections
    - **Alert**: >180 connections (90% of max 200)
    - **Max configured**: 200 connections

14. **Redis Memory Usage**: Memory consumed by Redis cache (MB)
    - **Max configured**: 4GB
    - **Monitor for**: Memory pressure

15. **NATS Message Rate**: Messages per second through NATS
    - **Monitor for**: Message processing capacity

#### Logs & Availability (Row 7)
16. **Recent Error Log**: Table of last 50 errors
    - **Columns**: Timestamp, Level, Component, Error Message, Instance
    - **Use for**: Quick troubleshooting

17. **Service Availability**: Percentage uptime (SLA tracking)
    - **Target**: >99.99%
    - **Alert**: <99.9% for 5 minutes

### Variables

- **datasource**: Select Prometheus data source
- **instance**: Filter by instance (node)

### Time Range Recommendations

- **Real-time monitoring**: Last 30 minutes (default)
- **Incident investigation**: Last 1-4 hours
- **Capacity planning**: Last 7-30 days

---

## Alert Configuration

### Alert Severity Levels

- **CRITICAL** (Red): Immediate action required, service impact likely
- **WARNING** (Yellow): Attention needed, potential service degradation
- **INFO** (Blue): Informational, no action required

### Performance Alerts

| Alert Name | Severity | Threshold | Duration | Action Required |
|------------|----------|-----------|----------|-----------------|
| Low Cache Write Throughput | WARNING | <400K ops/sec | 5 min | Investigate cache performance |
| Low Cache Read Throughput | WARNING | <1.5M ops/sec | 5 min | Check cache configuration |
| Low Cache Hit Rate | WARNING | <75% | 5 min | Review cache sizing/warming |
| Low Replication Throughput | WARNING | <8K ops/sec | 5 min | Check replication health |
| High Replication Lag | CRITICAL | >100ms | 5 min | Investigate network/load |
| High API Latency | CRITICAL | P99 >50ms | 5 min | Check system resources |
| High API Error Rate | CRITICAL | >5% | 5 min | Review application logs |
| High Tenant Quota Usage | WARNING | >85% | 5 min | Notify tenant, plan expansion |

### Security Alerts

| Alert Name | Severity | Threshold | Duration | Action Required |
|------------|----------|-----------|----------|-----------------|
| High Authentication Failure Rate | CRITICAL | >10/sec | 5 min | Investigate potential attack |
| High Authorization Failure Rate | WARNING | >5/sec | 5 min | Review permissions |
| Suspicious Activity Detected | CRITICAL | >1/sec | Immediate | Initiate security investigation |
| Certificate Expiring Soon | WARNING | <30 days | 1 hour | Renew certificates |
| Security Vulnerabilities Detected | CRITICAL | >1 critical | 5 min | Apply security patches |
| High Rate Limit Violations | WARNING | >10/sec | 5 min | Review rate limits |

### Operations Alerts

| Alert Name | Severity | Threshold | Duration | Action Required |
|------------|----------|-----------|----------|-----------------|
| High CPU Usage | WARNING | >85% | 5 min | Scale or optimize |
| High Memory Usage | CRITICAL | >90% | 5 min | Add memory or restart |
| High Disk Usage | WARNING | >85% | 5 min | Clean up or expand |
| Network Errors Detected | WARNING | >10/sec | 5 min | Check network hardware |
| High Goroutine Count | WARNING | >10,000 | 5 min | Investigate goroutine leak |
| High PostgreSQL Connection Count | WARNING | >180 | 5 min | Review connection pooling |
| Service Availability Below SLA | CRITICAL | <99.9% | 5 min | Incident response |

### Alert Notification Setup

1. **Configure AlertManager** (if using Prometheus AlertManager):
   ```yaml
   # Add to prometheus.yml or alertmanager.yml
   alerting:
     alertmanagers:
       - static_configs:
           - targets: ['alertmanager:9093']
   ```

2. **Grafana Notification Channels**:
   - Navigate to **Alerting** → **Notification channels**
   - Add channels: Email, Slack, PagerDuty, etc.
   - Configure routing based on severity

3. **Test Alerts**:
   ```bash
   # Generate test load to trigger alerts
   make load-test
   ```

---

## Metrics Reference

### Cache Metrics

```promql
# Write throughput
rate(minio_cache_writes_total[1m])

# Read throughput
rate(minio_cache_reads_total[1m])

# Hit rate
100 * rate(minio_cache_hits_total[1m]) / (rate(minio_cache_hits_total[1m]) + rate(minio_cache_misses_total[1m]))

# Eviction rate
rate(minio_cache_evictions_total[1m])
```

### Replication Metrics

```promql
# Replication throughput
rate(minio_replication_operations_total[1m])

# Replication lag
minio_replication_lag_milliseconds
```

### API Metrics

```promql
# Request rate
rate(minio_api_requests_total[1m])

# Latency percentiles
histogram_quantile(0.50, rate(minio_api_latency_bucket[1m]))  # P50
histogram_quantile(0.95, rate(minio_api_latency_bucket[1m]))  # P95
histogram_quantile(0.99, rate(minio_api_latency_bucket[1m]))  # P99

# Error rate
100 * rate(minio_api_errors_total[1m]) / rate(minio_api_requests_total[1m])
```

### Security Metrics

```promql
# Authentication attempts
rate(minio_auth_attempts_total{status="success"}[1m])
rate(minio_auth_attempts_total{status="failure"}[1m])

# Authorization failures
rate(minio_authorization_failures_total[1m])

# Certificate expiry
(minio_certificate_expiry_timestamp - time()) / 86400
```

### System Metrics

```promql
# CPU usage
100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage
100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))

# Disk I/O
rate(node_disk_read_bytes_total[1m]) / 1048576    # Read MB/s
rate(node_disk_written_bytes_total[1m]) / 1048576 # Write MB/s

# Network traffic
rate(node_network_receive_bytes_total[1m]) / 1048576   # Receive MB/s
rate(node_network_transmit_bytes_total[1m]) / 1048576  # Transmit MB/s
```

**Note**: Some metrics (like `minio_cache_writes_total`, `minio_auth_attempts_total`, etc.) are placeholders. You need to ensure your MinIO application exports these metrics to Prometheus. See [Implementing Metrics Export](#implementing-metrics-export) section.

---

## Troubleshooting

### Dashboard Not Loading

**Issue**: Dashboard shows "No data" or fails to load

**Solutions**:
1. **Check Prometheus Connection**:
   ```bash
   # Test Prometheus endpoint
   curl http://localhost:9090/-/healthy

   # Check targets
   curl http://localhost:9090/api/v1/targets
   ```

2. **Verify Data Source Configuration**:
   - Grafana → Configuration → Data Sources → Prometheus
   - Test connection (should show "Data source is working")

3. **Check Metric Availability**:
   ```bash
   # Query Prometheus for MinIO metrics
   curl 'http://localhost:9090/api/v1/query?query=up{job="minio"}'
   ```

### Alerts Not Firing

**Issue**: Configured alerts not triggering

**Solutions**:
1. **Verify Alert State**:
   - Dashboard → Panel → Edit → Alert tab
   - Check "State history" for alert evaluations

2. **Check Alert Rules**:
   ```bash
   # View active alerts in Prometheus
   curl http://localhost:9090/api/v1/rules
   ```

3. **Review Notification Channels**:
   - Grafana → Alerting → Notification channels
   - Test notification delivery

### Missing Metrics

**Issue**: Some panels show "No data" while others work

**Solutions**:
1. **Check Metric Names**:
   - Panels use specific metric names that must match your Prometheus exports
   - Update panel queries if metric names differ

2. **Verify Scrape Configuration**:
   ```yaml
   # prometheus.yml
   scrape_configs:
     - job_name: 'minio'
       static_configs:
         - targets: ['minio1:9000', 'minio2:9000', 'minio3:9000', 'minio4:9000']
   ```

3. **Implement Missing Metrics** (see next section)

### Implementing Metrics Export

If metrics are not being exported from your MinIO application:

1. **Install Prometheus Client**:
   ```go
   import "github.com/prometheus/client_golang/prometheus"
   ```

2. **Define Metrics**:
   ```go
   var (
       cacheWrites = prometheus.NewCounterVec(
           prometheus.CounterOpts{
               Name: "minio_cache_writes_total",
               Help: "Total number of cache write operations",
           },
           []string{"instance"},
       )
   )
   ```

3. **Expose Metrics Endpoint**:
   ```go
   http.Handle("/metrics", promhttp.Handler())
   ```

### Slow Dashboard Loading

**Issue**: Dashboards take long time to load

**Solutions**:
1. **Reduce Time Range**: Use shorter time windows (e.g., 15m instead of 24h)
2. **Optimize Queries**: Add `[1m]` or `[5m]` rate intervals
3. **Increase Prometheus Resources**: Allocate more CPU/memory
4. **Enable Query Caching**:
   ```yaml
   # grafana.ini
   [caching]
   enabled = true
   ```

---

## Customization Guide

### Adding New Panels

1. **Edit Dashboard** (via Grafana UI):
   - Open dashboard
   - Click **Add panel** → **Add new panel**
   - Configure query, visualization, and thresholds
   - Save dashboard

2. **Export Updated Dashboard**:
   - Dashboard settings → JSON Model
   - Copy JSON
   - Update file in `deployments/docker/grafana/dashboards/`

### Modifying Alert Thresholds

**Via Grafana UI**:
1. Dashboard → Panel → Edit
2. Alert tab → Conditions
3. Update threshold values
4. Save dashboard

**Via JSON**:
```json
{
  "alert": {
    "conditions": [
      {
        "evaluator": {
          "params": [85],  // Change threshold here
          "type": "gt"
        }
      }
    ]
  }
}
```

### Creating Custom Variables

Add new template variables for filtering:

```json
{
  "templating": {
    "list": [
      {
        "name": "tenant",
        "type": "query",
        "datasource": "$datasource",
        "query": "label_values(minio_tenant_requests_total, tenant)",
        "multi": true,
        "includeAll": true
      }
    ]
  }
}
```

### Dashboard Cloning

To create a variant dashboard:
1. Dashboard settings → Save As
2. Modify title and UID
3. Customize panels as needed
4. Export JSON and commit to repository

---

## Best Practices

### Monitoring Strategy

1. **Layered Approach**:
   - **Performance**: Primary dashboard for day-to-day operations
   - **Security**: Review daily for anomalies
   - **Operations**: Check during incidents and capacity planning

2. **Alert Tuning**:
   - Start with conservative thresholds
   - Adjust based on baseline performance
   - Reduce false positives over time

3. **Regular Reviews**:
   - Weekly: Review dashboard effectiveness
   - Monthly: Update thresholds based on trends
   - Quarterly: Add new metrics as features evolve

### Performance Optimization

1. **Use Appropriate Time Ranges**:
   - Real-time: 5-30 minutes
   - Analysis: 1-6 hours
   - Historical: 7-30 days

2. **Limit Panel Queries**:
   - Use `topk()` for high-cardinality metrics
   - Aggregate with `sum()` or `avg()` when possible
   - Add `[1m]` or `[5m]` to rate queries

3. **Dashboard Organization**:
   - Group related panels
   - Use rows for logical sections
   - Collapse non-critical rows by default

### Version Control

1. **Commit Dashboard Changes**:
   ```bash
   git add deployments/docker/grafana/dashboards/
   git commit -m "feat: update grafana dashboards with new metrics"
   git push
   ```

2. **Dashboard Versioning**:
   - Increment `version` field in JSON
   - Document changes in commit message
   - Tag major dashboard releases

---

## Additional Resources

- **Grafana Documentation**: https://grafana.com/docs/
- **Prometheus Query Language**: https://prometheus.io/docs/prometheus/latest/querying/basics/
- **MinIO Metrics**: See `docs/PERFORMANCE.md` for application-specific metrics
- **Alert Best Practices**: https://prometheus.io/docs/practices/alerting/

---

## Support

For dashboard issues or enhancements:
- **GitHub Issues**: [Repository Issues](https://github.com/abiolaogu/MinIO/issues)
- **Documentation Updates**: Submit PR to `docs/guides/GRAFANA_DASHBOARDS.md`

---

**Last Updated**: 2026-02-05
**Version**: 1.0
**Maintainer**: MinIO Enterprise Team
