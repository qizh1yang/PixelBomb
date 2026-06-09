# 经典地图地板层生成器
# 随机铺设三种地板瓦片
# 创建时间：2026-05-06

extends "res://prefabs/map/map_classic/floor_layer_yuansu.gd"

class_name FloorLayerClassic

# ── 导出变量 ──
@export_group("Map Settings")
@export var width: int = 49
@export var height: int = 49

func _ready() -> void:
	pass

# 初始化并生成地板
# seedVal：随机种子
func initialize_map(seedVal: int) -> void:
	seed(seedVal)
	clear()

	var cx: float = width / 2.0
	var cy: float = height / 2.0

	for x: int in range(width):
		for y: int in range(height):
			var dx: float = (x + 0.5) - cx
			var dy: float = (y + 0.5) - cy
			var dist: float = sqrt(dx * dx + dy * dy)
			
			# 精准判定：仅在圆形可通行区和外圈围栏区（共 R < 24.5）生成地板，圆外区域不生成
			if dist < 24.5:
				var r_val: int = randi() % 100
				if r_val < 90:
					cell_rode(x, y, MAP_FLOOR1)
				elif r_val < 95:
					cell_rode(x, y, MAP_FLOOR2)
				else:
					cell_rode(x, y, MAP_FLOOR3)
