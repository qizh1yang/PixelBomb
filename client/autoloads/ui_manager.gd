extends Node

signal scene_changed(scene_name: String)

var current_scene_name: String = ""
var _global_theme: Theme = null

# 场景路径注册表
var scenes = {
	"login": "res://scenes/Login/login.tscn",
	"lobby": "res://scenes/Lobby/lobby.tscn",
	"warehouse": "res://scenes/Warehouse/warehouse.tscn",
	"backpack_config": "res://scenes/Warehouse/backpack_config.tscn",
	"room": "res://scenes/Room/room.tscn",
	"game": "res://stages/game_stage.tscn"
}

func _ready() -> void:
	_setup_global_font()
	
	# 连接节点进入场景树的信号，实现对所有根 Control 节点的全自动主题拦截与强行注入
	get_tree().node_added.connect(_on_node_added)
	
	# 手动对已经存在的初始场景和常驻节点应用一次全局主题
	_apply_theme_to_existing_roots()
	
	# 记录初始场景
	var root = get_tree().root
	current_scene_name = root.get_child(root.get_child_count() - 1).name

func _setup_global_font() -> void:
	var font_path = "res://assets/fonts/lmm.ttf"
	if ResourceLoader.exists(font_path):
		var custom_font = load(font_path)
		if custom_font is Font:
			# 1. 动态生成一个配置了元气字体的全局 Theme 主题对象
			_global_theme = Theme.new()
			_global_theme.default_font = custom_font
			
			# 2. 设置底层 fallback_font 作为双重稳健兜底
			ThemeDB.fallback_font = custom_font
			print("[FONT] Global Theme created and fallback_font set directly to custom font: %s" % font_path)
			return
			
	push_warning("[FONT] Custom font not found at: %s, falling back to SystemFont" % font_path)
	var system_font = SystemFont.new()
	system_font.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Segoe UI", "Arial", "sans-serif"])
	ThemeDB.fallback_font = system_font
	print("[FONT] Global fallback theme default font dynamically set to SystemFont")

func _on_node_added(node: Node) -> void:
	if _global_theme == null:
		return
		
	if node is Control:
		# 极度精妙的设计：如果该 Control 没有 Control 类型的父节点，说明它是一个独立或场景的根 Control 节点
		# 我们给它赋上包含中文字体的全局 Theme，它的所有子孙节点（Label/Button等）都将无条件继承并刷新为该字体！
		var parent = node.get_parent()
		if parent == null or not parent is Control:
			node.theme = _global_theme

func _apply_theme_to_existing_roots() -> void:
	if _global_theme == null:
		return
	# 扫描目前已经在场景树中的所有节点，对存在的根 Control 节点补上全局 Theme 绑定
	_apply_theme_recursive(get_tree().root)

func _apply_theme_recursive(node: Node) -> void:
	if node is Control:
		var parent = node.get_parent()
		if parent == null or not parent is Control:
			node.theme = _global_theme
			return # 已经对根 Control 应用了 Theme，不需要再深层遍历，子孙节点会自动继承
			
	for child in node.get_children():
		_apply_theme_recursive(child)

# 切换场景 (带转场效果预留)
func change_scene(scene_id: String) -> void:
	if not scenes.has(scene_id):
		push_error("Scene ID not found: " + scene_id)
		return
		
	print("[UIManager] Switching to scene: ", scene_id)
	get_tree().change_scene_to_file(scenes[scene_id])
	current_scene_name = scene_id
	scene_changed.emit(scene_id)

# 弹出通用提示框 (简易版)
func show_message(title: String, message: String) -> void:
	# 这里可以实例化一个通用的 Modal 场景
	print("[UI_MESSAGE] %s: %s" % [title, message])

# 弹出结算面板 (由 GameMode 调用)
func show_settlement(is_winner: bool, winner_name: String) -> void:
	var result_scene = load("res://ui/result_panel/result_panel.tscn")
	if result_scene:
		var inst = result_scene.instantiate()
		get_tree().root.add_child(inst)
		if inst.has_method("setup"):
			inst.setup(is_winner)
