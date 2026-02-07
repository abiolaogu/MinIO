package minio

import (
	"bytes"
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
				Endpoint: "http://localhost:9000",
				APIKey:   "test-key",
			},
			wantErr: false,
		},
		{
			name:    "missing endpoint",
			config:  Config{},
			wantErr: true,
		},
		{
			name: "invalid endpoint URL",
			config: Config{
				Endpoint: "://invalid",
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := NewClient(tt.config)
			if (err != nil) != tt.wantErr {
				t.Errorf("NewClient() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestClient_Upload(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "PUT" {
			t.Errorf("Expected PUT request, got %s", r.Method)
		}
		if r.Header.Get("X-API-Key") != "test-key" {
			t.Errorf("Expected API key header, got %s", r.Header.Get("X-API-Key"))
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"key":"test.txt","etag":"abc123","size":11}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		Endpoint: server.URL,
		APIKey:   "test-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	data := strings.NewReader("hello world")
	resp, err := client.Upload(context.Background(), UploadRequest{
		TenantID: "tenant1",
		Key:      "test.txt",
		Data:     data,
		Size:     11,
	})

	if err != nil {
		t.Fatalf("Upload failed: %v", err)
	}

	if resp.Key != "test.txt" {
		t.Errorf("Expected key 'test.txt', got %s", resp.Key)
	}
	if resp.ETag != "abc123" {
		t.Errorf("Expected etag 'abc123', got %s", resp.ETag)
	}
	if resp.Size != 11 {
		t.Errorf("Expected size 11, got %d", resp.Size)
	}
}

func TestClient_Upload_Retry(t *testing.T) {
	attempts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		if attempts < 2 {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"key":"test.txt","etag":"abc123","size":11}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		Endpoint:  server.URL,
		APIKey:    "test-key",
		RetryMax:  3,
		RetryWait: 10 * time.Millisecond,
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	data := strings.NewReader("hello world")
	_, err = client.Upload(context.Background(), UploadRequest{
		TenantID: "tenant1",
		Key:      "test.txt",
		Data:     data,
		Size:     11,
	})

	if err != nil {
		t.Fatalf("Upload failed: %v", err)
	}

	if attempts != 2 {
		t.Errorf("Expected 2 attempts, got %d", attempts)
	}
}

func TestClient_Download(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("Expected GET request, got %s", r.Method)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("hello world"))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		Endpoint: server.URL,
		APIKey:   "test-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	reader, err := client.Download(context.Background(), DownloadRequest{
		TenantID: "tenant1",
		Key:      "test.txt",
	})
	if err != nil {
		t.Fatalf("Download failed: %v", err)
	}
	defer reader.Close()

	data, err := io.ReadAll(reader)
	if err != nil {
		t.Fatalf("Failed to read data: %v", err)
	}

	if string(data) != "hello world" {
		t.Errorf("Expected 'hello world', got %s", string(data))
	}
}

func TestClient_Delete(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "DELETE" {
			t.Errorf("Expected DELETE request, got %s", r.Method)
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()

	client, err := NewClient(Config{
		Endpoint: server.URL,
		APIKey:   "test-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	err = client.Delete(context.Background(), DeleteRequest{
		TenantID: "tenant1",
		Key:      "test.txt",
	})
	if err != nil {
		t.Fatalf("Delete failed: %v", err)
	}
}

func TestClient_List(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("Expected GET request, got %s", r.Method)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{
			"objects": [
				{"key":"file1.txt","size":100},
				{"key":"file2.txt","size":200}
			],
			"is_truncated": false
		}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		Endpoint: server.URL,
		APIKey:   "test-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	resp, err := client.List(context.Background(), ListRequest{
		TenantID: "tenant1",
		Prefix:   "file",
	})
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}

	if len(resp.Objects) != 2 {
		t.Errorf("Expected 2 objects, got %d", len(resp.Objects))
	}
	if resp.IsTruncated {
		t.Error("Expected is_truncated to be false")
	}
}

func TestClient_GetQuota(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("Expected GET request, got %s", r.Method)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{
			"tenant_id":"tenant1",
			"used":1000,
			"limit":10000,
			"objects":5
		}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		Endpoint: server.URL,
		APIKey:   "test-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	quota, err := client.GetQuota(context.Background(), "tenant1")
	if err != nil {
		t.Fatalf("GetQuota failed: %v", err)
	}

	if quota.TenantID != "tenant1" {
		t.Errorf("Expected tenant_id 'tenant1', got %s", quota.TenantID)
	}
	if quota.Used != 1000 {
		t.Errorf("Expected used 1000, got %d", quota.Used)
	}
	if quota.Limit != 10000 {
		t.Errorf("Expected limit 10000, got %d", quota.Limit)
	}
}

func TestClient_Health(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("Expected GET request, got %s", r.Method)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{
			"status":"healthy",
			"version":"2.0.0",
			"uptime":3600,
			"checks":{"database":"ok","cache":"ok"}
		}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		Endpoint: server.URL,
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	health, err := client.Health(context.Background())
	if err != nil {
		t.Fatalf("Health failed: %v", err)
	}

	if health.Status != "healthy" {
		t.Errorf("Expected status 'healthy', got %s", health.Status)
	}
	if health.Version != "2.0.0" {
		t.Errorf("Expected version '2.0.0', got %s", health.Version)
	}
}

func TestClient_ValidationErrors(t *testing.T) {
	client, _ := NewClient(Config{
		Endpoint: "http://localhost:9000",
		APIKey:   "test-key",
	})

	tests := []struct {
		name string
		fn   func() error
	}{
		{
			name: "upload missing tenant",
			fn: func() error {
				_, err := client.Upload(context.Background(), UploadRequest{
					Key:  "test.txt",
					Data: bytes.NewReader([]byte("test")),
				})
				return err
			},
		},
		{
			name: "upload missing key",
			fn: func() error {
				_, err := client.Upload(context.Background(), UploadRequest{
					TenantID: "tenant1",
					Data:     bytes.NewReader([]byte("test")),
				})
				return err
			},
		},
		{
			name: "download missing tenant",
			fn: func() error {
				_, err := client.Download(context.Background(), DownloadRequest{
					Key: "test.txt",
				})
				return err
			},
		},
		{
			name: "delete missing key",
			fn: func() error {
				return client.Delete(context.Background(), DeleteRequest{
					TenantID: "tenant1",
				})
			},
		},
		{
			name: "list missing tenant",
			fn: func() error {
				_, err := client.List(context.Background(), ListRequest{})
				return err
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.fn()
			if err == nil {
				t.Error("Expected error, got nil")
			}
		})
	}
}
