extends Control

# 战术背包核心逻辑
# 支持 8x8 主网格与 2x2 保险格
# 格子尺寸：80px

# ── 信号 ──
signal item_clicked(itemUI: Control)
signal item_detail_requested(itemUI: Control)
signal backpack_stats_updated(bomb: int, radius: int, shield: int, speed: float, epic: bool, r_up: int, r_down: int, r_left: int, r_right: int)
signal item_dropped_from_warehouse(source_path: String)
signal item_moved_internally()

# ── 配置 ──
@export var is_warehouse: bool = false
@export var ROWS: int = 8
@export var COLS: int = 6

# ── 常量 ──
const CELL_SIZE: int = 64
const SPACING: int = 8
const SPECIAL_ROWS: int = 2
const SPECIAL_COLS: int = 2

# ── 节点引用 ──
@onready var gridWrapper = %GridWrapper
@onready var cellsContainer = %Cells
@onready var itemsContainer = %Items
@onready var specialPanel = %SpecialPanel
@onready var specialCellsContainer = %SpecialCells
@onready var specialItemsContainer = %SpecialItems
var ghostPreview: Control = null
@onready var mainGridCap = %MainGridCap
@onready var specialGridCap = %SpecialGridCap

# ── 数据 ──
var gridData: Array = []        # 8x8 网格数据
var specialGridData: Array = [] # 2x2 保险格数据
var _is_open: bool = false
var _is_layout_mode: bool = false # 是否为整备中心模式
var _last_debug_info: Dictionary = {}

# ── 拖拽高亮样式 ──
var valid_style: StyleBoxFlat
var invalid_style: StyleBoxFlat

func _ready() -> void:
	# [AI MODIFY]
	# 统一拖拽协议与防止子节点事件拦截
	mouse_filter = Control.MOUSE_FILTER_STOP
	if is_instance_valid(gridWrapper): gridWrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	if is_instance_valid(cellsContainer): cellsContainer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(itemsContainer): itemsContainer.mouse_filter = Control.MOUSE_FILTER_PASS
	if is_instance_valid(specialPanel): specialPanel.mouse_filter = Control.MOUSE_FILTER_PASS
	if is_instance_valid(specialCellsContainer): specialCellsContainer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(specialItemsContainer): specialItemsContainer.mouse_filter = Control.MOUSE_FILTER_PASS

	_initDragStyles()
	
	if is_warehouse:
		var divider = get_node_or_null("BgPanel/Margin/VBox/ContentArea/Divider")
		if divider: divider.visible = false
		var specialArea = get_node_or_null("BgPanel/Margin/VBox/ContentArea/SpecialArea")
		if specialArea: specialArea.visible = false
		
		var mainTitle = get_node_or_null("BgPanel/Margin/VBox/TitleBar/MainTitle")
		if mainTitle: mainTitle.text = "物资仓库"
	else:
		var mainTitle = get_node_or_null("BgPanel/Margin/VBox/TitleBar/MainTitle")
		if mainTitle: mainTitle.text = "已装备"
		
		# 说明保险箱的作用，提示死亡不掉落规则
		var specialTitle = get_node_or_null("BgPanel/Margin/VBox/ContentArea/SpecialArea/SpecialVBox/SpecialTitle")
		if specialTitle:
			specialTitle.text = "保险箱\n(死亡不掉落)"
			specialTitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 处理 ScrollContainer 内部布局适配
	if get_parent() is ScrollContainer or (get_parent() and get_parent().get_parent() is ScrollContainer):
		anchors_preset = Control.PRESET_TOP_LEFT
		anchor_left = 0.0
		anchor_right = 0.0
		anchor_top = 0.0
		anchor_bottom = 0.0
		offset_left = 0.0
		offset_right = 0.0
		offset_top = 0.0
		offset_bottom = 0.0

	var required_width = COLS * CELL_SIZE + (COLS - 1) * SPACING + 48
	if not is_warehouse:
		required_width += 32 + SPECIAL_COLS * CELL_SIZE + (SPECIAL_COLS - 1) * SPACING
	var required_height = ROWS * CELL_SIZE + (ROWS - 1) * SPACING + 120
	custom_minimum_size = Vector2(required_width, required_height)

	_initGridData()
	_createVisualCells()
	updateBackpackStats()
	updateCapacityDisplay()

	# 核心修复：移除场景定义的 GhostPreview，并像 loot_grid.gd 一样动态创建，确保其绝对处于渲染队列最前端且不被任何父级遮挡/裁剪
	# [AI MODIFY]
	if is_instance_valid(ghostPreview):
		ghostPreview.queue_free()
		ghostPreview = null

	# [AI MODIFY]
	if not mouse_exited.is_connected(_clear_ghost_preview):
		mouse_exited.connect(_clear_ghost_preview)

