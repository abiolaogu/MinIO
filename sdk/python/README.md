# MinIO Enterprise Python SDK

Official Python SDK for MinIO Enterprise - Ultra-High-Performance Object Storage.

## Features

- **Simple API**: Intuitive methods for upload, download, and object management
- **Automatic Retries**: Exponential backoff retry logic for transient failures
- **Connection Pooling**: Built-in connection pooling for optimal performance
- **Context Manager Support**: Easy resource management with context managers
- **Type Hints**: Full type annotations for better IDE support

## Installation

```bash
pip install minio-enterprise
```

For development:

```bash
pip install -e ".[dev]"
```

## Quick Start

```python
from minio_enterprise import Client, Config

# Create a client
client = Client(Config(
    base_url="http://localhost:9000",
    tenant_id="550e8400-e29b-41d4-a716-446655440000"
))

# Upload an object
with open("file.txt", "rb") as f:
    response = client.upload("my-file.txt", f)
    print(f"Uploaded {response['key']} ({response['size']} bytes)")

# Download an object
data = client.download("my-file.txt")
print(data.decode())

# Clean up
client.close()
```

## API Reference

### Creating a Client

```python
from minio_enterprise import Client, Config

# Basic configuration
client = Client(Config(
    base_url="http://localhost:9000",
    tenant_id="your-tenant-id"
))

# Custom configuration
client = Client(Config(
    base_url="http://localhost:9000",
    tenant_id="your-tenant-id",
    timeout=60,      # HTTP timeout in seconds
    max_retries=5    # Maximum retry attempts
))
```

### Upload an Object

```python
# Upload from bytes
response = client.upload("test.txt", b"Hello, World!")

# Upload from file
with open("local-file.txt", "rb") as f:
    response = client.upload("remote-file.txt", f)

# Response structure
# {
#     "status": "uploaded",
#     "key": "remote-file.txt",
#     "size": 12345
# }
```

### Download an Object

```python
# Download to memory
data = client.download("test.txt")
print(data.decode())

# Download to file
client.download_to_file("remote.txt", "local.txt")
```

### Server Information

```python
info = client.get_server_info()
print(f"Version: {info['version']}")
print(f"Status: {info['status']}")
print(f"Performance: {info['performance']}")

# Response structure
# {
#     "status": "ok",
#     "version": "3.0.0-extreme",
#     "performance": "100x"
# }
```

### Health Check

```python
if client.health_check():
    print("Service is healthy")
else:
    print("Service is unhealthy")
```

## Error Handling

The SDK provides typed exceptions for better error handling:

```python
from minio_enterprise import Client, Config, APIError, NetworkError

client = Client(Config(
    base_url="http://localhost:9000",
    tenant_id="your-tenant-id"
))

try:
    data = client.download("non-existent-file.txt")
except APIError as e:
    if e.status_code == 404:
        print(f"File not found: {e.message}")
    elif e.status_code == 403:
        print(f"Quota exceeded: {e.message}")
    else:
        print(f"API error {e.status_code}: {e.message}")
except NetworkError as e:
    print(f"Network error: {e.message}")
```

## Advanced Usage

### Context Manager

```python
from minio_enterprise import Client, Config

with Client(Config(
    base_url="http://localhost:9000",
    tenant_id="your-tenant-id"
)) as client:
    # Upload a file
    with open("test.txt", "rb") as f:
        response = client.upload("test.txt", f)
        print(f"Uploaded: {response['key']}")

# Client automatically closes when exiting context
```

### Custom Configuration

```python
client = Client(Config(
    base_url="http://localhost:9000",
    tenant_id="your-tenant-id",
    timeout=60,      # Custom timeout: 60 seconds
    max_retries=5    # Custom retry count: 5 attempts
))
```

### Batch Operations

```python
import concurrent.futures

def upload_file(filename):
    with open(filename, "rb") as f:
        response = client.upload(filename, f)
        return response

files = ["file1.txt", "file2.txt", "file3.txt"]

with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
    futures = [executor.submit(upload_file, f) for f in files]
    for future in concurrent.futures.as_completed(futures):
        try:
            result = future.result()
            print(f"Uploaded: {result['key']}")
        except Exception as e:
            print(f"Error: {e}")
```

## Examples

See the [examples](examples/) directory for complete examples:

- `basic.py` - Basic upload and download
- `advanced.py` - Advanced features and error handling
- `batch.py` - Batch operations with threading
- `context_manager.py` - Using context managers

## Performance Characteristics

- **Upload Performance**: Up to 500K operations/sec
- **Download Performance**: Up to 2M operations/sec
- **Cache Hit Rate**: 95%+ (sub-millisecond latency)
- **Connection Pooling**: Automatic connection reuse
- **Retry Logic**: Exponential backoff (1s, 2s, 4s, ...)

## Requirements

- Python 3.8 or higher
- MinIO Enterprise server (version 3.0.0+)

## Development

Install development dependencies:

```bash
pip install -e ".[dev]"
```

Run tests:

```bash
pytest
```

Run tests with coverage:

```bash
pytest --cov=minio_enterprise --cov-report=html
```

Format code:

```bash
black minio_enterprise/
```

Lint code:

```bash
flake8 minio_enterprise/
mypy minio_enterprise/
```

## Contributing

Contributions are welcome! Please submit issues and pull requests to the main repository.

## License

Apache License 2.0 - See [LICENSE](../../LICENSE) file for details.

## Support

- **Documentation**: [MinIO Enterprise Docs](../../docs/)
- **Issues**: [GitHub Issues](https://github.com/abiolaogu/MinIO/issues)
- **Discussions**: [GitHub Discussions](https://github.com/abiolaogu/MinIO/discussions)
