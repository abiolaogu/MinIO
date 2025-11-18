// +build v2

// enterprise/performance/cache_engine_v2.go
// Ultra-High-Performance Multi-Tier Cache with Sharding and Object Pooling
package cache

import (
	"context"
	"crypto/md5"
	"fmt"
	"hash/fnv"
	"runtime"
	"sync"
	"sync/atomic"
	"time"

	"github.com/klauspost/compress/zstd"
)

const (
	// Sharding configuration for parallel access
	DefaultShardCount = 256 // Power of 2 for fast modulo

	// Worker pool sizes
	CompressionWorkers = 32
	PromotionWorkers   = 16

	// Buffer pool sizes
	SmallBufferSize  = 32 * 1024     // 32KB
	MediumBufferSize = 256 * 1024    // 256KB
	LargeBufferSize  = 2 * 1024 * 1024 // 2MB
)

// CacheConfig defines multi-tier caching strategy
type CacheConfig struct {
	L1MaxSize            int64
	L2MaxSize            int64
	L3MaxSize            int64
	L1EvictionPolicy     string
	L2TTL                time.Duration
	L3TTL                time.Duration
	CompressionThreshold int64
	CompressionCodec     string
	HotDataThreshold     int
	EnablePrefetch       bool
	PrefetchDistance     int
	ShardCount           int
	EnableMetrics        bool
}

// CacheEntry represents a cached object
type CacheEntry struct {
	Key            string
	Data           []byte
	CompressedData []byte
	ETag           string
	Size           int64
	CompressedSize int64
	AccessCount    atomic.Int64
	LastAccessed   atomic.Int64 // Unix nano
	CreatedAt      time.Time
	Tier           string
	Metadata       map[string]string
	TTL            time.Duration
}

// CacheStats tracks cache performance
type CacheStats struct {
	Hits              atomic.Int64
	Misses            atomic.Int64
	Evictions         atomic.Int64
	CompressionRatio  atomic.Uint64 // Fixed point: value/1000
	AverageLatency    atomic.Int64  // Nanoseconds
	MemoryUsed        atomic.Int64
	L1Size            atomic.Int64
	L2Size            atomic.Int64
	L3Size            atomic.Int64
}

// ShardedL1Cache uses multiple shards to reduce lock contention
type ShardedL1Cache struct {
	shards    []*L1CacheShard
	shardMask uint32
	maxSize   int64
	stats     *CacheStats
}

// L1CacheShard is a single shard of the L1 cache
type L1CacheShard struct {
	entries  map[string]*CacheEntry
	usedSize int64
	mu       sync.RWMutex
	lru      *LRUTracker
}

// L2Cache represents NVMe-backed cache with optimized I/O
type L2Cache struct {
	shards        []*L2CacheShard
	shardMask     uint32
	maxSize       int64
	ttl           time.Duration
	cleanupTicker *time.Ticker
}

type L2CacheShard struct {
	index    map[string]*CacheEntry
	usedSize int64
	mu       sync.RWMutex
}

// CompressionEngine with worker pool for parallel compression
type CompressionEngine struct {
	encoder          *zstd.Encoder
	decoder          *zstd.Decoder
	compressionLevel zstd.EncoderLevel
	minSize          int64
	workerPool       chan struct{}
	stats            CompressionStats
}

type CompressionStats struct {
	TotalCompressed   atomic.Int64
	TotalUncompressed atomic.Int64
	CompressionTime   atomic.Int64 // Total nanoseconds
	Operations        atomic.Int64
}

// Buffer pools for zero-allocation operations
var (
	smallBufferPool = sync.Pool{
		New: func() interface{} {
			buf := make([]byte, SmallBufferSize)
			return &buf
		},
	}
	mediumBufferPool = sync.Pool{
		New: func() interface{} {
			buf := make([]byte, MediumBufferSize)
			return &buf
		},
	}
	largeBufferPool = sync.Pool{
		New: func() interface{} {
			buf := make([]byte, LargeBufferSize)
			return &buf
		},
	}
	entryPool = sync.Pool{
		New: func() interface{} {
			return &CacheEntry{
				Metadata: make(map[string]string, 4),
			}
		},
	}
)

