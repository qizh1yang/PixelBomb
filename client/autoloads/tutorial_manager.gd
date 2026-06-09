extends Node

const CONFIG_PATH = "user://tutorial_state.cfg"
var _config: ConfigFile = ConfigFile.new()
var _active_toasts: Dictionary = {}

# ── [NEW] 新手教程测试强制标记 ──
var force_tutorial: bool = false
var _session_shown: Dictionary = {}

func _ready() -> void:
	_config.load(CONFIG_PATH)

func show_tutorial(tutorial_id: String, text: String, duration: float = 2.0, image_path: String = "", y_offset: float = 0.0) -> void:
	if force_tutorial:
		# 强制教程模式：如果在当前会话（对局）里已经显示过，则跳过
		if _session_shown.has(tutorial_id):
			return
	else:
		# 核心：如果是二次及以上老玩家，完全屏蔽新手引导提示！
		if is_instance_valid(GlobalPlayerData) and not GlobalPlayerData.is_first_game:
			return

		if _config.get_value("tutorials", tutorial_id, false):
			return # 已经显示过了
		
	# 如果已经是活跃的，避免重复实例化
	if _active_toasts.has(tutorial_id) and is_instance_valid(_active_toasts[tutorial_id]):
		return
	
	# 标记为已显示并保存
	if force_tutorial:
		_session_shown[tutorial_id] = true
	else:
		_config.set_value("tutorials", tutorial_id, true)
		_config.save(CONFIG_PATH)
	
	# 显示 Toast UI
	var toast_scene = load("res://ui/tutorial/tutorial_toast.tscn")
	if toast_scene:
		var toast = toast_scene.instantiate()
		if toast.has_method("setup"):
			toast.setup(text, duration, image_path, y_offset)
			
		# 核心：添加到当前主场景，确保其随场景销毁自动释放
		var target_parent = get_tree().current_scene
		if is_instance_valid(target_parent):
			target_parent.add_child(toast)
		else:
			get_tree().root.add_child(toast)
		
		# 追踪需要手动关闭的 toast
		if duration <= 0:
			_active_toasts[tutorial_id] = toast

func hide_tutorial(tutorial_id: String) -> void:
	if _active_toasts.has(tutorial_id):
		var toast = _active_toasts[tutorial_id]
		if is_instance_valid(toast) and toast.has_method("dismiss"):
			toast.dismiss()
		_active_toasts.erase(tutorial_id)

func clear_all_tutorials() -> void:
	for id in _active_toasts.keys():
		var toast = _active_toasts[id]
		if is_instance_valid(toast):
			toast.queue_free()
	_active_toasts.clear()
	_session_shown.clear()
