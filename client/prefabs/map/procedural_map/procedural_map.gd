# 万能模块化程序化生成地图场景控制器
# 支撑随机生成对局、JSON 导出、物理图块权重渲染和 PNG 小预览合成
# 创建时间：2026-05-27

extends Node2D

class_name ProceduralMap

# 派发生成完成信号，携带种子，与原有 Stage 流程保持完美对接
signal map_generated(seed_val: int)

@export_group("Map Core Settings")
# 自定义程序化地图详细资源配置文件 (MapConfig.tres)
@export var map_config: MapConfig = null

# 地图预设尺寸大小 Small/Medium/Large
@export_enum("small", "medium", "large") var map_size: String = "small"
# 形状算法
@export_enum("circle", "hexagon", "star", "ring", "cave") var shape_type: String = "circle"
# 可选的美术样式资源配置
@export var theme_config: MapThemeConfig = null
# 可破坏箱子填充密度
@export var soft_wall_rate: float = 0.38


@export_group("Developer & Debug Tools")
# 是否在屏幕上渲染 BFS 强连通拓扑绿线与几何边缘红梁
@export var show_debug_overlay: bool = false

# 内部业务状态（完全对齐 GameMode 的数据索取需求）
var is_offline_mode: bool = false
var _map_seed: int = 0
var _map_ready: bool = false

# 二维逻辑地图数据矩阵与出生点坐标
var map_data: Array = []
var spawn_points: Array[Vector2i] = []
var extraction_point: Vector2i = Vector2i(-1, -1)
var imbalance_score: float = 0.0
var distances: Array[int] = []

@onready var wall_layer: ProceduralWallLayer = $wallLayer
@onready var floor_layer: TileMapLayer = $FloorLayer

# 动态生成的调试叠加绘制层实例
var _debug_overlay_instance: MapDebugOverlay = null

# 标记是否已被外部注入配置（GameStage._apply_map_config 设置）
var _config_injected: bool = false

func _ready() -> void:
	# 如果外部已注入配置，说明 shape/size/seed 已经由 GameStage 设置好了
	if _config_injected:
		print("[PROCEDURAL_MAP] Config already injected externally, generating with injected params...")
		print("[PROCEDURAL_MAP]   shape=%s size=%s" % [shape_type, map_size])
		_generate_map(int(Time.get_unix_time_from_system()) if _map_seed == 0 else _map_seed)
		return

	# 联机模式下由网络同步驱动生成
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_connected_to_host:
		# [MAP CONFIG] 从 NetworkManager 读取 Host 选择的 shape/size
		if net.current_shape_type != "":
			shape_type = net.current_shape_type
			print("[PROCEDURAL_MAP] Using network shape_type: %s" % shape_type)
		if net.current_map_size != "":
			map_size = net.current_map_size
			print("[PROCEDURAL_MAP] Using network map_size: %s" % map_size)
		if net.seed_received:
			print("[PROCEDURAL_MAP] Generating with network seed: %d" % net.map_seed)
			_generate_map(net.map_seed)
		else:
			print("[PROCEDURAL_MAP] Waiting for seed via room_joined signal...")
			net.room_joined.connect(_on_seed_received, CONNECT_ONE_SHOT)
	else:
		is_offline_mode = true
		_map_seed = int(Time.get_unix_time_from_system())
		print("[PROCEDURAL_MAP] Offline mode: generating with seed %d, shape=%s, size=%s" % [_map_seed, shape_type, map_size])
		_generate_map(_map_seed)

func _on_seed_received(_seed: int) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net:
		print("[PROCEDURAL_MAP] Seed received via signal: %d" % net.map_seed)
		_generate_map(net.map_seed)

# 本地核心逻辑生成与图元绘制管道主入口
func _generate_map(seed_val: int) -> void:
	_map_seed = seed_val
	
	# 1. 实例化 Core 数据生成引擎
	var core = MapGeneratorCore.new()
	if map_config:
		core.apply_config(map_config)
		shape_type = core.shape_type
		map_size = core.map_size
	else:
		core.set_map_size_by_name(map_size)
		core.shape_type = shape_type
		core.soft_wall_rate = soft_wall_rate
		
	# 2. 生成纯数据逻辑网格
	var result = core.generate_logical_map(seed_val)
	map_data = result["map_data"]
	
	spawn_points.clear()
	if result.has("spawn_points"):
		var raw_spawns = result["spawn_points"]
		for sp in raw_spawns:
			spawn_points.append(Vector2i(sp))
			
	extraction_point = result.get("extraction_point", Vector2i(-1, -1))
	imbalance_score = result.get("imbalance_score", 0.0)
	
	distances.clear()
	if result.has("distances"):
		var raw_dists = result["distances"]
		for d in raw_dists:
			distances.append(int(d))

	
	var w = result["width"]
	var h = result["height"]
	
	# 3. 将数据注入物理碰撞 wallLayer，使其对外部寻路、炸弹提供原汁原味的底层支持
	wall_layer.setup_logical_data(map_data, spawn_points, w, h, theme_config)
	if "extraction_point" in wall_layer:
		wall_layer.extraction_point = extraction_point
		
	# 4. 调用解耦的渲染器在 FloorLayer 和 wallLayer 分层着色和绘制
	var renderer = MapRenderer.new()
	renderer.render_map(wall_layer, floor_layer, map_data, w, h, theme_config)
	
	# 5. 可视化寻路和状态叠加层控制
	_update_debug_overlay()
	
	# 6. 数据及预览图自动保存导出
	export_map_to_json("user://last_procedural_map.json")
	export_map_to_png("user://map_preview.png")
	
	_map_ready = true
	map_generated.emit(seed_val)
	print("[PROCEDURAL_MAP] Map successfully generated & rendered. Seed: %d" % seed_val)

