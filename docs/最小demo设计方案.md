# 最小可运行 Demo 设计方案

> 目标：本地能跑通完整游戏流程的最小可运行版本。
> 标准：登录 → 大厅 → 房间 → 炸弹人对局 → 结算，全流程无 crash，单机离线可测试。

---

## 一、当前项目真实状态总览

### 目录结构（实际）

```
client/
├── autoloads/
│   └── game_mode.gd              ✅ 完整（状态机+玩家生命周期）
├── utils/network/
│   └── network_manager.gd        ✅ 完整（WebSocket+离线mock）
├── ui/
│   ├── login/                    ⚠️ 场景文件存在，但脚本与 scenes/Login/ 重复
│   ├── lobby/                    ⚠️ 同上
│   ├── room/                     ⚠️ 同上
│   ├── hud/                      ⚠️ 同上
│   ├── connection_monitor/       ✅
│   └── dev_hud/                  ✅
├── scenes/
│   ├── Login/login.tscn + login.gd     ⚠️ 脚本引用旧 NetworkManager API
│   ├── Lobby/lobby.gd                  ⚠️ room_joined 参数类型不匹配
│   └── Room/room.gd                    ⚠️ game_started 参数类型不匹配
├── stages/
│   └── game_stage.tscn + game_stage.gd ⚠️ 第91行有语法错误（缩进缺失）
├── prefabs/
│   ├── Players/
│   │   ├── player1~4/  .tscn           ✅ 场景存在
│   │   └── player_controller.gd        ✅ 完整
│   ├── Bombs/
│   │   ├── bomb.tscn + bomb.gd         ✅ 完整
│   │   └── explosion_effect.tscn/.gd   ✅ 完整
│   ├── map/
│   │   ├── map_classic/                ✅ 地图生成完整（25×25十字形）
│   │   └── map_winter/                 ✅ 同套架构
│   ├── HUD/hud.tscn + hud.gd          ✅ 完整
│   ├── ResultPanel/result_panel.tscn   ✅ 完整
│   └── items/                          ⚠️ 有重复目录（见下）
└── project.godot                        ⚠️ main_scene路径错误，autoload路径需核查
```

### project.godot 现状

| 条目 | 当前值 | 状态 |
|------|--------|------|
| `run/main_scene` | `res://ui/login/login.tscn` | ⚠️ 应指向 `res://scenes/Login/login.tscn` |
| `NetworkManager` | `res://utils/network/network_manager.gd` | ✅ |
| `GameMode` | `res://autoloads/game_mode.gd` | ✅ |
| `ConnectionMonitor` | `res://ui/connection_monitor/connection_monitor.tscn` | ✅ |
| `DevHUD` | `res://ui/dev_hud/dev_hud.tscn` | ✅ |

### game_mode.gd 中的路径引用（旧路径，需核查）

```gdscript
# 当前代码中的路径（可能与实际文件位置不符）
"res://characters/player1/player1.tscn"  →  实际: res://prefabs/Players/player1/player1.tscn
"res://stages/game_stage.tscn"           →  实际: ✅ 路径正确（stages/ 在 client/ 根下）
"res://prefabs/HUD/hud.tscn"             →  实际: ✅ 路径正确
"res://prefabs/ResultPanel/result_panel.tscn" → ✅ 路径正确
"res://map/map_classic/map_classic.tscn" →  ❌ 实际: res://prefabs/map/map_classic/map_classic.tscn
```

---

## 二、已完成模块

| 模块 | 文件 | 完成度 | 说明 |
|------|------|--------|------|
| 网络管理 | `network_manager.gd` | ✅ 完整 | WebSocket连接、重连、离线mock均已实现 |
| 游戏状态机 | `game_mode.gd` | ✅ 完整 | 玩家生命周期、网络同步、结算均已实现 |
| 玩家控制 | `player_controller.gd` | ✅ 完整 | 移动、放炸弹、护盾、死亡逻辑完整 |
| 炸弹系统 | `bomb.gd` + `explosion_effect.gd` | ✅ 完整 | 引爆、扩散、破墙均正常 |
| 经典地图 | `map_classic/` (wall+floor+yuansu) | ✅ 完整 | 25×25 十字五区域，出生保护，随机seed |
| 冬季地图 | `map_winter/` | ✅ 完整 | 同套架构 |
| HUD | `hud.gd` | ✅ 完整 | 炸弹/护盾/速度数值显示 |
| 结算面板 | `result_panel.gd` | ✅ 完整 | 胜负显示，返回大厅 |
| 道具系统 | `item_base.gd` + 3种道具 | ✅ 完整 | 炸弹数/威力/速度道具 |
| 背包系统 | `backpack.gd` | ✅ 完整 | 道具持有/展示 |
| 断线监控 | `connection_monitor.gd` | ✅ 完整 | 自动弹出重连提示 |
| 游戏场景容器 | `game_stage.gd` | ⚠️ 有bug | 第91行缩进语法错误 |
| 登录场景 | `login.gd` | ⚠️ API不匹配 | 调用旧 NetworkManager 接口 |
| 大厅场景 | `lobby.gd` | ⚠️ 轻微问题 | `room_joined` 参数签名不匹配 |
| 房间场景 | `room.gd` | ⚠️ 轻微问题 | `game_started` 参数签名不匹配 |