func _initDragStyles() -> void:
	valid_style = StyleBoxFlat.new()
	valid_style.bg_color = Color("#2a3a4a")
	valid_style.border_width_left = 1
	valid_style.border_width_top = 1
	valid_style.border_width_right = 1
	valid_style.border_width_bottom = 1
	valid_style.border_color = Color("#4a90e2") # 蓝色
	valid_style.corner_radius_top_left = 4
	valid_style.corner_radius_top_right = 4
	valid_style.corner_radius_bottom_left = 4
	valid_style.corner_radius_bottom_right = 4

	invalid_style = StyleBoxFlat.new()
	invalid_style.bg_color = Color("#3a2a2a")
	invalid_style.border_width_left = 1
	invalid_style.border_width_top = 1
	invalid_style.border_width_right = 1
	invalid_style.border_width_bottom = 1
	invalid_style.border_color = Color("#e24a4a") # 红色
	invalid_style.corner_radius_top_left = 4
	invalid_style.corner_radius_top_right = 4
	invalid_style.corner_radius_bottom_left = 4
	invalid_style.corner_radius_bottom_right = 4

func _initGridData() -> void:
	# [AI MODIFY]
	gridData.clear()
	for r in range(ROWS):
		var row = []
		for c in range(COLS): row.append([])
		gridData.append(row)
		
	specialGridData.clear()
	for r in range(SPECIAL_ROWS):
		var row = []
		for c in range(SPECIAL_COLS): row.append([])
		specialGridData.append(row)

func _createVisualCells() -> void:
	# 清理旧格子
	for child in cellsContainer.get_children(): child.queue_free()
	for child in specialCellsContainer.get_children(): child.queue_free()
	
	# 动态调整 GridWrapper 尺寸以适配不同的 ROWS 和 COLS
	if gridWrapper:
		gridWrapper.custom_minimum_size = Vector2(COLS * CELL_SIZE + (COLS - 1) * SPACING, ROWS * CELL_SIZE + (ROWS - 1) * SPACING)
	
	var cell_scene = load("res://prefabs/Backpack/sub/InventoryCell.tscn")
	
	# 创建主格背景
	for r in range(ROWS):
		for c in range(COLS):
			var cell = cell_scene.instantiate()
			cell.is_special = false
			cell.position = Vector2(c * (CELL_SIZE + SPACING), r * (CELL_SIZE + SPACING))
			cellsContainer.add_child(cell)
			
	# 创建保险格背景
	if not is_warehouse:
		for r in range(SPECIAL_ROWS):
			for c in range(SPECIAL_COLS):
				var cell = cell_scene.instantiate()
				cell.is_special = true
				cell.position = Vector2(c * (CELL_SIZE + SPACING), r * (CELL_SIZE + SPACING))
				specialCellsContainer.add_child(cell)

func set_layout_mode(active: bool) -> void:
	_is_layout_mode = active
	if active:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_set_mouse_pass_recursive(self)
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_mouse_pass_recursive(self, true)

# 递归设置子节点 mouse_filter：restore=true 恢复为默认，否则设为 PASS
# [AI MODIFY]
func _set_mouse_pass_recursive(node: Node, restore: bool = false) -> void:
	for child in node.get_children():
		if child is Control:
			# [AI MODIFY] 确保关键网格层和物理网格不受干扰且符合规范协议
			if child == cellsContainer or child == specialCellsContainer:
				child.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if child.get_child_count() > 0 and child != ghostPreview:
					_set_mouse_pass_recursive(child, restore)
				continue
			if child == itemsContainer or child == specialItemsContainer:
				child.mouse_filter = Control.MOUSE_FILTER_PASS
				if child.get_child_count() > 0 and child != ghostPreview:
					_set_mouse_pass_recursive(child, restore)
				continue

			if restore:
				# 恢复默认拦截
				if child == ghostPreview:
					child.mouse_filter = Control.MOUSE_FILTER_IGNORE
				elif child is Panel or child is PanelContainer or child is MarginContainer or child is ScrollContainer or child is VBoxContainer or child is HBoxContainer:
					child.mouse_filter = Control.MOUSE_FILTER_STOP
			else:
				# 允许拖拽穿透
				if child is PanelContainer or child is Panel or child is MarginContainer or child is ScrollContainer or child is VBoxContainer or child is HBoxContainer:
					child.mouse_filter = Control.MOUSE_FILTER_PASS
		if child.get_child_count() > 0 and child != ghostPreview:
			_set_mouse_pass_recursive(child, restore)

