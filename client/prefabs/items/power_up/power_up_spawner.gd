# 局内道具生成管理器
# 监听墙壁破坏事件，按概率在对应位置生成增益道具
# 使用已有的 ItemCount / ItemPower / ItemSpeed / ItemShield 场景
# 创建时间：2026-05-11

extends Node

class_name PowerUpSpawner

# ── 配置 ──
const DROP_CHANCE: float = 0.45   # 45% 增益道具掉落概率
const CHEST_CHANCE: float = 0.015  # 1.5% 宝箱掉落概率

# ── 调试开关 ──
const DEBUG_FORCE_CHEST: bool = false # 关闭强制生成

# ── 道具场景池（路径 + 权重 + 名称） ──
const ITEM_POOL: Array = [
	# [scene_path, weight, display_name]
	["res://prefabs/items/ItemCount/item_count.tscn", 35, "炸弹+1"],
	["res://prefabs/items/ItemPower/item_power.tscn", 40, "威力+1"],
	["res://prefabs/items/ItemSpeed/item_speed.tscn", 20, "速度UP"],
	["res://prefabs/items/ItemShield/item_shield.tscn", 5, "护盾"],
]

const CHEST_SCENE_PATH: String = "res://prefabs/items/Chest/chest.tscn"

# ── 内部引用 ──
var _wall_layer: TileMapLayer = null
var _parent_node: Node2D = null
var _loaded_scenes: Dictionary = {}  # path -> PackedScene 缓存
var _chest_scene: PackedScene = null
var _destroyed_walls_count: int = 0  # 累计炸毁的墙壁数量

# 初始化生成器
func setup(wall_layer: TileMapLayer, parent_node: Node2D) -> void:
	_wall_layer = wall_layer
	_parent_node = parent_node
	print("[POWERUP_SPAWNER] Setting up. Wall Layer: %s, Parent: %s" % [wall_layer.name if wall_layer else "null", parent_node.name if parent_node else "null"])
	
	# 预加载所有道具场景
	_loaded_scenes.clear()
	for entry in ITEM_POOL:
		var path: String = entry[0]
		var display_name: String = entry[2]
		if ResourceLoader.exists(path):
			var scene = load(path)
			if scene:
				_loaded_scenes[path] = scene
				print("[POWERUP_SPAWNER] Successfully preloaded: %s (%s)" % [display_name, path])
			else:
				push_error("[POWERUP_SPAWNER] Failed to load scene file: %s" % path)
		else:
			push_warning("[POWERUP_SPAWNER] Resource path does not exist: %s" % path)
	
	# 预加载宝箱
	if ResourceLoader.exists(CHEST_SCENE_PATH):
		_chest_scene = load(CHEST_SCENE_PATH)
		if _chest_scene:
			print("[POWERUP_SPAWNER] Successfully preloaded Chest: %s" % CHEST_SCENE_PATH)
		else:
			push_error("[POWERUP_SPAWNER] Failed to load Chest scene: %s" % CHEST_SCENE_PATH)
	else:
		push_warning("[POWERUP_SPAWNER] Chest resource path does not exist: %s" % CHEST_SCENE_PATH)
	
	if _loaded_scenes.is_empty():
		push_error("[POWERUP_SPAWNER] No item scenes were successfully loaded!")
		return
	else:
		print("[POWERUP_SPAWNER] Total item scenes loaded: %d" % _loaded_scenes.size())
	
	# 连接墙壁破坏信号
	if _wall_layer.has_signal("wallDestroyed"):
		if not _wall_layer.wallDestroyed.is_connected(_on_wall_destroyed):
			_wall_layer.wallDestroyed.connect(_on_wall_destroyed)
			print("[POWERUP_SPAWNER] Connected to wallDestroyed signal")
	else:
		push_warning("[POWERUP_SPAWNER] wallLayer does not have 'wallDestroyed' signal")

