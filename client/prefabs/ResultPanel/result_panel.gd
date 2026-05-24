# 结算面板逻辑模块
# 显示对局胜负结果并提供返回大厅按钮
# 创建时间：2026-05-08

extends Control

class_name ResultPanel

# ── 节点引用 ──
@onready var titleLabel: Label = $Panel/VBoxContainer/Title
@onready var messageLabel: Label = $Panel/VBoxContainer/Message
@onready var backButton: Button = $Panel/VBoxContainer/BackButton

func _ready() -> void:
	backButton.pressed.connect(_onLobbyButtonPressed)

# 显示胜负结果
# is_winner：本机玩家是否胜利
# winnerName：获胜玩家名称
func showResult(isWinner: bool, winnerName: String) -> void:
	if isWinner:
		titleLabel.text = "胜利！"
		titleLabel.modulate = Color.GOLD
		messageLabel.text = "你是最后的幸存者！"
	else:
		titleLabel.text = "失败"
		titleLabel.modulate = Color(0.9, 0.3, 0.3, 1)
		if winnerName == "No one":
			messageLabel.text = "平局！所有人都被炸飞了！"
		else:
			messageLabel.text = winnerName + " 赢得了比赛。"
	visible = true

# 返回大厅按钮回调
func _onLobbyButtonPressed() -> void:
	UIManager.change_scene("lobby")
