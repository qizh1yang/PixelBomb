# 仓库物品卡片
extends Button

@onready var vbox: VBoxContainer = %VBox
@onready var iconRect: TextureRect = %Icon
@onready var nameLabel: Label = %ItemName
@onready var infoLabel: Label = %InfoLabel

var resource: BackpackItemResource
var res_path: String = ""
var isDragging: bool = false
var active_drag_preview: Control = null

# 信号
signal pack_requested(res: BackpackItemResource, path: String)
signal sell_requested(res: BackpackItemResource, path: String)
signal detail_requested(res: BackpackItemResource)

func _ready() -> void:
	pass

func setup(res: BackpackItemResource, path: String = "") -> void:
	resource = res
	res_path = path if path != "" else res.resource_path
	nameLabel.text = res.item_name
	iconRect.texture = res.icon

	# 设置稀有度颜色
	var rarity_color = res.get_rarity_color()
	nameLabel.add_theme_color_override("font_color", rarity_color)

	# 给边框上色
	var style = get_theme_stylebox("normal")
	if style is StyleBoxFlat:
		var new_style = style.duplicate()
		new_style.border_color = rarity_color
		new_style.border_color.a = 0.5
		add_theme_stylebox_override("normal", new_style)
		add_theme_stylebox_override("hover", new_style)

	# 计算形状描述
	var min_x = 99; var max_x = -99; var min_y = 99; var max_y = -99
	for p in res.shape:
		min_x = min(min_x, p.x); max_x = max(max_x, p.x)
		min_y = min(min_y, p.y); max_y = max(max_y, p.y)
	var w = max_x - min_x + 1
	var h = max_y - min_y + 1
	var shape_text = "%dx%d" % [w, h]

	# 计算效果描述
	var effect = _get_effect_text(res)
	infoLabel.text = "%s · %s" % [shape_text, effect] if effect != "" else shape_text

func _get_effect_text(res: BackpackItemResource) -> String:
	if res.bomb_cap_boost > 0: return "炸弹+%d" % res.bomb_cap_boost
	elif res.speed_cap_boost > 0: return "速度+%.0f%%" % (res.speed_cap_boost * 100)
	elif res.radius_cap_boost > 0: return "范围+%d" % res.radius_cap_boost
	elif res.radius_up_boost > 0: return "威力(上)+%d" % res.radius_up_boost
	elif res.radius_down_boost > 0: return "威力(下)+%d" % res.radius_down_boost
	elif res.radius_left_boost > 0: return "威力(左)+%d" % res.radius_left_boost
	elif res.radius_right_boost > 0: return "威力(右)+%d" % res.radius_right_boost
	elif res.shield_cap_boost > 0: return "护盾+%d" % res.shield_cap_boost
	elif res.has_persistent_shield: return "免死护盾"
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			detail_requested.emit(resource)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# 右键弹出快捷菜单 (暂时触发售出以便测试)
			sell_requested.emit(resource, res_path)

func _on_mouse_entered() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", -4.0, 0.1).as_relative()
	tween.tween_property(self, "scale", Vector2(1.03, 1.03), 0.1)

func _on_mouse_exited() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", 4.0, 0.1).as_relative()
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)

# [AI MODIFY]
func _add_preview_to_drag_layer(preview: Control) -> void:
	if is_instance_valid(active_drag_preview):
		active_drag_preview.queue_free()
	active_drag_preview = null
	
	var drag_layer = null
	if get_tree() and get_tree().root:
		drag_layer = get_tree().root.get_node_or_null("GameStage/DragPreviewLayer")
		if not drag_layer:
			drag_layer = get_tree().root.get_node_or_null("MainUI/DragPreviewLayer")
		if not drag_layer:
			drag_layer = get_tree().root.get_node_or_null("DynamicDragPreviewLayer")
			if not drag_layer:
				drag_layer = CanvasLayer.new()
				drag_layer.name = "DynamicDragPreviewLayer"
				drag_layer.layer = 128
				get_tree().root.add_child(drag_layer)
				
	if drag_layer:
		drag_layer.add_child(preview)
		preview.top_level = true
		# [AI MODIFY]
		preview.z_index = 4096
		active_drag_preview = preview
		preview.global_position = get_global_mouse_position()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		isDragging = false
		if is_instance_valid(active_drag_preview):
			active_drag_preview.queue_free()
			active_drag_preview = null

func _process(_delta: float) -> void:
	if isDragging and is_instance_valid(active_drag_preview):
		active_drag_preview.global_position = get_global_mouse_position()

func _get_drag_data(_atPosition: Vector2) -> Variant:
	var preview: Control = Control.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 动态创建局内网格项作为拖拽预览，让玩家一眼看清道具占地几格，彻底拉满游戏感！
	var bp_item_scene = load("res://prefabs/Backpack/sub/backpack_item.tscn")
	var dummy = bp_item_scene.instantiate()
	dummy.setup(resource)
	
	# 设置其半透明效果，以完美的网格项视觉进行拖拽预览
	dummy.modulate.a = 0.7
	
	# 网格定位常数匹配 CELL_SIZE=64, SPACING=8, 步长为 72px
	var step = 64 + 8
	
	# 根据物品形状尺寸计算其物理像素尺寸
	var min_x = 99; var max_x = -99; var min_y = 99; var max_y = -99
	for p in resource.shape:
		min_x = min(min_x, p.x); max_x = max(max_x, p.x)
		min_y = min(min_y, p.y); max_y = max(max_y, p.y)
	var w = max_x - min_x + 1
	var h = max_y - min_y + 1
	var item_size = Vector2(w * step - 8, h * step - 8)
	
	dummy.custom_minimum_size = item_size
	dummy.size = item_size
	
	# 抓取中心点对齐，极佳的吸附手感
	var pickup_offset = item_size / 2.0
	
	var wrapper = Control.new()
	wrapper.size = item_size
	wrapper.position = -pickup_offset
	wrapper.add_child(dummy)
	
	preview.add_child(wrapper)
	
	# 递归设置所有预览控制节点的鼠标过滤器为 IGNORE，100% 确保其不会阻挡下方的网格接收拖拽悬停事件！
	_set_preview_mouse_ignore(preview)
	
	isDragging = true
	_add_preview_to_drag_layer(preview)
	
	return {
		"type": "item_card",
		"resource": resource,
		"source_path": res_path,
		"pickup_offset": pickup_offset,
		"card_node": self
	}

func _set_preview_mouse_ignore(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_preview_mouse_ignore(child)
