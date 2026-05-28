// Package logic contains the core game business logic and Nano components.
package logic

import (
	"errors"
	"fmt"
	"log"
	"math"
	"math/rand"
	"strconv"
	"sync"
	"time"

	"bomberman-server/metrics"
	"bomberman-server/security"

	"github.com/lonng/nano"
	"github.com/lonng/nano/component"
	"github.com/lonng/nano/session"
)

type (
	// RoomComponent handles game matchmaking and world state
	RoomComponent struct {
		component.Base
		group    *nano.Group
		rooms    map[string]*NanoRoom
		lock     sync.RWMutex
		userComp *UserComponent
		sweeper  *TombstoneSweeper
	}

	SettlementRequest struct {
		Success   bool               `json:"success"`
		Config    []BackpackItemInfo `json:"config"`
		Extracted []string           `json:"extracted"`
	}

	NanoPlayer struct {
		UID        int64  `json:"id"`
		Name       string `json:"name"`
		Ready      bool   `json:"ready"`
		Char       int    `json:"char"`
		SpawnIndex int    `json:"spawn_index"`
	}

	NanoRoom struct {
		ID                  string
		Players             map[int64]*NanoPlayer
		GameState           *GameState
		InGame              bool
		Group               *nano.Group
		Seed                int64
		State               int // 0: WAITING, 1: PLAYING, 2: FINISHED
		DeadPlayers         map[int64]bool
		Items               map[string]*WorldItemState
		TriggeredDrops      map[string]bool // Track coordinates that already triggered drop rolls
		DestroyedWallsCount int             // 累计炸毁的墙壁数量
		// [HOST AUTHORITY] 房主权威地图配置
		HostUID   int64  // 当前房主玩家的 UID
		MapType   string // "CLASSIC" | "WINTER" | "PROCEDURAL"
		ShapeType string // "circle" | "hexagon" | "star" | "ring" | "cave"
		MapSize   string // "small" | "medium" | "large"
	}

	// RoomSyncInfo 是 onRoomUpdate 广播的完整数据包，包含玩家列表与地图配置
	RoomSyncInfo struct {
		Players   []*NanoPlayer `json:"players"`
		HostUID   int64         `json:"host_uid"`
		MapType   string        `json:"map_type"`
		ShapeType string        `json:"shape_type"`
		MapSize   string        `json:"map_size"`
		Seed      int64         `json:"seed"`
	}

	// UpdateMapConfigRequest 是客户端 Host 修改地图配置时发送的请求体
	UpdateMapConfigRequest struct {
		MapType   string `json:"map_type"`
		ShapeType string `json:"shape_type"`
		MapSize   string `json:"map_size"`
		Seed      int64  `json:"seed"`
	}

	JoinRequest struct {
		RoomID string `json:"room_id"`
	}

	CreateRequest struct{}

	OpenChestRequest struct {
		ID string `json:"id"`
	}

	PickupRequest struct {
		ID string `json:"id"`
	}

	TriggerDropRequest struct {
		X int `json:"x"`
		Y int `json:"y"`
	}

	DieRequest struct{}

	UpdateStatsRequest struct {
		BombCap int     `json:"bomb_cap"`
		Radius  int     `json:"radius"`
		Speed   float64 `json:"speed"`
		Shields int     `json:"shields"`
	}

	UpdateRequest struct {
		Char int `json:"char"`
	}

	ReadyRequest struct{}
)

func NewRoomComponent(userComp *UserComponent) *RoomComponent {
	return &RoomComponent{
		group:    nano.NewGroup("global"),
		rooms:    make(map[string]*NanoRoom),
		userComp: userComp,
	}
}

func (c *RoomComponent) Name() string {
	return "Room"
}

func (c *RoomComponent) AfterInit() {
	log.Println("[Nano] RoomComponent initialized")

	// Register global session close callback for tombstone creation
	session.Lifetime.OnClosed(func(s *session.Session) {
		c.MarkDisconnected(s)
	})

	// Start the central tombstone sweeper (replaces per-player sleep goroutines)
	c.sweeper = NewTombstoneSweeper(5*time.Second, func(playerID string, roomID string) {
		uid, err := strconv.ParseInt(playerID, 10, 64)
		if err != nil {
			log.Printf("[Tombstone] Sweeper: invalid playerID %s", playerID)
			return
		}
		c.doLeaveByUID(uid, roomID)
		metrics.TombstoneExpiredTotal.Inc()
	})
	c.sweeper.Start()
}

func (r *NanoRoom) getUnusedSpawnIndex() int {
	used := make(map[int]bool)
	for _, p := range r.Players {
		used[p.SpawnIndex] = true
	}
	for i := 0; i < 4; i++ {
		if !used[i] {
			return i
		}
	}
	return len(r.Players)
}

