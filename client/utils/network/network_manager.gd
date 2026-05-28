extends Node

# Nano 协议常量
enum PacketType { HANDSHAKE = 1, HANDSHAKE_ACK = 2, HEARTBEAT = 3, DATA = 4, KICK = 5 }
enum MsgType { REQUEST = 0, NOTIFY = 1, RESPONSE = 2, PUSH = 3 }

# ── [NEW] 连接状态机 ──
enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	RECONNECTING,
	RESYNCING, # 废弃旧用，统合在 ConnectionRecoveryState 中
	RESUMING,
	FAILED
}
var connection_state: int = ConnectionState.DISCONNECTED

# ── [NEW] 全局重连恢复状态机与属性监听 ──
enum ConnectionRecoveryState {
	NORMAL,
	LOST,
	RECONNECTING,
	REAUTHENTICATING,
	RESYNCING,
	FAILED
}
var recovery_state: int = ConnectionRecoveryState.NORMAL:
	set(val):
		if recovery_state != val:
			recovery_state = val
			recovery_state_changed.emit(recovery_state)

signal recovery_state_changed(new_state: int)

func get_recovery_state() -> int:
	return recovery_state

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
signal game_state_resumed(snapshot: Dictionary) # [NEW] 墓碑恢复成功，广播权威快照

var socket := WebSocketPeer.new()
var http_client: HTTPRequest = null

var server_base_url := "http://127.0.0.1:8080"
var ws_url := "ws://127.0.0.1:8080/ws"


func _detect_urls() -> void:
	if OS.has_feature("web"):
		var host = JavaScriptBridge.eval("window.location.host", true)
		var protocol = JavaScriptBridge.eval("window.location.protocol", true)
		var ws_protocol = "wss://" if protocol == "https:" else "ws://"
		var http_protocol = "https://" if protocol == "https:" else "http://"
		server_base_url = http_protocol + host
		ws_url = ws_protocol + host + "/ws"
		net_log("Web detected, server_base_url: %s, ws_url: %s" % [server_base_url, ws_url])

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

# ── [MAP CONFIG] Host 权威地图配置 (RoomSyncInfo 解析) ──
var current_map_type: String = "CLASSIC"  # "CLASSIC" | "WINTER" | "PROCEDURAL"
var current_shape_type: String = "circle" # "circle" | "hexagon" | "star" | "ring" | "cave"
var current_map_size: String = "small"    # "small" | "medium" | "large"
var host_uid: int = 0                      # 当前房主的 UID

# 消息序列号与路由映射 (用于处理 Response)
var last_msg_id: int = 0
var pending_requests: Dictionary = {} # ID -> Route

# ── [NEW] 断线重连与心跳配置 ──
var reconnect_controller: Node = null
var last_ack_seq: int = 0
var last_send_heartbeat_time: float = 0.0
var last_recv_packet_time: float = 0.0

const RESUME_FILE = "user://resume_session.json"

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
	_detect_urls()
	http_client = HTTPRequest.new()
	add_child(http_client)
	
	# [NEW] 实例化重连控制器并挂载
	var ReconnectControllerScript = load("res://utils/network/reconnect_controller.gd")
	reconnect_controller = Node.new()
	reconnect_controller.set_script(ReconnectControllerScript)
	reconnect_controller.name = "ReconnectController"
	add_child(reconnect_controller)
	
	# 连接重连控制器信号
	reconnect_controller.attempt_failed.connect(_on_reconnect_attempt_failed)
	reconnect_controller.reconnect_failed.connect(_on_reconnect_failed)
	
	# [NEW] 实例化 SessionRecovery 控制器并挂载
	var SessionRecoveryScript = load("res://utils/network/session_recovery.gd")
	var session_recovery = Node.new()
	session_recovery.set_script(SessionRecoveryScript)
	session_recovery.name = "SessionRecovery"
	add_child(session_recovery)
	
	# 连接 SessionRecovery 信号
	session_recovery.recovery_complete.connect(_on_session_recovery_complete)
	session_recovery.recovery_failed.connect(_on_session_recovery_failed)
	
	net_log("Nano NetworkManager ready.")

