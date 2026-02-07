// Package minio provides a Go SDK client for MinIO Enterprise API
package minio

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path"
	"time"
)

// Client represents a MinIO Enterprise SDK client
type Client struct {
	baseURL    string
	httpClient *http.Client
	apiKey     string
	timeout    time.Duration
	maxRetries int
}

// Config holds the configuration for the MinIO client
type Config struct {
	BaseURL    string        // MinIO API base URL (e.g., "http://localhost:9000")
	APIKey     string        // API key for authentication
	Timeout    time.Duration // Request timeout (default: 30s)
	MaxRetries int           // Maximum retry attempts (default: 3)
}

// NewClient creates a new MinIO Enterprise SDK client
func NewClient(config Config) (*Client, error) {
	if config.BaseURL == "" {
		return nil, fmt.Errorf("base URL is required")
	}

	if config.Timeout == 0 {
		config.Timeout = 30 * time.Second
	}

	if config.MaxRetries == 0 {
		config.MaxRetries = 3
	}

	return &Client{
		baseURL: config.BaseURL,
		httpClient: &http.Client{
			Timeout: config.Timeout,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 100,
				IdleConnTimeout:     90 * time.Second,
			},
		},
		apiKey:     config.APIKey,
		timeout:    config.Timeout,
		maxRetries: config.MaxRetries,
	}, nil
}

// UploadRequest represents a file upload request
type UploadRequest struct {
	TenantID string    // Tenant identifier
	ObjectID string    // Object/file identifier
	Data     io.Reader // File data
	Size     int64     // File size in bytes
}

// UploadResponse represents the response from an upload operation
type UploadResponse struct {
	Message   string `json:"message"`
	TenantID  string `json:"tenant_id"`
	ObjectID  string `json:"object_id"`
	Size      int64  `json:"size"`
	Timestamp string `json:"timestamp"`
}

// Upload uploads a file to MinIO Enterprise
func (c *Client) Upload(ctx context.Context, req UploadRequest) (*UploadResponse, error) {
	if req.TenantID == "" || req.ObjectID == "" {
		return nil, fmt.Errorf("tenant_id and object_id are required")
	}

	endpoint := fmt.Sprintf("%s/upload", c.baseURL)

	// Read data into buffer
	data, err := io.ReadAll(req.Data)
	if err != nil {
		return nil, fmt.Errorf("failed to read data: %w", err)
	}

	// Prepare request body
	body := map[string]interface{}{
		"tenant_id": req.TenantID,
		"object_id": req.ObjectID,
		"data":      string(data),
	}

	var lastErr error
	for attempt := 0; attempt <= c.maxRetries; attempt++ {
		if attempt > 0 {
			// Exponential backoff
			time.Sleep(time.Duration(attempt) * time.Second)
		}

		resp, err := c.doRequest(ctx, "PUT", endpoint, body)
		if err != nil {
			lastErr = err
			continue
		}

		var uploadResp UploadResponse
		if err := json.Unmarshal(resp, &uploadResp); err != nil {
			return nil, fmt.Errorf("failed to parse response: %w", err)
		}

		return &uploadResp, nil
	}

	return nil, fmt.Errorf("upload failed after %d retries: %w", c.maxRetries, lastErr)
}

// DownloadRequest represents a file download request
type DownloadRequest struct {
	TenantID string // Tenant identifier
	ObjectID string // Object/file identifier
}

// DownloadResponse represents the response from a download operation
type DownloadResponse struct {
	Data      []byte `json:"-"`
	Message   string `json:"message"`
	TenantID  string `json:"tenant_id"`
	ObjectID  string `json:"object_id"`
	Size      int64  `json:"size"`
	Timestamp string `json:"timestamp"`
}