func open_backpack() -> void:
	_is_open = true
	show()
	modulate = Color(1, 1, 1, 0)
	scale = Vector2(0.9, 0.9)
	pivot_offset = size / 2.0
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.2)
	tween.tween_property(self, "scale", Vector2(1, 1), 0.2).set_ease(Tween.EASE_OUT)

func close_backpack() -> void:
	_is_open = false
	pivot_offset = size / 2.0
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.tween_property(self, "scale", Vector2(0.9, 0.9), 0.15).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func(): hide())

func toggle() -> void:
	if _is_open: close_backpack()
	else: open_backpack()

# ── 核心逻辑 ──

# [AI MODIFY]
func canPlaceItem(item_or_res: Variant, origin: Vector2i, is_special: bool = false) -> bool:
	if not item_or_res: return false
	
	var res: BackpackItemResource = null
	var itemUI: Control = null
	
	if item_or_res is BackpackItemResource:
		res = item_or_res
	elif item_or_res is Control:
		itemUI = item_or_res
		res = itemUI.resource
	
	if not res: return false
	
	var shape = item_or_res.runtime_shape if (item_or_res is Control and "runtime_shape" in item_or_res) else res.shape
	
	if is_special:
		return _isSpaceAvailableInGrid(specialGridData, SPECIAL_ROWS, SPECIAL_COLS, origin, shape, itemUI)
	else:
		return _isSpaceAvailableInGrid(gridData, ROWS, COLS, origin, shape, itemUI)

func _isSpaceAvailableInGrid(data: Array, max_r: int, max_c: int, origin: Vector2i, shape: Array, ignore_item: Control = null) -> bool:
	# [AI MODIFY]
	for offset in shape:
		var target = origin + offset
		if target.x < 0 or target.x >= max_c or target.y < 0 or target.y >= max_r:
			return false
		var cell = data[target.y][target.x]
		if cell is Array:
			for existing in cell:
				if existing != null and existing != ignore_item:
					return false
		else:
			if cell != null and cell != ignore_item:
				return false
	return true

# [AI MODIFY]
func placeItem(itemUI: Control, origin: Vector2i) -> void:
	# [AI MODIFY]
	removeItem(itemUI)
	var shape = itemUI.runtime_shape
	
	for offset in shape:
		var r = origin.y + offset.y
		var c = origin.x + offset.x
		if r >= 0 and r < ROWS and c >= 0 and c < COLS:
			if not (gridData[r][c] is Array):
				gridData[r][c] = []
			if not (itemUI in gridData[r][c]):
				gridData[r][c].append(itemUI)
	_transfer_to_container(itemUI, itemsContainer, origin)
	updateCapacityDisplay()

# [AI MODIFY]
func placeItemInSpecial(itemUI: Control, origin: Vector2i) -> void:
	# [AI MODIFY]
	removeItem(itemUI)
	var shape = itemUI.runtime_shape
	
	for offset in shape:
		var r = origin.y + offset.y
		var c = origin.x + offset.x
		if r >= 0 and r < SPECIAL_ROWS and c >= 0 and c < SPECIAL_COLS:
			if not (specialGridData[r][c] is Array):
				specialGridData[r][c] = []
			if not (itemUI in specialGridData[r][c]):
				specialGridData[r][c].append(itemUI)
	_transfer_to_container(itemUI, specialItemsContainer, origin)
	updateCapacityDisplay()

func _transfer_to_container(itemUI: Control, container: Control, origin: Vector2i) -> void:
	if itemUI.get_parent(): itemUI.get_parent().remove_child(itemUI)
	container.add_child(itemUI)
	itemUI.position = Vector2(origin.x * (CELL_SIZE + SPACING), origin.y * (CELL_SIZE + SPACING))
	itemUI.gridPos = origin
	if itemUI.has_method("play_appear_animation"):
		itemUI.play_appear_animation()
	
	if itemUI.has_signal("clicked") and not itemUI.clicked.is_connected(_on_item_clicked):
		itemUI.clicked.connect(_on_item_clicked)
	if itemUI.has_signal("detail_requested") and not itemUI.detail_requested.is_connected(_on_item_detail_requested):
		itemUI.detail_requested.connect(_on_item_detail_requested)
		
	updateBackpackStats()

