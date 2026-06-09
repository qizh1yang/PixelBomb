# GameMode 全局游戏状态机
# 管理游戏流程状态、玩家生命周期与网络同步
# 创建时间：2026-05-06

extends Node

# 注意：不使用 class_name，避免与 Autoload 单例名称冲突

# ── 枚举 ──
enum Stage { LOBBY, PLAYING, SETTLEMENT }

# ── 信号 ──
signal gameStarted()
signal playerDied(playerId: String)
signal gameEnded(winnerId: String, winnerName: String)
signal mapGenerated()
signal gameOverReceived(isSuccess: bool)

# ── 公开状态 ──
var current_stage: Stage = Stage.LOBBY
var players: Dictionary = {}
var initial_stats_cache: Dictionary = {}
var is_offline_mode: bool = false
var map_seed: int = 0
var is_game_active: bool = false
var gameTimeRemaining: float = 300.0 
var evacTriggered: bool = false

# ── 内部引用 ──
var game_stage: Node2D = null
var map_instance: Node2D = null
var wall_layer: TileMapLayer = null
var hud: CanvasLayer = null
var camera: Camera2D = null
var chests: Dictionary = {} 
var items: Dictionary = {}  
var powerup_spawner: Node = null  

# ── 网络同步 ──
var syncTimer: float = 0.0
const SYNC_INTERVAL: float = 0.033
var lastSentPos: Vector2 = Vector2.ZERO
var lastSentState: String = ""
var lastSentDir: String = ""

var selectedMapName: String = "CLASSIC"

func get_selected_map_path() -> String:
	var net = get_node_or_null("/root/NetworkManager")
	var map_type: String = selectedMapName
	if net and not GameMode.is_offline_mode:
		map_type = net.current_map_type
	print("[GameMode] get_selected_map_path: map_type=%s offline=%s" % [map_type, str(is_offline_mode)])
	return MapFactory.get_map_scene_path(map_type)

## 构建当前地图配置字典，传递给 GameStage.setupMap
func get_map_config() -> Dictionary:
	var net = get_node_or_null("/root/NetworkManager")
	if not net or is_offline_mode:
		return {"map_type": selectedMapName, "shape_type": "circle", "map_size": "small", "seed": map_seed}
	var cfg = {"map_type": net.current_map_type, "shape_type": net.current_shape_type, "map_size": net.current_map_size, "seed": net.map_seed}
	print("[GameMode] get_map_config: %s" % str(cfg))
	return cfg


# ══════════════════════════════════════════════════════
#  生命周期
# ══════════════════════════════════════════════════════

func start_game() -> void:
	if is_game_active: return
	current_stage = Stage.PLAYING
	is_game_active = true
	GlobalPlayerData.opened_chests_count = 0
	var stageScene: PackedScene = preload("res://stages/game_stage.tscn")
	game_stage = stageScene.instantiate()
	if game_stage.has_signal("stageReady"):
		game_stage.stageReady.connect(_onStageReady, CONNECT_ONE_SHOT)
	get_tree().root.add_child(game_stage)
	var mapPath: String = get_selected_map_path()
	var mapConfig = get_map_config()
	print("[GameMode] start_game: mapPath=%s config=%s" % [mapPath, str(mapConfig)])
	game_stage.setupMap(mapPath, mapConfig)
	_get_references_from_stage()
	_connectNetwork()

func _onStageReady() -> void:
	pass

func _get_references_from_stage() -> void:
	if not game_stage: return
	camera = game_stage.get_node_or_null("Camera2D")
	if camera: camera.make_current()
	hud = game_stage.get_node_or_null("HUD")
	if hud and hud.get_child_count() == 0:
		var hudScene: PackedScene = load("res://prefabs/HUD/hud.tscn")
		if hudScene:
			var hudInst: Node = hudScene.instantiate()
			hud.add_child(hudInst)
			hud = hudInst
	map_instance = game_stage.get_node_or_null("Map")
	if not map_instance: map_instance = game_stage.find_child("*Map*", true, false)
	if map_instance:
		wall_layer = map_instance.get_node_or_null("wallLayer")
		if wall_layer and not wall_layer.is_in_group("WallLayer"):
			wall_layer.add_to_group("WallLayer")
		if map_instance.has_signal("map_generated"):
			if not map_instance.map_generated.is_connected(_onMapGenerated):
				map_instance.map_generated.connect(_onMapGenerated)
		if map_instance.get("_map_ready") == true:
			_onMapGenerated(map_instance.get("_map_seed"))

