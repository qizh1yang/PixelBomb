# MapPreviewRenderer.gd
# 轻量级地图缩略图预览控件
# 直接复用真实的 MapGeneratorCore 算法生成逻辑矩阵，再通过 Control._draw() 进行像素绘制
# 这保证了预览图与真实地图 100% 一致，彻底防止算法漂移。
# 创建时间：2026-05-27

extends Control

class_name MapPreviewRenderer

# ── 外观配置 ──
const COLOR_VOID       := Color(0.05, 0.05, 0.1, 1.0)   # VOID 区域 (地图外)：极暗蓝黑
const COLOR_FLOOR      := Color(0.15, 0.18, 0.22, 1.0)  # 地板 0：深石板灰
const COLOR_HARD_WALL  := Color(0.3, 0.32, 0.38, 1.0)   # 硬立柱 1：中灰
const COLOR_SOFT_WALL  := Color(0.45, 0.38, 0.28, 1.0)  # 软墙箱子 2：暖棕色
const COLOR_SPAWN      := Color(0.2, 0.9, 0.5, 0.85)    # 出生点：翠绿
const COLOR_EXTRACTION := Color(1.0, 0.85, 0.2, 0.95)   # 撤离点：金黄
const COLOR_BORDER     := Color(0.6, 0.65, 0.75, 0.15)  # 网格线：半透明浅蓝

# ── 内部缓存 ──
var _map_data: Array = []
var _spawn_points: Array = []
var _extraction_point: Vector2i = Vector2i(-1, -1)
var _map_width: int = 31
var _map_height: int = 31
var _map_type: String = "CLASSIC"
var _is_valid: bool = false

# ── 状态提示文本 ──
var _status_text: String = ""

func _ready() -> void:
	# 确保控件可以接收 _draw 调用
	set_process(false)
	clip_contents = true
	_draw_empty_placeholder()

## 核心接口：传入地图配置参数，异步重生成并重绘预览
## map_type: "CLASSIC" | "WINTER" | "PROCEDURAL"
## shape: "circle" | "hexagon" | "star" | "ring" | "cave"
## size_name: "small" | "medium" | "large"
## map_seed: 任意整数种子
func setup(map_type: String, shape: String = "circle", size_name: String = "small", map_seed: int = 12345) -> void:
	_map_type = map_type.to_upper()
	_is_valid = false
	_status_text = ""
	
	if _map_type == "PROCEDURAL":
		# [规范3] 直接复用真实的 MapGeneratorCore，绝对不自写算法
		# 仅在内存中运行逻辑生成，完全不挂载物理节点，极速完成
		var core = MapGeneratorCore.new()
		if core and core.has_method("generate_logical_map"):
			core.set_map_size_by_name(size_name)
			core.shape_type = shape
			var result: Dictionary = core.generate_logical_map(map_seed)
			_map_data = result.get("map_data", [])
			_spawn_points = result.get("spawn_points", [])
			_extraction_point = result.get("extraction_point", Vector2i(-1, -1))
			_map_width = core.width
			_map_height = core.height

			if _map_data.is_empty():
				_status_text = "生成失败"
				_is_valid = false
			else:
				_is_valid = true
		else:
			_status_text = "MapGeneratorCore not available"
			_is_valid = false
			print("[MapPreview] MapGeneratorCore not available, fallback")
	else:
		# CLASSIC / WINTER 地图：绘制固定缩略图占位
		_map_data = []
		_map_width = 31
		_map_height = 31
		_is_valid = false  # 使用自定义绘制
	
	# 请求重绘
	queue_redraw()

## Godot Control 绘制入口
func _draw() -> void:
	var rect = get_rect()
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	
	# 绘制深色背景底板
	draw_rect(Rect2(Vector2.ZERO, rect.size), Color(0.06, 0.07, 0.1, 1.0))
	
	if not _is_valid or _map_data.is_empty():
		_draw_non_procedural(rect)
		return
	
	_draw_procedural_map(rect)

