@tool
extends Control

class_name BackpackItem

# ── 私有成员变量 ──
@export var resource: BackpackItemResource:
	set(val):
		resource = val
		# [AI MODIFY]
		if resource:
			runtime_shape = resource.shape.duplicate()
		_refresh_visuals()

# [AI MODIFY]
var runtime_shape: Array[Vector2i] = []
var gridPos: Vector2i = Vector2i(-1, -1)
var is_rotated: bool = false
var current_rotation: float = 0.0
var isDragging: bool = false
var dragOffset: Vector2 = Vector2.ZERO
var source_path: String = "" # 记录资源原始路径
# [AI MODIFY]
var instance_id: String = ""
var active_drag_data: Dictionary = {}
var active_drag_preview: Control = null

# ── 悬停提示框系统 ──
var tooltip_timer: SceneTreeTimer = null
var tooltip: Control = null

const CELL_SIZE: int = 64
const SPACING: int = 8

# ── 节点引用 ──
@onready var iconRect = %Icon
@onready var bgRect = %BG
@onready var nameLabel = %NameLabel
@onready var countLabel = %CountLabel

@export var item_count: int = 1:
	set(val):
		item_count = val
		if is_instance_valid(countLabel):
			if item_count > 1:
				countLabel.visible = true
				countLabel.text = str(item_count)
			else:
				countLabel.visible = false

func _ready() -> void:
	# 确保在进入场景树时刷新一次
	_refresh_visuals()
	add_to_group("BackpackItem")
	
	# 配置鼠标拾取并关联悬停系统
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)

# 初始化物品显示
func setup(res: BackpackItemResource, p_source_path: String = "") -> void:
	# 优先级：1. 显式传入的路径 2. 资源自带的路径 3. 当前已有的路径
	if p_source_path != "":
		source_path = p_source_path
	elif res.resource_path != "":
		source_path = res.resource_path
		
	# 使用 setter 触发刷新
	resource = res.duplicate()
	# [AI MODIFY]
	if resource:
		runtime_shape = resource.shape.duplicate()
	is_rotated = false
	current_rotation = 0.0
	# [AI MODIFY]
	if instance_id == "":
		instance_id = str(Time.get_ticks_usec()) + "_" + str(randi())

