// Package minio provides an official Go SDK for MinIO Enterprise
// Ultra-high-performance object storage with 10-100x performance improvements
package minio

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

const (
	// DefaultTimeout is the default timeout for HTTP requests
	DefaultTimeout = 30 * time.Second

	// DefaultMaxRetries is the default maximum number of retries
	DefaultMaxRetries = 3

	// DefaultBaseDelay is the default base delay for exponential backoff
	DefaultBaseDelay = 1 * time.Second
)

// Client represents a MinIO Enterprise SDK client
type Client struct {
	baseURL    string
	tenantID   string
	httpClient *http.Client
	maxRetries int
	baseDelay  time.Duration
}

// Config contains configuration options for the MinIO client
type Config struct {
	// BaseURL is the MinIO server URL (e.g., "http://localhost:9000")
	BaseURL string

	// TenantID is the tenant identifier for multi-tenancy
	TenantID string

	// Timeout is the HTTP request timeout (default: 30s)
	Timeout time.Duration

	// MaxRetries is the maximum number of retry attempts (default: 3)
	MaxRetries int

	// BaseDelay is the base delay for exponential backoff (default: 1s)
	BaseDelay time.Duration

	// HTTPClient allows providing a custom HTTP client
	HTTPClient *http.Client
}

// NewClient creates a new MinIO client with the provided configuration
func NewClient(config Config) (*Client, error) {
	if config.BaseURL == "" {
		return nil, fmt.Errorf("base URL is required")
	}

	if config.TenantID == "" {
		return nil, fmt.Errorf("tenant ID is required")
	}

	// Set defaults
	if config.Timeout == 0 {
		config.Timeout = DefaultTimeout
	}

	if config.MaxRetries == 0 {
		config.MaxRetries = DefaultMaxRetries
	}

	if config.BaseDelay == 0 {
		config.BaseDelay = DefaultBaseDelay
	}

	// Create or use provided HTTP client
	httpClient := config.HTTPClient
	if httpClient == nil {
		httpClient = &http.Client{
			Timeout: config.Timeout,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 10,
				IdleConnTimeout:     90 * time.Second,
				DisableKeepAlives:   false,
			},
		}
	}

	return &Client{
		baseURL:    config.BaseURL,
		tenantID:   config.TenantID,
		httpClient: httpClient,
		maxRetries: config.MaxRetries,
		baseDelay:  config.BaseDelay,
	}, nil
}

// UploadResponse represents the response from an upload operation
type UploadResponse struct {
	Status string `json:"status"`
	Key    string `json:"key"`
	Size   int64  `json:"size"`
}

// ServerInfo represents server information
type ServerInfo struct {
	Status      string `json:"status"`
	Version     string `json:"version"`
	Performance string `json:"performance"`
}

// ErrorResponse represents an error response from the API
type ErrorResponse struct {
	Error string `json:"error"`
}

// Upload uploads an object to MinIO storage
//
// Parameters:
//   - ctx: Context for cancellation and timeouts
//   - key: Unique object key identifier
//   - data: Object data as byte slice
//
// Returns:
//   - UploadResponse containing upload status, key, and size
//   - error if the upload fails
//
// Example:
//
//	resp, err := client.Upload(ctx, "my-file.txt", []byte("Hello, World!"))
//	if err != nil {
//	    log.Fatal(err)
//	}
//	fmt.Printf("Uploaded %s: %d bytes\n", resp.Key, resp.Size)
func (c *Client) Upload(ctx context.Context, key string, data []byte) (*UploadResponse, error) {
	endpoint := fmt.Sprintf("%s/upload?key=%s", c.baseURL, url.QueryEscape(key))

	var resp *UploadResponse
	err := c.doWithRetry(ctx, func() error {
		req, err := http.NewRequestWithContext(ctx, http.MethodPut, endpoint, bytes.NewReader(data))
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		req.Header.Set("X-Tenant-ID", c.tenantID)
		req.Header.Set("Content-Type", "application/octet-stream")

		httpResp, err := c.httpClient.Do(req)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer httpResp.Body.Close()

		body, err := io.ReadAll(httpResp.Body)
		if err != nil {
			return fmt.Errorf("failed to read response: %w", err)
		}

		if httpResp.StatusCode != http.StatusOK {
			var errResp ErrorResponse
			if err := json.Unmarshal(body, &errResp); err == nil {
				return fmt.Errorf("upload failed: %s (status: %d)", errResp.Error, httpResp.StatusCode)
			}
			return fmt.Errorf("upload failed with status: %d", httpResp.StatusCode)
		}

		resp = &UploadResponse{}
		if err := json.Unmarshal(body, resp); err != nil {
			return fmt.Errorf("failed to parse response: %w", err)
		}

		return nil
	})

	return resp, err
}

