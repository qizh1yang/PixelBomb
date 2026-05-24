# 独立鼠标监控器 - 用于底层输入分析
extends Node

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# 每隔一定帧数输出，避免日志洪水
		if Engine.get_frames_drawn() % 15 == 0:
			print("[鼠标底层] 移动 | 全局位置:%s" % event.global_position)
			
	elif event is InputEventMouseButton:
		var action = "按下" if event.pressed else "抬起"
		var button = "左键" if event.button_index == MOUSE_BUTTON_LEFT else "右键"
		print("[鼠标底层] 点击 | 动作:%s | 按键:%s | 位置:%s" % [action, button, event.global_position])
