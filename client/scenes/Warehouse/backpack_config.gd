extends Control

# 战前战备逻辑 (1920x1080 适配版)
# 处理背包与仓库之间物品的转移、保存、售卖及战备方案

# ── 信号 ──
signal item_packed(res: BackpackItemResource, path: String)
signal item_sold(res: BackpackItemResource, path: String, price: int)

# ── 节点引用 ──
@onready var mainBackpack = %MainBackpack
@onready var warehouseGrid = %WarehouseGrid
@onready var coinLabel = %CoinLabel
@onready var itemCountLabel = %ItemCount
@onready var confirmDialog = %ConfirmDialog
@onready var dialogMsg = %DialogMsg
@onready var dialogPrice = %DialogPrice
@onready var dialogTitle = %ConfirmDialog.get_node("DialogVBox/DialogTitle") as Label
@onready var dialogConfirm = %ConfirmDialog.get_node("DialogVBox/DialogBtnRow/DialogConfirm") as Button

# 统计面板
@onready var bombStat = %BombStat
@onready var speedStat = %SpeedStat
@onready var radiusStat = %RadiusStat
@onready var shieldStat = %ShieldStat
@onready var loadStat = %LoadStat



# 弹窗引用
@onready var detailDialog = %DetailDialog
@onready var detailClose = %DetailClose
@onready var detailIcon = %DetailIcon
@onready var detailName = %DetailName
@onready var detailType = %DetailType
@onready var detailDesc = %DetailDesc
@onready var detailPackBtn = %DetailPackBtn
@onready var detailSellBtn = %DetailSellBtn

@onready var contextMenu = %ContextMenu
@onready var ctxDetail = %CtxDetail
@onready var ctxSell = %CtxSell

var _pending_detail_res: BackpackItemResource = null
var _pending_detail_path: String = ""
var _pending_detail_source: String = "" # "warehouse" or "backpack"
var _pending_detail_node: Control = null

# 筛选标签
@onready var tabAll = %TabAll
@onready var tabBomb = %TabBomb
@onready var tabSpeed = %TabSpeed
@onready var tabRange = %TabRange
@onready var tabSpecial = %TabSpecial

# 战备方案按钮
@onready var preset1 = %Preset1
@onready var preset2 = %Preset2
@onready var preset3 = %Preset3

# 排序按钮
@onready var sortBtn = %SortBtn

var ItemCardScene = preload("res://scenes/Warehouse/sub/item_card.tscn")

# 筛选状态: -1=全部, 0=BOMB, 1=SPEED, 2=RANGE, 3=SPECIAL
var current_category: int = -1
# 排序模式: 0=默认, 1=品质高到低, 2=格子小到大
var sort_mode: int = 0

# 售出与操作对话框暂存
var _pending_sell_path: String = ""
var _pending_sell_res: BackpackItemResource = null
var _pending_sell_price: int = 0
var _dialog_mode: String = "" # "sell", "clear", "sort"

var _initial_coins: int = 0
var _initial_backpack: Array[Dictionary] = []
var _initial_owned: Array[String] = []

# 【黄金优化】：用于过滤本地拖放导致的重复清空与重建逻辑，让道具在拖放后 100% 保持精准物理定位，不闪烁、不失效！
var _ignore_rebuild: bool = false

