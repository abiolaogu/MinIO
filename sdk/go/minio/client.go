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

// Client is the MinIO Enterprise API client
type Client struct {
	baseURL    string
	tenantID   string
	httpClient *http.Client
	retryMax   int
	retryDelay time.Duration
}

// Config holds the client configuration
type Config struct {
	// BaseURL is the MinIO server base URL (e.g., "http://localhost:9000")
	BaseURL string

	// TenantID is the tenant identifier for multi-tenancy
	TenantID string

	// HTTPClient is the optional HTTP client to use (default: http.DefaultClient with timeout)
	HTTPClient *http.Client

	// RetryMax is the maximum number of retry attempts (default: 3)
	RetryMax int

	// RetryDelay is the initial delay between retries (default: 1s, uses exponential backoff)
	RetryDelay time.Duration
}

// NewClient creates a new MinIO Enterprise API client
func NewClient(config *Config) (*Client, error) {
	if config.BaseURL == "" {
		return nil, fmt.Errorf("BaseURL is required")
	}
	if config.TenantID == "" {
		return nil, fmt.Errorf("TenantID is required")
	}

	// Parse and validate base URL
	_, err := url.Parse(config.BaseURL)
	if err != nil {
		return nil, fmt.Errorf("invalid BaseURL: %w", err)
	}

	// Set defaults
	httpClient := config.HTTPClient
	if httpClient == nil {
		httpClient = &http.Client{
			Timeout: 30 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 10,
				IdleConnTimeout:     90 * time.Second,
			},
		}
	}

	retryMax := config.RetryMax
	if retryMax <= 0 {
		retryMax = 3
	}

	retryDelay := config.RetryDelay
	if retryDelay <= 0 {
		retryDelay = 1 * time.Second
	}

	return &Client{
		baseURL:    config.BaseURL,
		tenantID:   config.TenantID,
		httpClient: httpClient,
		retryMax:   retryMax,
		retryDelay: retryDelay,
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
func (c *Client) Upload(ctx context.Context, key string, data io.Reader) (*UploadResponse, error) {
	if key == "" {
		return nil, fmt.Errorf("key cannot be empty")
	}
	if data == nil {
		return nil, fmt.Errorf("data cannot be nil")
	}

	// Build URL
	uploadURL := fmt.Sprintf("%s/upload?key=%s", c.baseURL, url.QueryEscape(key))

	// Read data into buffer for retry capability
	buf := new(bytes.Buffer)
	size, err := io.Copy(buf, data)
	if err != nil {
		return nil, fmt.Errorf("failed to read data: %w", err)
	}

	var resp *UploadResponse
	err = c.doWithRetry(ctx, func() error {
		// Create request
		req, err := http.NewRequestWithContext(ctx, http.MethodPut, uploadURL, bytes.NewReader(buf.Bytes()))
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		// Set headers
		req.Header.Set("X-Tenant-ID", c.tenantID)
		req.Header.Set("Content-Type", "application/octet-stream")

		// Execute request
		httpResp, err := c.httpClient.Do(req)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer httpResp.Body.Close()

		// Read response body
		body, err := io.ReadAll(httpResp.Body)
		if err != nil {
			return fmt.Errorf("failed to read response: %w", err)
		}

		// Handle error responses
		if httpResp.StatusCode != http.StatusOK {
			var errResp ErrorResponse
			if err := json.Unmarshal(body, &errResp); err == nil && errResp.Error != "" {
				return &APIError{
					StatusCode: httpResp.StatusCode,
					Message:    errResp.Error,
				}
			}
			return &APIError{
				StatusCode: httpResp.StatusCode,
				Message:    fmt.Sprintf("upload failed with status %d", httpResp.StatusCode),
			}
		}

		// Parse success response
		var uploadResp UploadResponse
		if err := json.Unmarshal(body, &uploadResp); err != nil {
			return fmt.Errorf("failed to parse response: %w", err)
		}

		resp = &uploadResp
		return nil
	})

	if err != nil {
		return nil, err
	}

	return resp, nil
}

// Download downloads an object from MinIO storage
func (c *Client) Download(ctx context.Context, key string) (io.ReadCloser, error) {
	if key == "" {
		return nil, fmt.Errorf("key cannot be empty")
	}

	// Build URL
	downloadURL := fmt.Sprintf("%s/download?key=%s", c.baseURL, url.QueryEscape(key))

	var result io.ReadCloser
	err := c.doWithRetry(ctx, func() error {
		// Create request
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, downloadURL, nil)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		// Set headers
		req.Header.Set("X-Tenant-ID", c.tenantID)

		// Execute request
		httpResp, err := c.httpClient.Do(req)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}

		// Handle error responses
		if httpResp.StatusCode != http.StatusOK {
			defer httpResp.Body.Close()
			body, _ := io.ReadAll(httpResp.Body)

			var errResp ErrorResponse
			if err := json.Unmarshal(body, &errResp); err == nil && errResp.Error != "" {
				return &APIError{
					StatusCode: httpResp.StatusCode,
					Message:    errResp.Error,
					Retryable:  httpResp.StatusCode >= 500, // Retry on 5xx errors
				}
			}

			return &APIError{
				StatusCode: httpResp.StatusCode,
				Message:    fmt.Sprintf("download failed with status %d", httpResp.StatusCode),
				Retryable:  httpResp.StatusCode >= 500,
			}
		}

		result = httpResp.Body
		return nil
	})

	if err != nil {
		return nil, err
	}

	return result, nil
}

