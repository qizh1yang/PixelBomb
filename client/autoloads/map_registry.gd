extends Node

var maps: Dictionary = {} # id -> MapResource

func _ready() -> void:
	_scan_maps()

func _scan_maps() -> void:
	var path = "res://resources/maps/"
	var dir = DirAccess.open(path)
	if not dir:
		DirAccess.make_dir_recursive_absolute(path)
		return
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res = load(path + file_name) as MapResource
			if res:
				register_map(res)
		file_name = dir.get_next()
	
	print("[MapRegistry] Registered %d maps" % maps.size())

func register_map(res: MapResource) -> void:
	maps[res.map_id] = res

func get_map(id: String) -> MapResource:
	return maps.get(id)

func get_all_maps() -> Array:
	return maps.values()