func _refresh_visuals() -> void:
	if not resource: return
	
	# 确保 UI 节点已准备好（防止 setup 在 _ready 前被调用时报错）
	if not is_node_ready(): return

	# [AI MODIFY]
	if runtime_shape.is_empty() and resource:
		runtime_shape = resource.shape.duplicate()

	var maxX: int = 0
	var maxY: int = 0
	for cell: Vector2i in runtime_shape:
		maxX = max(maxX, cell.x)
		maxY = max(maxY, cell.y)

	custom_minimum_size = Vector2((maxX + 1) * CELL_SIZE + maxX * SPACING, (maxY + 1) * CELL_SIZE + maxY * SPACING)
	size = custom_minimum_size
	
	if is_instance_valid(iconRect):
		if resource.icon:
			iconRect.texture = resource.icon
			iconRect.modulate = Color.WHITE
		else:
			# 兜底显示：使用默认图标并染色
			iconRect.texture = load("res://icon.svg")
			iconRect.modulate = resource.theme_color
			print("[BACKPACK_ITEM] Warning: Icon missing for item %s" % resource.item_name)
		
		# 动态调整图标为全拉伸，并向内缩进 10px margins，确保贴合任何格数的物品边框
		iconRect.set_anchors_preset(Control.PRESET_FULL_RECT)
		iconRect.offset_left = 10
		iconRect.offset_right = -10
		iconRect.offset_top = 10
		iconRect.offset_bottom = -10
		iconRect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		iconRect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		# 核心旋转轴心：使用物理 Control 的绝对几何中心作为轴心，保证旋转时对称不跑偏
		iconRect.pivot_offset = custom_minimum_size / 2.0
		iconRect.rotation = current_rotation
	
	if is_instance_valid(bgRect) and bgRect is Panel:
		var border_color = Color("#0078d4") # 默认稀有蓝
		var bg_color = Color(0.0, 0.47, 0.83, 0.1)
		var glow_effect = "blue_glow"

		var is_special_shield = (resource.shield_cap_boost > 0 or resource.has_persistent_shield)
		
		if is_special_shield:
			border_color = Color("#ff4444")
			bg_color = Color(1.0, 0.27, 0.27, 0.1)
			glow_effect = "pulse"
		else:
			match resource.rarity:
				0: # RARE
					border_color = Color("#0078d4")
					bg_color = Color(0.0, 0.47, 0.83, 0.1)
					glow_effect = "blue_glow"
				1: # EPIC
					border_color = Color("#a335ee")
					bg_color = Color(0.64, 0.21, 0.93, 0.1)
					glow_effect = "breathing"
				2: # DIAMOND
					border_color = Color("#ffd700")
					bg_color = Color(1.0, 0.84, 0.0, 0.1)
					glow_effect = "flickering"

		var style = StyleBoxFlat.new()
		style.bg_color = bg_color
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = border_color
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		
		# 添加内阴影/外发光模拟边缘明亮效果 (从 8px 优化为 12px 闪耀特效)
		style.shadow_color = Color(border_color.r, border_color.g, border_color.b, 0.35)
		style.shadow_size = 12
		bgRect.add_theme_stylebox_override("panel", style)
		
		# 处理特有品质的微动效/呼吸发光 (仅在游戏运行时，且匹配有效动效时，防止编辑器内死循环或空 Tween 报错)
		if not Engine.is_editor_hint() and glow_effect in ["breathing", "flickering", "pulse"]:
			if has_meta("glow_tween"):
				var old_tween = get_meta("glow_tween")
				if old_tween and old_tween.is_valid():
					old_tween.kill()

			var glow_tween = create_tween().set_loops()
			set_meta("glow_tween", glow_tween)
			
			match glow_effect:
				"breathing":
					# 紫色史诗：优雅的慢呼吸
					glow_tween.tween_property(self, "modulate", Color(1.0, 0.85, 1.0, 0.9), 1.5).set_ease(Tween.EASE_IN_OUT)
					glow_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 1.5).set_ease(Tween.EASE_IN_OUT)
				"flickering":
					# 金色钻石：高贵的闪烁发光
					glow_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 0.75), 0.15).set_ease(Tween.EASE_OUT)
					glow_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1).set_ease(Tween.EASE_IN)
					glow_tween.tween_interval(0.4)
				"pulse":
					# 红色特殊/免死金牌：带感的主动脉冲 (微小缩放与亮度交替)
					glow_tween.tween_property(self, "scale", Vector2(1.03, 1.03), 0.4).set_ease(Tween.EASE_OUT)
					glow_tween.parallel().tween_property(self, "modulate", Color(1.1, 0.9, 0.9, 1.0), 0.4)
					glow_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.4).set_ease(Tween.EASE_IN)
					glow_tween.parallel().tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.4)
	
	if is_instance_valid(nameLabel):
		nameLabel.visible = false

	if is_instance_valid(countLabel):
		if item_count > 1:
			countLabel.visible = true
			countLabel.text = str(item_count)
		else:
			countLabel.visible = false

func play_appear_animation():
	modulate = Color(1, 1, 1, 0)
	scale = Vector2(0.8, 0.8)
	pivot_offset = custom_minimum_size / 2.0
	
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1, 0.15)
	tween.tween_property(self, "scale", Vector2(1, 1), 0.15).set_ease(Tween.EASE_OUT)

func play_disappear_animation():
	pivot_offset = custom_minimum_size / 2.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0, 0.15)
	tween.tween_property(self, "scale", Vector2(0.8, 0.8), 0.15).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)


signal clicked(itemUI: Control)
signal detail_requested(itemUI: Control)

# 开始拖拽
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

