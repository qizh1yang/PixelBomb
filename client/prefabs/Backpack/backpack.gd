extends Control

# 战术背包核心逻辑
# 支持 5x6 主网格与 2x2 保险格 (1920x1080 优化重构)

# ── 信号 ──
signal item_clicked(itemUI: Control)

# ── 常量 ──
const ROWS: int = 5
const COLS: int = 6
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
@onready var closeBtn = %CloseBtn

# ── 底部功能按钮已被删除 ──

# ── 数据 ──
var gridData: Array = []        # 5x6 网格数据
var specialGridData: Array = [] # 2x2 保险格数据
var _is_open: bool = false
var _is_layout_mode: bool = false # 是否为整备中心模式（宝箱分屏模式）
var _original_offsets: Dictionary = {} # 保存原始偏移，用于恢复
var _last_debug_info: Dictionary = {}

# ── 窗口拖拽与右键战术菜单变量 ──
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

var contextMenu: PanelContainer
var menuUseBtn: Button
var menuInsuranceBtn: Button
var menuDiscardBtn: Button
var menuCancelBtn: Button
var active_context_item: Control = null

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

	add_to_group("Backpack")
	_initGridData()
	_createVisualCells()
	
	# 从 GlobalPlayerData 中加载初始战前配备的物品并初始化局内背包数据
	_load_initial_backpack_items()

	if is_instance_valid(closeBtn):
		closeBtn.pressed.connect(close_backpack)
		closeBtn.mouse_entered.connect(func(): closeBtn.add_theme_color_override("font_color", Color.RED))
		closeBtn.mouse_exited.connect(func(): closeBtn.remove_theme_color_override("font_color"))

	# 核心修复：移除场景定义的 GhostPreview，并像 loot_grid.gd 一样动态创建，确保其绝对处于渲染队列最前端且不被任何父级遮挡/裁剪
	# [AI MODIFY]
	if is_instance_valid(ghostPreview):
		ghostPreview.queue_free()
		ghostPreview = null

	# [AI MODIFY]
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)

	# 底部功能按钮信号连结已移除

	# 窗口拖拽连结
	var title_bar = $BgPanel/Margin/VBox/TitleBar
	if is_instance_valid(title_bar):
		title_bar.gui_input.connect(_on_title_bar_gui_input)

	# 动态创建右键快捷菜单
	_init_context_menu()

func _load_initial_backpack_items() -> void:
	if not is_instance_valid(GlobalPlayerData): return
	print("[Backpack] Linking warehouse backpack: loading initial items from GlobalPlayerData.backpack_config, count: ", GlobalPlayerData.backpack_config.size())
	
	var itemUIScene = load("res://prefabs/Backpack/sub/backpack_item.tscn")
	if not itemUIScene:
		push_error("[Backpack] Failed to load backpack_item.tscn")
		return

	for item_info in GlobalPlayerData.backpack_config:
		var res_path = item_info.get("res_path", "")
		var pos = item_info.get("grid_pos", Vector2i.ZERO)
		var is_special = item_info.get("is_insurance", false)
		var rotated = item_info.get("rotated", false)

		if res_path != "":
			var res = load(res_path)
			if res is BackpackItemResource:
				var itemUI = itemUIScene.instantiate()
				itemUI.setup(res, res_path)
				if rotated: 
					itemUI.rotateItem()
				
				if is_special:
					placeItemInSpecial(itemUI, pos)
				else:
					placeItem(itemUI, pos)
			else:
				push_error("[Backpack] Failed to load item resource: " + res_path)

func _initGridData() -> void:
	gridData.clear()
	for r in range(ROWS):
		var row = []
		for c in range(COLS): row.append(null)
		gridData.append(row)
		
	specialGridData.clear()
	for r in range(SPECIAL_ROWS):
		var row = []
		for c in range(SPECIAL_COLS): row.append(null)
		specialGridData.append(row)

