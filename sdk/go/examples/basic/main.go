// Package main demonstrates basic usage of the MinIO Enterprise Go SDK
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
	// Create a new MinIO client
	client, err := minio.NewClient(minio.Config{
		BaseURL:    "http://localhost:9000",
		APIKey:     "your-api-key-here",
		Timeout:    30 * time.Second,
		MaxRetries: 3,
	})
	if err != nil {
		log.Fatalf("Failed to create client: %v", err)
	}

	ctx := context.Background()

	// Example 1: Health Check
	fmt.Println("=== Health Check ===")
	healthResp, err := client.HealthCheck(ctx)
	if err != nil {
		log.Printf("Health check failed: %v", err)
	} else {
		fmt.Printf("Status: %s\n", healthResp.Status)
	}
	fmt.Println()

	// Example 2: Upload a file
	fmt.Println("=== Upload File ===")
	uploadResp, err := client.Upload(ctx, minio.UploadRequest{
		TenantID: "tenant-123",
		ObjectID: "example-file.txt",
		Data:     strings.NewReader("Hello, MinIO Enterprise!"),
		Size:     25,
	})
	if err != nil {
		log.Printf("Upload failed: %v", err)
	} else {
		fmt.Printf("Message: %s\n", uploadResp.Message)
		fmt.Printf("Size: %d bytes\n", uploadResp.Size)
	}
	fmt.Println()

	// Example 3: Download the file
	fmt.Println("=== Download File ===")
	downloadResp, err := client.Download(ctx, minio.DownloadRequest{
		TenantID: "tenant-123",
		ObjectID: "example-file.txt",
	})
	if err != nil {
		log.Printf("Download failed: %v", err)
	} else {
		fmt.Printf("Message: %s\n", downloadResp.Message)
		fmt.Printf("Size: %d bytes\n", downloadResp.Size)
		fmt.Printf("Data: %s\n", string(downloadResp.Data))
	}
	fmt.Println()

	// Example 4: List objects
	fmt.Println("=== List Objects ===")
	listResp, err := client.List(ctx, minio.ListRequest{
		TenantID: "tenant-123",
		Limit:    10,
	})
	if err != nil {
		log.Printf("List failed: %v", err)
	} else {
		fmt.Printf("Found %d objects:\n", listResp.Count)
		for i, obj := range listResp.Objects {
			fmt.Printf("  %d. %s (%d bytes)\n", i+1, obj.ObjectID, obj.Size)
		}
	}
	fmt.Println()

	// Example 5: Get quota information
	fmt.Println("=== Get Quota ===")
	quotaResp, err := client.GetQuota(ctx, minio.QuotaRequest{
		TenantID: "tenant-123",
	})
	if err != nil {
		log.Printf("Get quota failed: %v", err)
	} else {
		fmt.Printf("Used: %d bytes\n", quotaResp.Used)
		fmt.Printf("Limit: %d bytes\n", quotaResp.Limit)
		fmt.Printf("Available: %d bytes\n", quotaResp.Available)
		fmt.Printf("Usage: %.2f%%\n", float64(quotaResp.Used)/float64(quotaResp.Limit)*100)
	}
	fmt.Println()

	// Example 6: Delete the file
	fmt.Println("=== Delete File ===")
	deleteResp, err := client.Delete(ctx, minio.DeleteRequest{
		TenantID: "tenant-123",
		ObjectID: "example-file.txt",
	})
	if err != nil {
		log.Printf("Delete failed: %v", err)
	} else {
		fmt.Printf("Message: %s\n", deleteResp.Message)
	}
	fmt.Println()

	fmt.Println("All examples completed successfully!")
}
