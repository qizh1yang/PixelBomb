# 掉落物品显示网格 - 工业级精准对齐版
# 更新：2026-05-11 - 修复关闭按钮，支持全局缩放对齐

extends Control

class_name LootGrid

# ── 常量 ──
const CELL_SIZE: int = 64
const SPACING: int = 8

# ── 属性 ──
@export var rows: int = 6
@export var cols: int = 4

# ── 节点引用 ──
@onready var cellsContainer: Control = $Cells
@onready var itemsContainer: Control = $Items
@onready var takeAllBtn: Button = get_parent().get_node_or_null("TakeAllBtn")

# ── 内部变量 ──
var gridData: Array = []
var ghostPreview: Control = null
# [AI MODIFY]
var specialItemsContainer: Control = null

func _ready() -> void:
	# [AI MODIFY]
	mouse_filter = Control.MOUSE_FILTER_STOP
	if is_instance_valid(cellsContainer): cellsContainer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(itemsContainer): itemsContainer.mouse_filter = Control.MOUSE_FILTER_PASS

	itemsContainer.name = "LootItems"
	_initGridData()
	_drawGrid()
	
	if takeAllBtn:
		takeAllBtn.pressed.connect(_on_take_all_pressed)
		
	# 1. 递归设置透传，允许双向拖入
	_set_mouse_filter_recursive(get_parent())
	
	# 2. 初始化独立预览层
	# [AI MODIFY]
	if is_instance_valid(ghostPreview):
		ghostPreview.queue_free()
		ghostPreview = null
	
	# [AI MODIFY]
	if not mouse_exited.is_connected(_clear_ghost_preview):
		mouse_exited.connect(_clear_ghost_preview)
	
	# 3. 动态创建关闭按钮 (必须通过 call_deferred)
	_setup_close_button.call_deferred()

func _set_mouse_filter_recursive(node: Node) -> void:
	if node is Control:
		if node is Container or node is TextureRect or "Area" in node.name or "Grid" in node.name or node is Panel:
			node.mouse_filter = Control.MOUSE_FILTER_PASS
	for child in node.get_children():
		_set_mouse_filter_recursive(child)

func _setup_close_button() -> void:
	var win = get_parent()
	if not win: return
	var close_btn = win.get_node_or_null("CloseBtn")
	if not close_btn:
		close_btn = Button.new()
		close_btn.text = " X "
		close_btn.name = "CloseBtn"
		close_btn.add_theme_color_override("font_color", Color.WHITE)
		close_btn.add_theme_color_override("font_hover_color", Color.RED)
		close_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		close_btn.offset_left = -45
		close_btn.offset_top = 5
		close_btn.offset_right = -5
		close_btn.offset_bottom = 45
		win.add_child(close_btn)
	
	if not close_btn.pressed.is_connected(_on_close_clicked):
		close_btn.pressed.connect(_on_close_clicked)

func _on_close_clicked() -> void:
	var bp = get_tree().get_first_node_in_group("Backpack")
	if bp: bp.set_layout_mode(false)
	var win = get_parent().get_parent() # 获取 LootWindow 根节点
	if is_instance_valid(win):
		win.queue_free()
	else:
		get_parent().queue_free()

func _initGridData() -> void:
	gridData.clear()
	for r in range(rows):
		var row_arr = []
		for c in range(cols): row_arr.append(null)
		gridData.append(row_arr)

func _drawGrid() -> void:
	for child in cellsContainer.get_children(): child.queue_free()
	var cell_scene = load("res://prefabs/Backpack/sub/InventoryCell.tscn")
	for r in range(rows):
		for c in range(cols):
			var cell = cell_scene.instantiate()
			cell.is_special = false
			cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
			cell.position = Vector2(c * (CELL_SIZE + SPACING), r * (CELL_SIZE + SPACING))
			cellsContainer.add_child(cell)

# ── 核心状态机 (全缩放适配版) ──

