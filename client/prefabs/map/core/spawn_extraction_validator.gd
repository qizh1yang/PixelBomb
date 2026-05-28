# 公平性撤离与出生验证器 (Fairness Solver & Spawn Extraction Validator)
# 用于计算所有玩家到撤离点的最短行走路径，控制路径差值在 15% 以内，实现竞技公平
# 创建时间：2026-05-27

extends RefCounted

class_name SpawnExtractionValidator

# 检查撤离点候选格子是否合法：不贴边、不紧靠虚空、未被障碍死锁包围
static func is_valid_extraction_candidate(pos: Vector2i, map_data: Array, width: int, height: int) -> bool:
	# 必须是可行走的陆地地板 (0)
	if pos.x < 0 or pos.x >= width or pos.y < 0 or pos.y >= height:
		return false
	if map_data[pos.x][pos.y] != 0:
		return false
		
	# 不贴近地图极限物理边缘（预留 2 格缓冲，防止玩家挤在墙角）
	if pos.x < 2 or pos.x >= width - 2 or pos.y < 2 or pos.y >= height - 2:
		return false
		
	# 8 邻域检查：绝对不能靠着 VOID (-1) 虚空深渊
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cx = pos.x + dx
			var cy = pos.y + dy
			if cx < 0 or cx >= width or cy < 0 or cy >= height:
				return false
			if map_data[cx][cy] == -1:
				return false
				
	# 4 邻域检查：不能被硬墙 (1) 彻底包围，至少需要有 2 格空地可以挪腾
	var walk_neighbors = 0
	var neighbors = [
		Vector2i(pos.x + 1, pos.y),
		Vector2i(pos.x - 1, pos.y),
		Vector2i(pos.x, pos.y + 1),
		Vector2i(pos.x, pos.y - 1)
	]
	for n in neighbors:
		if map_data[n.x][n.y] == 0 or map_data[n.x][n.y] == 3:
			walk_neighbors += 1
			
	return walk_neighbors >= 2

# BFS 计算地图上任意两点之间的最短真实可行走路径步数
# 允许跨越空地 (0, 3) 以及可炸毁的软墙箱子 (2)（因为软墙箱子前期可以被炸开联通，但不能穿越 1 或 -1）
static func get_path_distance(start: Vector2i, end: Vector2i, map_data: Array, width: int, height: int) -> int:
	if start == end: return 0
	
	var visited := {}
	var queue: Array[Array] = [[start, 0]]
	visited[start] = true
	
	while not queue.is_empty():
		var item = queue.pop_front()
		var curr = item[0]
		var dist = item[1]
		
		if curr == end:
			return dist
			
		var neighbors = [
			Vector2i(curr.x + 1, curr.y),
			Vector2i(curr.x - 1, curr.y),
			Vector2i(curr.x, curr.y + 1),
			Vector2i(curr.x, curr.y - 1)
		]
		
		for n in neighbors:
			if n.x >= 0 and n.x < width and n.y >= 0 and n.y < height:
				var val = map_data[n.x][n.y]
				# 允许穿越 0, 2, 3，不允许穿越 1 (硬墙) 或 -1 (虚空)
				if (val == 0 or val == 2 or val == 3) and not visited.has(n):
					visited[n] = true
					queue.append([n, dist + 1])
					
	return -1 # 物理不可达

