# 升级版 - 出生点求解器与可达连通校验
# 引入对 VOID (-1) 状态的寻路阻断、3格出生安全避让缓冲区以及降级自适应
# 创建时间：2026-05-27

extends RefCounted

class_name SpawnPointSolver

# 检查一个网格格子是否过于靠近虚空 VOID (-1) 或大地图越界边缘
static func is_near_void(pos: Vector2i, map_data: Array, width: int, height: int, margin: int = 3) -> bool:
	for dx in range(-margin, margin + 1):
		for dy in range(-margin, margin + 1):
			var cx = pos.x + dx
			var cy = pos.y + dy
			# 靠着地图极限物理边缘，等同于靠着虚空
			if cx < 0 or cx >= width or cy < 0 or cy >= height:
				return true
			# 靠着 VOID (-1) 网格，判定为靠近虚空
			if map_data[cx][cy] == -1:
				return true
	return false

# 获取地图最大的连通空地区域 (排除 -1 VOID 物理不可达格)
static func get_largest_connected_region(map_data: Array, width: int, height: int) -> Array[Vector2i]:
	var visited := {}
	var regions: Array[Array] = []
	
	for x in range(width):
		for y in range(height):
			var pos = Vector2i(x, y)
			# 只有非硬墙和非虚空格（0=地板，2=软墙箱子，3=出生点），才属于可移动连通域的计算因子
			if (map_data[x][y] == 0 or map_data[x][y] == 2 or map_data[x][y] == 3) and not visited.has(pos):
				var region: Array[Vector2i] = []
				var queue: Array[Vector2i] = [pos]
				visited[pos] = true
				
				while not queue.is_empty():
					var current = queue.pop_front()
					region.append(current)
					
					var neighbors = [
						Vector2i(current.x + 1, current.y),
						Vector2i(current.x - 1, current.y),
						Vector2i(current.x, current.y + 1),
						Vector2i(current.x, current.y - 1)
					]
					for n in neighbors:
						if n.x >= 0 and n.x < width and n.y >= 0 and n.y < height:
							# 连通性寻路支持可通行的地板 (0, 3) 以及可炸毁的软墙箱子 (2)
							var cell_val = map_data[n.x][n.y]
							if (cell_val == 0 or cell_val == 2 or cell_val == 3) and not visited.has(n):
								visited[n] = true
								queue.append(n)
								
				regions.append(region)
				
	var largest_region: Array[Vector2i] = []
	for r in regions:
		if r.size() > largest_region.size():
			largest_region = r
			
	return largest_region

# 贪心或轴对称镜像求解出生点 (加入 3格 虚空避让 margin 检测和对称选点)
static func solve_spawn_points(connected_region: Array[Vector2i], map_data: Array, width: int, height: int, count: int = 4, shape_type: String = "") -> Array[Vector2i]:
	var spawn_points: Array[Vector2i] = []
	if connected_region.is_empty():
		return spawn_points
		
	# ── Symmetry 轴对称镜像选点 (Circle, Hexagon, Ring 专用) ──
	if shape_type.to_lower() in ["circle", "hexagon", "ring"] and count == 4:
		var center_x = width / 2.0
		var center_y = height / 2.0
		var safe_quad_candidates: Array[Vector2i] = []
		
		# 尝试从最安全的 3格 margin 到 0格 margin 寻找左上象限的出生点候选
		var test_margin = 3
		while safe_quad_candidates.is_empty() and test_margin >= 0:
			for pos in connected_region:
				# 必须在严格左上象限 (排除中线)
				if pos.x < center_x - 1 and pos.y < center_y - 1:
					if map_data[pos.x][pos.y] == 0 and not is_near_void(pos, map_data, width, height, test_margin):
						# 验证四个镜像点是否全部位于可行走连通域内且为 FLOOR (0)
						var m1 = pos
						var m2 = Vector2i(width - 1 - pos.x, pos.y)
						var m3 = Vector2i(pos.x, height - 1 - pos.y)
						var m4 = Vector2i(width - 1 - pos.x, height - 1 - pos.y)
						
						if m2 in connected_region and m3 in connected_region and m4 in connected_region:
							if map_data[m2.x][m2.y] == 0 and map_data[m3.x][m3.y] == 0 and map_data[m4.x][m4.y] == 0:
								safe_quad_candidates.append(pos)
			test_margin -= 1
			
		if not safe_quad_candidates.is_empty():
			# 挑选左上角候选格点中距离物理中心最远（即最偏左上）的那一个
			var best_sp = safe_quad_candidates[0]
			var max_dist = 0.0
			for pos in safe_quad_candidates:
				var dist = Vector2(pos).distance_to(Vector2(center_x, center_y))
				if dist > max_dist:
					max_dist = dist
					best_sp = pos
					
			spawn_points.append(best_sp)
			spawn_points.append(Vector2i(width - 1 - best_sp.x, best_sp.y))
			spawn_points.append(Vector2i(best_sp.x, height - 1 - best_sp.y))
			spawn_points.append(Vector2i(width - 1 - best_sp.x, height - 1 - best_sp.y))
			print("[SPAWN] Successfully solved perfectly mirrored 4-axis symmetric spawn points: ", spawn_points)
			return spawn_points

	# ── 非对称/常规贪心求解保底 ──
	# 过滤出距离虚空边界至少有 3格 安全距离的候选地带。
	# 若地图地形过于崎岖而无一格满足，利用自适应降级机制（从 3格 渐进减少到 0格）直到不为空，保障绝对零报错崩溃。
	var safe_candidates: Array[Vector2i] = []
	var test_margin = 3
	
	while safe_candidates.is_empty() and test_margin >= 0:
		for pos in connected_region:
			# 优先选择当前为空地 FLOOR (0) 且安全的格子，避免直接降生在箱子上
			if map_data[pos.x][pos.y] == 0 and not is_near_void(pos, map_data, width, height, test_margin):
				safe_candidates.append(pos)
		test_margin -= 1
		
	if safe_candidates.is_empty():
		# 极度拥挤的情况下，回退到包含箱子的候选连通点中进行避让
		test_margin = 3
		while safe_candidates.is_empty() and test_margin >= 0:
			for pos in connected_region:
				if not is_near_void(pos, map_data, width, height, test_margin):
					safe_candidates.append(pos)
			test_margin -= 1
			
	if safe_candidates.is_empty():
		safe_candidates = connected_region # 终极保底

		
	# 1. 挑选安全候选区内最偏左上的格子作为第 1 个出生点
	var first_point = safe_candidates[0]
	for pos in safe_candidates:
		if (pos.x + pos.y) < (first_point.x + first_point.y):
			first_point = pos
	spawn_points.append(first_point)
	
	# 2. 贪心挑选距离其它已选中点欧式距离之和最远的下一个点
	for i in range(1, count):
		var best_candidate = safe_candidates[0]
		var max_dist_sum: float = -1.0
		
		for candidate in safe_candidates:
			if candidate in spawn_points: continue
			
			var dist_sum: float = 0.0
			for selected in spawn_points:
				dist_sum += Vector2(candidate).distance_to(Vector2(selected))
				
			if dist_sum > max_dist_sum:
				max_dist_sum = dist_sum
				best_candidate = candidate
				
		spawn_points.append(best_candidate)
		
	return spawn_points