// Join handles player joining a room
// Route: Room.Join
func (c *RoomComponent) Join(s *session.Session, msg *JoinRequest) error {
	// 核心修复：如果已在房间中，先离开
	if s.Value("room_id") != nil {
		c.doLeave(s)
	}

	roomID := msg.RoomID

	c.lock.Lock()
	r, ok := c.rooms[roomID]
	if ok && r.Group != nil && r.Group.Count() == 0 {
		// 房间存在但活跃人数为0，说明该房间已废弃且正处于墓碑硬清理期。直接将其物理销毁重置，避免脏状态残留
		delete(c.rooms, roomID)
		ok = false
		log.Printf("[Nano] Room %s had 0 active players during Join, destroyed and recreated.", roomID)
	}
	if !ok {
		r = &NanoRoom{
			ID:          roomID,
			Group:       nano.NewGroup("room_" + roomID),
			Seed:        rand.Int63(),
			State:       0,
			DeadPlayers: make(map[int64]bool),
			Items:       make(map[string]*WorldItemState),
		}
		c.rooms[roomID] = r
	}

	if r.State != 0 {
		c.lock.Unlock()
		return s.Response(map[string]interface{}{
			"type":    "ERROR",
			"message": "room locked",
		})
	}
	if r.DeadPlayers != nil && r.DeadPlayers[s.UID()] {
		c.lock.Unlock()
		return s.Response(map[string]interface{}{
			"type":    "ERROR",
			"message": "cannot rejoin: you died in this match",
		})
	}
	c.lock.Unlock()

	r.Group.Add(s)
	s.Set("room_id", roomID)

	// 初始化玩家信息
	c.lock.Lock()
	if r.Players == nil {
		r.Players = make(map[int64]*NanoPlayer)
	}
	name := s.Value("name")
	pName := "Unknown"
	if name != nil {
		pName = name.(string)
	}

	spawnIdx := r.getUnusedSpawnIndex()
	r.Players[s.UID()] = &NanoPlayer{
		UID:        s.UID(),
		Name:       pName,
		Char:       0,
		SpawnIndex: spawnIdx,
	}
	c.lock.Unlock()

	c.syncRoom(r)

	token := security.GenerateResumeToken(s.UID(), roomID)
	s.Set("resume_token", token.String())

	// 推送欢迎消息
	return s.Response(map[string]interface{}{
		"type":         "WELCOME",
		"room":         roomID,
		"seed":         r.Seed,
		"player_id":    strconv.FormatInt(s.UID(), 10),
		"resume_token": token.String(),
	})
}

func (c *RoomComponent) syncRoom(r *NanoRoom) {
	c.lock.RLock()
	var playerList []*NanoPlayer
	for _, p := range r.Players {
		playerList = append(playerList, p)
	}
	syncInfo := &RoomSyncInfo{
		Players:   playerList,
		HostUID:   r.HostUID,
		MapType:   r.MapType,
		ShapeType: r.ShapeType,
		MapSize:   r.MapSize,
		Seed:      r.Seed,
	}
	c.lock.RUnlock()

	r.Group.Broadcast("onRoomUpdate", syncInfo)
}

// Create handles room creation
// Route: Room.Create
func (c *RoomComponent) Create(s *session.Session, msg *CreateRequest) error {
	// 核心修复：如果已在房间中，先离开
	if s.Value("room_id") != nil {
		c.doLeave(s)
	}

	roomID := fmt.Sprintf("Room_%d", rand.Intn(9000)+1000)
	
	c.lock.Lock()
	r := &NanoRoom{
		ID:             roomID,
		Group:          nano.NewGroup("room_" + roomID),
		Seed:           rand.Int63(),
		State:          0,
		DeadPlayers:    make(map[int64]bool),
		Items:          make(map[string]*WorldItemState),
		TriggeredDrops: make(map[string]bool),
		// [HOST AUTHORITY] 新建房间：初始化房主与默认地图配置
		HostUID:   s.UID(),
		MapType:   "CLASSIC",
		ShapeType: "circle",
		MapSize:   "small",
	}
	c.rooms[roomID] = r
	c.lock.Unlock()

	r.Group.Add(s)
	s.Set("room_id", roomID)

	c.lock.Lock()
	r.Players = make(map[int64]*NanoPlayer)
	name := s.Value("name")
	pName := "Unknown"
	if name != nil {
		pName = name.(string)
	}
	r.Players[s.UID()] = &NanoPlayer{
		UID:        s.UID(),
		Name:       pName,
		Ready:      true,
		Char:       0,
		SpawnIndex: 0,
	}
	c.lock.Unlock()

	c.syncRoom(r)

	token := security.GenerateResumeToken(s.UID(), roomID)
	s.Set("resume_token", token.String())

	return s.Response(map[string]interface{}{
		"type":         "WELCOME",
		"room":         roomID,
		"seed":         r.Seed,
		"player_id":    strconv.FormatInt(s.UID(), 10),
		"resume_token": token.String(),
	})
}

// Update handles player property updates (e.g. character selection)
// Route: Room.Update
func (c *RoomComponent) Update(s *session.Session, msg *UpdateRequest) error {
	roomIDVal := s.Value("room_id")
	if roomIDVal == nil {
		return errors.New("not in a room")
	}
	roomID := roomIDVal.(string)

	c.lock.Lock()
	r, ok := c.rooms[roomID]
	if ok && r.Players != nil {
		if p, ok := r.Players[s.UID()]; ok {
			p.Char = msg.Char
		}
	}
	c.lock.Unlock()

	if ok {
		c.syncRoom(r)
	}
	return s.Response(map[string]string{"status": "ok"})
}

// Ready handles player ready status toggle
// Route: Room.Ready
func (c *RoomComponent) Ready(s *session.Session, msg *ReadyRequest) error {
	roomIDVal := s.Value("room_id")
	if roomIDVal == nil {
		return errors.New("not in a room")
	}
	roomID := roomIDVal.(string)

	c.lock.Lock()
	r, ok := c.rooms[roomID]
	if ok && r.Players != nil {
		if p, ok := r.Players[s.UID()]; ok {
			p.Ready = !p.Ready
		}
	}
	c.lock.Unlock()

	if ok {
		c.syncRoom(r)
	}
	return s.Response(map[string]string{"status": "ok"})
}

type RoomInfo struct {
	Name        string `json:"name"`
	PlayerCount int    `json:"player_count"`
}

// List returns the list of active rooms
// Route: Room.List
func (c *RoomComponent) List(s *session.Session, msg []byte) error {
	c.lock.RLock()
	defer c.lock.RUnlock()

	var rooms []RoomInfo
	for _, r := range c.rooms {
		count := r.Group.Count()
		if r.State == 0 && count > 0 {
			rooms = append(rooms, RoomInfo{
				Name:        r.ID,
				PlayerCount: count,
			})
		}
	}
	
	// 如果没有房间，返回空数组而不是 nil
	if rooms == nil {
		rooms = []RoomInfo{}
	}

	return s.Response(rooms)
}