# 核心 Fairness Solver：寻找与所有出生点行走距离最均衡的黄金撤离点
static func solve_extraction_point(map_data: Array, width: int, height: int, spawn_points: Array[Vector2i], shape_type: String) -> Dictionary:
	var best_pos = Vector2i(-1, -1)
	var min_imbalance = 999.0
	var best_distances: Array[int] = []
	
	# 如果是高度对称的地图（Circle, Hexagon, Ring），物理中心点是天然最公平的撤离点，可以直接尝试使用
	var center = Vector2i(width / 2, height / 2)
	if shape_type.to_lower() in ["circle", "hexagon", "ring"]:
		if is_valid_extraction_candidate(center, map_data, width, height):
			var dists: Array[int] = []
			var all_reachable = true
			for sp in spawn_points:
				var d = get_path_distance(sp, center, map_data, width, height)
				if d < 0:
					all_reachable = false
					break
				dists.append(d)
				
			if all_reachable:
				var max_d = dists.max()
				var min_d = dists.min()
				var diff_pct = (max_d - min_d) / float(max_d) if max_d > 0 else 0.0
				
				# 在镜像对称下，如果极差百分比非常小（近乎 0），则直接钦定为中心撤离点，实现完美对称！
				if diff_pct <= 0.05:
					return {
						"extraction_point": center,
						"imbalance_score": diff_pct,
						"distances": dists
					}
					
	# 否则或未通过时，遍历全地图候选格点进行最优距离差值检索
	for x in range(width):
		for y in range(height):
			var cand = Vector2i(x, y)
			if not is_valid_extraction_candidate(cand, map_data, width, height):
				continue
				
			# 计算 4 个出生点到该格子的真实步数
			var dists: Array[int] = []
			var all_reachable = true
			for sp in spawn_points:
				var d = get_path_distance(sp, cand, map_data, width, height)
				if d < 0:
					all_reachable = false
					break
				dists.append(d)
				
			if not all_reachable:
				continue
				
			var max_d = dists.max()
			var min_d = dists.min()
			if max_d == 0: continue
			
			# 路径不平衡极差比例
			var diff_pct = (max_d - min_d) / float(max_d)
			
			# 贪心保留极差百分比最小（最公平）的那个位置作为黄金分割点
			if diff_pct < min_imbalance:
				min_imbalance = diff_pct
				best_pos = cand
				best_distances = dists
				
	return {
		"extraction_point": best_pos,
		"imbalance_score": min_imbalance if best_pos != Vector2i(-1, -1) else 999.0,
		"distances": best_distances
	}

# 出生点与撤离点综合公平可达性校验
static func validate_spawn_and_extraction(map_data: Array, width: int, height: int, spawn_points: Array[Vector2i], extraction_point: Vector2i, imbalance_score: float, shape_type: String, attempt: int = 1) -> bool:
	if spawn_points.size() < 4 or extraction_point == Vector2i(-1, -1):
		return false
		
	# 1. 验证出生点互相之间的物理曼哈顿距离是否合理拉开（防止挤在一起）
	var min_spawn_dist = width * 0.35
	# 动态自适应放宽：当多次尝试失败时，微调拉开距离，避免出生点由于地图极度狭窄被卡死
	if attempt > 4:
		min_spawn_dist = max(width * 0.22, min_spawn_dist - (attempt - 4) * 0.6)
		
	for i in range(spawn_points.size()):
		for j in range(i + 1, spawn_points.size()):
			var manhattan = abs(spawn_points[i].x - spawn_points[j].x) + abs(spawn_points[i].y - spawn_points[j].y)
			if manhattan < min_spawn_dist:
				return false
				
	# 2. 验证每个玩家到撤离点的距离不能过近（不能出生即毕业，至少需要走一定步数）
	var min_step = 6
	if width <= 31:
		min_step = 5 # Small 地图尺寸较小，放宽到 5 步即可
		
	# 动态自适应放宽：若重滚多次依然失败，逐渐降低逃生距离步数要求，最低保留 3 步，保证地图可玩
	if attempt > 5:
		min_step = max(3, min_step - (attempt - 5))
		
	for sp in spawn_points:
		var d = get_path_distance(sp, extraction_point, map_data, width, height)
		if d < min_step:
			return false
			
	# 3. Path Balance Score 公平性检查
	var limit = 0.15 # 默认限制为 15%
	if shape_type.to_lower() == "cave":
		limit = 0.30 # 洞穴地貌复杂，宽容度放宽至 30%
	elif width <= 31:
		limit = 0.20 # 31x31 尺寸相对较小，路径离散步数差异大，宽容度放宽至 20%
		
	# 动态自适应放宽：在尝试重试次数增加时，代表当前种子地形极其复杂，逐渐线性调宽公平限度，最低也强于回退 classic 形状
	if attempt > 3:
		limit += 0.05 * (attempt - 3)
		
	if imbalance_score > limit:
		print("[VALIDATOR] Path Balance Check FAILED: Imbalance %.1f%% exceeds limit of %.1f%% (Attempt %d)" % [imbalance_score * 100.0, limit * 100.0, attempt])
		return false
		
	print("[VALIDATOR] Spawn & Extraction Validation PASSED. Imbalance: %.1f%% (Attempt %d)" % [imbalance_score * 100.0, attempt])
	return true
