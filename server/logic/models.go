// Package logic contains the core game business logic and Nano components.
package logic

import (
	"sync"
	"time"
)

// ── 持久化数据模型 ──

type BackpackItemInfo struct {
	ResPath     string `json:"res_path"`
	GridPos     [2]int `json:"grid_pos"`
	IsInsurance bool   `json:"is_insurance"`
	Rotated     bool   `json:"rotated"`
}

type UserProfile struct {
	ID             int64              `json:"id"`
	Name           string             `json:"name"`
	Coins          int                `json:"coins"`
	Inventory      []string           `json:"inventory"`
	BackpackConfig []BackpackItemInfo `json:"backpack_config"`
	Presets        [][]BackpackItemInfo `json:"presets"`
}

// ── 游戏状态模型 ──

type ChestState struct {
	ID     string `json:"id"`
	X      int    `json:"x"`
	Y      int    `json:"y"`
	Tier   int    `json:"tier"` // 0: White, 1: Blue, 2: Gold
	Opened bool   `json:"opened"`
}

type WorldItemState struct {
	ID   string `json:"id"`
	Type string `json:"type"` // bomb, radius, speed, shield
	X    int    `json:"x"`
	Y    int    `json:"y"`
}

type GameState struct {
	Players        map[string]*PlayerState    `json:"players"`
	Bombs          map[string]*BombState      `json:"bombs"`
	Chests         map[string]*ChestState     `json:"chests"`
	Items          map[string]*WorldItemState `json:"items"`
	Map            [][]int                    `json:"map"`
	Width          int                        `json:"width"`
	Height         int                        `json:"height"`
	EvacActivated  bool                       `json:"evac_activated"`
	RemainingTime  int                        `json:"remaining_time"`
	StartTime      time.Time                  `json:"-"`
	GameOver       bool                       `json:"game_over"`
	Lock           sync.Mutex                 `json:"-"`
}

type PlayerState struct {
	ID             string    `json:"id"`
	X              float64   `json:"x"`
	Y              float64   `json:"y"`
	VX             float64   `json:"vx"`
	VY             float64   `json:"vy"`

	// Caps (背包带来的上限)
	BombCap        int       `json:"bomb_cap"`
	RadiusCap      int       `json:"radius_cap"`
	SpeedCap       float64   `json:"speed_cap"`
	ShieldCap      int       `json:"shield_cap"`

	// Currents (局内吃道具后的当前值)
	BombCurrent    int       `json:"bomb_current"`
	RadiusCurrent  int       `json:"radius_current"`
	SpeedCurrent   float64   `json:"speed_current"`
	ShieldCurrent  int       `json:"shield_current"`

	IsDead         bool      `json:"is_dead"`
	IsEvacuated    bool      `json:"is_evacuated"`
	LastMoveTime   time.Time `json:"last_move_time"`
	LastDamageTime time.Time `json:"last_damage_time"`
	EvacStartTime  time.Time `json:"evac_start_time"`
	EvacInProgress bool      `json:"evac_in_progress"`
	EvacPos        [2]int    `json:"evac_pos"`

	// StateVersion is incremented on every authoritative state mutation.
	// Used to detect stale snapshots during tombstone resume.
	StateVersion  int64      `json:"state_version"`
}

// SnapshotRestorable returns a deep copy of only the fields that are safe to
// restore from a tombstone snapshot. Fields governed by server authority
// (IsDead, IsEvacuated, LastDamageTime, ShieldCurrent) are NOT copied —
// the live authoritative values are preserved.
func (ps *PlayerState) SnapshotRestorable() *PlayerState {
	return &PlayerState{
		X:             ps.X,
		Y:             ps.Y,
		VX:            ps.VX,
		VY:            ps.VY,
		BombCap:       ps.BombCap,
		RadiusCap:     ps.RadiusCap,
		SpeedCap:      ps.SpeedCap,
		ShieldCap:     ps.ShieldCap,
		BombCurrent:   ps.BombCurrent,
		RadiusCurrent: ps.RadiusCurrent,
		SpeedCurrent:  ps.SpeedCurrent,
		ShieldCurrent: ps.ShieldCurrent,
		StateVersion:  ps.StateVersion,
	}
}

// ApplySnapshotRestorable overwrites only the safe-to-restore fields from src.
// Authority fields (IsDead, IsEvacuated, LastDamageTime, LastMoveTime,
// EvacStartTime, EvacInProgress, EvacPos) are left untouched.
func (ps *PlayerState) ApplySnapshotRestorable(src *PlayerState) {
	ps.X = src.X
	ps.Y = src.Y
	ps.VX = src.VX
	ps.VY = src.VY
	ps.BombCap = src.BombCap
	ps.RadiusCap = src.RadiusCap
	ps.SpeedCap = src.SpeedCap
	ps.ShieldCap = src.ShieldCap
	ps.BombCurrent = src.BombCurrent
	ps.RadiusCurrent = src.RadiusCurrent
	ps.SpeedCurrent = src.SpeedCurrent
	ps.ShieldCurrent = src.ShieldCurrent
	ps.StateVersion = src.StateVersion
}

type BombState struct {
	ID        string    `json:"id"`
	OwnerID   string    `json:"owner_id"`
	X         int       `json:"x"`
	Y         int       `json:"y"`
	Radius    int       `json:"radius"`
	PlaceTime time.Time `json:"place_time"`
	Fuse      float64   `json:"fuse"`
}
