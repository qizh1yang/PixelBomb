# PROGRESS.md — PixelBomb 开发进度

> 最后更新：2026-05-09
> 版本目标：最小可运行 Demo（本地单机 + 联机流程全跑通）

---

## 当前状态快照

| 层 | 模块 | 完成度 |
|----|------|--------|
| 基础架构 | NetworkManager / GameMode / 场景切换 | 90% |
| 核心玩法 | 地图 / 玩家 / 炸弹 | 95% |
| UI流程 | 登录 / 大厅 / 房间 / 结算 | 70% |
| 技术债 | 路径错误 / 目录混乱 / 脚本语法bug | 待修 |

---

## 阶段一：P0 路径 & 语法 Bug 修复（最高优先级）

> 目标：项目能正常启动并运行游戏场景

- [x] **BUG-01** 修复 `game_stage.gd` 第91行缩进语法错误
  - 文件：`client/stages/game_stage.gd`
  - 问题：`if GameMode.is_game_active:` 在 `_process()` 函数外
  - ✅ 已修复（2026-05-09）

- [x] **BUG-02** 修复 `game_mode.gd` 玩家场景路径
  - 文件：`client/autoloads/game_mode.gd`
  - 修改：`res://characters/playerX/` → `res://prefabs/Players/playerX/`
  - ✅ 已修复（2026-05-09）

- [x] **BUG-03** 修复 `game_mode.gd` 地图路径
  - 文件：`client/autoloads/game_mode.gd`
  - 修改：`res://map/map_*/` → `res://prefabs/map/map_*/`
  - ✅ 已修复（2026-05-09）

- [x] **BUG-04** 修复 `wall_layer.gd` + `floor_layer.gd` 中的 extends 路径
  - 文件：`client/prefabs/map/map_classic/wall_layer.gd`
  - 文件：`client/prefabs/map/map_classic/floor_layer.gd`
  - 文件：`client/prefabs/map/map_winter/wall_layer.gd`（原指向 classic，已改为 winter 自己的 floor_layer_yuansu）
  - 文件：`client/prefabs/map/map_winter/floor_layer.gd`（同上）
  - ✅ 已修复（2026-05-09）

- [x] **BUG-05** 修复 `project.godot` main_scene 路径
  - `res://ui/login/login.tscn` → `res://scenes/Login/login.tscn`
  - ✅ 已修复（2026-05-09）

### 额外修复（本轮路径扫描发现）

- [x] **BUG-09** 修复 `bomb.gd` 音效路径大小写
  - `res://prefabs/bombs/res/Explosion2.wav` → `res://prefabs/Bombs/res/Explosion2.wav`
  - ✅ 已修复（2026-05-09）

- [x] **BUG-10** 修复 `ItemCount/item_count.tscn` + `ItemPower/item_power.tscn` + `ItemSpeed/item_speed.tscn` 脚本路径大小写
  - `res://prefabs/Items/` → `res://prefabs/items/`（全小写）
  - ✅ 已修复（2026-05-09）

- [x] **BUG-11** 修复 `backpack.gd` 道具资源路径
  - `res://prefabs/items/resources/` → `res://prefabs/items/res/`
  - ✅ 已修复（2026-05-09）

- [x] **BUG-12** 修复 `ui/ResultPanel.tscn` 脚本路径
  - `res://ui/result_panel/result_panel.gd` → `res://prefabs/ResultPanel/result_panel.gd`
  - ✅ 已修复（2026-05-09）

- [x] **BUG-13** 创建缺失的 `map_classic.gd` 脚本文件
  - 文件：`client/prefabs/map/map_classic/map_classic.gd`（新建）
  - `map_classic.tscn` 引用的脚本文件不存在，按 map_winter.gd 架构创建
  - ✅ 已修复（2026-05-09）

- [x] **BUG-14** 修复 `game_stage.gd` 地图路径（离线回退路径）
  - `res://map/map_classic/map_classic.tscn` → `res://prefabs/map/map_classic/map_classic.tscn`
  - ✅ 已修复（2026-05-09）

> ⚠️ **待处理**：`map_classic.tscn` 的四张贴图（All Tiles Free Ver.png / TilesetFloor.png / TilesetElement.png / TilesetNature.png）原始文件缺失。当前**临时指向 map_winter 的同名贴图**使地图可运行，但视觉风格为冬季主题。需补充 classic 专属贴图后，在 Godot Editor 中重新指定（Tileset 数据与贴图绑定，需在编辑器内操作）。

---

## 阶段二：P1 联机流程 Bug 修复

> 目标：完整走通 登录→大厅→房间→游戏→结算 联机流程

- [ ] **BUG-06** 修复 `login.gd` NetworkManager API 不匹配
  - 文件：`client/scenes/Login/login.gd`
  - 问题：调用了不存在的 `connection_succeeded`、`connection_failed` 信号和旧版 `connect_to_server()` 参数
  - 修复：改为 `connected_to_server` 信号，设置 `net.player_name`，调用无参 `net.connect_to_server()`

- [ ] **BUG-07** 修复 `lobby.gd` room_joined 参数类型
  - 文件：`client/scenes/Lobby/lobby.gd`
  - 问题：`_onRoomJoined(Dictionary)` → 实际信号为 `room_joined(seed_val: int)`
  - 修复：`func _onRoomJoined(_seedVal: int)`

- [ ] **BUG-08** 修复 `room.gd` game_started 参数和调用方式
  - 文件：`client/scenes/Room/room.gd`
  - 问题1：`_onGameStarted(Dictionary)` → 实际信号无参数
  - 问题2：直接 `change_scene_to_file` 绕过了 GameMode，玩家无法生成
  - 修复：`func _onGameStarted()` + 调用 `GameMode.start_game()`

