# MinIO Enterprise Python SDK

Official Python SDK for MinIO Enterprise - Ultra-High-Performance Object Storage

## Features

- **Full API Coverage**: Upload, Download, Delete, List, Quota Management, Health Checks
- **Authentication**: Support for API keys and JWT tokens
- **Automatic Retry Logic**: Built-in retry with exponential backoff
- **Connection Pooling**: Efficient HTTP connection reuse
- **Type Hints**: Full type annotations for better IDE support
- **Context Manager Support**: Automatic resource cleanup
- **Comprehensive Testing**: Unit tests with high coverage
- **Pythonic API**: Clean, idiomatic Python interface

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
from minio_enterprise import MinIOClient

# Create client
client = MinIOClient(
    endpoint="http://localhost:9000",
    api_key="your-api-key",
)

# Upload a file
with open("document.pdf", "rb") as f:
    response = client.upload(
        tenant_id="my-tenant",
        key="documents/report.pdf",
        data=f,
        content_type="application/pdf",
    )
    print(f"Uploaded: {response['key']} (ETag: {response['etag']})")

# Download a file
stream = client.download(
    tenant_id="my-tenant",
    key="documents/report.pdf",
)
with open("downloaded.pdf", "wb") as f:
    f.write(stream.read())

# List objects
result = client.list(
    tenant_id="my-tenant",
    prefix="documents/",
)
for obj in result["objects"]:
    print(f"{obj['key']} - {obj['size']} bytes")

# Clean up
client.close()
```

## Configuration

### Basic Configuration

```python
from minio_enterprise import MinIOClient

client = MinIOClient(
    endpoint="http://localhost:9000",
    api_key="your-api-key",
)
```

### Advanced Configuration

```python
client = MinIOClient(
    endpoint="https://minio.example.com",
    token="jwt-token",                    # Use JWT instead of API key
    timeout=60,                            # Request timeout in seconds
    retry_max=5,                           # Maximum retry attempts
    retry_backoff=2.0,                     # Backoff factor for retries
    verify_ssl=True,                       # Verify SSL certificates
)
```

### Using Context Manager

```python
with MinIOClient(endpoint="http://localhost:9000", api_key="key") as client:
    # Automatically closes connection when done
    result = client.health()
```

## API Reference

### Upload

Upload an object to MinIO:

```python
response = client.upload(
    tenant_id="my-tenant",
    key="documents/report.pdf",
    data=file_object,                      # File-like object
    size=1024,                             # Optional: size in bytes
    content_type="application/pdf",        # Optional
    metadata={                             # Optional
        "author": "John Doe",
        "department": "Engineering",
    },
)

print(response)
# {
#     'key': 'documents/report.pdf',
#     'etag': 'abc123...',
#     'size': 1024
# }
```

### Download

Download an object from MinIO:

```python
stream = client.download(
    tenant_id="my-tenant",
    key="documents/report.pdf",
)

# Save to file
with open("local_file.pdf", "wb") as f:
    f.write(stream.read())

# Or read in chunks
for chunk in iter(lambda: stream.read(8192), b""):
    process_chunk(chunk)
```

### Delete

Delete an object:

```python
client.delete(
    tenant_id="my-tenant",
    key="documents/old-report.pdf",
)
```

### List

List objects with optional filtering:

```python
result = client.list(
    tenant_id="my-tenant",
    prefix="documents/",                   # Optional: filter by prefix
    limit=100,                             # Optional: max results
    marker="",                             # Optional: pagination marker
)

print(result)
# {
#     'objects': [
#         {'key': 'file1.txt', 'size': 100, ...},
#         {'key': 'file2.txt', 'size': 200, ...},
#     ],
#     'is_truncated': False,
#     'next_marker': ''
# }

# Handle pagination
if result["is_truncated"]:
    next_result = client.list(
        tenant_id="my-tenant",
        marker=result["next_marker"],
    )
```

### List All (Auto-pagination)

List all objects with automatic pagination:

```python
for obj in client.list_all(tenant_id="my-tenant", prefix="documents/"):
    print(f"{obj['key']} - {obj['size']} bytes")
```

### Get Quota

Check tenant quota usage:

```python
quota = client.get_quota(tenant_id="my-tenant")

print(quota)
# {
#     'tenant_id': 'my-tenant',
#     'used': 1000000,
#     'limit': 10000000,
#     'objects': 42
# }

print(f"Used: {quota['used'] / quota['limit'] * 100:.1f}%")
```

### Health Check

Check service health:

```python
health = client.health()

print(health)
# {
#     'status': 'healthy',
#     'version': '2.0.0',
#     'uptime': 3600,
#     'checks': {
#         'database': 'ok',
#         'cache': 'ok',
#         'storage': 'ok'
#     }
# }
```

## Examples

### Upload a File

```python
from minio_enterprise import MinIOClient

with MinIOClient(endpoint="http://localhost:9000", api_key="key") as client:
    with open("document.pdf", "rb") as f:
        response = client.upload(
            tenant_id="my-tenant",
            key="uploads/document.pdf",
            data=f,
            content_type="application/pdf",
        )
        print(f"Uploaded: {response['etag']}")
```

### Download Multiple Files

```python
from minio_enterprise import MinIOClient

with MinIOClient(endpoint="http://localhost:9000", api_key="key") as client:
    # List all files
    result = client.list(tenant_id="my-tenant", prefix="reports/")

    # Download each file
    for obj in result["objects"]:
        stream = client.download(
            tenant_id="my-tenant",
            key=obj["key"],
        )

        # Save locally
        local_path = f"downloads/{obj['key'].replace('/', '_')}"
        with open(local_path, "wb") as f:
            f.write(stream.read())

        print(f"Downloaded: {obj['key']}")
