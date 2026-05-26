# session_recovery.gd - Session 深度业务还原协调器
# 挂载在 NetworkManager 下，驱动 reconnect -> re-auth -> reload snapshot -> resync inventory -> resync quest 串行流水线
extends Node

# 还原成功完成信号
signal recovery_complete()
# 还原遭遇致命错误彻底失败信号
signal recovery_failed(error_msg: String)

var net: Node = null

func _ready() -> void:
	net = get_parent()
	if net and net.has_method("net_log"):
		net.call("net_log", "SessionRecovery coordinator initialized successfully.")

## 启动六大步骤深度 Session 恢复流程
func start_recovery_sequence() -> void:
	if not net:
		emit_signal("recovery_failed", "NetworkManager parent reference missing")
		return
		
	net.call("net_log", "SessionRecovery: Starting sequential recovery pipeline...")
	
	# Step 1: Reconnect WebSocket (此时底层物理已建立并握手成功)
	# 状态切换为: 恢复玩家身份凭证
	net.recovery_state = net.ConnectionRecoveryState.REAUTHENTICATING
	net.call("net_log", "SessionRecovery [Step 1/5]: Socket open. Initiating Re-authentication...")
	
	_execute_re_auth()

# Step 2: 重新认证 (User.Auth)
func _execute_re_auth() -> void:
	var player_name = net.player_name
	if player_name == "" or player_name == "Player":
		# 如果本地连玩家名都没有，说明根本没登录过，直接失败
		_on_pipeline_failed("Player credentials missing in NetworkManager")
		return
		
	# 临时监听一次 Auth 回应信号
	var auth_listener = [null]
	auth_listener[0] = func(route: String, body: Dictionary):
		if route == "User.Auth":
			# 收到响应，注销监听器
			if net.message_received.is_connected(auth_listener[0]):
				net.message_received.disconnect(auth_listener[0])
				
			if body.has("id"):
				net.call("net_log", "SessionRecovery [Step 2/5]: Re-auth succeeded. Proceeding to reload profile...")
				# 状态切换为: 同步个人数据与状态
				net.recovery_state = net.ConnectionRecoveryState.RESYNCING
				_execute_reload_snapshot()
			else:
				_on_pipeline_failed("Re-auth response lacked valid User ID")
				
	net.message_received.connect(auth_listener[0])
	net.auth(player_name)

# Step 3: 拉取玩家快照与金币数据 (User.GetProfile)
func _execute_reload_snapshot() -> void:
	var profile_listener = [null]
	profile_listener[0] = func(route: String, body: Dictionary):
		if route == "User.GetProfile" or route == "User.Auth": # Nano Auth 返回体中通常也包含 data
			# 确保接收的是 GetProfile 或者是包含玩家初始数据的包
			if route == "User.GetProfile" or (route == "User.Auth" and body.has("data")):
				if net.message_received.is_connected(profile_listener[0]):
					net.message_received.disconnect(profile_listener[0])
				
				net.call("net_log", "SessionRecovery [Step 3/5]: Authoritative Player Profile loaded.")
				_execute_resync_inventory(body.get("data", body))
				
	net.message_received.connect(profile_listener[0])
	net.fetch_profile()

# Step 4: 同步仓库与背包缓存 (Stash/Inventory Sync)
func _execute_resync_inventory(profile_data: Dictionary) -> void:
	net.call("net_log", "SessionRecovery [Step 4/5]: Synced player inventory & coins.")
	# 解析并同步到 GlobalPlayerData
	if profile_data.has("coins"):
		GlobalPlayerData.coins = int(profile_data.get("coins", 0))
	if profile_data.has("inventory"):
		var inv = profile_data.get("inventory", [])
		var mapped_inv: Array[String] = []
		for item in inv: mapped_inv.append(str(item))
		GlobalPlayerData.owned_items = mapped_inv
	if profile_data.has("backpack_config"):
		GlobalPlayerData.backpack_config = profile_data.get("backpack_config", [])
	if profile_data.has("presets"):
		GlobalPlayerData.presets = profile_data.get("presets", [])
		
	# 广播同步完毕信号
	GlobalPlayerData.inventory_updated.emit()
	GlobalPlayerData.backpack_updated.emit()
	GlobalPlayerData.sync_completed.emit()
	
	_execute_resync_quest()

# Step 5: 同步任务与大厅/局内房间状态 (Quest / Lobby Room Sync)
func _execute_resync_quest() -> void:
	net.call("net_log", "SessionRecovery [Step 5/5]: Re-synchronizing room / lobby quest state...")
	
	# 如果此前已持久化了房间 Resume Token，说明是在局内发生物理断网，需要串行触发 Room.Resume
	var session_data = net.load_resume_session()
	var token = session_data.get("resume_token", "")
	var room_id = session_data.get("room_id", "")
	
	if token != "" and room_id != "" and net.current_room != "":
		# 触发对局快照追赶
		var resume_listener = [null]
		resume_listener[0] = func(route: String, body: Dictionary):
			if route == "Room.Resume":
				if net.message_received.is_connected(resume_listener[0]):
					net.message_received.disconnect(resume_listener[0])
				
				if body.get("success") == false:
					net.call("net_warn", "SessionRecovery: Room.Resume tombstone expired. Reverting to lobby.")
					net.current_room = ""
					net.clear_resume_session()
					_sync_lobby_only()
				else:
					net.call("net_log", "SessionRecovery: Match GameState fully caught up!")
					_on_pipeline_succeeded()
					
		net.message_received.connect(resume_listener[0])
		net._send_resume_rpc()
	else:
		_sync_lobby_only()

func _sync_lobby_only() -> void:
	# 大厅同步只需拉取一次房间列表并恢复正常即可
	var room_listener = [null]
	room_listener[0] = func(route: String, body: Dictionary):
		if route == "Room.List":
			if net.message_received.is_connected(room_listener[0]):
				net.message_received.disconnect(room_listener[0])
			
			net.call("net_log", "SessionRecovery: Lobby room list successfully synchronized.")
			_on_pipeline_succeeded()
			
	net.message_received.connect(room_listener[0])
	net.request_room_list()

func _on_pipeline_succeeded() -> void:
	net.call("net_log", "SessionRecovery Pipeline COMPLETE! Session restored successfully.")
	net.recovery_state = net.ConnectionRecoveryState.NORMAL
	emit_signal("recovery_complete")

func _on_pipeline_failed(reason: String) -> void:
	net.call("net_warn", "SessionRecovery Pipeline FAILED: " + reason)
	net.recovery_state = net.ConnectionRecoveryState.FAILED
	emit_signal("recovery_failed", reason)
