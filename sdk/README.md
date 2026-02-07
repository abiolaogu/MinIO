# MinIO Enterprise SDK

Official SDK client libraries for MinIO Enterprise - Ultra-High-Performance Object Storage

## Available SDKs

### Go SDK

**Location**: `sdk/go/`

Full-featured Go client library with type-safe API and zero external dependencies.

**Features**:
- Full API coverage (Upload, Download, Delete, List, Quota, Health)
- Automatic retry with exponential backoff
- HTTP/2 connection pooling
- Context support for cancellation and timeouts
- Zero allocations in critical paths
- 100% test coverage

**Installation**:
```bash
go get github.com/abiolaogu/MinIO/sdk/go
```

**Quick Example**:
```go
client, _ := minio.NewClient(minio.Config{
    Endpoint: "http://localhost:9000",
    APIKey:   "your-api-key",
})
defer client.Close()

resp, _ := client.Upload(ctx, minio.UploadRequest{
    TenantID: "my-tenant",
    Key:      "document.pdf",
    Data:     file,
})
```

[View Go SDK Documentation →](go/README.md)

---

### Python SDK

**Location**: `sdk/python/`

Pythonic client library with type hints and comprehensive error handling.

**Features**:
- Full API coverage (Upload, Download, Delete, List, Quota, Health)
- Automatic retry with exponential backoff
- Connection pooling (100 connections per host)
- Context manager support
- Type hints for IDE support
- Streaming support for large files

**Installation**:
```bash
pip install minio-enterprise
```

**Quick Example**:
```python
from minio_enterprise import MinIOClient

with MinIOClient(endpoint="http://localhost:9000", api_key="key") as client:
    response = client.upload(
        tenant_id="my-tenant",
        key="document.pdf",
        data=file,
    )
```

[View Python SDK Documentation →](python/README.md)

---

## API Coverage

Both SDKs provide complete coverage of the MinIO Enterprise API:

| Operation | Go SDK | Python SDK | Description |
|-----------|--------|------------|-------------|
| Upload | ✅ | ✅ | Upload objects with metadata |
| Download | ✅ | ✅ | Download objects as streams |
| Delete | ✅ | ✅ | Delete objects |
| List | ✅ | ✅ | List objects with filtering |
| Get Quota | ✅ | ✅ | Check tenant quota usage |
| Health Check | ✅ | ✅ | Service health status |

## Authentication

Both SDKs support multiple authentication methods:

1. **API Key Authentication**:
   ```go
   // Go
   client, _ := minio.NewClient(minio.Config{
       Endpoint: "http://localhost:9000",
       APIKey:   "your-api-key",
   })
   ```
   ```python
   # Python
   client = MinIOClient(
       endpoint="http://localhost:9000",
       api_key="your-api-key",
   )
   ```

2. **JWT Token Authentication**:
   ```go
   // Go
   client, _ := minio.NewClient(minio.Config{
       Endpoint: "http://localhost:9000",
       Token:    "jwt-token",
   })
   ```
   ```python
   # Python
   client = MinIOClient(
       endpoint="http://localhost:9000",
       token="jwt-token",
   )
   ```

## Common Patterns

### Upload a File

**Go**:
```go
file, _ := os.Open("document.pdf")
defer file.Close()

stat, _ := file.Stat()
resp, err := client.Upload(ctx, minio.UploadRequest{
    TenantID: "my-tenant",
    Key:      "uploads/document.pdf",
    Data:     file,
    Size:     stat.Size(),
})
```

**Python**:
```python
with open("document.pdf", "rb") as f:
    response = client.upload(
        tenant_id="my-tenant",
        key="uploads/document.pdf",
        data=f,
    )
```

### Download a File

**Go**:
```go
reader, err := client.Download(ctx, minio.DownloadRequest{
    TenantID: "my-tenant",
    Key:      "uploads/document.pdf",
})
defer reader.Close()

out, _ := os.Create("downloaded.pdf")
io.Copy(out, reader)
```

