# 断线监控 UI 模块
# 监听 NetworkManager 连接状态，显示或隐藏断线提示面板
# 创建时间：2026-05-08

extends CanvasLayer

# 注意：不使用 class_name，避免与 Autoload 单例名称冲突
# 单例可通过 /root/ConnectionMonitor 访问

# ── 节点引用 ──
@onready var statusPanel: Panel = $StatusPanel
@onready var statusText: Label = $StatusPanel/Label

func _ready() -> void:
	var net: Node = get_node("/root/NetworkManager")
	net.connection_closed.connect(_onDisconnected)
	net.connected_to_server.connect(_onConnected)
	statusPanel.visible = false

# 断开连接时显示重连提示
func _onDisconnected() -> void:
	statusPanel.visible = true
	statusText.text = "连接断开，正在尝试重连..."

# 连接成功时隐藏提示
func _onConnected() -> void:
	statusPanel.visible = false
