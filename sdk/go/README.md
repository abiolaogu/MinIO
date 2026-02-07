# MinIO Enterprise Go SDK

Official Go client library for MinIO Enterprise, providing a simple and intuitive API for object storage operations.

## Features

- **Simple API**: Easy-to-use methods for common operations (Upload, Download, Delete, List)
- **Automatic Retries**: Built-in retry logic with exponential backoff
- **Connection Pooling**: Efficient HTTP connection reuse
- **Context Support**: Full context support for timeout and cancellation
- **Type Safety**: Strong typing with comprehensive error handling
- **Zero Dependencies**: No external dependencies in core SDK
- **Production Ready**: Tested and optimized for high-performance applications

## Installation

```bash
go get github.com/abiolaogu/MinIO/sdk/go/minio
```

## Quick Start

```go
package main

import (
    "context"
    "fmt"
    "log"
    "strings"

    "github.com/abiolaogu/MinIO/sdk/go/minio"
)

func main() {
    // Create a new client
    client, err := minio.NewClient(minio.Config{
        Endpoint: "http://localhost:9000",
        APIKey:   "your-api-key-here",
    })
    if err != nil {
        log.Fatalf("Failed to create client: %v", err)
    }
    defer client.Close()

    // Upload an object
    data := strings.NewReader("Hello, MinIO Enterprise!")
    err = client.Upload(context.Background(), "my-tenant", "hello.txt", data, nil)
    if err != nil {
        log.Fatalf("Upload failed: %v", err)
    }

    fmt.Println("Upload successful!")
}
```

## Configuration

### Basic Configuration

```go
client, err := minio.NewClient(minio.Config{
    Endpoint: "http://localhost:9000",
    APIKey:   "your-api-key-here",
})
```

### Advanced Configuration

```go
import (
    "net/http"
    "time"
)

client, err := minio.NewClient(minio.Config{
    Endpoint:        "http://localhost:9000",
    APIKey:          "your-api-key-here",
    Timeout:         60 * time.Second,        // Custom timeout
    MaxRetries:      5,                        // Retry up to 5 times
    BackoffDuration: 2 * time.Second,         // Initial backoff duration
    Transport: &http.Transport{               // Custom HTTP transport
        MaxIdleConns:        200,
        MaxIdleConnsPerHost: 20,
        IdleConnTimeout:     120 * time.Second,
    },
})
```

## API Reference

### Upload

Upload an object to MinIO.

```go
// Basic upload
data := strings.NewReader("file content")
err := client.Upload(ctx, "tenant-id", "path/to/file.txt", data, nil)

// Upload with content type
err := client.Upload(ctx, "tenant-id", "image.jpg", imageData, &minio.UploadOptions{
    ContentType: "image/jpeg",
})

// Upload with metadata
err := client.Upload(ctx, "tenant-id", "doc.pdf", pdfData, &minio.UploadOptions{
    ContentType: "application/pdf",
    Metadata: map[string]string{
        "author": "John Doe",
        "department": "Engineering",
    },
})
```

### Download

Download an object from MinIO.

```go
// Download an object
reader, err := client.Download(ctx, "tenant-id", "path/to/file.txt")
if err != nil {
    log.Fatalf("Download failed: %v", err)
}
defer reader.Close()

// Read the content
data, err := io.ReadAll(reader)
if err != nil {
    log.Fatalf("Failed to read data: %v", err)
}

fmt.Printf("Downloaded: %s\n", string(data))
```

### Delete

Delete an object from MinIO.

```go
err := client.Delete(ctx, "tenant-id", "path/to/file.txt")
if err != nil {
    log.Fatalf("Delete failed: %v", err)
}
```

### List

List objects in a tenant's storage.

