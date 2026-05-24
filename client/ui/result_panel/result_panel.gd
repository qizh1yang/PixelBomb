# 游戏结算面板
# 展示撤离成功或失败的状态，并提供返回大厅的按钮
# 创建时间：2026-05-09

extends CanvasLayer

# ── 节点引用 ──
@onready var titleLabel: Label = %Title
@onready var descLabel: Label = %Description
@onready var icon: TextureRect = %Icon
@onready var backButton: Button = %BackButton

func _ready() -> void:
	backButton.pressed.connect(_onBackButtonPressed)

# 设置结算状态
# isSuccess：是否撤离成功
func setup(isSuccess: bool) -> void:
	if isSuccess:
		titleLabel.text = "撤离成功"
		titleLabel.add_theme_color_override("font_color", Color.GOLD)
		descLabel.text = "你已成功带回所有搜刮到的物资！"
		# 这里可以根据是否有图标资源设置 icon.texture
	else:
		titleLabel.text = "撤离失败"
		titleLabel.add_theme_color_override("font_color", Color.RED)
		descLabel.text = "你在战斗中失踪或未能按时到达撤离点，物资全部丢失。"

func _onBackButtonPressed() -> void:
	# 先通知服务器离开房间 (Stash/Global Lobby)
	var net = get_node_or_null("/root/NetworkManager")
	if net:
		net.leave_room()
	
	# 重置全局游戏状态
	GameMode.cleanup_game()
	
	# 切换场景
	get_tree().change_scene_to_file("res://scenes/Lobby/lobby.tscn")
