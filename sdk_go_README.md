# MinIO Enterprise Go SDK

Official Go SDK for MinIO Enterprise - Ultra-high-performance object storage with 10-100x performance improvements.

## Features

- **Complete API Coverage**: Upload, Download, Delete, List operations
- **Authentication**: Tenant-based authentication with X-Tenant-ID header
- **Automatic Retry Logic**: Exponential backoff with configurable retries
- **Connection Pooling**: HTTP/2 keep-alive for optimal performance
- **Context Support**: Full context.Context support for cancellation and timeouts
- **Type Safety**: Strongly typed API with comprehensive error handling
- **Production Ready**: Battle-tested with comprehensive examples

## Installation

```bash
# Add to your Go module
go get github.com/abiolaogu/MinIO/sdk
```

Or use the SDK directly from this repository:

```go
import "github.com/abiolaogu/MinIO/sdk/go/minio"
```

## Quick Start

```go
package main

import (
    "context"
    "fmt"
    "log"
    "time"

    minio "github.com/abiolaogu/MinIO/sdk/go"
)

func main() {
    // Create client configuration
    config := minio.Config{
        BaseURL:  "http://localhost:9000",
        TenantID: "550e8400-e29b-41d4-a716-446655440000",
        Timeout:  30 * time.Second,
    }

    // Create client
    client, err := minio.NewClient(config)
    if err != nil {
        log.Fatal(err)
    }

    ctx := context.Background()

    // Upload an object
    data := []byte("Hello, MinIO Enterprise!")
    resp, err := client.Upload(ctx, "my-file.txt", data)
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("Uploaded: %s (%d bytes)\n", resp.Key, resp.Size)

    // Download the object
    downloaded, err := client.Download(ctx, "my-file.txt")
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("Downloaded: %s\n", string(downloaded))

    // List objects
    keys, err := client.List(ctx, "")
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("Found %d objects\n", len(keys))

    // Delete the object
    err = client.Delete(ctx, "my-file.txt")
    if err != nil {
        log.Fatal(err)
    }
    fmt.Println("Deleted successfully")
}
```

## API Reference

### Client Configuration

```go
type Config struct {
    // BaseURL is the MinIO server URL (required)
    BaseURL string

    // TenantID is the tenant identifier (required)
    TenantID string

    // Timeout is the HTTP request timeout (default: 30s)
    Timeout time.Duration

    // MaxRetries is the maximum number of retry attempts (default: 3)
    MaxRetries int

    // BaseDelay is the base delay for exponential backoff (default: 1s)
    BaseDelay time.Duration

    // HTTPClient allows providing a custom HTTP client (optional)
    HTTPClient *http.Client
}
```

### Create Client

```go
client, err := minio.NewClient(config)
```

Creates a new MinIO client with the provided configuration.

**Parameters**:
- `config`: Configuration object with BaseURL, TenantID, and optional settings

**Returns**:
- `*Client`: MinIO client instance
- `error`: Error if configuration is invalid

### Upload Object

```go
resp, err := client.Upload(ctx, key, data)
```

Uploads an object to MinIO storage.

**Parameters**:
- `ctx`: Context for cancellation and timeouts
- `key`: Unique object key identifier (string)
- `data`: Object data as byte slice ([]byte)

**Returns**:
- `*UploadResponse`: Upload response with status, key, and size
- `error`: Error if upload fails

**Performance**: Up to 500K writes/sec

### Download Object

```go
data, err := client.Download(ctx, key)
```

Downloads an object from MinIO storage with multi-tier caching (L1/L2/L3).

**Parameters**:
- `ctx`: Context for cancellation and timeouts
- `key`: Unique object key identifier (string)

**Returns**:
- `[]byte`: Object data
- `error`: Error if download fails

**Performance**: Up to 2M reads/sec with 95%+ cache hit ratio

### Delete Object

```go
err := client.Delete(ctx, key)
```

Deletes an object from MinIO storage.

**Parameters**:
- `ctx`: Context for cancellation and timeouts
- `key`: Unique object key identifier (string)

**Returns**:
- `error`: Error if deletion fails

### List Objects

```go
keys, err := client.List(ctx, prefix)
```

Lists objects in MinIO storage with optional prefix filtering.

**Parameters**:
- `ctx`: Context for cancellation and timeouts
- `prefix`: Optional prefix to filter objects (empty string for all)