```go
// List all objects
resp, err := client.List(ctx, "tenant-id", nil)
if err != nil {
    log.Fatalf("List failed: %v", err)
}

fmt.Printf("Found %d objects:\n", resp.Count)
for _, obj := range resp.Objects {
    fmt.Printf("  - %s (%d bytes)\n", obj.Key, obj.Size)
}

// List with prefix filter
resp, err := client.List(ctx, "tenant-id", &minio.ListOptions{
    Prefix:  "documents/",
    MaxKeys: 100,
})

// List with pagination
resp, err := client.List(ctx, "tenant-id", &minio.ListOptions{
    MaxKeys: 50, // Limit to 50 results
})
```

### Get Quota

Retrieve quota information for a tenant.

```go
quota, err := client.GetQuota(ctx, "tenant-id")
if err != nil {
    log.Fatalf("GetQuota failed: %v", err)
}

fmt.Printf("Quota for %s:\n", quota.TenantID)
fmt.Printf("  Used: %d bytes\n", quota.Used)
fmt.Printf("  Limit: %d bytes\n", quota.Limit)
fmt.Printf("  Percentage: %.2f%%\n", quota.Percentage)
```

### Health Check

Check the health status of the MinIO service.

```go
health, err := client.Health(ctx)
if err != nil {
    log.Fatalf("Health check failed: %v", err)
}

fmt.Printf("Service Status: %s (at %s)\n", health.Status, health.Timestamp)
```

## Complete Examples

### Example 1: File Upload and Download

```go
package main

import (
    "context"
    "fmt"
    "io"
    "log"
    "os"

    "github.com/abiolaogu/MinIO/sdk/go/minio"
)

func main() {
    client, err := minio.NewClient(minio.Config{
        Endpoint: "http://localhost:9000",
        APIKey:   os.Getenv("MINIO_API_KEY"),
    })
    if err != nil {
        log.Fatalf("Failed to create client: %v", err)
    }
    defer client.Close()

    ctx := context.Background()
    tenantID := "my-tenant"

    // Upload a file
    file, err := os.Open("local-file.txt")
    if err != nil {
        log.Fatalf("Failed to open file: %v", err)
    }
    defer file.Close()

    err = client.Upload(ctx, tenantID, "remote-file.txt", file, &minio.UploadOptions{
        ContentType: "text/plain",
    })
    if err != nil {
        log.Fatalf("Upload failed: %v", err)
    }
    fmt.Println("Upload successful!")

    // Download the file
    reader, err := client.Download(ctx, tenantID, "remote-file.txt")
    if err != nil {
        log.Fatalf("Download failed: %v", err)
    }
    defer reader.Close()

    // Save to local file
    outFile, err := os.Create("downloaded-file.txt")
    if err != nil {
        log.Fatalf("Failed to create output file: %v", err)
    }
    defer outFile.Close()

    _, err = io.Copy(outFile, reader)
    if err != nil {
        log.Fatalf("Failed to write file: %v", err)
    }
    fmt.Println("Download successful!")
}
```

### Example 2: Batch Operations

```go
package main

import (
    "context"
    "fmt"
    "log"
    "strings"
    "sync"

    "github.com/abiolaogu/MinIO/sdk/go/minio"
)

func main() {
    client, err := minio.NewClient(minio.Config{
        Endpoint: "http://localhost:9000",
        APIKey:   "your-api-key",
    })
    if err != nil {
        log.Fatalf("Failed to create client: %v", err)
    }
    defer client.Close()

    ctx := context.Background()
    tenantID := "my-tenant"

    // Upload multiple files concurrently
    var wg sync.WaitGroup
    files := []string{"file1.txt", "file2.txt", "file3.txt"}

    for _, fileName := range files {
        wg.Add(1)
        go func(name string) {
            defer wg.Done()

            data := strings.NewReader(fmt.Sprintf("Content of %s", name))
            err := client.Upload(ctx, tenantID, name, data, nil)
            if err != nil {
                log.Printf("Failed to upload %s: %v", name, err)
                return
            }
            fmt.Printf("Uploaded: %s\n", name)
        }(fileName)
    }

    wg.Wait()
    fmt.Println("All uploads complete!")

    // List all uploaded files
    resp, err := client.List(ctx, tenantID, nil)
    if err != nil {
        log.Fatalf("List failed: %v", err)
    }

    fmt.Printf("\nFound %d objects:\n", resp.Count)
    for _, obj := range resp.Objects {
        fmt.Printf("  - %s (%d bytes, modified: %s)\n",
            obj.Key, obj.Size, obj.LastModified.Format("2006-01-02 15:04:05"))
    }
}
```

