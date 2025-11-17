# Enterprise MinIO API Reference

## Overview
The Enterprise MinIO API extends standard S3 API with enterprise features including multi-tenancy, advanced replication, cost analytics, and compliance controls.

**Base URL**: `https://your-enterprise-minio.com:8080/api/v1`

**Authentication**: Bearer token in Authorization header
```
Authorization: Bearer <tenant_access_token>
```

---

## Multi-Tenancy APIs

### Create Tenant

Create a new isolated tenant.

```http
POST /api/v1/tenants
Authorization: Bearer <admin_token>
Content-Type: application/json

{
  "name": "Acme Corporation",
  "storage_quota": 107374182400,
  "bandwidth_quota": 1073741824,
  "request_rate_limit": 10000,
  "regions": ["us-east-1", "eu-west-1"],
  "data_residency": "EU",
  "features": {
    "active_active_replication": true,
    "cost_analytics": true,
    "advanced_audit": true,
    "disaster_recovery": true,
    "data_tiering": true,
    "edge_acceleration": true,
    "compliance_modules": "GDPR"
  }
}
```

**Response (201 Created)**:
```json
{
  "id": "tenant_a1b2c3d4e5f6",
  "name": "Acme Corporation",
  "storage_quota": 107374182400,
  "created_at": "2024-01-15T10:30:00Z",
  "status": "active"
}
```

### List Tenants

```http
GET /api/v1/tenants
Authorization: Bearer <admin_token>
```

**Query Parameters**:
- `limit` (default: 100) - Maximum number of results
- `offset` (default: 0) - Pagination offset
- `status` - Filter by status: active, suspended, deleted

**Response**:
```json
{
  "tenants": [
    {
      "id": "tenant_a1b2c3d4e5f6",
      "name": "Acme Corporation",
      "storage_used": 53687091200,
      "storage_quota": 107374182400,
      "status": "active",
      "created_at": "2024-01-15T10:30:00Z"
    }
  ],
  "total": 1,
  "limit": 100,
  "offset": 0
}
```

### Get Tenant Details

```http
GET /api/v1/tenants/{tenant_id}
Authorization: Bearer <admin_token>
```

**Response**:
```json
{
  "id": "tenant_a1b2c3d4e5f6",
  "name": "Acme Corporation",
  "storage_quota": 107374182400,
  "bandwidth_quota": 1073741824,
  "request_rate_limit": 10000,
  "regions": ["us-east-1", "eu-west-1"],
  "data_residency": "EU",
  "features": {
    "active_active_replication": true,
    "cost_analytics": true
  },
  "status": "active",
  "created_at": "2024-01-15T10:30:00Z",
  "updated_at": "2024-01-20T14:22:00Z"
}
```

### Update Tenant Quota

```http
PATCH /api/v1/tenants/{tenant_id}
Authorization: Bearer <admin_token>
Content-Type: application/json

{
  "storage_quota": 214748364800,
  "request_rate_limit": 20000
}
```

### Get Tenant Metrics

```http
GET /api/v1/tenants/{tenant_id}/metrics
Authorization: Bearer <tenant_token>
```

**Query Parameters**:
- `time_range` - 1h, 24h, 7d, 30d (default: 24h)
- `granularity` - 1m, 5m, 1h (default: 1h)

**Response**:
```json
{
  "tenant_id": "tenant_a1b2c3d4e5f6",
  "period": {
    "start": "2024-01-20T00:00:00Z",
    "end": "2024-01-21T00:00:00Z"
  },
  "storage": {
    "used_bytes": 53687091200,
    "quota_bytes": 107374182400,
    "percentage": 50.0
  },
  "operations": {
    "total_requests": 1234567,
    "get_requests": 800000,
    "put_requests": 300000,
    "delete_requests": 100000,
    "list_requests": 34567
  },
  "performance": {
    "average_latency_ms": 45.2,
    "p99_latency_ms": 250.5,
    "throughput_mbps": 125.3,
    "error_rate_percent": 0.1
  },
  "costs": {
    "storage_cost": 1250.00,
    "request_cost": 125.50,
    "bandwidth_cost": 450.75,
    "total_cost": 1826.25
  }
}
```

---

## Replication APIs

### Create Replication Configuration

```http
POST /api/v1/replication/configs
Authorization: Bearer <admin_token>
Content-Type: application/json

{
  "source_region": "us-east-1",
  "destination_regions": ["eu-west-1", "ap-south-1"],
  "rule": {
    "filter": {
      "prefix": "important-data/",
      "size": {
        "min": 0,
        "max": 5368709120
      }
    },
    "action": "replicate",
    "storage_class": "STANDARD"
  },
  "conflict_resolution": "last-write-wins",
  "max_replication_delay_ms": 100,
  "enable_bidirectional": true
}
```

### List Replication Configurations

```http
GET /api/v1/replication/configs
Authorization: Bearer <admin_token>
```

