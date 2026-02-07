// Example usage of MinIO Enterprise Go SDK
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
		BaseURL:    "http://localhost:9000",
		TenantID:   "550e8400-e29b-41d4-a716-446655440000",
		Timeout:    30 * time.Second,
		MaxRetries: 3,
		BaseDelay:  1 * time.Second,
	}

	// Create client
	client, err := minio.NewClient(config)
	if err != nil {
		log.Fatalf("Failed to create client: %v", err)
	}

	ctx := context.Background()

	// Example 1: Health check
	fmt.Println("=== Health Check ===")
	healthy, err := client.HealthCheck(ctx)
	if err != nil {
		log.Printf("Health check failed: %v", err)
	} else if healthy {
		fmt.Println("✓ Server is healthy")
	} else {
		fmt.Println("✗ Server is not healthy")
	}

	// Example 2: Get server info
	fmt.Println("\n=== Server Info ===")
	info, err := client.GetServerInfo(ctx)
	if err != nil {
		log.Printf("Failed to get server info: %v", err)
	} else {
		fmt.Printf("Status: %s\n", info.Status)
		fmt.Printf("Version: %s\n", info.Version)
		fmt.Printf("Performance: %s\n", info.Performance)
	}

	// Example 3: Upload objects
	fmt.Println("\n=== Upload Objects ===")
	files := map[string][]byte{
		"documents/report.txt":  []byte("Annual Report 2024"),
		"images/photo.jpg":      []byte("Binary image data..."),
		"config/settings.json":  []byte(`{"setting": "value"}`),
	}

	for key, data := range files {
		resp, err := client.Upload(ctx, key, data)
		if err != nil {
			log.Printf("✗ Failed to upload %s: %v", key, err)
			continue
		}
		fmt.Printf("✓ Uploaded: %s (%d bytes, status: %s)\n", resp.Key, resp.Size, resp.Status)
	}

	// Example 4: List objects
	fmt.Println("\n=== List Objects ===")
	keys, err := client.List(ctx, "")
	if err != nil {
		log.Printf("Failed to list objects: %v", err)
	} else {
		fmt.Printf("Found %d objects:\n", len(keys))
		for i, key := range keys {
			fmt.Printf("  %d. %s\n", i+1, key)
		}
	}

	// Example 5: List with prefix
	fmt.Println("\n=== List Objects with Prefix 'documents/' ===")
	docKeys, err := client.List(ctx, "documents/")
	if err != nil {
		log.Printf("Failed to list documents: %v", err)
	} else {
		fmt.Printf("Found %d documents:\n", len(docKeys))
		for i, key := range docKeys {
			fmt.Printf("  %d. %s\n", i+1, key)
		}
	}

	// Example 6: Download objects
	fmt.Println("\n=== Download Objects ===")
	for key := range files {
		data, err := client.Download(ctx, key)
		if err != nil {
			log.Printf("✗ Failed to download %s: %v", key, err)
			continue
		}
		fmt.Printf("✓ Downloaded: %s (%d bytes)\n", key, len(data))

		// For text files, print a preview
		if len(data) < 100 {
			fmt.Printf("  Preview: %s\n", string(data))
		}
	}

	// Example 7: Delete objects
	fmt.Println("\n=== Delete Objects ===")
	for key := range files {
		err := client.Delete(ctx, key)
		if err != nil {
			log.Printf("✗ Failed to delete %s: %v", key, err)
			continue
		}
		fmt.Printf("✓ Deleted: %s\n", key)
	}

	// Example 8: Verify deletion
	fmt.Println("\n=== Verify Deletion ===")
	keysAfterDelete, err := client.List(ctx, "")
	if err != nil {
		log.Printf("Failed to list objects: %v", err)
	} else {
		fmt.Printf("Objects remaining: %d\n", len(keysAfterDelete))
	}

	fmt.Println("\n=== Example Complete ===")
}
