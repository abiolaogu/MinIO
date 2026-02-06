# MinIO Enterprise Python SDK

Official Python client library for MinIO Enterprise, providing a simple and intuitive API for object storage operations.

## Features

- **Simple API**: Easy-to-use methods for common operations (Upload, Download, Delete, List)
- **Automatic Retries**: Built-in retry logic with exponential backoff
- **Connection Pooling**: Efficient HTTP connection reuse
- **Type Hints**: Full type annotations for better IDE support
- **Exception Handling**: Comprehensive exception hierarchy for precise error handling
- **Context Manager Support**: Use with `with` statement for automatic resource cleanup
- **Production Ready**: Tested and optimized for high-performance applications

## Installation

### From PyPI (when published)

```bash
pip install minio-enterprise
```

### From Source

```bash
git clone https://github.com/abiolaogu/MinIO.git
cd MinIO/sdk/python
pip install -e .
```

### Development Installation

```bash
pip install -e ".[dev]"
```

## Quick Start

```python
from minio import Client, Config

# Create a new client
client = Client(Config(
    endpoint="http://localhost:9000",
    api_key="your-api-key-here"
))

# Upload an object
with open("local-file.txt", "rb") as f:
    client.upload("my-tenant", "remote-file.txt", f)

print("Upload successful!")

# Close the client
client.close()
```

## Configuration

### Basic Configuration

```python
from minio import Client, Config

client = Client(Config(
    endpoint="http://localhost:9000",
    api_key="your-api-key-here"
))
```

### Advanced Configuration

```python
from minio import Client, Config

client = Client(Config(
    endpoint="http://localhost:9000",
    api_key="your-api-key-here",
    timeout=60,              # Request timeout in seconds
    max_retries=5,           # Maximum number of retries
    backoff_factor=2.0,      # Exponential backoff multiplier
    verify_ssl=True          # Verify SSL certificates
))
```

### Using Context Manager

```python
from minio import Client, Config

# Automatically closes the client when done
with Client(Config(endpoint="http://localhost:9000", api_key="your-api-key")) as client:
    client.upload("tenant-id", "file.txt", data)
    # Client is automatically closed after this block
```

## API Reference

### Upload

Upload an object to MinIO.

```python
from minio import Client, Config, UploadOptions

client = Client(Config(
    endpoint="http://localhost:9000",
    api_key="your-api-key"
))

# Basic upload
with open("file.txt", "rb") as f:
    client.upload("tenant-id", "path/to/file.txt", f)

# Upload with content type
with open("image.jpg", "rb") as f:
    client.upload(
        "tenant-id",
        "images/photo.jpg",
        f,
        UploadOptions(content_type="image/jpeg")
    )

# Upload with metadata
with open("document.pdf", "rb") as f:
    client.upload(
        "tenant-id",
        "docs/report.pdf",
        f,
        UploadOptions(
            content_type="application/pdf",
            metadata={"author": "John Doe", "department": "Engineering"}
        )
    )

client.close()
```

### Download

Download an object from MinIO.

```python
from minio import Client, Config

client = Client(Config(
    endpoint="http://localhost:9000",
    api_key="your-api-key"
))

# Download an object
data = client.download("tenant-id", "path/to/file.txt")
print(f"Downloaded {len(data)} bytes")

# Save to file
with open("local-file.txt", "wb") as f:
    f.write(data)

client.close()
```

### Delete

Delete an object from MinIO.

```python
from minio import Client, Config

client = Client(Config(
    endpoint="http://localhost:9000",
    api_key="your-api-key"
))

# Delete an object
client.delete("tenant-id", "path/to/file.txt")
print("Delete successful!")

client.close()
```

### List

List objects in a tenant's storage.

```python
from minio import Client, Config, ListOptions

client = Client(Config(
    endpoint="http://localhost:9000",
    api_key="your-api-key"
))

# List all objects
response = client.list("tenant-id")
print(f"Found {response.count} objects:")
for obj in response.objects:
    print(f"  - {obj.key} ({obj.size} bytes)")

# List with prefix filter
response = client.list(
    "tenant-id",
    ListOptions(prefix="documents/", max_keys=100)
)

# List with pagination
response = client.list(
    "tenant-id",
    ListOptions(max_keys=50)  # Limit to 50 results
)

client.close()
```

