// enterprise/multitenancy/tenantmanager.go
package multitenancy

import (
	"context"
	"crypto/sha256"
	"fmt"
	"sync"
	"time"

	"github.com/google/uuid"
)

// TenantConfig represents an isolated tenant environment
type TenantConfig struct {
	ID              string            // Unique tenant identifier
	Name            string            // Human-readable tenant name
	StorageQuota    int64             // Maximum bytes this tenant can store
	BandwidthQuota  int64             // Maximum bytes/second egress
	RequestRateLimit int64            // Requests per second limit
	Regions         []string          // Allowed regions for this tenant
	DataResidency   string            // Enforce data residency (e.g., "EU")
	EncryptionKey   []byte            // Tenant-specific encryption key
	CreatedAt       time.Time
	Features        TenantFeatures
	Metadata        map[string]string // Custom tenant metadata
	mu              sync.RWMutex      // Protects concurrent access
}

// TenantFeatures defines which features are enabled for a tenant
type TenantFeatures struct {
	ActiveActiveReplication bool
	CostAnalytics          bool
	AdvancedAudit          bool
	DisasterRecovery       bool
	DataTiering            bool
	EdgeAcceleration       bool
	ComplianceModules      string // "GDPR", "HIPAA", "PCI-DSS", "NONE"
}

// TenantQuotaUsage tracks current usage against quotas
type TenantQuotaUsage struct {
	TenantID        string
	StorageUsed     int64
	RequestCount    int64
	BandwidthUsed   int64
	LastUpdated     time.Time
}

// TenantManager manages tenant lifecycle and isolation
type TenantManager struct {
	tenants      map[string]*TenantConfig
	usage        map[string]*TenantQuotaUsage
	mu           sync.RWMutex
	auditLog     AuditLogger
	policyEngine PolicyEngine
}

// NewTenantManager creates a new tenant manager
func NewTenantManager(auditLog AuditLogger, policyEngine PolicyEngine) *TenantManager {
	return &TenantManager{
		tenants:      make(map[string]*TenantConfig),
		usage:        make(map[string]*TenantQuotaUsage),
		auditLog:     auditLog,
		policyEngine: policyEngine,
	}
}

// CreateTenant creates a new tenant with strict isolation
func (tm *TenantManager) CreateTenant(ctx context.Context, req CreateTenantRequest) (*TenantConfig, error) {
	tenantID := uuid.New().String()
	
	// Generate tenant-specific encryption key
	encKey := make([]byte, 32)
	if _, err := deriveKey([]byte(tenantID)); err != nil {
		return nil, fmt.Errorf("failed to derive encryption key: %w", err)
	}

	tenant := &TenantConfig{
		ID:               tenantID,
		Name:             req.Name,
		StorageQuota:     req.StorageQuota,
		BandwidthQuota:   req.BandwidthQuota,
		RequestRateLimit: req.RequestRateLimit,
		Regions:          req.Regions,
		DataResidency:    req.DataResidency,
		EncryptionKey:    encKey,
		CreatedAt:        time.Now(),
		Features:         req.Features,
		Metadata:         req.Metadata,
	}

	tm.mu.Lock()
	defer tm.mu.Unlock()

	if _, exists := tm.tenants[tenantID]; exists {
		return nil, fmt.Errorf("tenant already exists: %s", tenantID)
	}

	tm.tenants[tenantID] = tenant
	tm.usage[tenantID] = &TenantQuotaUsage{
		TenantID:    tenantID,
		StorageUsed: 0,
		RequestCount: 0,
		BandwidthUsed: 0,
		LastUpdated: time.Now(),
	}

	// Audit log creation
	tm.auditLog.LogEvent(ctx, AuditEvent{
		TenantID: tenantID,
		Action:   "TENANT_CREATED",
		Timestamp: time.Now(),
		Details:  map[string]interface{}{"name": req.Name, "quota": req.StorageQuota},
	})

	return tenant, nil
}

// GetTenant retrieves tenant configuration
func (tm *TenantManager) GetTenant(ctx context.Context, tenantID string) (*TenantConfig, error) {
	tm.mu.RLock()
	defer tm.mu.RUnlock()

	tenant, exists := tm.tenants[tenantID]
	if !exists {
		return nil, fmt.Errorf("tenant not found: %s", tenantID)
	}

	return tenant, nil
}

// UpdateQuotaUsage atomically updates quota usage
func (tm *TenantManager) UpdateQuotaUsage(ctx context.Context, tenantID string, bytesAdded int64, requestCount int64, bandwidthUsed int64) error {
	tm.mu.Lock()
	defer tm.mu.Unlock()

	usage, exists := tm.usage[tenantID]
	if !exists {
		return fmt.Errorf("tenant not found: %s", tenantID)
	}

	tenant := tm.tenants[tenantID]

	// Check quotas
	if tenant.StorageQuota > 0 && usage.StorageUsed+bytesAdded > tenant.StorageQuota {
		return fmt.Errorf("storage quota exceeded: %d > %d", usage.StorageUsed+bytesAdded, tenant.StorageQuota)
	}

	if tenant.BandwidthQuota > 0 && usage.BandwidthUsed+bandwidthUsed > tenant.BandwidthQuota {
		return fmt.Errorf("bandwidth quota exceeded")
	}

	// Atomic update
	usage.StorageUsed += bytesAdded
	usage.RequestCount += requestCount
	usage.BandwidthUsed += bandwidthUsed
	usage.LastUpdated = time.Now()

	return nil
}