# ── 拖拽系统 ──
func _check_grid_hit(container: Control, g_mouse: Vector2, offset_px: Vector2, item_or_res: Variant, shape: Array, max_r: int, max_c: int, is_special: bool) -> Dictionary:
	if container.get_child_count() == 0:
		return {"is_hit": false, "is_valid": false, "grid_pos": Vector2i(-1, -1)}

	# 获取鼠标相对于 cells 容器的本地坐标
	# [AI MODIFY]
	var l_mouse = container.get_global_transform().affine_inverse() * g_mouse
	
	# 计算拖拽物品的左上角相对于 cells 容器的本地像素坐标
	var local_item_tl = l_mouse - offset_px

	# ── 终极黄金 Snapping 算法（基于左上角四舍五入对齐并引入智能边界磁吸 Clamp） ──
	# 计算拖拽物品的占用列数与行数，以实现完美的网格边缘自动磁吸定位，杜绝越界导致变红或无法松手
	var item_w = 1
	var item_h = 1
	for offset in shape:
		item_w = max(item_w, offset.x + 1)
		item_h = max(item_h, offset.y + 1)
	
	var clamp_max_x = max(0, max_c - item_w)
	var clamp_max_y = max(0, max_r - item_h)
	
	var step = CELL_SIZE + SPACING
	var snap_x = clamp(roundi(local_item_tl.x / step), 0, clamp_max_x)
	var snap_y = clamp(roundi(local_item_tl.y / step), 0, clamp_max_y)
	var snap_cell = Vector2i(snap_x, snap_y)

	# 网格本地总尺寸 (用于极具手感的边界检测)
	var max_width = max_c * CELL_SIZE + (max_c - 1) * SPACING
	var max_height = max_r * CELL_SIZE + (max_r - 1) * SPACING
	
	# 【超级手感优化】：我们将边界检测范围适当扩大，以给玩家极其宽容的拖入判定！
	var local_bound = Rect2(0, 0, max_width, max_height).grow(64)

	var start_node = container.get_child(0)
	var g_scale = start_node.get_global_transform().get_scale()

	var res = {
		"is_hit": false, 
		"is_valid": false, 
		"grid_pos": Vector2i(-1, -1),
		"origin_g": start_node.get_global_position(),
		"scale": g_scale,
		"scaled_cell": start_node.size.x * g_scale.x,
		"scaled_step": (start_node.size.x + SPACING) * g_scale.x
	}

	if local_bound.has_point(l_mouse):
		res.is_hit = true
		res.grid_pos = snap_cell
		
		# 使用最权威的 canPlaceItem 进行合法性验证，确保拖拽虚影与最终放置决策 100% 对齐一致！
		res.is_valid = canPlaceItem(item_or_res, res.grid_pos, is_special)

	return res

func _get_dist_to_rect(l_mouse: Vector2, rows: int, cols: int) -> float:
	var width = cols * CELL_SIZE + (cols - 1) * SPACING
	var height = rows * CELL_SIZE + (rows - 1) * SPACING
	var dx = maxf(0.0, maxf(-l_mouse.x, l_mouse.x - width))
	var dy = maxf(0.0, maxf(-l_mouse.y, l_mouse.y - height))
	return sqrt(dx * dx + dy * dy)

# [AI MODIFY]
func _get_drop_info(at_position: Vector2, pickup_offset: Vector2, data: Variant = null) -> Dictionary:
	var g_mouse = get_global_mouse_position()
	var itemUI = data.get("node") if data is Dictionary else (data if data is Control else null)
	var res = data.get("resource") if data is Dictionary else (itemUI.resource if itemUI else null)
	if not res and itemUI:
		res = itemUI.resource
		
	var shape = []
	if itemUI:
		shape = itemUI.runtime_shape
	elif res:
		shape = res.shape

	var item_to_check = itemUI if itemUI else res
	var sp_hit = null
	var main_hit = null

	# 检测保险格 (如果不是仓库，且保险格可用)
	if not is_warehouse and specialCellsContainer and specialCellsContainer.get_child_count() > 0:
		sp_hit = _check_grid_hit(specialCellsContainer, g_mouse, pickup_offset, item_to_check, shape, SPECIAL_ROWS, SPECIAL_COLS, true)

	# 检测主网格
	main_hit = _check_grid_hit(cellsContainer, g_mouse, pickup_offset, item_to_check, shape, ROWS, COLS, false)

	# ── 智能仲裁逻辑 ──
	if sp_hit and sp_hit.is_hit and sp_hit.is_valid:
		sp_hit.valid = true
		sp_hit.is_special = true
		sp_hit.origin = sp_hit.grid_pos
		return sp_hit
	if main_hit and main_hit.is_hit and main_hit.is_valid:
		main_hit.valid = true
		main_hit.is_special = false
		main_hit.origin = main_hit.grid_pos
		return main_hit

	if main_hit and main_hit.is_hit and sp_hit and sp_hit.is_hit:
		var l_mouse_main = cellsContainer.get_global_transform().affine_inverse() * g_mouse
		var l_mouse_sp = specialCellsContainer.get_global_transform().affine_inverse() * g_mouse
		var dist_to_main = _get_dist_to_rect(l_mouse_main, ROWS, COLS)
		var dist_to_sp = _get_dist_to_rect(l_mouse_sp, SPECIAL_ROWS, SPECIAL_COLS)
		if dist_to_main < dist_to_sp:
			main_hit.valid = false
			main_hit.is_special = false
			main_hit.origin = main_hit.grid_pos
			return main_hit
		else:
			sp_hit.valid = false
			sp_hit.is_special = true
			sp_hit.origin = sp_hit.grid_pos
			return sp_hit

	if main_hit and main_hit.is_hit:
		main_hit.valid = false
		main_hit.is_special = false
		main_hit.origin = main_hit.grid_pos
		return main_hit
	if sp_hit and sp_hit.is_hit:
		sp_hit.valid = false
		sp_hit.is_special = true
		sp_hit.origin = sp_hit.grid_pos
		return sp_hit

	return {"is_hit": false, "valid": false, "is_special": false, "origin": Vector2i(-1, -1)}

