# 角色选择卡片
extends Button

@onready var avatar: TextureRect = $HBoxContainer/Avatar
@onready var nameLabel: Label = $HBoxContainer/VBoxContainer/NameLabel
@onready var descLabel: Label = %DescLabel

var char_index: int = 0

func setup(idx: int, char_name: String, texture: Texture) -> void:
	char_index = idx
	nameLabel.text = char_name
	avatar.texture = texture
	
	# 根据职业索引，动态装载 14px 灰度技能描述信息
	var descriptions = [
		"擅长火焰伤害，极致高爆发",
		"冰霜控制，大范围减速与冰冻",
		"自然治愈，持续恢复与团队增益",
		"虚空穿梭，高机动性与瞬移突袭"
	]
	if idx >= 0 and idx < descriptions.size():
		descLabel.text = descriptions[idx]
	else:
		descLabel.text = "破壁者特殊作战单元"

func set_selected(is_selected: bool) -> void:
	if is_selected:
		var selected_style = load("res://scenes/Room/sub/card_selected.tres")
		add_theme_stylebox_override("normal", selected_style)
		add_theme_stylebox_override("hover", selected_style)
		add_theme_stylebox_override("pressed", selected_style)
	else:
		remove_theme_stylebox_override("normal")
		remove_theme_stylebox_override("hover")
		remove_theme_stylebox_override("pressed")