# 开始拖拽
func _get_drag_data(_atPosition: Vector2) -> Variant:
	var preview: Control = Control.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wrapper = _create_drag_preview_wrapper(_atPosition)
		
	# 设拖拽预览节点的缩放与原物品全局缩放一致，确保在缩放的容器中拖拽时尺寸完美贴合网格，且计算坐标无偏差
	preview.scale = self.get_global_transform().get_scale()
	preview.add_child(wrapper)
	
	isDragging = true
	dragOffset = _atPosition
	
	_add_preview_to_drag_layer(preview)
	
	# 【核心改进】开始拖拽时原图标变为更淡的半透明，提供极好的拖动视觉反馈
	self.modulate.a = 0.3
	_hide_tooltip()
	
	active_drag_data = {
		"type": "backpack_item",
		"resource": resource,
		"source_path": source_path,
		"node": self,
		"pickup_offset": _atPosition
	}
	
	# [AI MODIFY]
	var dc = get_node_or_null("/root/DragCoordinator")
	if dc:
		dc.begin_drag(
			self,
			get_owner_container()
		)
	
	return active_drag_data

# [AI MODIFY]
func get_owner_container() -> Control:
	var p = get_parent()
	while p:
		if p.has_method("removeItem"):
			return p
		p = p.get_parent()
	return null

# 监听拖拽结束（无论成功失败都会触发）
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		isDragging = false
		# 恢复显示
		self.modulate.a = 1.0
		if is_instance_valid(active_drag_preview):
			active_drag_preview.queue_free()
			active_drag_preview = null

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			clicked.emit(self)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			detail_requested.emit(self)

func _input(event: InputEvent) -> void:
	if isDragging and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			rotateItem()
			get_viewport().set_input_as_handled()

# [AI MODIFY]
# 将物品形状顺时针旋转 90 度
func rotateItem() -> void:
	var prev_size = size
	var newShape: Array[Vector2i] = []
	# 顺时针旋转公式: (x, y) -> (-y, x)
	for cell: Vector2i in runtime_shape:
		newShape.append(Vector2i(-cell.y, cell.x))

	# 归一化坐标，确保包含 (0,0) 且都在正象限
	var minX: int = 0
	var minY: int = 0
	for cell: Vector2i in newShape:
		minX = min(minX, cell.x)
		minY = min(minY, cell.y)

	for i: int in range(newShape.size()):
		newShape[i] -= Vector2i(minX, minY)

	runtime_shape = newShape
	current_rotation = fmod(current_rotation + PI / 2.0, PI * 2.0)
	is_rotated = (abs(current_rotation) > 0.01)
	_refresh_visuals()
	
	# 如果正在拖拽，更新预览
	if isDragging:
		# 旋转拖拽时的点击偏移量，确保吸附定位 100% 精准不跳变！
		dragOffset = Vector2(prev_size.y - dragOffset.y, dragOffset.x)
		if not active_drag_data.is_empty():
			active_drag_data["pickup_offset"] = dragOffset
		_update_drag_preview()

func _update_drag_preview() -> void:
	var preview = Control.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wrapper = _create_drag_preview_wrapper(dragOffset)
	preview.scale = self.get_global_transform().get_scale()
	preview.add_child(wrapper)
	_add_preview_to_drag_layer(preview)

# [AI MODIFY]
# ── 核心扩充：创建一个极富科幻风、与物品网格大小完全一致的战术科技蓝网格，让玩家拖拽时一眼看清该道具占几格 ──
func _create_drag_preview_wrapper(offset: Vector2) -> Control:
	var wrapper = Control.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.size = size
	wrapper.position = -offset
	
	# 提取当前物理形状 (使用 runtime_shape)
	var shape = runtime_shape
		
	# 绘制半透明网格底
	for p in shape:
		var cell_panel = Panel.new()
		cell_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell_panel.size = Vector2(64, 64)
		cell_panel.position = Vector2(p.x * 72, p.y * 72)
		
		var style = StyleBoxFlat.new()
		style.bg_color = Color("#00e5ff1b") # 极柔和半透明战术青
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color("#00e5ffaa") # 高亮青色细边框
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		cell_panel.add_theme_stylebox_override("panel", style)
		wrapper.add_child(cell_panel)
		
	# 绘制贴图 TextureRect
	var copy = TextureRect.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if resource and resource.icon:
		copy.texture = resource.icon
	else:
		copy.texture = load("res://icon.svg")
		
	copy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	copy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	copy.size = size
	copy.modulate = Color(1, 1, 1, 0.8) # 保持图标的清晰可见度
	copy.position = Vector2.ZERO
	
	if is_rotated:
		copy.pivot_offset = size / 2.0
		copy.rotation = current_rotation
		
	wrapper.add_child(copy)
	
	# 递归设置子节点 mouse_filter 为 IGNORE
	_set_preview_mouse_ignore(wrapper)
	return wrapper

