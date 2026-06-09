extends Node

signal inventory_updated()
signal backpack_updated()
signal sync_completed()

# 拥有的物品列表 (仅限仓库/Stash，不含已装备的)
var owned_items: Array[String] = []

# 当前背包配置 (已装备的物品)
# 格式: { "res_path": String, "grid_pos": Vector2i, "is_insurance": bool, "rotated": bool }
var backpack_config: Array[Dictionary] = []

# 战备方案 (Presets)
var backpack_presets: Array[Array] = [[], [], []]

var coins: int = 12500
var player_name: String = "破壁者"

# 局内统计：记录本局开启的宝箱数量
var opened_chests_count: int = 0
# 钻石装备软保底计数器：自上一次获得钻石装备以来开启的宝箱数量
var chests_since_last_diamond: int = 0

# 新手引导首次游戏判定
var is_first_game: bool = true

func _ready() -> void:
	# 连接网络同步信号
	NetworkManager.profile_loaded.connect(_on_profile_loaded)
	pass

func _initial_sync() -> void:
	if NetworkManager.my_id != "":
		NetworkManager.fetch_profile()

func _on_profile_loaded(data: Dictionary) -> void:
	print("[GlobalPlayerData] Profile synced from server")
	if data.has("coins"): coins = data["coins"]
	if data.has("name"): player_name = data["name"]
	if data.has("is_first_game"): is_first_game = data["is_first_game"]
	
	if data.get("backpack_config") != null:
		backpack_config.clear()
		print("[GlobalPlayerData] Syncing Backpack: ", data["backpack_config"].size(), " items")
		for item in data["backpack_config"]:
			var pos_arr = item.get("grid_pos", [0, 0])
			backpack_config.append({
				"res_path": item["res_path"],
				"grid_pos": Vector2i(pos_arr[0], pos_arr[1]),
				"is_insurance": item["is_insurance"],
				"rotated": item["rotated"]
			})
	
	# 核心修复：服务器下发的 inventory 应该是 Stash（不含背包内物品）
	if data.get("inventory") != null:
		owned_items.clear()
		print("[GlobalPlayerData] Syncing Stash: ", data["inventory"].size(), " items")
		for item in data["inventory"]:
			owned_items.append(item)
	
	if data.get("presets") != null:
		backpack_presets.clear()
		for p_data in data["presets"]:
			var preset_config = []
			for item in p_data:
				var pos_arr = item.get("grid_pos", [0, 0])
				preset_config.append({
					"res_path": item["res_path"],
					"grid_pos": Vector2i(pos_arr[0], pos_arr[1]),
					"is_insurance": item["is_insurance"],
					"rotated": item["rotated"]
				})
			backpack_presets.append(preset_config)
		while backpack_presets.size() < 3:
			backpack_presets.append([])
	
	inventory_updated.emit()
	backpack_updated.emit()
	sync_completed.emit()

func add_item(res_path: String) -> void:
	owned_items.append(res_path)
	inventory_updated.emit()

func remove_item(res_path: String) -> void:
	if res_path in owned_items:
		owned_items.erase(res_path)
		inventory_updated.emit()

func save_backpack(config: Array[Dictionary]) -> void:
	backpack_config = config
	backpack_updated.emit()
	sync_to_server()

func save_preset(index: int, config: Array[Dictionary]) -> void:
	if index >= 0 and index < backpack_presets.size():
		backpack_presets[index] = config
		
		# 同步到服务端
		var remote_presets = []
		for p in backpack_presets:
			var p_config = []
			for item in p:
				p_config.append({
					"res_path": item["res_path"],
					"grid_pos": [item["grid_pos"].x, item["grid_pos"].y],
					"is_insurance": item["is_insurance"],
					"rotated": item["rotated"]
				})
			remote_presets.append(p_config)
		
		NetworkManager.push_presets(remote_presets)
		print("[GlobalPlayerData] Presets pushed to server")

func sync_to_server() -> void:
	# 同时推送背包布局和仓库状态，确保原子性
	var remote_config = []
	for item in backpack_config:
		remote_config.append({
			"res_path": item["res_path"],
			"grid_pos": [item["grid_pos"].x, item["grid_pos"].y],
			"is_insurance": item["is_insurance"],
			"rotated": item["rotated"]
		})
	
	NetworkManager.push_backpack_config(NetworkManager.my_id, remote_config)
	NetworkManager.push_inventory_config(owned_items, coins)
	print("[GlobalPlayerData] Full profile (Backpack + Inventory) pushed to server")

# 将局内提取出的物品存入仓库
func collect_items_from_backpack(item_resources: Array) -> void:
	# 注意：在我们的逻辑中，提取出的物品已经在 final_config (BackpackConfig) 里了
	inventory_updated.emit()
	backpack_updated.emit()

func sell_item(res_path: String, price: int) -> void:
	if res_path in owned_items:
		owned_items.erase(res_path)
		coins += price
		inventory_updated.emit()
		sync_to_server()
