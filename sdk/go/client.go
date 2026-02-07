// Package minio provides an official Go SDK for MinIO Enterprise
package minio

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

// Client is the MinIO Enterprise client
type Client struct {
	endpoint   string
	httpClient *http.Client
	apiKey     string
	token      string
	retryMax   int
	retryWait  time.Duration
}

// Config holds the client configuration
type Config struct {
	Endpoint  string        // MinIO API endpoint (e.g., "http://localhost:9000")
	APIKey    string        // API key for authentication
	Token     string        // JWT token for authentication
	Timeout   time.Duration // Request timeout (default: 30s)
	RetryMax  int           // Maximum retry attempts (default: 3)
	RetryWait time.Duration // Wait time between retries (default: 1s)
	TLSConfig *tls.Config   // Optional TLS configuration
}

// NewClient creates a new MinIO Enterprise client
func NewClient(config Config) (*Client, error) {
	if config.Endpoint == "" {
		return nil, fmt.Errorf("endpoint is required")
	}

	// Validate endpoint URL
	_, err := url.Parse(config.Endpoint)
	if err != nil {
		return nil, fmt.Errorf("invalid endpoint URL: %w", err)
	}

	// Set defaults
	if config.Timeout == 0 {
		config.Timeout = 30 * time.Second
	}
	if config.RetryMax == 0 {
		config.RetryMax = 3
	}
	if config.RetryWait == 0 {
		config.RetryWait = time.Second
	}

	// Create HTTP client with connection pooling
	transport := &http.Transport{
		MaxIdleConns:        100,
		MaxIdleConnsPerHost: 100,
		IdleConnTimeout:     90 * time.Second,
		TLSClientConfig:     config.TLSConfig,
	}

	httpClient := &http.Client{
		Timeout:   config.Timeout,
		Transport: transport,
	}

	return &Client{
		endpoint:   config.Endpoint,
		httpClient: httpClient,
		apiKey:     config.APIKey,
		token:      config.Token,
		retryMax:   config.RetryMax,
		retryWait:  config.RetryWait,
	}, nil
}

// Object represents a MinIO object
type Object struct {
	Key          string            `json:"key"`
	Size         int64             `json:"size"`
	ContentType  string            `json:"content_type,omitempty"`
	Metadata     map[string]string `json:"metadata,omitempty"`
	LastModified time.Time         `json:"last_modified,omitempty"`
	ETag         string            `json:"etag,omitempty"`
}

// UploadRequest represents an upload request
type UploadRequest struct {
	TenantID    string            `json:"tenant_id"`
	Key         string            `json:"key"`
	Data        io.Reader         `json:"-"`
	Size        int64             `json:"size"`
	ContentType string            `json:"content_type,omitempty"`
	Metadata    map[string]string `json:"metadata,omitempty"`
}

// UploadResponse represents an upload response
type UploadResponse struct {
	Key  string `json:"key"`
	ETag string `json:"etag"`
	Size int64  `json:"size"`
}