// Download downloads an object from MinIO storage
//
// Parameters:
//   - ctx: Context for cancellation and timeouts
//   - key: Unique object key identifier
//
// Returns:
//   - Object data as byte slice
//   - error if the download fails
//
// Example:
//
//	data, err := client.Download(ctx, "my-file.txt")
//	if err != nil {
//	    log.Fatal(err)
//	}
//	fmt.Printf("Downloaded: %s\n", string(data))
func (c *Client) Download(ctx context.Context, key string) ([]byte, error) {
	endpoint := fmt.Sprintf("%s/download?key=%s", c.baseURL, url.QueryEscape(key))

	var data []byte
	err := c.doWithRetry(ctx, func() error {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		req.Header.Set("X-Tenant-ID", c.tenantID)

		httpResp, err := c.httpClient.Do(req)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer httpResp.Body.Close()

		if httpResp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(httpResp.Body)
			var errResp ErrorResponse
			if err := json.Unmarshal(body, &errResp); err == nil {
				return fmt.Errorf("download failed: %s (status: %d)", errResp.Error, httpResp.StatusCode)
			}
			return fmt.Errorf("download failed with status: %d", httpResp.StatusCode)
		}

		data, err = io.ReadAll(httpResp.Body)
		if err != nil {
			return fmt.Errorf("failed to read response: %w", err)
		}

		return nil
	})

	return data, err
}

// Delete deletes an object from MinIO storage
//
// Parameters:
//   - ctx: Context for cancellation and timeouts
//   - key: Unique object key identifier
//
// Returns:
//   - error if the deletion fails
//
// Example:
//
//	err := client.Delete(ctx, "my-file.txt")
//	if err != nil {
//	    log.Fatal(err)
//	}
//	fmt.Println("Object deleted successfully")
func (c *Client) Delete(ctx context.Context, key string) error {
	endpoint := fmt.Sprintf("%s/delete?key=%s", c.baseURL, url.QueryEscape(key))

	return c.doWithRetry(ctx, func() error {
		req, err := http.NewRequestWithContext(ctx, http.MethodDelete, endpoint, nil)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		req.Header.Set("X-Tenant-ID", c.tenantID)

		httpResp, err := c.httpClient.Do(req)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer httpResp.Body.Close()

		if httpResp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(httpResp.Body)
			var errResp ErrorResponse
			if err := json.Unmarshal(body, &errResp); err == nil {
				return fmt.Errorf("delete failed: %s (status: %d)", errResp.Error, httpResp.StatusCode)
			}
			return fmt.Errorf("delete failed with status: %d", httpResp.StatusCode)
		}

		return nil
	})
}

