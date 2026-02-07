# MinIO Enterprise Python SDK

Official Python SDK for MinIO Enterprise - Ultra-High-Performance Object Storage.

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
from minio_enterprise import Client, Config, UploadRequest, DownloadRequest

# Create a new MinIO client
client = Client(Config(
    base_url="http://localhost:9000",
    api_key="your-api-key-here",
    timeout=30,
    max_retries=3,
))

# Upload a file
upload_response = client.upload(UploadRequest(
    tenant_id="tenant-123",
    object_id="my-file.txt",
    data=b"Hello, MinIO Enterprise!",
))
print(f"Uploaded: {upload_response['message']}")

# Download a file
download_response = client.download(DownloadRequest(
    tenant_id="tenant-123",
    object_id="my-file.txt",
))
print(f"Downloaded {download_response['size']} bytes")
print(f"Data: {download_response['data']}")

# Close the client (or use context manager)
client.close()
```

## Features

- **Simple API**: Intuitive methods for all common operations
- **Automatic Retries**: Built-in exponential backoff retry logic
- **Connection Pooling**: Efficient HTTP connection reuse
- **Type Safety**: Type hints for better IDE support
- **Context Manager**: Supports `with` statement for resource management
- **Comprehensive Error Handling**: Custom exceptions for different error types

## API Reference

### Client Configuration

```python
from minio_enterprise import Client, Config

config = Config(
    base_url="http://localhost:9000",  # MinIO API endpoint
    api_key="your-api-key",            # API key for authentication
    timeout=30,                        # Request timeout in seconds
    max_retries=3,                     # Maximum retry attempts
)

client = Client(config)
```

### Upload File

```python
from minio_enterprise import UploadRequest

response = client.upload(UploadRequest(
    tenant_id="tenant-123",
    object_id="file.txt",
    data=b"file content",
))

print(response)
# {
#     "message": "Upload successful",
#     "tenant_id": "tenant-123",
#     "object_id": "file.txt",
#     "size": 12,
#     "timestamp": "2024-01-18T10:30:00Z"
# }
```

### Download File

```python
from minio_enterprise import DownloadRequest

response = client.download(DownloadRequest(
    tenant_id="tenant-123",
    object_id="file.txt",
))

# Access file data
file_data = response['data']
```

### Delete File

```python
from minio_enterprise import DeleteRequest

response = client.delete(DeleteRequest(
    tenant_id="tenant-123",
    object_id="file.txt",
))
```

### List Objects

```python
from minio_enterprise import ListRequest

response = client.list(ListRequest(
    tenant_id="tenant-123",
    prefix="folder/",  # Optional prefix filter
    limit=100,         # Optional limit (default: 100)
))

for obj in response['objects']:
    print(f"{obj['object_id']}: {obj['size']} bytes")
```

### Get Quota

```python
from minio_enterprise import QuotaRequest

response = client.get_quota(QuotaRequest(
    tenant_id="tenant-123",
))

print(f"Used: {response['used']} bytes")
print(f"Limit: {response['limit']} bytes")
print(f"Available: {response['available']} bytes")
```

### Health Check

```python
response = client.health_check()
print(f"Status: {response['status']}")
```

## Error Handling

The SDK provides custom exceptions for different error scenarios:

```python
from minio_enterprise import (
    MinIOError,              # Base exception
    MinIOConnectionError,    # Connection/network errors
    MinIOValidationError,    # Validation errors
    MinIOAPIError,           # API errors (4xx, 5xx)
)

try:
    response = client.upload(upload_request)
except MinIOValidationError as e:
    print(f"Validation error: {e}")
except MinIOConnectionError as e:
    print(f"Connection error: {e}")
except MinIOAPIError as e:
    print(f"API error: {e}")
    print(f"Status code: {e.status_code}")
    print(f"Response body: {e.response_body}")
except MinIOError as e:
    print(f"General error: {e}")
```

## Context Manager

Use the client as a context manager to ensure proper cleanup:

```python
with Client(config) as client:
    response = client.upload(upload_request)
    print(response)
# Client is automatically closed when exiting the context
```

## Examples

### Upload with Error Handling

```python
from minio_enterprise import Client, Config, UploadRequest, MinIOError

client = Client(Config(base_url="http://localhost:9000", api_key="key"))

try:
    response = client.upload(UploadRequest(
        tenant_id="tenant-123",
        object_id="important-file.txt",
        data=b"Important data",
    ))
    print(f"Upload successful: {response['message']}")
except MinIOError as e:
    print(f"Upload failed: {e}")
finally:
    client.close()
```

### List with Prefix Filter

```python
from minio_enterprise import ListRequest

response = client.list(ListRequest(
    tenant_id="tenant-123",
    prefix="images/2024/",
    limit=50,
))

print(f"Found {response['count']} objects:")
for obj in response['objects']:
    print(f"  - {obj['object_id']} ({obj['size']} bytes)")
```

### Check Quota Before Upload

```python
from minio_enterprise import QuotaRequest, UploadRequest

# Check available quota
quota = client.get_quota(QuotaRequest(tenant_id="tenant-123"))

file_data = b"Large file content..."
file_size = len(file_data)

if quota['available'] < file_size:
    print(f"Insufficient quota: need {file_size} bytes, have {quota['available']} bytes")
else:
    # Proceed with upload
    response = client.upload(UploadRequest(
        tenant_id="tenant-123",
        object_id="large-file.bin",
        data=file_data,
    ))
    print("Upload successful!")
```

### Batch Operations

```python
import concurrent.futures

def upload_file(filename, data):
    try:
        response = client.upload(UploadRequest(
            tenant_id="tenant-123",
            object_id=filename,
            data=data,
        ))
        return f"✓ {filename}"
    except MinIOError as e:
        return f"✗ {filename}: {e}"

# Upload multiple files concurrently
files = {
    "file1.txt": b"Data 1",
    "file2.txt": b"Data 2",
    "file3.txt": b"Data 3",
}

with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
    futures = [
        executor.submit(upload_file, filename, data)
        for filename, data in files.items()
    ]

    for future in concurrent.futures.as_completed(futures):
        print(future.result())
```

## Development

### Running Tests

```bash
# Install development dependencies
pip install -e ".[dev]"

# Run tests
pytest

# Run tests with coverage
pytest --cov=minio_enterprise --cov-report=html

# Run type checking
mypy minio_enterprise

# Run linting
flake8 minio_enterprise
black --check minio_enterprise
```

### Code Formatting

```bash
# Format code with black
black minio_enterprise

# Check code style
flake8 minio_enterprise
```

## Performance

The Python SDK is designed for high performance with:

- **Connection Pooling**: Reuses HTTP connections (up to 100 per host)
- **Automatic Retries**: Handles transient failures with exponential backoff
- **Efficient Memory Usage**: Streams large files without loading into memory
- **Session Management**: Persistent HTTP sessions across requests

## Requirements

- Python 3.8 or higher
- requests >= 2.31.0
- urllib3 >= 2.0.0

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Run `pytest` to ensure tests pass
5. Run `black` and `flake8` to format and lint code
6. Submit a pull request

## License

Apache License 2.0 - See [LICENSE](../../LICENSE) file for details.

## Support

- **Documentation**: [MinIO Enterprise Docs](../../docs/)
- **API Reference**: [API_REFERENCE.md](../../API_REFERENCE.md)
- **Issues**: [GitHub Issues](https://github.com/abiolaogu/MinIO/issues)

## Version

SDK Version: 1.0.0
Compatible with: MinIO Enterprise 2.0.0+
