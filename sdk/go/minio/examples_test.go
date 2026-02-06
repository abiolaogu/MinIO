package minio_test

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	"github.com/abiolaogu/MinIO/sdk/go/minio"
)

// ExampleNewClient demonstrates how to create a new MinIO client
func ExampleNewClient() {
	client, err := minio.NewClient(&minio.Config{
		BaseURL:  "http://localhost:9000",
		TenantID: "550e8400-e29b-41d4-a716-446655440000",
	})
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("Client created for tenant: %s\n", client.GetTenantID())
	// Output: Client created for tenant: 550e8400-e29b-41d4-a716-446655440000
}

// ExampleClient_Upload demonstrates how to upload an object
func ExampleClient_Upload() {
	client, _ := minio.NewClient(&minio.Config{
		BaseURL:  "http://localhost:9000",
		TenantID: "550e8400-e29b-41d4-a716-446655440000",
	})

	ctx := context.Background()
	data := bytes.NewReader([]byte("Hello, MinIO Enterprise!"))

	resp, err := client.Upload(ctx, "hello.txt", data)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("Uploaded: %s (status: %s, size: %d bytes)\n", resp.Key, resp.Status, resp.Size)
}

// ExampleClient_Download demonstrates how to download an object
func ExampleClient_Download() {
	client, _ := minio.NewClient(&minio.Config{
		BaseURL:  "http://localhost:9000",
		TenantID: "550e8400-e29b-41d4-a716-446655440000",
	})

	ctx := context.Background()

	reader, err := client.Download(ctx, "hello.txt")
	if err != nil {
		log.Fatal(err)
	}
	defer reader.Close()

	data, err := io.ReadAll(reader)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("Downloaded: %s\n", string(data))
}

// ExampleClient_Delete demonstrates how to delete an object
func ExampleClient_Delete() {
	client, _ := minio.NewClient(&minio.Config{
		BaseURL:  "http://localhost:9000",
		TenantID: "550e8400-e29b-41d4-a716-446655440000",
	})

	ctx := context.Background()

	err := client.Delete(ctx, "hello.txt")
	if err != nil {
		log.Fatal(err)
	}

	fmt.Println("Object deleted successfully")
}

// ExampleClient_GetServerInfo demonstrates how to get server information
func ExampleClient_GetServerInfo() {
	client, _ := minio.NewClient(&minio.Config{
		BaseURL:  "http://localhost:9000",
		TenantID: "550e8400-e29b-41d4-a716-446655440000",
	})

	ctx := context.Background()

	info, err := client.GetServerInfo(ctx)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("Server: %s, Version: %s, Performance: %s\n", info.Status, info.Version, info.Performance)
}

// ExampleClient_HealthCheck demonstrates how to check server health
func ExampleClient_HealthCheck() {
	client, _ := minio.NewClient(&minio.Config{
		BaseURL:  "http://localhost:9000",
		TenantID: "550e8400-e29b-41d4-a716-446655440000",
	})

	ctx := context.Background()

	err := client.HealthCheck(ctx)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Println("Server is healthy")
}

// ExampleClient_customHTTPClient demonstrates using a custom HTTP client
func ExampleClient_customHTTPClient() {
	customClient := &http.Client{
		Timeout: 60 * time.Second,
	}

	client, _ := minio.NewClient(&minio.Config{
		BaseURL:    "http://localhost:9000",
		TenantID:   "550e8400-e29b-41d4-a716-446655440000",
		HTTPClient: customClient,
		RetryMax:   5,
		RetryDelay: 2 * time.Second,
	})

	ctx := context.Background()
	data := bytes.NewReader([]byte("Custom client example"))

	_, err := client.Upload(ctx, "custom.txt", data)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Println("Upload successful with custom HTTP client")
}
