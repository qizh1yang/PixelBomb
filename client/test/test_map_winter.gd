# map_winter 测试脚本
# 用于验证程序化地图生成功能
# 创建时间：2026-05-09

extends Node2D

@onready var map_winter = $map_winter
@onready var status_label = $CanvasLayer/StatusLabel

func _ready() -> void:
	# 等待地图生成完成
	if map_winter and map_winter.has_signal("map_generated"):
		map_winter.map_generated.connect(_on_map_generated)
	
	# 使用默认种子生成地图
	_generate_map_with_seed(12345)

	# 自动化模拟开箱测试（验证重构后各阶段及软保底的全部日志表现）
	print("================= START Loot Chest Simulation =================")
	# 重置全局状态以便进行纯净测试
	GlobalPlayerData.opened_chests_count = 0
	GlobalPlayerData.chests_since_last_diamond = 0
	
	# 加载宝箱场景并实例化，专门用来进行纯逻辑算法校验
	var test_chest = load("res://prefabs/items/Chest/chest.tscn").instantiate()
	add_child(test_chest)
	
	for c_idx in range(60):
		# 模拟宝箱开启的阶段更新时序
		test_chest._diamond_looted_this_chest = false
		GlobalPlayerData.opened_chests_count += 1
		
		# 每个宝箱产出 1~2 个物品
		var roll_count = randi() % 2 + 1
		for r_idx in range(roll_count):
			test_chest._get_random_outfit_path()
			
		# 根据本箱中是否抽中钻石来计算保底重置/累加
		if test_chest._diamond_looted_this_chest:
			GlobalPlayerData.chests_since_last_diamond = 0
			print("[TEST-SIM] Simulated Diamond hit on Chest %d! Reset pity to 0." % [c_idx + 1])
		else:
			GlobalPlayerData.chests_since_last_diamond += 1
			print("[TEST-SIM] Simulated Chest %d open. Pity now: %d" % [c_idx + 1, GlobalPlayerData.chests_since_last_diamond])
			
	test_chest.queue_free()
	print("================= END Loot Chest Simulation =================")


func _generate_map_with_seed(custom_seed: int = -1) -> void:
	if map_winter == null:
		push_error("[TEST] map_winter not found!")
		return
	
	var seed_val = custom_seed if custom_seed > 0 else int(Time.get_unix_time_from_system())
	
	print("[TEST] Generating map with seed: %d" % seed_val)
	status_label.text = "Generating map with seed: %d" % seed_val
	
	map_winter._generate_map(seed_val)


func _on_map_generated(seed_val: int) -> void:
	print("[TEST] Map generated successfully with seed: %d" % seed_val)
	status_label.text = "Map generated! Seed: %d\nPress R to regenerate\nPress S to save map data" % seed_val


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.key_label == "R":
			# 重新生成地图
			_generate_map_with_seed()
		elif event.key_label == "S":
			# 保存地图数据到文件
			_save_map_data()
		elif event.key_label == "L":
			# 从文件加载地图数据
			_load_map_data()


func _save_map_data() -> void:
	if map_winter == null: return
	
	var file_path = "user://map_winter_data.json"
	map_winter.export_map_data(file_path)
	status_label.text += "\nMap data saved to: " + file_path
	print("[TEST] Map data saved to: " + file_path)


func _load_map_data() -> void:
	if map_winter == null: return
	
	var file_path = "user://map_winter_data.json"
	map_winter.import_map_data(file_path)
	status_label.text += "\nMap data loaded from: " + file_path
	print("[TEST] Map data loaded from: " + file_path)
