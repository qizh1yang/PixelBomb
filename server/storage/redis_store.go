// Package storage provides persistent tombstone storage backends.
package storage

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
)

// TombstoneData is the serializable payload stored in Redis.
type TombstoneData struct {
	PlayerID     string `json:"player_id"`
	RoomID       string `json:"room_id"`
	SessionID    int64  `json:"session_id"`
	DisconnectAt int64  `json:"disconnect_at"` // unix timestamp
	ExpireAt     int64  `json:"expire_at"`     // unix timestamp

	// Snapshot contains the selective player state snapshot.
	Snapshot *SnapshotData `json:"snapshot,omitempty"`
}

// SnapshotData contains only the safe-to-restore fields from PlayerState.
type SnapshotData struct {
	X             float64 `json:"x"`
	Y             float64 `json:"y"`
	VX            float64 `json:"vx"`
	VY            float64 `json:"vy"`
	BombCap       int     `json:"bomb_cap"`
	RadiusCap     int     `json:"radius_cap"`
	SpeedCap      float64 `json:"speed_cap"`
	ShieldCap     int     `json:"shield_cap"`
	BombCurrent   int     `json:"bomb_current"`
	RadiusCurrent int     `json:"radius_current"`
	SpeedCurrent  float64 `json:"speed_current"`
	ShieldCurrent int     `json:"shield_current"`
}

const (
	// RedisKeyPrefix is prepended to all tombstone keys.
	RedisKeyPrefix = "tombstone:"

	// DefaultRedisAddr is the default Redis address.
	DefaultRedisAddr = "127.0.0.1:6379"
)

// RedisTombstoneStore stores tombstones in Redis with TTL-based auto-expiry.
// It also maintains a local shadow set of pending cleanups for the central sweeper.
type RedisTombstoneStore struct {
	client *redis.Client
	mu     sync.RWMutex
	// pendingCleanups tracks (playerID, roomID) by token for the sweeper.
	// Key: token, Value: cleanup info for when TTL expires.
	pendingCleanups map[string]*PendingCleanup
}

// PendingCleanup holds the info needed to hard-remove a player after tombstone expiry.
type PendingCleanup struct {
	PlayerID string
	RoomID   string
	ExpireAt time.Time
}

// NewRedisTombstoneStore creates a new Redis-backed tombstone store.
// Reads REDIS_ADDR from env, falls back to DefaultRedisAddr.
func NewRedisTombstoneStore() *RedisTombstoneStore {
	addr := os.Getenv("REDIS_ADDR")
	if addr == "" {
		addr = DefaultRedisAddr
	}

	client := redis.NewClient(&redis.Options{
		Addr:         addr,
		Password:     os.Getenv("REDIS_PASSWORD"),
		DB:           0,
		DialTimeout:  3 * time.Second,
		ReadTimeout:  2 * time.Second,
		WriteTimeout: 2 * time.Second,
	})

	return &RedisTombstoneStore{
		client:          client,
		pendingCleanups: make(map[string]*PendingCleanup),
	}
}

// Ping checks Redis connectivity.
func (s *RedisTombstoneStore) Ping(ctx context.Context) error {
	return s.client.Ping(ctx).Err()
}

// Store saves a tombstone in Redis with TTL = 30 seconds.
// Also tracks it locally for the sweeper.
func (s *RedisTombstoneStore) Store(ctx context.Context, token string, data *TombstoneData) error {
	payload, err := json.Marshal(data)
	if err != nil {
		return fmt.Errorf("marshal tombstone: %w", err)
	}

	ttl := time.Until(time.Unix(data.ExpireAt, 0))
	if ttl <= 0 {
		ttl = 30 * time.Second
	}

	key := RedisKeyPrefix + token
	if err := s.client.SetEx(ctx, key, payload, ttl).Err(); err != nil {
		return fmt.Errorf("redis setex: %w", err)
	}

	// Track locally for sweeper
	s.mu.Lock()
	s.pendingCleanups[token] = &PendingCleanup{
		PlayerID: data.PlayerID,
		RoomID:   data.RoomID,
		ExpireAt: time.Unix(data.ExpireAt, 0),
	}
	s.mu.Unlock()

	return nil
}

// Consume atomically retrieves and deletes a tombstone from Redis.
// Uses a Lua script to ensure atomic GET+DEL.
// Returns the tombstone data and true if found, nil and false otherwise.
func (s *RedisTombstoneStore) Consume(ctx context.Context, token string) (*TombstoneData, bool) {
	key := RedisKeyPrefix + token

	// Atomic GET + DEL via Lua script (prevents double-consumption)
	script := `
		local val = redis.call('GET', KEYS[1])
		if val then
			redis.call('DEL', KEYS[1])
			return val
		end
		return nil
	`
	result, err := s.client.Eval(ctx, script, []string{key}).Result()
	if err != nil || result == nil {
		return nil, false
	}

	val, ok := result.(string)
	if !ok {
		return nil, false
	}

	var data TombstoneData
	if err := json.Unmarshal([]byte(val), &data); err != nil {
		log.Printf("[RedisStore] Failed to unmarshal tombstone data: %v", err)
		return nil, false
	}

	// Remove from local tracking
	s.mu.Lock()
	delete(s.pendingCleanups, token)
	s.mu.Unlock()

	return &data, true
}

// Delete removes a tombstone from Redis and local tracking.
func (s *RedisTombstoneStore) Delete(ctx context.Context, token string) {
	key := RedisKeyPrefix + token
	s.client.Del(ctx, key)

	s.mu.Lock()
	delete(s.pendingCleanups, token)
	s.mu.Unlock()
}

// DeleteByPlayerID removes all tombstones for a given player.
func (s *RedisTombstoneStore) DeleteByPlayerID(ctx context.Context, playerID string) {
	s.mu.Lock()
	for token, cleanup := range s.pendingCleanups {
		if cleanup.PlayerID == playerID {
			s.client.Del(ctx, RedisKeyPrefix+token)
			delete(s.pendingCleanups, token)
		}
	}
	s.mu.Unlock()
}

// GetExpiredCleanups returns all locally-tracked tombstones whose TTL has
// elapsed and who no longer exist in Redis (confirming they weren't consumed).
// This is called by the central sweeper.
func (s *RedisTombstoneStore) GetExpiredCleanups(ctx context.Context) []*PendingCleanup {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	var expired []*PendingCleanup

	for token, cleanup := range s.pendingCleanups {
		if now.After(cleanup.ExpireAt) {
			// Double-check: is the Redis key really gone?
			exists, err := s.client.Exists(ctx, RedisKeyPrefix+token).Result()
			if err != nil || exists == 0 {
				// Key is gone (expired or consumed) — safe to hard-cleanup
				expired = append(expired, cleanup)
				delete(s.pendingCleanups, token)
			}
			// If key still exists (clock skew?), skip and try next sweep
		}
	}

	return expired
}

// Close releases the Redis connection.
func (s *RedisTombstoneStore) Close() error {
	return s.client.Close()
}