type MoveRequest struct {
	X         float64 `json:"x"`
	Y         float64 `json:"y"`
	VX        float64 `json:"vx"`
	VY        float64 `json:"vy"`
	State     string  `json:"state"`
	Direction string  `json:"direction"`
	Tick      int64   `json:"tick"`
}

// Move handles player movement
// Route: Room.Move
func (c *RoomComponent) Move(s *session.Session, msg *MoveRequest) error {
	roomIDVal := s.Value("room_id")
	if roomIDVal == nil {
		return errors.New("not in a room")
	}
	roomID := roomIDVal.(string)
	
	c.lock.Lock()
	defer c.lock.Unlock()

	r, ok := c.rooms[roomID]
	if !ok {
		return errors.New("room not found")
	}

	// 广播移动消息
	r.Group.Broadcast("onMove", map[string]interface{}{
		"id":        s.UID(),
		"x":         msg.X,
		"y":         msg.Y,
		"vx":        msg.VX,
		"vy":        msg.VY,
		"state":     msg.State,
		"direction": msg.Direction,
		"tick":      msg.Tick,
	})

	// 更新局内权威 GameState 中的玩家坐标和速度
	if r.GameState != nil {
		r.GameState.Lock.Lock()
		if ps, ok := r.GameState.Players[fmt.Sprintf("%d", s.UID())]; ok {
			ps.X = msg.X
			ps.Y = msg.Y
			ps.VX = msg.VX
			ps.VY = msg.VY
			ps.LastMoveTime = time.Now()
		}
		r.GameState.Lock.Unlock()
	}

	return nil
}

type PlayerInitialStats struct {
	BombCap             int     `json:"bomb_cap"`
	RadiusCap           int     `json:"radius_cap"`
	SpeedCap            float64 `json:"speed_cap"`
	ShieldCap           int     `json:"shield_cap"`
	HasPersistentShield bool    `json:"has_persistent_shield"`
}

func CalculateInitialStats(backpack []BackpackItemInfo) PlayerInitialStats {
	bomb := 0
	radius := 0
	speed := 0.0
	shield := 0
	epic := false

	// Deduplicate items just in case (same logic as backpack.gd)
	seen := make(map[string]bool)
	for _, item := range backpack {
		if item.ResPath == "" || seen[item.ResPath] {
			continue
		}
		seen[item.ResPath] = true

		switch item.ResPath {
		// 旧版局外物品兼容
		case "res://prefabs/items/res/item_boots.tres":
			speed += 20.0
		case "res://prefabs/items/res/item_epic_shield.tres":
			shield += 1
			epic = true
		case "res://prefabs/items/res/item_power_core.tres":
			radius += 2
		case "res://prefabs/items/res/item_ammo_long.tres":
			bomb += 2
		case "res://prefabs/items/res/item_ammo_small.tres":
			bomb += 1

		// 新版局外物品（TRES格式）
		// 1. 炸弹上限加成
		case "res://prefabs/OutfitItems/outfit_bag_large.tres":
			bomb += 1
		case "res://prefabs/OutfitItems/outfit_suitcase_wood.tres":
			bomb += 2
		case "res://prefabs/OutfitItems/outfit_pumpkin_giant.tres":
			bomb += 3

		// 2. 移动速度上限加成
		case "res://prefabs/OutfitItems/outfit_speed_1.tres":
			speed += 1.0
		case "res://prefabs/OutfitItems/outfit_speed_3.tres":
			speed += 3.0
		case "res://prefabs/OutfitItems/outfit_speed_5.tres":
			speed += 5.0

		// 3. 护盾加成与免死金牌
		case "res://prefabs/OutfitItems/outfit_epic_shield.tres":
			shield += 1
			epic = true

		// 4. 爆炸范围加成（全向及方向卷轴）
		case "res://prefabs/OutfitItems/outfit_power_1.tres",
			"res://prefabs/OutfitItems/outfit_power_up_1.tres",
			"res://prefabs/OutfitItems/outfit_power_down_1.tres",
			"res://prefabs/OutfitItems/outfit_power_left_1.tres",
			"res://prefabs/OutfitItems/outfit_power_right_1.tres":
			radius += 1
		case "res://prefabs/OutfitItems/outfit_power_2.tres",
			"res://prefabs/OutfitItems/outfit_power_up_2.tres",
			"res://prefabs/OutfitItems/outfit_power_down_2.tres",
			"res://prefabs/OutfitItems/outfit_power_left_2.tres",
			"res://prefabs/OutfitItems/outfit_power_right_2.tres":
			radius += 2
		case "res://prefabs/OutfitItems/outfit_power_3.tres",
			"res://prefabs/OutfitItems/outfit_power_up_3.tres",
			"res://prefabs/OutfitItems/outfit_power_down_3.tres",
			"res://prefabs/OutfitItems/outfit_power_left_3.tres",
			"res://prefabs/OutfitItems/outfit_power_right_3.tres":
			radius += 3
		}
	}

	return PlayerInitialStats{
		BombCap:             2 + bomb,
		RadiusCap:           1 + radius,
		SpeedCap:            95.0 + speed,
		ShieldCap:           1 + shield,
		HasPersistentShield: epic,
	}
}

