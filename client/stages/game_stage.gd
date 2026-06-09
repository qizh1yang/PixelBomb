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

	# 监听被踢信号 (多开/重复登录)
	if not NetworkManager.kicked.is_connected(_on_kicked_from_game):
		NetworkManager.kicked.connect(_on_kicked_from_game)

	var is_standalone = (get_parent() == get_tree().root)

	if gm:
		# 仅纯离线/教程模式才走此分支（联机模式由 prepare_for_game 初始化，is_game_active 已为 true）
		if is_standalone and not gm.is_game_active and gm.is_offline_mode:
			print("[STAGE] Standalone/offline detected, loading default map...")
			gm.cleanup_game()
			gm.is_game_active = true
			gm.current_stage = gm.Stage.PLAYING
			gm.is_offline_mode = true
			var defaultMap: String = gm.get_selected_map_path()
			var cfg = gm.get_map_config()
			setupMap(defaultMap, cfg)
		elif not mapInstance:
			print("[STAGE] Online/networked mode, loading map (offline=%s active=%s standalone=%s)" % [str(gm.is_offline_mode), str(gm.is_game_active), str(is_standalone)])
			var defaultMap: String = gm.get_selected_map_path()
			var cfg = gm.get_map_config()
			setupMap(defaultMap, cfg)

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

func _on_kicked_from_game(reason: String, message: String) -> void:
	print("[STAGE] Kicked by server during game: %s — %s" % [reason, message])
	# 游戏中被踢，清理并返回登录界面
	if gm:
		gm.cleanup_game()
	UIManager.change_scene("login")

func _onGameOver(isSuccess: bool) -> void:
	print("[STAGE] 收到结算信号，显示结果面板: ", "成功" if isSuccess else "失败")
	
	if TutorialManager:
		TutorialManager.clear_all_tutorials()
		
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
# map_config：程序化地图参数 Dictionary { "map_type", "shape_type", "map_size", "seed" }
func setupMap(mapPath: String, map_config: Dictionary = {}) -> void:
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

	# [MAP CONFIG] 将 Host 权威的程序化地图参数注入到 ProceduralMap 实例
	_apply_map_config(mapInstance, map_config)

	print("[STAGE] Map '%s' loaded and instantiated (config: %s)" % [mapPath, str(map_config)])

## 将联机/离线地图配置参数注入到地图实例
func _apply_map_config(map_node: Node2D, config: Dictionary) -> void:
	if config.is_empty():
		return

	var map_type = config.get("map_type", "")
	print("[STAGE] Applying map config: type=%s shape=%s size=%s seed=%d" % [
		map_type,
		config.get("shape_type", ""),
		config.get("map_size", ""),
		config.get("seed", 0)
	])

	# 如果是 ProceduralMap，设置生成参数
	if map_type == "PROCEDURAL" and map_node.has_method("_generate_map"):
		if config.has("shape_type") and config["shape_type"] != "":
			map_node.shape_type = config["shape_type"]
		if config.has("map_size") and config["map_size"] != "":
			map_node.map_size = config["map_size"]
		# 标记为已通过外部注入参数，防止 _ready 重复生成
		map_node._config_injected = true
		print("[STAGE] Injected procedural map config into ProceduralMap node")

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
	
	if TutorialManager:
		TutorialManager.show_tutorial("controls", "上下左右键控制方向，空格键释放炸弹", -1.0, "res://assets/guide/方向键_chroma.webp", -160.0)
		
		# ── [NEW] 新手教程模式：在玩家身旁自动刷新一个宝箱 ──
		if TutorialManager.force_tutorial:
			_spawn_tutorial_chest_delayed()

func _process(delta: float) -> void:
	_updateDebugInfo()
	if gm and gm.is_game_active:
		gm.tick(delta)
	# 摄像机跟随本地玩家（不依赖 gm 状态，直接从场景树找）
	if is_instance_valid(camera):
		for p in get_tree().get_nodes_in_group("Player"):
			if is_instance_valid(p) and p.get("isLocal") == true:
				camera.global_position = p.global_position
				if not camera.is_current():
					camera.make_current()
				break

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
		
		if TutorialManager:
			TutorialManager.show_tutorial("evac_zone", "到撤离区域按E能够成功撤离", -1.0, "", 200.0)
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

func _spawn_tutorial_chest_delayed() -> void:
	# 稍微延迟 0.5 秒生成，给玩家一个视觉缓冲
	await get_tree().create_timer(0.5).timeout
	if gm:
		var lp = gm.get_local_player()
		if lp and gm.wall_layer:
			var cell = gm.wall_layer.local_to_map(gm.wall_layer.to_local(lp.global_position))
			
			var w = gm.wall_layer.width
			var h = gm.wall_layer.height
			var cx = w / 2
			var cy = h / 2
			
			# 朝向地图中心的方向向量
			var dir = Vector2(cx - cell.x, cy - cell.y).normalized()
			# 取最主要的轴方向
			var offset_dir = Vector2i.ZERO
			if abs(dir.x) > abs(dir.y):
				offset_dir.x = 1 if dir.x > 0 else -1
			else:
				offset_dir.y = 1 if dir.y > 0 else -1
				
			# 偏移 2 个格子生成宝箱，确保在朝向地图中心的方向上，绝不出界
			var chest_cell = cell + offset_dir * 2
			
			# 移除该格子上的任何墙壁以及数据矩阵记录，防止被遮挡或检测出碰撞
			gm.wall_layer.set_cell(chest_cell, -1)
			if "indestructibleMap" in gm.wall_layer:
				gm.wall_layer.indestructibleMap[chest_cell.x][chest_cell.y] = false
			if "_destructibleTiles" in gm.wall_layer:
				gm.wall_layer._destructibleTiles.erase(chest_cell)
			
			# 调用 GameMode 原有的生成宝箱视觉表现的方法
			if gm.has_method("_spawnChestVisual"):
				gm._spawnChestVisual("tutorial_chest", chest_cell.x, chest_cell.y)
				print("[TUTORIAL] Spawned tutorial chest at cell: ", chest_cell)
