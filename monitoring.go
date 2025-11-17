// enterprise/observability/monitoring.go
package observability

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"
	"time"
)

// MetricsCollector gathers system metrics
type MetricsCollector struct {
	// Operation metrics
	putOpsTotal      int64
	getOpsTotal      int64
	deleteOpsTotal   int64
	listOpsTotal     int64
	
	putLatencySum    int64 // in nanoseconds
	getLatencySum    int64
	deleteLatencySum int64
	listLatencySum   int64
	
	putLatencyCount  int64
	getLatencyCount  int64
	deleteLatencyCount int64
	listLatencyCount   int64
	
	// Error metrics
	errorCount       int64
	errorsByType     map[string]int64
	
	// Storage metrics
	bytesStored      int64
	objectCount      int64
	
	// Cache metrics
	cacheHits        int64
	cacheMisses       int64
	
	// Replication metrics
	replicationLag   int64
	replicationErrors int64
	
	// Resource metrics
	cpuUsage         float64
	memoryUsage      int64
	networkBandwidth int64
	
	mu               sync.RWMutex
	lastCollected    time.Time
}

// OperationMetrics tracks detailed metrics for an operation
type OperationMetrics struct {
	OperationType    string
	TenantID         string
	Timestamp        time.Time
	Duration         time.Duration
	BytesTransferred int64
	Success          bool
	ErrorCode        string
	Region           string
}

// PercentileMetrics tracks percentile latencies
type PercentileMetrics struct {
	P50  time.Duration
	P90  time.Duration
	P95  time.Duration
	P99  time.Duration
	P999 time.Duration
}

// MetricsAggregator aggregates metrics over time windows
type MetricsAggregator struct {
	windows map[string]*TimeWindow
	mu      sync.RWMutex
}

// TimeWindow represents a time-based aggregation window
type TimeWindow struct {
	StartTime       time.Time
	EndTime         time.Time
	Operations      []OperationMetrics
	Percentiles     PercentileMetrics
	Throughput      float64 // ops/sec
	ErrorRate       float64
	AverageLatency  time.Duration
}

// DistributedTracer enables request tracing across services
type DistributedTracer struct {
	traces          map[string]*RequestTrace
	spanCollector   SpanCollector
	mu              sync.RWMutex
}

// RequestTrace tracks a complete request through all services
type RequestTrace struct {
	TraceID         string
	RequestID       string
	TenantID        string
	StartTime       time.Time
	EndTime         time.Time
	RootSpan        *Span
	Spans           []*Span
	Status          string
}

// Span represents a single operation within a trace
type Span struct {
	SpanID         string
	TraceID        string
	ParentSpanID   string
	OperationName  string
	StartTime      time.Time
	EndTime        time.Duration
	Tags           map[string]interface{}
	Logs           []LogEntry
	Status         string
}

type LogEntry struct {
	Timestamp time.Time
	Level     string
	Message   string
	Fields    map[string]interface{}
}

// AnomalyDetector detects unusual patterns in metrics
type AnomalyDetector struct {
	baselines  map[string]Baseline
	threshold  float64 // percentage deviation
	mu         sync.RWMutex
}

type Baseline struct {
	Metric    string
	Mean      float64
	Stddev    float64
	LastUpdate time.Time
}

// AlertManager manages alert generation
type AlertManager struct {
	rules        []*AlertRule
	alerts       map[string]*Alert
	subscribers  map[string]AlertSubscriber
	mu           sync.RWMutex
}

// AlertRule defines conditions for alert generation
type AlertRule struct {
	ID              string
	Name            string
	Condition       AlertCondition
	Severity        string // "critical", "warning", "info"
	NotificationCh  chan *Alert
	Enabled         bool
}

type AlertCondition struct {
	Metric      string
	Operator    string // ">", "<", "==", "!="
	Threshold   float64
	Duration    time.Duration // sustained for this duration
}

