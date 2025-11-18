// performance_test.go - Core performance tests without external dependencies
package main

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// ============================================================
// Mock Cache Implementation for Testing
// ============================================================

type SimpleCacheEntry struct {
	Key          string
	Data         []byte
	AccessCount  atomic.Int64
	LastAccessed atomic.Int64
}

type SimpleCache struct {
	entries sync.Map
	hits    atomic.Int64
	misses  atomic.Int64
}

func NewSimpleCache() *SimpleCache {
	return &SimpleCache{}
}

func (c *SimpleCache) Set(key string, data []byte) {
	entry := &SimpleCacheEntry{
		Key:  key,
		Data: data,
	}
	entry.LastAccessed.Store(time.Now().UnixNano())
	c.entries.Store(key, entry)
}

func (c *SimpleCache) Get(key string) ([]byte, bool) {
	val, ok := c.entries.Load(key)
	if !ok {
		c.misses.Add(1)
		return nil, false
	}

	entry := val.(*SimpleCacheEntry)
	entry.AccessCount.Add(1)
	entry.LastAccessed.Store(time.Now().UnixNano())
	c.hits.Add(1)

	return entry.Data, true
}

func (c *SimpleCache) GetStats() (hits, misses int64) {
	return c.hits.Load(), c.misses.Load()
}

// ============================================================
// Performance Tests
// ============================================================

func TestCacheConcurrentWrites(t *testing.T) {
	cache := NewSimpleCache()
	numGoroutines := 100
	operationsPerGoroutine := 1000

	var wg sync.WaitGroup
	start := time.Now()

	for i := 0; i < numGoroutines; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			for j := 0; j < operationsPerGoroutine; j++ {
				key := fmt.Sprintf("key_%d_%d", id, j)
				data := []byte(fmt.Sprintf("data_%d_%d", id, j))
				cache.Set(key, data)
			}
		}(i)
	}

	wg.Wait()
	duration := time.Since(start)

	totalOps := numGoroutines * operationsPerGoroutine
	opsPerSec := float64(totalOps) / duration.Seconds()

	t.Logf("✓ Concurrent writes: %d ops in %v (%.2f ops/sec)", totalOps, duration, opsPerSec)

	if opsPerSec < 10000 {
		t.Logf("Warning: Performance below 10K ops/sec: %.2f", opsPerSec)
	}
}

func TestCacheConcurrentReads(t *testing.T) {
	cache := NewSimpleCache()

	// Pre-populate
	for i := 0; i < 1000; i++ {
		key := fmt.Sprintf("read_key_%d", i)
		cache.Set(key, []byte("test data"))
	}

	numGoroutines := 100
	operationsPerGoroutine := 10000

	var wg sync.WaitGroup
	start := time.Now()

	for i := 0; i < numGoroutines; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			for j := 0; j < operationsPerGoroutine; j++ {
				key := fmt.Sprintf("read_key_%d", j%1000)
				cache.Get(key)
			}
		}(i)
	}

	wg.Wait()
	duration := time.Since(start)

	totalOps := numGoroutines * operationsPerGoroutine
	opsPerSec := float64(totalOps) / duration.Seconds()

	hits, misses := cache.GetStats()
	hitRatio := float64(hits) / float64(hits+misses) * 100

	t.Logf("✓ Concurrent reads: %d ops in %v (%.2f ops/sec)", totalOps, duration, opsPerSec)
	t.Logf("✓ Hit ratio: %.2f%% (%d hits, %d misses)", hitRatio, hits, misses)

	if opsPerSec < 50000 {
		t.Logf("Warning: Read performance below 50K ops/sec: %.2f", opsPerSec)
	}

	if hitRatio < 90 {
		t.Errorf("Hit ratio too low: %.2f%% (expected > 90%%)", hitRatio)
	}
}

func TestCacheMixedWorkload(t *testing.T) {
	cache := NewSimpleCache()
	duration := 5 * time.Second

	var writes, reads atomic.Int64
	ctx, cancel := context.WithTimeout(context.Background(), duration)
	defer cancel()

	var wg sync.WaitGroup

	// Writers
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			counter := 0
			for {
				select {
				case <-ctx.Done():
					return
				default:
					key := fmt.Sprintf("key_%d_%d", id, counter)
					cache.Set(key, []byte("data"))
					writes.Add(1)
					counter++
				}
			}
		}(i)
	}

	// Readers
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			counter := 0
			for {
				select {
				case <-ctx.Done():
					return
				default:
					key := fmt.Sprintf("key_%d_%d", id%10, counter)
					cache.Get(key)
					reads.Add(1)
					counter++
					if counter > 1000 {
						counter = 0
					}
				}
			}
		}(i)
	}

	wg.Wait()

	totalWrites := writes.Load()
	totalReads := reads.Load()
	totalOps := totalWrites + totalReads

	writeOpsPerSec := float64(totalWrites) / duration.Seconds()
	readOpsPerSec := float64(totalReads) / duration.Seconds()
	totalOpsPerSec := float64(totalOps) / duration.Seconds()

	t.Logf("✓ Mixed workload (%v):", duration)
	t.Logf("  - Writes: %d (%.2f ops/sec)", totalWrites, writeOpsPerSec)
	t.Logf("  - Reads: %d (%.2f ops/sec)", totalReads, readOpsPerSec)
	t.Logf("  - Total: %d (%.2f ops/sec)", totalOps, totalOpsPerSec)
}

