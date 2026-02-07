# MinIO Enterprise Go SDK

Official Go SDK for MinIO Enterprise - Ultra-High-Performance Object Storage.

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
	// Create a new MinIO client
	client, err := minio.NewClient(minio.Config{
		BaseURL: "http://localhost:9000",
		APIKey:  "your-api-key-here",
	})
	if err != nil {
		log.Fatal(err)
	}

	ctx := context.Background()

	// Upload a file
	uploadResp, err := client.Upload(ctx, minio.UploadRequest{
		TenantID: "tenant-123",
		ObjectID: "my-file.txt",
		Data:     strings.NewReader("Hello, MinIO!"),
		Size:     13,
	})
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Uploaded: %s\n", uploadResp.Message)

	// Download a file
	downloadResp, err := client.Download(ctx, minio.DownloadRequest{
		TenantID: "tenant-123",
		ObjectID: "my-file.txt",
	})
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Downloaded %d bytes\n", downloadResp.Size)

	// List objects
	listResp, err := client.List(ctx, minio.ListRequest{
		TenantID: "tenant-123",
		Limit:    10,
	})
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Found %d objects\n", listResp.Count)

	// Get quota information
	quotaResp, err := client.GetQuota(ctx, minio.QuotaRequest{
		TenantID: "tenant-123",
	})
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Quota: %d/%d bytes used\n", quotaResp.Used, quotaResp.Limit)

	// Delete a file
	deleteResp, err := client.Delete(ctx, minio.DeleteRequest{
		TenantID: "tenant-123",
		ObjectID: "my-file.txt",
	})
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Deleted: %s\n", deleteResp.Message)
}
```

## Features

- **Simple API**: Intuitive methods for all common operations
- **Automatic Retries**: Built-in exponential backoff retry logic
- **Connection Pooling**: Efficient HTTP connection reuse
- **Context Support**: Full support for Go contexts for cancellation and timeouts
- **Zero Dependencies**: No external dependencies required
- **Type Safety**: Strongly typed requests and responses

## API Reference

### Client Configuration

```go
config := minio.Config{
	BaseURL:    "http://localhost:9000", // MinIO API endpoint
	APIKey:     "your-api-key",          // API key for authentication
	Timeout:    30 * time.Second,        // Request timeout (default: 30s)
	MaxRetries: 3,                       // Maximum retry attempts (default: 3)
}

client, err := minio.NewClient(config)
```

### Upload File

```go
resp, err := client.Upload(ctx, minio.UploadRequest{
	TenantID: "tenant-123",
	ObjectID: "file.txt",
	Data:     reader,
	Size:     size,
})
```

### Download File

```go
resp, err := client.Download(ctx, minio.DownloadRequest{
	TenantID: "tenant-123",
	ObjectID: "file.txt",
})
// Access file data: resp.Data
```

### Delete File

```go
resp, err := client.Delete(ctx, minio.DeleteRequest{
	TenantID: "tenant-123",
	ObjectID: "file.txt",
})
```

### List Objects

```go
resp, err := client.List(ctx, minio.ListRequest{
	TenantID: "tenant-123",
	Prefix:   "folder/",    // Optional prefix filter
	Limit:    100,          // Optional limit (default: 100)
})
```

### Get Quota

```go
resp, err := client.GetQuota(ctx, minio.QuotaRequest{
	TenantID: "tenant-123",
})
```

### Health Check

```go
resp, err := client.HealthCheck(ctx)
```

## Error Handling

The SDK automatically retries failed requests with exponential backoff. All methods return errors that can be checked:

```go
resp, err := client.Upload(ctx, req)
if err != nil {
	// Handle error
	log.Printf("Upload failed: %v", err)
	return
}
```

## Examples

### Upload with Custom Timeout

```go
ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
defer cancel()

resp, err := client.Upload(ctx, minio.UploadRequest{
	TenantID: "tenant-123",
	ObjectID: "large-file.bin",
	Data:     fileReader,
	Size:     fileSize,
})
```

### List with Prefix Filter

```go
resp, err := client.List(ctx, minio.ListRequest{
	TenantID: "tenant-123",
	Prefix:   "images/2024/",
	Limit:    50,
})

for _, obj := range resp.Objects {
	fmt.Printf("Object: %s, Size: %d bytes\n", obj.ObjectID, obj.Size)
}
```

### Check Quota Before Upload

```go
quotaResp, err := client.GetQuota(ctx, minio.QuotaRequest{
	TenantID: "tenant-123",
})
if err != nil {
	return err
}

if quotaResp.Available < fileSize {
	return fmt.Errorf("insufficient quota: need %d bytes, have %d bytes",
		fileSize, quotaResp.Available)
}

// Proceed with upload
uploadResp, err := client.Upload(ctx, minio.UploadRequest{
	TenantID: "tenant-123",
	ObjectID: "file.txt",
	Data:     fileReader,
	Size:     fileSize,
})
```

## Advanced Usage

### Custom HTTP Client

```go
client, err := minio.NewClient(minio.Config{
	BaseURL: "http://localhost:9000",
	APIKey:  "your-api-key",
	Timeout: 60 * time.Second,
})

// The client uses connection pooling by default with:
// - MaxIdleConns: 100
// - MaxIdleConnsPerHost: 100
// - IdleConnTimeout: 90 seconds
```

### Batch Operations

```go
// Upload multiple files concurrently
var wg sync.WaitGroup
files := []string{"file1.txt", "file2.txt", "file3.txt"}

for _, filename := range files {
	wg.Add(1)
	go func(name string) {
		defer wg.Done()

		data, _ := os.Open(name)
		defer data.Close()

		_, err := client.Upload(ctx, minio.UploadRequest{
			TenantID: "tenant-123",
			ObjectID: name,
			Data:     data,
		})
		if err != nil {
			log.Printf("Failed to upload %s: %v", name, err)
		}
	}(filename)
}

wg.Wait()
```

## Testing

Run the SDK tests:

```bash
cd sdk/go
go test -v ./...
```

Run tests with race detector:

```bash
go test -race -v ./...
```

## Performance

The Go SDK is designed for high performance with:

- **Connection Pooling**: Reuses HTTP connections to reduce latency
- **Minimal Allocations**: Efficient memory usage
- **Automatic Retries**: Handles transient failures transparently
- **Context Cancellation**: Supports request cancellation and timeouts

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Run `go test -v ./...` to ensure tests pass
5. Submit a pull request

## License

Apache License 2.0 - See [LICENSE](../../LICENSE) file for details.

## Support

- **Documentation**: [MinIO Enterprise Docs](../../docs/)
- **API Reference**: [API_REFERENCE.md](../../API_REFERENCE.md)
- **Issues**: [GitHub Issues](https://github.com/abiolaogu/MinIO/issues)

## Version

SDK Version: 1.0.0
Compatible with: MinIO Enterprise 2.0.0+