**Returns**:
- `[]string`: Slice of object keys
- `error`: Error if listing fails

### Get Server Info

```go
info, err := client.GetServerInfo(ctx)
```

Retrieves server information including version and performance metrics.

**Parameters**:
- `ctx`: Context for cancellation and timeouts

**Returns**:
- `*ServerInfo`: Server information (status, version, performance)
- `error`: Error if request fails

### Health Check

```go
healthy, err := client.HealthCheck(ctx)
```

Performs a health check on the MinIO server.

**Parameters**:
- `ctx`: Context for cancellation and timeouts

**Returns**:
- `bool`: true if server is healthy
- `error`: Error if health check fails

## Examples

### Example 1: Basic Upload and Download

```go
package main

import (
    "context"
    "fmt"
    "log"

    minio "github.com/abiolaogu/MinIO/sdk/go"
)

func main() {
    config := minio.Config{
        BaseURL:  "http://localhost:9000",
        TenantID: "550e8400-e29b-41d4-a716-446655440000",
    }

    client, err := minio.NewClient(config)
    if err != nil {
        log.Fatal(err)
    }

    ctx := context.Background()

    // Upload
    data := []byte("Hello, World!")
    resp, err := client.Upload(ctx, "hello.txt", data)
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("Uploaded: %s (%d bytes)\n", resp.Key, resp.Size)

    // Download
    downloaded, err := client.Download(ctx, "hello.txt")
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("Content: %s\n", string(downloaded))
}
```

### Example 2: Bulk Upload with Error Handling

```go
package main

import (
    "context"
    "fmt"
    "log"

    minio "github.com/abiolaogu/MinIO/sdk/go"
)

func main() {
    config := minio.Config{
        BaseURL:  "http://localhost:9000",
        TenantID: "550e8400-e29b-41d4-a716-446655440000",
    }

    client, err := minio.NewClient(config)
    if err != nil {
        log.Fatal(err)
    }

    ctx := context.Background()

    // Bulk upload with error handling
    files := map[string][]byte{
        "file1.txt": []byte("Content 1"),
        "file2.txt": []byte("Content 2"),
        "file3.txt": []byte("Content 3"),
    }

    for key, data := range files {
        resp, err := client.Upload(ctx, key, data)
        if err != nil {
            log.Printf("Failed to upload %s: %v", key, err)
            continue
        }
        fmt.Printf("✓ Uploaded: %s (%d bytes)\n", resp.Key, resp.Size)
    }
}
```

### Example 3: List and Download with Prefix Filter

```go
package main

import (
    "context"
    "fmt"
    "log"

    minio "github.com/abiolaogu/MinIO/sdk/go"
)

func main() {
    config := minio.Config{
        BaseURL:  "http://localhost:9000",
        TenantID: "550e8400-e29b-41d4-a716-446655440000",
    }

    client, err := minio.NewClient(config)
    if err != nil {
        log.Fatal(err)
    }

    ctx := context.Background()

    // List objects with prefix
    keys, err := client.List(ctx, "uploads/")
    if err != nil {
        log.Fatal(err)
    }

    fmt.Printf("Found %d objects with prefix 'uploads/'\n", len(keys))

    // Download each object
    for _, key := range keys {
        data, err := client.Download(ctx, key)
        if err != nil {
            log.Printf("Failed to download %s: %v", key, err)
            continue
        }
        fmt.Printf("✓ Downloaded %s: %d bytes\n", key, len(data))
    }
}
```

### Example 4: Custom HTTP Client with Timeout

```go
package main

import (
    "context"
    "fmt"
    "log"
    "net/http"
    "time"

    minio "github.com/abiolaogu/MinIO/sdk/go"
)

func main() {
    // Create custom HTTP client with specific timeout
    httpClient := &http.Client{
        Timeout: 10 * time.Second,
        Transport: &http.Transport{
            MaxIdleConns:        50,
            MaxIdleConnsPerHost: 5,
            IdleConnTimeout:     60 * time.Second,
        },
    }

    config := minio.Config{
        BaseURL:    "http://localhost:9000",
        TenantID:   "550e8400-e29b-41d4-a716-446655440000",
        HTTPClient: httpClient,
        MaxRetries: 5,
        BaseDelay:  2 * time.Second,
    }

    client, err := minio.NewClient(config)
    if err != nil {
        log.Fatal(err)
    }

    ctx := context.Background()

    // Operations will use the custom HTTP client
    resp, err := client.Upload(ctx, "test.txt", []byte("Test data"))
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("Uploaded with custom client: %s\n", resp.Key)
}
```

