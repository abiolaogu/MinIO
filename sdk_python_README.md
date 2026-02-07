# MinIO Enterprise Python SDK

Official Python SDK for MinIO Enterprise - Ultra-high-performance object storage with 10-100x performance improvements.

## Features

- **Complete API Coverage**: Upload, Download, Delete, List operations
- **Authentication**: Tenant-based authentication with X-Tenant-ID header
- **Automatic Retry Logic**: Exponential backoff with configurable retries
- **Connection Pooling**: Persistent connections for optimal performance
- **Type Hints**: Full type annotations for better IDE support
- **Context Manager Support**: Automatic resource cleanup with `with` statement
- **Production Ready**: Comprehensive error handling and examples

## Installation

```bash
# Install from PyPI (once published)
pip install minio-enterprise-sdk

# Or install from repository
pip install git+https://github.com/abiolaogu/MinIO.git#subdirectory=sdk/python
```

### Requirements

- Python 3.7+
- requests >= 2.28.0

Install dependencies:

```bash
pip install requests
```

## Quick Start

```python
from minio_sdk import MinIOClient, Config

# Create client configuration
config = Config(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000"
)

# Create client
client = MinIOClient(config)

# Upload an object
resp = client.upload("my-file.txt", b"Hello, MinIO Enterprise!")
print(f"Uploaded: {resp.key} ({resp.size} bytes)")

# Download the object
data = client.download("my-file.txt")
print(f"Downloaded: {data.decode()}")

# List objects
keys = client.list()
print(f"Found {len(keys)} objects")

# Delete the object
client.delete("my-file.txt")
print("Deleted successfully")

# Clean up
client.close()
```

## API Reference

### Configuration

```python
from minio_sdk import Config

config = Config(
    base_url="http://localhost:9000",      # MinIO server URL (required)
    tenant_id="tenant-uuid",                # Tenant identifier (required)
    timeout=30,                              # Request timeout in seconds (default: 30)
    max_retries=3,                           # Max retry attempts (default: 3)
    base_delay=1.0                           # Base delay for backoff (default: 1.0)
)
```

### Create Client

```python
from minio_sdk import MinIOClient, Config

client = MinIOClient(config)
```

Or use the convenience function:

```python
from minio_sdk import create_client

client = create_client(
    base_url="http://localhost:9000",
    tenant_id="tenant-uuid",
    timeout=60,
    max_retries=5
)
```

### Upload Object

```python
response = client.upload(key, data)
```

Uploads an object to MinIO storage.

**Parameters**:
- `key` (str): Unique object key identifier
- `data` (bytes): Object data as bytes

**Returns**:
- `UploadResponse`: Response with status, key, and size

**Raises**:
- `MinIOError`: If upload fails after retries

**Performance**: Up to 500K writes/sec

### Download Object

```python
data = client.download(key)
```

Downloads an object from MinIO storage with multi-tier caching.

**Parameters**:
- `key` (str): Unique object key identifier

**Returns**:
- `bytes`: Object data

**Raises**:
- `MinIOError`: If download fails after retries

**Performance**: Up to 2M reads/sec with 95%+ cache hit ratio

### Delete Object

```python
client.delete(key)
```

Deletes an object from MinIO storage.

**Parameters**:
- `key` (str): Unique object key identifier

**Raises**:
- `MinIOError`: If deletion fails after retries

### List Objects

```python
keys = client.list(prefix="")
```

Lists objects in MinIO storage with optional prefix filtering.

**Parameters**:
- `prefix` (str, optional): Prefix to filter objects (default: "")

**Returns**:
- `List[str]`: List of object keys

**Raises**:
- `MinIOError`: If listing fails after retries

### Get Server Info

```python
info = client.get_server_info()
```

Retrieves server information.

**Returns**:
- `ServerInfo`: Server information (status, version, performance)

**Raises**:
- `MinIOError`: If request fails after retries

### Health Check

```python
healthy = client.health_check()
```

Performs a health check on the MinIO server.

**Returns**:
- `bool`: True if server is healthy

**Raises**:
- `MinIOError`: If health check request fails

## Examples

### Example 1: Basic Upload and Download

```python
from minio_sdk import create_client

# Create client
client = create_client(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000"
)

try:
    # Upload
    data = b"Hello, World!"
    resp = client.upload("hello.txt", data)
    print(f"Uploaded: {resp.key} ({resp.size} bytes)")

    # Download
    downloaded = client.download("hello.txt")
    print(f"Content: {downloaded.decode()}")

finally:
    client.close()
```

### Example 2: Context Manager (Recommended)

```python
from minio_sdk import MinIOClient, Config

config = Config(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000"
)

# Use context manager for automatic cleanup
with MinIOClient(config) as client:
    # Upload
    resp = client.upload("test.txt", b"Test data")
    print(f"Uploaded: {resp.key}")

    # Download
    data = client.download("test.txt")
    print(f"Downloaded: {data.decode()}")

# Client automatically closed
```

### Example 3: Bulk Upload with Error Handling

```python
from minio_sdk import create_client, MinIOError

client = create_client(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000"
)

files = {
    "file1.txt": b"Content 1",
    "file2.txt": b"Content 2",
    "file3.txt": b"Content 3",
}

try:
    for key, data in files.items():
        try:
            resp = client.upload(key, data)
            print(f"✓ Uploaded: {resp.key} ({resp.size} bytes)")
        except MinIOError as e:
            print(f"✗ Failed to upload {key}: {e}")

finally:
    client.close()
```

### Example 4: List and Download with Prefix Filter