func _createVisualCells() -> void:
	# 清理旧格子
	for child in cellsContainer.get_children(): child.queue_free()
	for child in specialCellsContainer.get_children(): child.queue_free()
	
	var cell_scene = load("res://prefabs/Backpack/sub/InventoryCell.tscn")
	
	# 创建主格背景
	for r in range(ROWS):
		for c in range(COLS):
			var cell = cell_scene.instantiate()
			cell.is_special = false
			cell.position = Vector2(c * (CELL_SIZE + SPACING), r * (CELL_SIZE + SPACING))
			cellsContainer.add_child(cell)
			
	# 创建保险格背景
	for r in range(SPECIAL_ROWS):
		for c in range(SPECIAL_COLS):
			var cell = cell_scene.instantiate()
			cell.is_special = true
			cell.position = Vector2(c * (CELL_SIZE + SPACING), r * (CELL_SIZE + SPACING))
			specialCellsContainer.add_child(cell)

func set_layout_mode(active: bool) -> void:
	_is_layout_mode = active
	if active:
		# [AI MODIFY]
		# 保存原始偏移和锚点，确保能完全复原
		_original_offsets = {
			"anchor_left": anchor_left,
			"anchor_right": anchor_right,
			"anchor_top": anchor_top,
			"anchor_bottom": anchor_bottom,
			"left": offset_left,
			"top": offset_top,
			"right": offset_right,
			"bottom": offset_bottom,
		}
		
		# 将锚点设置为屏幕中心，保证在不同分辨率下完美居中
		anchor_left = 0.5
		anchor_right = 0.5
		anchor_top = 0.5
		anchor_bottom = 0.5
		
		# 动态计算背包位置：宽度 640，高度 680，间距 40
		var backpack_width = 640.0
		var backpack_height = 680.0
		var gap = 40.0
		
		# 偏左放置：右边缘距离中心 -20，左边缘距离中心 -660
		offset_left = -backpack_width - gap / 2.0
		offset_right = -gap / 2.0
		offset_top = -backpack_height / 2.0
		offset_bottom = backpack_height / 2.0
		
		mouse_filter = Control.MOUSE_FILTER_STOP
		_set_mouse_pass_recursive(self)
	else:
		# 恢复原始位置
		# [AI MODIFY]
		if _original_offsets.has("left"):
			anchor_left = _original_offsets.get("anchor_left", 1.0)
			anchor_right = _original_offsets.get("anchor_right", 1.0)
			anchor_top = _original_offsets.get("anchor_top", 0.0)
			anchor_bottom = _original_offsets.get("anchor_bottom", 0.0)
			offset_left = _original_offsets["left"]
			offset_top = _original_offsets["top"]
			offset_right = _original_offsets["right"]
			offset_bottom = _original_offsets["bottom"]
		else:
			anchor_left = 1.0
			anchor_right = 1.0
			anchor_top = 0.0
			anchor_bottom = 0.0
			offset_left = -880
			offset_right = -80
			offset_top = 120
			offset_bottom = 720
		
		# 核心修复：根据当前背包是否开启，动态设置鼠标拦截状态
		if _is_open:
			mouse_filter = Control.MOUSE_FILTER_STOP
			_set_mouse_pass_recursive(self, false)
		else:
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			_set_mouse_pass_recursive(self, true)

# 递归设置子节点 mouse_filter：restore=true 恢复为默认，否则设为 PASS
# 递归设置子节点 mouse_filter：restore=true 恢复为默认，否则设为 PASS
# [AI MODIFY]
func _set_mouse_pass_recursive(node: Node, restore: bool = false) -> void:
	for child in node.get_children():
		if child is Control and child != self:
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
				# 恢复：Panel/PanelContainer 用 STOP，其他保持 IGNORE
				if child is PanelContainer or child is Panel:
					child.mouse_filter = Control.MOUSE_FILTER_STOP
				elif child == ghostPreview:
					child.mouse_filter = Control.MOUSE_FILTER_IGNORE
			else:
				# 分屏模式：让所有中间容器透传事件
				if child is PanelContainer or child is Panel or child is MarginContainer or child is VBoxContainer or child is HBoxContainer:
					child.mouse_filter = Control.MOUSE_FILTER_PASS
		if child.get_child_count() > 0 and child != ghostPreview:
			_set_mouse_pass_recursive(child, restore)

