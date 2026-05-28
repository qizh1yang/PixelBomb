# 破壁者准备室 - 深度定制版
extends Control

# ── 节点引用 ──
@onready var roomCodeLabel: Label = %RoomCode
@onready var roomCodeRightLabel: Label = %RoomCodeRight
@onready var playerNameLabel: Label = %CurrentPlayerName
@onready var charList: VBoxContainer = %CharList
@onready var playerSlotContainer: VBoxContainer = %PlayerList
@onready var actionBtn: Button = %ActionBtn
@onready var missionInfo: VBoxContainer = %MissionInfo
@onready var statusHint: Label = %StatusHint

@onready var copyCodeBtn: Button = %CopyCodeBtn
@onready var inviteBtn: Button = %InviteBtn
@onready var charPreview: TextureRect = %CharPreview
@onready var toastPanel: PanelContainer = %ToastPanel
@onready var toastLabel: Label = %ToastLabel

# ── 预制体 ──
var CharCardScene = preload("res://scenes/Room/sub/character_card.tscn")
var PlayerSlotScene = preload("res://scenes/Room/sub/player_slot.tscn")

# ── 数据 ──
var player_slots: Array = []
var char_cards: Array = []
var _toast_tween: Tween

# ── [MAP CONFIG] 地图配置 UI 节点 (动态创建) ──
var _map_panel: PanelContainer = null
var _map_name_label: Label = null
var _map_left_btn: Button = null
var _map_right_btn: Button = null
var _map_preview: Control = null  # MapPreviewRenderer 实例
var _map_shape_label: Label = null
var _map_size_label: Label = null
var _roll_seed_btn: Button = null
var _map_config_locked_hint: Label = null

# 地图类型循环列表
var _MAP_TYPES: Array[String] = []  # populated in _ready() from MapFactory
const _SHAPE_TYPES: Array[String] = ["circle", "hexagon", "star", "ring", "cave"]
const _SIZE_TYPES: Array[String] = ["small", "medium", "large"]
const _SHAPE_NAMES: Dictionary = {"circle":"圆形","hexagon":"六边形","star":"星形","ring":"环形","cave":"洞穴"}
const _SIZE_NAMES: Dictionary = {"small":"小","medium":"中","large":"大"}

func _ready() -> void:
	# 初始化 UI 骨架
	# [MAP CONFIG] 动态从 MapFactory 获取所有可用地图类型
	_MAP_TYPES = MapFactory.get_all_map_types()
	# DEV: 仅开放经典地图，其余地图开发中
	_MAP_TYPES = _MAP_TYPES.filter(func(t): return t == "CLASSIC")
	print("[RoomUI] Map types available: %s (dev-locked to CLASSIC)" % str(_MAP_TYPES))
	_setup_char_selection()
	_setup_player_slots()
	
	# 连接新建交互按钮的信号
	copyCodeBtn.pressed.connect(_on_copy_code_pressed)
	inviteBtn.pressed.connect(_on_invite_pressed)
	
	# 连接网络信号
	var net = NetworkManager
	net.room_state_updated.connect(_on_room_state_updated)
	net.host_updated.connect(_on_host_updated)
	net.game_started.connect(_on_game_started)
	
	# [MAP CONFIG] 动态创建地图配置面板并插入到 missionInfo 区域
	_setup_map_config_panel()
	
	# 初始更新
	_refresh_ui()

func _setup_char_selection() -> void:
	for child in charList.get_children(): child.queue_free()
	char_cards.clear()
	
	# 使用 CharacterRegistry 动态获取所有角色资源
	var all_chars = CharacterRegistry.get_all_characters()
	for char_res in all_chars:
		var card = CharCardScene.instantiate()
		charList.add_child(card)
		
		var idx = char_res.char_index
		var texture = char_res.icon
		if not texture:
			# 如果资源里没配置 icon，则使用默认的路径规则
			var texture_path = "res://prefabs/Players/player%d/res/Faceset.png" % (idx + 1)
			if ResourceLoader.exists(texture_path):
				texture = load(texture_path)
				
		card.setup(idx, char_res.display_name, char_res.description, texture)
		card.pressed.connect(_on_char_selected.bind(idx))
		char_cards.append(card)
	
	_update_char_highlight()

