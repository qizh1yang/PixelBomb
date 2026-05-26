# reconnect_controller.gd - 斐波那契指数退避重连控制器
# 挂载在 NetworkManager 下作为子节点，驱动网络断线自动重新连接

extends Node

# ── 信号 ──
signal attempt_failed(attempt_count: int, next_delay: float)
signal reconnect_failed()

# ── 常量与退避周期 ──
const MAX_ATTEMPTS: int = 8

# ── 状态变量 ──
var current_attempt: int = 0
var is_active: bool = false
var retry_timer: Timer = null
var net_manager: Node = null

# 二进制指数退避延迟变量
var retry_delay: float = 1.0

func _ready() -> void:
	net_manager = get_parent()
	
	# 创建单次定时器
	retry_timer = Timer.new()
	retry_timer.one_shot = true
	retry_timer.timeout.connect(_on_timer_timeout)
	add_child(retry_timer)
	
	if net_manager and net_manager.has_method("net_log"):
		net_manager.call("net_log", "ReconnectController initialized successfully.")

# 开始发起重连循环
func start_reconnecting() -> void:
	if is_active:
		return
	is_active = true
	current_attempt = 0
	retry_delay = 1.0 # 初始设置为 1.0s
	if net_manager and net_manager.has_method("net_log"):
		net_manager.call("net_log", "ReconnectController activated. Starting reconnect backoff loop...")
	_schedule_next_attempt()

# 停止重连循环
func stop_reconnecting() -> void:
	is_active = false
	current_attempt = 0
	retry_delay = 1.0 # 重置延迟
	if retry_timer:
		retry_timer.stop()
	if net_manager and net_manager.has_method("net_log"):
		net_manager.call("net_log", "ReconnectController stopped and reset.")

# 外部手动触发下一次尝试调度 (当某次握手或连线失败重新回落到 STATE_CLOSED 时)
func schedule_next() -> void:
	if not is_active:
		return
	_schedule_next_attempt()

# 调度下一次重连尝试
func _schedule_next_attempt() -> void:
	if not is_active:
		return
	
	if current_attempt >= MAX_ATTEMPTS:
		is_active = false
		if net_manager and net_manager.has_method("net_warn"):
			net_manager.call("net_warn", "Reconnect reached maximum attempts (%d). Giving up." % MAX_ATTEMPTS)
		reconnect_failed.emit()
		return
	
	var delay = retry_delay
	retry_delay = min(retry_delay * 2.0, 30.0) # 二进制倍增指数退避，最大限制为 30 秒
	current_attempt += 1
	
	if net_manager and net_manager.has_method("net_log"):
		net_manager.call("net_log", "Scheduling reconnect attempt #%d in %.1fs..." % [current_attempt, delay])
	
	retry_timer.start(delay)
	attempt_failed.emit(current_attempt, delay)

# 定时器溢出：发起物理连接
func _on_timer_timeout() -> void:
	if not is_active:
		return
	
	if net_manager and net_manager.has_method("net_log"):
		net_manager.call("net_log", "Executing reconnect attempt #%d now..." % current_attempt)
		
	# 发起底层套接字重连
	if net_manager and net_manager.has_method("connect_to_server"):
		net_manager.call("connect_to_server")
