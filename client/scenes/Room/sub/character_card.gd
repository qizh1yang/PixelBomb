# 角色选择卡片
extends Button

@onready var avatar: TextureRect = $HBoxContainer/Avatar
@onready var nameLabel: Label = $HBoxContainer/VBoxContainer/NameLabel
@onready var descLabel: Label = %DescLabel

var char_index: int = 0

func setup(idx: int, char_name: String, char_desc: String, texture: Texture) -> void:
	char_index = idx
	nameLabel.text = char_name
	descLabel.text = char_desc
	if texture:
		avatar.texture = texture

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
