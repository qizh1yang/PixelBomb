// Package logic contains the core game business logic and Nano components.
package logic
import (
	"encoding/json"
	"errors"
	"log"
	"os"
	"sync"
	"sync/atomic"

	"github.com/lonng/nano/component"
	"github.com/lonng/nano/session"
)

type (
	// UserComponent handles player profile and authentication
	UserComponent struct {
		component.Base
		users   map[int64]*UserProfile
		names   map[string]int64 // Name to UID mapping
		nextUID int64
		lock    sync.RWMutex
	}

	AuthRequest struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}

	AuthResponse struct {
		ID    int64        `json:"id"`
		Name  string       `json:"name"`
		Coins int          `json:"coins"`
		Data  *UserProfile `json:"data"`
	}
)

func NewUserComponent() *UserComponent {
	c := &UserComponent{
		users:   make(map[int64]*UserProfile),
		names:   make(map[string]int64),
		nextUID: 10000,
	}
	c.load() // 启动时加载
	return c
}

func (c *UserComponent) Name() string {
	return "User"
}

func (c *UserComponent) save() {
	c.lock.RLock()
	defer c.lock.RUnlock()

	data := struct {
		Users   map[int64]*UserProfile `json:"users"`
		Names   map[string]int64       `json:"names"`
		NextUID int64                  `json:"next_uid"`
	}{
		Users:   c.users,
		Names:   c.names,
		NextUID: atomic.LoadInt64(&c.nextUID),
	}

	bytes, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		log.Printf("[Storage] Marshal error: %v", err)
		return
	}

	err = os.WriteFile("users.json", bytes, 0644)
	if err != nil {
		log.Printf("[Storage] Write file error: %v", err)
	}
}

func (c *UserComponent) load() {
	bytes, err := os.ReadFile("users.json")
	if err != nil {
		if os.IsNotExist(err) {
			log.Println("[Storage] No existing users.json found, starting fresh.")
			return
		}
		log.Printf("[Storage] Read file error: %v", err)
		return
	}

	data := struct {
		Users   map[int64]*UserProfile `json:"users"`
		Names   map[string]int64       `json:"names"`
		NextUID int64                  `json:"next_uid"`
	}{}

	err = json.Unmarshal(bytes, &data)
	if err != nil {
		log.Printf("[Storage] Unmarshal error: %v", err)
		return
	}

	c.users = data.Users
	c.names = data.Names
	atomic.StoreInt64(&c.nextUID, data.NextUID)
	log.Printf("[Storage] Loaded %d users from users.json", len(c.users))
}

func (c *UserComponent) AfterInit() {
	log.Println("[Nano] UserComponent initialized")
	
	c.lock.Lock()
	_, exists := c.names["破壁者"]
	if !exists {
		uid := atomic.AddInt64(&c.nextUID, 1)
		c.users[uid] = &UserProfile{
			ID:    uid,
			Name:  "破壁者",
			Coins: 12500,
			Inventory: []string{
				"res://prefabs/OutfitItems/outfit_bag_large.tres",
			},
		}
		c.names["破壁者"] = uid
	}
	c.lock.Unlock()

	if !exists {
		c.save()
	}
}

// Auth handles user authentication
// Route: User.Auth
func (c *UserComponent) Auth(s *session.Session, msg *AuthRequest) error {
	uname := msg.Username
	log.Printf("[Nano] Auth request for user: %s", uname)

	c.lock.Lock()
	uid, ok := c.names[uname]
	var u *UserProfile
	if !ok {
		uid = atomic.AddInt64(&c.nextUID, 1)
		u = &UserProfile{
			ID:        uid,
			Name:      uname,
			Coins:     500,
			Inventory: []string{},
		}
		c.users[uid] = u
		c.names[uname] = uid
	} else {
		u = c.users[uid]
	}
	c.lock.Unlock()

	if !ok {
		c.save() // 保存新创建的用户
	}

	// 绑定会话 (Nano 要求 UID 是 int64)
	err := s.Bind(uid)
	if err != nil {
		return err
	}
	s.Set("name", u.Name)

	return s.Response(AuthResponse{
		ID:    u.ID,
		Name:  u.Name,
		Coins: u.Coins,
		Data:  u,
	})
}

type RegisterRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// Register handles user registration
// Route: User.Register
func (c *UserComponent) Register(s *session.Session, msg *RegisterRequest) error {
	uname := msg.Username
	log.Printf("[Nano] Register request for user: %s", uname)

	c.lock.Lock()
	if _, ok := c.names[uname]; ok {
		c.lock.Unlock()
		return s.Response(map[string]interface{}{
			"type":    "ERROR",
			"message": "用户已存在",
		})
	}

	uid := atomic.AddInt64(&c.nextUID, 1)
	u := &UserProfile{
		ID:        uid,
		Name:      uname,
		Coins:     1000, // 注册奖励更高
		Inventory: []string{},
	}
	c.users[uid] = u
	c.names[uname] = uid
	c.lock.Unlock()

	c.save() // 保存新注册的用户

	return s.Response(map[string]interface{}{
		"type": "REGISTER_SUCCESS",
	})
}

