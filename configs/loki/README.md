# Loki Log Aggregation - MinIO Enterprise

This directory contains the configuration for **Grafana Loki**, a horizontally-scalable, highly-available log aggregation system inspired by Prometheus. Loki is integrated with the MinIO Enterprise stack to provide centralized log collection, search, and analysis.

## 📑 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Log Sources](#log-sources)
- [Querying Logs](#querying-logs)
- [Dashboards](#dashboards)
- [Retention Policies](#retention-policies)
- [Performance Tuning](#performance-tuning)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Overview

### What is Loki?

Loki is a log aggregation system designed to be cost-effective and easy to operate. Unlike other logging systems, Loki does not index the contents of logs but rather indexes metadata (labels) about your logs. This makes Loki extremely efficient and cost-effective.

### Key Features

- **Efficient Storage**: Only indexes metadata, not log content
- **Grafana Integration**: Native integration with Grafana for visualization
- **LogQL**: Powerful query language similar to PromQL
- **Multi-tenancy**: Support for multiple isolated tenants
- **High Availability**: Horizontally scalable architecture
- **Cost-Effective**: Lower storage and indexing costs

### Components

1. **Loki**: The main server that ingests and stores logs
2. **Promtail**: The log collector that forwards logs to Loki
3. **Grafana**: The visualization layer for exploring logs

---

## Architecture

```
┌─────────────────┐
│  MinIO Cluster  │
│  (4 nodes)      │
└────────┬────────┘
         │
┌────────▼────────┐      ┌─────────────┐
│   HAProxy       │      │  Postgres   │
│   Redis         │      │  NATS       │
│   Monitoring    │      │  Jaeger     │
└────────┬────────┘      └──────┬──────┘
         │                      │
         └──────────┬───────────┘
                    │
         ┌──────────▼──────────┐
         │     Promtail        │  (Collects logs from all containers)
         │  (Log Collector)    │
         └──────────┬──────────┘
                    │
         ┌──────────▼──────────┐
         │       Loki          │  (Stores and indexes logs)
         │  (Log Aggregation)  │
         └──────────┬──────────┘
                    │
         ┌──────────▼──────────┐
         │      Grafana        │  (Visualizes and queries logs)
         │   (Visualization)   │
         └─────────────────────┘
```

---

## Quick Start

### 1. Deploy the Stack

The Loki stack is automatically deployed with the MinIO production Docker Compose:

```bash
cd deployments/docker
docker-compose -f docker-compose.production.yml up -d
```

### 2. Verify Deployment

Check that all services are running:

```bash
# Check Loki
docker-compose -f docker-compose.production.yml ps loki
curl http://localhost:3100/ready

# Check Promtail
docker-compose -f docker-compose.production.yml ps promtail
docker-compose -f docker-compose.production.yml logs promtail | tail -20

# Check Grafana
curl http://localhost:3000/api/health
```

### 3. Access Grafana

1. Open Grafana: http://localhost:3000
2. Login with credentials (default: admin/admin)
3. Navigate to **Explore** (compass icon in left sidebar)
4. Select **Loki** as the data source
5. Start querying logs!

---

## Configuration

### Loki Configuration (`loki-config.yml`)

Key configuration sections:

#### Storage

```yaml
storage_config:
  tsdb_shipper:
    active_index_directory: /loki/tsdb-index
    cache_location: /loki/tsdb-cache
  filesystem:
    directory: /loki/chunks
```

- Logs stored in `/loki/chunks`
- Index stored in `/loki/tsdb-index`
- Default retention: **31 days** (744 hours)

#### Limits

```yaml
limits_config:
  retention_period: 744h  # 31 days
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20
  max_streams_per_user: 5000
```

- Max ingestion rate: 10 MB/s
- Burst capacity: 20 MB
- Max streams per tenant: 5000

### Promtail Configuration (`promtail-config.yml`)

Promtail is configured to collect logs from all Docker containers in the MinIO stack:

- MinIO nodes (minio1-4)
- HAProxy
- PostgreSQL
- Redis
- Prometheus
- Grafana
- AlertManager
- Jaeger
- NATS

Each service has custom log parsing pipelines to extract structured data.

---

## Log Sources

### Collected Services

| Service | Container | Log Format | Labels |
|---------|-----------|------------|--------|
| MinIO | minio1-4 | JSON | level, component, container |
| HAProxy | haproxy | Syslog | frontend, backend, server, status_code |
| PostgreSQL | postgres | Text | level, container |
| Redis | redis | Text | role, container |
| Prometheus | prometheus | Logfmt | level, caller |
| Grafana | grafana | JSON | level, logger |
| AlertManager | alertmanager | Logfmt | level, component |
| Jaeger | jaeger | JSON | level |
| NATS | nats | Text | level |

### Log Labels

Common labels applied to all logs:

- `container`: Container name
- `service`: Service name
- `stream`: stdout or stderr
- `level`: Log level (info, warn, error, debug)
- `job`: Job name (service type)

---

## Querying Logs

### LogQL Basics

LogQL is Loki's query language, inspired by PromQL. It consists of:

1. **Log Stream Selector**: Filter logs by labels
2. **Log Pipeline**: Parse and filter log content

### Example Queries

#### Basic Stream Selection

```logql
{container="minio1"}                    # All logs from minio1
{service="minio"}                       # All logs from MinIO services
{level="error"}                         # All error logs
{container="minio1", level="error"}     # Error logs from minio1
```

#### Log Pipeline Operations

```logql
# Search for "cache" in MinIO logs
{service="minio"} |= "cache"

# Exclude health check logs
{container="haproxy"} != "health"

# JSON parsing
{service="minio"} | json | level="error"

# Regex matching
{service="minio"} |~ "error|failed|timeout"

# Rate over time (logs per second)
rate({service="minio"}[5m])
```

#### Advanced Queries

```logql
# Count errors per container
sum by (container) (count_over_time({level="error"}[1h]))

# Top 10 error messages
topk(10, sum by (message) (count_over_time({level="error"}[1h])))

# Authentication failures from security logs
{service="minio"} | json | component="auth" | level="warn"

# HTTP 5xx errors from HAProxy
{container="haproxy"} | regexp `status_code=5\d\d`

# Slow queries (>100ms) from logs
{service="minio"} | json | duration > 100
```

### Query Performance Tips

1. **Use Specific Time Ranges**: Narrow time ranges improve performance
2. **Filter by Labels First**: Label filters are indexed and fast
3. **Limit Results**: Use `| limit 100` for large result sets
4. **Use Metrics Queries**: Use `rate()` and `count_over_time()` for metrics

---

## Dashboards

### Creating a Log Dashboard

1. Go to Grafana → **Dashboards** → **New Dashboard**
2. Add a new panel
3. Select **Loki** as data source
4. Enter your LogQL query
5. Configure visualization:
   - **Logs Panel**: For raw log viewing
   - **Time Series**: For log rates and counts
   - **Stat Panel**: For single value metrics
   - **Table**: For aggregated data

### Pre-configured Queries for Dashboards

```logql
# Error rate per service
sum by (service) (rate({level="error"}[$__interval]))

# Log volume by container
sum by (container) (count_over_time({job=~".+"}[$__interval]))

# Authentication failures
sum(count_over_time({service="minio"} |= "authentication failed" [$__range]))

# Top 5 error-producing containers
topk(5, sum by (container) (count_over_time({level="error"}[1h])))

# Cache hit/miss rates
sum by (result) (rate({service="minio"} |= "cache" | json | result=~"hit|miss" [$__interval]))
```

### Alerting on Logs

Create alerts in Grafana based on log patterns:

1. Create a panel with a LogQL metrics query
2. Click **Alert** tab
3. Configure conditions (e.g., `error_rate > 10`)
4. Set notification channels

Example alert query:
```logql
sum(rate({service="minio", level="error"}[5m])) > 10
```

---

## Retention Policies

### Current Configuration

- **Retention Period**: 31 days (744 hours)
- **Compaction Interval**: 10 minutes
- **Retention Delete Delay**: 2 hours

### Modifying Retention

Edit `configs/loki/loki-config.yml`:

```yaml
limits_config:
  retention_period: 720h  # 30 days

compactor:
  retention_enabled: true
  retention_delete_delay: 2h
```

Then restart Loki:

```bash
docker-compose -f docker-compose.production.yml restart loki
```

### Storage Calculation

Estimated storage requirements:

- **Low volume** (100 MB/day): ~3 GB/month
- **Medium volume** (1 GB/day): ~30 GB/month
- **High volume** (10 GB/day): ~300 GB/month

Monitor storage usage:

```bash
docker exec loki du -sh /loki
```

---

## Performance Tuning

### Loki Performance

#### Memory Settings

Adjust memory limits in `docker-compose.production.yml`:

```yaml
loki:
  deploy:
    resources:
      limits:
        memory: 4G  # Increase for high log volume
      reservations:
        memory: 2G
```

#### Query Performance

```yaml
query_range:
  cache_results: true
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 200  # Increase cache size
```

### Promtail Performance

#### Batch Settings

```yaml
clients:
  - url: http://loki:3100/loki/api/v1/push
    batchwait: 1s         # Increase for higher throughput
    batchsize: 2097152    # 2 MB (increase for better batching)
```

#### Rate Limits

```yaml
limits_config:
  readline_rate: 20000    # Increase for high log volume
  readline_burst: 40000
```

### Monitoring Performance

Key metrics to monitor:

- **Ingestion Rate**: `loki_ingester_ingestion_rate`
- **Query Duration**: `loki_query_duration_seconds`
- **Memory Usage**: `process_resident_memory_bytes`
- **Disk Usage**: `loki_chunk_store_stored_chunks_total`

Access metrics:

```bash
curl http://localhost:3100/metrics
```

---

## Troubleshooting

### Common Issues

#### 1. Loki Not Receiving Logs

**Symptom**: No logs appear in Grafana

**Solutions**:

```bash
# Check Promtail status
docker-compose -f docker-compose.production.yml logs promtail

# Verify Promtail can reach Loki
docker exec promtail wget -O- http://loki:3100/ready

# Check Promtail targets
curl http://localhost:9080/targets

# Verify Docker socket is mounted
docker exec promtail ls -la /var/run/docker.sock
```

#### 2. High Memory Usage

**Symptom**: Loki consuming excessive memory

**Solutions**:

```bash
# Check current memory usage
docker stats loki

# Reduce cache sizes in loki-config.yml
# Reduce retention period
# Increase compaction frequency
```

#### 3. Slow Queries

**Symptom**: Queries timeout or take too long

**Solutions**:

- Use shorter time ranges
- Add more specific label filters
- Enable query result caching
- Limit result sets with `| limit N`

#### 4. Disk Space Issues

**Symptom**: Loki volume filling up

**Solutions**:

```bash
# Check disk usage
docker exec loki du -sh /loki/*

# Reduce retention period
# Enable compaction
# Increase compaction frequency

# Manual cleanup (if needed)
docker-compose -f docker-compose.production.yml stop loki
docker volume rm deployments_loki-data
docker-compose -f docker-compose.production.yml up -d loki
```

#### 5. Container Logs Not Parsed

**Symptom**: Logs appear but fields not extracted

**Solutions**:

- Verify regex patterns in `promtail-config.yml`
- Check pipeline stages for errors
- Test regex with sample logs
- Review Promtail logs for parsing errors

### Debug Commands

```bash
# View Loki logs
docker-compose -f docker-compose.production.yml logs loki -f

# View Promtail logs
docker-compose -f docker-compose.production.yml logs promtail -f

# Check Loki metrics
curl http://localhost:3100/metrics | grep loki_

# Test Loki API
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={service="minio"}' | jq

# Check ingested streams
curl -G -s "http://localhost:3100/loki/api/v1/labels" | jq
```

---

## Best Practices

### 1. Label Design

**DO**:
- Use labels for filterable metadata (service, environment, level)
- Keep cardinality low (<100 unique values per label)
- Use consistent label names across services

**DON'T**:
- Use labels for high-cardinality data (request IDs, user IDs)
- Create labels from log content
- Use too many labels (>10 per stream)

### 2. Log Format

**Recommendations**:
- Use structured logging (JSON) when possible
- Include consistent fields: timestamp, level, message, component
- Add correlation IDs for request tracing
- Log errors with stack traces

Example MinIO log format:
```json
{
  "time": "2024-01-20T10:30:45.123Z",
  "level": "error",
  "component": "cache",
  "operation": "set",
  "key": "object-123",
  "error": "connection timeout",
  "duration_ms": 5000
}
```

### 3. Query Optimization

- **Filter Early**: Apply label filters before log filters
- **Use Time Ranges**: Always specify time ranges
- **Avoid Wildcards**: Use specific label values when possible
- **Cache Results**: Enable query result caching

### 4. Retention Strategy

- **Short-term**: 7 days for debug logs
- **Medium-term**: 31 days for application logs
- **Long-term**: 90+ days for audit logs (consider external storage)

### 5. Security

- **Log Sanitization**: Never log sensitive data (passwords, tokens, PII)
- **Access Control**: Use Grafana's RBAC for log access control
- **Encryption**: Enable TLS for Promtail → Loki communication (production)
- **Audit Logging**: Enable Loki's audit logging for compliance

### 6. Monitoring

Set up alerts for:
- High error rates: `rate({level="error"}[5m]) > threshold`
- Loki down: `up{job="loki"} == 0`
- High ingestion lag: `loki_ingester_flush_queue_length > 100`
- Disk space: `loki_chunk_store_stored_chunks_total > threshold`

---

## Resources

### Documentation

- [Loki Official Documentation](https://grafana.com/docs/loki/latest/)
- [LogQL Reference](https://grafana.com/docs/loki/latest/logql/)
- [Promtail Configuration](https://grafana.com/docs/loki/latest/clients/promtail/configuration/)
- [Grafana Explore](https://grafana.com/docs/grafana/latest/explore/)

### Tools

- **Loki CLI**: `logcli` - Command-line client for Loki
- **Log Parser Tester**: Test LogQL queries locally
- **Grafana Labs Cloud**: Hosted Loki service

### Support

- **GitHub Issues**: [MinIO Repository Issues](../../issues)
- **Grafana Community**: [Grafana Community Forums](https://community.grafana.com/)
- **Loki Slack**: [Grafana Slack #loki channel](https://grafana.slack.com/)

---

## Changelog

| Date | Version | Changes | Author |
|------|---------|---------|--------|
| 2026-02-06 | 1.0 | Initial log aggregation setup with Loki and Promtail | Claude Code Agent |

---

**Last Updated**: 2026-02-06
**Maintained By**: DevOps Team
**Review Cycle**: Monthly
