# 局外宝箱逻辑
# 炸毁墙壁后有 5% 概率掉落
# 炸毁墙壁后有 20% 概率掉落
# 开启需要 1.5 秒，开启后 40% 概率获得局外物品（OutfitItem）
# 创建时间：2026-05-11

extends Area2D

class_name LootChest

# ── 信号 ──
signal opened(item_resource: BackpackItemResource)

# ── 常量 ──
const OPEN_TIME: float = 1.5  # 开启时间
const LOOT_CHANCE: float = 0.4 # 40% 爆率

# ── 调试开关 ──
const DEBUG_FORCE_LOOT: bool = false  # 关闭强制出货

# ── 节点引用 ──
@onready var sprite: Sprite2D = $Sprite2D
@onready var progressBar: ProgressBar = $ProgressBar
@onready var timer: Timer = $Timer

# ── 内部变量 ──
var _is_player_inside: bool = false
var _opening_progress: float = 0.0
var _is_opened: bool = false
var chestID: String = ""

# 局外物品池（按类别和权重定义）
# 稀有(Rare): 55%, 史诗(Epic): 35%, 钻石(Diamond): 10%
var _outfit_pool_data: Dictionary = {
	"bomb": {
		"items": ["res://prefabs/OutfitItems/outfit_bag_large.tres", "res://prefabs/OutfitItems/outfit_suitcase_wood.tres", "res://prefabs/OutfitItems/outfit_pumpkin_giant.tres"],
		"weights": [55, 35, 10]
	},
	"speed": {
		"items": ["res://prefabs/OutfitItems/outfit_speed_1.tres", "res://prefabs/OutfitItems/outfit_speed_3.tres", "res://prefabs/OutfitItems/outfit_speed_5.tres"],
		"weights": [55, 35, 10]
	},
	"power_all": {
		"items": ["res://prefabs/OutfitItems/outfit_power_1.tres", "res://prefabs/OutfitItems/outfit_power_2.tres", "res://prefabs/OutfitItems/outfit_power_3.tres"],
		"weights": [55, 35, 10]
	},
	"power_left": {
		"items": ["res://prefabs/OutfitItems/outfit_power_left_1.tres", "res://prefabs/OutfitItems/outfit_power_left_2.tres", "res://prefabs/OutfitItems/outfit_power_left_3.tres"],
		"weights": [55, 35, 10]
	},
	"power_right": {
		"items": ["res://prefabs/OutfitItems/outfit_power_right_1.tres", "res://prefabs/OutfitItems/outfit_power_right_2.tres", "res://prefabs/OutfitItems/outfit_power_right_3.tres"],
		"weights": [55, 35, 10]
	},
	"power_up": {
		"items": ["res://prefabs/OutfitItems/outfit_power_up_1.tres", "res://prefabs/OutfitItems/outfit_power_up_2.tres", "res://prefabs/OutfitItems/outfit_power_up_3.tres"],
		"weights": [55, 35, 10]
	},
	"power_down": {
		"items": ["res://prefabs/OutfitItems/outfit_power_down_1.tres", "res://prefabs/OutfitItems/outfit_power_down_2.tres", "res://prefabs/OutfitItems/outfit_power_down_3.tres"],
		"weights": [55, 35, 10]
	},
	"special": {
		"items": ["res://prefabs/OutfitItems/outfit_epic_shield.tres"],
		"weights": [100]
	}
}

func _get_random_outfit_path() -> String:
	var current_opened = GlobalPlayerData.opened_chests_count
	var diamond_items = [
		"outfit_pumpkin_giant.tres",
		"outfit_speed_5.tres",
		"outfit_power_3.tres",
		"outfit_power_left_3.tres",
		"outfit_power_right_3.tres",
		"outfit_power_up_3.tres",
		"outfit_power_down_3.tres",
		"outfit_epic_shield.tres"
	]
	
	var categories = _outfit_pool_data.keys()
	# 如果开启次数小于3，剔除 special 类别（因为里面全是钻石级物品）
	if current_opened < 3:
		categories.erase("special")
	
	var cat = categories.pick_random()
	var data = _outfit_pool_data[cat]
	
	# 过滤数据池：如果开启次数小于3，暂时移除钻石级物品并重算权重
	var available_items = []
	var available_weights = []
	for i in range(data.items.size()):
		var is_diamond = false
		for d in diamond_items:
			if d in data.items[i]:
				is_diamond = true
				break
		
		if current_opened >= 3 or not is_diamond:
			available_items.append(data.items[i])
			available_weights.append(data.weights[i])
	
	# 如果该类别下没有可用物品（理论上不应该，除非全被过滤了），回退到第一个
	if available_items.is_empty():
		return data.items[0]

	var total_weight = 0
	for w in available_weights: total_weight += w
	
	var r = randi() % total_weight
	var current_w = 0
	for i in range(available_items.size()):
		current_w += available_weights[i]
		if r < current_w:
			return available_items[i]
	return available_items[0]

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 # 检测玩家
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	progressBar.hide()
	progressBar.max_value = OPEN_TIME
	progressBar.value = 0
	
	print("[CHEST] Chest spawned at %s" % global_position)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		# 只有本地玩家可以开启（简化逻辑，防止多人冲突）
		if "isLocal" in body and body.isLocal:
			_is_player_inside = true
			print("[CHEST] Player started opening chest")

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		if "isLocal" in body and body.isLocal:
			_is_player_inside = false
			print("[CHEST] Player left chest")