// Upload uploads an object to MinIO
func (c *Client) Upload(ctx context.Context, req UploadRequest) (*UploadResponse, error) {
	if req.TenantID == "" {
		return nil, fmt.Errorf("tenant_id is required")
	}
	if req.Key == "" {
		return nil, fmt.Errorf("key is required")
	}
	if req.Data == nil {
		return nil, fmt.Errorf("data is required")
	}

	url := fmt.Sprintf("%s/upload?tenant=%s&key=%s", c.endpoint, req.TenantID, req.Key)

	// Read data into buffer (for retry support)
	data, err := io.ReadAll(req.Data)
	if err != nil {
		return nil, fmt.Errorf("failed to read data: %w", err)
	}

	var resp *http.Response
	for attempt := 0; attempt <= c.retryMax; attempt++ {
		if attempt > 0 {
			time.Sleep(c.retryWait * time.Duration(1<<uint(attempt-1))) // Exponential backoff
		}

		httpReq, err := http.NewRequestWithContext(ctx, "PUT", url, bytes.NewReader(data))
		if err != nil {
			return nil, fmt.Errorf("failed to create request: %w", err)
		}

		c.setAuthHeaders(httpReq)
		if req.ContentType != "" {
			httpReq.Header.Set("Content-Type", req.ContentType)
		}

		resp, err = c.httpClient.Do(httpReq)
		if err != nil {
			if attempt == c.retryMax {
				return nil, fmt.Errorf("request failed after %d attempts: %w", c.retryMax+1, err)
			}
			continue
		}

		// Success or non-retryable error
		if resp.StatusCode < 500 {
			break
		}

		resp.Body.Close()
		if attempt == c.retryMax {
			return nil, fmt.Errorf("request failed with status %d after %d attempts", resp.StatusCode, c.retryMax+1)
		}
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("upload failed with status %d: %s", resp.StatusCode, string(body))
	}

	var uploadResp UploadResponse
	if err := json.NewDecoder(resp.Body).Decode(&uploadResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &uploadResp, nil
}

// DownloadRequest represents a download request
type DownloadRequest struct {
	TenantID string `json:"tenant_id"`
	Key      string `json:"key"`
}

// Download downloads an object from MinIO
func (c *Client) Download(ctx context.Context, req DownloadRequest) (io.ReadCloser, error) {
	if req.TenantID == "" {
		return nil, fmt.Errorf("tenant_id is required")
	}
	if req.Key == "" {
		return nil, fmt.Errorf("key is required")
	}

	url := fmt.Sprintf("%s/download?tenant=%s&key=%s", c.endpoint, req.TenantID, req.Key)

	var resp *http.Response
	var err error
	for attempt := 0; attempt <= c.retryMax; attempt++ {
		if attempt > 0 {
			time.Sleep(c.retryWait * time.Duration(1<<uint(attempt-1)))
		}

		httpReq, err := http.NewRequestWithContext(ctx, "GET", url, nil)
		if err != nil {
			return nil, fmt.Errorf("failed to create request: %w", err)
		}

		c.setAuthHeaders(httpReq)

		resp, err = c.httpClient.Do(httpReq)
		if err != nil {
			if attempt == c.retryMax {
				return nil, fmt.Errorf("request failed after %d attempts: %w", c.retryMax+1, err)
			}
			continue
		}

		if resp.StatusCode < 500 {
			break
		}

		resp.Body.Close()
		if attempt == c.retryMax {
			return nil, fmt.Errorf("request failed with status %d after %d attempts", resp.StatusCode, c.retryMax+1)
		}
	}

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		return nil, fmt.Errorf("download failed with status %d: %s", resp.StatusCode, string(body))
	}

	return resp.Body, nil
}

// DeleteRequest represents a delete request
type DeleteRequest struct {
	TenantID string `json:"tenant_id"`
	Key      string `json:"key"`
}

// Delete deletes an object from MinIO
func (c *Client) Delete(ctx context.Context, req DeleteRequest) error {
	if req.TenantID == "" {
		return fmt.Errorf("tenant_id is required")
	}
	if req.Key == "" {
		return fmt.Errorf("key is required")
	}

	url := fmt.Sprintf("%s/delete?tenant=%s&key=%s", c.endpoint, req.TenantID, req.Key)

	var resp *http.Response
	var err error
	for attempt := 0; attempt <= c.retryMax; attempt++ {
		if attempt > 0 {
			time.Sleep(c.retryWait * time.Duration(1<<uint(attempt-1)))
		}

		httpReq, err := http.NewRequestWithContext(ctx, "DELETE", url, nil)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		c.setAuthHeaders(httpReq)

		resp, err = c.httpClient.Do(httpReq)
		if err != nil {
			if attempt == c.retryMax {
				return fmt.Errorf("request failed after %d attempts: %w", c.retryMax+1, err)
			}
			continue
		}

		if resp.StatusCode < 500 {
			break
		}

		resp.Body.Close()
		if attempt == c.retryMax {
			return fmt.Errorf("request failed with status %d after %d attempts", resp.StatusCode, c.retryMax+1)
		}
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("delete failed with status %d: %s", resp.StatusCode, string(body))
	}

	return nil
}

// ListRequest represents a list request
type ListRequest struct {
	TenantID string `json:"tenant_id"`
	Prefix   string `json:"prefix,omitempty"`
	Limit    int    `json:"limit,omitempty"`
	Marker   string `json:"marker,omitempty"`
}

// ListResponse represents a list response
type ListResponse struct {
	Objects    []Object `json:"objects"`
	NextMarker string   `json:"next_marker,omitempty"`
	IsTruncated bool    `json:"is_truncated"`
}

