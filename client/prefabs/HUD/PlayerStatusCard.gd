# 玩家状态卡片 (PixelBomb Premium Edition)
# 挂载在 PlayerStatusCard.tscn 的根节点 PanelContainer 上
# 重构时间：2026-05-20 - 升级为 Emoji 图标与 3 行紧凑中文高亮排版

extends PanelContainer

# ── 节点引用（通过 unique_name 访问）──────────────────────────────
@onready var avatar_rect: TextureRect   = %AvatarRect
@onready var name_label: Label          = %NameLabel
@onready var pid_label: Label           = %PidLabel
@onready var status_label: Label        = %StatusLabel
@onready var bomb_label: Label          = %BombLabel
@onready var power_label: RichTextLabel = %PowerLabel
@onready var shield_label: Label        = %ShieldLabel
@onready var speed_label: Label         = %SpeedLabel

# 玩家颜色主题（R/G/B for modulate）
const PLAYER_COLORS: Array[Color] = [
	Color(0.22, 0.62, 0.85, 1),  # P1 蓝
	Color(0.85, 0.35, 0.22, 1),  # P2 橙红
	Color(0.39, 0.72, 0.27, 1),  # P3 绿
	Color(0.85, 0.65, 0.13, 1),  # P4 金
]

var _player_idx: int = 0
var _is_dead: bool    = false

# ── 初始化 ─────────────────────────────────────────────────────────
func setup(player_idx: int, player_name: String, avatar_tex: Texture2D = null) -> void:
	_player_idx = player_idx
	_is_dead    = false

	if name_label:
		name_label.text = player_name
	if pid_label:
		pid_label.text  = "玩家 %d" % (player_idx + 1)
	if avatar_rect:
		if avatar_tex:
			avatar_rect.texture = avatar_tex
			avatar_rect.modulate = Color.WHITE
		else:
			# 无头像时显示彩色占位方块
			avatar_rect.modulate = PLAYER_COLORS[player_idx % PLAYER_COLORS.size()]

	# 设置左侧边框色与 80% 透明黑遮罩
	_apply_accent(player_idx)
	_is_dead = false
	modulate.a = 1.0
	if status_label:
		status_label.text = "存活"
		status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 0.7))

# ── 状态更新 ───────────────────────────────────────────────────────
## 通过直接绑定玩家实例数据进行一站式刷新 (数据驱动)
func refresh_from_player(player: Node) -> void:
	if not is_instance_valid(player):
		return

	# 1. 判定死亡状态并刷新视觉
	var dead: bool = player.get("isDead") if player.get("isDead") != null else false
	if dead:
		_is_dead = true
		if status_label:
			status_label.text = "已阵亡"
			status_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		modulate.a = 0.45
	else:
		_is_dead = false
		modulate.a = 1.0
		if status_label:
			status_label.text = "存活"
			status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 0.7))

	# 2. 刷新炸弹数 (显示当前最大携带量 / 背包天花板上限)
	var cur_bombs: int = player.get("currentMaxBombs") if player.get("currentMaxBombs") != null else 1
	var cap_bombs: int = player.get("maxBombsCap") if player.get("maxBombsCap") != null else 2
	if bomb_label:
		bomb_label.text = "炸弹 %d/%d" % [cur_bombs, cap_bombs]
		bomb_label.add_theme_color_override("font_color", Color("#ffffff"))

	# 3. 刷新威力值和四向威力上限
	var cur_r: int = player.get("currentRadius") if player.get("currentRadius") != null else 1
	var pow_up: int = player.get("radiusUpCap") if player.get("radiusUpCap") != null else 0
	var pow_down: int = player.get("radiusDownCap") if player.get("radiusDownCap") != null else 0
	var pow_left: int = player.get("radiusLeftCap") if player.get("radiusLeftCap") != null else 0
	var pow_right: int = player.get("radiusRightCap") if player.get("radiusRightCap") != null else 0
	if power_label:
		power_label.text = "[color=#ffb300]威力 %d[/color] [color=#ff4d4d](上%d 下%d 左%d 右%d)[/color]" % [cur_r, pow_up, pow_down, pow_left, pow_right]

	# 4. 刷新护盾层数
	var shields: int = player.get("currentShields") if player.get("currentShields") != null else 0
	var max_shields: int = player.get("maxShieldsCap") if player.get("maxShieldsCap") != null else 1
	if shield_label:
		shield_label.text = "护盾 %d/%d" % [shields, max_shields]
		if shields > 0:
			shield_label.add_theme_color_override("font_color", Color("#4a90e2"))
		else:
			shield_label.add_theme_color_override("font_color", Color("#888888"))

	# 5. 刷新移动速度
	var speed: float = player.get("currentSpeed") if player.get("currentSpeed") != null else 75.0
	if speed_label:
		var base_speed := 75.0
		var speed_pct := int(round((speed - base_speed) / base_speed * 100.0))
		speed_label.text = "速度 +%d%%" % speed_pct if speed_pct >= 0 else "速度 %d%%" % speed_pct
		speed_label.add_theme_color_override("font_color", Color("#86efac"))

# ── 私有辅助 ───────────────────────────────────────────────────────
func _apply_accent(idx: int) -> void:
	# 通过 StyleBoxFlat 给卡片左边框上色，体现玩家颜色，整体加 55% 透明度黑色遮罩背景板，且左边框弱化为 12px，阴影大小增大为 4px
	var color: Color = PLAYER_COLORS[idx % PLAYER_COLORS.size()]
	var sb := StyleBoxFlat.new()
	sb.bg_color         = Color(0, 0, 0, 0.55) # 55% 透明度黑色遮罩背景板
	sb.border_width_left = 12 # 左边框配合大卡片加粗至 12px
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = color # 整个边框使用玩家主题色
	sb.set_corner_radius_all(20) # 圆角 20px
	
	# 弱化阴影效果
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 4 # 阴影大小调整为 4px
	sb.shadow_offset = Vector2(0, 2)
	
	add_theme_stylebox_override("panel", sb)