func _set_preview_mouse_ignore(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_preview_mouse_ignore(child)

# [AI MODIFY]
func get_rotated_shape() -> Array[Vector2i]:
	var newShape: Array[Vector2i] = []
	for cell: Vector2i in runtime_shape:
		newShape.append(Vector2i(-cell.y, cell.x))
	var minX: int = 0
	var minY: int = 0
	for cell: Vector2i in newShape:
		minX = min(minX, cell.x)
		minY = min(minY, cell.y)
	for i: int in range(newShape.size()):
		newShape[i] -= Vector2i(minX, minY)
	return newShape


# ══════════════════════════════════════
# 🖱️ 悬停提示框系统实现
# ══════════════════════════════════════

func _on_mouse_entered() -> void:
	if Engine.is_editor_hint(): return
	# 启动 0.3 秒延迟显示定时器
	tooltip_timer = get_tree().create_timer(0.3)
	tooltip_timer.timeout.connect(func():
		if tooltip_timer != null:
			_show_tooltip()
	)

func _on_mouse_exited() -> void:
	if Engine.is_editor_hint(): return
	tooltip_timer = null
	_hide_tooltip()

func _show_tooltip() -> void:
	if tooltip or not resource: return
	
	# 动态创建极致优雅、高性能的纯代码悬停面板，防止因缺失外置场景造成资源加载失败
	tooltip = ItemTooltipPanel.new()
	tooltip.setup(resource)
	get_tree().root.add_child(tooltip)
	_update_tooltip_position()

func _hide_tooltip() -> void:
	if tooltip:
		tooltip.queue_free()
		tooltip = null

func _process(_delta: float) -> void:
	# [AI MODIFY]
	if isDragging and is_instance_valid(active_drag_preview):
		active_drag_preview.global_position = get_global_mouse_position()

	if not Engine.is_editor_hint() and tooltip and is_instance_valid(tooltip):
		_update_tooltip_position()

func _update_tooltip_position() -> void:
	if tooltip:
		# 悬停提示框完美位于鼠标右下方
		tooltip.global_position = get_global_mouse_position() + Vector2(16, 16)

# ══════════════════════════════════════
# 💎 AAA级纯代码战术提示面板 (ItemTooltipPanel)
# ══════════════════════════════════════

class ItemTooltipPanel extends PanelContainer:
	var name_label: Label
	var rarity_label: Label
	var desc_label: Label
	var price_label: Label
	
	func _init() -> void:
		# 极具质感的 #1a2535 科技深蓝背景、1px #2a3a4f 亮色边框及 6px 圆角
		var style = StyleBoxFlat.new()
		style.bg_color = Color("#1a2535")
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color("#2a3a4f")
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		
		# 边缘柔和外阴影，增加层次感
		style.shadow_color = Color(0, 0, 0, 0.45)
		style.shadow_size = 6
		style.shadow_offset = Vector2(2, 3)
		
		# 内边距设置
		style.content_margin_left = 12
		style.content_margin_top = 10
		style.content_margin_right = 12
		style.content_margin_bottom = 10
		add_theme_stylebox_override("panel", style)
		
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 6)
		add_child(vbox)
		
		# 物品名称
		name_label = Label.new()
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.add_theme_color_override("font_color", Color("#ffffff"))
		name_label.text = "装备名称"
		vbox.add_child(name_label)
		
		# 稀有度标签
		rarity_label = Label.new()
		rarity_label.add_theme_font_size_override("font_size", 10)
		rarity_label.text = "稀有度"
		vbox.add_child(rarity_label)
		
		# 亮色分割线
		var sep1 = Panel.new()
		sep1.custom_minimum_size = Vector2(0, 1)
		var sep_style = StyleBoxFlat.new()
		sep_style.bg_color = Color("#2a3a4f")
		sep1.add_theme_stylebox_override("panel", sep_style)
		vbox.add_child(sep1)
		
		# 效果描述
		desc_label = Label.new()
		desc_label.add_theme_font_size_override("font_size", 11)
		desc_label.add_theme_color_override("font_color", Color("#c0c0c0"))
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_label.custom_minimum_size = Vector2(180, 0)
		desc_label.text = "效果描述..."
		vbox.add_child(desc_label)
		
		# 第二条分割线
		var sep2 = Panel.new()
		sep2.custom_minimum_size = Vector2(0, 1)
		sep2.add_theme_stylebox_override("panel", sep_style)
		vbox.add_child(sep2)
		
		# 出售价格
		price_label = Label.new()
		price_label.add_theme_font_size_override("font_size", 10)
		price_label.add_theme_color_override("font_color", Color("#ffb300"))
		price_label.text = "回收价值"
		vbox.add_child(price_label)

	func setup(item_res: BackpackItemResource) -> void:
		name_label.text = item_res.item_name
		
		# 映射高亮品质颜色与文本
		var rarity_str = "普通装备"
		var rarity_color = Color("#909090")
		match item_res.rarity:
			0:
				rarity_str = "稀有 (Rare)"
				rarity_color = Color("#0078d4")
			1:
				rarity_str = "史诗 (Epic)"
				rarity_color = Color("#a335ee")
			2:
				rarity_str = "钻石 (Diamond)"
				rarity_color = Color("#ffd700")
		if item_res.has_persistent_shield or item_res.shield_cap_boost > 0:
			rarity_str = "特殊免死金牌"
			rarity_color = Color("#ff4444")
			
		rarity_label.text = rarity_str
		rarity_label.add_theme_color_override("font_color", rarity_color)
		
		# 编译属性增益描述
		var desc = ""
		var maxX: int = 0
		var maxY: int = 0
		for cell: Vector2i in item_res.shape:
			maxX = max(maxX, cell.x)
			maxY = max(maxY, cell.y)
		desc += "占用格子: %dx%d\n" % [(maxX + 1), (maxY + 1)]
		if item_res.bomb_cap_boost > 0: 
			desc += "炸弹容量: +%d 个\n" % item_res.bomb_cap_boost
		if item_res.speed_cap_boost > 0: 
			desc += "移动速度: +%.0f%%\n" % (item_res.speed_cap_boost * 100)
		if item_res.shield_cap_boost > 0: 
			desc += "护盾上限: +%d 个\n" % item_res.shield_cap_boost
		if item_res.has_persistent_shield: 
			desc += "携带开局免死护盾\n"
		
		var power_boosts = []
		if item_res.radius_cap_boost > 0: power_boosts.append("全方向 +%d" % item_res.radius_cap_boost)
		if item_res.radius_up_boost > 0: power_boosts.append("向上 +%d" % item_res.radius_up_boost)
		if item_res.radius_down_boost > 0: power_boosts.append("向下 +%d" % item_res.radius_down_boost)
		if item_res.radius_left_boost > 0: power_boosts.append("向左 +%d" % item_res.radius_left_boost)
		if item_res.radius_right_boost > 0: power_boosts.append("向右 +%d" % item_res.radius_right_boost)
		if power_boosts.size() > 0:
			desc += "爆炸威力: " + ", ".join(power_boosts) + "\n"
			
		if desc == "":
			desc = "基础属性加成装备"
		else:
			desc = desc.strip_edges()
			
		desc_label.text = desc
		
		# 回收公式计算
		var price = 0
		price += item_res.bomb_cap_boost * 50
		price += item_res.radius_cap_boost * 60
		price += item_res.radius_up_boost * 40
		price += item_res.radius_down_boost * 40
		price += item_res.radius_left_boost * 40
		price += item_res.radius_right_boost * 40
		price += int(item_res.speed_cap_boost * 30)
		price += item_res.shield_cap_boost * 80
		if item_res.has_persistent_shield: price += 200
		price += item_res.shape.size() * 10
		price = max(price, 10)
		match item_res.rarity:
			1: price *= 2
			2: price *= 4
			
		price_label.text = "回收价值: %d 金币" % price
