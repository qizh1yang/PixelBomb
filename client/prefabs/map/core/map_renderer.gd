# 地图美术瓦片渲染器
# 解析二维逻辑地图数据，并依据带权重的 MapThemeConfig 资源池进行随机瓦片绘制，实现逻辑与美术解耦
# 创建时间：2026-05-27

extends RefCounted

class_name MapRenderer

# 缓存的默认保底主题，如果策划在编辑器里没给分配 theme_config，则自动采用这组默认值，保障零崩溃
var _fallback_theme: MapThemeConfig = null

func _init() -> void:
	_fallback_theme = MapThemeConfig.new()
	_fallback_theme.theme_name = "DefaultSnow"
	_fallback_theme.floor_tiles = [
		{ "source": 1, "atlas": Vector2i(1, 1), "weight": 80.0 },
		{ "source": 1, "atlas": Vector2i(0, 4), "weight": 20.0 }
	]
	_fallback_theme.hard_wall_tiles = [
		{ "source": 1, "atlas": Vector2i(15, 9), "weight": 50.0 },
		{ "source": 1, "atlas": Vector2i(4, 13), "weight": 50.0 }
	]
	_fallback_theme.soft_wall_tiles = [
		{ "source": 1, "atlas": Vector2i(4, 15), "weight": 50.0 },
		{ "source": 1, "atlas": Vector2i(5, 15), "weight": 50.0 }
	]
	_fallback_theme.border_wall_tile = { "source": 0, "atlas": Vector2i(3, 2) }

# 核心渲染主入口
# wall_layer: 绘制硬墙和软墙的物理层
# floor_layer: 绘制地面背景的层 (可为空)
# map_data: 纯数据逻辑二维数组
# theme_config: 策划挂载的 MapThemeConfig 资源（可空）
func render_map(wall_layer: TileMapLayer, floor_layer: TileMapLayer, map_data: Array, width: int, height: int, theme_config: MapThemeConfig = null) -> void:
	if not is_instance_valid(wall_layer):
		push_error("[MAP_RENDERER] wall_layer is invalid!")
		return
		
	var active_theme = theme_config if theme_config != null else _fallback_theme
	print("[MAP_RENDERER] Starting to render %dx%d map using theme: %s" % [width, height, active_theme.theme_name])
	
	wall_layer.clear()
	if is_instance_valid(floor_layer):
		floor_layer.clear()
	
	for x in range(width):
		for y in range(height):
			var tile_coords = Vector2i(x, y)
			var grid_val = map_data[x][y]
			
			match grid_val:
				-1:
					# -1 = 虚空，彻底不做任何渲染（在 TileMapLayer 上留空）
					if is_instance_valid(floor_layer):
						floor_layer.erase_cell(tile_coords)
					wall_layer.erase_cell(tile_coords)
					
				0, 3:
					# 0 = 空地，3 = 出生点（出生点底层也是地板）
					var floor_def = active_theme.pick_tile(active_theme.floor_tiles, { "source": 1, "atlas": Vector2i(1, 1) })
					if is_instance_valid(floor_layer):
						floor_layer.set_cell(tile_coords, floor_def.source, floor_def.atlas)
					else:
						wall_layer.set_cell(tile_coords, floor_def.source, floor_def.atlas)
					
				1:
					# 1 = 不可破坏硬墙
					# 检测上下左右邻居是否是虚空或出界
					var is_up_void = y == 0 or map_data[x][y - 1] == -1
					var is_down_void = y == height - 1 or map_data[x][y + 1] == -1
					var is_left_void = x == 0 or map_data[x - 1][y] == -1
					var is_right_void = x == width - 1 or map_data[x + 1][y] == -1
					
					if is_up_void or is_down_void or is_left_void or is_right_void:
						# 这是悬浮在虚空边缘的边界悬崖/护栏
						var border_def = active_theme.border_wall_tile
						var source_id = border_def.source
						var atlas_coord = border_def.atlas
						
						# 根据邻近虚空的朝向，进行图元 Atlas 偏移以形成 Autotile 自适应悬崖
						if is_up_void:
							atlas_coord = border_def.atlas
						elif is_down_void:
							atlas_coord = Vector2i(border_def.atlas.x, border_def.atlas.y + 1)
						elif is_left_void:
							atlas_coord = Vector2i(border_def.atlas.x - 1, border_def.atlas.y)
						elif is_right_void:
							atlas_coord = Vector2i(border_def.atlas.x + 1, border_def.atlas.y)
							
						wall_layer.set_cell(tile_coords, source_id, atlas_coord)
					else:
						# 普通内部立柱
						var wall_def = active_theme.pick_tile(active_theme.hard_wall_tiles, { "source": 1, "atlas": Vector2i(15, 9) })
						wall_layer.set_cell(tile_coords, wall_def.source, wall_def.atlas)
						
				2:
					# 2 = 可破坏箱子
					var box_def = active_theme.pick_tile(active_theme.soft_wall_tiles, { "source": 1, "atlas": Vector2i(4, 15) })
					wall_layer.set_cell(tile_coords, box_def.source, box_def.atlas)
					
				4:
					# 4 = 特殊地貌
					var spec_def = active_theme.pick_tile(active_theme.special_tiles, { "source": 1, "atlas": Vector2i(0, 14) })
					wall_layer.set_cell(tile_coords, spec_def.source, spec_def.atlas)
					
				5:
					# 5 = 撤离点传送门
					var ext_def = active_theme.extraction_tile
					if is_instance_valid(floor_layer):
						floor_layer.set_cell(tile_coords, ext_def.source, ext_def.atlas)
					else:
						wall_layer.set_cell(tile_coords, ext_def.source, ext_def.atlas)
						
	print("[MAP_RENDERER] Map rendering completed successfully.")


