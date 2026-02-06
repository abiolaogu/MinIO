// Package minio provides a Go SDK for MinIO Enterprise
package minio

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	// DefaultTimeout is the default timeout for HTTP requests
	DefaultTimeout = 30 * time.Second

	// DefaultMaxRetries is the default number of retry attempts
	DefaultMaxRetries = 3

	// DefaultBackoffMultiplier is the default backoff multiplier for retries
	DefaultBackoffMultiplier = 2
)

// Client is the MinIO Enterprise SDK client
type Client struct {
	endpoint   string
	apiKey     string
	httpClient *http.Client
	maxRetries int
	backoff    time.Duration
}

// Config contains configuration options for the MinIO client
type Config struct {
	// Endpoint is the MinIO server endpoint (e.g., "http://localhost:9000")
	Endpoint string

	// APIKey is the authentication API key
	APIKey string

	// Timeout is the HTTP client timeout (default: 30s)
	Timeout time.Duration

	// MaxRetries is the maximum number of retry attempts (default: 3)
	MaxRetries int

	// BackoffDuration is the initial backoff duration for retries (default: 1s)
	BackoffDuration time.Duration

	// Transport allows customizing the HTTP transport
	Transport http.RoundTripper
}

// NewClient creates a new MinIO Enterprise client
func NewClient(config Config) (*Client, error) {
	if config.Endpoint == "" {
		return nil, fmt.Errorf("endpoint is required")
	}

	if config.APIKey == "" {
		return nil, fmt.Errorf("API key is required")
	}

	// Set defaults
	if config.Timeout == 0 {
		config.Timeout = DefaultTimeout
	}

	if config.MaxRetries == 0 {
		config.MaxRetries = DefaultMaxRetries
	}

	if config.BackoffDuration == 0 {
		config.BackoffDuration = time.Second
	}

	// Create HTTP client
	transport := config.Transport
	if transport == nil {
		transport = &http.Transport{
			MaxIdleConns:        100,
			MaxIdleConnsPerHost: 10,
			IdleConnTimeout:     90 * time.Second,
		}
	}

	httpClient := &http.Client{
		Timeout:   config.Timeout,
		Transport: transport,
	}

	return &Client{
		endpoint:   strings.TrimSuffix(config.Endpoint, "/"),
		apiKey:     config.APIKey,
		httpClient: httpClient,
		maxRetries: config.MaxRetries,
		backoff:    config.BackoffDuration,
	}, nil
}

// Object represents a MinIO object
type Object struct {
	Key          string    `json:"key"`
	Size         int64     `json:"size"`
	LastModified time.Time `json:"last_modified"`
	ContentType  string    `json:"content_type"`
	ETag         string    `json:"etag"`
}

// UploadOptions contains options for uploading objects
type UploadOptions struct {
	// ContentType specifies the MIME type of the object
	ContentType string

	// Metadata contains custom metadata key-value pairs
	Metadata map[string]string
}

// Upload uploads an object to MinIO
func (c *Client) Upload(ctx context.Context, tenantID, key string, data io.Reader, opts *UploadOptions) error {
	if tenantID == "" {
		return fmt.Errorf("tenant ID is required")
	}

	if key == "" {
		return fmt.Errorf("object key is required")
	}

	if data == nil {
		return fmt.Errorf("data reader is required")
	}

	if opts == nil {
		opts = &UploadOptions{}
	}

	// Build request
	path := fmt.Sprintf("/upload?tenant_id=%s&key=%s", url.QueryEscape(tenantID), url.QueryEscape(key))

	return c.doWithRetry(ctx, "PUT", path, data, opts.ContentType, nil)
}