func open_backpack() -> void:
	_is_open = true
	show()
	modulate = Color(1, 1, 1, 0)
	scale = Vector2(0.9, 0.9)
	
	# [AI MODIFY] 正常在游戏内打开背包时，将其居中定位在屏幕中央
	if not _is_layout_mode:
		anchor_left = 0.5
		anchor_right = 0.5
		anchor_top = 0.5
		anchor_bottom = 0.5
		offset_left = -320.0
		offset_right = 320.0
		offset_top = -340.0
		offset_bottom = 340.0
		pivot_offset = Vector2(320.0, 340.0)
	else:
		pivot_offset = size / 2.0
	
	# 核心修复：确保开启时能拦截并透传事件，且子节点过滤已清除
	mouse_filter = Control.MOUSE_FILTER_STOP
	_set_mouse_pass_recursive(self, false)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.2)
	tween.tween_property(self, "scale", Vector2(1, 1), 0.2).set_ease(Tween.EASE_OUT)

func close_backpack() -> void:
	_is_open = false
	pivot_offset = size / 2.0
	

	if is_instance_valid(contextMenu):
		contextMenu.hide()
	
	# 核心修复：关闭时彻底不拦截
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_mouse_pass_recursive(self, true)
	
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
func canPlaceItem(itemUI: Control, origin: Vector2i, is_special: bool = false) -> bool:
	var shape = itemUI.runtime_shape
	
	if is_special:
		return _isSpaceAvailableInGrid(specialGridData, SPECIAL_ROWS, SPECIAL_COLS, origin, shape, itemUI)
	else:
		return _isSpaceAvailableInGrid(gridData, ROWS, COLS, origin, shape, itemUI)

func _isSpaceAvailableInGrid(data: Array, max_r: int, max_c: int, origin: Vector2i, shape: Array, ignore_item: Control = null) -> bool:
	for offset in shape:
		var target = origin + offset
		if target.x < 0 or target.x >= max_c or target.y < 0 or target.y >= max_r:
			return false
		var existing = data[target.y][target.x]
		if existing != null and existing != ignore_item:
			return false
	return true

# [AI MODIFY]
func placeItem(itemUI: Control, origin: Vector2i) -> void:
	var shape = itemUI.runtime_shape
	
	# [AI MODIFY]
	for offset in shape:
		var r = origin.y + offset.y
		var c = origin.x + offset.x
		if r >= 0 and r < ROWS and c >= 0 and c < COLS:
			gridData[r][c] = itemUI
	_transfer_to_container(itemUI, itemsContainer, origin)

# [AI MODIFY]
func placeItemInSpecial(itemUI: Control, origin: Vector2i) -> void:
	var shape = itemUI.runtime_shape
	
	# [AI MODIFY]
	for offset in shape:
		var r = origin.y + offset.y
		var c = origin.x + offset.x
		if r >= 0 and r < SPECIAL_ROWS and c >= 0 and c < SPECIAL_COLS:
			specialGridData[r][c] = itemUI
	_transfer_to_container(itemUI, specialItemsContainer, origin)

func _transfer_to_container(itemUI: Control, container: Control, origin: Vector2i) -> void:
	if itemUI.get_parent(): itemUI.get_parent().remove_child(itemUI)
	container.add_child(itemUI)
	itemUI.position = Vector2(origin.x * (CELL_SIZE + SPACING), origin.y * (CELL_SIZE + SPACING))
	itemUI.gridPos = origin
	if itemUI.has_method("play_appear_animation"):
		itemUI.play_appear_animation()
	
	if itemUI.has_signal("clicked") and not itemUI.clicked.is_connected(_on_item_clicked):
		itemUI.clicked.connect(_on_item_clicked)
		
	if itemUI.has_signal("detail_requested") and not itemUI.detail_requested.is_connected(_on_item_right_clicked):
		itemUI.detail_requested.connect(_on_item_right_clicked)
		
	updateBackpackStats()

func _on_item_clicked(itemUI: Control) -> void:
	item_clicked.emit(itemUI)

func removeItem(itemUI: Control) -> void:
	for r in range(ROWS):
		for c in range(COLS):
			if gridData[r][c] == itemUI: gridData[r][c] = null
	for r in range(SPECIAL_ROWS):
		for c in range(SPECIAL_COLS):
			if specialGridData[r][c] == itemUI: specialGridData[r][c] = null
	updateBackpackStats()

func notify_item_removed(itemUI: Control) -> void:
	if is_instance_valid(itemUI):
		removeItem(itemUI)

# ── 拖放接收 ──