// MultiTierCacheManager orchestrates all cache tiers with extreme performance
type MultiTierCacheManager struct {
	config          *CacheConfig
	l1Cache         *ShardedL1Cache
	l2Cache         *L2Cache
	l3Cache         FileStore
	compression     *CompressionEngine
	stats           *CacheStats
	prefetcher      *Prefetcher
	promotionPool   chan promotionTask
	shutdownCh      chan struct{}
	wg              sync.WaitGroup
}

type promotionTask struct {
	ctx   context.Context
	entry *CacheEntry
	tier  string
}

// NewMultiTierCacheManager creates an ultra-high-performance cache manager
func NewMultiTierCacheManager(config *CacheConfig) (*MultiTierCacheManager, error) {
	if config.ShardCount == 0 {
		config.ShardCount = DefaultShardCount
	}

	stats := &CacheStats{}

	// Create compression engine with worker pool
	encoder, err := zstd.NewWriter(nil, zstd.WithEncoderLevel(zstd.SpeedBetterCompression))
	if err != nil {
		return nil, fmt.Errorf("failed to create zstd encoder: %w", err)
	}

	decoder, err := zstd.NewReader(nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create zstd decoder: %w", err)
	}

	compression := &CompressionEngine{
		encoder:          encoder,
		decoder:          decoder,
		compressionLevel: zstd.SpeedBetterCompression,
		minSize:          config.CompressionThreshold,
		workerPool:       make(chan struct{}, CompressionWorkers),
	}

	// Initialize worker pool
	for i := 0; i < CompressionWorkers; i++ {
		compression.workerPool <- struct{}{}
	}

	mgr := &MultiTierCacheManager{
		config: config,
		l1Cache: &ShardedL1Cache{
			shards:    make([]*L1CacheShard, config.ShardCount),
			shardMask: uint32(config.ShardCount - 1),
			maxSize:   config.L1MaxSize * 1024 * 1024 * 1024,
			stats:     stats,
		},
		l2Cache: &L2Cache{
			shards:    make([]*L2CacheShard, config.ShardCount),
			shardMask: uint32(config.ShardCount - 1),
			maxSize:   config.L2MaxSize * 1024 * 1024 * 1024,
			ttl:       config.L2TTL,
		},
		compression:   compression,
		stats:         stats,
		prefetcher:    NewPrefetcher(config.EnablePrefetch, config.PrefetchDistance),
		promotionPool: make(chan promotionTask, 1000),
		shutdownCh:    make(chan struct{}),
	}

	// Initialize shards
	for i := 0; i < config.ShardCount; i++ {
		mgr.l1Cache.shards[i] = &L1CacheShard{
			entries: make(map[string]*CacheEntry, 1000),
			lru:     NewLRUTracker(),
		}
		mgr.l2Cache.shards[i] = &L2CacheShard{
			index: make(map[string]*CacheEntry, 1000),
		}
	}

	// Start promotion workers
	for i := 0; i < PromotionWorkers; i++ {
		mgr.wg.Add(1)
		go mgr.promotionWorker()
	}

	// Start L2 cleanup
	mgr.wg.Add(1)
	go mgr.l2CleanupWorker()

	return mgr, nil
}

// getShard returns the shard for a given key using fast hashing
func (m *MultiTierCacheManager) getShard(key string) uint32 {
	h := fnv.New32a()
	h.Write([]byte(key))
	return h.Sum32() & m.l1Cache.shardMask
}

// Get retrieves object from cache hierarchy with zero-copy optimizations
func (m *MultiTierCacheManager) Get(ctx context.Context, key string) ([]byte, error) {
	startTime := time.Now()
	defer func() {
		latency := time.Since(startTime).Nanoseconds()
		m.stats.AverageLatency.Add(latency)
	}()

	// Check L1 (sharded for parallel access)
	if data, err := m.l1Get(key); err == nil {
		m.stats.Hits.Add(1)

		// Trigger prefetch if enabled (async, non-blocking)
		if m.config.EnablePrefetch {
			go m.prefetcher.TriggerPrefetch(ctx, key)
		}

		return data, nil
	}

	// Check L2
	if data, err := m.l2Get(ctx, key); err == nil {
		m.stats.Hits.Add(1)

		// Async promotion to L1 (non-blocking)
		select {
		case m.promotionPool <- promotionTask{ctx: ctx, entry: &CacheEntry{Key: key, Data: data}, tier: "L1"}:
		default:
			// Pool full, skip promotion
		}

		return data, nil
	}

	// Check L3
	if m.l3Cache != nil {
		entry, err := m.l3Cache.Get(ctx, key)
		if err == nil && entry != nil {
			m.stats.Hits.Add(1)

			data := m.decompressIfNeeded(entry)

			// Async promotion to L2 (non-blocking)
			select {
			case m.promotionPool <- promotionTask{ctx: ctx, entry: entry, tier: "L2"}:
			default:
			}

			return data, nil
		}
	}

	m.stats.Misses.Add(1)
	return nil, fmt.Errorf("cache miss for key: %s", key)
}