---

## 三、Demo 目标范围

### 3.1 必须跑通（P0）

- [x] 离线单机模式：跳过登录直接进入游戏
- [x] 地图生成与渲染正常
- [x] 本地玩家可移动、放炸弹、死亡
- [x] 炸弹爆炸：破坏可破坏墙、伤害玩家
- [x] 结算面板弹出并能返回

### 3.2 联机流程（P1）

- [x] 登录（输入名称）→ 连接服务器
- [x] 大厅看到房间列表 → 创建/加入房间
- [x] 房间内准备 → 房主开始游戏
- [x] 多人对局同步（位置/炸弹/死亡）
- [x] 结算后返回大厅

### 3.3 暂不要求（P2，后续迭代）

- [ ] 道具从宝箱掉落（chest_base 已实现但未接入游戏）
- [ ] 背包 UI 在游戏内展示
- [ ] 冬季地图选择（Winter 地图已存在但未在大厅提供选择入口）
- [ ] 特效完善（爆炸方向旋转、闪烁）
- [ ] 音效总线配置（SFX bus 已接入炸弹）
- [ ] 6号玩家角色

---

## 四、异形背包道具设计 (New)

为了增加背包系统的策略性，引入了占据多个格子且形状各异的道具（异形物品）。这些道具主要用于提升玩家的基础上限属性。

### 4.1 属性加成道具列表 (当前版本仅实现以下三种局外物品)

| 道具名称 | 占据格子 | 形状 (Vector2i 数组) | 属性加成 | 资源路径 |
| :--- | :--- | :--- | :--- | :--- |
| **大号购物袋** | 2x2 | `[(0,0), (1,0), (0,1), (1,1)]` | 炸弹数量上限 +1 | `outfit_bag_large.tres` |
| **木制手提箱** | 2x3 | `[(0,0), (1,0), (0,1), (1,1), (0,2), (1,2)]` | 炸弹数量上限 +2 | `outfit_suitcase_wood.tres` |
| **巨型南瓜罐罐** | 3x3 | `[(0,0), (1,0), (2,0), (0,1), (1,1), (2,1), (0,2), (1,2), (2,2)]` | 炸弹数量上限 +3 | `outfit_pumpkin_giant.tres` |

### 4.2 交互逻辑
- **拾取**：玩家在对局中捡起 `OutfitItemEntity` 后，系统会自动尝试将其放入背包。
- **存储**：如果背包中有足够的连续空间容纳该道具的形状，则成功存入；否则无法拾取。
- **生效**：存入背包的道具会立即增加对应的上限属性（如炸弹上限），即使是在对局中拾取。

---

## 五、需要修复的 Bug 清单

### BUG-01：`game_stage.gd` 第 91 行语法错误（P0）

```gdscript
# 当前（错误）：if 块缺少缩进，独立在函数外
func _process(delta: float) -> void:
	_updateDebugInfo()
if GameMode.is_game_active:       # ← 这行在函数外，语法错误
		GameMode.tick(delta)

# 修复：
func _process(delta: float) -> void:
	_updateDebugInfo()
	if GameMode.is_game_active:
		GameMode.tick(delta)
```

### BUG-02：`game_mode.gd` 中玩家场景路径错误（P0）

```gdscript
# 当前（错误）：
"res://characters/player1/player1.tscn"

# 修复：
"res://prefabs/Players/player1/player1.tscn"
# player2/3/4 同理
```

### BUG-03：`game_mode.gd` 中地图路径错误（P0）