# [AI MODIFY]
func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	var itemUI = data.get("node") if data is Dictionary else data
	if not is_instance_valid(itemUI) or not itemUI.resource: return false

	var g_mouse = get_global_mouse_position()
	var status = _get_drop_status(g_mouse, data)
	
	var debug_key = str(status.is_hit) + "_" + str(status.is_valid) + "_" + str(status.is_special) + "_" + str(status.grid_pos)
	if not _last_debug_info.has(debug_key):
		_last_debug_info.clear()
		_last_debug_info[debug_key] = true
		print("[InGameDragDebug] name=", name, " is_hit=", status.is_hit, " valid=", status.is_valid, " is_special=", status.is_special, " origin=", status.grid_pos, " mouse=", g_mouse)
		
	_update_drop_feedback(g_mouse, data, status)
	return status.is_valid

# [AI MODIFY]
func _drop_data(_pos: Vector2, data: Variant) -> void:
	_clear_ghost_preview()
	var g_mouse = get_global_mouse_position()
	var status = _get_drop_status(g_mouse, data)
	var itemUI = data.get("node") if data is Dictionary else data

	if not status.is_valid or not is_instance_valid(itemUI): return

	var dc = get_node_or_null("/root/DragCoordinator")
	if dc:
		dc.transfer(
			self,
			status.grid_pos,
			status.is_special
		)

func _get_dist_to_rect(l_mouse: Vector2, rows: int, cols: int) -> float:
	var width = cols * CELL_SIZE + (cols - 1) * SPACING
	var height = rows * CELL_SIZE + (rows - 1) * SPACING
	var dx = maxf(0.0, maxf(-l_mouse.x, l_mouse.x - width))
	var dy = maxf(0.0, maxf(-l_mouse.y, l_mouse.y - height))
	return sqrt(dx * dx + dy * dy)

# [AI MODIFY]
func _get_drop_status(g_mouse: Vector2, data: Variant) -> Dictionary:
	var itemUI = data.get("node") if data is Dictionary else data
	var offset_px = data.get("pickup_offset", Vector2.ZERO) if data is Dictionary else Vector2.ZERO
	if not is_instance_valid(itemUI): return {"is_hit": false, "is_valid": false, "grid_pos": Vector2i(-1, -1), "is_special": false}

	var shape = itemUI.runtime_shape
	var sp_result = null
	var main_result = null

	if specialCellsContainer and specialCellsContainer.get_child_count() > 0:
		sp_result = _check_grid_hit(specialCellsContainer, g_mouse, offset_px, itemUI, shape, SPECIAL_ROWS, SPECIAL_COLS, true)

	main_result = _check_grid_hit(cellsContainer, g_mouse, offset_px, itemUI, shape, ROWS, COLS, false)

	if sp_result and sp_result.is_hit and sp_result.is_valid:
		return sp_result
	if main_result and main_result.is_hit and main_result.is_valid:
		return main_result

	if main_result and main_result.is_hit and sp_result and sp_result.is_hit:
		# [AI MODIFY]
		var l_mouse_main = cellsContainer.get_global_transform().affine_inverse() * g_mouse
		var l_mouse_sp = specialCellsContainer.get_global_transform().affine_inverse() * g_mouse
		var dist_to_main = _get_dist_to_rect(l_mouse_main, ROWS, COLS)
		var dist_to_sp = _get_dist_to_rect(l_mouse_sp, SPECIAL_ROWS, SPECIAL_COLS)
		if dist_to_main < dist_to_sp:
			return main_result
		else:
			return sp_result

	if main_result and main_result.is_hit:
		return main_result
	if sp_result and sp_result.is_hit:
		return sp_result

	return {"is_hit": false, "is_valid": false, "grid_pos": Vector2i(-1, -1), "is_special": false}

