# 游戏场景容器
# 负责持有地图、相机、HUD；玩家生命周期由 GameMode 管理
# 创建时间：2026-05-08

extends Node2D

class_name GameStage

# ── 信号 ──
signal stageReady()

# ── 节点引用 ──
@onready var camera: Camera2D = $Camera2D
@onready var hudLayer: CanvasLayer = $HUD
@onready var background: CanvasLayer = $Background
@onready var transitionLayer: CanvasLayer = $TransitionLayer
@onready var countdownLabel: Label = $HUD/CountdownLabel

# ── 单例引用 ──
var gm: Node = null

# ── 私有成员变量 ──
var mapInstance: Node2D = null
var _lastDebugCell: Vector2i = Vector2i(-999, -999)

func _ready() -> void:
	gm = get_node_or_null("/root/GameMode")
	_playEntranceTransition()

	var is_standalone = (get_parent() == get_tree().root)
	
	if gm:
		if is_standalone and not gm.is_game_active:
			print("[STAGE] Standalone detected, loading default map...")
			gm.cleanup_game()
			gm.is_game_active = true
			gm.current_stage = gm.Stage.PLAYING
			gm.is_offline_mode = true
			var defaultMap: String = gm.get_selected_map_path()
			setupMap(defaultMap)
		elif not mapInstance:
			# 在正常网络流程中，如果进入场景时地图还没加载，则主动加载一次
			var defaultMap: String = gm.get_selected_map_path()
			setupMap(defaultMap)
		
		# 无论如何，同步引用
		gm.init_from_stage(self)
		
		# 监听结算信号
		if not gm.gameOverReceived.is_connected(_onGameOver):
			gm.gameOverReceived.connect(_onGameOver)
	else:
		if is_standalone:
			setupMap("res://prefabs/map/map_classic/map_classic.tscn")

	print("[STAGE] Game stage ready")
	stageReady.emit()

func _onGameOver(isSuccess: bool) -> void:
	print("[STAGE] 收到结算信号，显示结果面板: ", "成功" if isSuccess else "失败")
	var resultScene = load("res://ui/result_panel/result_panel.tscn")
	if resultScene:
		var resultInstance = resultScene.instantiate()
		add_child(resultInstance)
		resultInstance.setup(isSuccess)

# 播放入场黑幕淡出效果
func _playEntranceTransition() -> void:
	if transitionLayer.has_node("ColorRect"):
		var rect: ColorRect = transitionLayer.get_node("ColorRect")
		rect.color = Color(0, 0, 0, 1)
		rect.show()
		var tween: Tween = create_tween()
		tween.tween_property(rect, "modulate:a", 0.0, 0.5).from(1.0)
		tween.finished.connect(func(): rect.hide())

# 加载并实例化地图场景
# mapPath：地图场景资源路径
func setupMap(mapPath: String) -> void:
	if mapInstance:
		mapInstance.queue_free()

	var mapScene: PackedScene = load(mapPath)
	if not mapScene:
		push_error("[STAGE] Failed to load map: " + mapPath)
		return

	mapInstance = mapScene.instantiate()
	mapInstance.name = "Map"
	add_child(mapInstance)
	move_child(mapInstance, 0)

	print("[STAGE] Map '%s' loaded and instantiated" % mapPath)

# 播放对局开始倒计时动画
func startCountdown() -> void:
	if not countdownLabel:
		return

	countdownLabel.show()
	for i: int in range(3, 0, -1):
		countdownLabel.text = str(i)
		countdownLabel.scale = Vector2(2, 2)
		var tween: Tween = create_tween()
		tween.tween_property(countdownLabel, "scale", Vector2(1, 1), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(1.0).timeout

	countdownLabel.text = "开始！"
	var tween: Tween = create_tween()
	tween.tween_property(countdownLabel, "modulate:a", 0.0, 0.5)
	await tween.finished
	countdownLabel.hide()
	countdownLabel.modulate.a = 1.0

func _process(delta: float) -> void:
	_updateDebugInfo()
	if gm and gm.is_game_active:
		gm.tick(delta)

# 调试信息：输出本地玩家所在地图格子（格子变化时打印）
func _updateDebugInfo() -> void:
	if not gm:
		return
	var p = gm.get_local_player()
	if is_instance_valid(p):
		var pos: Vector2 = p.global_position
		var cell: Vector2i = Vector2i.ZERO
		if gm.wall_layer:
			cell = gm.wall_layer.local_to_map(gm.wall_layer.to_local(pos))
		if cell != _lastDebugCell:
			_lastDebugCell = cell
			print("[DEBUG] Player Pos: (%.1f, %.1f) | Map Cell: %s" % [pos.x, pos.y, cell])

func show_evac_zone() -> void:
	print("[STAGE] 正在尝试在地图中心激活撤离点...")
	
	var cellSize: float = 16.0 # 策划书定义的 16x16
	
	if gm and gm.wall_layer:
		# 自动适配：根据地图实际大小的一半来确定中心
		var used_rect = gm.wall_layer.get_used_rect()
		var centerCell = used_rect.position + (used_rect.size / 2)
		
		# 获取该格子的局部坐标
		var local_pos = gm.wall_layer.map_to_local(centerCell)
		
		var marker = ColorRect.new()
		marker.name = "EvacZone"
		# 将标记添加为地图层的子节点，这样坐标和缩放会自动同步
		gm.wall_layer.add_child(marker)
		
		marker.z_index = 5
		marker.color = Color(0, 1, 0, 0.4)
		
		# 撤离区覆盖 3x3 个格子
		marker.size = Vector2(cellSize * 3, cellSize * 3)
		# map_to_local 是格子中心，需要向左上角偏移 1.5 个格子宽度以对齐
		marker.position = local_pos - Vector2(cellSize * 1.5, cellSize * 1.5)
		
		var label = Label.new()
		marker.add_child(label)
		label.text = "撤离点"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = marker.size
		label.add_theme_font_size_override("font_size", 8)
		
		print("[STAGE] 撤离点已创建在地图格子: %s, 局部坐标: %s" % [centerCell, marker.position])
	else:
		print("[STAGE] 错误：无法获取 wall_layer，撤离点创建失败")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		print("[STAGE] ESC pressed - implement pause menu here")

	# 使用 InputMap action 触发打开/关闭背包界面，解决空格键误触发问题
	if event.is_action_pressed("toggle_backpack"):
		var backpack = get_tree().get_first_node_in_group("Backpack") if get_tree() else null
		if not backpack:
			backpack = get_node_or_null("BackpackLayer/Backpack")
		if backpack and backpack.has_method("toggle"):
			backpack.toggle()
			get_viewport().set_input_as_handled()