### Get Quota

Retrieve quota information for a tenant.

```python
from minio import Client, Config

client = Client(Config(
    endpoint="http://localhost:9000",
    api_key="your-api-key"
))

quota = client.get_quota("tenant-id")
print(f"Quota for {quota.tenant_id}:")
print(f"  Used: {quota.used} bytes")
print(f"  Limit: {quota.limit} bytes")
print(f"  Percentage: {quota.percentage:.2f}%")

client.close()
```

### Health Check

Check the health status of the MinIO service.

```python
from minio import Client, Config

client = Client(Config(
    endpoint="http://localhost:9000",
    api_key="your-api-key"
))

health = client.health()
print(f"Service Status: {health.status} (at {health.timestamp})")

client.close()
```

## Complete Examples

### Example 1: File Upload and Download

```python
import os
from minio import Client, Config, UploadOptions

def main():
    # Create client using context manager
    with Client(Config(
        endpoint="http://localhost:9000",
        api_key=os.getenv("MINIO_API_KEY")
    )) as client:

        tenant_id = "my-tenant"

        # Upload a file
        print("Uploading file...")
        with open("local-file.txt", "rb") as f:
            client.upload(
                tenant_id,
                "remote-file.txt",
                f,
                UploadOptions(content_type="text/plain")
            )
        print("Upload successful!")

        # Download the file
        print("Downloading file...")
        data = client.download(tenant_id, "remote-file.txt")

        # Save to local file
        with open("downloaded-file.txt", "wb") as f:
            f.write(data)
        print(f"Download successful! ({len(data)} bytes)")

if __name__ == "__main__":
    main()
```

### Example 2: Batch Operations

```python
import concurrent.futures
import io
from minio import Client, Config

def upload_file(client, tenant_id, filename, content):
    """Upload a single file"""
    try:
        data = io.BytesIO(content.encode())
        client.upload(tenant_id, filename, data)
        print(f"Uploaded: {filename}")
    except Exception as e:
        print(f"Failed to upload {filename}: {e}")

def main():
    with Client(Config(
        endpoint="http://localhost:9000",
        api_key="your-api-key"
    )) as client:

        tenant_id = "my-tenant"

        # Upload multiple files concurrently
        files = {
            "file1.txt": "Content of file 1",
            "file2.txt": "Content of file 2",
            "file3.txt": "Content of file 3",
        }

        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            futures = [
                executor.submit(upload_file, client, tenant_id, name, content)
                for name, content in files.items()
            ]
            concurrent.futures.wait(futures)

        print("\nAll uploads complete!")

        # List all uploaded files
        response = client.list(tenant_id)
        print(f"\nFound {response.count} objects:")
        for obj in response.objects:
            print(f"  - {obj.key} ({obj.size} bytes, "
                  f"modified: {obj.last_modified.strftime('%Y-%m-%d %H:%M:%S')})")

if __name__ == "__main__":
    main()
```

### Example 3: Error Handling

```python
from minio import (
    Client,
    Config,
    AuthenticationError,
    QuotaExceededError,
    NotFoundError,
    RateLimitError,
    MinIOError
)
import io

def main():
    with Client(Config(
        endpoint="http://localhost:9000",
        api_key="your-api-key"
    )) as client:

        tenant_id = "my-tenant"

        try:
            # Attempt to upload
            data = io.BytesIO(b"test data")
            client.upload(tenant_id, "test.txt", data)
            print("Upload successful!")

        except AuthenticationError as e:
            print(f"Authentication failed: {e}")
            print("Please check your API key")

        except QuotaExceededError as e:
            print(f"Quota exceeded: {e}")
            print("Please increase tenant quota or delete old files")

        except NotFoundError as e:
            print(f"Resource not found: {e}")

        except RateLimitError as e:
            print(f"Rate limited: {e}")
            print("Please slow down your requests")

        except MinIOError as e:
            print(f"MinIO error: {e}")
            print(f"Status code: {e.status_code}")
            print(f"Response body: {e.response_body}")

if __name__ == "__main__":
    main()
```

### Example 4: Quota Monitoring