# [AI MODIFY]
func _check_grid_hit(container: Control, g_mouse: Vector2, offset_px: Vector2, itemUI: Control, shape: Array, max_r: int, max_c: int, is_special: bool) -> Dictionary:
	if container.get_child_count() == 0:
		return {"is_hit": false, "is_valid": false, "grid_pos": Vector2i(-1, -1), "is_special": is_special}

	# [AI MODIFY]
	var l_mouse = container.get_global_transform().affine_inverse() * g_mouse
	var local_item_tl = l_mouse - offset_px

	var step_local = CELL_SIZE + SPACING
	var snap_x = roundi(local_item_tl.x / step_local)
	var snap_y = roundi(local_item_tl.y / step_local)
	var snap_cell = Vector2i(snap_x, snap_y)

	var max_width = max_c * CELL_SIZE + (max_c - 1) * SPACING
	var max_height = max_r * CELL_SIZE + (max_r - 1) * SPACING
	var local_bound = Rect2(0, 0, max_width, max_height).grow(64)

	var start_node = container.get_child(0)
	var g_scale = start_node.get_global_transform().get_scale()

	var res = {
		"is_hit": false, 
		"is_valid": false, 
		"grid_pos": Vector2i(-1, -1), 
		"is_special": is_special,
		"origin_g": start_node.get_global_position(),
		"scale": g_scale,
		"scaled_cell": start_node.size.x * g_scale.x,
		"scaled_step": (start_node.size.x + SPACING) * g_scale.x
	}

	if local_bound.has_point(l_mouse):
		res.is_hit = true
		res.grid_pos = snap_cell
		res.is_valid = canPlaceItem(itemUI, res.grid_pos, is_special)

	return res

# [AI MODIFY]
func _update_drop_feedback(g_mouse: Vector2, data: Variant, status: Dictionary = {}) -> void:
	if not is_instance_valid(ghostPreview):
		ghostPreview = Control.new()
		ghostPreview.name = "GhostPreview"
		ghostPreview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghostPreview.z_index = 100
		ghostPreview.top_level = true
		add_child(ghostPreview)
		
	if status.is_empty(): status = _get_drop_status(g_mouse, data)

	for child in ghostPreview.get_children(): child.queue_free()

	if status.get("is_hit", false) and status.get("is_valid", false):
		ghostPreview.show()
		var itemUI = data.get("node") if data is Dictionary else data
		if not is_instance_valid(itemUI): return
		var shape = itemUI.runtime_shape
		var g_scale = status.get("scale", Vector2.ONE)
		var scaled_step = status.get("scaled_step", (CELL_SIZE + SPACING) * g_scale.x)
		var origin_g = status.get("origin_g", Vector2.ZERO)

		for offset in shape:
			var cell_pos = status.grid_pos + offset
			var rect = ColorRect.new()
			rect.size = Vector2(CELL_SIZE, CELL_SIZE)
			rect.global_position = origin_g + (Vector2(cell_pos) * scaled_step)
			rect.color = Color(0.1, 0.9, 0.5, 0.35)
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ghostPreview.add_child(rect)
	else:
		ghostPreview.hide()

func updateBackpackStats() -> void:
	var bomb = 0; var radius = 0; var shield = 0; var speed = 0.0; var epic = false
	var r_up = 0; var r_down = 0; var r_left = 0; var r_right = 0
	var items = []
	for r in range(ROWS):
		for c in range(COLS):
			var it = gridData[r][c]
			if it and it not in items: items.append(it)
	for r in range(SPECIAL_ROWS):
		for c in range(SPECIAL_COLS):
			var it = specialGridData[r][c]
			if it and it not in items: items.append(it)
	
	for it in items:
		var res = it.resource
		bomb += res.bomb_cap_boost; radius += res.radius_cap_boost
		r_up += res.radius_up_boost; r_down += res.radius_down_boost
		r_left += res.radius_left_boost; r_right += res.radius_right_boost
		shield += res.shield_cap_boost; speed += res.speed_cap_boost
		if res.has_persistent_shield: epic = true
	
	_syncToPlayer(bomb, radius, shield, speed, epic, r_up, r_down, r_left, r_right)

func _syncToPlayer(bomb, radius, shield, speed, epic, r_up, r_down, r_left, r_right) -> void:
	# 标注修改点：联机模式下，初始属性由服务端权威广播，不在此由本地背包直接同步覆盖
	if GameMode and not GameMode.is_offline_mode:
		return
		
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
	var layout: Array[Dictionary] = []
	var processed_items = []
	var scan_and_add = func(data_grid, is_insurance):
		for r in range(data_grid.size()):
			for c in range(data_grid[r].size()):
				var it = data_grid[r][c]
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

# ── 外部接口：自动添加物品 ──

