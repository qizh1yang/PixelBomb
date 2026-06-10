# PixelBomb 项目记忆

## 项目基本信息
- **类型**: Godot 4.5 游戏，前后端分离，单人开发
- **前端**: `client/` 目录，Godot 4.5 项目
- **后端**: `server/` 目录，Go 语言
- **通信协议**: WebSocket，消息类型为 JSON
- **主要 autoload**: `NetworkManager`（网络管理）、`GameMode`（游戏状态机+玩家管理）、`ConnectionMonitor`（断线监控）、`DevHUD`（调试面板）


##场景 / 预制体生成与资源复用规则
- 新建可复用预制体，必须创建同名专属文件夹，内含场景文件、专属业务脚本；独有资源新建res/子文件夹单独存放。
- 全局通用资源 / 脚本统一存放在根目录对应公共文件夹，直接引用不重复复制；查找优先级：场景专属 res → 模块内公共资源 → 全局根目录公共资源。
- 一次性业务场景（关卡 / UI 界面）按业务模块归类存放，专属资源遵循同规则管理。

## 游戏流程
登录 → 大厅（创建/加入房间）→ 房间（准备/开始）→ 游戏场景（碎空岛探索）→ 结算面板

## 游戏世界观设定（2026-05-14 确立）
- **游戏名**：浮岛劫掠：破壁者
- **世界**：沧溟海上的漂浮空岛（碎空岛），蕴含"源晶"矿石
- **玩家角色**：破壁者，受雇探索碎空岛搜刮源晶
- **核心武器**：爆弹（炸弹），十字方向冲击波
- **地图解释**：碎空岛呈晶格结构（网格地形），基岩结构=不可破坏墙，源晶矿壁=可破坏墙
- **道具解释**：散逸源晶=局内道具（爆核晶/烈焰晶/疾风晶/护心晶），封存物资=局外物品
- **撤离解释**：雇佣方接应艇空投+接应，时间限制=空岛不稳定，名额限制=燃料有限
- **背包解释**：主背包=搜刮区（死亡丢失），保险格=加固隔层（安全回收）
- **名词对照**见策划方案 0.7 节

## 已知文件路径约定（2026-05-09 核实）
- 玩家角色脚本：`res://prefabs/Players/player_controller.gd`（player1-4 共用）
- 玩家场景：`res://prefabs/Players/player1~4/playerX.tscn`
- 炸弹：`res://prefabs/Bombs/bomb.tscn`、`bomb.gd`
- 地图脚本：`res://prefabs/map/map_classic/`（wall_layer.gd、floor_layer.gd、floor_layer_yuansu.gd、camera_controller.gd）
- 地图场景：`res://prefabs/map/map_classic/map_classic.tscn`
- 游戏场景：`res://stages/game_stage.tscn` + `game_stage.gd`（**容器场景：map + camera + HUD**）
- **GameMode**: `res://autoloads/game_mode.gd` — 游戏状态机，通过 `start_game()` 实例化 game_stage
- 炸弹 shader：`res://prefabs/Bombs/res/bomb.gdshader`（如有）
- 场景专属资源子目录统一命名为 `res/`

## 架构约定
- `map_classic.gd` **完全独立**，只负责地图生成，不依赖 GameMode；通过 `signal map_generated(seed)` 通知外部
- `game_stage.tscn` 是游戏容器场景（Camera2D + HUD CanvasLayer），`game_stage.gd` 在 `_ready()` 实例化 map_classic
- `GameMode.start_game()` 实例化 game_stage，连接 map 的 `map_generated` 信号，然后生成玩家
- 玩家生命周期（spawn/die/settlement）由 GameMode 管理，不在 map 脚本中
- `is_connected_to_host` 是 NetworkManager 的 **变量**（property），不是函数，访问时不加括号

## 地图规格
- **默认尺寸**: 25×25（含边界墙）
- **结构**: 十字形5区域 — 四角独立房间 + 中心十字通道，每区域内部均为经典炸弹人布局
- **区域划分**:
  - 区域1(左上): `_fill_region_classic(1, 1, 8, 8)`，内部 x[2,7] y[2,7]
  - 区域2(右上): `_fill_region_classic(16, 1, 8, 8)`，内部 x[17,22] y[2,7]
  - 区域3(中心): 十字臂 x[10,14] y[1,23] + x[1,23] y[10,14]
  - 区域4(左下): `_fill_region_classic(1, 16, 8, 8)`，内部 x[2,7] y[17,22]
  - 区域5(右下): `_fill_region_classic(16, 16, 8, 8)`，内部 x[17,22] y[17,22]
- **分隔墙**: 不可破坏墙在 x=9,15 和 y=9,15，每面开2格固定缺口通行
- **缺口位置**: x=9/15 在 y=4,5,19,20；y=9/15 在 x=4,5,19,20
- **经典布局**: 偶数坐标(x%2==0 && y%2==0)放不可破坏柱子，非柱子格 65% 概率可破坏墙
- **十字区域**: 可破坏墙概率降低到 45%（通道需更多移动空间）
- **出生保护**: 四角各 3×2 区域无墙
- **边界墙**: 用 MAP_Indestructible_WALL3

## HUD 玩家状态卡片 API（2026-05-16 更新）
- `PlayerStatusCard.update_stats(bombs, max_bombs, pow_up, max_up, pow_down, max_down, pow_left, max_left, pow_right, max_right, shields, max_shields, speed, max_speed)`
- 四维威力：各方向实际威力 = `min(currentRadius, explosionRadiusCap + radiusXxxCap)`，在 game_mode.gd tick() 中计算
- `hud.update_player_stats()` 签名同上（多一个 peer_id 首参）
- 旧 `updateStats()` 兼容层保留，内部推算四维威力后转发

## 战前战备/仓库系统（2026-05-17 完善）
- **战前战备场景**：`res://scenes/Warehouse/backpack_config.tscn` + `backpack_config.gd`
- **独立仓库场景**：`res://scenes/Warehouse/warehouse.tscn` + `warehouse.gd`
- **仓库物品卡片**：`res://scenes/Warehouse/sub/item_card.tscn` + `item_card.gd`
- **背包核心**：`res://prefabs/Backpack/backpack.gd`（8×8主网格+2×2保险格）
- **背包物品UI**：`res://prefabs/Backpack/sub/backpack_item.gd`（class_name: BackpackItem）
- **物品资源**：`res://prefabs/Backpack/item_resource.gd`（class_name: BackpackItemResource）
- **全局玩家数据**：`res://autoloads/player_data.gd`（GlobalPlayerData 单例）
- `GlobalPlayerData.owned_items`：仓库物品列表（Array[String] 资源路径）
- `GlobalPlayerData.backpack_config`：背包配置（Array[Dictionary]）
- `GlobalPlayerData.backpack_presets`：战备方案（Array[Array]，3套）
- `GlobalPlayerData.sell_item(path, price)`：售出物品
- `item_card.setup(res: BackpackItemResource, path: String)`：卡片初始化签名
- 售出价值 = 基础属性加成总值 × 稀有度系数（RARE×1/EPIC×2/DIAMOND×4）

## 工具与开发规范约定
- **客户端修改规范**: 每次修改客户端（Godot）内容时，**都必须调用 godot-mcp 工具**（例如用于解析场景文件 `read_scene`、修改场景属性 `modify_scene_node`、运行时调试 `game_eval` 等），以保证代码修改与 Godot 编辑器的引擎数据和场景文件结构完全同步一致。

## 重要修复记录（2026-05-06）
见每日日志

