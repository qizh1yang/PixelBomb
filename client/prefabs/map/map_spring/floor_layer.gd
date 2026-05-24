extends "res://prefabs/map/map_spring/floor_layer_yuansu.gd"

@export_group("Map Settings")
@export var width: int = 26
@export var height: int = 26

func initialize_map(_seed_val: int) -> void:
	clear()
	# 程序化填充地板
	for x in range(width):
		for y in range(height):
			var floor_def = _get_random_floor()
			set_cell(Vector2i(x, y), floor_def.source, floor_def.atlas)


func _get_random_floor() -> Dictionary:
	var r = randf()
	if r < 0.8:
		return MAP_FLOOR1 # 主要地板
	elif r < 0.9:
		return MAP_FLOOR2 # 装饰1
	else:
		return MAP_FLOOR3 # 装饰2


func is_wall_at(x: int, y: int) -> bool:
	# 检查是否有墙（通过检查 wallLayer）
	var wall_layer = get_parent().get_node_or_null("wallLayer")
	if wall_layer:
		return wall_layer.is_indestructible(x, y) or wall_layer.is_destructible_wall(x, y)
	return false
