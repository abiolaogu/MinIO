// Package minio provides a Go SDK for MinIO Enterprise API
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
	// DefaultTimeout is the default HTTP timeout
	DefaultTimeout = 30 * time.Second
	// DefaultMaxRetries is the default number of retries
	DefaultMaxRetries = 3
)

// Client is the MinIO Enterprise SDK client
type Client struct {
	BaseURL    string
	HTTPClient *http.Client
	TenantID   string
	MaxRetries int
}

// Config holds the configuration for creating a new Client
type Config struct {
	BaseURL    string
	TenantID   string
	Timeout    time.Duration
	MaxRetries int
}

// NewClient creates a new MinIO Enterprise client
func NewClient(config Config) (*Client, error) {
	if config.BaseURL == "" {
		return nil, fmt.Errorf("base URL is required")
	}
	if config.TenantID == "" {
		return nil, fmt.Errorf("tenant ID is required")
	}

	timeout := config.Timeout
	if timeout == 0 {
		timeout = DefaultTimeout
	}

	maxRetries := config.MaxRetries
	if maxRetries == 0 {
		maxRetries = DefaultMaxRetries
	}

	return &Client{
		BaseURL: config.BaseURL,
		HTTPClient: &http.Client{
			Timeout: timeout,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 10,
				IdleConnTimeout:     90 * time.Second,
			},
		},
		TenantID:   config.TenantID,
		MaxRetries: maxRetries,
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

// Upload uploads an object to MinIO
func (c *Client) Upload(ctx context.Context, key string, data io.Reader) (*UploadResponse, error) {
	return c.uploadWithRetry(ctx, key, data)
}

// uploadWithRetry performs upload with exponential backoff retry
func (c *Client) uploadWithRetry(ctx context.Context, key string, data io.Reader) (*UploadResponse, error) {
	var lastErr error
	backoff := time.Second

	for attempt := 0; attempt <= c.MaxRetries; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(backoff):
				backoff *= 2
			}
		}

		resp, err := c.performUpload(ctx, key, data)
		if err == nil {
			return resp, nil
		}

		lastErr = err

		// Don't retry on client errors (4xx except 429)
		if apiErr, ok := err.(*APIError); ok {
			if apiErr.StatusCode >= 400 && apiErr.StatusCode < 500 && apiErr.StatusCode != 429 {
				return nil, err
			}
		}
	}

	return nil, fmt.Errorf("upload failed after %d retries: %w", c.MaxRetries, lastErr)
}

// performUpload performs a single upload attempt
func (c *Client) performUpload(ctx context.Context, key string, data io.Reader) (*UploadResponse, error) {
	uploadURL := fmt.Sprintf("%s/upload?key=%s", c.BaseURL, url.QueryEscape(key))

	req, err := http.NewRequestWithContext(ctx, "PUT", uploadURL, data)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("X-Tenant-ID", c.TenantID)
	req.Header.Set("Content-Type", "application/octet-stream")

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		var errResp ErrorResponse
		if err := json.Unmarshal(body, &errResp); err != nil {
			return nil, &APIError{
				StatusCode: resp.StatusCode,
				Message:    string(body),
			}
		}
		return nil, &APIError{
			StatusCode: resp.StatusCode,
			Message:    errResp.Error,
		}
	}

	var uploadResp UploadResponse
	if err := json.Unmarshal(body, &uploadResp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	return &uploadResp, nil
}

// Download downloads an object from MinIO
func (c *Client) Download(ctx context.Context, key string) (io.ReadCloser, error) {
	return c.downloadWithRetry(ctx, key)
}

// downloadWithRetry performs download with exponential backoff retry
func (c *Client) downloadWithRetry(ctx context.Context, key string) (io.ReadCloser, error) {
	var lastErr error
	backoff := time.Second

	for attempt := 0; attempt <= c.MaxRetries; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(backoff):
				backoff *= 2
			}
		}

		reader, err := c.performDownload(ctx, key)
		if err == nil {
			return reader, nil
		}

		lastErr = err

		// Don't retry on client errors (4xx except 429)
		if apiErr, ok := err.(*APIError); ok {
			if apiErr.StatusCode >= 400 && apiErr.StatusCode < 500 && apiErr.StatusCode != 429 {
				return nil, err
			}
		}
	}

	return nil, fmt.Errorf("download failed after %d retries: %w", c.MaxRetries, lastErr)
}

// performDownload performs a single download attempt
func (c *Client) performDownload(ctx context.Context, key string) (io.ReadCloser, error) {
	downloadURL := fmt.Sprintf("%s/download?key=%s", c.BaseURL, url.QueryEscape(key))

	req, err := http.NewRequestWithContext(ctx, "GET", downloadURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("X-Tenant-ID", c.TenantID)

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		defer resp.Body.Close()
		body, _ := io.ReadAll(resp.Body)

		var errResp ErrorResponse
		if err := json.Unmarshal(body, &errResp); err != nil {
			return nil, &APIError{
				StatusCode: resp.StatusCode,
				Message:    string(body),
			}
		}
		return nil, &APIError{
			StatusCode: resp.StatusCode,
			Message:    errResp.Error,
		}
	}

	return resp.Body, nil
}

// GetServerInfo retrieves server information
func (c *Client) GetServerInfo(ctx context.Context) (*ServerInfo, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", c.BaseURL+"/", nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, &APIError{
			StatusCode: resp.StatusCode,
			Message:    string(body),
		}
	}

	var info ServerInfo
	if err := json.Unmarshal(body, &info); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	return &info, nil
}

// HealthCheck performs a health check
func (c *Client) HealthCheck(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, "GET", c.BaseURL+"/minio/health/ready", nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("health check failed: %s", string(body))
	}

	return nil
}

// APIError represents an API error
type APIError struct {
	StatusCode int
	Message    string
}

// Error implements the error interface
func (e *APIError) Error() string {
	return fmt.Sprintf("API error (status %d): %s", e.StatusCode, e.Message)
}

// Close closes the client and releases resources
func (c *Client) Close() {
	c.HTTPClient.CloseIdleConnections()
}