// List lists objects in MinIO
func (c *Client) List(ctx context.Context, req ListRequest) (*ListResponse, error) {
	if req.TenantID == "" {
		return nil, fmt.Errorf("tenant_id is required")
	}

	params := url.Values{}
	params.Add("tenant", req.TenantID)
	if req.Prefix != "" {
		params.Add("prefix", req.Prefix)
	}
	if req.Limit > 0 {
		params.Add("limit", fmt.Sprintf("%d", req.Limit))
	}
	if req.Marker != "" {
		params.Add("marker", req.Marker)
	}

	url := fmt.Sprintf("%s/list?%s", c.endpoint, params.Encode())

	var resp *http.Response
	var err error
	for attempt := 0; attempt <= c.retryMax; attempt++ {
		if attempt > 0 {
			time.Sleep(c.retryWait * time.Duration(1<<uint(attempt-1)))
		}

		httpReq, err := http.NewRequestWithContext(ctx, "GET", url, nil)
		if err != nil {
			return nil, fmt.Errorf("failed to create request: %w", err)
		}

		c.setAuthHeaders(httpReq)

		resp, err = c.httpClient.Do(httpReq)
		if err != nil {
			if attempt == c.retryMax {
				return nil, fmt.Errorf("request failed after %d attempts: %w", c.retryMax+1, err)
			}
			continue
		}

		if resp.StatusCode < 500 {
			break
		}

		resp.Body.Close()
		if attempt == c.retryMax {
			return nil, fmt.Errorf("request failed with status %d after %d attempts", resp.StatusCode, c.retryMax+1)
		}
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("list failed with status %d: %s", resp.StatusCode, string(body))
	}

	var listResp ListResponse
	if err := json.NewDecoder(resp.Body).Decode(&listResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &listResp, nil
}

// QuotaInfo represents tenant quota information
type QuotaInfo struct {
	TenantID string `json:"tenant_id"`
	Used     int64  `json:"used"`
	Limit    int64  `json:"limit"`
	Objects  int64  `json:"objects"`
}

// GetQuota retrieves tenant quota information
func (c *Client) GetQuota(ctx context.Context, tenantID string) (*QuotaInfo, error) {
	if tenantID == "" {
		return nil, fmt.Errorf("tenant_id is required")
	}

	url := fmt.Sprintf("%s/quota?tenant=%s", c.endpoint, tenantID)

	var resp *http.Response
	var err error
	for attempt := 0; attempt <= c.retryMax; attempt++ {
		if attempt > 0 {
			time.Sleep(c.retryWait * time.Duration(1<<uint(attempt-1)))
		}

		httpReq, err := http.NewRequestWithContext(ctx, "GET", url, nil)
		if err != nil {
			return nil, fmt.Errorf("failed to create request: %w", err)
		}

		c.setAuthHeaders(httpReq)

		resp, err = c.httpClient.Do(httpReq)
		if err != nil {
			if attempt == c.retryMax {
				return nil, fmt.Errorf("request failed after %d attempts: %w", c.retryMax+1, err)
			}
			continue
		}

		if resp.StatusCode < 500 {
			break
		}

		resp.Body.Close()
		if attempt == c.retryMax {
			return nil, fmt.Errorf("request failed with status %d after %d attempts", resp.StatusCode, c.retryMax+1)
		}
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("get quota failed with status %d: %s", resp.StatusCode, string(body))
	}

	var quota QuotaInfo
	if err := json.NewDecoder(resp.Body).Decode(&quota); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &quota, nil
}

// HealthInfo represents health check information
type HealthInfo struct {
	Status  string            `json:"status"`
	Version string            `json:"version"`
	Uptime  int64             `json:"uptime"`
	Checks  map[string]string `json:"checks"`
}

// Health performs a health check
func (c *Client) Health(ctx context.Context) (*HealthInfo, error) {
	url := fmt.Sprintf("%s/health", c.endpoint)

	httpReq, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("health check failed with status %d: %s", resp.StatusCode, string(body))
	}

	var health HealthInfo
	if err := json.NewDecoder(resp.Body).Decode(&health); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &health, nil
}

// setAuthHeaders sets authentication headers on the request
func (c *Client) setAuthHeaders(req *http.Request) {
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	} else if c.apiKey != "" {
		req.Header.Set("X-API-Key", c.apiKey)
	}
}

// Close closes the client and releases resources
func (c *Client) Close() error {
	c.httpClient.CloseIdleConnections()
	return nil
}