func _ready() -> void:
	# 记录进入界面时的初始状态以便未点击确认配备时回滚
	_initial_coins = GlobalPlayerData.coins
	
	_initial_backpack.clear()
	for d in GlobalPlayerData.backpack_config:
		_initial_backpack.append(d.duplicate(true))
		
	_initial_owned.clear()
	for o in GlobalPlayerData.owned_items:
		_initial_owned.append(o)

	# 延迟一帧，确保布局大小计算完毕后进行完美的居中对齐
	get_tree().process_frame.connect(func():
		_update_ui_scale(1.0)
	, ConnectFlags.CONNECT_ONE_SHOT)

	# 【核心视觉适配与全屏黄金紧凑排布】
	var mainContent = %MainContent
	var backpackPanel = %BackpackPanel
	var warehousePanel = %WarehousePanel
	var vsep = mainContent.get_node_or_null("VSeparator")
	
	if mainContent and backpackPanel and warehousePanel:
		# 清理已有的 spacer 节点，防止重复创建
		for child in mainContent.get_children():
			if child.name in ["LeftSpacer", "RightSpacer", "MidSpacer", "MidGap"]:
				child.queue_free()
				
		# 1. 插入最左侧弹性对齐 Spacer
		var leftSpacer = Control.new()
		leftSpacer.name = "LeftSpacer"
		mainContent.add_child(leftSpacer)
		
		# 2. 插入最右侧弹性对齐 Spacer
		var rightSpacer = Control.new()
		rightSpacer.name = "RightSpacer"
		mainContent.add_child(rightSpacer)
		
		# 3. 设置面板大小紧密贴合内部格子物理宽度，实现完美的右侧无留白
		backpackPanel.custom_minimum_size = Vector2(568, 0)
		warehousePanel.custom_minimum_size = Vector2(904, 0)
		
		# 4. 仅使用 custom_minimum_size 承载宽度，不要额外延伸填满
		backpackPanel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		warehousePanel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		
		# 5. 按照几何顺序重新排序子节点
		mainContent.move_child(leftSpacer, 0)
		mainContent.move_child(backpackPanel, 1)
		if vsep:
			mainContent.move_child(vsep, 2)
			mainContent.move_child(warehousePanel, 3)
			mainContent.move_child(rightSpacer, 4)
		else:
			mainContent.move_child(warehousePanel, 2)
			mainContent.move_child(rightSpacer, 3)

		# 6. 让两边的子网格在滚动区域中双向居中对齐，彻底消除边缘和下方死角留白
		mainBackpack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mainBackpack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		warehouseGrid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		warehouseGrid.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		# 7. 动态绑定窗口尺寸变化信号，支持 1080p 至 4K 全自适应居中对齐
		if not get_viewport().size_changed.is_connected(_update_layout_spacers):
			get_viewport().size_changed.connect(_update_layout_spacers)
			
		# 8. 首次触发计算
		_update_layout_spacers()

	# 开启双向格子的整备交互模式
	mainBackpack.set_layout_mode(true)
	mainBackpack.open_backpack()
	
	warehouseGrid.set_layout_mode(true)
	warehouseGrid.open_backpack()

	# 连接已装备背包的信号
	mainBackpack.item_clicked.connect(_on_backpack_item_clicked)
	mainBackpack.backpack_stats_updated.connect(_update_stats_preview)
	if mainBackpack.has_signal("item_dropped_from_warehouse"):
		mainBackpack.item_dropped_from_warehouse.connect(_on_item_dropped_from_warehouse)
	if mainBackpack.has_signal("item_detail_requested"):
		mainBackpack.item_detail_requested.connect(_on_backpack_item_detail_requested)
	if mainBackpack.has_signal("item_moved_internally"):
		mainBackpack.item_moved_internally.connect(func(): _save_both())

	# 连接仓库网格的信号
	warehouseGrid.item_clicked.connect(_on_warehouse_item_double_clicked)
	if warehouseGrid.has_signal("item_dropped_from_warehouse"):
		warehouseGrid.item_dropped_from_warehouse.connect(_on_item_dropped_from_backpack)
	if warehouseGrid.has_signal("item_detail_requested"):
		warehouseGrid.item_detail_requested.connect(_on_warehouse_item_detail_requested)
	if warehouseGrid.has_signal("item_moved_internally"):
		warehouseGrid.item_moved_internally.connect(func(): _save_both())

	# 弹窗按钮连接
	detailClose.pressed.connect(_close_detail_dialog)
	detailPackBtn.pressed.connect(_on_detail_pack_pressed)
	detailSellBtn.pressed.connect(_on_detail_sell_pressed)
	ctxDetail.pressed.connect(_on_ctx_detail_pressed)
	ctxSell.pressed.connect(_on_ctx_sell_pressed)

	# 监听全局数据同步
	GlobalPlayerData.inventory_updated.connect(_on_data_updated)
	GlobalPlayerData.backpack_updated.connect(_on_data_updated)

	# 连接筛选标签
	tabAll.pressed.connect(_on_filter_pressed.bind(-1))
	tabBomb.pressed.connect(_on_filter_pressed.bind(0))
	tabSpeed.pressed.connect(_on_filter_pressed.bind(1))
	tabRange.pressed.connect(_on_filter_pressed.bind(2))
	tabSpecial.pressed.connect(_on_filter_pressed.bind(3))

	# 排序按钮
	sortBtn.pressed.connect(_on_sort_pressed)

	# 动态创建并连接自动整理背包按钮
	var bottom_hbox = get_node_or_null("BottomBar/BottomHBox")
	if bottom_hbox:
		var auto_sort_btn = Button.new()
		auto_sort_btn.name = "AutoSortBtn"
		auto_sort_btn.text = "自动整理背包"
		auto_sort_btn.custom_minimum_size = Vector2(200, 52) # 设为统一的 52 高度，确保对称
		var clear_btn = bottom_hbox.get_node_or_null("ClearBtn")
		if clear_btn:
			auto_sort_btn.theme = clear_btn.theme
			for mode in ["normal", "hover", "pressed"]:
				var style = clear_btn.get_theme_stylebox(mode)
				if style: auto_sort_btn.add_theme_stylebox_override(mode, style)
		bottom_hbox.add_child(auto_sort_btn)
		bottom_hbox.move_child(auto_sort_btn, 1) # 排在 ClearBtn (0) 的右侧
		auto_sort_btn.pressed.connect(_on_auto_sort_backpack_pressed)

	# 战备方案按钮 (暂时禁止使用，置灰)
	for btn in [preset1, preset2, preset3]:
		if btn:
			btn.disabled = true
			btn.modulate = Color(0.5, 0.5, 0.5, 0.5)

	# ─── 高规格 UI 排版整齐对齐与美化 ───
	# 1. 隐藏重复的物资仓库计数文本，杜绝多余信息
	if itemCountLabel:
		itemCountLabel.visible = false

	# 2. 统一操作按钮尺寸为 Y=52，确保完美的对称对齐
	var clear_btn = get_node_or_null("BottomBar/BottomHBox/ClearBtn")
	if clear_btn:
		clear_btn.custom_minimum_size = Vector2(200, 52)
		
	var discard_btn = get_node_or_null("TopBar/HBox/RightBox/DiscardBtn")
	if discard_btn:
		discard_btn.custom_minimum_size = Vector2(140, 52)
		
	var confirm_btn = get_node_or_null("TopBar/HBox/RightBox/ConfirmBtn")
	if confirm_btn:
		confirm_btn.custom_minimum_size = Vector2(160, 52)

	# 3. 确保 TopBar 内部所有节点和容器垂直居中对齐
	var hbox = get_node_or_null("TopBar/HBox")
	if hbox:
		for child in hbox.get_children():
			if child is Control:
				child.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				if child is HBoxContainer:
					for sub_child in child.get_children():
						if sub_child is Control:
							sub_child.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# 4. 整理底部栏对齐，隐藏 Spacer4，并垂直居中所有子节点
	if bottom_hbox:
		var spacer4 = bottom_hbox.get_node_or_null("Spacer4")
		if spacer4:
			spacer4.visible = false
			
		for child in bottom_hbox.get_children():
			if child is Control:
				child.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# 5. 统一分类筛选标签的尺寸
	var tabs = [tabAll, tabBomb, tabSpeed, tabRange, tabSpecial]
	for btn in tabs:
		if btn:
			btn.custom_minimum_size = Vector2(140, 44)
			
	# 6. 美化排序按钮，使其与普通分类标签产生显著视觉区隔
	var sort_normal = StyleBoxFlat.new()
	sort_normal.bg_color = Color("#0f2035a0") # 极深蓝半透明
	sort_normal.border_width_left = 1
	sort_normal.border_width_top = 1
	sort_normal.border_width_right = 1
	sort_normal.border_width_bottom = 1
	sort_normal.border_color = Color("#00a3ffb0") # 霓虹科技蓝/青色半透明边框
	sort_normal.corner_radius_top_left = 6
	sort_normal.corner_radius_top_right = 6
	sort_normal.corner_radius_bottom_right = 6
	sort_normal.corner_radius_bottom_left = 6
	
	var sort_hover = sort_normal.duplicate()
	sort_hover.bg_color = Color("#142f4ca0")
	sort_hover.border_color = Color("#00c3ffd0")
	
	var sort_pressed = sort_normal.duplicate()
	sort_pressed.bg_color = Color("#0c1b2c")
	sort_pressed.border_color = Color("#0070c0")
	
	if sortBtn:
		sortBtn.add_theme_stylebox_override("normal", sort_normal)
		sortBtn.add_theme_stylebox_override("hover", sort_hover)
		sortBtn.add_theme_stylebox_override("pressed", sort_pressed)
		sortBtn.add_theme_color_override("font_color", Color("#00c3ff")) # 亮青色字体
		sortBtn.custom_minimum_size = Vector2(150, 44)

	# 初始化
	_on_data_updated()
	_ignore_rebuild = true