// Alert represents a single alert
type Alert struct {
	ID        string
	RuleID    string
	Severity  string
	Timestamp time.Time
	Message   string
	Value     float64
	Status    string // "firing", "resolved"
}

// NewMetricsCollector creates a new metrics collector
func NewMetricsCollector() *MetricsCollector {
	return &MetricsCollector{
		errorsByType: make(map[string]int64),
		lastCollected: time.Now(),
	}
}

// RecordOperation records a single operation
func (mc *MetricsCollector) RecordOperation(ctx context.Context, op OperationMetrics) {
	switch op.OperationType {
	case "PUT":
		atomic.AddInt64(&mc.putOpsTotal, 1)
		atomic.AddInt64(&mc.putLatencySum, op.Duration.Nanoseconds())
		atomic.AddInt64(&mc.putLatencyCount, 1)
		atomic.AddInt64(&mc.bytesStored, op.BytesTransferred)
		atomic.AddInt64(&mc.objectCount, 1)

	case "GET":
		atomic.AddInt64(&mc.getOpsTotal, 1)
		atomic.AddInt64(&mc.getLatencySum, op.Duration.Nanoseconds())
		atomic.AddInt64(&mc.getLatencyCount, 1)

	case "DELETE":
		atomic.AddInt64(&mc.deleteOpsTotal, 1)
		atomic.AddInt64(&mc.deleteLatencySum, op.Duration.Nanoseconds())
		atomic.AddInt64(&mc.deleteLatencyCount, 1)
		atomic.AddInt64(&mc.bytesStored, -op.BytesTransferred)
		atomic.AddInt64(&mc.objectCount, -1)

	case "LIST":
		atomic.AddInt64(&mc.listOpsTotal, 1)
		atomic.AddInt64(&mc.listLatencySum, op.Duration.Nanoseconds())
		atomic.AddInt64(&mc.listLatencyCount, 1)
	}

	if !op.Success {
		atomic.AddInt64(&mc.errorCount, 1)
	}
}

// GetLatencyPercentiles calculates percentile latencies
func (mc *MetricsCollector) GetLatencyPercentiles(opType string) *PercentileMetrics {
	// In production, use actual percentile tracking (e.g., HDR Histogram)
	// This is a simplified version
	
	var avgLatency time.Duration
	var count int64
	
	switch opType {
	case "GET":
		count = atomic.LoadInt64(&mc.getLatencyCount)
		if count > 0 {
			sum := atomic.LoadInt64(&mc.getLatencySum)
			avgLatency = time.Duration(sum / count)
		}
	case "PUT":
		count = atomic.LoadInt64(&mc.putLatencyCount)
		if count > 0 {
			sum := atomic.LoadInt64(&mc.putLatencySum)
			avgLatency = time.Duration(sum / count)
		}
	}

	return &PercentileMetrics{
		P50:  avgLatency,
		P90:  avgLatency * 2,
		P95:  avgLatency * 3,
		P99:  avgLatency * 5,
		P999: avgLatency * 10,
	}
}

// GetThroughput returns ops/sec
func (mc *MetricsCollector) GetThroughput() float64 {
	total := atomic.LoadInt64(&mc.putOpsTotal) + 
	         atomic.LoadInt64(&mc.getOpsTotal) +
	         atomic.LoadInt64(&mc.deleteOpsTotal)
	
	elapsed := time.Since(mc.lastCollected).Seconds()
	return float64(total) / elapsed
}

// GetErrorRate returns error percentage
func (mc *MetricsCollector) GetErrorRate() float64 {
	total := atomic.LoadInt64(&mc.putOpsTotal) + 
	         atomic.LoadInt64(&mc.getOpsTotal) +
	         atomic.LoadInt64(&mc.deleteOpsTotal)
	
	if total == 0 {
		return 0
	}

	errors := atomic.LoadInt64(&mc.errorCount)
	return float64(errors) / float64(total) * 100
}

// ========== DistributedTracer Implementation ==========