var _loot_ui_instance: Control = null

func _complete_opening() -> void:
	_is_opened = true
	progressBar.hide()
	
	# 增加开启计数
	GlobalPlayerData.opened_chests_count += 1
	print("[CHEST] Chest opened! Total count this match: %d" % GlobalPlayerData.opened_chests_count)
	
	# 播放开启音效
	_play_sfx("res://assets/audio/sfx/Explosion.wav")
	
	# 打开摸金界面（左右分屏）
	_spawn_loot_ui()
	
	# 动画效果：宝箱保持开启状态，直到玩家离开
	sprite.region_rect = Rect2(64, 16, 16, 16) # 切换到开启状态的贴图（假设在 64,16）
	print("[CHEST] Chest opened into UI mode")
	
	# [NET] 如果是联机模式，向服务器上报开箱
	var net = get_node_or_null("/root/NetworkManager")
	var gm = get_node_or_null("/root/GameMode")
	if net and gm and not gm.is_offline_mode:
		net.request("Room.OpenChest", {"id": chestID})

func _spawn_loot_ui() -> void:
	# 1. 寻找背包并打开分屏布局
	var backpack = get_tree().get_first_node_in_group("Backpack")
	if not backpack:
		push_error("[CHEST] Backpack not found!")
		return
	backpack.open_backpack()
	if backpack.has_method("set_layout_mode"):
		backpack.set_layout_mode(true)
	
	# 2. 实例化掉落窗口
	var loot_scene = load("res://prefabs/Backpack/sub/loot_window.tscn")
	if not loot_scene: return
	
	_loot_ui_instance = loot_scene.instantiate()
	backpack.get_parent().add_child(_loot_ui_instance)
	_loot_ui_instance.name = "LootWindow"
	
	# 3. 填充随机物品
	var loot_grid = _loot_ui_instance.get_node("%LootGrid")
	if loot_grid:
		# 策划要求：一个宝箱只能出 1~2 件物品
		var count = 2 if DEBUG_FORCE_LOOT else (randi() % 2 + 1)
		var items = []
		for i in range(count):
			items.append(_get_random_outfit_path())
		loot_grid.fillRandomItems(items, count)
	
	# 4. 设置分屏偏移：宝箱窗口移到右侧（与左侧背包对称）
	# [AI MODIFY]
	# 动态计算宝箱窗口位置：宽度 320，高度 568，与背包间距 40
	# 由于 LootWindow 默认在 scene 中是 center 锚点 (anchor_left/right/top/bottom = 0.5)
	# 偏右放置：左边缘距离中心 20，右边缘距离中心 340
	var loot_width = 320.0
	var loot_height = 568.0
	var gap = 40.0
	
	_loot_ui_instance.offset_left = gap / 2.0
	_loot_ui_instance.offset_right = gap / 2.0 + loot_width
	_loot_ui_instance.offset_top = -loot_height / 2.0
	_loot_ui_instance.offset_bottom = loot_height / 2.0
	
	# 5. 记录关闭逻辑：当窗口销毁时，背包恢复居中
	_loot_ui_instance.tree_exiting.connect(func(): 
		if is_instance_valid(backpack) and backpack.has_method("set_layout_mode"):
			backpack.set_layout_mode(false)
		_loot_ui_instance = null
	)

# 已将全部拾取逻辑迁移至 loot_grid.gd，此处仅保留引用清除

func _process(delta: float) -> void:
	if _is_opened:
		# 如果玩家离开太远，自动关闭界面并销毁宝箱
		if not _is_player_inside and _loot_ui_instance:
			_loot_ui_instance.queue_free()
			var tween = create_tween()
			tween.tween_property(self, "modulate:a", 0.0, 0.5)
			tween.tween_callback(queue_free)
		return
	
	if _is_player_inside:
		_opening_progress += delta
		progressBar.show()
		progressBar.value = _opening_progress
		
		if _opening_progress >= OPEN_TIME:
			_complete_opening()
	else:
		if _opening_progress > 0:
			_opening_progress = max(0, _opening_progress - delta * 2)
			progressBar.value = _opening_progress
			if _opening_progress <= 0:
				progressBar.hide()

func _play_sfx(path: String) -> void:
	if ResourceLoader.exists(path):
		var sfx = AudioStreamPlayer2D.new()
		sfx.stream = load(path)
		sfx.bus = &"SFX"
		get_parent().add_child(sfx)
		sfx.global_position = global_position
		sfx.play()
		sfx.finished.connect(sfx.queue_free)
