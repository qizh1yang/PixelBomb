extends Node

var characters: Dictionary = {}  # id -> CharacterResource

func _ready() -> void:
	_scan_characters()

# 自动扫描资源目录
func _scan_characters() -> void:
	var path = "res://resources/characters/"
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
				var clean_name = file_name.replace(".remap", "")
				var res = load(path + clean_name) as CharacterResource
				if res:
					register_character(res)
			file_name = dir.get_next()
	
	# Web 端等特殊环境 Fallback 机制：如果扫描不到任何角色资源，则直接加载硬编码的预定义资源
	if characters.is_empty():
		var fallback_files = ["player1.tres", "player2.tres", "player3.tres", "player4.tres"]
		for fname in fallback_files:
			var full_path = path + fname
			var res = load(full_path) as CharacterResource
			if res:
				register_character(res)
	
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
