# 玩家列表槽位
extends PanelContainer

# ── 交互信号 ──
signal invite_clicked

@onready var avatar: TextureRect = %Avatar
@onready var nameLabel: Label = %PlayerName
@onready var roleTag: Label = %RoleTag
@onready var charNameLabel: Label = %CharName
@onready var statusDot: ColorRect = %StatusDot
@onready var statusText: Label = %StatusText
@onready var selfMarker: ColorRect = $SelfMarker
@onready var invisibleBtn: Button = %InvisibleButton

func _ready() -> void:
	invisibleBtn.pressed.connect(_on_invisible_btn_pressed)

func set_empty() -> void:
	%OccupiedContent.hide()
	%EmptyContent.show()
	selfMarker.hide()
	modulate.a = 0.6
	
	# 空槽位时，允许透明按钮交互以一键邀请好友
	invisibleBtn.show()
	invisibleBtn.mouse_filter = Control.MOUSE_FILTER_STOP

func set_player(data: Dictionary, is_self: bool, is_host_of_room: bool) -> void:
	%OccupiedContent.show()
	%EmptyContent.hide()
	modulate.a = 1.0
	
	# 被占领时，隐藏并禁用透明按钮
	invisibleBtn.hide()
	invisibleBtn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	nameLabel.text = data.get("name", "Unknown")
	var char_idx = data.get("char", 0)
	charNameLabel.text = _get_char_name(char_idx)
	avatar.texture = _get_char_avatar(char_idx)
	
	var is_host = data.get("is_host", false)
	roleTag.text = "队长" if is_host else "队员"
	roleTag.add_theme_color_override("font_color", Color("#F5A623") if is_host else Color("#A0A0B0"))
	
	var is_ready = data.get("ready", false)
	if is_ready:
		statusDot.color = Color("#5CDB6F")
		statusText.text = "已准备"
		statusText.add_theme_color_override("font_color", Color("#5CDB6F"))
	else:
		statusDot.color = Color("#888888")
		statusText.text = "未准备"
		statusText.add_theme_color_override("font_color", Color("#888888"))
		
	selfMarker.visible = is_self

func _on_invisible_btn_pressed() -> void:
	invite_clicked.emit()

func _get_char_name(idx: int) -> String:
	var names = ["烈焰破壁者", "寒冰破壁者", "自然破壁者", "虚空破壁者"]
	if idx >= 0 and idx < names.size(): return names[idx]
	return "Player %d" % (idx + 1)

func _get_char_avatar(idx: int) -> Texture:
	var path = "res://prefabs/Players/player%d/res/Idle.png" % (idx + 1)
	if ResourceLoader.exists(path):
		return load(path)
	return null