```python
from minio_sdk import create_client

client = create_client(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000"
)

try:
    # List objects with prefix
    keys = client.list(prefix="uploads/")
    print(f"Found {len(keys)} objects with prefix 'uploads/'")

    # Download each object
    for key in keys:
        try:
            data = client.download(key)
            print(f"✓ Downloaded {key}: {len(data)} bytes")
        except MinIOError as e:
            print(f"✗ Failed to download {key}: {e}")

finally:
    client.close()
```

### Example 5: Custom Configuration with Retries

```python
from minio_sdk import MinIOClient, Config

config = Config(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000",
    timeout=60,        # 60 second timeout
    max_retries=5,     # 5 retry attempts
    base_delay=2.0     # 2 second base delay
)

with MinIOClient(config) as client:
    # Operations will use custom retry settings
    resp = client.upload("test.txt", b"Test data")
    print(f"Uploaded with custom config: {resp.key}")
```

### Example 6: Health Check and Server Info

```python
from minio_sdk import create_client

client = create_client(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000"
)

try:
    # Health check
    if client.health_check():
        print("✓ Server is healthy")
    else:
        print("✗ Server is not healthy")

    # Get server info
    info = client.get_server_info()
    print(f"\nServer Info:")
    print(f"  Status: {info.status}")
    print(f"  Version: {info.version}")
    print(f"  Performance: {info.performance}")

finally:
    client.close()
```

### Example 7: Working with Binary Files

```python
from minio_sdk import create_client

client = create_client(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000"
)

try:
    # Read a local file
    with open("image.jpg", "rb") as f:
        image_data = f.read()

    # Upload to MinIO
    resp = client.upload("images/photo.jpg", image_data)
    print(f"Uploaded image: {resp.size} bytes")

    # Download from MinIO
    downloaded = client.download("images/photo.jpg")

    # Save to local file
    with open("downloaded_image.jpg", "wb") as f:
        f.write(downloaded)
    print("Downloaded and saved image")

finally:
    client.close()
```

### Example 8: Batch Operations

```python
from minio_sdk import create_client
from concurrent.futures import ThreadPoolExecutor, as_completed

client = create_client(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000"
)

# Files to upload
files = {f"file{i}.txt": f"Content {i}".encode() for i in range(100)}

try:
    # Upload files concurrently
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = {
            executor.submit(client.upload, key, data): key
            for key, data in files.items()
        }

        for future in as_completed(futures):
            key = futures[future]
            try:
                resp = future.result()
                print(f"✓ Uploaded: {resp.key}")
            except Exception as e:
                print(f"✗ Failed to upload {key}: {e}")

finally:
    client.close()
```

## Error Handling

The SDK provides comprehensive error handling:

```python
from minio_sdk import create_client, MinIOError

client = create_client(
    base_url="http://localhost:9000",
    tenant_id="tenant-id"
)

try:
    resp = client.upload("test.txt", b"Test data")
except MinIOError as e:
    print(f"Upload failed: {e}")
except ValueError as e:
    print(f"Invalid configuration: {e}")
finally:
    client.close()
```

## Retry Logic

The SDK automatically retries failed requests with exponential backoff:

- **Default Max Retries**: 3 attempts
- **Default Base Delay**: 1 second
- **Backoff Strategy**: Exponential (1s, 2s, 4s, 8s, ...)

Configure retry behavior:

```python
config = Config(
    base_url="http://localhost:9000",
    tenant_id="tenant-id",
    max_retries=5,      # Custom retry count
    base_delay=2.0      # Custom base delay
)
```

## Connection Pooling

The SDK uses connection pooling for optimal performance:

- **Pool Connections**: 100
- **Pool Max Size**: 100
- **Persistent Connections**: Enabled by default

## Performance Tips

1. **Use Context Manager**: Automatically handles cleanup
2. **Reuse Client**: Create one client and reuse across operations
3. **Concurrent Operations**: Use ThreadPoolExecutor for batch operations
4. **Configure Timeouts**: Set appropriate timeouts based on workload
5. **Monitor Errors**: Implement proper error handling and logging

## Best Practices

1. **Always use context managers**: Use `with` statement for automatic cleanup
2. **Handle errors properly**: Catch `MinIOError` and log appropriately
3. **Set reasonable timeouts**: Configure timeouts based on expected duration
4. **Validate inputs**: Check keys and data before making requests
5. **Use type hints**: Leverage type annotations for better IDE support

## Thread Safety

The `MinIOClient` uses a `requests.Session` which is thread-safe for making requests, but not for modifying session attributes. For concurrent operations, either:

1. Create separate client instances per thread
2. Use a connection pool with thread-local storage

## Type Hints

The SDK provides full type annotations:

```python
from typing import List
from minio_sdk import MinIOClient, Config, UploadResponse, ServerInfo

def process_files(client: MinIOClient, keys: List[str]) -> None:
    for key in keys:
        data: bytes = client.download(key)
        # Process data...
```

## License

Apache License 2.0 - See [LICENSE](../LICENSE) file for details.

## Support

- **Documentation**: [MinIO Enterprise Docs](../docs/)
- **API Reference**: [OpenAPI Specification](../docs/api/openapi.yaml)
- **Issues**: [GitHub Issues](https://github.com/abiolaogu/MinIO/issues)
- **Discussions**: [GitHub Discussions](https://github.com/abiolaogu/MinIO/discussions)

## Version

**SDK Version**: 1.0.0
**API Version**: 3.0.0
**Python Version**: 3.7+