func _get_drag_status(g_mouse: Vector2, data: Variant) -> Dictionary:
	var itemUI = data.node if data is Dictionary else data
	var offset_px = data.pickup_offset if data is Dictionary else Vector2.ZERO
	
	# 【核心校准】获取物理格子的真实位置和当前整体缩放
	var start_node = cellsContainer.get_child(0) if cellsContainer.get_child_count() > 0 else cellsContainer
	var true_origin_g = start_node.get_global_position()
	var g_scale = start_node.get_global_transform().get_scale()
	
	# 动态获取插槽本身的尺寸，避免硬编码 64 的尺寸误差
	var cell_w = start_node.size.x if (start_node is Control and start_node.size.x > 0) else float(CELL_SIZE)
	
	var scaled_cell = cell_w * g_scale.x
	var scaled_step = (cell_w + SPACING) * g_scale.x
	
	# 如果子节点多于1个，动态计算更精确的步长（包含实际间距）
	if cellsContainer.get_child_count() > 1:
		var node0 = cellsContainer.get_child(0)
		for i in range(1, cellsContainer.get_child_count()):
			var nodeI = cellsContainer.get_child(i)
			if abs(nodeI.get_global_position().y - node0.get_global_position().y) < 1.0:
				var dist = nodeI.get_global_position().x - node0.get_global_position().x
				if dist > 0:
					scaled_step = dist
					break
	
	# 核心修复：这里必须乘以全局缩放 g_scale，而不是 itemUI 本地的 scale，以消除 UI 缩放带来的偏移
	var item_tl_g = g_mouse - (offset_px * g_scale)
	var item_center = item_tl_g + Vector2(scaled_cell/2.0, scaled_cell/2.0)
	
	# 感应区 (带 10px 边缘容错)
	var bound = Rect2(true_origin_g, Vector2(cols * scaled_step - SPACING * g_scale.x, rows * scaled_step - SPACING * g_scale.y)).grow(10)
	
	var res = {"is_hit": false, "grid_pos": Vector2i(-1,-1), "is_valid": false, "origin_g": true_origin_g, "scale": g_scale, "scaled_step": scaled_step, "scaled_cell": scaled_cell}
	
	if bound.has_point(item_center):
		res.is_hit = true
		res.grid_pos = Vector2i(
			round((item_tl_g.x - true_origin_g.x) / scaled_step), 
			round((item_tl_g.y - true_origin_g.y) / scaled_step)
		)
		res.is_valid = canPlaceItem(itemUI, res.grid_pos)
		
	return res

func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	var g_mouse = get_global_mouse_position()
	var status = _get_drag_status(g_mouse, data)
	_update_drag_feedback(g_mouse, data, status)
	return status.is_valid

# [AI MODIFY]
func _update_drag_feedback(g_mouse: Vector2, data: Variant, status: Dictionary = {}) -> void:
	# [AI MODIFY]
	if not is_instance_valid(ghostPreview):
		ghostPreview = Control.new()
		ghostPreview.name = "GhostPreview"
		ghostPreview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghostPreview.z_index = 100
		ghostPreview.top_level = true
		add_child(ghostPreview)
	
	if status.is_empty(): status = _get_drag_status(g_mouse, data)
	
	for child in ghostPreview.get_children(): child.queue_free()
	
	if status.is_hit and status.is_valid:
		ghostPreview.show()
		var itemUI = data.node if data is Dictionary else data
		var color = Color(0.1, 0.9, 0.5, 0.35) # 极具科幻质感的半透明翡翠绿，完美覆盖上方
		var g_scale = status.get("scale", Vector2.ONE)
		var scaled_cell = status.get("scaled_cell", CELL_SIZE * g_scale.x)
		var scaled_step = status.get("scaled_step", (CELL_SIZE + SPACING) * g_scale.x)
		
		# 核心状态同步，绘制拖拽预览
		# [AI MODIFY]
		var shape = itemUI.runtime_shape
		for offset in shape:
			var cell_pos = status.grid_pos + offset
			var rect = ColorRect.new()
			rect.size = Vector2(CELL_SIZE, CELL_SIZE)
			rect.global_position = status.origin_g + (Vector2(cell_pos) * scaled_step)
			rect.color = color
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ghostPreview.add_child(rect)
	else:
		ghostPreview.hide()

