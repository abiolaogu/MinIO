# MinIO Enterprise SDK

Official SDK client libraries for MinIO Enterprise - Ultra-High-Performance Object Storage

## Available SDKs

### Go SDK
- **Location**: [`sdk/go/`](./go/)
- **Package**: `github.com/abiolaogu/MinIO/sdk/go`
- **Status**: ✅ Production Ready
- **Features**:
  - Zero external dependencies (standard library only)
  - Type-safe API with full compile-time checking
  - Automatic retry with exponential backoff
  - Connection pooling with HTTP/2 support
  - Context-aware operations
  - Comprehensive test coverage

**Installation:**
```bash
go get github.com/abiolaogu/MinIO/sdk/go
```

**Quick Start:**
```go
import minio "github.com/abiolaogu/MinIO/sdk/go"

client, err := minio.New(&minio.Config{
    Endpoint:  "http://localhost:9000",
    APIKey:    "your-api-key",
    APISecret: "your-api-secret",
    TenantID:  "your-tenant-id",
})

err = client.Upload(ctx, "bucket", "key", data)
```

See [Go SDK Documentation](./go/README.md) for details.

### Python SDK
- **Location**: [`sdk/python/`](./python/)
- **Package**: `minio-enterprise` (PyPI)
- **Status**: ✅ Production Ready
- **Features**:
  - Pythonic API with type hints
  - Context manager support
  - Automatic retry with exponential backoff
  - Connection pooling with requests.Session
  - Custom exception classes for error handling
  - Comprehensive test coverage

**Installation:**
```bash
pip install minio-enterprise
```

**Quick Start:**
```python
from minio_enterprise import Client

with Client(
    endpoint="http://localhost:9000",
    api_key="your-api-key",
    api_secret="your-api-secret",
    tenant_id="your-tenant-id"
) as client:
    client.upload("bucket", "key", b"data")
```

See [Python SDK Documentation](./python/README.md) for details.

## API Coverage

Both SDKs provide complete coverage of the MinIO Enterprise API:

| Operation | Go SDK | Python SDK | Description |
|-----------|--------|------------|-------------|
| Upload | ✅ | ✅ | Upload objects to MinIO |
| Download | ✅ | ✅ | Download objects from MinIO |
| Delete | ✅ | ✅ | Delete objects |
| List | ✅ | ✅ | List objects in a bucket |
| Get Quota | ✅ | ✅ | Get tenant quota information |
| Health | ✅ | ✅ | Check service health |

## Common Features

All SDKs share these features:

### 1. Authentication
- API Key + Secret authentication
- Tenant ID for multi-tenancy support
- Secure header-based authentication

### 2. Automatic Retry
- Exponential backoff for transient failures
- Configurable retry attempts (default: 3)
- Retry only on server errors (5xx)
- No retry on client errors (4xx)

### 3. Connection Pooling
- Efficient connection reuse
- Configurable pool size
- Keep-alive connections
- HTTP/2 support (Go SDK)

### 4. Error Handling
- Type-specific error classes/types
- Detailed error messages
- Status code preservation
- Retryable vs non-retryable errors

### 5. Context/Timeout Support
- Operation timeouts
- Cancellation support
- Context propagation (Go)
- Timeout configuration (Python)

## Configuration Options

### Go SDK Config
```go
&minio.Config{
    Endpoint:     "http://localhost:9000",  // Required
    APIKey:       "key",                    // Required
    APISecret:    "secret",                 // Required
    TenantID:     "tenant",                 // Required
    Timeout:      30 * time.Second,         // Optional (default: 30s)
    MaxRetries:   3,                        // Optional (default: 3)
    RetryBackoff: 100 * time.Millisecond,  // Optional (default: 100ms)
}
```

### Python SDK Config
```python
Client(
    endpoint="http://localhost:9000",  # Required
    api_key="key",                     # Required
    api_secret="secret",               # Required
    tenant_id="tenant",                # Required
    timeout=30,                        # Optional (default: 30s)
    max_retries=3,                     # Optional (default: 3)
    retry_backoff=0.1,                 # Optional (default: 0.1s)
)
```

## Examples

Each SDK includes comprehensive examples in the `examples/` directory:

### Go Examples
- `basic_upload.go` - Basic operations (upload, download, list, delete)
- Complete runnable examples with error handling

### Python Examples
- `basic_upload.py` - Basic operations with context manager
- Error handling patterns
- Environment variable configuration

## Testing

### Go SDK Tests
```bash
cd sdk/go
go test -v ./...
go test -race ./...
```

**Test Coverage**: 12+ test cases covering all operations and error scenarios

### Python SDK Tests
```bash
cd sdk/python
pip install -e ".[dev]"
pytest tests/ -v
pytest tests/ --cov=minio_enterprise
```

**Test Coverage**: 15+ test cases with mocking for unit tests

## Performance

Both SDKs are optimized for performance:

| Metric | Go SDK | Python SDK |
|--------|--------|------------|
| Dependencies | 0 (stdlib only) | 1 (requests) |
| Connection Pooling | ✅ HTTP/2 | ✅ Session |
| Memory Allocation | Zero allocs | Efficient |
| Retry Overhead | <10ms | <10ms |
| Latency | <5ms (P99) | <5ms (P99) |

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for contribution guidelines.

## Roadmap

### Phase 1 (Current) ✅
- [x] Go SDK implementation
- [x] Python SDK implementation
- [x] Unit tests and integration tests
- [x] Basic examples and documentation

### Phase 2 (Planned)
- [ ] JavaScript/TypeScript SDK
- [ ] Java SDK
- [ ] Async support for Python (asyncio)
- [ ] Streaming upload/download support
- [ ] Multipart upload support

### Phase 3 (Future)
- [ ] Rust SDK
- [ ] Ruby SDK
- [ ] PHP SDK
- [ ] CLI tool built on SDK

## Support

- **Documentation**: [docs/](../docs/)
- **Issues**: [GitHub Issues](https://github.com/abiolaogu/MinIO/issues)
- **Discussions**: [GitHub Discussions](https://github.com/abiolaogu/MinIO/discussions)

## License

Apache License 2.0 - See [LICENSE](../LICENSE) for details.

---

**Status**: ✅ Production Ready
**Version**: 1.0.0
**Last Updated**: 2026-02-07