---

## 阶段三：离线 Demo 验证

> 目标：不启动服务器，直接在 Godot Editor 运行 game_stage.tscn 验证核心玩法

- [ ] 直接运行 `stages/game_stage.tscn`，验证地图正常生成
- [ ] 验证玩家可在地图内移动，方向正确
- [ ] 验证放炸弹（Space 键），爆炸后可破坏墙消失
- [ ] 验证玩家被爆炸伤害后死亡
- [ ] 验证结算面板弹出显示正常

---

## 阶段四：联机 Demo 验证

> 目标：本地启动 Go 服务器，2个客户端跑通完整流程

- [ ] 启动后端 `server/`（`go run .` 或 `go build`）
- [ ] 客户端1 登录 → 创建房间
- [ ] 客户端2 登录 → 加入房间
- [ ] 客户端1（房主）开始游戏
- [ ] 双端地图种子一致，地图相同
- [ ] 双端玩家位置同步正常
- [ ] 炸弹爆炸同步（BOMB 消息）
- [ ] 一方死亡，结算面板双端弹出
- [ ] 结算后返回大厅，状态重置

---

## 阶段五：技术债清理（Demo 之后）

> 目标：规范目录结构，消除重复文件，统一资源引用

### 5.1 目录清理（需在 Godot Editor 内执行，禁止直接移文件）

- [ ] 废弃 `ui/login/`, `ui/lobby/`, `ui/room/`, `ui/hud/`（旧版场景）
  - 保留 `ui/connection_monitor/`, `ui/dev_hud/`（这两个是 autoload 引用的）
- [ ] 废弃道具旧目录：`prefabs/items/item_count/`, `item_power/`, `item_speed/`, `base/`
  - 保留 `prefabs/items/ItemCount/`, `ItemPower/`, `ItemSpeed/`, `ItemBase/`
- [ ] 确认 `characters/player_controller.gd` 已迁入 `prefabs/Players/player_controller.gd`（当前已在 prefabs/Players/）

### 5.2 脚本规范检查

- [ ] `scenes/Login/login.gd` 修复后，确认类名、注释、类型标注符合规范
- [ ] `scenes/Lobby/lobby.gd` 同上
- [ ] `scenes/Room/room.gd` 同上

### 5.3 map_winter 脚本路径对齐

- [ ] 检查 `prefabs/map/map_winter/wall_layer.gd` 中的 extends 路径是否指向 `map_winter/floor_layer_yuansu.gd`

---

## 阶段六：后续功能迭代（Demo 后）

| 功能 | 优先级 | 依赖 | 状态 |
|------|--------|------|------|
| 宝箱掉落道具（chest_base 接入） | 高 | 阶段四完成 | 待开发 |
| 游戏内背包 UI | 中 | 宝箱系统 | 待开发 |
| 地图选择（大厅选 winter/classic） | 中 | 阶段四完成 | 待开发 |
| 5/6号玩家角色 | 低 | - | 待开发 |
| 音效总线完善（BGM/SFX 音量控制） | 低 | - | 待开发 |
| 爆炸特效方向优化 | 低 | - | 待开发 |
| 移动端虚拟摇杆 | 低 | - | 待开发 |
| **新增：异形背包道具 (2x2, 2x3, 3x3)** | 高 | - | ✅ 已完成 |

---

## 参考路径对照表（修复后的正确路径）

| 资源 | 正确路径（res:// 相对 client/） |
|------|-------------------------------|
| 游戏场景 | `stages/game_stage.tscn` |
| 经典地图 | `prefabs/map/map_classic/map_classic.tscn` |
| 冬季地图 | `prefabs/map/map_winter/map_winter.tscn` |
| 玩家1场景 | `prefabs/Players/player1/player1.tscn` |
| 玩家2场景 | `prefabs/Players/player2/player2.tscn` |
| 玩家3场景 | `prefabs/Players/player3/player3.tscn` |
| 玩家4场景 | `prefabs/Players/player4/player4.tscn` |
| 炸弹预制体 | `prefabs/Bombs/bomb.tscn` |
| HUD | `prefabs/HUD/hud.tscn` |
| 结算面板 | `prefabs/ResultPanel/result_panel.tscn` |
| 登录场景 | `scenes/Login/login.tscn` |
| 大厅场景 | `scenes/Lobby/lobby.tscn` |
| 房间场景 | `scenes/Room/room.tscn` |
| 断线监控 | `ui/connection_monitor/connection_monitor.tscn` |
| 调试 HUD | `ui/dev_hud/dev_hud.tscn` |

---

## 变更日志

| 日期 | 内容 |
|------|------|
| 2026-05-06 | 项目初始化，地图十字五区域架构设计 |
| 2026-05-07 | 十字形5区域地图完成，25×25，分隔墙+缺口+出生保护 |
| 2026-05-08 | 玩家控制、炸弹、道具、背包、结算、HUD、网络同步全部实现 |
| 2026-05-09 | 全项目 GDScript 规范化整理；发现路径错误集群；制定 demo 修复方案和本进度文档 |
| 2026-05-09 | 完成全项目场景引用路径检查与修复（共修复12处错误）；新建 map_classic.gd 补全缺失脚本；map_classic.tscn 贴图临时指向 winter 贴图 |
| 2026-05-12 | 实现 2x2/2x3/3x3 异形背包道具（购物袋、手提箱、南瓜罐），配置图标资源与设计方案 |