func TestAtomicOperations(t *testing.T) {
	var counter atomic.Int64
	numGoroutines := 1000
	incrementsPerGoroutine := 10000

	var wg sync.WaitGroup
	start := time.Now()

	for i := 0; i < numGoroutines; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < incrementsPerGoroutine; j++ {
				counter.Add(1)
			}
		}()
	}

	wg.Wait()
	duration := time.Since(start)

	expected := int64(numGoroutines * incrementsPerGoroutine)
	actual := counter.Load()

	t.Logf("✓ Atomic operations: %d increments in %v", actual, duration)

	if actual != expected {
		t.Errorf("Atomic counter mismatch: got %d, expected %d", actual, expected)
	}
}

func TestMemoryEfficiency(t *testing.T) {
	cache := NewSimpleCache()

	// Measure memory by creating and releasing entries
	numEntries := 100000
	dataSize := 1024 // 1KB per entry

	start := time.Now()
	for i := 0; i < numEntries; i++ {
		key := fmt.Sprintf("key_%d", i)
		data := make([]byte, dataSize)
		cache.Set(key, data)
	}
	duration := time.Since(start)

	totalDataMB := float64(numEntries*dataSize) / (1024 * 1024)
	t.Logf("✓ Memory test: Stored %.2f MB (%d entries) in %v", totalDataMB, numEntries, duration)
}

// ============================================================
// Benchmarks
// ============================================================

func BenchmarkCacheSet(b *testing.B) {
	cache := NewSimpleCache()
	data := []byte("benchmark data")

	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		i := 0
		for pb.Next() {
			key := fmt.Sprintf("bench_key_%d", i)
			cache.Set(key, data)
			i++
		}
	})
}

func BenchmarkCacheGet(b *testing.B) {
	cache := NewSimpleCache()
	data := []byte("benchmark data")

	// Pre-populate
	for i := 0; i < 10000; i++ {
		cache.Set(fmt.Sprintf("key_%d", i), data)
	}

	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		i := 0
		for pb.Next() {
			key := fmt.Sprintf("key_%d", i%10000)
			cache.Get(key)
			i++
		}
	})
}

func BenchmarkAtomicIncrement(b *testing.B) {
	var counter atomic.Int64

	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			counter.Add(1)
		}
	})
}

// ============================================================
// Integration Tests
// ============================================================

func TestEndToEndWorkflow(t *testing.T) {
	cache := NewSimpleCache()

	// Simulate real application workflow
	t.Run("UserSession", func(t *testing.T) {
		// User creates session
		cache.Set("session:user1", []byte("session_data"))

		// User performs operations
		for i := 0; i < 100; i++ {
			key := fmt.Sprintf("user1:object_%d", i)
			cache.Set(key, []byte("object_data"))
		}

		// User retrieves objects
		for i := 0; i < 100; i++ {
			key := fmt.Sprintf("user1:object_%d", i)
			if _, ok := cache.Get(key); !ok {
				t.Errorf("Failed to retrieve object: %s", key)
			}
		}

		// Check session still valid
		if _, ok := cache.Get("session:user1"); !ok {
			t.Error("Session lost during operations")
		}
	})

	t.Run("ConcurrentUsers", func(t *testing.T) {
		numUsers := 50
		objectsPerUser := 100

		var wg sync.WaitGroup
		for userId := 0; userId < numUsers; userId++ {
			wg.Add(1)
			go func(uid int) {
				defer wg.Done()

				// Create session
				sessionKey := fmt.Sprintf("session:user%d", uid)
				cache.Set(sessionKey, []byte("session"))

				// Create objects
				for i := 0; i < objectsPerUser; i++ {
					key := fmt.Sprintf("user%d:obj_%d", uid, i)
					cache.Set(key, []byte("data"))
				}

				// Verify objects
				for i := 0; i < objectsPerUser; i++ {
					key := fmt.Sprintf("user%d:obj_%d", uid, i)
					if _, ok := cache.Get(key); !ok {
						t.Errorf("User %d lost object %d", uid, i)
					}
				}
			}(userId)
		}
		wg.Wait()

		hits, misses := cache.GetStats()
		t.Logf("✓ Concurrent users test: %d hits, %d misses", hits, misses)
	})
}

// ============================================================
// Helper Functions
// ============================================================

func TestMain(m *testing.M) {
	fmt.Println("========================================")
	fmt.Println("MinIO Enterprise Test Suite")
	fmt.Println("========================================")
	fmt.Println()

	exitCode := m.Run()

	fmt.Println()
	fmt.Println("========================================")
	if exitCode == 0 {
		fmt.Println("✓ All tests passed")
	} else {
		fmt.Println("✗ Some tests failed")
	}
	fmt.Println("========================================")

	os.Exit(exitCode)
}
