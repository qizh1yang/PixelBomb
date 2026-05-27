# 经典地图墙层生成器
# 负责生成外墙、固定柱子和随机可破坏砖块
# 创建时间：2026-05-06

extends "res://prefabs/map/map_classic/floor_layer_yuansu.gd"

class_name WallLayerClassic

# ── 信号 ──
signal wallDestroyed(cellPos: Vector2i)

# ── 导出变量 ──
@export_group("Map Settings")
@export var width: int = 20
@export var height: int = 20
@export var destructibleRate: float = 0.75

# ── 私有成员变量 ──
var indestructibleMap := []
var _destructibleTiles := {}

func _ready() -> void:
	add_to_group("WallLayer")

# 外部调用入口，初始化并生成地图
# seedVal：随机种子
func initialize_map(seedVal: int) -> void:
	seed(seedVal)
	_resetData()
	generateMap()

# 导入服务端权威地图数据
func import_map_data(data: Array) -> void:
	_resetData()
	clear()
	for x in range(min(data.size(), width)):
		for y in range(min(data[x].size(), height)):
			var type = data[x][y]
			if type == 1:
				indestructibleMap[x][y] = true
			elif type == 2:
				_addDestructibleWall(x, y)
	_renderToTilemap()

# 重置内部数据矩阵
func _resetData() -> void:
	indestructibleMap.clear()
	_destructibleTiles.clear()
	indestructibleMap.resize(width)
	for x: int in range(width):
		indestructibleMap[x] = []
		for y: int in range(height):
			indestructibleMap[x].append(false)

# 生成完整地图：计算逻辑 → 清除出生点 → 渲染
func generateMap() -> void:
	clear()
	_placeLogicWalls()
	_clearSpawnAreas()
	_renderToTilemap()

# 核心逻辑生成：边界外墙 + 偶数坐标柱子 + 随机可破坏砖块
func _placeLogicWalls() -> void:
	for x: int in range(width):
		for y: int in range(height):
			if x == 0 or x == width - 1 or y == 0 or y == height - 1:
				indestructibleMap[x][y] = true
				continue
			if x % 2 == 0 and y % 2 == 0:
				indestructibleMap[x][y] = true
				continue
			if randf() < destructibleRate:
				_addDestructibleWall(x, y)

# 清除四角出生点保护区域内的所有墙
func _clearSpawnAreas() -> void:
	var spawnPoints: Array = [
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2),
		Vector2i(width - 2, 1), Vector2i(width - 3, 1), Vector2i(width - 2, 2),
		Vector2i(1, height - 2), Vector2i(2, height - 2), Vector2i(1, height - 3),
		Vector2i(width - 2, height - 2), Vector2i(width - 3, height - 2), Vector2i(width - 2, height - 3)
	]

	for pos: Vector2i in spawnPoints:
		if pos.x > 0 and pos.x < width - 1 and pos.y > 0 and pos.y < height - 1:
			indestructibleMap[pos.x][pos.y] = false
			_destructibleTiles.erase(pos)

# 随机选取可破坏墙类型并记录
func _addDestructibleWall(x: int, y: int) -> void:
	var r: float = randf()
	var wallDef: Dictionary
	if r < 0.33: wallDef = MAP_Destructible_WALL1
	elif r < 0.66: wallDef = MAP_Destructible_WALL2
	else: wallDef = MAP_Destructible_WALL3
	_destructibleTiles[Vector2i(x, y)] = wallDef

# 将逻辑数据渲染到 TileMapLayer
func _renderToTilemap() -> void:
	for x: int in range(width):
		for y: int in range(height):
			if indestructibleMap[x][y]:
				if x == 0 or x == width - 1 or y == 0 or y == height - 1:
					cell_rode(x, y, MAP_Indestructible_WALL3)
				else:
					var wallDef: Dictionary = MAP_Indestructible_WALL1 if randf() < 0.5 else MAP_Indestructible_WALL2
					cell_rode(x, y, wallDef)
			elif _destructibleTiles.has(Vector2i(x, y)):
				cell_rode(x, y, _destructibleTiles[Vector2i(x, y)])

# ── 外部接口 ──

# 判断指定格子是否为不可破坏墙
func is_indestructible(x: int, y: int) -> bool:
	if x < 0 or x >= width or y < 0 or y >= height: return true
	return indestructibleMap[x][y]

# 判断指定格子是否为可破坏墙
func is_destructible_wall(x: int, y: int) -> bool:
	return _destructibleTiles.has(Vector2i(x, y))

# 销毁指定格子的可破坏墙并发出信号
func destroy_destructible_wall(x: int, y: int) -> void:
	_destructibleTiles.erase(Vector2i(x, y))
	erase_cell(Vector2i(x, y))
	wallDestroyed.emit(Vector2i(x, y))
