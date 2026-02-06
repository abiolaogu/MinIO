# MinIO Enterprise API Documentation

This directory contains the OpenAPI 3.0 specification for MinIO Enterprise API.

## Overview

MinIO Enterprise provides a high-performance object storage API with:
- **Upload/Download**: Object storage operations with 500K writes/sec and 2M reads/sec
- **Health Checks**: Kubernetes-compatible liveness and readiness probes
- **Metrics**: Prometheus-formatted performance metrics
- **Multi-tenancy**: Tenant isolation with quota management

## Files

- `openapi.yaml` - OpenAPI 3.0 specification (complete API documentation)

## API Endpoints

### Object Storage
- `POST /upload` - Upload an object (requires X-Tenant-ID header)
- `PUT /upload` - Upload an object (alternative method)
- `GET /download` - Download an object (requires X-Tenant-ID header)

### Health Checks
- `GET /minio/health/live` - Liveness probe (Kubernetes)
- `GET /minio/health/ready` - Readiness probe (Kubernetes)

### Metrics & Info
- `GET /` - Server information and version
- `GET /metrics` - Prometheus metrics (port 9001)

## Viewing the Documentation

### Option 1: Integrated Swagger UI (Recommended) ✨ NEW
We now have a custom Swagger UI integration with enhanced features!

```bash
# From the docs/api directory
docker-compose up -d

# Access the documentation at:
# http://localhost:8080
```

**Features**:
- Interactive API testing with "Try it out" functionality
- Persistent authentication headers
- Syntax highlighting with Monokai theme
- Request duration display
- Full search capabilities
- Auto-generated code examples

Stop the server:
```bash
docker-compose down
```

**Alternative without Docker**:
```bash
# Using Python's built-in HTTP server
cd docs/api
python3 -m http.server 8080

# Or using Node.js http-server
npx http-server -p 8080

# Access at http://localhost:8080
```

### Option 2: Swagger UI (Online)
1. Go to [Swagger Editor](https://editor.swagger.io/)
2. Copy the contents of `openapi.yaml`
3. Paste into the editor
4. View the interactive documentation

### Option 3: Redoc (Local with Docker)
```bash
docker run -p 8080:80 \
  -e SPEC_URL=/api/openapi.yaml \
  -v $(pwd)/docs/api:/api \
  redocly/redoc
```
Then open: http://localhost:8080

### Option 4: VS Code Extension
1. Install "OpenAPI (Swagger) Editor" extension
2. Open `openapi.yaml` in VS Code
3. Right-click → "Preview Swagger"

## Validating the Specification

### Using Swagger Editor
1. Go to [Swagger Editor](https://editor.swagger.io/)
2. Paste the `openapi.yaml` contents
3. Check for any validation errors in the right panel

### Using OpenAPI CLI
```bash
npm install -g @openapitools/openapi-generator-cli
openapi-generator-cli validate -i docs/api/openapi.yaml
```

### Using Docker
```bash
docker run --rm -v $(pwd):/local openapitools/openapi-generator-cli validate \
  -i /local/docs/api/openapi.yaml
```

## Generating Client SDKs

The OpenAPI specification can be used to generate client libraries for various languages.

### Go Client
```bash
openapi-generator-cli generate \
  -i docs/api/openapi.yaml \
  -g go \
  -o ./sdk/go
```

### Python Client
```bash
openapi-generator-cli generate \
  -i docs/api/openapi.yaml \
  -g python \
  -o ./sdk/python
```

### JavaScript/TypeScript Client
```bash
openapi-generator-cli generate \
  -i docs/api/openapi.yaml \
  -g typescript-axios \
  -o ./sdk/typescript
```

## Example Usage

### Upload Object
```bash
curl -X POST "http://localhost:9000/upload?key=test-file.txt" \
  -H "X-Tenant-ID: 550e8400-e29b-41d4-a716-446655440000" \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@test-file.txt"
```

Response:
```json
{
  "status": "uploaded",
  "key": "test-file.txt",
  "size": 1024
}
```

### Download Object
```bash
curl -X GET "http://localhost:9000/download?key=test-file.txt" \
  -H "X-Tenant-ID: 550e8400-e29b-41d4-a716-446655440000" \
  -o downloaded-file.txt
```

### Get Metrics
```bash
curl http://localhost:9001/metrics
```

### Health Check
```bash
curl http://localhost:9000/minio/health/live
# Response: OK

curl http://localhost:9000/minio/health/ready
# Response: READY
```

## Authentication

All object storage endpoints require the `X-Tenant-ID` header for:
- Multi-tenant isolation
- Quota management (storage size, object count, bandwidth)
- Access control

Health check and metrics endpoints do not require authentication.

## Performance Specifications

| Operation | Performance | Latency |
|-----------|-------------|---------|
| Cache Writes | 500K ops/sec | <1ms |
| Cache Reads | 2M ops/sec | <1ms |
| Replication | 10K ops/sec | <50ms P99 |
| Cache Hit Rate | 95%+ | - |

## Next Steps

1. ~~**Swagger UI Integration**: Deploy Swagger UI for interactive documentation~~ ✅ COMPLETED (2026-02-05)
2. **SDK Generation**: Generate official client libraries (Go, Python, JavaScript)
3. **API Testing**: Add automated API tests using the specification
4. **Versioning**: Implement API versioning strategy (/api/v1, /api/v2)
5. **Enhanced Auth**: Add OAuth2/JWT authentication flows

## Related Documentation

- [README.md](../../README.md) - Project overview
- [PERFORMANCE.md](../guides/PERFORMANCE.md) - Performance optimization guide
- [DEPLOYMENT.md](../guides/DEPLOYMENT.md) - Deployment instructions
- [PRD.md](../PRD.md) - Product requirements document

## Contributing

To update the API documentation:
1. Edit `openapi.yaml` using the OpenAPI 3.0 specification
2. Validate the specification using one of the methods above
3. Test with Swagger UI to ensure it renders correctly
4. Update this README if adding new endpoints
5. Submit a pull request

## Support

For API questions or issues:
- Open an issue: [GitHub Issues](https://github.com/abiolaogu/MinIO/issues)
- Read the docs: [Documentation](../../README.md)