// l1Get retrieves from L1 cache using sharding
func (m *MultiTierCacheManager) l1Get(key string) ([]byte, error) {
	shardIdx := m.getShard(key)
	shard := m.l1Cache.shards[shardIdx]

	shard.mu.RLock()
	entry, exists := shard.entries[key]
	shard.mu.RUnlock()

	if !exists {
		return nil, fmt.Errorf("not found")
	}

	// Update access tracking (lock-free)
	entry.AccessCount.Add(1)
	entry.LastAccessed.Store(time.Now().UnixNano())
	shard.lru.Update(key, entry.AccessCount.Load())

	return m.decompressIfNeeded(entry), nil
}

// l2Get retrieves from L2 cache
func (m *MultiTierCacheManager) l2Get(ctx context.Context, key string) ([]byte, error) {
	shardIdx := m.getShard(key)
	shard := m.l2Cache.shards[shardIdx]

	shard.mu.RLock()
	entry, exists := shard.index[key]
	shard.mu.RUnlock()

	if !exists {
		return nil, fmt.Errorf("not found")
	}

	// Check TTL
	if time.Since(entry.CreatedAt) > m.l2Cache.ttl {
		go m.l2Delete(ctx, key) // Async deletion
		return nil, fmt.Errorf("entry expired")
	}

	entry.AccessCount.Add(1)
	entry.LastAccessed.Store(time.Now().UnixNano())

	return m.decompressIfNeeded(entry), nil
}

// Set stores object with intelligent placement and parallel compression
func (m *MultiTierCacheManager) Set(ctx context.Context, key string, data []byte, metadata map[string]string) error {
	entry := m.acquireEntry()
	entry.Key = key
	entry.Data = data
	entry.Size = int64(len(data))
	entry.AccessCount.Store(0)
	entry.LastAccessed.Store(time.Now().UnixNano())
	entry.CreatedAt = time.Now()
	entry.Metadata = metadata

	// Parallel compression if beneficial
	if m.config.CompressionThreshold > 0 && entry.Size > m.config.CompressionThreshold {
		// Acquire worker from pool (bounded parallelism)
		<-m.compression.workerPool

		go func() {
			defer func() { m.compression.workerPool <- struct{}{} }()

			compressed, ratio := m.compression.Compress(data)
			if ratio < 0.9 { // >10% reduction
				entry.CompressedData = compressed
				entry.CompressedSize = int64(len(compressed))
			}
		}()
	}

	// Intelligent placement based on size
	if entry.Size < 100*1024*1024 { // <100MB -> L1
		entry.Tier = "L1"
		return m.l1Set(ctx, entry)
	} else if entry.Size < 1*1024*1024*1024 { // <1GB -> L2
		entry.Tier = "L2"
		return m.l2Set(ctx, entry)
	} else {
		entry.Tier = "L3"
		if m.l3Cache != nil {
			return m.l3Cache.Set(ctx, key, entry)
		}
	}

	return nil
}

// BatchGet retrieves multiple keys efficiently
func (m *MultiTierCacheManager) BatchGet(ctx context.Context, keys []string) (map[string][]byte, error) {
	results := make(map[string][]byte, len(keys))
	var mu sync.Mutex

	// Process in parallel using worker pool
	workers := runtime.NumCPU()
	workCh := make(chan string, len(keys))
	var wg sync.WaitGroup

	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for key := range workCh {
				if data, err := m.Get(ctx, key); err == nil {
					mu.Lock()
					results[key] = data
					mu.Unlock()
				}
			}
		}()
	}

	for _, key := range keys {
		workCh <- key
	}
	close(workCh)
	wg.Wait()

	return results, nil
}