// Download downloads an object from MinIO
func (c *Client) Download(ctx context.Context, tenantID, key string) (io.ReadCloser, error) {
	if tenantID == "" {
		return nil, fmt.Errorf("tenant ID is required")
	}

	if key == "" {
		return nil, fmt.Errorf("object key is required")
	}

	path := fmt.Sprintf("/download?tenant_id=%s&key=%s", url.QueryEscape(tenantID), url.QueryEscape(key))

	req, err := c.newRequest(ctx, "GET", path, nil, "")
	if err != nil {
		return nil, err
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("download failed: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		return nil, fmt.Errorf("download failed with status %d: %s", resp.StatusCode, string(body))
	}

	return resp.Body, nil
}

// Delete deletes an object from MinIO
func (c *Client) Delete(ctx context.Context, tenantID, key string) error {
	if tenantID == "" {
		return fmt.Errorf("tenant ID is required")
	}

	if key == "" {
		return fmt.Errorf("object key is required")
	}

	path := fmt.Sprintf("/delete?tenant_id=%s&key=%s", url.QueryEscape(tenantID), url.QueryEscape(key))

	return c.doWithRetry(ctx, "DELETE", path, nil, "", nil)
}

// ListOptions contains options for listing objects
type ListOptions struct {
	// Prefix filters objects by key prefix
	Prefix string

	// MaxKeys limits the number of results (default: 1000)
	MaxKeys int
}

// ListResponse contains the list of objects
type ListResponse struct {
	Objects []Object `json:"objects"`
	Count   int      `json:"count"`
}

// List lists objects in a tenant's storage
func (c *Client) List(ctx context.Context, tenantID string, opts *ListOptions) (*ListResponse, error) {
	if tenantID == "" {
		return nil, fmt.Errorf("tenant ID is required")
	}

	if opts == nil {
		opts = &ListOptions{}
	}

	path := fmt.Sprintf("/list?tenant_id=%s", url.QueryEscape(tenantID))

	if opts.Prefix != "" {
		path += fmt.Sprintf("&prefix=%s", url.QueryEscape(opts.Prefix))
	}

	if opts.MaxKeys > 0 {
		path += fmt.Sprintf("&max_keys=%d", opts.MaxKeys)
	}

	var listResp ListResponse
	if err := c.doWithRetry(ctx, "GET", path, nil, "", &listResp); err != nil {
		return nil, err
	}

	return &listResp, nil
}

// QuotaInfo contains tenant quota information
type QuotaInfo struct {
	TenantID   string `json:"tenant_id"`
	Used       int64  `json:"used"`
	Limit      int64  `json:"limit"`
	Percentage float64 `json:"percentage"`
}

// GetQuota retrieves the quota information for a tenant
func (c *Client) GetQuota(ctx context.Context, tenantID string) (*QuotaInfo, error) {
	if tenantID == "" {
		return nil, fmt.Errorf("tenant ID is required")
	}

	path := fmt.Sprintf("/quota?tenant_id=%s", url.QueryEscape(tenantID))

	var quota QuotaInfo
	if err := c.doWithRetry(ctx, "GET", path, nil, "", &quota); err != nil {
		return nil, err
	}

	return &quota, nil
}

// HealthStatus contains the health status of the MinIO service
type HealthStatus struct {
	Status    string `json:"status"`
	Timestamp string `json:"timestamp"`
}

// Health checks the health of the MinIO service
func (c *Client) Health(ctx context.Context) (*HealthStatus, error) {
	var health HealthStatus
	if err := c.doWithRetry(ctx, "GET", "/health", nil, "", &health); err != nil {
		return nil, err
	}

	return &health, nil
}

// doWithRetry executes an HTTP request with retry logic
func (c *Client) doWithRetry(ctx context.Context, method, path string, body io.Reader, contentType string, result interface{}) error {
	var lastErr error
	backoff := c.backoff

	for attempt := 0; attempt <= c.maxRetries; attempt++ {
		if attempt > 0 {
			// Wait before retrying
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(backoff):
			}

			// Exponential backoff
			backoff *= DefaultBackoffMultiplier
		}

		// Create request
		var bodyReader io.Reader
		if body != nil {
			// For retries, we need to be able to re-read the body
			// In production, consider using a seeker or buffering
			if seeker, ok := body.(io.Seeker); ok {
				seeker.Seek(0, io.SeekStart)
				bodyReader = body
			} else {
				bodyReader = body
			}
		}

		req, err := c.newRequest(ctx, method, path, bodyReader, contentType)
		if err != nil {
			lastErr = err
			continue
		}

		resp, err := c.httpClient.Do(req)
		if err != nil {
			lastErr = fmt.Errorf("request failed: %w", err)
			continue
		}

		defer resp.Body.Close()

		// Check if we should retry based on status code
		if c.shouldRetry(resp.StatusCode) {
			respBody, _ := io.ReadAll(resp.Body)
			lastErr = fmt.Errorf("request failed with status %d: %s", resp.StatusCode, string(respBody))
			continue
		}

		// Success - parse response if result is provided
		if result != nil && resp.StatusCode == http.StatusOK {
			respBody, err := io.ReadAll(resp.Body)
			if err != nil {
				return fmt.Errorf("failed to read response: %w", err)
			}

			if err := json.Unmarshal(respBody, result); err != nil {
				return fmt.Errorf("failed to parse response: %w", err)
			}
		}

		// Check for non-200 status codes that shouldn't be retried
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			respBody, _ := io.ReadAll(resp.Body)
			return fmt.Errorf("request failed with status %d: %s", resp.StatusCode, string(respBody))
		}

		return nil
	}

	return fmt.Errorf("max retries exceeded: %w", lastErr)
}

// newRequest creates a new HTTP request
func (c *Client) newRequest(ctx context.Context, method, path string, body io.Reader, contentType string) (*http.Request, error) {
	url := c.endpoint + path

	req, err := http.NewRequestWithContext(ctx, method, url, body)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// Set headers
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	} else if body != nil {
		req.Header.Set("Content-Type", "application/octet-stream")
	}

	return req, nil
}

// shouldRetry determines if a request should be retried based on status code
func (c *Client) shouldRetry(statusCode int) bool {
	// Retry on server errors and rate limiting
	return statusCode == http.StatusTooManyRequests ||
		statusCode == http.StatusServiceUnavailable ||
		statusCode == http.StatusGatewayTimeout ||
		statusCode >= 500
}

// Close closes the client and releases resources
func (c *Client) Close() error {
	// Close idle connections
	if transport, ok := c.httpClient.Transport.(*http.Transport); ok {
		transport.CloseIdleConnections()
	}
	return nil
}
