package minio

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
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
				Endpoint: "http://localhost:9000",
				APIKey:   "test-api-key",
			},
			wantErr: false,
		},
		{
			name: "missing endpoint",
			config: Config{
				APIKey: "test-api-key",
			},
			wantErr: true,
		},
		{
			name: "missing api key",
			config: Config{
				Endpoint: "http://localhost:9000",
			},
			wantErr: true,
		},
		{
			name: "custom timeout",
			config: Config{
				Endpoint: "http://localhost:9000",
				APIKey:   "test-api-key",
				Timeout:  10 * time.Second,
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
			if !tt.wantErr && client == nil {
				t.Error("NewClient() returned nil client")
			}
		})
	}
}

func TestClient_Upload(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "PUT" {
			t.Errorf("Expected PUT request, got %s", r.Method)
		}

		// Check authorization header
		auth := r.Header.Get("Authorization")
		if auth != "Bearer test-api-key" {
			t.Errorf("Expected Authorization header 'Bearer test-api-key', got %s", auth)
		}

		// Check query parameters
		tenantID := r.URL.Query().Get("tenant_id")
		key := r.URL.Query().Get("key")

		if tenantID != "tenant1" {
			t.Errorf("Expected tenant_id 'tenant1', got %s", tenantID)
		}

		if key != "test.txt" {
			t.Errorf("Expected key 'test.txt', got %s", key)
		}

		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client, err := NewClient(Config{
		Endpoint: server.URL,
		APIKey:   "test-api-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	data := bytes.NewReader([]byte("test data"))
	err = client.Upload(context.Background(), "tenant1", "test.txt", data, nil)
	if err != nil {
		t.Errorf("Upload() error = %v", err)
	}
}

func TestClient_Download(t *testing.T) {
	expectedData := []byte("test file content")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("Expected GET request, got %s", r.Method)
		}

		// Check authorization header
		auth := r.Header.Get("Authorization")
		if auth != "Bearer test-api-key" {
			t.Errorf("Expected Authorization header 'Bearer test-api-key', got %s", auth)
		}

		w.WriteHeader(http.StatusOK)
		w.Write(expectedData)
	}))
	defer server.Close()

	client, err := NewClient(Config{
		Endpoint: server.URL,
		APIKey:   "test-api-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	reader, err := client.Download(context.Background(), "tenant1", "test.txt")
	if err != nil {
		t.Fatalf("Download() error = %v", err)
	}
	defer reader.Close()

	data, err := io.ReadAll(reader)
	if err != nil {
		t.Fatalf("Failed to read downloaded data: %v", err)
	}

	if !bytes.Equal(data, expectedData) {
		t.Errorf("Downloaded data = %s, want %s", string(data), string(expectedData))
	}
}

func TestClient_Delete(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "DELETE" {
			t.Errorf("Expected DELETE request, got %s", r.Method)
		}

		// Check authorization header
		auth := r.Header.Get("Authorization")
		if auth != "Bearer test-api-key" {
			t.Errorf("Expected Authorization header 'Bearer test-api-key', got %s", auth)
		}

		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client, err := NewClient(Config{
		Endpoint: server.URL,
		APIKey:   "test-api-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	err = client.Delete(context.Background(), "tenant1", "test.txt")
	if err != nil {
		t.Errorf("Delete() error = %v", err)
	}
}

func TestClient_List(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("Expected GET request, got %s", r.Method)
		}

		// Check authorization header
		auth := r.Header.Get("Authorization")
		if auth != "Bearer test-api-key" {
			t.Errorf("Expected Authorization header 'Bearer test-api-key', got %s", auth)
		}

		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"objects":[{"key":"test1.txt","size":100},{"key":"test2.txt","size":200}],"count":2}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		Endpoint: server.URL,
		APIKey:   "test-api-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	resp, err := client.List(context.Background(), "tenant1", nil)
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}

	if resp.Count != 2 {
		t.Errorf("List() count = %d, want 2", resp.Count)
	}

	if len(resp.Objects) != 2 {
		t.Errorf("List() objects length = %d, want 2", len(resp.Objects))
	}
}

func TestClient_GetQuota(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("Expected GET request, got %s", r.Method)
		}

		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"tenant_id":"tenant1","used":1000,"limit":10000,"percentage":10.0}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		Endpoint: server.URL,
		APIKey:   "test-api-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	quota, err := client.GetQuota(context.Background(), "tenant1")
	if err != nil {
		t.Fatalf("GetQuota() error = %v", err)
	}

	if quota.TenantID != "tenant1" {
		t.Errorf("GetQuota() tenant_id = %s, want tenant1", quota.TenantID)
	}

	if quota.Used != 1000 {
		t.Errorf("GetQuota() used = %d, want 1000", quota.Used)
	}

	if quota.Limit != 10000 {
		t.Errorf("GetQuota() limit = %d, want 10000", quota.Limit)
	}
}

func TestClient_Health(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("Expected GET request, got %s", r.Method)
		}

		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"healthy","timestamp":"2024-01-01T00:00:00Z"}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		Endpoint: server.URL,
		APIKey:   "test-api-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	health, err := client.Health(context.Background())
	if err != nil {
		t.Fatalf("Health() error = %v", err)
	}

	if health.Status != "healthy" {
		t.Errorf("Health() status = %s, want healthy", health.Status)
	}
}

func TestClient_Retry(t *testing.T) {
	attempts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		if attempts < 3 {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client, err := NewClient(Config{
		Endpoint:        server.URL,
		APIKey:          "test-api-key",
		MaxRetries:      3,
		BackoffDuration: 10 * time.Millisecond,
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}
	defer client.Close()

	err = client.Delete(context.Background(), "tenant1", "test.txt")
	if err != nil {
		t.Errorf("Delete() with retry error = %v", err)
	}

	if attempts != 3 {
		t.Errorf("Expected 3 attempts, got %d", attempts)
	}
}
