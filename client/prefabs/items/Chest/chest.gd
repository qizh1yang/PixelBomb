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

# ── 集中概率配置 ──
const STAGE_EARLY_LIMIT: int = 5  # 前5个宝箱为早期阶段
const STAGE_MID_LIMIT: int = 15   # 5~15个宝箱为中期阶段

# 各阶段品质权重定义 [T1, T2, T3, DIAMOND]
const WEIGHTS_EARLY: Array[float] = [100.0, 0.0, 0.0, 0.0]
const WEIGHTS_MID: Array[float] = [88.0, 11.0, 1.0, 0.0]
const WEIGHTS_LATE: Array[float] = [92.0, 7.0, 0.9, 0.1]

# 钻石保底配置
const PITY_30_PROBABILITY: float = 1.0  # 连续30个没出钻石，概率提升至 1%
const PITY_50_PROBABILITY: float = 3.0  # 连续50个没出钻石，概率提升至 3%

var _diamond_looted_this_chest: bool = false

# ── 结构化局外装备掉落池（T1 / T2 / T3 / DIAMOND） ──
const LOOT_POOL: Dictionary = {
	"tier1": [
		"res://prefabs/OutfitItems/outfit_bag_large.tres",
		"res://prefabs/OutfitItems/outfit_speed_1.tres",
		"res://prefabs/OutfitItems/outfit_power_1.tres",
		"res://prefabs/OutfitItems/outfit_power_left_1.tres",
		"res://prefabs/OutfitItems/outfit_power_right_1.tres",
		"res://prefabs/OutfitItems/outfit_power_up_1.tres",
		"res://prefabs/OutfitItems/outfit_power_down_1.tres"
	],
	"tier2": [
		"res://prefabs/OutfitItems/outfit_suitcase_wood.tres",
		"res://prefabs/OutfitItems/outfit_speed_3.tres",
		"res://prefabs/OutfitItems/outfit_power_2.tres",
		"res://prefabs/OutfitItems/outfit_power_left_2.tres",
		"res://prefabs/OutfitItems/outfit_power_right_2.tres",
		"res://prefabs/OutfitItems/outfit_power_up_2.tres",
		"res://prefabs/OutfitItems/outfit_power_down_2.tres"
	],
	"tier3": [
		"res://prefabs/OutfitItems/outfit_speed_5.tres",
		"res://prefabs/OutfitItems/outfit_power_3.tres",
		"res://prefabs/OutfitItems/outfit_power_left_3.tres",
		"res://prefabs/OutfitItems/outfit_power_right_3.tres",
		"res://prefabs/OutfitItems/outfit_power_up_3.tres",
		"res://prefabs/OutfitItems/outfit_power_down_3.tres"
	],
	"diamond": [
		"res://prefabs/OutfitItems/outfit_pumpkin_giant.tres",
		"res://prefabs/OutfitItems/outfit_epic_shield.tres"
	]
}

func _get_random_outfit_path() -> String:
	# 步骤 1：根据 opened_chests_count 确定当前阶段
	var current_opened = GlobalPlayerData.opened_chests_count
	var stage: String = "EARLY"
	
	if current_opened < STAGE_EARLY_LIMIT:
		stage = "EARLY"
	elif current_opened < STAGE_MID_LIMIT:
		stage = "MID"
	else:
		stage = "LATE"
	
	# 步骤 2 & 3：根据当前阶段和保底计数构建动态生成的品质权重
	var w_tier1: float = 0.0
	var w_tier2: float = 0.0
	var w_tier3: float = 0.0
	var w_diamond: float = 0.0
	
	if stage == "EARLY":
		w_tier1 = WEIGHTS_EARLY[0]
		w_tier2 = WEIGHTS_EARLY[1]
		w_tier3 = WEIGHTS_EARLY[2]
		w_diamond = WEIGHTS_EARLY[3]
	elif stage == "MID":
		w_tier1 = WEIGHTS_MID[0]
		w_tier2 = WEIGHTS_MID[1]
		w_tier3 = WEIGHTS_MID[2]
		w_diamond = WEIGHTS_MID[3]
	elif stage == "LATE":
		w_tier1 = WEIGHTS_LATE[0]
		w_tier2 = WEIGHTS_LATE[1]
		w_tier3 = WEIGHTS_LATE[2]
		
		# 钻石软保底概率跃升：
		# 正常 0.1% -> 30个没出 1% -> 50个没出 3%
		var pity_count = GlobalPlayerData.chests_since_last_diamond
		w_diamond = WEIGHTS_LATE[3]
		if pity_count >= 50:
			w_diamond = PITY_50_PROBABILITY
		elif pity_count >= 30:
			w_diamond = PITY_30_PROBABILITY
	
	# 步骤 4：根据品质权重，先随机抽取“品质级别”
	var weights: Array = [w_tier1, w_tier2, w_tier3, w_diamond]
	var tiers: Array = ["tier1", "tier2", "tier3", "diamond"]
	
	var total_weight: float = w_tier1 + w_tier2 + w_tier3 + w_diamond
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	var chosen_tier: String = "tier1"
	
	for i in range(weights.size()):
		cumulative += weights[i]
		if roll <= cumulative:
			chosen_tier = tiers[i]
			break
	
	# 步骤 5：再从该品质中随机抽具体物品，并同步处理钻石保底标志
	var item_list: Array = LOOT_POOL.get(chosen_tier, [])
	var chosen_item_path: String = ""
	if not item_list.is_empty():
		chosen_item_path = item_list.pick_random()
	else:
		chosen_item_path = LOOT_POOL["tier1"].pick_random()
	
	# 如果抽中钻石品质，则立刻标记本箱已产出钻石
	if chosen_tier == "diamond":
		_diamond_looted_this_chest = true
	
	# 打印日志输出
	# 规范格式，例如：[CHEST] Stage: EARLY, Tier: T1, Item: outfit_power_1, Diamond pity: 12
	var readable_tier = "T1"
	match chosen_tier:
		"tier1": readable_tier = "T1"
		"tier2": readable_tier = "T2"
		"tier3": readable_tier = "T3"
		"diamond": readable_tier = "DIAMOND"
		
	var item_name = chosen_item_path.get_file().replace(".tres", "")
	print("[CHEST] Stage: %s, Tier: %s, Item: %s, Diamond pity: %d" % [
		stage,
		readable_tier,
		item_name,
		GlobalPlayerData.chests_since_last_diamond
	])
	
	return chosen_item_path

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
	
	# 重置当前箱内是否获得过钻石的标志
	_diamond_looted_this_chest = false
	
	# 增加开启计数
	GlobalPlayerData.opened_chests_count += 1
	
	# 播放开启音效
	_play_sfx("res://assets/audio/sfx/Explosion.wav")
	
	# 打开摸金界面（左右分屏）
	_spawn_loot_ui()
	
	# 时序校正：在抽奖完毕后决定保底计数的重置或自增，确保自增和清零绝对逻辑严密
	if _diamond_looted_this_chest:
		GlobalPlayerData.chests_since_last_diamond = 0
		print("[CHEST] Diamond obtained! Pity count reset to 0.")
	else:
		GlobalPlayerData.chests_since_last_diamond += 1
		print("[CHEST] No diamond this chest. Pity count incremented to %d" % GlobalPlayerData.chests_since_last_diamond)
	
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