func tryAddItem(res: BackpackItemResource, source_path: String = "") -> bool:
	if not res: return false
	
	for r in range(ROWS):
		for c in range(COLS):
			var origin = Vector2i(c, r)
			if canPlaceItem_by_shape(res, origin):
				var itemUIScene = load("res://prefabs/Backpack/sub/backpack_item.tscn")
				if not itemUIScene: return false
				var itemUI = itemUIScene.instantiate()
				itemUI.setup(res, source_path)
				itemsContainer.add_child(itemUI)
				placeItem(itemUI, origin)
				return true

	for r in range(SPECIAL_ROWS):
		for c in range(SPECIAL_COLS):
			var origin = Vector2i(c, r)
			if canPlaceItemInSpecial_by_shape(res, origin):
				var itemUIScene = load("res://prefabs/Backpack/sub/backpack_item.tscn")
				if not itemUIScene: return false
				var itemUI = itemUIScene.instantiate()
				itemUI.setup(res, source_path)
				specialItemsContainer.add_child(itemUI)
				placeItemInSpecial(itemUI, origin)
				return true

	return false

# [AI MODIFY]
func canPlaceItem_by_shape(res: BackpackItemResource, origin: Vector2i) -> bool:
	var shape = res.shape
	for offset in shape:
		var target = origin + offset
		if target.x < 0 or target.x >= COLS or target.y < 0 or target.y >= ROWS:
			return false
		if gridData[target.y][target.x] != null:
			return false
	return true

# [AI MODIFY]
func canPlaceItemInSpecial_by_shape(res: BackpackItemResource, origin: Vector2i) -> bool:
	var shape = res.shape
	for offset in shape:
		var target = origin + offset
		if target.x < 0 or target.x >= SPECIAL_COLS or target.y < 0 or target.y >= SPECIAL_ROWS:
			return false
		if specialGridData[target.y][target.x] != null:
			return false
	return true

func get_all_item_resources(only_special: bool = false) -> Array:
	var res_list = []
	var items = []
	if only_special:
		for r in range(SPECIAL_ROWS):
			for c in range(SPECIAL_COLS):
				var it = specialGridData[r][c]
				if it and it not in items: items.append(it)
	else:
		for r in range(ROWS):
			for c in range(COLS):
				var it = gridData[r][c]
				if it and it not in items: items.append(it)
		for r in range(SPECIAL_ROWS):
			for c in range(SPECIAL_COLS):
				var it = specialGridData[r][c]
				if it and it not in items: items.append(it)
	
	for it in items: res_list.append(it.resource)
	return res_list

# ── 拖拽和输入连结 ──

func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging = true
				_drag_offset = get_global_mouse_position() - global_position
			else:
				_is_dragging = false
	elif event is InputEventMouseMotion:
		if _is_dragging:
			global_position = get_global_mouse_position() - _drag_offset

# ── 底部功能按钮接口已移除 ──

# ── 右键战术快捷菜单系统 ──

func _init_context_menu() -> void:
	contextMenu = PanelContainer.new()
	contextMenu.name = "RightClickContextMenu"
	contextMenu.visible = false
	contextMenu.z_index = 110
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#121522")
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color("#d4af37")
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 6
	style.content_margin_top = 6
	style.content_margin_right = 6
	style.content_margin_bottom = 6
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 8
	contextMenu.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	contextMenu.add_child(vbox)
	
	var btn_style_normal = StyleBoxFlat.new()
	btn_style_normal.bg_color = Color("#1a1d2e")
	btn_style_normal.set_corner_radius_all(4)
	btn_style_normal.content_margin_left = 10
	btn_style_normal.content_margin_right = 10
	btn_style_normal.content_margin_top = 6
	btn_style_normal.content_margin_bottom = 6
	
	var btn_style_hover = StyleBoxFlat.new()
	btn_style_hover.bg_color = Color("#22263a")
	btn_style_hover.border_color = Color("#4a90e2")
	btn_style_hover.border_width_left = 1
	btn_style_hover.border_width_top = 1
	btn_style_hover.border_width_right = 1
	btn_style_hover.border_width_bottom = 1
	btn_style_hover.set_corner_radius_all(4)
	btn_style_hover.content_margin_left = 10
	btn_style_hover.content_margin_right = 10
	btn_style_hover.content_margin_top = 5
	btn_style_hover.content_margin_bottom = 5
	
	var make_btn = func(text: String) -> Button:
		var btn = Button.new()
		btn.text = text
		btn.flat = false
		btn.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_stylebox_override("normal", btn_style_normal)
		btn.add_theme_stylebox_override("hover", btn_style_hover)
		btn.add_theme_font_size_override("font_size", 12)
		vbox.add_child(btn)
		return btn
		
	menuUseBtn = make_btn.call("⚡ 使用装备")
	menuInsuranceBtn = make_btn.call("🔒 移入保险格")
	menuDiscardBtn = make_btn.call("🗑️ 快捷丢弃")
	menuCancelBtn = make_btn.call("× 取消")
	
	menuUseBtn.pressed.connect(_on_menu_use_pressed)
	menuInsuranceBtn.pressed.connect(_on_menu_insurance_pressed)
	menuDiscardBtn.pressed.connect(_on_menu_discard_pressed)
	menuCancelBtn.pressed.connect(func(): contextMenu.hide())
	
	add_child(contextMenu)