# ══════════════════════════════════════
# UI 刷新
# ══════════════════════════════════════

func _on_data_updated() -> void:
	if _ignore_rebuild:
		# [AI MODIFY] 本地操作引起的更新：不重建网格，只更新金币/统计面板
		# 不能调用 _refresh_ui()，因为它会调用 _render_warehouse_list() 导致仓库物品被销毁重建
		_refresh_ui_silent()
		return
		
	_load_current_config()
	_refresh_ui()

func _refresh_ui() -> void:
	# 更新金币
	if coinLabel:
		coinLabel.text = "💰   %s" % _format_number(GlobalPlayerData.coins)

	# 更新物品计数
	if itemCountLabel:
		itemCountLabel.text = "%d 件物资" % GlobalPlayerData.owned_items.size()

	# 更新统计栏与预览
	mainBackpack.updateBackpackStats()
	_update_stats_bar()

	# 更新战备方案按钮高亮
	_update_preset_buttons()

	# 渲染仓库物品列表
	_render_warehouse_list()

func _refresh_ui_silent() -> void:
	if coinLabel:
		coinLabel.text = "💰   %s" % _format_number(GlobalPlayerData.coins)
	if itemCountLabel:
		itemCountLabel.text = "%d 件物资" % GlobalPlayerData.owned_items.size()
	mainBackpack.updateBackpackStats()
	_update_stats_bar()
	_update_preset_buttons()

func _update_stats_bar() -> void:
	# 从背包获取占用格数
	var main_count = 0
	var processed = []
	# [AI MODIFY]
	for r in range(mainBackpack.ROWS):
		for c in range(mainBackpack.COLS):
			var cell = mainBackpack.gridData[r][c]
			if cell is Array:
				for it in cell:
					if it and it not in processed:
						processed.append(it)
						main_count += it.runtime_shape.size()
			else:
				var it = cell
				if it and it not in processed:
					processed.append(it)
					main_count += it.runtime_shape.size()

	# 从保险箱获取占用格数
	var spec_count = 0
	# [AI MODIFY]
	for r in range(mainBackpack.SPECIAL_ROWS):
		for c in range(mainBackpack.SPECIAL_COLS):
			var cell = mainBackpack.specialGridData[r][c]
			if cell is Array:
				for it in cell:
					if it and it not in processed:
						processed.append(it)
						spec_count += it.runtime_shape.size()
			else:
				var it = cell
				if it and it not in processed:
					processed.append(it)
					spec_count += it.runtime_shape.size()

	# ── 随身背包标题容量动态更新 ──
	var bTitle = get_node_or_null("MainContent/BackpackPanel/BVBox/BHeader/BTitle")
	if bTitle:
		if spec_count > 0:
			bTitle.text = "已装备 [ %d/30 ] (保险箱 [ %d/4 ])" % [main_count, spec_count]
		else:
			bTitle.text = "已装备 [ %d/30 ]" % main_count
		bTitle.add_theme_font_size_override("font_size", 32)
		
		# 80% 黄色，95% 红色亮眼提示
		var pct = float(main_count) / 30.0
		if pct >= 0.95:
			bTitle.add_theme_color_override("font_color", Color("#ff4444"))
		elif pct >= 0.8:
			bTitle.add_theme_color_override("font_color", Color("#ffd700"))
		else:
			bTitle.add_theme_color_override("font_color", Color("#ffffff"))

	# ── 物资仓库标题容量动态更新 ──
	var wTitle = get_node_or_null("MainContent/WarehousePanel/WVBox/WHeader/WTitle")
	var owned_count = GlobalPlayerData.owned_items.size()
	if wTitle:
		wTitle.text = "物资仓库 [ %d/96 ]" % owned_count
		wTitle.add_theme_font_size_override("font_size", 32)
		
		# 80% 黄色，95% 红色亮眼提示
		var pct = float(owned_count) / 96.0
		if pct >= 0.95:
			wTitle.add_theme_color_override("font_color", Color("#ff4444"))
		elif pct >= 0.8:
			wTitle.add_theme_color_override("font_color", Color("#ffd700"))
		else:
			wTitle.add_theme_color_override("font_color", Color("#ffffff"))

# ── 拖拽系统 (已在子网格中处理) ──
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	pass

