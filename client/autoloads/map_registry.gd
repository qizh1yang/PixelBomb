extends Node

# MapRegistry — 地图元数据统一注册中心
# 所有地图的 ID、名称、场景路径、程序化参数均由此处统一管理
# 客户端/服务端/JSON/RPC 全部使用字符串 Map ID（UPPERCASE）

var maps: Dictionary = {} # String map_id -> MapResource

# ── 合法地图类型（白名单验证） ──
const VALID_MAP_TYPES: Array[String] = ["CLASSIC", "WINTER", "PROCEDURAL"]
const VALID_SHAPES: Array[String] = ["circle", "hexagon", "star", "ring", "cave"]
const VALID_SIZES: Array[String] = ["small", "medium", "large"]

signal maps_registered()

func _ready() -> void:
	_scan_maps()

func _scan_maps() -> void:
	var path = "res://resources/maps/"
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
				var clean_name = file_name.replace(".remap", "")
				var res = load(path + clean_name) as MapResource
				if res:
					register_map(res)
			file_name = dir.get_next()

	# Fallback：如果文件系统扫描不到任何资源，硬编码加载
	if maps.is_empty():
		var fallback_files = ["classic.tres", "winter.tres", "procedural.tres"]
		for fname in fallback_files:
			var full_path = path + fname
			if ResourceLoader.exists(full_path):
				var res = load(full_path) as MapResource
				if res:
					register_map(res)

	print("[MapRegistry] Registered %d maps: %s" % [maps.size(), str(maps.keys())])
	maps_registered.emit()

func register_map(res: MapResource) -> void:
	# 规范化 ID 为大写
	var normalized_id = res.map_id.to_upper().strip_edges()
	res.map_id = normalized_id
	maps[normalized_id] = res
	print("[MapRegistry]   + %s -> %s" % [normalized_id, res.display_name])

func get_map(id: String) -> MapResource:
	var key = id.to_upper().strip_edges()
	return maps.get(key)

func get_all_maps() -> Array:
	return maps.values()

func get_all_map_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in maps.keys():
		ids.append(key)
	return ids

## 根据 map_id 获取场景路径（MapFactory 通过此方法查询）
func get_scene_path(map_id: String) -> String:
	var res = get_map(map_id)
	if res and res.map_scene:
		return res.map_scene.resource_path
	push_warning("[MapRegistry] No scene path for map_id: '%s'" % map_id)
	return ""

## 获取人类可读的地图名称
func get_display_name(map_id: String) -> String:
	var res = get_map(map_id)
	if res:
		return res.display_name
	return "未知地图"

## 检查 map_id 是否合法
func is_valid_map_type(map_id: String) -> bool:
	return map_id.to_upper().strip_edges() in VALID_MAP_TYPES

## 检查 shape 是否合法
func is_valid_shape(shape: String) -> bool:
	return shape in VALID_SHAPES

## 检查 size 是否合法
func is_valid_size(size: String) -> bool:
	return size in VALID_SIZES

## 获取程序化地图的默认参数
func get_procedural_defaults(map_id: String) -> Dictionary:
	var res = get_map(map_id)
	if res and res.is_procedural:
		return {
			"shape": res.default_shape,
			"size": res.default_map_size,
		}
	return {}