**Python**:
```python
stream = client.download(
    tenant_id="my-tenant",
    key="uploads/document.pdf",
)

with open("downloaded.pdf", "wb") as f:
    f.write(stream.read())
```

### List All Objects

**Go**:
```go
resp, err := client.List(ctx, minio.ListRequest{
    TenantID: "my-tenant",
    Prefix:   "documents/",
})

for _, obj := range resp.Objects {
    fmt.Printf("%s (%d bytes)\n", obj.Key, obj.Size)
}
```

**Python**:
```python
# Auto-pagination
for obj in client.list_all(tenant_id="my-tenant", prefix="documents/"):
    print(f"{obj['key']} ({obj['size']} bytes)")
```

### Check Quota

**Go**:
```go
quota, err := client.GetQuota(ctx, "my-tenant")
fmt.Printf("Used: %d / %d bytes\n", quota.Used, quota.Limit)
```

**Python**:
```python
quota = client.get_quota(tenant_id="my-tenant")
print(f"Used: {quota['used']} / {quota['limit']} bytes")
```

## Error Handling

### Go

```go
resp, err := client.Upload(ctx, req)
if err != nil {
    if strings.Contains(err.Error(), "required") {
        // Validation error
    } else if strings.Contains(err.Error(), "timeout") {
        // Timeout error
    } else {
        // Other errors
    }
    return err
}
```

### Python

```python
from minio_enterprise import ValidationError, APIError

try:
    response = client.upload(...)
except ValidationError as e:
    print(f"Validation error: {e}")
except APIError as e:
    if e.status_code == 404:
        print("Not found")
    elif e.status_code == 403:
        print("Permission denied")
```

## Performance Characteristics

### Go SDK
- **Zero allocations** in critical paths
- **Connection pooling**: 100 idle connections per host
- **Retry logic**: Up to 3 retries with exponential backoff
- **Context support**: Proper cancellation and timeout handling

### Python SDK
- **Connection pooling**: 100 connections per host (via urllib3)
- **Retry logic**: Configurable retry with exponential backoff
- **Streaming support**: Efficient handling of large files
- **Thread-safe**: Safe for concurrent operations

## Testing

### Go SDK
```bash
cd sdk/go
go test -v
go test -race
go test -cover
```

### Python SDK
```bash
cd sdk/python
python -m pytest test_minio_enterprise.py -v
python -m pytest --cov=minio_enterprise
```

## Requirements

### Go SDK
- Go 1.18 or later
- No external dependencies (uses only Go standard library)

### Python SDK
- Python 3.7 or later
- requests >= 2.25.0
- urllib3 >= 1.26.0

## Documentation

- [API Reference (OpenAPI)](../docs/api/) - Complete API specification
- [Go SDK Documentation](go/README.md) - Go-specific documentation
- [Python SDK Documentation](python/README.md) - Python-specific documentation
- [Performance Guide](../docs/guides/PERFORMANCE.md) - Performance optimization tips
- [Deployment Guide](../docs/guides/DEPLOYMENT.md) - Production deployment guide

## Examples

Complete example applications are available in each SDK directory:

- **Go**: See [sdk/go/README.md](go/README.md) for examples
- **Python**: See [sdk/python/README.md](python/README.md) for examples

## Support

- **Issues**: [GitHub Issues](https://github.com/abiolaogu/MinIO/issues)
- **Discussions**: [GitHub Discussions](https://github.com/abiolaogu/MinIO/discussions)
- **Documentation**: [MinIO Enterprise Docs](https://github.com/abiolaogu/MinIO/tree/main/docs)

## License

Apache License 2.0 - See [LICENSE](../LICENSE) file for details

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines.

---

**Version**: 2.0.0
**Last Updated**: 2026-02-07
**Status**: ✅ Production Ready