# [AI MODIFY]
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var itemUI = data.get("node") if data is Dictionary else (data if data is Control else null)
	var res = data.get("resource") if data is Dictionary else (itemUI.resource if itemUI else null)
	if not res:
		return false
	
	var info = _get_drop_info(at_position, data.get("pickup_offset", Vector2.ZERO) if data is Dictionary else Vector2.ZERO, data)
	
	var debug_key = str(info.is_hit) + "_" + str(info.valid) + "_" + str(info.is_special) + "_" + str(info.origin)
	if not _last_debug_info.has(debug_key):
		_last_debug_info.clear()
		_last_debug_info[debug_key] = true
		var offset_val = data.get("pickup_offset", Vector2.ZERO) if data is Dictionary else Vector2.ZERO
		var g_scale = Vector2.ONE
		if cellsContainer.get_child_count() > 0:
			g_scale = cellsContainer.get_child(0).get_global_transform().get_scale()
		var item_tl_g = get_global_mouse_position() - (offset_val * g_scale)
		print("[DragDebug] name=", name, " is_hit=", info.is_hit, " valid=", info.valid, " is_special=", info.is_special, " origin=", info.origin, " mouse=", get_global_mouse_position(), " pickup_offset=", offset_val, " item_tl_g=", item_tl_g)
		
	if not info.is_hit:
		_clear_grid_highlights()
		return false
	
	var shape = itemUI.runtime_shape if itemUI else res.shape
	var can = info.valid
	_highlight_cells(info.origin, shape, info.is_special, can, info)
	return can

# [AI MODIFY]
func _drop_data(at_position: Vector2, data: Variant) -> void:
	_clear_ghost_preview()
	var info = _get_drop_info(at_position, data.get("pickup_offset", Vector2.ZERO) if data is Dictionary else Vector2.ZERO, data)
	
	if not info.is_hit or not info.valid:
		_clear_grid_highlights()
		return
		
	var itemUI = data.get("node") if data is Dictionary else (data if data is Control else null)
	if itemUI:
		var can = canPlaceItem(itemUI, info.origin, info.is_special)
		if not can:
			_clear_grid_highlights()
			return
			
		var dc = get_node_or_null("/root/DragCoordinator")
		var source_container = dc.source_container if dc else null
		var success = dc.transfer(self, info.origin, info.is_special) if dc else false
		if success:
			if source_container:
				if source_container != self:
					item_dropped_from_warehouse.emit(itemUI.source_path)
				else:
					item_moved_internally.emit()
	else:
		var res = data.get("resource")
		var dummy = load("res://prefabs/Backpack/sub/backpack_item.tscn").instantiate()
		dummy.setup(res)
		var can = canPlaceItem(dummy, info.origin, info.is_special)
		dummy.free()
		if not can:
			_clear_grid_highlights()
			return
			
		var itemUIScene = load("res://prefabs/Backpack/sub/backpack_item.tscn")
		var newItem = itemUIScene.instantiate()
		newItem.setup(res, data.get("source_path"))
		if info.is_special: placeItemInSpecial(newItem, info.origin)
		else: placeItem(newItem, info.origin)
		item_dropped_from_warehouse.emit(data.get("source_path"))
	
	_clear_grid_highlights()

func notify_item_removed(itemUI: Control) -> void:
	if is_instance_valid(itemUI):
		removeItem(itemUI)

func _on_item_clicked(itemUI: Control) -> void:
	item_clicked.emit(itemUI)

func _on_item_detail_requested(itemUI: Control) -> void:
	item_detail_requested.emit(itemUI)

