# 独立仓库界面逻辑
extends Control

@onready var grid: GridContainer = %ItemGrid
@onready var coinsLabel: Label = %CoinsLabel
@onready var itemCountLabel: Label = %ItemCount
@onready var tabHBox: HBoxContainer = %TabHBox

var ItemCardScene = preload("res://scenes/Warehouse/sub/item_card.tscn")
var current_category: int = -1 # -1 means ALL

func _ready() -> void:
	GlobalPlayerData.inventory_updated.connect(_refresh_ui)
	_setup_tabs()
	_refresh_ui()

func _setup_tabs() -> void:
	var tab_names = ["All", "Bomb", "Speed", "Range", "Special"]
	var tab_categories = [-1, 0, 1, 2, 3]
	for child in tabHBox.get_children():
		if child is Button:
			var idx = child.get_index()
			if idx < tab_categories.size():
				child.pressed.connect(_on_tab_pressed.bind(tab_categories[idx]))

func _refresh_ui() -> void:
	coinsLabel.text = "💰 %s" % _format_number(GlobalPlayerData.coins)
	itemCountLabel.text = "%d 件物资" % GlobalPlayerData.owned_items.size()
	_update_grid()
	_update_filter_styles()

func _update_grid() -> void:
	for child in grid.get_children():
		child.queue_free()

	for res_path in GlobalPlayerData.owned_items:
		var res = load(res_path) as BackpackItemResource
		if not res: continue

		# 过滤类别
		if current_category != -1 and int(res.category) != current_category:
			continue

		var card = ItemCardScene.instantiate()
		grid.add_child(card)
		card.setup(res, res_path)
		# 独立仓库中，装包按钮变为"前往战备"
		card.pack_requested.connect(_on_pack_from_warehouse)
		card.sell_requested.connect(_on_sell_requested)

func _on_tab_pressed(category: int) -> void:
	current_category = category
	_update_filter_styles()
	_update_grid()

func _update_filter_styles() -> void:
	var categories = [-1, 0, 1, 2, 3]
	for child in tabHBox.get_children():
		if child is Button:
			var idx = child.get_index()
			if idx < categories.size():
				var is_active = (categories[idx] == current_category)
				if is_active:
					child.add_theme_color_override("font_color", Color(0.2, 0.15, 0.05, 1))
					var style = StyleBoxFlat.new()
					style.bg_color = Color(0.831373, 0.686275, 0.215686, 0.9)
					style.corner_radius_top_left = 6
					style.corner_radius_top_right = 6
					style.corner_radius_bottom_right = 6
					style.corner_radius_bottom_left = 6
					child.add_theme_stylebox_override("normal", style)
				else:
					child.add_theme_color_override("font_color", Color(0.549, 0.647, 0.788, 1))
					var style = StyleBoxFlat.new()
					style.bg_color = Color(0.075, 0.118, 0.196, 0.6)
					style.border_color = Color(0.227, 0.294, 0.423, 0.4)
					style.set_border_width_all(1)
					style.corner_radius_top_left = 6
					style.corner_radius_top_right = 6
					style.corner_radius_bottom_right = 6
					style.corner_radius_bottom_left = 6
					child.add_theme_stylebox_override("normal", style)

func _on_pack_from_warehouse(res: BackpackItemResource, path: String) -> void:
	# 独立仓库点击"装包" → 跳转到战前战备场景
	UIManager.change_scene("backpack_config")

func _on_sell_requested(res: BackpackItemResource, path: String) -> void:
	# 独立仓库中直接售出（简化版，不弹确认弹窗）
	var price = _calculate_sell_price(res)
	GlobalPlayerData.sell_item(path, price)
	print("[Warehouse] 已售出: %s, 获得 %d 金币" % [res.item_name, price])

func _calculate_sell_price(res: BackpackItemResource) -> int:
	var value = 0
	value += res.bomb_cap_boost * 50
	value += res.radius_cap_boost * 60
	value += res.radius_up_boost * 40
	value += res.radius_down_boost * 40
	value += res.radius_left_boost * 40
	value += res.radius_right_boost * 40
	value += int(res.speed_cap_boost * 30)
	value += res.shield_cap_boost * 80
	if res.has_persistent_shield: value += 200
	value += res.shape.size() * 10
	value = max(value, 10)
	match res.rarity:
		1: value *= 2
		2: value *= 4
	return value

func _on_close_pressed() -> void:
	hide()
	if get_tree().current_scene == self:
		UIManager.change_scene("lobby")

func _on_goto_config_pressed() -> void:
	UIManager.change_scene("backpack_config")

func _format_number(n: int) -> String:
	var s = str(n)
	var result = ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result
