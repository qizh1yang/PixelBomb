# input_manager.gd - 全局输入管理器
# 驱动全局物理锁屏，当网络丢失重连时在上游吞没一切键盘、Esc 和快捷键动作
extends Node

# 全局物理输入锁，开启时将全自动消费掉全部视口层级的输入事件，阻断穿透底层交互
var block_game_input: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if block_game_input:
		# 阻断性吞没：直接将该事件标记为已处理，切断 Godot 对该事件向下层 Control 或 _unhandled_input 的分发！
		get_viewport().set_input_as_handled()
