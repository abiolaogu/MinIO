# MinIO Enterprise Python SDK

Official Python SDK for MinIO Enterprise - Ultra-High-Performance Object Storage

## Installation

```bash
pip install minio-enterprise
```

Or install from source:

```bash
cd sdk/python
pip install -e .
```

## Quick Start

```python
from minio_enterprise import Client

# Initialize client
client = Client(
    endpoint="http://localhost:9000",
    api_key="your-api-key",
    api_secret="your-api-secret",
    tenant_id="your-tenant-id"
)

# Upload an object
client.upload(
    bucket="my-bucket",
    key="my-object.txt",
    data=b"Hello, World!"
)

print("Upload successful!")
```

## Features

- **Simple API**: Pythonic interface for common operations
- **Auto-Retry**: Automatic retry with exponential backoff
- **Connection Pooling**: Efficient connection reuse with requests.Session
- **Type Hints**: Full type annotations for better IDE support
- **Context Manager**: Proper resource cleanup with `with` statement
- **Async Support**: Async methods for concurrent operations (optional)

## API Coverage

- `upload(bucket, key, data)` - Upload object
- `download(bucket, key)` - Download object
- `delete(bucket, key)` - Delete object
- `list(bucket, prefix=None)` - List objects
- `get_quota()` - Get tenant quota information
- `health()` - Check service health

## Documentation

See [API Reference](./docs/API.md) for detailed documentation.

## Examples

See [examples/](./examples/) directory for complete examples:
- `basic_upload.py` - Simple upload example
- `batch_operations.py` - Batch upload/download
- `error_handling.py` - Error handling patterns
- `async_operations.py` - Async operations example

## Usage Examples

### Basic Operations

```python
from minio_enterprise import Client

client = Client(
    endpoint="http://localhost:9000",
    api_key="your-api-key",
    api_secret="your-api-secret",
    tenant_id="your-tenant-id"
)

# Upload
client.upload("my-bucket", "file.txt", b"content")

# Download
data = client.download("my-bucket", "file.txt")

# List
objects = client.list("my-bucket", prefix="folder/")

# Delete
client.delete("my-bucket", "file.txt")

# Check quota
quota = client.get_quota()
print(f"Used: {quota['used']} / {quota['limit']} bytes")
```

### Context Manager

```python
from minio_enterprise import Client

with Client(endpoint="http://localhost:9000", ...) as client:
    client.upload("my-bucket", "file.txt", b"content")
    # Client automatically closed when exiting context
```

### Error Handling

```python
from minio_enterprise import Client, MinIOError, QuotaExceededError

try:
    client.upload("my-bucket", "file.txt", b"content")
except QuotaExceededError as e:
    print(f"Quota exceeded: {e}")
except MinIOError as e:
    print(f"MinIO error: {e}")
```

## Contributing

Please see [CONTRIBUTING.md](../../CONTRIBUTING.md) for contribution guidelines.

## License

Apache License 2.0 - See [LICENSE](../../LICENSE) for details.
