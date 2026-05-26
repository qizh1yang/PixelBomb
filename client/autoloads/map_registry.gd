extends Node

var maps: Dictionary = {} # id -> MapResource

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
	
	# Web 端等特殊环境 Fallback 机制：如果扫描不到任何地图资源，则直接加载硬编码的预定义资源
	if maps.is_empty():
		var fallback_files = ["classic.tres", "spring.tres", "winter.tres"]
		for fname in fallback_files:
			var full_path = path + fname
			var res = load(full_path) as MapResource
			if res:
				register_map(res)
	
	print("[MapRegistry] Registered %d maps" % maps.size())

func register_map(res: MapResource) -> void:
	maps[res.map_id] = res

func get_map(id: String) -> MapResource:
	return maps.get(id)

func get_all_maps() -> Array:
	return maps.values()
