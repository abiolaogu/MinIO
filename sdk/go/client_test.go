package minio

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestNew(t *testing.T) {
	tests := []struct {
		name    string
		config  *Config
		wantErr bool
	}{
		{
			name: "valid config",
			config: &Config{
				Endpoint: "http://localhost:9000",
				APIKey:   "test-key",
				TenantID: "test-tenant",
			},
			wantErr: false,
		},
		{
			name: "missing endpoint",
			config: &Config{
				APIKey:   "test-key",
				TenantID: "test-tenant",
			},
			wantErr: true,
		},
		{
			name: "missing API key",
			config: &Config{
				Endpoint: "http://localhost:9000",
				TenantID: "test-tenant",
			},
			wantErr: true,
		},
		{
			name: "missing tenant ID",
			config: &Config{
				Endpoint: "http://localhost:9000",
				APIKey:   "test-key",
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			client, err := New(tt.config)
			if (err != nil) != tt.wantErr {
				t.Errorf("New() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !tt.wantErr && client == nil {
				t.Error("New() returned nil client for valid config")
			}
		})
	}
}

func TestClient_Upload(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "PUT" {
			t.Errorf("Expected PUT request, got %s", r.Method)
		}
		if r.Header.Get("X-API-Key") == "" {
			t.Error("Missing X-API-Key header")
		}
		if r.Header.Get("X-Tenant-ID") == "" {
			t.Error("Missing X-Tenant-ID header")
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client, err := New(&Config{
		Endpoint: server.URL,
		APIKey:   "test-key",
		TenantID: "test-tenant",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	ctx := context.Background()
	err = client.Upload(ctx, "test-bucket", "test-key", []byte("test data"))
	if err != nil {
		t.Errorf("Upload() error = %v", err)
	}
}

func TestClient_Download(t *testing.T) {
	expectedData := []byte("test data")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("Expected GET request, got %s", r.Method)
		}
		w.WriteHeader(http.StatusOK)
		w.Write(expectedData)
	}))
	defer server.Close()

	client, err := New(&Config{
		Endpoint: server.URL,
		APIKey:   "test-key",
		TenantID: "test-tenant",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	ctx := context.Background()
	data, err := client.Download(ctx, "test-bucket", "test-key")
	if err != nil {
		t.Errorf("Download() error = %v", err)
	}
	if string(data) != string(expectedData) {
		t.Errorf("Download() got %s, want %s", string(data), string(expectedData))
	}
}

func TestClient_Delete(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "DELETE" {
			t.Errorf("Expected DELETE request, got %s", r.Method)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client, err := New(&Config{
		Endpoint: server.URL,
		APIKey:   "test-key",
		TenantID: "test-tenant",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	ctx := context.Background()
	err = client.Delete(ctx, "test-bucket", "test-key")
	if err != nil {
		t.Errorf("Delete() error = %v", err)
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

	client, err := New(&Config{
		Endpoint: server.URL,
		APIKey:   "test-key",
		TenantID: "test-tenant",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	ctx := context.Background()
	health, err := client.Health(ctx)
	if err != nil {
		t.Errorf("Health() error = %v", err)
	}
	if health.Status != "healthy" {
		t.Errorf("Health() status = %s, want healthy", health.Status)
	}
}

func TestClient_RetryOnServerError(t *testing.T) {
	attempts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		if attempts < 3 {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client, err := New(&Config{
		Endpoint:     server.URL,
		APIKey:       "test-key",
		TenantID:     "test-tenant",
		MaxRetries:   3,
		RetryBackoff: 10 * time.Millisecond,
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	ctx := context.Background()
	err = client.Upload(ctx, "test-bucket", "test-key", []byte("test data"))
	if err != nil {
		t.Errorf("Upload() error = %v (attempts: %d)", err, attempts)
	}
	if attempts != 3 {
		t.Errorf("Expected 3 attempts, got %d", attempts)
	}
}

func TestClient_NoRetryOnClientError(t *testing.T) {
	attempts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte("bad request"))
	}))
	defer server.Close()

	client, err := New(&Config{
		Endpoint:     server.URL,
		APIKey:       "test-key",
		TenantID:     "test-tenant",
		MaxRetries:   3,
		RetryBackoff: 10 * time.Millisecond,
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	ctx := context.Background()
	err = client.Upload(ctx, "test-bucket", "test-key", []byte("test data"))
	if err == nil {
		t.Error("Upload() expected error, got nil")
	}
	if attempts != 1 {
		t.Errorf("Expected 1 attempt for client error, got %d", attempts)
	}
}