# 强连通寻路可达校验：检测所有出生点是否可以通过 FLOOR (0) 或可炸毁的 SOFT_WALL (2) 连通彼此
static func verify_reachability(map_data: Array, width: int, height: int, spawn_points: Array[Vector2i]) -> bool:
	if spawn_points.is_empty(): return false
	
	var start = spawn_points[0]
	var visited := {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	
	while not queue.is_empty():
		var current = queue.pop_front()
		var neighbors = [
			Vector2i(current.x + 1, current.y),
			Vector2i(current.x - 1, current.y),
			Vector2i(current.x, current.y + 1),
			Vector2i(current.x, current.y - 1)
		]
		for n in neighbors:
			if n.x >= 0 and n.x < width and n.y >= 0 and n.y < height:
				# 寻路检测：-1 (VOID) 和 1 (HARD_WALL) 会被物理阻隔，0, 2, 3 可以连通
				var cell_val = map_data[n.x][n.y]
				if (cell_val == 0 or cell_val == 2 or cell_val == 3) and not visited.has(n):
					visited[n] = true
					queue.append(n)
					
	for sp in spawn_points:
		if not visited.has(sp):
			return false
			
	return true

# 清除出生点防困安全区 (仅保留朝内侧 2 格 L 形经典窄通道，极大提升紧迫感)
static func apply_spawn_safety_zones(map_data: Array, width: int, height: int, spawn_points: Array[Vector2i]) -> Array:
	var modified_map = map_data.duplicate(true)
	var cx = width / 2
	var cy = height / 2
	
	for sp in spawn_points:
		# 1. 强行设出生点自身为 3
		modified_map[sp.x][sp.y] = 3
		
		# 2. 根据到中心点 (cx, cy) 的象限相对方位，选择向内侧开辟的 2 个通道邻居
		# 左半边朝右，右半边朝左；上半边朝下，下半边朝上
		var choice_x = 1 if sp.x < cx else -1
		var choice_y = 1 if sp.y < cy else -1
		
		var target_h = Vector2i(sp.x + choice_x, sp.y)
		var target_v = Vector2i(sp.x, sp.y + choice_y)
		
		# 3. 只要目标在有效格内且不是 VOID (-1)，强行抹平成空地板 0
		if target_h.x >= 0 and target_h.x < width and target_h.y >= 0 and target_h.y < height:
			if modified_map[target_h.x][target_h.y] != -1:
				modified_map[target_h.x][target_h.y] = 0
				
		if target_v.x >= 0 and target_v.x < width and target_v.y >= 0 and target_v.y < height:
			if modified_map[target_v.x][target_v.y] != -1:
				modified_map[target_v.x][target_v.y] = 0
				
	return modified_map