```gdscript
# 当前（错误）：
"classic": "res://map/map_classic/map_classic.tscn"
"winter": "res://map/map_winter/map_winter.tscn"

# 修复：
"classic": "res://prefabs/map/map_classic/map_classic.tscn"
"winter":  "res://prefabs/map/map_winter/map_winter.tscn"
```

### BUG-04：`wall_layer.gd` 中 `extends` 路径错误（P0）

```gdscript
# 当前（错误）：
extends "res://map/map_classic/floor_layer_yuansu.gd"

# 修复：
extends "res://prefabs/map/map_classic/floor_layer_yuansu.gd"
```

同理 `floor_layer.gd`：

```gdscript
# 当前（错误）：
extends "res://map/map_classic/floor_layer_yuansu.gd"

# 修复：
extends "res://prefabs/map/map_classic/floor_layer_yuansu.gd"
```

### BUG-05：`login.gd` 调用旧 NetworkManager API（P1）

```gdscript
# 当前（错误）：使用不存在的信号和方法
net.connection_succeeded.connect(...)
net.connection_failed.connect(...)
net.connect_to_server("127.0.0.1", 12345, playerName)

# NetworkManager 实际的信号和方法：
net.connected_to_server.connect(...)    # 信号名不同
# 没有 connection_failed 信号，WebSocket 靠 connection_closed
net.player_name = playerName
net.connect_to_server()                 # 无参数，URL 在初始化时读取
```

**修复方案**：

```gdscript
func _onLoginButtonPressed() -> void:
	var playerName: String = nameInput.text.strip_edges()
	if playerName == "":
		return
	var net = get_node_or_null("/root/NetworkManager")
	if net:
		net.player_name = playerName
		net.connected_to_server.connect(_onConnectionSucceeded, CONNECT_ONE_SHOT)
		net.connect_to_server()

func _onConnectionSucceeded() -> void:
	get_tree().change_scene_to_file("res://scenes/Lobby/lobby.tscn")
```

### BUG-06：`lobby.gd` 中 `_onRoomJoined` 参数类型错误（P1）

```gdscript
# NetworkManager 实际发射：room_joined(seed_val: int)
# 当前 lobby.gd 接受 Dictionary，类型不匹配

# 修复：
func _onRoomJoined(_seedVal: int) -> void:
	get_tree().change_scene_to_file("res://scenes/Room/room.tscn")
```

### BUG-07：`room.gd` 中 `_onGameStarted` 参数类型错误（P1）

```gdscript
# NetworkManager 实际发射：game_started()（无参数）
# 当前接受 Dictionary，类型不匹配

# 修复：
func _onGameStarted() -> void:
	GameMode.start_game()
```

> **注意**：Room 场景收到 game_started 后，应调用 `GameMode.start_game()` 而不是直接切换场景。GameMode 会在地图生成完毕后自动处理场景切换和玩家生成。

### BUG-08：`project.godot` main_scene 路径错误（P0）

```ini
# 当前（错误）：
run/main_scene="res://ui/login/login.tscn"

# 修复：
run/main_scene="res://scenes/Login/login.tscn"
```

---

## 六、目录混乱问题（技术债）

项目存在三套 UI/场景目录并行：

| 路径 | 内容 | 状态 |
|------|------|------|
| `ui/login/`, `ui/lobby/`, `ui/room/`, `ui/hud/` | 旧版场景 | 应逐步废弃 |
| `scenes/Login/`, `scenes/Lobby/`, `scenes/Room/` | 新版场景脚本 | 保留，作为 demo 使用 |
| `prefabs/HUD/`, `prefabs/ResultPanel/` | 游戏内 UI 预制体 | 保留 |

**短期策略**：Demo 阶段统一使用 `scenes/` 目录的场景脚本，不迁移 `ui/` 下的旧场景（留作参考），在 Godot Editor 中手动将 `scenes/Login/login.tscn` 等绑定到对应脚本。

**道具目录重复**：

| 路径 | 状态 |
|------|------|
| `prefabs/items/ItemCount/item_count.gd` | ✅ 正确版本（有 class_name） |
| `prefabs/items/item_count/item_count.gd` | ⚠️ 旧版，可删除 |
| `prefabs/items/ItemPower/`, `ItemSpeed/` | ✅ 正确版本 |
| `prefabs/items/item_power/`, `item_speed/` | ⚠️ 旧版，可删除 |
| `prefabs/items/ItemBase/` | ✅ 保留（基类） |
| `prefabs/items/base/` | ⚠️ 与 ItemBase 重复，可删除 |

