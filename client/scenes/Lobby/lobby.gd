# 大厅（任务中心）逻辑
extends Control

# ── 节点引用 ──
@onready var roomList: VBoxContainer = %RoomList
@onready var playerNameLabel: Label = %PlayerName
@onready var coinsLabel: Label = %CoinsLabel
@onready var missionCountLabel: Label = %MissionCount
@onready var refreshBtn: Button = %RefreshBtn
@onready var createBtn: Button = %CreateBtn
@onready var connStatus: Label = %ConnStatus

# ── 预制体 ──
var RoomCardScene = preload("res://scenes/Lobby/sub/room_card.tscn")

func _ready() -> void:
	var net = NetworkManager
	net.room_list_received.connect(_on_room_list_received)
	net.room_joined.connect(_on_room_joined)
	net.room_join_failed.connect(_on_room_join_failed)
	net.connection_closed.connect(_on_connection_lost)
	net.connected_to_server.connect(_on_connection_restored)
	
	if not GlobalPlayerData.sync_completed.is_connected(_refresh_ui):
		GlobalPlayerData.sync_completed.connect(_refresh_ui)
	
	_refresh_ui()
	
	# 初始同步个人信息（仓库、背包）
	net.fetch_profile()
	
	# 初始请求房间列表
	net.request_room_list()
	
	var logout_btn = get_node_or_null("MainLayout/BottomBar/Margin/HBox/LogoutBtn")
	if logout_btn:
		logout_btn.mouse_entered.connect(func(): logout_btn.add_theme_color_override("font_color", Color("#b96a5d")))
		logout_btn.mouse_exited.connect(func(): logout_btn.add_theme_color_override("font_color", Color("#B8B2A7")))

func _refresh_ui() -> void:
	var net = NetworkManager
	playerNameLabel.text = net.player_name
	coinsLabel.text = "%s" % _format_number(GlobalPlayerData.coins)
	
	_update_connection_status()

func _format_number(n: int) -> String:
	var s = str(n)
	var result = ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result

func _update_connection_status() -> void:
	var net = NetworkManager
	if net.is_connected_to_host:
		connStatus.text = "● 已连接至沧溟海联合事务所"
		connStatus.modulate = Color("#7fa97a")
	else:
		connStatus.text = "● 连接中断"
		connStatus.modulate = Color("#b96a5d")

# ── 信号回调 ──

func _on_room_list_received(rooms: Array) -> void:
	for child in roomList.get_children():
		child.queue_free()
	
	var valid_rooms = []
	for room_data in rooms:
		var current_players = int(room_data.get("player_count", 0))
		if current_players > 0:
			valid_rooms.append(room_data)
			
	missionCountLabel.text = "共 %d 个探索任务" % valid_rooms.size()
	
	if valid_rooms.is_empty():
		var empty_label = Label.new()
		empty_label.text = "暂无探索任务，创建一个？"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.modulate.a = 0.5
		roomList.add_child(empty_label)
	else:
		for room_data in valid_rooms:
			var card = RoomCardScene.instantiate()
			roomList.add_child(card)
			card.setup(room_data)
			card.join_pressed.connect(_on_join_room.bind(str(room_data.get("name", ""))))

func _on_join_room(room_id: String) -> void:
	NetworkManager.join_room(room_id)

func _on_refresh_pressed() -> void:
	NetworkManager.request_room_list()
	# 简单的旋转动画效果
	var tween = create_tween()
	tween.tween_property(refreshBtn, "rotation_degrees", 360, 0.5).from(0)

func _on_create_pressed() -> void:
	# 防御性清理：如果残留房间状态，先离开旧房间
	if NetworkManager.current_room != "":
		NetworkManager.leave_room()
	NetworkManager.request("Room.Create", {"name": "Room_%d" % randi_range(1000, 9999)})

func _on_room_joined(_seed: int) -> void:
	UIManager.change_scene("room")

func _on_room_join_failed(message: String) -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "加入失败"
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()

func _on_connection_lost() -> void:
	_update_connection_status()

func _on_connection_restored() -> void:
	_update_connection_status()
	NetworkManager.fetch_profile()
	NetworkManager.request_room_list()

func _on_logout_pressed() -> void:
	# 断开连接并返回登录 (Stash/Global Lobby)
	NetworkManager.disconnect_from_server()
	UIManager.change_scene("login")

func _on_maintenance_pressed() -> void:
	UIManager.change_scene("backpack_config")