func _notification(what: int) -> void:
	# Graceful shutdown: send Room.Leave before closing to avoid creating
	# a tombstone on the server for a normal client exit.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		net_log("Window close requested — sending graceful Room.Leave...")
		if current_room != "" and is_connected_to_host:
			notify("Room.Leave", {})
			OS.delay_msec(100)
		socket.close()
		return

	# 桌面端（Windows/macOS/Linux）在失焦时不断开连接，保持后台运行保活。
	# 仅在非桌面平台（如 Web/Mobile，其浏览器或系统有挂起JS限频机制）下，才在失去焦点时主动物理断开以保护 session。
	var is_mobile_or_web = OS.has_feature("mobile") or OS.has_feature("web")

	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if is_mobile_or_web:
			net_log("Application focus out (backgrounded). Actively pausing connection to protect session.")
			if connection_state == ConnectionState.CONNECTED or connection_state == ConnectionState.RESUMING:
				connection_state = ConnectionState.RECONNECTING
				socket.close() # 主动断开套接字
				is_connected_to_host = false
				if reconnect_controller:
					reconnect_controller.stop_reconnecting() # 暂停自动重连
				connection_closed.emit()
		else:
			net_log("Application focus out. (Desktop platform, keeping connection active)")
			
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if is_mobile_or_web:
			net_log("Application focus in (resumed). Re-activating reconnect controller if disconnected...")
			if connection_state == ConnectionState.RECONNECTING:
				if reconnect_controller:
					reconnect_controller.start_reconnecting()
		else:
			# 桌面端：如果网络由于其他原因（如长时间挂机或网络抖动）在失焦期间断开，切回前台时立刻唤醒重连机制
			net_log("Application focus in. Checking connection stability...")
			var state = socket.get_ready_state()
			if state == WebSocketPeer.STATE_CLOSED or connection_state == ConnectionState.DISCONNECTED:
				if not load_resume_session().is_empty():
					net_log("Connection was lost. Refocus triggers instant reconnect.")
					connection_state = ConnectionState.RECONNECTING
					if reconnect_controller:
						reconnect_controller.start_reconnecting()
					else:
						connect_to_server()

func _process(_delta: float) -> void:
	socket.poll()
	var state = socket.get_ready_state()
	var current_time = Time.get_ticks_msec() / 1000.0
	
	if state == WebSocketPeer.STATE_OPEN:
		# 1. 首次建连握手转换
		if connection_state == ConnectionState.CONNECTING:
			connection_state = ConnectionState.CONNECTED
			is_connected_to_host = true
			_send_handshake()
			last_recv_packet_time = current_time
		
		# 2. 如果是从 RECONNECTING 重新建连成功，切为 RESUMING 状态，完成 Handshake
		elif connection_state == ConnectionState.RECONNECTING:
			connection_state = ConnectionState.RESUMING
			is_connected_to_host = true
			_send_handshake()
			reconnect_controller.stop_reconnecting()
			last_recv_packet_time = current_time
		
		# 3. 消费所有的底层数据包
		while socket.get_available_packet_count():
			var packet = socket.get_packet()
			last_recv_packet_time = current_time # 每次收包重置 15s 丢包计时器
			_handle_nano_packet(packet)
			
		# 4. 客户端权威心跳丢包判定 (丢包检测调整为 30.0 秒，容忍网络抖动，与服务端 5 秒心跳保活完美匹配)
		if current_time - last_recv_packet_time > 30.0:
			net_warn("No heartbeat responses from server for 30s. Disconnecting to trigger seamless reconnect...")
			socket.close() # 物理关闭以触发下方的 STATE_CLOSED
	
	elif state == WebSocketPeer.STATE_CLOSED:
		is_connected_to_host = false
		
		# 正常对局进行中突发断线，不重置状态，切换到 RECONNECTING 并开启指数退避重试
		if connection_state == ConnectionState.CONNECTED or connection_state == ConnectionState.RESUMING:
			connection_state = ConnectionState.RECONNECTING
			recovery_state = ConnectionRecoveryState.LOST # [NEW] 状态机同步切为 LOST
			net_warn("Socket connection lost! Initiating seamless reconnect backoff sequence...")
			reconnect_controller.start_reconnecting()
			connection_closed.emit()
		
		# 已经是重连过程中，且某次连接尝试失败回落到 CLOSED 时
		elif connection_state == ConnectionState.RECONNECTING:
			reconnect_controller.schedule_next()
			
		# 手动断开或失败时置为 DISCONNECTED
		else:
			if connection_state != ConnectionState.FAILED:
				connection_state = ConnectionState.DISCONNECTED

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
			
			# 物理通道与协议重连成功，将控制权交给 SessionRecovery 进行深层 Session 业务验证恢复
			if connection_state == ConnectionState.RESUMING:
				var recovery = get_node_or_null("SessionRecovery")
				if recovery:
					# 延迟 0.05s 发起，保证服务端的 HANDSHAKE 完全解析
					get_tree().create_timer(0.05).timeout.connect(func():
						recovery.call("start_recovery_sequence")
					)
		PacketType.HEARTBEAT:
			# 服务端心跳响应回复
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
	
	# [NEW] 记录收到的最新包自增 seq (用于丢包恢复，支持防御性过滤)
	if body is Dictionary and body.has("seq"):
		last_ack_seq = int(body.seq)
	
	if route != "":
		net_log("Route: " + route + " Msg: " + body_str)
		_dispatch_route_message(route, body)

