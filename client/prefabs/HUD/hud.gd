# 游戏 HUD 逻辑模块
# 负责顶部计时/存活显示、通知、倒计时提示，以及左侧多玩家状态框管理
# 创建时间：2026-05-08
# 更新：2026-05-11 - 连接背包按钮
# 更新：2026-05-16 - 新增左侧 PlayerStatusCard 多玩家状态框

extends CanvasLayer

class_name HUD

# ── PlayerStatusCard 预制体 ───────────────────────────────────────
const PlayerStatusCardScene = preload("res://prefabs/HUD/PlayerStatusCard.tscn")

# ── 节点引用 ──────────────────────────────────────────────────────
@onready var playerStatusList: VBoxContainer = $MarginContainer/RootHBox/LeftPanel/PlayerStatusList
@onready var countdownLabel: Label           = $CountdownLabel
@onready var backpackBtn: Button             = $MarginContainer/RootHBox/RightPanel/BottomRight/BackpackBtn
@onready var notifyLabel: Label              = %NotificationLabel
@onready var timeLabel: Label                = $MarginContainer/RootHBox/CenterPanel/TopCenter/TopCenterVBox/TimeLabel
@onready var survivalLabel: Label            = $MarginContainer/RootHBox/CenterPanel/TopCenter/TopCenterVBox/SurvivalLabel

# 玩家 peer_id → PlayerStatusCard 实例 的映射
var _cards: Dictionary = {}

# ── 生命周期 ──────────────────────────────────────────────────────
func _ready() -> void:
	if backpackBtn:
		backpackBtn.pressed.connect(_on_backpack_btn_pressed)

# ── 多玩家状态框 API ──────────────────────────────────────────────

## 初始化所有玩家状态框
## player_list: Array of Dictionary { "peer_id": int, "name": String, "player_idx": int, "avatar": Texture2D(可选) }
func setup_players(player_list: Array) -> void:
	if not playerStatusList:
		push_warning("[HUD] PlayerStatusList 节点未找到")
		return

	# 清空旧卡片
	for child in playerStatusList.get_children():
		child.queue_free()
	_cards.clear()

	for info in player_list:
		var peer_id: int      = info.get("peer_id", 0)
		var pname: String     = info.get("name", "破壁者")
		var pidx: int         = info.get("player_idx", 0)
		var avatar: Texture2D = info.get("avatar", null)

		var card = PlayerStatusCardScene.instantiate()
		playerStatusList.add_child(card)
		card.setup(pidx, pname, avatar)
		_cards[peer_id] = card

## 数据驱动刷新指定玩家的 HUD 卡片状态
func refresh_player_hud(peer_id: int, player: Node) -> void:
	var card = _cards.get(peer_id, null)
	if card and is_instance_valid(card):
		card.refresh_from_player(player)

# ── 背包按钮 ──────────────────────────────────────────────────────
func _on_backpack_btn_pressed() -> void:
	var backpack = get_tree().get_first_node_in_group("Backpack") if get_tree() else null
	if not backpack:
		var stage = get_parent()
		if stage:
			backpack = stage.get_node_or_null("BackpackLayer/Backpack")
	if backpack and backpack.has_method("toggle"):
		backpack.toggle()
	else:
		print("[HUD] 找不到背包节点")

# ── 全局 HUD 显示 ─────────────────────────────────────────────────

## 更新顶部计时器
func updateTime(seconds: float) -> void:
	if not timeLabel: return
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	timeLabel.text = "%02d:%02d" % [m, s]
	if seconds < 30:
		timeLabel.add_theme_color_override("font_color", Color.RED)
	else:
		timeLabel.remove_theme_color_override("font_color")

## 更新存活人数
func updateSurvivors(count: int) -> void:
	if survivalLabel:
		survivalLabel.text = "存活: %d" % count

## 弹出通知文字
func showNotification(text: String, duration: float = 5.0) -> void:
	if not notifyLabel: return
	notifyLabel.text = text
	notifyLabel.modulate.a = 1.0
	notifyLabel.show()
	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_property(notifyLabel, "modulate:a", 0.0, 1.0)
	tween.finished.connect(func(): notifyLabel.hide())

## 启动对局开始倒计时动画（3→2→1→开始！）
func startCountdown() -> void:
	if not countdownLabel: return
	countdownLabel.show()
	for i: int in range(3, 0, -1):
		countdownLabel.text = str(i)
		countdownLabel.scale = Vector2(2, 2)
		var tween: Tween = create_tween()
		tween.tween_property(countdownLabel, "scale", Vector2(1, 1), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(1.0).timeout
	countdownLabel.text = "开始！"
	var tween: Tween = create_tween()
	tween.tween_property(countdownLabel, "modulate:a", 0.0, 0.5)
	await tween.finished
	countdownLabel.hide()
	countdownLabel.modulate.a = 1.0

# ── 兼容旧 API（自机单玩家状态，已被多玩家 API 取代，保留避免报错）─
func updateStats(bombs: int, maxBombs: int, speed: float, maxSpeed: float, shields: int, maxShields: int, current_r: int, base_limit: int, _r_up: int, _r_down: int, _r_left: int, _r_right: int) -> void:
	var local_id := int(multiplayer.get_unique_id()) if multiplayer else 0
	var gm = get_node_or_null("/root/GameMode")
	if gm and gm.has_method("get_local_player"):
		var lp = gm.get_local_player()
		if lp:
			refresh_player_hud(local_id, lp)