func _update_stats_preview(bomb: int, radius: int, shield: int, speed: float, epic: bool, r_up: int, r_down: int, r_left: int, r_right: int) -> void:
	if not bombStat: return
	
	# 💣 炸弹容量
	if bomb > 0:
		bombStat.text = "💣   炸弹容量: 1 (+%d)" % bomb
		bombStat.add_theme_color_override("font_color", Color("#00ff00"))
	else:
		bombStat.text = "💣   炸弹容量: 1"
		bombStat.add_theme_color_override("font_color", Color("#909090"))
		
	# 👟 移动速度
	if speed > 0:
		speedStat.text = "👟   移动速度: 100%% (+%.0f%%)" % [speed * 100]
		speedStat.add_theme_color_override("font_color", Color("#00ff00"))
	else:
		speedStat.text = "👟   移动速度: 100%"
		speedStat.add_theme_color_override("font_color", Color("#909090"))
		
	# 🔥 爆炸威力
	var range_parts = []
	if radius > 0: range_parts.append("全 +%d" % radius)
	if r_up > 0: range_parts.append("上 +%d" % r_up)
	if r_down > 0: range_parts.append("下 +%d" % r_down)
	if r_left > 0: range_parts.append("左 +%d" % r_left)
	if r_right > 0: range_parts.append("右 +%d" % r_right)
	if range_parts.size() > 0:
		radiusStat.text = "🔥   爆炸威力: 3 (%s)" % (" | ".join(range_parts))
		radiusStat.add_theme_color_override("font_color", Color("#00ff00"))
	else:
		radiusStat.text = "🔥   爆炸威力: 3"
		radiusStat.add_theme_color_override("font_color", Color("#909090"))
		
	# 🛡️ 免死护盾
	var total_shields = shield + (1 if epic else 0)
	if total_shields > 0:
		shieldStat.text = "🛡️   免死护盾: +%d" % total_shields
		shieldStat.add_theme_color_override("font_color", Color("#00ff00"))
	else:
		shieldStat.text = "🛡️   免死护盾: 0"
		shieldStat.add_theme_color_override("font_color", Color("#909090"))
		
	# 📦 背包载重
	var main_count = 0
	var processed = []
	# [AI MODIFY]
	for r in range(mainBackpack.ROWS):
		for c in range(mainBackpack.COLS):
			var cell = mainBackpack.gridData[r][c]
			if cell is Array:
				for it in cell:
					if it and it not in processed:
						processed.append(it)
						main_count += it.runtime_shape.size()
			else:
				var it = cell
				if it and it not in processed:
					processed.append(it)
					main_count += it.runtime_shape.size()
				
	var spec_count = 0
	# [AI MODIFY]
	for r in range(mainBackpack.SPECIAL_ROWS):
		for c in range(mainBackpack.SPECIAL_COLS):
			var cell = mainBackpack.specialGridData[r][c]
			if cell is Array:
				for it in cell:
					if it and it not in processed:
						processed.append(it)
						spec_count += it.runtime_shape.size()
			else:
				var it = cell
				if it and it not in processed:
					processed.append(it)
					spec_count += it.runtime_shape.size()
				
	var pct = roundi(float(main_count) / 30.0 * 100.0)
	if spec_count > 0:
		loadStat.text = "📦   背包载重: %d / 30 格 (%d%%) [ 保险箱: %d / 4 格 ]" % [main_count, pct, spec_count]
	else:
		loadStat.text = "📦   背包载重: %d / 30 格 (%d%%)" % [main_count, pct]
	if pct >= 95:
		loadStat.add_theme_color_override("font_color", Color("#ff4444"))
	elif pct >= 80:
		loadStat.add_theme_color_override("font_color", Color("#ffd700"))
	else:
		loadStat.add_theme_color_override("font_color", Color("#909090"))

# ══════════════════════════════════════
# 仓库物品列表渲染
# ══════════════════════════════════════

func _render_warehouse_list() -> void:
	# 静默清理旧的仓库网格数据
	warehouseGrid._initGridData()
	for child in warehouseGrid.itemsContainer.get_children():
		child.queue_free()

	# 收集并过滤物品
	var filtered_items = []
	for path in GlobalPlayerData.owned_items:
		var res = load(path) as BackpackItemResource
		if not res: continue

		# 筛选
		if current_category != -1 and int(res.category) != current_category:
			continue

		filtered_items.append({"res": res, "path": path})

	# 排序
	_sort_items(filtered_items)

	# 渲染到物理格子中
	var itemUIScene = load("res://prefabs/Backpack/sub/backpack_item.tscn")
	for item_data in filtered_items:
		var res = item_data["res"]
		var path = item_data["path"]
		
		# 创建物品实例以检测放置
		var itemUI = itemUIScene.instantiate()
		itemUI.setup(res, path)
		
		# 自动寻找第一个可用格子放置
		var empty_pos = warehouseGrid.find_first_empty_slot(itemUI)
		if empty_pos.x != -1:
			warehouseGrid.placeItem(itemUI, empty_pos)
		else:
			# 空间不足，释放实例
			print("[BackpackConfig] 仓库已满，无法容纳物品: ", res.item_name)
			itemUI.queue_free()

func _on_warehouse_item_double_clicked(itemUI: Control) -> void:
	var res = itemUI.resource
	var path = itemUI.source_path if ("source_path" in itemUI and itemUI.source_path != "") else res.resource_path
	
	# 尝试将物品放入随身背包的第一个空格子
	var dummy = load("res://prefabs/Backpack/sub/backpack_item.tscn").instantiate()
	dummy.setup(res, path)
	var empty_pos = mainBackpack.find_first_empty_slot(dummy)
	dummy.free()
	
	if empty_pos.x != -1:
		# 从仓库移除
		warehouseGrid.removeItem(itemUI)
		itemUI.queue_free()
		
		# 实例化并在背包中放置
		var new_item = load("res://prefabs/Backpack/sub/backpack_item.tscn").instantiate()
		new_item.setup(res, path)
		mainBackpack.placeItem(new_item, empty_pos)
		
		# 同步并保存
		_save_both()
		print("[BackpackConfig] 物品已装备至随身背包: ", res.item_name)
	else:
		# 尝试放入保险箱
		var dummy_spec = load("res://prefabs/Backpack/sub/backpack_item.tscn").instantiate()
		dummy_spec.setup(res, path)
		var spec_pos = Vector2i(-1, -1)
		for r in range(mainBackpack.SPECIAL_ROWS):
			for c in range(mainBackpack.SPECIAL_COLS):
				if mainBackpack.canPlaceItem(dummy_spec, Vector2i(c, r), true):
					spec_pos = Vector2i(c, r)
					break
			if spec_pos.x != -1: break
		dummy_spec.free()
		
		if spec_pos.x != -1:
			warehouseGrid.removeItem(itemUI)
			itemUI.queue_free()
			
			var new_item = load("res://prefabs/Backpack/sub/backpack_item.tscn").instantiate()
			new_item.setup(res, path)
			mainBackpack.placeItemInSpecial(new_item, spec_pos)
			
			_save_both()
			print("[BackpackConfig] 物品已放入保险格: ", res.item_name)
		else:
			print("[BackpackConfig] 随身背包及保险格已满，无法装备: ", res.item_name)