// StartGame starts the authoritative game loop
// Route: Room.StartGame
func (c *RoomComponent) StartGame(s *session.Session, msg []byte) error {
	roomIDVal := s.Value("room_id")
	if roomIDVal == nil {
		return errors.New("not in a room")
	}
	roomID := roomIDVal.(string)
	
	c.lock.Lock()
	r, ok := c.rooms[roomID]
	if ok {
		r.InGame = true
		r.State = 1 // PLAYING
		r.Group.Broadcast("onGameStart", map[string]interface{}{"seed": r.Seed})
		
		// 初始化局内权威 GameState
		r.GameState = &GameState{
			Players:       make(map[string]*PlayerState),
			Bombs:         make(map[string]*BombState),
			RemainingTime: 300, // 初始对局时间：300 秒 (5分钟)
			Lock:          sync.Mutex{},
		}

		// 权威计算所有玩家的初始配置并广播属性同步
		for uid, _ := range r.Players {
			profile, err := c.userComp.GetUserProfile(uid)
			var stats PlayerInitialStats
			if err == nil && profile != nil {
				stats = CalculateInitialStats(profile.BackpackConfig)
			} else {
				stats = PlayerInitialStats{
					BombCap:             2,
					RadiusCap:           1,
					SpeedCap:            95.0,
					ShieldCap:           1,
					HasPersistentShield: false,
				}
			}

			// 保存玩家信息到服务端 authoritative GameState
			r.GameState.Players[fmt.Sprintf("%d", uid)] = &PlayerState{
				ID:             fmt.Sprintf("%d", uid),
				BombCap:        stats.BombCap,
				RadiusCap:      stats.RadiusCap,
				SpeedCap:       stats.SpeedCap,
				ShieldCap:      stats.ShieldCap,
				BombCurrent:    1,    // 局内初始炸弹量：1
				RadiusCurrent:  1,    // 局内初始炸弹范围：1
				SpeedCurrent:   75.0, // 局内初始速度：75.0
				ShieldCurrent:  0,    // 局内初始护盾：0
				IsDead:         false,
				IsEvacuated:    false,
				LastMoveTime:   time.Now(),
				LastDamageTime: time.Time{},
			}

			// 广播同步属性给全房间所有人，包括 Caps(上限) 与 Currents(当前值)
			r.Group.Broadcast("onPlayerStats", map[string]interface{}{
				"id": fmt.Sprintf("%d", uid),
				"stats": map[string]interface{}{
					"bomb_cap":              stats.BombCap,
					"bomb_current":          1,
					"radius_cap":            stats.RadiusCap,
					"radius_current":        1,
					"speed_cap":             stats.SpeedCap,
					"speed_current":         75.0,
					"shield_cap":            stats.ShieldCap,
					"shield_current":        0,
					"has_persistent_shield": stats.HasPersistentShield,
				},
			})
		}
		
		go c.runGameLoop(r)
	}
	c.lock.Unlock()

	return nil
}

// Return handles player returning to room after game
// Route: Room.Return
func (c *RoomComponent) Return(s *session.Session, msg []byte) error {
	roomID := s.Value("room_id").(string)
	c.lock.Lock()
	r, ok := c.rooms[roomID]
	if ok {
		r.InGame = false
		r.State = 0 // WAITING
		r.DeadPlayers = make(map[int64]bool)
		r.Items = make(map[string]*WorldItemState)
		r.TriggeredDrops = make(map[string]bool)
		r.DestroyedWallsCount = 0
		r.Group.Broadcast("onReturn", nil)
	}
	c.lock.Unlock()
	return nil
}

// Settlement handles match settlement
// Route: Room.Settlement
func (c *RoomComponent) Settlement(s *session.Session, msg *SettlementRequest) error {
	uid := s.UID()
	if uid <= 0 {
		return errors.New("unauthorized")
	}

	err := c.userComp.OnSettlement(uid, msg.Config, msg.Extracted)
	if err != nil {
		return s.Response(map[string]string{"status": "error", "message": err.Error()})
	}

	return s.Response(map[string]string{"status": "ok"})
}

// Leave handles player leaving a room
// Route: Room.Leave
func (c *RoomComponent) Leave(s *session.Session, msg []byte) error {
	c.doLeave(s)
	return s.Response(map[string]string{"status": "ok"})
}

func (c *RoomComponent) doLeave(s *session.Session) {
	roomIDVal := s.Value("room_id")
	if roomIDVal == nil {
		return
	}
	roomID := roomIDVal.(string)

	// Clean up any tombstone for this player (normal leave = no reconnect needed)
	GlobalTombstoneStore.DeleteByPlayerID(strconv.FormatInt(s.UID(), 10))
	metrics.ActiveTombstones.Set(float64(GlobalTombstoneStore.Count()))

	c.lock.Lock()
	r, ok := c.rooms[roomID]
	if ok && r.Players != nil {
		leavingUID := s.UID()
		delete(r.Players, leavingUID)
		r.Group.Leave(s)
		s.Remove("room_id")
		// [HOST AUTHORITY] Host Migration: 若离开的是房主，迁移主权
		if r.HostUID == leavingUID && len(r.Players) > 0 {
			for nextUID := range r.Players {
				r.HostUID = nextUID
				log.Printf("[Nano] Host migrated from %d to %d in room %s", leavingUID, nextUID, roomID)
				break
			}
		}
	}
	c.lock.Unlock()

	if ok {
		c.syncRoom(r)
		c.lock.Lock()
		if r.Group.Count() == 0 {
			r.InGame = false
			delete(c.rooms, roomID)
			log.Printf("[Nano] Room %s is empty, deleted.", roomID)
		}
		c.lock.Unlock()
	}
}

// doLeaveByUID removes a player from a room by UID, without requiring a session.
// Used by the tombstone sweeper for hard cleanup after expiry.
// The player has already been removed from the Group by MarkDisconnected.
func (c *RoomComponent) doLeaveByUID(uid int64, roomID string) {
	c.lock.Lock()
	r, ok := c.rooms[roomID]
	if ok && r.Players != nil {
		delete(r.Players, uid)
		// [HOST AUTHORITY] Host Migration: 若离开的是房主，迁移主权
		if r.HostUID == uid && len(r.Players) > 0 {
			for nextUID := range r.Players {
				r.HostUID = nextUID
				log.Printf("[Nano] Host migrated (sweeper) from %d to %d in room %s", uid, nextUID, roomID)
				break
			}
		}
	}
	c.lock.Unlock()

	if !ok {
		return
	}

	c.syncRoom(r)

	c.lock.Lock()
	if r.Group != nil && r.Group.Count() == 0 {
		r.InGame = false
		delete(c.rooms, roomID)
		log.Printf("[Nano] Room %s is empty, deleted (via sweeper).", roomID)
	}
	c.lock.Unlock()

	log.Printf("[Nano] Player %d hard-removed from room %s by sweeper", uid, roomID)
}