// CheckQuota checks if operation would exceed quota
func (tm *TenantManager) CheckQuota(ctx context.Context, tenantID string, bytesRequired int64) (bool, error) {
	tm.mu.RLock()
	defer tm.mu.RUnlock()

	tenant, exists := tm.tenants[tenantID]
	if !exists {
		return false, fmt.Errorf("tenant not found")
	}

	usage := tm.usage[tenantID]

	if tenant.StorageQuota > 0 {
		return usage.StorageUsed+bytesRequired <= tenant.StorageQuota, nil
	}

	return true, nil
}

// IssueTenantToken creates a scoped access token for a tenant
func (tm *TenantManager) IssueTenantToken(ctx context.Context, tenantID string, permissions []string, expiresIn time.Duration) (string, error) {
	tm.mu.RLock()
	defer tm.mu.RUnlock()

	_, exists := tm.tenants[tenantID]
	if !exists {
		return "", fmt.Errorf("tenant not found")
	}

	// Create JWT with tenant claims
	claims := TenantClaims{
		TenantID:    tenantID,
		Permissions: permissions,
		ExpiresAt:   time.Now().Add(expiresIn),
		IssuedAt:    time.Now(),
	}

	token, err := signTenantClaims(claims)
	if err != nil {
		return "", fmt.Errorf("failed to create token: %w", err)
	}

	tm.auditLog.LogEvent(ctx, AuditEvent{
		TenantID: tenantID,
		Action:   "TOKEN_ISSUED",
		Timestamp: time.Now(),
	})

	return token, nil
}

// EnforceTenantIsolation validates request against tenant policies
func (tm *TenantManager) EnforceTenantIsolation(ctx context.Context, tenantID string, req TenantRequest) error {
	tm.mu.RLock()
	defer tm.mu.RUnlock()

	tenant, exists := tm.tenants[tenantID]
	if !exists {
		return fmt.Errorf("tenant not found")
	}

	// 1. Verify region compliance
	if len(tenant.Regions) > 0 {
		allowed := false
		for _, r := range tenant.Regions {
			if r == req.Region {
				allowed = true
				break
			}
		}
		if !allowed {
			return fmt.Errorf("region not allowed for tenant: %s", req.Region)
		}
	}

	// 2. Verify data residency
	if tenant.DataResidency != "" && !isDataResidencyCompliant(req.Region, tenant.DataResidency) {
		return fmt.Errorf("data residency violation: %s", tenant.DataResidency)
	}

	// 3. Apply policies
	if err := tm.policyEngine.EvaluatePolicy(ctx, tenant, req); err != nil {
		return fmt.Errorf("policy violation: %w", err)
	}

	return nil
}

// GetTenantMetrics returns current metrics for a tenant
func (tm *TenantManager) GetTenantMetrics(ctx context.Context, tenantID string) (*TenantMetrics, error) {
	tm.mu.RLock()
	defer tm.mu.RUnlock()

	usage, exists := tm.usage[tenantID]
	if !exists {
		return nil, fmt.Errorf("tenant not found")
	}

	tenant := tm.tenants[tenantID]

	return &TenantMetrics{
		TenantID:          tenantID,
		StorageUsed:       usage.StorageUsed,
		StorageQuota:      tenant.StorageQuota,
		StoragePercentage: float64(usage.StorageUsed) / float64(tenant.StorageQuota) * 100,
		RequestCount:      usage.RequestCount,
		RequestRateLimit:  tenant.RequestRateLimit,
		BandwidthUsed:     usage.BandwidthUsed,
		LastUpdated:       usage.LastUpdated,
	}, nil
}

// Helper functions
func deriveKey(seed []byte) ([]byte, error) {
	h := sha256.New()
	h.Write(seed)
	return h.Sum(nil), nil
}

func isDataResidencyCompliant(region string, residency string) bool {
	// Map regions to compliance zones
	euRegions := map[string]bool{
		"eu-west-1": true, "eu-central-1": true, "eu-north-1": true,
	}
	
	switch residency {
	case "EU":
		return euRegions[region]
	case "US":
		return region == "us-east-1" || region == "us-west-2"
	default:
		return true
	}
}

func signTenantClaims(claims TenantClaims) (string, error) {
	// Implementation uses JWT library
	// This is a placeholder
	return fmt.Sprintf("token_%s_%d", claims.TenantID, claims.IssuedAt.Unix()), nil
}

// ========== Type Definitions ==========

type CreateTenantRequest struct {
	Name             string
	StorageQuota     int64
	BandwidthQuota   int64
	RequestRateLimit int64
	Regions          []string
	DataResidency    string
	Features         TenantFeatures
	Metadata         map[string]string
}

type TenantRequest struct {
	Operation string
	Region    string
	Bucket    string
	Key       string
	Size      int64
}

type TenantClaims struct {
	TenantID    string
	Permissions []string
	ExpiresAt   time.Time
	IssuedAt    time.Time
}

type TenantMetrics struct {
	TenantID          string
	StorageUsed       int64
	StorageQuota      int64
	StoragePercentage float64
	RequestCount      int64
	RequestRateLimit  int64
	BandwidthUsed     int64
	LastUpdated       time.Time
}

// Interface definitions
type AuditLogger interface {
	LogEvent(ctx context.Context, event AuditEvent) error
}

type PolicyEngine interface {
	EvaluatePolicy(ctx context.Context, tenant *TenantConfig, req TenantRequest) error
}

type AuditEvent struct {
	TenantID  string
	Action    string
	Timestamp time.Time
	Details   map[string]interface{}
}