## 绘制程序化地图缩略图
func _draw_procedural_map(rect: Rect2) -> void:
	var pw = rect.size.x / float(_map_width)
	var ph = rect.size.y / float(_map_height)
	var cell_size = Vector2(pw, ph)
	
	# 遍历逻辑矩阵，按 Tile 类型逐格填色
	for x in range(_map_width):
		for y in range(_map_height):
			if x >= _map_data.size(): continue
			var col = _map_data[x]
			if y >= col.size(): continue
			var tile_val: int = col[y]
			
			var color: Color
			match tile_val:
				-1: color = COLOR_VOID         # VOID (地图外)
				0:  color = COLOR_FLOOR        # 地板
				1:  color = COLOR_HARD_WALL    # 硬立柱
				2:  color = COLOR_SOFT_WALL    # 软墙箱子
				_:  color = COLOR_FLOOR
			
			var cell_rect = Rect2(Vector2(x * pw, y * ph), cell_size)
			draw_rect(cell_rect, color)
	
	# 绘制出生点（翠绿高亮）
	for sp in _spawn_points:
		if sp is Vector2i:
			var cell_rect = Rect2(Vector2(sp.x * pw, sp.y * ph), cell_size * 1.5)
			draw_rect(cell_rect, COLOR_SPAWN)
			# 绘制小圆点标记
			var center = Vector2((sp.x + 0.5) * pw, (sp.y + 0.5) * ph)
			draw_circle(center, min(pw, ph) * 0.55, COLOR_SPAWN)
	
	# 绘制撤离点（金黄圆圈）
	if _extraction_point.x >= 0 and _extraction_point.y >= 0:
		var ep = _extraction_point
		var center = Vector2((ep.x + 0.5) * pw, (ep.y + 0.5) * ph)
		var radius = min(pw, ph) * 1.2
		draw_circle(center, radius, COLOR_EXTRACTION)
		draw_circle(center, radius * 0.6, COLOR_VOID)  # 空心效果
	
	# 绘制外边框
	draw_rect(Rect2(Vector2.ZERO, rect.size), Color(0.4, 0.5, 0.65, 0.5), false, 1.0)

## 绘制 CLASSIC / WINTER 地图的固定风格占位缩略图
func _draw_non_procedural(rect: Rect2) -> void:
	var cols = 15
	var rows = 15
	var pw = rect.size.x / float(cols)
	var ph = rect.size.y / float(rows)
	
	# 模拟经典炸弹人的固定立柱阵列
	for x in range(cols):
		for y in range(rows):
			var color: Color
			if x == 0 or y == 0 or x == cols-1 or y == rows-1:
				color = COLOR_HARD_WALL  # 外边界
			elif x % 2 == 0 and y % 2 == 0:
				color = COLOR_HARD_WALL  # 固定立柱
			elif randf() < 0.32:
				color = COLOR_SOFT_WALL  # 随机箱子
			else:
				color = COLOR_FLOOR
			draw_rect(Rect2(Vector2(x * pw, y * ph), Vector2(pw, ph)), color)
	
	# 在角落绘制出生点标记
	var corners = [
		Vector2(1.5 * pw, 1.5 * ph),
		Vector2((cols - 2.5) * pw, 1.5 * ph),
		Vector2(1.5 * pw, (rows - 2.5) * ph),
		Vector2((cols - 2.5) * pw, (rows - 2.5) * ph)
	]
	for c in corners:
		draw_circle(c, min(pw, ph) * 0.5, COLOR_SPAWN)
	
	# 中心撤离点
	draw_circle(rect.size * 0.5, min(pw, ph) * 1.0, COLOR_EXTRACTION)
	draw_circle(rect.size * 0.5, min(pw, ph) * 0.5, COLOR_VOID)
	
	# 地图类型标签
	var label = MapFactory.get_map_display_name(_map_type)
	draw_string(ThemeDB.fallback_font, Vector2(4, rect.size.y - 6), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.8, 0.9, 1.0, 0.7))
	
	# 外边框
	draw_rect(Rect2(Vector2.ZERO, rect.size), Color(0.4, 0.5, 0.65, 0.5), false, 1.0)

## 绘制空占位符
func _draw_empty_placeholder() -> void:
	queue_redraw()
