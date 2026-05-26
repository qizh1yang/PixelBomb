// Package logic contains the core game business logic and Nano components.
package logic

import (
	"context"
	"log"
	"sync"
	"time"

	"bomberman-server/storage"
)

// TombstoneStore is the interface for tombstone persistence backends.
// Implementations: MemoryTombstoneStore (in-memory), or the Redis-backed
// store in package storage (used via TombstoneStoreAdapter).
type TombstoneStore interface {
	Store(token string, data *TombstoneData) error
	Consume(token string) (*TombstoneData, bool)
	Delete(token string)
	DeleteByPlayerID(playerID string)
	Count() int
}

// TombstoneData is the serializable tombstone payload (used by both memory and Redis).
type TombstoneData struct {
	PlayerID     string              `json:"player_id"`
	RoomID       string              `json:"room_id"`
	SessionID    int64               `json:"session_id"`
	DisconnectAt time.Time           `json:"disconnect_at"`
	ExpireAt     time.Time           `json:"expire_at"`
	Snapshot     *PlayerState        `json:"snapshot,omitempty"`
}

// ── In-memory Tombstone Store ──

// MemoryTombstoneStore is a thread-safe in-memory tombstone store with central sweeper support.
type MemoryTombstoneStore struct {
	mu         sync.RWMutex
	tombstones map[string]*TombstoneData
}

// NewMemoryTombstoneStore creates an empty in-memory store.
func NewMemoryTombstoneStore() *MemoryTombstoneStore {
	return &MemoryTombstoneStore{
		tombstones: make(map[string]*TombstoneData),
	}
}

func (s *MemoryTombstoneStore) Store(token string, data *TombstoneData) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.tombstones[token] = data
	return nil
}

// Consume atomically retrieves and deletes a non-expired tombstone.
// Returns nil, false if not found or expired.
func (s *MemoryTombstoneStore) Consume(token string) (*TombstoneData, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	t, ok := s.tombstones[token]
	if !ok {
		return nil, false
	}
	if time.Now().After(t.ExpireAt) {
		return nil, false
	}
	delete(s.tombstones, token)
	return t, true
}

func (s *MemoryTombstoneStore) Delete(token string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.tombstones, token)
}

func (s *MemoryTombstoneStore) DeleteByPlayerID(playerID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for k, v := range s.tombstones {
		if v.PlayerID == playerID {
			delete(s.tombstones, k)
		}
	}
}

func (s *MemoryTombstoneStore) Count() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.tombstones)
}

// GetExpiredAndRemove returns all expired tombstones and removes them atomically.
// Called by the central sweeper.
func (s *MemoryTombstoneStore) GetExpiredAndRemove() []*TombstoneData {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	var expired []*TombstoneData
	for token, t := range s.tombstones {
		if now.After(t.ExpireAt) {
			expired = append(expired, t)
			delete(s.tombstones, token)
		}
	}
	return expired
}

// ── Redis Adapter ──

// RedisTombstoneAdapter wraps storage.RedisTombstoneStore to implement TombstoneStore.
type RedisTombstoneAdapter struct {
	redis *storage.RedisTombstoneStore
}

// NewRedisTombstoneAdapter creates an adapter around the Redis store.
func NewRedisTombstoneAdapter(redisStore *storage.RedisTombstoneStore) *RedisTombstoneAdapter {
	return &RedisTombstoneAdapter{redis: redisStore}
}

func (a *RedisTombstoneAdapter) Store(token string, data *TombstoneData) error {
	sd := &storage.TombstoneData{
		PlayerID:     data.PlayerID,
		RoomID:       data.RoomID,
		SessionID:    data.SessionID,
		DisconnectAt: data.DisconnectAt.Unix(),
		ExpireAt:     data.ExpireAt.Unix(),
	}
	if data.Snapshot != nil {
		sd.Snapshot = &storage.SnapshotData{
			X:             data.Snapshot.X,
			Y:             data.Snapshot.Y,
			VX:            data.Snapshot.VX,
			VY:            data.Snapshot.VY,
			BombCap:       data.Snapshot.BombCap,
			RadiusCap:     data.Snapshot.RadiusCap,
			SpeedCap:      data.Snapshot.SpeedCap,
			ShieldCap:     data.Snapshot.ShieldCap,
			BombCurrent:   data.Snapshot.BombCurrent,
			RadiusCurrent: data.Snapshot.RadiusCurrent,
			SpeedCurrent:  data.Snapshot.SpeedCurrent,
			ShieldCurrent: data.Snapshot.ShieldCurrent,
		}
	}
	return a.redis.Store(context.Background(), token, sd)
}