// Evacuate handles evacuation request
// Route: Room.Evacuate
func (c *RoomComponent) Evacuate(s *session.Session, msg []byte) error {
	roomID := s.Value("room_id").(string)
	c.lock.RLock()
	r, ok := c.rooms[roomID]
	c.lock.RUnlock()
	if ok {
		r.Group.Broadcast("onPlayerEvacuated", map[string]interface{}{"id": s.UID()})
	}
	return nil
}

// OpenChest handles chest opening
// Route: Room.OpenChest
func (c *RoomComponent) OpenChest(s *session.Session, msg *OpenChestRequest) error {
	roomID := s.Value("room_id").(string)
	c.lock.RLock()
	r, ok := c.rooms[roomID]
	c.lock.RUnlock()
	if ok {
		r.Group.Broadcast("onChestOpened", msg)
	}
	return nil
}

// Pickup handles item pickup notification
// Route: Room.Pickup
func (c *RoomComponent) Pickup(s *session.Session, msg *PickupRequest) error {
	roomID := s.Value("room_id").(string)
	c.lock.Lock()
	defer c.lock.Unlock()

	r, ok := c.rooms[roomID]
	if !ok {
		return errors.New("room not found")
	}

	if r.Items != nil {
		if _, exists := r.Items[msg.ID]; exists {
			delete(r.Items, msg.ID)
			r.Group.Broadcast("onPickup", map[string]interface{}{
				"player_id": s.UID(),
				"id":        msg.ID,
			})
		}
	}
	return nil
}

// TriggerDrop handles item spawning request from client on wall destruction
// Route: Room.TriggerDrop
func (c *RoomComponent) TriggerDrop(s *session.Session, msg *TriggerDropRequest) error {
	roomID := s.Value("room_id").(string)
	c.lock.Lock()
	defer c.lock.Unlock()

	r, ok := c.rooms[roomID]
	if !ok {
		return errors.New("room not found")
	}

	// Deduplicate TriggerDrop requests by coordinate to prevent multiple drops on the same cell
	if r.TriggeredDrops == nil {
		r.TriggeredDrops = make(map[string]bool)
	}
	key := fmt.Sprintf("%d,%d", msg.X, msg.Y)
	if r.TriggeredDrops[key] {
		log.Printf("[Room %s] TriggerDrop request at coordinate (%d, %d) ignored (already triggered)", roomID, msg.X, msg.Y)
		return nil
	}
	r.TriggeredDrops[key] = true
	r.DestroyedWallsCount++

	roll := rand.Float64()
	var dropType string
	isChestAllowed := r.DestroyedWallsCount >= 18

	if roll < 0.015 && isChestAllowed {
		dropType = "chest"
	} else if roll >= 0.015 && roll < 0.465 {
		// Roll item type
		itemRoll := rand.Intn(100)
		if itemRoll < 35 {
			dropType = "count"
		} else if itemRoll < 75 {
			dropType = "power"
		} else if itemRoll < 95 {
			dropType = "speed"
		} else {
			dropType = "shield"
		}
	} else {
		return nil // No drop (including rolls under 0.015 when wall count < 18)
	}

	if r.Items == nil {
		r.Items = make(map[string]*WorldItemState)
	}
	itemID := fmt.Sprintf("item_%d_%d", time.Now().UnixNano(), rand.Intn(1000))
	item := &WorldItemState{
		ID:   itemID,
		Type: dropType,
		X:    msg.X,
		Y:    msg.Y,
	}
	r.Items[itemID] = item

	r.Group.Broadcast("onItemSpawn", map[string]interface{}{
		"id":   itemID,
		"type": dropType,
		"x":    msg.X,
		"y":    msg.Y,
	})
	return nil
}

// Die handles player death notification
// Route: Room.Die
func (c *RoomComponent) Die(s *session.Session, msg *DieRequest) error {
	roomID := s.Value("room_id").(string)
	c.lock.Lock()
	defer c.lock.Unlock()

	r, ok := c.rooms[roomID]
	if !ok {
		return errors.New("room not found")
	}

	if r.DeadPlayers == nil {
		r.DeadPlayers = make(map[int64]bool)
	}
	r.DeadPlayers[s.UID()] = true

	// 更新服务器端玩家状态
	if r.GameState != nil {
		r.GameState.Lock.Lock()
		if ps, ok := r.GameState.Players[fmt.Sprintf("%d", s.UID())]; ok {
			ps.IsDead = true
		}
		r.GameState.Lock.Unlock()
	}

	r.Group.Broadcast("onPlayerDie", map[string]interface{}{
		"id": s.UID(),
	})
	return nil
}