func NewDistributedTracer(spanCollector SpanCollector) *DistributedTracer {
	return &DistributedTracer{
		traces:        make(map[string]*RequestTrace),
		spanCollector: spanCollector,
	}
}

// StartTrace begins a new distributed trace
func (dt *DistributedTracer) StartTrace(ctx context.Context, traceID, requestID, tenantID string) *RequestTrace {
	trace := &RequestTrace{
		TraceID:   traceID,
		RequestID: requestID,
		TenantID:  tenantID,
		StartTime: time.Now(),
		Spans:     make([]*Span, 0),
	}

	dt.mu.Lock()
	defer dt.mu.Unlock()
	dt.traces[traceID] = trace

	return trace
}

// CreateSpan creates a new span in a trace
func (dt *DistributedTracer) CreateSpan(traceID, parentSpanID, operationName string) *Span {
	span := &Span{
		TraceID:        traceID,
		ParentSpanID:   parentSpanID,
		OperationName:  operationName,
		StartTime:      time.Now(),
		Tags:           make(map[string]interface{}),
		Logs:           make([]LogEntry, 0),
	}

	dt.mu.Lock()
	defer dt.mu.Unlock()

	if trace, exists := dt.traces[traceID]; exists {
		trace.Spans = append(trace.Spans, span)
	}

	return span
}

// FinishTrace completes a trace and exports spans
func (dt *DistributedTracer) FinishTrace(traceID string) error {
	dt.mu.Lock()
	defer dt.mu.Unlock()

	trace, exists := dt.traces[traceID]
	if !exists {
		return fmt.Errorf("trace not found")
	}

	trace.EndTime = time.Now()

	// Export spans to collector
	for _, span := range trace.Spans {
		span.EndTime = span.StartTime.Add(100 * time.Millisecond) // Simplified
		if err := dt.spanCollector.CollectSpan(span); err != nil {
			// Log error but continue
		}
	}

	return nil
}

// ========== AnomalyDetector Implementation ==========

func NewAnomalyDetector(threshold float64) *AnomalyDetector {
	return &AnomalyDetector{
		baselines: make(map[string]Baseline),
		threshold: threshold,
	}
}

// UpdateBaseline updates the baseline for a metric
func (ad *AnomalyDetector) UpdateBaseline(metric string, value float64) {
	ad.mu.Lock()
	defer ad.mu.Unlock()

	baseline, exists := ad.baselines[metric]
	if !exists {
		baseline = Baseline{
			Metric: metric,
			Mean:   value,
		}
	} else {
		// Simple exponential moving average
		alpha := 0.3
		baseline.Mean = alpha*value + (1-alpha)*baseline.Mean
	}

	baseline.LastUpdate = time.Now()
	ad.baselines[metric] = baseline
}

// DetectAnomaly checks if a value deviates from baseline
func (ad *AnomalyDetector) DetectAnomaly(metric string, value float64) (bool, float64) {
	ad.mu.RLock()
	defer ad.mu.RUnlock()

	baseline, exists := ad.baselines[metric]
	if !exists {
		return false, 0
	}

	if baseline.Mean == 0 {
		return false, 0
	}

	deviation := ((value - baseline.Mean) / baseline.Mean) * 100
	isAnomaly := deviation > ad.threshold

	return isAnomaly, deviation
}

// ========== AlertManager Implementation ==========

func NewAlertManager() *AlertManager {
	return &AlertManager{
		rules:       make([]*AlertRule, 0),
		alerts:      make(map[string]*Alert),
		subscribers: make(map[string]AlertSubscriber),
	}
}

// RegisterRule adds a new alert rule
func (am *AlertManager) RegisterRule(rule *AlertRule) error {
	am.mu.Lock()
	defer am.mu.Unlock()

	for _, existing := range am.rules {
		if existing.ID == rule.ID {
			return fmt.Errorf("rule already exists: %s", rule.ID)
		}
	}

	am.rules = append(am.rules, rule)
	return nil
}

