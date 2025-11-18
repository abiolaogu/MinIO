# MinIO Enterprise Deployment Guide

## 🚀 Quick Start

### Prerequisites
- Docker 24.0+
- Docker Compose 2.20+
- 16GB+ RAM recommended
- 100GB+ disk space

### 1. Clone and Configure

```bash
# Clone repository
git clone <repository-url>
cd MinIO

# Copy environment template
cp .env.example .env

# Edit configuration
vim .env  # Update passwords and settings
```

### 2. Build Production Image

```bash
# Build optimized production image
docker build -f Dockerfile.production -t minio-enterprise:latest .

# Verify image
docker images | grep minio-enterprise
```

### 3. Deploy Stack

```bash
# Start all services
docker-compose -f docker-compose.production.yml up -d

# Check status
docker-compose -f docker-compose.production.yml ps

# View logs
docker-compose -f docker-compose.production.yml logs -f minio1
```

### 4. Verify Deployment

```bash
# Health check
curl http://localhost:9000/minio/health/live

# Metrics
curl http://localhost:9090/metrics

# Console
open http://localhost:9001
```

---

## 🏗️ Architecture Overview

```
                         ┌─────────────┐
                         │   HAProxy   │
                         │ Load Balancer│
                         └──────┬──────┘
                                │
                ┌───────────────┼───────────────┐
                │               │               │
         ┌──────▼─────┐  ┌─────▼──────┐  ┌────▼───────┐
         │   MinIO1   │  │   MinIO2   │  │   MinIO3/4 │
         │  (Leader)  │  │ (Replica)  │  │ (Replicas) │
         └──────┬─────┘  └─────┬──────┘  └────┬───────┘
                │               │               │
                └───────────────┼───────────────┘
                                │
                    ┌───────────┴───────────┐
                    │                       │
             ┌──────▼──────┐        ┌──────▼──────┐
             │ PostgreSQL  │        │    Redis    │
             │  Metadata   │        │    Cache    │
             └─────────────┘        └─────────────┘
                    │                       │
                    └───────────┬───────────┘
                                │
                    ┌───────────▼───────────┐
                    │                       │
             ┌──────▼──────┐        ┌──────▼──────┐
             │ Prometheus  │        │   Grafana   │
             │  Metrics    │        │     UI      │
             └─────────────┘        └─────────────┘
```

---

## 📦 Components

### MinIO Cluster (4 nodes)
- **Ports**: 9000 (API), 9001 (Console)
- **HA**: Distributed mode with 4 nodes
- **Resources**: 8 CPU, 16GB RAM per node
- **Storage**: Persistent volumes

### HAProxy Load Balancer
- **Ports**: 80 (HTTP), 443 (HTTPS), 8404 (Stats)
- **Algorithm**: Least connections
- **Health checks**: Every 10s

### PostgreSQL Database
- **Port**: 5432
- **Configuration**: Optimized for OLTP
- **Connections**: 200 max
- **Storage**: Persistent volume

### Redis Cache
- **Port**: 6379
- **Memory**: 4GB with LRU eviction
- **Persistence**: AOF + RDB snapshots

### Prometheus Monitoring
- **Port**: 9090
- **Retention**: 30 days
- **Storage**: 50GB limit

### Grafana Dashboards
- **Port**: 3000
- **Dashboards**: Pre-configured for MinIO
- **Alerts**: Configured rules

### Jaeger Tracing
- **Ports**: 16686 (UI), 14268 (Collector)
- **Storage**: Badger (persistent)

---

## 🔒 Security Hardening

### 1. Change Default Credentials

```bash
# Update .env file
MINIO_ROOT_USER=your_secure_username
MINIO_ROOT_PASSWORD=your_very_secure_password_min_32_chars
POSTGRES_PASSWORD=postgres_secure_password
GRAFANA_PASSWORD=grafana_secure_password
```

### 2. Enable TLS

```bash
# Generate certificates
mkdir -p certs
openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
  -keyout certs/server.key -out certs/server.crt

# Combine for HAProxy
cat certs/server.crt certs/server.key > certs/server.pem

# Update docker-compose to mount certs
```

### 3. Network Isolation

```yaml
# Create isolated network
networks:
  minio-internal:
    driver: bridge
    internal: true  # No external access
  minio-external:
    driver: bridge
```

### 4. Read-Only Containers

```yaml
# Enable in docker-compose
read_only: true
tmpfs:
  - /tmp:rw,noexec,nosuid,size=1g
```

### 5. Security Scanning