// UpdateStats handles player stats synchronization
// Route: Room.UpdateStats
func (c *RoomComponent) UpdateStats(s *session.Session, msg *UpdateStatsRequest) error {
	roomID := s.Value("room_id").(string)
	c.lock.Lock()
	defer c.lock.Unlock()

	r, ok := c.rooms[roomID]
	if ok && r.GameState != nil {
		r.GameState.Lock.Lock()
		defer r.GameState.Lock.Unlock()
		if ps, ok := r.GameState.Players[fmt.Sprintf("%d", s.UID())]; ok {
			ps.BombCurrent = msg.BombCap
			ps.RadiusCurrent = msg.Radius
			ps.SpeedCurrent = msg.Speed
			ps.ShieldCurrent = msg.Shields

			// 广播玩家属性同步消息给房间内所有人，实现HUD卡片完全由服务端广播权威数据驱动，拆分 Caps 和 Currents
			r.Group.Broadcast("onPlayerStats", map[string]interface{}{
				"id": fmt.Sprintf("%d", s.UID()),
				"stats": map[string]interface{}{
					"bomb_cap":              ps.BombCap,
					"bomb_current":          ps.BombCurrent,
					"radius_cap":            ps.RadiusCap,
					"radius_current":        ps.RadiusCurrent,
					"speed_cap":             ps.SpeedCap,
					"speed_current":         ps.SpeedCurrent,
					"shield_cap":            ps.ShieldCap,
					"shield_current":        ps.ShieldCurrent,
					"has_persistent_shield": ps.ShieldCurrent > 0,
				},
			})
		}
	}
	return nil
}

type BombRequest struct {
	X int `json:"x"`
	Y int `json:"y"`
}

func IsPlayerInExplosion(pcx, pcy, bx, by, radius int) bool {
	if pcx == bx && pcy == by {
		return true
	}
	if pcx == bx && pcy >= by-radius && pcy <= by+radius {
		return true
	}
	if pcy == by && pcx >= bx-radius && pcx <= bx+radius {
		return true
	}
	return false
}

// PlaceBomb handles bomb placement
// Route: Room.PlaceBomb
func (c *RoomComponent) PlaceBomb(s *session.Session, msg *BombRequest) error {
	roomID := s.Value("room_id").(string)
	c.lock.Lock()
	defer c.lock.Unlock()

	r, ok := c.rooms[roomID]
	if !ok {
		return errors.New("room not found")
	}

	if r.GameState == nil {
		return errors.New("game not started")
	}

	r.GameState.Lock.Lock()
	defer r.GameState.Lock.Unlock()

	radius := 1
	if ps, ok := r.GameState.Players[fmt.Sprintf("%d", s.UID())]; ok {
		radius = ps.RadiusCurrent
	}

	r.Group.Broadcast("onBombPlaced", map[string]interface{}{
		"owner":  s.UID(),
		"x":      msg.X,
		"y":      msg.Y,
		"radius": radius,
	})

	if r.GameState.Bombs != nil {
		bombID := fmt.Sprintf("bomb_%d_%d", time.Now().UnixNano(), rand.Intn(1000))
		r.GameState.Bombs[bombID] = &BombState{
			ID:        bombID,
			OwnerID:   fmt.Sprintf("%d", s.UID()),
			X:         msg.X,
			Y:         msg.Y,
			Radius:    radius,
			PlaceTime: time.Now(),
			Fuse:      2.0, // 初始引爆剩余时间：2.0 秒
		}
	}
	return nil
}

// UpdateBombs updates all authoritative bomb fuses and triggers explosions synchronously in Tick loop
func (c *RoomComponent) UpdateBombs(r *NanoRoom, delta float64) {
	if r.GameState == nil {
		return
	}

	r.GameState.Lock.Lock()
	defer r.GameState.Lock.Unlock()

	if r.GameState.Bombs == nil {
		return
	}

	var exploded []*BombState
	for bid, bomb := range r.GameState.Bombs {
		bomb.Fuse -= delta
		if bomb.Fuse <= 0 {
			exploded = append(exploded, bomb)
			delete(r.GameState.Bombs, bid)
		}
	}

	// 统一结算所有触发引爆的炸弹
	for _, bomb := range exploded {
		bx := bomb.X
		by := bomb.Y
		rad := bomb.Radius

		// 广播炸弹爆炸消息给客户端，触发同步爆炸画面
		r.Group.Broadcast("onBombExploded", map[string]interface{}{
			"x":      bx,
			"y":      by,
			"radius": rad,
		})

		for pid, ps := range r.GameState.Players {
			if ps.IsDead || ps.IsEvacuated {
				continue
			}

			// 受击冷却判定：防止在连续的几帧 Tick 内重复受击导致护盾瞬间扣光
			if time.Since(ps.LastDamageTime) < 300*time.Millisecond {
				continue
			}

			// 使用玩家的坐标、上一次更新时间和当前的速度向量来预测最真实的受击坐标
			dt := time.Since(ps.LastMoveTime).Seconds()
			if dt > 0.1 {
				dt = 0.1
			}
			predX := ps.X + ps.VX*dt
			predY := ps.Y + ps.VY*dt

			// 权威向下取整进行格子坐标换算，与 Godot 的 local_to_map 完美对齐
			pcx := int(math.Floor(predX / 16.0))
			pcy := int(math.Floor(predY / 16.0))

			// 服务端权威爆炸受击判定
			if IsPlayerInExplosion(pcx, pcy, bx, by, rad) {
				ps.LastDamageTime = time.Now() // 设置上一次受伤/爆盾时间

				if ps.ShieldCurrent > 0 {
					// 护盾扣减一层
					ps.ShieldCurrent--
					r.Group.Broadcast("onShieldLost", map[string]interface{}{
						"id": pid,
					})
					log.Printf("[Explosion] Authoritative (Tick-Auth): Player %s shield consumed by bomb at (%d, %d)", pid, bx, by)
				} else {
					// 判定死亡并广播
					ps.IsDead = true
					uidVal, _ := strconv.ParseInt(pid, 10, 64)
					if r.DeadPlayers == nil {
						r.DeadPlayers = make(map[int64]bool)
					}
					r.DeadPlayers[uidVal] = true

					r.Group.Broadcast("onPlayerDie", map[string]interface{}{
						"id": pid,
					})
					log.Printf("[Explosion] Authoritative (Tick-Auth): Player %s killed by bomb at (%d, %d)", pid, bx, by)
				}
			}
		}
	}
}

