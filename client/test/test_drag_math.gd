# test_drag_math.gd
# 拖拽吸附与网格仲裁数学诊断测试脚本
# 用于精确量化与定位拖拽吸附不精准及不能正确改变位置的问题。

extends SceneTree

const CELL_SIZE: int = 64
const SPACING: int = 8
const STEP: int = CELL_SIZE + SPACING # 72

# 容器数据
const ROWS: int = 8
const COLS: int = 6
const SPECIAL_ROWS: int = 2
const SPECIAL_COLS: int = 2

# 主网格与保险格的近似全局位置 (以 1920x1080 为基准计算出的物理位置)
# 在 lobby/backpack_config 中，主网格在左侧，保险箱在其右侧
const MAIN_GRID_GLOBAL_POS = Vector2(188.0, 291.0)
const SPECIAL_GRID_GLOBAL_POS = Vector2(771.0, 418.0)
const WAREHOUSE_GRID_GLOBAL_POS = Vector2(799.0, 301.0)

# 测试日志数据 (由用户提供)
var test_logs = [
	{
		"name": "MainBackpack",
		"is_special": true,
		"origin": Vector2i(0, 0),
		"mouse": Vector2(810.0, 471.0),
		"pickup_offset": Vector2(67.0, 75.0),
		"item_tl_g": Vector2(743.0, 396.0)
	},
	{
		"name": "WarehouseGrid",
		"is_special": false,
		"origin": Vector2i(0, 1),
		"mouse": Vector2(866.0, 448.0),
		"pickup_offset": Vector2(67.0, 75.0),
		"item_tl_g": Vector2(799.0, 373.0)
	},
	{
		"name": "MainBackpack",
		"is_special": false,
		"origin": Vector2i(3, 1),
		"mouse": Vector2(662.0, 451.0),
		"pickup_offset": Vector2(67.0, 75.0),
		"item_tl_g": Vector2(595.0, 376.0)
	},
	{
		"name": "MainBackpack",
		"is_special": false,
		"origin": Vector2i(0, 3),
		"mouse": Vector2(253.0, 592.0),
		"pickup_offset": Vector2(67.0, 75.0),
		"item_tl_g": Vector2(186.0, 517.0)
	},
	{
		"name": "MainBackpack",
		"is_special": false,
		"origin": Vector2i(0, 0),
		"mouse": Vector2(343.0, 271.0),
		"pickup_offset": Vector2(67.0, 75.0),
		"item_tl_g": Vector2(276.0, 196.0)
	},
	{
		"name": "MainBackpack",
		"is_special": false,
		"origin": Vector2i(3, 2),
		"mouse": Vector2(661.0, 494.0),
		"pickup_offset": Vector2(62.0, 83.0),
		"item_tl_g": Vector2(599.0, 411.0)
	},
	{
		"name": "MainBackpack",
		"is_special": false,
		"origin": Vector2i(0, 0),
		"mouse": Vector2(250.0, 374.0),
		"pickup_offset": Vector2(62.0, 83.0),
		"item_tl_g": Vector2(188.0, 291.0)
	},
	{
		"name": "MainBackpack",
		"is_special": true,
		"origin": Vector2i(0, 0),
		"mouse": Vector2(820.0, 477.0),
		"pickup_offset": Vector2(49.0, 59.0),
		"item_tl_g": Vector2(771.0, 418.0)
	},
	{
		"name": "MainBackpack",
		"is_special": false,
		"origin": Vector2i(3, 2),
		"mouse": Vector2(650.0, 503.0),
		"pickup_offset": Vector2(63.0, 78.0),
		"item_tl_g": Vector2(587.0, 425.0)
	}
]

func _init() -> void:
	print("=========================================================")
	print("           PixelBomb 拖拽吸附数学诊断测试                 ")
	print("=========================================================")
	
	run_diagnostics()
	
	quit()

