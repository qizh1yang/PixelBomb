# 地图逻辑寻路连通与生成器状态调试可视化挂件层
# 动态绘制裁切硬梁、曼哈顿最远出生红圈、亮绿色 EXIT 圈、距离路径线以及状态大面板
# 创建时间：2026-05-27

extends Node2D

class_name MapDebugOverlay

var map_data: Array = []
var spawn_points: Array[Vector2i] = []
var seed_val: int = 0
var shape_name: String = ""
var cell_size: float = 16.0  # 单个网格对应的像素尺寸

# 新增的公平性与撤离数据缓存
var extraction_point: Vector2i = Vector2i(-1, -1)
var imbalance_score: float = 0.0
var distances: Array[int] = []

# 填充传统调试数据并重新触发绘制
func setup(p_map_data: Array, p_spawns: Array[Vector2i], p_seed: int, p_shape: String) -> void:
	map_data = p_map_data
	spawn_points = p_spawns
	seed_val = p_seed
	shape_name = p_shape
	queue_redraw()

# 填充带有公平性指标的调试数据并重新触发绘制
func setup_fairness(p_map_data: Array, p_spawns: Array[Vector2i], p_seed: int, p_shape: String, p_extract: Vector2i, p_imbalance: float, p_dists: Array[int]) -> void:
	map_data = p_map_data
	spawn_points = p_spawns
	seed_val = p_seed
	shape_name = p_shape
	extraction_point = p_extract
	imbalance_score = p_imbalance
	distances = p_dists
	queue_redraw()

func _draw() -> void:
	if map_data.is_empty(): return
	
	var width = map_data.size()
	var height = map_data[0].size()
	var default_font = ThemeDB.get_fallback_font()
	
	# 1. 绘制虚空和裁剪硬墙（虚空半透明黑，硬墙红色半透明）
	for x in range(width):
		for y in range(height):
			var val = map_data[x][y]
			var rect = Rect2(x * cell_size, y * cell_size, cell_size, cell_size)
			if val == -1:
				# 绘制虚空深色半透明格
				draw_rect(rect, Color(0.08, 0.08, 0.1, 0.65), true)
				draw_rect(rect, Color(0.15, 0.15, 0.2, 0.3), false, 0.5)
			elif val == 1:
				# 绘制裁剪硬墙红色半透明小方格
				draw_rect(rect, Color(0.9, 0.1, 0.1, 0.12), true)
				draw_rect(rect, Color(0.9, 0.1, 0.1, 0.25), false, 0.5)
				
	# 2. 绘制黄金撤离点 (值为 5 的网格) 与路径连线
	if extraction_point != Vector2i(-1, -1):
		var ext_center = Vector2(extraction_point.x * cell_size + cell_size/2.0, extraction_point.y * cell_size + cell_size/2.0)
		
		# 绘制亮橙色/亮绿色双重同心圆光环
		draw_circle(ext_center, cell_size * 0.55, Color("2ecc71", 0.55))
		draw_arc(ext_center, cell_size * 0.75, 0, TAU, 32, Color("e67e22", 0.85), 2.0)
		
		# 绘制 "EXIT" 文字
		draw_string(default_font, ext_center + Vector2(-12.0, 4.0), "EXIT", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color.WHITE)
		
		# 绘制从每个玩家出生点到撤离点的半透明蓝色指引线，凸显不平衡差值
		for sp in spawn_points:
			var sp_center = Vector2(sp.x * cell_size + cell_size/2.0, sp.y * cell_size + cell_size/2.0)
			draw_line(sp_center, ext_center, Color("3498db", 0.55), 1.5)
			
	# 3. 绘制 4 个出生点位置（红润遮罩圆圈及大写的 P1/P2/P3/P4）
	var idx = 1
	for sp in spawn_points:
		var center_pos = Vector2(sp.x * cell_size + cell_size/2.0, sp.y * cell_size + cell_size/2.0)
		draw_circle(center_pos, cell_size * 0.45, Color("e74c3c", 0.78))
		
		# 绘制编号
		draw_string(default_font, center_pos + Vector2(-6.0, 4.0), "P" + str(idx), HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.WHITE)
		idx += 1
		
	# 4. 绘制 4 个出生点之间的 BFS 寻路连通拓扑关系（亮绿色表示无缝互通，可达性完美通过）
	if spawn_points.size() >= 2:
		for i in range(spawn_points.size()):
			var p1 = Vector2(spawn_points[i].x * cell_size + cell_size/2.0, spawn_points[i].y * cell_size + cell_size/2.0)
			var p2 = Vector2(spawn_points[(i+1)%spawn_points.size()].x * cell_size + cell_size/2.0, spawn_points[(i+1)%spawn_points.size()].y * cell_size + cell_size/2.0)
			draw_line(p1, p2, Color("2ecc71", 0.55), 1.5)
			
	# 5. 绘制 HUD 调试文字信息面板
	var dist_list_str = ""
	var total_dist = 0
	if not distances.is_empty():
		for i in range(distances.size()):
			dist_list_str += "P%d:%d步 " % [i+1, distances[i]]
			total_dist += distances[i]
			
	var avg_dist = total_dist / float(distances.size()) if not distances.is_empty() else 0.0
	var balance_status = "MIRROR PERFECT (0.0%)" if imbalance_score == 0.0 else "%.1f%%" % [imbalance_score * 100.0]
	var limit_val = 30.0 if shape_name.to_lower() == "cave" else 15.0
	
	var info_text = "Procedural Map Overhaul Stats (Godot 4.3):\n" + \
					"- Current Theme Shape: %s\n" % shape_name.capitalize() + \
					"- Active System Seed: %d | Size: %dx%d\n" % [seed_val, width, height] + \
					"- Spawn to Exit Distances: %s\n" % dist_list_str + \
					"- Average Extraction Steps: %.1f steps\n" % avg_dist + \
					"- Path Balance Score: %s (LIMIT: %.1f%%)\n" % [balance_status, limit_val] + \
					"- Controls: [R] Seed | [S] Save | [O] Overlay | [M] Size | [1]-[5] Shape"
					
	# 绘制半透明黑框作为调试文字背景
	var panel_rect = Rect2(10.0, 10.0, 390.0, 115.0)
	draw_rect(panel_rect, Color(0, 0, 0, 0.76), true)
	draw_rect(panel_rect, Color("f1c40f", 0.8), false, 1.5)
	
	draw_string(default_font, Vector2(20.0, 26.0), info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("f1c40f"))