# 墙壁被破坏时的回调
func _on_wall_destroyed(cell_pos: Vector2i) -> void:
	var gm = get_node_or_null("/root/GameMode")
	if gm and not gm.is_offline_mode:
		# 标注修改点：联机模式下，由服务端决定并广播生成，客户端不在此本地生成
		# 直接上报给服务端进行权威概率掉落生成
		var net = get_node_or_null("/root/NetworkManager")
		if net:
			net.request("Room.TriggerDrop", {"x": cell_pos.x, "y": cell_pos.y})
		return

	_destroyed_walls_count += 1
	var roll = randf()
	var is_chest_allowed = (_destroyed_walls_count >= 18)
	print("[POWERUP_SPAWNER] Wall destroyed at %s, roll: %.3f, wall_destroyed_count: %d, chest_allowed: %s" % [cell_pos, roll, _destroyed_walls_count, is_chest_allowed])
	
	# 统一概率轴：
	# 0.000 ~ 0.015 -> 宝箱 (1.5%，但需炸毁墙体数 >= 18 才有几率掉落)
	# 0.015 ~ 0.465 -> 局内道具 (45%)
	# 0.465 ~ 1.000 -> 无掉落
	
	if (DEBUG_FORCE_CHEST or roll < CHEST_CHANCE) and is_chest_allowed:
		print("[POWERUP_SPAWNER] Chest roll success (roll < %.3f)" % CHEST_CHANCE)
		_spawn_chest_at_cell(cell_pos)
	elif roll >= CHEST_CHANCE and roll < (CHEST_CHANCE + DROP_CHANCE):
		print("[POWERUP_SPAWNER] Item roll success (%.3f < roll < %.3f)" % [CHEST_CHANCE, CHEST_CHANCE + DROP_CHANCE])
		_spawn_item_at_cell(cell_pos)
	else:
		print("[POWERUP_SPAWNER] No drop this time. (Allowed chest: %s, count: %d)" % [is_chest_allowed, _destroyed_walls_count])

# 生成宝箱
func _spawn_chest_at_cell(cell_pos: Vector2i) -> void:
	if not _chest_scene:
		push_warning("[POWERUP_SPAWNER] Chest scene not loaded!")
		return
	if not _wall_layer or not _parent_node:
		push_warning("[POWERUP_SPAWNER] Wall layer or parent node missing!")
		return
	
	var chest = _chest_scene.instantiate()
	var world_pos: Vector2 = _wall_layer.to_global(_wall_layer.map_to_local(cell_pos))
	
	_parent_node.add_child(chest)
	chest.global_position = world_pos
	
	# 播放出现动画
	chest.scale = Vector2.ZERO
	var tween = chest.create_tween()
	tween.tween_property(chest, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	print("[POWERUP_SPAWNER] Spawned Chest at cell %s" % cell_pos)

# 根据权重随机选择一个道具场景
func _pick_random_item() -> Array:
	var total_weight: int = 0
	var available_entries: Array = []
	
	for entry in ITEM_POOL:
		var path = entry[0]
		if _loaded_scenes.has(path) and _loaded_scenes[path] != null:
			available_entries.append(entry)
			total_weight += entry[1]
	
	print("[POWERUP_SPAWNER] Picking item. Available: %d, Total Weight: %d" % [available_entries.size(), total_weight])
	
	if total_weight == 0 or available_entries.is_empty():
		push_warning("[POWERUP_SPAWNER] No valid items to pick from! Loaded count: %d" % _loaded_scenes.size())
		return []
	
	var roll: int = randi() % total_weight
	var cumulative: int = 0
	for entry in available_entries:
		cumulative += entry[1]
		if roll < cumulative:
			return entry
	
	return available_entries[0]  # fallback

# 在指定地图格子位置生成一个随机道具
func _spawn_item_at_cell(cell_pos: Vector2i) -> void:
	if not _wall_layer or not _parent_node:
		return
	
	var chosen: Array = _pick_random_item()
	if chosen.is_empty():
		print("[POWERUP_SPAWNER] Pick random item returned empty")
		return
	
	var scene_path: String = chosen[0]
	var display_name: String = chosen[2]
	
	var item_scene = _loaded_scenes.get(scene_path)
	if not item_scene:
		print("[POWERUP_SPAWNER] Scene not found in cache: %s" % scene_path)
		return
	
	var item: Node = item_scene.instantiate()
	
	# 计算世界坐标（格子中心）
	var world_pos: Vector2 = _wall_layer.to_global(_wall_layer.map_to_local(cell_pos))
	
	_parent_node.add_child(item)
	item.global_position = world_pos
	item.z_index = 1
	
	# 播放出现动画（从小变大）
	item.scale = Vector2.ZERO
	var tween: Tween = item.create_tween()
	tween.tween_property(item, "scale", Vector2(1.2, 1.2), 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "scale", Vector2(1.0, 1.0), 0.1)
	
	print("[POWERUP_SPAWNER] Spawned [%s] at cell %s" % [display_name, cell_pos])
