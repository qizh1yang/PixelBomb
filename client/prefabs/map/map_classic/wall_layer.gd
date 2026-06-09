# 经典地图墙层生成器
# 负责生成外墙、固定柱子和随机可破坏砖块
# 创建时间：2026-05-06

extends "res://prefabs/map/map_classic/floor_layer_yuansu.gd"

class_name WallLayerClassic

# ── 信号 ──
signal wallDestroyed(cellPos: Vector2i)

# ── 导出变量 ──
@export_group("Map Settings")
@export var width: int = 49
@export var height: int = 49
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

# 核心逻辑生成：圆圈外边界精准围栏 + 圆圈内固定柱子 + 随机可破坏砖块，圆圈外部虚空留白
func _placeLogicWalls() -> void:
	var cx: float = width / 2.0
	var cy: float = height / 2.0
	
	for x: int in range(width):
		for y: int in range(height):
			var dx: float = (x + 0.5) - cx
			var dy: float = (y + 0.5) - cy
			var dist: float = sqrt(dx * dx + dy * dy)
			
			if dist >= 24.5:
				# 外部虚空区域，不生成任何墙体
				continue
			
			if dist >= 23.5:
				# 精准的圆边界最外圈围栏（不可破坏外墙）
				indestructibleMap[x][y] = true
				continue
			
			# 圆形内部的经典布局逻辑
			if x % 2 == 0 and y % 2 == 0:
				indestructibleMap[x][y] = true
				continue
				
			if randf() < destructibleRate:
				_addDestructibleWall(x, y)

# 清除上下左右四个出生点保护区域内的障碍墙（上下端点清除横向，左右端点清除纵向，保留最外圈围栏）
func _clearSpawnAreas() -> void:
	var cx_i: int = width / 2
	var cy_i: int = height / 2
	var spawnPoints: Array = [
		Vector2i(cx_i, 1),
		Vector2i(cx_i, height - 2),
		Vector2i(1, cy_i),
		Vector2i(width - 2, cy_i)
	]

	var cx: float = width / 2.0
	var cy: float = height / 2.0

	for pos: Vector2i in spawnPoints:
		# 1. 清除出生点本身
		indestructibleMap[pos.x][pos.y] = false
		_destructibleTiles.erase(pos)
		
		# 判断是上下边缘还是左右边缘
		var is_top_bottom_edge: bool = (pos.y == 1 or pos.y == height - 2)
		
		if is_top_bottom_edge:
			# 上下边缘：清除水平横向（左右各 2 格，X 轴变化）
			for dx in [-2, -1, 1, 2]:
				var px = pos.x + dx
				var py = pos.y
				if px >= 0 and px < width:
					var dist_dx = (px + 0.5) - cx
					var dist_dy = (py + 0.5) - cy
					var dist = sqrt(dist_dx * dist_dx + dist_dy * dist_dy)
					# 只有圆通行区内的格子才做清除，避免把边界最外圈围栏也清理掉
					if dist < 23.5:
						indestructibleMap[px][py] = false
						_destructibleTiles.erase(Vector2i(px, py))
		else:
			# 左右边缘：清除垂直纵向（上下各 2 格，Y 轴变化）
			for dy in [-2, -1, 1, 2]:
				var px = pos.x
				var py = pos.y + dy
				if py >= 0 and py < height:
					var dist_dx = (px + 0.5) - cx
					var dist_dy = (py + 0.5) - cy
					var dist = sqrt(dist_dx * dist_dx + dist_dy * dist_dy)
					# 只有圆通行区内的格子才做清除，避免把边界最外圈围栏也清理掉
					if dist < 23.5:
						indestructibleMap[px][py] = false
						_destructibleTiles.erase(Vector2i(px, py))

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
	var cx: float = width / 2.0
	var cy: float = height / 2.0
	
	for x: int in range(width):
		for y: int in range(height):
			var dx: float = (x + 0.5) - cx
			var dy: float = (y + 0.5) - cy
			var dist: float = sqrt(dx * dx + dy * dy)
			
			if dist >= 24.5:
				# 外部区域一律不进行渲染，保持完全虚空留空
				continue
				
			if indestructibleMap[x][y]:
				if dist >= 23.5:
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
	var cx: float = width / 2.0
	var cy: float = height / 2.0
	var dx: float = (x + 0.5) - cx
	var dy: float = (y + 0.5) - cy
	var dist: float = sqrt(dx * dx + dy * dy)
	# 将圆圈外围所有的空地都在碰撞/波及矩阵上视为不可通行的边界阻挡，增加物理安全系数
	if dist >= 24.5:
		return true
	return indestructibleMap[x][y]

# 判断指定格子是否为可破坏墙
func is_destructible_wall(x: int, y: int) -> bool:
	return _destructibleTiles.has(Vector2i(x, y))

# 销毁指定格子的可破坏墙并发出信号
func destroy_destructible_wall(x: int, y: int) -> void:
	_destructibleTiles.erase(Vector2i(x, y))
	erase_cell(Vector2i(x, y))
	wallDestroyed.emit(Vector2i(x, y))