func _sort_items(items: Array) -> void:
	match sort_mode:
		0: # 默认：不做排序
			pass
		1: # 品质从高到低
			items.sort_custom(func(a, b): return a["res"].rarity > b["res"].rarity)
		2: # 格子从小到大
			items.sort_custom(func(a, b): return a["res"].shape.size() < b["res"].shape.size())

# ══════════════════════════════════════
# 筛选 & 排序
# ══════════════════════════════════════

func _on_filter_pressed(category: int) -> void:
	current_category = category
	# 更新标签样式
	_update_filter_styles()
	_render_warehouse_list()

func _update_filter_styles() -> void:
	# 简化：使用 theme 覆盖
	var tabs = [tabAll, tabBomb, tabSpeed, tabRange, tabSpecial]
	var categories = [-1, 0, 1, 2, 3]
	for i in range(tabs.size()):
		var btn = tabs[i]
		if not btn: continue
		var is_active = (categories[i] == current_category)
		
		# 强制保持 uniform 大小，保证文本不拥挤
		btn.custom_minimum_size = Vector2(140, 44)
		
		if is_active:
			btn.add_theme_color_override("font_color", Color(0.2, 0.15, 0.05, 1))
			btn.add_theme_color_override("font_hover_color", Color(0.2, 0.15, 0.05, 1))
			btn.add_theme_color_override("font_pressed_color", Color(0.2, 0.15, 0.05, 1))
			
			# 激活样式：高贵尊奢金黄
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.831373, 0.686275, 0.215686, 0.9)
			style.corner_radius_top_left = 6
			style.corner_radius_top_right = 6
			style.corner_radius_bottom_right = 6
			style.corner_radius_bottom_left = 6
			
			btn.add_theme_stylebox_override("normal", style)
			btn.add_theme_stylebox_override("hover", style)
			btn.add_theme_stylebox_override("pressed", style)
		else:
			btn.add_theme_color_override("font_color", Color(0.549, 0.647, 0.788, 1))
			btn.add_theme_color_override("font_hover_color", Color(0.75, 0.82, 0.93, 1))
			btn.add_theme_color_override("font_pressed_color", Color(0.549, 0.647, 0.788, 1))
			
			# 普通样式：深海战术蓝背景，半透明科技感灰蓝边框
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.075, 0.118, 0.196, 0.6)
			style.border_color = Color(0.227, 0.294, 0.423, 0.4)
			style.set_border_width_all(1)
			style.corner_radius_top_left = 6
			style.corner_radius_top_right = 6
			style.corner_radius_bottom_right = 6
			style.corner_radius_bottom_left = 6
			
			var hover_style = style.duplicate()
			hover_style.bg_color = Color(0.12, 0.18, 0.28, 0.7)
			hover_style.border_color = Color(0.3, 0.38, 0.52, 0.6)
			
			btn.add_theme_stylebox_override("normal", style)
			btn.add_theme_stylebox_override("hover", hover_style)
			btn.add_theme_stylebox_override("pressed", style)

func _on_sort_pressed() -> void:
	sort_mode = (sort_mode + 1) % 3
	var labels = ["默认排序", "品质 高→低", "格子 小→大"]
	sortBtn.text = "排序: %s" % labels[sort_mode]
	_render_warehouse_list()

# ══════════════════════════════════════
# 仓库 → 背包 (装包)
# ══════════════════════════════════════

func _on_warehouse_pack_requested(res: BackpackItemResource, path: String) -> void:
	# 自动寻找空格放入背包
	var placed = false
	for r in range(mainBackpack.ROWS):
		for c in range(mainBackpack.COLS):
			if _try_add_item_at(res, Vector2i(c, r), false, path):
				GlobalPlayerData.remove_item(path)
				placed = true
				break
		if placed: break

	if placed:
		_on_save_pressed() # 自动保存
		item_packed.emit(res, path)
	else:
		# 背包已满，尝试保险格
		for r in range(mainBackpack.SPECIAL_ROWS):
			for c in range(mainBackpack.SPECIAL_COLS):
				if _try_add_item_at(res, Vector2i(c, r), true, path):
					GlobalPlayerData.remove_item(path)
					placed = true
					break
			if placed: break

		if not placed:
			print("[BackpackConfig] 背包已满，无法装入: ", res.item_name)

# ══════════════════════════════════════
# 售出 / 分解 & 详情弹窗
# ══════════════════════════════════════

func _input(event: InputEvent) -> void:
	if detailDialog.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_on_detail_pack_pressed()
			get_viewport().set_input_as_handled()
			return
			
	# 点击其他区域关闭右键菜单
	if contextMenu.visible and event is InputEventMouseButton and event.pressed:
		var rect = contextMenu.get_global_rect()
		if not rect.has_point(event.global_position):
			contextMenu.hide()

func _on_warehouse_context_menu(res: BackpackItemResource, path: String) -> void:
	_pending_detail_res = res
	_pending_detail_path = path
	contextMenu.global_position = get_global_mouse_position()
	contextMenu.show()