```

### Batch Delete

```python
from minio_enterprise import MinIOClient
import concurrent.futures

def delete_object(client, tenant_id, key):
    try:
        client.delete(tenant_id=tenant_id, key=key)
        return f"Deleted: {key}"
    except Exception as e:
        return f"Failed to delete {key}: {e}"

with MinIOClient(endpoint="http://localhost:9000", api_key="key") as client:
    keys_to_delete = ["file1.txt", "file2.txt", "file3.txt"]

    # Delete in parallel
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        futures = [
            executor.submit(delete_object, client, "my-tenant", key)
            for key in keys_to_delete
        ]

        for future in concurrent.futures.as_completed(futures):
            print(future.result())
```

### Upload with Progress Bar

```python
from minio_enterprise import MinIOClient
from tqdm import tqdm
import os

class ProgressFileReader:
    """File reader with progress bar"""

    def __init__(self, filename):
        self.filename = filename
        self.size = os.path.getsize(filename)
        self.file = open(filename, 'rb')
        self.pbar = tqdm(total=self.size, unit='B', unit_scale=True)

    def read(self, size=-1):
        data = self.file.read(size)
        self.pbar.update(len(data))
        return data

    def close(self):
        self.pbar.close()
        self.file.close()

with MinIOClient(endpoint="http://localhost:9000", api_key="key") as client:
    reader = ProgressFileReader("large_file.zip")
    try:
        response = client.upload(
            tenant_id="my-tenant",
            key="uploads/large_file.zip",
            data=reader,
        )
        print(f"\nUpload complete: {response['etag']}")
    finally:
        reader.close()
```

### Error Handling

```python
from minio_enterprise import MinIOClient, ValidationError, APIError

with MinIOClient(endpoint="http://localhost:9000", api_key="key") as client:
    try:
        stream = client.download(
            tenant_id="my-tenant",
            key="nonexistent.txt",
        )
    except ValidationError as e:
        print(f"Validation error: {e}")
    except APIError as e:
        if e.status_code == 404:
            print("File not found")
        elif e.status_code == 403:
            print("Permission denied")
        elif e.status_code == 429:
            print("Rate limit exceeded")
        else:
            print(f"API error ({e.status_code}): {e}")
    except Exception as e:
        print(f"Unexpected error: {e}")
```

### Streaming Upload

```python
from minio_enterprise import MinIOClient
import io

def generate_data():
    """Generate data on-the-fly"""
    for i in range(1000):
        yield f"Line {i}\n".encode()

with MinIOClient(endpoint="http://localhost:9000", api_key="key") as client:
    # Create a file-like object from generator
    data = io.BytesIO(b"".join(generate_data()))

    response = client.upload(
        tenant_id="my-tenant",
        key="generated/data.txt",
        data=data,
    )
    print(f"Uploaded: {response['size']} bytes")
```

## Error Handling

The SDK uses custom exception classes:

- **`MinIOError`**: Base exception for all SDK errors
- **`ValidationError`**: Raised when input validation fails
- **`APIError`**: Raised when API request fails (includes `status_code`)

All exceptions inherit from `MinIOError`, making it easy to catch all SDK errors:

```python
from minio_enterprise import MinIOClient, MinIOError

try:
    client = MinIOClient(endpoint="http://localhost:9000", api_key="key")
    result = client.upload(...)
except MinIOError as e:
    print(f"MinIO error: {e}")
```

## Testing

Run the test suite:

```bash
cd sdk/python
python -m pytest test_minio_enterprise.py -v
python -m pytest test_minio_enterprise.py --cov=minio_enterprise
```

Or use unittest:

```bash
python -m unittest test_minio_enterprise.py
```

## Performance

- **Connection Pooling**: 100 connections per host
- **Automatic Retry**: Configurable retry with exponential backoff
- **Streaming Support**: Efficient handling of large files
- **Concurrent Operations**: Thread-safe for parallel operations

## Best Practices

1. **Use Context Manager**: Ensures proper resource cleanup
   ```python
   with MinIOClient(...) as client:
       # Work with client
   # Resources automatically released
   ```

2. **Handle Large Files**: Use streaming for large uploads/downloads
   ```python
   with open("large_file.bin", "rb") as f:
       client.upload(tenant_id="tenant", key="large", data=f)
   ```

3. **Error Handling**: Always catch and handle exceptions
   ```python
   try:
       result = client.download(...)
   except APIError as e:
       if e.status_code == 404:
           # Handle not found
   ```

4. **Pagination**: Use `list_all()` for automatic pagination
   ```python
   for obj in client.list_all(tenant_id="tenant"):
       process(obj)
   ```

5. **Concurrent Operations**: Reuse client across threads
   ```python
   client = MinIOClient(...)
   with ThreadPoolExecutor() as executor:
       futures = [executor.submit(client.upload, ...) for ...]
   ```

## Requirements

- Python 3.7 or later
- requests >= 2.25.0
- urllib3 >= 1.26.0

## Support

- **Documentation**: [MinIO Enterprise Docs](https://github.com/abiolaogu/MinIO/tree/main/docs)
- **Issues**: [GitHub Issues](https://github.com/abiolaogu/MinIO/issues)
- **API Reference**: [OpenAPI Specification](https://github.com/abiolaogu/MinIO/tree/main/docs/api)

## License

Apache License 2.0 - See [LICENSE](../../LICENSE) file for details