// Delete deletes an object from MinIO storage (not in current API, but commonly needed)
func (c *Client) Delete(ctx context.Context, key string) error {
	if key == "" {
		return fmt.Errorf("key cannot be empty")
	}

	// Build URL
	deleteURL := fmt.Sprintf("%s/delete?key=%s", c.baseURL, url.QueryEscape(key))

	return c.doWithRetry(ctx, func() error {
		// Create request
		req, err := http.NewRequestWithContext(ctx, http.MethodDelete, deleteURL, nil)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		// Set headers
		req.Header.Set("X-Tenant-ID", c.tenantID)

		// Execute request
		httpResp, err := c.httpClient.Do(req)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer httpResp.Body.Close()

		// Handle error responses
		if httpResp.StatusCode != http.StatusOK && httpResp.StatusCode != http.StatusNoContent {
			body, _ := io.ReadAll(httpResp.Body)

			var errResp ErrorResponse
			if err := json.Unmarshal(body, &errResp); err == nil && errResp.Error != "" {
				return &APIError{
					StatusCode: httpResp.StatusCode,
					Message:    errResp.Error,
					Retryable:  httpResp.StatusCode >= 500,
				}
			}

			return &APIError{
				StatusCode: httpResp.StatusCode,
				Message:    fmt.Sprintf("delete failed with status %d", httpResp.StatusCode),
				Retryable:  httpResp.StatusCode >= 500,
			}
		}

		return nil
	})
}

// GetServerInfo retrieves server information
func (c *Client) GetServerInfo(ctx context.Context) (*ServerInfo, error) {
	infoURL := fmt.Sprintf("%s/", c.baseURL)

	var info *ServerInfo
	err := c.doWithRetry(ctx, func() error {
		// Create request
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, infoURL, nil)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		// Execute request
		httpResp, err := c.httpClient.Do(req)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer httpResp.Body.Close()

		// Read response body
		body, err := io.ReadAll(httpResp.Body)
		if err != nil {
			return fmt.Errorf("failed to read response: %w", err)
		}

		// Handle error responses
		if httpResp.StatusCode != http.StatusOK {
			return &APIError{
				StatusCode: httpResp.StatusCode,
				Message:    fmt.Sprintf("server info request failed with status %d", httpResp.StatusCode),
				Retryable:  httpResp.StatusCode >= 500,
			}
		}

		// Parse response
		var serverInfo ServerInfo
		if err := json.Unmarshal(body, &serverInfo); err != nil {
			return fmt.Errorf("failed to parse response: %w", err)
		}

		info = &serverInfo
		return nil
	})

	if err != nil {
		return nil, err
	}

	return info, nil
}

// HealthCheck checks if the server is healthy and ready
func (c *Client) HealthCheck(ctx context.Context) error {
	healthURL := fmt.Sprintf("%s/minio/health/ready", c.baseURL)

	return c.doWithRetry(ctx, func() error {
		// Create request
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, healthURL, nil)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		// Execute request
		httpResp, err := c.httpClient.Do(req)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer httpResp.Body.Close()

		// Check status
		if httpResp.StatusCode != http.StatusOK {
			return &APIError{
				StatusCode: httpResp.StatusCode,
				Message:    "health check failed",
				Retryable:  true,
			}
		}

		return nil
	})
}

// APIError represents an API error with retry information
type APIError struct {
	StatusCode int
	Message    string
	Retryable  bool
}

func (e *APIError) Error() string {
	return fmt.Sprintf("API error (status %d): %s", e.StatusCode, e.Message)
}

// doWithRetry executes a function with exponential backoff retry logic
func (c *Client) doWithRetry(ctx context.Context, fn func() error) error {
	var lastErr error

	for attempt := 0; attempt <= c.retryMax; attempt++ {
		// Check context cancellation
		if ctx.Err() != nil {
			return ctx.Err()
		}

		// Execute function
		err := fn()
		if err == nil {
			return nil
		}

		lastErr = err

		// Check if error is retryable
		var apiErr *APIError
		if attempt < c.retryMax {
			if apiErr, _ := err.(*APIError); apiErr != nil && !apiErr.Retryable {
				// Non-retryable error, return immediately
				return err
			}

			// Calculate backoff delay (exponential: 1s, 2s, 4s, 8s, ...)
			delay := c.retryDelay * time.Duration(1<<uint(attempt))

			// Wait before retry
			timer := time.NewTimer(delay)
			select {
			case <-ctx.Done():
				timer.Stop()
				return ctx.Err()
			case <-timer.C:
				// Continue to next attempt
			}
		}
	}

	return fmt.Errorf("max retries exceeded: %w", lastErr)
}

// GetTenantID returns the configured tenant ID
func (c *Client) GetTenantID() string {
	return c.tenantID
}

// GetBaseURL returns the configured base URL
func (c *Client) GetBaseURL() string {
	return c.baseURL
}
