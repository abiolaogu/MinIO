# MinIO Enterprise Go SDK

Official Go SDK for MinIO Enterprise - Ultra-High-Performance Object Storage

## Installation

```bash
go get github.com/abiolaogu/MinIO/sdk/go
```

## Quick Start

```go
package main

import (
    "context"
    "log"

    minio "github.com/abiolaogu/MinIO/sdk/go"
)

func main() {
    // Initialize client
    client, err := minio.New(&minio.Config{
        Endpoint:  "http://localhost:9000",
        APIKey:    "your-api-key",
        APISecret: "your-api-secret",
        TenantID:  "your-tenant-id",
    })
    if err != nil {
        log.Fatal(err)
    }

    // Upload an object
    ctx := context.Background()
    err = client.Upload(ctx, "my-bucket", "my-object.txt", []byte("Hello, World!"))
    if err != nil {
        log.Fatal(err)
    }

    log.Println("Upload successful!")
}
```

## Features

- **Simple API**: Intuitive methods for common operations
- **Auto-Retry**: Automatic retry with exponential backoff
- **Connection Pooling**: Efficient connection reuse
- **Type Safety**: Full type definitions with compile-time checking
- **Context Support**: Proper context handling for cancellation and timeouts
- **Comprehensive Documentation**: Detailed API reference and examples

## API Coverage

- `Upload(ctx, bucket, key, data)` - Upload object
- `Download(ctx, bucket, key)` - Download object
- `Delete(ctx, bucket, key)` - Delete object
- `List(ctx, bucket, prefix)` - List objects
- `GetQuota(ctx)` - Get tenant quota information
- `Health(ctx)` - Check service health

## Documentation

See [API Reference](./docs/API.md) for detailed documentation.

## Examples

See [examples/](./examples/) directory for complete examples:
- `basic_upload.go` - Simple upload example
- `batch_operations.go` - Batch upload/download
- `error_handling.go` - Error handling patterns
- `advanced_features.go` - Advanced features (retry, timeout)

## Contributing

Please see [CONTRIBUTING.md](../../CONTRIBUTING.md) for contribution guidelines.

## License

Apache License 2.0 - See [LICENSE](../../LICENSE) for details.