func _connectNetwork() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net:
		if not net.message_received.is_connected(_onNetworkMessage):
			net.message_received.connect(_onNetworkMessage)
		if net.has_signal("game_state_resumed") and not net.game_state_resumed.is_connected(_on_game_state_resumed):
			net.game_state_resumed.connect(_on_game_state_resumed)

func cleanup_game() -> void:
	if TutorialManager:
		TutorialManager.clear_all_tutorials()
		TutorialManager.force_tutorial = false
		
	is_game_active = false
	current_stage = Stage.LOBBY
	players.clear()
	chests.clear()
	items.clear()
	map_seed = 0
	gameTimeRemaining = 300.0
	evacTriggered = false
	var net = get_node_or_null("/root/NetworkManager")
	if net:
		if net.message_received.is_connected(_onNetworkMessage):
			net.message_received.disconnect(_onNetworkMessage)
		if net.has_signal("game_state_resumed") and net.game_state_resumed.is_connected(_on_game_state_resumed):
			net.game_state_resumed.disconnect(_on_game_state_resumed)
	if is_instance_valid(game_stage):
		game_stage.queue_free()
	game_stage = null; map_instance = null; wall_layer = null; hud = null; camera = null
	lastSentPos = Vector2.ZERO; syncTimer = 0.0
	if is_instance_valid(powerup_spawner): powerup_spawner.queue_free()
	powerup_spawner = null
	print("[GameMode] Game state cleaned up.")
	powerup_spawner = null

func prepare_for_game() -> void:
	cleanup_game()
	current_stage = Stage.PLAYING
	is_game_active = true
	is_offline_mode = false
	GlobalPlayerData.opened_chests_count = 0
	# 立即重连网络消息监听，防止 cleanup_game 断开后丢失服务端紧跟着发来的 onPlayerStats
	_connectNetwork()
	var net = get_node_or_null("/root/NetworkManager")
	if net:
		map_seed = net.map_seed
		if net.current_map_type != "":
			selectedMapName = net.current_map_type
			print("[GameMode] prepare_for_game: synced type=%s shape=%s size=%s seed=%d" % [net.current_map_type, net.current_shape_type, net.current_map_size, net.map_seed])

func init_from_stage(stage: Node2D) -> void:
	game_stage = stage
	_get_references_from_stage()
	_connectNetwork()

func _onMapGenerated(seedVal: int) -> void:
	map_seed = seedVal
	# 仅在地图确认离线模式时覆盖，绝不将联机模式错误切回离线
	if map_instance and "is_offline_mode" in map_instance and map_instance.is_offline_mode:
		is_offline_mode = true
		print("[GameMode] Map confirmed offline mode")
	mapGenerated.emit()
	_spawnLocalPlayer()
	_syncExistingPlayers()
	_setupPowerUpSpawner()
	_setupHudPlayerCards()
	if game_stage and game_stage.has_method("startCountdown"):
		game_stage.startCountdown()

func _onGameStarted() -> void:
	gameStarted.emit()



func _onGameEnded(winnerId: String, winnerName: String) -> void:
	gameEnded.emit(winnerId, winnerName)


# ══════════════════════════════════════════════════════
#  玩家生成
# ══════════════════════════════════════════════════════