# 二维逻辑地图数据序列化导出 JSON
func export_map_to_json(file_path: String) -> void:
	if map_data.is_empty(): return
	
	var export_dict = {
		"seed": _map_seed,
		"size": map_size,
		"shape": shape_type,
		"width": map_data.size(),
		"height": map_data[0].size(),
		"spawn_points": [],
		"extraction_point": [extraction_point.x, extraction_point.y],
		"imbalance_score": imbalance_score,
		"map_matrix": map_data
	}
	
	for sp in spawn_points:
		export_dict["spawn_points"].append([sp.x, sp.y])
		
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(export_dict, "  "))
		file.close()
		print("[MAP_EXPORT] Logical data exported to: %s" % ProjectSettings.globalize_path(file_path))
	else:
		push_error("[MAP_EXPORT] Failed to open path: %s for JSON writing!" % file_path)

# 将当前的二维数据直接高效合成压缩保存为本地 PNG 小预览缩略图
func export_map_to_png(file_path: String) -> void:
	if map_data.is_empty(): return
	
	var w = map_data.size()
	var h = map_data[0].size()
	
	# 新建一幅与地图尺寸完美像素对齐的内存图像
	var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	
	for x in range(w):
		for y in range(h):
			var val = map_data[x][y]
			var color = Color.WHITE # 默认为地板空闲区：白色
			
			match val:
				-1:
					color = Color(0, 0, 0, 0)  # 虚空区：完全透明
				1:
					color = Color.BLACK        # 不可破坏墙：黑色
				2:
					color = Color.DARK_GRAY    # 可破坏箱子：深灰色
				3:
					color = Color.RED          # 曼哈顿出生点：红色
				4:
					color = Color.BLUE         # 特殊地形：蓝色
				5:
					color = Color.GREEN        # 撤离点：绿色
					
			img.set_pixel(x, y, color)
			
	var err = img.save_png(file_path)
	if err == OK:
		print("[MAP_EXPORT] Mini preview thumbnail saved successfully at: %s" % ProjectSettings.globalize_path(file_path))
	else:
		push_error("[MAP_EXPORT] Failed to save PNG preview. Error code: %d" % err)

# 获取非虚空陆地网格的最小与最大活动包围盒 (Bounding Box)
func get_active_bounds() -> Rect2i:
	if map_data.is_empty():
		return Rect2i(0, 0, 0, 0)
		
	var w = map_data.size()
	var h = map_data[0].size()
	
	var min_x = w
	var max_x = -1
	var min_y = h
	var max_y = -1
	
	for x in range(w):
		for y in range(h):
			if map_data[x][y] != -1:
				if x < min_x: min_x = x
				if x > max_x: max_x = x
				if y < min_y: min_y = y
				if y > max_y: max_y = y
				
	if max_x == -1: # 如果全是 VOID
		return Rect2i(0, 0, w, h)
		
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


# 动态开关和更新寻路调试层
func _update_debug_overlay() -> void:
	if show_debug_overlay:
		if not is_instance_valid(_debug_overlay_instance):
			_debug_overlay_instance = MapDebugOverlay.new()
			add_child(_debug_overlay_instance)
			_debug_overlay_instance.z_index = 5 # 处于高层遮罩
		
		_debug_overlay_instance.setup_fairness(
			map_data, 
			spawn_points, 
			_map_seed, 
			shape_type, 
			extraction_point, 
			imbalance_score, 
			distances
		)
	else:
		if is_instance_valid(_debug_overlay_instance):
			_debug_overlay_instance.queue_free()
			_debug_overlay_instance = null

func _process(_delta: float) -> void:
	# 支持在对局中动态监听并微调开发调试叠加层的绘制更新
	if show_debug_overlay and not is_instance_valid(_debug_overlay_instance):
		_update_debug_overlay()
	elif not show_debug_overlay and is_instance_valid(_debug_overlay_instance):
		_update_debug_overlay()