### Get Replication Status

```http
GET /api/v1/replication/status
Authorization: Bearer <admin_token>
```

**Response**:
```json
{
  "replication_id": "rep_config_123",
  "status": "healthy",
  "regions": {
    "us-east-1": {
      "role": "source",
      "status": "healthy",
      "objects_replicated": 1000000,
      "bytes_replicated": 53687091200,
      "last_sync": "2024-01-21T10:00:00Z"
    },
    "eu-west-1": {
      "role": "destination",
      "status": "healthy",
      "replication_lag_ms": 45,
      "objects_synced": 1000000,
      "last_update": "2024-01-21T10:00:00Z"
    },
    "ap-south-1": {
      "role": "destination",
      "status": "degraded",
      "replication_lag_ms": 850,
      "objects_synced": 998500,
      "last_update": "2024-01-21T09:55:00Z",
      "error": "Network latency high"
    }
  },
  "conflicts_detected": 12,
  "conflicts_resolved": 12,
  "pending_objects": 0
}
```

### Trigger Replication Sync

```http
POST /api/v1/replication/{replication_id}/sync
Authorization: Bearer <admin_token>

{
  "force": true,
  "include_deleted": true
}
```

---

## Caching APIs

### Get Cache Status

```http
GET /api/v1/cache/status
Authorization: Bearer <tenant_token>
```

**Response**:
```json
{
  "l1_cache": {
    "tier": "L1",
    "backend": "memory",
    "max_size_bytes": 53687091200,
    "used_bytes": 26843545600,
    "hit_ratio": 0.92,
    "eviction_policy": "LRU"
  },
  "l2_cache": {
    "tier": "L2",
    "backend": "nvme",
    "max_size_bytes": 536870912000,
    "used_bytes": 268435456000,
    "hit_ratio": 0.78,
    "ttl_seconds": 86400
  },
  "l3_cache": {
    "tier": "L3",
    "backend": "s3",
    "max_size_bytes": 10995116277760,
    "used_bytes": 5497558138880,
    "hit_ratio": 0.45,
    "ttl_seconds": 604800
  },
  "compression": {
    "enabled": true,
    "codec": "zstd",
    "compression_ratio": 0.35,
    "total_compressed_bytes": 18796884480,
    "total_uncompressed_bytes": 53687091200
  }
}
```

### Invalidate Cache Entry

```http
DELETE /api/v1/cache/objects/{object_key}
Authorization: Bearer <tenant_token>

{
  "cascade": false,
  "invalidate_all_tiers": true
}
```

---

## Monitoring APIs

### Get Metrics

```http
GET /api/v1/metrics
Authorization: Bearer <tenant_token>
```

**Query Parameters**:
- `time_range` - Time range in minutes (default: 60)
- `granularity` - Aggregation granularity: 1m, 5m, 1h

**Response**:
```json
{
  "metrics": [
    {
      "timestamp": "2024-01-21T10:00:00Z",
      "put_ops": 12345,
      "get_ops": 98765,
      "delete_ops": 1234,
      "list_ops": 5678,
      "put_latency_p99_ms": 125.5,
      "get_latency_p99_ms": 45.2,
      "error_rate_percent": 0.05,
      "cache_hit_ratio": 0.88,
      "replication_lag_ms": 45
    }
  ]
}
```

### Get Prometheus Metrics

```http
GET /api/v1/metrics/prometheus
Authorization: Bearer <admin_token>
```

Returns metrics in Prometheus exposition format.

### List Alerts

```http
GET /api/v1/alerts
Authorization: Bearer <admin_token>
```

**Query Parameters**:
- `severity` - critical, warning, info
- `status` - firing, resolved
- `limit` - Maximum number of alerts (default: 100)

**Response**:
```json
{
  "alerts": [
    {
      "id": "alert_123",
      "rule_id": "rule_high_error_rate",
      "severity": "critical",
      "status": "firing",
      "message": "Error rate exceeded 1% threshold",
      "value": 1.5,
      "threshold": 1.0,
      "timestamp": "2024-01-21T10:15:00Z",
      "resolved_at": null
    }
  ]
}
```

---

## Audit & Compliance APIs

### Get Audit Log

```http
GET /api/v1/audit/logs
Authorization: Bearer <tenant_token>
```

**Query Parameters**:
- `start_time` - ISO 8601 timestamp
- `end_time` - ISO 8601 timestamp
- `action` - Filter by action (PUT, GET, DELETE, etc.)
- `limit` - Maximum results (default: 1000)

**Response**:
```json
{
  "logs": [
    {
      "id": "log_123",
      "tenant_id": "tenant_a1b2c3d4e5f6",
      "timestamp": "2024-01-21T10:15:23Z",
      "action": "PUT",
      "resource": "bucket/object-key",
      "status": "success",
      "user_id": "user_123",
      "source_ip": "192.168.1.1",
      "details": {
        "size_bytes": 1048576,
        "encryption": "AES-256-GCM"
      }
    }
  ],
  "total": 5000,
  "limit": 100
}
```

