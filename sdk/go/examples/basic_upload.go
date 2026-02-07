package main

import (
	"context"
	"fmt"
	"log"
	"os"

	minio "github.com/abiolaogu/MinIO/sdk/go"
)

func main() {
	// Initialize client with configuration from environment variables
	client, err := minio.New(&minio.Config{
		Endpoint:  getEnv("MINIO_ENDPOINT", "http://localhost:9000"),
		APIKey:    getEnv("MINIO_API_KEY", "your-api-key"),
		APISecret: getEnv("MINIO_API_SECRET", "your-api-secret"),
		TenantID:  getEnv("MINIO_TENANT_ID", "your-tenant-id"),
	})
	if err != nil {
		log.Fatalf("Failed to create MinIO client: %v", err)
	}
	defer client.Close()

	ctx := context.Background()

	// Example 1: Upload a simple text file
	fmt.Println("Example 1: Uploading a text file...")
	textData := []byte("Hello, MinIO Enterprise! This is a test file.")
	err = client.Upload(ctx, "my-bucket", "hello.txt", textData)
	if err != nil {
		log.Fatalf("Upload failed: %v", err)
	}
	fmt.Println("✓ Upload successful: hello.txt")

	// Example 2: Download the file
	fmt.Println("\nExample 2: Downloading the file...")
	data, err := client.Download(ctx, "my-bucket", "hello.txt")
	if err != nil {
		log.Fatalf("Download failed: %v", err)
	}
	fmt.Printf("✓ Download successful: %s\n", string(data))

	// Example 3: Upload multiple files
	fmt.Println("\nExample 3: Uploading multiple files...")
	files := map[string][]byte{
		"file1.txt": []byte("Content of file 1"),
		"file2.txt": []byte("Content of file 2"),
		"file3.txt": []byte("Content of file 3"),
	}

	for filename, content := range files {
		err = client.Upload(ctx, "my-bucket", filename, content)
		if err != nil {
			log.Printf("Failed to upload %s: %v", filename, err)
			continue
		}
		fmt.Printf("✓ Uploaded: %s\n", filename)
	}

	// Example 4: List all files in the bucket
	fmt.Println("\nExample 4: Listing all files in bucket...")
	objects, err := client.List(ctx, "my-bucket", "")
	if err != nil {
		log.Fatalf("List failed: %v", err)
	}
	fmt.Printf("✓ Found %d objects:\n", len(objects))
	for _, obj := range objects {
		fmt.Printf("  - %s (size: %d bytes, modified: %s)\n",
			obj.Key, obj.Size, obj.LastModified.Format("2006-01-02 15:04:05"))
	}

	// Example 5: Check quota
	fmt.Println("\nExample 5: Checking quota...")
	quota, err := client.GetQuota(ctx)
	if err != nil {
		log.Fatalf("Get quota failed: %v", err)
	}
	fmt.Printf("✓ Quota Info:\n")
	fmt.Printf("  - Used: %d bytes\n", quota.Used)
	fmt.Printf("  - Limit: %d bytes\n", quota.Limit)
	fmt.Printf("  - Usage: %.2f%%\n", quota.Percentage)

	// Example 6: Delete a file
	fmt.Println("\nExample 6: Deleting a file...")
	err = client.Delete(ctx, "my-bucket", "file3.txt")
	if err != nil {
		log.Fatalf("Delete failed: %v", err)
	}
	fmt.Println("✓ Delete successful: file3.txt")

	// Example 7: Health check
	fmt.Println("\nExample 7: Checking service health...")
	health, err := client.Health(ctx)
	if err != nil {
		log.Fatalf("Health check failed: %v", err)
	}
	fmt.Printf("✓ Service Status: %s (checked at: %s)\n",
		health.Status, health.Timestamp.Format("2006-01-02 15:04:05"))

	fmt.Println("\n✅ All examples completed successfully!")
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