### Example 3: Error Handling

```go
package main

import (
    "context"
    "errors"
    "fmt"
    "log"
    "net"
    "strings"

    "github.com/abiolaogu/MinIO/sdk/go/minio"
)

func main() {
    client, err := minio.NewClient(minio.Config{
        Endpoint: "http://localhost:9000",
        APIKey:   "your-api-key",
    })
    if err != nil {
        log.Fatalf("Failed to create client: %v", err)
    }
    defer client.Close()

    ctx := context.Background()
    tenantID := "my-tenant"

    // Attempt to upload with error handling
    data := strings.NewReader("test data")
    err = client.Upload(ctx, tenantID, "test.txt", data, nil)

    if err != nil {
        // Handle different types of errors
        var netErr net.Error
        if errors.As(err, &netErr) && netErr.Timeout() {
            log.Printf("Upload timed out: %v", err)
            // Retry logic here
        } else if strings.Contains(err.Error(), "status 429") {
            log.Printf("Rate limited, backing off: %v", err)
            // Backoff and retry
        } else if strings.Contains(err.Error(), "status 403") {
            log.Printf("Authentication failed: %v", err)
            // Check API key
        } else if strings.Contains(err.Error(), "quota exceeded") {
            log.Printf("Tenant quota exceeded: %v", err)
            // Handle quota issue
        } else {
            log.Printf("Upload failed: %v", err)
        }
        return
    }

    fmt.Println("Upload successful!")
}
```

### Example 4: Context and Timeout

```go
package main

import (
    "context"
    "fmt"
    "log"
    "strings"
    "time"

    "github.com/abiolaogu/MinIO/sdk/go/minio"
)

func main() {
    client, err := minio.NewClient(minio.Config{
        Endpoint: "http://localhost:9000",
        APIKey:   "your-api-key",
    })
    if err != nil {
        log.Fatalf("Failed to create client: %v", err)
    }
    defer client.Close()

    tenantID := "my-tenant"

    // Upload with timeout
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    data := strings.NewReader("test data")
    err = client.Upload(ctx, tenantID, "test.txt", data, nil)
    if err != nil {
        if ctx.Err() == context.DeadlineExceeded {
            log.Printf("Upload timed out after 5 seconds")
        } else {
            log.Printf("Upload failed: %v", err)
        }
        return
    }

    fmt.Println("Upload successful!")

    // Download with cancellation
    ctx2, cancel2 := context.WithCancel(context.Background())

    // Cancel after 2 seconds
    go func() {
        time.Sleep(2 * time.Second)
        cancel2()
    }()

    reader, err := client.Download(ctx2, tenantID, "large-file.bin")
    if err != nil {
        if ctx2.Err() == context.Canceled {
            log.Printf("Download was cancelled")
        } else {
            log.Printf("Download failed: %v", err)
        }
        return
    }
    defer reader.Close()

    // Process downloaded data...
}
```

## Best Practices

### 1. Always Close the Client

```go
client, err := minio.NewClient(config)
if err != nil {
    log.Fatal(err)
}
defer client.Close() // Important: Close to release resources
```

### 2. Use Context for Timeout and Cancellation

```go
ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
defer cancel()

err := client.Upload(ctx, tenantID, key, data, nil)
```

### 3. Handle Errors Appropriately

