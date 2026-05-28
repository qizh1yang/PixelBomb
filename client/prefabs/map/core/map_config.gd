# 策划程序化地图配置文件结构体
# 创建时间：2026-05-27

extends Resource

class_name MapConfig

@export_enum("circle", "hexagon", "star", "ring", "cave") var shape_type: String = "circle"
@export_enum("small", "medium", "large") var map_size: String = "small"
@export var noise_strength: float = 2.8
@export var wall_density: float = 0.25
@export var soft_wall_density: float = 0.38
@export var spawn_count: int = 4