func _dispatch_route_message(route: String, body: Variant) -> void:
	match route:
		"User.Auth":
			my_id = clean_id(body.get("id", ""))
			player_name = body.get("name", "")
			
			# 同步至全局唯一 User 会话单例中，完成登录状态认证
			var user_node = get_node_or_null("/root/User")
			if user_node:
				user_node.call("set_authenticated_user", body)
				
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
			
			# [NEW] 预生成的 resume_token 与 player_id 本地持久化缓存
			var p_id = body.get("player_id", "")
			var r_token = body.get("resume_token", "")
			if p_id != "" and r_token != "":
				save_resume_session(p_id, current_room, r_token)
				
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
			# [NEW] 支持新版 RoomSyncInfo 格式（含 host_uid 和地图配置）
			# 同时兼容旧版纯 Array 格式，确保向下兼容
			if body is Dictionary and body.has("host_uid"):
				# ── 新版 RoomSyncInfo 协议解析 ──
				room_players = body.get("players", [])
				if room_players == null: room_players = []
				
				# [MAP CONFIG] 提取并更新地图配置
				var new_map_type: String = str(body.get("map_type", "CLASSIC"))
				var new_shape: String = str(body.get("shape_type", "circle"))
				var new_size: String = str(body.get("map_size", "small"))
				var new_seed: int = int(body.get("seed", 0))
				var new_host_uid: int = int(body.get("host_uid", 0))
				net_log("[MAP-SYNC] onRoomUpdate: type=%s shape=%s size=%s seed=%d host=%d" % [new_map_type, new_shape, new_size, new_seed, new_host_uid])
				
				# [ROOM MAP VALIDATOR] 不合法的配置降级到安全默认值
				var valid_map_types = ["CLASSIC", "WINTER", "PROCEDURAL"]
				var valid_shapes = ["circle", "hexagon", "star", "ring", "cave"]
				var valid_sizes = ["small", "medium", "large"]
				if not new_map_type in valid_map_types: new_map_type = "CLASSIC"
				if not new_shape in valid_shapes: new_shape = "circle"
				if not new_size in valid_sizes: new_size = "small"
				
				current_map_type = new_map_type
				current_shape_type = new_shape
				current_map_size = new_size
				if new_seed != 0: map_seed = new_seed
				host_uid = new_host_uid
				
				# [HOST AUTHORITY] 动态计算并更新 is_host 状态
				var was_host = is_host
				is_host = (my_id != "" and clean_id(my_id) == str(new_host_uid))
				
				# 重建 players 字典
				players.clear()
				for p in room_players:
					players[clean_id(p.id)] = p
				
				# 发出房间状态广播信号
				room_state_updated.emit(room_players)
				
				# 若 is_host 状态发生变化，发出 host_updated 信号驱动 UI 刷新权限
				if is_host != was_host:
					host_updated.emit(is_host, str(new_host_uid))
					net_log("Host status changed: is_host=%s, host_uid=%d" % [str(is_host), new_host_uid])
			else:
				# ── 旧版 Array 格式屟容 ──
				room_players = body if body is Array else []
				players.clear()
				for p in room_players:
					players[clean_id(p.id)] = p
				room_state_updated.emit(room_players)
		
		# [NEW] 重连恢复响应
		"Room.Resume":
			if body.get("success") == false:
				var err_msg = body.get("error", "Tombstone expired")
				net_warn("Room.Resume failed: " + err_msg)
				_on_reconnect_failed()
				return
			
			net_log("Room.Resume succeeded! Dynamic Catchup Triggered.")
			
			# 切回连接态，恢复房间数据
			connection_state = ConnectionState.CONNECTED
			is_connected_to_host = true
			current_room = body.get("room_id", "")
			map_seed = int(body.get("seed", 0))
			seed_received = true
			
			# 执行快照还原
			var snapshot = body.get("snapshot", {})
			var missed_events = body.get("missed_events", [])
			apply_snapshot(snapshot)
			replay_events(missed_events)
			
			room_joined.emit(map_seed)
	
	message_received.emit(route, body)

