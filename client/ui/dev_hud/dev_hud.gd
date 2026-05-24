# 开发调试 HUD 覆盖层
# 按反引号键切换显示，展示 FPS、地图种子、网络状态等信息
# 创建时间：2026-05-08

extends CanvasLayer

# 注意：不使用 class_name，避免与 Autoload 单例名称冲突
# 单例可通过 /root/DevHUD 访问

# ── 节点引用 ──
@onready var panel: Panel = $Panel
@onready var fpsLabel: Label = $Panel/VBox/FPS
@onready var seedLabel: Label = $Panel/VBox/Seed
@onready var roomLabel: Label = $Panel/VBox/Room
@onready var playerLabel: Label = $Panel/VBox/Player
@onready var netStatusLabel: Label = $Panel/VBox/NetStatus
@onready var copySeedBtn: Button = $Panel/VBox/CopySeed

@onready var testTrigger: Button = %TestTrigger
@onready var testPanel: Control = %TestPanel
@onready var testButtonsContainer: VBoxContainer = %TestButtons
@onready var closeTestBtn: Button = $TestPanel/VBox/CloseTest

# ── 私有成员变量 ──
var _isVisible: bool = false

func _ready() -> void:
	panel.visible = false
	testPanel.visible = false
	copySeedBtn.pressed.connect(_copySeed)
	testTrigger.pressed.connect(_onTestTriggerPressed)
	closeTestBtn.pressed.connect(func(): testPanel.hide())

	# 优化开发者调试面板触发按钮，使其融入现代界面且语义清晰，避免玩家困惑
	if testTrigger:
		testTrigger.text = "🛠️ DEV"
		testTrigger.add_theme_font_size_override("font_size", 12)
		testTrigger.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.4)) # 设为 40% 半透明
		
		# 创建精致的微型极简半透明背景
		var dev_style = StyleBoxFlat.new()
		dev_style.bg_color = Color(0.0, 0.0, 0.0, 0.25) # 极淡深灰色背板
		dev_style.corner_radius_top_left = 4
		dev_style.corner_radius_top_right = 4
		dev_style.corner_radius_bottom_left = 4
		dev_style.corner_radius_bottom_right = 4
		dev_style.content_margin_left = 6
		dev_style.content_margin_right = 6
		dev_style.content_margin_top = 2
		dev_style.content_margin_bottom = 2
		
		testTrigger.add_theme_stylebox_override("normal", dev_style)
		testTrigger.add_theme_stylebox_override("hover", dev_style)
		testTrigger.add_theme_stylebox_override("pressed", dev_style)

func _onTestTriggerPressed() -> void:
	testPanel.visible = !testPanel.visible
	if testPanel.visible:
		_refreshTestButtons()

func _refreshTestButtons() -> void:
	# 清空旧按钮
	for child in testButtonsContainer.get_children():
		child.queue_free()
	
	var currentScene = get_tree().current_scene
	if not currentScene: return
	
	var scenePath = currentScene.scene_file_path
	
	# 根据场景添加不同测试按钮
	if scenePath.contains("login.tscn"):
		_addTestButton("跳过登录 (Mock)", _testSkipLogin)
	
	if scenePath.contains("lobby.tscn"):
		_addTestButton("强制进入房间", func(): 
			var net = get_node_or_null("/root/NetworkManager")
			if net: net.join_room("TEST_ROOM")
		)
		
	if scenePath.contains("game_stage.tscn"):
		_addTestButton("填充背包 (T)", func():
			var player = GameMode.get_local_player()
			if player and player.get_node_or_null("Backpack"):
				player.get_node("Backpack").show()
				player.get_node("Backpack").debugFill()
		)
		_addTestButton("自杀", func():
			var player = GameMode.get_local_player()
			if player and player.has_method("die"):
				player.die()
		)
		_addTestButton("强制激活撤离点", func():
			var gm = get_node_or_null("/root/GameMode")
			var net = get_node_or_null("/root/NetworkManager")
			print("[DEV] Clicked Force Evac Activate")
			if gm:
				gm._onNetworkMessage({"type": "evac_activated", "payload": {}}, net)
		)

func _addTestButton(text: String, callback: Callable) -> void:
	var btn = Button.new()
	btn.text = text
	btn.pressed.connect(callback)
	btn.pressed.connect(func(): testPanel.hide()) # 点击后自动关闭
	testButtonsContainer.add_child(btn)

# --- 特殊测试逻辑 ---

func _testSkipLogin() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net:
		net.mock_login_for_offline(12345678)
		get_tree().change_scene_to_file("res://scenes/Lobby/lobby.tscn")

func _process(_delta: float) -> void:
	if not _isVisible:
		return
	fpsLabel.text = "帧率: %d" % Engine.get_frames_per_second()

	var net = get_node_or_null("/root/NetworkManager")
	if net:
		seedLabel.text = "地图种子: %d" % net.map_seed
		roomLabel.text = "房间号: %s" % net.current_room
		playerLabel.text = "玩家: %s (序号 %d)" % [net.player_name, net.my_player_index]
		netStatusLabel.text = "网络状态: %s" % ("已连接" if net.is_connected_to_host else "未连接")
	else:
		seedLabel.text = "地图种子: N/A"
		roomLabel.text = "房间号: N/A"
		playerLabel.text = "玩家: N/A"
		netStatusLabel.text = "网络状态: 无网络管理器"

# 将地图种子复制到系统剪贴板
func _copySeed() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net:
		var seedText: String = str(net.map_seed)
		DisplayServer.clipboard_set(seedText)
		copySeedBtn.text = "已复制!"
		var timer: SceneTreeTimer = get_tree().create_timer(1.5)
		timer.timeout.connect(func(): copySeedBtn.text = "复制种子")
