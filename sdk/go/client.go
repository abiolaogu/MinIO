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

// Config holds the configuration for the MinIO client
type Config struct {
	Endpoint  string // MinIO server endpoint (e.g., "http://localhost:9000")
	APIKey    string // API key for authentication
	APISecret string // API secret for authentication
	TenantID  string // Tenant ID for multi-tenancy support
	Timeout   time.Duration
	// MaxRetries is the maximum number of retry attempts (default: 3)
	MaxRetries int
	// RetryBackoff is the initial backoff duration for retries (default: 100ms)
	RetryBackoff time.Duration
}

// Client is the MinIO Enterprise SDK client
type Client struct {
	config     *Config
	httpClient *http.Client
}

// New creates a new MinIO client with the provided configuration
func New(config *Config) (*Client, error) {
	if config.Endpoint == "" {
		return nil, fmt.Errorf("endpoint is required")
	}
	if config.APIKey == "" {
		return nil, fmt.Errorf("API key is required")
	}
	if config.TenantID == "" {
		return nil, fmt.Errorf("tenant ID is required")
	}

	// Set defaults
	if config.Timeout == 0 {
		config.Timeout = 30 * time.Second
	}
	if config.MaxRetries == 0 {
		config.MaxRetries = 3
	}
	if config.RetryBackoff == 0 {
		config.RetryBackoff = 100 * time.Millisecond
	}

	client := &Client{
		config: config,
		httpClient: &http.Client{
			Timeout: config.Timeout,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 10,
				IdleConnTimeout:     90 * time.Second,
			},
		},
	}

	return client, nil
}

// Upload uploads an object to MinIO
func (c *Client) Upload(ctx context.Context, bucket, key string, data []byte) error {
	uploadURL := fmt.Sprintf("%s/upload?tenant_id=%s&bucket=%s&key=%s",
		c.config.Endpoint, url.QueryEscape(c.config.TenantID),
		url.QueryEscape(bucket), url.QueryEscape(key))

	return c.retryOperation(ctx, func() error {
		req, err := http.NewRequestWithContext(ctx, "PUT", uploadURL, bytes.NewReader(data))
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		c.setAuthHeaders(req)
		req.Header.Set("Content-Type", "application/octet-stream")

		resp, err := c.httpClient.Do(req)
		if err != nil {
			return &RetryableError{err: err}
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			if resp.StatusCode >= 500 {
				return &RetryableError{err: fmt.Errorf("server error (%d): %s", resp.StatusCode, string(body))}
			}
			return fmt.Errorf("upload failed (%d): %s", resp.StatusCode, string(body))
		}

		return nil
	})
}

// Download downloads an object from MinIO
func (c *Client) Download(ctx context.Context, bucket, key string) ([]byte, error) {
	downloadURL := fmt.Sprintf("%s/download?tenant_id=%s&bucket=%s&key=%s",
		c.config.Endpoint, url.QueryEscape(c.config.TenantID),
		url.QueryEscape(bucket), url.QueryEscape(key))

	var data []byte
	err := c.retryOperation(ctx, func() error {
		req, err := http.NewRequestWithContext(ctx, "GET", downloadURL, nil)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		c.setAuthHeaders(req)

		resp, err := c.httpClient.Do(req)
		if err != nil {
			return &RetryableError{err: err}
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			if resp.StatusCode >= 500 {
				return &RetryableError{err: fmt.Errorf("server error (%d): %s", resp.StatusCode, string(body))}
			}
			return fmt.Errorf("download failed (%d): %s", resp.StatusCode, string(body))
		}

		data, err = io.ReadAll(resp.Body)
		if err != nil {
			return fmt.Errorf("failed to read response: %w", err)
		}

		return nil
	})

	return data, err
}

