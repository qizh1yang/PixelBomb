# PixelBomb 前端修复报告

## 修复概要

本次修复解决了所有 GDScript 解析错误、资源路径错误，并为 UI 场景添加了配色方案。

---

## 一、资源路径修复（.tscn 文件）

| 文件 | 问题 | 修复 |
|---|---|---|
| `levels/roglaik/roglaik.tscn` | 所有脚本指向 `res://assets/audio/` | 改为 `res://levels/roglaik/`；纹理改为 `res://levels/roglaik/textures/` |
| `prefabs/bombs/bomb.tscn` | 脚本指向 `res://scenes/player/bomb/` | 改为 `res://prefabs/bombs/` |
| `prefabs/bombs/explosion_effect.tscn` | 同上 | 同上 |
| `characters/player1-6/playerX.tscn` | bomb 引用 `res://scenes/player/bomb/bomb.tscn` | 改为 `res://prefabs/bombs/bomb.tscn` |

---

## 二、GDScript 解析错误修复（.gd 文件）

| 文件 | 错误原因 | 修复方式 |
|---|---|---|
| `prefabs/bombs/flash.gd` | 关键代码 `sprite.material = sprite.material.duplicate()` 被截断进注释，导致所有炸弹共享材质 | 分离注释与代码，重写 |
| `levels/roglaik/roglaik.gd` | 第 207 行含隐藏字符/非法字面量 | 重写整个文件 |
| `levels/roglaik/wall_layer.gd` | 第 122 行 Tab/空格混用缩进错误 | 重写整个文件 |
| `characters/player1-6/player_controller.gd` | 第 130 行缩进不一致（6 个文件相同问题） | 重写 player1 再复制至 2-6 |
| `prefabs/bombs/bomb.gd` | 第 80 行格式错误 | 重写，同时改进音效加载（优雅降级） |
| `prefabs/bombs/explosion_effect.gd` | 第 8 行格式错误 | 重写 |

---

## 三、逻辑 Bug 修复

### 3.1 Lobby 信号错误（P0 致命）
- **问题**：`net.seed_received.connect(_on_room_joined)` — `seed_received` 是 **bool 变量**，不是信号，调用 `.connect()` 会报运行时错误，玩家加入房间后**永远无法进入 Room 场景**
- **修复**：
  - `network_manager.gd` 新增 `signal room_joined(seed_val: int)`
  - 在 `WELCOME` 消息处理末尾加 `room_joined.emit(map_seed)`
  - `lobby.gd` 改为 `net.room_joined.connect(_on_room_joined)`

### 3.2 断线重连信号丢失
- **问题**：断线重连时 `current_room != ""` 分支不 emit `connected_to_server`，导致登录界面无法响应
- **修复**：两个分支都 emit `connected_to_server`

### 3.3 Result Panel 缺少 tscn 文件
- **问题**：`result_panel.tscn` 根本不存在，游戏结束时 `load()` 会失败
- **修复**：新建 `ui/result_panel/result_panel.tscn`；同时添加平局文案

### 3.4 ConnectionMonitor.tscn 路径不符
- **问题**：`project.godot` autoload 引用 `res://ui/connection_monitor/connection_monitor.tscn`，但该文件不存在
- **修复**：在正确路径新建场景文件

### 3.5 bomb.gdshader 缺失
- **问题**：`bomb.tscn` 引用的 shader 文件不存在，炸弹场景无法加载
- **修复**：新建 `prefabs/bombs/bomb.gdshader`（白色闪光效果）

---

## 四、新建文件清单

| 文件 | 说明 |
|---|---|
| `prefabs/bombs/bomb.gdshader` | 炸弹闪烁 Shader（原缺失） |
| `ui/result_panel/result_panel.tscn` | 游戏结算面板场景（原缺失） |
| `ui/connection_monitor/connection_monitor.tscn` | 断线提示 autoload 场景（原缺失） |

---

## 五、UI 配色改造

采用炸弹人主题配色（深蓝黑底 + 橙黄 + 火红）：

| 场景 | 改动 |
|---|---|
| `login.tscn` | 深色背景、橙黄标题、绿色状态文字 |
| `lobby.tscn` | 头部橙黄标题、绿色玩家名、分割线 |
| `room.tscn` | 橙黄房间号、绿色 Ready 按钮、红色 Leave 按钮、蓝色 Start 按钮 |
| `hud.tscn` | 黄色炸弹数、橙色火焰半径、蓝色速度，图标改用 emoji |
| `result_panel.tscn` | 半透明黑色遮罩、金色 VICTORY / 红色 DEFEAT |

---

## 注意事项

1. **音频文件缺失**：`Bonus2.wav`、`Explosion.wav` 等音效文件不存在。目前代码已做优雅降级（不存在时不播放），但需要补充音效资源
2. **BGM 缺失**：`4 - Village.ogg` 不存在，roglaik 场景的 BGM 节点已移除 stream 引用
3. **纹理路径迁移**：roglaik 场景的贴图应存放在 `levels/roglaik/textures/` 下，请确认 `All Tiles Free Ver.png`、`TilesetFloor.png`、`TilesetElement.png`、`TilesetNature.png` 均在该目录