func (c *RoomComponent) runGameLoop(r *NanoRoom) {
	ticker := time.NewTicker(50 * time.Millisecond)
	defer ticker.Stop()

	var timeAccumulator float64
	for range ticker.C {
		c.lock.Lock()
		inGame := r.InGame
		playerCount := 0
		if r.Group != nil {
			playerCount = r.Group.Count()
		}

		if !inGame || playerCount == 0 {
			c.lock.Unlock()
			return
		}

		// 倒计时累加器：由于每 50ms 一 Tick，累加 0.05 秒
		timeAccumulator += 0.05
		if timeAccumulator >= 1.0 {
			timeAccumulator -= 1.0
			if r.GameState != nil {
				r.GameState.Lock.Lock()
				if r.GameState.RemainingTime > 0 {
					r.GameState.RemainingTime--
					if r.GameState.RemainingTime <= 0 {
						r.GameState.GameOver = true
					}
				}
				r.GameState.Lock.Unlock()
			}
		}

		// 联机权威炸弹与受击定时 Tick 同步更新
		c.UpdateBombs(r, 0.05)
		c.lock.Unlock()

		remainingTime := 300
		if r.GameState != nil {
			r.GameState.Lock.Lock()
			remainingTime = r.GameState.RemainingTime
			r.GameState.Lock.Unlock()
		}

		r.Group.Broadcast("onTick", map[string]interface{}{
			"time":           time.Now().Unix(),
			"remaining_time": remainingTime,
		})
	}
}

// MarkDisconnected marks a player as disconnected, creates a tombstone with a
// selective snapshot, and removes the session from the room group.
// Hard cleanup is handled by the central TombstoneSweeper — no per-player goroutine.
func (c *RoomComponent) MarkDisconnected(s *session.Session) {
	roomIDVal := s.Value("room_id")
	if roomIDVal == nil {
		return
	}
	roomID := roomIDVal.(string)

	uid := s.UID()
	uidStr := strconv.FormatInt(uid, 10)

	// Generate or reuse resume token
	tokenVal := s.Value("resume_token")
	var rt *security.ResumeToken
	if tokenVal != nil {
		// Reuse existing token if still valid
		rt = security.ParseResumeToken(tokenVal.(string))
	}
	if rt == nil || time.Now().Unix() > rt.ExpireAt {
		rt = security.GenerateResumeToken(uid, roomID)
	}
	tokenStr := rt.String()

	log.Printf("[Nano-Reconnect] Player %d disconnected from room %s. Creating tombstone (token prefix: %s)...",
		uid, roomID, tokenStr[:min(10, len(tokenStr))])

	// Capture a selective snapshot (safe-to-restore fields only)
	c.lock.Lock()
	r, roomExists := c.rooms[roomID]
	var playerSnapshot *PlayerState
	if roomExists && r.GameState != nil {
		r.GameState.Lock.Lock()
		if ps, ok := r.GameState.Players[uidStr]; ok {
			playerSnapshot = ps.SnapshotRestorable()
		}
		r.GameState.Lock.Unlock()
	}
	c.lock.Unlock()

	// Store tombstone in global store (memory or Redis)
	t := &TombstoneData{
		PlayerID:     uidStr,
		RoomID:       roomID,
		SessionID:    s.ID(),
		DisconnectAt: time.Now(),
		ExpireAt:     time.Unix(rt.ExpireAt, 0),
		Snapshot:     playerSnapshot,
	}
	if err := GlobalTombstoneStore.Store(tokenStr, t); err != nil {
		log.Printf("[Nano-Reconnect] Failed to store tombstone: %v", err)
	}

	// Remove from room group to prevent broadcasts to dead socket
	if roomExists && r.Group != nil {
		r.Group.Leave(s)
	}

	metrics.TombstoneCreatedTotal.Inc()
	metrics.ActiveTombstones.Set(float64(GlobalTombstoneStore.Count()))

	// Hard cleanup is now handled by the central TombstoneSweeper.
	// No per-player goroutine is spawned.
}

// ResumeRequest 断线重连恢复请求参数
type ResumeRequest struct {
	ResumeToken string `json:"resume_token"`
	LastAckSeq  int64  `json:"last_ack_seq"`
}