func _on_ctx_detail_pressed() -> void:
	contextMenu.hide()
	_show_detail_dialog(_pending_detail_res, _pending_detail_path, "warehouse", _pending_detail_node)

func _on_ctx_sell_pressed() -> void:
	contextMenu.hide()
	_on_warehouse_sell_requested(_pending_detail_res, _pending_detail_path)

func _on_warehouse_item_detail_requested(itemUI: Control) -> void:
	var path = itemUI.source_path if ("source_path" in itemUI and itemUI.source_path != "") else itemUI.resource.resource_path
	_show_detail_dialog(itemUI.resource, path, "warehouse", itemUI)

func _on_backpack_item_detail_requested(itemUI: Control) -> void:
	var path = itemUI.source_path if ("source_path" in itemUI and itemUI.source_path != "") else itemUI.resource.resource_path
	_show_detail_dialog(itemUI.resource, path, "backpack", itemUI)

func _show_detail_dialog(res: BackpackItemResource, path: String, source: String, node: Control) -> void:
	_pending_detail_res = res
	_pending_detail_path = path
	_pending_detail_source = source
	_pending_detail_node = node
	
	detailIcon.texture = res.icon
	detailName.text = res.item_name
	detailName.add_theme_color_override("font_color", res.get_rarity_color())
	
	var min_x = 99; var max_x = -99; var min_y = 99; var max_y = -99
	for p in res.shape:
		min_x = min(min_x, p.x); max_x = max(max_x, p.x)
		min_y = min(min_y, p.y); max_y = max(max_y, p.y)
	var shape_text = "%dx%d" % [max_x - min_x + 1, max_y - min_y + 1]
	
	var dummy_card = ItemCardScene.instantiate()
	var effect = dummy_card._get_effect_text(res)
	dummy_card.free()
	detailDesc.text = "%s\n%s" % [shape_text, effect]
	
	if source == "warehouse":
		detailPackBtn.show()
		detailPackBtn.text = "装入背包"
		detailSellBtn.show()
		detailSellBtn.text = "售出"
	else:
		detailPackBtn.show()
		detailPackBtn.text = "取出物品"
		detailSellBtn.hide()
		
	detailDialog.show()

func _close_detail_dialog() -> void:
	detailDialog.hide()

func _on_detail_pack_pressed() -> void:
	if _pending_detail_source == "warehouse":
		if _pending_detail_node:
			_on_warehouse_item_double_clicked(_pending_detail_node)
	elif _pending_detail_source == "backpack":
		if _pending_detail_node:
			_on_backpack_item_clicked(_pending_detail_node)
	_close_detail_dialog()

func _on_detail_sell_pressed() -> void:
	if _pending_detail_source == "warehouse":
		_on_warehouse_sell_requested(_pending_detail_res, _pending_detail_path)
		_close_detail_dialog()

func _on_warehouse_sell_requested(res: BackpackItemResource, path: String) -> void:
	var base_value = _get_item_value(res)
	var rarity_mult = _get_rarity_multiplier(res.rarity)
	var sell_price = base_value * rarity_mult

	_pending_sell_res = res
	_pending_sell_path = path
	_pending_sell_price = sell_price
	_dialog_mode = "sell"

	dialogTitle.text = "确认出售物资"
	dialogConfirm.text = "确认出售"
	dialogMsg.text = "确定出售「%s」？\n此操作不可撤销。" % res.item_name
	if dialogPrice:
		dialogPrice.text = "预计获得: 💰 %d 金币" % sell_price
		dialogPrice.show()
	confirmDialog.visible = true

func _get_item_value(res: BackpackItemResource) -> int:
	# 基础价值：根据属性加成总值
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
	# 根据占用格子数额外加权
	value += res.shape.size() * 10
	return max(value, 10) # 最低 10 金币

func _get_rarity_multiplier(rarity: int) -> int:
	match rarity:
		0: return 1  # RARE
		1: return 2  # EPIC
		2: return 4  # DIAMOND
		_: return 1

func _on_dialog_cancel() -> void:
	confirmDialog.visible = false
	_pending_sell_path = ""
	_pending_sell_res = null
	_dialog_mode = ""

func _on_dialog_confirm_sell() -> void:
	confirmDialog.visible = false
	if _dialog_mode == "sell":
		if _pending_sell_path != "" and _pending_sell_res != null:
			# 关键修复：出售物资时，必须暂时允许重建网格以将售出物资从仓库列表上移除
			_ignore_rebuild = false
			GlobalPlayerData.sell_item(_pending_sell_path, _pending_sell_price)
			_ignore_rebuild = true
			
			item_sold.emit(_pending_sell_res, _pending_sell_path, _pending_sell_price)
			print("[BackpackConfig] 已售出: %s, 获得 %d 金币" % [_pending_sell_res.item_name, _pending_sell_price])
	elif _dialog_mode == "clear":
		_execute_clear_backpack()
	elif _dialog_mode == "sort":
		_execute_auto_sort()
	elif _dialog_mode == "save":
		_execute_save_backpack()

	_pending_sell_path = ""
	_pending_sell_res = null
	_dialog_mode = ""

# ══════════════════════════════════════
# 战备方案 (Presets)
# ══════════════════════════════════════

func _on_preset_pressed(index: int) -> void:
	var preset = GlobalPlayerData.backpack_presets[index]
	if preset.size() == 0:
		# 空方案，保存当前配置
		var config = mainBackpack.get_backpack_layout_data()
		GlobalPlayerData.save_preset(index, config)
		print("[BackpackConfig] 已保存方案 %d" % (index + 1))
	else:
		# 加载方案
		_clear_backpack_silent()
		_load_config_from_data(preset)
		print("[BackpackConfig] 已加载方案 %d" % (index + 1))

	_refresh_ui_silent()
	_update_preset_buttons()

func _update_preset_buttons() -> void:
	var btns = [preset1, preset2, preset3]
	for i in range(3):
		var has_data = GlobalPlayerData.backpack_presets[i].size() > 0
		btns[i].text = "方案%d%s" % [i + 1, " ✓" if has_data else ""]

