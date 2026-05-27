extends "res://prefabs/map/map_winter/floor_layer_yuansu.gd"

# ── 信号 ──
signal wallDestroyed(cellPos: Vector2i)

@export_group("Map Settings")
@export var width: int = 26    # 扫描宽度
@export var height: int = 26   # 扫描高度
@export var destructible_rate: float = 0.75 # 基础填充率

var indestructible_map := {} # 记录不可破坏墙的位置 Vector2i -> bool
var _destructible_tiles := {} 

func initialize_map(seed_val: int) -> void:
	seed(seed_val)
	_reset_data()
	
	# 手绘扫描模式
	_scan_and_fill_map()
	_clear_spawn_areas()
	_render_destructibles_only()


func _reset_data() -> void:
	indestructible_map.clear()
	_destructible_tiles.clear()


func _scan_and_fill_map() -> void:
	var used_rect = get_used_rect()
	if used_rect.size == Vector2i.ZERO: return
	
	# 1. 第一遍扫描：记录所有手绘的不可破坏墙
	for x in range(used_rect.position.x, used_rect.end.x):
		for y in range(used_rect.position.y, used_rect.end.y):
			var pos = Vector2i(x, y)
			var source_id = get_cell_source_id(pos)
			if source_id != -1:
				# 记录为不可破坏墙
				indestructible_map[pos] = true
				
				# 可选：如果是手绘的，我们可以保留它，或者统一替换为标准样式
				# 这里我们保留手绘的样式
	
	# 2. 第二遍扫描：填充内部空地
	for x in range(used_rect.position.x, used_rect.end.x):
		for y in range(used_rect.position.y, used_rect.end.y):
			var pos = Vector2i(x, y)
			
			# 如果该位置已有瓦片，跳过
			if indestructible_map.has(pos): continue
			
			# 判定是否在手绘围墙内部
			if not _is_inside_walls(pos, used_rect):
				continue
			
			# 【核心】跟随逻辑：如果周围有不可破坏墙，则有几率生成可破坏墙
			# 这样可以保证可破坏墙是“跟随”不可破坏墙生成的
			if _has_indestructible_neighbor(pos):
				if randf() < destructible_rate:
					_add_destructible_wall(x, y)
			else:
				# 如果周围没有，则几率较低，或者不生成
				if randf() < destructible_rate * 0.3:
					_add_destructible_wall(x, y)


# 检查周围是否有不可破坏墙
func _has_indestructible_neighbor(pos: Vector2i) -> bool:
	var neighbors = [
		Vector2i(pos.x + 1, pos.y), Vector2i(pos.x - 1, pos.y),
		Vector2i(pos.x, pos.y + 1), Vector2i(pos.x, pos.y - 1)
	]
	for n in neighbors:
		if indestructible_map.has(n):
			return true
	return false


# 简单的四向包围检测，确保只在围墙内部生成
func _is_inside_walls(pos: Vector2i, rect: Rect2i) -> bool:
	var l = false; var r = false; var u = false; var d = false
	for i in range(rect.position.x, pos.x):
		if indestructible_map.has(Vector2i(i, pos.y)): 
			l = true
			break
	for i in range(pos.x + 1, rect.end.x):
		if indestructible_map.has(Vector2i(i, pos.y)): 
			r = true
			break
	for j in range(rect.position.y, pos.y):
		if indestructible_map.has(Vector2i(pos.x, j)): 
			u = true
			break
	for j in range(pos.y + 1, rect.end.y):
		if indestructible_map.has(Vector2i(pos.x, j)): 
			d = true
			break
	return l and r and u and d


func _clear_spawn_areas() -> void:
	# 默认保护区域：四个角落
	var used_rect = get_used_rect()
	var pos = used_rect.position
	var end = used_rect.end
	
	var spawn_zones = [
		Rect2i(pos.x + 1, pos.y + 1, 3, 3), # 左上
		Rect2i(end.x - 4, pos.y + 1, 3, 3), # 右上
		Rect2i(pos.x + 1, end.y - 4, 3, 3), # 左下
		Rect2i(end.x - 4, end.y - 4, 3, 3)  # 右下
	]
	
	for zone in spawn_zones:
		for x in range(zone.position.x, zone.end.x):
			for y in range(zone.position.y, zone.end.y):
				_destructible_tiles.erase(Vector2i(x, y))


func _add_destructible_wall(x: int, y: int) -> void:
	var r = randf()
	var wall_def
	if r < 0.33: wall_def = MAP_Destructible_WALL1
	elif r < 0.66: wall_def = MAP_Destructible_WALL2
	else: wall_def = MAP_Destructible_WALL3
	_destructible_tiles[Vector2i(x, y)] = wall_def


func _render_destructibles_only() -> void:
	for pos in _destructible_tiles:
		cell_rode(pos.x, pos.y, _destructible_tiles[pos])


func is_indestructible(x: int, y: int) -> bool:
	return indestructible_map.get(Vector2i(x, y), false)


func is_destructible_wall(x: int, y: int) -> bool:
	return _destructible_tiles.has(Vector2i(x, y))


func destroy_destructible_wall(x: int, y: int) -> void:
	_destructible_tiles.erase(Vector2i(x, y))
	erase_cell(Vector2i(x, y))
	wallDestroyed.emit(Vector2i(x, y))
