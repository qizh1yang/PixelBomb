# 房间卡片逻辑
extends PanelContainer

signal join_pressed()

@onready var roomID: Label = %RoomID
@onready var playerCount: Label = %PlayerCount
@onready var hostName: Label = %HostName
@onready var statusLabel: Label = %StatusLabel
@onready var joinBtn: Button = %JoinBtn

func setup(data: Dictionary) -> void:
	roomID.text = "#" + str(data.get("name", "0000"))
	var count = data.get("player_count", 1)
	playerCount.text = "%d/4 人" % count
	if count >= 4:
		playerCount.add_theme_color_override("font_color", Color("#4ADE80"))
	else:
		playerCount.remove_theme_color_override("font_color")
	
	hostName.text = "队长：" + str(data.get("host_name", "Unknown"))
	
	var in_game = data.get("in_game", false)
	if in_game:
		statusLabel.text = "● 进行中"
		statusLabel.modulate = Color("#888888")
		joinBtn.disabled = true
		joinBtn.text = "进行中"
	else:
		statusLabel.text = "● 等待中"
		statusLabel.modulate = Color("#F5A623")
		joinBtn.disabled = false
		joinBtn.text = "加入任务"

func _on_join_btn_pressed() -> void:
	join_pressed.emit()