func (a *RedisTombstoneAdapter) Consume(token string) (*TombstoneData, bool) {
	sd, ok := a.redis.Consume(context.Background(), token)
	if !ok || sd == nil {
		return nil, false
	}

	t := &TombstoneData{
		PlayerID:     sd.PlayerID,
		RoomID:       sd.RoomID,
		SessionID:    sd.SessionID,
		DisconnectAt: time.Unix(sd.DisconnectAt, 0),
		ExpireAt:     time.Unix(sd.ExpireAt, 0),
	}
	if sd.Snapshot != nil {
		t.Snapshot = &PlayerState{
			X:             sd.Snapshot.X,
			Y:             sd.Snapshot.Y,
			VX:            sd.Snapshot.VX,
			VY:            sd.Snapshot.VY,
			BombCap:       sd.Snapshot.BombCap,
			RadiusCap:     sd.Snapshot.RadiusCap,
			SpeedCap:      sd.Snapshot.SpeedCap,
			ShieldCap:     sd.Snapshot.ShieldCap,
			BombCurrent:   sd.Snapshot.BombCurrent,
			RadiusCurrent: sd.Snapshot.RadiusCurrent,
			SpeedCurrent:  sd.Snapshot.SpeedCurrent,
			ShieldCurrent: sd.Snapshot.ShieldCurrent,
		}
	}
	return t, true
}

func (a *RedisTombstoneAdapter) Delete(token string) {
	a.redis.Delete(context.Background(), token)
}

func (a *RedisTombstoneAdapter) DeleteByPlayerID(playerID string) {
	a.redis.DeleteByPlayerID(context.Background(), playerID)
}

func (a *RedisTombstoneAdapter) Count() int {
	// Redis adapter doesn't maintain an exact count; return 0 for gauge reporting.
	return 0
}

// GetExpiredCleanups returns cleanups for tombstones whose Redis TTL has elapsed.
func (a *RedisTombstoneAdapter) GetExpiredCleanups() []*storage.PendingCleanup {
	return a.redis.GetExpiredCleanups(context.Background())
}

// ── Global Store (backward-compatible singleton) ──

// GlobalTombstoneStore is the active tombstone store singleton.
// Defaults to in-memory; call UseRedisStore to switch.
var GlobalTombstoneStore TombstoneStore = NewMemoryTombstoneStore()

// UseRedisStore switches the global store to Redis-backed persistence.
func UseRedisStore(redisStore *storage.RedisTombstoneStore) {
	GlobalTombstoneStore = NewRedisTombstoneAdapter(redisStore)
	log.Println("[Tombstone] Switched to Redis-backed tombstone store")
}

// ── Central Tombstone Sweeper ──

// TombstoneSweeper periodically cleans up expired tombstones.
// It replaces the old per-player time.Sleep goroutine model.
type TombstoneSweeper struct {
	interval time.Duration
	stopCh   chan struct{}

	// onExpired is called for each expired tombstone that needs hard cleanup.
	// Signature: func(playerID string, roomID string)
	onExpired func(playerID string, roomID string)
}

// NewTombstoneSweeper creates a central sweeper.
// interval is how often to scan for expired tombstones (default 5s).
func NewTombstoneSweeper(interval time.Duration, onExpired func(string, string)) *TombstoneSweeper {
	if interval <= 0 {
		interval = 5 * time.Second
	}
	return &TombstoneSweeper{
		interval:  interval,
		stopCh:    make(chan struct{}),
		onExpired: onExpired,
	}
}

// Start begins the sweeper loop in a background goroutine.
func (s *TombstoneSweeper) Start() {
	go func() {
		ticker := time.NewTicker(s.interval)
		defer ticker.Stop()

		log.Printf("[Tombstone] Central sweeper started (interval=%v)", s.interval)

		for {
			select {
			case <-ticker.C:
				s.sweep()
			case <-s.stopCh:
				log.Println("[Tombstone] Central sweeper stopped")
				return
			}
		}
	}()
}

// Stop gracefully stops the sweeper.
func (s *TombstoneSweeper) Stop() {
	close(s.stopCh)
}

func (s *TombstoneSweeper) sweep() {
	// Route to the correct backend based on the global store type.
	switch store := GlobalTombstoneStore.(type) {
	case *MemoryTombstoneStore:
		expired := store.GetExpiredAndRemove()
		for _, t := range expired {
			log.Printf("[Tombstone] Expired: player=%s room=%s", t.PlayerID, t.RoomID)
			if s.onExpired != nil {
				s.onExpired(t.PlayerID, t.RoomID)
			}
		}
		if len(expired) > 0 {
			log.Printf("[Tombstone] Sweeper cleaned up %d expired tombstones", len(expired))
		}

	case *RedisTombstoneAdapter:
		expired := store.GetExpiredCleanups()
		for _, c := range expired {
			log.Printf("[Tombstone] Expired (Redis): player=%s room=%s", c.PlayerID, c.RoomID)
			if s.onExpired != nil {
				s.onExpired(c.PlayerID, c.RoomID)
			}
		}
		if len(expired) > 0 {
			log.Printf("[Tombstone] Sweeper cleaned up %d expired Redis tombstones", len(expired))
		}
	}
}
