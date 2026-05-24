# 经典地图控制器
# 负责协调 FloorLayer 与 WallLayer 的初始化，广播地图生成完成信号
# 创建时间：2026-05-09

extends Node2D

class_name MapClassic

## 地图生成完成信号，携带本次使用的随机种子
signal map_generated(seed_val: int)

# ── 导出变量 ──
@export_group("Map Config")
@export var map_width: int = 25
@export var map_height: int = 25

# ── 私有成员变量 ──
var is_offline_mode: bool = false
var _map_seed: int = 0
var _map_ready: bool = false

# ── 节点引用 ──
@onready var wall_layer: TileMapLayer = $wallLayer
@onready var floor_bg: TileMapLayer = $FloorLayer


func _ready() -> void:
	randomize()
	_generate_map_with_seed()


# 根据网络状态决定使用服务器种子还是本地随机种子
func _generate_map_with_seed() -> void:
	var net: Node = get_node_or_null("/root/NetworkManager")
	if net and net.is_connected_to_host:
		if net.seed_received:
			_generate_map(net.map_seed)
		else:
			net.room_joined.connect(_on_seed_received, CONNECT_ONE_SHOT)
	else:
		is_offline_mode = true
		_map_seed = int(Time.get_unix_time_from_system())
		_generate_map(_map_seed)


# 收到服务器种子后触发地图生成
func _on_seed_received(_seed: int) -> void:
	var net: Node = get_node_or_null("/root/NetworkManager")
	if net:
		_generate_map(net.map_seed)


# 使用指定种子生成地图
# seed_val：随机种子，保证多端一致
func _generate_map(seed_val: int) -> void:
	_map_seed = seed_val

	# 同步尺寸到子层
	wall_layer.width = map_width
	wall_layer.height = map_height
	floor_bg.width = map_width
	floor_bg.height = map_height

	print("[MAP] Generating %dx%d classic map with Seed: %d" % [map_width, map_height, seed_val])

	wall_layer.initialize_map(seed_val)
	floor_bg.initialize_map(seed_val)

	_map_ready = true
	map_generated.emit(seed_val)
