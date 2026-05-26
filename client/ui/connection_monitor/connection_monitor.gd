# connection_monitor.gd - 全局断线监控与状态还原 UI 面板
# 监听网络重连状态机，驱动全屏阻断遮罩显隐与 InputManager 键盘物理拦截锁
extends CanvasLayer

@onready var fullScreenMask: ColorRect = $FullScreenMask
@onready var statusPanel: Panel = $FullScreenMask/StatusPanel
@onready var statusText: Label = $FullScreenMask/StatusPanel/Label
@onready var reconnectBtn: Button = $FullScreenMask/StatusPanel/ReconnectBtn

var net: Node = null

func _ready() -> void:
	net = get_node_or_null("/root/NetworkManager")
	if net:
		net.connection_closed.connect(_onDisconnected)
		net.connected_to_server.connect(_onConnected)
		if net.has_signal("recovery_state_changed"):
			net.recovery_state_changed.connect(_on_recovery_state_changed)
	
	if reconnectBtn:
		reconnectBtn.pressed.connect(_on_reconnect_pressed)
		
	fullScreenMask.visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		# 当游戏切回前台 (获得焦点)
		# 强制实施 User 登录拦截：没有通过认证前，绝对不弹窗扰民
		var user = get_node_or_null("/root/User")
		if not user or not user.call("is_authenticated"):
			return
			
		if net and net.connection_state == net.ConnectionState.RECONNECTING:
			fullScreenMask.visible = true
			var input_mgr = get_node_or_null("/root/InputManager")
			if input_mgr:
				input_mgr.block_game_input = true
				
			statusText.text = "游戏曾退入后台，连接已自动断开。"
			if reconnectBtn:
				reconnectBtn.disabled = false
				reconnectBtn.text = "重新连接"

# 断开连接时显示重连提示
func _onDisconnected() -> void:
	# 强制实施 User 登录拦截：没有通过认证前，绝对不触发异常断网弹窗
	var user = get_node_or_null("/root/User")
	if not user or not user.call("is_authenticated"):
		return
		
	fullScreenMask.visible = true
	var input_mgr = get_node_or_null("/root/InputManager")
	if input_mgr:
		input_mgr.block_game_input = true
		
	if net and net.connection_state == net.ConnectionState.RECONNECTING:
		statusText.text = "网络连接丢失，请点击下方按钮重新连接。"
	else:
		statusText.text = "连接已断开，重新连接请点击下方按钮。"
	
	if reconnectBtn:
		reconnectBtn.disabled = false
		reconnectBtn.text = "重新连接"

# 物理连接重新握手成功时隐藏提示 (如果是非对局/非异常丢包)
func _onConnected() -> void:
	# 如果还没有开始 SessionRecovery 或者是普通的认证前连接成功
	if net and net.has_method("get_recovery_state") and net.recovery_state == net.ConnectionRecoveryState.NORMAL:
		fullScreenMask.visible = false
		var input_mgr = get_node_or_null("/root/InputManager")
		if input_mgr:
			input_mgr.block_game_input = false

# 重新连接按钮回调
func _on_reconnect_pressed() -> void:
	if not net:
		return
		
	# 如果当前重连状态为 FAILED，此按钮行为转为：点击返回登录界面
	if net.has_method("get_recovery_state") and net.recovery_state == net.ConnectionRecoveryState.FAILED:
		# 强制卸载事件阻断并退回登录场景
		var input_mgr = get_node_or_null("/root/InputManager")
		if input_mgr:
			input_mgr.block_game_input = false
		net.disconnect_from_server()
		fullScreenMask.visible = false
		UIManager.change_scene("login")
		return
		
	reconnectBtn.disabled = true
	reconnectBtn.text = "正在连接..."
	statusText.text = "正在与服务器重新建立通信通道..."
	
	# 切为 RESUMING 状态，进行网络连线恢复
	net.connection_state = net.ConnectionState.RESUMING
	net.connect_to_server()

# ── 状态机信号槽回调 ──
func _on_recovery_state_changed(new_state: int) -> void:
	# 强制实施 User 登录拦截，确保只有认证成功的会话享受状态重置服务
	var user = get_node_or_null("/root/User")
	if not user or not user.call("is_authenticated"):
		return
		
	var input_mgr = get_node_or_null("/root/InputManager")
	
	match new_state:
		net.ConnectionRecoveryState.NORMAL:
			fullScreenMask.visible = false
			if input_mgr:
				input_mgr.block_game_input = false
				
		net.ConnectionRecoveryState.LOST:
			fullScreenMask.visible = true
			if input_mgr:
				input_mgr.block_game_input = true
			statusText.text = "连接已中断，正在尝试启动自动重连..."
			if reconnectBtn:
				reconnectBtn.disabled = false
				reconnectBtn.text = "手动重连"
				
		net.ConnectionRecoveryState.RECONNECTING:
			fullScreenMask.visible = true
			if input_mgr:
				input_mgr.block_game_input = true
			statusText.text = "网络连接丢失，正在与事务所重新建立连接..."
			if reconnectBtn:
				reconnectBtn.disabled = true
				reconnectBtn.text = "正在重连..."
				
		net.ConnectionRecoveryState.REAUTHENTICATING:
			fullScreenMask.visible = true
			if input_mgr:
				input_mgr.block_game_input = true
			statusText.text = "物理通道建立成功，正在恢复玩家身份凭证..."
			if reconnectBtn:
				reconnectBtn.disabled = true
				reconnectBtn.text = "验证身份..."
				
		net.ConnectionRecoveryState.RESYNCING:
			fullScreenMask.visible = true
			if input_mgr:
				input_mgr.block_game_input = true
			statusText.text = "身份验证成功，正在从服务器重新拉取装备与任务列表..."
			if reconnectBtn:
				reconnectBtn.disabled = true
				reconnectBtn.text = "同步数据..."
				
		net.ConnectionRecoveryState.FAILED:
			fullScreenMask.visible = true
			if input_mgr:
				input_mgr.block_game_input = true
			statusText.text = "重连超时或身份已过期，连接已彻底断开。"
			if reconnectBtn:
				reconnectBtn.disabled = false
				reconnectBtn.text = "返回登录"
