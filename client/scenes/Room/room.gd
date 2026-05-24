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

func _ready() -> void:
	# 初始化 UI 骨架
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
	
	# 初始更新
	_refresh_ui()

func _setup_char_selection() -> void:
	for child in charList.get_children(): child.queue_free()
	char_cards.clear()
	
	var names = ["烈焰破壁者", "寒冰破壁者", "自然破壁者", "虚空破壁者"]
	for i in range(4):
		var card = CharCardScene.instantiate()
		charList.add_child(card)
		var texture = load("res://prefabs/Players/player%d/res/Idle.png" % (i + 1))
		card.setup(i, names[i], texture)
		card.pressed.connect(_on_char_selected.bind(i))
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
				
	if players.size() < 2: all_ready = false # 至少两人？或者单人也可？策划没说，Demo暂定全员准备即可
	
	statusHint.visible = not all_ready
	statusHint.text = "等待所有破壁者就位..." if players.size() > 1 else "等待队友加入..."
 
func _update_action_button() -> void:
	var net = NetworkManager
	if net.is_host:
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
