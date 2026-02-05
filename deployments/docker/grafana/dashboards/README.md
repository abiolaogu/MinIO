# MinIO Enterprise Grafana Dashboards

This directory contains custom Grafana dashboards for comprehensive monitoring of MinIO Enterprise deployment.

## Available Dashboards

### 1. Performance Dashboard (`performance-dashboard.json`)
**UID**: `minio-performance`

Monitors system performance metrics and throughput.

**Key Panels**:
- **Cache Throughput**: Real-time cache write/read operations per second
- **Cache Hit Rate**: Percentage of cache hits (target: >90%)
- **Cache Latency**: P50/P95/P99 latency percentiles
- **Replication Throughput & Errors**: Cross-region replication metrics
- **Replication Lag**: Multi-region replication delay in milliseconds
- **Tenant Quota Usage**: Per-tenant storage consumption vs limits
- **API Request Rate**: Requests per second by endpoint and method
- **API Latency**: P50/P95/P99 API response time percentiles

**Alert Thresholds**:
- Cache hit rate <70% (warning), <50% (critical)
- P99 latency >100ms (warning), >200ms (critical)
- Replication lag >100ms (warning), >200ms (critical)

### 2. Security Dashboard (`security-dashboard.json`)
**UID**: `minio-security`

Tracks authentication, authorization, and security events.

**Key Panels**:
- **Authentication Events**: Successful vs failed authentication attempts
- **Failed Auth Rate**: Real-time attack detection gauge
- **Access Denied Events**: Authorization failures by resource
- **Access Patterns by User**: Request patterns per user account
- **Access Patterns by IP**: Request patterns per source IP
- **Security Violations**: Categorized security event tracking
- **Active TLS Connections**: Current encrypted connection count
- **Audit Log Events**: Comprehensive audit trail by event type

**Alert Thresholds**:
- Failed auth rate >10/sec (warning), >50/sec (critical - potential attack)
- Security violations >5/min (warning), >20/min (critical)

### 3. Operations Dashboard (`operations-dashboard.json`)
**UID**: `minio-operations`

System health, resource utilization, and operational metrics.

**Key Panels**:
- **CPU Usage**: Aggregate CPU utilization percentage
- **Memory Usage**: RAM consumption vs available memory
- **Disk Usage**: Storage utilization percentage
- **Service Availability**: UP/DOWN status for each instance
- **Memory Usage by Instance**: Per-instance memory tracking
- **Goroutines Count**: Go runtime goroutine tracking
- **Network I/O**: RX/TX throughput by network interface
- **Disk I/O**: Read/write IOPS by disk device
- **Error Rate by Type**: Categorized error tracking
- **Service Uptime**: Time since service start

**Alert Thresholds**:
- CPU >70% (warning), >90% (critical)
- Memory >70% (warning), >85% (critical)
- Disk >70% (warning), >90% (critical)
- Service availability <100% (critical - instance down)

## Setup Instructions

### 1. Automatic Provisioning (Recommended)

The dashboards are automatically provisioned when using the production Docker Compose stack:

```bash
# Start the full stack including Grafana
docker-compose -f deployments/docker/docker-compose.production.yml up -d

# Access Grafana
open http://localhost:3000
```

**Default Credentials**:
- Username: `admin`
- Password: `admin` (change on first login)

### 2. Manual Import

If you need to import dashboards manually:

1. Open Grafana UI: http://localhost:3000
2. Navigate to: **Dashboards → Import**
3. Upload JSON file or paste JSON content
4. Select **Prometheus** as the data source
5. Click **Import**

### 3. Dashboard Configuration