```go
err := client.Upload(ctx, tenantID, key, data, nil)
if err != nil {
    // Log error with context
    log.Printf("Upload failed for tenant=%s, key=%s: %v", tenantID, key, err)
    // Handle error appropriately
}
```

### 4. Reuse Client Instances

```go
// Good: Create one client and reuse it
var globalClient *minio.Client

func init() {
    var err error
    globalClient, err = minio.NewClient(config)
    if err != nil {
        log.Fatal(err)
    }
}

// Bad: Creating a new client for each request
func uploadFile() {
    client, _ := minio.NewClient(config) // Don't do this!
    client.Upload(...)
}
```

### 5. Use Connection Pooling

```go
// Configure HTTP transport for optimal performance
client, err := minio.NewClient(minio.Config{
    Endpoint: "http://localhost:9000",
    APIKey:   "your-api-key",
    Transport: &http.Transport{
        MaxIdleConns:        100,              // Total idle connections
        MaxIdleConnsPerHost: 10,               // Idle connections per host
        IdleConnTimeout:     90 * time.Second, // Idle timeout
    },
})
```

### 6. Monitor Quota Usage

```go
quota, err := client.GetQuota(ctx, tenantID)
if err != nil {
    log.Printf("Failed to get quota: %v", err)
    return
}

if quota.Percentage > 80.0 {
    log.Printf("Warning: Tenant %s is at %.2f%% quota usage", tenantID, quota.Percentage)
    // Send alert or take action
}
```

## Testing

Run the test suite:

```bash
cd sdk/go/minio
go test -v
```

Run tests with race detector:

```bash
go test -race -v
```

Run benchmarks:

```bash
go test -bench=. -benchmem
```

## Performance Tips

1. **Connection Pooling**: Reuse client instances to benefit from connection pooling
2. **Concurrent Uploads**: Use goroutines for concurrent uploads of multiple files
3. **Context Timeout**: Set appropriate timeouts to prevent hanging requests
4. **Buffer Size**: Use appropriate buffer sizes when reading/writing large files
5. **Retry Configuration**: Tune retry settings based on your network conditions

## Error Handling

The SDK returns standard Go errors. Common error scenarios:

- **Network Errors**: Connection failures, timeouts
- **HTTP Errors**: 4xx (client errors), 5xx (server errors)
- **Validation Errors**: Invalid parameters (empty tenant ID, key, etc.)
- **Quota Errors**: Tenant quota exceeded

Example:

```go
err := client.Upload(ctx, tenantID, key, data, nil)
if err != nil {
    if strings.Contains(err.Error(), "quota exceeded") {
        // Handle quota error
    } else if strings.Contains(err.Error(), "status 500") {
        // Handle server error
    } else {
        // Handle other errors
    }
}
```

## Troubleshooting

### Connection Refused

```
Error: request failed: dial tcp 127.0.0.1:9000: connect: connection refused
```

**Solution**: Ensure the MinIO server is running and accessible at the configured endpoint.

### Authentication Failed

```
Error: request failed with status 403: unauthorized
```

**Solution**: Verify that your API key is correct and has the necessary permissions.

### Timeout Errors

```
Error: context deadline exceeded
```

**Solution**: Increase the timeout in the client configuration or context timeout.

### Rate Limiting

```
Error: request failed with status 429: too many requests
```

**Solution**: The SDK automatically retries rate-limited requests. If this persists, reduce request rate.

## Support

- **Documentation**: [MinIO Enterprise Docs](https://github.com/abiolaogu/MinIO/tree/main/docs)
- **Issues**: [GitHub Issues](https://github.com/abiolaogu/MinIO/issues)
- **Discussions**: [GitHub Discussions](https://github.com/abiolaogu/MinIO/discussions)

## License

Apache License 2.0 - See [LICENSE](../../LICENSE) file for details.

## Contributing

Contributions are welcome! Please read our [Contributing Guide](../../CONTRIBUTING.md) for details.
