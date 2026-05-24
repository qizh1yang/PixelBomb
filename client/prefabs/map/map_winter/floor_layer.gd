extends "res://prefabs/map/map_winter/floor_layer_yuansu.gd"

@export_group("Map Settings")
@export var width: int = 26
@export var height: int = 26

func initialize_map(_seed_val: int) -> void:
	# 已改为手动绘制模式，不再通过代码生成地板
	# 如果需要在这里做一些地表装饰（如随机小草），可以在此添加逻辑
	pass


func is_wall_at(x: int, y: int) -> bool:
	# 检查是否有墙（通过检查 wallLayer）
	var wall_layer = get_parent().get_node_or_null("wallLayer")
	if wall_layer:
		return wall_layer.is_indestructible(x, y) or wall_layer.is_destructible_wall(x, y)
	return false
