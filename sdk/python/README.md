# MinIO Enterprise Python SDK

Official Python SDK for [MinIO Enterprise](https://github.com/abiolaogu/MinIO) - Ultra-high-performance object storage with 10-100x performance improvements.

## Features

- **Simple API**: Intuitive methods for upload, download, delete operations
- **Automatic Retries**: Exponential backoff retry logic for transient failures
- **Connection Pooling**: HTTP connection pooling and keep-alive
- **Streaming Support**: Efficient streaming for large files
- **Type Hints**: Full type annotations for better IDE support
- **Context Manager**: Proper resource management with context managers
- **Exception Handling**: Structured exceptions with detailed error information
- **Production Ready**: Battle-tested with comprehensive examples

## Installation

### From PyPI (when published)

```bash
pip install minio-enterprise
```

### From Source

```bash
cd sdk/python
pip install -e .
```

### Development Installation

```bash
cd sdk/python
pip install -e ".[dev]"
```

## Quick Start

```python
from minio_enterprise import Client

# Create a new client
client = Client(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000"
)

# Upload an object
response = client.upload("hello.txt", b"Hello, MinIO Enterprise!")
print(f"Uploaded: {response['key']} ({response['size']} bytes)")

# Download the object
data = client.download("hello.txt")
print(f"Downloaded: {data.decode('utf-8')}")

# Delete the object
client.delete("hello.txt")
print("Object deleted successfully")
```

## Configuration

### Basic Configuration

```python
from minio_enterprise import Client

client = Client(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000"
)
```

### Advanced Configuration

```python
import requests
from minio_enterprise import Client

# Create custom session with connection pooling
session = requests.Session()
adapter = requests.adapters.HTTPAdapter(
    pool_connections=20,
    pool_maxsize=20,
    max_retries=0
)
session.mount('http://', adapter)
session.mount('https://', adapter)

client = Client(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000",
    timeout=60,           # Request timeout in seconds
    retry_max=5,          # Maximum retry attempts
    retry_delay=2.0,      # Initial retry delay in seconds
    session=session       # Custom requests session
)
```

### Configuration Options

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `base_url` | `str` | Yes | - | MinIO server base URL (e.g., "http://localhost:9000") |
| `tenant_id` | `str` | Yes | - | Tenant identifier for multi-tenancy |
| `timeout` | `int` | No | 30 | Request timeout in seconds |
| `retry_max` | `int` | No | 3 | Maximum number of retry attempts |
| `retry_delay` | `float` | No | 1.0 | Initial delay between retries (uses exponential backoff) |
| `session` | `requests.Session` | No | None | Custom requests session for advanced configuration |

## API Reference

### Upload

Upload an object to MinIO storage.

```python
def upload(key: str, data: Union[bytes, BinaryIO]) -> Dict
```

**Parameters:**
- `key` (str): Unique object key identifier (1-1024 characters)
- `data` (bytes or BinaryIO): Object data as bytes or file-like object

**Returns:**
- `Dict`: Contains status, key, and size

**Raises:**
- `ConfigurationError`: If key is invalid
- `QuotaExceededError`: If tenant quota is exceeded
- `APIError`: If upload fails
- `NetworkError`: If network communication fails

**Example:**

```python
# Upload from bytes
response = client.upload("hello.txt", b"Hello, World!")
print(f"Uploaded: {response['key']} ({response['size']} bytes)")

# Upload from file
with open("document.pdf", "rb") as f:
    response = client.upload("document.pdf", f)
    print(f"Uploaded: {response['key']}")
```

### Download

Download an object from MinIO storage.

```python
def download(key: str) -> bytes
```

**Parameters:**
- `key` (str): Unique object key identifier

**Returns:**
- `bytes`: Object data

**Raises:**
- `ConfigurationError`: If key is invalid
- `ObjectNotFoundError`: If object does not exist
- `APIError`: If download fails
- `NetworkError`: If network communication fails

**Example:**

```python
# Download to bytes
data = client.download("hello.txt")
print(data.decode('utf-8'))

# Download to file
data = client.download("document.pdf")
with open("downloaded.pdf", "wb") as f:
    f.write(data)
```

### Download Stream

Download an object as a stream (recommended for large files).

```python
def download_stream(key: str) -> requests.Response
```

**Parameters:**
- `key` (str): Unique object key identifier

**Returns:**
- `requests.Response`: Response object with streaming enabled

**Example:**

```python
# Stream to file
response = client.download_stream("large-file.bin")
with open("large-file.bin", "wb") as f:
    for chunk in response.iter_content(chunk_size=8192):
        if chunk:
            f.write(chunk)
```

### Delete

Delete an object from MinIO storage.

```python
def delete(key: str) -> None
```

**Parameters:**
- `key` (str): Unique object key identifier

**Raises:**
- `ConfigurationError`: If key is invalid
- `APIError`: If delete fails
- `NetworkError`: If network communication fails

**Example:**

```python
client.delete("hello.txt")
print("Object deleted")
```

### Get Server Info

Get server version and status information.

```python
def get_server_info() -> Dict
```

**Returns:**
- `Dict`: Contains status, version, and performance info

**Example:**

```python
info = client.get_server_info()
print(f"Server: {info['status']}")
print(f"Version: {info['version']}")
print(f"Performance: {info['performance']}")
```

### Health Check

Check if the server is healthy and ready.

```python
def health_check() -> bool
```

**Returns:**
- `bool`: True if server is healthy, False otherwise

**Example:**

```python
if client.health_check():
    print("Server is healthy")
else:
    print("Server is unhealthy")
```

## Error Handling

The SDK provides structured exception handling:

```python
from minio_enterprise import (
    Client,
    APIError,
    QuotaExceededError,
    ObjectNotFoundError,
    NetworkError,
    ConfigurationError
)

client = Client(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000"
)

try:
    response = client.upload("key", b"data")
except QuotaExceededError as e:
    print(f"Quota exceeded: {e}")
except ObjectNotFoundError as e:
    print(f"Object not found: {e.key}")
except APIError as e:
    print(f"API error (status {e.status_code}): {e}")
except NetworkError as e:
    print(f"Network error: {e}")
except ConfigurationError as e:
    print(f"Configuration error: {e}")
```

### Exception Hierarchy

```
MinIOError
├── ConfigurationError
├── NetworkError
└── APIError
    ├── QuotaExceededError
    └── ObjectNotFoundError
```

## Advanced Usage

### Context Manager

Use the client as a context manager for automatic resource cleanup:

```python
with Client(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000"
) as client:
    response = client.upload("key", b"data")
    print(f"Uploaded: {response['key']}")
# Session is automatically closed
```

### Large File Upload

```python
# Upload large file with streaming
with open("large-file.bin", "rb") as f:
    response = client.upload("large-file.bin", f)
    print(f"Uploaded {response['size']} bytes")
```

### Large File Download

```python
# Download large file with streaming
response = client.download_stream("large-file.bin")
with open("downloaded.bin", "wb") as f:
    for chunk in response.iter_content(chunk_size=1024*1024):  # 1MB chunks
        if chunk:
            f.write(chunk)
```

### Concurrent Operations

```python
import concurrent.futures

def upload_file(key, data):
    with Client(
        base_url="http://localhost:9000",
        tenant_id="550e8400-e29b-41d4-a716-446655440000"
    ) as client:
        return client.upload(key, data)

files = {
    "file1.txt": b"content1",
    "file2.txt": b"content2",
    "file3.txt": b"content3"
}

with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
    futures = [
        executor.submit(upload_file, key, data)
        for key, data in files.items()
    ]

    for future in concurrent.futures.as_completed(futures):
        result = future.result()
        print(f"Uploaded: {result['key']}")
```

### Custom Session Configuration

```python
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# Create session with custom retry configuration
session = requests.Session()

# Configure connection pooling
adapter = HTTPAdapter(
    pool_connections=50,
    pool_maxsize=50
)

session.mount('http://', adapter)
session.mount('https://', adapter)

# Create client with custom session
client = Client(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000",
    session=session
)
```

## Performance Optimization

### Connection Pooling

For optimal performance with many requests:

```python
import requests

session = requests.Session()
adapter = requests.adapters.HTTPAdapter(
    pool_connections=100,     # Total connection pools
    pool_maxsize=100         # Connections per pool
)
session.mount('http://', adapter)
session.mount('https://', adapter)

client = Client(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000",
    session=session
)
```

### Retry Strategy

The SDK uses exponential backoff for retries:

- **Attempt 1**: Immediate
- **Attempt 2**: Wait 1s (retry_delay × 2^0)
- **Attempt 3**: Wait 2s (retry_delay × 2^1)
- **Attempt 4**: Wait 4s (retry_delay × 2^2)

Customize retry behavior:

```python
client = Client(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000",
    retry_max=5,          # 5 retry attempts
    retry_delay=0.5       # Start with 500ms
)
```

## Testing

Run the test suite:

```bash
cd sdk/python
pytest tests/ -v
```

Run with coverage:

```bash
pytest tests/ -v --cov=minio_enterprise --cov-report=html
```

## Best Practices

1. **Use context managers**: Always use `with` statement for automatic cleanup
2. **Handle exceptions**: Catch and handle specific exceptions appropriately
3. **Reuse clients**: Create one client and reuse it for all operations
4. **Stream large files**: Use `download_stream()` for large files
5. **Connection pooling**: Configure session for your workload
6. **Set timeouts**: Always set appropriate timeouts for your use case
7. **Monitor retries**: Log retry attempts for debugging

## Performance Metrics

MinIO Enterprise delivers exceptional performance:

| Operation | Throughput | Latency (P99) |
|-----------|------------|---------------|
| Cache Write | 500K ops/sec | <2ms |
| Cache Read | 2M ops/sec | <1ms |
| Upload | Limited by network | <50ms |
| Download | Limited by network | <50ms (cache hit) |

## Troubleshooting

### Connection Refused

```
NetworkError: Network error: Connection refused
```

**Solution**: Ensure MinIO server is running and accessible at the configured base_url.

### Quota Exceeded

```
QuotaExceededError: Quota exceeded
```

**Solution**: Increase tenant quota or delete unused objects.

### Timeout

```
NetworkError: Network error: Read timed out
```

**Solution**: Increase timeout or check network connectivity.

### SSL Certificate Errors

For HTTPS endpoints with self-signed certificates:

```python
import requests

session = requests.Session()
session.verify = False  # Only for testing!

client = Client(
    base_url="https://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000",
    session=session
)
```

## Type Checking

The SDK includes full type hints for mypy:

```bash
mypy your_code.py
```

## Code Formatting

Format code with black:

```bash
black minio_enterprise/
```

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines.

## License

Apache License 2.0 - See [LICENSE](../../LICENSE) file for details.

## Support

- **Documentation**: [MinIO Enterprise Docs](https://github.com/abiolaogu/MinIO)
- **Issues**: [GitHub Issues](https://github.com/abiolaogu/MinIO/issues)
- **API Reference**: [OpenAPI Specification](../../docs/api/openapi.yaml)

## Related Resources

- [MinIO Enterprise Performance Guide](../../docs/guides/PERFORMANCE.md)
- [MinIO Enterprise Deployment Guide](../../docs/guides/DEPLOYMENT.md)
- [Go SDK](../go/README.md)
- [API Documentation](../../docs/api/)

## Examples

### Complete Example

```python
from minio_enterprise import Client, QuotaExceededError, ObjectNotFoundError

def main():
    # Create client
    with Client(
        base_url="http://localhost:9000",
        tenant_id="550e8400-e29b-41d4-a716-446655440000",
        timeout=30,
        retry_max=3
    ) as client:
        # Check server health
        if not client.health_check():
            print("Server is unhealthy!")
            return

        # Get server info
        info = client.get_server_info()
        print(f"Connected to {info['version']}")

        try:
            # Upload an object
            response = client.upload("example.txt", b"Hello, World!")
            print(f"Uploaded: {response['key']} ({response['size']} bytes)")

            # Download the object
            data = client.download("example.txt")
            print(f"Downloaded: {data.decode('utf-8')}")

            # Delete the object
            client.delete("example.txt")
            print("Deleted successfully")

        except QuotaExceededError:
            print("Quota exceeded! Please free up space.")
        except ObjectNotFoundError as e:
            print(f"Object not found: {e.key}")
        except Exception as e:
            print(f"Error: {e}")

if __name__ == "__main__":
    main()
```

---

**Generated with [Claude Code](https://claude.ai/code)**
