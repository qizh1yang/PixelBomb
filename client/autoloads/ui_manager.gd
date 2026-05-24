extends Node

signal scene_changed(scene_name: String)

var current_scene_name: String = ""

# 场景路径注册表
var scenes = {
	"login": "res://scenes/Login/login.tscn",
	"lobby": "res://scenes/Lobby/lobby.tscn",
	"warehouse": "res://scenes/Warehouse/warehouse.tscn",
	"backpack_config": "res://scenes/Warehouse/backpack_config.tscn",
	"room": "res://scenes/Room/room.tscn",
	"game": "res://stages/game_stage.tscn"
}

func _ready() -> void:
	# 记录初始场景
	var root = get_tree().root
	current_scene_name = root.get_child(root.get_child_count() - 1).name

# 切换场景 (带转场效果预留)
func change_scene(scene_id: String) -> void:
	if not scenes.has(scene_id):
		push_error("Scene ID not found: " + scene_id)
		return
		
	print("[UIManager] Switching to scene: ", scene_id)
	get_tree().change_scene_to_file(scenes[scene_id])
	current_scene_name = scene_id
	scene_changed.emit(scene_id)

# 弹出通用提示框 (简易版)
func show_message(title: String, message: String) -> void:
	# 这里可以实例化一个通用的 Modal 场景
	print("[UI_MESSAGE] %s: %s" % [title, message])

# 弹出结算面板 (由 GameMode 调用)
func show_settlement(is_winner: bool, winner_name: String) -> void:
	var result_scene = load("res://ui/result_panel/result_panel.tscn")
	if result_scene:
		var inst = result_scene.instantiate()
		get_tree().root.add_child(inst)
		if inst.has_method("setup"):
			inst.setup(is_winner)
