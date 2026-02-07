package minio

import (
	"context"
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
				BaseURL: "http://localhost:9000",
				APIKey:  "test-key",
			},
			wantErr: false,
		},
		{
			name: "valid config with custom timeout",
			config: Config{
				BaseURL:    "http://localhost:9000",
				APIKey:     "test-key",
				Timeout:    60 * time.Second,
				MaxRetries: 5,
			},
			wantErr: false,
		},
		{
			name: "missing base URL",
			config: Config{
				APIKey: "test-key",
			},
			wantErr: true,
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
				t.Error("NewClient() returned nil client without error")
			}
			if !tt.wantErr {
				// Check defaults are applied
				if client.timeout == 0 {
					t.Error("Client timeout not set")
				}
				if client.maxRetries == 0 {
					t.Error("Client maxRetries not set")
				}
			}
		})
	}
}

func TestUploadRequest_Validation(t *testing.T) {
	client, err := NewClient(Config{
		BaseURL: "http://localhost:9000",
		APIKey:  "test-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	tests := []struct {
		name    string
		req     UploadRequest
		wantErr bool
	}{
		{
			name: "valid request",
			req: UploadRequest{
				TenantID: "tenant-123",
				ObjectID: "file.txt",
				Data:     strings.NewReader("test data"),
				Size:     9,
			},
			wantErr: false,
		},
		{
			name: "missing tenant_id",
			req: UploadRequest{
				ObjectID: "file.txt",
				Data:     strings.NewReader("test data"),
				Size:     9,
			},
			wantErr: true,
		},
		{
			name: "missing object_id",
			req: UploadRequest{
				TenantID: "tenant-123",
				Data:     strings.NewReader("test data"),
				Size:     9,
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			_, err := client.Upload(ctx, tt.req)
			// We expect validation errors or network errors
			// Validation errors should occur immediately
			if tt.wantErr && err == nil {
				t.Error("Upload() expected validation error, got nil")
			}
			if !tt.wantErr && err != nil {
				// Network errors are expected in tests (no server)
				t.Logf("Upload() error = %v (expected in test environment)", err)
			}
		})
	}
}

func TestDownloadRequest_Validation(t *testing.T) {
	client, err := NewClient(Config{
		BaseURL: "http://localhost:9000",
		APIKey:  "test-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	tests := []struct {
		name    string
		req     DownloadRequest
		wantErr bool
	}{
		{
			name: "valid request",
			req: DownloadRequest{
				TenantID: "tenant-123",
				ObjectID: "file.txt",
			},
			wantErr: false,
		},
		{
			name: "missing tenant_id",
			req: DownloadRequest{
				ObjectID: "file.txt",
			},
			wantErr: true,
		},
		{
			name: "missing object_id",
			req: DownloadRequest{
				TenantID: "tenant-123",
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			_, err := client.Download(ctx, tt.req)
			if tt.wantErr && err == nil {
				t.Error("Download() expected validation error, got nil")
			}
			if !tt.wantErr && err != nil {
				// Network errors are expected in tests (no server)
				t.Logf("Download() error = %v (expected in test environment)", err)
			}
		})
	}
}

func TestDeleteRequest_Validation(t *testing.T) {
	client, err := NewClient(Config{
		BaseURL: "http://localhost:9000",
		APIKey:  "test-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	tests := []struct {
		name    string
		req     DeleteRequest
		wantErr bool
	}{
		{
			name: "valid request",
			req: DeleteRequest{
				TenantID: "tenant-123",
				ObjectID: "file.txt",
			},
			wantErr: false,
		},
		{
			name: "missing tenant_id",
			req: DeleteRequest{
				ObjectID: "file.txt",
			},
			wantErr: true,
		},
		{
			name: "missing object_id",
			req: DeleteRequest{
				TenantID: "tenant-123",
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			_, err := client.Delete(ctx, tt.req)
			if tt.wantErr && err == nil {
				t.Error("Delete() expected validation error, got nil")
			}
			if !tt.wantErr && err != nil {
				// Network errors are expected in tests (no server)
				t.Logf("Delete() error = %v (expected in test environment)", err)
			}
		})
	}
}

func TestListRequest_Validation(t *testing.T) {
	client, err := NewClient(Config{
		BaseURL: "http://localhost:9000",
		APIKey:  "test-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	tests := []struct {
		name    string
		req     ListRequest
		wantErr bool
	}{
		{
			name: "valid request",
			req: ListRequest{
				TenantID: "tenant-123",
				Limit:    10,
			},
			wantErr: false,
		},
		{
			name: "valid request with defaults",
			req: ListRequest{
				TenantID: "tenant-123",
			},
			wantErr: false,
		},
		{
			name: "missing tenant_id",
			req: ListRequest{
				Limit: 10,
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			_, err := client.List(ctx, tt.req)
			if tt.wantErr && err == nil {
				t.Error("List() expected validation error, got nil")
			}
			if !tt.wantErr && err != nil {
				// Network errors are expected in tests (no server)
				t.Logf("List() error = %v (expected in test environment)", err)
			}
		})
	}
}

func TestQuotaRequest_Validation(t *testing.T) {
	client, err := NewClient(Config{
		BaseURL: "http://localhost:9000",
		APIKey:  "test-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	tests := []struct {
		name    string
		req     QuotaRequest
		wantErr bool
	}{
		{
			name: "valid request",
			req: QuotaRequest{
				TenantID: "tenant-123",
			},
			wantErr: false,
		},
		{
			name:    "missing tenant_id",
			req:     QuotaRequest{},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			_, err := client.GetQuota(ctx, tt.req)
			if tt.wantErr && err == nil {
				t.Error("GetQuota() expected validation error, got nil")
			}
			if !tt.wantErr && err != nil {
				// Network errors are expected in tests (no server)
				t.Logf("GetQuota() error = %v (expected in test environment)", err)
			}
		})
	}
}

func TestContextCancellation(t *testing.T) {
	client, err := NewClient(Config{
		BaseURL: "http://localhost:9000",
		APIKey:  "test-key",
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	// Create a context that's already cancelled
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	// Try to make a request with cancelled context
	_, err = client.Upload(ctx, UploadRequest{
		TenantID: "tenant-123",
		ObjectID: "file.txt",
		Data:     strings.NewReader("test"),
		Size:     4,
	})

	if err == nil {
		t.Error("Expected error with cancelled context")
	}
	t.Logf("Got expected error with cancelled context: %v", err)
}

func TestClientConfiguration(t *testing.T) {
	client, err := NewClient(Config{
		BaseURL:    "http://localhost:9000",
		APIKey:     "test-key",
		Timeout:    60 * time.Second,
		MaxRetries: 5,
	})
	if err != nil {
		t.Fatalf("Failed to create client: %v", err)
	}

	if client.baseURL != "http://localhost:9000" {
		t.Errorf("baseURL = %v, want %v", client.baseURL, "http://localhost:9000")
	}

	if client.apiKey != "test-key" {
		t.Errorf("apiKey = %v, want %v", client.apiKey, "test-key")
	}

	if client.timeout != 60*time.Second {
		t.Errorf("timeout = %v, want %v", client.timeout, 60*time.Second)
	}

	if client.maxRetries != 5 {
		t.Errorf("maxRetries = %v, want %v", client.maxRetries, 5)
	}

	if client.httpClient == nil {
		t.Error("httpClient is nil")
	}
}
