extends Node

# Nano 协议常量
enum PacketType { HANDSHAKE = 1, HANDSHAKE_ACK = 2, HEARTBEAT = 3, DATA = 4, KICK = 5 }
enum MsgType { REQUEST = 0, NOTIFY = 1, RESPONSE = 2, PUSH = 3 }

## [NET] 日志工具
func net_log(msg: String) -> void:
	if OS.is_debug_build(): print("[NANO-NET] " + msg)

func net_warn(msg: String) -> void:
	if OS.is_debug_build(): push_warning("[NANO-NET] " + msg)

# 信号
signal connected_to_server()
signal connection_closed()
signal message_received(route: String, data: Dictionary)
signal profile_loaded(profile_data: Dictionary)
signal room_list_received(rooms: Array)
signal room_joined(seed_val: int)
signal host_updated(is_host: bool, host_id: String)
signal game_started()
signal room_state_updated(room_players: Array)
signal room_join_failed(message: String)

var socket := WebSocketPeer.new()
var http_client: HTTPRequest = null

var server_base_url := "http://127.0.0.1:8080"
var ws_url := "ws://127.0.0.1:8080/ws"

var is_connected_to_host := false
var my_id: String = ""
var player_name: String = "Player"
var current_room: String = ""
var is_host: bool = false
var room_players: Array = []
var players: Dictionary = {} # UID string -> Player info dict
var map_seed: int = 0
var seed_received: bool = false
var my_player_index: int = 0
var selected_char_index: int = 0

# 消息序列号与路由映射 (用于处理 Response)
var last_msg_id: int = 0
var pending_requests: Dictionary = {} # ID -> Route

## 安全且鲁棒地清洗用户ID，将其规范化为纯整数字符串，去除 JSON 解析可能引入的 .0 浮点后缀
func clean_id(val: Variant) -> String:
	if val == null:
		return ""
	var s = str(val).strip_edges()
	if s.ends_with(".0"):
		s = s.substr(0, s.length() - 2)
	return s

# ── 生命周期 ──

func _ready() -> void:
	http_client = HTTPRequest.new()
	add_child(http_client)
	net_log("Nano NetworkManager ready.")

func _process(_delta: float) -> void:
	socket.poll()
	var state = socket.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected_to_host:
			is_connected_to_host = true
			_send_handshake()
		
		while socket.get_available_packet_count():
			var packet = socket.get_packet()
			_handle_nano_packet(packet)
	
	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected_to_host:
			reset_state()
			connection_closed.emit()

# ── Nano 协议编解码 ──

func _send_handshake() -> void:
	var body = JSON.stringify({
		"sys": {"type": "js-websocket", "version": "0.0.1"},
		"user": {}
	}).to_utf8_buffer()
	_send_raw_packet(PacketType.HANDSHAKE, body)

func _handle_nano_packet(packet: PackedByteArray) -> void:
	if packet.size() < 4: return
	
	var type = packet[0]
	var length = (packet[1] << 16) | (packet[2] << 8) | packet[3]
	var body = packet.slice(4, 4 + length)
	
	match type:
		PacketType.HANDSHAKE:
			net_log("Handshake received, sending ACK...")
			_send_raw_packet(PacketType.HANDSHAKE_ACK, PackedByteArray())
			connected_to_server.emit()
		PacketType.HEARTBEAT:
			_send_raw_packet(PacketType.HEARTBEAT, PackedByteArray())
		PacketType.DATA:
			_handle_data_packet(body)

func _handle_data_packet(data: PackedByteArray) -> void:
	if data.is_empty(): return
	
	var flag = data[0]
	var msg_type = (flag >> 1) & 0x07
	var is_compressed = (flag & 0x01) > 0
	var offset = 1
	
	var msg_id = 0
	if msg_type == MsgType.REQUEST or msg_type == MsgType.RESPONSE:
		var shift = 0
		while true:
			var b = data[offset]
			msg_id |= (b & 0x7F) << shift
			offset += 1
			if not (b & 0x80): break
			shift += 7
	
	var route = ""
	# 关键：根据 Nano 协议，Response 类型不包含 Route 字符串
	if msg_type == MsgType.REQUEST or msg_type == MsgType.NOTIFY or msg_type == MsgType.PUSH:
		if is_compressed:
			var route_id = (data[offset] << 8) | data[offset+1]
			offset += 2
			route = "CompressedRoute_" + str(route_id)
		else:
			var route_len = data[offset]
			offset += 1
			route = data.slice(offset, offset + route_len).get_string_from_utf8()
			offset += route_len
	elif msg_type == MsgType.RESPONSE:
		# 从待处理请求中找回路由
		if pending_requests.has(msg_id):
			route = pending_requests[msg_id]
			pending_requests.erase(msg_id)
	
	var body_bytes = data.slice(offset)
	if body_bytes.is_empty(): return
	
	var body_str = body_bytes.get_string_from_utf8()
	var body = JSON.parse_string(body_str)
	if body == null:
		net_warn("JSON Parse Error. Raw: " + body_str)
		return
	
	if route != "":
		net_log("Route: " + route + " Msg: " + body_str)
		_dispatch_route_message(route, body)

