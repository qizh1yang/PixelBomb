extends "res://prefabs/map/map_spring/floor_layer_yuansu.gd"

# ── 信号 ──
signal wallDestroyed(cellPos: Vector2i)

@export_group("Map Settings")
@export var width: int = 26    # 扫描宽度
@export var height: int = 26   # 扫描高度
@export var destructible_rate: float = 0.8 # 基础填充率

var indestructible_map := {} # 记录不可破坏墙的位置 Vector2i -> bool
var _destructible_tiles := {} 

func initialize_map(seed_val: int) -> void:
	seed(seed_val)
	_reset_data()
	
	# 程序化生成模式
	_generate_procedural()
	_clear_spawn_areas()
	_render_to_tilemap()


func _reset_data() -> void:
	indestructible_map.clear()
	_destructible_tiles.clear()


func _generate_procedural() -> void:
	# 1. 生成外围墙
	for x in range(width):
		indestructible_map[Vector2i(x, 0)] = true
		indestructible_map[Vector2i(x, height - 1)] = true
	for y in range(1, height - 1):
		indestructible_map[Vector2i(0, y)] = true
		indestructible_map[Vector2i(width - 1, y)] = true
	
	# 2. 生成内部固定柱子 (每隔一格一个)
	for x in range(2, width - 2, 2):
		for y in range(2, height - 2, 2):
			indestructible_map[Vector2i(x, y)] = true
	
	# 3. 填充可破坏墙 (在剩余空地)
	for x in range(1, width - 1):
		for y in range(1, height - 1):
			var pos = Vector2i(x, y)
			if indestructible_map.has(pos): continue
			
			if randf() < destructible_rate:
				_add_destructible_wall(x, y)


func _clear_spawn_areas() -> void:
	# 四个角落 3x3 区域设为安全区
	var spawn_zones = [
		Rect2i(1, 1, 3, 3),                 # 左上
		Rect2i(width - 4, 1, 3, 3),          # 右上
		Rect2i(1, height - 4, 3, 3),         # 左下
		Rect2i(width - 4, height - 4, 3, 3)   # 右下
	]
	
	for zone in spawn_zones:
		for x in range(zone.position.x, zone.end.x):
			for y in range(zone.position.y, zone.end.y):
				var pos = Vector2i(x, y)
				_destructible_tiles.erase(pos)


func _add_destructible_wall(x: int, y: int) -> void:
	var r = randf()
	var wall_def
	if r < 0.33: wall_def = MAP_Destructible_WALL1
	elif r < 0.66: wall_def = MAP_Destructible_WALL2
	else: wall_def = MAP_Destructible_WALL3
	_destructible_tiles[Vector2i(x, y)] = wall_def


func _render_to_tilemap() -> void:
	clear()
	# 渲染不可破坏墙
	for pos in indestructible_map:
		if pos.x == 0 or pos.x == width - 1 or pos.y == 0 or pos.y == height - 1:
			cell_rode(pos.x, pos.y, MAP_Indestructible_WALL3)
		else:
			var wall_def = MAP_Indestructible_WALL1 if randf() < 0.5 else MAP_Indestructible_WALL2
			cell_rode(pos.x, pos.y, wall_def)
	
	# 渲染可破坏墙
	for pos in _destructible_tiles:
		cell_rode(pos.x, pos.y, _destructible_tiles[pos])


func is_indestructible(x: int, y: int) -> bool:
	return indestructible_map.has(Vector2i(x, y))


func is_destructible_wall(x: int, y: int) -> bool:
	return _destructible_tiles.has(Vector2i(x, y))


func destroy_destructible_wall(x: int, y: int) -> void:
	_destructible_tiles.erase(Vector2i(x, y))
	erase_cell(Vector2i(x, y))
	wallDestroyed.emit(Vector2i(x, y))