// Download downloads a file from MinIO Enterprise
func (c *Client) Download(ctx context.Context, req DownloadRequest) (*DownloadResponse, error) {
	if req.TenantID == "" || req.ObjectID == "" {
		return nil, fmt.Errorf("tenant_id and object_id are required")
	}

	u, err := url.Parse(c.baseURL)
	if err != nil {
		return nil, fmt.Errorf("invalid base URL: %w", err)
	}
	u.Path = path.Join(u.Path, "download")

	query := u.Query()
	query.Set("tenant_id", req.TenantID)
	query.Set("object_id", req.ObjectID)
	u.RawQuery = query.Encode()

	var lastErr error
	for attempt := 0; attempt <= c.maxRetries; attempt++ {
		if attempt > 0 {
			time.Sleep(time.Duration(attempt) * time.Second)
		}

		resp, err := c.doRequest(ctx, "GET", u.String(), nil)
		if err != nil {
			lastErr = err
			continue
		}

		var downloadResp DownloadResponse
		if err := json.Unmarshal(resp, &downloadResp); err != nil {
			return nil, fmt.Errorf("failed to parse response: %w", err)
		}
		downloadResp.Data = resp

		return &downloadResp, nil
	}

	return nil, fmt.Errorf("download failed after %d retries: %w", c.maxRetries, lastErr)
}

// DeleteRequest represents a file deletion request
type DeleteRequest struct {
	TenantID string // Tenant identifier
	ObjectID string // Object/file identifier
}

// DeleteResponse represents the response from a delete operation
type DeleteResponse struct {
	Message   string `json:"message"`
	TenantID  string `json:"tenant_id"`
	ObjectID  string `json:"object_id"`
	Timestamp string `json:"timestamp"`
}

// Delete deletes a file from MinIO Enterprise
func (c *Client) Delete(ctx context.Context, req DeleteRequest) (*DeleteResponse, error) {
	if req.TenantID == "" || req.ObjectID == "" {
		return nil, fmt.Errorf("tenant_id and object_id are required")
	}

	u, err := url.Parse(c.baseURL)
	if err != nil {
		return nil, fmt.Errorf("invalid base URL: %w", err)
	}
	u.Path = path.Join(u.Path, "delete")

	query := u.Query()
	query.Set("tenant_id", req.TenantID)
	query.Set("object_id", req.ObjectID)
	u.RawQuery = query.Encode()

	var lastErr error
	for attempt := 0; attempt <= c.maxRetries; attempt++ {
		if attempt > 0 {
			time.Sleep(time.Duration(attempt) * time.Second)
		}

		resp, err := c.doRequest(ctx, "DELETE", u.String(), nil)
		if err != nil {
			lastErr = err
			continue
		}

		var deleteResp DeleteResponse
		if err := json.Unmarshal(resp, &deleteResp); err != nil {
			return nil, fmt.Errorf("failed to parse response: %w", err)
		}

		return &deleteResp, nil
	}

	return nil, fmt.Errorf("delete failed after %d retries: %w", c.maxRetries, lastErr)
}

// ListRequest represents a list objects request
type ListRequest struct {
	TenantID string // Tenant identifier
	Prefix   string // Optional prefix filter
	Limit    int    // Optional limit (default: 100)
}

// ObjectInfo represents information about an object
type ObjectInfo struct {
	ObjectID  string `json:"object_id"`
	Size      int64  `json:"size"`
	Timestamp string `json:"timestamp"`
}

// ListResponse represents the response from a list operation
type ListResponse struct {
	Objects   []ObjectInfo `json:"objects"`
	TenantID  string       `json:"tenant_id"`
	Count     int          `json:"count"`
	Timestamp string       `json:"timestamp"`
}