func removeItem(itemUI: Control) -> void:
	# [AI MODIFY]
	for r in range(ROWS):
		for c in range(COLS):
			var cell = gridData[r][c]
			if cell is Array:
				cell.erase(itemUI)
			elif cell == itemUI:
				gridData[r][c] = null
	for r in range(SPECIAL_ROWS):
		for c in range(SPECIAL_COLS):
			var cell = specialGridData[r][c]
			if cell is Array:
				cell.erase(itemUI)
			elif cell == itemUI:
				specialGridData[r][c] = null
	updateBackpackStats()
	updateCapacityDisplay()

# [AI MODIFY]
func updateCapacityDisplay() -> void:
	# [AI MODIFY]
	var main_count = 0
	var processed = []
	for r in range(ROWS):
		for c in range(COLS):
			var cell = gridData[r][c]
			if cell is Array:
				for it in cell:
					if it and it not in processed:
						processed.append(it)
						var it_size = it.runtime_shape.size()
						main_count += it_size
			else:
				var it = cell
				if it and it not in processed:
					processed.append(it)
					var it_size = it.runtime_shape.size()
					main_count += it_size
	if mainGridCap: mainGridCap.text = "%d/%d" % [main_count, ROWS * COLS]
	
	var spec_count = 0
	processed.clear()
	for r in range(SPECIAL_ROWS):
		for c in range(SPECIAL_COLS):
			var cell = specialGridData[r][c]
			if cell is Array:
				for it in cell:
					if it and it not in processed:
						processed.append(it)
						var it_size = it.runtime_shape.size()
						spec_count += it_size
			else:
				var it = cell
				if it and it not in processed:
					processed.append(it)
					var it_size = it.runtime_shape.size()
					spec_count += it_size
	if specialGridCap: specialGridCap.text = "%d/4" % spec_count

func updateBackpackStats() -> void:
	# [AI MODIFY]
	var bomb = 0; var radius = 0; var shield = 0; var speed = 0.0; var epic = false
	var r_up = 0; var r_down = 0; var r_left = 0; var r_right = 0
	var items = []
	for r in range(ROWS):
		for c in range(COLS):
			var cell = gridData[r][c]
			if cell is Array:
				for it in cell:
					if it and it not in items: items.append(it)
			else:
				var it = cell
				if it and it not in items: items.append(it)
	for r in range(SPECIAL_ROWS):
		for c in range(SPECIAL_COLS):
			var cell = specialGridData[r][c]
			if cell is Array:
				for it in cell:
					if it and it not in items: items.append(it)
			else:
				var it = cell
				if it and it not in items: items.append(it)
	
	for it in items:
		var res = it.resource
		bomb += res.bomb_cap_boost; radius += res.radius_cap_boost
		r_up += res.radius_up_boost; r_down += res.radius_down_boost
		r_left += res.radius_left_boost; r_right += res.radius_right_boost
		shield += res.shield_cap_boost; speed += res.speed_cap_boost
		if res.has_persistent_shield: epic = true
	
	_syncToPlayer(bomb, radius, shield, speed, epic, r_up, r_down, r_left, r_right)
	backpack_stats_updated.emit(bomb, radius, shield, speed, epic, r_up, r_down, r_left, r_right)

func _syncToPlayer(bomb, radius, shield, speed, epic, r_up, r_down, r_left, r_right) -> void:
	var p = GameMode.get_local_player()
	if is_instance_valid(p):
		p.maxBombsCap = 2 + bomb
		p.explosionRadiusCap = 1 + radius
		p.radiusUpCap = r_up
		p.radiusDownCap = r_down
		p.radiusLeftCap = r_left
		p.radiusRightCap = r_right
		p.maxShieldsCap = 1 + shield
		p.speedCap = 95.0 + speed
		p.hasPersistentShield = epic

func get_backpack_layout_data() -> Array[Dictionary]:
	# [AI MODIFY]
	var layout: Array[Dictionary] = []
	var processed_items = []
	var scan_and_add = func(data_grid, is_insurance):
		for r in range(data_grid.size()):
			for c in range(data_grid[r].size()):
				var cell = data_grid[r][c]
				if cell is Array:
					for it in cell:
						if it and it not in processed_items:
							processed_items.append(it)
							var path = it.source_path if ("source_path" in it and it.source_path != "") else it.resource.resource_path
							if path == "" or path == "res://": continue
								
							layout.append({
								"res_path": path,
								"grid_pos": it.gridPos,
								"is_insurance": is_insurance,
								"rotated": it.is_rotated
							})
				else:
					var it = cell
					if it and it not in processed_items:
						processed_items.append(it)
						var path = it.source_path if ("source_path" in it and it.source_path != "") else it.resource.resource_path
						if path == "" or path == "res://": continue
							
						layout.append({
							"res_path": path,
							"grid_pos": it.gridPos,
							"is_insurance": is_insurance,
							"rotated": it.is_rotated
						})
	scan_and_add.call(gridData, false)
	scan_and_add.call(specialGridData, true)
	return layout