```python
import time
from minio import Client, Config

def monitor_quota(client, tenant_id, threshold=80.0):
    """Monitor tenant quota usage"""
    quota = client.get_quota(tenant_id)

    print(f"Quota Status for {quota.tenant_id}:")
    print(f"  Used: {quota.used:,} bytes")
    print(f"  Limit: {quota.limit:,} bytes")
    print(f"  Percentage: {quota.percentage:.2f}%")

    if quota.percentage >= threshold:
        print(f"\n⚠️  WARNING: Quota usage is at {quota.percentage:.2f}%!")
        print("   Consider cleaning up old files or increasing quota.")
    else:
        print(f"\n✓ Quota usage is healthy.")

def main():
    with Client(Config(
        endpoint="http://localhost:9000",
        api_key="your-api-key"
    )) as client:

        # Monitor quota every 60 seconds
        while True:
            monitor_quota(client, "my-tenant", threshold=80.0)
            time.sleep(60)

if __name__ == "__main__":
    main()
```

### Example 5: Large File Upload with Progress

```python
import os
from minio import Client, Config, UploadOptions

class ProgressReader:
    """Wrapper to track upload progress"""

    def __init__(self, file, total_size):
        self.file = file
        self.total_size = total_size
        self.uploaded = 0

    def read(self, size=-1):
        data = self.file.read(size)
        self.uploaded += len(data)

        # Print progress
        percentage = (self.uploaded / self.total_size) * 100
        print(f"\rProgress: {percentage:.1f}% ({self.uploaded:,}/{self.total_size:,} bytes)", end="")

        return data

def upload_large_file(client, tenant_id, local_path, remote_key):
    """Upload a large file with progress tracking"""
    file_size = os.path.getsize(local_path)

    with open(local_path, "rb") as f:
        progress_reader = ProgressReader(f, file_size)
        client.upload(
            tenant_id,
            remote_key,
            progress_reader,
            UploadOptions(content_type="application/octet-stream")
        )

    print()  # New line after progress

def main():
    with Client(Config(
        endpoint="http://localhost:9000",
        api_key="your-api-key",
        timeout=300  # 5 minutes for large files
    )) as client:

        upload_large_file(
            client,
            "my-tenant",
            "large-file.bin",
            "uploads/large-file.bin"
        )

        print("Upload complete!")

if __name__ == "__main__":
    main()
```

### Example 6: Backup and Restore

```python
import os
from pathlib import Path
from minio import Client, Config, ListOptions

def backup_directory(client, tenant_id, local_dir, remote_prefix):
    """Backup a local directory to MinIO"""
    local_path = Path(local_dir)

    for file_path in local_path.rglob("*"):
        if file_path.is_file():
            # Calculate relative path
            relative_path = file_path.relative_to(local_path)
            remote_key = f"{remote_prefix}/{relative_path}".replace("\\", "/")

            # Upload file
            with open(file_path, "rb") as f:
                client.upload(tenant_id, remote_key, f)
                print(f"Backed up: {relative_path}")

def restore_directory(client, tenant_id, remote_prefix, local_dir):
    """Restore files from MinIO to local directory"""
    local_path = Path(local_dir)
    local_path.mkdir(parents=True, exist_ok=True)

    # List all objects with prefix
    response = client.list(tenant_id, ListOptions(prefix=remote_prefix))

    for obj in response.objects:
        # Remove prefix to get relative path
        relative_key = obj.key[len(remote_prefix):].lstrip("/")
        local_file = local_path / relative_key

        # Create parent directories
        local_file.parent.mkdir(parents=True, exist_ok=True)

        # Download file
        data = client.download(tenant_id, obj.key)
        with open(local_file, "wb") as f:
            f.write(data)

        print(f"Restored: {relative_key}")

def main():
    with Client(Config(
        endpoint="http://localhost:9000",
        api_key="your-api-key"
    )) as client:

        # Backup
        print("Starting backup...")
        backup_directory(client, "my-tenant", "./data", "backups/2024-01-15")
        print("\nBackup complete!")

        # Restore
        print("\nStarting restore...")
        restore_directory(client, "my-tenant", "backups/2024-01-15", "./restored-data")
        print("\nRestore complete!")

if __name__ == "__main__":
    main()
```