# ── 发送接口 ──

func request(route: String, data: Dictionary) -> void:
	_send_msg(MsgType.REQUEST, route, data)

func notify(route: String, data: Dictionary) -> void:
	_send_msg(MsgType.NOTIFY, route, data)

func _send_msg(type: int, route: String, data: Dictionary) -> void:
	# 让 last_msg_id 在 [1, 127] 之间循环自增并回绕，保证请求端与接收端对齐
	last_msg_id = (last_msg_id + 1) & 0x7F
	if last_msg_id == 0:
		last_msg_id = 1
		
	var body_str = JSON.stringify(data)
	var body_bytes = body_str.to_utf8_buffer()
	
	var msg = PackedByteArray()
	msg.append(type << 1)
	
	if type == MsgType.REQUEST or type == MsgType.RESPONSE:
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

# ── [NEW] 重连网络逻辑与快照追赶 ──

# 执行 Room.Resume RPC 请求
func _send_resume_rpc() -> void:
	var session_data = load_resume_session()
	var token = session_data.get("resume_token", "")
	if token == "":
		net_warn("No resume token found. Reconnection aborted.")
		_on_reconnect_failed()
		return
		
	net_log("Sending Room.Resume RPC with token: " + token)
	request("Room.Resume", {
		"resume_token": token,
		"last_ack_seq": last_ack_seq
	})

# 还原服务端局内 authoritative 快照到局内玩家状态中
func apply_snapshot(snapshot: Dictionary) -> void:
	net_log("Applying authoritative GameState snapshot: " + JSON.stringify(snapshot))
	
	# 刷新 player 字典与 room_players 信息
	var snap_players = snapshot.get("players", {})
	room_players.clear()
	players.clear()
	
	for pid in snap_players.keys():
		var p_state = snap_players[pid]
		var nano_player = {
			"id": int(pid) if pid.is_valid_int() else 0,
			"name": p_state.get("name", "UnknownPlayer"),
			"ready": true,
			"char": 0
		}
		room_players.append(nano_player)
		players[clean_id(pid)] = nano_player
		
	room_state_updated.emit(room_players)
	
	# 广播最核心的快照数据，促使游戏局内重新渲染对局
	game_state_resumed.emit(snapshot)

# 补发丢失的对局微小事件 (回放包)
func replay_events(_events: Array) -> void:
	net_log("Replaying missed events, count: " + str(_events.size()))

