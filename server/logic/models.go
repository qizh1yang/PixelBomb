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
