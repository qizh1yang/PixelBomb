package logic

import (
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"

	_ "modernc.org/sqlite"
	"golang.org/x/crypto/bcrypt"
)

type SQLiteStore struct {
	db   *sql.DB
	lock sync.Mutex
}

var DB *SQLiteStore

func InitSQLite(dbPath string) error {
	// 确保文件夹存在
	dir := filepath.Dir(dbPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return err
	}

	// 限制 SQLite 的最大打开连接数为 1，防止高并发写导致锁冲突
	db.SetMaxOpenConns(1)

	store := &SQLiteStore{db: db}
	if err := store.createTables(); err != nil {
		db.Close()
		return err
	}

	DB = store
	log.Printf("[SQLite] Database initialized at: %s", dbPath)
	return nil
}

func (s *SQLiteStore) createTables() error {
	query := `
	CREATE TABLE IF NOT EXISTS users (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		username TEXT UNIQUE NOT NULL,
		password_hash TEXT NOT NULL,
		coins INTEGER DEFAULT 500,
		is_first_game BOOLEAN DEFAULT 1,
		played_time REAL DEFAULT 0.0,
		last_login_time TEXT,
		inventory TEXT DEFAULT '[]',
		backpack_config TEXT DEFAULT '[]',
		presets TEXT DEFAULT '[]',
		device_id TEXT DEFAULT ''
	);
	`
	if _, err := s.db.Exec(query); err != nil {
		return err
	}
	// 兼容旧数据库：如果 device_id 列不存在则添加
	s.db.Exec(`ALTER TABLE users ADD COLUMN device_id TEXT DEFAULT ''`)
	return nil
}

func (s *SQLiteStore) RegisterUser(username, password string) error {
	s.lock.Lock()
	defer s.lock.Unlock()

	// 使用 Bcrypt 对密码进行加密哈希
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	query := `INSERT INTO users (username, password_hash, coins, is_first_game, played_time, last_login_time, inventory, backpack_config, presets) 
	VALUES (?, ?, 500, 1, 0.0, ?, '[]', '[]', '[]');`
	
	nowStr := time.Now().Format("2006-01-02 15:04:05")
	_, err = s.db.Exec(query, username, string(hash), nowStr)
	return err
}

func (s *SQLiteStore) AuthenticateUser(username, password string) (*UserProfile, error) {
	s.lock.Lock()
	defer s.lock.Unlock()

	var (
		id           int64
		pHash        string
		coins        int
		isFirstGame  bool
		playedTime   float64
		lastLogin    sql.NullString
		inventory    string
		backpackConf string
		presets      string
	)

	query := `SELECT id, password_hash, coins, is_first_game, played_time, last_login_time, inventory, backpack_config, presets 
	FROM users WHERE username = ?;`
	
	err := s.db.QueryRow(query, username).Scan(&id, &pHash, &coins, &isFirstGame, &playedTime, &lastLogin, &inventory, &backpackConf, &presets)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, errors.New("user not found")
		}
		return nil, err
	}

	// 核对密码哈希
	if err := bcrypt.CompareHashAndPassword([]byte(pHash), []byte(password)); err != nil {
		return nil, errors.New("invalid password")
	}

	// 更新最近登录时间
	nowStr := time.Now().Format("2006-01-02 15:04:05")
	_, _ = s.db.Exec(`UPDATE users SET last_login_time = ? WHERE id = ?;`, nowStr, id)

	// 解码 JSON 仓库及背包配置
	var invArr []string
	if err := json.Unmarshal([]byte(inventory), &invArr); err != nil {
		invArr = []string{}
	}

	var bpConfArr []BackpackItemInfo
	if err := json.Unmarshal([]byte(backpackConf), &bpConfArr); err != nil {
		bpConfArr = []BackpackItemInfo{}
	}

	var presetsArr [][]BackpackItemInfo
	if err := json.Unmarshal([]byte(presets), &presetsArr); err != nil {
		presetsArr = [][]BackpackItemInfo{}
	}

	profile := &UserProfile{
		ID:             id,
		Name:           username,
		Coins:          coins,
		Inventory:      invArr,
		BackpackConfig: bpConfArr,
		Presets:        presetsArr,
		IsFirstGame:    isFirstGame,
		PlayedTime:     playedTime,
		LastLoginTime:  nowStr,
	}

	return profile, nil
}