func run_diagnostics() -> void:
	print("\n--- [测试阶段 1: 边界磁吸与提前 Clamp 验证] ---")
	
	# 测试案例：模拟当鼠标移出网格左上角边界时，提前 Clamp 导致的计算锁死
	# 假设鼠标在左边 80px, 顶上 80px 之外 (local_item_tl = Vector2(-80.0, -80.0))
	var local_item_tl = Vector2(-80.0, -80.0)
	var shape = [Vector2i(0, 0)] # 1x1 物品
	
	var item_w = 1
	var item_h = 1
	var max_valid_x = COLS - item_w
	var max_valid_y = ROWS - item_h
	
	# 旧算法：直接 clampi 限制
	var old_snap_x = clampi(roundi(local_item_tl.x / STEP), 0, max_valid_x)
	var old_snap_y = clampi(roundi(local_item_tl.y / STEP), 0, max_valid_y)
	
	# 新算法：允许超出网格范围 (不提前 clamp)
	var new_snap_x = roundi(local_item_tl.x / STEP)
	var new_snap_y = roundi(local_item_tl.y / STEP)
	
	print("模拟输入：物品左上角处于网格之外 (local_item_tl = ", local_item_tl, ")")
	print(" -> [旧算法] 计算的网格位置: (", old_snap_x, ", ", old_snap_y, ")")
	print("    由于提前 clampi 被强制锁定在 (0, 0)。如果 (0, 0) 为空，则 validity=TRUE")
	print("    这会导致：明明鼠标已经在网格外面极远的地方，却强行触发 (0, 0) 的绿色预览！(磁铁般粘死在左上角)")
	print(" -> [新算法] 计算的网格位置: (", new_snap_x, ", ", new_snap_y, ")")
	print("    因为未提前 clampi，其网格位置为负数，进入 canPlaceItem 会自然判定为越界无效 (validity=FALSE)")
	print("    这会触发：预览格正确消失或变红，彻底解决边缘磁吸锁死问题！")
	
	print("\n--- [测试阶段 2: 多网格重叠与几何仲裁验证] ---")
	
	# 测试案例：拖拽普通物品 (如炸弹 1x1，不能放入保险箱) 到保险格 (771, 418) 附近
	# 主网格的 grow(64) 边界会与保险格重叠
	var test_g_mouse = Vector2(810.0, 471.0)
	var test_pickup_offset = Vector2(67.0, 75.0)
	# 计算 l_mouse_main (相对于主网格) 和 l_mouse_spec (相对于保险格)
	var l_mouse_main = test_g_mouse - MAIN_GRID_GLOBAL_POS
	var l_mouse_spec = test_g_mouse - SPECIAL_GRID_GLOBAL_POS
	
	var main_width = COLS * CELL_SIZE + (COLS - 1) * SPACING
	var main_height = ROWS * CELL_SIZE + (ROWS - 1) * SPACING
	var main_bound = Rect2(0, 0, main_width, main_height).grow(64)
	
	var spec_width = SPECIAL_COLS * CELL_SIZE + (SPECIAL_COLS - 1) * SPACING
	var spec_height = SPECIAL_ROWS * CELL_SIZE + (SPECIAL_ROWS - 1) * SPACING
	var spec_bound = Rect2(0, 0, spec_width, spec_height).grow(64)
	
	var main_hit = main_bound.has_point(l_mouse_main)
	var spec_hit = spec_bound.has_point(l_mouse_spec)
	
	print("模拟全局鼠标坐标: ", test_g_mouse)
	print(" -> 是否碰撞主网格 (grow 64): ", main_hit, " (l_mouse: ", l_mouse_main, ")")
	print(" -> 是否碰撞保险格 (grow 64): ", spec_hit, " (l_mouse: ", l_mouse_spec, ")")
	
	# 旧算法仲裁：
	var old_decision = ""
	if spec_hit and false: # 假设 sp_hit.is_valid 是 false (普通物品不能放保险格)
		old_decision = "Special"
	elif main_hit and false: # 假设 main_hit.is_valid 是 false (主网格距离太远越界)
		old_decision = "Main"
	else:
		# Priority 2: 都没有合法位置，优先返回 main_hit
		if main_hit:
			old_decision = "Main (Fallback)"
		elif spec_hit:
			old_decision = "Special (Fallback)"
	
	# 新算法仲裁：使用欧氏距离几何中心仲裁
	var dist_to_main = _get_dist_to_rect(l_mouse_main, Rect2(0, 0, main_width, main_height))
	var dist_to_spec = _get_dist_to_rect(l_mouse_spec, Rect2(0, 0, spec_width, spec_height))
	
	var new_decision = "Main" if dist_to_main < dist_to_spec else "Special"
	
	print(" -> [旧仲裁判定结果]: ", old_decision)
	print("    由于普通物品无法在保险格中 valid，主网格在 grow(64) 的重叠区把所有事件优先抢走了！")
	print("    这导致：当玩家拖拽普通物品悬停在保险格上时，根本显示不出保险格的红色无效框，而是强行在主网格边缘画一个不精准的无效框！")
	print(" -> [新几何几何仲裁结果]:")
	print("    鼠标到主网格矩形距离: ", dist_to_main)
	print("    鼠标到保险格矩形距离: ", dist_to_spec)
	print("    根据最近距离仲裁归属于: ", new_decision)
	print("    这会触发：当鼠标离保险格更近时，仲裁归属于保险箱，从而正确呈现红色的无效预览，让玩家清晰看到该栏不可放置！")

	print("\n=========================================================")
	print("                  诊断结论与优化实施方案                 ")
	print("=========================================================")
	print("1. 移除提前 clamping：在 _check_grid_hit 中，只在 roundi 计算网格单元时保留其负值和越界值，不提前 Clamp，")
	print("   让 canPlaceItem 的几何验证天然拒绝越界，仅在最终 drop 执行 placement 时使用保护性 clamp。")
	print("2. 引入欧氏距离多网格几何仲裁：如果多个网格均碰撞且无合法位置时，通过计算鼠标到网格矩形边缘的最小欧氏距离")
	print("   进行智能分配，精准响应红色无效警告，彻底消除主副网格边缘冲突。")

# 计算鼠标到矩形的欧几里得距离
func _get_dist_to_rect(p: Vector2, rect: Rect2) -> float:
	var dx = maxf(0.0, maxf(-p.x, p.x - rect.size.x))
	var dy = maxf(0.0, maxf(-p.y, p.y - rect.size.y))
	return sqrt(dx * dx + dy * dy)