# [AI MODIFY]
func _on_item_right_clicked(itemUI: Control) -> void:
	active_context_item = itemUI
	if not is_instance_valid(contextMenu): return
	
	var in_insurance = false
	for r in range(SPECIAL_ROWS):
		for c in range(SPECIAL_COLS):
			if specialGridData[r][c] == itemUI:
				in_insurance = true
				break
		if in_insurance: break
		
	menuInsuranceBtn.visible = true
	if in_insurance:
		menuInsuranceBtn.text = "🎒 移回主背包"
	else:
		menuInsuranceBtn.text = "🔒 移入保险格"
		
	contextMenu.show()
	contextMenu.global_position = get_global_mouse_position() + Vector2(4, 4)

func _on_menu_use_pressed() -> void:
	if not is_instance_valid(active_context_item): return
	contextMenu.hide()
	
	var hud = get_tree().get_first_node_in_group("HUD") if get_tree() else null
	if not hud:
		var stage = get_parent()
		if stage: hud = stage.get_node_or_null("HUD")
	if hud and hud.has_method("showNotification"):
		hud.showNotification("战术道具 " + active_context_item.resource.item_name + " 正在持续提供属性增益", 2.5)

func _on_menu_insurance_pressed() -> void:
	if not is_instance_valid(active_context_item): return
	contextMenu.hide()
	var it = active_context_item
	
	var in_insurance = false
	var item_pos = Vector2i(-1, -1)
	for r in range(SPECIAL_ROWS):
		for c in range(SPECIAL_COLS):
			if specialGridData[r][c] == it:
				in_insurance = true
				item_pos = it.gridPos
				break
		if in_insurance: break
		
	var hud = get_tree().get_first_node_in_group("HUD") if get_tree() else null
	if not hud:
		var stage = get_parent()
		if stage: hud = stage.get_node_or_null("HUD")
		
	if in_insurance:
		removeItem(it)
		var placed = false
		for r in range(ROWS):
			for c in range(COLS):
				var origin = Vector2i(c, r)
				if canPlaceItem(it, origin, false):
					placeItem(it, origin)
					placed = true
					break
			if placed: break
		if not placed:
			placeItemInSpecial(it, item_pos)
			if hud and hud.has_method("showNotification"):
				hud.showNotification("主背包空间不足，移回主包失败", 2.0)
	else:
		var item_old_pos = it.gridPos
		removeItem(it)
		var placed = false
		for r in range(SPECIAL_ROWS):
			for c in range(SPECIAL_COLS):
				var origin = Vector2i(c, r)
				if canPlaceItem(it, origin, true):
					placeItemInSpecial(it, origin)
					placed = true
					break
			if placed: break
		if not placed:
			placeItem(it, item_old_pos)
			if hud and hud.has_method("showNotification"):
				hud.showNotification("保险格空间不足，移入保险格失败", 2.0)

func _on_menu_discard_pressed() -> void:
	if not is_instance_valid(active_context_item): return
	contextMenu.hide()
	var it = active_context_item
	removeItem(it)
	it.play_disappear_animation()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if is_instance_valid(contextMenu) and contextMenu.visible:
			if not contextMenu.get_global_rect().has_point(get_global_mouse_position()):
				contextMenu.hide()

# [AI MODIFY]
func get_items_container() -> Control:
	return itemsContainer

# [AI MODIFY]
func _clear_ghost_preview() -> void:
	if is_instance_valid(ghostPreview):
		ghostPreview.queue_free()
		ghostPreview = null

# [AI MODIFY]
func _on_mouse_exited() -> void:
	_clear_ghost_preview()

# [AI MODIFY]
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_ghost_preview()

# [AI MODIFY]
func _exit_tree() -> void:
	_clear_ghost_preview()