# ══════════════════════════════════════
# 背包配置加载/清空
# ══════════════════════════════════════

func _load_current_config() -> void:
	_clear_backpack_silent()
	_load_config_from_data(GlobalPlayerData.backpack_config)

func _load_config_from_data(config: Array) -> void:
	for item_info in config:
		var res_path = item_info.get("res_path", "")
		var pos = item_info.get("grid_pos", Vector2i.ZERO)
		var is_special = item_info.get("is_insurance", false)
		var rotated = item_info.get("rotated", false)

		if res_path != "":
			var res = load(res_path)
			if res is BackpackItemResource:
				_try_place_item_directly(res, pos, is_special, rotated, res_path)

func _try_place_item_directly(res: BackpackItemResource, pos: Vector2i, is_special: bool, rotated: bool, path: String) -> void:
	var itemUIScene = load("res://prefabs/Backpack/sub/backpack_item.tscn")
	var itemUI = itemUIScene.instantiate()
	itemUI.setup(res, path)
	if rotated: itemUI.rotateItem()

	if is_special:
		mainBackpack.placeItemInSpecial(itemUI, pos)
	else:
		mainBackpack.placeItem(itemUI, pos)

func _try_add_item_at(res: BackpackItemResource, pos: Vector2i, is_special: bool, path: String) -> bool:
	var itemUIScene = load("res://prefabs/Backpack/sub/backpack_item.tscn")
	var itemUI = itemUIScene.instantiate()
	itemUI.setup(res, path)

	if mainBackpack.canPlaceItem(itemUI, pos, is_special):
		if is_special: mainBackpack.placeItemInSpecial(itemUI, pos)
		else: mainBackpack.placeItem(itemUI, pos)
		return true

	itemUI.queue_free()
	return false

# 静默清空背包（不触发保存）
func _clear_backpack_silent() -> void:
	mainBackpack._initGridData()
	for child in mainBackpack.itemsContainer.get_children(): child.queue_free()
	for child in mainBackpack.specialItemsContainer.get_children(): child.queue_free()

# ══════════════════════════════════════
# 交互事件
# ══════════════════════════════════════

func _on_item_dropped_from_warehouse(path: String) -> void:
	# 物品从仓库拖入了随身背包，从仓库中移除并保存
	GlobalPlayerData.remove_item(path)
	_save_both()

func _on_item_dropped_from_backpack(path: String) -> void:
	# 物品从随身背包拖入了仓库，加入仓库并保存
	GlobalPlayerData.add_item(path)
	_save_both()

func _on_backpack_item_clicked(itemUI: Control) -> void:
	# 双击随身背包物品，卸下并移回仓库
	var res = itemUI.resource
	var path = itemUI.source_path if ("source_path" in itemUI and itemUI.source_path != "") else res.resource_path
	
	var dummy = load("res://prefabs/Backpack/sub/backpack_item.tscn").instantiate()
	dummy.setup(res, path)
	var empty_pos = warehouseGrid.find_first_empty_slot(dummy)
	dummy.free()
	
	if empty_pos.x != -1:
		mainBackpack.removeItem(itemUI)
		itemUI.queue_free()
		
		var new_item = load("res://prefabs/Backpack/sub/backpack_item.tscn").instantiate()
		new_item.setup(res, path)
		warehouseGrid.placeItem(new_item, empty_pos)
		
		_save_both()
		print("[BackpackConfig] 物品已从背包卸载: ", res.item_name)
	else:
		print("[BackpackConfig] 仓库空间不足，无法卸载: ", res.item_name)

func _save_both() -> void:
	# 1. 获取最新背包布局配置
	var config = mainBackpack.get_backpack_layout_data()
	
	# 2. 同步仓库 owned_items 列表（直接根据 warehouseGrid 上的实例扫描提取）
	var stash_items: Array[String] = []
	# [AI MODIFY]
	var processed_instances = []
	# [AI MODIFY]
	for r in range(warehouseGrid.ROWS):
		for c in range(warehouseGrid.COLS):
			var cell = warehouseGrid.gridData[r][c]
			if cell is Array:
				for it in cell:
					if it and it not in processed_instances:
						processed_instances.append(it)
						stash_items.append(it.source_path)
			else:
				var it = cell
				if it and it not in processed_instances:
					processed_instances.append(it)
					stash_items.append(it.source_path)
				
	# 3. 先更新本地数据，合并为一次性状态变更，防多次/异步网络调用产生冲突
	GlobalPlayerData.backpack_config = config
	GlobalPlayerData.owned_items = stash_items
	
	# 4. 手动发送本地更新信号以同步 UI 状态
	GlobalPlayerData.backpack_updated.emit()
	GlobalPlayerData.inventory_updated.emit()
	
	# 5. 只触发一次原子同步到服务器
	GlobalPlayerData.sync_to_server()
	
	# 静默更新统计面板
	_refresh_ui_silent()
	print("[BackpackConfig] 双向网格数据已同步至本地和服务器")

func _on_save_pressed() -> void:
	_dialog_mode = "save"
	dialogTitle.text = "确认保存战备"
	dialogConfirm.text = "确认保存"
	dialogMsg.text = "是否确认保存当前战备配置并同步至服务器？"
	if dialogPrice:
		dialogPrice.text = ""
		dialogPrice.hide()
	confirmDialog.visible = true

func _execute_save_backpack() -> void:
	_save_both()
	# 更新初始状态备份为最新确认过的配置
	_initial_coins = GlobalPlayerData.coins
	
	_initial_backpack.clear()
	for d in GlobalPlayerData.backpack_config:
		_initial_backpack.append(d.duplicate(true))
		
	_initial_owned.clear()
	for o in GlobalPlayerData.owned_items:
		_initial_owned.append(o)
		
	_show_toast("确认装配成功！配置已保存并同步")

