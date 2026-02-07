package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"strings"

	minio "github.com/abiolaogu/MinIO/sdk/go"
)

func main() {
	// Create a new MinIO Enterprise client
	client, err := minio.NewClient(minio.Config{
		BaseURL:  "http://localhost:9000",
		TenantID: "550e8400-e29b-41d4-a716-446655440000",
	})
	if err != nil {
		log.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	ctx := context.Background()

	// Example 1: Upload a text object
	fmt.Println("=== Example 1: Upload a text object ===")
	text := "Hello, MinIO Enterprise! This is a test file."
	data := strings.NewReader(text)

	uploadResp, err := client.Upload(ctx, "hello.txt", data)
	if err != nil {
		log.Fatalf("Upload failed: %v", err)
	}

	fmt.Printf("✓ Uploaded successfully\n")
	fmt.Printf("  Key: %s\n", uploadResp.Key)
	fmt.Printf("  Size: %d bytes\n", uploadResp.Size)
	fmt.Printf("  Status: %s\n\n", uploadResp.Status)

	// Example 2: Download the object
	fmt.Println("=== Example 2: Download the object ===")
	reader, err := client.Download(ctx, "hello.txt")
	if err != nil {
		log.Fatalf("Download failed: %v", err)
	}
	defer reader.Close()

	content, err := io.ReadAll(reader)
	if err != nil {
		log.Fatalf("Failed to read content: %v", err)
	}

	fmt.Printf("✓ Downloaded successfully\n")
	fmt.Printf("  Content: %s\n\n", string(content))

	// Example 3: Get server information
	fmt.Println("=== Example 3: Server Information ===")
	info, err := client.GetServerInfo(ctx)
	if err != nil {
		log.Fatalf("Failed to get server info: %v", err)
	}

	fmt.Printf("✓ Server Info:\n")
	fmt.Printf("  Status: %s\n", info.Status)
	fmt.Printf("  Version: %s\n", info.Version)
	fmt.Printf("  Performance: %s improvement\n\n", info.Performance)

	// Example 4: Health check
	fmt.Println("=== Example 4: Health Check ===")
	if err := client.HealthCheck(ctx); err != nil {
		log.Fatalf("Health check failed: %v", err)
	}
	fmt.Println("✓ Service is healthy!\n")

	fmt.Println("All examples completed successfully!")
}
