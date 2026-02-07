package minio

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestNewClient(t *testing.T) {
	tests := []struct {
		name    string
		config  Config
		wantErr bool
	}{
		{
			name: "valid config",
			config: Config{
				BaseURL:  "http://localhost:9000",
				TenantID: "test-tenant",
			},
			wantErr: false,
		},
		{
			name: "missing base URL",
			config: Config{
				TenantID: "test-tenant",
			},
			wantErr: true,
		},
		{
			name: "missing tenant ID",
			config: Config{
				BaseURL: "http://localhost:9000",
			},
			wantErr: true,
		},
		{
			name: "with custom timeout",
			config: Config{
				BaseURL:  "http://localhost:9000",
				TenantID: "test-tenant",
				Timeout:  60 * time.Second,
			},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			client, err := NewClient(tt.config)
			if (err != nil) != tt.wantErr {
				t.Errorf("NewClient() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if client != nil {
				defer client.Close()
			}
		})
	}
}

func TestUpload(t *testing.T) {
	// Create a test server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "PUT" {
			t.Errorf("Expected PUT request, got %s", r.Method)
		}

		if r.Header.Get("X-Tenant-ID") != "test-tenant" {
			t.Errorf("Expected X-Tenant-ID header, got %s", r.Header.Get("X-Tenant-ID"))
		}

		if r.URL.Path != "/upload" {
			t.Errorf("Expected /upload path, got %s", r.URL.Path)
		}

		key := r.URL.Query().Get("key")
		if key != "test.txt" {
			t.Errorf("Expected key=test.txt, got key=%s", key)
		}

		// Read body
		body, _ := io.ReadAll(r.Body)
		bodyStr := string(body)

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"uploaded","key":"test.txt","size":` + string(rune(len(bodyStr))) + `}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		BaseURL:  server.URL,
		TenantID: "test-tenant",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	data := strings.NewReader("test data")
	resp, err := client.Upload(context.Background(), "test.txt", data)
	if err != nil {
		t.Fatalf("Upload failed: %v", err)
	}

	if resp.Status != "uploaded" {
		t.Errorf("Expected status 'uploaded', got '%s'", resp.Status)
	}

	if resp.Key != "test.txt" {
		t.Errorf("Expected key 'test.txt', got '%s'", resp.Key)
	}
}

func TestDownload(t *testing.T) {
	testData := "Hello, MinIO!"

	// Create a test server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("Expected GET request, got %s", r.Method)
		}

		if r.Header.Get("X-Tenant-ID") != "test-tenant" {
			t.Errorf("Expected X-Tenant-ID header, got %s", r.Header.Get("X-Tenant-ID"))
		}

		if r.URL.Path != "/download" {
			t.Errorf("Expected /download path, got %s", r.URL.Path)
		}

		w.Header().Set("Content-Type", "application/octet-stream")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(testData))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		BaseURL:  server.URL,
		TenantID: "test-tenant",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	reader, err := client.Download(context.Background(), "test.txt")
	if err != nil {
		t.Fatalf("Download failed: %v", err)
	}
	defer reader.Close()

	data, err := io.ReadAll(reader)
	if err != nil {
		t.Fatalf("Failed to read data: %v", err)
	}

	if string(data) != testData {
		t.Errorf("Expected data '%s', got '%s'", testData, string(data))
	}
}

func TestGetServerInfo(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			t.Errorf("Expected / path, got %s", r.URL.Path)
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ok","version":"3.0.0","performance":"100x"}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		BaseURL:  server.URL,
		TenantID: "test-tenant",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	info, err := client.GetServerInfo(context.Background())
	if err != nil {
		t.Fatalf("GetServerInfo failed: %v", err)
	}

	if info.Status != "ok" {
		t.Errorf("Expected status 'ok', got '%s'", info.Status)
	}

	if info.Version != "3.0.0" {
		t.Errorf("Expected version '3.0.0', got '%s'", info.Version)
	}

	if info.Performance != "100x" {
		t.Errorf("Expected performance '100x', got '%s'", info.Performance)
	}
}

func TestHealthCheck(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/minio/health/ready" {
			t.Errorf("Expected /minio/health/ready path, got %s", r.URL.Path)
		}

		w.WriteHeader(http.StatusOK)
		w.Write([]byte("READY"))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		BaseURL:  server.URL,
		TenantID: "test-tenant",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	err = client.HealthCheck(context.Background())
	if err != nil {
		t.Errorf("HealthCheck failed: %v", err)
	}
}

func TestAPIError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusForbidden)
		w.Write([]byte(`{"error":"Quota exceeded"}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		BaseURL:  server.URL,
		TenantID: "test-tenant",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	data := strings.NewReader("test data")
	_, err = client.Upload(context.Background(), "test.txt", data)

	if err == nil {
		t.Fatal("Expected error, got nil")
	}

	apiErr, ok := err.(*APIError)
	if !ok {
		t.Fatalf("Expected APIError, got %T", err)
	}

	if apiErr.StatusCode != http.StatusForbidden {
		t.Errorf("Expected status code %d, got %d", http.StatusForbidden, apiErr.StatusCode)
	}

	if apiErr.Message != "Quota exceeded" {
		t.Errorf("Expected message 'Quota exceeded', got '%s'", apiErr.Message)
	}
}

func TestRetryLogic(t *testing.T) {
	attempts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		if attempts < 3 {
			// Fail the first 2 attempts with 500
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte(`{"error":"Internal server error"}`))
			return
		}

		// Succeed on the 3rd attempt
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"uploaded","key":"test.txt","size":9}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		BaseURL:    server.URL,
		TenantID:   "test-tenant",
		MaxRetries: 3,
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	data := strings.NewReader("test data")
	resp, err := client.Upload(context.Background(), "test.txt", data)
	if err != nil {
		t.Fatalf("Upload failed after retries: %v", err)
	}

	if attempts != 3 {
		t.Errorf("Expected 3 attempts, got %d", attempts)
	}

	if resp.Status != "uploaded" {
		t.Errorf("Expected status 'uploaded', got '%s'", resp.Status)
	}
}