func _dispatch_route_message(route: String, body: Variant) -> void:
	match route:
		"User.Auth":
			my_id = clean_id(body.get("id", ""))
			player_name = body.get("name", "")
			if body.has("data"):
				profile_loaded.emit(body.get("data", {}))
		"Room.Join", "Room.Create":
			if body.get("type") == "ERROR":
				var err_msg = body.get("message", "Unknown error")
				net_warn("Room join/create failed: " + err_msg)
				room_join_failed.emit(err_msg)
				return
			net_log("Room joined/created successfully: " + str(body.get("room", "")))
			current_room = str(body.get("room", ""))
			map_seed = int(body.get("seed", 0))
			seed_received = true
			is_host = (route == "Room.Create")
			room_joined.emit(map_seed)
		"Room.List":
			net_log("Room list updated, count: " + str(body.size() if body is Array else 0))
			room_list_received.emit(body if body is Array else [])
		"onGameStart":
			game_started.emit()
		"onMove":
			pass
		"User.GetProfile":
			profile_loaded.emit(body)
		"onRoomUpdate":
			room_players = body
			players.clear()
			for p in room_players:
				players[clean_id(p.id)] = p
			room_state_updated.emit(room_players)
	
	message_received.emit(route, body)

# ── 发送接口 ──

func request(route: String, data: Dictionary) -> void:
	_send_msg(MsgType.REQUEST, route, data)

func notify(route: String, data: Dictionary) -> void:
	_send_msg(MsgType.NOTIFY, route, data)

func _send_msg(type: int, route: String, data: Dictionary) -> void:
	# 核心修复：让 last_msg_id 在 [1, 127] 之间循环自增并回绕，保证请求端与接收端对齐
	last_msg_id = (last_msg_id + 1) & 0x7F
	if last_msg_id == 0:
		last_msg_id = 1
		
	var body_str = JSON.stringify(data)
	var body_bytes = body_str.to_utf8_buffer()
	
	var msg = PackedByteArray()
	msg.append(type << 1)
	
	if type == MsgType.REQUEST or type == MsgType.RESPONSE:
		# 直接写入 7位 回绕 ID，存储与解析使用完全一致的 Key
		msg.append(last_msg_id)
		if type == MsgType.REQUEST:
			pending_requests[last_msg_id] = route
	
	# Route (仅 Request, Notify, Push)
	if type != MsgType.RESPONSE:
		var route_bytes = route.to_utf8_buffer()
		msg.append(route_bytes.size())
		msg.append_array(route_bytes)
	
	msg.append_array(body_bytes)
	_send_raw_packet(PacketType.DATA, msg)

func _send_raw_packet(type: int, body: PackedByteArray) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
		
	var packet = PackedByteArray()
	packet.append(type)
	var length = body.size()
	packet.append((length >> 16) & 0xFF)
	packet.append((length >> 8) & 0xFF)
	packet.append(length & 0xFF)
	packet.append_array(body)
	socket.put_packet(packet)

# ── 业务接口 ──

func connect_to_server() -> void:
	socket.connect_to_url(ws_url)

func disconnect_from_server() -> void:
	socket.close()
	reset_state()
	net_log("Manual disconnect requested.")

func reset_state() -> void:
	is_connected_to_host = false
	my_id = ""
	current_room = ""
	is_host = false
	room_players = []
	players.clear()
	last_msg_id = 0
	pending_requests.clear()
	seed_received = false
	net_log("Network state reset.")

func auth(username: String) -> void:
	request("User.Auth", {"username": username, "password": ""})

func join_room(room_id: String) -> void:
	request("Room.Join", {"room_id": room_id})

func move(x: float, y: float, vx: float = 0.0, vy: float = 0.0, state: String = "idle", direction: String = "down") -> void:
	notify("Room.Move", {
		"x": x,
		"y": y,
		"vx": vx,
		"vy": vy,
		"state": state,
		"direction": direction,
		"tick": Time.get_ticks_msec()
	})

func start_game_request() -> void:
	request("Room.StartGame", {})

func toggle_ready() -> void:
	request("Room.Ready", {})

func leave_room() -> void:
	request("Room.Leave", {})
	current_room = ""
	is_host = false
	room_players = []
	players.clear()

func request_room_list() -> void:
	request("Room.List", {})

func send_data(data: Dictionary) -> void:
	var type = data.get("type", "")
	match type:
		"LOGIN": auth(data.get("username", "Player"))
		"CREATE_ROOM": request("Room.Create", data)
		"JOIN": join_room(data.get("room_id", ""))
		"MOVE": move(
			data.get("x", 0.0),
			data.get("y", 0.0),
			data.get("vx", 0.0),
			data.get("vy", 0.0),
			data.get("state", "idle"),
			data.get("direction", "down")
		)
		"BOMB": request("Room.PlaceBomb", data)
		"evacuate": request("Room.Evacuate", {})
		"OPEN_CHEST": request("Room.OpenChest", data)
		"PICKUP": request("Room.Pickup", data)
		"DIE": request("Room.Die", {})
		"RETURN_TO_ROOM": request("Room.Return", {})
		"SETTLEMENT": request("Room.Settlement", data)

func push_backpack_config(_uid: String, config: Array) -> void:
	request("User.SaveBackpack", {"config": config})

func push_inventory_config(inventory: Array[String], coins: int) -> void:
	request("User.SaveInventory", {"inventory": inventory, "coins": coins})

func push_presets(presets: Array) -> void:
	request("User.SavePresets", {"presets": presets})

func fetch_profile() -> void:
	request("User.GetProfile", {})