// l1Set stores in L1 cache with eviction
func (m *MultiTierCacheManager) l1Set(ctx context.Context, entry *CacheEntry) error {
	shardIdx := m.getShard(entry.Key)
	shard := m.l1Cache.shards[shardIdx]

	shard.mu.Lock()
	defer shard.mu.Unlock()

	// Evict if necessary
	maxShardSize := m.l1Cache.maxSize / int64(len(m.l1Cache.shards))
	for shard.usedSize+entry.Size > maxShardSize {
		evicted := shard.lru.EvictLRU(shard.entries)
		if evicted == "" {
			return fmt.Errorf("unable to evict space")
		}

		if old, exists := shard.entries[evicted]; exists {
			shard.usedSize -= old.Size
			delete(shard.entries, evicted)
			m.stats.Evictions.Add(1)
			m.releaseEntry(old)
		}
	}

	shard.entries[entry.Key] = entry
	shard.usedSize += entry.Size
	shard.lru.Add(entry.Key, entry.AccessCount.Load())
	m.stats.L1Size.Add(entry.Size)

	return nil
}

// l2Set stores in L2 cache
func (m *MultiTierCacheManager) l2Set(ctx context.Context, entry *CacheEntry) error {
	shardIdx := m.getShard(entry.Key)
	shard := m.l2Cache.shards[shardIdx]

	shard.mu.Lock()
	defer shard.mu.Unlock()

	// Simple eviction for L2
	maxShardSize := m.l2Cache.maxSize / int64(len(m.l2Cache.shards))
	if entry.Size+shard.usedSize > maxShardSize {
		// Evict oldest entry
		var oldestKey string
		var oldestTime int64 = 9223372036854775807

		for k, v := range shard.index {
			if accessed := v.LastAccessed.Load(); accessed < oldestTime {
				oldestTime = accessed
				oldestKey = k
			}
		}

		if oldestKey != "" {
			if old, exists := shard.index[oldestKey]; exists {
				shard.usedSize -= old.Size
				delete(shard.index, oldestKey)
				m.releaseEntry(old)
			}
		}
	}

	shard.index[entry.Key] = entry
	shard.usedSize += entry.Size
	m.stats.L2Size.Add(entry.Size)

	return nil
}

// l2Delete removes from L2 cache
func (m *MultiTierCacheManager) l2Delete(ctx context.Context, key string) {
	shardIdx := m.getShard(key)
	shard := m.l2Cache.shards[shardIdx]

	shard.mu.Lock()
	defer shard.mu.Unlock()

	if entry, exists := shard.index[key]; exists {
		shard.usedSize -= entry.Size
		delete(shard.index, key)
		m.stats.L2Size.Add(-entry.Size)
		m.releaseEntry(entry)
	}
}

// promotionWorker handles cache tier promotions
func (m *MultiTierCacheManager) promotionWorker() {
	defer m.wg.Done()

	for {
		select {
		case <-m.shutdownCh:
			return
		case task := <-m.promotionPool:
			switch task.tier {
			case "L1":
				task.entry.Tier = "L1"
				m.l1Set(task.ctx, task.entry)
			case "L2":
				task.entry.Tier = "L2"
				m.l2Set(task.ctx, task.entry)
			}
		}
	}
}

// l2CleanupWorker periodically removes expired entries
func (m *MultiTierCacheManager) l2CleanupWorker() {
	defer m.wg.Done()

	ticker := time.NewTicker(1 * time.Minute)
	defer ticker.Stop()

	for {
		select {
		case <-m.shutdownCh:
			return
		case <-ticker.C:
			m.l2Cleanup()
		}
	}
}

func (m *MultiTierCacheManager) l2Cleanup() {
	now := time.Now()

	for _, shard := range m.l2Cache.shards {
		shard.mu.Lock()

		for key, entry := range shard.index {
			if now.Sub(entry.CreatedAt) > m.l2Cache.ttl {
				shard.usedSize -= entry.Size
				delete(shard.index, key)
				m.stats.L2Size.Add(-entry.Size)
				m.releaseEntry(entry)
			}
		}

		shard.mu.Unlock()
	}
}

