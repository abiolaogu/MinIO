package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"strings"
	"time"

	minio "github.com/abiolaogu/MinIO/sdk/go"
)

func main() {
	// Create a client with custom configuration
	client, err := minio.NewClient(minio.Config{
		BaseURL:    "http://localhost:9000",
		TenantID:   "550e8400-e29b-41d4-a716-446655440000",
		Timeout:    60 * time.Second, // Custom timeout
		MaxRetries: 5,                // Custom retry count
	})
	if err != nil {
		log.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	// Example 1: Upload with context timeout
	fmt.Println("=== Example 1: Upload with timeout ===")
	uploadWithTimeout(client)

	// Example 2: Error handling
	fmt.Println("\n=== Example 2: Error Handling ===")
	handleErrors(client)

	// Example 3: Context cancellation
	fmt.Println("\n=== Example 3: Context Cancellation ===")
	demonstrateCancellation(client)

	fmt.Println("\nAll advanced examples completed!")
}

func uploadWithTimeout(client *minio.Client) {
	// Create a context with 10 second timeout
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	data := strings.NewReader("This upload has a 10 second timeout")
	resp, err := client.Upload(ctx, "timeout-example.txt", data)

	if err == context.DeadlineExceeded {
		fmt.Println("✗ Upload timed out after 10 seconds")
		return
	}
	if err != nil {
		log.Printf("Upload failed: %v", err)
		return
	}

	fmt.Printf("✓ Uploaded with timeout: %s (%d bytes)\n", resp.Key, resp.Size)
}

func handleErrors(client *minio.Client) {
	ctx := context.Background()

	// Try to download a non-existent object
	reader, err := client.Download(ctx, "non-existent-file.txt")
	if err != nil {
		// Check if it's an API error
		if apiErr, ok := err.(*minio.APIError); ok {
			switch apiErr.StatusCode {
			case 404:
				fmt.Printf("✓ Correctly handled 404 error: %s\n", apiErr.Message)
			case 403:
				fmt.Printf("✗ Quota exceeded: %s\n", apiErr.Message)
			case 500:
				fmt.Printf("✗ Server error: %s\n", apiErr.Message)
			default:
				fmt.Printf("✗ API error %d: %s\n", apiErr.StatusCode, apiErr.Message)
			}
		} else {
			fmt.Printf("✗ Network or other error: %v\n", err)
		}
		return
	}
	defer reader.Close()

	fmt.Println("✗ Expected an error but download succeeded")
}

func demonstrateCancellation(client *minio.Client) {
	// Create a cancellable context
	ctx, cancel := context.WithCancel(context.Background())

	// Start an upload
	go func() {
		data := strings.NewReader("This upload will be cancelled")
		_, err := client.Upload(ctx, "cancelled.txt", data)
		if err == context.Canceled {
			fmt.Println("✓ Upload was successfully cancelled")
		} else if err != nil {
			fmt.Printf("Upload failed with different error: %v\n", err)
		}
	}()

	// Cancel after a short delay
	time.Sleep(100 * time.Millisecond)
	cancel()

	// Wait for goroutine to finish
	time.Sleep(200 * time.Millisecond)
}