func _spawnLocalPlayer() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	var p: Node = null
	if not net or is_offline_mode:
		p = _createPlayer("local_player", Vector2.ZERO, 0, "Player", true)
		var cells: Array[Vector2i] = _getRandomCornerCells()
		_setPlayerToCell(p, cells[0])
	else:
		var myId: String = net.my_id
		var charIdx: int = net.selected_char_index
		p = _createPlayer(myId, Vector2.ZERO, charIdx, net.player_name, true)
		var cells: Array[Vector2i] = _getRandomCornerCells()
		var spawn_idx: int = 0
		if net.players.has(myId):
			spawn_idx = int(net.players[myId].get("spawn_index", 0))
		else:
			spawn_idx = net.my_player_index
		var idx: int = spawn_idx % cells.size()
		_setPlayerToCell(p, cells[idx])
		
		print("[SPAWN] Local player spawned at corner cell index: ", idx, " pos=", p.global_position)

	# 核心修复：玩家生成后，立刻触发背包将属性上限同步给玩家控制器，确保战前配备的物品加成生效
	var backpack_node = get_tree().get_first_node_in_group("Backpack")
	if is_instance_valid(backpack_node) and backpack_node.has_method("updateBackpackStats"):
		backpack_node.updateBackpackStats()

func _syncExistingPlayers() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if not net: return
	var localId: String = "local_player" if is_offline_mode else net.my_id
	for id: String in net.players:
		if not players.has(id) and id != localId:
			var data: Dictionary = net.players[id]
			var charIdx: int = int(data.get("char", 0))
			var pname: String = data.get("name", "Unknown")
			
			# 标注修改点：远程玩家不直接依赖数据中的 x 和 y 坐标生成，而是读取 spawn_index 并在 corners 中生成，保证客户端完全一致
			var p = _createPlayer(id, Vector2.ZERO, charIdx, pname, false)
			var cells: Array[Vector2i] = _getRandomCornerCells()
			var spawn_idx: int = int(data.get("spawn_index", 0))
			var idx: int = spawn_idx % cells.size()
			_setPlayerToCell(p, cells[idx])
			
			print("[SPAWN] Remote player %s synced at corner cell index: %d" % [id, idx])

## 玩家全部生成后，向 HUD 初始化状态卡片
func _setupHudPlayerCards() -> void:
	if not is_instance_valid(hud) or not hud.has_method("setup_players"):
		return
	var player_list: Array = []
	var idx: int = 0
	for pid in players:
		var p: Node = players[pid]
		if not is_instance_valid(p): continue
		var peerId: int = int(pid) if pid.is_valid_int() else 0
		var pname: String = p.get("player_name") if p.get("player_name") != null else ("玩家%d" % (idx + 1))
		
		var char_idx = p.get("char_index") if p.get("char_index") != null else 0
		var avatar_texture = null
		var avatar_path = "res://prefabs/Players/player%d/res/Faceset.png" % (char_idx + 1)
		if ResourceLoader.exists(avatar_path):
			avatar_texture = load(avatar_path)
			
		player_list.append({
			"peer_id":    peerId,
			"name":       pname,
			"player_idx": idx,
			"avatar":     avatar_texture
		})
		idx += 1
	hud.setup_players(player_list)

func _createPlayer(id: String, pos: Vector2, charIdx: int, pname: String, isLocal: bool) -> Node:
	var char_res = CharacterRegistry.get_character_by_index(charIdx)
	var p: Node = CharacterFactory.create_character(char_res)
	if not p: return null
	p.name = str(id); p.isLocal = isLocal; p.network_id = id; p.player_name = pname; p.char_index = charIdx
	p.global_position = pos
	if not isLocal: p.target_pos = pos
	if game_stage:
		game_stage.add_child(p); p.z_index = 1
	else: return null
	players[id] = p
	
	# 双保险机制：应用已缓存的权威属性配置
	if initial_stats_cache.has(id):
		if p.has_method("apply_stats"):
			p.apply_stats(initial_stats_cache[id])
			
	if isLocal and is_instance_valid(camera):
		camera.global_position = p.global_position
		camera.reset_smoothing()
	return p

func _getRandomCornerCells() -> Array[Vector2i]:
	var w: int = 20; var h: int = 20
	if wall_layer:
		if wall_layer.get("width"): w = wall_layer.width
		if wall_layer.get("height"): h = wall_layer.height
	if selectedMapName == "CLASSIC":
		var cx: int = w / 2
		var cy: int = h / 2
		return [
			Vector2i(cx, 1),        # 上边缘出生点
			Vector2i(cx, h - 2),    # 下边缘出生点
			Vector2i(1, cy),        # 左边缘出生点
			Vector2i(w - 2, cy)     # 右边缘出生点
		]
	else:
		var left: int = 1; var top: int = 1; var right: int = w - 2; var bottom: int = h - 2
		return [Vector2i(left, top), Vector2i(right, top), Vector2i(left, bottom), Vector2i(right, bottom)]