---

## 七、Demo 执行架构（修复后）

```
运行入口
└── scenes/Login/login.tscn
    └── login.gd
        └── net.player_name = name
            net.connect_to_server()
            → [已连接] → scenes/Lobby/lobby.tscn

scenes/Lobby/lobby.tscn
└── lobby.gd
    └── 显示房间列表
        创建/加入房间 → [room_joined] → scenes/Room/room.tscn

scenes/Room/room.tscn
└── room.gd
    └── 显示准备状态
        [game_started] → GameMode.start_game()

GameMode.start_game()
    └── 实例化 stages/game_stage.tscn
        setupMap("res://prefabs/map/map_classic/map_classic.tscn")
        ↓ [map_generated 信号]
        _spawnLocalPlayer() + _syncExistingPlayers()
        game_stage.startCountdown()
        ↓ [游戏进行中]
        tick(delta) 每帧同步位置+HUD
        ↓ [_checkGameOver()]
        _showResult() → ResultPanel

ResultPanel
    └── [返回按钮] → scenes/Lobby/lobby.tscn
                     GameMode.cleanup_game()
```

---

## 八、离线快速测试方法

> 适用于无服务器环境的单机调试

在 `game_stage.gd` 的独立运行检测里，已有以下逻辑：

```gdscript
func _ready() -> void:
	if get_parent() == get_tree().root:
		# 直接运行 game_stage.tscn 时，GameMode 自动 mock 登录
		var gm = get_node_or_null("/root/GameMode")
		if gm:
			gm.game_stage = self
			gm.is_game_active = true
			setupMap(gm.get_selected_map_path())
			gm._get_references_from_stage()
```

同时 `NetworkManager` 提供 `mock_login_for_offline(seed_val)` 方法可在任意时机触发离线模式。

**推荐调试流程**：直接在 Godot Editor 中运行 `stages/game_stage.tscn` 即可测试地图生成+玩家控制+炸弹系统，无需启动服务器。

---

## 九、代码规范要求（遵守 Godot 4 项目代码规范）

所有脚本修改必须遵循以下规范：

### 命名规范
- **类名**：`PascalCase`（如 `GameMode`, `PlayerController`）
- **变量/函数**：`camelCase`（如 `isLocal`, `placeBomb()`）
- **信号**：动词过去式 + `camelCase`（如 `mapGenerated`, `playerDied`）
- **常量**：`ALL_CAPS`（如 `SYNC_INTERVAL`, `MAX_BOMBS`）
- **节点引用**（`@onready`）：`camelCase`（如 `animSprite`, `bombLabel`）
- **预制体/场景文件夹名**：`PascalCase`（如 `Players/`, `Bombs/`）

### 注释规范
- 文件头：`# 功能描述\n# 职责说明\n# 创建时间：YYYY-MM-DD`
- 函数注释：紧接函数定义之前，说明作用；参数说明格式 `# paramName：说明`
- 禁止使用 emoji

### 代码规范
- 所有变量/参数必须有类型标注
- `@onready` 节点引用加类型标注
- 使用 `get_node_or_null()` 而非 `$`（除 `@onready`）
- 信号连接优先用 `connect()`，避免 `+=`

---

## 十、P0 修复优先级执行表

| 序号 | Bug | 文件 | 影响 | 是否完成 |
|------|-----|------|------|----------|
| 1 | game_stage.gd 语法错误 | `stages/game_stage.gd` | 游戏无法运行 | [ ] |
| 2 | 玩家场景路径错误 | `autoloads/game_mode.gd` | 玩家无法生成 | [ ] |
| 3 | 地图路径错误 | `autoloads/game_mode.gd` | 地图无法加载 | [ ] |
| 4 | wall_layer/floor_layer extends 路径 | `prefabs/map/map_classic/` | 地图脚本加载失败 | [ ] |
| 5 | project.godot main_scene 路径 | `project.godot` | 游戏无法启动 | [ ] |
| 6 | login.gd NetworkManager API | `scenes/Login/login.gd` | 登录无法连接 | [ ] |
| 7 | lobby.gd 参数类型 | `scenes/Lobby/lobby.gd` | 无法进入房间 | [ ] |
| 8 | room.gd 参数类型+调用方式 | `scenes/Room/room.gd` | 游戏无法开始 | [ ] |
