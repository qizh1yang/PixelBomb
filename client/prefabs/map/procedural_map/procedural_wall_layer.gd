# 程序化物理碰撞墙体与箱子层
# 完美对齐老旧 wall_layer 的全部 API，对外派发破坏信号，完美响应联机数据同步 import_map_data()
# 创建时间：2026-05-27

extends TileMapLayer

class_name ProceduralWallLayer

# 局内障碍破坏信号（供 Spawner 监听掉落及 GameMode 监听特效）
signal wallDestroyed(cellPos: Vector2i)

var width: int = 25
var height: int = 25
var map_data: Array = []
var spawn_points: Array[Vector2i] = []
var extraction_point: Vector2i = Vector2i(-1, -1)

# 地图美术风格（用于联机反序列化时自动重新渲染）
var theme_config: MapThemeConfig = null

func _ready() -> void:
	add_to_group("WallLayer")

# 设置二维逻辑数据和尺寸
func setup_logical_data(p_map_data: Array, p_spawns: Array[Vector2i], w: int, h: int, theme: MapThemeConfig = null) -> void:
	map_data = p_map_data
	spawn_points = p_spawns
	width = w
	height = h
	theme_config = theme

# 判定是否不可破坏硬墙 (1 或者超出地图网格边界，或者为虚空 -1)
func is_indestructible(x: int, y: int) -> bool:
	if x < 0 or x >= width or y < 0 or y >= height:
		return true
	if map_data.is_empty():
		return false
	return map_data[x][y] == 1 or map_data[x][y] == -1


# 判定是否可破坏墙 (2)
func is_destructible_wall(x: int, y: int) -> bool:
	if x < 0 or x >= width or y < 0 or y >= height:
		return false
	if map_data.is_empty():
		return false
	return map_data[x][y] == 2

# 破坏可破坏箱子，将其设为空地，清除 Tile 瓦片并向外广播
func destroy_destructible_wall(x: int, y: int) -> void:
	if is_destructible_wall(x, y):
		map_data[x][y] = 0 # 擦除为普通空地
		erase_cell(Vector2i(x, y))
		wallDestroyed.emit(Vector2i(x, y))

# [NET] 联机模式下导入服务端下发的权威地图数据并触发反序列化渲染
func import_map_data(data: Array) -> void:
	if data.is_empty(): return
	
	width = data.size()
	height = data[0].size()
	
	map_data.clear()
	map_data.resize(width)
	for x in range(width):
		map_data[x] = []
		for y in range(height):
			map_data[x].append(data[x][y])
			
	# 反向提取出生点坐标 (值为 3 的网格) 与撤离点 (值为 5 的网格)
	spawn_points.clear()
	extraction_point = Vector2i(-1, -1)
	for x in range(width):
		for y in range(height):
			if map_data[x][y] == 3:
				spawn_points.append(Vector2i(x, y))
			elif map_data[x][y] == 5:
				extraction_point = Vector2i(x, y)
				
	print("[NET-SYNC] Authoritative map data synced! Re-rendering %dx%d map layout..." % [width, height])
	
	# 调用解耦渲染器执行重新上色绘制
	var renderer = MapRenderer.new()
	var floor_layer = get_parent().get_node_or_null("FloorLayer")
	renderer.render_map(self, floor_layer, map_data, width, height, theme_config)