func _setPlayerToCell(player: Node2D, cell: Vector2i) -> void:
	if wall_layer:
		var localPos: Vector2 = wall_layer.map_to_local(cell)
		player.global_position = wall_layer.to_global(localPos)
	else: player.global_position = Vector2(24, 24)


# ══════════════════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════════════════

func tick(delta: float) -> void:
	if not is_game_active or not game_stage: return
	if current_stage == Stage.PLAYING:
		gameTimeRemaining -= delta
		if is_instance_valid(hud) and hud.has_method("updateTime"):
			hud.updateTime(max(0, gameTimeRemaining))
		if gameTimeRemaining <= 120.0 and not evacTriggered:
			evacTriggered = true; _activateEvacuation()
		if gameTimeRemaining <= 0:
			_onTimeOut(); return
	var aliveCount = 0
	for pid in players:
		if is_instance_valid(players[pid]) and not players[pid].isDead: aliveCount += 1
	if is_instance_valid(hud) and hud.has_method("updateSurvivors"):
		hud.updateSurvivors(aliveCount)
	# 每帧数据驱动更新所有玩家状态卡片
	if is_instance_valid(hud) and hud.has_method("refresh_player_hud"):
		for pid in players:
			var p: Node = players[pid]
			if not is_instance_valid(p): continue
			var peerId: int = int(pid) if pid.is_valid_int() else 0
			hud.refresh_player_hud(peerId, p)
	var localKey: String = get_local_player_id()
	if not players.has(localKey): return
	var p: Node = players[localKey]
	if not is_instance_valid(p): return
	if is_instance_valid(camera): camera.global_position = p.global_position
	if not is_offline_mode:
		var net = get_node_or_null("/root/NetworkManager")
		if net and net.is_connected_to_host:
			syncTimer += delta
			if syncTimer >= SYNC_INTERVAL:
				var current_state = "idle"
				if p.isDead:
					current_state = "dead"
				elif p.velocityInput.length() > 0:
					current_state = "walk"
				var facing_dir = p.currentDirection
				
				# 优化同步判定：位置变化（大于1.0距离平方）或 状态/朝向变化时才进行广播发送
				var pos_changed = p.global_position.distance_squared_to(lastSentPos) > 1.0
				var state_changed = (current_state != lastSentState) or (facing_dir != lastSentDir)
				
				if pos_changed or state_changed:
					lastSentPos = p.global_position
					lastSentState = current_state
					lastSentDir = facing_dir
					syncTimer = 0.0
					# 问题1：上报坐标的同时，上报速度矢量 vx 和 vy 用于服务端预测受击位置
					NetworkManager.move(p.global_position.x, p.global_position.y, p.velocity.x, p.velocity.y, current_state, facing_dir)


# ══════════════════════════════════════════════════════
#  网络消息处理
# ══════════════════════════════════════════════════════