func _setup_player_slots() -> void:
	for child in playerSlotContainer.get_children(): child.queue_free()
	player_slots.clear()
	for i in range(4):
		var slot = PlayerSlotScene.instantiate()
		playerSlotContainer.add_child(slot)
		slot.set_empty()
		# 关联空槽位的点击一键邀请信号
		slot.invite_clicked.connect(_on_invite_pressed)
		player_slots.append(slot)

func _refresh_ui() -> void:
	var net = NetworkManager
	roomCodeLabel.text = "出发准备室 #%s" % net.current_room
	roomCodeRightLabel.text = "队伍 ID: #Room_%s" % net.current_room
	playerNameLabel.text = "当前账号：%s" % net.player_name
	
	_update_player_list()
	_update_action_button()
	_update_char_highlight()

func _update_player_list() -> void:
	var net = NetworkManager
	var players = net.room_players
	
	# 重置所有槽位
	for slot in player_slots:
		slot.set_empty()
		
	var all_ready = true
	for i in range(players.size()):
		if i < player_slots.size():
			var p_info = players[i]
			var is_self = (net.clean_id(p_info.get("id")) == net.my_id)
			player_slots[i].set_player(p_info, is_self, net.is_host)
			if not p_info.get("ready", false):
				all_ready = false
				
	if players.size() < 2: all_ready = false
	
	statusHint.visible = not all_ready
	statusHint.text = "等待所有破壁者就位..." if players.size() > 1 else "等待队友加入..."
	
	# [MAP CONFIG] 同步刷新地图配置 UI
	_refresh_map_config_ui()
 
func _update_action_button() -> void:
	var net = NetworkManager
	if net.is_host:
		# [ROOM STATE LOCK] 检测是否有非房主队员已 Ready
		var is_any_member_ready = false
		for p in net.room_players:
			if net.clean_id(p.get("id")) != net.my_id and p.get("ready", false):
				is_any_member_ready = true
				break
		var all_others_ready = true
		for p in net.room_players:
			if net.clean_id(p.get("id")) != net.my_id and not p.get("ready", false):
				all_others_ready = false
		
		actionBtn.text = "开始出发"
		actionBtn.disabled = not all_others_ready or net.room_players.size() < 2
		if actionBtn.disabled:
			actionBtn.modulate = Color(0.5, 0.5, 0.5)
		else:
			actionBtn.modulate = Color.WHITE
		
		# [ROOM STATE LOCK] 若有队员 Ready，锁定房主的地图配置 UI，防止时序错乱
		var can_config = not is_any_member_ready
		if is_instance_valid(_map_left_btn): _map_left_btn.disabled = not can_config
		if is_instance_valid(_map_right_btn): _map_right_btn.disabled = not can_config
		if is_instance_valid(_roll_seed_btn): _roll_seed_btn.disabled = not can_config
		if is_instance_valid(_map_config_locked_hint):
			_map_config_locked_hint.visible = is_any_member_ready
	else:
		var my_ready = false
		for p in net.room_players:
			if net.clean_id(p.get("id")) == net.my_id:
				my_ready = p.get("ready", false)
				break
		
		actionBtn.text = "取消准备" if my_ready else "准备就绪"
		actionBtn.disabled = false
		actionBtn.modulate = Color("#5CDB6F") if not my_ready else Color("#888888")

func _update_char_highlight() -> void:
	var current_idx = NetworkManager.selected_char_index
	for card in char_cards:
		card.set_selected(card.char_index == current_idx)
		
	# 动态联动：在右列显示当前选中角色的科技感半透明高清立绘
	var texture_path = "res://prefabs/Players/player%d/res/Idle.png" % (current_idx + 1)
	if ResourceLoader.exists(texture_path):
		var new_tex = load(texture_path)
		if charPreview.texture != new_tex:
			charPreview.texture = new_tex
			charPreview.modulate.a = 0.0
			var tween = create_tween()
			tween.tween_property(charPreview, "modulate:a", 0.7, 0.25)