// GetProfile handles profile fetching
// Route: User.GetProfile
func (c *UserComponent) GetProfile(s *session.Session, msg []byte) error {
	uid := s.UID()
	if uid <= 0 {
		return errors.New("unauthorized")
	}

	c.lock.RLock()
	u, ok := c.users[uid]
	c.lock.RUnlock()

	if !ok {
		return errors.New("user not found")
	}

	return s.Response(u)
}

// GetUserProfile returns a user profile by UID
func (c *UserComponent) GetUserProfile(uid int64) (*UserProfile, error) {
	c.lock.RLock()
	defer c.lock.RUnlock()
	u, ok := c.users[uid]
	if !ok {
		return nil, errors.New("user not found")
	}
	return u, nil
}

type SaveBackpackRequest struct {
	Config []BackpackItemInfo `json:"config"`
}

type SavePresetsRequest struct {
	Presets [][]BackpackItemInfo `json:"presets"`
}

type SaveInventoryRequest struct {
	Inventory []string `json:"inventory"`
	Coins     int      `json:"coins"`
}

// SaveBackpack handles backpack configuration saving
// Route: User.SaveBackpack
func (c *UserComponent) SaveBackpack(s *session.Session, msg *SaveBackpackRequest) error {
	uid := s.UID()
	if uid <= 0 {
		return errors.New("unauthorized")
	}

	needsSave := false
	c.lock.Lock()
	if u, ok := c.users[uid]; ok {
		u.BackpackConfig = msg.Config
		log.Printf("[Nano] Saved backpack for user ID: %d", uid)
		needsSave = true
	}
	c.lock.Unlock()

	if needsSave {
		c.save() // 保存背包变更
	}

	return s.Response(map[string]string{"status": "ok"})
}

// SaveInventory handles global inventory saving
// Route: User.SaveInventory
func (c *UserComponent) SaveInventory(s *session.Session, msg *SaveInventoryRequest) error {
	uid := s.UID()
	if uid <= 0 {
		return errors.New("unauthorized")
	}

	needsSave := false
	c.lock.Lock()
	if u, ok := c.users[uid]; ok {
		u.Inventory = msg.Inventory
		u.Coins = msg.Coins
		log.Printf("[Nano] Saved inventory for user ID: %d", uid)
		needsSave = true
	}
	c.lock.Unlock()

	if needsSave {
		c.save()
	}

	return s.Response(map[string]string{"status": "ok"})
}

// SavePresets handles battle presets saving
// Route: User.SavePresets
func (c *UserComponent) SavePresets(s *session.Session, msg *SavePresetsRequest) error {
	uid := s.UID()
	if uid <= 0 {
		return errors.New("unauthorized")
	}

	needsSave := false
	c.lock.Lock()
	if u, ok := c.users[uid]; ok {
		u.Presets = msg.Presets
		log.Printf("[Nano] Saved presets for user ID: %d", uid)
		needsSave = true
	}
	c.lock.Unlock()

	if needsSave {
		c.save()
	}

	return s.Response(map[string]string{"status": "ok"})
}

// OnSettlement handles final match settlement from Room component
func (c *UserComponent) OnSettlement(uid int64, config []BackpackItemInfo, extracted []string) error {
	if uid <= 0 {
		return errors.New("unauthorized")
	}

	c.lock.Lock()
	defer c.lock.Unlock()

	u, ok := c.users[uid]
	if !ok {
		return errors.New("user not found")
	}

	// 1. 更新背包配置 (带回对局后的最终布局)
	u.BackpackConfig = config

	// 2. 将提取出的物品存入仓库
	// 注意：如果物品已经在 BackpackConfig 中，则不需要重复加入 Inventory
	// 我们遍历 extracted，如果该物品不在新的 BackpackConfig 中，则放入 Stash (Inventory)
	log.Printf("[Settlement] Processing extracted items for User %d (%s)...", uid, u.Name)
	addedToStash := 0
	for _, path := range extracted {
		if path == "" {
			continue
		}
		
		foundInBackpack := false
		for _, item := range config {
			if item.ResPath == path {
				foundInBackpack = true
				break
			}
		}
		
		if !foundInBackpack {
			u.Inventory = append(u.Inventory, path)
			log.Printf("  - Item added to STASH: %s", path)
			addedToStash++
		} else {
			log.Printf("  - Item remains in BACKPACK: %s", path)
		}
	}

	log.Printf("[Settlement] User %d Summary: %d in Backpack, %d new items to Stash", uid, len(config), addedToStash)
	
	go c.save() 
	return nil
}