// EvaluateRules checks all rules and generates alerts
func (am *AlertManager) EvaluateRules(ctx context.Context, metrics *MetricsCollector) {
	am.mu.RLock()
	rules := make([]*AlertRule, len(am.rules))
	copy(rules, am.rules)
	am.mu.RUnlock()

	for _, rule := range rules {
		if !rule.Enabled {
			continue
		}

		// Get metric value (simplified)
		metricValue := am.getMetricValue(metrics, rule.Condition.Metric)

		// Check condition
		triggered := am.checkCondition(metricValue, rule.Condition.Operator, rule.Condition.Threshold)

		if triggered {
			alert := &Alert{
				ID:        fmt.Sprintf("%s_%d", rule.ID, time.Now().Unix()),
				RuleID:    rule.ID,
				Severity:  rule.Severity,
				Timestamp: time.Now(),
				Message:   fmt.Sprintf("%s: %s %s %f", rule.Name, rule.Condition.Metric, rule.Condition.Operator, rule.Condition.Threshold),
				Value:     metricValue,
				Status:    "firing",
			}

			am.mu.Lock()
			am.alerts[alert.ID] = alert
			am.mu.Unlock()

			// Notify subscribers
			am.notifySubscribers(alert)
		}
	}
}

// Subscribe adds an alert subscriber
func (am *AlertManager) Subscribe(name string, subscriber AlertSubscriber) {
	am.mu.Lock()
	defer am.mu.Unlock()
	am.subscribers[name] = subscriber
}

// notifySubscribers notifies all subscribers of an alert
func (am *AlertManager) notifySubscribers(alert *Alert) {
	am.mu.RLock()
	subscribers := make(map[string]AlertSubscriber)
	for k, v := range am.subscribers {
		subscribers[k] = v
	}
	am.mu.RUnlock()

	for _, subscriber := range subscribers {
		go subscriber.OnAlert(alert)
	}
}

// Helper methods
func (am *AlertManager) getMetricValue(metrics *MetricsCollector, name string) float64 {
	switch name {
	case "error_rate":
		return metrics.GetErrorRate()
	case "throughput":
		return metrics.GetThroughput()
	case "cache_hit_ratio":
		hits := atomic.LoadInt64(&metrics.cacheHits)
		total := hits + atomic.LoadInt64(&metrics.cacheMisses)
		if total == 0 {
			return 0
		}
		return float64(hits) / float64(total) * 100
	default:
		return 0
	}
}

func (am *AlertManager) checkCondition(value float64, operator string, threshold float64) bool {
	switch operator {
	case ">":
		return value > threshold
	case "<":
		return value < threshold
	case "==":
		return value == threshold
	case "!=":
		return value != threshold
	default:
		return false
	}
}

// ========== Interfaces ==========

type SpanCollector interface {
	CollectSpan(span *Span) error
}

type AlertSubscriber interface {
	OnAlert(alert *Alert)
}

// Prometheus metrics export
func (mc *MetricsCollector) ExportPrometheusMetrics() string {
	output := "# HELP minio_put_ops_total Total PUT operations\n"
	output += "# TYPE minio_put_ops_total counter\n"
	output += fmt.Sprintf("minio_put_ops_total %d\n", atomic.LoadInt64(&mc.putOpsTotal))
	
	output += "# HELP minio_get_ops_total Total GET operations\n"
	output += "# TYPE minio_get_ops_total counter\n"
	output += fmt.Sprintf("minio_get_ops_total %d\n", atomic.LoadInt64(&mc.getOpsTotal))
	
	output += "# HELP minio_error_rate Error rate percentage\n"
	output += "# TYPE minio_error_rate gauge\n"
	output += fmt.Sprintf("minio_error_rate %.2f\n", mc.GetErrorRate())
	
	output += "# HELP minio_throughput Operations per second\n"
	output += "# TYPE minio_throughput gauge\n"
	output += fmt.Sprintf("minio_throughput %.2f\n", mc.GetThroughput())
	
	return output
}