// List lists objects in MinIO storage (with optional prefix)
//
// Parameters:
//   - ctx: Context for cancellation and timeouts
//   - prefix: Optional prefix to filter objects (empty string for all)
//
// Returns:
//   - Slice of object keys
//   - error if the listing fails
//
// Example:
//
//	keys, err := client.List(ctx, "uploads/")
//	if err != nil {
//	    log.Fatal(err)
//	}
//	for _, key := range keys {
//	    fmt.Println(key)
//	}
func (c *Client) List(ctx context.Context, prefix string) ([]string, error) {
	endpoint := fmt.Sprintf("%s/list", c.baseURL)
	if prefix != "" {
		endpoint = fmt.Sprintf("%s?prefix=%s", endpoint, url.QueryEscape(prefix))
	}

	var keys []string
	err := c.doWithRetry(ctx, func() error {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		req.Header.Set("X-Tenant-ID", c.tenantID)

		httpResp, err := c.httpClient.Do(req)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer httpResp.Body.Close()

		if httpResp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(httpResp.Body)
			var errResp ErrorResponse
			if err := json.Unmarshal(body, &errResp); err == nil {
				return fmt.Errorf("list failed: %s (status: %d)", errResp.Error, httpResp.StatusCode)
			}
			return fmt.Errorf("list failed with status: %d", httpResp.StatusCode)
		}

		body, err := io.ReadAll(httpResp.Body)
		if err != nil {
			return fmt.Errorf("failed to read response: %w", err)
		}

		if err := json.Unmarshal(body, &keys); err != nil {
			return fmt.Errorf("failed to parse response: %w", err)
		}

		return nil
	})

	return keys, err
}

// GetServerInfo retrieves server information
//
// Parameters:
//   - ctx: Context for cancellation and timeouts
//
// Returns:
//   - ServerInfo containing status, version, and performance metrics
//   - error if the request fails
//
// Example:
//
//	info, err := client.GetServerInfo(ctx)
//	if err != nil {
//	    log.Fatal(err)
//	}
//	fmt.Printf("Server: %s (version: %s, performance: %s)\n",
//	    info.Status, info.Version, info.Performance)
func (c *Client) GetServerInfo(ctx context.Context) (*ServerInfo, error) {
	endpoint := fmt.Sprintf("%s/", c.baseURL)

	var info *ServerInfo
	err := c.doWithRetry(ctx, func() error {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		httpResp, err := c.httpClient.Do(req)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer httpResp.Body.Close()

		if httpResp.StatusCode != http.StatusOK {
			return fmt.Errorf("request failed with status: %d", httpResp.StatusCode)
		}

		body, err := io.ReadAll(httpResp.Body)
		if err != nil {
			return fmt.Errorf("failed to read response: %w", err)
		}

		info = &ServerInfo{}
		if err := json.Unmarshal(body, info); err != nil {
			return fmt.Errorf("failed to parse response: %w", err)
		}

		return nil
	})

	return info, err
}

// HealthCheck performs a health check on the MinIO server
//
// Parameters:
//   - ctx: Context for cancellation and timeouts
//
// Returns:
//   - true if the server is healthy, false otherwise
//   - error if the health check fails
//
// Example:
//
//	healthy, err := client.HealthCheck(ctx)
//	if err != nil {
//	    log.Fatal(err)
//	}
//	if healthy {
//	    fmt.Println("Server is healthy")
//	}
func (c *Client) HealthCheck(ctx context.Context) (bool, error) {
	endpoint := fmt.Sprintf("%s/health", c.baseURL)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return false, fmt.Errorf("failed to create request: %w", err)
	}

	httpResp, err := c.httpClient.Do(req)
	if err != nil {
		return false, fmt.Errorf("request failed: %w", err)
	}
	defer httpResp.Body.Close()

	return httpResp.StatusCode == http.StatusOK, nil
}

// doWithRetry executes a function with exponential backoff retry logic
func (c *Client) doWithRetry(ctx context.Context, fn func() error) error {
	var lastErr error

	for attempt := 0; attempt <= c.maxRetries; attempt++ {
		// Check if context is cancelled
		if ctx.Err() != nil {
			return ctx.Err()
		}

		// Execute the function
		lastErr = fn()
		if lastErr == nil {
			return nil
		}

		// Don't retry on last attempt
		if attempt == c.maxRetries {
			break
		}

		// Calculate exponential backoff delay
		delay := c.baseDelay * time.Duration(1<<uint(attempt))

		// Wait before retrying
		select {
		case <-time.After(delay):
			// Continue to next attempt
		case <-ctx.Done():
			return ctx.Err()
		}
	}

	return fmt.Errorf("operation failed after %d attempts: %w", c.maxRetries+1, lastErr)
}