### Example 5: Context Timeout and Cancellation

```go
package main

import (
    "context"
    "fmt"
    "log"
    "time"

    minio "github.com/abiolaogu/MinIO/sdk/go"
)

func main() {
    config := minio.Config{
        BaseURL:  "http://localhost:9000",
        TenantID: "550e8400-e29b-41d4-a716-446655440000",
    }

    client, err := minio.NewClient(config)
    if err != nil {
        log.Fatal(err)
    }

    // Create context with timeout
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    // Upload with timeout
    data := []byte("Hello, World!")
    resp, err := client.Upload(ctx, "hello.txt", data)
    if err != nil {
        if ctx.Err() == context.DeadlineExceeded {
            log.Fatal("Upload timed out")
        }
        log.Fatal(err)
    }
    fmt.Printf("Uploaded: %s\n", resp.Key)
}
```

### Example 6: Health Check and Server Info

```go
package main

import (
    "context"
    "fmt"
    "log"

    minio "github.com/abiolaogu/MinIO/sdk/go"
)

func main() {
    config := minio.Config{
        BaseURL:  "http://localhost:9000",
        TenantID: "550e8400-e29b-41d4-a716-446655440000",
    }

    client, err := minio.NewClient(config)
    if err != nil {
        log.Fatal(err)
    }

    ctx := context.Background()

    // Health check
    healthy, err := client.HealthCheck(ctx)
    if err != nil {
        log.Fatal(err)
    }

    if !healthy {
        log.Fatal("Server is not healthy")
    }
    fmt.Println("✓ Server is healthy")

    // Get server info
    info, err := client.GetServerInfo(ctx)
    if err != nil {
        log.Fatal(err)
    }

    fmt.Printf("Server Info:\n")
    fmt.Printf("  Status: %s\n", info.Status)
    fmt.Printf("  Version: %s\n", info.Version)
    fmt.Printf("  Performance: %s\n", info.Performance)
}
```

## Error Handling

The SDK provides comprehensive error handling with detailed error messages:

```go
resp, err := client.Upload(ctx, "test.txt", data)
if err != nil {
    // Check for specific error types
    if ctx.Err() == context.DeadlineExceeded {
        log.Println("Request timed out")
    } else if ctx.Err() == context.Canceled {
        log.Println("Request was cancelled")
    } else {
        log.Printf("Upload failed: %v", err)
    }
    return
}
```

## Retry Logic

The SDK automatically retries failed requests with exponential backoff:

- **Default Max Retries**: 3 attempts
- **Default Base Delay**: 1 second
- **Backoff Strategy**: Exponential (1s, 2s, 4s, 8s, ...)

Configure retry behavior:

```go
config := minio.Config{
    BaseURL:    "http://localhost:9000",
    TenantID:   "tenant-id",
    MaxRetries: 5,              // Custom retry count
    BaseDelay:  2 * time.Second, // Custom base delay
}
```

## Connection Pooling

The SDK uses HTTP connection pooling for optimal performance:

- **Max Idle Connections**: 100
- **Max Idle Connections Per Host**: 10
- **Idle Connection Timeout**: 90 seconds
- **Keep-Alive**: Enabled by default

## Performance Tips

1. **Reuse Client Instances**: Create one client and reuse it across requests
2. **Use Context Timeouts**: Set appropriate timeouts to prevent hanging requests
3. **Batch Operations**: Use goroutines for concurrent uploads/downloads
4. **Monitor Errors**: Implement proper error handling and logging
5. **Tune Connection Pool**: Adjust connection pool settings based on workload

## Best Practices

1. **Always use context**: Pass context.Context for cancellation support
2. **Handle errors properly**: Check and log errors with meaningful messages
3. **Set reasonable timeouts**: Configure timeouts based on expected operation duration
4. **Use defer for cleanup**: Use `defer cancel()` when creating contexts with timeout
5. **Validate inputs**: Ensure keys and data are valid before making requests

## Thread Safety

The `Client` is thread-safe and can be used concurrently from multiple goroutines.

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
**Go Version**: 1.22+
