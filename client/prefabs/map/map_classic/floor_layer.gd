# 经典地图地板层生成器
# 随机铺设三种地板瓦片
# 创建时间：2026-05-06

extends "res://prefabs/map/map_classic/floor_layer_yuansu.gd"

class_name FloorLayerClassic

# ── 导出变量 ──
@export_group("Map Settings")
@export var width: int = 15
@export var height: int = 11

func _ready() -> void:
	pass

# 初始化并生成地板
# seedVal：随机种子
func initialize_map(seedVal: int) -> void:
	seed(seedVal)
	clear()

	for x: int in range(width):
		for y: int in range(height):
			var r: int = randi() % 100
			if r < 90:
				cell_rode(x, y, MAP_FLOOR1)
			elif r < 95:
				cell_rode(x, y, MAP_FLOOR2)
			else:
				cell_rode(x, y, MAP_FLOOR3)