// Resume restores a disconnected player's session and selectively applies
// the tombstone snapshot. Authority fields (death, damage, evac) are preserved.
// Route: Room.Resume
func (c *RoomComponent) Resume(s *session.Session, msg *ResumeRequest) error {
	startTime := time.Now()
	token := msg.ResumeToken
	log.Printf("[Nano-Reconnect] Received Room.Resume for token prefix: %s", token[:min(10, len(token))])

	// 1. Atomically consume the tombstone (GET+DELETE, prevents double-consumption)
	tomb, ok := GlobalTombstoneStore.Consume(token)
	if !ok {
		log.Printf("[Nano-Reconnect] Resume failed: token expired or already consumed")
		metrics.ResumeFailedTotal.WithLabelValues(metrics.ReasonExpired).Inc()
		return s.Response(map[string]interface{}{
			"success": false,
			"error":   "Tombstone expired or invalid",
		})
	}

	// 2. Verify HMAC signature (prevents token forgery)
	uid, err := strconv.ParseInt(tomb.PlayerID, 10, 64)
	if err != nil {
		metrics.ResumeFailedTotal.WithLabelValues(metrics.ReasonPlayerIDFormat).Inc()
		return s.Response(map[string]interface{}{
			"success": false,
			"error":   "Invalid Player ID format in tombstone",
		})
	}

	if !security.VerifyResumeToken(token, uid, tomb.RoomID) {
		log.Printf("[Nano-Reconnect] Resume failed: HMAC verification failed for player %d", uid)
		metrics.ResumeFailedTotal.WithLabelValues(metrics.ReasonInvalidToken).Inc()
		return s.Response(map[string]interface{}{
			"success": false,
			"error":   "Token verification failed",
		})
	}

	roomID := tomb.RoomID

	// 3. Verify room still exists
	c.lock.Lock()
	r, roomExists := c.rooms[roomID]
	if !roomExists {
		c.lock.Unlock()
		metrics.ResumeFailedTotal.WithLabelValues(metrics.ReasonRoomNotFound).Inc()
		return s.Response(map[string]interface{}{
			"success": false,
			"error":   "Room no longer exists",
		})
	}
	c.lock.Unlock()

	// 4. Bind new session to the returning player's UID
	if err := s.Bind(uid); err != nil {
		log.Printf("[Nano-Reconnect] Resume session bind failed: %v", err)
		metrics.ResumeFailedTotal.WithLabelValues(metrics.ReasonBindFailed).Inc()
		return s.Response(map[string]interface{}{
			"success": false,
			"error":   "Session bind failed",
		})
	}
	s.Set("room_id", roomID)
	s.Set("resume_token", token)

	// 5. Re-add to room group
	r.Group.Add(s)

	// 6. Selectively restore player state (safe fields only, not authority fields)
	if r.GameState != nil && tomb.Snapshot != nil {
		r.GameState.Lock.Lock()
		if liveState, exists := r.GameState.Players[tomb.PlayerID]; exists {
			// Apply only safe-to-restore fields; authority fields (IsDead,
			// IsEvacuated, LastDamageTime, etc.) remain as-is from server truth.
			liveState.ApplySnapshotRestorable(tomb.Snapshot)
			log.Printf("[Nano-Reconnect] Player %s state selectively restored (version: %d)",
				tomb.PlayerID, tomb.Snapshot.StateVersion)
		} else {
			// Player was fully removed — restore from snapshot
			r.GameState.Players[tomb.PlayerID] = tomb.Snapshot
			log.Printf("[Nano-Reconnect] Player %s fully restored from snapshot", tomb.PlayerID)
		}
		r.GameState.Lock.Unlock()
	}

	log.Printf("[Nano-Reconnect] Player %d successfully resumed to room %s (took %v)", uid, roomID, time.Since(startTime))

	// 7. Sync room state to all players
	c.syncRoom(r)

	// 8. Metrics
	metrics.TombstoneResumedTotal.Inc()
	metrics.ResumeLatency.Observe(time.Since(startTime).Seconds())
	metrics.ActiveTombstones.Set(float64(GlobalTombstoneStore.Count()))

	// 9. Return authoritative game state snapshot
	r.GameState.Lock.Lock()
	defer r.GameState.Lock.Unlock()

	return s.Response(map[string]interface{}{
		"success":       true,
		"room_id":       roomID,
		"seed":          r.Seed,
		"snapshot":      r.GameState,
		"missed_events": []interface{}{},
	})
}

// min returns the smaller of two integers (polyfill for Go < 1.21 if needed).
// Remove this if your Go version already has the builtin.
// func min(a, b int) int { if a < b { return a }; return b }

// UpdateMapConfig handles room map configuration changes from the host.
// Route: Room.UpdateMapConfig
// [HOST AUTHORITY] 严格校验：只有当前房主（HostUID）才能修改地图配置，其余请求全部被拦截。
func (c *RoomComponent) UpdateMapConfig(s *session.Session, msg *UpdateMapConfigRequest) error {
	roomIDVal := s.Value("room_id")
	if roomIDVal == nil {
		return errors.New("not in a room")
	}
	roomID := roomIDVal.(string)

	c.lock.Lock()
	r, ok := c.rooms[roomID]
	if !ok {
		c.lock.Unlock()
		return errors.New("room not found")
	}

	// [HOST AUTHORITY CHECK] 只允许当前 HostUID 等于发起者 UID 的请求通过
	if r.HostUID != s.UID() {
		c.lock.Unlock()
		log.Printf("[Nano] UpdateMapConfig REJECTED: UID %d is not host (HostUID=%d) in room %s", s.UID(), r.HostUID, roomID)
		return s.Response(map[string]string{
			"status":  "error",
			"message": "unauthorized: only host can modify map config",
		})
	}

	// [VALIDATION] 验证地图类型合法性
	validMapTypes := map[string]bool{"CLASSIC": true, "WINTER": true, "PROCEDURAL": true}
	if msg.MapType != "" && !validMapTypes[msg.MapType] {
		c.lock.Unlock()
		return s.Response(map[string]string{"status": "error", "message": "invalid map_type"})
	}

	// [VALIDATION] 验证 Shape 合法性
	validShapes := map[string]bool{"circle": true, "hexagon": true, "star": true, "ring": true, "cave": true}
	if msg.ShapeType != "" && !validShapes[msg.ShapeType] {
		c.lock.Unlock()
		return s.Response(map[string]string{"status": "error", "message": "invalid shape_type"})
	}

	// [VALIDATION] 验证尺寸合法性
	validSizes := map[string]bool{"small": true, "medium": true, "large": true}
	if msg.MapSize != "" && !validSizes[msg.MapSize] {
		c.lock.Unlock()
		return s.Response(map[string]string{"status": "error", "message": "invalid map_size"})
	}

	// 通过所有校验，更新房间地图参数
	if msg.MapType != "" {
		r.MapType = msg.MapType
	}
	if msg.ShapeType != "" {
		r.ShapeType = msg.ShapeType
	}
	if msg.MapSize != "" {
		r.MapSize = msg.MapSize
	}
	if msg.Seed != 0 {
		r.Seed = msg.Seed
	}

	log.Printf("[Nano] Host %d updated map config in room %s: type=%s shape=%s size=%s seed=%d",
		s.UID(), roomID, r.MapType, r.ShapeType, r.MapSize, r.Seed)
	c.lock.Unlock()

	// 广播新版 RoomSyncInfo 到全房间，触发所有客户端实时同步
	c.syncRoom(r)

	return s.Response(map[string]string{"status": "ok"})
}