# [AI MODIFY]
func _drop_data(_pos: Vector2, data: Variant) -> void:
	# [AI MODIFY]
	_clear_ghost_preview()
	var g_mouse = get_global_mouse_position()
	var status = _get_drag_status(g_mouse, data)
	var itemUI = data.node if data is Dictionary else data
	
	if not status.is_valid or not is_instance_valid(itemUI): return
	
	# [AI MODIFY]
	var dc = get_node_or_null("/root/DragCoordinator")
	if dc:
		dc.transfer(
			self,
			status.grid_pos
		)

# ── 业务逻辑 ──

# [AI MODIFY]
func canPlaceItem(itemUI: Control, origin: Vector2i, is_special: bool = false) -> bool:
	# [AI MODIFY]
	var shape = itemUI.runtime_shape
	for offset in shape:
		var r = origin.y + offset.y
		var c = origin.x + offset.x
		if r < 0 or r >= rows or c < 0 or c >= cols: return false
		var existing = gridData[r][c]
		if existing and existing != itemUI: return false
	return true

# [AI MODIFY]
func placeItem(itemUI: Control, origin: Vector2i) -> void:
	_removeItemFromData(itemUI)
	if itemUI.get_parent(): itemUI.get_parent().remove_child(itemUI)
	itemsContainer.add_child(itemUI)
	# [AI MODIFY]
	var shape = itemUI.runtime_shape
	for offset in shape:
		gridData[origin.y + offset.y][origin.x + offset.x] = itemUI
	itemUI.position = Vector2(origin.x * (CELL_SIZE + SPACING), origin.y * (CELL_SIZE + SPACING))
	itemUI.gridPos = origin

# [AI MODIFY]
func removeItem(itemUI: Control) -> void:
	_removeItemFromData(itemUI)

func _removeItemFromData(itemUI: Control) -> void:
	for r in range(rows):
		for c in range(cols):
			if gridData[r][c] == itemUI: gridData[r][c] = null

func notify_item_removed(itemUI: Control) -> void:
	if is_instance_valid(itemUI): _removeItemFromData(itemUI)

func fillRandomItems(item_paths: Array, count: int) -> void:
	var itemUIScene = load("res://prefabs/Backpack/sub/backpack_item.tscn")
	var spawned = 0
	for path in item_paths:
		if spawned >= count: break
		var res = load(path) as BackpackItemResource
		if not res: continue
		var itemUI = itemUIScene.instantiate()
		itemUI.setup(res, path)
		var found = false
		for r in range(rows):
			for c in range(cols):
				if canPlaceItem(itemUI, Vector2i(c, r)):
					placeItem(itemUI, Vector2i(c, r)); found = true; spawned += 1; break
			if found: break
		if not found: itemUI.queue_free()

func _on_take_all_pressed() -> void:
	var bp = get_tree().get_first_node_in_group("Backpack")
	if not bp: return
	var items_to_move = []
	for r in range(rows):
		for c in range(cols):
			var it = gridData[r][c]
			if it and it not in items_to_move: items_to_move.append(it)
	for it in items_to_move:
		if bp.tryAddItem(it.resource, it.source_path):
			_removeItemFromData(it)
			if it.get_parent(): it.get_parent().remove_child(it)
			it.queue_free()
	print("[宝箱] 全部拾取完成")

# [AI MODIFY]
func get_items_container() -> Control:
	return itemsContainer

# [AI MODIFY]
func _clear_ghost_preview() -> void:
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