func (s *SQLiteStore) SaveUserProfile(uid int64, coins int, inventory []string, backpack []BackpackItemInfo, presets [][]BackpackItemInfo) error {
	s.lock.Lock()
	defer s.lock.Unlock()

	invBytes, err := json.Marshal(inventory)
	if err != nil {
		return err
	}

	bpBytes, err := json.Marshal(backpack)
	if err != nil {
		return err
	}

	presetBytes, err := json.Marshal(presets)
	if err != nil {
		return err
	}

	query := `UPDATE users SET coins = ?, inventory = ?, backpack_config = ?, presets = ? WHERE id = ?;`
	_, err = s.db.Exec(query, coins, string(invBytes), string(bpBytes), string(presetBytes), uid)
	return err
}

func (s *SQLiteStore) CompleteFirstGame(uid int64) error {
	s.lock.Lock()
	defer s.lock.Unlock()

	_, err := s.db.Exec(`UPDATE users SET is_first_game = 0 WHERE id = ?;`, uid)
	return err
}

func (s *SQLiteStore) UpdatePlayedTime(uid int64, durationSec float64) error {
	s.lock.Lock()
	defer s.lock.Unlock()

	_, err := s.db.Exec(`UPDATE users SET played_time = played_time + ? WHERE id = ?;`, durationSec, uid)
	return err
}

// RegisterGuest 为设备ID创建游客账号，返回生成的用户名
func (s *SQLiteStore) RegisterGuest(deviceID string) (string, error) {
	s.lock.Lock()
	defer s.lock.Unlock()

	// 生成游客名：勇者_ + 6位随机字符
	const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	r := time.Now().UnixNano()
	b := make([]byte, 6)
	for i := range b {
		b[i] = chars[r%int64(len(chars))]
		r = r>>8 + r&0xFF
		if r < int64(len(chars)) {
			r += time.Now().UnixNano()
		}
	}
	nickname := "勇者_" + string(b)

	hash, _ := bcrypt.GenerateFromPassword([]byte(""), bcrypt.DefaultCost)
	nowStr := time.Now().Format("2006-01-02 15:04:05")
	_, err := s.db.Exec(
		`INSERT INTO users (username, password_hash, device_id, coins, is_first_game, played_time, last_login_time, inventory, backpack_config, presets)
		VALUES (?, ?, ?, 500, 1, 0.0, ?, '[]', '[]', '[]')`,
		nickname, string(hash), deviceID, nowStr,
	)
	return nickname, err
}

// FindByDeviceID 通过设备ID查找已存在的游客账号
func (s *SQLiteStore) FindByDeviceID(deviceID string) (*UserProfile, error) {
	s.lock.Lock()
	defer s.lock.Unlock()

	if deviceID == "" {
		return nil, errors.New("device_id is empty")
	}

	var (
		id           int64
		username     string
		coins        int
		isFirstGame  bool
		playedTime   float64
		lastLogin    sql.NullString
		inventory    string
		backpackConf string
		presets      string
	)

	err := s.db.QueryRow(
		`SELECT id, username, coins, is_first_game, played_time, last_login_time, inventory, backpack_config, presets
		FROM users WHERE device_id = ? LIMIT 1`, deviceID,
	).Scan(&id, &username, &coins, &isFirstGame, &playedTime, &lastLogin, &inventory, &backpackConf, &presets)

	if err != nil {
		if err == sql.ErrNoRows {
			return nil, errors.New("device not found")
		}
		return nil, err
	}

	nowStr := time.Now().Format("2006-01-02 15:04:05")
	s.db.Exec(`UPDATE users SET last_login_time = ? WHERE id = ?`, nowStr, id)

	var invArr []string
	json.Unmarshal([]byte(inventory), &invArr)
	var bpConfArr []BackpackItemInfo
	json.Unmarshal([]byte(backpackConf), &bpConfArr)
	var presetsArr [][]BackpackItemInfo
	json.Unmarshal([]byte(presets), &presetsArr)

	return &UserProfile{
		ID:             id,
		Name:           username,
		Coins:          coins,
		Inventory:      invArr,
		BackpackConfig: bpConfArr,
		Presets:        presetsArr,
		IsFirstGame:    isFirstGame,
		PlayedTime:     playedTime,
		LastLoginTime:  nowStr,
	}, nil
}

func (s *SQLiteStore) Close() error {
	if s.db != nil {
		return s.db.Close()
	}
	return nil
}