func get_all_item_resources(only_special: bool = false) -> Array:
	# [AI MODIFY]
	var res_list = []
	var items = []
	if only_special:
		for r in range(SPECIAL_ROWS):
			for c in range(SPECIAL_COLS):
				var cell = specialGridData[r][c]
				if cell is Array:
					for it in cell:
						if it and it not in items: items.append(it)
				else:
					var it = cell
					if it and it not in items: items.append(it)
	else:
		for r in range(ROWS):
			for c in range(COLS):
				var cell = gridData[r][c]
				if cell is Array:
					for it in cell:
						if it and it not in items: items.append(it)
				else:
					var it = cell
					if it and it not in items: items.append(it)
		for r in range(SPECIAL_ROWS):
			for c in range(SPECIAL_COLS):
				var cell = specialGridData[r][c]
				if cell is Array:
					for it in cell:
						if it and it not in items: items.append(it)
				else:
					var it = cell
					if it and it not in items: items.append(it)
	
	for it in items: res_list.append(it.resource)
	return res_list

func _clear_grid_highlights() -> void:
	for cell in cellsContainer.get_children():
		cell.current_state = InventoryCell.State.NORMAL
	for cell in specialCellsContainer.get_children():
		cell.current_state = InventoryCell.State.NORMAL
	if is_instance_valid(ghostPreview):
		ghostPreview.hide()
		for child in ghostPreview.get_children():
			child.queue_free()

func _highlight_cells(origin: Vector2i, shape: Array, is_special: bool, can_place: bool, info: Dictionary = {}) -> void:
	_clear_grid_highlights()
	
	var state = InventoryCell.State.VALID_DROP if can_place else InventoryCell.State.INVALID_DROP
	var container = specialCellsContainer if is_special else cellsContainer
	var cols_count = SPECIAL_COLS if is_special else COLS
	var rows_count = SPECIAL_ROWS if is_special else ROWS
	
	for offset in shape:
		var coord = origin + offset
		if coord.x >= 0 and coord.x < cols_count and coord.y >= 0 and coord.y < rows_count:
			var index = coord.y * cols_count + coord.x
			if index < container.get_child_count():
				var cell = container.get_child(index)
				cell.current_state = state
				
	_update_drop_feedback(info, shape)

# [AI MODIFY]
func _update_drop_feedback(info: Dictionary, shape: Array) -> void:
	if not is_instance_valid(ghostPreview):
		ghostPreview = Control.new()
		ghostPreview.name = "GhostPreview"
		ghostPreview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghostPreview.z_index = 100
		ghostPreview.top_level = true
		add_child(ghostPreview)
		
	# 清除旧的绿色预览方块
	for child in ghostPreview.get_children():
		child.queue_free()
		
	if info.get("is_hit", false) and info.get("is_valid", false):
		ghostPreview.show()
		var origin_g = info.get("origin_g", Vector2.ZERO)
		var g_scale = info.get("scale", Vector2.ONE)
		var scaled_cell = info.get("scaled_cell", CELL_SIZE * g_scale.x)
		var scaled_step = info.get("scaled_step", (CELL_SIZE + SPACING) * g_scale.x)
		
		var container = specialCellsContainer if info.get("is_special", false) else cellsContainer
		var cols_count = SPECIAL_COLS if info.get("is_special", false) else COLS
		var rows_count = SPECIAL_ROWS if info.get("is_special", false) else ROWS
		
		for offset in shape:
			var cell_pos = info.grid_pos + offset
			var rect = ColorRect.new()
			rect.size = Vector2(CELL_SIZE, CELL_SIZE)
			
			var calculated_gpos = origin_g + (Vector2(cell_pos) * scaled_step)
			rect.global_position = calculated_gpos
			rect.color = Color(0.1, 0.9, 0.5, 0.35) # 极具科幻质感的半透明翡翠绿，完美覆盖上方
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ghostPreview.add_child(rect)
			
			# 精准诊断日志
			var cell_gpos = Vector2.ZERO
			if cell_pos.x >= 0 and cell_pos.x < cols_count and cell_pos.y >= 0 and cell_pos.y < rows_count:
				var index = cell_pos.y * cols_count + cell_pos.x
				if index < container.get_child_count():
					cell_gpos = container.get_child(index).global_position
			print("[PreviewDiagnostic] name=", name, " cell=", cell_pos, " calc_gpos=", calculated_gpos, " cell_gpos=", cell_gpos, " diff=", calculated_gpos - cell_gpos)
	else:
		ghostPreview.hide()

