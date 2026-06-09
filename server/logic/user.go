// Package logic contains the core game business logic and Nano components.
package logic

import (
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"sync"
	"time"

	"github.com/lonng/nano/component"
	"github.com/lonng/nano/session"
)

type (
	// UserComponent handles player profile and authentication
	UserComponent struct {
		component.Base
		lock          sync.RWMutex
		uidToSession  map[int64]*session.Session // uid → active session (for duplicate login kick)
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
	// 初始化 SQLite 数据库
	if err := InitSQLite("storage/pixelbomb.db"); err != nil {
		log.Fatalf("[SQLite] Failed to initialize database: %v", err)
	}

	c := &UserComponent{
		uidToSession: make(map[int64]*session.Session),
	}
	return c
}

// ── 多账号防多开工具 ──

// TrackSession records a UID→Session mapping for duplicate-login detection.
// Called by Room.Resume when a player reconnects with a new session.
func (c *UserComponent) TrackSession(uid int64, s *session.Session) {
	c.lock.Lock()
	c.uidToSession[uid] = s
	c.lock.Unlock()
	log.Printf("[Auth] Tracked session for UID=%d (SessionID=%d) via Resume", uid, s.ID())
}

// ── 生命周期与账户业务逻辑 ──

func (c *UserComponent) Name() string {
	return "User"
}

func (c *UserComponent) AfterInit() {
	log.Println("[Nano] UserComponent initialized")

	// 注册会话关闭回调，确保 uidToSession 映射在断连时自动清理
	session.Lifetime.OnClosed(func(s *session.Session) {
		uid := s.UID()
		if uid <= 0 {
			return
		}
		c.lock.Lock()
		if existing, ok := c.uidToSession[uid]; ok && existing.ID() == s.ID() {
			delete(c.uidToSession, uid)
			log.Printf("[Auth] Session closed for UID=%d (SessionID=%d), cleaned up tracking", uid, s.ID())
		}
		c.lock.Unlock()
	})

	// 创建默认保底账号 "破壁者"
	if DB != nil {
		_, err := DB.AuthenticateUser("破壁者", "123456")
		if err != nil && err.Error() == "user not found" {
			log.Println("[SQLite] Creating default user: 破壁者")
			err = DB.RegisterUser("破壁者", "123456")
			if err != nil {
				log.Printf("[SQLite] Failed to register default user: %v", err)
			} else {
				profile, err := DB.AuthenticateUser("破壁者", "123456")
				if err == nil {
					_ = DB.SaveUserProfile(profile.ID, 12500, []string{"res://prefabs/OutfitItems/outfit_bag_large.tres"}, []BackpackItemInfo{}, [][]BackpackItemInfo{})
				}
			}
		}
	}
}

// Auth handles user authentication
// Route: User.Auth
func (c *UserComponent) Auth(s *session.Session, msg *AuthRequest) error {
	uname := msg.Username
	pwd := msg.Password
	if pwd == "" {
		pwd = "default_password" // 保底默认密码，防止老客户端无密码认证崩溃
	}
	log.Printf("[Nano] Auth request for user: %s", uname)

	profile, err := DB.AuthenticateUser(uname, pwd)
	if err != nil {
		if err.Error() == "user not found" {
			// 用户不存在时自动注册 (兼容局内免密码极速创建逻辑)
			log.Printf("[SQLite] User not found, auto-registering: %s", uname)
			err = DB.RegisterUser(uname, pwd)
			if err != nil {
				return s.Response(map[string]interface{}{
					"type":    "ERROR",
					"message": "自动注册失败: " + err.Error(),
				})
			}
			// 再次尝试校验登录
			profile, err = DB.AuthenticateUser(uname, pwd)
			if err != nil {
				return s.Response(map[string]interface{}{
					"type":    "ERROR",
					"message": "登录失败: " + err.Error(),
				})
			}
		} else {
			return s.Response(map[string]interface{}{
				"type":    "ERROR",
				"message": "登录失败: " + err.Error(),
			})
		}
	}

	// ── 防止多开同账号：检查并踢掉已有的旧会话 ──
	c.lock.Lock()
	if oldSession, exists := c.uidToSession[profile.ID]; exists {
		// 如果是同一会话重复鉴权（如 _spawnLocalPlayer 触发的 User.Auth），直接跳过踢出逻辑
		if oldSession.ID() != s.ID() {
			log.Printf("[Auth] Duplicate login detected for UID=%d (old SessionID=%d, new SessionID=%d), kicking old client...",
				profile.ID, oldSession.ID(), s.ID())
			// 先尝试推送踢出通知给旧客户端
			_ = oldSession.Push("onKicked", map[string]interface{}{
				"reason": "duplicate_login",
				"message": "您的账号已在其他设备登录",
			})
			// 给推送消息一点时间写出，然后关闭旧连接
			time.Sleep(50 * time.Millisecond)
			oldSession.Close()
			delete(c.uidToSession, profile.ID)
			log.Printf("[Auth] Old session (UID=%d, SessionID=%d) kicked successfully", profile.ID, oldSession.ID())
		} else {
			log.Printf("[Auth] Same session re-auth for UID=%d (SessionID=%d), skipping kick", profile.ID, s.ID())
		}
	}
	// 绑定（或重新绑定）当前会话
	err = s.Bind(profile.ID)
	if err != nil {
		c.lock.Unlock()
		return err
	}
	c.uidToSession[profile.ID] = s
	c.lock.Unlock()
	// ── 多开检测结束 ──

	s.Set("name", profile.Name)

	return s.Response(AuthResponse{
		ID:    profile.ID,
		Name:  profile.Name,
		Coins: profile.Coins,
		Data:  profile,
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
	pwd := msg.Password
	if pwd == "" {
		pwd = "default_password"
	}
	log.Printf("[Nano] Register request for user: %s", uname)

	err := DB.RegisterUser(uname, pwd)
	if err != nil {
		log.Printf("[SQLite] Register failed: %v", err)
		return s.Response(map[string]interface{}{
			"type":    "ERROR",
			"message": "用户已存在",
		})
	}

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

	u, err := c.GetUserProfile(uid)
	if err != nil {
		return err
	}

	return s.Response(u)
}

// GetUserProfile returns a user profile by UID
func (c *UserComponent) GetUserProfile(uid int64) (*UserProfile, error) {
	var (
		username     string
		coins        int
		isFirstGame  bool
		playedTime   float64
		lastLogin    sql.NullString
		inventory    string
		backpackConf string
		presets      string
	)

	query := `SELECT username, coins, is_first_game, played_time, last_login_time, inventory, backpack_config, presets 
	FROM users WHERE id = ?;`
	
	err := DB.db.QueryRow(query, uid).Scan(&username, &coins, &isFirstGame, &playedTime, &lastLogin, &inventory, &backpackConf, &presets)
	if err != nil {
		return nil, err
	}

	var invArr []string
	_ = json.Unmarshal([]byte(inventory), &invArr)

	var bpConfArr []BackpackItemInfo
	_ = json.Unmarshal([]byte(backpackConf), &bpConfArr)

	var presetsArr [][]BackpackItemInfo
	_ = json.Unmarshal([]byte(presets), &presetsArr)

	profile := &UserProfile{
		ID:             uid,
		Name:           username,
		Coins:          coins,
		Inventory:      invArr,
		BackpackConfig: bpConfArr,
		Presets:        presetsArr,
		IsFirstGame:    isFirstGame,
		PlayedTime:     playedTime,
		LastLoginTime:  lastLogin.String,
	}

	return profile, nil
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

	u, err := c.GetUserProfile(uid)
	if err != nil {
		return err
	}

	err = DB.SaveUserProfile(uid, u.Coins, u.Inventory, msg.Config, u.Presets)
	if err != nil {
		return err
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

	u, err := c.GetUserProfile(uid)
	if err != nil {
		return err
	}

	err = DB.SaveUserProfile(uid, msg.Coins, msg.Inventory, u.BackpackConfig, u.Presets)
	if err != nil {
		return err
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

	u, err := c.GetUserProfile(uid)
	if err != nil {
		return err
	}

	err = DB.SaveUserProfile(uid, u.Coins, u.Inventory, u.BackpackConfig, msg.Presets)
	if err != nil {
		return err
	}

	return s.Response(map[string]string{"status": "ok"})
}

// OnSettlement handles final match settlement from Room component
func (c *UserComponent) OnSettlement(uid int64, config []BackpackItemInfo, extracted []string) error {
	if uid <= 0 {
		return errors.New("unauthorized")
	}

	u, err := c.GetUserProfile(uid)
	if err != nil {
		return err
	}

	// 1. 更新背包网格布局
	u.BackpackConfig = config

	// 2. 统计提取回仓库物品
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
	
	// 保存背包布局及最终仓库物品到 SQLite
	err = DB.SaveUserProfile(uid, u.Coins, u.Inventory, u.BackpackConfig, u.Presets)
	if err != nil {
		return err
	}

	// 重要：完成第一局游戏，将首次游戏标记设为 false，并提交到 SQLite 数据库中
	if u.IsFirstGame {
		log.Printf("[SQLite] User %d (%s) finished their first game. Bypassing future tutorials.", uid, u.Name)
		_ = DB.CompleteFirstGame(uid)
	}

	return nil
}