```bash
# Scan with Trivy
trivy image minio-enterprise:latest

# Scan with Grype
grype minio-enterprise:latest
```

---

## 📊 Monitoring & Observability

### Grafana Dashboards

Access at http://localhost:3000

**Pre-configured Dashboards:**
- MinIO Overview
- Cache Performance
- Replication Metrics
- Tenant Usage
- System Resources

### Prometheus Metrics

Key metrics to monitor:
```
minio_cache_hit_ratio
minio_replication_latency_seconds
minio_tenant_quota_usage_bytes
minio_cluster_nodes_online
```

### Jaeger Tracing

Access at http://localhost:16686

Track distributed requests across:
- Cache operations
- Replication flows
- Tenant operations

---

## 🔧 Performance Tuning

### Kernel Parameters

```bash
# Add to /etc/sysctl.conf
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_tw_reuse=1
net.core.rmem_max=134217728
net.core.wmem_max=134217728
fs.file-max=2097152

# Apply
sysctl -p
```

### Docker Settings

```json
{
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10,
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
```

### MinIO Optimization

```bash
# Environment variables in .env
MINIO_API_REQUESTS_MAX=10000
MINIO_API_REQUESTS_DEADLINE=10s
MINIO_CACHE_DRIVES="/cache"
MINIO_CACHE_QUOTA=80
MINIO_STORAGE_CLASS_STANDARD=EC:4
```

---

## 🔄 Backup & Recovery

### Database Backup

```bash
# Backup PostgreSQL
docker exec postgres pg_dump -U minio minio_enterprise > backup.sql

# Restore
docker exec -i postgres psql -U minio minio_enterprise < backup.sql
```

### MinIO Data Backup

```bash
# Using mc (MinIO Client)
mc alias set myminio http://localhost:9000 minioadmin minioadmin123
mc mirror myminio/bucket /backup/location
```

### Automated Backups

```bash
# Add to crontab
0 2 * * * /path/to/backup-script.sh
```

---

## 📈 Scaling

### Horizontal Scaling

```bash
# Add more MinIO nodes
docker-compose -f docker-compose.production.yml up -d --scale minio=8
```

### Vertical Scaling

```yaml
# Update resource limits
deploy:
  resources:
    limits:
      cpus: '16'
      memory: 32G
```

### Kubernetes Deployment

```bash
# Apply manifests
kubectl apply -f k8s/namespace.yml
kubectl apply -f k8s/statefulset.yml
kubectl apply -f k8s/service.yml
kubectl apply -f k8s/ingress.yml
```

---

## 🐛 Troubleshooting

### Check Logs

```bash
# All services
docker-compose -f docker-compose.production.yml logs

# Specific service
docker-compose -f docker-compose.production.yml logs -f minio1

# Last 100 lines
docker-compose -f docker-compose.production.yml logs --tail=100
```

### Health Checks

```bash
# MinIO
curl http://localhost:9000/minio/health/live
curl http://localhost:9000/minio/health/ready

# PostgreSQL
docker exec postgres pg_isready

# Redis
docker exec redis redis-cli ping
```

### Performance Issues

```bash
# Check resource usage
docker stats

# Check disk I/O
iostat -x 1

# Check network
iftop
```

### Common Issues

**Issue**: Container keeps restarting
```bash
# Check logs
docker logs container_name

# Check resource limits
docker inspect container_name | grep -A 20 Resources
```

**Issue**: High memory usage
```bash
# Adjust GOGC
export GOGC=50

# Add memory limit
export GOMEMLIMIT=14GB
```

**Issue**: Slow performance
```bash
# Enable profiling
curl http://localhost:6060/debug/pprof/profile > cpu.prof
go tool pprof cpu.prof
```

---

## 🔐 Production Checklist

- [ ] Change all default passwords
- [ ] Enable TLS/SSL
- [ ] Configure firewall rules
- [ ] Set up automated backups
- [ ] Configure monitoring alerts
- [ ] Enable audit logging
- [ ] Implement rate limiting
- [ ] Set resource quotas
- [ ] Configure log rotation
- [ ] Test disaster recovery
- [ ] Document runbooks
- [ ] Set up on-call rotation

---

## 📞 Support

- **Documentation**: https://docs.minio-enterprise.io
- **Issues**: https://github.com/minio/enterprise/issues
- **Email**: support@minio-enterprise.io
- **Slack**: #minio-enterprise

---

**Version**: 2.0.0
**Last Updated**: 2024-01-18
**Maintainer**: MinIO Enterprise Team