# [AI MODIFY]
func _clear_ghost_preview() -> void:
	_clear_grid_highlights()
	if is_instance_valid(ghostPreview):
		ghostPreview.queue_free()
		ghostPreview = null

# [AI MODIFY]
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_ghost_preview()

# [AI MODIFY]
func _exit_tree() -> void:
	_clear_ghost_preview()

func find_first_empty_slot(itemUI: Control) -> Vector2i:
	for r in range(ROWS):
		for c in range(COLS):
			if canPlaceItem(itemUI, Vector2i(c, r), false):
				return Vector2i(c, r)
	return Vector2i(-1, -1)

func auto_sort() -> void:
	# [AI MODIFY]
	# 1. 收集所有当前网格内物品
	var items_to_sort: Array = []
	for r in range(ROWS):
		for c in range(COLS):
			var cell = gridData[r][c]
			if cell is Array:
				for it in cell:
					if it and it not in items_to_sort:
						items_to_sort.append(it)
			else:
				var it = cell
				if it and it not in items_to_sort:
					items_to_sort.append(it)
				
	# 2. 从主格完全卸下（保留节点引用）
	for it in items_to_sort:
		removeItem(it)
		
	# 3. 排序策略：按品质降序（DIAMOND > EPIC > RARE），其次按物理形状大小（面积）降序，便于高效紧凑打包
	# [AI MODIFY]
	# [AI MODIFY]
	items_to_sort.sort_custom(func(a, b):
		var size_a = a.runtime_shape.size()
		var size_b = b.runtime_shape.size()
		var val_a = a.resource.rarity * 1000 + size_a
		var val_b = b.resource.rarity * 1000 + size_b
		return val_a > val_b
	)
	
	# 4. 贪心对齐放置（若标准旋转不通过，则尝试 90 度旋转）
	var failed_items: Array = []
	for it in items_to_sort:
		var placed = false
		var pos = find_first_empty_slot(it)
		if pos.x != -1:
			placeItem(it, pos)
			placed = true
		else:
			# 尝试旋转后装箱
			it.rotateItem()
			pos = find_first_empty_slot(it)
			if pos.x != -1:
				placeItem(it, pos)
				placed = true
			else:
				# 还原旋转状态
				it.rotateItem()
				failed_items.append(it)
				
	# 5. 保险格回填逻辑
	if not is_warehouse and failed_items.size() > 0:
		# [AI MODIFY]
		var spec_items: Array = []
		for r in range(SPECIAL_ROWS):
			for c in range(SPECIAL_COLS):
				var cell = specialGridData[r][c]
				if cell is Array:
					for it in cell:
						if it and it not in spec_items:
							spec_items.append(it)
				else:
					var it = cell
					if it and it not in spec_items:
						spec_items.append(it)
					
		var to_remove = []
		for it in failed_items:
			var is_shield_item = (it.resource.shield_cap_boost > 0 or it.resource.has_persistent_shield)
			if is_shield_item:
				var spec_pos = Vector2i(-1, -1)
				for r in range(SPECIAL_ROWS):
					for c in range(SPECIAL_COLS):
						if canPlaceItem(it, Vector2i(c, r), true):
							spec_pos = Vector2i(c, r)
							break
					if spec_pos.x != -1: break
				if spec_pos.x != -1:
					placeItemInSpecial(it, spec_pos)
					to_remove.append(it)
		for it in to_remove:
			failed_items.erase(it)

	# 6. 如果仍然有无法放入背包的物品，安全退回仓库
	if not is_warehouse and failed_items.size() > 0:
		# 寻找 backpack_config 主节点的仓库网格
		var config_root = get_parent()
		while config_root and not config_root.has_node("%WarehouseGrid"):
			config_root = config_root.get_parent()
		if config_root:
			var w_grid = config_root.get_node("%WarehouseGrid")
			for it in failed_items:
				var empty_w = w_grid.find_first_empty_slot(it)
				if empty_w.x != -1:
					w_grid.placeItem(it, empty_w)
					print("[AutoSort] 背包整理溢出，物品安全退回仓库: ", it.resource.item_name)
				else:
					it.queue_free() # 防泄漏
		else:
			for it in failed_items: it.queue_free()

	updateCapacityDisplay()
	updateBackpackStats()

# [AI MODIFY]
func get_items_container() -> Control:
	return itemsContainer