// Delete deletes an object from MinIO
func (c *Client) Delete(ctx context.Context, bucket, key string) error {
	deleteURL := fmt.Sprintf("%s/delete?tenant_id=%s&bucket=%s&key=%s",
		c.config.Endpoint, url.QueryEscape(c.config.TenantID),
		url.QueryEscape(bucket), url.QueryEscape(key))

	return c.retryOperation(ctx, func() error {
		req, err := http.NewRequestWithContext(ctx, "DELETE", deleteURL, nil)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		c.setAuthHeaders(req)

		resp, err := c.httpClient.Do(req)
		if err != nil {
			return &RetryableError{err: err}
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent {
			body, _ := io.ReadAll(resp.Body)
			if resp.StatusCode >= 500 {
				return &RetryableError{err: fmt.Errorf("server error (%d): %s", resp.StatusCode, string(body))}
			}
			return fmt.Errorf("delete failed (%d): %s", resp.StatusCode, string(body))
		}

		return nil
	})
}

// Object represents an object in MinIO
type Object struct {
	Key          string    `json:"key"`
	Size         int64     `json:"size"`
	LastModified time.Time `json:"last_modified"`
	ETag         string    `json:"etag"`
}

// List lists objects in a bucket with an optional prefix
func (c *Client) List(ctx context.Context, bucket, prefix string) ([]Object, error) {
	listURL := fmt.Sprintf("%s/list?tenant_id=%s&bucket=%s",
		c.config.Endpoint, url.QueryEscape(c.config.TenantID),
		url.QueryEscape(bucket))

	if prefix != "" {
		listURL += "&prefix=" + url.QueryEscape(prefix)
	}

	var objects []Object
	err := c.retryOperation(ctx, func() error {
		req, err := http.NewRequestWithContext(ctx, "GET", listURL, nil)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		c.setAuthHeaders(req)

		resp, err := c.httpClient.Do(req)
		if err != nil {
			return &RetryableError{err: err}
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			if resp.StatusCode >= 500 {
				return &RetryableError{err: fmt.Errorf("server error (%d): %s", resp.StatusCode, string(body))}
			}
			return fmt.Errorf("list failed (%d): %s", resp.StatusCode, string(body))
		}

		if err := json.NewDecoder(resp.Body).Decode(&objects); err != nil {
			return fmt.Errorf("failed to decode response: %w", err)
		}

		return nil
	})

	return objects, err
}

// QuotaInfo represents quota information for a tenant
type QuotaInfo struct {
	TenantID   string `json:"tenant_id"`
	Used       int64  `json:"used"`
	Limit      int64  `json:"limit"`
	Percentage float64 `json:"percentage"`
}

// GetQuota retrieves quota information for the tenant
func (c *Client) GetQuota(ctx context.Context) (*QuotaInfo, error) {
	quotaURL := fmt.Sprintf("%s/quota?tenant_id=%s",
		c.config.Endpoint, url.QueryEscape(c.config.TenantID))

	var quota QuotaInfo
	err := c.retryOperation(ctx, func() error {
		req, err := http.NewRequestWithContext(ctx, "GET", quotaURL, nil)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		c.setAuthHeaders(req)

		resp, err := c.httpClient.Do(req)
		if err != nil {
			return &RetryableError{err: err}
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			if resp.StatusCode >= 500 {
				return &RetryableError{err: fmt.Errorf("server error (%d): %s", resp.StatusCode, string(body))}
			}
			return fmt.Errorf("get quota failed (%d): %s", resp.StatusCode, string(body))
		}

		if err := json.NewDecoder(resp.Body).Decode(&quota); err != nil {
			return fmt.Errorf("failed to decode response: %w", err)
		}

		return nil
	})

	return &quota, err
}

// HealthStatus represents the health status of the MinIO service
type HealthStatus struct {
	Status    string            `json:"status"`
	Timestamp time.Time         `json:"timestamp"`
	Services  map[string]string `json:"services,omitempty"`
}

// Health checks the health status of the MinIO service
func (c *Client) Health(ctx context.Context) (*HealthStatus, error) {
	healthURL := fmt.Sprintf("%s/health", c.config.Endpoint)

	var health HealthStatus
	err := c.retryOperation(ctx, func() error {
		req, err := http.NewRequestWithContext(ctx, "GET", healthURL, nil)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		resp, err := c.httpClient.Do(req)
		if err != nil {
			return &RetryableError{err: err}
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			if resp.StatusCode >= 500 {
				return &RetryableError{err: fmt.Errorf("server error (%d): %s", resp.StatusCode, string(body))}
			}
			return fmt.Errorf("health check failed (%d): %s", resp.StatusCode, string(body))
		}

		if err := json.NewDecoder(resp.Body).Decode(&health); err != nil {
			return fmt.Errorf("failed to decode response: %w", err)
		}

		return nil
	})

	return &health, err
}

// setAuthHeaders sets authentication headers on the request
func (c *Client) setAuthHeaders(req *http.Request) {
	req.Header.Set("X-API-Key", c.config.APIKey)
	req.Header.Set("X-API-Secret", c.config.APISecret)
	req.Header.Set("X-Tenant-ID", c.config.TenantID)
}

// RetryableError indicates an error that should be retried
type RetryableError struct {
	err error
}

func (e *RetryableError) Error() string {
	return e.err.Error()
}

func (e *RetryableError) Unwrap() error {
	return e.err
}

// retryOperation executes an operation with exponential backoff retry
func (c *Client) retryOperation(ctx context.Context, operation func() error) error {
	var lastErr error
	backoff := c.config.RetryBackoff

	for attempt := 0; attempt <= c.config.MaxRetries; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(backoff):
				backoff *= 2 // Exponential backoff
			}
		}

		err := operation()
		if err == nil {
			return nil
		}

		lastErr = err

		// Check if error is retryable
		var retryableErr *RetryableError
		if !isRetryable(err) {
			return err
		}
	}

	return fmt.Errorf("operation failed after %d attempts: %w", c.config.MaxRetries+1, lastErr)
}

// isRetryable checks if an error should be retried
func isRetryable(err error) bool {
	var retryableErr *RetryableError
	return (err != nil && (retryableErr != nil ||
		// Also retry on context deadline exceeded if not final
		err == context.DeadlineExceeded))
}

// Close closes the client and releases resources
func (c *Client) Close() error {
	c.httpClient.CloseIdleConnections()
	return nil
}