func _on_discard_pressed() -> void:
	# 玩家未确认配备直接离开：回滚在界面内的全部修改，包括售出物资、金币变更和背包配置
	GlobalPlayerData.coins = _initial_coins
	GlobalPlayerData.backpack_config = _initial_backpack
	GlobalPlayerData.owned_items = _initial_owned
	GlobalPlayerData.sync_to_server()
	UIManager.change_scene("lobby")

func _on_clear_pressed() -> void:
	_dialog_mode = "clear"
	dialogTitle.text = "确认清空已配备"
	dialogConfirm.text = "确认清空"
	dialogMsg.text = "确定要卸下并清空所有已配备物资吗？\n所有装备的物品将放回仓库。"
	if dialogPrice:
		dialogPrice.text = ""
		dialogPrice.hide()
	confirmDialog.visible = true

func _execute_clear_backpack() -> void:
	# 一键清空随身背包：所有装备中的物品放回仓库
	var all_items = []
	# [AI MODIFY]
	for r in range(mainBackpack.ROWS):
		for c in range(mainBackpack.COLS):
			var cell = mainBackpack.gridData[r][c]
			if cell is Array:
				for it in cell:
					if it and it not in all_items:
						all_items.append(it)
			else:
				var it = cell
				if it and it not in all_items:
					all_items.append(it)
	for r in range(mainBackpack.SPECIAL_ROWS):
		for c in range(mainBackpack.SPECIAL_COLS):
			var cell = mainBackpack.specialGridData[r][c]
			if cell is Array:
				for it in cell:
					if it and it not in all_items:
						all_items.append(it)
			else:
				var it = cell
				if it and it not in all_items:
					all_items.append(it)

	var success_count = 0
	for it in all_items:
		var path = it.source_path if it.source_path != "" else it.resource.resource_path
		if path != "" and path != "res://":
			var dummy = load("res://prefabs/Backpack/sub/backpack_item.tscn").instantiate()
			dummy.setup(it.resource, path)
			var empty_pos = warehouseGrid.find_first_empty_slot(dummy)
			dummy.free()
			
			if empty_pos.x != -1:
				mainBackpack.removeItem(it)
				it.queue_free()
				
				var new_item = load("res://prefabs/Backpack/sub/backpack_item.tscn").instantiate()
				new_item.setup(it.resource, path)
				warehouseGrid.placeItem(new_item, empty_pos)
				success_count += 1
			else:
				print("[BackpackConfig] 仓库已满，一键卸载中断于: ", it.resource.item_name)
				break

	if success_count > 0:
		_save_both()
		_show_toast("一键清空成功，共卸下 %d 件物资" % success_count)
		print("[BackpackConfig] 一键卸下成功，共卸下 %d 件物资" % success_count)

func _on_auto_sort_backpack_pressed() -> void:
	_dialog_mode = "sort"
	dialogTitle.text = "确认整理背包"
	dialogConfirm.text = "确认整理"
	dialogMsg.text = "确定要自动整理当前背包内所有物品吗？\n系统将自动寻找最优排列布局空间。"
	if dialogPrice:
		dialogPrice.text = ""
		dialogPrice.hide()
	confirmDialog.visible = true

func _execute_auto_sort() -> void:
	mainBackpack.auto_sort()
	_save_both()
	_show_toast("随身背包自动整理完成！")
	print("[BackpackConfig] 随身背包已自动整理与优化排列完成")

# ══════════════════════════════════════
# 工具方法
# ══════════════════════════════════════

func _format_number(n: int) -> String:
	# 千分位格式化
	var s = str(n)
	var result = ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result

func _show_toast(message: String) -> void:
	var toast = Label.new()
	toast.text = message
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# 设计高规格半透明战术风格背景
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#0f1520e0") # 深蓝色半透明底
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("#0078d4") # 科技蓝发光边框
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.expand_margin_left = 20
	style.expand_margin_right = 20
	style.expand_margin_top = 10
	style.expand_margin_bottom = 10
	
	toast.add_theme_stylebox_override("normal", style)
	toast.add_theme_color_override("font_color", Color("#00ff00")) # 成功成功绿颜色
	
	add_child(toast)
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	# 浮动升华淡出 Tween
	toast.modulate.a = 0.0
	toast.scale = Vector2(0.9, 0.9)
	toast.pivot_offset = toast.size / 2.0
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(toast, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(toast, "scale", Vector2(1.0, 1.0), 0.2).set_ease(Tween.EASE_OUT)
	
	var fade_tween = create_tween()
	fade_tween.tween_interval(1.2)
	
	var end_tween = create_tween().set_parallel(true)
	end_tween.tween_property(toast, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_IN)
	end_tween.tween_property(toast, "position:y", toast.position.y - 30, 0.3).set_ease(Tween.EASE_IN)
	end_tween.finished.connect(toast.queue_free)



func _update_ui_scale(val: float) -> void:
	self.scale = Vector2(val, val)
	
	# 让大厅界面缩放时始终保持在屏幕正中心对齐
	var win_size = get_viewport_rect().size
	var scaled_size = win_size * val
	self.position = (win_size - scaled_size) / 2.0

func _update_layout_spacers() -> void:
	var mainContent = %MainContent
	if not mainContent: return
	
	var win_width = get_viewport_rect().size.x
	# 两个紧密包裹面板的宽度 (568 + 904) + 16 (HBox 默认间距) = 1488px
	var total_content_width = 568 + 904 + 16
	var remaining = win_width - total_content_width
	
	# 将余下空间以 50px 偏移量分配给左右 Spacers，确保居中的同时整体向右偏移 50px
	var left_width = max(0.0, (remaining / 2.0) + 50.0)
	var right_width = max(0.0, (remaining / 2.0) - 50.0)
	
	var leftSpacer = mainContent.get_node_or_null("LeftSpacer")
	if leftSpacer:
		leftSpacer.custom_minimum_size = Vector2(left_width, 0)
		
	var rightSpacer = mainContent.get_node_or_null("RightSpacer")
	if rightSpacer:
		rightSpacer.custom_minimum_size = Vector2(right_width, 0)