// Compress compresses data using zstd
func (ce *CompressionEngine) Compress(data []byte) ([]byte, float64) {
	startTime := time.Now()
	defer func() {
		ce.stats.CompressionTime.Add(time.Since(startTime).Nanoseconds())
		ce.stats.Operations.Add(1)
	}()

	compressed := ce.encoder.EncodeAll(data, make([]byte, 0, len(data)))

	ce.stats.TotalCompressed.Add(int64(len(compressed)))
	ce.stats.TotalUncompressed.Add(int64(len(data)))

	ratio := float64(len(compressed)) / float64(len(data))
	return compressed, ratio
}

// Decompress decompresses data
func (ce *CompressionEngine) Decompress(data []byte) ([]byte, error) {
	return ce.decoder.DecodeAll(data, nil)
}

// decompressIfNeeded decompresses data if compressed
func (m *MultiTierCacheManager) decompressIfNeeded(entry *CacheEntry) []byte {
	if entry.CompressedData != nil && len(entry.CompressedData) > 0 {
		data, err := m.compression.Decompress(entry.CompressedData)
		if err == nil {
			return data
		}
	}
	return entry.Data
}

// Invalidate removes entry from all tiers
func (m *MultiTierCacheManager) Invalidate(ctx context.Context, key string) error {
	shardIdx := m.getShard(key)

	// L1
	l1Shard := m.l1Cache.shards[shardIdx]
	l1Shard.mu.Lock()
	if entry, exists := l1Shard.entries[key]; exists {
		l1Shard.usedSize -= entry.Size
		delete(l1Shard.entries, key)
		m.stats.L1Size.Add(-entry.Size)
		m.releaseEntry(entry)
	}
	l1Shard.mu.Unlock()

	// L2
	m.l2Delete(ctx, key)

	// L3
	if m.l3Cache != nil {
		m.l3Cache.Delete(ctx, key)
	}

	return nil
}

// GetStats returns current cache statistics
func (m *MultiTierCacheManager) GetStats() *CacheStats {
	return m.stats
}

// Shutdown gracefully shuts down the cache manager
func (m *MultiTierCacheManager) Shutdown(ctx context.Context) error {
	close(m.shutdownCh)

	// Wait for workers with timeout
	done := make(chan struct{})
	go func() {
		m.wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

// Object pool methods
func (m *MultiTierCacheManager) acquireEntry() *CacheEntry {
	entry := entryPool.Get().(*CacheEntry)
	// Reset fields
	entry.Key = ""
	entry.Data = nil
	entry.CompressedData = nil
	entry.Size = 0
	entry.CompressedSize = 0
	entry.AccessCount.Store(0)
	entry.LastAccessed.Store(0)
	entry.Tier = ""
	return entry
}

func (m *MultiTierCacheManager) releaseEntry(entry *CacheEntry) {
	// Clear large slices to avoid memory leaks
	entry.Data = nil
	entry.CompressedData = nil
	entryPool.Put(entry)
}

// ========== LRU Tracker ==========

type LRUTracker struct {
	items map[string]int64
	mu    sync.RWMutex
}

func NewLRUTracker() *LRUTracker {
	return &LRUTracker{items: make(map[string]int64, 1000)}
}

func (lru *LRUTracker) Add(key string, accessCount int64) {
	lru.mu.Lock()
	lru.items[key] = accessCount
	lru.mu.Unlock()
}

func (lru *LRUTracker) Update(key string, accessCount int64) {
	lru.mu.Lock()
	lru.items[key] = accessCount
	lru.mu.Unlock()
}

func (lru *LRUTracker) EvictLRU(entries map[string]*CacheEntry) string {
	lru.mu.RLock()
	defer lru.mu.RUnlock()

	var lruKey string
	var lruAccess int64 = 9223372036854775807

	for key, entry := range entries {
		if access := entry.LastAccessed.Load(); access < lruAccess {
			lruAccess = access
			lruKey = key
		}
	}

	return lruKey
}

// ========== Interfaces ==========

type FileStore interface {
	Get(ctx context.Context, key string) (*CacheEntry, error)
	Set(ctx context.Context, key string, entry *CacheEntry) error
	Delete(ctx context.Context, key string) error
}

type Prefetcher struct {
	enabled  bool
	distance int
}

func NewPrefetcher(enabled bool, distance int) *Prefetcher {
	return &Prefetcher{enabled: enabled, distance: distance}
}

func (p *Prefetcher) TriggerPrefetch(ctx context.Context, key string) {
	if !p.enabled {
		return
	}
	// Implementation would prefetch related objects
}