## Best Practices

### 1. Use Context Manager

```python
# Good: Automatically closes resources
with Client(Config(endpoint="...", api_key="...")) as client:
    client.upload(...)

# Also acceptable: Manual close
client = Client(Config(endpoint="...", api_key="..."))
try:
    client.upload(...)
finally:
    client.close()
```

### 2. Handle Exceptions Appropriately

```python
from minio import Client, Config, QuotaExceededError, MinIOError

with Client(Config(endpoint="...", api_key="...")) as client:
    try:
        client.upload(tenant_id, key, data)
    except QuotaExceededError:
        # Handle quota specifically
        print("Quota exceeded, cleaning up old files...")
    except MinIOError as e:
        # Handle all other MinIO errors
        print(f"Operation failed: {e}")
```

### 3. Reuse Client Instances

```python
# Good: Create once, use many times
client = Client(Config(endpoint="...", api_key="..."))

for file in files:
    client.upload(tenant_id, file.name, file.data)

client.close()

# Bad: Creating a new client for each operation
for file in files:
    client = Client(Config(endpoint="...", api_key="..."))  # Don't do this!
    client.upload(tenant_id, file.name, file.data)
    client.close()
```

### 4. Use Environment Variables for Credentials

```python
import os
from minio import Client, Config

client = Client(Config(
    endpoint=os.getenv("MINIO_ENDPOINT", "http://localhost:9000"),
    api_key=os.getenv("MINIO_API_KEY"),
))
```

### 5. Monitor Quota Usage

```python
quota = client.get_quota(tenant_id)

if quota.percentage > 80:
    print(f"Warning: Quota at {quota.percentage:.1f}%")
    # Send alert or clean up old files
```

### 6. Use Appropriate Timeouts

```python
# For large files, use longer timeout
client = Client(Config(
    endpoint="...",
    api_key="...",
    timeout=300  # 5 minutes
))
```

## Testing

### Run Tests

```bash
pytest tests/
```

### Run with Coverage

```bash
pytest --cov=minio --cov-report=html tests/
```

### Run Type Checking

```bash
mypy minio/
```

### Run Linting

```bash
flake8 minio/
black minio/
```

## Exception Hierarchy

```
MinIOError (base exception)
├── AuthenticationError (401, 403)
├── QuotaExceededError (quota exceeded)
├── NotFoundError (404)
├── RateLimitError (429)
├── ServerError (5xx)
└── ValidationError (invalid parameters)
```

## Performance Tips

1. **Connection Pooling**: Reuse client instances to benefit from connection pooling
2. **Concurrent Operations**: Use threading/multiprocessing for concurrent uploads
3. **Appropriate Timeouts**: Set timeouts based on file sizes and network conditions
4. **Retry Configuration**: Tune retry settings based on your network reliability
5. **Buffering**: Use appropriate buffer sizes when working with large files

## Troubleshooting

### Connection Refused

```
Error: Connection refused
```

**Solution**: Ensure the MinIO server is running and accessible at the configured endpoint.

### Authentication Failed

```
AuthenticationError: Authentication failed: unauthorized
```

**Solution**: Verify your API key is correct and has necessary permissions.

### SSL Certificate Verification Failed

```
Error: SSL certificate verification failed
```

**Solution**: Either fix the SSL certificate or disable verification (not recommended for production):

```python
client = Client(Config(
    endpoint="...",
    api_key="...",
    verify_ssl=False  # Only for development!
))
```

### Timeout Errors

```
Error: Request timed out
```

**Solution**: Increase the timeout in the client configuration:

```python
client = Client(Config(
    endpoint="...",
    api_key="...",
    timeout=60  # Increase timeout
))
```

## Support

- **Documentation**: [MinIO Enterprise Docs](https://github.com/abiolaogu/MinIO/tree/main/docs)
- **Issues**: [GitHub Issues](https://github.com/abiolaogu/MinIO/issues)
- **Discussions**: [GitHub Discussions](https://github.com/abiolaogu/MinIO/discussions)

## License

Apache License 2.0 - See [LICENSE](../../LICENSE) file for details.

## Contributing

Contributions are welcome! Please read our [Contributing Guide](../../CONTRIBUTING.md) for details.
