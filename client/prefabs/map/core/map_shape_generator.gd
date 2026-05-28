# 高精度地图外轮廓与形状 Shape Mask 生成器
# 仅保留并专注实现 5 种高精度、对称性佳且可玩性极强的地图几何形状
# 创建时间：2026-05-27

extends RefCounted

class_name MapShapeGenerator

# 核心 Shape Mask 裁切与虚空标定
# 返回 width x height 二维数组，内格为 0 (地板) 或 -1 (VOID)
static func generate_shape_mask(shape_type: String, width: int, height: int, map_seed: int, noise: FastNoiseLite) -> Array:
	seed(map_seed)
	
	var map_data: Array = []
	map_data.resize(width)
	for x in range(width):
		map_data[x] = []
		for y in range(height):
			map_data[x].append(-1) # 默认所有地方都是 -1 (VOID)
			
	var center = Vector2((width - 1) / 2.0, (height - 1) / 2.0)
	var max_radius = min(width, height) / 2.0 - 0.5
	var edge_strength = 2.0 # 保持自然的边缘扰动
	
	match shape_type.to_lower():
		"circle":
			# 真正圆形悬浮大陆（高轴对称公平竞技场）
			for x in range(width):
				for y in range(height):
					# 镜像对称取坐标以确保边缘噪声 100% 轴对称
					var sym_x = x if x < center.x else (width - 1 - x)
					var sym_y = y if y < center.y else (height - 1 - y)
					var n_val = noise.get_noise_2d(sym_x, sym_y)
					
					var perturbed_radius = max_radius + n_val * edge_strength
					var pos = Vector2(x, y)
					if center.distance_to(pos) <= perturbed_radius:
						map_data[x][y] = 0
						
		"hexagon":
			# 真正六边形悬浮大陆（采用 flat-topped 正六边形公式边界，四轴镜像对称）
			var hex_h = max_radius * sqrt(3.0) / 2.0 # 正六边形高
			for x in range(width):
				for y in range(height):
					var sym_x = x if x < center.x else (width - 1 - x)
					var sym_y = y if y < center.y else (height - 1 - y)
					var n_val = noise.get_noise_2d(sym_x, sym_y)
					
					# 带有对称噪声起伏的六边形边界半径
					var r_bound = max_radius + n_val * edge_strength
					var h_bound = r_bound * sqrt(3.0) / 2.0
					
					var dx = abs(x - center.x)
					var dy = abs(y - center.y)
					
					# 正六边形斜边界公式判定
					var in_height = dy <= h_bound
					var in_slant = dx + dy / sqrt(3.0) <= r_bound
					
					if in_height and in_slant:
						map_data[x][y] = 0
						
		"star":
			# 真正五角星神殿（基于极坐标五角星波形函数极值判定）
			# R(theta) = R_avg + R_amp * cos(5 * theta)
			var r_avg = max_radius * 0.70
			var r_amp = max_radius * 0.28
			
			for x in range(width):
				for y in range(height):
					var dx = x - center.x
					var dy = y - center.y
					var dist = center.distance_to(Vector2(x, y))
					
					# 极坐标角度 theta (范围 -PI 到 PI)
					var theta = atan2(dy, dx)
					
					# 五角星极值波形公式
					var star_radius = r_avg + r_amp * cos(5.0 * theta)
					
					# 叠加轻微非对称边缘噪声丰富质感
					var n_val = noise.get_noise_2d(x, y)
					star_radius += n_val * (edge_strength * 0.5)
					
					if dist <= star_radius:
						map_data[x][y] = 0
						
		"ring":
			# 真正环形大陆（中央为空洞，带有4条跨深渊的坚固实木对称连通桥梁）
			var inner_radius = max_radius * 0.40
			var outer_radius = max_radius
			
			for x in range(width):
				for y in range(height):
					var sym_x = x if x < center.x else (width - 1 - x)
					var sym_y = y if y < center.y else (height - 1 - y)
					var n_val = noise.get_noise_2d(sym_x, sym_y)
					
					var perturbed_outer = outer_radius + n_val * edge_strength
					var perturbed_inner = inner_radius - n_val * (edge_strength * 0.5)
					
					var pos = Vector2(x, y)
					var dist = center.distance_to(pos)
					
					# 1. 基础环体部分
					var in_ring = dist >= perturbed_inner and dist <= perturbed_outer
					
					# 2. 跨深渊连接桥梁（0, 90, 180, 270 度，即 X 轴与 Y 轴方向宽度为 3 的通道）
					# 在外半径以内，且 Y 偏离中心在 1.5 以内 (Chebyshev/Manhattan 3格通道) 或 X 偏离中心在 1.5 以内
					var is_bridge = dist <= perturbed_outer and (abs(y - center.y) <= 1.5 or abs(x - center.x) <= 1.5)
					
					if in_ring or is_bridge:
						map_data[x][y] = 0
						
		"cave":
			# 经典 CA 元胞自动机收缩洞穴
			# 初始化随机矩阵，中心密集度高，边缘全部为 VOID (-1)
			for x in range(width):
				for y in range(height):
					if x == 0 or x == width - 1 or y == 0 or y == height - 1:
						map_data[x][y] = -1
						continue
					
					var dist_factor = center.distance_to(Vector2(x, y)) / max_radius
					var void_chance = lerp(0.38, 0.70, clamp(dist_factor, 0.0, 1.0))
					
					if randf() < void_chance:
						map_data[x][y] = -1
					else:
						map_data[x][y] = 0
						
			# 4次元胞自动机收缩迭代，形成曲折洞穴
			for step in range(4):
				var next_step: Array = []
				next_step.resize(width)
				for x in range(width):
					next_step[x] = map_data[x].duplicate(true)
					
				for x in range(1, width - 1):
					for y in range(1, height - 1):
						var void_count = 0
						for dx in range(-1, 2):
							for dy in range(-1, 2):
								if map_data[x + dx][y + dy] == -1:
									void_count += 1
									
						if void_count >= 5:
							next_step[x][y] = -1
						elif void_count <= 3:
							next_step[x][y] = 0
				map_data = next_step
				
	return map_data