### Export Audit Trail

```http
POST /api/v1/audit/export
Authorization: Bearer <admin_token>
Content-Type: application/json

{
  "start_time": "2024-01-01T00:00:00Z",
  "end_time": "2024-01-31T23:59:59Z",
  "format": "csv",
  "include_details": true
}
```

**Response**:
```json
{
  "export_id": "export_123",
  "status": "processing",
  "download_url": "https://...",
  "expires_at": "2024-01-28T10:30:00Z"
}
```

---

## Cost Analytics APIs

### Get Cost Analysis

```http
GET /api/v1/costs/analysis
Authorization: Bearer <tenant_token>
```

**Query Parameters**:
- `period` - 1m, 1h, 1d, 1w, 1mo, 1y (default: 1mo)
- `breakdown` - by_region, by_operation, by_storage_class

**Response**:
```json
{
  "period": {
    "start": "2024-01-01T00:00:00Z",
    "end": "2024-01-31T23:59:59Z"
  },
  "summary": {
    "total_cost": 1826.25,
    "storage_cost": 1250.00,
    "request_cost": 125.50,
    "bandwidth_cost": 450.75
  },
  "breakdown_by_region": {
    "us-east-1": 912.50,
    "eu-west-1": 690.25,
    "ap-south-1": 223.50
  },
  "breakdown_by_operation": {
    "PUT": 45.50,
    "GET": 60.25,
    "DELETE": 12.75,
    "LIST": 7.00
  }
}
```

### Get Cost Forecast

```http
GET /api/v1/costs/forecast
Authorization: Bearer <tenant_token>
```

**Query Parameters**:
- `forecast_horizon_days` - 7, 30, 90 (default: 30)

**Response**:
```json
{
  "forecast": [
    {
      "date": "2024-01-22",
      "predicted_cost": 58.9,
      "confidence_interval": {
        "low": 52.1,
        "high": 65.7
      }
    }
  ],
  "trend": "increasing",
  "projected_monthly_cost": 1876.00,
  "recommendations": [
    "Consider enabling data tiering to reduce storage costs",
    "Archive objects older than 90 days"
  ]
}
```

---

## Error Responses

All error responses follow this format:

```json
{
  "error": {
    "code": "INVALID_REQUEST",
    "message": "Request validation failed",
    "details": {
      "field": "storage_quota",
      "reason": "Must be greater than 1GB"
    },
    "request_id": "req_123abc"
  }
}
```

### Common Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| INVALID_REQUEST | 400 | Invalid request format or parameters |
| UNAUTHORIZED | 401 | Missing or invalid authentication token |
| FORBIDDEN | 403 | Insufficient permissions |
| NOT_FOUND | 404 | Resource not found |
| QUOTA_EXCEEDED | 429 | Quota limit exceeded |
| INTERNAL_ERROR | 500 | Server error |
| SERVICE_UNAVAILABLE | 503 | Service temporarily unavailable |

---

## Rate Limiting

API requests are rate-limited based on tenant tier:

- **Starter**: 100 requests/second
- **Professional**: 1,000 requests/second
- **Enterprise**: 10,000 requests/second

Rate limit headers are included in all responses:

```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 987
X-RateLimit-Reset: 1642765200
```

---

## Pagination

List endpoints support cursor-based pagination:

```http
GET /api/v1/tenants?limit=50&offset=0
```

Response includes pagination metadata:

```json
{
  "data": [...],
  "pagination": {
    "limit": 50,
    "offset": 0,
    "total": 250,
    "has_more": true,
    "next_offset": 50
  }
}
```

---

## Webhooks

Register webhooks for real-time event notifications:

```http
POST /api/v1/webhooks
Authorization: Bearer <admin_token>
Content-Type: application/json

{
  "url": "https://your-service.com/webhook",
  "events": ["object.created", "object.deleted", "alert.triggered"],
  "active": true
}
```

Webhook payload example:

```json
{
  "event": "object.created",
  "timestamp": "2024-01-21T10:30:00Z",
  "tenant_id": "tenant_a1b2c3d4e5f6",
  "data": {
    "bucket": "my-bucket",
    "object": "path/to/object",
    "size_bytes": 1048576
  }
}
```

---

## SDKs & Libraries

- **Python**: `pip install enterprise-minio-sdk`
- **JavaScript/Node.js**: `npm install enterprise-minio-sdk`
- **Go**: `go get github.com/enterprise-minio/sdk-go`
- **Java**: Available via Maven Central

See SDK documentation at: https://docs.enterprise-minio.io/sdks

---

## Support

For API support:
- Documentation: https://docs.enterprise-minio.io
- Email: api-support@enterprise-minio.io
- Slack: https://enterprise-minio.slack.com
