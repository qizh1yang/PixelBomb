extends Node2D
## map_spring - 春季主题地图
## 模仿冬季地图，支持手绘布局和随机障碍物生成

signal map_generated(seed_val: int)

@export_group("Map Config")
@export var map_width: int = 26
@export var map_height: int = 26

var is_offline_mode: bool = false
var _map_seed: int = 0
var _map_ready: bool = false

@onready var wall_layer: TileMapLayer = $wallLayer
@onready var floor_bg: TileMapLayer = $FloorLayer


func _ready() -> void:
	_generate_map_with_seed()


func _generate_map_with_seed() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_connected_to_host:
		if net.seed_received:
			_generate_map(net.map_seed)
		else:
			net.room_joined.connect(_on_seed_received, CONNECT_ONE_SHOT)
	else:
		is_offline_mode = true
		_map_seed = int(Time.get_unix_time_from_system())
		_generate_map(_map_seed)


func _on_seed_received(_seed: int) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net:
		_generate_map(net.map_seed)


func _generate_map(seed_val: int) -> void:
	_map_seed = seed_val
	
	# 同步尺寸到子层
	wall_layer.width = map_width
	wall_layer.height = map_height
	
	print("[MAP_SPRING] Initializing spring map with Seed: %d" % [seed_val])
	
	# 生成地板
	floor_bg.initialize_map(seed_val)
	
	# 生成墙壁 (程序化生成)
	wall_layer.initialize_map(seed_val)
	
	_map_ready = true
	map_generated.emit(seed_val)