func _onNetworkMessage(route: String, data: Variant) -> void:
	if not is_game_active: return
	
	match route:
		"onGameStart":
			var payload = data
			var mapData = payload.get("map", [])
			if wall_layer and wall_layer.has_method("import_map_data"): wall_layer.import_map_data(mapData)
		"onMove":
			var pid = NetworkManager.clean_id(data.get("id", ""))
			if pid != "" and pid != NetworkManager.my_id and players.has(pid):
				var target_x = data.get("x", 0.0)
				var target_y = data.get("y", 0.0)
				var rem_state = data.get("state", "idle")
				var rem_dir = data.get("direction", "down")
				var tick = int(data.get("tick", 0))
				
				var remote_player = players[pid]
				if tick <= remote_player.last_remote_tick:
					return
				remote_player.last_remote_tick = tick
				remote_player.target_pos = Vector2(target_x, target_y)
				if "remote_state" in remote_player:
					remote_player.remote_state = rem_state
				if "remote_direction" in remote_player:
					remote_player.remote_direction = rem_dir
		"onBombPlaced":
			var ownerId = NetworkManager.clean_id(data.get("owner", ""))
			# 核心修复：如果是本地玩家，跳过该消息，因为本地玩家已经先放过了
			if players.has(ownerId) and ownerId != NetworkManager.my_id:
				var cell = Vector2i(data.get("x", 0), data.get("y", 0))
				var radius = int(data.get("radius", 1))
				players[ownerId].doSpawnBomb(cell, radius)
		"onBombExploded":
			var cell = Vector2i(data.get("x", 0), data.get("y", 0))
			var radius = int(data.get("radius", 1))
			_handleBombExplodedFromServer(cell, radius)
		"onPlayerEvacuated":
			var pid = NetworkManager.clean_id(data.get("id", ""))
			if players.has(pid): players[pid].hide()
			if pid == get_local_player_id(): _finalizeMatchSettlement(true)
		"onEvacFailed":
			var reason = data.get("reason", "")
			var message = data.get("message", "撤离失败")
			print("[GAME] Evacuation failed: %s — %s" % [reason, message])
			if is_instance_valid(hud) and hud.has_method("showNotification"):
				hud.showNotification(message)
		"onPlayerDie":
			var pid = NetworkManager.clean_id(data.get("id", ""))
			print("[GAME] onPlayerDie received: pid=%s my_id=%s in_players=%s" % [pid, NetworkManager.my_id, str(players.has(pid))])
			if players.has(pid):
				var p = players[pid]
				if p.has_method("die") and not p.isDead:
					print("[GAME] Calling die() on player %s" % pid)
					p.die()
				else:
					print("[GAME] Skip die: has_method=%s isDead=%s" % [str(p.has_method("die")), str(p.isDead)])
				playerDied.emit(pid)
				_checkGameOver()
			else:
				print("[GAME] onPlayerDie: player %s not found! keys=%s" % [pid, str(players.keys())])
		"onShieldLost":
			var pid = NetworkManager.clean_id(data.get("id", ""))
			print("[GAME] onShieldLost received: pid=%s" % pid)
			if pid != "" and players.has(pid):
				var p = players[pid]
				if p.has_method("lose_shield"):
					p.lose_shield()
		"onChestOpened":
			var cid = NetworkManager.clean_id(data.get("id", ""))
			_handleChestOpened(cid)
		"onItemSpawn":
			var itemID = NetworkManager.clean_id(data.get("id", ""))
			var type = data.get("type", "")
			var x = int(data.get("x", 0))
			var y = int(data.get("y", 0))
			print("[NETWORK] Spawn item: %s, type: %s at (%d, %d)" % [itemID, type, x, y])
			if type == "chest":
				_spawnChestVisual(itemID, x, y)
			else:
				_spawnItemVisual(itemID, type, x, y)
		"onPickup":
			var pid = NetworkManager.clean_id(data.get("player_id", ""))
			if pid == "":
				pid = NetworkManager.clean_id(data.get("id", ""))
			var itemID = NetworkManager.clean_id(data.get("id", ""))
			print("[NETWORK] Player %s picked up item: %s" % [pid, itemID])

			# 移除世界道具（所有玩家统一处理）
			_removeWorldItem(itemID)

			# 本地玩家已在 _onBodyEntered 乐观应用；此处兜底非本地玩家表现清理
			if pid != get_local_player_id():
				var item = items.get(itemID)
				if is_instance_valid(item) and item.has_method("_playPickupEffect"):
					item._playPickupEffect()
		"onPlayerStats":
			var pid = NetworkManager.clean_id(data.get("id", ""))
			var stats = data.get("stats", {})
			if pid != "":
				initial_stats_cache[pid] = stats
				if players.has(pid):
					var p = players[pid]
					if p.has_method("apply_stats"):
						p.apply_stats(stats)
		"onTick":
			var rem_time = data.get("remaining_time", -1)
			if rem_time != -1:
				gameTimeRemaining = float(rem_time)

# ── 核心结算逻辑 ──

