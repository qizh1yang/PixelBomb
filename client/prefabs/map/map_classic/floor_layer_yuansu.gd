# TileMap 元素常量与工具基类
# 定义地板、不可破坏墙、可破坏墙的瓦片常量以及通用绘制方法
# 创建时间：2026-05-06

extends TileMapLayer

class_name FloorLayerBase

# ── 地板瓦片 ──
var MAP_FLOOR1: Dictionary = { "source": 1, "atlas": Vector2i(1, 1) }
var MAP_FLOOR2: Dictionary = { "source": 1, "atlas": Vector2i(0, 4) }
var MAP_FLOOR3: Dictionary = { "source": 1, "atlas": Vector2i(1, 4) }

# ── 不可破坏墙瓦片 ──
var MAP_Indestructible_WALL1: Dictionary = { "source": 1, "atlas": Vector2i(15, 9) }
var MAP_Indestructible_WALL2: Dictionary = { "source": 1, "atlas": Vector2i(4, 13) }
var MAP_Indestructible_WALL3: Dictionary = { "source": 0, "atlas": Vector2i(3, 2) }

# ── 可破坏墙瓦片 ──
var MAP_Destructible_WALL1: Dictionary = { "source": 1, "atlas": Vector2i(4, 15) }
var MAP_Destructible_WALL2: Dictionary = { "source": 1, "atlas": Vector2i(5, 15) }
var MAP_Destructible_WALL3: Dictionary = { "source": 1, "atlas": Vector2i(0, 14) }

# 设置指定格子的瓦片
# x：列坐标；y：行坐标；rodes：包含 source 与 atlas 的瓦片定义字典
func cell_rode(x: int, y: int, rodes: Dictionary) -> void:
	set_cell(Vector2i(x, y), rodes.source, rodes.atlas)