All dashboards are pre-configured with:
- **Data Source**: Prometheus (http://prometheus:9090)
- **Refresh Rate**: 30 seconds (configurable)
- **Time Range**: Last 1 hour (default)
- **Tags**: `minio`, `performance`/`security`/`operations`

## Required Prometheus Metrics

The dashboards expect the following Prometheus metrics to be exported:

### Performance Metrics
- `minio_cache_writes_total` - Cache write operation counter
- `minio_cache_reads_total` - Cache read operation counter
- `minio_cache_hit_rate` - Cache hit rate (0-1)
- `minio_cache_latency_bucket` - Cache latency histogram
- `minio_replication_total` - Replication operation counter
- `minio_replication_errors_total` - Replication error counter
- `minio_replication_lag_ms` - Replication lag gauge
- `minio_tenant_quota_used_bytes` - Tenant quota usage
- `minio_tenant_quota_limit_bytes` - Tenant quota limit
- `minio_api_requests_total` - API request counter
- `minio_api_latency_bucket` - API latency histogram

### Security Metrics
- `minio_auth_success_total` - Successful authentication counter
- `minio_auth_failure_total` - Failed authentication counter
- `minio_access_denied_total` - Access denied counter
- `minio_security_violations_total` - Security violation counter
- `minio_active_tls_connections` - Active TLS connection gauge
- `minio_audit_log_events_total` - Audit log event counter

### Operations Metrics
- `process_cpu_seconds_total` - CPU time counter
- `process_resident_memory_bytes` - Memory usage gauge
- `go_goroutines` - Goroutine count gauge
- `node_memory_*` - System memory metrics
- `node_filesystem_*` - Filesystem metrics
- `node_network_*` - Network I/O metrics
- `node_disk_*` - Disk I/O metrics
- `minio_errors_total` - Error counter by type
- `process_start_time_seconds` - Process start timestamp
- `up` - Service availability gauge

## Customization

### Adding New Panels

1. Open dashboard in Grafana
2. Click **Add Panel**
3. Select **Prometheus** data source
4. Write PromQL query
5. Configure visualization options
6. Click **Apply**
7. Click **Save Dashboard**
8. Export JSON via **Share → Export → Save to file**
9. Commit updated JSON to repository

### Modifying Alert Thresholds

Edit the dashboard JSON file:

```json
"thresholds": {
  "mode": "absolute",
  "steps": [
    {"color": "green", "value": null},
    {"color": "yellow", "value": 70},
    {"color": "red", "value": 90}
  ]
}
```

### Adding Variables

For multi-tenant or multi-region deployments, add dashboard variables:

```json
"templating": {
  "list": [
    {
      "name": "tenant",
      "type": "query",
      "datasource": "Prometheus",
      "query": "label_values(minio_tenant_quota_used_bytes, tenant)"
    }
  ]
}
```

## Prometheus Alert Rules

Companion alert rules are available in `/deployments/docker/prometheus-alerts.yml`:

```yaml
groups:
  - name: minio_performance
    interval: 30s
    rules:
      - alert: CacheHitRateLow
        expr: minio_cache_hit_rate < 0.7
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Cache hit rate below 70%"
```

## Troubleshooting

### Dashboards Not Appearing

1. Check Grafana logs:
   ```bash
   docker-compose logs grafana
   ```

2. Verify provisioning configuration:
   ```bash
   docker exec -it grafana cat /etc/grafana/provisioning/dashboards/dashboard-provisioning.yml
   ```

3. Check file permissions:
   ```bash
   ls -la deployments/docker/grafana/dashboards/
   ```

### No Data in Panels

1. Verify Prometheus data source:
   - Grafana → Configuration → Data Sources → Prometheus
   - Test connection should succeed

2. Check Prometheus targets:
   ```bash
   open http://localhost:9090/targets
   ```

3. Verify metrics are being scraped:
   ```bash
   curl http://localhost:9090/api/v1/query?query=up
   ```

### Metrics Not Found

If specific metrics are missing:

1. Check MinIO is exporting metrics:
   ```bash
   curl http://localhost:9000/metrics
   ```

2. Verify Prometheus scrape config:
   ```bash
   docker exec -it prometheus cat /etc/prometheus/prometheus.yml
   ```

3. Check for metric name changes in MinIO version

## Best Practices

1. **Regular Review**: Review dashboards weekly for anomalies
2. **Alert Tuning**: Adjust thresholds based on baseline performance
3. **Dashboard Backup**: Export JSON regularly for version control
4. **Access Control**: Use Grafana RBAC for multi-team environments
5. **Retention**: Configure appropriate Prometheus retention (default: 30 days)

## Performance Tips

1. **Query Optimization**: Use rate windows of 5m+ for stability
2. **Refresh Rate**: 30s default, increase for high-cardinality metrics
3. **Time Range**: Limit time range for faster loading
4. **Cardinality**: Avoid high-cardinality labels (IP addresses, user IDs)

## References

- [Grafana Documentation](https://grafana.com/docs/)
- [Prometheus Query Language](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [MinIO Performance Guide](../../docs/guides/PERFORMANCE.md)
- [Deployment Guide](../../docs/guides/DEPLOYMENT.md)

## Support

For issues or questions:
- GitHub Issues: [Repository Issues](https://github.com/abiolaogu/MinIO/issues)
- Documentation: [docs/](../../docs/)

---

**Last Updated**: 2026-02-05
**Version**: 1.0.0
**Maintainer**: Development Team