func _finalizeMatchSettlement(isSuccess: bool) -> void:
	if current_stage == Stage.SETTLEMENT: return
	
	print("[GameMode] Finalizing Match Settlement. Success: ", isSuccess)
	current_stage = Stage.SETTLEMENT
	is_game_active = false
	
	# ── [NEW] 新手教程模式：跳过背包装备同步和联网结算，不污染局外数据 ──
	if TutorialManager and TutorialManager.force_tutorial:
		gameOverReceived.emit(isSuccess)
		return
	
	# 提取背包物品并同步到服务器
	var backpack_node = get_tree().get_first_node_in_group("Backpack")
	if is_instance_valid(backpack_node):
		var items_res = backpack_node.get_all_item_resources(!isSuccess)
		var layout_data = backpack_node.get_backpack_layout_data()
		
		# 过滤布局数据 (如果失败，只保留保险格)
		var final_config: Array[Dictionary] = []
		if isSuccess:
			final_config = layout_data
		else:
			for it in layout_data:
				if it.get("is_insurance", false):
					final_config.append(it)
		
		# 提取路径 (从最终确定的布局配置中提取)
		var paths: Array[String] = []
		print("[Settlement] --- 提取物品清单 ---")
		for item_data in final_config:
			var path = item_data.get("res_path", "")
			if path != "":
				paths.append(path)
				print("  - 带出物品: ", path)
		
		if paths.is_empty():
			print("  - 无物品提取")
		print("[Settlement] ------------------")
		
		# 1. 客户端同步更新 (用于立即显示)
		GlobalPlayerData.collect_items_from_backpack(items_res)
		GlobalPlayerData.backpack_config = final_config # 显式设置本地配置
		
		# 2. 发送联网结算请求
		var net = get_node_or_null("/root/NetworkManager")
		if net and net.is_connected_to_host:
			var remote_config = []
			for item in final_config:
				var pos = item.get("grid_pos", Vector2i.ZERO)
				remote_config.append({
					"res_path": item.get("res_path", ""),
					"grid_pos": [pos.x, pos.y],
					"is_insurance": item.get("is_insurance", false),
					"rotated": item.get("rotated", false)
				})
			
			NetworkManager.request("Room.Settlement", {
				"success": isSuccess,
				"config": remote_config,
				"extracted": paths
			})
	
	gameOverReceived.emit(isSuccess)
	


# ══════════════════════════════════════════════════════
#  游戏结束与结算
# ══════════════════════════════════════════════════════

func _checkGameOver() -> void:
	# 在联机模式下，每个玩家的生死和结算都是完全独立的，不因为其他玩家的死亡而强制结束自己当前的对局
	if not is_offline_mode:
		return
		
	var alive: Array = []
	for id: String in players:
		var p: Node = players[id]
		if is_instance_valid(p) and not p.isDead: alive.append(p)
	if alive.size() > 1: return
	var lp = get_local_player()
	var isSuccess = false
	if lp: isSuccess = lp.visible == false or (lp.has_method("is_evacuated") and lp.is_evacuated)
	_finalizeMatchSettlement(isSuccess)

# ══════════════════════════════════════════════════════
#  工具
# ══════════════════════════════════════════════════════

func _spawnWorldItem(data: Dictionary) -> void:
	var id = data.get("id", ""); var type = data.get("type", "bomb"); var x = data.get("x", 0); var y = data.get("y", 0)
	if items.has(id): return
	var itemScene = load("res://prefabs/items/world_item.tscn")
	if itemScene:
		var item = itemScene.instantiate(); item.itemID = id
		if game_stage:
			game_stage.get_node("EntityLayer").add_child(item); item.global_position = Vector2(x * 16 + 8, y * 16 + 8); items[id] = item

func _removeWorldItem(id: String) -> void:
	if items.has(id): items[id].queue_free(); items.erase(id)

func _handleChestOpened(id: String) -> void:
	if chests.has(id): chests[id].queue_free(); chests.erase(id)

func get_local_player() -> Node:
	var p = players.get(get_local_player_id())
	return p if is_instance_valid(p) else null

func get_local_player_id() -> String:
	if is_offline_mode: return "local_player"
	var net = get_node_or_null("/root/NetworkManager")
	return net.clean_id(net.my_id) if net else ""