# ReconnectController 信号绑定：单次尝试重连失败
func _on_reconnect_attempt_failed(attempt: int, next_delay: float) -> void:
	net_log("Seamless reconnect attempt #%d failed. Scheduled next try in %.1fs" % [attempt, next_delay])
	recovery_state = ConnectionRecoveryState.RECONNECTING # [NEW] 状态机同步切为 RECONNECTING

# ReconnectController 信号绑定：重连总重试彻底失败
func _on_reconnect_failed() -> void:
	net_warn("All reconnect attempts failed or token expired. Clearing session.")
	reconnect_controller.stop_reconnecting()
	connection_state = ConnectionState.FAILED
	recovery_state = ConnectionRecoveryState.FAILED # [NEW] 状态机同步切为 FAILED
	reset_state()
	connection_closed.emit()

# [NEW] SessionRecovery 信号绑定：成功恢复完毕
func _on_session_recovery_complete() -> void:
	net_log("NetworkManager: Session recovery pipeline completed successfully.")
	# 状态机已由 SessionRecovery 自动切回 NORMAL，触发 UI 释放

# [NEW] SessionRecovery 信号绑定：恢复中发生致命业务错误彻底失败
func _on_session_recovery_failed(error_msg: String) -> void:
	net_warn("NetworkManager: Session recovery pipeline failed: " + error_msg)
	_on_reconnect_failed()

# ── [NEW] Session 持久化本地工具 ──

func save_resume_session(player_id: String, room_id: String, token: String) -> void:
	var data = {
		"player_id": player_id,
		"room_id": room_id,
		"resume_token": token,
		"saved_at": Time.get_unix_time_from_system()
	}
	var file = FileAccess.open(RESUME_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		net_log("Saved resume session to local file successfully.")

func load_resume_session() -> Dictionary:
	if not FileAccess.file_exists(RESUME_FILE):
		return {}
	var file = FileAccess.open(RESUME_FILE, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		var data = JSON.parse_string(content)
		if data is Dictionary:
			return data
	return {}

func clear_resume_session() -> void:
	if FileAccess.file_exists(RESUME_FILE):
		DirAccess.remove_absolute(RESUME_FILE)
		net_log("Cleared local resume session.")

# ── 业务接口 ──

func connect_to_server() -> void:
	if connection_state != ConnectionState.RECONNECTING:
		connection_state = ConnectionState.CONNECTING
	
	# 重置并重新创建新的套接字，清除旧的物理连接脏状态，解决 STATE_CLOSED 连不上问题
	socket = WebSocketPeer.new()
	var err = socket.connect_to_url(ws_url)
	if err != OK:
		net_warn("Failed to initiate connect_to_url, error code: " + str(err))

func disconnect_from_server() -> void:
	socket.close()
	reset_state()
	net_log("Manual disconnect requested.")

func reset_state() -> void:
	connection_state = ConnectionState.DISCONNECTED
	recovery_state = ConnectionRecoveryState.NORMAL # [NEW] 复位重连状态
	is_connected_to_host = false
	my_id = ""
	current_room = ""
	is_host = false
	room_players = []
	players.clear()
	last_msg_id = 0
	pending_requests.clear()
	seed_received = false
	clear_resume_session()
	
	# [NEW] 重置全局 User 会话凭据单例，彻底切断会话
	var user_node = get_node_or_null("/root/User")
	if user_node:
		user_node.call("clear")
		
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

# [HOST AUTHORITY] Host 修改地图配置时调用，向服务端发起 Room.UpdateMapConfig 请求
# 服务端会进行 HostUID 校验，只有真正的房主请求才会被接受
func update_map_config(map_type: String = "", shape_type: String = "", map_size: String = "", seed: int = 0) -> void:
	if not is_host:
		net_warn("update_map_config called but is_host=false. Blocked client-side.")
		return
	var payload: Dictionary = {}
	if map_type != "": payload["map_type"] = map_type
	if shape_type != "": payload["shape_type"] = shape_type
	if map_size != "": payload["map_size"] = map_size
	if seed != 0: payload["seed"] = seed
	if payload.is_empty(): return
	request("Room.UpdateMapConfig", payload)
	net_log("Host sent UpdateMapConfig: %s" % str(payload))