# ── 科技感 Toast 通知体系 ──

func show_toast(text: String) -> void:
	toastLabel.text = text
	toastPanel.show()
	
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
		
	toastPanel.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(toastPanel, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(1.5)
	_toast_tween.tween_property(toastPanel, "modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(toastPanel.hide)

# ── 交互回调 ──

func _on_char_selected(idx: int) -> void:
	NetworkManager.selected_char_index = idx
	_update_char_highlight()
	# 同步到服务端
	NetworkManager.request("Room.Update", { "char": idx })

func _on_action_pressed() -> void:
	var net = NetworkManager
	if net.is_host:
		net.start_game_request()
		actionBtn.text = "出发中..."
		actionBtn.disabled = true
	else:
		net.toggle_ready()

func _on_solo_test_pressed() -> void:
	# 绕过人数限制直接请求开始游戏
	NetworkManager.start_game_request()
	actionBtn.text = "单人测试中..."
	actionBtn.disabled = true

func _on_leave_pressed() -> void:
	NetworkManager.leave_room()
	UIManager.change_scene("lobby")

func _on_room_state_updated(_players: Array) -> void:
	_refresh_ui()

func _on_host_updated(_is_host: bool, _host_id: String) -> void:
	_refresh_ui()

func _on_game_started() -> void:
	if GameMode.has_method("prepare_for_game"):
		GameMode.prepare_for_game()
	UIManager.change_scene("game")

func _on_copy_code_pressed() -> void:
	DisplayServer.clipboard_set(NetworkManager.current_room)
	show_toast("已成功复制房间码！")

func _on_invite_pressed() -> void:
	DisplayServer.clipboard_set(NetworkManager.current_room)
	show_toast("房间码已复制到剪贴板，快去邀请你的好友吧！")

# ══════════════════════════════════════════════════════
# [MAP CONFIG] 动态地图配置面板
# ══════════════════════════════════════════════════════

## 在 missionInfo 区域动态创建地图配置面板
func _setup_map_config_panel() -> void:
	if not is_instance_valid(missionInfo):
		return
	
	# 清理旧面板
	if is_instance_valid(_map_panel):
		_map_panel.queue_free()
	
	_map_panel = PanelContainer.new()
	_map_panel.name = "MapConfigPanel"
	missionInfo.add_child(_map_panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_map_panel.add_child(vbox)
	
	# 标题行
	var title = Label.new()
	title.text = "🗺 地图设置"
	title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(title)
	
	# 地图类型切换行（Host 专属）
	var type_row = HBoxContainer.new()
	vbox.add_child(type_row)
	
	_map_left_btn = Button.new()
	_map_left_btn.text = "◀"
	_map_left_btn.custom_minimum_size = Vector2(28, 28)
	_map_left_btn.pressed.connect(_on_map_type_prev)
	type_row.add_child(_map_left_btn)
	
	_map_name_label = Label.new()
	_map_name_label.text = "经典地图"
	_map_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_row.add_child(_map_name_label)
	
	_map_right_btn = Button.new()
	_map_right_btn.text = "▶"
	_map_right_btn.custom_minimum_size = Vector2(28, 28)
	_map_right_btn.pressed.connect(_on_map_type_next)
	type_row.add_child(_map_right_btn)
	
	# 地图预览区域
	var preview_container = Control.new()
	preview_container.custom_minimum_size = Vector2(0, 80)
	preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(preview_container)
	
	# 动态创建 MapPreviewRenderer 实例（仅在脚本可用时）
	var prev_script = load("res://prefabs/map/core/map_preview_renderer.gd")
	if prev_script == null:
		print("[RoomUI] WARNING: map_preview_renderer.gd failed to load, preview disabled")
	else:
		_map_preview = Control.new()
		_map_preview.set_script(prev_script)
		_map_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview_container.add_child(_map_preview)
	
	# Shape 行（仅 PROCEDURAL 显示）
	var shape_row = HBoxContainer.new()
	vbox.add_child(shape_row)
	
	var shape_lbl = Label.new()
	shape_lbl.text = "形状："
	shape_row.add_child(shape_lbl)
	
	_map_shape_label = Label.new()
	_map_shape_label.text = "圆形"
	_map_shape_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shape_row.add_child(_map_shape_label)
	
	var shape_left = Button.new()
	shape_left.text = "◀"
	shape_left.custom_minimum_size = Vector2(24, 24)
	shape_left.pressed.connect(_on_shape_prev)
	shape_row.add_child(shape_left)
	
	var shape_right = Button.new()
	shape_right.text = "▶"
	shape_right.custom_minimum_size = Vector2(24, 24)
	shape_right.pressed.connect(_on_shape_next)
	shape_row.add_child(shape_right)
	
	# Size 行
	var size_row = HBoxContainer.new()
	vbox.add_child(size_row)
	
	var size_lbl = Label.new()
	size_lbl.text = "大小："
	size_row.add_child(size_lbl)
	
	_map_size_label = Label.new()
	_map_size_label.text = "小"
	_map_size_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(_map_size_label)
	
	var size_left = Button.new()
	size_left.text = "◀"
	size_left.custom_minimum_size = Vector2(24, 24)
	size_left.pressed.connect(_on_size_prev)
	size_row.add_child(size_left)
	
	var size_right = Button.new()
	size_right.text = "▶"
	size_right.custom_minimum_size = Vector2(24, 24)
	size_right.pressed.connect(_on_size_next)
	size_row.add_child(size_right)
	
	# 重滚 Seed 按钮（Host 专属）
	_roll_seed_btn = Button.new()
	_roll_seed_btn.text = "🎲 重滚随机种子"
	_roll_seed_btn.pressed.connect(_on_roll_seed)
	vbox.add_child(_roll_seed_btn)
	
	# 状态锁定提示（队员 Ready 后出现）
	_map_config_locked_hint = Label.new()
	_map_config_locked_hint.text = "⚠ 已有队员就绪，地图配置已锁定"
	_map_config_locked_hint.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
	_map_config_locked_hint.add_theme_font_size_override("font_size", 10)
	_map_config_locked_hint.visible = false
	vbox.add_child(_map_config_locked_hint)
	
	_refresh_map_config_ui()

## 根据当前 NetworkManager 状态刷新地图配置 UI 显示
func _refresh_map_config_ui() -> void:
	if not is_instance_valid(_map_panel): return
	var net = NetworkManager
	print("[RoomUI] MAP-REFRESH: type=%s shape=%s size=%s seed=%d is_host=%s" % [net.current_map_type, net.current_shape_type, net.current_map_size, net.map_seed, str(net.is_host)])
	
	var map_type = net.current_map_type
	var shape = net.current_shape_type
	var size = net.current_map_size
	
	# 更新文字标签
	if is_instance_valid(_map_name_label):
		_map_name_label.text = MapFactory.get_map_display_name(map_type)
	if is_instance_valid(_map_shape_label):
		_map_shape_label.text = _SHAPE_NAMES.get(shape, shape)
	if is_instance_valid(_map_size_label):
		_map_size_label.text = _SIZE_NAMES.get(size, size)
	
	# Shape 和 Size 行仅 PROCEDURAL 显示
	var is_procedural = (map_type == "PROCEDURAL")
	if is_instance_valid(_map_shape_label):
		_map_shape_label.get_parent().visible = is_procedural
	if is_instance_valid(_map_size_label):
		_map_size_label.get_parent().visible = is_procedural
	if is_instance_valid(_roll_seed_btn):
		_roll_seed_btn.visible = is_procedural
	
	# 控件可见性：Host 显示操控，非 Host 仅显示标签
	# 只有单个地图类型时禁用切换按钮
	var single_map = _MAP_TYPES.size() <= 1
	if is_instance_valid(_map_left_btn):
		_map_left_btn.visible = net.is_host
		_map_left_btn.disabled = single_map
		_map_right_btn.visible = net.is_host
		_map_right_btn.disabled = single_map
	
	# 触发预览重绘
	if is_instance_valid(_map_preview) and _map_preview.has_method("setup"):
		_map_preview.call("setup", map_type, shape, size, net.map_seed)

# ── 地图配置交互回调 (Host Only) ──

func _on_map_type_prev() -> void:
	if not NetworkManager.is_host: return
	if _MAP_TYPES.is_empty(): return
	print('[RoomUI] MAP-SWITCH: prev clicked, current=%s' % NetworkManager.current_map_type)
	var idx = _MAP_TYPES.find(NetworkManager.current_map_type)
	idx = (idx - 1 + _MAP_TYPES.size()) % _MAP_TYPES.size()
	var new_type = _MAP_TYPES[idx]
	print("[RoomUI] MAP-SWITCH: sending UpdateMapConfig type=%s" % new_type)
	# 乐观本地更新：立即刷新 UI，不等待服务端 onRoomUpdate 回环
	NetworkManager.current_map_type = new_type
	_refresh_map_config_ui()
	NetworkManager.update_map_config(new_type, "", "", 0)

func _on_map_type_next() -> void:
	if not NetworkManager.is_host: return
	if _MAP_TYPES.is_empty(): return
	print('[RoomUI] MAP-SWITCH: next clicked, current=%s' % NetworkManager.current_map_type)
	var idx = _MAP_TYPES.find(NetworkManager.current_map_type)
	idx = (idx + 1) % _MAP_TYPES.size()
	var new_type = _MAP_TYPES[idx]
	print("[RoomUI] MAP-SWITCH: sending UpdateMapConfig type=%s" % new_type)
	# 乐观本地更新：立即刷新 UI，不等待服务端 onRoomUpdate 回环
	NetworkManager.current_map_type = new_type
	_refresh_map_config_ui()
	NetworkManager.update_map_config(new_type, "", "", 0)

func _on_shape_prev() -> void:
	if not NetworkManager.is_host: return
	var idx = _SHAPE_TYPES.find(NetworkManager.current_shape_type)
	idx = (idx - 1 + _SHAPE_TYPES.size()) % _SHAPE_TYPES.size()
	var new_shape = _SHAPE_TYPES[idx]
	NetworkManager.current_shape_type = new_shape
	_refresh_map_config_ui()
	NetworkManager.update_map_config("", new_shape, "", 0)

func _on_shape_next() -> void:
	if not NetworkManager.is_host: return
	var idx = _SHAPE_TYPES.find(NetworkManager.current_shape_type)
	idx = (idx + 1) % _SHAPE_TYPES.size()
	var new_shape = _SHAPE_TYPES[idx]
	NetworkManager.current_shape_type = new_shape
	_refresh_map_config_ui()
	NetworkManager.update_map_config("", new_shape, "", 0)

func _on_size_prev() -> void:
	if not NetworkManager.is_host: return
	var idx = _SIZE_TYPES.find(NetworkManager.current_map_size)
	idx = (idx - 1 + _SIZE_TYPES.size()) % _SIZE_TYPES.size()
	var new_size = _SIZE_TYPES[idx]
	NetworkManager.current_map_size = new_size
	_refresh_map_config_ui()
	NetworkManager.update_map_config("", "", new_size, 0)

func _on_size_next() -> void:
	if not NetworkManager.is_host: return
	var idx = _SIZE_TYPES.find(NetworkManager.current_map_size)
	idx = (idx + 1) % _SIZE_TYPES.size()
	var new_size = _SIZE_TYPES[idx]
	NetworkManager.current_map_size = new_size
	_refresh_map_config_ui()
	NetworkManager.update_map_config("", "", new_size, 0)

func _on_roll_seed() -> void:
	if not NetworkManager.is_host: return
	var new_seed = randi()
	NetworkManager.map_seed = new_seed
	_refresh_map_config_ui()
	NetworkManager.update_map_config("", "", "", new_seed)
	show_toast("🎲 已重滚新种子：%d" % new_seed)