func _activateEvacuation() -> void:
	if is_instance_valid(hud) and hud.has_method("showNotification"):
		hud.showNotification("撤离点已经在地图中心出现，请及时撤离")
	if game_stage and game_stage.has_method("show_evac_zone"): game_stage.show_evac_zone()

func _onTimeOut() -> void:
	var lp = get_local_player()
	var isSuccess = false
	if lp: isSuccess = lp.visible == false or (lp.has_method("is_evacuated") and lp.is_evacuated)
	_finalizeMatchSettlement(isSuccess)

func _setupPowerUpSpawner() -> void:
	if not wall_layer or not game_stage: return
	if is_instance_valid(powerup_spawner): return
	powerup_spawner = Node.new(); powerup_spawner.name = "PowerUpSpawner"
	powerup_spawner.set_script(load("res://prefabs/items/power_up/power_up_spawner.gd"))
	game_stage.add_child(powerup_spawner)
	var entity_layer: Node2D = game_stage.get_node_or_null("EntityLayer")
	if not entity_layer: entity_layer = game_stage
	powerup_spawner.setup(wall_layer, entity_layer)

func _spawnChestVisual(itemID: String, x: int, y: int) -> void:
	var path = "res://prefabs/items/Chest/chest.tscn"
	var scene = load(path)
	if scene and wall_layer and game_stage:
		var chest = scene.instantiate()
		chest.chestID = itemID
		var cell_pos = Vector2i(x, y)
		var world_pos = wall_layer.to_global(wall_layer.map_to_local(cell_pos))
		game_stage.add_child(chest)
		chest.global_position = world_pos
		chests[itemID] = chest
		# 出现动画
		chest.scale = Vector2.ZERO
		var tween = chest.create_tween()
		tween.tween_property(chest, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _spawnItemVisual(itemID: String, type: String, x: int, y: int) -> void:
	var path = ""
	match type:
		"count": path = "res://prefabs/items/ItemCount/item_count.tscn"
		"power": path = "res://prefabs/items/ItemPower/item_power.tscn"
		"speed": path = "res://prefabs/items/ItemSpeed/item_speed.tscn"
		"shield": path = "res://prefabs/items/ItemShield/item_shield.tscn"
	if path == "": return
	var scene = load(path)
	if scene and wall_layer and game_stage:
		var item = scene.instantiate()
		if "itemID" in item:
			item.itemID = itemID
		elif item.has_meta("itemID"):
			item.set_meta("itemID", itemID)
		
		var cell_pos = Vector2i(x, y)
		var world_pos = wall_layer.to_global(wall_layer.map_to_local(cell_pos))
		
		var entity_layer = game_stage.get_node_or_null("EntityLayer")
		if entity_layer:
			entity_layer.add_child(item)
		else:
			game_stage.add_child(item)
			
		item.global_position = world_pos
		item.z_index = 1
		items[itemID] = item
		
		# 出现动画
		item.scale = Vector2.ZERO
		var tween = item.create_tween()
		tween.tween_property(item, "scale", Vector2(1.2, 1.2), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(item, "scale", Vector2(1.0, 1.0), 0.1)

func shake_camera(duration: float = 0.2, intensity: float = 4.0) -> void:
	if not is_instance_valid(camera):
		return
	var original_offset = camera.offset
	var timer = 0.0
	while timer < duration:
		camera.offset = original_offset + Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		await get_tree().create_timer(0.02).timeout
		timer += 0.02
	camera.offset = original_offset


func _handleBombExplodedFromServer(cell: Vector2i, radius: int) -> void:
	if not wall_layer: return
	var target_world_pos = wall_layer.to_global(wall_layer.map_to_local(cell))
	
	# Find any bomb near this position
	var found_bomb = false
	var bombs = get_tree().get_nodes_in_group("Bomb")
	for bomb in bombs:
		if is_instance_valid(bomb) and bomb is Bomb:
			var bomb_cell = wall_layer.local_to_map(wall_layer.to_local(bomb.global_position))
			if bomb_cell == cell:
				# Trigger explosion immediately if not already done
				if bomb.has_method("explode"):
					bomb.explode()
				found_bomb = true
				break
				
	# If no bomb was found locally (e.g. lag or prediction mismatch), spawn the visual effect manually
	if not found_bomb:
		print("[SYNC] Bomb at cell %s exploded on server but not found locally. Spawning visual explosion." % str(cell))
		var lp = get_local_player()
		if lp and "bombScene" in lp and lp.bombScene:
			var bomb = lp.bombScene.instantiate()
			wall_layer.get_parent().add_child(bomb)
			bomb.wallLayer = wall_layer
			bomb.explosionLength = radius
			bomb.limitUp = radius
			bomb.limitDown = radius
			bomb.limitLeft = radius
			bomb.limitRight = radius
			bomb.global_position = target_world_pos
			if bomb.has_method("explode"):
				bomb.explode()

func _on_game_state_resumed(snapshot: Dictionary) -> void:
	print("[GameMode] Seamless Reconnect caught authoritative game state snapshot! Re-syncing visual battlefield...")
	
	# 1. 恢复对局时间
	var rem_time = snapshot.get("remaining_time", -1)
	if rem_time != -1:
		gameTimeRemaining = float(rem_time)
		if is_instance_valid(hud) and hud.has_method("updateTime"):
			hud.updateTime(max(0, gameTimeRemaining))
			
	# 2. 物理校准并重绘所有玩家的位置、生死状态
	var snap_players = snapshot.get("players", {})
	for pid in snap_players.keys():
		var p_state = snap_players[pid]
		if players.has(pid):
			var p = players[pid]
			if is_instance_valid(p):
				p.global_position = Vector2(p_state.get("x", 0.0), p_state.get("y", 0.0))
				if "target_pos" in p:
					p.target_pos = p.global_position
				
				# 状态重置
				p.isDead = p_state.get("is_dead", false)
				if p.isDead and p.has_method("die"):
					p.die()
				elif not p.isDead:
					p.show() # 如果断线前被清除隐藏，重连后重现
				
				# 属性同步
				if p.has_method("apply_stats"):
					p.apply_stats(p_state)
		else:
			# 如果该玩家之前本地不存在，动态为其补发创建 (防漏人)
			var charIdx = int(p_state.get("char", 0))
			var pname = p_state.get("name", "Player")
			var isLocal = (pid == get_local_player_id())
			var p = _createPlayer(pid, Vector2(p_state.get("x", 0.0), p_state.get("y", 0.0)), charIdx, pname, isLocal)
			if p:
				p.isDead = p_state.get("is_dead", false)
				if p.isDead and p.has_method("die"):
					p.die()

	# 3. 清理并重新生成对局中所有的炸弹表现，防止因网络断开遗留残余炸弹引发视效错乱
	var old_bombs = get_tree().get_nodes_in_group("Bomb")
	for bomb in old_bombs:
		if is_instance_valid(bomb):
			bomb.queue_free()
			
	var snap_bombs = snapshot.get("bombs", {})
	var lp = get_local_player()
	for bid in snap_bombs.keys():
		var b_state = snap_bombs[bid]
		var b_owner = b_state.get("owner_id", "")
		if players.has(b_owner) and is_instance_valid(players[b_owner]):
			var cell = Vector2i(int(b_state.get("x", 0)), int(b_state.get("y", 0)))
			var radius = int(b_state.get("radius", 1))
			players[b_owner].doSpawnBomb(cell, radius)
		elif lp and "bombScene" in lp and lp.bombScene:
			# 安全备用：由本地玩家辅助生成表现
			var bomb = lp.bombScene.instantiate()
			wall_layer.get_parent().add_child(bomb)
			bomb.wallLayer = wall_layer
			bomb.explosionLength = int(b_state.get("radius", 1))
			var cell = Vector2i(int(b_state.get("x", 0)), int(b_state.get("y", 0)))
			bomb.global_position = wall_layer.to_global(wall_layer.map_to_local(cell))
			
	# 4. 强制隐藏或恢复断线重连监控的 UI
	var conn_monitor = get_node_or_null("/root/ConnectionMonitor")
	if conn_monitor and "statusPanel" in conn_monitor:
		conn_monitor.statusPanel.visible = false

	print("[GameMode] Battle state fully catchup and synchronized successfully.")