// List lists objects in MinIO Enterprise
func (c *Client) List(ctx context.Context, req ListRequest) (*ListResponse, error) {
	if req.TenantID == "" {
		return nil, fmt.Errorf("tenant_id is required")
	}

	if req.Limit == 0 {
		req.Limit = 100
	}

	u, err := url.Parse(c.baseURL)
	if err != nil {
		return nil, fmt.Errorf("invalid base URL: %w", err)
	}
	u.Path = path.Join(u.Path, "list")

	query := u.Query()
	query.Set("tenant_id", req.TenantID)
	if req.Prefix != "" {
		query.Set("prefix", req.Prefix)
	}
	query.Set("limit", fmt.Sprintf("%d", req.Limit))
	u.RawQuery = query.Encode()

	var lastErr error
	for attempt := 0; attempt <= c.maxRetries; attempt++ {
		if attempt > 0 {
			time.Sleep(time.Duration(attempt) * time.Second)
		}

		resp, err := c.doRequest(ctx, "GET", u.String(), nil)
		if err != nil {
			lastErr = err
			continue
		}

		var listResp ListResponse
		if err := json.Unmarshal(resp, &listResp); err != nil {
			return nil, fmt.Errorf("failed to parse response: %w", err)
		}

		return &listResp, nil
	}

	return nil, fmt.Errorf("list failed after %d retries: %w", c.maxRetries, lastErr)
}

// QuotaRequest represents a quota information request
type QuotaRequest struct {
	TenantID string // Tenant identifier
}

// QuotaResponse represents the response from a quota operation
type QuotaResponse struct {
	TenantID  string `json:"tenant_id"`
	Used      int64  `json:"used"`
	Limit     int64  `json:"limit"`
	Available int64  `json:"available"`
	Timestamp string `json:"timestamp"`
}

// GetQuota retrieves quota information for a tenant
func (c *Client) GetQuota(ctx context.Context, req QuotaRequest) (*QuotaResponse, error) {
	if req.TenantID == "" {
		return nil, fmt.Errorf("tenant_id is required")
	}

	u, err := url.Parse(c.baseURL)
	if err != nil {
		return nil, fmt.Errorf("invalid base URL: %w", err)
	}
	u.Path = path.Join(u.Path, "quota")

	query := u.Query()
	query.Set("tenant_id", req.TenantID)
	u.RawQuery = query.Encode()

	var lastErr error
	for attempt := 0; attempt <= c.maxRetries; attempt++ {
		if attempt > 0 {
			time.Sleep(time.Duration(attempt) * time.Second)
		}

		resp, err := c.doRequest(ctx, "GET", u.String(), nil)
		if err != nil {
			lastErr = err
			continue
		}

		var quotaResp QuotaResponse
		if err := json.Unmarshal(resp, &quotaResp); err != nil {
			return nil, fmt.Errorf("failed to parse response: %w", err)
		}

		return &quotaResp, nil
	}

	return nil, fmt.Errorf("quota request failed after %d retries: %w", c.maxRetries, lastErr)
}

// HealthResponse represents the response from a health check
type HealthResponse struct {
	Status    string `json:"status"`
	Timestamp string `json:"timestamp"`
}

// HealthCheck performs a health check on the MinIO service
func (c *Client) HealthCheck(ctx context.Context) (*HealthResponse, error) {
	endpoint := fmt.Sprintf("%s/health", c.baseURL)

	resp, err := c.doRequest(ctx, "GET", endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("health check failed: %w", err)
	}

	var healthResp HealthResponse
	if err := json.Unmarshal(resp, &healthResp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	return &healthResp, nil
}

// doRequest performs an HTTP request with authentication
func (c *Client) doRequest(ctx context.Context, method, url string, body interface{}) ([]byte, error) {
	var reqBody io.Reader
	if body != nil {
		jsonData, err := json.Marshal(body)
		if err != nil {
			return nil, fmt.Errorf("failed to marshal request body: %w", err)
		}
		reqBody = bytes.NewBuffer(jsonData)
	}

	req, err := http.NewRequestWithContext(ctx, method, url, reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// Set headers
	req.Header.Set("Content-Type", "application/json")
	if c.apiKey != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.apiKey))
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("request failed with status %d: %s", resp.StatusCode, string(respBody))
	}

	return respBody, nil
}
