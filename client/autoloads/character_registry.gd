extends Node

var characters: Dictionary = {}  # id -> CharacterResource

func _ready() -> void:
	_scan_characters()

# 自动扫描资源目录
func _scan_characters() -> void:
	var path = "res://resources/characters/"
	var dir = DirAccess.open(path)
	if not dir:
		DirAccess.make_dir_recursive_absolute(path)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res = load(path + file_name) as CharacterResource
			if res:
				register_character(res)
		file_name = dir.get_next()
	
	print("[CharacterRegistry] Registered %d characters" % characters.size())

func register_character(res: CharacterResource) -> void:
	characters[res.character_id] = res

func get_character(id: String) -> CharacterResource:
	return characters.get(id)

func get_all_characters() -> Array:
	var list = characters.values()
	list.sort_custom(func(a, b): return a.char_index < b.char_index)
	return list

func get_character_by_index(idx: int) -> CharacterResource:
	for char in characters.values():
		if char.char_index == idx:
			return char
	return null
